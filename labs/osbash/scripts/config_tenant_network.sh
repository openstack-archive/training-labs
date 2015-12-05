#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Create tenant network
# http://docs.openstack.org/kilo/install-guide/install/apt/content/neutron_initial-tenant-network.html
#------------------------------------------------------------------------------

echo "Sourcing the demo credentials."
source "$CONFIG_DIR/demo-openstackrc.sh"

# Wait for neutron to start
wait_for_neutron

echo "Creating the tenant network."
neutron net-create demo-net

echo "Creating a subnet on the tenant network."
neutron subnet-create demo-net \
    "$TENANT_NETWORK_CIDR" \
    --name demo-subnet \
    --dns-nameserver "$TENANT_VM_DNS_SERVER" \
    --gateway "$TENANT_NETWORK_GATEWAY"

echo "Creating a router on the tenant network."
neutron router-create demo-router

echo "Attaching the router to the demo tenant subnet."
neutron router-interface-add demo-router demo-subnet

echo "Attaching the router to the external network by setting it as the" \
    "gateway."
neutron router-gateway-set demo-router ext-net
