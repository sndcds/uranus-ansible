"""Backend runtime-path migration must retain the previous working activation."""
import copy
import grp
import os
import pwd
import subprocess
import shlex
import tarfile

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('previous', ['none', 'legacy', 'central'])
def test_failed_runtime_migration_restores_config_unit_and_release(tmp_path, previous):
    tasks = yaml.safe_load((ROOT / 'roles/debian13_backend/tasks/activate.yml').read_text())
    activation = copy.deepcopy(next(task for task in tasks if 'rescue' in task))
    rollback = yaml.safe_load((ROOT / 'roles/debian13_backend/tasks/rollback.yml').read_text())
    old, candidate = tmp_path / 'old', tmp_path / 'candidate'
    old.mkdir()
    candidate.mkdir()
    (old / 'config.json').write_text('{"legacy":true}\n')
    current, config, unit = tmp_path / 'current', tmp_path / 'config.json', tmp_path / 'backend.service'
    if previous != 'none':
        current.symlink_to(old, target_is_directory=True)
        unit.write_text('previous service definition\n')
    if previous == 'central':
        config.write_text('{"previous":true}\n')
        config.chmod(0o600)
    user, group = pwd.getpwuid(os.getuid()).pw_name, grp.getgrgid(os.getgid()).gr_name
    replacements = {
        '/opt/uranus/backend/current': str(current),
        '/etc/systemd/system/uranus-backend.service': str(unit),
        '/opt/uranus/backend/releases/{{ backend_repo_version }}': str(candidate),
    }
    for task in activation['block'] + rollback:
        for module in ['ansible.builtin.file', 'ansible.builtin.copy']:
            if module in task:
                task[module] = {k: replacements.get(v, v) if isinstance(v, str) else v
                                for k, v in task[module].items()}
                if 'owner' in task[module]:
                    task[module].update(owner=user, group=group)
        if 'ansible.builtin.systemd_service' in task:
            task.pop('ansible.builtin.systemd_service')
            task['ansible.builtin.debug'] = {'msg': task['name']}
        if 'ansible.builtin.template' in task:
            args = task.pop('ansible.builtin.template')
            args.pop('src')
            args.pop('validate', None)
            args['dest'] = replacements.get(args['dest'], args['dest'])
            args.update(owner=user, group=group, content='candidate configuration\n')
            task['ansible.builtin.copy'] = args
        if 'ansible.builtin.uri' in task:
            task.pop('ansible.builtin.uri')
            for key in ['until', 'retries', 'delay', 'register']:
                task.pop(key, None)
            task['ansible.builtin.fail'] = {'msg': 'fixture backend unavailable'}
    rollback_file = tmp_path / 'rollback.yml'
    rollback_file.write_text(yaml.safe_dump(rollback))
    activation['rescue'][0]['ansible.builtin.include_tasks'] = str(rollback_file)
    playbook = tmp_path / 'activation.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'gather_facts': False,
        'vars': {
            'ansible_remote_tmp': str(tmp_path / 'remote'),
            'debian13_backend_config_path': str(config),
            'debian13_backend_previous': {'stat': {'exists': previous != 'none', 'lnk_source': str(old)}},
            'debian13_backend_before': {'results': [
                {'stat': {'exists': previous == 'central'}},
                {'stat': {'exists': previous != 'none'}},
            ]},
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
    assert 'Previous release, configuration and service restored' in output
    if previous == 'none':
        assert not current.is_symlink() and not unit.exists()
    else:
        assert current.resolve() == old
        assert unit.read_text() == 'previous service definition\n'
    if previous == 'central':
        assert config.read_text() == '{"previous":true}\n'
        assert config.stat().st_mode & 0o777 == 0o600
    else:
        assert not config.exists()
    assert (old / 'config.json').read_text() == '{"legacy":true}\n'
    assert candidate.is_dir()


def test_application_archive_contains_central_config_and_original_media(tmp_path):
    from jinja2 import Environment, StrictUndefined
    tasks = yaml.safe_load((ROOT / 'roles/application_backup/tasks/main.yml').read_text())
    script = next(task['ansible.builtin.copy']['content'] for task in tasks
                  if task.get('ansible.builtin.copy', {}).get('dest') == '/usr/local/sbin/uranus-app-backup')
    script = Environment(undefined=StrictUndefined).from_string(script).render(
        inventory_hostname='fixture', backup_retention_days=14)
    filesystem, archives = tmp_path / 'root', tmp_path / 'archives'
    archives.mkdir()
    contents = {
        'opt/uranus/code': b'code', 'etc/nginx/site.conf': b'nginx',
        'etc/uranus/config.json': b'{"private":"fixture"}',
        'var/lib/uranus/image/photo.webp': b'original',
        'var/lib/uranus/avatar/profile.webp': b'avatar',
        'var/cache/uranus/thumbnail.webp': b'disposable',
    }
    for name, content in contents.items():
        path = filesystem / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    (filesystem / 'etc/uranus/config.json').chmod(0o600)
    script = script.replace('/var/backups/uranus/app', str(archives))
    script = script.replace('tar -C / ', 'tar -C ' + shlex.quote(str(filesystem)) + ' ')
    subprocess.run(['bash', '-c', script], check=True, capture_output=True)
    archive_path, = archives.iterdir()
    assert archive_path.stat().st_mode & 0o777 == 0o600
    with tarfile.open(archive_path) as archive:
        for name in contents:
            if name.startswith('var/cache/'):
                assert name not in archive.getnames()
            else:
                assert archive.extractfile(name).read() == contents[name]
        assert archive.getmember('etc/uranus/config.json').mode == 0o600
