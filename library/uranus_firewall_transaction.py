#!/usr/bin/python
"""Ansible boundary for the host-side firewall watchdog."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_firewall import FirewallTransaction, FirewallError

DOCUMENTATION = r'''
---
module: uranus_firewall_transaction
short_description: Apply firewall changes with automatic rollback
description: Arms a host-side timer before changes and requires fresh SSH proof before committing.
author: Uranus contributors
options:
  state:
    description: Prepare, confirm or rollback a firewall transaction.
    type: str
    required: true
    choices: [prepared, confirmed, rolled_back]
  candidate:
    description: Validated nftables candidate file.
    type: path
  connection:
    description: Server-observed SSH_CONNECTION before changes.
    type: str
  networks:
    description: Authorized management CIDRs.
    type: list
    elements: str
    default: []
  timeout:
    description: Host watchdog timeout in seconds.
    type: int
    default: 90
  token:
    description: Transaction correlation token.
    type: str
  proof:
    description: Fresh SSH challenge response.
    type: dict
    default: {}
supports_check_mode: true
'''
EXAMPLES = r'''
- name: Roll back a pending transaction
  uranus_firewall_transaction:
    state: rolled_back
    token: "{{ firewall_token }}"
'''
RETURN = r'''
token:
  description: Correlates preparation, fresh SSH and confirmation
  returned: prepared
  type: str
'''


def main():
    module = AnsibleModule(argument_spec=dict(
        state=dict(type='str', choices=['prepared', 'confirmed', 'rolled_back'], required=True),
        candidate=dict(type='path'), connection=dict(type='str'), networks=dict(type='list', elements='str', default=[]),
        timeout=dict(type='int', default=90), token=dict(type='str'), proof=dict(type='dict', default={})),
        supports_check_mode=True)
    p = module.params
    try:
        transaction = FirewallTransaction()
        if p['state'] == 'prepared':
            result = transaction.begin(p['candidate'], p['connection'], p['networks'], p['timeout'], module.check_mode)
        elif module.check_mode:
            result = {'changed': False}
        elif p['state'] == 'confirmed':
            result = transaction.confirm(p['token'], p['proof'])
        else:
            result = transaction.rollback(p['token'])
        module.exit_json(**result)
    except (FirewallError, OSError, ValueError, KeyError, TypeError) as exc:
        module.fail_json(msg=str(exc))


if __name__ == '__main__':
    main()
