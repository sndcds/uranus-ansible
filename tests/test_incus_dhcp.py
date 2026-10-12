"""Exercise DHCP recovery with real shell/files and a local networkd fixture."""
import json
import os
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT


@pytest.fixture
def dhcp_fixture(tmp_path):
    network_dir = tmp_path / 'network'
    network_dir.mkdir()
    base = network_dir / '10-cloud-init-eth0.network'
    original = '[Match]\nName=eth0\n\n[Network]\nDHCP=ipv4\n'
    base.write_text(original)
    managed = network_dir / '05-uranus-incus.network'
    state = tmp_path / 'state.json'
    events = tmp_path / 'events.jsonl'
    binaries = tmp_path / 'bin'
    binaries.mkdir()
    executable = binaries / 'network-fixture'
    executable.write_text(f'''#!{sys.executable}
import json
from pathlib import Path
import sys

state_file = Path({str(state)!r})
state = json.loads(state_file.read_text())
command = Path(sys.argv[0]).name
args = sys.argv[1:]
if command == 'systemctl':
    assert args == ['is-active', '--quiet', 'systemd-networkd']
    sys.exit(0)
if command == 'ip':
    interface = state.get('interface', 'eth0')
    if args == ['-o', 'link', 'show']:
        print('1: lo: <LOOPBACK,UP> link/loopback 00:00:00:00:00:00')
        for name in state.get('interfaces', [interface]):
            print('8: ' + name + ': <BROADCAST,MULTICAST> link/ether 10:66:6a:d2:85:42')
    else:
        assert args == ['-4', '-o', 'address', 'show', 'dev', interface]
        if state['address']:
            print('8: ' + interface + ' inet ' + state['address'] + '/24 scope global dynamic ' + interface)
elif command == 'networkctl':
    with Path({str(events)!r}).open('a') as stream:
        stream.write(json.dumps(args) + '\\n')
    import configparser
    config = configparser.ConfigParser()
    config.read({str(managed)!r})
    assert config['Match']['MACAddress'] == '10:66:6a:d2:85:42'
    assert config['Network']['DHCP'] == 'ipv4'
    assert config['DHCPv4']['ClientIdentifier'] == 'mac'
    interface = state.get('interface', 'eth0')
    if args == ['reconfigure', interface]:
        if state['acquire']:
            state['address'] = state['reserved']
            state_file.write_text(json.dumps(state))
    else:
        assert args in [['reload'], ['up', interface]]
elif command == 'sleep':
    pass
else:
    raise RuntimeError('Unexpected network command')
''')
    executable.chmod(0o755)
    for command in ['systemctl', 'networkctl', 'ip', 'sleep']:
        (binaries / command).symlink_to(executable)
    return {
        'base': base, 'original': original, 'managed': managed,
        'state': state, 'events': events, 'network_dir': network_dir,
        'env': {**os.environ, 'PATH': str(binaries) + os.pathsep + os.environ['PATH']},
    }


def run_recovery(render, fixture, instance):
    script = render('roles/incus_instance/templates/dhcp-mac.sh.j2', incus_instance=instance)
    script = script.replace('/etc/systemd/network', str(fixture['network_dir']))
    return subprocess.run(['sh', '-ec', script], env=fixture['env'],
                          capture_output=True, text=True, timeout=30)


@pytest.mark.parametrize('index', range(6))
def test_wrong_duid_lease_is_recovered_and_repeat_preserves_network(render, settings, dhcp_fixture, index):
    instance = settings['incus_instances'][index]
    fixture = dhcp_fixture
    fixture['state'].write_text(json.dumps({
        'address': '10.77.0.91', 'reserved': instance['ip'], 'acquire': True,
    }))
    first = run_recovery(render, fixture, instance)
    assert first.returncode == 0, first.stdout + first.stderr
    assert first.stdout == 'changed\n'
    assert json.loads(fixture['state'].read_text())['address'] == instance['ip']
    assert fixture['managed'].stat().st_mode & 0o777 == 0o644
    assert fixture['base'].read_text() == fixture['original']
    events = [json.loads(line) for line in fixture['events'].read_text().splitlines()]
    assert events == [['reload'], ['reconfigure', 'eth0'], ['up', 'eth0']]
    before = fixture['managed'].stat().st_mtime_ns
    repeat = run_recovery(render, fixture, instance)
    assert repeat.returncode == 0, repeat.stdout + repeat.stderr
    assert repeat.stdout == 'unchanged\n'
    assert fixture['managed'].stat().st_mtime_ns == before
    assert fixture['events'].read_text().splitlines() == [json.dumps(event) for event in events]


def test_existing_managed_config_with_old_lease_is_renewed(render, settings, dhcp_fixture):
    fixture = dhcp_fixture
    instance = settings['incus_instances'][1]
    fixture['state'].write_text(json.dumps({
        'address': '10.77.0.91', 'reserved': instance['ip'], 'acquire': True,
    }))
    first = run_recovery(render, fixture, instance)
    assert first.returncode == 0, first.stdout + first.stderr
    before = fixture['managed'].stat().st_mtime_ns
    state = json.loads(fixture['state'].read_text())
    state['address'] = '10.77.0.91'
    fixture['state'].write_text(json.dumps(state))
    result = run_recovery(render, fixture, instance)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout == 'changed\n'
    assert json.loads(fixture['state'].read_text())['address'] == instance['ip']
    assert fixture['managed'].stat().st_mtime_ns == before


