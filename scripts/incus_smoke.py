#!/usr/bin/env python3
"""Real Debian Incus CLI/API contract test inside a disposable, privileged lab.

This bypasses only the production NVMe/UUID guard, which has separate fault tests.
It never connects to SSH or changes /data, and never deletes Incus resources.
Destroy the enclosing test container to remove the lab afterwards.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from jinja2 import Environment, StrictUndefined
import yaml

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'module_utils'))
import uranus_incus as safety


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--data-dir',required=True)
    parser.add_argument('--image-cache',help='Offline lab cache containing verified incus.tar.xz, root.squashfs and disk.qcow2; imports must reproduce configured fingerprints')
    parser.add_argument('--boot',action='store_true',help='Require real container and VM boot, agent execution and SSH; needs delegated cgroups and KVM')
    args=parser.parse_args()
    data=Path(args.data_dir)
    if not data.is_absolute() or not str(data).startswith('/tmp/uranus-incus-smoke-') or data.exists():
        raise RuntimeError('Require a fresh disposable /tmp/uranus-incus-smoke-* directory')
    if os.geteuid()!=0: raise RuntimeError('Run only as root inside a disposable privileged test environment')
    data.mkdir(mode=0o700)
    env={**os.environ,'INCUS_DIR':str(data)}
    def run(argv,stdin=None):
        result=subprocess.run(argv,input=stdin,env=env,capture_output=True,text=True,timeout=300)
        if result.returncode:
            raise RuntimeError(f"{argv[0]} exited {result.returncode}: {result.stderr.strip()}")
        return result.stdout
    log=(data/'daemon.log').open('w')
    daemon=subprocess.Popen(['/usr/libexec/incus/incusd'],env=env,stdout=log,stderr=log)
    try:
        for _ in range(90):
            if (data/'unix.socket').exists(): break
            if daemon.poll() is not None: raise RuntimeError((data/'daemon.log').read_text())
            time.sleep(1)
        run(['incus','--force-local','admin','waitready','--timeout=60'])
        cfg=yaml.safe_load((ROOT/'environments/hetzner/group_vars/all.yml').read_text())
        cli=['incus','--force-local']
        project=cli+['--project','uranus']
        run(cli+['project','create','uranus','--description',safety.OWNER]+[v for k,value in safety.PROJECT_CONFIG.items() for v in ['-c',f'{k}={value}']])
        run(cli+['storage','create','uranus','dir','user.uranus.owner='+safety.OWNER])
        run(cli+['network','create',safety.NETWORK]+[f'{k}={v}' for k,v in safety.NETWORK_CONFIG.items()])
        resources=[{**i,'cpu':1,'memory':1024 if i['type']=='virtual-machine' else 256,'disk':8} for i in cfg['incus_instances']]
        safety.DATA=data
        safety.POOL_PATH=data/'storage-pools'/'uranus'
        guard=lambda _: {'options':'rw'}  # Contract test only; never claim the production UUID was verified here.
        safety.validate_layout(resources,cfg['incus_images'])
        empty=json.loads(run(cli+['query','--raw','/1.0/instances?recursion=2&project=uranus']))
        assert empty['metadata']==[]
        # Production reserves are tested separately; a CI runner cannot reserve 160 GiB.
        key=data/'identity'
        run(['ssh-keygen','-q','-t','ed25519','-N','','-f',str(key)])
        jinja=Environment(undefined=StrictUndefined)
        jinja.filters['to_json']=json.dumps
        template=jinja.from_string((ROOT/'roles/incus_instance/templates/instance.yml.j2').read_text())
        if args.image_cache:
            cache=Path(args.image_cache)
            for kind,file in [('container','root.squashfs'),('virtual-machine','disk.qcow2')]:
                run(project+['image','import',str(cache/'incus.tar.xz'),str(cache/file)])
                image=json.loads(run(cli+['query','--raw','/1.0/images/'+cfg['incus_images'][kind]+'?project=uranus']))
                assert image['metadata']['fingerprint']==cfg['incus_images'][kind]
        for instance in resources:
            body=template.render(incus_instance=instance,incus_container_quotas=False,
                                 hetzner_ssh_public_key_file=str(key)+'.pub',lookup=lambda kind,path: Path(path).read_text())
            command=project+['init',('' if args.image_cache else 'images:')+cfg['incus_images'][instance['type']],instance['name'],'--no-profiles']
            if instance['type']=='virtual-machine': command+=['--vm']
            run(command,stdin=body)
        after=safety.preflight(resources,cfg['incus_images'],run=run,guard=guard)
        repeat=safety.preflight(resources,cfg['incus_images'],run=run,guard=guard)
        assert after==repeat and not after['new_instances'] and set(after['stopped_instances'])==safety.NAMES
        print('PASS: Debian native project, pool, network, six VM/container initializations and repeated read-only preflight',flush=True)
        if args.boot:
            for name in ['dev01','db01']:
                run(project+['start',name])
                for attempt in range(90):
                    try:
                        release=run(project+['exec',name,'--','cat','/etc/os-release'])
                        assert 'VERSION_ID="13"' in release
                        break
                    except RuntimeError:
                        if attempt==89: raise
                        time.sleep(2)
                run(project+['exec',name,'--','timeout','180','cloud-init','status','--wait'])
                ip=next(i['ip'] for i in resources if i['name']==name)
                run(['ssh','-i',str(key),'-o','StrictHostKeyChecking=accept-new','-o','UserKnownHostsFile='+str(data/'known_hosts'),'-o','BatchMode=yes','debian@'+ip,'true'])
            print('PASS: container and VM boot, Incus agent, cloud-init and real SSH',flush=True)
        else:
            print('NOT RUN: boot, guest SSH and applications; use --boot in a lab with delegated cgroups and /dev/kvm',flush=True)
    except Exception:
        print('Native Incus daemon diagnostics:',file=sys.stderr)
        print((data/'daemon.log').read_text()[-12000:],file=sys.stderr)
        raise
    finally:
        daemon.terminate()
        try: daemon.wait(timeout=30)
        except subprocess.TimeoutExpired: daemon.kill();daemon.wait()
        log.close()

if __name__=='__main__': main()
