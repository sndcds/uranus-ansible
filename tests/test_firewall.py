import importlib.util
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace
import pytest
from conftest import ROOT

@pytest.fixture
def firewall(tmp_path, monkeypatch):
    spec=importlib.util.spec_from_file_location('firewall',ROOT/'roles/host_firewall/files/firewall.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.STATE=tmp_path/'state';module.CANDIDATE=tmp_path/'candidate.nft';module.PERSIST=tmp_path/'confirmed.nft'
    module.SSHD_CONFIG=tmp_path/'ssh/sshd_config'
    module.SSH_CONFIG=tmp_path/'ssh/sshd_config.d/00-uranus-host.conf'
    module.SSH_CONFIG.parent.mkdir(parents=True)
    module.SSHD_CONFIG.write_text(f'Include {module.SSH_CONFIG.parent}/*.conf\n')
    module.SSH_CONFIG.write_text(module.SSH_HEADER+'PasswordAuthentication yes\n')
    module.SSH_CONFIG.chmod(0o640)
    module.SSH_CANDIDATE=tmp_path/'ssh-candidate.conf'
    module.SSH_CANDIDATE.write_text((ROOT/'roles/host_firewall/files/host-ssh.conf').read_text())
    module.SSH_DEFAULTS=tmp_path/'default-ssh'
    monkeypatch.setattr(module.pwd,'getpwnam',lambda name: SimpleNamespace(pw_uid=0 if name in ('root','root-alias') else 1000))
    module.CANDIDATE.write_text('destroy table inet uranus_host\ntable inet uranus_host {}\n')
    module.PERSIST.write_text('previous confirmed rules')
    module.calls=[];module.live='previous live rules';module.fail=False
    module.policy_override={};module.fail_reload=False;module.fail_timer=False
    module.service_command='/usr/sbin/sshd -D $SSHD_OPTS'
    module.service_environment=''
    module.service_environment_files=''
    original_transact=module.transact
    def transact(action,*args,**kwargs):
        kwargs.setdefault('user','operator')
        kwargs.setdefault('connection','198.51.100.7 43210 94.130.236.38 22')
        return original_transact(action,*args,**kwargs)
    module.transact=transact
    def run(args):
        module.calls.append(args)
        if args[0]==module.SSHD and '-T' in args:
            policy={**module.SSH_POLICY,'port':'22',**module.policy_override}
            if not module.SSH_CONFIG.exists() or 'AuthenticationMethods publickey' not in module.SSH_CONFIG.read_text():
                policy['passwordauthentication']='yes'
            return '\n'.join(f'{key} {value}' for key,value in policy.items())+'\n'
        if args[:3]==['systemctl','show','ssh.service']:
            if args[3]=='--property=ExecStart':return '{ argv[]='+module.service_command+' ; }'
            if args[3]=='--property=Environment':return module.service_environment
            if args[3]=='--property=EnvironmentFiles':return module.service_environment_files
        if args[:2]==['systemctl','reload'] and module.fail_reload:
            module.fail_reload=False
            raise RuntimeError('SSH reload failed')
        if args[0]=='systemd-run' and module.fail_timer:
            raise RuntimeError('Timer failed')
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


def test_timer_precedes_ssh_change_and_keys_are_required_before_public_firewall(firewall):
    firewall.transact('begin')
    timer=next(i for i,c in enumerate(firewall.calls) if c[0]=='systemd-run')
    ssh_reload=next(i for i,c in enumerate(firewall.calls) if c[:2]==['systemctl','reload'])
    apply=next(i for i,c in enumerate(firewall.calls) if c[:2]==['nft','--file'])
    assert timer<ssh_reload<apply
    assert firewall.SSH_CONFIG.read_bytes()==firewall.SSH_CANDIDATE.read_bytes()


def test_rollback_restores_ssh_bytes_and_permissions(firewall):
    previous=firewall.SSH_CONFIG.read_bytes()
    firewall.transact('begin');firewall.transact('rollback')
    assert firewall.SSH_CONFIG.read_bytes()==previous
    assert firewall.SSH_CONFIG.stat().st_mode & 0o777 == 0o640
    assert ['systemctl','reload','ssh.service'] in firewall.calls


def test_failed_firewall_recovery_retains_key_only_ssh(firewall):
    firewall.transact('begin')
    original_run=firewall.run
    def run(args):
        if args==['nft','--file',str(firewall.STATE/'rollback.nft')]:
            raise RuntimeError('nft unavailable')
        return original_run(args)
    firewall.run=run
    with pytest.raises(RuntimeError,match='retain key-only SSH'):firewall.transact('rollback')
    assert firewall.SSH_CONFIG.read_bytes()==firewall.SSH_CANDIDATE.read_bytes()
    assert (firewall.STATE/'pending').exists()


def test_first_ssh_dropin_is_removed_by_rollback(firewall):
    firewall.SSH_CONFIG.unlink()
    firewall.transact('begin');firewall.transact('rollback')
    assert not firewall.SSH_CONFIG.exists()


def test_boot_recovery_handles_inactive_ssh_and_restores_confirmation_interruption(firewall):
    previous=firewall.SSH_CONFIG.read_bytes()
    firewall.transact('begin')
    firewall.PERSIST.write_text('new rules written just before controller interruption')
    original_run=firewall.run
    def run(args):
        if args[:2]==['systemctl','is-active']:
            raise subprocess.CalledProcessError(3,args)
        return original_run(args)
    firewall.run=run
    firewall.transact('rollback')
    assert firewall.SSH_CONFIG.read_bytes()==previous
    assert firewall.PERSIST.read_text()=='previous confirmed rules'
    assert not (firewall.STATE/'pending').exists()


def test_failed_ssh_reload_recovers_before_opening_firewall(firewall):
    previous=firewall.SSH_CONFIG.read_bytes();firewall.fail_reload=True
    with pytest.raises(RuntimeError,match='SSH reload failed'):firewall.transact('begin')
    assert firewall.SSH_CONFIG.read_bytes()==previous
    assert 'previous live rules' in firewall.live
    assert not any(c==['nft','--file',str(firewall.STATE/'applied.nft')] for c in firewall.calls)


def test_missing_timer_never_opens_public_ssh(firewall):
    previous=firewall.SSH_CONFIG.read_bytes();firewall.fail_timer=True
    with pytest.raises(RuntimeError,match='Timer failed'):firewall.transact('begin')
    assert firewall.SSH_CONFIG.read_bytes()==previous
    assert not any(c==['nft','--file',str(firewall.STATE/'applied.nft')] for c in firewall.calls)


@pytest.mark.parametrize('key,value',[('authenticationmethods','any'),('passwordauthentication','yes'),('kbdinteractiveauthentication','yes'),('permitrootlogin','prohibit-password'),('pubkeyauthentication','no'),('port','2222')])
def test_effective_policy_conflicts_never_expose_public_ssh(firewall,key,value):
    previous=firewall.SSH_CONFIG.read_bytes();firewall.policy_override={key:value}
    with pytest.raises(RuntimeError,match='Effective SSH policy'):firewall.transact('begin')
    assert firewall.SSH_CONFIG.read_bytes()==previous
    assert not any(c==['nft','--file',str(firewall.STATE/'applied.nft')] for c in firewall.calls)


def test_existing_match_rule_in_nested_include_stops_before_any_mutation(firewall):
    extra=firewall.SSH_CONFIG.parent/'custom.conf'
    extra.write_text('Match User another-admin\n  PasswordAuthentication yes\n')
    previous=firewall.SSH_CONFIG.read_bytes()
    with pytest.raises(RuntimeError,match='Match rules'):firewall.transact('begin')
    assert firewall.SSH_CONFIG.read_bytes()==previous and firewall.live=='previous live rules'
    assert not (firewall.STATE/'pending').exists()


def test_recursive_include_is_rejected(firewall):
    firewall.SSHD_CONFIG.write_text(f'Include={firewall.SSHD_CONFIG}\n')
    with pytest.raises(RuntimeError,match='Recursive SSH Include'):firewall.transact('begin')
    assert firewall.live=='previous live rules'


@pytest.mark.parametrize('command',['/usr/sbin/sshd -D -o PasswordAuthentication=yes','/usr/sbin/sshd -D -f /etc/ssh/other.conf'])
def test_custom_service_cannot_bypass_ssh_policy(firewall,command):
    firewall.service_command=command
    with pytest.raises(RuntimeError,match='service command'):firewall.transact('begin')
    assert firewall.live=='previous live rules'


def test_service_environment_cannot_enable_passwords(firewall):
    firewall.service_environment='"SSHD_OPTS=-o PasswordAuthentication=yes"'
    with pytest.raises(RuntimeError,match='SSHD_OPTS'):firewall.transact('begin')


def test_default_environment_file_cannot_override_audited_config(firewall):
    firewall.SSH_DEFAULTS.write_text('SSHD_OPTS="-f /etc/ssh/unsafe.conf"\n')
    with pytest.raises(RuntimeError,match='SSHD_OPTS'):firewall.transact('begin')


def test_existing_unmanaged_dropin_is_preserved(firewall):
    firewall.SSH_CONFIG.write_text('PasswordAuthentication yes\n')
    with pytest.raises(RuntimeError,match='Unmanaged SSH drop-in'):firewall.transact('begin')
    assert firewall.SSH_CONFIG.read_text()=='PasswordAuthentication yes\n'
    assert firewall.live=='previous live rules'


@pytest.mark.parametrize('user',['root','root-alias'])
def test_root_accounts_cannot_be_locked_out_by_hardening(firewall,user):
    with pytest.raises(RuntimeError,match='Root SSH'):firewall.transact('begin',user=user)
    assert firewall.live=='previous live rules'


def test_ssh_candidate_checksum_is_verified_before_changes(firewall):
    with pytest.raises(RuntimeError,match='concurrently'):firewall.transact('begin',ssh_checksum='wrong-checksum')
    assert firewall.live=='previous live rules' and not firewall.calls


def test_unconfirmed_ssh_policy_cannot_be_modified_or_promoted(firewall):
    token=firewall.transact('begin')
    firewall.SSH_CONFIG.write_text(firewall.SSH_HEADER+'PasswordAuthentication yes\n')
    with pytest.raises(RuntimeError,match='changed during'):firewall.transact('confirm',token)
    assert firewall.PERSIST.read_text()=='previous confirmed rules'
    assert (firewall.STATE/'pending').exists()


def test_audit_repetition_is_read_only_and_detects_drift(firewall):
    assert firewall.transact('audit')=='change'
    token=firewall.transact('begin');firewall.transact('confirm',token)
    before=firewall.SSH_CONFIG.stat().st_mtime_ns
    assert firewall.transact('audit')=='current'
    assert firewall.SSH_CONFIG.stat().st_mtime_ns==before
    firewall.policy_override={'passwordauthentication':'yes'}
    assert firewall.transact('audit')=='change'


@pytest.mark.parametrize('source',['198.51.100.8','203.0.113.20','2001:db8:abcd::123'])
def test_changing_ipv4_and_ipv6_sources_need_no_allowlist(firewall,source):
    assert firewall.transact('audit',connection=f'{source} 43210 94.130.236.38 22')=='change'


def test_access_role_uses_fresh_key_connections_and_installs_boot_recovery():
    import yaml
    tasks=yaml.safe_load((ROOT/'roles/host_firewall/tasks/main.yml').read_text())
    inventory=yaml.safe_load((ROOT/'environments/hetzner/inventory.yml').read_text())
    args=inventory['all']['vars']['ansible_ssh_extra_args']
    assert 'PreferredAuthentications=publickey' in args
    assert 'PasswordAuthentication=no' in args and 'KbdInteractiveAuthentication=no' in args
    resets=[i for i,t in enumerate(tasks) if t.get('ansible.builtin.meta')=='reset_connection']
    first_write=next(i for i,t in enumerate(tasks) if 'ansible.builtin.file' in t)
    assert resets[0]<first_write
    stop=next(i for i,t in enumerate(tasks) if t['name']=='Stop before overwriting an unconfirmed candidate')
    helper=next(i for i,t in enumerate(tasks) if t.get('ansible.builtin.copy',{}).get('src')=='firewall.py')
    assert stop<helper
    recovery=next(t['ansible.builtin.copy']['content'] for t in tasks if t.get('ansible.builtin.copy',{}).get('dest')=='/etc/systemd/system/ssh.service.d/uranus-access-recovery.conf')
    assert 'Requires=uranus-access-recovery.service' in recovery and 'After=uranus-access-recovery.service' in recovery
