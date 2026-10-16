#!/usr/bin/env python3
"""Grow the existing db01 disk and ext4 filesystem to 600 GiB, with terminal sudo."""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time

GIB = 1024**3
TARGET_GIB = 600
EXPECTED_UUID = 'ed4bb368-30b1-46bc-abc4-4b657f8e41d1'


def prepare_controller_ssh_config():
    """Share the authenticated bastion session between resizing and ProxyJump."""
    root = Path(__file__).resolve().parents[1]
    private = root / '.uranus-private/ssh'
    private.mkdir(mode=0o700, parents=True, exist_ok=True)
    private.chmod(0o700)

    def config_path(path):
        value = str(path)
        if '\n' in value or '\r' in value:
            raise RuntimeError('SSH configuration paths must not contain newlines')
        return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

    config = private / 'nominatim.conf'
    # Keep using the trusted connection established while diagnosing the resize.
    # ProxyJump inherits -F, so its nested SSH client uses this same socket too.
    lines = [
        'Host 94.130.236.38',
        '    User awendelk',
        '    ControlMaster auto',
        '    ControlPersist 15m',
        '    ControlPath ' + config_path(private / 'db01-resize.sock'),
        'Host *',
        '    BatchMode yes',
        '    StrictHostKeyChecking yes',
        '    ConnectTimeout 60',
        '    ServerAliveInterval 15',
        '    ServerAliveCountMax 3',
    ]
    personal = Path.home() / '.ssh/config'
    if personal.is_file():
        lines.append('    Include ' + config_path(personal))
    config.write_text('\n'.join(lines) + '\n')
    config.chmod(0o600)
    # Ansible adds its own command-line ControlPath even when ssh_config already
    # has one. Pin the direct bastion connection too, without changing guests.
    overlay = private / 'nominatim-inventory.json'
    overlay.write_text(json.dumps({'all': {'hosts': {'hetzner': {
        'ansible_control_path': str(private / 'db01-resize.sock'),
    }}}}, indent=2) + '\n')
    overlay.chmod(0o600)
    return config


def run(arguments, *, check=True, input=None, timeout=None):
    result = subprocess.run(arguments, text=True, capture_output=True, input=input, timeout=timeout)
    if check and result.returncode:
        raise RuntimeError(f'{arguments[0]} failed: {result.stderr.strip()[:1000]}')
    return result


def incus(arguments, **options):
    return run(['incus', '--force-local', *arguments, '--project', 'uranus'], **options)


def guest(arguments, **options):
    return run(['incus', '--force-local', 'exec', 'db01', '--project', 'uranus', '--', *arguments], **options)


def managed_instance(*, running=True):
    instances = json.loads(incus(['list', '--format=json']).stdout)
    instance = next(item for item in instances if item['name'] == 'db01')
    root = instance['expanded_devices']['root']
    if (instance['type'] != 'virtual-machine'
            or (running and instance['status'] != 'Running')
            or instance.get('profiles') or root['pool'] != 'uranus' or root['path'] != '/'
            or instance['expanded_config'].get('user.uranus.owner') != 'uranus/incus/v1'):
        raise RuntimeError('Require the managed db01 VM with its dedicated root disk')
    return instance


def disk_size_bytes():
    return int(guest(['blockdev', '--getsize64', '/dev/sda']).stdout)


def wait_for_postgresql():
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        try:
            result = guest(['systemctl', 'is-active', '--quiet', 'postgresql@17-main'],
                           check=False, timeout=10)
            if result.returncode == 0:
                return
        except subprocess.TimeoutExpired:
            pass
        time.sleep(5)
    raise RuntimeError('db01 has started but its agent or PostgreSQL is not ready; inspect before continuing')


def ensure_guest_disk_size():
    """Handle Incus 6.0 dir volumes deferring an in-use resize until next start."""
    instance = managed_instance()
    root = instance['expanded_devices']['root']
    if root.get('size') != f'{TARGET_GIB}GiB':
        raise RuntimeError('The configured root disk is not 600 GiB; no restart or partition change performed')
    size = disk_size_bytes()
    if size > TARGET_GIB * GIB:
        raise RuntimeError('The guest disk is larger than the target; refusing to shrink it')
    pending = instance['expanded_config'].get('volatile.root.apply_quota', '').lower() == 'true'
    if not pending:
        for attempt in range(10):
            if size == TARGET_GIB * GIB:
                return
            if attempt == 0:
                guest(['python3', '-c',
                       'from pathlib import Path; p=Path("/sys/class/block/sda/device/rescan"); '
                       'p.write_text("1\\n") if p.exists() else None'])
            time.sleep(1)
            size = disk_size_bytes()
            if size > TARGET_GIB * GIB:
                raise RuntimeError('The guest disk is larger than the target; refusing to shrink it')
        if size == TARGET_GIB * GIB:
            return
    print('Incus must apply the 600 GiB disk size at the next start. '
          'Stopping and starting db01 cleanly; database connections will be interrupted.', flush=True)
    # A guest reboot does not run Incus device Start/applyDeferredQuota.
    # Never force-stop the shared database VM.
    incus(['stop', 'db01', '--timeout=120'], timeout=150)
    if managed_instance(running=False)['status'] != 'Stopped':
        raise RuntimeError('db01 did not stop cleanly; no forced stop or partition change performed')
    incus(['start', 'db01'])
    wait_for_postgresql()
    instance = managed_instance()
    size = disk_size_bytes()
    pending = instance['expanded_config'].get('volatile.root.apply_quota', '').lower() == 'true'
    if size != TARGET_GIB * GIB or pending:
        raise RuntimeError(f'After stop/start the guest disk is {size / GIB:.1f} GiB '
                           f'(deferred resize={pending}); no partition was changed by this helper')


