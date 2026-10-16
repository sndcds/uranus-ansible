"""Exercise dashboard SPA routes and its separate API upstream with real nginx."""
import http.client
import socket
import ssl
import subprocess
import time

import pytest


@pytest.fixture
def dashboard_server(render, tmp_path, request):
    key, cert = tmp_path / 'key.pem', tmp_path / 'cert.pem'
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(key), '-out', str(cert), '-days', '1',
                    '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'],
                   check=True, capture_output=True)
    sockets = [socket.socket() for _ in range(2)]
    for listener in sockets:
        listener.bind(('127.0.0.1', 0))
    port, backend = [s.getsockname()[1] for s in sockets]
    public = tmp_path / 'dashboard'
    (public / 'assets').mkdir(parents=True)
    (public / 'index.html').write_text('<html><div id="app">dashboard fixture</div></html>')
    (public / 'assets/app.js').write_text('window.dashboardLoaded = true;')
    text = render('roles/debian13_guest_web/templates/guest.conf.j2',
                  instance_role='dev', ansible_host='127.0.0.1',
                  frontend_runtime='node', frontend_port=backend,
                  frontend_domain='dev.example.test', backend_domain='api.dev.example.test',
                  backend_port=backend, dashboard_enabled=True,
                  dashboard_domain='app.dev.example.test', **getattr(request, 'param', {}))
    for before, after in {
        '127.0.0.1:443': f'127.0.0.1:{port}',
        '/etc/ssl/certs/uranus-instance.pem': str(cert),
        '/etc/ssl/private/uranus-instance.key': str(key),
        '/opt/uranus/dashboard/current': str(public),
    }.items():
        text = text.replace(before, after)
    text += f'''
server {{
    listen 127.0.0.1:{backend};
    location /api/ {{
        default_type application/json;
        return 200 '{{"uri":"$request_uri","origin":"$http_origin","proto":"$http_x_forwarded_proto"}}';
    }}
    location = /api/missing {{ return 404 '{{"error":"missing"}}'; }}
    location / {{ return 200 'existing Kulturbytes client'; }}
}}
'''
    paths = '\n'.join(f'{name}_temp_path {tmp_path}/{name};'
                      for name in ['client_body', 'proxy', 'fastcgi', 'uwsgi', 'scgi'])
    config = tmp_path / 'nginx.conf'
    config.write_text(f'pid {tmp_path}/nginx.pid;\nerror_log stderr;\nevents {{}}\n'
                      f'http {{\naccess_log off;\n{paths}\n{text}\n}}\n')
    for listener in sockets:
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
                with socket.create_connection(('127.0.0.1', port), timeout=0.1):
                    break
            except OSError:
                if time.monotonic() > deadline:
                    pytest.fail('Dashboard nginx did not start')
                time.sleep(0.02)

        def request(path, host='app.dev.example.test', method='GET', origin=None, body=None, declared_size=None):
            connection = http.client.HTTPSConnection('localhost', port,
                            context=ssl.create_default_context(cafile=str(cert)), timeout=5)
            headers = {'Host': host}
            if origin:
                headers['Origin'] = origin
            if declared_size is not None:
                headers['Content-Length'] = str(declared_size)
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            result = response.status, response.read().decode(), dict(response.getheaders())
            connection.close()
            return result
        yield request
    finally:
        process.terminate()
        process.communicate(timeout=5)


@pytest.mark.parametrize('path', ['/', '/app/login', '/admin/events'])
def test_dashboard_deep_links_serve_the_spa(dashboard_server, path):
    status, body, headers = dashboard_server(path)
    assert status == 200 and 'id="app"' in body
    assert headers['Cache-Control'] == 'no-cache'


def test_dashboard_assets_and_api_never_fall_back_to_html(dashboard_server):
    assert dashboard_server('/assets/app.js')[:2] == (200, 'window.dashboardLoaded = true;')
    status, body, _ = dashboard_server('/assets/missing.js')
    assert status == 404 and 'id="app"' not in body
    status, body, _ = dashboard_server('/api/missing')
    assert status == 404 and body == '{"error":"missing"}'


@pytest.mark.parametrize('origin', ['https://app.dev.example.test', 'https://foreign.example.test'])
def test_dashboard_api_preserves_browser_origin_for_backend_csrf(dashboard_server, origin):
    import json
    status, body, _ = dashboard_server('/api/admin/refresh?fixture=1', method='POST', origin=origin)
    assert status == 200
    assert json.loads(body) == {'uri': '/api/admin/refresh?fixture=1', 'origin': origin, 'proto': 'https'}


def test_dashboard_does_not_replace_existing_client(dashboard_server):
    assert dashboard_server('/', host='dev.example.test')[:2] == (200, 'existing Kulturbytes client')


@pytest.mark.parametrize('dashboard_server', [
    {'backend_pluto_image_max_file_size': 2},
    {'backend_pluto_image_max_file_size': 20},
    {'backend_pluto_image_max_file_size': 32},
], indirect=True)
def test_guest_accepts_a_full_size_file_with_multipart_overhead(dashboard_server, request):
    limit = request.node.callspec.params['dashboard_server']['backend_pluto_image_max_file_size']
    body = (b'--fixture\r\nContent-Disposition: form-data; name="file"; filename="image.bin"\r\n\r\n'
            + b'x' * (limit * 1048576) + b'\r\n--fixture--\r\n')
    for domain in ['app.dev.example.test', 'api.dev.example.test', 'dev.example.test']:
        assert dashboard_server('/api/upload-fixture', host=domain, method='PUT', body=body)[0] == 200
        assert dashboard_server('/api/upload-fixture', host=domain, method='PUT',
                                declared_size=(limit + 1) * 1048576 + 1)[0] == 413
