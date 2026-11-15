#!/usr/bin/env python3
"""Add missing node identities using the existing encrypted CA; never replace identities."""
import argparse
import os
from pathlib import Path
import secrets
import tempfile

import yaml

from prepare_pki import ROOT, identities, publish, run


def extend(pki_dir, private_dir, nodes):
    ca = pki_dir / 'ca.crt'
    ca_key = private_dir / 'ca.key'
    password = private_dir / 'vault-password'
    for path in [ca, ca_key, password, private_dir / 'ca.crt']:
        if not path.is_file() or path.is_symlink():
            raise ValueError(f'Require existing regular PKI input: {path}')
    if ca.read_bytes() != (private_dir / 'ca.crt').read_bytes():
        raise ValueError('Controller CA copies differ')
    if not ca_key.read_bytes().startswith(b'$ANSIBLE_VAULT;'):
        raise ValueError('Require a Vault-encrypted existing CA key')
    pending = {}
    for name, addresses in nodes.items():
        cert, key = pki_dir / f'{name}.crt', pki_dir / f'{name}.key'
        if cert.exists() != key.exists() or cert.is_symlink() or key.is_symlink():
            raise ValueError(f'Incomplete or symlinked identity: {name}')
        if cert.exists():
            run(['openssl', 'verify', '-CAfile', ca, '-verify_hostname', name, cert])
            for address in addresses:
                run(['openssl', 'verify', '-CAfile', ca, '-verify_ip', address, cert])
        else:
            pending[name] = addresses
    if not pending:
        print('All requested identities already exist; no changes.')
        return
    with tempfile.TemporaryDirectory(prefix='uranus-pki-extension-') as temporary:
        staging = Path(temporary)
        decrypted_ca = staging / 'ca.key'
        run(['ansible-vault', 'decrypt', '--vault-id', f'pki@{password}', '--output', decrypted_ca, ca_key])
        if (run(['openssl', 'x509', '-in', ca, '-pubkey', '-noout']).strip() !=
                run(['openssl', 'pkey', '-in', decrypted_ca, '-pubout']).strip()):
            raise ValueError('Existing CA certificate and private key differ')
        for name, addresses in pending.items():
            key, cert, csr = (staging / f'{name}.{ext}' for ext in ['key', 'crt', 'csr'])
            run(['openssl', 'req', '-new', '-newkey', 'rsa:3072', '-noenc', '-sha256',
                 '-subj', f'/CN={name}', '-keyout', key, '-out', csr])
            extensions = staging / 'extensions.cnf'
            extensions.write_text('\n'.join([
                'basicConstraints=critical,CA:FALSE',
                'keyUsage=critical,digitalSignature,keyEncipherment',
                'extendedKeyUsage=serverAuth,clientAuth',
                'subjectKeyIdentifier=hash', 'authorityKeyIdentifier=keyid:always,issuer',
                'subjectAltName=DNS:' + name + ''.join(',IP:' + ip for ip in addresses),
            ]) + '\n')
            run(['openssl', 'x509', '-req', '-in', csr, '-CA', ca, '-CAkey', decrypted_ca,
                 '-set_serial', str(secrets.randbits(159) or 1), '-days', '365', '-sha256',
                 '-extfile', extensions, '-out', cert])
            for purpose in ['sslserver', 'sslclient']:
                run(['openssl', 'verify', '-CAfile', ca, '-purpose', purpose, '-verify_hostname', name, cert])
            run(['ansible-vault', 'encrypt', '--vault-id', f'pki@{password}', '--encrypt-vault-id', 'pki', key])
            publish(cert, pki_dir / f'{name}.crt', 0o644)
            publish(key, pki_dir / f'{name}.key', 0o600)
    print('Added identities without replacing the CA or existing nodes: ' + ', '.join(pending))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pki-dir', type=Path, default=ROOT / 'environments/hetzner/pki')
    parser.add_argument('--private-dir', type=Path, default=ROOT / '.uranus-private/pki')
    args = parser.parse_args()
    settings = yaml.safe_load((ROOT / 'environments/hetzner/group_vars/all.yml').read_text())
    inventory = yaml.safe_load((ROOT / 'environments/hetzner/inventory.yml').read_text())
    mask = os.umask(0o077)
    try:
        extend(args.pki_dir.absolute(), args.private_dir.absolute(), identities(settings, inventory))
    finally:
        os.umask(mask)


if __name__ == '__main__':
    main()
