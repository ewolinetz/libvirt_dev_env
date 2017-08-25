#! /bin/bash

set -x

MASTER_COUNT=1
NODE_COUNT=1
ISO_LOCATION="/var/lib/libvirt/images"
IMAGE_LOCATION="/home/ewolinetz/images"
IMAGE_SIZE="10G"

# check options to create multiple nodes/masters
while getopts "m:n:" opt; do
  case $opt in
    m) [[ ! $OPTARG =~ [[:digit:]] ]] && echo "Numeric value required for master count" && exit 1
       MASTER_COUNT=$OPTARG
       ;;
    n) [[ ! $OPTARG =~ [[:digit:]] ]] && echo "Numeric value required for node count" && exit 1
       NODE_COUNT=$OPTARG
       ;;
  esac
done

## Run this as root
[ "$(whoami)" != "root" ] && echo "Running as root is required" && exit 1

[ "$(whereis virsh | grep 'bin')" ] || ( echo "virsh command is required" && exit 1 )

# check that we have an install image at /var/lib/libvirt/images/
[ ! -e $ISO_LOCATION/*.iso ] && echo "Missing install iso at $ISO_LOCATION" && exit 1

# build HOSTLIST that we can iterate through later
HOSTLIST=""
for i in `seq 1 $(echo $MASTER_COUNT)`; do
  HOSTLIST="$HOSTLIST `printf 'm%02d.example.com' $i`"
done

for i in `seq 1 $(echo $NODE_COUNT)`; do
  HOSTLIST="$HOSTLIST `printf 'n%02d.example.com' $i`"
done

[ ! -d $IMAGE_LOCATION ] && mkdir -p $IMAGE_LOCATION

# for each master needed and each node needed
for node in $HOSTLIST; do
  # check for -base images
  [ ! -e $IMAGE_LOCATION/${node}-base ] && qemu-img create -f raw $IMAGE_LOCATION/${node}-base $IMAGE_SIZE

  # check for qcow2 images
  [ ! -e $IMAGE_LOCATION/${node} ] && qemu-img create -f qcow2 -b $IMAGE_LOCATION/${node}-base $IMAGE_LOCATION/${node}

done

# use virt-manager to create nodes... wait here
echo "Launching virt-manager..."
virt-manager
echo "Create following VMs:"
for host in $HOSTLIST; do
  echo "  * $host"

# Create the images
# virt-install --name ${host} --memory 1024 --location $ISO_LOCATION/rhel-server-7.3-x86_64-dvd.iso --vcpus cores=1,threads=2 --disk $IMAGE_LOCATION/${node} --network network=example --initrd-inject ./ks.cfg --extra-args="ks=file:/ks.cfg console=tty0 console=ttyS0,115200n8"

done
read -rsp $"and then press any key to continue..." -n1 key


# check that all expected hosts are created and running...
CREATED_HOSTS=$(virsh list --name --all)
RUNNING_HOSTS=$(virsh list --name)
for host in $HOSTLIST; do
  [[ ! $CREATED_HOSTS =~ $host ]] && echo "Error: expected $host to be created" && exit 1
  [[ ! $RUNNING_HOSTS =~ $host ]] && echo "Error: expected $host to be running" && exit 1
done

# update /etc/hosts

# get host ip address
for host in $HOSTLIST; do
# TODO: lets make that cleaner with a single awk...
  HOST_IP=$(virsh domifaddr $host | grep ipv | awk '{print $4}' | sed "s,/.*,,")
  HOST_SHORTNAME=$(echo $host | cut -d'.' -f 1)

  sed -i "/^.*$host$/d" /etc/hosts
  echo $HOST_IP  $HOST_SHORTNAME  $host >> /etc/hosts
  echo $HOST_IP  $HOST_SHORTNAME  $host >> vm_hosts

  sed -i "/^${host}.*$/d" /home/ewolinetz/.ssh/known_hosts
  [ -e ~/.ssh/known_hosts ] && sed -i "/^${host}.*$/d" ~/.ssh/known_hosts

  ssh-copy-id -i /home/ewolinetz/.ssh/id_rsa.pub root@$host
  [ -e ~/.ssh/id_rsa.pub ] && ssh-copy-id -i ~/.ssh/id_rsa.pub root@$host
done

# copy ssh keys to nodes
for host in $HOSTLIST; do
  cat vm_hosts | ssh root@$host 'cat - >> /etc/hosts'
done

# clean up vm_hosts file
rm vm_hosts

# stop our hosts
sh stopAnsibleEnv.sh

# back them up
for host in $HOSTLIST; do
  qemu-img commit -b $IMAGE_LOCATION/${host}-base $IMAGE_LOCATION/$host 1>/dev/null 2>&1 || qemu-img commit $IMAGE_LOCATION/$host
done

# start them back up
sh startAnsibleEnv.sh

sh exportRHSUBvars.sh

sh generateHostFile.sh
