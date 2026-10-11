import copy
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace
import xml.etree.ElementTree as ET

import pytest
import uranus_debian13 as safety


class FakeHost:
    """Stateful libvirt boundary; no SSH, packages, firewall or real guests."""

    def __init__(self, root, vms, network):
        self.root, self.vms, self.network = root, vms, network
        self.domains = {}
        self.networks = {}
        self.pools = {}
        self.active = set()
        self.autostart = set()
        self.calls = []
        self.fail_on = None

    def domain_xml(self, vm, owner=safety.OWNER, **changes):
        vm = {**vm, **changes}
        return f'''<domain><name>{vm['name']}</name><description>{owner}</description>
        <memory unit="MiB">{vm['memory']}</memory><vcpu>{vm['cpu']}</vcpu><devices>
        <disk device="disk"><source file="{safety.STORAGE / (vm['name'] + '.qcow2')}"/></disk>
        <interface type="network"><source network="uranus-debian13"/><mac address="{vm['mac']}"/></interface>
        </devices></domain>'''

    def run(self, argv):
        self.calls.append(argv)
        if self.fail_on and self.fail_on in argv:
            raise safety.SafetyError('Injected command failure')
        if argv[0] == 'ip':
            return '[]'
        if argv[0] == 'virsh':
            operation, *args = argv[3:]
            if operation in ('list', 'net-list', 'pool-list'):
                return '\n'.join({'list': self.domains, 'net-list': self.networks, 'pool-list': self.pools}[operation])
            if operation == 'dumpxml':
                return self.domains[args[0]]
            if operation == 'net-dumpxml':
                return self.networks[args[0]]
            if operation == 'pool-dumpxml':
                return f'<pool type="dir"><target><path>{self.pools[args[0]]}</path></target></pool>'
            if operation == 'net-define':
                self.networks['uranus-debian13'] = Path(args[0]).read_text()
            elif operation == 'pool-define-as':
                self.pools[args[0]] = args[-1]
            elif operation in ('net-info', 'pool-info'):
                active = 'yes' if operation[:3] in self.active else 'no'
                autostart = 'yes' if operation[:3] in self.autostart else 'no'
                return f'Active: {active}\nAutostart: {autostart}'
            elif operation in ('net-start', 'pool-start'):
                self.active.add(operation[:3])
            elif operation in ('net-autostart', 'pool-autostart'):
                self.autostart.add(operation[:3])
            elif operation == 'domstate':
                return 'shut off'
            elif operation == 'start':
                return 'started'
            else:
                if operation not in ('net-define', 'pool-define-as'):
                    raise AssertionError(f'Unexpected virsh operation: {operation}')
            return ''
        if argv[:2] == ['qemu-img', 'info']:
            name = Path(argv[-1]).stem
            size = next((v['disk'] * 1024**3 for v in self.vms if v['name'] == name), 1024**3)
            return json.dumps({'format': 'qcow2', 'virtual-size': size})
        if argv[:2] == ['qemu-img', 'convert']:
            Path(argv[-1]).write_bytes(b'Independent VM disk')
            return ''
        if argv[:2] == ['qemu-img', 'resize']:
            return ''
        if argv[0] == 'cloud-localds':
            Path(argv[3]).write_bytes(b'NoCloud ISO fixture')
            return ''
        if argv[0] == 'virt-install':
            name = argv[argv.index('--name') + 1]
            vm = next(v for v in self.vms if v['name'] == name)
            self.domains[name] = self.domain_xml(vm)
            return ''
        raise AssertionError(f'Unexpected command: {argv}')

    def mutations(self):
        reads = {'list', 'net-list', 'pool-list', 'dumpxml', 'net-dumpxml', 'pool-dumpxml', 'net-info', 'pool-info', 'domstate'}
        return [argv for argv in self.calls if not ((argv[0] == 'virsh' and argv[3] in reads) or
                argv[:2] == ['qemu-img', 'info'] or argv[0] == 'ip')]


