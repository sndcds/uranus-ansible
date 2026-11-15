#!/usr/bin/env python3
"""Forward only public ACME challenges, leaving the live analytics writer in place."""
import argparse
import inspect
import ipaddress
import json
import re
import subprocess


def replace_http_server(text, domain, address):
    ipaddress.IPv4Address(address)
    if not re.fullmatch(r'[a-z0-9.-]+', domain):
        raise ValueError('Invalid domain')
    candidates = []
    for match in re.finditer(r'^server\s*\{', text, re.MULTILINE):
        depth = 1
        end = match.end()
        while depth and end < len(text):
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        if depth:
            raise ValueError('Unbalanced nginx server block')
        block = text[match.start():end]
        names = re.findall(r'\bserver_name\s+([^;]+);', block)
        if names != [domain]:
            raise ValueError('Expected a dedicated Plausible virtual host')
        if re.search(r'\blisten\s+(?:\[::\]:)?80\s*;', block):
            candidates.append((match.start(), end))
    if len(candidates) != 1:
        raise ValueError('Expected exactly one dedicated HTTP server')
    replacement = '''server {
    listen 80;
    listen [::]:80;
    server_name DOMAIN;
    location ^~ /.well-known/acme-challenge/ {
        proxy_pass http://ADDRESS;
        proxy_set_header Host DOMAIN;
    }
    location / { return 301 https://DOMAIN$request_uri; }
}'''.replace('DOMAIN', domain).replace('ADDRESS', address)
    start, end = candidates[0]
    return text[:start] + replacement + text[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', default='awendelk@webserver')
    parser.add_argument('--control-path', required=True)
    parser.add_argument('--domain', required=True)
    parser.add_argument('--ingress-ipv4', required=True)
    args = parser.parse_args()
    payload = 'import ipaddress,re,json,datetime,subprocess\nfrom pathlib import Path\n'
    payload += inspect.getsource(replace_http_server)
    payload += '\ndomain,address = ' + repr((args.domain, args.ingress_ipv4)) + '\n'
    payload += '''
path = Path('/etc/nginx/sites-available/plausible')
old = path.read_text()
new = replace_http_server(old, domain, address)
result = {'changed': False}
if new != old:
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = Path('/var/backups/plausible-challenge-' + stamp + '.conf')
    backup.write_text(old)
    backup.chmod(0o600)
    try:
        path.write_text(new)
        subprocess.run(['nginx', '-t'], check=True, capture_output=True)
        subprocess.run(['systemctl', 'reload', 'nginx'], check=True, capture_output=True)
    except Exception:
        path.write_text(old)
        subprocess.run(['systemctl', 'reload', 'nginx'], capture_output=True)
        raise
    result = {'changed': True, 'backup': str(backup)}
print(json.dumps(result))
'''
    result = subprocess.run(['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ControlPath=' + args.control_path,
                             args.source, 'sudo -n python3 -'], input=payload, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('ACME forwarding failed: ' + result.stderr)
    print(result.stdout.strip())


if __name__ == '__main__':
    main()
