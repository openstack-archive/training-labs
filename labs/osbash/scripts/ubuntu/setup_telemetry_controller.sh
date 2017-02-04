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
# http://docs.openstack.org/project-install-guide/telemetry/newton/install-base-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Create Ceilometer user and database.
ceilometer_admin_user=ceilometer

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
sudo apt install -y ceilometer-api ceilometer-collector \
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
iniset_sudo $conf service_credentials auth_type password
iniset_sudo $conf service_credentials os_auth_url http://controller:5000/v3
iniset_sudo $conf service_credentials project_domain_name default
iniset_sudo $conf service_credentials user_domain_name default
iniset_sudo $conf service_credentials project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf service_credentials username "$ceilometer_admin_user"
iniset_sudo $conf service_credentials password "$CEILOMETER_PASS"
iniset_sudo $conf service_credentials interface internalURL
iniset_sudo $conf service_credentials region_name "$REGION"

# FIXME /var/www/cgi-bin/ceilometer/app does not exist
echo "Creating /etc/apache2/sites-available/wsgi-ceilometer.conf"
cat << WSGI | sudo tee -a /etc/apache2/sites-available/wsgi-ceilometer.conf
Listen 8777

<VirtualHost *:8777>
    WSGIDaemonProcess ceilometer-api processes=1 threads=5 user=ceilometer group=ceilometer display-name=%{GROUP}
    WSGIProcessGroup ceilometer-api
    WSGIScriptAlias / "/var/www/cgi-bin/ceilometer/app"
    WSGIApplicationGroup %{GLOBAL}
    ErrorLog /var/log/apache2/ceilometer_error.log
    CustomLog /var/log/apache2/ceilometer_access.log combined
</VirtualHost>

WSGISocketPrefix /var/run/apache2
WSGI

echo "Enabling the Telemetry service virtual hosts."

# FIXME The documentation uses ceilometer here
# https://bugs.launchpad.net/ceilometer/+bug/1631629
sudo a2ensite wsgi-ceilometer

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Reloading the Apache HTTP server."
sudo service apache2 reload

echo "Restarting telemetry service."
sudo service ceilometer-agent-central restart
sudo service ceilometer-agent-notification restart
sudo service ceilometer-collector restart

#------------------------------------------------------------------------------
# Enable Image service meters
# http://docs.openstack.org/project-install-guide/telemetry/newton/configure_services/glance/install-glance-ubuntu.html
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

echo "Restarting the Image service."
sudo service glance-registry restart
sudo service glance-api restart

#------------------------------------------------------------------------------
# Enable Block Storage meters
# http://docs.openstack.org/project-install-guide/telemetry/newton/configure_services/cinder/install-cinder-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure Cinder to use Telemetry
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

conf=/etc/cinder/cinder.conf
echo "Configuring $conf."

# Configure [oslo_messaging_notifications] section.
iniset_sudo $conf oslo_messaging_notifications driver messagingv2

echo "Restarting the Block Storage services on the controller node."
sudo service cinder-api restart
sudo service cinder-scheduler restart
