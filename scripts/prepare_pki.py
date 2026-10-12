#!/usr/bin/env python3
"""Prepare a fresh controller-only internal CA and Vault-encrypted node keys."""
import argparse
import ipaddress
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[1]


def run(argv):
    result = subprocess.run([str(arg) for arg in argv], capture_output=True,
                            text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f'{argv[0]} failed: {result.stderr.strip()}')
    return result.stdout


def identities(settings, inventory):
    host = inventory['all']['children']['incus_hosts']['hosts']['hetzner']['ansible_host']
    nodes = {'hetzner': [host, settings['incus_gateway'], settings['hetzner_public_ipv6']]}
    for instance in settings['incus_instances']:
        if instance['name'] in nodes:
            raise ValueError('Duplicate PKI node name')
        nodes[instance['name']] = [instance['ip']]
    for name, addresses in nodes.items():
        if not re.fullmatch(r'[a-z][a-z0-9-]*', name):
            raise ValueError(f'Invalid PKI node name: {name}')
        nodes[name] = list(dict.fromkeys(str(ipaddress.ip_address(ip)) for ip in addresses))
    return nodes


def publish(source, destination, mode):
    with destination.open('xb') as stream:
        stream.write(source.read_bytes())
    destination.chmod(mode)


def prepare(pki_dir, private_dir, nodes):
    for directory in (pki_dir, private_dir):
        if directory.exists() or directory.is_symlink():
            raise ValueError(f'Refusing to replace existing PKI material: {directory}')
        for parent in directory.parents:
            if parent.is_symlink():
                raise ValueError(f'Symlink in PKI destination: {parent}')
    if pki_dir == private_dir or pki_dir in private_dir.parents or private_dir in pki_dir.parents:
        raise ValueError('Use separate PKI and private directories')
    for tool in ('openssl', 'ansible-vault'):
        if not shutil.which(tool):
            raise RuntimeError(f'Install {tool} on the controller before preparing the PKI')
    with tempfile.TemporaryDirectory(prefix='uranus-pki-') as temporary:
        staging = Path(temporary)
        password = staging / 'vault-password'
        password.write_text(secrets.token_urlsafe(48) + '\n')
        password.chmod(0o600)
        ca_key, ca_cert = staging / 'ca.key', staging / 'ca.crt'
        run(['openssl', 'req', '-x509', '-newkey', 'rsa:4096', '-noenc', '-sha256',
             '-days', '3650', '-set_serial', str(secrets.randbits(159) or 1),
             '-subj', '/CN=Uranus Internal CA', '-keyout', ca_key, '-out', ca_cert,
             '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0',
             '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
             '-addext', 'subjectKeyIdentifier=hash'])
        keys = [ca_key]
        for name, addresses in nodes.items():
            key, cert, csr = (staging / f'{name}.{extension}' for extension in ('key', 'crt', 'csr'))
            run(['openssl', 'req', '-new', '-newkey', 'rsa:3072', '-noenc', '-sha256',
                 '-subj', f'/CN={name}', '-keyout', key, '-out', csr])
            extensions = staging / f'{name}.ext'
            extensions.write_text('\n'.join([
                'basicConstraints=critical,CA:FALSE',
                'keyUsage=critical,digitalSignature,keyEncipherment',
                'extendedKeyUsage=serverAuth,clientAuth',
                'subjectKeyIdentifier=hash',
                'authorityKeyIdentifier=keyid:always,issuer',
                'subjectAltName=DNS:' + name + ''.join(',IP:' + ip for ip in addresses),
            ]) + '\n')
            run(['openssl', 'x509', '-req', '-in', csr, '-CA', ca_cert, '-CAkey', ca_key,
                 '-set_serial', str(secrets.randbits(159) or 1), '-days', '365', '-sha256',
                 '-extfile', extensions, '-out', cert])
            run(['openssl', 'verify', '-CAfile', ca_cert, '-purpose', 'sslserver',
                 '-verify_hostname', name, cert])
            run(['openssl', 'verify', '-CAfile', ca_cert, '-purpose', 'sslclient', cert])
            for address in addresses:
                run(['openssl', 'verify', '-CAfile', ca_cert, '-verify_ip', address, cert])
            if (run(['openssl', 'x509', '-in', cert, '-pubkey', '-noout']).strip() !=
                    run(['openssl', 'pkey', '-in', key, '-pubout']).strip()):
                raise RuntimeError(f'Certificate key mismatch: {name}')
            keys.append(key)
        run(['ansible-vault', 'encrypt', '--vault-id', f'pki@{password}',
             '--encrypt-vault-id', 'pki', *keys])
        if any(not key.read_bytes().startswith(b'$ANSIBLE_VAULT;1.2;AES256;pki\n') for key in keys):
            raise RuntimeError('Vault encryption did not produce the expected encrypted key files')
        # Publish only after every certificate and encrypted key has been checked.
        pki_dir.mkdir(mode=0o700, parents=True)
        private_dir.mkdir(mode=0o700, parents=True)
        publish(ca_cert, pki_dir / 'ca.crt', 0o644)
        publish(ca_cert, private_dir / 'ca.crt', 0o644)
        publish(ca_key, private_dir / 'ca.key', 0o600)
        publish(password, private_dir / 'vault-password', 0o600)
        for name in nodes:
            publish(staging / f'{name}.crt', pki_dir / f'{name}.crt', 0o644)
            publish(staging / f'{name}.key', pki_dir / f'{name}.key', 0o600)
    print(f'Prepared a new internal CA and {len(nodes)} verified node identities in {pki_dir}')
    print(f'Encrypted CA key and local Vault credential: {private_dir}')
    print(f'Add to your existing Ansible command: --vault-id pki@{private_dir / "vault-password"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pki-dir', type=Path, default=ROOT / 'environments/hetzner/pki')
    parser.add_argument('--private-dir', type=Path, default=ROOT / '.uranus-private/pki')
    args = parser.parse_args()
    settings = yaml.safe_load((ROOT / 'environments/hetzner/group_vars/all.yml').read_text())
    inventory = yaml.safe_load((ROOT / 'environments/hetzner/inventory.yml').read_text())
    previous_umask = os.umask(0o077)
    try:
        prepare(args.pki_dir.absolute(), args.private_dir.absolute(), identities(settings, inventory))
    finally:
        os.umask(previous_umask)


if __name__ == '__main__':
    main()
