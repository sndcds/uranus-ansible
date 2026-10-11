import json
from pathlib import Path
import re
import shutil
import socket
import subprocess

import pytest
import yaml

from conftest import ROOT


def test_private_nat_has_six_stable_reservations_and_no_public_bridge(settings, render):
    import xml.etree.ElementTree as ET
    xml = ET.fromstring(render('roles/debian13_hypervisor/templates/network.xml.j2'))
    assert xml.find('forward').attrib == {'mode': 'nat'}
    assert xml.find('bridge').get('name') == 'virbr-uranus'
    assert len(xml.findall('ip/dhcp/host')) == 6
    assert {h.get('ip') for h in xml.findall('ip/dhcp/host')} == {v['ip'] for v in settings['hetzner_vms']}
    assert not xml.findall("ip[@family='ipv6']")
    assert not xml.findall('forward/interface')


@pytest.mark.parametrize('name', ['db01', 'dev01', 'prod01', 'mon01', 'nom01', 'vers01'])
def test_cloud_init_disables_passwords_and_validates_with_real_schema(name, settings, render, tmp_path):
    vm = next(v for v in settings['hetzner_vms'] if v['name'] == name)
    text = render('roles/debian13_hypervisor/templates/user-data.yml.j2', item=vm, hetzner_ssh_public_key_file='fixture.pub')
    data = yaml.safe_load(text)
    assert data['disable_root'] and data['ssh_pwauth'] is False
    assert data['users'][0]['lock_passwd'] and data['users'][0]['name'] == 'debian'
    assert 'password' not in data
    assert 'qemu-guest-agent' in data['packages']
    path = tmp_path / 'user-data.yml'
    path.write_text(text)
    assert shutil.which('cloud-init'), 'Install cloud-init to validate its actual schema'
    subprocess.run(['cloud-init', 'schema', '-c', str(path)], check=True, capture_output=True, text=True)
    network = render('roles/debian13_hypervisor/templates/network-config.yml.j2', item=vm)
    path.write_text(network)
    subprocess.run(['cloud-init', 'schema', '-t', 'network-config', '-c', str(path)], check=True, capture_output=True, text=True)
    converted = tmp_path / 'debian-network'
    subprocess.run(['cloud-init', 'devel', 'net-convert', '-p', str(path), '-k', 'yaml',
                    '-d', str(converted), '-D', 'debian', '-O', 'eni', '-m', f"ens3,{vm['mac']}"],
                   check=True, capture_output=True, text=True)
    eni = (converted / 'etc/network/interfaces.d/50-cloud-init').read_text()
    assert 'iface ens3 inet dhcp' in eni and re.search(r'accept[-_]ra\s+0', eni)
    rules = (converted / 'etc/udev/rules.d/70-persistent-net.rules').read_text()
    assert vm['mac'] in rules and 'NAME="ens3"' in rules
    metadata = yaml.safe_load(render('roles/debian13_hypervisor/templates/meta-data.yml.j2', item=vm))
    assert metadata['instance-id'] == f'uranus-debian13-{name}-v1'


