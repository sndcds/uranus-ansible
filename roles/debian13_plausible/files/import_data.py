#!/usr/bin/env python3
"""Restore a verified snapshot into empty dedicated target databases only."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def command(argv, **kwargs):
    return subprocess.check_output(argv, **kwargs)


def ch(query, data=None):
    return command(['clickhouse-client', '--optimize_on_insert=0', '--max_threads=2', '--query', query], input=data)


def pg(query, database='plausible_db'):
    return command(['runuser', '-u', 'postgres', '--', 'psql', '-XAt', '-d', database, '-c', query], text=True).strip()


def validate_snapshot(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    assert manifest['version'] == 1
    assert manifest['clickhouse_database'] == 'plausible_events_db'
    if 'postgres.dump' not in manifest['sha256']:
        raise ValueError('PostgreSQL dump lacks a checksum')
    for name, digest in manifest['sha256'].items():
        if Path(name).name != name or (directory / name).is_symlink():
            raise ValueError('Unsafe snapshot path')
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != digest:
            raise ValueError('Snapshot checksum mismatch')
    for table in manifest['tables']:
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', table['name']):
            raise ValueError('Unexpected table identifier')
        if 'file' in table and table['file'] not in manifest['sha256']:
            raise ValueError('Data file lacks a checksum')
    return manifest


def ordered_functions(functions):
    remaining = {f['name']: f for f in functions}
    ordered = []
    while remaining:
        ready = [name for name, function in remaining.items()
                 if not any(re.search(r'(?<![A-Za-z0-9_])' + re.escape(other) + r'\s*\(', function['create_query'])
                            for other in remaining if other != name)]
        if not ready:
            raise ValueError('Cyclic user-defined function dependencies')
        for name in ready:
            ordered.append(remaining.pop(name))
    return ordered


def main():
    os.umask(0o077)
    directory = Path(sys.argv[1])
    database = sys.argv[2] if len(sys.argv) > 2 else 'plausible_events_db'
    postgres_database = sys.argv[3] if len(sys.argv) > 3 else 'plausible_db'
    marker = Path('/etc/plausible/' + ('rehearsal-complete.json' if len(sys.argv) > 4 and sys.argv[4] == 'rehearsal' else 'import-complete.json'))
    for name in [database, postgres_database]:
        if not re.fullmatch(r'plausible_[A-Za-z0-9_]+', name):
            raise ValueError('Require a dedicated Plausible database name')
    if marker.exists():
        raise ValueError('An import is already complete; never overwrite its data')
    if subprocess.run(['systemctl', 'is-active', '--quiet', 'plausible']).returncode == 0:
        raise ValueError('Target application must be stopped')
    manifest = validate_snapshot(directory)
    if int(pg("SELECT count(*) FROM pg_tables WHERE schemaname='public'", postgres_database)):
        raise ValueError('Target PostgreSQL database is not empty')
    if int(ch("SELECT count(*) FROM system.tables WHERE database='%s'" % database)):
        raise ValueError('Target ClickHouse database is not empty')
    with (directory / 'postgres.dump').open('rb') as source:
        subprocess.run(['runuser', '-u', 'postgres', '--', 'pg_restore', '--exit-on-error', '--clean', '--if-exists',
                        '--no-owner', '--no-acl', '--role=plausible', '-d', postgres_database], stdin=source, check=True)
    for table in manifest['tables']:
        table['create_table_query'] = table['create_table_query'].replace('plausible_events_db', database)
    for function in manifest.get('functions', []):
        function['create_query'] = function['create_query'].replace('plausible_events_db', database)
    manifest['target_clickhouse_database'] = database
    manifest['target_postgres_database'] = postgres_database
    physical = [t for t in manifest['tables'] if 'file' in t]
    dictionaries = [t for t in manifest['tables'] if t['engine'] == 'Dictionary']
    foundation = {'location_data', 'acquisition_channel_paid_sources', 'acquisition_channel_source_category'}
    # Event defaults use dictionaries. Populate their source tables before creating dependent tables.
    def restore_table(table):
        ch(table['create_table_query'])
        if table['engine'].endswith('MergeTree'):
            ch('SYSTEM STOP MERGES `%s`.`%s`' % (database, table['name']))
        if table['rows']:
            with gzip.open(directory / table['file'], 'rb') as source:
                ch('INSERT INTO `%s`.`%s` FORMAT Native' % (database, table['name']), data=source.read())
        count = int(ch('SELECT count(*) FROM `%s`.`%s`' % (database, table['name'])))
        if count != table['rows']:
            raise ValueError('ClickHouse restored row count differs for %s: expected %s, received %s' % (table['name'], table['rows'], count))

    for table in physical:
        if table['name'] in foundation:
            restore_table(table)
    for table in dictionaries:
        ch(table['create_table_query'])
    for function in ordered_functions(manifest.get('functions', [])):
        ch(re.sub(r'^CREATE FUNCTION ', 'CREATE OR REPLACE FUNCTION ', function['create_query']))
    for table in physical:
        if table['name'] not in foundation:
            restore_table(table)
    # Create materialized views last, so inserts do not duplicate exported aggregates.
    for table in manifest['tables']:
        if table['engine'] in ['View', 'MaterializedView']:
            ch(table['create_table_query'])
    for table, count in manifest['postgres_counts'].items():
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', table):
            raise ValueError('Unexpected PostgreSQL table identifier')
        if int(pg('SELECT count(*) FROM public."%s"' % table, postgres_database)) != count:
            raise ValueError('PostgreSQL restored row count differs')
    manifest['snapshot'] = str(directory)
    marker.write_text(json.dumps(manifest, indent=2) + '\n')
    marker.chmod(0o600)
    for table in physical:
        if table['engine'].endswith('MergeTree'):
            ch('SYSTEM START MERGES `%s`.`%s`' % (database, table['name']))
    print(json.dumps({'verified': True, 'postgres_tables': len(manifest['postgres_counts']),
                      'clickhouse_tables': len(manifest['tables'])}))


if __name__ == '__main__':
    main()
