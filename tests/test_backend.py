"""The Debian backend must build without disabling startup validation."""
import json

import yaml
from conftest import ROOT


def test_backend_configuration_serializes_secrets_and_private_database(render):
    defaults = yaml.safe_load((ROOT / 'group_vars/all.yml').read_text())
    defaults['backend_smtp_port'] = 587  # Resolve the legacy nested variable for plain Jinja.
    password = 'quotes" and backslash\\ and newline\n'
    configuration = json.loads(render('roles/debian13_backend/templates/config.json.j2',
                                     **defaults, app_env='development', backend_domain='api.example.test',
                                     frontend_domain='app.example.test', hostvars={'db01': {'ansible_host': '10.77.0.11'}},
                                     db_host='localhost', db_name='uranus_dev', db_user='uranus_dev', db_password=password))
    assert configuration['db_password'] == password
    assert configuration['db_host'] == '10.77.0.11'
    assert configuration['dev_mode'] is True
    assert configuration['base_api_url'] == 'https://api.example.test'


def test_backend_preserves_validation_source_and_existing_toolchains():
    tasks = yaml.safe_load((ROOT / 'roles/debian13_backend/tasks/main.yml').read_text())
    checkout = next(t for t in tasks if 'ansible.builtin.git' in t)
    assert checkout['ansible.builtin.git']['force'] is False
    commands = [t['ansible.builtin.command']['argv'] for t in tasks if 'ansible.builtin.command' in t]
    assert len(commands) == 1 and '-mod=readonly' in commands[0]
    assert commands[0][1] == 'build'
    assert not any('ansible.builtin.replace' in t or 'ansible.builtin.shell' in t for t in tasks)
    assert not any(t.get('ansible.builtin.file', {}).get('state') == 'absent' for t in tasks)
    text = (ROOT / 'roles/debian13_backend/tasks/main.yml').read_text()
    assert 'not debian13_backend_binary.stat.exists' in text
    assert text.index('Build backend without') < text.index('Record only successful backend build inputs')
    configure = (ROOT / 'playbooks/debian13/configure.yml').read_text()
    assert 'name: debian13_backend' in configure and 'name: app_backend' not in configure
