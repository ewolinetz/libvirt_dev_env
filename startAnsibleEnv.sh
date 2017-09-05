#! /bin/bash

## Run this as root
[ "$(whoami)" != "root" ] && echo "Running as root is required" && exit 1

## Ensure that libvertd and virtlogd are running
[ -n "$(systemctl status libvirtd | grep 'Active: active (running)')" ] || echo "Starting libvirtd..." && systemctl start libvirtd
[ -n "$(systemctl status virtlogd | grep 'Active: active (running)')" ] || echo "Starting virtlogd..." && systemctl start virtlogd

# list running vms
RUNNING=$(virsh list --name)

echo "Starting shutdown vms..."
# lists all defined vms
for vm in `virsh list --name --all`; do
  [[ ! $RUNNING =~ "$vm" ]] && virsh start $vm
done

for vm in `virsh list --name`; do
  echo "Waiting for $vm to be ready..."
  ssh -o ConnectTimeout=5 root@${vm} true 2>/dev/null
  while [[ $? -eq 255 ]]; do
    sleep 1
    ssh -o ConnectTimeout=5 root@${vm} true 2>/dev/null
  done
done
