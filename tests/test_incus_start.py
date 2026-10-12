"""Run the real start tasks against local Incus and storage-guard fixtures."""
import json
import os
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('start_rc, log_rc, guard_failed', [
    (0, 0, False),
    (1, 0, False),
    (1, 1, False),
    (0, 0, True),
], ids=['success', 'startup-log', 'unavailable-log', 'storage-rejected'])
def test_start_preserves_failures_and_only_reads_diagnostics(
        tmp_path, start_rc, log_rc, guard_failed):
    events = tmp_path / 'events.jsonl'
    binaries = tmp_path / 'bin'
    library = tmp_path / 'library'
    binaries.mkdir()
    library.mkdir()
    executable = binaries / 'incus'
    executable.write_text(f'''#!{sys.executable}
import json
from pathlib import Path
import sys

with Path({str(events)!r}).open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\\n')
assert sys.argv[1:4] == ['--force-local', '--project', 'uranus']
if sys.argv[4:] == ['start', 'dev01']:
    if {start_rc}:
        print('forkstart failed with exit status 1', file=sys.stderr)
    sys.exit({start_rc})
if sys.argv[4:] == ['info', '--show-log', 'dev01']:
    if {log_rc}:
        print('fixture log retrieval failed', file=sys.stderr)
    else:
        print('LXC startup cause fixture')
    sys.exit({log_rc})
raise RuntimeError('Unexpected Incus mutation or command')
''')
    executable.chmod(0o755)
    (library / 'uranus_storage_guard.py').write_text(f'''
import json
from pathlib import Path
from ansible.module_utils.basic import AnsibleModule

module = AnsibleModule(argument_spec={{}})
with Path({str(events)!r}).open('a') as stream:
    stream.write(json.dumps(['storage-guard']) + '\\n')
if {guard_failed!r}:
    module.fail_json(msg='fixture storage UUID mismatch')
module.exit_json(changed=False)
''')
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text(yaml.safe_dump({'all': {'hosts': {'localhost': {
        'ansible_connection': 'local',
        'ansible_python_interpreter': sys.executable,
    }}}}))
    playbook = tmp_path / 'start.yml'
    playbook.write_text(yaml.safe_dump([{
        'name': 'Exercise local startup fixtures',
        'hosts': 'localhost',
        'gather_facts': False,
        'vars': {'incus_instance_name': 'dev01'},
        'environment': {
            'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
            'INCUS_DIR': str(tmp_path),
        },
        'tasks': [{
            'name': 'Exercise the shared Incus start tasks',
            'ansible.builtin.include_tasks': str(ROOT / 'roles/incus_instance/tasks/start.yml'),
        }],
    }]))
    env = {
        **os.environ,
        'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
        'ANSIBLE_LIBRARY': str(library),
        'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
        'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote'),
    }
    result = subprocess.run(
        ['ansible-playbook', '-i', str(inventory), str(playbook)],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    assert result.returncode == (2 if start_rc or guard_failed else 0), output
    calls = [json.loads(line) for line in events.read_text().splitlines()]
    expected = [['storage-guard']]
    if guard_failed:
        assert 'fixture storage UUID mismatch' in output
    else:
        expected.append(['--force-local', '--project', 'uranus', 'start', 'dev01'])
        if start_rc:
            expected.append(['--force-local', '--project', 'uranus', 'info', '--show-log', 'dev01'])
            assert 'Start error: forkstart failed with exit status 1' in output
            assert 'initialized instance and its disk have been retained' in output
            assert ('fixture log retrieval failed' if log_rc else 'LXC startup cause fixture') in output
    assert calls == expected
