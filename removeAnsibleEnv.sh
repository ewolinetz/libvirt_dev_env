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
  echo "Removing ${node}..."
  [ -e $IMAGE_LOCATION/${node}-base ] && rm $IMAGE_LOCATION/${node}-base
  [ -e $IMAGE_LOCATION/${node} ] && rm $IMAGE_LOCATION/${node}

  virsh undefine ${node} --remove-all-storage
done

exit 0
