"""Adversarial read-only preflight tests; no real instances or SSH targets."""
import copy
import json
from types import SimpleNamespace
import pytest
import uranus_incus as incus
import uranus_safety as safety

class API:
    def __init__(self):
        self.calls=[]
        self.data={
            '/1.0':{'config':{},'environment':{'server_version':'6.0.4','server_clustered':False,'driver':'lxc | qemu'}},
            '/1.0/projects?recursion=1':[],
            '/1.0/storage-pools?recursion=1':[],
            '/1.0/networks?recursion=1':[],
            '/1.0/instances?recursion=2&project=uranus':[],
            '/1.0/storage-pools/uranus/volumes?recursion=1&project=uranus':[],
        }
    def run(self,args):
        self.calls.append(args)
        if args[0]=='ip': return '[]'
        assert args[:4]==['incus','--force-local','query','--raw'],args
        return json.dumps({'type':'sync','status_code':200,'metadata':self.data[args[-1]]})
    def managed(self,instances):
        self.data['/1.0/projects?recursion=1']=[{'name':'uranus','description':incus.OWNER,'config':copy.deepcopy(incus.PROJECT_CONFIG)}]
        self.data['/1.0/storage-pools?recursion=1']=[{'name':'uranus','driver':'dir','config':{'source':str(incus.POOL_PATH),'user.uranus.owner':incus.OWNER}}]
        self.data['/1.0/networks?recursion=1']=[{'name':incus.NETWORK,'type':'bridge','managed':True,'config':copy.deepcopy(incus.NETWORK_CONFIG)}]
        self.data['/1.0/instances?recursion=2&project=uranus']=[{'name':i['name'],'type':i['type'],'status':'Running','profiles':[],
            'expanded_config':incus.desired_config(i),'expanded_devices':incus.desired_devices(i)} for i in instances]

@pytest.fixture
def layout(settings,tmp_path,monkeypatch):
    monkeypatch.setattr(incus,'DATA',tmp_path/'data')
    monkeypatch.setattr(incus,'POOL_PATH',tmp_path/'data/storage-pools/uranus')
    monkeypatch.setattr(incus.shutil,'disk_usage',lambda p:SimpleNamespace(free=10**15))
    return copy.deepcopy(settings['incus_instances']),settings['incus_images']

def plan(api,layout,**kwargs):
    return incus.preflight(*layout,run=api.run,guard=lambda run:{'options':'rw'},**kwargs)

def test_first_installation_plans_all_six_without_mutation(layout):
    api=API(); result=plan(api,layout)
    assert set(result['new_instances'])==incus.NAMES
    assert not result['project_exists']

@pytest.mark.parametrize('drivers',['lxc','',None,[],{},'lxc | not-qemu'])
def test_unavailable_qemu_stops_before_resource_inspection(layout,drivers):
    api=API();api.data['/1.0']['environment']['driver']=drivers
    before=copy.deepcopy(api.data)
    with pytest.raises(safety.SafetyError,match='QEMU driver is not operational') as error:
        plan(api,layout)
    assert 'journalctl -u incus' in str(error.value)
    assert api.data==before
    assert len(api.calls)==1 and api.calls[0][-1]=='/1.0'

def test_missing_driver_metadata_stops_before_resource_inspection(layout):
    api=API();del api.data['/1.0']['environment']['driver']
    with pytest.raises(safety.SafetyError,match='QEMU driver is not operational'):
        plan(api,layout)
    assert len(api.calls)==1

@pytest.mark.parametrize('drivers',['qemu','qemu | lxc',' lxc | qemu '])
def test_operational_qemu_allows_vm_provisioning(layout,drivers):
    api=API();api.data['/1.0']['environment']['driver']=drivers
    assert set(plan(api,layout)['new_instances'])==incus.NAMES

def test_container_only_layout_does_not_require_qemu(layout):
    api=API();api.data['/1.0']['environment']['driver']='lxc'
    for instance in layout[0]:instance['type']='container'
    assert set(plan(api,layout)['new_instances'])==incus.NAMES

@pytest.mark.parametrize('path',[
    '/1.0/projects?recursion=1',
    '/1.0/storage-pools?recursion=1',
    '/1.0/networks?recursion=1',
])
def test_first_installation_accepts_null_empty_collections(layout,path):
    api=API();api.data[path]=None;before=copy.deepcopy(api.data)
    result=plan(api,layout)
    assert set(result['new_instances'])==incus.NAMES
    assert not any(result[key] for key in ('project_exists','pool_exists','network_exists'))
    assert api.data==before

@pytest.mark.parametrize('path',[
    '/1.0/instances?recursion=2&project=uranus',
    '/1.0/storage-pools/uranus/volumes?recursion=1&project=uranus',
])
def test_existing_project_accepts_null_empty_collections(layout,path):
    api=API();api.managed(layout[0]);api.data[path]=None;before=copy.deepcopy(api.data)
    result=plan(api,layout)
    expected=incus.NAMES if path.startswith('/1.0/instances?') else set()
    assert set(result['new_instances'])==expected
    assert all(result[key] for key in ('project_exists','pool_exists','network_exists'))
    assert api.data==before

