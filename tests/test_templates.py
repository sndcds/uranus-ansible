import re
import shutil
import socket
import subprocess
import pytest
from conftest import ROOT

def nginx_check(text, tmp_path):
    assert shutil.which('nginx'), 'Install nginx for the actual parser check'
    key,cert=tmp_path/'guest-key.pem',tmp_path/'guest-cert.pem'
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=guest'],check=True,capture_output=True)
    text=text.replace('/etc/ssl/certs/uranus-instance.pem',str(cert)).replace('/etc/ssl/private/uranus-instance.key',str(key)).replace('/etc/ssl/certs/uranus-ca.pem',str(cert))
    # nginx -t also probes listening sockets. Use temporary, unprivileged
    # loopback ports so the fixtures never bind the production interfaces.
    ports = {}
    def local_listener(match):
        original = match.group(2)
        if original not in ports:
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                ports[original] = listener.getsockname()[1]
        port = ports[original]
        address = f'[::1]:{port}' if original.startswith('[') else f'127.0.0.1:{port}'
        return match.group(1) + address
    text = re.sub(r'(?m)^(\s*listen\s+)([^ ;]+)', local_listener, text)
    paths = '\n'.join(f'{name}_temp_path {tmp_path}/{name};' for name in ['client_body', 'proxy', 'fastcgi', 'uwsgi', 'scgi'])
    conf = tmp_path / 'nginx.conf'
    conf.write_text(f'pid {tmp_path}/nginx.pid;\nerror_log stderr;\nevents {{}}\nhttp {{\naccess_log off;\n{paths}\n{text}\n}}\n')
    result = subprocess.run(['nginx', '-t', '-p', str(tmp_path), '-c', str(conf)], text=True, capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr


@pytest.mark.parametrize('role', ['dev', 'prod', 'monitoring', 'nominatim', 'versatiles', 'analytics'])
def test_guest_nginx_is_parseable_and_preserves_tls_forwarding(role, render, tmp_path):
    text = render('roles/debian13_guest_web/templates/guest.conf.j2',
                  instance_role=role, ansible_host='10.77.0.12', frontend_domain='app.example.test',
                  backend_domain='api.example.test', icinga_web_domain='mon.example.test',
                  nominatim_domain='nom.example.test', versatiles_domain='tiles.example.test',
                  backend_port=9090, versatiles_port=8080)
    text = text.replace('include fastcgi_params;', 'include /etc/nginx/fastcgi_params;')
    assert 'ssl_certificate' in text
    assert 'set_real_ip_from 10.77.0.17;' in text
    if role == 'monitoring':
        assert '/run/php/php8.4-fpm.sock' in text and 'fastcgi_param HTTPS on;' in text
    assert 'X-Forwarded-Proto https;' in text
    nginx_check(text, tmp_path)


def test_plausible_ingress_has_websockets_and_trusts_only_explicit_legacy_proxies(render, tmp_path):
    domain = 'plausible.example.test'
    text = render('roles/debian13_ingress/templates/ingress.conf.j2',
                  debian13_ingress_sites=[dict(instance='plausible01', key='plausible', domain=domain, upstream='10.77.0.18')],
                  debian13_ingress_tls_ready=True, plausible_legacy_proxy_addresses=['192.0.2.8', '2001:db8::8'])
    assert '192.0.2.8 $http_x_real_ip;' in text
    assert '2001:db8::8 $http_x_real_ip;' in text
    assert 'default $remote_addr;' in text
    assert 'proxy_set_header Upgrade $http_upgrade;' in text
    assert 'proxy_set_header Connection $uranus_connection_upgrade;' in text
    assert 'proxy_set_header X-Real-IP $uranus_plausible_client_ip;' in text
    assert 'proxy_ssl_name plausible01;' in text
    text = text.replace(f'/etc/letsencrypt/live/{domain}/fullchain.pem', str(tmp_path / 'guest-cert.pem'))
    text = text.replace(f'/etc/letsencrypt/live/{domain}/privkey.pem', str(tmp_path / 'guest-key.pem'))
    nginx_check(text, tmp_path)


@pytest.mark.parametrize('tls', [False, True])
def test_public_ingress_is_parseable_and_enforces_trust_boundary(tls, render, tmp_path):
    sites = [dict(instance='fixture',key='prod_frontend', domain='app.example.test', upstream='10.77.0.13'),
             dict(instance='fixture',key='dev_frontend', domain='dev.example.test', upstream='10.77.0.12'),
             dict(instance='fixture',key='icinga', domain='monitoring.example.test', upstream='10.77.0.14'),
             dict(instance='fixture',key='nominatim', domain='nom.example.test', upstream='10.77.0.15')]
    text = render('roles/debian13_ingress/templates/ingress.conf.j2',
                  debian13_ingress_sites=sites, debian13_ingress_tls_ready=tls,
                  hetzner_private_web_networks=['203.0.113.0/24'])
    if tls:
        key, cert = tmp_path / 'key.pem', tmp_path / 'cert.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1', '-subj', '/CN=example.test'],
                       check=True, capture_output=True)
        for site in sites:
            text = text.replace(f'/etc/letsencrypt/live/{site["domain"]}/fullchain.pem', str(cert))
            text = text.replace(f'/etc/letsencrypt/live/{site["domain"]}/privkey.pem', str(key))
        assert 'TLSv1.2 TLSv1.3' in text and 'ssl_reject_handshake on;' in text
        assert text.count('deny all;') == 2
        assert 'proxy_set_header X-Forwarded-For $remote_addr;' in text
        assert '$proxy_add_x_forwarded_for' not in text
        assert 'proxy_pass https://10.77.0.13:443;' in text
        assert 'proxy_ssl_verify on;' in text
    assert '/.well-known/acme-challenge/' in text
    assert 'listen 127.0.0.1:80 proxy_protocol' in text
    assert 'real_ip_header proxy_protocol;' in text
    assert 'set_real_ip_from 127.0.0.1;' in text
    nginx_check(text, tmp_path)


