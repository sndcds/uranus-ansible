"""Check controller prerequisites and consume a real generated PKI through Ansible."""
import hashlib
import os
import stat
import subprocess
import sys

import pytest
import yaml

from conftest import ROOT


def run_ansible(tmp_path, tasks, variables, vault_password=None):
    inventory = tmp_path / 'inventory.yml'
    inventory.write_text(yaml.safe_dump({'all': {'hosts': {'hetzner': {
        'ansible_host': '127.0.0.1', 'ansible_port': 1,
    }}}}))
    playbook = tmp_path / 'playbook.yml'
    playbook.write_text(yaml.safe_dump([{
        'name': 'Only local PKI fixtures', 'hosts': 'hetzner',
        'gather_facts': False, 'become': True,
        'vars': variables, 'tasks': tasks,
    }]))
    env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
           'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible-local'),
           'ANSIBLE_REMOTE_TEMP': str(tmp_path / 'ansible-remote')}
    args = ['ansible-playbook', '-i', str(inventory), str(playbook)]
    if vault_password:
        args += ['--vault-id', f'pki@{vault_password}']
    return subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=60)


@pytest.mark.parametrize('invalid', ['ca.crt', 'hetzner.crt', 'hetzner.key', 'directory', None])
def test_controller_inputs_fail_before_remote_changes(tmp_path, invalid):
    pki = tmp_path / 'pki'
    pki.mkdir()
    for name in ('ca.crt', 'hetzner.crt', 'hetzner.key'):
        if name != invalid:
            (pki / name).write_text('public or encrypted fixture only\n')
    if invalid == 'directory':
        (pki / 'ca.crt').unlink()
        (pki / 'ca.crt').mkdir()
    if invalid:
        # The complete role must stop before apt, SSH, or any TLS staging.
        action = {'ansible.builtin.include_role': {'name': 'internal_tls'}}
    else:
        action = {'ansible.builtin.include_tasks': str(ROOT / 'roles/internal_tls/tasks/inputs.yml')}
    result = run_ansible(tmp_path, [
        {'name': 'Exercise real PKI input checks', **action},
        {'name': 'After PKI inputs', 'ansible.builtin.debug': {'msg': 'PKI_INPUTS_ACCEPTED'}},
    ], {'uranus_pki_dir': str(pki)})
    output = result.stdout + result.stderr
    assert result.returncode == (2 if invalid else 0), output
    assert 'unreachable=0' in output
    assert ('PKI_INPUTS_ACCEPTED' in output) is (invalid is None)
    if invalid:
        assert 'missing or unreadable' in output
        assert 'prepare_pki.py' in output
        assert 'TASK [internal_tls : Install certificate validation tools' not in output


@pytest.fixture(scope='module')
def prepared_pki(tmp_path_factory):
    directory = tmp_path_factory.mktemp('generated-pki')
    pki, private = directory / 'pki', directory / 'private'
    args = [sys.executable, str(ROOT / 'scripts/prepare_pki.py'),
            '--pki-dir', str(pki), '--private-dir', str(private)]
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stdout + result.stderr
    return pki, private, args


def test_generated_keys_decrypt_through_ansible_copy_and_match_certificates(prepared_pki, tmp_path):
    pki, private, _ = prepared_pki
    destination = tmp_path / 'decrypted'
    destination.mkdir(mode=0o700)
    names = ['hetzner', 'db01', 'dev01', 'prod01', 'mon01', 'nom01', 'vers01', 'nginx01', 'plausible01']
    result = run_ansible(tmp_path, [{
        'name': 'Consume encrypted keys with the real Ansible copy action',
        'ansible.builtin.copy': {
            'src': str(pki / '{{ item }}.key'),
            'dest': str(destination / '{{ item }}.key'),
            'mode': '0600',
            'validate': '/usr/bin/openssl pkey -noout -in %s',
        },
        'loop': names, 'delegate_to': 'localhost', 'become': False, 'no_log': True,
    }], {}, private / 'vault-password')
    assert result.returncode == 0, result.stdout + result.stderr
    assert not (pki / 'ca.key').exists()
    assert not (pki / 'vault-password').exists()
    assert stat.S_IMODE(pki.stat().st_mode) == 0o700
    assert stat.S_IMODE(private.stat().st_mode) == 0o700
    for key in [private / 'ca.key', *(pki / f'{name}.key' for name in names)]:
        assert key.read_bytes().splitlines()[0] == b'$ANSIBLE_VAULT;1.2;AES256;pki'
        assert stat.S_IMODE(key.stat().st_mode) == 0o600
    assert stat.S_IMODE((private / 'vault-password').stat().st_mode) == 0o600
    for name in names:
        cert_public = subprocess.check_output(
            ['openssl', 'x509', '-in', str(pki / f'{name}.crt'), '-pubkey', '-noout'])
        key_public = subprocess.check_output(
            ['openssl', 'pkey', '-in', str(destination / f'{name}.key'), '-pubout'])
        assert cert_public.strip() == key_public.strip()
        invalid_name = subprocess.run([
            'openssl', 'verify', '-CAfile', str(pki / 'ca.crt'),
            '-verify_hostname', 'unrelated.example.test', str(pki / f'{name}.crt'),
        ], capture_output=True, text=True)
        assert invalid_name.returncode != 0
        assert 'hostname mismatch' in invalid_name.stderr


def test_existing_pki_is_not_replaced(prepared_pki):
    pki, private, args = prepared_pki
    files = [*pki.iterdir(), *private.iterdir()]
    before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=30)
    assert result.returncode != 0
    assert 'Refusing to replace existing PKI material' in result.stderr
    assert {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in files} == before


def test_extension_preserves_existing_ca_and_node_identities(prepared_pki, tmp_path):
    import shutil
    original, private_original, _ = prepared_pki
    pki, private = tmp_path / 'pki', tmp_path / 'private'
    shutil.copytree(original, pki)
    shutil.copytree(private_original, private)
    for suffix in ['crt', 'key']:
        (pki / ('plausible01.' + suffix)).unlink()
    existing = [*pki.iterdir(), *private.iterdir()]
    before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in existing}
    args = [sys.executable, str(ROOT / 'scripts/extend_pki.py'), '--pki-dir', str(pki), '--private-dir', str(private)]
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stderr
    assert {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in existing} == before
    assert (pki / 'plausible01.key').read_bytes().startswith(b'$ANSIBLE_VAULT;')
    subprocess.run(['openssl', 'verify', '-CAfile', str(pki / 'ca.crt'), '-verify_hostname', 'plausible01',
                    '-verify_ip', '10.77.0.18', str(pki / 'plausible01.crt')], check=True, capture_output=True)
    after = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in pki.iterdir()}
    assert subprocess.run(args, cwd=ROOT, capture_output=True, timeout=60).returncode == 0
    assert {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in pki.iterdir()} == after
