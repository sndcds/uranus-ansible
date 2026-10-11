import json
from pathlib import Path

import pytest
from uranus_firewall import FirewallTransaction, FirewallError, fresh_ssh

PEER = '203.0.113.10 40000 94.130.236.38 22'
NETWORKS = ['203.0.113.10/32']
OLD = 'table inet uranus_debian13 { chain input { type filter hook input priority 10; policy accept; } }\n'
NEW = OLD.replace('policy accept', 'policy drop')


@pytest.fixture
def firewall(tmp_path):
    directory = tmp_path / 'state'
    config, candidate = tmp_path / 'confirmed.nft', tmp_path / 'candidate.nft'
    config.write_text(OLD)
    candidate.write_text(NEW)
    calls, live = [], {'table': OLD, 'time': 0, 'fail_timer': False}
    def run(argv):
        calls.append(argv)
        if argv[:4] == ['nft', '--json', 'list', 'tables']:
            return json.dumps({'nftables': [{'table': {'family': 'inet', 'name': 'uranus_debian13'}}] if live['table'] else []})
        if argv[:4] == ['nft', '--json', 'list', 'table']:
            return json.dumps({'nftables': [{'rule': {'text': live['table']}}]})
        if argv[:3] == ['nft', 'list', 'table']:
            return live['table']
        if argv[:2] == ['nft', '--file']:
            text = Path(argv[2]).read_text()
            live['table'] = text.split('\n', 1)[1] if text.startswith('destroy table') else text
        if argv[0] == 'systemd-run' and live['fail_timer']:
            raise FirewallError('Timer unavailable')
        return ''
    return FirewallTransaction(directory, config, run=run, now=lambda: live['time']), candidate, live, calls


def begin(firewall, **kwargs):
    transaction, candidate, *_ = firewall
    return transaction.begin(candidate, PEER, NETWORKS, **kwargs)


def test_watchdog_is_armed_before_firewall_and_confirmed_file_is_preserved(firewall):
    transaction, _, live, calls = firewall
    result = begin(firewall)
    assert live['table'] == NEW and transaction.config.read_text() == OLD
    assert transaction.pending.exists()
    assert next(i for i, c in enumerate(calls) if c[0] == 'systemd-run') < next(i for i, c in enumerate(calls) if c[:2] == ['nft', '--file'])
    assert '--timer-property=AccuracySec=1s' in next(c for c in calls if c[0] == 'systemd-run')
    assert result['deadline'] == 90


def test_disconnect_or_controller_death_leaves_watchdog_restore_data(firewall):
    transaction, _, live, _ = firewall
    result = begin(firewall)
    # Simulate the independent host watchdog in a new process/object.
    rebooted = FirewallTransaction(transaction.directory, transaction.config, run=transaction.run)
    assert rebooted.rollback(result['token'])['rolled_back']
    assert live['table'] == OLD and transaction.config.read_text() == OLD
    assert not transaction.pending.exists()
    assert not rebooted.rollback(result['token'])['changed']


def test_initial_table_absence_rolls_back_only_the_managed_table(firewall):
    transaction, _, live, calls = firewall
    live['table'] = ''
    transaction.config.unlink()
    result = begin(firewall)
    transaction.rollback(result['token'])
    assert live['table'] == '' and not transaction.config.exists()
    assert not any('flush ruleset' in ' '.join(c) for c in calls)


def test_missing_timer_prevents_candidate_application(firewall):
    transaction, _, live, calls = firewall
    live['fail_timer'] = True
    with pytest.raises(FirewallError, match='Timer unavailable'):
        begin(firewall)
    assert live['table'] == OLD and not transaction.pending.exists()
    assert not any(c[:2] == ['nft', '--file'] and Path(c[2]).name == 'candidate.nft' for c in calls)


@pytest.mark.parametrize('connection', ['', '198.51.100.2 40000 94.130.236.38 22', '203.0.113.10 40000 94.130.236.38 2222'])
def test_unverified_peer_or_port_is_rejected_before_any_firewall_operation(firewall, connection):
    transaction, candidate, _, calls = firewall
    with pytest.raises(FirewallError):
        transaction.begin(candidate, connection, NETWORKS)
    assert not calls


