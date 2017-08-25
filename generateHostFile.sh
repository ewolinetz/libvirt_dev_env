#! /bin/bash

set -x

## Run this as root
[ "$(whoami)" != "root" ] && echo "Running as root is required" && exit 1

sh startAnsibleEnv.sh

MASTERS=""
NODES=""

# get host ip address
for host in `virsh list --name`; do
# TODO: lets make that cleaner with a single awk...
  HOST_IP=$(virsh domifaddr $host | grep ipv | awk '{print $4}' | sed "s,/.*,,")

  LINE="$host openshift_hostname=$host openshift_ip=$HOST_IP openshift_public_hostname=$host openshift_public_ip=$HOST_IP"
  OPTIONS=""

  [[ $host =~ ^m.*$ ]] && MASTERS="${MASTERS}${LINE}\n" && OPTIONS="openshift_scheduable=False"
  [[ $host =~ ^n.*$ ]] && OPTIONS="openshift_node_labels=\"{'region': 'infra'}\""
  NODES="${NODES}${LINE} ${OPTIONS}\n"
done

# Generate host file
echo "Generating host file..."
cat > /home/ewolinetz/hosts <<CONFIG
[OSEv3:children]
masters
nodes
etcd

[OSEv3:vars]
ansible_ssh_user=root
ansible_become=yes

openshift_deployment_type=openshift-enterprise
deployment_type=openshift-enterprise

#containerized=True
#openshift_image_tag=v3.6.143

openshift_uninstall_images=False

openshift_disable_check=disk_availability,memory_availability,docker_storage,package_version,docker_image_availability

#### Service catalog vars

#openshift_enable_service_catalog=True

#openshift_hosted_etcd_storage_kind=nfs
#openshift_hosted_etcd_storage_access_modes=['ReadWriteOnce']
#openshift_hosted_etcd_storage_host=nfs.example.com
#openshift_hosted_etcd_storage_nfs_directory=/exports
#openshift_hosted_etcd_storage_volume_name=etcd
#openshift_hosted_etcd_storage_volume_size=1Gi
#openshift_hosted_etcd_storage_labels={'storage': 'etcd'}

ansible_service_broker_log_level=debug
ansible_service_broker_output_request=true
ansible_service_broker_registry_url="http://registry.access.stage.redhat.com"
ansible_service_broker_image_prefix="asb-registry.usersys.redhat.com:5000/openshift3/ose-"


openshift_service_catalog_image_prefix=openshift/origin-
openshift_service_catalog_image_version=latest

#ansible_service_broker_image_prefix=ansibleplaybookbundle/
#ansible_service_broker_image_tag=latest

ansible_service_broker_etcd_image_prefix=quay.io/coreos/
ansible_service_broker_etcd_image_tag=latest
ansible_service_broker_etcd_image_etcd_path=/usr/local/bin/etcd

#### Service catalog vars

### auth

openshift_master_identity_providers=[{'name': 'htpasswd_auth', 'login': 'true', 'challenge': 'true', 'kind': 'HTPasswdPasswordIdentityProvider', 'filename': '/etc/origin/master/htpasswd'}]
openshift_master_htpasswd_file=/home/ewolinetz/local_ansible_scripts/openshift.htpasswd

#openshift_master_identity_providers=[{'name': 'allow_all', 'login': 'true', 'challenge': 'true', 'kind': 'AllowAllPasswordIdentityProvider'}]

### auth


# Variables for the aos-ansible playbooks:
#qe_repo_image_prepull=False
aos_repo=https://mirror.openshift.com/enterprise/enterprise-3.6/latest/RH7-RHAOS-3.6/x86_64/os

#openshift_hosted_metrics_deploy=True

#openshift_metrics_cassandra_storage_type=dynamic
#openshift_metrics_cassandra_pvc_size=1Gi
#openshift_metrics_install_hawkular_agent=True

#openshift_hosted_metrics_storage_kind=nfs
#openshift_hosted_metrics_storage_access_modes=['ReadWriteOnce']
#openshift_hosted_metrics_storage_host=nfs.example.com
#openshift_hosted_metrics_storage_nfs_directory=/exports
#openshift_hosted_metrics_storage_volume_name=metrics
#openshift_hosted_metrics_storage_volume_size=10Gi
#openshift_hosted_metrics_storage_labels={'storage': 'metrics'}

#openshift_hosted_logging_deploy=True

openshift_logging_es_pvc_dynamic=false
openshift_logging_es_pvc_size=1Gi
#openshift_logging_es_pv_selector=None

openshift_hosted_logging_storage_kind=nfs
openshift_hosted_logging_storage_access_modes=['ReadWriteOnce']
openshift_hosted_logging_storage_host=nfs.example.com
openshift_hosted_logging_storage_nfs_directory=/exports
openshift_hosted_logging_storage_volume_name=logging
openshift_hosted_logging_storage_volume_size=1Gi
openshift_hosted_logging_storage_labels={'storage': 'logging'}

openshift_metrics_hawkular_hostname="hawkular.example.com"

openshift_master_default_subdomain="example.com"

#openshift_install_examples=True

rhsub_pass="{{ lookup('env','RHSUB_PASS') }}"
rhsub_pool="Employee SKU*"
rhsub_user="{{ lookup('env','RHSUB_USER') }}"
rhel_skip_subscription='no'

openshift_additional_repos=[{'id': 'ose-devel', 'name': 'ose-devel', 'baseurl': 'http://download.eng.bos.redhat.com/rcm-guest/puddles/RHAOS/AtomicOpenShift/3.6/latest/x86_64/os/', 'enabled': 1, 'gpgcheck': 0}]
#oreg_url='registry.ops.openshift.com/openshift3/ose-${component}:${version}'

openshift_docker_additional_registries="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888,registry.ops.openshift.com"
#openshift_docker_additional_registries="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888,registry.ops.openshift.com,asb-registry.usersys.redhat.com"

#openshift_docker_insecure_registries="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888,registry.ops.openshift.com"
openshift_docker_insecure_registries="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888,registry.ops.openshift.com,'asb-registry.usersys.redhat.com:5000'"

openshift_hosted_metrics_deployer_prefix="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888/openshift3/"
openshift_hosted_logging_deployer_prefix="brew-pulp-docker01.web.prod.ext.phx2.redhat.com:8888/openshift3/"

[masters]
`echo -e $MASTERS`

[nodes]
`echo -e $NODES`

[etcd]
`echo -e $MASTERS`
CONFIG

# run playbook
echo "Finished setting up, run the following as a non-root user:"

# playbook to subscribe machines
echo "ansible-playbook -i ./hosts /home/ewolinetz/git/openshift-ansible/playbooks/byo/rhel_subscribe.yml"

# also need to install PyYAML on machines...

# playbook to install openshift
echo "ansible-playbook -i ./hosts /home/ewolinetz/git/openshift-ansible/playbooks/byo/config.yml"
