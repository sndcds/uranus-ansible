#!/usr/bin/python
"""Preserve interrupted application database initialization state."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_initialization import initialize

DOCUMENTATION = r'''
---
module: uranus_initialization_guard
short_description: Claim and complete a database initialization durably
description: Uses exclusive fsynced markers before database creation and never retries interrupted initialization.
author: Uranus contributors
options:
  state_dir:
    description: Existing protected PostgreSQL state directory.
    type: path
    required: true
  database:
    description: Application database identity.
    type: str
    required: true
  state:
    description: Claim before creation or complete after all initialization tasks succeed.
    type: str
    choices: [claimed, completed]
    required: true
  token:
    description: Exclusive initialization claim identifier.
    type: str
  import_requested:
    description: Whether this initialization includes an explicitly requested SQL import.
    type: bool
    default: false
supports_check_mode: true
'''
EXAMPLES = r'''
- name: Claim a new database initialization
  uranus_initialization_guard:
    state_dir: /var/lib/postgresql
    database: uranus_dev
    state: claimed
'''
RETURN = r'''
token:
  description: Exclusive claim identifier
  returned: claimed
  type: str
'''


def main():
    module = AnsibleModule(argument_spec=dict(state_dir=dict(type='path', required=True),
        database=dict(type='str', required=True), state=dict(type='str', choices=['claimed', 'completed'], required=True),
        token=dict(type='str'), import_requested=dict(type='bool', default=False)), supports_check_mode=True)
    try:
        module.exit_json(**initialize(**module.params, check_mode=module.check_mode))
    except (ValueError, OSError) as exc:
        module.fail_json(msg=str(exc))


if __name__ == '__main__':
    main()
