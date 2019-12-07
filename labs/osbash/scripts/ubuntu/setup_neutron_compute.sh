#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/admin-openstackrc.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Install and configure compute node
# https://docs.openstack.org/neutron/train/install/compute-install-ubuntu.html
#------------------------------------------------------------------------------

echo "Installing networking components for compute node."
sudo apt install -y neutron-linuxbridge-agent

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the common component
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring neutron for compute node."

conf=/etc/neutron/neutron.conf
echo "Configuring $conf."

echo "Configuring RabbitMQ message queue access."
iniset_sudo $conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@controller"

# Configuring [DEFAULT] section
iniset_sudo $conf DEFAULT auth_strategy keystone

neutron_admin_user=neutron

# Configuring [keystone_authtoken] section
iniset_sudo $conf keystone_authtoken www_authenticate_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:5000
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$neutron_admin_user"
iniset_sudo $conf keystone_authtoken password "$NEUTRON_PASS"

# lock_path, not in install-guide:
iniset_sudo $conf oslo_concurrency lock_path /var/lib/neutron/tmp
