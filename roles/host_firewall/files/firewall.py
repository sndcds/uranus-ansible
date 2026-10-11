#!/usr/bin/python3
"""Apply key-only SSH and one nftables table with independent timed recovery."""
import fcntl
import glob
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import subprocess
import sys
import uuid

STATE = Path('/var/lib/uranus/host-access')
PERSIST = Path('/etc/uranus/host-firewall.nft')
CANDIDATE = Path('/etc/uranus/host-firewall.candidate.nft')
SSH_CANDIDATE = Path('/etc/uranus/host-ssh.candidate.conf')
SSH_CONFIG = Path('/etc/ssh/sshd_config.d/00-uranus-host.conf')
SSHD_CONFIG = Path('/etc/ssh/sshd_config')
SSH_DEFAULTS = Path('/etc/default/ssh')
SSHD = '/usr/sbin/sshd'
SCRIPT = Path('/usr/local/sbin/uranus-firewall.py')
UNIT = 'uranus-firewall-rollback'
SSH_HEADER = '# Managed by Uranus Ansible: key-only administrative SSH.\n'
SSH_POLICY = {
    'pubkeyauthentication': 'yes',
    'authenticationmethods': 'publickey',
    'passwordauthentication': 'no',
    'kbdinteractiveauthentication': 'no',
    'permitrootlogin': 'no',
}


def run(argv):
    return subprocess.run(argv, check=True, capture_output=True, text=True).stdout


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def replace_file(path, content, mode=0o600, uid=None, gid=None):
    """Durably replace a file; an abandoned temporary is never an SSH .conf."""
    temporary = path.with_name(path.name + '.uranus-' + uuid.uuid4().hex + '.tmp')
    try:
        with temporary.open('xb') as output:
            os.chmod(temporary, mode)
            if uid is not None:
                os.chown(temporary, uid, gid)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


def require_simple_ssh_config(path, ancestors=()):
    """Fail closed on conditional policy and recursive Includes; edit neither."""
    resolved = path.resolve(strict=True)
    if resolved in ancestors or len(ancestors) >= 16:
        raise RuntimeError('Recursive SSH Include requires manual review')
    for line in resolved.read_text().splitlines():
        match = re.match(r'^\s*([A-Za-z][A-Za-z0-9]*)\s*(?:=\s*)?(.*)$', line)
        if not match:
            continue
        keyword, arguments = match.group(1).lower(), match.group(2)
        if keyword == 'match':
            raise RuntimeError('Existing SSH Match rules require manual review before public SSH')
        if keyword == 'include':
            for pattern in shlex.split(arguments, comments=True):
                if not Path(pattern).is_absolute():
                    pattern = str(SSHD_CONFIG.parent / pattern)
                for included in sorted(glob.glob(pattern)):
                    require_simple_ssh_config(Path(included), ancestors + (resolved,))


def require_standard_ssh_service():
    """Refuse service options that could bypass the audited sshd_config."""
    properties = {}
    for name in ('ExecStart', 'Environment', 'EnvironmentFiles'):
        properties[name] = run(['systemctl', 'show', 'ssh.service', '--property=' + name, '--value']).strip()
    command = re.search(r'argv\[\]=([^;]+)', properties['ExecStart'])
    if not command or shlex.split(command.group(1)) not in (
        [SSHD, '-D', '$SSHD_OPTS'], [SSHD, '-D'],
    ):
        raise RuntimeError('Custom SSH service command requires manual review')
    allowed_files = ('', str(SSH_DEFAULTS) + ' (ignore_errors=yes)', str(SSH_DEFAULTS) + ' (ignore_errors=no)')
    if properties['EnvironmentFiles'] not in allowed_files:
        raise RuntimeError('Custom SSH environment files require manual review')
    for assignment in shlex.split(properties['Environment']):
        if assignment.startswith('SSHD_OPTS=') and assignment != 'SSHD_OPTS=':
            raise RuntimeError('Nonempty SSHD_OPTS requires manual review')
    if SSH_DEFAULTS.exists():
        for line in SSH_DEFAULTS.read_text().splitlines():
            assignment = re.match(r'^\s*(?:export\s+)?SSHD_OPTS\s*=(.*)$', line)
            if assignment and any(shlex.split(assignment.group(1), comments=True)):
                raise RuntimeError('Nonempty SSHD_OPTS requires manual review')


