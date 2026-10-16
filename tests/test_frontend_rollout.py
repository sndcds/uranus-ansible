"""Exercise failed Nuxt activation against actual Ansible file restoration."""
import base64
import copy
import grp
import os
import pwd
import subprocess

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('previous', ['none', 'static', 'node'])
def test_failed_nuxt_activation_restores_release_service_environment_and_nginx(tmp_path, previous):
    tasks = yaml.safe_load((ROOT / 'roles/debian13_frontend/tasks/node.yml').read_text())
    activation = copy.deepcopy(next(task for task in tasks if 'rescue' in task))
    rollback = yaml.safe_load((ROOT / 'roles/debian13_frontend/tasks/rollback.yml').read_text())
    current = tmp_path / 'current'
    candidate = tmp_path / 'candidate'
    candidate.mkdir()
    old = tmp_path / 'old-release'
    old.mkdir()
    current.symlink_to(candidate, target_is_directory=True)
    paths = [current, tmp_path / 'frontend.service', tmp_path / 'frontend.env', tmp_path / 'nginx.conf']
    original = {paths[3]: 'previous nginx configuration\n'}
    if previous == 'node':
        original.update({paths[1]: 'previous systemd unit\n', paths[2]: 'previous environment\n'})
    before = [{'item': str(path), 'stat': {'exists': path in original}} for path in paths]
    before[0]['stat'] = {'exists': previous != 'none', 'lnk_source': str(old)}
    saved = [
        {'source': str(path), 'content': base64.b64encode(text.encode()).decode()}
        for path, text in original.items()
    ]
    for path in paths[1:]:
        path.write_text('rejected configuration\n')
    for task in rollback:
        if 'ansible.builtin.systemd_service' in task or 'ansible.builtin.command' in task:
            # Substitute the daemon boundary; keep all real restore/file tasks.
            task.pop('ansible.builtin.systemd_service', None)
            task.pop('ansible.builtin.command', None)
            task['ansible.builtin.debug'] = {'msg': task['name']}
        if 'ansible.builtin.file' in task:
            task['ansible.builtin.file'] = {
                k: str(current) if v == '/opt/uranus/frontend/current' else v
                for k, v in task['ansible.builtin.file'].items()
            }
        if 'ansible.builtin.copy' in task:
            task['ansible.builtin.copy']['owner'] = pwd.getpwuid(os.getuid()).pw_name
            task['ansible.builtin.copy']['group'] = grp.getgrgid(os.getgid()).gr_name
    rollback_path = tmp_path / 'rollback.yml'
    rollback_path.write_text(yaml.safe_dump(rollback))
    activation['block'] = [{
        'name': 'Inject a rejected candidate after activation',
        'ansible.builtin.fail': {'msg': 'fixture SSR health failure'},
    }]
    activation['rescue'][0]['ansible.builtin.include_tasks'] = str(rollback_path)
    playbook = tmp_path / 'rollout.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'gather_facts': False,
        'vars': {
            'ansible_remote_tmp': str(tmp_path / 'remote'),
            'debian13_frontend_previous': before[0],
            'debian13_frontend_before': {'results': before},
            'debian13_frontend_saved_files': {'results': saved},
        },
        'tasks': [activation],
    }]))
    result = subprocess.run(
        ['ansible-playbook', '-i', 'localhost,', '-c', 'local', str(playbook)],
        capture_output=True, text=True,
        env={**os.environ, 'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible')},
    )
    output = result.stdout + result.stderr
    assert result.returncode == 2, output
    assert 'fixture SSR health failure' in output
    if previous == 'none':
        assert not current.is_symlink()
    else:
        assert current.resolve() == old
    for path in paths[1:]:
        if path in original:
            assert path.read_text() == original[path]
        else:
            assert not path.exists()
    assert candidate.is_dir() and old.is_dir()


@pytest.mark.parametrize('runtime', ['static', 'node'])
def test_frontend_nginx_supports_static_and_private_ssr(runtime, render, tmp_path):
    from test_templates import nginx_check
    text = render('roles/debian13_guest_web/templates/guest.conf.j2',
                  instance_role='dev', ansible_host='10.77.0.12',
                  frontend_domain='dev.example.test', backend_domain='api.dev.example.test',
                  backend_port=9090, frontend_runtime=runtime, frontend_port=3000)
    assert ('proxy_pass http://127.0.0.1:3000;' in text) == (runtime == 'node')
    assert ('root /opt/uranus/frontend/current;' in text) == (runtime == 'static')
    nginx_check(text, tmp_path)
