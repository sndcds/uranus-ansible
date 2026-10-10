"""Exercise real Ansible database tasks against a disposable local PostgreSQL cluster."""
import grp
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess

import pytest
import yaml

from conftest import ROOT


@pytest.fixture(scope='module')
def postgres(tmp_path_factory):
    directory = tmp_path_factory.mktemp('local-postgres')
    binaries = sorted(Path('/usr/lib/postgresql').glob('*/bin/initdb'), key=lambda p: int(p.parents[1].name))
    assert binaries, 'Install PostgreSQL for the isolated database integration tests'
    binary_dir = binaries[-1].parent
    data, socket = directory / 'data', directory / 'socket'
    socket.mkdir()
    subprocess.run([str(binary_dir / 'initdb'), '-D', str(data), '-U', 'postgres', '--auth=trust', '--no-locale'],
                   check=True, capture_output=True, text=True)
    subprocess.run([str(binary_dir / 'pg_ctl'), '-D', str(data), '-l', str(directory / 'postgres.log'),
                    '-o', f"-k {socket} -c listen_addresses=''", '-w', 'start'],
                   check=True, capture_output=True, text=True)
    state = dict(directory=directory, socket=socket, binary_dir=binary_dir)
    try:
        yield state
    finally:
        subprocess.run([str(binary_dir / 'pg_ctl'), '-D', str(data), '-m', 'immediate', '-w', 'stop'],
                       check=True, capture_output=True, text=True)


def sql(postgres, query, database='postgres'):
    result = subprocess.run([str(postgres['binary_dir'] / 'psql'), '-X', '-tA',
                             '-h', str(postgres['socket']), '-U', 'postgres', '-d', database,
                             '-v', 'ON_ERROR_STOP=1', '-c', query], check=True, capture_output=True, text=True)
    return result.stdout.strip()


def configure_database(postgres, tmp_path, name, dump, *, allow_import=True, expect_success=True):
    state_dir = postgres['directory'] / 'state'
    state_dir.mkdir(exist_ok=True)
    source = tmp_path / 'input.sql'
    source.write_text(dump)
    variables = {
        'application_db': {'name': name, 'user': name, 'password': 'test-password-only', 'dump_file': 'input.sql'},
        'debian13_postgresql_state_dir': str(state_dir),
        'debian13_postgresql_dump_root': str(tmp_path),
        'debian13_postgresql_socket': str(postgres['socket']),
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
                   'ansible.builtin.include_tasks': str(ROOT / 'roles/debian13_postgresql/tasks/application-database.yml')}]
    }]))
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text('all:\n  hosts:\n    localhost:\n      ansible_connection: local\n      ansible_python_interpreter: /usr/bin/python3\n')
    env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible-debian13.cfg'),
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
    sql(postgres, f'CREATE USER {name} NOSUPERUSER NOCREATEDB NOCREATEROLE')


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
