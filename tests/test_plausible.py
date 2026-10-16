import hashlib
import importlib.util
import json
from pathlib import Path

import pytest

from conftest import ROOT


def load(relative):
    spec = importlib.util.spec_from_file_location(Path(relative).stem, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


exporter = load('roles/debian13_plausible/files/export_data.py')
importer = load('roles/debian13_plausible/files/import_data.py')
challenge = load('scripts/plausible_challenge_proxy.py')


def snapshot(tmp_path):
    (tmp_path / 'postgres.dump').write_bytes(b'snapshot')
    manifest = {'version': 1, 'clickhouse_database': 'plausible_events_db', 'tables': [],
                'sha256': {'postgres.dump': hashlib.sha256(b'snapshot').hexdigest()}}
    (tmp_path / 'manifest.json').write_text(json.dumps(manifest))
    return manifest


def test_import_rejects_corrupted_data_before_opening_databases(tmp_path):
    snapshot(tmp_path)
    (tmp_path / 'postgres.dump').write_bytes(b'changed')
    with pytest.raises(ValueError, match='checksum'):
        importer.validate_snapshot(tmp_path)


@pytest.mark.parametrize('unsafe', ['../outside', '/etc/passwd', 'link'])
def test_import_rejects_paths_outside_the_snapshot(tmp_path, unsafe):
    manifest = snapshot(tmp_path)
    (tmp_path / 'link').symlink_to('/etc/passwd')
    manifest['sha256'][unsafe] = 'unused'
    (tmp_path / 'manifest.json').write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match='Unsafe snapshot path'):
        importer.validate_snapshot(tmp_path)


def test_import_rejects_unverified_table_files(tmp_path):
    manifest = snapshot(tmp_path)
    manifest['tables'] = [{'name': 'events_v2', 'file': 'events.native.gz'}]
    (tmp_path / 'manifest.json').write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match='checksum'):
        importer.validate_snapshot(tmp_path)


def test_dictionaries_use_new_local_connection_without_old_credentials():
    table = {'name': 'location_data_dict', 'create_table_query':
             "CREATE DICTIONARY plausible_events_db.location_data_dict (id String) "
             "SOURCE(CLICKHOUSE(HOST 'old' USER 'old' PASSWORD 'secret(with\\\'quote)' "
             "TABLE 'location_data' DB 'plausible_events_db')) LIFETIME(0) LAYOUT(HASHED())"}
    exporter.portable_dictionary(table, 'plausible_events_db')
    query = table['create_table_query']
    assert 'secret' not in query and "'old'" not in query
    assert "HOST '127.0.0.1' PORT 9000 USER 'default' PASSWORD ''" in query
    assert query.endswith('LIFETIME(0) LAYOUT(HASHED())')


def test_source_merges_resume_when_snapshot_fails(monkeypatch):
    calls = []
    monkeypatch.setattr(exporter, 'clickhouse', lambda url, query: calls.append(query))
    with pytest.raises(RuntimeError):
        with exporter.pause_merges('not-used', 'plausible_events_db', [{'name': 'events', 'engine': 'MergeTree'}]):
            raise RuntimeError('Export failed')
    assert calls == ['SYSTEM STOP MERGES `plausible_events_db`.`events`',
                     'SYSTEM START MERGES `plausible_events_db`.`events`']


def test_acme_change_preserves_the_running_https_application():
    https = 'server {\n server_name plausible.example.com;\n listen 443 ssl;\n location / { proxy_pass http://127.0.0.1:8200; }\n}\n'
    http = 'server {\n server_name plausible.example.com;\n listen 80;\n if ($host = plausible.example.com) { return 301 https://$host$request_uri; }\n return 404;\n}\n'
    result = challenge.replace_http_server(https + http, 'plausible.example.com', '192.0.2.1')
    assert result.startswith(https)
    assert 'location ^~ /.well-known/acme-challenge/' in result
    assert 'proxy_pass http://192.0.2.1;' in result
    assert result == challenge.replace_http_server(result, 'plausible.example.com', '192.0.2.1')
    with pytest.raises(ValueError, match='dedicated'):
        challenge.replace_http_server(https + http.replace('server_name plausible.example.com;', 'server_name other.example.com;'),
                                      'plausible.example.com', '192.0.2.1')


def test_import_refuses_running_application_before_touching_databases(tmp_path, monkeypatch):
    snapshot(tmp_path)
    monkeypatch.setattr(importer.sys, 'argv', ['import', str(tmp_path)])
    monkeypatch.setattr(importer.subprocess, 'run', lambda *a, **k: type('Result', (), {'returncode': 0})())
    with pytest.raises(ValueError, match='must be stopped'):
        importer.main()


def test_import_requires_a_verified_postgres_dump(tmp_path):
    manifest = snapshot(tmp_path)
    manifest['sha256'] = {}
    (tmp_path / 'manifest.json').write_text(json.dumps(manifest))
    with pytest.raises(ValueError, match='dump lacks a checksum'):
        importer.validate_snapshot(tmp_path)


def test_functions_are_restored_after_their_dependencies():
    functions = [{'name': 'outer_function', 'create_query': 'CREATE FUNCTION outer_function AS (x) -> inner_function(x)'},
                 {'name': 'inner_function', 'create_query': 'CREATE FUNCTION inner_function AS (x) -> x + 1'}]
    assert [f['name'] for f in importer.ordered_functions(functions)] == ['inner_function', 'outer_function']
    functions[1]['create_query'] = 'CREATE FUNCTION inner_function AS (x) -> outer_function(x)'
    with pytest.raises(ValueError, match='Cyclic'):
        importer.ordered_functions(functions)


def test_remote_cutover_and_rollback_programs_parse_before_ssh(monkeypatch, capsys):
    import argparse
    import ast
    migration = load('scripts/plausible_migrate.py')
    operation = object.__new__(migration.Migration)
    operation.args = argparse.Namespace(domain='plausible.example.com', ingress_ipv4='192.0.2.1', source='fixture')
    operation.state = {'import': {'verified': True}, 'stamp': 'fixture', 'source_stopped': True}
    operation.save = lambda: None
    programs = []

    def run(code, target=False):
        ast.parse(code)
        programs.append(code)
        return ''

    operation.run = run
    monkeypatch.setattr(migration.subprocess, 'run', lambda *args, **kwargs: None)
    operation.cutover()
    operation.rollback()
    assert len(programs) == 3
    assert 'if backup.exists():' in programs[-1]
