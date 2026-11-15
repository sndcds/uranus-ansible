"""Validate incremental TLS selection using real certificates and Ansible tasks."""
import datetime
import os
import subprocess

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import Encoding
from cryptography.x509.oid import NameOID
import pytest
import yaml

from conftest import ROOT


@pytest.mark.parametrize('ready', [False, True])
def test_only_unexpired_matching_domains_receive_tls(tmp_path, ready):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.datetime.now(datetime.timezone.utc)
    for domain, san, expired in [('ready.example.test', 'ready.example.test', False),
                                 ('wrong.example.test', 'different.example.test', False),
                                 ('expired.example.test', 'expired.example.test', True)]:
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, san)])
        certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                       .public_key(key.public_key()).serial_number(x509.random_serial_number())
                       .not_valid_before(now - datetime.timedelta(days=2))
                       .not_valid_after(now + datetime.timedelta(days=-1 if expired else 1))
                       .add_extension(x509.SubjectAlternativeName([x509.DNSName(san)]), critical=False)
                       .sign(key, hashes.SHA256()))
        directory = tmp_path / 'certificates' / domain
        directory.mkdir(parents=True)
        (directory / 'fullchain.pem').write_bytes(certificate.public_bytes(Encoding.PEM))
    tasks = yaml.safe_load((ROOT / 'roles/debian13_ingress/tasks/certificates.yml').read_text())
    for task in tasks:
        if 'ansible.builtin.command' in task:
            task['ansible.builtin.command']['argv'][-1] = str(tmp_path / 'certificates') + '/{{ item.domain }}/fullchain.pem'
    domains = ['wrong.example.test', 'expired.example.test', 'missing.example.test']
    if ready:
        domains.append('ready.example.test')
    tasks.append({'name': 'Check certificate readiness without relying on command return code alone',
                  'ansible.builtin.assert': {'that': [
                      f"debian13_ingress_tls_domains == {['ready.example.test'] if ready else []!r}",
                      f'debian13_ingress_tls_ready == {ready}',
                  ]}})
    playbook = tmp_path / 'certificates-test.yml'
    playbook.write_text(yaml.safe_dump([{
        'hosts': 'localhost', 'gather_facts': False,
        'vars': {'debian13_ingress_sites': [{'domain': name} for name in domains],
                 'ansible_remote_tmp': str(tmp_path / 'remote')},
        'tasks': tasks,
    }]))
    result = subprocess.run(['ansible-playbook', '-i', 'localhost,', '-c', 'local', str(playbook)],
                            capture_output=True, text=True, env={
                                **os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible.cfg'),
                                'ANSIBLE_LOCAL_TEMP': str(tmp_path / 'ansible'),
                                'ANSIBLE_NOCOWS': '1',
                            })
    assert result.returncode == 0, result.stdout + result.stderr
