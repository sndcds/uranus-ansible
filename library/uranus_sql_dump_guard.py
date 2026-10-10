#!/usr/bin/python
"""Reject unsafe psql commands in initial application dumps."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_debian13 import SafetyError, validate_sql_dump

DOCUMENTATION = r'''
---
module: uranus_sql_dump_guard
short_description: Reject psql escapes and global database operations in initial dumps
description: Streams a dump without modifying it and refuses unsafe psql commands.
author: Uranus contributors
options:
  path:
    description: Local path on the managed database host.
    required: true
    type: path
supports_check_mode: true
'''
EXAMPLES = r'''
- name: Verify initial dump
  uranus_sql_dump_guard:
    path: /var/lib/postgresql/uranus_dev.initial.sql
'''
RETURN = r'''
changed:
  description: Always false
  returned: always
  type: bool
'''


def main():
    module = AnsibleModule(argument_spec={'path': dict(type='path', required=True)}, supports_check_mode=True)
    try:
        validate_sql_dump(module.params['path'])
        module.exit_json(changed=False)
    except (SafetyError, OSError, ValueError) as exc:
        module.fail_json(msg=str(exc))


if __name__ == '__main__':
    main()
