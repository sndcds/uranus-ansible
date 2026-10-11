#!/usr/bin/env python3
"""Offline architectural, dependency, YAML and secret checks for the supported tree."""
from pathlib import Path
import re
import subprocess
import yaml
ROOT=Path(__file__).resolve().parents[1]

class UniqueLoader(yaml.SafeLoader):
    pass

def unique(loader,node,deep=False):
    result={}
    for key,value in node.value:
        name=loader.construct_object(key,deep=deep)
        if name in result: raise ValueError(f'Duplicate YAML key: {name}')
        result[name]=loader.construct_object(value,deep=deep)
    return result
UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,unique)

def check():
    paths=[]
    for folder in ('roles','playbooks','environments','library','module_utils','scripts','.github'):
        paths.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix in ('.yml','.yaml','.j2','.py','.sh','.example'))
    for p in paths:
        if p.name in ('vault.yml','deployment.yml') or 'pki' in p.parts: continue
        text=p.read_text()
        if p.suffix in ('.yml','.yaml') or p.name.endswith('.yml.example'):
            yaml.load(text,Loader=UniqueLoader)
        if p.name != 'check_repository.py' and re.search(r'\b(?:uvtool|uvirt|virt-install|virsh|libvirt)\b',text,re.I):
            raise ValueError(f'Obsolete provisioning dependency: {p.relative_to(ROOT)}')
        if re.search(r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,}|AKIA[0-9A-Z]{16})',text):
            raise ValueError(f'Credential token committed: {p.relative_to(ROOT)}')
        if re.search(r'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----',text):
            raise ValueError(f'Private key committed: {p.relative_to(ROOT)}')
    # Every remaining role must have a static consumer in the supported workflow.
    content='\n'.join(p.read_text() for p in paths if p.suffix in ('.yml','.j2'))
    for p in (ROOT/'roles').iterdir():
        if p.is_dir() and not re.search(r'(?:role:|name:)\s*'+re.escape(p.name)+r'\b',content):
            raise ValueError(f'Unused role: {p.name}')
    # Detect unreferenced central variables rather than maintaining obsolete defaults.
    config=ROOT/'environments/hetzner/group_vars/all.yml'
    variables=yaml.safe_load(config.read_text())
    usage='\n'.join(p.read_text() for p in paths if p!=config and p.name!='check_repository.py')
    unused=[name for name in variables if not re.search(r'\b'+re.escape(name)+r'\b',usage)]
    if unused: raise ValueError('Unused central variables: '+', '.join(unused))
    # Tracked files, including dotfiles and SQL, are scanned for private key material.
    for name in subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True).splitlines():
        p=ROOT/name
        if p.is_file() and re.search(rb'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----',p.read_bytes()):
            raise ValueError(f'Private key committed: {name}')
    return len(paths)
if __name__=='__main__': print(f'Repository policy passed: {check()} source files')
