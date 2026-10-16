"""Read-only Incus preflight. Incus and Ansible own all lifecycle operations.

No mutation, reconciliation, deletion or resize operation exists in this module.
CLI queries use the local socket and the raw API envelope of Incus 6.0 LTS.
"""
import ipaddress
import json
from pathlib import Path
import re
import shutil
try:
    from ansible.module_utils.uranus_safety import DATA, SafetyError, execute, storage_guard
except ImportError:
    from uranus_safety import DATA, SafetyError, execute, storage_guard

OWNER = 'uranus/incus/v1'
PROJECT = 'uranus'
POOL = 'uranus'
NETWORK = 'uranusincus0'
POOL_PATH = DATA / 'storage-pools' / 'uranus'
NAMES = {'db01','dev01','prod01','mon01','nom01','vers01','nginx01','plausible01'}
PROJECT_CONFIG = {'features.images':'true','features.profiles':'true',
                  'features.storage.volumes':'true','features.networks':'false',
                  'restricted':'true','restricted.containers.privilege':'unprivileged',
                  'restricted.containers.nesting':'block','restricted.devices.disk':'managed',
                  'restricted.devices.nic':'managed','restricted.devices.proxy':'allow',
                  'restricted.networks.access':NETWORK}
NETWORK_CONFIG = {'ipv4.address':'10.77.0.1/24','ipv4.nat':'true','ipv4.dhcp':'true',
                  'ipv6.address':'none','user.uranus.owner':OWNER}


def desired_config(instance):
    config = {'user.uranus.owner':OWNER,'user.uranus.disk_gib':str(instance['disk']),
              'limits.memory':f"{instance['memory']}MiB",'limits.cpu':str(instance['cpu']),
              'boot.autostart':'true','security.protection.delete':'true'}
    if instance['type'] == 'container':
        config.update({'security.privileged':'false','security.nesting':'false',
                       'security.idmap.isolated':'true'})
    return config


def desired_devices(instance, quotas=False):
    root = {'type':'disk','path':'/','pool':POOL}
    if instance['type'] == 'virtual-machine' or quotas:
        root['size'] = f"{instance['disk']}GiB"
    devices = {'root':root, 'eth0':{'type':'nic','name':'eth0','network':NETWORK,
                               'ipv4.address':instance['ip'],'security.mac_filtering':'true',
                               'security.ipv4_filtering':'true','security.ipv6_filtering':'true'}}
    if instance['role'] == 'ingress':
        # Incus connects inside the container's network namespace. The IPv6
        # wildcard uses Go's dual-stack TCP listener on the Debian host.
        for name, port in (('http', 80), ('https', 443)):
            devices[name] = {'type':'proxy', 'bind':'host', 'nat':'false',
                             'listen':f'tcp:[::]:{port}',
                             'connect':f'tcp:127.0.0.1:{port}',
                             'proxy_protocol':'true'}
    return devices


def validate_layout(instances, images):
    if len(instances) != len(NAMES) or {i['name'] for i in instances} != NAMES:
        raise SafetyError('Require the eight unique Uranus instance names')
    addresses=set()
    for instance in instances:
        if ((instance['name'] == 'nginx01') != (instance['role'] == 'ingress')
                or (instance['role'] == 'ingress' and instance['type'] != 'container')):
            raise SafetyError('Require nginx01 as the dedicated ingress container')
        if ((instance['name'] == 'plausible01') != (instance['role'] == 'analytics')
                or (instance['role'] == 'analytics' and instance['type'] != 'container')):
            raise SafetyError('Require plausible01 as the dedicated analytics container')
        if instance['type'] not in ('container','virtual-machine'):
            raise SafetyError('Use container or virtual-machine')
        for key in ('memory','cpu','disk'):
            if type(instance[key]) is not int or instance[key] < 1:
                raise SafetyError(f'Invalid {key} allocation')
        if instance.get('privileged',False):
            raise SafetyError('Privileged containers are prohibited')
        ip=ipaddress.ip_address(instance['ip'])
        if ip not in ipaddress.ip_network('10.77.0.0/24') or str(ip) in ('10.77.0.0','10.77.0.1','10.77.0.255'):
            raise SafetyError('Invalid private IP address')
        addresses.add(str(ip))
        if not re.fullmatch('[0-9a-f]{64}',images.get(instance['type'],'') or ''):
            raise SafetyError('Pin full Debian 13 cloud-image fingerprints for each selected type')
    if len(addresses) != len(NAMES):
        raise SafetyError('Duplicate instance IP addresses')


