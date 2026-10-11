"""Shared non-destructive storage and SQL safety checks."""
import os
import json
import re
import subprocess
from pathlib import Path

EXPECTED_UUID = "7f882d89-a2cf-46d2-9db8-5333be51a300"
DATA = Path("/data/incus")

class SafetyError(Exception):
    """Unsafe or ambiguous target state."""

def execute(argv):
    result = subprocess.run(argv, capture_output=True, text=True, env={**os.environ,"LC_ALL":"C","INCUS_DIR":str(DATA)}, timeout=120)
    if result.returncode:
        raise SafetyError(f"Read failed: {argv[0]}: {result.stderr.strip()}")
    return result.stdout.strip()

def reject_symlinks(path):
    path=Path(path)
    for p in [path,*path.parents]:
        if p.is_symlink():
            raise SafetyError(f"Symlink in protected storage path: {p}")

def validate_sql_dump(path):
    """Reject psql commands that can escape the selected new database or run a shell."""
    in_copy = False
    with open(path, encoding='utf-8') as stream:
        for line in stream:
            if in_copy:
                if line.rstrip('\n') == r'\.':
                    in_copy = False
                continue
            if re.match(r'^COPY .+ FROM stdin;\s*$', line, re.IGNORECASE):
                in_copy = True
            elif line.lstrip().startswith('\\') and not re.fullmatch(r'\\(?:unrestrict|restrict) [A-Za-z0-9]+\s*', line):
                raise SafetyError('Unsafe psql metacommand in initial SQL dump')
            elif re.match(r'^\s*(?:DROP|CREATE|ALTER)\s+DATABASE\b', line, re.IGNORECASE):
                raise SafetyError('Global database operation in initial SQL dump')
    if in_copy:
        raise SafetyError('Incomplete COPY data in SQL dump')



def storage_guard(run=execute):
    """Read-only verification. Never mounts, formats, remounts or repairs storage."""
    reject_symlinks(Path('/data'))
    mounts = json.loads(run(['findmnt','--json','--mountpoint','/data','--output','TARGET,UUID,OPTIONS,FSTYPE']))['filesystems']
    if len(mounts) != 1 or mounts[0].get('target') != '/data':
        raise SafetyError('/data must be a separate mount point')
    mount = mounts[0]
    if mount.get('uuid') != EXPECTED_UUID or 'rw' not in mount.get('options','').split(',') or mount.get('fstype') != 'ext4':
        raise SafetyError(f'/data requires writable ext4 with UUID {EXPECTED_UUID}')
    for path in [DATA,DATA/'storage-pools',DATA/'storage-pools/uranus',DATA/'backups',DATA/'images',DATA/'database']:
        reject_symlinks(path)
        existing = path
        while not existing.exists():
            existing = existing.parent
        target = json.loads(run(['findmnt','--json','--target',str(existing),'--output','TARGET,UUID,OPTIONS,FSTYPE']))['filesystems'][0]
        if (target.get('target') != '/data' or target.get('uuid') != EXPECTED_UUID
                or 'rw' not in target.get('options','').split(',')):
            raise SafetyError(f'Unexpected filesystem underneath {path}')
    return mount

if __name__ == '__main__':
    storage_guard()
