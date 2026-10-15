"""Run real creation tasks against a local Incus fixture with no remote or VM."""
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('kind, scenario', [
    ('container', 'cached'),
    ('virtual-machine', 'cached'),
    ('container', 'download'),
    ('virtual-machine', 'download'),
    ('container', 'copy-failed'),
    ('container', 'list-failed'),
    ('container', 'wrong-fingerprint'),
    ('container', 'wrong-type'),
])
def test_creation_uses_verified_project_images_before_initializing(tmp_path, settings, kind, scenario):
    events = tmp_path / 'events.jsonl'
    binaries, library = tmp_path / 'bin', tmp_path / 'library'
    binaries.mkdir()
    library.mkdir()
    name = 'nginx01' if kind == 'container' else 'db01'
    instance = next(i for i in settings['incus_instances'] if i['name'] == name)
    fingerprint = settings['incus_images'][kind]
    cached = scenario in ('cached', 'wrong-fingerprint', 'wrong-type')
    executable = binaries / 'incus'
    executable.write_text(f'''#!{sys.executable}
import json
from pathlib import Path
import sys

args = sys.argv[1:]
with Path({str(events)!r}).open('a') as stream:
    stream.write(json.dumps(args) + '\\n')
if args == ['--force-local', 'query', '--raw', '/1.0/images/' + {fingerprint!r} + '?project=uranus']:
    print(json.dumps({{'type': 'sync', 'status_code': 200, 'metadata': {{
        'fingerprint': {'f' * 64 if scenario == 'wrong-fingerprint' else fingerprint!r},
        'type': {'virtual-machine' if scenario == 'wrong-type' else kind!r},
    }}}}))
    sys.exit(0)
assert args[:3] == ['--force-local', '--project', 'uranus']
action = args[3:]
if action == ['image', 'list', '--format=json']:
    if {scenario == 'list-failed'!r}:
        print('fixture image store unavailable', file=sys.stderr)
        sys.exit(1)
    print(json.dumps([{{'fingerprint': {fingerprint!r}, 'type': {kind!r}}}] if {cached!r} else []))
elif action == ['image', 'copy', 'images:' + {fingerprint!r}, 'local:', '--target-project', 'uranus'] + (['--vm'] if {kind!r} == 'virtual-machine' else []):
    assert not {cached!r}, 'A cached image must not require a remote server'
    if {scenario == 'copy-failed'!r}:
        print("The requested image couldn't be found", file=sys.stderr)
        sys.exit(1)
elif action == ['init', {fingerprint!r}, {name!r}, '--no-profiles'] + (['--vm'] if {kind!r} == 'virtual-machine' else []):
    body = sys.stdin.read()
    assert 'profiles: []' in body and 'user.user-data:' in body
elif action == ['start', {name!r}]:
    pass
else:
    raise RuntimeError('Unexpected Incus operation: ' + repr(args))
''')
    executable.chmod(0o755)
    for module_name, arguments, result in [
        ('uranus_incus_guard', {
            'instances': {'type': 'list', 'elements': 'dict'}, 'images': {'type': 'dict'},
            'reserve_gib': {'type': 'int'}, 'quotas': {'type': 'bool'},
        }, {'new_instances': [name]}),
        ('uranus_storage_guard', {}, {}),
    ]:
        (library / f'{module_name}.py').write_text(f'''
import json
from pathlib import Path
from ansible.module_utils.basic import AnsibleModule
module = AnsibleModule(argument_spec={arguments!r})
with Path({str(events)!r}).open('a') as stream:
    stream.write(json.dumps([{module_name!r}]) + '\\n')
module.exit_json(changed=False, **{result!r})
''')
    public_key = tmp_path / 'identity.pub'
    public_key.write_text('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureFixtureFixtureFixtureFixtureFixture tests\n')
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text(yaml.safe_dump({'all': {'hosts': {'localhost': {
        'ansible_connection': 'local', 'ansible_python_interpreter': sys.executable,
    }}}}))
    playbook = tmp_path / 'create.yml'
    playbook.write_text(yaml.safe_dump([{
        'name': 'Exercise image acquisition and initialization locally',
        'hosts': 'localhost', 'gather_facts': False,
        'vars': {**settings, 'incus_instance': instance, 'hetzner_ssh_public_key_file': str(public_key)},
        'environment': {'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
                        'INCUS_DIR': str(tmp_path)},
        'tasks': [{'name': 'Exercise real instance creation tasks',
                   'ansible.builtin.include_role': {'name': 'incus_instance', 'tasks_from': 'create'}}],
    }]))
    result = subprocess.run(['ansible-playbook', '-i', str(inventory), str(playbook)],
                            cwd=ROOT, capture_output=True, text=True, timeout=60,
                            env={**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
                                 'ANSIBLE_LIBRARY': str(library),
                                 'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
                                 'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote')})
    output = result.stdout + result.stderr
    success = scenario in ('cached', 'download')
    assert result.returncode == (0 if success else 2), output
    calls = [json.loads(line) for line in events.read_text().splitlines()]
    operations = [call[3] if call[0] == '--force-local' else call[0] for call in calls]
    # Every init uses the bare fingerprint; cached images never contact images:.
    initializations = [call for call in calls if call[:4] == ['--force-local', '--project', 'uranus', 'init']]
    assert bool(initializations) is success
    if success:
        assert initializations[0][4] == fingerprint
        init_index = operations.index('init')
        assert operations[init_index - 1] == 'uranus_storage_guard'
        assert operations[-1] == 'start'
    copies = [call for call in calls if call[3:5] == ['image', 'copy']]
    assert bool(copies) is (scenario in ('download', 'copy-failed'))
    if copies:
        assert calls[calls.index(copies[0]) - 1] == ['uranus_storage_guard']
    if scenario == 'copy-failed':
        assert 'No instance was initialized' in output
        assert "requested image couldn't be found" in output
    if not success:
        assert 'start' not in operations
