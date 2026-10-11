"""Native Debian application checks, enforced in a separate isolated CI container."""
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import subprocess
import tarfile
import urllib.request

import pytest
import yaml
from conftest import ROOT

pytestmark = pytest.mark.skipif(os.environ.get('URANUS_NATIVE_APPLICATIONS') != '1',
                               reason='Native application dependencies are installed in the dedicated Debian CI job')
BACKEND = 'ce426a0f9b2d4c79f81a0ccd291999406cddfa11'
FRONTEND = '87658dc2ff8d1492c6e0158afd57e59d428c6451'


def run(argv, **kwargs):
    result = subprocess.run(argv, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, result.stdout + result.stderr
    return result.stdout + result.stderr


def download(url, target, checksum):
    with urllib.request.urlopen(url, timeout=60) as response, target.open('wb') as stream:
        while chunk := response.read(1024 * 1024):
            stream.write(chunk)
    assert hashlib.sha256(target.read_bytes()).hexdigest() == checksum


def checkout(path, repository, revision):
    run(['git', 'init', str(path)])
    run(['git', '-C', str(path), 'fetch', '--depth=1', repository, revision])
    run(['git', '-C', str(path), 'checkout', '--detach', 'FETCH_HEAD'])
    assert run(['git', '-C', str(path), 'rev-parse', 'HEAD']).strip() == revision


def test_native_package_tools_and_monitoring_configuration(render):
    os_release = Path('/etc/os-release').read_text()
    assert 'VERSION_ID="13"' in os_release
    tools = [(['psql', '--version'], '17.'), (['osm2pgsql', '--version'], 'osm2pgsql'),
             (['php', '--version'], '8.4.'), (['influxd', 'version'], 'InfluxDB'),
             (['postconf', '-d', '-h', 'mail_version'], '3.'),
             (['osinfo-query', 'os'], 'debian13')]
    for argv, expected in tools:
        assert expected in run(argv)
    schemas = [p for p in Path('/usr/share/icingaweb2').rglob('*.sql') if p.name in ('pgsql.schema.sql', 'pgsql.sql')]
    assert len(schemas) == 1
    assert Path('/usr/share/icinga2-ido-pgsql/schema/pgsql.sql').is_file()
    # Only this disposable container's package defaults are extended and parsed.
    Path('/etc/icinga2/conf.d/uranus-compatibility.conf').write_text(
        render('roles/debian13_monitoring/templates/vm-checks.conf.j2'))
    run(['icinga2', 'daemon', '-C'])
    run(['/usr/share/grafana/bin/grafana', 'server', '--help'])


def test_nominatim_python_and_asgi_api_on_debian13(tmp_path, monkeypatch):
    assert importlib.metadata.version('nominatim-db') == '5.1.0'
    assert importlib.metadata.version('nominatim-api') == '5.1.0'
    run(['nominatim', '--help'])
    from nominatim_api.server.falcon.server import run_wsgi
    monkeypatch.chdir(tmp_path)
    application = run_wsgi()
    assert application.__class__.__module__ == 'falcon.asgi.app'


def test_backend_compiles_with_verified_toolchain_and_consistency_check_intact(tmp_path):
    defaults = yaml.safe_load((ROOT / 'group_vars/all.yml').read_text())
    archive = tmp_path / 'go.tar.gz'
    download(f'https://go.dev/dl/go{defaults["backend_go_version"]}.linux-amd64.tar.gz',
             archive, defaults['backend_go_archive_sha256'])
    with tarfile.open(archive) as stream:
        stream.extractall(tmp_path, filter='data')
    source = tmp_path / 'backend'
    checkout(source, defaults['backend_repo_url'], BACKEND)
    before = (source / 'uranus-api.go').read_bytes()
    assert b'CheckAllDatabaseConsistency(context.Background())' in before
    env = {**os.environ, 'GOTOOLCHAIN': 'local', 'CGO_ENABLED': '1'}
    run([str(tmp_path / 'go/bin/go'), 'build', '-mod=readonly', '-o', str(tmp_path / 'uranus-api'), './uranus-api.go'],
        cwd=source, env=env, timeout=600)
    assert (source / 'uranus-api.go').read_bytes() == before
    assert run(['git', '-C', str(source), 'status', '--porcelain']).strip() == ''
    assert (tmp_path / 'uranus-api').is_file()


def test_frontend_builds_with_node24_and_frozen_pnpm_lock(tmp_path):
    assert run(['node', '--version']).startswith('v24.')
    source = tmp_path / 'frontend'
    checkout(source, 'https://github.com/sndcds/uranus-dashboard.git', FRONTEND)
    package = json.loads((source / 'package.json').read_text())
    manager = package['packageManager']
    assert manager.startswith('pnpm@')
    lock = (source / 'pnpm-lock.yaml').read_bytes()
    command = ['npm', 'exec', '--yes', '--package=' + manager, '--', 'pnpm']
    run(command + ['install', '--frozen-lockfile'], cwd=source, timeout=600)
    run(command + ['run', 'build'], cwd=source, timeout=600)
    assert (source / 'dist/index.html').is_file()
    assert (source / 'pnpm-lock.yaml').read_bytes() == lock


def test_verified_versatiles_binary_runs_on_native_debian13(tmp_path, settings):
    archive = tmp_path / 'versatiles.tar.gz'
    download(settings['hetzner_versatiles_archive_url'], archive, settings['hetzner_versatiles_archive_sha256'])
    with tarfile.open(archive) as stream:
        stream.extractall(tmp_path, filter='data')
    assert '5.0.0' in run([str(tmp_path / 'versatiles'), '--version'])


def test_backup_and_logrotate_tools_support_generated_scripts(tmp_path):
    from jinja2 import Environment
    env = Environment()
    variables = {'vm_role': 'dev', 'backup_root': str(tmp_path), 'inventory_hostname': 'dev01',
                 'managed_app_backup_paths': [], 'backup_retention_days': 14}
    legacy = yaml.safe_load((ROOT / 'roles/backup/tasks/main.yml').read_text())
    task = next(t for t in legacy if t['name'] == 'Install application backup script')
    script = tmp_path / 'backup.sh'
    script.write_text(env.from_string(task['ansible.builtin.copy']['content']).render(**variables))
    run(['bash', '-n', str(script)])
    config = tmp_path / 'logrotate.conf'
    task = yaml.safe_load((ROOT / 'roles/logrotate/tasks/main.yml').read_text())[0]
    config.write_text(env.from_string(task['ansible.builtin.copy']['content']).render(logrotate_retention=14))
    run(['logrotate', '--debug', '--state', str(tmp_path / 'state'), str(config)])
