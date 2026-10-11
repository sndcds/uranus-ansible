#!/usr/bin/python
"""Read-only safety guard for Ansible's Incus CLI tasks."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_incus import preflight, SafetyError
DOCUMENTATION = r'''
---
module: uranus_incus_guard
short_description: Validate Incus resources without modifying them
description: Refuses resource drift, unsafe APIs, storage faults, address collisions and orphaned data.
author: Uranus contributors
options:
  instances:
    type: list
    elements: dict
    required: true
    description: Complete desired instance layout.
  images:
    type: dict
    required: true
    description: Full pinned image fingerprints by type.
  reserve_gib:
    type: int
    default: 160
    description: Required backup and snapshot headroom.
  quotas:
    type: bool
    default: false
    description: Require existing ext4 project quotas for containers.
'''
EXAMPLES = r'''
- name: Validate before Incus commands
  uranus_incus_guard:
    instances: "{{ incus_instances }}"
    images: "{{ incus_images }}"
'''
RETURN = r'''
new_instances:
  description: Missing instances eligible for creation.
  type: list
  returned: success
'''
def main():
    module=AnsibleModule(argument_spec={'instances':{'type':'list','elements':'dict','required':True},
        'images':{'type':'dict','required':True},'reserve_gib':{'type':'int','default':160},
        'quotas':{'type':'bool','default':False}},supports_check_mode=True)
    try:
        module.exit_json(changed=False,**preflight(**module.params))
    except (SafetyError,OSError,ValueError,KeyError,TypeError) as error:
        module.fail_json(msg=str(error))
if __name__=='__main__': main()
