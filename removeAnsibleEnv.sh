#! /bin/bash

ISO_LOCATION="/var/lib/libvirt/images"
LOCAL_USER="${1:-$(whoami)}"

# check options to create multiple nodes/masters
while getopts "u:" opt; do
  case $opt in
    u) [[ ! OPTARG =~ [[:alnum:]] ]] && echo "Alpha numeric value required for local user" && exit 1
       LOCAL_USER=$OPTARG
       ;;
  esac
done

IMAGE_LOCATION="/home/${LOCAL_USER}/images"

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
