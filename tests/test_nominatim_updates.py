"""Protect the live search database before replication is initialized or scheduled."""
import json
import os
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT
from test_database_integration import create_user, postgres, sql
from test_nominatim import run_tasks


@pytest.mark.parametrize('state', ['frozen', 'incomplete', 'missing_flatnode', 'unknown_source',
                                   'changed_source', 'changed_database', 'connection_mismatch',
                                   'duplicate_connection', 'flatnode_mismatch', 'missing_nodes',
                                   'initialized', 'ready'])
def test_replication_preflight_preserves_data_and_rejects_unsafe_states(postgres, tmp_path, state):
    name = 'updates_' + state
    create_user(postgres, name)
    sql(postgres, f'CREATE DATABASE {name} OWNER {name}')
    sql(postgres, 'CREATE TABLE placex(id integer); INSERT INTO placex VALUES (42); '
        'CREATE TABLE import_status(indexed boolean, sequence_id bigint); '
        f"INSERT INTO import_status VALUES ({'false' if state == 'incomplete' else 'true'}, "
        f"{'123' if state in ('unknown_source', 'initialized') else 'NULL'})", name)
    if state != 'frozen':
        sql(postgres, 'CREATE TABLE place(id integer); CREATE TABLE planet_osm_ways(id integer); '
            'CREATE TABLE planet_osm_rels(id integer)', name)
    flatnode = tmp_path / 'flatnode'
    if state != 'missing_flatnode':
        flatnode.write_bytes(b'original node data')
    password = 'fixture-password'
    environment = (f'NOMINATIM_DATABASE_DSN=pgsql:host=localhost;port={postgres["port"]};'
                   f'sslmode=verify-full;sslrootcert=/etc/ssl/certs/uranus-ca.pem;dbname={name};'
                   f'user={name};password={password}\nNOMINATIM_FLATNODE_FILE={flatnode}\n')
    if state == 'connection_mismatch':
        environment = environment.replace(f'dbname={name}', 'dbname=another_database')
    if state == 'duplicate_connection':
        environment += 'export NOMINATIM_DATABASE_DSN=pgsql:dbname=another_database\n'
    if state == 'flatnode_mismatch':
        environment = environment.replace(f'NOMINATIM_FLATNODE_FILE={flatnode}',
                                          'NOMINATIM_FLATNODE_FILE=/another/flatnode')
    if state == 'missing_nodes':
        environment = environment.split('NOMINATIM_FLATNODE_FILE=')[0]
    (tmp_path / '.env').write_text(environment)
    marker = tmp_path / '.uranus-replication-source.json'
    oid = int(sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'"))
    source = 'https://download.geofabrik.de/europe-updates'
    if state in ('changed_source', 'changed_database', 'initialized'):
        marker.write_text(json.dumps({'url': source + ('/other' if state == 'changed_source' else ''),
                                      'database_oid': oid + int(state == 'changed_database')}))
    before = marker.read_bytes() if marker.exists() else None
    result = run_tasks(postgres, tmp_path, name, tasks_from='updates' if state == 'frozen' else 'updates-preflight',
                       nominatim_db_password=password,
                       nominatim_flatnode_file='' if state == 'missing_nodes' else str(flatnode),
                       debian13_nominatim_updates_enabled=True,
                       debian13_nominatim_replication_url=source,
                       debian13_nominatim_venv='/opt/nominatim/fixture/venv')
    assert result.returncode == (0 if state in ('ready', 'initialized') else 2), result.stdout + result.stderr
    assert sql(postgres, 'SELECT id FROM placex', name) == '42'
    assert int(sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")) == oid
    assert (tmp_path / '.env').read_text() == environment
    assert (marker.read_bytes() if marker.exists() else None) == before
    if state == 'frozen':
        assert 'No packages, files, replication state or timers have been changed' in result.stdout


@pytest.mark.parametrize('retain_updates', [True, False])
def test_import_only_freezes_when_explicitly_requested(tmp_path, retain_updates):
    tasks = yaml.safe_load((ROOT / 'roles/debian13_nominatim/tasks/main.yml').read_text())
    block = next(task['block'] for task in tasks if task['name'] == 'Import Nominatim only when the database is absent')
    task = next(task for task in block if 'ansible.builtin.command' in task)
    binary = tmp_path / 'venv/bin/nominatim'
    binary.parent.mkdir(parents=True)
    observed = tmp_path / 'arguments.json'
    binary.write_text(f'#!{sys.executable}\nimport json,sys\nfrom pathlib import Path\n'
                      f'Path({str(observed)!r}).write_text(json.dumps(sys.argv[1:]))\n')
    binary.chmod(0o755)
    task = {**task, 'become': False, 'no_log': False, 'async': 10, 'poll': 1}
    # Run the actual import command definition, with an inert executable in place of Nominatim.
    variables = {'debian13_nominatim_venv': str(binary.parents[1]),
                 'nominatim_project_dir': str(tmp_path), 'nominatim_data_file': str(tmp_path / 'extract.pbf'),
                 'debian13_nominatim_import_threads': 4, 'debian13_nominatim_import_updates': retain_updates,
                 'ansible_python_interpreter': '/usr/bin/python3', 'ansible_remote_tmp': str(tmp_path / 'remote')}
    playbook = tmp_path / 'command.yml'
    playbook.write_text(yaml.safe_dump([{'hosts': 'localhost', 'gather_facts': False,
                                       'vars': variables, 'tasks': [task]}]))
    result = subprocess.run(['ansible-playbook', '-i', 'localhost,', '-c', 'local', str(playbook)],
                            capture_output=True, text=True, env={**os.environ,
                            'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
                            'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible'),
                            'ANSIBLE_ASYNC_DIR': str(tmp_path / 'async')})
    assert result.returncode == 0, result.stdout + result.stderr
    arguments = json.loads(observed.read_text())
    assert ('--no-updates' in arguments) is (not retain_updates)
    defaults = yaml.safe_load((ROOT / 'roles/debian13_nominatim/defaults/main.yml').read_text())
    assert defaults['debian13_nominatim_import_updates'] is True


def test_generated_update_units_are_valid_systemd_units(tmp_path, render):
    variables = {'nominatim_project_dir': '/srv/nominatim/europe-project',
                 'debian13_nominatim_venv': '/opt/nominatim/5.3.3/venv',
                 'debian13_nominatim_replication_url': 'https://download.geofabrik.de/europe-updates',
                 'debian13_nominatim_replication_interval': 86400,
                 'debian13_nominatim_replication_recheck': 900,
                 'debian13_nominatim_replication_threads': 2}
    units = []
    for name in ('nominatim-updates.service', 'nominatim-updates.timer'):
        path = tmp_path / name
        path.write_text(render(f'roles/debian13_nominatim/templates/{name}.j2', **variables))
        units.append(str(path))
    result = subprocess.run(['systemd-analyze', 'verify', '--man=no', *units], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
