"""Two-phase firewall update with a host-side watchdog and fresh SSH proof."""
import base64
import contextlib
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import secrets
import shlex
import stat
import subprocess
import tempfile
import time

TABLE = 'uranus_debian13'


class FirewallError(Exception):
    """Preserve the previous confirmed configuration on ambiguous state."""


def command(argv):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=20, check=False)
    except subprocess.TimeoutExpired as exc:
        raise FirewallError(f'{argv[0]} timed out; leave the independent rollback armed') from exc
    if result.returncode:
        raise FirewallError(f'{argv[0]} failed: {result.stderr.strip()}')
    return result.stdout


def durable_write(path, data):
    path = Path(path)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, path)
            sync_directory(path.parent)
        finally:
            temporary.unlink(missing_ok=True)


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def connection_tuple(value, networks):
    fields = value.split()
    if len(fields) != 4:
        raise FirewallError('Require the server-observed SSH_CONNECTION tuple')
    peer, local = ipaddress.ip_address(fields[0]), ipaddress.ip_address(fields[2])
    if peer.version != local.version or not 0 < int(fields[1]) < 65536 or int(fields[3]) != 22:
        raise FirewallError('Only the verified SSH listener on port 22 is supported')
    allowed = [ipaddress.ip_network(n, strict=True) for n in networks]
    if not allowed or any(n.prefixlen == 0 for n in allowed):
        raise FirewallError('Explicit management CIDRs are required')
    if not any(peer.version == n.version and peer in n for n in allowed):
        raise FirewallError('The observed SSH peer is outside the management CIDRs')
    return fields


def fresh_ssh(host, user, port, token, private_key=None, common_args='', run=command):
    if not host or host.startswith('-') or not user or user.startswith('-') or int(port) != 22:
        raise FirewallError('Require an explicit authorized SSH user, host and port 22')
    extra = shlex.split(common_args)
    if any(arg == '-S' or arg.startswith('-S') or arg in ('-O', '-M') for arg in extra):
        raise FirewallError('SSH multiplexing operations cannot be used for the fresh probe')
    script = 'import json,os,sys; print(json.dumps({"token":sys.argv[1],"connection":os.environ["SSH_CONNECTION"]}))'
    remote = shlex.join(['/usr/bin/python3', '-c', script, token])
    argv = ['ssh', '-o', 'ControlMaster=no', '-o', 'ControlPath=none', '-o', 'ControlPersist=no',
            '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectionAttempts=1',
            '-o', 'ConnectTimeout=10', '-o', 'ForwardAgent=no', '-o', 'ClearAllForwardings=yes',
            '-p', str(port), '-l', user]
    if private_key:
        argv += ['-i', private_key]
    proof = json.loads(run(argv + extra + [host, remote]))
    if proof.get('token') != token:
        raise FirewallError('The fresh SSH probe returned an invalid challenge')
    return proof


