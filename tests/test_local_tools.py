import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest
import uranus_debian13 as safety

from conftest import ROOT
from test_provisioning import FakeHost


def test_real_qemu_clone_and_nocloud_seed_preserve_guest_data_on_repeat(tmp_path, settings, render, monkeypatch):
    for tool in ['qemu-img', 'cloud-localds']:
        assert shutil.which(tool), f'Install {tool} to exercise actual disk and seed generation'
    storage = tmp_path / 'images'
    base_dir = storage / '.base'
    base_dir.mkdir(parents=True)
    seeds_dir = tmp_path / 'seeds'
    monkeypatch.setattr(safety, 'STORAGE', storage)
    monkeypatch.setattr(safety, 'SEEDS', seeds_dir)
    vm = {**settings['hetzner_vms'][0], 'disk': 1}
    network = render('roles/debian13_hypervisor/templates/network.xml.j2')
    image = base_dir / 'base.qcow2'
    subprocess.run(['qemu-img', 'create', '-f', 'qcow2', str(image), '16M'], check=True, capture_output=True)
    checksum = hashlib.sha512(image.read_bytes()).hexdigest()
    seeds = {vm['name']: {'user_data': render('roles/debian13_hypervisor/templates/user-data.yml.j2', item=vm, hetzner_ssh_public_key_file='fixture.pub'),
                         'meta_data': render('roles/debian13_hypervisor/templates/meta-data.yml.j2', item=vm),
                         'network_config': render('roles/debian13_hypervisor/templates/network-config.yml.j2', item=vm)}}
    fake = FakeHost(tmp_path, [vm], network)
    def run(argv):
        if argv[0] in ('qemu-img', 'cloud-localds'):
            return safety.execute(argv)
        return fake.run(argv)
    provisioner = safety.Provisioner(run, lambda run: None)
    kwargs = dict(vms=[vm], network_xml=network, image=str(image), checksum=checksum, seeds=seeds)
    assert provisioner.apply(**kwargs)['changed']
    guest = storage / 'db01.qcow2'
    info = json.loads(safety.execute(['qemu-img', 'info', '--output=json', str(guest)]))
    assert info['virtual-size'] == 1024**3 and not info.get('backing-filename')
    # Place real data in the independent guest image, then exercise the second run.
    subprocess.run(['qemu-io', '-f', 'qcow2', '-c', 'write -P 0x55 8M 4k', str(guest)], check=True, capture_output=True)
    before = hashlib.sha512(guest.read_bytes()).hexdigest()
    assert not provisioner.apply(**kwargs)['changed']
    assert hashlib.sha512(guest.read_bytes()).hexdigest() == before
    assert (seeds_dir / 'db01/seed.iso').is_file()


def test_concurrent_provisioning_is_locked_before_any_libvirt_change(tmp_path, monkeypatch):
    lock_path = tmp_path / 'lock'
    original_open = safety.os.open
    monkeypatch.setattr(safety.os, 'open', lambda path, flags, mode: original_open(lock_path, flags, mode))
    with lock_path.open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        provisioner = safety.Provisioner(lambda args: pytest.fail('No libvirt operation is allowed'), lambda run: None)
        with pytest.raises(BlockingIOError):
            safety.locked_apply(provisioner)


@pytest.mark.parametrize('dump', [r'\! touch /tmp/forbidden', r'\connect other_db', r'\i other.sql', r'\gexec', 'DROP DATABASE valuable;', 'CREATE DATABASE unexpected;'])
def test_unsafe_initial_sql_dumps_are_rejected(dump, tmp_path):
    path = tmp_path / 'dump.sql'
    path.write_text(dump + '\n')
    with pytest.raises(safety.SafetyError):
        safety.validate_sql_dump(path)


def test_sql_copy_rows_are_treated_as_data_and_existing_repository_dumps_validate(tmp_path):
    path = tmp_path / 'dump.sql'
    path.write_text('COPY uranus.test FROM stdin;\nDROP DATABASE is only a data string here\n\\connect is data here\n\\.\n')
    safety.validate_sql_dump(path)
    for name in ['uranus.sql', 'uranus_dev.sql']:
        safety.validate_sql_dump(ROOT / name)


def test_incomplete_sql_copy_is_rejected(tmp_path):
    path = tmp_path / 'dump.sql'
    path.write_text('COPY uranus.test FROM stdin;\nunfinished data\n')
    with pytest.raises(safety.SafetyError):
        safety.validate_sql_dump(path)