def partition_table():
    return json.loads(guest(['sfdisk', '--json', '/dev/sda']).stdout)['partitiontable']


def filesystem():
    return json.loads(guest(['findmnt', '--json', '--target', '/var/lib/postgresql',
                             '-o', 'SOURCE,FSTYPE,UUID,TARGET,OPTIONS']).stdout)['filesystems'][0]


def validate_layout(table, fs):
    if (table['label'] != 'gpt' or table['device'] != '/dev/sda'
            or fs['source'] != '/dev/sda2' or fs['fstype'] != 'ext4'
            or fs['target'] != '/' or fs['uuid'] != EXPECTED_UUID
            or 'rw' not in fs['options'].split(',')):
        raise RuntimeError('Unexpected db01 partition layout or filesystem identity; preserve and inspect')
    parts = {part['node']: part for part in table['partitions']}
    if (set(parts) != {'/dev/sda1', '/dev/sda2'} or parts['/dev/sda1']['start'] != 2048
            or parts['/dev/sda1']['size'] != 204800 or parts['/dev/sda2']['start'] != 206848):
        raise RuntimeError('Unexpected EFI or root partition boundaries; preserve and inspect')


def verify_partition_preservation(before, after):
    for key in ('label', 'id', 'device', 'unit', 'sectorsize'):
        if before.get(key) != after.get(key):
            raise RuntimeError('Partition table identity changed')
    old = {part['node']: part for part in before['partitions']}
    new = {part['node']: part for part in after['partitions']}
    if set(old) != set(new) or old['/dev/sda1'] != new['/dev/sda1']:
        raise RuntimeError('EFI partition changed')
    if (new['/dev/sda2']['size'] < old['/dev/sda2']['size']
            or {k: v for k, v in old['/dev/sda2'].items() if k != 'size'}
            != {k: v for k, v in new['/dev/sda2'].items() if k != 'size'}):
        raise RuntimeError('Root partition start or identity changed')


def database_oids():
    query = "SELECT datname,oid FROM pg_database WHERE NOT datistemplate ORDER BY datname"
    return guest(['runuser', '-u', 'postgres', '--', 'psql', '-XAt', '-d', 'postgres',
                  '-v', 'ON_ERROR_STOP=1', '-c', query]).stdout


