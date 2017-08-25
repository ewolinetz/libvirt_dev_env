#! /bin/bash

ISO_LOCATION="/var/lib/libvirt/images"
IMAGE_LOCATION="/home/ewolinetz/images"

## Run this as root
[ "$(whoami)" != "root" ] && echo "Running as root is required" && exit 1

## Ensure that libvertd and virtlogd are running
[ -n "$(systemctl status libvirtd | grep 'Active: active (running)')" ] || echo "Starting libvirtd..." && systemctl start libvirtd
[ -n "$(systemctl status virtlogd | grep 'Active: active (running)')" ] || echo "Starting virtlogd..." && systemctl start virtlogd

sh stopAnsibleEnv.sh

HOSTLIST=$(virsh list --name --all)
for node in $HOSTLIST; do
  [ ! -e $IMAGE_LOCATION/${node}-base ] && echo "No base image for $node found. Please re-initialize!" && exit 1
  [ -e $IMAGE_LOCATION/${node} ] && echo "Removing previous ${node} image..." && rm $IMAGE_LOCATION/${node}
  echo "Restoring $node from /var/lib/libvirt/images/${node}-base..."
  qemu-img create -f qcow2 -b $IMAGE_LOCATION/${node}-base $IMAGE_LOCATION/${node}
done

#sh startAnsibleEnv.sh

exit 0
