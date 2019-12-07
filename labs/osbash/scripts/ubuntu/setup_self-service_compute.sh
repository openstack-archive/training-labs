#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Networking Option 2: Self-service networks
# https://docs.openstack.org/neutron/train/install/compute-install-option2-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Linux bridge agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the Linux bridge agent."
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
