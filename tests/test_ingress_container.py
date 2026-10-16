"""Exercise container ingress with real nginx, TLS and Incus PROXY headers."""
import ipaddress
import re
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


@pytest.mark.parametrize('role', ['dev', 'prod', 'monitoring', 'nominatim', 'versatiles', 'analytics'])
def test_application_firewalls_only_accept_https_from_ingress(role, render):
    firewall = render('roles/debian13_guest/templates/firewall.nft.j2', instance_role=role)
    web_rules = [line.strip() for line in firewall.splitlines() if 'dport 443' in line]
    assert web_rules == ['ip saddr 10.77.0.17 tcp dport 443 accept']
    monitoring = render('roles/debian13_guest/templates/firewall.nft.j2', instance_role='monitoring')
    assert '10.77.0.17 } tcp dport 5665 accept' in monitoring


@pytest.fixture
def ingress_server(render, tmp_path, request):
    key, cert = tmp_path / 'key.pem', tmp_path / 'cert.pem'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=fixture',
                    '-addext', 'subjectAltName=DNS:fixture,DNS:public.example.test,DNS:private.example.test,DNS:dashboard.example.test'],
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
                                 ('dev_frontend', 'private.example.test'),
                                 ('dev_dashboard', 'dashboard.example.test'),
                                 ('nominatim', 'nominatim.example.test'),
                                 ('versatiles', 'tiles.example.test')]]
    access_policy = {'hetzner_private_web_networks': ['203.0.113.0/24', '2001:db8:1::/48'],
                     'debian13_ingress_tls_ready': True}
    access_policy.update(getattr(request, 'param', {}))
    text = render('roles/debian13_ingress/templates/ingress.conf.j2',
                  debian13_ingress_sites=sites, **access_policy)
    landing = tmp_path / 'ip-test'
    landing.mkdir()
    (landing / 'index.html').write_text(render('roles/debian13_ingress/templates/ip-test.html.j2', **access_policy))
    (landing / 'map.html').write_text(render('roles/debian13_ingress/templates/ip-map.html.j2'))
    replacements = {
        '127.0.0.1:80 ': f'127.0.0.1:{http_port} ',
        '127.0.0.1:443 ': f'127.0.0.1:{tls_port} ',
        '10.77.0.17:443 ': f'127.0.0.1:{direct_port} ',
        'https://127.0.0.1:443': f'https://127.0.0.1:{upstream_port}',
        '/etc/ssl/certs/uranus-ca.pem': str(cert),
        '/var/www/letsencrypt': str(webroot),
        '/var/www/uranus-ip-test': str(landing),
    }
    for before, after in replacements.items():
        text = text.replace(before, after)
    for site in sites:
        text = text.replace(f'/etc/letsencrypt/live/{site["domain"]}/fullchain.pem', str(cert))
        text = text.replace(f'/etc/letsencrypt/live/{site["domain"]}/privkey.pem', str(key))
    # A real TLS upstream echoes what the application actually receives.
    text += f'''
server {{
    listen 127.0.0.1:{upstream_port} ssl;
    # The fixture emulates a backend; only the ingress limit is under test.
    client_max_body_size 0;
    ssl_certificate {cert};
    ssl_certificate_key {key};
    location / {{
        return 200 "$http_x_real_ip|$http_x_forwarded_for|$http_x_forwarded_proto";
    }}
    location /search {{
        return 200 "$request_uri|$http_host|$http_x_real_ip|$http_x_forwarded_for|$http_x_forwarded_proto";
    }}
    location ~ ^/(assets|tiles)/ {{
        return 200 "$request_uri|$http_host|$http_x_real_ip|$http_x_forwarded_for|$http_x_forwarded_proto";
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
                with socket.create_connection(('127.0.0.1', upstream_port), timeout=0.1):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    pytest.fail('Local nginx did not start')
                time.sleep(0.02)

        def request(client_ip, domain, tls=True, direct=False, path='/', method='GET', body=b'', declared_size=None):
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
                size = len(body) if declared_size is None else declared_size
                connection.sendall(f'{method} {path} HTTP/1.1\r\nHost: {domain}\r\n'
                                   'X-Real-IP: 203.0.113.99\r\n'
                                   'X-Forwarded-For: 203.0.113.99\r\n'
                                   f'Content-Length: {size}\r\nConnection: close\r\n\r\n'.encode())
                if body:
                    connection.sendall(body)
                response = b''
                while chunk := connection.recv(65536):
                    response += chunk
                    headers, separator, response_body = response.partition(b'\r\n\r\n')
                    length = re.search(rb'\r\nContent-Length:\s*(\d+)', headers, re.IGNORECASE)
                    # An early 413 may keep the socket open to discard the unsent body.
                    if separator and length and len(response_body) >= int(length.group(1)):
                        break
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


@pytest.mark.parametrize('ingress_server', [
    {'hetzner_private_sites': [], 'hetzner_private_web_networks': []},
], indirect=True)
def test_explicit_public_policy_opens_formerly_private_sites(ingress_server):
    for client_ip in ['198.51.100.8', '2001:db8:2::8']:
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


def test_parallel_frontend_assets_do_not_exhaust_the_page_or_api_budget(ingress_server):
    client, domain = '198.51.100.28', 'public.example.test'
    for index in range(80):
        prefix = ['/_nuxt/', '/api/image/', '/assets/'][index % 3]
        assert '200 OK' in ingress_server(client, domain, path=prefix + str(index))
    for path in ['/de/veranstaltungen/laender', '/api/events']:
        assert '200 OK' in ingress_server(client, domain, path=path)


def test_dynamic_api_requests_remain_rate_limited(ingress_server):
    from concurrent.futures import ThreadPoolExecutor
    client, domain = '198.51.100.29', 'public.example.test'
    with ThreadPoolExecutor(max_workers=8) as executor:
        responses = list(executor.map(
            lambda index: ingress_server(client, domain, path=f'/api/events?page={index}'),
            range(40)))
    assert any('429 Too Many Requests' in response for response in responses)
    assert '200 OK' in ingress_server(client, domain, path='/_nuxt/app.js')


def test_dashboard_lookup_startup_fits_its_burst_and_sustained_api_remains_limited(ingress_server):
    from concurrent.futures import ThreadPoolExecutor
    client, domain = '203.0.113.30', 'dashboard.example.test'
    with ThreadPoolExecutor(max_workers=12) as executor:
        responses = list(executor.map(
            lambda index: ingress_server(client, domain, path=f'/api/lookup?fixture={index}'),
            range(24)))
        assert all('200 OK' in response for response in responses)
        sustained = list(executor.map(
            lambda index: ingress_server(client, domain, path=f'/api/lookup?fixture={index}'),
            range(120)))
    assert any('429 Too Many Requests' in response for response in sustained)


@pytest.mark.parametrize('ingress_server', [
    {'backend_pluto_image_max_file_size': 2},
    {'backend_pluto_image_max_file_size': 20},
    {'backend_pluto_image_max_file_size': 32},
], indirect=True)
def test_ingress_accepts_a_full_size_file_with_multipart_overhead(ingress_server, request):
    limit = request.node.callspec.params['ingress_server']['backend_pluto_image_max_file_size']
    body = (b'--fixture\r\nContent-Disposition: form-data; name="file"; filename="image.bin"\r\n\r\n'
            + b'x' * (limit * 1048576) + b'\r\n--fixture--\r\n')
    for domain in ['public.example.test', 'private.example.test', 'dashboard.example.test']:
        response = ingress_server('203.0.113.31', domain, path='/api/upload-fixture', method='PUT', body=body)
        assert '200 OK' in response
        rejected = ingress_server('203.0.113.31', domain, path='/api/upload-fixture', method='PUT',
                                  declared_size=(limit + 1) * 1048576 + 1)
        assert '413 Request Entity Too Large' in rejected


@pytest.mark.parametrize('ingress_server', [
    {'debian13_ingress_ip_testing': True, 'debian13_ingress_ip_tiles': True,
     'debian13_ingress_tls_ready': False},
], indirect=True)
def test_ip_map_uses_local_assets_and_tiles_with_room_for_map_request_bursts(ingress_server):
    host, client = '94.130.236.38', '198.51.100.8'
    landing = ingress_server(client, host, tls=False)
    assert 'href="/map/"' in landing
    page = ingress_server(client, host, tls=False, path='/map/')
    assert '200 OK' in page and 'Europa entdecken' in page
    assert 'window.location.origin' in page
    assert '302 Moved' in ingress_server(client, host, tls=False, path='/map')
    for path in ['/assets/lib/maplibre-gl/maplibre-gl.js', '/tiles/osm/tiles.json']:
        response = ingress_server(client, host, tls=False, path=path)
        assert '200 OK' in response
        assert response.endswith(f'{path}|tiles.example.test|{client}|{client}|http')
    for index in range(60):
        response = ingress_server(client, host, tls=False, path=f'/tiles/osm/8/{index}/80.pbf')
        assert '200 OK' in response


def test_ip_testing_is_disabled_by_default(ingress_server):
    assert ingress_server('198.51.100.8', '94.130.236.38', tls=False) == ''


@pytest.mark.parametrize('ingress_server', [
    {'debian13_ingress_tls_domains': ['public.example.test']},
], indirect=True)
def test_one_certified_domain_works_while_pending_domains_keep_acme_access(ingress_server):
    assert '200 OK' in ingress_server('198.51.100.8', 'public.example.test')
    with pytest.raises(ssl.SSLError):
        ingress_server('198.51.100.8', 'private.example.test')
    response = ingress_server('198.51.100.8', 'private.example.test', tls=False,
                              path='/.well-known/acme-challenge/token')
    assert '200 OK' in response and response.endswith('acme-token')


@pytest.mark.parametrize('ingress_server', [
    {'debian13_ingress_ip_testing': True, 'debian13_ingress_tls_ready': False},
    {'debian13_ingress_ip_testing': True, 'debian13_ingress_tls_ready': True},
], indirect=True)
def test_ip_http_landing_and_nominatim_work_without_dns_or_public_tls(ingress_server):
    for domain, client_ip in [('94.130.236.38', '198.51.100.8'),
                              ('[2a01:4f8:13b:1405::2]', '2001:db8:2::8')]:
        landing = ingress_server(client_ip, domain, tls=False)
        assert '200 OK' in landing and 'text/html' in landing
        assert 'Nginx ist erreichbar' in landing
        assert 'action="/nominatim/search"' in landing
        assert 'Location:' not in landing
        search = ingress_server(client_ip, domain, tls=False,
                                path='/nominatim/search?q=Flensburg&format=jsonv2')
        assert '200 OK' in search
        assert search.endswith(f'/search?q=Flensburg&format=jsonv2|nominatim.example.test|'
                               f'{client_ip}|{client_ip}|http')
        assert '404 Not Found' in ingress_server(client_ip, domain, tls=False, path='/missing')
    assert ingress_server('198.51.100.8', 'unknown.example.test', tls=False) == ''
    challenge = ingress_server('198.51.100.8', 'public.example.test', tls=False,
                               path='/.well-known/acme-challenge/token')
    assert '200 OK' in challenge and challenge.endswith('acme-token')
