"""Exercise real Ansible database tasks against a disposable local PostgreSQL cluster."""
import grp
import json
import os
from pathlib import Path
import pwd
import shutil
import signal
import subprocess
import time

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


def configure_database(postgres, tmp_path, name, dump, *, allow_import=True, expect_success=True,
                       fault_before=None, background=False):
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
    tasks = [{'name': 'Exercise real safe application database tasks',
              'ansible.builtin.include_tasks': str(ROOT / 'roles/debian13_postgresql/tasks/application-database.yml')}]
    if fault_before:
        tasks = yaml.safe_load((ROOT / 'roles/debian13_postgresql/tasks/application-database.yml').read_text())
        for task in tasks:
            if 'ansible.builtin.include_tasks' in task:
                task['ansible.builtin.include_tasks'] = str(ROOT / 'roles/debian13_postgresql/tasks' / task['ansible.builtin.include_tasks'])
        index = next(i for i, task in enumerate(tasks) if task['name'] == fault_before)
        tasks.insert(index, {'name': 'Injected interruption at the real task boundary',
                            'ansible.builtin.fail': {'msg': 'Injected interruption'}})
    playbook.write_text(yaml.safe_dump([{
        'name': 'Only the disposable local database', 'hosts': 'localhost', 'gather_facts': False,
        'vars': variables,
        'tasks': tasks
    }]))
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text('all:\n  hosts:\n    localhost:\n      ansible_connection: local\n      ansible_python_interpreter: /usr/bin/python3\n')
    env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible-debian13.cfg'),
           'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
           'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote')}
    argv = ['ansible-playbook', '-i', str(inventory), str(playbook)]
    if background:
        return subprocess.Popen(argv, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
    result = subprocess.run(argv,
                            cwd=ROOT, env=env, text=True, capture_output=True)
    if expect_success:
        assert result.returncode == 0, result.stdout + result.stderr
    else:
        assert result.returncode != 0, result.stdout + result.stderr
    return result


def create_user(postgres, name):
    sql(postgres, f'CREATE USER {name} NOSUPERUSER NOCREATEDB NOCREATEROLE')


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
            FROM pg_hba_file_rules WHERE type='host' AND 'nominatim'=ANY(user_name)
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


@pytest.mark.parametrize('boundary', ['Create only an absent application database',
                                     'Enable PostGIS without replacing application data',
                                     'Complete initialization only after import schema and grants succeeded'])
def test_interruption_at_creation_and_commit_boundaries_never_reimports(postgres, tmp_path, boundary):
    name = {'Create only an absent application database': 'safe_before_create',
            'Enable PostGIS without replacing application data': 'safe_after_create',
            'Complete initialization only after import schema and grants succeeded': 'safe_after_commit'}[boundary]
    create_user(postgres, name)
    dump = "CREATE SCHEMA uranus; CREATE TABLE uranus.records(value text); INSERT INTO uranus.records VALUES ('preserve');"
    configure_database(postgres, tmp_path, name, dump, fault_before=boundary, expect_success=False)
    pending = postgres['directory'] / f'state/.{name}_initial_import_pending'
    assert pending.exists()
    oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
    assert bool(oid) == (boundary != 'Create only an absent application database')
    result = configure_database(postgres, tmp_path, name, dump, expect_success=False)
    assert 'interrupted' in result.stdout
    assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'") == oid
    if boundary.startswith('Complete'):
        assert sql(postgres, 'SELECT value FROM uranus.records', name) == 'preserve'


def test_killed_controller_keeps_claim_when_import_worker_continues(postgres, tmp_path):
    name = 'safe_killed'
    create_user(postgres, name)
    dump = 'CREATE SCHEMA uranus; CREATE TABLE uranus.partial(id integer); INSERT INTO uranus.partial VALUES (42); SELECT pg_sleep(2);'
    process = configure_database(postgres, tmp_path, name, dump, background=True)
    active = f"SELECT count(*) FROM pg_stat_activity WHERE datname='{name}' AND query LIKE '%pg_sleep(2)%' AND state='active'"
    try:
        deadline = time.monotonic() + 30
        while sql(postgres, active) != '1':
            if process.poll() is not None:
                stdout, stderr = process.communicate()
                pytest.fail(stdout + stderr)
            assert time.monotonic() < deadline, 'The real import did not reach its interruption boundary'
            time.sleep(0.1)
        oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)
        deadline = time.monotonic() + 15
        while sql(postgres, active) != '0':
            assert time.monotonic() < deadline, 'Interrupted SQL connection remained active'
            time.sleep(0.1)
        committed = sql(postgres, "SELECT to_regclass('uranus.partial') IS NOT NULL", name) == 't'
        if committed:
            assert sql(postgres, 'SELECT id FROM uranus.partial', name) == '42'
        result = configure_database(postgres, tmp_path, name, 'CREATE SCHEMA uranus;', expect_success=False)
        assert 'interrupted' in result.stdout
        assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'") == oid
        if committed:
            assert sql(postgres, 'SELECT id FROM uranus.partial', name) == '42'
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        process.communicate()


def test_missing_previously_initialized_database_requires_restore(postgres, tmp_path):
    name = 'safe_lost'
    create_user(postgres, name)
    configure_database(postgres, tmp_path, name, '', allow_import=False)
    sql(postgres, f'DROP DATABASE {name}')  # Only the disposable local test database.
    result = configure_database(postgres, tmp_path, name, '', allow_import=False, expect_success=False)
    assert 'Previously initialized database is missing' in result.stdout
    assert sql(postgres, f"SELECT count(*) FROM pg_database WHERE datname='{name}'") == '0'
