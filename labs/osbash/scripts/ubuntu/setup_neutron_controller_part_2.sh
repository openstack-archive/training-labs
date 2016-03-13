#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Set up OpenStack Networking (neutron) for controller node.
# http://docs.openstack.org/mitaka/install-guide-ubuntu/neutron-controller-install.html
#------------------------------------------------------------------------------

source "$CONFIG_DIR/admin-openstackrc.sh"

neutron_admin_user=$(service_to_user_name neutron)

# Wait for keystone to come up
wait_for_keystone

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the metadata agent
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring the metadata agent."
conf=/etc/neutron/metadata_agent.ini
iniset_sudo $conf DEFAULT auth_uri http://controller:5000
iniset_sudo $conf DEFAULT auth_url http://controller:35357
iniset_sudo $conf DEFAULT auth_region "$REGION"
iniset_sudo $conf DEFAULT auth_type password
iniset_sudo $conf DEFAULT project_domain_name default
iniset_sudo $conf DEFAULT user_domain_name default
iniset_sudo $conf DEFAULT project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf DEFAULT username "$neutron_admin_user"
iniset_sudo $conf DEFAULT password "$NEUTRON_PASS"

iniset_sudo $conf DEFAULT nova_metadata_ip controller

iniset_sudo $conf DEFAULT metadata_proxy_shared_secret "$METADATA_SECRET"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure Compute to use Networking
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Configuring Compute to use Networking."
conf=/etc/nova/nova.conf
iniset_sudo $conf neutron url http://controller:9696
iniset_sudo $conf neutron auth_url http://controller:35357
# no complaints without auth_type
#iniset_sudo $conf neutron auth_type password
# without this auth_plugin line, we get
# Unexpected API Error. Please report this at http://bugs.launchpad.net/nova/ and attach the Nova API log if possible.
# <class 'neutronclient.common.exceptions.Unauthorized'> (HTTP 500) (Request-ID: req-1ac10a31-4da0-4bdc-8f9f-7d941b408072)
iniset_sudo $conf neutron auth_plugin password
iniset_sudo $conf neutron project_domain_name default
iniset_sudo $conf neutron user_domain_name default
iniset_sudo $conf neutron region_name "$REGION"
iniset_sudo $conf neutron project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf neutron username "$neutron_admin_user"
iniset_sudo $conf neutron password "$NEUTRON_PASS"

iniset_sudo $conf neutron service_metadata_proxy True
iniset_sudo $conf neutron metadata_proxy_shared_secret "$METADATA_SECRET"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Finalize installation
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sudo neutron-db-manage \
    --config-file /etc/neutron/neutron.conf \
    --config-file /etc/neutron/plugins/ml2/ml2_conf.ini \
    upgrade head

echo "Restarting nova services."
sudo service nova-api restart

echo "Restarting neutron-server."
sudo service neutron-server restart

echo "Restarting neutron-linuxbridge-agent."
sudo service neutron-linuxbridge-agent restart

echo "Restarting neutron-dhcp-agent."
sudo service neutron-dhcp-agent restart

echo "Restarting neutron-metadata-agent."
sudo service neutron-metadata-agent restart

if type neutron-l3-agent; then
    # Installed only for networking option 2 of the install-guide.
    echo "Restarting neutron-l3-agent."
    sudo service neutron-l3-agent restart
fi

echo "Removing default SQLite database."
sudo rm -f /var/lib/neutron/neutron.sqlite

#------------------------------------------------------------------------------
# Set up OpenStack Networking (neutron) for controller node.
# http://docs.openstack.org/mitaka/install-guide-ubuntu/neutron-verify.html
#------------------------------------------------------------------------------

echo "Verifying operation."
until neutron ext-list >/dev/null 2>&1; do
    sleep 1
done

neutron ext-list
