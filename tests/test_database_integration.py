"""Exercise real Ansible database tasks against a disposable local PostgreSQL cluster."""
import grp
import json
import os
from pathlib import Path
import pwd
import shutil
import socket as network_socket
import subprocess

import pytest
import yaml

from conftest import ROOT


@pytest.fixture(scope='module')
def postgres(tmp_path_factory):
    directory = tmp_path_factory.mktemp('local-postgres')
    version = yaml.safe_load((ROOT / 'environments/hetzner/group_vars/all.yml').read_text())['postgresql_version']
    binaries = sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'), key=lambda p: int(p.parents[1].name))
    assert binaries, 'Install PostgreSQL for the isolated database integration tests'
    # Native Debian CI uses the configured major; Ubuntu also checks its packaged major.
    configured = Path('/usr/lib/postgresql') / str(version) / 'bin'
    binary_dir = configured if (configured / 'initdb').is_file() else binaries[-1].parent
    data, socket = directory / 'data', directory / 'socket'
    socket.mkdir()
    subprocess.run([str(binary_dir / 'initdb'), '-D', str(data), '-U', 'postgres', '--auth=trust', '--no-locale'],
                   check=True, capture_output=True, text=True)
    (data / 'pg_hba.conf').write_text('local all postgres trust\nlocal all all peer\nhost all all 127.0.0.1/32 scram-sha-256\n')
    with network_socket.socket() as port_reservation:
        port_reservation.bind(('127.0.0.1', 0))
        port = port_reservation.getsockname()[1]
    key,cert=directory/'key.pem',directory/'cert.pem'
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=local-postgres'],check=True,capture_output=True)
    key.chmod(0o600)
    with (data/'postgresql.conf').open('a') as stream:
        stream.write(f"\nssl=on\nssl_cert_file='{cert}'\nssl_key_file='{key}'\n")
    subprocess.run([str(binary_dir / 'pg_ctl'), '-D', str(data), '-l', str(directory / 'postgres.log'),
                    '-o', f"-k {socket} -c listen_addresses='127.0.0.1' -p {port}", '-w', 'start'],
                   check=True, capture_output=True, text=True)
    state = dict(directory=directory, socket=socket, binary_dir=binary_dir, port=port)
    try:
        yield state
    finally:
        subprocess.run([str(binary_dir / 'pg_ctl'), '-D', str(data), '-m', 'immediate', '-w', 'stop'],
                       check=True, capture_output=True, text=True)


def sql(postgres, query, database='postgres'):
    result = subprocess.run([str(postgres['binary_dir'] / 'psql'), '-X', '-tA',
                             '-h', str(postgres['socket']), '-p', str(postgres['port']), '-U', 'postgres', '-d', database,
                             '-v', 'ON_ERROR_STOP=1', '-c', query], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def configure_database(postgres, tmp_path, name, dump, *, allow_import=True, expect_success=True,
                       tasks_from='application-database'):
    state_dir = postgres['directory'] / 'state'
    state_dir.mkdir(exist_ok=True)
    source = tmp_path / 'input.sql'
    if isinstance(dump, Path):
        shutil.copyfile(dump, source)
    else:
        source.write_text(dump)
    variables = {
        'application_db': {'name': name, 'user': name, 'password': 'test-password-only', 'dump_file': 'input.sql'},
        'debian13_postgresql_state_dir': str(state_dir),
        'debian13_postgresql_dump_root': str(tmp_path),
        'debian13_postgresql_socket': str(postgres['socket']),
        'debian13_postgresql_port': postgres['port'],
        'debian13_postgresql_import_host': '127.0.0.1',
        'debian13_postgresql_postgis_enabled': (
            Path('/usr/share/postgresql') / postgres['binary_dir'].parent.name / 'extension/postgis.control'
        ).exists(),
        'debian13_postgresql_owner': pwd.getpwuid(os.getuid()).pw_name,
        'debian13_postgresql_group': grp.getgrgid(os.getgid()).gr_name,
        'hetzner_app_initial_import': allow_import,
        'ansible_become': False,
    }
    playbook = tmp_path / 'test.yml'
    playbook.write_text(yaml.safe_dump([{
        'name': 'Only the disposable local database', 'hosts': 'localhost', 'gather_facts': False,
        'vars': variables,
        'tasks': [{'name': 'Exercise real safe application database tasks',
                   'ansible.builtin.include_tasks': str(ROOT / f'roles/debian13_postgresql/tasks/{tasks_from}.yml')}]
    }]))
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text('all:\n  hosts:\n    localhost:\n      ansible_connection: local\n      ansible_python_interpreter: /usr/bin/python3\n')
    env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
           'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
           'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote')}
    result = subprocess.run(['ansible-playbook', '-i', str(inventory), str(playbook)],
                            cwd=ROOT, env=env, text=True, capture_output=True)
    if expect_success:
        assert result.returncode == 0, result.stdout + result.stderr
    else:
        assert result.returncode != 0, result.stdout + result.stderr
    return result


