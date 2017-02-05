#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Install Compute controller services
# http://docs.openstack.org/newton/install-guide-ubuntu/nova-controller-install.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Setting up database nova."
setup_database nova "$NOVA_DB_USER" "$NOVA_DBPASS"

echo "Setting up database nova_api."
setup_database nova_api "$NOVA_DB_USER" "$NOVA_DBPASS"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

nova_admin_user=nova

# Wait for keystone to come up
wait_for_keystone

echo "Creating nova user and giving it the admin role."
openstack user create \
    --domain default  \
    --password "$NOVA_PASS" \
    "$nova_admin_user"

openstack role add \
    --project "$SERVICE_PROJECT_NAME" \
    --user "$nova_admin_user" \
    "$ADMIN_ROLE_NAME"

echo "Creating the nova service entity."
openstack service create \
    --name nova \
    --description "OpenStack Compute" \
    compute

echo "Creating nova endpoints."
openstack endpoint create \
    --region "$REGION" \
    compute public http://controller:8774/v2.1/%\(tenant_id\)s

openstack endpoint create \
    --region "$REGION" \
    compute internal http://controller:8774/v2.1/%\(tenant_id\)s

openstack endpoint create \
    --region "$REGION" \
    compute admin http://controller:8774/v2.1/%\(tenant_id\)s

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing nova for controller node."
sudo apt install -y nova-api nova-conductor nova-consoleauth \
    nova-novncproxy nova-scheduler

conf=/etc/nova/nova.conf

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT enabled_apis osapi_compute,metadata

# Configure [api_database] section.
database_url="mysql+pymysql://$NOVA_DB_USER:$NOVA_DBPASS@controller/nova_api"
echo "Setting API database connection: $database_url."
iniset_sudo $conf api_database connection "$database_url"

# Configure [database] section.
database_url="mysql+pymysql://$NOVA_DB_USER:$NOVA_DBPASS@controller/nova"
echo "Setting database connection: $database_url."
iniset_sudo $conf database connection "$database_url"

echo "Configuring nova services."

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT rpc_backend rabbit

# Configure [oslo_messaging_rabbit] section.
iniset_sudo $conf oslo_messaging_rabbit rabbit_host controller
iniset_sudo $conf oslo_messaging_rabbit rabbit_userid openstack
iniset_sudo $conf oslo_messaging_rabbit rabbit_password "$RABBIT_PASS"

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT auth_strategy keystone

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
iniset_sudo $conf DEFAULT my_ip "$(hostname_to_ip controller)"
iniset_sudo $conf DEFAULT use_neutron True
iniset_sudo $conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

# Configure [VNC] section.
iniset_sudo $conf vnc vncserver_listen '$my_ip'
iniset_sudo $conf vnc vncserver_proxyclient_address '$my_ip'

# Configure [glance] section.
iniset_sudo $conf glance api_servers http://controller:9292

# Configure [oslo_concurrency] section.
iniset_sudo $conf oslo_concurrency lock_path /var/lib/nova/tmp

# Delete logdir line
# According to install-guide, "Due to a packaging bug, remove the logdir option
# from the [DEFAULT] section."
sudo sed -i "/^logdir/ d" $conf

echo "Populating the Compute databases."
sudo nova-manage api_db sync
sudo nova-manage db sync

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Finalize installation
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Restarting nova services."
declare -a nova_services=(nova-api nova-consoleauth nova-scheduler \
    nova-conductor nova-novncproxy)

for nova_service in "${nova_services[@]}"; do
    echo "Restarting $nova_service."
    sudo service "$nova_service" restart
done

# Not in install-guide:
echo "Removing default SQLite database."
sudo rm -v /var/lib/nova/nova.sqlite

#------------------------------------------------------------------------------
# Verify the Compute controller installation (not in install-guide)
#------------------------------------------------------------------------------

echo -n "Verifying operation of the Compuyte service."
until openstack service list 2>/dev/null; do
    sleep 1
    echo -n .
done
echo

echo "Checking nova endpoints."
openstack catalog list

echo "Checking nova images."
openstack image list
