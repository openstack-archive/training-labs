#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

# Wait for keystone to come up
wait_for_keystone

#------------------------------------------------------------------------------
# Install the Orchestration Service (heat)
# https://docs.openstack.org/heat/train/install/install-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Setting up database for heat."
setup_database heat "$HEAT_DB_USER" "$HEAT_DBPASS"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

heat_admin_user=heat

# Wait for keystone to come up
wait_for_keystone

echo "Creating heat user and giving it admin role under service tenant."
openstack user create \
    --domain default \
    --password "$HEAT_PASS" \
    "$heat_admin_user"

openstack role add \
    --project "$SERVICE_PROJECT_NAME" \
    --user "$heat_admin_user" \
    "$ADMIN_ROLE_NAME"

echo "Creating the heat and heat-cfn service entities."
openstack service create \
    --name heat \
    --description "Orchestration" \
    orchestration

openstack service create \
    --name heat-cfn \
    --description "Orchestration" \
    cloudformation

echo "Creating heat and heat-cfn endpoints."
openstack endpoint create \
    --region "$REGION" \
    orchestration public http://controller:8004/v1/%\(tenant_id\)s

openstack endpoint create \
    --region "$REGION" \
    orchestration internal http://controller:8004/v1/%\(tenant_id\)s

openstack endpoint create \
    --region "$REGION" \
    orchestration admin http://controller:8004/v1/%\(tenant_id\)s

openstack endpoint create  \
    --region "$REGION" \
    cloudformation public http://controller:8000/v1

openstack endpoint create  \
    --region "$REGION" \
    cloudformation internal http://controller:8000/v1

openstack endpoint create  \
    --region "$REGION" \
    cloudformation admin http://controller:8000/v1

echo "Creating heat domain."
openstack domain create \
    --description "Stack projects and users" \
    heat

echo "Creating heat_domain_admin user."
openstack user create \
    --domain heat \
    --password "$HEAT_DOMAIN_PASS" \
    heat_domain_admin

openstack role add \
    --domain heat \
    --user-domain heat \
    --user heat_domain_admin \
    "$ADMIN_ROLE_NAME"

echo "Creating the heat_stack_owner role."
openstack role create "heat_stack_owner"

openstack role add \
    --project "$DEMO_PROJECT_NAME" \
    --user "$DEMO_USER_NAME" \
    "heat_stack_owner"

echo "Creating the heat_stack_user role."
openstack role create "heat_stack_user"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing heat."

sudo apt install -y heat-api heat-api-cfn heat-engine

function get_database_url {
    local db_user=$HEAT_DB_USER
    local database_host=controller

    echo "mysql+pymysql://$db_user:$HEAT_DBPASS@$database_host/heat"
}

database_url=$(get_database_url)
echo "Database connection: $database_url."

echo "Configuring heat.conf."
conf=/etc/heat/heat.conf
iniset_sudo $conf database connection "$database_url"

echo "Configuring keystone."

echo "Configuring RabbitMQ message queue access."
iniset_sudo $conf DEFAULT transport_url "rabbit://openstack:$RABBIT_PASS@controller"

# Configure [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken www_authenticate_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:5000
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$heat_admin_user"
iniset_sudo $conf keystone_authtoken password "$HEAT_PASS"

# Configure [trustee] section.
iniset_sudo $conf trustee auth_type password
iniset_sudo $conf trustee auth_url http://controller:5000
iniset_sudo $conf trustee username "$heat_admin_user"
iniset_sudo $conf trustee password "$HEAT_PASS"
iniset_sudo $conf trustee user_domain_name default

# Configure [clients_keystone] section.
iniset_sudo $conf clients_keystone auth_uri http://controller:5000

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT heat_metadata_server_url http://controller:8000
iniset_sudo $conf DEFAULT heat_waitcondition_server_url http://controller:8000/v1/waitcondition

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT stack_domain_admin heat_domain_admin
iniset_sudo $conf DEFAULT stack_domain_admin_password "$HEAT_DOMAIN_PASS"
iniset_sudo $conf DEFAULT stack_user_domain_name heat

echo "Creating the database tables for heat."
sudo heat-manage db_sync

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Finalize installation
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Restarting heat services."
STARTTIME=$(date +%s)
sudo service heat-api restart
sudo service heat-api-cfn restart
sudo service heat-engine restart

echo -n "Waiting for openstack stack list."
until openstack stack list; do
    sleep 1
    echo -n .
done
ENDTIME=$(date +%s)
echo "Restarting heat servies took $((ENDTIME - STARTTIME)) seconds."

#------------------------------------------------------------------------------
# Verify operation
# https://docs.openstack.org/heat/train/install/verify.html
#------------------------------------------------------------------------------

echo "Listing service components."
openstack orchestration service list