def create_user(postgres, name):
    sql(postgres, f"CREATE USER {name} NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD 'test-password-only'")


def test_database_acl_parses_and_limits_nominatim_maintenance_connection(postgres, render):
    hba = postgres['directory'] / 'data/pg_hba.conf'
    original = hba.read_text()
    try:
        hba.write_text(render('roles/debian13_postgresql/templates/pg_hba.conf.j2',
                              monitoring_web_db_name='icingaweb2', monitoring_web_db_user='icingaweb2',
                              monitoring_ido_db_name='icinga', monitoring_ido_db_user='icinga',
                              nominatim_db_name='nominatim', nominatim_db_user='nominatim'))
        # PostgreSQL parses the file directly; do not reload or alter live access.
        assert sql(postgres, 'SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL') == '0'
        rules = json.loads(sql(postgres, """
            SELECT json_agg(json_build_object('database',database,'user',user_name,
                                             'address',address,'method',auth_method))
            FROM pg_hba_file_rules WHERE type='hostssl' AND 'nominatim'=ANY(user_name)
        """))
        assert rules == [
            {'database': ['nominatim'], 'user': ['nominatim'], 'address': '10.77.0.15', 'method': 'scram-sha-256'},
            {'database': ['postgres'], 'user': ['nominatim'], 'address': '10.77.0.15', 'method': 'scram-sha-256'},
        ]
    finally:
        hba.write_text(original)


def test_initial_import_then_changed_dump_and_missing_marker_preserve_live_data(postgres, tmp_path):
    name = 'safe_initial'
    create_user(postgres, name)
    dump = "CREATE SCHEMA uranus; CREATE TABLE uranus.records(id integer PRIMARY KEY, value text); INSERT INTO uranus.records VALUES (1, 'initial');"
    configure_database(postgres, tmp_path, name, dump)
    original_oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
    sql(postgres, "INSERT INTO uranus.records VALUES (2, 'live data')", name)
    (postgres['directory'] / f'state/.{name}_initial_import_complete').unlink()
    configure_database(postgres, tmp_path, name, dump.replace('initial', 'replacement'))
    assert sql(postgres, 'SELECT string_agg(value,\',\' ORDER BY id) FROM uranus.records', name) == 'initial,live data'
    assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'") == original_oid


def test_existing_database_with_unexpected_schema_is_not_reset_or_imported(postgres, tmp_path):
    name = 'safe_existing'
    create_user(postgres, name)
    sql(postgres, f'CREATE DATABASE {name} OWNER {name}')
    sql(postgres, "CREATE TABLE public.valuable_data(value text); INSERT INTO public.valuable_data VALUES ('keep me')", name)
    oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
    configure_database(postgres, tmp_path, name, 'INVALID SQL WOULD FAIL IF IMPORTED')
    assert sql(postgres, 'SELECT value FROM public.valuable_data', name) == 'keep me'
    assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'") == oid


def test_disabled_initial_import_does_not_execute_the_dump(postgres, tmp_path):
    name = 'safe_disabled'
    create_user(postgres, name)
    configure_database(postgres, tmp_path, name, 'INVALID SQL', allow_import=False)
    assert sql(postgres, "SELECT count(*) FROM pg_tables WHERE schemaname='uranus'", name) == '0'


def test_failed_import_rolls_back_and_retry_stops_for_manual_recovery(postgres, tmp_path):
    name = 'safe_failure'
    create_user(postgres, name)
    configure_database(postgres, tmp_path, name, 'CREATE SCHEMA uranus; CREATE TABLE uranus.partial(id integer); INVALID SQL;', expect_success=False)
    assert sql(postgres, "SELECT to_regclass('uranus.partial') IS NULL", name) == 't'
    assert (postgres['directory'] / f'state/.{name}_initial_import_pending').exists()
    result = configure_database(postgres, tmp_path, name, 'CREATE SCHEMA uranus;', expect_success=False)
    assert 'interrupted' in result.stdout


def test_psql_escape_is_rejected_before_it_can_touch_another_database(postgres, tmp_path):
    name = 'safe_escape'
    create_user(postgres, name)
    result = configure_database(postgres, tmp_path, name, '\\connect postgres\nDROP TABLE nonexistent;\n', expect_success=False)
    assert 'Unsafe psql metacommand' in result.stdout
    assert sql(postgres, "SELECT count(*) FROM pg_database WHERE datname='postgres'") == '1'


