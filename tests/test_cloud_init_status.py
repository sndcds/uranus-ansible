"""Bound recovery to completed failures of the shared package and SSH bootstrap."""
import importlib.util
from pathlib import Path

import pytest

from conftest import ROOT

spec = importlib.util.spec_from_file_location('cloud_status', ROOT / 'filter_plugins/uranus_cloud_init.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


@pytest.mark.parametrize('status', ['done', 'disabled'])
def test_normal_terminal_status_is_allowed(status):
    assert module.bootstrap_status({'status': status, 'errors': []}) == {
        'allowed': True, 'recover': False, 'modules': [],
    }


def completed_failure():
    errors = [
        "('package-update-upgrade-install', ProcessExecutionError('apt returned 100'))",
        "('scripts-user', RuntimeError('Runparts: 1 failures (runcmd)'))",
    ]
    return {'status': 'error', 'stage': None, 'errors': errors,
            'modules-final': {'errors': errors}}


def test_completed_package_and_ssh_failures_can_be_repaired():
    assert module.bootstrap_status(completed_failure()) == {
        'allowed': True, 'recover': True,
        'modules': ['package-update-upgrade-install', 'scripts-user'],
    }


def test_completed_bootcmd_failure_is_a_candidate_for_verified_dhcp_recovery():
    errors = ["('bootcmd', ProcessExecutionError('early network configuration failed'))"]
    details = {'status': 'error', 'stage': None, 'errors': errors, 'init': {'errors': errors},
               'init-local': {'errors': []}, 'modules-config': {'errors': []},
               'modules-final': {'errors': []}}
    assert module.bootstrap_status(details) == {
        'allowed': True, 'recover': True, 'modules': ['bootcmd'],
    }
    details['init']['errors'] = errors + ["('users-groups', RuntimeError('missing user'))"]
    assert not module.bootstrap_status(details)['allowed']


@pytest.mark.parametrize('commands, expected', [
    ([['sh', '-ec', 'managed DHCP script\n']], True),
    ([['sh', '-ec', 'custom command']], False),
    ([['sh', '-ec', 'managed DHCP script'], ['sh', '-c', 'custom command']], False),
    ([['sh', '-c', 'managed DHCP script']], False),
    ([['sh', '-ec', None]], False),
    ([], False), (None, False),
])
def test_recovery_requires_the_single_exact_managed_bootcmd(commands, expected):
    assert module.managed_bootcmd({'bootcmd': commands}, 'managed DHCP script\n') is expected


@pytest.mark.parametrize('change', ['running', 'unknown', 'init', 'config', 'final-only'])
def test_other_failures_or_incomplete_initialization_are_rejected(change):
    details = completed_failure()
    if change == 'running':
        details['stage'] = 'modules-final'
    elif change == 'unknown':
        details['errors'].append("('users-groups', RuntimeError('missing user'))")
    elif change == 'final-only':
        details['modules-final'] = {'errors': ["('ssh', RuntimeError('key failure'))"]}
    else:
        details['init' if change == 'init' else 'modules-config'] = {'errors': ['early-stage failure']}
    assert not module.bootstrap_status(details)['allowed']


@pytest.mark.parametrize('details', [{'status': 'running', 'errors': []},
                                    {'status': 'not started', 'errors': []}])
def test_unfinished_status_does_not_establish_readiness(details):
    assert not module.bootstrap_status(details)['allowed']


def test_missing_or_malformed_status_is_rejected():
    with pytest.raises(module.AnsibleFilterError):
        module.bootstrap_status({'status': 'done'})
