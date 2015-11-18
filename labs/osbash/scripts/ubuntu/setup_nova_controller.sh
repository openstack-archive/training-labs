#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest"
exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Install Compute controller services
# http://docs.openstack.org/kilo/install-guide/install/apt/content/ch_nova.html#nova-controller-install
#------------------------------------------------------------------------------

echo "Setting up database for nova."
setup_database nova

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

nova_admin_user=$(service_to_user_name nova)
nova_admin_password=$(service_to_user_password nova)

# Wait for keystone to come up
wait_for_keystone

echo "Creating nova user and giving it the admin role."
openstack user create \
    --password "$nova_admin_password" \
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

openstack endpoint create \
    --publicurl 'http://controller-api:8774/v2/%(tenant_id)s' \
    --internalurl 'http://controller-mgmt:8774/v2/%(tenant_id)s' \
    --adminurl 'http://controller-mgmt:8774/v2/%(tenant_id)s' \
    --region "$REGION" \
    compute

echo "Installing nova for controller node."
sudo apt-get install -y \
    nova-api nova-cert nova-conductor nova-consoleauth \
    nova-novncproxy nova-scheduler python-novaclient

function get_database_url {
    local db_user=$(service_to_db_user nova)
    local db_password=$(service_to_db_password nova)
    local database_host=controller-mgmt

    echo "mysql://$db_user:$db_password@$database_host/nova"
}

database_url=$(get_database_url)

conf=/etc/nova/nova.conf

echo "Setting database connection: $database_url."
iniset_sudo $conf database connection "$database_url"

echo "Configuring nova services."

# Default Section.
iniset_sudo $conf DEFAULT rpc_backend rabbit

# oslo_messaging_rabbit section.
iniset_sudo $conf oslo_messaging_rabbit rabbit_host controller-mgmt
iniset_sudo $conf oslo_messaging_rabbit rabbit_userid openstack
iniset_sudo $conf oslo_messaging_rabbit rabbit_password "$RABBIT_PASSWORD"


iniset_sudo $conf DEFAULT auth_strategy keystone

# Configure keystone_authtoken section.
iniset_sudo $conf keystone_authtoken auth_uri http://controller-mgmt:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller-mgmt:35357
iniset_sudo $conf keystone_authtoken auth_plugin password
iniset_sudo $conf keystone_authtoken project_domain_id default
iniset_sudo $conf keystone_authtoken user_domain_id default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$nova_admin_user"
iniset_sudo $conf keystone_authtoken password "$nova_admin_password"

# Default section
iniset_sudo $conf DEFAULT my_ip "$(hostname_to_ip controller-mgmt)"
iniset_sudo $conf DEFAULT vncserver_listen controller-mgmt
iniset_sudo $conf DEFAULT vncserver_proxyclient_address controller-mgmt

# Glance section
iniset_sudo $conf glance host controller-mgmt

# oslo_concurrency section
iniset_sudo $conf oslo_concurrency lock_path /var/lib/nova/tmp

# default section
iniset_sudo $conf DEFAULT verbose True

echo "Creating the database tables for nova."
sudo nova-manage db sync

echo "Restarting nova services."
declare -a nova_services=(nova-api nova-cert nova-consoleauth \
    nova-scheduler nova-conductor nova-novncproxy)

for nova_service in "${nova_services[@]}"; do
    echo "Restarting $nova_service"
    sudo service "$nova_service" restart
done

# Remove SQLite database created by Ubuntu package for nova.
sudo rm -v /var/lib/nova/nova.sqlite

#------------------------------------------------------------------------------
# Verify the Compute controller installation
#------------------------------------------------------------------------------

echo "Verify nova service status."
# This call needs root privileges for read access to /etc/nova/nova.conf.
echo "sudo nova-manage service list"
sudo nova-manage service list

echo "nova service-list"
nova service-list

echo "nova endpoints"
nova endpoints

echo "nova image-list"
nova image-list

echo "nova list-extensions"
nova list-extensions
