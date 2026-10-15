"""Exercise Ansible's delegated SSH options without opening a connection."""
import os
from pathlib import Path
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('source,target', [('mon01', 'db01'), ('dev01', 'mon01')])
def test_delegated_guest_uses_its_own_address(tmp_path, source, target):
    inventory = yaml.safe_load((ROOT / 'environments/hetzner/inventory.yml').read_text())
    inventory['all']['children'].pop('incus_hosts')
    guests = inventory['all']['children']['uranus_instances']
    addresses = {name: f'127.0.0.{index}'
                 for index, name in enumerate(guests['hosts'], start=11)}
    guests['vars'].update({
        'ansible_connection': 'ssh',
        'ansible_ssh_executable': '/bin/false',
        'ansible_become': False,
        'ansible_python_interpreter': sys.executable,
        'ansible_remote_tmp': str(tmp_path / 'ansible-remote'),
        'incus_instances': [{'name': name, 'ip': address}
                            for name, address in addresses.items()],
    })
    inventory_path = tmp_path / 'inventory.yml'
    inventory_path.write_text(yaml.safe_dump(inventory))
    plugins = tmp_path / 'action_plugins'
    plugins.mkdir()
    (plugins / 'probe_connection_address.py').write_text('''
from ansible.plugins.action import ActionBase

class ActionModule(ActionBase):
    def run(self, tmp=None, task_vars=None):
        result = super().run(tmp, task_vars)
        result.update(changed=False, address=self._connection.get_option('host'))
        return result
''')
    playbook = tmp_path / 'delegation.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': source,
        'gather_facts': False,
        'tasks': [{
            'name': 'Read the resolved SSH target without executing a remote command',
            'probe_connection_address': {},
            'delegate_to': target,
            'changed_when': False,
            'register': 'resolved_address',
        }, {
            'ansible.builtin.assert': {
                'that': [f'resolved_address.address == "{addresses[target]}"'],
            },
        }],
    }]))
    environment = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
                   'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
                   'ANSIBLE_ACTION_PLUGINS': str(plugins),
                   'ANSIBLE_NOCOWS': '1'}
    result = subprocess.run([
        str(Path(sys.executable).with_name('ansible-playbook')),
        '-i', str(inventory_path), str(playbook),
    ], cwd=ROOT, env=environment, text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