@pytest.fixture
def host(tmp_path, settings, render, monkeypatch):
    storage = tmp_path / 'data/libvirt/images'
    storage.mkdir(parents=True)
    seeds = tmp_path / 'data/libvirt/cloud-init'
    monkeypatch.setattr(safety, 'STORAGE', storage)
    monkeypatch.setattr(safety, 'SEEDS', seeds)
    monkeypatch.setattr(safety.shutil, 'disk_usage', lambda path: SimpleNamespace(free=10**15))
    vms = copy.deepcopy(settings['hetzner_vms'])
    network = render('roles/debian13_hypervisor/templates/network.xml.j2')
    fake = FakeHost(tmp_path, vms, network)
    return fake


def apply(host, **changes):
    base = safety.STORAGE / '.base/image.qcow2'
    base.parent.mkdir(exist_ok=True)
    if not base.exists():
        base.write_bytes(b'Pinned cloud image')
    checksum = hashlib.sha512(base.read_bytes()).hexdigest()
    seeds = {v['name']: {'user_data': '#cloud-config\n', 'meta_data': 'instance-id: fixture\n', 'network_config': 'version: 2\n'} for v in host.vms}
    args = dict(vms=host.vms, network_xml=host.network, image=str(base), checksum=checksum, seeds=seeds)
    args.update(changes)
    return safety.Provisioner(host.run, lambda run: None).apply(**args)


def test_first_run_creates_six_independent_disks_and_second_run_preserves_them(host):
    first = apply(host)
    assert first['changed'] and set(first['new_vms']) == safety.VM_NAMES
    old_disks = {p.name: (p.stat().st_ino, p.read_bytes()) for p in safety.STORAGE.glob('*.qcow2')}
    old_seeds = {p: p.read_bytes() for p in safety.SEEDS.rglob('*') if p.is_file()}
    host.calls.clear()
    second = apply(host)
    assert not second['changed'] and not second['new_vms']
    assert not host.mutations()
    assert old_disks == {p.name: (p.stat().st_ino, p.read_bytes()) for p in safety.STORAGE.glob('*.qcow2')}
    assert old_seeds == {p: p.read_bytes() for p in safety.SEEDS.rglob('*') if p.is_file()}


def test_existing_stopped_guests_are_not_started_implicitly(host):
    apply(host)
    host.calls.clear()
    assert not apply(host)['changed']
    assert not host.mutations()


def test_explicitly_starting_existing_guests_does_not_change_disks(host):
    apply(host)
    host.calls.clear()
    result = apply(host, start_existing=True)
    assert result['changed']
    assert all(call[0] == 'virsh' and call[3] == 'start' for call in host.mutations())


def test_check_mode_creates_no_domains_disks_or_seeds(host):
    assert apply(host, check_mode=True)['changed']
    assert not host.mutations()
    assert not list(safety.STORAGE.glob('*.qcow2'))
    assert not safety.SEEDS.exists()


@pytest.mark.parametrize('kind', ['disk', 'seed'])
def test_orphaned_data_aborts_all_creation_and_is_preserved(host, kind):
    path = safety.STORAGE / 'vers01.qcow2' if kind == 'disk' else safety.SEEDS / 'vers01'
    path.parent.mkdir(parents=True, exist_ok=True)
    if kind == 'disk':
        path.write_bytes(b'Unmanaged data')
    else:
        path.mkdir()
    with pytest.raises(safety.SafetyError, match='Orphaned'):
        apply(host)
    assert not host.mutations()
    assert path.exists()


@pytest.mark.parametrize('change', ['owner', 'memory', 'cpu', 'mac'])
def test_existing_unmanaged_or_drifted_domain_is_never_adopted(host, change):
    vm = host.vms[0]
    path = safety.STORAGE / f"{vm['name']}.qcow2"
    path.write_bytes(b'Existing data')
    kwargs = {'owner': 'other deployment'} if change == 'owner' else {change: {'memory': 2048, 'cpu': 1, 'mac': '52:54:00:01:00:00'}[change]}
    host.domains[vm['name']] = host.domain_xml(vm, **kwargs)
    with pytest.raises(safety.SafetyError):
        apply(host)
    assert path.read_bytes() == b'Existing data'
    assert not host.mutations()


def test_existing_network_drift_is_not_redefined(host):
    host.networks['uranus-debian13'] = host.network.replace('10.77.0.1', '10.78.0.1')
    with pytest.raises(safety.SafetyError, match='configuration differs'):
        apply(host)
    assert not host.mutations()


