#!/usr/bin/python3
"""Host watchdog entrypoint; does not depend on the Ansible controller."""
import argparse
import json
import os
import sys

sys.path.insert(0, '/usr/local/lib/uranus')
from uranus_firewall import FirewallTransaction

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['rollback', 'recover'])
    parser.add_argument('--token')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Root privileges are required')
    print(json.dumps(FirewallTransaction().rollback(args.token)))
