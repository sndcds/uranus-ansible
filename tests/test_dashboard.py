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
    documentation = tmp_path / 'documentation'
    (documentation / '_astro').mkdir(parents=True)
    (documentation / 'api-reference').mkdir()
    (documentation / 'index.html').write_text('<html>Uranus Docs</html>')
    (documentation / 'api-reference/index.html').write_text('<html>API reference</html>')
    (documentation / '_astro/app.js').write_text('window.docsLoaded = true;')
    manual = tmp_path / 'manual'
    (manual / '_astro').mkdir(parents=True)
    (manual / 'img').mkdir()
    (manual / '_astro/app.js').write_text('window.manualLoaded = true;')
    (manual / 'img/sign-up.png').write_text('manual image fixture')
    for locale in ['en', 'de', 'da']:
        (manual / locale / 'event-edit').mkdir(parents=True)
        (manual / locale / 'index.html').write_text(f'<html>Manual {locale}</html>')
        (manual / locale / 'event-edit/index.html').write_text(f'<html>Events {locale}</html>')
    (manual / 'en/event-edit.md').write_text('# Events')
    text = render('roles/debian13_guest_web/templates/guest.conf.j2',
                  instance_role='dev', ansible_host='127.0.0.1',
                  frontend_runtime='node', frontend_port=backend,
                  frontend_domain='dev.example.test', backend_domain='api.dev.example.test',
                  backend_port=backend, dashboard_enabled=True,
                  documentation_enabled=True, documentation_domain='docs.example.test',
                  documentation_dist=str(documentation),
                  manual_enabled=True, manual_domain='manual.example.test', manual_dist=str(manual),
                  debian13_guest_web_manual_redirects=[{'from': path, 'to': '/en' + ('' if path == '/' else path), 'status': 308}
                                    for path in ['/', '/event-edit', '/event-edit.md']],
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


def test_documentation_serves_static_subpaths_and_preserves_queries(dashboard_server):
    host = 'docs.example.test'
    for path, expected in [('/docs/', '<html>Uranus Docs</html>'),
                           ('/docs/api-reference/', '<html>API reference</html>'),
                           ('/docs/_astro/app.js', 'window.docsLoaded = true;')]:
        assert dashboard_server(path, host=host)[:2] == (200, expected)
    assert dashboard_server('/', host=host)[2]['Location'] == '/docs/'
    status, _, headers = dashboard_server('/docs?query=kept', host=host)
    assert status == 301 and headers['Location'] == '/docs/?query=kept'
    for path in ['/docs/missing', '/docs/_astro/missing.js', '/unrelated', '/docs/.git/config']:
        assert dashboard_server(path, host=host)[0] == 404


def test_manual_serves_each_language_and_shared_assets(dashboard_server):
    host = 'manual.example.test'
    for locale in ['en', 'de', 'da']:
        assert dashboard_server(f'/{locale}/', host=host)[:2] == (200, f'<html>Manual {locale}</html>')
        assert dashboard_server(f'/{locale}/event-edit/', host=host)[:2] == (200, f'<html>Events {locale}</html>')
    assert dashboard_server('/_astro/app.js', host=host)[:2] == (200, 'window.manualLoaded = true;')
    assert dashboard_server('/img/sign-up.png', host=host)[:2] == (200, 'manual image fixture')
    for path, target in [('/', '/en'), ('/event-edit', '/en/event-edit'),
                         ('/event-edit/', '/en/event-edit'), ('/event-edit.md', '/en/event-edit.md')]:
        status, _, headers = dashboard_server(path + '?query=kept', host=host)
        assert status == 308 and headers['Location'] == target + '?query=kept'
    assert dashboard_server('/en?query=kept', host=host)[2]['Location'] == '/en/?query=kept'
    for path in ['/de/missing', '/_astro/missing.js', '/.git/config', '/package.json']:
        assert dashboard_server(path, host=host)[0] == 404


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
