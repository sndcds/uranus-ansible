import importlib.util
import json
from pathlib import Path
import pytest
from conftest import ROOT

@pytest.fixture
def firewall(tmp_path):
    spec=importlib.util.spec_from_file_location('firewall',ROOT/'roles/host_firewall/files/firewall.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.STATE=tmp_path/'state';module.CANDIDATE=tmp_path/'candidate.nft';module.PERSIST=tmp_path/'confirmed.nft'
    module.CANDIDATE.write_text('destroy table inet uranus_host\ntable inet uranus_host {}\n')
    module.PERSIST.write_text('previous confirmed rules')
    module.calls=[];module.live='previous live rules';module.fail=False
    def run(args):
        module.calls.append(args)
        if args==['nft','--json','list','tables']:
            return json.dumps({'nftables':[{'table':{'family':'inet','name':'uranus_host'}},{'table':{'family':'ip','name':'incus'}}]})
        if args[:3]==['nft','list','table']:return module.live
        if args[:2]==['nft','--file']:
            if args[-1]==str(module.STATE/'applied.nft') and module.fail:raise RuntimeError('Apply failed')
            module.live=Path(args[-1]).read_text()
        return ''
    module.run=run
    return module

def test_rollback_is_armed_before_live_rules_change(firewall):
    firewall.transact('begin')
    timer=next(i for i,c in enumerate(firewall.calls) if c[0]=='systemd-run')
    apply=next(i for i,c in enumerate(firewall.calls) if c[:2]==['nft','--file'])
    assert timer<apply
    assert firewall.PERSIST.read_text()=='previous confirmed rules'

def test_failed_fresh_ssh_connection_rolls_back_just_our_table(firewall):
    firewall.transact('begin');firewall.transact('rollback')
    assert 'previous live rules' in firewall.live
    assert 'flush ruleset' not in firewall.live
    assert 'incus' not in firewall.live
    assert firewall.PERSIST.read_text()=='previous confirmed rules'
    with pytest.raises(RuntimeError,match='expired'):firewall.transact('confirm')

def test_confirm_is_atomic_and_late_timer_does_nothing(firewall):
    transaction=firewall.transact('begin');firewall.transact('confirm',transaction)
    assert firewall.PERSIST.read_text()==firewall.CANDIDATE.read_text()
    before=firewall.live;firewall.transact('rollback');assert firewall.live==before

def test_command_failure_recovers_and_preserves_persistent_rules(firewall):
    firewall.fail=True
    with pytest.raises(RuntimeError,match='Apply failed'):firewall.transact('begin')
    assert 'previous live rules' in firewall.live
    assert firewall.PERSIST.read_text()=='previous confirmed rules'
    assert not (firewall.STATE/'pending').exists()

def test_concurrent_update_cannot_replace_pending_recovery(firewall):
    firewall.transact('begin');before=(firewall.STATE/'rollback.nft').read_text()
    with pytest.raises(RuntimeError,match='Pending'):firewall.transact('begin')
    assert (firewall.STATE/'rollback.nft').read_text()==before


def test_late_old_timer_does_not_undo_next_transaction(firewall):
    old=firewall.transact('begin');firewall.transact('confirm',old)
    new=firewall.transact('begin');before=firewall.live
    firewall.transact('rollback',old)
    assert firewall.live==before and (firewall.STATE/'pending').read_text()==new
    firewall.transact('rollback',new)
    assert not (firewall.STATE/'pending').exists()


def test_candidate_replacement_cannot_change_confirmed_rules(firewall):
    token=firewall.transact('begin');applied=firewall.live
    firewall.CANDIDATE.write_text('concurrent unreviewed candidate')
    firewall.transact('confirm',token)
    assert firewall.PERSIST.read_text()==applied


def test_wrong_candidate_digest_fails_before_live_change(firewall):
    with pytest.raises(RuntimeError,match='concurrently'):
        firewall.transact('begin','wrong-checksum')
    assert firewall.live=='previous live rules' and not firewall.calls


def test_wrong_confirmation_cannot_promote_pending_rules(firewall):
    firewall.transact('begin')
    with pytest.raises(RuntimeError,match='Wrong firewall'):
        firewall.transact('confirm','another-transaction')
    assert firewall.PERSIST.read_text()=='previous confirmed rules'


def test_unregistered_existing_table_is_preserved(firewall):
    firewall.PERSIST.unlink()
    with pytest.raises(RuntimeError,match='ownership'):
        firewall.transact('begin')
    assert firewall.live=='previous live rules'
    assert not (firewall.STATE/'pending').exists()