@pytest.mark.parametrize('kind',['container','virtual-machine'])
def test_native_cloud_init_schema_for_both_instance_types(kind,render,tmp_path):
    import yaml
    instance=dict(name='db01' if kind=='virtual-machine' else 'dev01',type=kind,cpu=2,memory=4096,disk=60,ip='10.77.0.12')
    text=render('roles/incus_instance/templates/instance.yml.j2',incus_instance=instance,incus_container_quotas=False,hetzner_ssh_public_key_file='fixture')
    config=yaml.safe_load(text)
    assert config['profiles']==[] and config['config']['security.protection.delete']=='true'
    if kind=='container':
        assert config['config']['security.privileged']=='false' and 'size' not in config['devices']['root']
    else: assert config['devices']['root']['size']=='60GiB'
    cloud=tmp_path/'cloud-config.yml';cloud.write_text(config['config']['user.user-data'])
    assert shutil.which('cloud-init'), 'Install cloud-init for the native schema check'
    result=subprocess.run(['cloud-init','schema','--config-file',str(cloud)],text=True,capture_output=True)
    assert result.returncode==0,result.stdout+result.stderr
    network=tmp_path/'network-config.yml'
    network.write_text(config['config']['user.network-config'])
    rendered=tmp_path/'network-rendered'
    # The real renderer chowns its output to systemd-network. Suppress only
    # that ownership change so this native conversion runs unprivileged.
    converter = '''
import runpy
import sys
from unittest.mock import patch
sys.argv = sys.argv[1:]
with patch('cloudinit.util.chownbyname'):
    runpy.run_path(sys.argv[0], run_name='__main__')
'''
    result=subprocess.run(['/usr/bin/python3','-c',converter,shutil.which('cloud-init'),
                           'devel','net-convert','-p',str(network),'-k','yaml',
                           '-d',str(rendered),'-D','debian','-O','networkd'],text=True,capture_output=True)
    assert result.returncode==0,result.stdout+result.stderr
    files=list((rendered/'etc/systemd/network').glob('*.network'))
    assert len(files)==1
    import configparser
    native=configparser.ConfigParser()
    native.read(files[0])
    assert native['Match']['Name']=='e*'
    assert native['Network']['DHCP']=='ipv4'