def preflight(instances, images, reserve_gib=160, quotas=False, run=execute, guard=storage_guard):
    guard(run)
    validate_layout(instances,images)
    mount=guard(run)
    if quotas and 'prjquota' not in mount.get('options','').split(','):
        raise SafetyError('Container quotas require pre-existing ext4 project quotas; no mount changes permitted')
    def query(path, expected_type=dict):
        result=json.loads(run(['incus','--force-local','query','--raw',path]))
        if (not isinstance(result,dict) or result.get('type') != 'sync'
                or result.get('status_code') != 200 or 'metadata' not in result):
            raise SafetyError(f'Unexpected Incus API response for {path}')
        metadata=result['metadata']
        # Incus 6.0 serializes some empty Go slices as JSON null instead of [].
        if expected_type is list and metadata is None:
            return []
        if (not isinstance(metadata,expected_type)
                or (expected_type is list and any(not isinstance(item,dict) for item in metadata))):
            raise SafetyError(f'Unexpected Incus API metadata for {path}')
        return metadata
    server=query('/1.0')
    for key in ('core.https_address','core.metrics_address','core.debug_address','core.storage_buckets_address'):
        if server.get('config',{}).get(key):
            raise SafetyError('Incus management and auxiliary APIs must be local-only')
    if not server.get('environment',{}).get('server_version','').startswith('6.0.'):
        raise SafetyError('Require Debian Incus 6.0 LTS; review newer versions separately')
    if server.get('environment',{}).get('server_clustered'):
        raise SafetyError('Cluster adoption is not supported by this single-host workflow')
    if any(i['type'] == 'virtual-machine' for i in instances):
        # Incus 6.0 lists only operational instance drivers in this API field.
        drivers=server.get('environment',{}).get('driver','')
        if not isinstance(drivers,str) or 'qemu' not in {d.strip() for d in drivers.split('|')}:
            raise SafetyError(
                'Incus QEMU driver is not operational; refuse VM provisioning before resource creation. '
                'Read sudo journalctl -u incus -b --no-pager for the underlying QEMU feature-check error. '
                'Verify KVM access and Debian ovmf/QEMU packages, then restart incus after repairing prerequisites.')
    projects={p['name']:p for p in query('/1.0/projects?recursion=1',list)}
    project=projects.get(PROJECT)
    project_proxy_upgrade = False
    if project:
        # Existing managed projects may predate the dedicated ingress container.
        # Only this known restriction can be upgraded, after the full audit.
        project_proxy_upgrade = project['config'].get('restricted.devices.proxy', 'block') == 'block'
        if project.get('description') != OWNER or any(
                project['config'].get(k) != v for k,v in PROJECT_CONFIG.items()
                if not (k == 'restricted.devices.proxy' and project_proxy_upgrade)):
            raise SafetyError('Unmanaged or drifted Uranus project')
    pools={p['name']:p for p in query('/1.0/storage-pools?recursion=1',list)}
    pool=pools.get(POOL)
    if pool:
        if pool['driver'] != 'dir' or pool['config'].get('source') != str(POOL_PATH) or pool['config'].get('user.uranus.owner') != OWNER:
            raise SafetyError('Unmanaged or drifted storage pool')
    elif POOL_PATH.exists() and any(POOL_PATH.iterdir()):
        raise SafetyError('Orphaned non-empty pool directory; preserve and recover manually')
    networks=query('/1.0/networks?recursion=1',list)
    network=next((n for n in networks if n['name']==NETWORK),None)
    if network and (not network.get('managed') or network.get('type') != 'bridge' or any(network['config'].get(k) != v for k,v in NETWORK_CONFIG.items())):
        raise SafetyError('Unmanaged or drifted private network')
    subnet=ipaddress.ip_network('10.77.0.0/24')
    for other in networks:
        if other['name']==NETWORK: continue
        address=other.get('config',{}).get('ipv4.address','none')
        if address not in ('','none','auto') and subnet.overlaps(ipaddress.ip_network(address,strict=False)):
            raise SafetyError('Private subnet overlaps another Incus network')
    for interface in json.loads(run(['ip','--json','address','show'])):
        if interface['ifname']==NETWORK:
            if not network: raise SafetyError('Unmanaged host bridge collision')
            continue
        for address in interface.get('addr_info',[]):
            if address['family']=='inet' and subnet.overlaps(ipaddress.ip_network(f"{address['local']}/{address['prefixlen']}",strict=False)):
                raise SafetyError('Private subnet overlaps a host interface')
    for route in json.loads(run(['ip','--json','route','show','table','all'])):
        if route.get('dst','default') == 'default' or (network and route.get('dev')==NETWORK): continue
        other=ipaddress.ip_network(route['dst'],strict=False)
        if other.version==4 and subnet.overlaps(other):
            raise SafetyError('Private subnet overlaps a host route')
    actual=query('/1.0/instances?recursion=2&project=uranus',list) if project else []
    by_name={i['name']:i for i in actual}
    if set(by_name) - NAMES:
        raise SafetyError('Unexpected instances in the dedicated Uranus project; preserve and audit manually')
    missing=[]; stopped=[]
    for instance in instances:
        name=instance['name']; old=by_name.get(name)
        if not old:
            # Incus generates these project-prefixed paths. They may survive an interrupted operation.
            for directory in ('containers','virtual-machines','containers-snapshots','virtual-machines-snapshots'):
                for parent in (DATA,POOL_PATH):
                    if (parent/directory/f'{PROJECT}_{name}').exists() or (parent/directory/f'{PROJECT}_{name}').is_symlink():
                        raise SafetyError(f'Orphaned instance data for {name}')
            missing.append(name); continue
        config=old['expanded_config']
        if old['type'] != instance['type'] or any(config.get(k) != v for k,v in desired_config(instance).items()):
            raise SafetyError(f'Instance ownership, type or resource drift: {name}; no automatic replacement')
        if any(k.startswith('raw.') or (k.startswith('security.') and k not in desired_config(instance)) for k in config):
            raise SafetyError(f'Unexpected security override: {name}')
        if old.get('profiles') or old['expanded_devices'] != desired_devices(instance,quotas):
            raise SafetyError(f'Unexpected profile or device drift: {name}')
        if old.get('status') not in ('Running','Stopped'):
            raise SafetyError(f'Incomplete or unexpected instance state: {name}')
        if old['status']=='Stopped': stopped.append(name)
    if pool:
        volumes=query('/1.0/storage-pools/uranus/volumes?recursion=1&project=uranus',list) if project else []
        for volume in volumes:
            if volume['type'] in ('container','virtual-machine') and volume['name'].split('/')[0] not in by_name:
                raise SafetyError('Orphaned Incus storage volume')
    if reserve_gib < 100:
        raise SafetyError('Keep at least 100 GiB reserve for images, snapshots and backups')
    if missing:
        probe=DATA
        while not probe.exists(): probe=probe.parent
        required=(sum(i['disk'] for i in instances if i['name'] in missing)+reserve_gib)*1024**3
        if shutil.disk_usage(probe).free < required:
            raise SafetyError('Insufficient free space for root-disk budgets and backup reserve')
    return {'new_instances':missing,'stopped_instances':stopped,'project_exists':bool(project),
            'pool_exists':bool(pool),'network_exists':bool(network),
            'project_proxy_upgrade':project_proxy_upgrade}
