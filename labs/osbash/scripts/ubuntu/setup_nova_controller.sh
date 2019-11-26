#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Install Compute controller services
# https://docs.openstack.org/nova/train/install/controller-install-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Setting up database nova."
setup_database nova "$NOVA_DB_USER" "$NOVA_DBPASS"

echo "Setting up database nova_api."
setup_database nova_api "$NOVA_DB_USER" "$NOVA_DBPASS"

echo "Setting up first cell database."
# nova_cell0 is default name for first cell database
# https://docs.openstack.org/developer/nova/cells.html#fresh-install
setup_database nova_cell0 "$NOVA_DB_USER" "$NOVA_DBPASS"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

nova_admin_user=nova
placement_admin_user=placement

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
    compute public http://controller:8774/v2.1

openstack endpoint create \
    --region "$REGION" \
    compute internal http://controller:8774/v2.1

openstack endpoint create \
    --region "$REGION" \
    compute admin http://controller:8774/v2.1

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing nova for controller node."
sudo apt install -y nova-api nova-conductor nova-novncproxy nova-scheduler

conf=/etc/nova/nova.conf

# Configure [api_database] section.
database_url="mysql+pymysql://$NOVA_DB_USER:$NOVA_DBPASS@controller/nova_api"
echo "Setting API database connection: $database_url."
iniset_sudo $conf api_database connection "$database_url"

# Configure [database] section.
database_url="mysql+pymysql://$NOVA_DB_USER:$NOVA_DBPASS@controller/nova"
echo "Setting database connection: $database_url."
iniset_sudo $conf database connection "$database_url"

echo "Configuring nova services."

echo "Configuring RabbitMQ message queue access."
iniset_sudo $conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@controller:5672"

# Configure [api] section.
iniset_sudo $conf api auth_strategy keystone

# Configure [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken www_authenticate_uri http://controller:5000/
iniset_sudo $conf keystone_authtoken auth_url http://controller:5000/
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name Default
iniset_sudo $conf keystone_authtoken user_domain_name Default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$nova_admin_user"
iniset_sudo $conf keystone_authtoken password "$NOVA_PASS"

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT my_ip "$(hostname_to_ip controller)"
iniset_sudo $conf DEFAULT use_neutron true
iniset_sudo $conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

# Configure [VNC] section.
iniset_sudo $conf vnc enabled true
iniset_sudo $conf vnc server_listen '$my_ip'
iniset_sudo $conf vnc server_proxyclient_address '$my_ip'

# Configure [glance] section.
iniset_sudo $conf glance api_servers http://controller:9292

# Configure [oslo_concurrency] section.
iniset_sudo $conf oslo_concurrency lock_path /var/lib/nova/tmp

# Delete log_dir line
# According to the install-guide, "Due to a packaging bug, remove the log_dir
# option from the [DEFAULT] section."
sudo grep "^log_dir" $conf
sudo sed -i "/^log_dir/ d" $conf

echo "Configuring access to the Placement service."
iniset_sudo $conf placement region_name RegionOne
iniset_sudo $conf placement project_domain_name Default
iniset_sudo $conf placement project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf placement auth_type password
iniset_sudo $conf placement user_domain_name Default
iniset_sudo $conf placement auth_url http://controller:5000/v3
iniset_sudo $conf placement username "$placement_admin_user"
iniset_sudo $conf placement password "$PLACEMENT_PASS"

echo "Populating the nova-api databases."
sudo nova-manage api_db sync

echo "Registering the cell0 database."
sudo nova-manage cell_v2 map_cell0

echo "Creating the cell1 cell."
sudo nova-manage cell_v2 create_cell --name=cell1 --verbose

echo "Populating the nova database."
sudo nova-manage db sync

echo "Verifying nova cell0 and cell1 are registered correctly."
sudo nova-manage cell_v2 list_cells

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

# Wait for keystone to come up
wait_for_keystone

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Finalize installation
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Restarting nova services."
declare -a nova_services=(nova-api nova-scheduler nova-conductor \
    nova-novncproxy)

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

echo -n "Verifying operation of the Compute service."
until openstack service list 2>/dev/null; do
    sleep 1
    echo -n .
done
echo

echo "Checking nova endpoints."
openstack catalog list

echo "Checking nova images."
openstack image list
