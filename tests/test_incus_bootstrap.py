"""Execute the guest bootstrap against real files and isolated guest commands."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT


@pytest.fixture
def bootstrap_fixture(tmp_path, settings):
    guest = tmp_path / 'guest'
    for directory in ['etc/ssh', 'etc/sudoers.d', 'home/debian', 'var/lib', 'run']:
        (guest / directory).mkdir(parents=True, exist_ok=True)
    (guest / 'etc/hostname').write_text('distrobuilder-fixture\n')
    (guest / 'etc/hosts').write_text('127.0.0.1 localhost\n127.0.1.1 distrobuilder-fixture\n::1 localhost\n')
    # Reproduce a cloud-init-created main file before openssh-server was installed.
    (guest / 'etc/ssh/sshd_config').write_text('PasswordAuthentication no\n')
    key = tmp_path / 'identity'
    subprocess.run(['ssh-keygen', '-t', 'ed25519', '-N', '', '-C', 'fixture $literal `comment`',
                    '-f', str(key)], check=True, capture_output=True)
    state = tmp_path / 'state.json'
    state.write_text(json.dumps({
        'packages': [], 'hostname': 'distrobuilder-fixture', 'user': False,
        'groups': [], 'shell': '/bin/sh', 'locked': False,
        'ssh_enabled': False, 'ssh_active': False,
    }))
    events = tmp_path / 'events.jsonl'
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    executable = binaries / 'guest-command'
    executable.write_text(f'''#!{sys.executable}
import json
import os
from pathlib import Path
import subprocess
import sys

guest = Path({str(guest)!r})
state_file = Path({str(state)!r})
state = json.loads(state_file.read_text())
command = Path(sys.argv[0]).name
args = sys.argv[1:]
with Path({str(events)!r}).open('a') as stream:
    stream.write(json.dumps([command, *args]) + '\\n')

def save():
    state_file.write_text(json.dumps(state))

if command == 'dpkg-query':
    assert args[:2] == ['-W', '-f=${{Status}}']
    if args[2] not in state['packages']:
        sys.exit(1)
    print('install ok installed')
elif command == 'apt-get':
    if state.get('apt_failure'):
        sys.exit(100)
    if 'install' in args:
        packages = args[args.index('install') + 1:]
        assert set(packages) <= set({settings['incus_guest_bootstrap_packages']!r})
        state['packages'] += packages
        save()
    else:
        assert args[-1] == 'update'
elif command == 'hostname':
    assert not args
    print(state['hostname'])
elif command == 'hostnamectl':
    assert args[0] == 'set-hostname'
    state['hostname'] = args[1]
    save()
elif command == 'getent':
    assert args in [['passwd', 'debian'], ['shadow', 'debian']]
    if not state['user']:
        sys.exit(2)
    if args[0] == 'passwd':
        print(f"debian:x:{{os.getuid()}}:{{os.getgid()}}::{{guest / 'home/debian'}}:{{state['shell']}}")
    else:
        print('debian:' + ('!' if state['locked'] else 'fixture-hash') + ':1:0:99999:7:::')
elif command == 'useradd':
    assert args == ['--create-home', '--shell', '/bin/bash', '--groups', 'adm,sudo', 'debian']
    state.update(user=True, shell='/bin/bash', groups=['adm', 'sudo'], locked=True)
    save()
elif command == 'usermod':
    if args == ['--lock', 'debian']:
        state['locked'] = True
    else:
        assert args == ['--append', '--groups', 'adm,sudo', '--shell', '/bin/bash', 'debian']
        state.update(groups=sorted(set(state['groups']) | {{'adm', 'sudo'}}), shell='/bin/bash')
    save()
elif command == 'id':
    assert args == ['-Gn', 'debian']
    print(' '.join(state['groups']))
elif command == 'visudo':
    file = args[1] if args[0] == '-cf' else str(guest / 'etc/sudoers.d/60-uranus-debian')
    # The native parser validates the staged sudoers file; never read system sudoers.
    sys.exit(subprocess.run(['/usr/sbin/visudo', '-cf', file]).returncode)
elif command == 'ssh-keygen':
    actual = ['-A', '-f', str(guest)] if args == ['-A'] else args
    sys.exit(subprocess.run(['/usr/bin/ssh-keygen', *actual]).returncode)
elif command == 'sshd':
    assert args in [['-t'], ['-T']] or args[:2] == ['-t', '-f']
    assert (guest / 'run/sshd').is_dir()
    assert list((guest / 'etc/ssh').glob('ssh_host_*_key'))
    if args == ['-T']:
        main = (guest / 'etc/ssh/sshd_config').read_text()
        if 'Subsystem sftp ' in main:
            print('subsystem sftp internal-sftp')
        required = 'Include ' + str(guest / 'etc/ssh/sshd_config.d/00-uranus.conf')
        if not main.startswith(required + '\\n'):
            print('passwordauthentication no\\nkbdinteractiveauthentication yes\\npermitrootlogin without-password\\nusepam no\\npubkeyauthentication yes\\nauthenticationmethods any')
            sys.exit(0)
        config = (guest / 'etc/ssh/sshd_config.d/00-uranus.conf').read_text()
        if state.get('ssh_override'):
            config = config.replace('PasswordAuthentication no', 'PasswordAuthentication yes')
        print(config.lower(), end='')
elif command == 'systemctl':
    assert args[-1] == 'ssh'
    if args[0] in ['is-enabled', 'is-active']:
        sys.exit(0 if state['ssh_enabled' if args[0] == 'is-enabled' else 'ssh_active'] else 1)
    if args == ['enable', '--now', 'ssh']:
        state.update(ssh_enabled=True, ssh_active=True)
        save()
    else:
        assert args == ['reload', 'ssh'] and state['ssh_active']
else:
    raise RuntimeError('Unexpected guest command: ' + command)
''')
    executable.chmod(0o755)
    for command in ['dpkg-query', 'apt-get', 'hostname', 'hostnamectl', 'getent',
                    'useradd', 'usermod', 'id', 'visudo', 'ssh-keygen', 'sshd', 'systemctl']:
        (binaries / command).symlink_to(executable)
    return {
        'guest': guest, 'key': key.with_suffix('.pub'), 'state': state,
        'events': events, 'bin': binaries,
        'env': {**os.environ, 'PATH': str(binaries) + os.pathsep + os.environ['PATH']},
    }


def guest_script(script, fixture):
    for path in ['/etc', '/var/lib/uranus', '/run/sshd']:
        script = script.replace(path, str(fixture['guest']) + path)
    return script.replace('/usr/sbin/sshd', str(fixture['bin'] / 'sshd'))


def bootstrap(render, fixture, instance):
    script = render('roles/incus_instance/templates/bootstrap.sh.j2',
                    incus_instance=instance, lookup=lambda kind, path: fixture['key'].read_text())
    return subprocess.run(['sh', '-s'], input=guest_script(script, fixture),
                          env=fixture['env'], capture_output=True, text=True, timeout=30)


@pytest.mark.parametrize('index', range(6))
def test_all_guests_get_the_baseline_and_repeat_preserves_keys(render, settings, bootstrap_fixture, index):
    fixture = bootstrap_fixture
    instance = settings['incus_instances'][index]
    first = bootstrap(render, fixture, instance)
    assert first.returncode == 0, first.stdout + first.stderr
    assert json.loads(first.stdout) == {'changed': True, 'instance': instance['name'], 'ready': True}
    guest = fixture['guest']
    state = json.loads(fixture['state'].read_text())
    assert set(state['packages']) == set(settings['incus_guest_bootstrap_packages'])
    assert state['hostname'] == instance['name']
    assert state['user'] and state['locked'] and state['shell'] == '/bin/bash'
    assert {'adm', 'sudo'} <= set(state['groups'])
    assert state['ssh_enabled'] and state['ssh_active']
    main = (guest / 'etc/ssh/sshd_config').read_text()
    assert main.startswith('Include ' + str(guest / 'etc/ssh/sshd_config.d/00-uranus.conf') + '\n')
    assert main.endswith('PasswordAuthentication no\n')
    assert main.count('Subsystem sftp internal-sftp') == 1
    keys = guest / 'home/debian/.ssh/authorized_keys'
    assert keys.read_text() == fixture['key'].read_text()
    assert keys.stat().st_mode & 0o777 == 0o600
    assert keys.parent.stat().st_mode & 0o777 == 0o700
    assert '127.0.0.1 localhost' in (guest / 'etc/hosts').read_text()
    assert '127.0.1.1\t' + instance['name'] in (guest / 'etc/hosts').read_text()
    assert (guest / 'etc/sudoers.d/60-uranus-debian').stat().st_mode & 0o777 == 0o440
    marker = guest / 'var/lib/uranus/instance-bootstrap.json'
    assert json.loads(marker.read_text()) == {'version': 1, 'instance': instance['name']}
    files = {path: (path.stat().st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest())
             for path in guest.rglob('*') if path.is_file()}
    calls = fixture['events'].read_text().splitlines()
    second = bootstrap(render, fixture, instance)
    assert second.returncode == 0, second.stdout + second.stderr
    assert json.loads(second.stdout)['changed'] is False
    assert files == {path: (path.stat().st_mtime_ns, hashlib.sha256(path.read_bytes()).hexdigest())
                     for path in guest.rglob('*') if path.is_file()}
    repeat = [json.loads(line) for line in fixture['events'].read_text().splitlines()[len(calls):]]
    assert not any(call[0] in ['apt-get', 'useradd', 'usermod', 'hostnamectl'] for call in repeat)
    assert not any(call[:2] == ['systemctl', 'reload'] for call in repeat)


def test_existing_user_keys_and_groups_are_preserved(render, settings, bootstrap_fixture):
    fixture = bootstrap_fixture
    state = json.loads(fixture['state'].read_text())
    state.update(user=True, groups=['operators'], ssh_active=True, ssh_enabled=True)
    fixture['state'].write_text(json.dumps(state))
    ssh = fixture['guest'] / 'home/debian/.ssh'
    ssh.mkdir()
    keys = ssh / 'authorized_keys'
    keys.write_text('ssh-ed25519 existing-key existing-admin\n')
    result = bootstrap(render, fixture, settings['incus_instances'][0])
    assert result.returncode == 0, result.stdout + result.stderr
    assert keys.read_text() == 'ssh-ed25519 existing-key existing-admin\n' + fixture['key'].read_text()
    state = json.loads(fixture['state'].read_text())
    assert set(state['groups']) == {'operators', 'adm', 'sudo'}
    assert state['locked']


def test_existing_main_ssh_configuration_is_preserved_and_reloaded(render, settings, bootstrap_fixture):
    fixture = bootstrap_fixture
    main = fixture['guest'] / 'etc/ssh/sshd_config'
    original = 'Port 2222\nInclude ' + str(fixture['guest'] / 'etc/ssh/sshd_config.d/*.conf') + '\nUsePAM yes\nSubsystem sftp /usr/lib/openssh/sftp-server\n'
    main.write_text(original)
    state = json.loads(fixture['state'].read_text())
    state.update(ssh_active=True, ssh_enabled=True)
    fixture['state'].write_text(json.dumps(state))
    result = bootstrap(render, fixture, settings['incus_instances'][0])
    assert result.returncode == 0, result.stdout + result.stderr
    assert main.read_text().endswith(original)
    assert main.read_text().count('Subsystem sftp ') == 1
    events = [json.loads(line) for line in fixture['events'].read_text().splitlines()]
    assert ['systemctl', 'reload', 'ssh'] in events
    assert any(call[0] == 'sshd' and call[1:3] == ['-t', '-f'] for call in events)


@pytest.mark.parametrize('failure', ['apt_failure', 'ssh_override', 'key_symlink'])
def test_failed_bootstrap_never_claims_readiness(render, settings, bootstrap_fixture, failure):
    fixture = bootstrap_fixture
    external = fixture['guest'].parent / 'existing-admin-keys'
    external.write_text('existing keys\n')
    if failure == 'key_symlink':
        ssh = fixture['guest'] / 'home/debian/.ssh'
        ssh.mkdir()
        (ssh / 'authorized_keys').symlink_to(external)
    else:
        state = json.loads(fixture['state'].read_text())
        state[failure] = True
        fixture['state'].write_text(json.dumps(state))
    result = bootstrap(render, fixture, settings['incus_instances'][0])
    assert result.returncode != 0
    assert not (fixture['guest'] / 'var/lib/uranus/instance-bootstrap.json').exists()
    assert external.read_text() == 'existing keys\n'
    assert not json.loads(fixture['state'].read_text())['ssh_enabled']


@pytest.mark.parametrize('cloud_status, guard_failed', [
    ('disabled', False), ('done', False), ('baseline-error', False),
    ('custom-command', False), ('error', False), ('running-error', False), ('disabled', True),
])
def test_ansible_bootstrap_checks_cloud_init_and_storage_before_mutations(
        tmp_path, settings, bootstrap_fixture, cloud_status, guard_failed):
    fixture = bootstrap_fixture
    library = tmp_path / 'library'
    library.mkdir()
    incus = fixture['bin'] / 'incus'
    incus.write_text(f'''#!{sys.executable}
import json
from pathlib import Path
import subprocess
import sys
assert sys.argv[1:7] == ['--force-local', '--project', 'uranus', 'exec', 'db01', '--']
args = sys.argv[7:]
with Path({str(fixture['events'])!r}).open('a') as stream:
    stream.write(json.dumps(['incus', *args]) + '\\n')
if args == ['timeout', '600', 'cloud-init', 'status', '--wait', '--format', 'json']:
    kind = {cloud_status!r}
    historical = kind in ['baseline-error', 'custom-command', 'running-error']
    errors = ["('package-update-upgrade-install', ProcessExecutionError('fixture apt failure'))",
              "('scripts-user', RuntimeError('fixture ssh failure'))"] if historical else (['fixture error'] if kind == 'error' else [])
    print(json.dumps({{'status': 'error' if errors else kind, 'errors': errors,
                      'stage': 'modules-final' if kind == 'running-error' else None,
                      'modules-final': {{'errors': errors}}}}))
    sys.exit(1 if errors else 0)
if args == ['cat', '/var/lib/cloud/instance/cloud-config.txt']:
    print({yaml.safe_dump({'packages': ['openssh-server', 'python3', 'sudo', 'acl'], 'runcmd': [['systemctl', 'enable', '--now', 'ssh']] if cloud_status != 'custom-command' else [['custom-application-import']]})!r})
    sys.exit(0)
assert args == ['timeout', '900', 'sh', '-s']
script = sys.stdin.read()
for path in ['/etc', '/var/lib/uranus', '/run/sshd']:
    script = script.replace(path, {str(fixture['guest'])!r} + path)
script = script.replace('/usr/sbin/sshd', {str(fixture['bin'] / 'sshd')!r})
sys.exit(subprocess.run(['sh', '-s'], input=script, text=True).returncode)
''')
    incus.chmod(0o755)
    (library / 'uranus_storage_guard.py').write_text(f'''
from ansible.module_utils.basic import AnsibleModule
module = AnsibleModule(argument_spec={{}})
if {guard_failed!r}:
    module.fail_json(msg='fixture storage mismatch')
module.exit_json(changed=False)
''')
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text(yaml.safe_dump({'all': {'hosts': {'localhost': {
        'ansible_connection': 'local', 'ansible_python_interpreter': sys.executable,
    }}}}))
    playbook = tmp_path / 'bootstrap.yml'
    playbook.write_text(yaml.safe_dump([{
        'name': 'Test guest bootstrap through the real Ansible tasks',
        'hosts': 'localhost', 'gather_facts': False,
        'vars': {
            'incus_instance': settings['incus_instances'][0],
            'incus_guest_bootstrap_packages': settings['incus_guest_bootstrap_packages'],
            'hetzner_ssh_public_key_file': str(fixture['key']),
        },
        'environment': {'PATH': fixture['env']['PATH']},
        'tasks': [{
            'name': 'Run actual Incus bootstrap tasks',
            'ansible.builtin.include_role': {
                'name': str(ROOT / 'roles/incus_instance'), 'tasks_from': 'bootstrap.yml',
            },
        }],
    }]))
    env = {**fixture['env'], 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
           'ANSIBLE_LIBRARY': str(library), 'ANSIBLE_HOME': str(tmp_path / 'ansible-home'),
           'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
           'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote')}
    success = cloud_status in ['disabled', 'done', 'baseline-error'] and not guard_failed
    for changed in ([1, 0] if success else [0]):
        result = subprocess.run(['ansible-playbook', '-i', str(inventory), str(playbook)],
                                cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        assert result.returncode == (0 if success else 2), output
        assert f'changed={changed}' in output, output
    calls = [json.loads(line) for line in fixture['events'].read_text().splitlines()] if fixture['events'].exists() else []
    if not success:
        assert not any(call[:3] == ['incus', 'timeout', '900'] for call in calls)
        assert not (fixture['guest'] / 'var/lib/uranus/instance-bootstrap.json').exists()


@pytest.mark.parametrize('marker_name, managed_error', [('db01', True), ('db01', False), ('wrong-guest', True)])
def test_configure_preflight_requires_verified_bootstrap_for_historical_errors(
        tmp_path, bootstrap_fixture, marker_name, managed_error):
    fixture = bootstrap_fixture
    cloud = fixture['bin'] / 'cloud-init'
    errors = (["('package-update-upgrade-install', ProcessExecutionError('old apt failure'))"]
              if managed_error else ["('users-groups', RuntimeError('unrepaired account failure'))"])
    details = {'status': 'error', 'errors': errors, 'stage': None, 'modules-final': {'errors': errors}}
    cloud.write_text(f'''#!{sys.executable}
import json
import sys
assert sys.argv[1:] == ['status', '--wait', '--format', 'json']
print({json.dumps(details)!r})
sys.exit(1)
''')
    cloud.chmod(0o755)
    marker = tmp_path / 'instance-bootstrap.json'
    marker.write_text(json.dumps({'version': 1, 'instance': marker_name}))
    configure = yaml.safe_load((ROOT / 'playbooks/configure.yml').read_text())[0]
    task_names = {'Wait for initial cloud-init to finish',
                  'Read the baseline verified by provisioning through Incus',
                  'Require verified guest initialization before application configuration'}
    tasks = [task for task in configure['pre_tasks'] if task['name'] in task_names]
    assert len(tasks) == 3
    tasks[1]['ansible.builtin.slurp']['src'] = str(marker)
    inventory = tmp_path / 'configure-inventory.yml'
    inventory.write_text(yaml.safe_dump({'all': {'hosts': {'db01': {
        'ansible_connection': 'local', 'ansible_python_interpreter': sys.executable,
    }}}}))
    playbook = tmp_path / 'configure-preflight.yml'
    playbook.write_text(yaml.safe_dump([{
        'name': 'Check real configure preflight', 'hosts': 'db01', 'gather_facts': False,
        'environment': {'PATH': fixture['env']['PATH']}, 'tasks': tasks,
    }]))
    env = {**fixture['env'], 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
           'ANSIBLE_HOME': str(tmp_path / 'ansible-home'),
           'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
           'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote')}
    result = subprocess.run(['ansible-playbook', '-i', str(inventory), str(playbook)],
                            cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    assert result.returncode == (0 if managed_error and marker_name == 'db01' else 2), result.stdout + result.stderr