def test_vm_without_cloud_network_config_is_configured_by_mac(render, settings, dhcp_fixture):
    fixture = dhcp_fixture
    instance = settings['incus_instances'][0]
    fixture['base'].unlink()
    fixture['state'].write_text(json.dumps({
        'interface': 'enp5s0', 'address': None, 'reserved': instance['ip'], 'acquire': True,
    }))
    result = run_recovery(render, fixture, instance)
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout == 'changed\n'
    assert json.loads(fixture['state'].read_text())['address'] == '10.77.0.11'
    events = [json.loads(line) for line in fixture['events'].read_text().splitlines()]
    assert events == [['reload'], ['reconfigure', 'enp5s0'], ['up', 'enp5s0']]
    assert not fixture['base'].exists()


@pytest.mark.parametrize('interfaces', [[], ['eth0', 'enp5s0']])
def test_ambiguous_ethernet_layout_is_rejected_without_mutation(render, settings, dhcp_fixture, interfaces):
    fixture = dhcp_fixture
    fixture['state'].write_text(json.dumps({
        'interfaces': interfaces, 'address': None, 'reserved': '10.77.0.11', 'acquire': True,
    }))
    result = run_recovery(render, fixture, settings['incus_instances'][0])
    assert result.returncode == 1, result.stdout + result.stderr
    assert 'Expected exactly one Ethernet interface' in result.stderr
    assert not fixture['managed'].exists()
    assert not fixture['events'].exists()
    assert fixture['base'].read_text() == fixture['original']


def test_missing_reserved_lease_fails_instead_of_claiming_network_ready(render, settings, dhcp_fixture):
    fixture = dhcp_fixture
    instance = settings['incus_instances'][1]
    fixture['state'].write_text(json.dumps({
        'address': '10.77.0.91', 'reserved': instance['ip'], 'acquire': False,
    }))
    result = run_recovery(render, fixture, instance)
    assert result.returncode == 1, result.stdout + result.stderr
    assert f"Expected eth0 address {instance['ip']}/24" in result.stderr
    assert fixture['base'].read_text() == fixture['original']
    assert 'changed' not in result.stdout


def test_real_ansible_network_task_reports_change_and_then_no_change(tmp_path, settings, dhcp_fixture):
    fixture = dhcp_fixture
    instance = settings['incus_instances'][1]
    fixture['state'].write_text(json.dumps({
        'address': '10.77.0.91', 'reserved': instance['ip'], 'acquire': True,
    }))
    binaries = tmp_path / 'incus-bin'
    library = tmp_path / 'library'
    binaries.mkdir()
    library.mkdir()
    incus = binaries / 'incus'
    incus.write_text(f'''#!{sys.executable}
import subprocess
import sys
assert sys.argv[1:] == ['--force-local', '--project', 'uranus', 'exec', 'dev01', '--', 'timeout', '150', 'sh', '-s']
script = sys.stdin.read().replace('/etc/systemd/network', {str(fixture['network_dir'])!r})
sys.exit(subprocess.run(['sh', '-s'], input=script, text=True).returncode)
''')
    incus.chmod(0o755)
    (library / 'uranus_storage_guard.py').write_text('''
from ansible.module_utils.basic import AnsibleModule
AnsibleModule(argument_spec={}).exit_json(changed=False)
''')
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text(yaml.safe_dump({'all': {'hosts': {'localhost': {
        'ansible_connection': 'local', 'ansible_python_interpreter': sys.executable,
    }}}}))
    public_key = tmp_path / 'identity.pub'
    public_key.write_text('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureFixtureFixtureFixtureFixtureFixture tests\n')
    playbook = tmp_path / 'network.yml'
    playbook.write_text(yaml.safe_dump([{
        'name': 'Exercise DHCP recovery through Incus', 'hosts': 'localhost', 'gather_facts': False,
        'vars': {
            'incus_instance': instance, 'incus_container_quotas': False,
            'incus_guest_bootstrap_packages': settings['incus_guest_bootstrap_packages'],
            'hetzner_ssh_public_key_file': str(public_key),
            'rendered_instance': "{{ lookup('template', '" + str(ROOT / 'roles/incus_instance/templates/instance.yml.j2') + "') | from_yaml }}",
        },
        'environment': {'PATH': str(binaries) + os.pathsep + fixture['env']['PATH']},
        'tasks': [{
            'name': 'Check the actual Ansible cloud-init rendering',
            'ansible.builtin.assert': {'that': [
                "(rendered_instance.config['user.user-data'] | from_yaml).package_update",
                "'ClientIdentifier=mac' in (rendered_instance.config['user.user-data'] | from_yaml).bootcmd[0][2]",
                "(rendered_instance.config['user.network-config'] | from_yaml).renderer == 'networkd'",
            ]},
        }, {
            'name': 'Run the real network tasks',
            'ansible.builtin.include_role': {
                'name': str(ROOT / 'roles/incus_instance'), 'tasks_from': 'network.yml',
            },
        }],
    }]))
    env = {
        **fixture['env'], 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
        'ANSIBLE_LIBRARY': str(library), 'ANSIBLE_HOME': str(tmp_path / 'ansible-home'),
        'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
        'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote'),
    }
    for changed in [1, 0]:
        result = subprocess.run(['ansible-playbook', '-i', str(inventory), str(playbook)],
                                cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert f'changed={changed}' in output, output
