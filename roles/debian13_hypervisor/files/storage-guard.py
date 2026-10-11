#!/usr/bin/python3
"""Read-only libvirt startup gate; do not start guests on a missing data mount."""
import json
from pathlib import Path
import subprocess
import sys


def main():
    try:
        for path in (Path('/data'), Path('/data/libvirt'), Path('/data/libvirt/images'), Path('/data/libvirt/cloud-init')):
            if path.is_symlink():
                raise ValueError('Symlink in protected storage')
        result = subprocess.run(
            ['findmnt', '--json', '--mountpoint', '/data', '--output', 'TARGET,UUID,OPTIONS'],
            check=True, text=True, capture_output=True)
        mounts = json.loads(result.stdout)['filesystems']
        mount = mounts[0]
        if (len(mounts) != 1 or mount['target'] != '/data'
                or mount.get('uuid') != '7f882d89-a2cf-46d2-9db8-5333be51a300'
                or 'rw' not in mount.get('options', '').split(',')):
            raise ValueError('Missing or incorrect writable /data filesystem')
        for path in ('/data/libvirt/images', '/data/libvirt/cloud-init'):
            result = subprocess.run(
                ['findmnt', '--json', '--target', path, '--output', 'TARGET,UUID'],
                check=True, text=True, capture_output=True)
            target = json.loads(result.stdout)['filesystems'][0]
            if target['target'] != '/data' or target.get('uuid') != mount['uuid']:
                raise ValueError('Unexpected nested mount in libvirt storage')
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        print(f'libvirt storage guard: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