def test_repeat_is_read_only_and_preserves_instance_state(layout):
    api=API();api.managed(layout[0]);before=copy.deepcopy(api.data)
    assert not plan(api,layout)['new_instances']
    assert api.data==before

def test_stopped_existing_instance_is_reported_without_starting(layout):
    api=API();api.managed(layout[0]);api.data['/1.0/instances?recursion=2&project=uranus'][0]['status']='Stopped'
    assert plan(api,layout)['stopped_instances']==['db01']

@pytest.mark.parametrize('key',['core.https_address','core.metrics_address','core.debug_address','core.storage_buckets_address'])
def test_network_management_listener_is_rejected(layout,key):
    api=API();api.data['/1.0']['config'][key]='[::]:8443'
    with pytest.raises(safety.SafetyError,match='local-only'): plan(api,layout)

@pytest.mark.parametrize('field',['type','owner','memory','extra_device','profile','raw','state','disk'])
def test_drift_aborts_without_replacing_existing_instances(layout,field):
    api=API();api.managed(layout[0]);old=api.data['/1.0/instances?recursion=2&project=uranus'][0]
    if field=='type':old['type']='container'
    elif field=='owner':old['expanded_config']['user.uranus.owner']='other'
    elif field=='memory':old['expanded_config']['limits.memory']='1MiB'
    elif field=='disk':old['expanded_devices']['root']['size']='1GiB'
    elif field=='extra_device':old['expanded_devices']['host']={'type':'disk','source':'/','path':'/host'}
    elif field=='profile':old['profiles']=['default']
    elif field=='raw':old['expanded_config']['raw.lxc']='unsafe'
    else:old['status']='Error'
    before=copy.deepcopy(api.data)
    with pytest.raises(safety.SafetyError):plan(api,layout)
    assert api.data==before

@pytest.mark.parametrize('kind',['project','pool','network'])
def test_shared_resource_drift_is_preserved(layout,kind):
    api=API();api.managed(layout[0])
    if kind=='project':api.data['/1.0/projects?recursion=1'][0]['description']='other'
    elif kind=='pool':api.data['/1.0/storage-pools?recursion=1'][0]['config']['source']='/wrong'
    else:api.data['/1.0/networks?recursion=1'][0]['config']['ipv6.address']='auto'
    with pytest.raises(safety.SafetyError):plan(api,layout)

@pytest.mark.parametrize('empty',[[],None])
def test_orphaned_volume_stops_before_any_creation(layout,empty):
    api=API();api.managed(layout[0]);api.data['/1.0/instances?recursion=2&project=uranus']=empty
    api.data['/1.0/storage-pools/uranus/volumes?recursion=1&project=uranus']=[{'name':'db01','type':'virtual-machine'}]
    with pytest.raises(safety.SafetyError,match='Orphaned'):plan(api,layout)

def test_interrupted_init_preserves_orphaned_disk(layout):
    api=API();path=incus.DATA/'virtual-machines/uranus_db01';path.mkdir(parents=True);(path/'valuable').write_text('keep')
    with pytest.raises(safety.SafetyError,match='Orphaned'):plan(api,layout)
    assert (path/'valuable').read_text()=='keep'

@pytest.mark.parametrize('empty',[[],None])
def test_nonempty_unregistered_pool_is_not_adopted(layout,empty):
    incus.POOL_PATH.mkdir(parents=True);(incus.POOL_PATH/'keep').write_text('data')
    api=API();api.data['/1.0/storage-pools?recursion=1']=empty
    with pytest.raises(safety.SafetyError,match='Orphaned'):plan(api,layout)

def test_out_of_space_aborts_even_when_pool_exists(layout,monkeypatch):
    api=API();api.managed(layout[0]);api.data['/1.0/instances?recursion=2&project=uranus']=[]
    monkeypatch.setattr(incus.shutil,'disk_usage',lambda p:SimpleNamespace(free=1))
    with pytest.raises(safety.SafetyError,match='Insufficient'):plan(api,layout)

@pytest.mark.parametrize('fault',['duplicate_ip','public_ip','bad_name','negative_cpu','bad_type','privileged','floating_image'])
def test_invalid_inputs_are_rejected_before_api_calls(layout,fault):
    instances,images=layout;images=copy.deepcopy(images);instance=instances[0]
    if fault=='duplicate_ip':instance['ip']=instances[1]['ip']
    elif fault=='public_ip':instance['ip']='94.130.236.38'
    elif fault=='bad_name':instance['name']='unknown'
    elif fault=='negative_cpu':instance['cpu']=-1
    elif fault=='bad_type':instance['type']='vm'
    elif fault=='privileged':instance['privileged']=True
    else:images['virtual-machine']='debian/trixie/cloud'
    api=API()
    with pytest.raises(safety.SafetyError):plan(api,(instances,images))
    assert not api.calls

