#!/usr/bin/env python3
"""Relay verified Plausible snapshots using controller SSH; never forward an agent."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


class Migration:
    def __init__(self, args):
        self.args = args
        self.private = ROOT / '.uranus-private/plausible'
        self.private.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.state_path = self.private / 'migration-state.json'
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}

    def save(self):
        self.state_path.write_text(json.dumps(self.state, indent=2) + '\n')
        self.state_path.chmod(0o600)

    def ssh(self, target=False):
        command = ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'ControlPath=' + self.args.control_path]
        if target:
            if self.args.ssh_config:
                command += ['-F', self.args.ssh_config]
            command += ['-o', 'UserKnownHostsFile=' + str(ROOT / '.uranus-private/known_hosts'),
                        '-J', self.args.jump, self.args.target]
        else:
            command += [self.args.source]
        return command

    def run(self, code, target=False):
        compile(code, '<plausible-migration>', 'exec')
        result = subprocess.run(self.ssh(target) + ['sudo -n python3 -'], input=code.encode(), capture_output=True)
        if result.returncode:
            # Database tools can include SQL in errors; keep it in the protected audit directory.
            with (self.private / 'migration-error.log').open('ab') as log:
                log.write(result.stdout + result.stderr)
            raise RuntimeError('Migration step failed; inspect the protected migration-error.log')
        return result.stdout.decode()

    def rollback(self):
        if not self.state.get('source_stopped'):
            return
        backup = self.state.get('proxy_backup')
        code = '''import subprocess
from pathlib import Path
'''
        if backup:
            code += 'backup=Path(' + repr(backup) + ')\n'
            code += '''assert backup.parent == Path('/var/backups') and backup.name.startswith('plausible-cutover-')
if backup.exists():
    Path('/etc/nginx/sites-available/plausible').write_bytes(backup.read_bytes())
else:
    assert 'proxy_pass http://127.0.0.1:8200;' in Path('/etc/nginx/sites-available/plausible').read_text()
subprocess.run(['nginx','-t'],check=True,capture_output=True)
subprocess.run(['systemctl','reload','nginx'],check=True)
'''
        code += "subprocess.run(['systemctl','enable','--now','plausible'],check=True)\n"
        self.run(code)
        self.state['rolled_back'] = True
        self.save()

    def import_data(self):
        if self.state:
            raise RuntimeError('Migration state exists; inspect it rather than replacing an existing snapshot')
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        source = '/var/backups/plausible-migration-' + stamp
        target = '/var/backups/plausible/import-' + stamp
        archive = self.private / ('migration-' + stamp + '.tar.gz')
        self.state = {'stamp': stamp, 'source': source, 'target': target, 'archive': str(archive)}
        self.run("import pathlib,subprocess\nassert not pathlib.Path('/etc/plausible/import-complete.json').exists()\n"
                 "assert subprocess.run(['systemctl','is-active','--quiet','plausible']).returncode != 0\n"
                 + 'pgdb,chdb=' + repr((self.args.postgres_database, self.args.clickhouse_database)) + '\n'
                 + "assert int(subprocess.check_output(['runuser','-u','postgres','--','psql','-XAt','-d',pgdb,'-c',"
                   "\"SELECT count(*) FROM pg_tables WHERE schemaname='public'\"])) == 0\n"
                 + "assert int(subprocess.check_output(['clickhouse-client','--query',"
                   "\"SELECT count(*) FROM system.databases WHERE name='\"+chdb+\"'\"])) == 1\n"
                 + "assert int(subprocess.check_output(['clickhouse-client','--query',"
                   "\"SELECT count(*) FROM system.tables WHERE database='\"+chdb+\"'\"])) == 0\n", target=True)
        self.save()
        try:
            self.run("import subprocess\nsubprocess.run(['systemctl','stop','plausible'],check=True)\n")
            self.state['source_stopped'] = True
            self.save()
            exporter = (ROOT / 'roles/debian13_plausible/files/export_data.py').read_text().split("if __name__ == '__main__':")[0]
            exported = self.run(exporter + '\nsys.argv=["export",' + repr(source) + ']\nmain()\n')
            self.state['export'] = json.loads(exported)
            self.save()
            # Only the data snapshot is relayed; no source configuration or TLS keys are archived.
            remote = "sudo -n tar -C " + shlex.quote(source) + ' -czf - .'
            with archive.open('xb') as output:
                result = subprocess.run(self.ssh() + [remote], stdout=output, stderr=subprocess.PIPE)
            if result.returncode:
                raise RuntimeError('Snapshot transport failed')
            receiver = '''import io,os,sys,tarfile
from pathlib import Path
os.umask(0o077)
destination=Path(DESTINATION)
destination.mkdir(mode=0o700)
with tarfile.open(fileobj=io.BytesIO(sys.stdin.buffer.read()),mode='r:gz') as archive:
    for member in archive:
        name=member.name.removeprefix('./')
        if name in ['', '.'] and member.isdir(): continue
        if not member.isfile() or Path(name).name != name: raise ValueError('Unsafe archive member')
        with (destination/name).open('xb') as output:
            output.write(archive.extractfile(member).read())
'''.replace('DESTINATION', repr(target))
            with archive.open('rb') as source_data:
                result = subprocess.run(self.ssh(True) + ['sudo -n python3 -c ' + shlex.quote(receiver)],
                                        stdin=source_data, capture_output=True)
            if result.returncode:
                raise RuntimeError('Protected target staging failed')
            importer = (ROOT / 'roles/debian13_plausible/files/import_data.py').read_text().split("if __name__ == '__main__':")[0]
            imported = self.run(importer + '\nsys.argv=["import",' + repr(target) + ',' + repr(self.args.clickhouse_database) + ',' + repr(self.args.postgres_database) + ']\nmain()\n', target=True)
            self.state['import'] = json.loads(imported)
            self.save()
            print(json.dumps(self.state['import']))
        except BaseException:
            self.rollback()
            raise

    def cutover(self):
        if not self.state.get('import', {}).get('verified') or self.state.get('rolled_back'):
            raise RuntimeError('A verified current import is required')
        domain, address = self.args.domain, self.args.ingress_ipv4
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '30',
                        '--resolve', domain + ':443:' + address, 'https://' + domain + '/api/health'],
                       check=True, capture_output=True)
        backup = '/var/backups/plausible-cutover-' + self.state['stamp'] + '.conf'
        self.state['proxy_backup'] = backup
        self.save()
        code = 'import subprocess\nfrom pathlib import Path\n'
        code += 'domain,address,backup=' + repr((domain, address, backup)) + '\n'
        code += r'''
path=Path('/etc/nginx/sites-available/plausible')
old=path.read_text()
assert old.count('server_name ' + domain + ';') == 2
needle='proxy_pass http://127.0.0.1:8200;'
assert old.count(needle) == 1
replacement=('proxy_pass https://' + address + ';\n'
             '    proxy_ssl_server_name on;\n'
             '    proxy_ssl_name ' + domain + ';\n'
             '    proxy_ssl_verify on;\n'
             '    proxy_ssl_verify_depth 4;\n'
             '    proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;')
saved=Path(backup)
assert not saved.exists()
saved.write_text(old)
saved.chmod(0o600)
try:
    path.write_text(old.replace(needle,replacement))
    subprocess.run(['nginx','-t'],check=True,capture_output=True)
    subprocess.run(['systemctl','reload','nginx'],check=True)
    subprocess.run(['systemctl','disable','plausible'],check=True,capture_output=True)
except Exception:
    path.write_text(old)
    subprocess.run(['systemctl','reload','nginx'],capture_output=True)
    raise
'''
        self.run(code)
        subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '30',
                        '--retry', '5', '--retry-delay', '1', '--retry-all-errors',
                        'https://' + domain + '/api/health'], check=True, capture_output=True)
        self.run("import json\nfrom pathlib import Path\np=Path('/etc/plausible/migration-cutover.json')\n"
                 + 'p.write_text(' + repr(json.dumps({'source': self.args.source, 'stamp': self.state['stamp']})) + ')\np.chmod(0o600)\n',
                 target=True)
        self.state['cutover'] = True
        self.save()
        print(json.dumps({'cutover': True, 'domain': domain}))


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['import', 'cutover', 'rollback'])
    parser.add_argument('--control-path', required=True)
    parser.add_argument('--source', default='awendelk@webserver')
    parser.add_argument('--target', required=True)
    parser.add_argument('--clickhouse-database', default='plausible_events_live')
    parser.add_argument('--postgres-database', default='plausible_live')
    parser.add_argument('--jump', required=True)
    parser.add_argument('--ssh-config')
    parser.add_argument('--domain', required=True)
    parser.add_argument('--ingress-ipv4', required=True)
    args = parser.parse_args()
    migration = Migration(args)
    if args.phase == 'import':
        migration.import_data()
    elif args.phase == 'cutover':
        migration.cutover()
    else:
        migration.rollback()


if __name__ == '__main__':
    main()