def nginx_check(text, tmp_path):
    assert shutil.which('nginx'), 'Install nginx for the actual parser check'
    # nginx -t also probes listening sockets. Use temporary, unprivileged
    # loopback ports so the fixtures never bind the production interfaces.
    ports = []
    for _ in range(2):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            ports.append(listener.getsockname()[1])
    def local_listener(match):
        original = match.group(2)
        port = ports[1] if original.endswith('443') else ports[0]
        address = f'[::1]:{port}' if original.startswith('[') else f'127.0.0.1:{port}'
        return match.group(1) + address
    text = re.sub(r'(?m)^(\s*listen\s+)([^ ;]+)', local_listener, text)
    paths = '\n'.join(f'{name}_temp_path {tmp_path}/{name};' for name in ['client_body', 'proxy', 'fastcgi', 'uwsgi', 'scgi'])
    conf = tmp_path / 'nginx.conf'
    conf.write_text(f'pid {tmp_path}/nginx.pid;\nerror_log stderr;\nevents {{}}\nhttp {{\naccess_log off;\n{paths}\n{text}\n}}\n')
    result = subprocess.run(['nginx', '-t', '-p', str(tmp_path), '-c', str(conf)], text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize('role', ['dev', 'prod', 'monitoring', 'nominatim', 'versatiles'])
def test_guest_nginx_is_parseable_and_preserves_tls_forwarding(role, render, tmp_path):
    text = render('roles/debian13_guest_web/templates/guest.conf.j2',
                  vm_role=role, ansible_host='10.77.0.12', frontend_domain='app.example.test',
                  backend_domain='api.example.test', icinga_web_domain='mon.example.test',
                  nominatim_domain='nom.example.test', versatiles_domain='tiles.example.test',
                  backend_port=9090, versatiles_port=8080)
    text = text.replace('include fastcgi_params;', 'include /etc/nginx/fastcgi_params;')
    assert 'listen 443' not in text
    assert 'set_real_ip_from 10.77.0.1;' in text
    if role == 'monitoring':
        assert '/run/php/php8.4-fpm.sock' in text and 'fastcgi_param HTTPS on;' in text
    assert 'X-Forwarded-Proto https;' in text
    nginx_check(text, tmp_path)


@pytest.mark.parametrize('tls', [False, True])
def test_public_ingress_is_parseable_and_enforces_trust_boundary(tls, render, tmp_path):
    sites = [dict(key='prod_frontend', domain='app.example.test', upstream='10.77.0.13'),
             dict(key='dev_frontend', domain='dev.example.test', upstream='10.77.0.12'),
             dict(key='icinga', domain='monitoring.example.test', upstream='10.77.0.14'),
             dict(key='nominatim', domain='nom.example.test', upstream='10.77.0.15')]
    text = render('roles/debian13_ingress/templates/ingress.conf.j2',
                  debian13_ingress_sites=sites, debian13_ingress_tls_ready=tls,
                  hetzner_private_web_networks=['203.0.113.0/24'])
    if tls:
        key, cert = tmp_path / 'key.pem', tmp_path / 'cert.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=example.test'],
                       check=True, capture_output=True)
        text = text.replace('/etc/letsencrypt/live/uranus-hetzner/fullchain.pem', str(cert))
        text = text.replace('/etc/letsencrypt/live/uranus-hetzner/privkey.pem', str(key))
        assert 'TLSv1.2 TLSv1.3' in text and 'ssl_reject_handshake on;' in text
        assert text.count('deny all;') == 2
        assert 'proxy_set_header X-Forwarded-For $remote_addr;' in text
        assert '$proxy_add_x_forwarded_for' not in text
        assert 'proxy_pass http://10.77.0.13:80;' in text
    assert '/.well-known/acme-challenge/' in text
    nginx_check(text, tmp_path)


def test_host_firewall_keeps_libvirt_and_restricts_public_ports(render):
    text = render('roles/debian13_hypervisor/templates/host-firewall.nft.j2', hetzner_management_networks=['203.0.113.10/32'])
    assert 'flush ruleset' not in text
    assert 'destroy table inet uranus_debian13' in text
    assert 'tcp dport { 80, 443 } accept' in text
    assert 'ip saddr { 203.0.113.10/32 } tcp dport 22 accept' in text
    assert '5432' not in text and '8086' not in text and '5665' not in text
    assert 'oifname "virbr-uranus" ct state new drop' in text


@pytest.mark.parametrize('role', ['db', 'dev', 'prod', 'monitoring', 'nominatim', 'versatiles'])
def test_guest_firewall_exposes_web_only_to_gateway_and_database_to_clients(role, render):
    text = render('roles/debian13_guest/templates/firewall.nft.j2', vm_role=role)
    assert 'policy drop' in text
    assert 'ip saddr 10.77.0.1 tcp dport 22 accept' in text
    assert ('tcp dport 5432 accept' in text) == (role == 'db')
    assert ('tcp dport 8086 accept' in text) == (role == 'monitoring')
    assert ('ip saddr 10.77.0.1 tcp dport 80 accept' in text) == (role != 'db')
