#!/usr/bin/python
"""Controller-side authenticated SSH check without connection multiplexing."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_firewall import fresh_ssh, FirewallError

DOCUMENTATION = r'''
---
module: uranus_fresh_ssh
short_description: Verify a new authenticated SSH connection
description: Uses existing authorized keys, strict host keys and disabled multiplexing for the firewall proof.
author: Uranus contributors
options:
  host:
    description: Authorized target host.
    type: str
    required: true
  user:
    description: Existing authorized SSH user.
    type: str
    required: true
  port:
    description: Verified SSH port.
    type: int
    default: 22
  token:
    description: Firewall transaction challenge.
    type: str
    required: true
  private_key:
    description: Existing authorized private key path, otherwise SSH config or agent is used.
    type: path
  common_args:
    description: Existing SSH connection options, including a configured jump host.
    type: str
    default: ''
supports_check_mode: true
'''
EXAMPLES = r'''
- name: Prove fresh SSH access
  uranus_fresh_ssh:
    host: "{{ ansible_host }}"
    user: "{{ ansible_user }}"
    token: "{{ firewall_token }}"
  delegate_to: localhost
  become: false
'''
RETURN = r'''
proof:
  description: Challenge and server-observed new TCP connection
  returned: success
  type: dict
'''


def main():
    module = AnsibleModule(argument_spec=dict(host=dict(type='str', required=True), user=dict(type='str', required=True),
        port=dict(type='int', default=22), token=dict(type='str', required=True), private_key=dict(type='path'),
        common_args=dict(type='str', default='')), supports_check_mode=True)
    try:
        proof = {} if module.check_mode else fresh_ssh(**module.params)
        module.exit_json(changed=False, proof=proof)
    except (FirewallError, OSError, ValueError, KeyError) as exc:
        module.fail_json(msg=str(exc))


if __name__ == '__main__':
    main()
