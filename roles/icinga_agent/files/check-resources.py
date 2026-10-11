#!/usr/bin/python3
"""Icinga perfdata from the local guest; respects cgroup v2 where available."""
import os
import argparse
from pathlib import Path
import shutil
import time

def cpu():
    cgroup=Path('/sys/fs/cgroup/cpu.stat')
    if cgroup.exists():
        values=dict(line.split() for line in cgroup.read_text().splitlines())
        return int(values['usage_usec']) / 1e6
    fields=Path('/proc/stat').read_text().splitlines()[0].split()[1:]
    return sum(int(v) for i,v in enumerate(fields[:8]) if i not in (3,4)) / os.sysconf('SC_CLK_TCK')

def network():
    result=0
    for line in Path('/proc/net/dev').read_text().splitlines()[2:]:
        name,values=line.split(':'); fields=values.split()
        if name.strip()!='lo': result+=int(fields[0])+int(fields[8])
    return result

def memory():
    current,maximum=Path('/sys/fs/cgroup/memory.current'),Path('/sys/fs/cgroup/memory.max')
    if current.exists() and maximum.read_text().strip()!='max':
        return 100*int(current.read_text())/int(maximum.read_text())
    data={line.split(':')[0]:int(line.split()[1]) for line in Path('/proc/meminfo').read_text().splitlines()}
    return 100*(data['MemTotal']-data['MemAvailable'])/data['MemTotal']

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--disk-path',default='/')
    for name,value in [('cpu-warning',85),('cpu-critical',95),('memory-warning',85),('memory-critical',95),('disk-warning',75),('disk-critical',85)]:
        parser.add_argument('--'+name,type=float,default=value)
    args=parser.parse_args()
    start=time.monotonic(); c1,n1=cpu(),network(); time.sleep(1)
    elapsed=time.monotonic()-start
    used_cpu=min(100,100*(cpu()-c1)/elapsed/len(os.sched_getaffinity(0)))
    used_ram=memory(); disk=shutil.disk_usage(args.disk_path); used_disk=100*disk.used/disk.total
    rate=(network()-n1)/elapsed
    level=2 if used_cpu>=args.cpu_critical or used_ram>=args.memory_critical or used_disk>=args.disk_critical else 1 if used_cpu>=args.cpu_warning or used_ram>=args.memory_warning or used_disk>=args.disk_warning else 0
    label=['OK','WARNING','CRITICAL'][level]
    print(f'{label}: CPU {used_cpu:.1f}%, RAM {used_ram:.1f}%, disk {used_disk:.1f}% | cpu={used_cpu:.1f}%;{args.cpu_warning};{args.cpu_critical} ram={used_ram:.1f}%;{args.memory_warning};{args.memory_critical} disk={used_disk:.1f}%;{args.disk_warning};{args.disk_critical} network={rate:.0f}B/s')
    return level
if __name__=='__main__': raise SystemExit(main())
