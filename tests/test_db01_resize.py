"""Reject layout changes that could endanger the existing database VM."""
import copy
import importlib.util
import json
import stat
import subprocess
import sys
from types import SimpleNamespace

import pytest

from conftest import ROOT

spec = importlib.util.spec_from_file_location('resize_db01', ROOT / 'scripts/resize_db01.py')
resize_db01 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resize_db01)


@pytest.fixture
def layout():
    return {
        'label': 'gpt', 'id': 'original-gpt-id', 'device': '/dev/sda', 'unit': 'sectors', 'sectorsize': 512,
        'partitions': [
            {'node': '/dev/sda1', 'start': 2048, 'size': 204800, 'uuid': 'efi-id'},
            {'node': '/dev/sda2', 'start': 206848, 'size': 314365919, 'uuid': 'root-partition-id'},
        ],
    }


def test_known_layout_accepts_only_the_verified_root_filesystem(layout):
    fs = {'source': '/dev/sda2', 'fstype': 'ext4', 'target': '/', 'options': 'rw,relatime',
          'uuid': resize_db01.EXPECTED_UUID}
    resize_db01.validate_layout(layout, fs)
    for key, value in [('uuid', 'some-other-volume'), ('fstype', 'xfs'), ('source', '/dev/sdb2'), ('options', 'ro')]:
        with pytest.raises(RuntimeError):
            resize_db01.validate_layout(layout, {**fs, key: value})


def test_growth_preserves_efi_partition_start_and_identities(layout):
    grown = copy.deepcopy(layout)
    grown['partitions'][1]['size'] += 450 * 1024**3 // 512
    resize_db01.verify_partition_preservation(layout, grown)


@pytest.mark.parametrize('change', ['efi', 'start', 'uuid', 'shrink', 'gpt', 'extra_partition'])
def test_unexpected_partition_changes_are_rejected(layout, change):
    after = copy.deepcopy(layout)
    if change == 'efi':
        after['partitions'][0]['size'] += 1
    elif change == 'start':
        after['partitions'][1]['start'] += 1
    elif change == 'uuid':
        after['partitions'][1]['uuid'] = 'replaced'
    elif change == 'shrink':
        after['partitions'][1]['size'] -= 1
    elif change == 'gpt':
        after['id'] = 'replaced'
    else:
        after['partitions'].append({'node': '/dev/sda3', 'start': 900000000, 'size': 1})
    with pytest.raises(RuntimeError):
        resize_db01.verify_partition_preservation(layout, after)


@pytest.fixture
def vm(monkeypatch):
    state = {'size': 150 * resize_db01.GIB, 'pending': True, 'status': 'Running', 'grow_on_start': True}
    calls = []

    def instance():
        return {'name': 'db01', 'type': 'virtual-machine', 'status': state['status'], 'profiles': [],
                'expanded_devices': {'root': {'pool': 'uranus', 'path': '/', 'size': '600GiB'}},
                'expanded_config': {'user.uranus.owner': 'uranus/incus/v1',
                                    'volatile.root.apply_quota': str(state['pending']).lower()}}

    def incus(args, **options):
        calls.append(('incus', args))
        if args[0] == 'list':
            return subprocess.CompletedProcess(args, 0, json.dumps([instance()]), '')
        if args[0] == 'stop':
            state['status'] = 'Stopped'
        if args[0] == 'start':
            state['status'] = 'Running'
            if state['grow_on_start']:
                state['size'] = 600 * resize_db01.GIB
                state['pending'] = False
        return subprocess.CompletedProcess(args, 0, '', '')

    def guest(args, **options):
        calls.append(('guest', args))
        stdout = str(state['size']) if args[0] == 'blockdev' else ''
        return subprocess.CompletedProcess(args, 0, stdout, '')

    monkeypatch.setattr(resize_db01, 'incus', incus)
    monkeypatch.setattr(resize_db01, 'guest', guest)
    monkeypatch.setattr(resize_db01.time, 'sleep', lambda seconds: None)
    return SimpleNamespace(state=state, calls=calls)