@pytest.mark.parametrize('kind',['interface','route','bridge','incus_network'])
def test_network_conflicts_fail_closed(layout,kind):
    api=API();original=api.run
    if kind=='incus_network':api.data['/1.0/networks?recursion=1']=[{'name':'vpn','config':{'ipv4.address':'10.77.0.1/24'}}]
    def run(args):
        if args[0]=='ip':
            if args[2]=='address' and kind=='interface':return json.dumps([{'ifname':'vpn','addr_info':[{'family':'inet','local':'10.77.0.2','prefixlen':24}]}])
            if args[2]=='address' and kind=='bridge':return json.dumps([{'ifname':incus.NETWORK}])
            if args[2]=='route' and kind=='route':return json.dumps([{'dev':'vpn','dst':'10.77.0.0/24'}])
        return original(args)
    with pytest.raises(safety.SafetyError):incus.preflight(*layout,run=run,guard=lambda run:{'options':'rw'})

def test_failed_api_read_never_means_resource_absent(layout):
    api=API()
    def run(args):raise safety.SafetyError('API unavailable')
    with pytest.raises(safety.SafetyError,match='unavailable'):incus.preflight(*layout,run=run,guard=lambda run:{'options':'rw'})

@pytest.mark.parametrize('response',[
    None,
    [],
    {'type':'sync','status_code':200},
    {'type':'error','status_code':500,'metadata':None},
    {'type':'sync','status_code':500,'metadata':None},
    {'type':'async','status_code':200,'metadata':None},
])
def test_invalid_api_envelope_never_means_resource_absent(layout,response):
    api=API();path='/1.0/storage-pools?recursion=1'
    def run(args):
        result=api.run(args)
        return json.dumps(response) if args[-1]==path else result
    with pytest.raises(safety.SafetyError,match=r'response for /1.0/storage-pools\?recursion=1'):
        incus.preflight(*layout,run=run,guard=lambda run:{'options':'rw'})
    assert api.calls[-1][-1]==path

@pytest.mark.parametrize('metadata',[{},'',0,False,[None],['/1.0/storage-pools/uranus']])
def test_invalid_collection_metadata_never_means_resource_absent(layout,metadata):
    api=API();api.data['/1.0/storage-pools?recursion=1']=metadata
    with pytest.raises(safety.SafetyError,match=r'metadata for /1.0/storage-pools\?recursion=1'):
        plan(api,layout)

def test_null_server_metadata_is_rejected(layout):
    api=API();api.data['/1.0']=None
    with pytest.raises(safety.SafetyError,match='metadata for /1.0'):
        plan(api,layout)
    assert len(api.calls)==1

def test_wrong_mount_stops_before_api_read(layout):
    api=API()
    def guard(run):raise safety.SafetyError('wrong UUID')
    with pytest.raises(safety.SafetyError):incus.preflight(*layout,run=api.run,guard=guard)
    assert not api.calls

@pytest.mark.parametrize('fault',['uuid','readonly','fstype','nested','symlink','missing'])
def test_storage_guard_rejects_unsafe_filesystems(tmp_path,monkeypatch,fault):
    data=tmp_path/'data';data.mkdir();monkeypatch.setattr(safety,'DATA',data)
    if fault=='symlink':data.rmdir();data.symlink_to(tmp_path)
    def run(args):
        mount={'target':'/data','uuid':safety.EXPECTED_UUID,'options':'rw,relatime','fstype':'ext4'}
        if fault=='uuid':mount['uuid']='wrong'
        if fault=='readonly':mount['options']='ro'
        if fault=='fstype':mount['fstype']='btrfs'
        if fault=='nested' and '--target' in args:mount['target']=str(data)
        return json.dumps({'filesystems':[] if fault=='missing' else [mount]})
    with pytest.raises(safety.SafetyError):safety.storage_guard(run)

def test_existing_ext4_is_accepted_without_mount_mutation(tmp_path,monkeypatch):
    monkeypatch.setattr(safety,'DATA',tmp_path)
    calls=[]
    def run(args):
        calls.append(args)
        return json.dumps({'filesystems':[{'target':'/data','uuid':safety.EXPECTED_UUID,'options':'rw','fstype':'ext4'}]})
    assert safety.storage_guard(run)['uuid']==safety.EXPECTED_UUID
    assert all(a[0]=='findmnt' for a in calls)

def test_quota_request_requires_existing_project_quotas(layout):
    with pytest.raises(safety.SafetyError,match='quotas'):plan(API(),layout,quotas=True)


def test_extra_project_instance_is_not_adopted_or_destroyed(layout):
    api=API();api.managed(layout[0]);unknown=copy.deepcopy(api.data['/1.0/instances?recursion=2&project=uranus'][0]);unknown['name']='foreign'
    api.data['/1.0/instances?recursion=2&project=uranus'].append(unknown)
    before=copy.deepcopy(api.data)
    with pytest.raises(safety.SafetyError,match='Unexpected instances'):plan(api,layout)
    assert api.data==before
