"""Validate the native metrics configuration produced by the Ansible tasks."""
from copy import deepcopy
import os
from pathlib import Path
import subprocess
import sys
import tomllib

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('legacy', [False, True])
def test_influx_https_options_are_written_to_http_section(tmp_path, legacy):
    config_path = tmp_path / 'influxdb.conf'
    config_path.write_text('''[meta]
dir = "/var/lib/influxdb/meta"
[data]
dir = "/var/lib/influxdb/data"
wal-dir = "/var/lib/influxdb/wal"
[http]
# https-enabled = false
[tls]
min-version = "tls1.2"
''' + ('''bind-address = "127.0.0.14:8086"
https-enabled = true
https-certificate = "/etc/ssl/certs/uranus-instance.pem"
https-private-key = "/etc/ssl/private/uranus-instance.key"
''' if legacy else ''))
    names = {
        'Remove misplaced HTTP options from the legacy TLS section',
        'Configure authenticated transport encryption for private metrics',
    }
    role = yaml.safe_load((ROOT / 'roles/debian13_monitoring/tasks/main.yml').read_text())
    tasks = [deepcopy(task) for task in role if task.get('name') in names]
    for task in tasks:
        task.pop('notify', None)
        module = next(key for key in task
                      if key.startswith(('ansible.builtin.', 'community.general.')))
        task[module]['path'] = str(config_path)
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text(yaml.safe_dump({'all': {'hosts': {'localhost': {
        'ansible_connection': 'local',
        'ansible_host': '127.0.0.14',
        'ansible_python_interpreter': sys.executable,
        'ansible_remote_tmp': str(tmp_path / 'ansible-remote'),
    }}}}))
    playbook = tmp_path / 'transport.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'gather_facts': False, 'tasks': tasks,
    }]))
    environment = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
                   'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
                   'ANSIBLE_NOCOWS': '1'}
    result = subprocess.run([
        str(Path(sys.executable).with_name('ansible-playbook')),
        '-i', str(inventory), str(playbook),
    ], cwd=ROOT, env=environment, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    config = tomllib.loads(config_path.read_text())
    assert config['http']['bind-address'] == '127.0.0.14:8086'
    assert config['http']['https-enabled'] is True
    assert config['http']['https-certificate'] == '/etc/ssl/certs/uranus-instance.pem'
    assert config['http']['https-private-key'] == '/etc/ssl/private/uranus-instance.key'
    assert config['tls'] == {'min-version': 'tls1.2'}
    assert config['meta']['dir'] == '/var/lib/influxdb/meta'
    assert config['data'] == {'dir': '/var/lib/influxdb/data',
                              'wal-dir': '/var/lib/influxdb/wal'}