def ssh_context(user, connection):
    if not user or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]*', user):
        raise RuntimeError('An existing non-root SSH user is required')
    if pwd.getpwnam(user).pw_uid == 0:
        raise RuntimeError('Root SSH cannot be retained by a key-only non-root policy')
    endpoints = (connection or '').split()
    if len(endpoints) != 4:
        raise RuntimeError('A real SSH_CONNECTION is required')
    source, source_port, destination, destination_port = endpoints
    ipaddress.ip_address(source)
    ipaddress.ip_address(destination)
    if not 0 < int(source_port) < 65536 or int(destination_port) != 22:
        raise RuntimeError('Only the existing SSH listener on port 22 is supported')
    return f'user={user},host={source},addr={source},laddr={destination},lport=22'


def ssh_policy_is_current(context):
    for arguments in ([], ['-C', context]):
        output = run([SSHD, '-T', '-f', str(SSHD_CONFIG), *arguments])
        settings = dict(line.split(None, 1) for line in output.splitlines() if ' ' in line)
        if any(settings.get(key) != value for key, value in SSH_POLICY.items()):
            return False
        if settings.get('port') != '22':
            return False
    return True


def audit_ssh(user, connection):
    context = ssh_context(user, connection)
    require_simple_ssh_config(SSHD_CONFIG)
    require_standard_ssh_service()
    if SSH_CONFIG.is_symlink() or (SSH_CONFIG.exists() and not SSH_CONFIG.is_file()):
        raise RuntimeError('Unexpected managed SSH path; preserve and review manually')
    if SSH_CONFIG.exists() and not SSH_CONFIG.read_text().startswith(SSH_HEADER):
        raise RuntimeError('Unmanaged SSH drop-in already exists; preserve it')
    if SSH_CONFIG.parent.is_symlink() or not SSH_CONFIG.parent.is_dir():
        raise RuntimeError('A real existing sshd_config.d directory is required')
    if not SSH_CANDIDATE.read_text().startswith(SSH_HEADER):
        raise RuntimeError('SSH candidate has no Uranus ownership marker')
    run([SSHD, '-t', '-f', str(SSHD_CONFIG)])
    run([SSHD, '-t', '-f', str(SSH_CANDIDATE)])
    current = SSH_CONFIG.exists() and SSH_CONFIG.read_bytes() == SSH_CANDIDATE.read_bytes()
    return 'current' if current and ssh_policy_is_current(context) else 'change'


def snapshot_file(path, name):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise RuntimeError('Unexpected access configuration path: ' + str(path))
    metadata = {'exists': path.exists()}
    if metadata['exists']:
        status = path.stat()
        metadata.update(mode=status.st_mode & 0o777, uid=status.st_uid, gid=status.st_gid)
        replace_file(STATE / (name + '.original'), path.read_bytes())
    replace_file(STATE / (name + '.json'), json.dumps(metadata).encode())


def restore_file(path, name):
    metadata = json.loads((STATE / (name + '.json')).read_text())
    if metadata['exists']:
        replace_file(path, (STATE / (name + '.original')).read_bytes(), metadata['mode'], metadata['uid'], metadata['gid'])
    else:
        path.unlink(missing_ok=True)
        sync_directory(path.parent)


def reload_ssh_if_running():
    # During boot recovery ssh.service has not started yet.
    try:
        run(['systemctl', 'is-active', '--quiet', 'ssh.service'])
    except subprocess.CalledProcessError as error:
        if error.returncode != 3:
            raise
    else:
        run(['systemctl', 'reload', 'ssh.service'])


def restore_access():
    # Never restore a weaker SSH policy while an unconfirmed public firewall remains.
    try:
        run(['nft', '--file', str(STATE / 'rollback.nft')])
    except Exception as error:
        raise RuntimeError('Firewall recovery failed; retain key-only SSH and pending state for console recovery') from error
    errors = []
    for operation in (
        lambda: restore_file(PERSIST, 'firewall'),
        lambda: restore_file(SSH_CONFIG, 'ssh'),
        lambda: run([SSHD, '-t', '-f', str(SSHD_CONFIG)]),
        reload_ssh_if_running,
    ):
        try:
            operation()
        except Exception as error:
            errors.append(error)
    if errors:
        raise RuntimeError('Access recovery incomplete; preserve pending state and use console recovery') from errors[0]