def test_pool_with_wrong_target_is_not_replaced(host):
    host.pools['uranus-debian13'] = '/wrong/storage'
    with pytest.raises(safety.SafetyError, match='unexpected target'):
        apply(host)
    assert not host.mutations()


def test_bad_checksum_aborts_before_any_libvirt_changes(host):
    with pytest.raises(safety.SafetyError, match='checksum mismatch'):
        apply(host, checksum='0' * 128)
    assert not host.mutations()


def test_failed_libvirt_read_is_not_treated_as_absent(host):
    host.fail_on = 'list'
    with pytest.raises(safety.SafetyError, match='Injected'):
        apply(host)
    assert not host.mutations()


def test_failed_create_leaves_disk_for_manual_recovery(host):
    host.fail_on = 'virt-install'
    with pytest.raises(safety.SafetyError):
        apply(host)
    assert (safety.STORAGE / 'db01.qcow2').exists()
    host.fail_on = None
    host.calls.clear()
    with pytest.raises(safety.SafetyError, match='Orphaned'):
        apply(host)
    assert not host.mutations()


def test_wrong_mount_aborts_before_libvirt_reads(host):
    def guard(run):
        raise safety.SafetyError('Wrong /data mount')
    with pytest.raises(safety.SafetyError):
        safety.Provisioner(host.run, guard).plan(host.vms, host.network)
    assert not host.calls


def test_insufficient_storage_prevents_all_creation(host, monkeypatch):
    monkeypatch.setattr(safety.shutil, 'disk_usage', lambda path: SimpleNamespace(free=1))
    with pytest.raises(safety.SafetyError, match='Insufficient free space'):
        apply(host)
    assert not host.mutations()


def test_symlinked_disk_is_rejected(host, tmp_path):
    protected = tmp_path / 'other-disk'
    protected.write_bytes(b'Keep me')
    (safety.STORAGE / 'db01.qcow2').symlink_to(protected)
    with pytest.raises(safety.SafetyError, match='Symlink'):
        apply(host)
    assert protected.read_bytes() == b'Keep me'
    assert not host.mutations()


@pytest.mark.parametrize('mutation', ['public_subnet', 'duplicate_ip', 'duplicate_mac', 'unknown_vm', 'invalid_resources'])
def test_invalid_layout_fails_closed(host, mutation):
    if mutation == 'public_subnet':
        host.network = host.network.replace('10.77.0.', '94.130.236.')
    elif mutation == 'duplicate_ip':
        host.vms[0]['ip'] = host.vms[1]['ip']
    elif mutation == 'duplicate_mac':
        host.vms[0]['mac'] = host.vms[1]['mac']
    elif mutation == 'unknown_vm':
        host.vms[0]['name'] = 'unmanaged'
    else:
        host.vms[0]['disk'] = -1
    with pytest.raises(safety.SafetyError):
        apply(host)
    assert not host.mutations()


def test_existing_overlapping_network_is_rejected(host):
    host.networks['other'] = host.network.replace('uranus-debian13', 'other').replace('virbr-uranus', 'virbr-other')
    with pytest.raises(safety.SafetyError, match='overlaps'):
        apply(host)
    assert not host.mutations()


@pytest.mark.parametrize('collision', ['interface', 'route', 'unmanaged_bridge'])
def test_host_network_collisions_are_rejected_before_any_mutation(host, collision):
    original = host.run
    def run(argv):
        if argv[:3] == ['ip', '--json', 'address']:
            if collision == 'interface':
                return json.dumps([{'ifname': 'vpn0', 'addr_info': [{'family': 'inet', 'local': '10.77.0.20', 'prefixlen': 24}]}])
            if collision == 'unmanaged_bridge':
                return json.dumps([{'ifname': 'virbr-uranus'}])
        if argv[:3] == ['ip', '--json', 'route'] and collision == 'route':
            return json.dumps([{'dst': '10.77.0.0/24', 'dev': 'vpn0'}])
        return original(argv)
    with pytest.raises(safety.SafetyError):
        safety.Provisioner(run, lambda run: None).plan(host.vms, host.network)
    assert not host.mutations()


