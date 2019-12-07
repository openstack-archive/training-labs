#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Networking Option 2: Self-service networks
# https://docs.openstack.org/neutron/train/install/controller-install-option2-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install the components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing additional packages for self-service networks."
sudo apt install -y \
    neutron-server neutron-plugin-ml2 \
    neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent \
    neutron-metadata-agent

echo "Configuring neutron for controller node."
function get_database_url {
    local db_user=$NEUTRON_DB_USER
    local database_host=controller

    echo "mysql+pymysql://$db_user:$NEUTRON_DBPASS@$database_host/neutron"
}

database_url=$(get_database_url)

neutron_admin_user=neutron

nova_admin_user=nova

echo "Setting database connection: $database_url."
conf=/etc/neutron/neutron.conf

# Configure [database] section.
iniset_sudo $conf database connection "$database_url"

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT core_plugin ml2
iniset_sudo $conf DEFAULT service_plugins router
iniset_sudo $conf DEFAULT allow_overlapping_ips true

echo "Configuring RabbitMQ message queue access."
iniset_sudo $conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@controller"

iniset_sudo $conf DEFAULT auth_strategy keystone

# Configuring [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken www_authenticate_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:5000
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$neutron_admin_user"
iniset_sudo $conf keystone_authtoken password "$NEUTRON_PASS"

# Configure nova related parameters
iniset_sudo $conf DEFAULT notify_nova_on_port_status_changes true
iniset_sudo $conf DEFAULT notify_nova_on_port_data_changes true

# Configure [nova] section.
iniset_sudo $conf nova auth_url http://controller:5000
iniset_sudo $conf nova auth_type password
iniset_sudo $conf nova project_domain_name default
iniset_sudo $conf nova user_domain_name default
iniset_sudo $conf nova region_name "$REGION"
iniset_sudo $conf nova project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf nova username "$nova_admin_user"
iniset_sudo $conf nova password "$NOVA_PASS"

# lock_path, not in install-guide:
iniset_sudo $conf oslo_concurrency lock_path /var/lib/neutron/tmp

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Modular Layer 2 (ML2) plug-in
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the Modular Layer 2 (ML2) plug-in."
conf=/etc/neutron/plugins/ml2/ml2_conf.ini

# Edit the [ml2] section.
iniset_sudo $conf ml2 type_drivers flat,vlan,vxlan
iniset_sudo $conf ml2 tenant_network_types vxlan
iniset_sudo $conf ml2 mechanism_drivers linuxbridge,l2population
iniset_sudo $conf ml2 extension_drivers port_security

# Edit the [ml2_type_flat] section.
iniset_sudo $conf ml2_type_flat flat_networks provider

iniset_sudo $conf ml2_type_vxlan vni_ranges 1:1000

# Edit the [securitygroup] section.
iniset_sudo $conf securitygroup enable_ipset true

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Linux bridge agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring Linux Bridge agent."
conf=/etc/neutron/plugins/ml2/linuxbridge_agent.ini

# Edit the [linux_bridge] section.
set_iface_list
PUBLIC_INTERFACE_NAME=$(ifnum_to_ifname 2)
echo "PUBLIC_INTERFACE_NAME=$PUBLIC_INTERFACE_NAME"
iniset_sudo $conf linux_bridge physical_interface_mappings provider:$PUBLIC_INTERFACE_NAME

# Edit the [vxlan] section.
OVERLAY_INTERFACE_IP_ADDRESS=$(get_node_ip_in_network "$(hostname)" "mgmt")
iniset_sudo $conf vxlan enable_vxlan true
iniset_sudo $conf vxlan local_ip $OVERLAY_INTERFACE_IP_ADDRESS
iniset_sudo $conf vxlan l2_population true

# Edit the [securitygroup] section.
iniset_sudo $conf securitygroup enable_security_group true
iniset_sudo $conf securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

echo "Ensuring that the kernel supports network bridge filters."
if ! sudo sysctl net.bridge.bridge-nf-call-iptables; then
    sudo modprobe br_netfilter
    echo "# bridge support module added by training-labs" >> /etc/modules
    echo br_netfilter >> /etc/modules
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the layer-3 agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the layer-3 agent."
conf=/etc/neutron/l3_agent.ini
iniset_sudo $conf DEFAULT interface_driver linuxbridge

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the DHCP agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the DHCP agent."
conf=/etc/neutron/dhcp_agent.ini
iniset_sudo $conf DEFAULT interface_driver linuxbridge
iniset_sudo $conf DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
iniset_sudo $conf DEFAULT enable_isolated_metadata true

# Not in install-guide:
iniset_sudo $conf DEFAULT dnsmasq_config_file /etc/neutron/dnsmasq-neutron.conf

cat << DNSMASQ | sudo tee /etc/neutron/dnsmasq-neutron.conf
# Override --no-hosts dnsmasq option supplied by neutron
addn-hosts=/etc/hosts

# Log dnsmasq queries to syslog
log-queries

# Verbose logging for DHCP
log-dhcp
DNSMASQ
