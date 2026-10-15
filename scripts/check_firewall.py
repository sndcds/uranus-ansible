#!/usr/bin/env python3
"""Native nftables parse-only tests; run in a disposable privileged network namespace."""
from pathlib import Path
import subprocess
import tempfile
from jinja2 import Environment,StrictUndefined
import yaml

ROOT=Path(__file__).resolve().parents[1]

def main():
    settings=yaml.safe_load((ROOT/'environments/hetzner/group_vars/all.yml').read_text())
    jinja=Environment(undefined=StrictUndefined)
    with tempfile.TemporaryDirectory(prefix='uranus-nft-parser-') as name:
        for role in ['host','db','dev','prod','monitoring','nominatim','versatiles','ingress']:
            source='roles/host_firewall/templates/host-firewall.nft.j2' if role=='host' else 'roles/debian13_guest/templates/firewall.nft.j2'
            context={**settings,'instance_role':role}
            file=Path(name)/f'{role}.nft'
            file.write_text(jinja.from_string((ROOT/source).read_text()).render(context))
            result=subprocess.run(['nft','--check','--file',str(file)],text=True,capture_output=True)
            if result.returncode:raise RuntimeError(role+': '+result.stdout+result.stderr)
            print('PASS: native nftables configuration for '+role)
if __name__=='__main__':main()
