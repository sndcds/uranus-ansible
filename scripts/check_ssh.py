#!/usr/bin/env python3
"""Validate effective key-only SSH with native OpenSSH; never start a daemon."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    sshd = shutil.which('sshd') or '/usr/sbin/sshd'
    if not Path(sshd).is_file():
        raise RuntimeError('Native openssh-server is required; this check cannot be skipped')
    spec = importlib.util.spec_from_file_location('access', ROOT / 'roles/host_firewall/files/firewall.py')
    access = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(access)
    access.SSHD = sshd
    with tempfile.TemporaryDirectory(prefix='uranus-ssh-parser-') as name:
        root = Path(name)
        snippets = root / 'sshd_config.d'
        snippets.mkdir()
        snippet = snippets / '00-uranus-host.conf'
        snippet.write_text((ROOT / 'roles/host_firewall/files/host-ssh.conf').read_text())
        key = root / 'host-key'
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key)], check=True, capture_output=True)
        config = root / 'sshd_config'
        config.write_text(f'Include {snippets}/*.conf\nHostKey {key}\nPort 22\n')
        access.SSHD_CONFIG = config
        access.require_simple_ssh_config(config)
        access.run([sshd, '-t', '-f', str(config)])
        for user in ('fixture-admin', 'root'):
            for source in ('198.51.100.8', '203.0.113.20', '2001:db8:abcd::123'):
                context = f'user={user},host={source},addr={source},laddr=127.0.0.1,lport=22'
                if not access.ssh_policy_is_current(context):
                    raise RuntimeError('Native effective SSH policy is not key-only: ' + context)
                print(f'PASS: native key-only SSH policy for {user} from {source}')
        conflict = snippets / '00-before-uranus.conf'
        conflict.write_text('PasswordAuthentication yes\n')
        if access.ssh_policy_is_current('user=fixture-admin,host=198.51.100.8,addr=198.51.100.8,laddr=127.0.0.1,lport=22'):
            raise RuntimeError('Conflicting earlier SSH policy was not detected')
        print('PASS: native OpenSSH detects a conflicting earlier drop-in')


if __name__ == '__main__':
    main()
