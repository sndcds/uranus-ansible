"""Exercise Nominatim's preservation and temporary privilege guards on real PostgreSQL."""
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT
from test_database_integration import create_user, postgres, sql


def run_tasks(postgres, tmp_path, name, tasks_from='preflight', **overrides):
    defaults = yaml.safe_load((ROOT / 'roles/debian13_nominatim/defaults/main.yml').read_text())
    variables = {
        **defaults, 'nominatim_db_name': name, 'nominatim_db_user': name,
        'nominatim_db_delegate_host': 'localhost', 'debian13_nominatim_db_socket': str(postgres['socket']),
        'debian13_nominatim_db_port': postgres['port'], 'hetzner_nominatim_initial_import': False,
        'nominatim_data_url': 'https://example.test/region.osm.pbf', 'nominatim_data_sha256': '0' * 64,
        'nominatim_project_dir': str(tmp_path), 'debian13_nominatim_db_min_free_gib': 0,
        'debian13_nominatim_db_storage_path': str(postgres['directory']),
        'ansible_become': False, 'ansible_python_interpreter': '/usr/bin/python3',
        'ansible_remote_tmp': str(tmp_path / 'remote'), **overrides,
    }
    playbook = tmp_path / 'nominatim-test.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'gather_facts': False, 'vars': variables,
        'tasks': [{'name': 'Exercise the real Nominatim database tasks',
                   'ansible.builtin.include_tasks': str(ROOT / f'roles/debian13_nominatim/tasks/{tasks_from}.yml')}],
    }]))
    return subprocess.run(['ansible-playbook', '-i', 'localhost,', '-c', 'local', str(playbook)],
                          text=True, capture_output=True, env={
                              **os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
                              'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible'), 'ANSIBLE_NOCOWS': '1',
                          })


@pytest.mark.parametrize('authorized', [False, True])
def test_absent_database_requires_import_authorization_without_creating_it(postgres, tmp_path, authorized):
    name = 'nom_absent_' + str(int(authorized))
    result = run_tasks(postgres, tmp_path, name, hetzner_nominatim_initial_import=authorized)
    assert result.returncode == (0 if authorized else 2), result.stdout + result.stderr
    assert sql(postgres, f"SELECT count(*) FROM pg_database WHERE datname='{name}'") == '0'


@pytest.mark.parametrize('state', ['empty', 'unindexed', 'ready'])
def test_existing_databases_are_preserved_and_only_finished_imports_pass(postgres, tmp_path, state):
    name = 'nom_existing_' + state
    create_user(postgres, name)
    sql(postgres, f'CREATE DATABASE {name} OWNER {name}')
    oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
    if state != 'empty':
        sql(postgres, 'CREATE TABLE placex(id integer); INSERT INTO placex VALUES (42); '
            'CREATE TABLE import_status(indexed boolean); INSERT INTO import_status VALUES (' +
            ('true' if state == 'ready' else 'false') + ')', name)
    result = run_tasks(postgres, tmp_path, name)
    assert result.returncode == (0 if state == 'ready' else 2), result.stdout + result.stderr
    assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'") == oid
    if state != 'empty':
        assert sql(postgres, 'SELECT id FROM placex', name) == '42'


@pytest.mark.parametrize('failure', [False, True])
def test_preparation_privileges_are_revoked_on_success_and_failure(postgres, tmp_path, failure):
    name = 'nom_prepare_' + str(int(failure))
    create_user(postgres, name)
    binary = tmp_path / 'venv/bin/nominatim'
    binary.parent.mkdir(parents=True)
    observed = tmp_path / 'observed.json'
    psql_args = [str(postgres['binary_dir'] / 'psql'), '-X', '-tA', '-h', str(postgres['socket']),
                 '-p', str(postgres['port']), '-U', 'postgres', '-d', 'postgres',
                 '-c', f"SELECT rolsuper FROM pg_roles WHERE rolname='{name}'"]
    binary.write_text(f'''#!{sys.executable}
import json
from pathlib import Path
import subprocess
import sys
assert sys.argv[1:] == ['import', '--project-dir', {str(tmp_path)!r}, '--prepare-database']
superuser = subprocess.check_output({psql_args!r}, text=True).strip()
Path({str(observed)!r}).write_text(json.dumps({{'superuser': superuser}}))
sys.exit({9 if failure else 0})
''')
    binary.chmod(0o755)
    result = run_tasks(postgres, tmp_path, name, tasks_from='prepare-database',
                       debian13_nominatim_venv=str(binary.parents[1]))
    assert result.returncode == (2 if failure else 0), result.stdout + result.stderr
    assert json.loads(observed.read_text()) == {'superuser': 't'}
    assert sql(postgres, f"SELECT rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname='{name}'") == 'f|f|f'
