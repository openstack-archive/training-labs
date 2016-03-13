#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/admin-openstackrc.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Set up OpenStack Compute (nova) for compute node.
# http://docs.openstack.org/mitaka/install-guide-ubuntu/nova-compute-install.html
#------------------------------------------------------------------------------

echo "Installing nova for compute node."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# NOTE We deviate slightly from the install-guide here because inside our VMs,
#      we cannot use KVM inside VirtualBox.
# TODO Add option to use nova-compute instead if we are inside a VM that allows
#      using KVM.
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo apt-get install -y nova-compute-qemu

echo "Configuring nova for compute node."

conf=/etc/nova/nova.conf
echo "Configuring $conf."

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT rpc_backend rabbit

# Configure [oslo_messaging_rabbit] section.
iniset_sudo $conf oslo_messaging_rabbit rabbit_host controller
iniset_sudo $conf oslo_messaging_rabbit rabbit_userid openstack
iniset_sudo $conf oslo_messaging_rabbit rabbit_password "$RABBIT_PASS"

# Configuring [DEFAULT] section.
iniset_sudo $conf DEFAULT auth_strategy keystone

nova_admin_user=$(service_to_user_name nova)

MY_MGMT_IP=$(get_node_ip_in_network "$(hostname)" "mgmt")

# Configure [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$nova_admin_user"
iniset_sudo $conf keystone_authtoken password "$NOVA_PASS"

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT my_ip "$MY_MGMT_IP"
iniset_sudo $conf DEFAULT use_neutron True
iniset_sudo $conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

# Configure [vnc] section.
iniset_sudo $conf vnc vnc_enabled True
iniset_sudo $conf vnc vncserver_listen 0.0.0.0
iniset_sudo $conf vnc vncserver_proxyclient_address '$my_ip'
# Using IP address because the host running the browser may not be able to
# resolve the host name "controller"
iniset_sudo $conf vnc novncproxy_base_url http://"$(hostname_to_ip controller)":6080/vnc_auto.html

# Configure [glance] section.
iniset_sudo $conf glance api_servers http://controller:9292

# Configure [oslo_concurrency] section.
iniset_sudo $conf oslo_concurrency lock_path /var/lib/nova/tmp

# Delete logdir line
sudo sed -i "/^logdir/ d" $conf

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Finalize installation
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Configure nova-compute.conf
conf=/etc/nova/nova-compute.conf
echo -n "Hardware acceleration for virtualization: "
if sudo egrep -q '(vmx|svm)' /proc/cpuinfo; then
    echo "available."
    iniset_sudo $conf libvirt virt_type kvm
else
    echo "not available."
    iniset_sudo $conf libvirt virt_type qemu
fi
echo "Config: $(sudo grep virt_type $conf)"

echo "Restarting nova services."
sudo service nova-compute restart

# Remove SQLite database created by Ubuntu package for nova.
sudo rm -v /var/lib/nova/nova.sqlite
