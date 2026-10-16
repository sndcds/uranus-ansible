#!/usr/bin/env python3
"""Export Plausible's databases with logical formats; never copy ClickHouse system logs."""
import base64
from contextlib import contextmanager
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import urllib.parse
import urllib.request


def identifier(value):
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', value):
        raise ValueError('Unexpected database or table identifier')
    return value


def environment(path):
    result = {}
    for line in Path(path).read_text().splitlines():
        key, sep, value = line.partition('=')
        if sep and not key.startswith('#'):
            result[key.strip()] = ' '.join(shlex.split(value))
    return result


def clickhouse(url, query):
    parsed = urllib.parse.urlsplit(url)
    address = urllib.parse.urlunsplit((parsed.scheme, parsed.hostname + ':' + str(parsed.port or 8123), '/', '', ''))
    parameters = urllib.parse.urlencode({'query': query, 'max_threads': 1, 'max_block_size': 8192})
    request = urllib.request.Request(address + '?' + parameters, data=b'')
    if parsed.username:
        credential = urllib.parse.unquote(parsed.username) + ':' + urllib.parse.unquote(parsed.password or '')
        request.add_header('Authorization', 'Basic ' + base64.b64encode(credential.encode()).decode())
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            body = error.read().decode(errors='replace')
            codes = re.findall(r'Code: (\d+)', body)
            if '241' in codes and attempt < 3:
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError('ClickHouse export failed: HTTP %s, codes %s' % (error.code, ','.join(codes))) from None


def postgres(query, database='plausible_db'):
    return subprocess.check_output(['runuser', '-u', 'postgres', '--', 'psql', '-XAt', '-d', database, '-c', query], text=True).strip()


def postgres_counts():
    tables = json.loads(postgres("SELECT coalesce(json_agg(tablename),'[]') FROM pg_tables WHERE schemaname='public'"))
    values = ','.join("'%s',(SELECT count(*) FROM public.\"%s\")" % (identifier(t), t) for t in tables)
    return json.loads(postgres('SELECT json_build_object(' + values + ')'))


def portable_dictionary(table, database):
    """Rebuild only the local data source; do not retain old embedded credentials."""
    sources = {'location_data_dict': 'location_data',
               'acquisition_channel_paid_sources_dict': 'acquisition_channel_paid_sources',
               'acquisition_channel_source_category_dict': 'acquisition_channel_source_category'}
    source_table = sources[table['name']]
    query = table['create_table_query']
    match = re.search(r'\bSOURCE\s*\(\s*CLICKHOUSE\s*\(', query, re.I)
    if not match:
        raise ValueError('Unexpected dictionary source')
    depth, quoted, escaped, end = 2, False, False, match.end()
    while depth and end < len(query):
        char = query[end]
        if escaped:
            escaped = False
        elif char == '\\' and quoted:
            escaped = True
        elif char == "'":
            quoted = not quoted
        elif not quoted:
            depth += (char == '(') - (char == ')')
        end += 1
    if depth:
        raise ValueError('Unbalanced dictionary source')
    replacement = "SOURCE(CLICKHOUSE(HOST '127.0.0.1' PORT 9000 USER 'default' PASSWORD '' DB '%s' TABLE '%s'))" % (database, source_table)
    table['create_table_query'] = query[:match.start()] + replacement + query[end:]


@contextmanager
def pause_merges(url, database, tables):
    names = [identifier(t['name']) for t in tables if t['engine'].endswith('MergeTree')]
    try:
        for name in names:
            clickhouse(url, f'SYSTEM STOP MERGES `{database}`.`{name}`')
        yield
    finally:
        for name in names:
            clickhouse(url, f'SYSTEM START MERGES `{database}`.`{name}`')


def main():
    os.umask(0o077)
    destination = Path(sys.argv[1])
    if destination.exists():
        raise ValueError('Snapshot destination already exists')
    destination.mkdir(mode=0o700, parents=True)
    env = environment('/etc/plausible/plausible.env')
    url = env['CLICKHOUSE_DATABASE_URL']
    database = identifier(urllib.parse.urlsplit(url).path.lstrip('/'))
    tables = json.loads(clickhouse(url, "SELECT name,engine,create_table_query FROM system.tables WHERE database='%s' ORDER BY name FORMAT JSON" % database))['data']
    for table in tables:
        if table['engine'] == 'Dictionary':
            portable_dictionary(table, database)
    with pause_merges(url, database, tables):
        manifest = {'version': 1, 'postgres_counts': postgres_counts(), 'clickhouse_database': database, 'tables': tables, 'functions': json.loads(clickhouse(url, "SELECT name,create_query FROM system.functions WHERE origin='SQLUserDefined' FORMAT JSON"))['data'], 'sha256': {}}
        with (destination / 'postgres.dump').open('xb') as output:
            subprocess.run(['runuser', '-u', 'postgres', '--', 'pg_dump', '-Fc', '--no-owner', '--no-acl', 'plausible_db'], stdout=output, check=True)
        for table in tables:
            name = identifier(table['name'])
            if table['engine'] in ['View', 'MaterializedView', 'Dictionary']:
                continue
            query = f'FROM `{database}`.`{name}`'
            before = int(clickhouse(url, 'SELECT count(*) ' + query))
            data = clickhouse(url, 'SELECT * ' + query + ' FORMAT Native')
            after = int(clickhouse(url, 'SELECT count(*) ' + query))
            if before != after:
                raise ValueError('Source changed during export; preserve it and retry after stopping the writer')
            table['rows'] = after
            table['file'] = name + '.native.gz'
            (destination / table['file']).write_bytes(gzip.compress(data))
        if postgres_counts() != manifest['postgres_counts']:
            raise ValueError('PostgreSQL changed during export')
        for path in destination.iterdir():
            manifest['sha256'][path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'snapshot': str(destination), 'postgres_tables': len(manifest['postgres_counts']),
                      'clickhouse_tables': len(tables), 'bytes': sum(p.stat().st_size for p in destination.iterdir())}))


if __name__ == '__main__':
    main()