class FirewallTransaction:
    def __init__(self, state_dir='/var/lib/uranus/firewall', config='/etc/uranus/host-firewall.nft',
                 helper='/usr/local/sbin/uranus-firewall-transaction', run=command, now=time.time,
                 unit='uranus-firewall-rollback', monotonic=time.monotonic):
        self.directory, self.config = Path(state_dir), Path(config)
        self.helper, self.run, self.now, self.unit = helper, run, now, unit
        self.monotonic = monotonic
        self.pending = self.directory / 'pending.json'
        self.receipt = self.directory / 'confirmed.json'

    @contextlib.contextmanager
    def locked(self, write=True):
        for path in (self.directory, self.config, self.pending, self.receipt):
            if any(p.is_symlink() for p in (path, *path.parents)):
                raise FirewallError('Symlinks are forbidden in firewall transaction storage')
        if not write:
            yield
            return
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        metadata = self.directory.stat()
        if metadata.st_uid != os.geteuid() or stat.S_IMODE(metadata.st_mode) & 0o022:
            raise FirewallError('Firewall transaction directory must be owned and writable only by its operator')
        fd = os.open(self.directory / 'lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'w') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            yield

    def table_exists(self):
        tables = json.loads(self.run(['nft', '--json', 'list', 'tables']))['nftables']
        return any(e.get('table', {}).get('family') == 'inet' and
                   e.get('table', {}).get('name') == TABLE for e in tables)

    def table_digest(self):
        entries = json.loads(self.run(['nft', '--json', 'list', 'table', 'inet', TABLE]))['nftables']
        def stable(value):
            if isinstance(value, dict):
                return {k: stable(v) for k, v in value.items() if k != 'handle'}
            if isinstance(value, list):
                return [stable(v) for v in value]
            return value
        return hashlib.sha256(json.dumps(stable([e for e in entries if 'metainfo' not in e]), sort_keys=True).encode()).hexdigest()

    def snapshot(self, path):
        return base64.b64encode(path.read_bytes()).decode() if path.exists() else None

    def restore_file(self, path, snapshot):
        if snapshot is None:
            path.unlink(missing_ok=True)
            sync_directory(path.parent)
        else:
            durable_write(path, base64.b64decode(snapshot))

    def rollback_locked(self, state):
        restore = f'destroy table inet {TABLE}\n' + state['previous_table']
        with tempfile.NamedTemporaryFile(mode='w', dir=self.directory) as stream:
            stream.write(restore)
            stream.flush()
            self.run(['nft', '--check', '--file', stream.name])
            self.run(['nft', '--file', stream.name])
        self.restore_file(self.config, state['previous_config'])
        self.restore_file(self.receipt, state['previous_receipt'])
        self.pending.unlink()
        sync_directory(self.directory)
        return {'changed': True, 'rolled_back': True}

    def begin(self, candidate, connection, networks, timeout=90, check_mode=False):
        connection_tuple(connection, networks)
        if not 30 <= timeout <= 600:
            raise FirewallError('Rollback timeout must be between 30 and 600 seconds')
        candidate = Path(candidate)
        if candidate.is_symlink():
            raise FirewallError('The firewall candidate must not be a symlink')
        data = candidate.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        with self.locked(write=not check_mode):
            if self.pending.exists():
                raise FirewallError('A firewall transaction is pending; wait for rollback or recover manually')
            exists = self.table_exists()
            if self.receipt.exists() and self.config.exists() and exists:
                confirmed = json.loads(self.receipt.read_text())
                if (hashlib.sha256(self.config.read_bytes()).hexdigest() == digest == confirmed['config_sha256']
                        and self.table_digest() == confirmed['table_sha256']):
                    return {'changed': False}
            self.run(['nft', '--check', '--file', str(candidate)])
            if check_mode:
                return {'changed': True}
            state = {'token': secrets.token_hex(32), 'deadline': self.now() + timeout,
                     'monotonic_deadline': self.monotonic() + timeout,
                     'boot_id': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                     'connection': connection, 'networks': networks,
                     'candidate': base64.b64encode(data).decode(),
                     'previous_table': self.run(['nft', 'list', 'table', 'inet', TABLE]) if exists else '',
                     'previous_config': self.snapshot(self.config), 'previous_receipt': self.snapshot(self.receipt)}
            durable_write(self.pending, json.dumps(state).encode())
            try:
                staged = self.directory / 'candidate.nft'
                durable_write(staged, data)
                self.run(['nft', '--check', '--file', str(staged)])
                self.run(['systemd-run', '--quiet', f'--unit={self.unit}-{state["token"][:16]}',
                          f'--on-active={timeout}s', '--timer-property=AccuracySec=1s',
                          '--property=TimeoutStartSec=30s', '--', self.helper,
                          'rollback', '--token', state['token']])
                self.run(['systemctl', 'is-active', '--quiet', f'{self.unit}-{state["token"][:16]}.timer'])
                self.run(['nft', '--file', str(staged)])
                state['candidate_table_sha256'] = self.table_digest()
                durable_write(self.pending, json.dumps(state).encode())
            except BaseException:
                self.rollback_locked(state)
                raise
            return {'changed': True, 'token': state['token'], 'deadline': state['deadline']}

    def confirm(self, token, proof):
        with self.locked():
            if not self.pending.exists():
                raise FirewallError('No pending transaction; it may already have rolled back')
            state = json.loads(self.pending.read_text())
            if token != state['token']:
                raise FirewallError('Stale firewall transaction token')
            if (self.now() >= state['deadline'] or self.monotonic() >= state['monotonic_deadline']
                    or Path('/proc/sys/kernel/random/boot_id').read_text().strip() != state['boot_id']):
                self.rollback_locked(state)
                raise FirewallError('The confirmation deadline expired; previous firewall restored')
            if proof.get('token') != token:
                raise FirewallError('Invalid fresh SSH proof')
            fresh = connection_tuple(proof.get('connection', ''), state['networks'])
            previous = connection_tuple(state['connection'], state['networks'])
            if fresh == previous or fresh[2:] != previous[2:]:
                raise FirewallError('Require a fresh TCP connection to the original SSH listener')
            if self.table_digest() != state['candidate_table_sha256']:
                raise FirewallError('Firewall drift after the SSH probe; do not cancel the watchdog')
            data = base64.b64decode(state['candidate'])
            durable_write(self.config, data)
            durable_write(self.receipt, json.dumps({'config_sha256': hashlib.sha256(data).hexdigest(),
                                                  'table_sha256': self.table_digest()}).encode())
            # This durable removal is the commit point. A late timer sees no pending state.
            self.pending.unlink()
            sync_directory(self.directory)
            # Once committed, an already queued watchdog safely does nothing.
            try:
                self.run(['systemctl', 'stop', f'{self.unit}-{token[:16]}.timer'])
            except FirewallError:
                pass
            return {'changed': True, 'confirmed': True}

    def rollback(self, token=None):
        with self.locked():
            if not self.pending.exists():
                return {'changed': False}
            state = json.loads(self.pending.read_text())
            if token is not None and token != state['token']:
                return {'changed': False}
            return self.rollback_locked(state)
