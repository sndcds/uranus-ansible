"""A standalone nginx failure must preserve frontend releases unless it activated one."""
import copy
import os
import subprocess

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('previous', ['absent', 'first-release', 'existing-release'])
def test_standalone_frontend_health_failure_preserves_or_restores_release(tmp_path, previous):
    tasks = yaml.safe_load((ROOT / 'roles/debian13_guest_web/tasks/main.yml').read_text())
    health = copy.deepcopy(next(task for task in tasks if 'rescue' in task))
    # Inject a failed health result and exercise the real Ansible rescue/file tasks.
    health['block'][1] = {
        'name': 'Inject an unavailable frontend',
        'ansible.builtin.fail': {'msg': 'fixture frontend unavailable'},
    }
    old_release = tmp_path / 'old-release'
    new_release = tmp_path / 'new-release'
    old_release.mkdir()
    new_release.mkdir()
    current = tmp_path / 'current'
    current.symlink_to(new_release, target_is_directory=True)
    health['rescue'][0]['ansible.builtin.file']['dest'] = str(current)
    variables = {'instance_role': 'prod', 'ansible_remote_tmp': str(tmp_path / 'remote')}
    if previous != 'absent':
        variables['debian13_frontend_previous'] = {
            'stat': {'exists': previous == 'existing-release', 'lnk_source': str(old_release)},
        }
    playbook = tmp_path / 'health.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'gather_facts': False,
        'vars': variables, 'tasks': [health],
    }]))
    result = subprocess.run(
        ['ansible-playbook', '-i', 'localhost,', '-c', 'local', str(playbook)],
        capture_output=True, text=True, env={
            **os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
            'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible'),
        })
    output = result.stdout + result.stderr
    assert result.returncode == 2, output
    assert 'Frontend healthcheck failed: fixture frontend unavailable' in output
    assert current.resolve() == (old_release if previous == 'existing-release' else new_release)
