#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Install the Image Service (glance).
# http://docs.openstack.org/mitaka/install-guide-ubuntu/glance-install.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Setting up database for glance."
setup_database glance "$GLANCE_DB_USER" "$GLANCE_DBPASS"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

glance_admin_user=$(service_to_user_name glance)

# Wait for keystone to come up
wait_for_keystone

echo "Creating glance user and giving it admin role under service tenant."
openstack user create \
    --domain default \
    --password "$GLANCE_PASS" \
    "$glance_admin_user"

openstack role add \
    --project "$SERVICE_PROJECT_NAME" \
    --user "$glance_admin_user" \
    "$ADMIN_ROLE_NAME"

# Create glance user
echo "Registering glance with keystone so that other services can locate it."
openstack service create \
    --name glance \
    --description "OpenStack Image Service" \
    image

# Create glance endpoints.
openstack endpoint create \
    --region "$REGION" \
    image public http://controller:9292

openstack endpoint create \
    --region "$REGION" \
    image internal http://controller:9292

openstack endpoint create \
    --region "$REGION" \
    image admin http://controller:9292

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing glance."
sudo apt-get install -y glance

function get_database_url {
    local db_user=$GLANCE_DB_USER
    local database_host=controller

    echo "mysql+pymysql://$db_user:$GLANCE_DBPASS@$database_host/glance"
}

database_url=$(get_database_url)
echo "Database connection: $database_url."

echo "Configuring glance-api.conf."
conf=/etc/glance/glance-api.conf

# Database
iniset_sudo $conf database connection "$database_url"

# Keystone_authtoken
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$glance_admin_user"
iniset_sudo $conf keystone_authtoken password "$GLANCE_PASS"

# Paste_deploy
iniset_sudo $conf paste_deploy flavor "keystone"

# glance_store
iniset_sudo $conf glance_store stores "file,http"
iniset_sudo $conf glance_store default_store file
iniset_sudo $conf glance_store filesystem_store_datadir /var/lib/glance/images/

echo "Configuring glance-registry.conf."
conf=/etc/glance/glance-registry.conf

# Database section
iniset_sudo $conf database connection "$database_url"

# Keystone authtoken section
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$glance_admin_user"
iniset_sudo $conf keystone_authtoken password "$GLANCE_PASS"

# Paste deploy section
iniset_sudo $conf paste_deploy flavor "keystone"

echo "Creating the database tables for glance."
sudo glance-manage db_sync

echo "Restarting glance service."
sudo service glance-registry restart
sudo service glance-api restart

echo "Removing default SQLite database."
sudo rm -f /var/lib/glance/glance.sqlite

#------------------------------------------------------------------------------
# Verify the Image Service installation
# http://docs.openstack.org/mitaka/install-guide-ubuntu/glance-verify.html
#------------------------------------------------------------------------------

# Our openstackrc.sh files already set OS_IMAGE_API_VERSION, we can skip this
# step in the install-guide.

echo -n "Waiting for glance to start."
until openstack image list >/dev/null 2>&1; do
    sleep 1
    echo -n .
done
echo

echo "Adding CirrOS image as $CIRROS_IMG_NAME to glance."

openstack image create "$CIRROS_IMG_NAME" \
    --file "$HOME/img/$(basename $CIRROS_URL)" \
    --disk-format qcow2 --container-format bare \
    --public

echo "Verifying that the image was successfully added to the service."

echo "openstack image list"
openstack image list
