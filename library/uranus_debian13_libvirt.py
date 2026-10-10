#!/usr/bin/python
"""Create missing Debian guests; never replace domains or their storage."""
from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.uranus_debian13 import Provisioner, SafetyError, locked_apply

DOCUMENTATION = r'''
---
module: uranus_debian13_libvirt
short_description: Safely provision dedicated Debian 13 libvirt guests
description: Creates only missing resources, rejects collisions and drift, and preserves all existing VM disks.
author: Uranus contributors
options:
  state:
    description: Plan without writes or apply the validated plan.
    choices: [planned, present]
    default: present
    type: str
  vms:
    description: VM resource definitions and stable network identities.
    required: true
    type: list
    elements: dict
  network_xml:
    description: Dedicated private NAT network with DHCP reservations.
    required: true
    type: str
  image:
    description: Immutable base qcow2 under the protected storage directory.
    type: path
  image_sha512:
    description: Pinned SHA512 digest for the base image.
    type: str
  seeds:
    description: Per-VM cloud-init user_data, meta_data and network_config.
    type: dict
    default: {}
  start_existing:
    description: Explicitly start previously stopped managed guests.
    type: bool
    default: false
supports_check_mode: true
'''
EXAMPLES = r'''
- name: Plan provisioning
  uranus_debian13_libvirt:
    state: planned
    vms: "{{ hetzner_vms }}"
    network_xml: "{{ lookup('template', 'network.xml.j2') }}"
'''
RETURN = r'''
new_vms:
  description: Guests absent at preflight time
  returned: success
  type: list
  elements: str
'''


def main():
    module = AnsibleModule(argument_spec=dict(
        state=dict(type="str", choices=["planned", "present"], default="present"),
        vms=dict(type="list", elements="dict", required=True),
        network_xml=dict(type="str", required=True), image=dict(type="path"),
        image_sha512=dict(type="str"), seeds=dict(type="dict", default={}, no_log=True),
        start_existing=dict(type="bool", default=False)), supports_check_mode=True)
    p = module.params
    try:
        provisioner = Provisioner()
        if p["state"] == "planned":
            result = dict(changed=False, **provisioner.plan(p["vms"], p["network_xml"]))
        elif module.check_mode:
            result = provisioner.apply(p["vms"], p["network_xml"], p["image"], p["image_sha512"], p["seeds"], check_mode=True)
        else:
            result = locked_apply(provisioner, vms=p["vms"], network_xml=p["network_xml"],
                                  image=p["image"], checksum=p["image_sha512"], seeds=p["seeds"],
                                  start_existing=p["start_existing"])
        module.exit_json(**result)
    except (SafetyError, OSError, ValueError, KeyError, AttributeError) as exc:
        module.fail_json(msg=str(exc), recovery="Preserve all disks and domains; inspect and recover manually before retrying.")


if __name__ == "__main__":
    main()
