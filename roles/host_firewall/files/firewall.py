#!/usr/bin/python3
"""Transactional update of one nftables table with timed SSH recovery."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

STATE=Path('/run/uranus-firewall')
PERSIST=Path('/etc/uranus/host-firewall.nft')
CANDIDATE=Path('/etc/uranus/host-firewall.candidate.nft')
SCRIPT=Path('/usr/local/sbin/uranus-firewall.py')
UNIT='uranus-firewall-rollback'

def run(argv):
    return subprocess.run(argv,check=True,capture_output=True,text=True).stdout

def transact(action, token=None):
    STATE.mkdir(mode=0o700,parents=True,exist_ok=True)
    with (STATE/'lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        pending=STATE/'pending'
        applied=STATE/'applied.nft'
        if action=='begin':
            if pending.exists(): raise RuntimeError('Pending firewall update; wait for rollback or recover manually')
            content=CANDIDATE.read_bytes()
            if token and hashlib.sha1(content).hexdigest()!=token:
                raise RuntimeError('Candidate changed concurrently; refuse unreviewed rules')
            applied.write_bytes(content)
            run(['nft','--check','--file',str(applied)])
            tables=json.loads(run(['nft','--json','list','tables']))['nftables']
            exists=any(t.get('table',{}).get('family')=='inet' and t['table']['name']=='uranus_host' for t in tables if 'table' in t)
            if exists and not PERSIST.exists():
                raise RuntimeError('Existing Uranus table has no confirmed ownership record; preserve and audit manually')
            rollback='destroy table inet uranus_host\n'
            if exists: rollback+=run(['nft','list','table','inet','uranus_host'])
            (STATE/'rollback.nft').write_text(rollback)
            transaction=uuid.uuid4().hex
            pending.write_text(transaction)
            try:
                run(['systemd-run','--unit='+UNIT+'-'+transaction,'--on-active=120s','/usr/bin/python3',str(SCRIPT),'rollback',transaction])
                run(['nft','--file',str(applied)])
            except Exception:
                run(['nft','--file',str(STATE/'rollback.nft')])
                pending.unlink(missing_ok=True)
                raise
            return transaction
        elif action=='rollback':
            if pending.exists() and (token is None or pending.read_text()==token):
                run(['nft','--file',str(STATE/'rollback.nft')])
                pending.unlink()
        elif action=='confirm':
            if not pending.exists(): raise RuntimeError('Update expired or was rolled back; refuse confirmation')
            if not token or pending.read_text()!=token:
                raise RuntimeError('Wrong firewall transaction; refuse confirmation')
            temporary=PERSIST.with_suffix('.new')
            shutil.copyfile(applied,temporary)
            temporary.chmod(0o600)
            os.replace(temporary,PERSIST)
            pending.unlink()
            # Late callbacks carry their own identity and cannot undo a later transaction.
            try: run(['systemctl','stop',UNIT+'-'+token+'.timer'])
            except subprocess.CalledProcessError: pass
        else: raise RuntimeError('Unknown firewall action')
if __name__=='__main__':
    result=transact(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else None)
    if result: print(result)
