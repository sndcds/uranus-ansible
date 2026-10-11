#!/usr/bin/python
"""Verify the dedicated host's storage without changing it."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_safety import SafetyError, storage_guard

DOCUMENTATION = r'''
---
module: uranus_storage_guard
short_description: Require the dedicated host's exact writable data filesystem
description: Checks the mount UUID, read-write state, nested mounts and symlinks. Never mounts or repairs storage.
author: Uranus contributors
options: {}
supports_check_mode: true
'''
EXAMPLES = r'''
- name: Verify protected storage
  uranus_storage_guard: {}
'''
RETURN = r'''
mount:
  description: Verified mount metadata
  returned: success
  type: dict
'''


def main():
    module = AnsibleModule(argument_spec={}, supports_check_mode=True)
    try:
        module.exit_json(changed=False, mount=storage_guard())
    except (SafetyError, OSError, ValueError, KeyError) as exc:
        module.fail_json(msg=str(exc))


if __name__ == "__main__":
    main()
