#! /bin/bash

## Run this as root
[ "$(whoami)" != "root" ] && echo "Running as root is required" && exit 1

echo "Stopping running vms..."
# list running vms
for vm in `virsh list --name`; do
  virsh shutdown $vm
done

# wait for them to actually be stopped
while [ -n "$(virsh list --name)" ]; do
  sleep 1s
done

echo "done stopping vms"
