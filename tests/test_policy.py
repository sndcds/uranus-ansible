import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

import yaml

from conftest import ROOT


def test_all_ubuntu_configuration_files_are_unchanged():
    baseline = json.loads((ROOT / 'tests/fixtures/ubuntu-sha256.json').read_text())
    for name, digest in baseline.items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name


def test_production_deployment_is_disabled_by_default(settings):
    assert settings['hetzner_deployment_approved'] is False
    assert settings['hetzner_start_existing_vms'] is False
    assert settings['hetzner_app_initial_import'] is False
    assert settings['hetzner_nominatim_initial_import'] is False
    assert 'host_key_checking = True' in (ROOT / 'ansible-debian13.cfg').read_text()


def test_new_database_tasks_never_drop_or_terminate_existing_data():
    for role in ['debian13_postgresql', 'debian13_monitoring', 'debian13_nominatim']:
        for path in (ROOT / 'roles' / role / 'tasks').glob('*.yml'):
            text = path.read_text()
            assert not re.search(r'\bdropdb\b|\bDROP\s+(DATABASE|SCHEMA|TABLE)\b|pg_terminate_backend', text, re.I), path
    app = (ROOT / 'roles/debian13_postgresql/tasks/application-database.yml').read_text()
    assert 'debian13_postgresql_created_db is changed' in app
    assert 'hetzner_app_initial_import | bool' in app
    initial = (ROOT / 'roles/debian13_postgresql/tasks/initial-import.yml').read_text()
    assert '--single-transaction' in initial and '--set=ON_ERROR_STOP=1' in initial


def test_every_mutating_entrypoint_checks_authorization_before_facts_or_roles():
    for name in ['provision.yml', 'configure.yml', 'ingress.yml']:
        for play in yaml.safe_load((ROOT / 'playbooks/debian13' / name).read_text()):
            assert play['gather_facts'] is False
            assert play['pre_tasks'][0]['ansible.builtin.import_tasks'] == 'gate.yml'


def test_default_gate_fails_locally_before_any_ssh_or_host_facts(tmp_path):
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text('all:\n  children:\n    debian13_hypervisors:\n      hosts:\n        blocked:\n          ansible_host: 127.0.0.1\n          ansible_port: 1\n')
    env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible-debian13.cfg'),
           'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local')}
    result = subprocess.run(['ansible-playbook', '-i', str(inventory), 'playbooks/debian13/provision.yml'],
                            cwd=ROOT, env=env, text=True, capture_output=True)
    assert result.returncode == 2, result.stdout + result.stderr
    assert 'Production deployment is disabled' in result.stdout
    assert 'unreachable=0' in result.stdout
    assert 'TASK [Gather host facts]' not in result.stdout


def test_ci_cannot_deploy_and_has_no_production_secrets():
    text = (ROOT / '.github/workflows/debian13.yml').read_text()
    assert 'secrets.' not in text
    assert 'ssh ' not in text
    assert 'hetzner_deployment_approved' not in text
    assert 'make check' in text
