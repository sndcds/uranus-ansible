#!/usr/bin/env python3
"""Keep fourteen completed local native Plausible database backups."""
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    os.umask(0o077)
    database = sys.argv[1]
    postgres_database = sys.argv[2]
    for name in [database, postgres_database]:
        if not re.fullmatch(r'plausible_[A-Za-z0-9_]+', name):
            raise ValueError('Require a dedicated Plausible database')
    with open('/run/lock/plausible-backup.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        parent = Path('/var/backups/plausible/daily')
        parent.mkdir(mode=0o700, exist_ok=True)
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        destination = parent / stamp
        destination.mkdir(mode=0o700)
        with (destination / 'postgres.dump').open('xb') as output:
            subprocess.run(['runuser', '-u', 'postgres', '--', 'pg_dump', '-Fc', '--no-owner', '--no-acl',
                            postgres_database], stdout=output, check=True)
        subprocess.run(['clickhouse-client', '--query',
                        "BACKUP DATABASE %s TO Disk('backups', '%s')" % (database, stamp)],
                       check=True, capture_output=True)
        functions = subprocess.check_output(['clickhouse-client', '--query',
                                              "SELECT name,create_query FROM system.functions WHERE origin='SQLUserDefined' FORMAT JSON"])
        (destination / 'functions.json').write_bytes(functions)
        shutil.copyfile('/etc/plausible/plausible.env', destination / 'plausible.env')
        (destination / 'complete.json').write_text(json.dumps({'stamp': stamp, 'clickhouse': stamp}) + '\n')
        completed = sorted(p for p in parent.iterdir() if re.fullmatch(r'[0-9]{8}T[0-9]{12}Z', p.name)
                           and not p.is_symlink() and (p / 'complete.json').is_file())
        for old in completed[:-14]:
            clickhouse = Path('/var/backups/plausible/clickhouse') / old.name
            if clickhouse.is_dir() and not clickhouse.is_symlink():
                shutil.rmtree(clickhouse)
            shutil.rmtree(old)
        print(json.dumps({'backup': str(destination), 'retained': min(len(completed), 14)}))


if __name__ == '__main__':
    main()
