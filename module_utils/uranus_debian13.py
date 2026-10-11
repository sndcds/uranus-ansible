"""Fail-closed storage and libvirt operations for the separate Debian 13 path."""

import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

EXPECTED_UUID = "7f882d89-a2cf-46d2-9db8-5333be51a300"
DATA = Path('/data')
STORAGE = Path("/data/libvirt/images")
SEEDS = Path("/data/libvirt/cloud-init")
OWNER = "uranus-debian13/v1"
VM_NAMES = {"db01", "dev01", "prod01", "mon01", "nom01", "vers01"}


class SafetyError(Exception):
    """The requested operation is unsafe or the system state is ambiguous."""


def execute(argv):
    result = subprocess.run(argv, check=False, capture_output=True, text=True,
                            env={**os.environ, "LC_ALL": "C"})
    if result.returncode:
        raise SafetyError(f"Command failed ({result.returncode}): {argv[0]}: {result.stderr.strip()}")
    return result.stdout.strip()


def reject_symlinks(path):
    path = Path(path)
    for component in [path, *path.parents]:
        if component.is_symlink():
            raise SafetyError(f"Symlink in protected storage path: {component}")


def storage_guard(run=execute):
    """Never mount, format, or repair /data; require the exact writable mount."""
    reject_symlinks(Path("/data"))
    mounts = json.loads(run(["findmnt", "--json", "--mountpoint", "/data",
                             "--output", "TARGET,UUID,OPTIONS"]))["filesystems"]
    if len(mounts) != 1 or mounts[0]["target"] != "/data":
        raise SafetyError("/data must be a separate mount point")
    mount = mounts[0]
    if mount.get("uuid") != EXPECTED_UUID or "rw" not in mount.get("options", "").split(","):
        raise SafetyError(f"/data must be mounted read-write with UUID {EXPECTED_UUID}")
    for path in (STORAGE, STORAGE / '.base', SEEDS):
        reject_symlinks(path)
        # Check the deepest existing parent to reject nested/bind mounts too.
        existing = path
        while not existing.exists():
            existing = existing.parent
        target = json.loads(run(["findmnt", "--json", "--target", str(existing),
                                 "--output", "TARGET,UUID,OPTIONS"]))["filesystems"][0]
        if target["target"] != "/data" or target.get("uuid") != EXPECTED_UUID:
            raise SafetyError(f"Unexpected filesystem underneath {path}")
    return mount


def validate_sql_dump(path):
    """Reject psql commands that can escape the selected new database or run a shell."""
    in_copy = False
    with open(path, encoding='utf-8') as stream:
        for line in stream:
            if in_copy:
                if line.rstrip('\n') == r'\.':
                    in_copy = False
                continue
            if re.match(r'^COPY .+ FROM stdin;\s*$', line, re.IGNORECASE):
                in_copy = True
            elif line.lstrip().startswith('\\') and not re.fullmatch(r'\\(?:unrestrict|restrict) [A-Za-z0-9]+\s*', line):
                raise SafetyError('Unsafe psql metacommand in initial SQL dump')
            elif re.match(r'^\s*(?:DROP|CREATE|ALTER)\s+DATABASE\b', line, re.IGNORECASE):
                raise SafetyError('Global database operation in initial SQL dump')
    if in_copy:
        raise SafetyError('Incomplete COPY data in SQL dump')


def network_signature(xml):
    root = ET.fromstring(xml)
    ip = root.find("ip")
    bridge = root.find("bridge")
    forward = root.find("forward")
    if ip is None or bridge is None or forward is None:
        raise SafetyError("Incomplete libvirt NAT network")
    if len(root.findall("ip")) != 1 or ip.get("family", "ipv4") != "ipv4":
        raise SafetyError("The guest network must have IPv4 only")
    if forward.get("mode") != "nat" or forward.find("interface") is not None or forward.get("dev"):
        raise SafetyError("The guest network must use private NAT without a physical bridge")
    return (root.findtext("name"), bridge.get("name"), ip.get("address"), ip.get("netmask"),
            sorted((h.get("mac"), h.get("name"), h.get("ip")) for h in root.findall("ip/dhcp/host")),
            [(r.get("start"), r.get("end")) for r in root.findall("ip/dhcp/range")],
            root.find("domain").attrib if root.find("domain") is not None else {})