@pytest.mark.parametrize('proof', ['same_session', 'wrong_token', 'wrong_peer', 'wrong_listener'])
def test_confirmation_requires_fresh_authenticated_connection(firewall, proof):
    transaction, _, _, _ = firewall
    token = begin(firewall)['token']
    response = {'token': token, 'connection': '203.0.113.10 40001 94.130.236.38 22'}
    response.update({'same_session': {'connection': PEER}, 'wrong_token': {'token': 'wrong'},
                     'wrong_peer': {'connection': '198.51.100.2 40001 94.130.236.38 22'},
                     'wrong_listener': {'connection': '203.0.113.10 40001 94.130.236.39 22'}}[proof])
    with pytest.raises(FirewallError):
        transaction.confirm(token, response)
    assert transaction.pending.exists() and transaction.config.read_text() == OLD


def test_success_commits_once_and_second_run_does_not_reload(firewall):
    transaction, _, live, calls = firewall
    token = begin(firewall)['token']
    assert transaction.confirm(token, {'token': token, 'connection': '203.0.113.10 40001 94.130.236.38 22'})['confirmed']
    assert transaction.config.read_text() == NEW and not transaction.pending.exists()
    calls.clear()
    assert not begin(firewall)['changed']
    assert not any(c[0] == 'systemd-run' or c[:2] == ['nft', '--file'] for c in calls)
    assert not transaction.rollback(token)['changed']


def test_late_confirmation_restores_previous_firewall(firewall):
    transaction, _, live, _ = firewall
    token = begin(firewall)['token']
    live['time'] = 91
    with pytest.raises(FirewallError, match='deadline expired'):
        transaction.confirm(token, {'token': token, 'connection': '203.0.113.10 40001 94.130.236.38 22'})
    assert live['table'] == OLD and not transaction.pending.exists()


def test_parallel_transaction_cannot_replace_pending_snapshot(firewall):
    transaction, *_ = firewall
    begin(firewall)
    snapshot = transaction.pending.read_bytes()
    with pytest.raises(FirewallError, match='pending'):
        begin(firewall)
    assert transaction.pending.read_bytes() == snapshot


def test_probe_disables_connection_reuse_and_preserves_host_key_verification():
    calls = []
    def run(argv):
        calls.append(argv)
        return json.dumps({'token': 'a' * 64, 'connection': PEER})
    assert fresh_ssh('94.130.236.38', 'awendelk', 22, 'a' * 64, run=run)['connection'] == PEER
    argv = calls[0]
    for option in ['ControlMaster=no', 'ControlPath=none', 'ControlPersist=no', 'StrictHostKeyChecking=yes']:
        assert option in argv
    with pytest.raises(FirewallError, match='multiplexing'):
        fresh_ssh('94.130.236.38', 'awendelk', 22, 'a' * 64, common_args='-S /tmp/master', run=run)


def test_drift_after_probe_cannot_be_confirmed(firewall):
    transaction, _, live, _ = firewall
    token = begin(firewall)['token']
    live['table'] = 'Unexpected rules from another process'
    with pytest.raises(FirewallError, match='drift'):
        transaction.confirm(token, {'token': token, 'connection': '203.0.113.10 40001 94.130.236.38 22'})
    assert transaction.pending.exists()
    transaction.rollback(token)
    assert live['table'] == OLD


def test_wall_clock_rollback_cannot_extend_confirmation_deadline(firewall):
    transaction, _, live, _ = firewall
    transaction.monotonic = lambda: live['time']
    token = begin(firewall)['token']
    live['time'] = 91
    transaction.now = lambda: -1000
    with pytest.raises(FirewallError, match='deadline expired'):
        transaction.confirm(token, {'token': token, 'connection': '203.0.113.10 40001 94.130.236.38 22'})
    assert live['table'] == OLD


def test_firewall_check_mode_creates_no_transaction_files_or_timer(firewall):
    transaction, _, live, calls = firewall
    assert begin(firewall, check_mode=True)['changed']
    assert not transaction.directory.exists()
    assert live['table'] == OLD
    assert not any(c[0] == 'systemd-run' or c[:2] == ['nft', '--file'] for c in calls)
