"""Exercise container ingress with real nginx, TLS and Incus PROXY headers."""
import ipaddress
import socket
import ssl
import subprocess
import time

import pytest
import yaml

from conftest import ROOT
from uranus_incus import desired_devices


def test_ingress_instance_template_matches_guard(settings, render):
    instance = next(i for i in settings['incus_instances'] if i['name'] == 'nginx01')
    config = yaml.safe_load(render('roles/incus_instance/templates/instance.yml.j2',
                                  incus_instance=instance, hetzner_ssh_public_key_file='fixture'))
    assert config['devices'] == desired_devices(instance)
    inventory = yaml.safe_load((ROOT / 'environments/hetzner/inventory.yml').read_text())
    assert 'nginx01' in inventory['all']['children']['uranus_instances']['hosts']


@pytest.mark.parametrize('role', ['dev', 'prod', 'monitoring', 'nominatim', 'versatiles'])
def test_application_firewalls_only_accept_https_from_ingress(role, render):
    firewall = render('roles/debian13_guest/templates/firewall.nft.j2', instance_role=role)
    web_rules = [line.strip() for line in firewall.splitlines() if 'dport 443' in line]
    assert web_rules == ['ip saddr 10.77.0.17 tcp dport 443 accept']
    monitoring = render('roles/debian13_guest/templates/firewall.nft.j2', instance_role='monitoring')
    assert '10.77.0.17 } tcp dport 5665 accept' in monitoring


@pytest.fixture
def ingress_server(render, tmp_path):
    key, cert = tmp_path / 'key.pem', tmp_path / 'cert.pem'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=fixture',
                    '-addext', 'subjectAltName=DNS:fixture,DNS:public.example.test,DNS:private.example.test'],
                   check=True, capture_output=True)
    # Reserve all test ports together to avoid duplicate ephemeral allocations.
    listeners = [socket.socket() for _ in range(4)]
    for listener in listeners:
        listener.bind(('127.0.0.1', 0))
    http_port, tls_port, direct_port, upstream_port = [s.getsockname()[1] for s in listeners]
    webroot = tmp_path / 'webroot'
    challenge = webroot / '.well-known/acme-challenge/token'
    challenge.parent.mkdir(parents=True)
    challenge.write_text('acme-token')
    sites = [dict(key=key, domain=domain, instance='fixture', upstream='127.0.0.1')
             for key, domain in [('prod_frontend', 'public.example.test'),
                                 ('dev_frontend', 'private.example.test')]]
    text = render('roles/debian13_ingress/templates/ingress.conf.j2',
                  debian13_ingress_sites=sites, debian13_ingress_tls_ready=True,
                  hetzner_private_web_networks=['203.0.113.0/24', '2001:db8:1::/48'])
    replacements = {
        '127.0.0.1:80 ': f'127.0.0.1:{http_port} ',
        '127.0.0.1:443 ': f'127.0.0.1:{tls_port} ',
        '10.77.0.17:443 ': f'127.0.0.1:{direct_port} ',
        'https://127.0.0.1:443;': f'https://127.0.0.1:{upstream_port};',
        '/etc/letsencrypt/live/uranus-hetzner/fullchain.pem': str(cert),
        '/etc/letsencrypt/live/uranus-hetzner/privkey.pem': str(key),
        '/etc/ssl/certs/uranus-ca.pem': str(cert),
        '/var/www/letsencrypt': str(webroot),
    }
    for before, after in replacements.items():
        text = text.replace(before, after)
    # A real TLS upstream echoes what the application actually receives.
    text += f'''
server {{
    listen 127.0.0.1:{upstream_port} ssl;
    ssl_certificate {cert};
    ssl_certificate_key {key};
    location / {{
        return 200 "$http_x_real_ip|$http_x_forwarded_for|$http_x_forwarded_proto";
    }}
}}
'''
    paths = '\n'.join(f'{name}_temp_path {tmp_path}/{name};'
                      for name in ['client_body', 'proxy', 'fastcgi', 'uwsgi', 'scgi'])
    config = tmp_path / 'nginx.conf'
    config.write_text(f'pid {tmp_path}/nginx.pid;\nerror_log stderr;\nevents {{}}\n'
                      f'http {{\naccess_log off;\n{paths}\n{text}\n}}\n')
    for listener in listeners:
        listener.close()
    process = subprocess.Popen(['nginx', '-p', str(tmp_path), '-c', str(config),
                                '-g', 'daemon off; master_process off;'],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 5
        while True:
            if process.poll() is not None:
                pytest.fail(process.communicate()[1].decode())
            try:
                with socket.create_connection(('127.0.0.1', direct_port), timeout=0.1):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    pytest.fail('Local nginx did not start')
                time.sleep(0.02)

        def request(client_ip, domain, tls=True, direct=False, path='/'):
            port = direct_port if direct else tls_port if tls else http_port
            connection = socket.create_connection(('127.0.0.1', port), timeout=5)
            if not direct:
                family = ipaddress.ip_address(client_ip).version
                destination = '::1' if family == 6 else '127.0.0.1'
                connection.sendall(f'PROXY TCP{family} {client_ip} {destination} 43210 443\r\n'.encode())
            if tls:
                context = ssl.create_default_context(cafile=str(cert))
                connection = context.wrap_socket(connection, server_hostname=domain)
            with connection:
                # Forged HTTP headers must never bypass CIDRs or reach an application.
                connection.sendall(f'GET {path} HTTP/1.1\r\nHost: {domain}\r\n'
                                   'X-Real-IP: 203.0.113.99\r\n'
                                   'X-Forwarded-For: 203.0.113.99\r\n'
                                   'Connection: close\r\n\r\n'.encode())
                response = b''
                while chunk := connection.recv(65536):
                    response += chunk
            return response.decode()
        yield request
    finally:
        process.terminate()
        process.communicate(timeout=5)


@pytest.mark.parametrize('client_ip', ['198.51.100.8', '2001:db8:2::8'])
def test_proxy_client_ip_reaches_tls_upstream_and_private_sites_stay_closed(ingress_server, client_ip):
    public = ingress_server(client_ip, 'public.example.test')
    assert '200 OK' in public
    assert public.endswith(f'{client_ip}|{client_ip}|https')
    private = ingress_server(client_ip, 'private.example.test')
    assert '403 Forbidden' in private


@pytest.mark.parametrize('client_ip', ['203.0.113.8', '2001:db8:1::8'])
def test_allowed_ipv4_and_ipv6_clients_can_reach_private_sites(ingress_server, client_ip):
    response = ingress_server(client_ip, 'private.example.test')
    assert '200 OK' in response
    assert response.endswith(f'{client_ip}|{client_ip}|https')


def test_acme_challenge_and_direct_monitoring_listener(ingress_server):
    challenge = ingress_server('198.51.100.8', 'private.example.test', tls=False,
                               path='/.well-known/acme-challenge/token')
    assert '200 OK' in challenge and challenge.endswith('acme-token')
    monitoring = ingress_server('127.0.0.1', 'public.example.test', direct=True)
    assert '200 OK' in monitoring
    assert monitoring.endswith('127.0.0.1|127.0.0.1|https')
