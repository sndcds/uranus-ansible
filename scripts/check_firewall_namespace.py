#!/usr/bin/env python3
"""Real SSH/nft/systemd regression, run only inside an isolated CI network namespace."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'module_utils'))
from uranus_firewall import FirewallTransaction, fresh_ssh


def run(argv, timeout=20):
    result = subprocess.run(argv, check=True, capture_output=True, text=True, timeout=timeout)
    return result.stdout


def worker(directory):
    directory = Path(directory)
    assert os.geteuid() == 0
    # Prove isolation from PID 1's host network before any nft or link mutation.
    assert os.readlink('/proc/self/ns/net') != os.readlink('/proc/1/ns/net')
    client = subprocess.Popen(['unshare', '--net', 'sleep', '120'])
    server = master = controller = None
    unit = 'uranus-firewall-ci-' + directory.name.replace('_', '-')
    timer_unit = None
    try:
        deadline = time.monotonic() + 5
        while os.readlink(f'/proc/{client.pid}/ns/net') == os.readlink('/proc/self/ns/net'):
            assert time.monotonic() < deadline
            time.sleep(0.05)
        enter = ['nsenter', '--target', str(client.pid), '--net']
        run(['ip', 'link', 'set', 'lo', 'up'])
        run(['ip', 'link', 'add', 'server-peer', 'type', 'veth', 'peer', 'name', 'client-peer'])
        run(['ip', 'address', 'add', '10.254.74.1/24', 'dev', 'server-peer'])
        run(['ip', 'link', 'set', 'server-peer', 'up'])
        run(['ip', 'link', 'set', 'client-peer', 'netns', str(client.pid)])
        for argv in (['ip', 'link', 'set', 'lo', 'up'],
                     ['ip', 'address', 'add', '10.254.74.2/24', 'dev', 'client-peer'],
                     ['ip', 'link', 'set', 'client-peer', 'up']):
            run(enter + argv)
        key, host_key = directory / 'client-key', directory / 'host-key'
        for path in (key, host_key):
            run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(path)])
        known = directory / 'known_hosts'
        known.write_text('10.254.74.1 ' + host_key.with_suffix('.pub').read_text())
        config = directory / 'sshd_config'
        config.write_text(f'Port 22\nListenAddress 10.254.74.1\nHostKey {host_key}\n'
                          f'AuthorizedKeysFile {key}.pub\nPidFile {directory}/sshd.pid\n'
                          'PermitRootLogin prohibit-password\nPasswordAuthentication no\nUsePAM no\nStrictModes no\n')
        Path('/run/sshd').mkdir(exist_ok=True)
        server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        common = f'-F /dev/null -o UserKnownHostsFile={known} -o IdentitiesOnly=yes'
        def client_run(argv):
            return run(enter + argv)
        deadline = time.monotonic() + 5
        while True:
            try:
                original = fresh_ssh('10.254.74.1', 'root', 22, 'before', str(key), common, client_run)['connection']
                break
            except subprocess.CalledProcessError:
                assert time.monotonic() < deadline
                time.sleep(0.1)
        control = directory / 'master.sock'
        base = ['ssh', '-F', '/dev/null', '-o', f'UserKnownHostsFile={known}', '-o', 'StrictHostKeyChecking=yes',
                '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-i', str(key), '-l', 'root']
        master = subprocess.Popen(enter + base + ['-M', '-S', str(control), '-N', '10.254.74.1'],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 5
        while not control.exists():
            assert time.monotonic() < deadline
            time.sleep(0.05)
        old = ('table inet uranus_debian13 { chain input { type filter hook input priority 10; policy drop; '
               'iifname "lo" accept; ct state established,related accept; '
               'ip saddr 10.254.74.2 tcp dport 22 accept; } }\n')
        bad = 'destroy table inet uranus_debian13\n' + old.replace('10.254.74.2', '10.254.74.99')
        confirmed, candidate = directory / 'confirmed.nft', directory / 'candidate.nft'
        confirmed.write_text(old)
        candidate.write_text(bad)
        initial = directory / 'initial.nft'
        initial.write_text(old + 'table inet unrelated_sentinel { set keep { type ipv4_addr; elements = { 192.0.2.1 }; } }\n')
        run(['nft', '--file', str(initial)])
        sentinel = run(['nft', 'list', 'table', 'inet', 'unrelated_sentinel'])
        state = directory / 'state'
        helper = directory / 'watchdog'
        helper.write_text(f'#!{sys.executable}\nimport sys\nsys.path.insert(0,{str(ROOT / "module_utils")!r})\n'
                          'from uranus_firewall import FirewallTransaction\n'
                          f'FirewallTransaction({str(state)!r},{str(confirmed)!r}).rollback(sys.argv[-1])\n')
        helper.chmod(0o755)
        # A real systemd timer/service runs independently, in this server namespace.
        code = f'''
import json,sys,time,subprocess
sys.path.insert(0,{str(ROOT / 'module_utils')!r})
from uranus_firewall import FirewallTransaction,command
def run(argv):
    if argv[0]=='systemd-run':
        argv=argv[:1]+['--property=NetworkNamespacePath=/proc/{os.getpid()}/ns/net']+argv[1:]
    return command(argv)
tx=FirewallTransaction({str(state)!r},{str(confirmed)!r},helper={str(helper)!r},run=run,unit={unit!r})
print(json.dumps(tx.begin({str(candidate)!r},{original!r},['10.254.74.2/32'],30)),flush=True)
time.sleep(120)
'''
        controller = subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        prepared = json.loads(controller.stdout.readline())
        timer_unit = f'{unit}-{prepared["token"][:16]}'
        os.kill(controller.pid, signal.SIGKILL)
        controller.wait(timeout=5)
        assert run(enter + base + ['-S', str(control), '10.254.74.1', 'printf reused']) == 'reused'
        try:
            fresh_ssh('10.254.74.1', 'root', 22, prepared['token'], str(key), common, client_run)
            raise AssertionError('The bad firewall allowed a new TCP connection')
        except subprocess.CalledProcessError:
            pass
        deadline = time.monotonic() + 45
        while (state / 'pending.json').exists():
            assert time.monotonic() < deadline, 'Independent systemd watchdog failed to restore access'
            time.sleep(0.2)
        assert confirmed.read_text() == old
        assert run(['nft', 'list', 'table', 'inet', 'unrelated_sentinel']) == sentinel
        fresh_ssh('10.254.74.1', 'root', 22, 'restored', str(key), common, client_run)
        # Also prove confirmation stops rollback and a late callback is harmless.
        good = directory / 'good.nft'
        good.write_text('destroy table inet uranus_debian13\n' + old)
        def schedule(argv):
            if argv[0] == 'systemd-run':
                argv = argv[:1] + [f'--property=NetworkNamespacePath=/proc/{os.getpid()}/ns/net'] + argv[1:]
            return run(argv)
        tx = FirewallTransaction(state, confirmed, helper=str(helper), run=schedule, unit=unit)
        prepared = tx.begin(good, original, ['10.254.74.2/32'], 30)
        timer_unit = f'{unit}-{prepared["token"][:16]}'
        proof = fresh_ssh('10.254.74.1', 'root', 22, prepared['token'], str(key), common, client_run)
        assert tx.confirm(prepared['token'], proof)['confirmed']
        assert not tx.rollback(prepared['token'])['changed']
        assert not tx.begin(good, proof['connection'], ['10.254.74.2/32'], 30)['changed']
        print(json.dumps({'fresh_ssh_blocked': True, 'reused_ssh_detected': True,
                          'automatic_rollback_after_sigkill': True, 'unrelated_table_preserved': True,
                          'confirmed_update_idempotent': True}))
    finally:
        if timer_unit:
            subprocess.run(['systemctl', 'stop', timer_unit + '.timer', timer_unit + '.service'], capture_output=True)
        for process in (controller, master, server, client):
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    worker(sys.argv[1])