class Provisioner:
    """Validate all selected resources before applying any libvirt mutation."""

    def __init__(self, run=execute, guard=storage_guard):
        self.run = run
        self.guard = guard

    def virsh(self, *args):
        return self.run(["virsh", "--connect", "qemu:///system", *args])

    def validate_domain(self, vm, xml, network_name):
        root = ET.fromstring(xml)
        disk = root.find("devices/disk[@device='disk']/source")
        nics = root.findall("devices/interface")
        path = STORAGE / f"{vm['name']}.qcow2"
        reject_symlinks(path)
        if root.findtext("description") != OWNER:
            raise SafetyError(f"Refusing to adopt unmanaged domain {vm['name']}")
        if disk is None or disk.get("file") != str(path) or not path.is_file():
            raise SafetyError(f"Unexpected or missing disk for {vm['name']}")
        if len(root.findall("devices/disk[@device='disk']")) != 1 or len(nics) != 1:
            raise SafetyError(f"Unexpected extra disk or NIC for {vm['name']}")
        if nics[0].get("type") != "network" or nics[0].find("source").get("network") != network_name:
            raise SafetyError(f"Unexpected network for {vm['name']}")
        if nics[0].find("mac").get("address", "").lower() != vm["mac"].lower():
            raise SafetyError(f"MAC drift for {vm['name']}")
        if int(root.findtext("vcpu", "0")) != vm["cpu"]:
            raise SafetyError(f"CPU drift for {vm['name']}; resize separately after review")
        memory = root.find("memory")
        unit = memory.get("unit", "KiB") if memory is not None else "KiB"
        factor = {"KiB": 1 / 1024, "MiB": 1, "GiB": 1024}.get(unit)
        if factor is None or int(memory.text) * factor != vm["memory"]:
            raise SafetyError(f"Memory drift for {vm['name']}; resize separately after review")
        size = json.loads(self.run(["qemu-img", "info", "--force-share", "--output=json", str(path)]))
        if size.get("backing-filename") or size["virtual-size"] != vm["disk"] * 1024 ** 3:
            raise SafetyError(f"Disk size/backing-file drift for {vm['name']}")

    def capacity(self, vms, missing, domains, image=None):
        """Reserve maximum disk growth, including foreign domains on /data."""
        volumes = {p for p in STORAGE.rglob('*.qcow2') if '.base' not in p.relative_to(STORAGE).parts}
        for name in domains:
            root = ET.fromstring(self.virsh('dumpxml', name, '--inactive'))
            for source in root.findall("devices/disk[@device='disk']/source"):
                path = Path(source.get('file', '/'))
                if path.is_relative_to(DATA) and not path.is_relative_to(STORAGE):
                    reject_symlinks(path)
                    if not path.is_file():
                        raise SafetyError(f'Cannot account for missing foreign VM disk {path}')
                    mount = json.loads(self.run(['findmnt', '--json', '--target', str(path),
                                                 '--output', 'UUID']))['filesystems'][0]
                    if mount.get('uuid') == EXPECTED_UUID:
                        volumes.add(path)
        growth, seen, accounted = 0, set(), []
        for path in sorted(volumes):
            reject_symlinks(path)
            if path.name.startswith('.'):
                raise SafetyError(f'Interrupted disk staging requires manual recovery: {path}')
            stat = path.stat()
            identity = (stat.st_dev, stat.st_ino)
            if identity in seen:
                continue
            seen.add(identity)
            info = json.loads(self.run(['qemu-img', 'info', '--force-share', '--output=json', str(path)]))
            if info.get('backing-filename') or info.get('format') not in ('qcow2', 'raw'):
                raise SafetyError(f'Unbounded backing chain or unknown disk format: {path}')
            reserved = max(0, info['virtual-size'] - stat.st_blocks * 512)
            growth += reserved
            accounted.append({'path': str(path), 'growth_bytes': reserved})
        cache = 0
        if missing:
            # Free space already excludes existing caches. Keep scratch space for
            # a replacement download alongside them, even if a cache file exists.
            cache = 10 * 1024**3
            if image and Path(image).is_file():
                reject_symlinks(image)
                if Path(image).stat().st_size > 10 * 1024**3:
                    raise SafetyError('Pinned base image exceeds the 10 GiB cache budget')
        new_disks = sum(vm['disk'] for vm in vms if vm['name'] in missing) * 1024**3
        required = new_disks + growth + cache + 5 * 1024**3
        existing = STORAGE
        while not existing.exists():
            existing = existing.parent
        free = shutil.disk_usage(existing).free
        if free < required:
            raise SafetyError(f'Insufficient free space: require {required} bytes for new disks, '
                              'existing disk growth, cache and 5 GiB reserve')
        return {'required_bytes': required, 'free_bytes': free, 'new_disk_bytes': new_disks,
                'existing_growth_bytes': growth, 'cache_bytes': cache, 'volumes': accounted}

    def plan(self, vms, network_xml, image=None):
        self.guard(self.run)
        desired = network_signature(network_xml)
        network_name, bridge, gateway = desired[:3]
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,40}", network_name or "") or network_name == "default":
            raise SafetyError("Use a separate named network; never replace default")
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,15}", bridge or "") or bridge == "virbr0":
            raise SafetyError("Use a separate bridge; never replace virbr0")
        subnet = ipaddress.ip_network(f"{gateway}/{desired[3]}", strict=False)
        if not subnet.is_private or not vms or len({v['name'] for v in vms}) != len(vms):
            raise SafetyError("Require unique VMs and a private subnet")
        if len({v['mac'].lower() for v in vms}) != len(vms) or len({v['ip'] for v in vms}) != len(vms):
            raise SafetyError("VM MAC and IP addresses must be unique")
        for vm in vms:
            if vm["name"] not in VM_NAMES or any(type(vm[key]) is not int or vm[key] < 1 for key in ("memory", "cpu", "disk")):
                raise SafetyError("Invalid VM name or resource allocation")
            if not re.fullmatch(r"52:54:00(?::[0-9a-fA-F]{2}){3}", vm["mac"]):
                raise SafetyError("Require a valid locally managed QEMU MAC")
            address = ipaddress.ip_address(vm["ip"])
            if address not in subnet or address in (subnet.network_address, subnet.broadcast_address, ipaddress.ip_address(gateway)):
                raise SafetyError("VM address is outside the usable guest subnet")
            if (vm["mac"], vm["name"], vm["ip"]) not in desired[4]:
                raise SafetyError("Missing matching DHCP reservation")
        networks = self.virsh("net-list", "--all", "--name").splitlines()
        pools = self.virsh("pool-list", "--all", "--name").splitlines()
        domains = self.virsh("list", "--all", "--name").splitlines()
        if network_name in networks:
            actual = network_signature(self.virsh("net-dumpxml", network_name, "--inactive"))
            if actual != desired:
                raise SafetyError("Existing NAT configuration differs; no automatic network replacement")
            active_info = self.virsh('net-info', network_name)
            if re.search(r'^Active:\s+yes$', active_info, re.MULTILINE):
                if network_signature(self.virsh('net-dumpxml', network_name)) != desired:
                    raise SafetyError('Active NAT configuration differs from its persistent definition')
        interfaces = json.loads(self.run(['ip', '--json', 'address', 'show']))
        for interface in interfaces:
            if interface['ifname'] == bridge:
                if network_name not in networks:
                    raise SafetyError('Refusing to adopt an existing unmanaged host bridge')
                continue
            for address in interface.get('addr_info', []):
                if address['family'] == 'inet':
                    host_subnet = ipaddress.ip_network(f"{address['local']}/{address['prefixlen']}", strict=False)
                    if subnet.overlaps(host_subnet):
                        raise SafetyError('Guest subnet overlaps a host interface')
        for route in json.loads(self.run(['ip', '--json', 'route', 'show', 'table', 'all'])):
            if route.get('dst', 'default') == 'default' or (route.get('dev') == bridge and network_name in networks):
                continue
            routed_subnet = ipaddress.ip_network(route['dst'], strict=False)
            if routed_subnet.version == 4 and subnet.overlaps(routed_subnet):
                raise SafetyError('Guest subnet overlaps an existing host route')
        for other in networks:
            if other == network_name:
                continue
            root = ET.fromstring(self.virsh("net-dumpxml", other, "--inactive"))
            if root.find("bridge") is not None and root.find("bridge").get("name") == bridge:
                raise SafetyError("Bridge already belongs to another libvirt network")
            for ip in root.findall("ip"):
                if ip.get("family", "ipv4") == "ipv4":
                    other_subnet = ipaddress.ip_network(f"{ip.get('address')}/{ip.get('netmask', ip.get('prefix', '24'))}", strict=False)
                    if subnet.overlaps(other_subnet):
                        raise SafetyError("Guest subnet overlaps another libvirt network")
        if network_name in pools:
            root = ET.fromstring(self.virsh("pool-dumpxml", network_name))
            if root.get("type") != "dir" or root.findtext("target/path") != str(STORAGE):
                raise SafetyError("Existing storage pool has an unexpected target")
        missing = []
        for vm in vms:
            if vm["name"] in domains:
                self.validate_domain(vm, self.virsh("dumpxml", vm["name"], "--inactive"), network_name)
            else:
                disk = STORAGE / f"{vm['name']}.qcow2"
                seed = SEEDS / vm["name"]
                reject_symlinks(disk)
                reject_symlinks(seed)
                if os.path.lexists(disk) or os.path.lexists(seed):
                    raise SafetyError(f"Orphaned disk/cloud-init data for {vm['name']}; manual recovery required")
                missing.append(vm["name"])
        capacity = self.capacity(vms, missing, domains, image)
        return {"new_vms": missing, "network_exists": network_name in networks,
                "pool_exists": network_name in pools, "network_name": network_name, 'capacity': capacity}

    def apply(self, vms, network_xml, image, checksum, seeds, check_mode=False, start_existing=False):
        plan = self.plan(vms, network_xml, image)
        if check_mode:
            return {**plan, "changed": bool(plan["new_vms"] or not plan["network_exists"] or not plan["pool_exists"])}
        changed = False
        if plan["new_vms"]:
            reject_symlinks(image)
            if Path(image).parent != STORAGE / ".base" or not re.fullmatch(r"[0-9a-f]{128}", checksum):
                raise SafetyError("Cloud image must have a pinned SHA512 under the protected .base directory")
            with open(image, "rb") as stream:
                if hashlib.file_digest(stream, "sha512").hexdigest() != checksum:
                    raise SafetyError("Cloud image checksum mismatch")
            info = json.loads(self.run(["qemu-img", "info", "--output=json", str(image)]))
            if info["format"] != "qcow2" or info.get("backing-filename"):
                raise SafetyError("Cloud image must be a standalone qcow2")
            for vm in vms:
                if vm["name"] in plan["new_vms"]:
                    if vm["disk"] * 1024 ** 3 < info["virtual-size"]:
                        raise SafetyError("Requested VM disk is smaller than the cloud image")
                    if not all(seeds.get(vm["name"], {}).get(key) for key in ("user_data", "meta_data", "network_config")):
                        raise SafetyError("Missing cloud-init seed configuration")
        # No failed read is interpreted as 'not found'. All reads above must succeed.
        if not plan["network_exists"]:
            self.guard(self.run)
            with tempfile.NamedTemporaryFile(mode="w", suffix=".xml") as stream:
                stream.write(network_xml)
                stream.flush()
                self.virsh("net-define", stream.name)
            changed = True
        if not plan["pool_exists"]:
            self.guard(self.run)
            STORAGE.mkdir(parents=True, exist_ok=True, mode=0o755)
            self.virsh("pool-define-as", plan["network_name"], "dir", "--target", str(STORAGE))
            changed = True
        for kind in ("net", "pool"):
            info = self.virsh(f"{kind}-info", plan["network_name"])
            if not re.search(r"^Autostart:\s+yes$", info, re.MULTILINE):
                self.guard(self.run)
                self.virsh(f"{kind}-autostart", plan["network_name"])
                changed = True
            if not re.search(r"^(Active:\s+yes|State:\s+running)$", info, re.MULTILINE):
                self.guard(self.run)
                self.virsh(f"{kind}-start", plan["network_name"])
                changed = True
        for vm in vms:
            name = vm["name"]
            if name not in plan["new_vms"]:
                if start_existing and self.virsh("domstate", name).strip() == "shut off":
                    self.guard(self.run)
                    self.virsh("start", name)
                    changed = True
                continue
            self.guard(self.run)
            disk = STORAGE / f"{name}.qcow2"
            # Publish without clobbering a path that appeared after the preflight.
            fd, temporary = tempfile.mkstemp(prefix=f".{name}-", suffix=".qcow2", dir=STORAGE)
            os.close(fd)
            try:
                self.run(["qemu-img", "convert", "-f", "qcow2", "-O", "qcow2", str(image), temporary])
                self.run(["qemu-img", "resize", "-f", "qcow2", temporary, f"{vm['disk']}G"])
                os.chmod(temporary, 0o600)
                self.guard(self.run)
                os.link(temporary, disk)
            finally:
                os.unlink(temporary)
            SEEDS.mkdir(parents=True, exist_ok=True, mode=0o755)
            seed = SEEDS / name
            seed.mkdir(mode=0o755)
            for key, filename in (("user_data", "user-data"), ("meta_data", "meta-data"), ("network_config", "network-config")):
                with (seed / filename).open("x") as stream:
                    stream.write(seeds[name][key])
                (seed / filename).chmod(0o600)
            self.run(["cloud-localds", "--network-config", str(seed / "network-config"),
                      str(seed / "seed.iso"), str(seed / "user-data"), str(seed / "meta-data")])
            (seed / "seed.iso").chmod(0o600)
            self.guard(self.run)
            self.run(["virt-install", "--connect", "qemu:///system", "--name", name,
                      "--virt-type", "kvm", "--osinfo", "debian13", "--import",
                      "--memory", str(vm["memory"]), "--vcpus", str(vm["cpu"]),
                      "--cpu", "host-passthrough", "--metadata", f"description={OWNER}",
                      "--disk", f"path={disk},format=qcow2,bus=virtio",
                      "--disk", f"path={seed / 'seed.iso'},device=cdrom,readonly=on",
                      "--network", f"network={plan['network_name']},model=virtio,mac={vm['mac']}",
                      "--channel", "unix,target.type=virtio,target.name=org.qemu.guest_agent.0",
                      "--graphics", "none", "--serial", "pty", "--console", "pty,target_type=serial",
                      "--noautoconsole", "--autostart", "--wait", "0"])
            changed = True
        return {**plan, "changed": changed}


def locked_apply(provisioner, **kwargs):
    provisioner.guard(provisioner.run)
    # /run is ephemeral. This lock serializes concurrent Ansible controllers.
    fd = os.open("/run/lock/uranus-debian13.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return provisioner.apply(**kwargs)