def test_explicit_import_populates_an_existing_empty_database_with_a_backup(postgres, tmp_path):
    name = 'safe_empty_import'
    create_user(postgres, name)
    configure_database(postgres, tmp_path, name, '', allow_import=False)
    oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
    peer_login = subprocess.run([str(postgres['binary_dir'] / 'psql'), '-X', '-h', str(postgres['socket']),
                                 '-p', str(postgres['port']), '-U', name, '-d', name, '-c', 'SELECT current_user'],
                                capture_output=True, text=True)
    assert peer_login.returncode != 0
    assert 'Peer authentication failed' in peer_login.stderr
    dump = "CREATE SCHEMA uranus; CREATE TABLE uranus.records(id integer PRIMARY KEY, value text); INSERT INTO uranus.records VALUES (1, 'imported');"
    configure_database(postgres, tmp_path, name, dump, tasks_from='import-empty')
    assert sql(postgres, 'SELECT value FROM uranus.records', name) == 'imported'
    assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'") == oid
    backup, = (postgres['directory'] / 'state').glob(f'{name}.before-initial-import.*.dump')
    subprocess.run([str(postgres['binary_dir'] / 'pg_restore'), '--list', str(backup)],
                   check=True, capture_output=True, text=True)
    configure_database(postgres, tmp_path, name, dump, tasks_from='import-empty', expect_success=False)
    assert sql(postgres, 'SELECT value FROM uranus.records', name) == 'imported'


@pytest.mark.parametrize('name,object_sql', [
    ('safe_occupied_table', "CREATE TABLE uranus.valuable_data(value text); INSERT INTO uranus.valuable_data VALUES ('keep me');"),
    ('safe_occupied_type', 'CREATE TYPE uranus.valuable_type AS ENUM (\'keep me\');'),
    ('safe_occupied_function', "CREATE FUNCTION uranus.valuable_function() RETURNS text LANGUAGE sql AS $$ SELECT 'keep me'::text $$;"),
])
def test_explicit_import_rejects_existing_tables_types_and_functions(postgres, tmp_path, name, object_sql):
    create_user(postgres, name)
    configure_database(postgres, tmp_path, name, '', allow_import=False)
    sql(postgres, object_sql, name)
    result = configure_database(postgres, tmp_path, name, 'CREATE SCHEMA uranus;',
                                tasks_from='import-empty', expect_success=False)
    assert 'absent or empty uranus schema' in result.stdout
    assert not list((postgres['directory'] / 'state').glob(f'{name}.before-initial-import.*.dump'))
    if object_sql.startswith('CREATE TABLE'):
        assert sql(postgres, 'SELECT value FROM uranus.valuable_data', name) == 'keep me'


def test_explicit_import_of_repository_dump_matches_all_copy_row_counts(postgres, tmp_path):
    import re

    name = 'safe_real_uranus'
    create_user(postgres, name)
    configure_database(postgres, tmp_path, name, '', allow_import=False)
    dump = ROOT / 'uranus_dev.sql'
    configure_database(postgres, tmp_path, name, dump, tasks_from='import-empty')
    expected = {}
    table = None
    for line in dump.read_text().splitlines():
        if table is not None:
            if line == r'\.':
                table = None
            else:
                expected[table] += 1
        elif match := re.match(r'^COPY (\S+) .* FROM stdin;$', line):
            table = match[1]
            expected[table] = 0
    assert len(expected) == 56
    query = ' UNION ALL '.join(f"SELECT '{table}', count(*) FROM {table}" for table in expected)
    actual = {table: int(count) for table, count in (row.split('|') for row in sql(postgres, query, name).splitlines())}
    assert actual == expected
    assert sql(postgres, f"SELECT count(*) FROM pg_tables WHERE schemaname='uranus' AND tableowner <> '{name}'", name) == '0'


def test_import_transaction_rechecks_the_schema_before_executing_dump_statements(postgres, tmp_path):
    name = 'safe_transaction_guard'
    create_user(postgres, name)
    configure_database(postgres, tmp_path, name, '', allow_import=False)
    sql(postgres, "CREATE TYPE uranus.arrived_before_import AS ENUM ('keep me')", name)
    configure_database(postgres, tmp_path, name,
                       'CREATE SCHEMA uranus; CREATE TABLE uranus.unwanted(id integer);',
                       tasks_from='initial-import', expect_success=False)
    assert sql(postgres, "SELECT to_regclass('uranus.unwanted') IS NULL", name) == 't'
    assert sql(postgres, "SELECT to_regtype('uranus.arrived_before_import') IS NOT NULL", name) == 't'
    assert (postgres['directory'] / f'state/.{name}_initial_import_pending').exists()