def remove_pending(pending):
    pending.unlink()
    sync_directory(STATE)


def transact(action, token=None, ssh_checksum=None, user=None, connection=None):
    if action == 'audit':
        return audit_ssh(user, connection)
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (STATE / 'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        pending = STATE / 'pending'
        applied = STATE / 'applied.nft'
        applied_ssh = STATE / 'applied-ssh.conf'
        if action == 'begin':
            if pending.exists():
                raise RuntimeError('Pending access update; wait for rollback or recover manually')
            content, ssh_content = CANDIDATE.read_bytes(), SSH_CANDIDATE.read_bytes()
            if (token and hashlib.sha1(content).hexdigest() != token) or (
                ssh_checksum and hashlib.sha1(ssh_content).hexdigest() != ssh_checksum
            ):
                raise RuntimeError('Candidate changed concurrently; refuse unreviewed configuration')
            audit_ssh(user, connection)
            context = ssh_context(user, connection)
            replace_file(applied, content)
            replace_file(applied_ssh, ssh_content)
            run(['nft', '--check', '--file', str(applied)])
            tables = json.loads(run(['nft', '--json', 'list', 'tables']))['nftables']
            exists = any(t.get('table', {}).get('family') == 'inet' and t['table']['name'] == 'uranus_host' for t in tables if 'table' in t)
            if exists and not PERSIST.exists():
                raise RuntimeError('Existing Uranus table has no confirmed ownership record; preserve and audit manually')
            rollback = 'destroy table inet uranus_host\n'
            if exists:
                rollback += run(['nft', 'list', 'table', 'inet', 'uranus_host'])
            replace_file(STATE / 'rollback.nft', rollback.encode())
            snapshot_file(SSH_CONFIG, 'ssh')
            snapshot_file(PERSIST, 'firewall')
            transaction = uuid.uuid4().hex
            replace_file(pending, transaction.encode())
            try:
                run(['systemd-run', '--unit=' + UNIT + '-' + transaction, '--on-active=120s', '/usr/bin/python3', str(SCRIPT), 'rollback', transaction])
                replace_file(SSH_CONFIG, applied_ssh.read_bytes())
                run([SSHD, '-t', '-f', str(SSHD_CONFIG)])
                if not ssh_policy_is_current(context):
                    raise RuntimeError('Effective SSH policy is not key-only; refuse public SSH')
                run(['systemctl', 'reload', 'ssh.service'])
                run(['nft', '--file', str(applied)])
            except Exception:
                restore_access()
                remove_pending(pending)
                raise
            return transaction
        if action == 'rollback':
            if pending.exists() and (token is None or pending.read_text() == token):
                restore_access()
                remove_pending(pending)
            return None
        if action == 'confirm':
            if not pending.exists():
                raise RuntimeError('Update expired or was rolled back; refuse confirmation')
            if not token or pending.read_text() != token:
                raise RuntimeError('Wrong firewall transaction; refuse confirmation')
            if SSH_CONFIG.read_bytes() != applied_ssh.read_bytes() or audit_ssh(user, connection) != 'current':
                raise RuntimeError('SSH policy changed during verification; refuse confirmation')
            replace_file(PERSIST, applied.read_bytes())
            remove_pending(pending)
            # An old callback cannot undo a later transaction.
            try:
                run(['systemctl', 'stop', UNIT + '-' + token + '.timer'])
            except subprocess.CalledProcessError:
                pass
            return None
        raise RuntimeError('Unknown firewall action')


if __name__ == '__main__':
    action = sys.argv[1]
    if action == 'audit':
        result = transact(action, user=sys.argv[2], connection=sys.argv[3])
    elif action == 'begin':
        result = transact(action, sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif action == 'confirm':
        result = transact(action, sys.argv[2], user=sys.argv[3], connection=sys.argv[4])
    else:
        result = transact(action, sys.argv[2] if len(sys.argv) > 2 else None)
    if result:
        print(result)