def test_deferred_resize_restarts_the_vm_and_waits_for_postgresql(vm):
    resize_db01.ensure_guest_disk_size()
    operations = [args[0] for kind, args in vm.calls if kind == 'incus' and args[0] != 'list']
    assert operations == ['stop', 'start']
    assert vm.state['size'] == 600 * resize_db01.GIB
    assert not vm.state['pending']
    assert ('guest', ['systemctl', 'is-active', '--quiet', 'postgresql@17-main']) in vm.calls
    assert not any('force' in arg for _, args in vm.calls for arg in args)


def test_already_visible_size_does_not_restart(vm):
    vm.state.update(size=600 * resize_db01.GIB, pending=False)
    resize_db01.ensure_guest_disk_size()
    assert not any(kind == 'incus' and args[0] in ('stop', 'start') for kind, args in vm.calls)


def test_final_online_poll_does_not_cause_an_unnecessary_restart(vm, monkeypatch):
    vm.state['pending'] = False
    sizes = iter([150 * resize_db01.GIB] * 10 + [600 * resize_db01.GIB])
    monkeypatch.setattr(resize_db01, 'disk_size_bytes', lambda: next(sizes))
    resize_db01.ensure_guest_disk_size()
    assert not any(kind == 'incus' and args[0] in ('stop', 'start') for kind, args in vm.calls)


def test_missing_online_size_uses_clean_restart_as_fallback(vm):
    vm.state['pending'] = False
    resize_db01.ensure_guest_disk_size()
    assert vm.state['size'] == 600 * resize_db01.GIB
    assert ('incus', ['stop', 'db01', '--timeout=120']) in vm.calls


def test_failed_stop_never_forces_or_starts_vm(vm, monkeypatch):
    original = resize_db01.incus

    def failed_stop(args, **options):
        if args[0] == 'stop':
            raise RuntimeError('db01 did not stop within timeout')
        return original(args, **options)

    monkeypatch.setattr(resize_db01, 'incus', failed_stop)
    with pytest.raises(RuntimeError, match='timeout'):
        resize_db01.ensure_guest_disk_size()
    assert not any(kind == 'incus' and args[0] == 'start' for kind, args in vm.calls)
    assert vm.state['status'] == 'Running'


def test_incorrect_size_after_restart_does_not_reach_partition_tools(vm):
    vm.state['grow_on_start'] = False
    with pytest.raises(RuntimeError, match='no partition was changed'):
        resize_db01.ensure_guest_disk_size()
    assert not any(kind == 'guest' and args[0] in ('growpart', 'resize2fs') for kind, args in vm.calls)


def test_oversized_guest_disk_is_never_restarted_or_shrunk(vm):
    vm.state['size'] = 700 * resize_db01.GIB
    with pytest.raises(RuntimeError, match='refusing to shrink'):
        resize_db01.ensure_guest_disk_size()
    assert not any(kind == 'incus' and args[0] in ('stop', 'start') for kind, args in vm.calls)


