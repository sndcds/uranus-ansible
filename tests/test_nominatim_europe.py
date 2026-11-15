"""Run replacement safeguards against an isolated local PostgreSQL cluster."""
import json

import pytest
import yaml

from conftest import ROOT
from test_database_integration import create_user, postgres, sql
from test_nominatim import run_tasks


def europe_variables(tmp_path):
    return {
        **yaml.safe_load((ROOT / 'environments/hetzner/nominatim-europe.yml').read_text()),
        'debian13_nominatim_europe_state_dir': str(tmp_path / 'europe-state'),
        'debian13_nominatim_europe_previous_database': 'europe_previous',
        'debian13_nominatim_europe_host': 'localhost',
        'debian13_nominatim_europe_host_storage_path': str(tmp_path),
        'debian13_nominatim_europe_nom_min_free_gib': 0,
        'debian13_nominatim_europe_nom_storage_path': str(tmp_path),
        'debian13_nominatim_europe_host_reserve_gib': 0,
        'debian13_nominatim_db_min_free_gib': 0,
    }


@pytest.mark.parametrize('collision', [False, True])
def test_preserving_database_keeps_its_identity_and_rows(postgres, tmp_path, collision):
    name = 'europe_preserve_' + str(int(collision))
    previous = name + '_previous'
    create_user(postgres, name)
    sql(postgres, f'CREATE DATABASE {name} OWNER {name}')
    sql(postgres, "CREATE TABLE important(value text); INSERT INTO important VALUES ('retained')", name)
    oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
    if collision:
        sql(postgres, f'CREATE DATABASE {previous}')
    result = run_tasks(postgres, tmp_path, name, tasks_from='europe-preserve-database',
                       debian13_nominatim_europe_previous_database=previous)
    assert result.returncode == (2 if collision else 0), result.stdout + result.stderr
    retained_name = name if collision else previous
    assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{retained_name}'") == oid
    assert sql(postgres, 'SELECT value FROM important', retained_name) == 'retained'
    if not collision:
        assert sql(postgres, f"SELECT count(*) FROM pg_database WHERE datname='{name}'") == '0'


def test_capacity_failure_happens_without_creating_an_attempt_or_renaming(postgres, tmp_path):
    name = 'europe_capacity'
    create_user(postgres, name)
    sql(postgres, f'CREATE DATABASE {name} OWNER {name}')
    variables = europe_variables(tmp_path)
    variables['debian13_nominatim_europe_previous_database'] = 'europe_capacity_previous'
    variables['debian13_nominatim_db_min_free_gib'] = 10**9
    result = run_tasks(postgres, tmp_path, name, tasks_from='europe-preflight', **variables)
    assert result.returncode == 2, result.stdout + result.stderr
    assert 'Insufficient Europe import capacity' in result.stdout
    assert sql(postgres, f"SELECT count(*) FROM pg_database WHERE datname='{name}'") == '1'
    assert not (tmp_path / 'europe-state').exists()


@pytest.mark.parametrize('manifest', [None, {'completed': False, 'phase': 'replacing'}])
def test_interrupted_attempt_stops_before_touching_a_database(postgres, tmp_path, manifest):
    variables = europe_variables(tmp_path)
    attempt = tmp_path / 'europe-state'
    attempt.mkdir()
    if manifest is not None:
        (attempt / 'manifest.json').write_text(json.dumps(manifest))
    result = run_tasks(postgres, tmp_path, 'europe_interrupted', tasks_from='europe', **variables)
    assert result.returncode == 2, result.stdout + result.stderr
    assert 'A previous Europe attempt needs inspection' in result.stdout
    assert 'Verify the current database' not in result.stdout
    assert sql(postgres, "SELECT count(*) FROM pg_database WHERE datname='europe_interrupted'") == '0'
    assert attempt.exists()


def test_runtime_checksum_authorizes_only_the_prepared_import(postgres, tmp_path):
    variables = europe_variables(tmp_path)
    variables.update(debian13_nominatim_europe_verified_sha256='a' * 64, debian13_nominatim_europe_import_authorized=True)
    result = run_tasks(postgres, tmp_path, 'europe_runtime_checksum', **variables)
    assert result.returncode == 0, result.stdout + result.stderr
    assert sql(postgres, "SELECT count(*) FROM pg_database WHERE datname='europe_runtime_checksum'") == '0'


def test_read_only_preflight_finishes_without_reserving_or_changing_the_database(postgres, tmp_path):
    name = 'europe_read_only'
    create_user(postgres, name)
    sql(postgres, f'CREATE DATABASE {name} OWNER {name}')
    sql(postgres, 'CREATE TABLE placex(id integer); CREATE TABLE import_status(indexed boolean); '
        'INSERT INTO import_status VALUES (true)', name)
    original_oid = sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'")
    variables = europe_variables(tmp_path)
    variables.update(debian13_nominatim_europe_preflight_only=True,
                     debian13_nominatim_europe_previous_database='europe_read_only_previous')
    result = run_tasks(postgres, tmp_path, name, tasks_from='europe', **variables)
    assert result.returncode == 0, result.stdout + result.stderr
    assert sql(postgres, f"SELECT oid FROM pg_database WHERE datname='{name}'") == original_oid
    assert not (tmp_path / 'europe-state').exists()
