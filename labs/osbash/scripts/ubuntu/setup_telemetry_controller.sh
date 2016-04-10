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
# Install the Telemetry service
# http://docs.openstack.org/mitaka/install-guide-ubuntu/ceilometer-install.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Create Ceilometer user and database.
ceilometer_admin_user=$(service_to_user_name ceilometer)

mongodb_user=$CEILOMETER_DB_USER

echo "Creating the ceilometer database."
mongo --host controller --eval "
    db = db.getSiblingDB(\"ceilometer\");
    db.addUser({user: \"${mongodb_user}\",
    pwd: \"${CEILOMETER_DBPASS}\",
    roles: [ \"readWrite\", \"dbAdmin\" ]})"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

# Wait for keystone to come up
wait_for_keystone

echo "Creating ceilometer user and giving it admin role under service tenant."
openstack user create \
    --domain default \
    --password "$CEILOMETER_PASS" \
    "$ceilometer_admin_user"

openstack role add \
    --project "$SERVICE_PROJECT_NAME" \
    --user "$ceilometer_admin_user" \
    "$ADMIN_ROLE_NAME"

echo "Registering ceilometer with keystone so that other services can locate it."
openstack service create \
    --name ceilometer \
    --description "Telemetry" \
    metering

openstack endpoint create \
    --region "$REGION" \
    metering \
    public http://controller:8777

openstack endpoint create \
    --region "$REGION" \
    metering \
    internal http://controller:8777

openstack endpoint create \
    --region "$REGION" \
    metering \
    admin http://controller:8777

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing ceilometer."
sudo apt-get install -y ceilometer-api ceilometer-collector \
                        ceilometer-agent-central \
                        ceilometer-agent-notification \
                        python-ceilometerclient

function get_database_url {
    local database_host=controller

    echo "mongodb://$mongodb_user:$CEILOMETER_DBPASS@$database_host:27017/ceilometer"
}

database_url=$(get_database_url)
echo "Database connection: $database_url."

echo "Configuring ceilometer.conf."
conf=/etc/ceilometer/ceilometer.conf
iniset_sudo $conf database connection "$database_url"

# Configure RabbitMQ variables
iniset_sudo $conf DEFAULT rpc_backend rabbit

iniset_sudo $conf oslo_messaging_rabbit rabbit_host controller
iniset_sudo $conf oslo_messaging_rabbit rabbit_userid openstack
iniset_sudo $conf oslo_messaging_rabbit rabbit_password "$RABBIT_PASS"

# Configure the [DEFAULT] section
iniset_sudo $conf DEFAULT auth_strategy keystone

# Configure [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$ceilometer_admin_user"
iniset_sudo $conf keystone_authtoken password "$CEILOMETER_PASS"

# Configure [service_credentials] section.
iniset_sudo $conf service_credentials os_auth_url http://controller:5000/v2.0
iniset_sudo $conf service_credentials os_username "$ceilometer_admin_user"
iniset_sudo $conf service_credentials os_tenant_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf service_credentials os_password "$CEILOMETER_PASS"
iniset_sudo $conf service_credentials interface internalURL
iniset_sudo $conf service_credentials region_name "$REGION"

iniset_sudo $conf DEFAULT verbose True

echo "Restarting telemetry service."
sudo service ceilometer-agent-central restart
sudo service ceilometer-agent-notification restart
sudo service ceilometer-api restart
sudo service ceilometer-collector restart

#------------------------------------------------------------------------------
# Enable Image service meters
# http://docs.openstack.org/mitaka/install-guide-ubuntu/ceilometer-glance.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Image service to use Telemetry
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

conf=/etc/glance/glance-api.conf
echo "Configuring $conf."

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT rpc_backend rabbit

# Configure [oslo_messaging_notifications] section.
iniset_sudo $conf oslo_messaging_notifications driver messagingv2

# Configure [oslo_messaging_rabbit] section.
iniset_sudo $conf oslo_messaging_rabbit rabbit_host controller
iniset_sudo $conf oslo_messaging_rabbit rabbit_userid openstack
iniset_sudo $conf oslo_messaging_rabbit rabbit_password "$RABBIT_PASS"

conf=/etc/glance/glance-registry.conf
echo "Configuring $conf."

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT rpc_backend rabbit

# Configure [oslo_messaging_notifications] section.
iniset_sudo $conf oslo_messaging_notifications driver messagingv2

# Configure [oslo_messaging_rabbit] section.
iniset_sudo $conf oslo_messaging_rabbit rabbit_host controller
iniset_sudo $conf oslo_messaging_rabbit rabbit_userid openstack
iniset_sudo $conf oslo_messaging_rabbit rabbit_password "$RABBIT_PASS"

sudo service glance-registry restart
sudo service glance-api restart

#------------------------------------------------------------------------------
# Enable Block Storage meters
# http://docs.openstack.org/mitaka/install-guide-ubuntu/ceilometer-cinder.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure Cinder to use Telemetry
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

conf=/etc/cinder/cinder.conf
echo "Configuring $conf."

# Configure [oslo_messaging_notifications] section.
iniset_sudo $conf oslo_messaging_notifications notification_driver messagingv2

echo "Restarting cinder services."
sudo service cinder-api restart
sudo service cinder-scheduler restart