def test_deferred_resize_capacity_uses_actual_size_instead_of_config(vm, layout, tmp_path, monkeypatch):
    original_guest = resize_db01.guest

    def guest(args, **options):
        if args[0] == 'sfdisk':
            return subprocess.CompletedProcess(args, 0, json.dumps({'partitiontable': layout}), '')
        if args[0] == 'findmnt':
            fs = {'source': '/dev/sda2', 'fstype': 'ext4', 'uuid': resize_db01.EXPECTED_UUID,
                  'target': '/', 'options': 'rw,relatime'}
            return subprocess.CompletedProcess(args, 0, json.dumps({'filesystems': [fs]}), '')
        if args[:2] == ['python3', '-c']:
            return subprocess.CompletedProcess(args, 0, str(145 * resize_db01.GIB), '')
        if args[0] == 'runuser':
            return subprocess.CompletedProcess(args, 0, 'postgres|5\nnominatim|42\n', '')
        return original_guest(args, **options)

    monkeypatch.setenv('INCUS_DIR', '/data/incus')
    monkeypatch.setattr(resize_db01.os, 'geteuid', lambda: 0)
    monkeypatch.setattr(resize_db01.os, 'umask', lambda value: 0o022)
    monkeypatch.setattr(resize_db01, 'open', lambda *args: (tmp_path / 'lock').open('a'), raising=False)
    monkeypatch.setattr(resize_db01, 'run', lambda *args, **kwargs: subprocess.CompletedProcess([], 0, '', ''))
    monkeypatch.setattr(resize_db01, 'guest', guest)
    monkeypatch.setattr(resize_db01.shutil, 'disk_usage', lambda path: SimpleNamespace(free=200 * resize_db01.GIB))
    with pytest.raises(RuntimeError, match='Insufficient host space'):
        resize_db01.resize()
    assert not any(kind == 'incus' and args[0] in ('stop', 'start', 'config') for kind, args in vm.calls)


def test_controller_error_is_concise_and_does_not_dump_remote_script(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(sys, 'argv', ['resize_db01.py'])
    monkeypatch.setattr(resize_db01, 'prepare_controller_ssh_config', lambda: tmp_path / 'ssh.conf')
    monkeypatch.setattr(resize_db01.subprocess, 'run',
                        lambda *args, **kwargs: subprocess.CompletedProcess([], 1))
    with pytest.raises(SystemExit) as error:
        resize_db01.main()
    assert error.value.code == 1
    message = capsys.readouterr().err
    assert 'Europe import was not started' in message
    assert 'Traceback' not in message and 'import argparse' not in message


def test_generated_jump_config_reuses_trusted_connection_and_keeps_user_host_keys(tmp_path, monkeypatch):
    project = tmp_path / 'project with spaces'
    home = tmp_path / 'personal config'
    personal = home / '.ssh/config'
    personal.parent.mkdir(parents=True)
    known_hosts = home / '.ssh/known_hosts'
    personal.write_text(f'Host *\n    UserKnownHostsFile "{known_hosts}"\n')
    personal.chmod(0o600)
    monkeypatch.setattr(resize_db01, '__file__', str(project / 'scripts/resize_db01.py'))
    monkeypatch.setattr(resize_db01.Path, 'home', lambda: home)
    config = resize_db01.prepare_controller_ssh_config()
    result = subprocess.run(['ssh', '-G', '-F', str(config), 'awendelk@94.130.236.38'],
                            check=True, capture_output=True, text=True)
    options = dict(line.split(' ', 1) for line in result.stdout.splitlines())
    assert options['controlpath'] == str(project / '.uranus-private/ssh/db01-resize.sock')
    assert options['controlmaster'] == 'auto'
    assert options['controlpersist'] == '900'
    assert options['connecttimeout'] == '60'
    assert options['stricthostkeychecking'] in ('true', 'yes')
    assert str(known_hosts) in options['userknownhostsfile']
    assert stat.S_IMODE(config.stat().st_mode) == 0o600
    assert stat.S_IMODE(config.parent.stat().st_mode) == 0o700
    overlay = config.parent / 'nominatim-inventory.json'
    assert json.loads(overlay.read_text()) == {'all': {'hosts': {'hetzner': {
        'ansible_control_path': str(config.parent / 'db01-resize.sock'),
    }}}}
    assert stat.S_IMODE(overlay.stat().st_mode) == 0o600


def test_resize_uses_the_same_ssh_config_as_the_import(tmp_path, monkeypatch):
    config = tmp_path / 'shared.conf'
    monkeypatch.setattr(sys, 'argv', ['resize_db01.py', '--ssh-config', str(config)])
    calls = []

    def connect(args, **kwargs):
        calls.append(args)
        return subprocess.CompletedProcess(args, 0)

    monkeypatch.setattr(resize_db01.subprocess, 'run', connect)
    resize_db01.main()
    assert calls[0][calls[0].index('-F') + 1] == str(config)
