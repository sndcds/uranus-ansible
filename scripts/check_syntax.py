#!/usr/bin/env python3
"""Parse all playbooks offline, using fixture-only inventories and no SSH."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    env = {**os.environ, 'ANSIBLE_CONFIG': str(ROOT / 'ansible-debian13.cfg'),
           'ANSIBLE_LOCAL_TEMP': os.environ.get('ANSIBLE_LOCAL_TEMP', '/tmp/uranus-ansible-local')}
    with tempfile.TemporaryDirectory(prefix='uranus-syntax-') as directory:
        inventory = Path(directory) / 'inventory.yml'
        inventory.write_text('''---
all:
  vars:
    ansible_connection: local
  children:
    kvm_hosts:
      hosts:
        localhost: {}
    debian13_hypervisors:
      hosts:
        localhost: {}
    debian13_vms:
      hosts:
        db01: {}
        dev01: {}
        prod01: {}
        mon01: {}
        nom01: {}
        vers01: {}
    provisioned_vms:
      hosts: {}
    db:
      hosts: {}
    dev:
      hosts: {}
    prod:
      hosts: {}
    monitoring:
      hosts: {}
    nominatim:
      hosts: {}
    versatiles:
      hosts: {}
''')
        for playbook in sorted((ROOT / 'playbooks').rglob('*.yml')):
            if playbook.parent.name == 'debian13' and playbook.name in ('gate.yml', 'guest-vars.yml'):
                continue
            subprocess.run(['ansible-playbook', '--syntax-check', '-i', str(inventory), str(playbook)],
                           cwd=ROOT, env=env, check=True)


if __name__ == '__main__':
    main()
