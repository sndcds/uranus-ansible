import os
import subprocess
import yaml
import pytest
from conftest import ROOT

@pytest.mark.parametrize('entrypoint',['provision','configure','ingress','postgresql','import-databases'])
@pytest.mark.parametrize('check_mode',[False,True])
def test_default_gate_stops_locally_before_ssh(entrypoint,check_mode,tmp_path):
    inventory=tmp_path/'inventory.yml'
    inventory.write_text('all:\n  vars:\n    ansible_host: 127.0.0.1\n    ansible_port: 1\n  children:\n    incus_hosts:\n      hosts:\n        blocked: {}\n    uranus_instances:\n      hosts:\n        db01: {}\n        nginx01: {}\n')
    env={**os.environ,'ANSIBLE_CONFIG':str(ROOT/'ansible.cfg'),'ANSIBLE_LOCAL_TEMP':str(tmp_path/'ansible')}
    args=['ansible-playbook','-i',str(inventory),str(ROOT/f'playbooks/{entrypoint}.yml')]
    if check_mode:args+=['--check']
    result=subprocess.run(args,capture_output=True,text=True,env=env)
    assert result.returncode==2,result.stdout+result.stderr
    assert 'Production deployment is disabled' in result.stdout
    assert 'unreachable=0' in result.stdout
    assert 'TASK [Gather host facts]' not in result.stdout

def test_every_supported_entrypoint_gates_before_connections(settings):
    assert settings['hetzner_deployment_approved'] is False
    assert settings['uranus_security_review_complete'] is False
    assert settings['hetzner_app_initial_import'] is False
    assert settings['hetzner_nominatim_initial_import'] is False
    for name in ['provision','configure','ingress','postgresql','import-databases']:
        for play in yaml.safe_load((ROOT/f'playbooks/{name}.yml').read_text()):
            assert play['gather_facts'] is False
            assert play['pre_tasks'][0]['ansible.builtin.import_tasks']=='tasks/gate.yml'

def test_ci_has_no_remote_deployment_or_production_secrets():
    text=(ROOT/'.github/workflows/incus.yml').read_text()
    assert 'secrets.' not in text and 'ssh ' not in text
    assert 'hetzner_deployment_approved' not in text

def test_repository_policy():
    import importlib.util
    spec=importlib.util.spec_from_file_location('policy',ROOT/'scripts/check_repository.py')
    policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)
    assert policy.check()>50
