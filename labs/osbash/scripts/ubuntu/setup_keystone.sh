#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$CONFIG_DIR/openstack"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Set up keystone for controller node
# https://docs.openstack.org/keystone/train/install/keystone-install-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Setting up database for keystone."
setup_database keystone "$KEYSTONE_DB_USER" "$KEYSTONE_DBPASS"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Not in install-guide:
echo "Sanity check: local auth should work."
mysql -u keystone -p"$KEYSTONE_DBPASS" keystone -e quit

echo "Sanity check: remote auth should work."
mysql -u keystone -p"$KEYSTONE_DBPASS" keystone -h controller -e quit

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing keystone."
sudo apt install -y keystone

conf=/etc/keystone/keystone.conf
echo "Editing $conf."

function get_database_url {
    local db_user=$KEYSTONE_DB_USER
    local database_host=controller

    echo "mysql+pymysql://$db_user:$KEYSTONE_DBPASS@$database_host/keystone"
}

database_url=$(get_database_url)

echo "Setting database connection: $database_url."
iniset_sudo $conf database connection "$database_url"

echo "Configuring the Fernet token provider."
iniset_sudo $conf token provider fernet

echo "Creating the database tables for keystone."
sudo keystone-manage db_sync

echo "Initializing Fernet key repositories."
sudo keystone-manage fernet_setup \
    --keystone-user keystone \
    --keystone-group keystone

sudo keystone-manage credential_setup \
    --keystone-user keystone \
    --keystone-group keystone

echo "Bootstrapping the Identity service."
sudo keystone-manage bootstrap --bootstrap-password "$ADMIN_PASS" \
    --bootstrap-admin-url http://controller:5000/v3/ \
    --bootstrap-internal-url http://controller:5000/v3/ \
    --bootstrap-public-url http://controller:5000/v3/ \
    --bootstrap-region-id "$REGION"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure the Apache HTTP server
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

conf=/etc/apache2/apache2.conf
echo "Configuring ServerName option in $conf to reference controller node."
echo "ServerName controller" | sudo tee -a $conf


conf=/etc/apache2/sites-enabled/keystone.conf
if [ -f $conf ]; then
    echo "Identity service virtual hosts enabled."
else
    echo "Identity service virtual hosts not enabled."
    exit 1
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Reduce memory usage (not in install-guide)
sudo sed -i --follow-symlinks '/WSGIDaemonProcess/ s/processes=[0-9]*/processes=1/' $conf
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Finalize the installation
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Restarting apache."
sudo service apache2 restart

# Set environment variables for authentication
export OS_USERNAME=$ADMIN_USER_NAME
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=$ADMIN_PROJECT_NAME
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3

#------------------------------------------------------------------------------
# Create a domain, projects, users, and roles
# https://docs.openstack.org/keystone/train/install/keystone-users-ubuntu.html
#------------------------------------------------------------------------------

# Wait for keystone to come up
wait_for_keystone

# Not creating domain because default domain has already been created by
# keystone-manage bootstrap
# openstack domain create --description "An Example Domain" example

echo "Creating service project."
openstack project create --domain default \
    --description "Service Project" \
    "$SERVICE_PROJECT_NAME"

echo "Creating demo project."
openstack project create --domain default \
    --description "Demo Project" \
    "$DEMO_PROJECT_NAME"

echo "Creating demo user."
openstack user create --domain default \
    --password "$DEMO_PASS" \
    "$DEMO_USER_NAME"

echo "Creating the user role."
openstack role create \
    "$USER_ROLE_NAME"

echo "Linking user role to demo project and user."
openstack role add \
    --project "$DEMO_PROJECT_NAME" \
    --user "$DEMO_USER_NAME" \
    "$USER_ROLE_NAME"

#------------------------------------------------------------------------------
# Verify operation
# https://docs.openstack.org/keystone/train/install/keystone-verify-ubuntu.html
#------------------------------------------------------------------------------

echo "Verifying keystone installation."

# From this point on, we are going to use keystone for authentication
unset OS_AUTH_URL OS_PASSWORD

echo "Requesting an authentication token as an admin user."
openstack \
    --os-auth-url http://controller:5000/v3 \
    --os-project-domain-name Default \
    --os-user-domain-name Default \
    --os-project-name "$ADMIN_PROJECT_NAME" \
    --os-username "$ADMIN_USER_NAME" \
    --os-auth-type password \
    --os-password "$ADMIN_PASS" \
    token issue

echo "Requesting an authentication token for the demo user."
openstack \
    --os-auth-url http://controller:5000/v3 \
    --os-project-domain-name Default \
    --os-user-domain-name Default \
    --os-project-name "$DEMO_PROJECT_NAME" \
    --os-username "$DEMO_USER_NAME" \
    --os-auth-type password \
    --os-password "$DEMO_PASS" \
    token issue
