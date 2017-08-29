#! /bin/bash

set -e

MASTER_COUNT=1
NODE_COUNT=1
LOCAL_USER="$(whoami)"
ISO_LOCATION="/var/lib/libvirt/images"
INSTALL_ISO="rhel-server-7.3-x86_64-dvd.iso"
IMAGE_SIZE="10G"
VM_MEMORY="1024"
VM_CORES="1"
VM_THREADS="1"

function help() {

  echo "Usage: $0 [m|n|d|v|c|t|u]"
  echo "  -m number:      The number of master nodes to create the cluster with. Defaults to ${MASTER_COUNT}"
  echo "  -n number:      The number of nodes to create the cluster with. Defaults to ${NODE_COUNT}"
  echo "  -d number[M|G]: The size of the disk to create for each VM. Defaults to ${IMAGE_SIZE}"
  echo "  -v number:      The amount of memory each VM should be configured with, in MB. Defaults to ${VM_MEMORY}"
  echo "  -c number:      The number of CPU cores each VM should be configured to use. Defaults to ${VM_CORES}"
  echo "  -t number:      The number of CPU threads each VM should be configured to use. Defaults to ${VM_THREADS}"
  echo "  -i string:      The name of the iso to be used for installing the VM OS. This file should exist in ${ISO_LOCATION} and defaults to ${INSTALL_ISO}"
  echo "  -u string:      The local user under whom images will be configured and shell RC will be updated. Defaults to \$(whoami)"
  echo "  -h:             Displays this information"
  echo "  -?:             Displays this information"

  exit 0
}

function confirm() {

  echo "Will install with the following configuration:"
  echo "Number of masters:                        ${MASTER_COUNT}"
  echo "Number of nodes:                          ${NODE_COUNT}"
  echo "Per VM disk size (double to allow reset): ${IMAGE_SIZE}"
  echo "Per VM memory size (in MB):               ${VM_MEMORY}"
  echo "Per VM CPU core count:                    ${VM_CORES}"
  echo "Per VM CPU thread count:                  ${VM_THREADS}"
  echo "VM install iso:                           ${INSTALL_ISO}"
  echo "Local user:                               ${LOCAL_USER}"
  read -rp $"Is this correct?[y]: " -n 1 confirmation

  case $confirmation in
    y) echo ""
    ;;
    Y) echo ""
    ;;
    "")
    ;;
    *) echo "" && exit 1
    ;;
  esac

}

# check options to create multiple nodes/masters
while getopts "m:n:d:v:c:t:u:i:h:?:" opt; do
  case $opt in
    m) [[ ! $OPTARG =~ [[:digit:]] ]] && echo "Numeric value required for master count" && exit 1
       MASTER_COUNT=$OPTARG
       ;;
    n) [[ ! $OPTARG =~ [[:digit:]] ]] && echo "Numeric value required for node count" && exit 1
       NODE_COUNT=$OPTARG
       ;;
    d) [[ ! $OPTARG =~ [[:digit:]][M|G] ]] && echo "Image size must be a numeric value in [M]b or [G]b" && exit 1
       IMAGE_SIZE=$OPTARG
       ;;
    v) [[ ! $OPTARG =~ [[:digit:]] ]] && echo "Numeric value required for vm memory size (in MB)" && exit 1
       VM_MEMORY=$OPTARG
       ;;
    c) [[ ! $OPTARG =~ [[:digit:]] ]] && echo "Numeric value required for vm cpu core count" && exit 1
       VM_CORES=$OPTARG
       ;;
    t) [[ ! $OPTARG =~ [[:digit:]] ]] && echo "Numeric value required for vm cpu thread count" && exit 1
       VM_THREADS=$OPTARG
       ;;
    u) [[ ! OPTARG =~ [[:alnum:]] ]] && echo "Alpha numeric value required for local user" && exit 1
       LOCAL_USER=$OPTARG
       ;;
    i) [[ ! -f ${ISO_LOCATION}/${OPTARG} ]] && echo "Invalid install iso name provided. '${ISO_LOCATION}/${OPTARG}' does not exist" && exit 1
       INSTALL_ISO=$OPTARG
       ;;
    h) help
       ;;
    ?) help
       ;;
  esac
done

confirm

IMAGE_LOCATION="/home/${LOCAL_USER}/images"

## Run this as root
[ "$(whoami)" != "root" ] && echo "Running as root is required" && exit 1

[ "$(whereis virsh | grep 'bin')" ] || ( echo "virsh command is required" && exit 1 )
[ "$(whereis virt-install | grep 'bin')" ] || (echo "virt-install command is required" && exit 1 )

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

# Set up virt network to use

# First check if the example network is active
if [[ -z "$(virsh net-list --name | grep example)"]]; then
  # stop any that might currently be bound to the network
  # -- this doesn't actually delete it
  for network in "$(virsh net-list --name)"; do
    virsh net-destroy $network
  done

  # if its not just inactive, create it
  [[ -z "$(virsh net-list --inactive | grep example)" ]] && virsh net-define example_network.xml

  virsh net-autostart example
  virsh net-start example
fi

createPIDs=()
echo "Creating VMs..."
for host in $HOSTLIST; do
# Create the vms
  sed "s,network  --hostname=.*,network  --hostname=${host}," ks.cfg > ${host}-ks.cfg

  virt-install --name ${host} \
               --memory $VM_MEMORY \
               --location $ISO_LOCATION/${INSTALL_ISO} \
               --vcpus cores=${VM_CORES},threads=${VM_THREADS} \
               --disk $IMAGE_LOCATION/${node} \
               --network network=example \
               --initrd-inject ./${host}-ks.cfg \
               --extra-args="ks=file:/${host}-ks.cfg console=tty0 console=ttyS0,115200n8" &

  createPIDs+=( $! )
done

wait ${createPIDs[@]}
rm ./*-ks.cfg


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

  sed -i "/^${host}.*$/d" /home/${LOCAL_USER}/.ssh/known_hosts
  [ -e ~/.ssh/known_hosts ] && sed -i "/^${host}.*$/d" ~/.ssh/known_hosts

  ssh-copy-id -i /home/${LOCAL_USER}/.ssh/id_rsa.pub root@$host
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

sh exportRHSUBvars.sh "$LOCAL_USER"

sh generateHostFile.sh
