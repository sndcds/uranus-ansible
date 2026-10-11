#!/usr/bin/python
"""Verify public dual-stack DNS before ACME or ingress changes."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_dns import verify_dns

DOCUMENTATION = r'''
---
module: uranus_dns_guard
short_description: Verify expected public A and AAAA records
description: Resolves IPv4 and IPv6 independently and rejects foreign addresses or resolver errors.
author: Uranus contributors
options:
  domain:
    description: Validated public service hostname.
    type: str
    required: true
  ipv4:
    description: Expected public IPv4 address.
    type: str
    required: true
  ipv6:
    description: Expected public IPv6 addresses, empty for IPv4-only DNS.
    type: list
    elements: str
    default: []
  assigned_ipv6:
    description: IPv6 addresses observed on the ingress host.
    type: list
    elements: str
    default: []
supports_check_mode: true
'''
EXAMPLES = r'''
- name: Verify ingress DNS
  uranus_dns_guard:
    domain: app.example.com
    ipv4: 94.130.236.38
    ipv6: []
'''
RETURN = r'''
records:
  description: Separately validated A and AAAA records
  returned: success
  type: dict
'''


def main():
    module = AnsibleModule(argument_spec=dict(domain=dict(type='str', required=True),
        ipv4=dict(type='str', required=True), ipv6=dict(type='list', elements='str', default=[]),
        assigned_ipv6=dict(type='list', elements='str', default=[])),
        supports_check_mode=True)
    try:
        module.exit_json(changed=False, records=verify_dns(**module.params))
    except (ValueError, OSError) as exc:
        module.fail_json(msg=str(exc))


if __name__ == '__main__':
    main()
