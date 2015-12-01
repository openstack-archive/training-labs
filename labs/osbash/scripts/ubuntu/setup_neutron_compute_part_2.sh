#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Set up OpenStack Networking (neutron) for compute node.
# http://docs.openstack.org/liberty/install-guide-ubuntu/neutron-compute-install.html
#------------------------------------------------------------------------------

neutron_admin_user=$(service_to_user_name neutron)
neutron_admin_password=$(service_to_user_password neutron)

echo "Configuring Compute to use Networking."
conf=/etc/nova/nova.conf
iniset_sudo $conf neutron url http://controller:9696
iniset_sudo $conf neutron auth_url http://controller:35357
iniset_sudo $conf neutron auth_plugin password
iniset_sudo $conf neutron project_domain_id default
iniset_sudo $conf neutron user_domain_id default
iniset_sudo $conf neutron region_name "$REGION"
iniset_sudo $conf neutron project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf neutron username "$neutron_admin_user"
iniset_sudo $conf neutron password "$neutron_admin_password"

echo "Restarting the Compute service."
sudo service nova-compute restart

echo "Restarting neutron-plugin-linuxbridge-agent."
sudo service neutron-plugin-linuxbridge-agent restart

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

echo "neutron agent-list"
neutron agent-list