def resize():
    if os.geteuid() != 0:
        raise RuntimeError('Run the remote operation with sudo')
    os.umask(0o077)
    os.environ['INCUS_DIR'] = '/data/incus'
    lock = open('/run/lock/uranus-db01-resize.lock', 'a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    run(['python3', '/usr/local/sbin/uranus-storage-guard.py'])
    instance = managed_instance()
    root = instance['expanded_devices']['root']
    match = re.fullmatch(r'(\d+)GiB', root.get('size', ''))
    if not match or int(match[1]) not in (150, TARGET_GIB):
        raise RuntimeError('Only the verified 150 GiB disk or a partial 600 GiB resize is supported')
    current_gib = int(match[1])
    before = partition_table()
    validate_layout(before, filesystem())
    guest(['systemctl', 'is-active', '--quiet', 'postgresql@17-main'])
    oids = database_oids()
    fs_bytes = int(guest(['python3', '-c',
                         'import os; s=os.statvfs("/var/lib/postgresql"); print(s.f_blocks*s.f_frsize)']).stdout)
    actual_size = disk_size_bytes()
    if actual_size > TARGET_GIB * GIB:
        raise RuntimeError('The guest disk is larger than the target; refusing to shrink it')
    pending = instance['expanded_config'].get('volatile.root.apply_quota', '').lower() == 'true'
    if current_gib == TARGET_GIB and actual_size == TARGET_GIB * GIB and fs_bytes >= 580 * GIB and not pending:
        incus(['config', 'set', 'db01', 'user.uranus.disk_gib=600'])
        print('db01 already has a 600 GiB disk and an expanded ext4 filesystem.')
        return
    # The configuration can already say 600 GiB while the backing disk is still
    # 150 GiB after a deferred resize. Budget from the actual guest-visible size.
    required = max(0, TARGET_GIB * GIB - actual_size) + 160 * GIB
    if shutil.disk_usage('/data').free < required:
        raise RuntimeError('Insufficient host space for disk growth plus 160 GiB reserve')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = '/var/backups/db01-before-resize-' + stamp
    host_backup = Path(backup)
    host_backup.mkdir(mode=0o700)
    (host_backup / 'instance.json').write_text(json.dumps(instance, indent=2) + '\n')
    (host_backup / 'partition-table.sfdisk').write_text(guest(['sfdisk', '--dump', '/dev/sda']).stdout)
    guest(['install', '-d', '-o', 'postgres', '-g', 'postgres', '-m', '0700', backup])
    guest(['runuser', '-u', 'postgres', '--', 'pg_dumpall', '--globals-only', '--file=' + backup + '/roles.sql'])
    for line in oids.splitlines():
        name = line.split('|')[0]
        if not re.fullmatch(r'[a-z][a-z0-9_]*', name):
            raise RuntimeError('Unexpected database name; preserve and inspect')
        path = backup + '/' + name + '.dump'
        guest(['runuser', '-u', 'postgres', '--', 'pg_dump', '--format=custom', '--file=' + path + '.partial', name])
        guest(['runuser', '-u', 'postgres', '--', 'pg_restore', '--list', path + '.partial'])
        guest(['mv', '--no-clobber', path + '.partial', path])
    print('Database dumps and partition metadata saved under ' + backup, flush=True)
    if current_gib < TARGET_GIB:
        incus(['config', 'device', 'set', 'db01', 'root', 'size=600GiB'])
    ensure_guest_disk_size()
    # Cloud-image services may have grown the root partition during startup.
    # Check their result against the original layout before doing further work.
    validate_layout(partition_table(), filesystem())
    verify_partition_preservation(before, partition_table())
    dry_run = guest(['growpart', '--dry-run', '/dev/sda', '2'], check=False)
    (host_backup / 'growpart-dry-run.txt').write_text(dry_run.stdout + dry_run.stderr)
    if dry_run.returncode == 0:
        guest(['growpart', '/dev/sda', '2'])
    elif dry_run.returncode != 1 or 'NOCHANGE' not in dry_run.stdout + dry_run.stderr:
        raise RuntimeError('growpart dry-run failed; inspect the protected backup directory')
    verify_partition_preservation(before, partition_table())
    guest(['resize2fs', '/dev/sda2'])
    validate_layout(partition_table(), filesystem())
    guest(['systemctl', 'is-active', '--quiet', 'postgresql@17-main'])
    if database_oids() != oids:
        raise RuntimeError('Database identities changed during the resize; inspect before importing')
    fs_bytes = int(guest(['python3', '-c',
                         'import os; s=os.statvfs("/var/lib/postgresql"); print(s.f_blocks*s.f_frsize)']).stdout)
    if fs_bytes < 580 * GIB:
        raise RuntimeError('The filesystem did not grow to the expected size; preserve and inspect')
    incus(['config', 'set', 'db01', 'user.uranus.disk_gib=600'])
    print(guest(['df', '-h', '/var/lib/postgresql']).stdout, end='')
    print('db01 expanded; PostgreSQL is active and database identities are unchanged.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--remote', action='store_true', help=argparse.SUPPRESS)
    modes.add_argument('--prepare-ssh', action='store_true',
                       help='Write the private shared SSH configuration without connecting')
    parser.add_argument('--ssh-config', type=Path, help='Use an existing controller SSH configuration')
    args = parser.parse_args()
    if args.remote:
        resize()
        return
    if args.prepare_ssh:
        print(prepare_controller_ssh_config())
        return
    ssh = ['ssh', '-t', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes']
    config = args.ssh_config or prepare_controller_ssh_config()
    ssh += ['-F', str(config)]
    code = Path(__file__).read_text()
    command = 'sudo python3 -c ' + shlex.quote(code) + ' --remote'
    # stdin belongs to the operator, so sudo reads its password from the SSH TTY.
    result = subprocess.run([*ssh, 'awendelk@94.130.236.38', command])
    if result.returncode:
        print(f'db01 resize failed (SSH exit {result.returncode}). '
              'The Europe import was not started. Read the remote error above; '
              'existing backups are retained.', file=sys.stderr)
        raise SystemExit(1)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, StopIteration, subprocess.TimeoutExpired) as exc:
        print(f'db01 resize: {exc}', file=sys.stderr)
        raise SystemExit(1)
