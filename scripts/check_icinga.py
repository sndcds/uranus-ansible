#!/usr/bin/env python3
"""Parse production Icinga templates for host, master, container and VM; never start services."""
import json
from pathlib import Path
import subprocess
import tempfile

from jinja2 import Environment, StrictUndefined
import yaml

ROOT=Path(__file__).resolve().parents[1]


def main():
    settings=yaml.safe_load((ROOT/'environments/hetzner/group_vars/all.yml').read_text())
    jinja=Environment(undefined=StrictUndefined)
    jinja.filters['to_json']=json.dumps
    hostvars={i['name']:{'ansible_host':i['ip']} for i in settings['incus_instances']}
    for node in ['hetzner','mon01','dev01','db01']:
        with tempfile.TemporaryDirectory(prefix='uranus-icinga-parser-') as name:
            root=Path(name);root.chmod(0o755);(root/'conf.d').mkdir();(root/'features-enabled').mkdir()
            key,cert=root/'key.pem',root/'cert.pem'
            subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN='+node],check=True,capture_output=True)
            key.chmod(0o644)  # Disposable self-signed test identity; Icinga drops privileges during -C.
            (root/'constants.conf').write_text(f'const NodeName = "{node}"\nconst ZoneName = "{"master" if node=="mon01" else node}"\nconst PluginDir = "/usr/lib/nagios/plugins"\nconst PluginContribDir = PluginDir\n')
            main_config=next(t['ansible.builtin.copy']['content'] for t in yaml.safe_load((ROOT/'roles/icinga_agent/tasks/main.yml').read_text()) if t['name']=='Select application configuration without distribution sample checks')
            (root/'icinga2.conf').write_text(main_config)
            context={**settings,'inventory_hostname':node,'ansible_host':hostvars.get(node,{'ansible_host':'94.130.236.38'})['ansible_host'],'hostvars':hostvars,
                     'monitoring_ido_db_password':'test-only','monitoring_api_password':'test-only',
                     'hetzner_domains':{key:key+'.example.test' for key in ['dev_frontend','prod_frontend','icinga','nominatim','versatiles']}}
            mappings={'roles/icinga_agent/templates/zones.conf.j2':'zones.conf',
                      'roles/icinga_agent/templates/api.conf.j2':'features-enabled/api.conf',
                      'roles/icinga_agent/templates/check-command.conf.j2':'conf.d/uranus-check-command.conf'}
            if node=='mon01':
                mappings.update({'roles/debian13_monitoring/templates/vm-checks.conf.j2':'conf.d/uranus-debian13.conf',
                                 'roles/debian13_monitoring/templates/api-users.conf.j2':'conf.d/api-users.conf',
                                 'roles/debian13_monitoring/templates/ido-pgsql.conf.j2':'features-enabled/ido-pgsql.conf',
                                 'roles/debian13_monitoring/templates/influxdb.conf.j2':'features-enabled/influxdb.conf'})
            else:
                for file in ['api-users','uranus-debian13']:(root/'conf.d'/f'{file}.conf').write_text('// Empty on agent\n')
            templates=Path('/etc/icinga2/conf.d/templates.conf').read_text()
            (root/'conf.d/templates.conf').write_text(templates)
            for source,dest in mappings.items():
                content=jinja.from_string((ROOT/source).read_text()).render(context)
                content=content.replace('/etc/ssl/certs/uranus-instance.pem',str(cert)).replace('/etc/ssl/private/uranus-instance.key',str(key)).replace('/etc/ssl/certs/uranus-ca.pem',str(cert))
                if dest=='features-enabled/api.conf':
                    content=content.replace('\n}', f'\n  cert_path = "{cert}"\n  key_path = "{key}"\n  ca_path = "{cert}"\n}}')
                (root/dest).write_text(content)
            result=subprocess.run(['icinga2','daemon','-C','-c',str(root/'icinga2.conf')],text=True,capture_output=True)
            if result.returncode: raise RuntimeError(node+': '+result.stdout+result.stderr)
            print('PASS: native Icinga configuration for '+node)

if __name__=='__main__':main()