@pytest.mark.parametrize('uuid,options', [(safety.EXPECTED_UUID, 'rw,relatime'), ('wrong', 'rw'), (safety.EXPECTED_UUID, 'ro')])
def test_storage_uuid_and_rw_are_required(uuid, options, monkeypatch):
    monkeypatch.setattr(safety.Path, 'exists', lambda self: True)
    monkeypatch.setattr(safety.Path, 'is_symlink', lambda self: False)
    def run(argv):
        return json.dumps({'filesystems': [{'target': '/data', 'uuid': uuid, 'options': options}]})
    if uuid == safety.EXPECTED_UUID and options.startswith('rw'):
        assert safety.storage_guard(run)['uuid'] == uuid
    else:
        with pytest.raises(safety.SafetyError):
            safety.storage_guard(run)


def test_nested_mount_under_storage_is_rejected(monkeypatch):
    monkeypatch.setattr(safety.Path, 'exists', lambda self: True)
    monkeypatch.setattr(safety.Path, 'is_symlink', lambda self: False)
    def run(argv):
        target = '/data' if '--mountpoint' in argv else '/data/libvirt/images'
        return json.dumps({'filesystems': [{'target': target, 'uuid': safety.EXPECTED_UUID, 'options': 'rw'}]})
    with pytest.raises(safety.SafetyError, match='Unexpected filesystem'):
        safety.storage_guard(run)


def test_existing_sparse_disks_are_reserved_even_when_no_vm_is_missing(host, monkeypatch):
    apply(host)
    host.calls.clear()
    monkeypatch.setattr(safety.shutil, 'disk_usage', lambda path: SimpleNamespace(free=20 * 1024**3))
    with pytest.raises(safety.SafetyError, match='existing disk growth'):
        apply(host)
    assert not host.mutations()


def test_partial_provisioning_accounts_for_all_existing_disks(host):
    apply(host)
    result = safety.Provisioner(host.run, lambda run: None).plan(host.vms[:1], host.network)
    assert len(result['capacity']['volumes']) == 6
    assert result['capacity']['existing_growth_bytes'] > 599 * 1024**3
    assert result['capacity']['new_disk_bytes'] == 0


def test_capacity_includes_initial_base_cache_and_full_new_disks(host):
    result = safety.Provisioner(host.run, lambda run: None).plan(host.vms, host.network)
    assert result['capacity']['required_bytes'] == 615 * 1024**3
    assert result['capacity']['cache_bytes'] == 10 * 1024**3


def test_existing_cache_keeps_space_for_a_replacement_download(host):
    result = apply(host)
    assert result['capacity']['cache_bytes'] == 10 * 1024**3
    assert result['capacity']['required_bytes'] == 615 * 1024**3


def test_foreign_vm_disk_on_data_is_included_without_adopting_it(host, monkeypatch):
    root = safety.STORAGE.parent.parent
    monkeypatch.setattr(safety, 'DATA', root)
    foreign = root / 'foreign.qcow2'
    foreign.write_bytes(b'Foreign data')
    host.domains['foreign'] = f'<domain><devices><disk device="disk"><source file="{foreign}"/></disk></devices></domain>'
    original = host.run
    def run(argv):
        if argv[0] == 'findmnt':
            return json.dumps({'filesystems': [{'uuid': safety.EXPECTED_UUID}]})
        if argv[0] == 'qemu-img' and argv[-1] == str(foreign):
            return json.dumps({'format': 'qcow2', 'virtual-size': 80 * 1024**3})
        return original(argv)
    result = safety.Provisioner(run, lambda run: None).plan(host.vms, host.network)
    assert result['capacity']['existing_growth_bytes'] > 79 * 1024**3
    assert foreign.read_bytes() == b'Foreign data' and not host.mutations()


def test_capacity_rejects_unbounded_foreign_backing_chains(host):
    extra = safety.STORAGE / 'foreign.qcow2'
    extra.write_bytes(b'Do not alter')
    original = host.run
    def run(argv):
        if argv[0] == 'qemu-img' and argv[-1] == str(extra):
            return json.dumps({'format': 'qcow2', 'virtual-size': 1024**3, 'backing-filename': 'other.qcow2'})
        return original(argv)
    with pytest.raises(safety.SafetyError, match='backing chain'):
        safety.Provisioner(run, lambda run: None).plan(host.vms, host.network)
    assert extra.read_bytes() == b'Do not alter' and not host.mutations()
