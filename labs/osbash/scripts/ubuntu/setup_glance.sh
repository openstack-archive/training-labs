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
# http://docs.openstack.org/liberty/install-guide-ubuntu/glance-install.html
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

echo "Installing glance."
sudo apt-get install -y glance python-glanceclient

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
iniset_sudo $conf keystone_authtoken auth_plugin password
iniset_sudo $conf keystone_authtoken project_domain_id default
iniset_sudo $conf keystone_authtoken user_domain_id default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$glance_admin_user"
iniset_sudo $conf keystone_authtoken password "$GLANCE_PASS"

# Paste_deploy
iniset_sudo $conf paste_deploy flavor "keystone"

# Glance_store
iniset_sudo $conf glance_store default_store file
iniset_sudo $conf glance_store filesystem_store_datadir /var/lib/glance/images/

# Default section
iniset_sudo $conf DEFAULT notification_driver noop
iniset_sudo $conf DEFAULT verbose "$OPENSTACK_VERBOSE"

echo "Configuring glance-registry.conf."
conf=/etc/glance/glance-registry.conf

# Database section
iniset_sudo $conf database connection "$database_url"

# Keystone authtoken section
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken auth_plugin password
iniset_sudo $conf keystone_authtoken project_domain_id default
iniset_sudo $conf keystone_authtoken user_domain_id default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$glance_admin_user"
iniset_sudo $conf keystone_authtoken password "$GLANCE_PASS"

# Paste deploy section
iniset_sudo $conf paste_deploy flavor "keystone"

# Default section
iniset_sudo $conf DEFAULT notification_driver noop
iniset_sudo $conf DEFAULT verbose "$OPENSTACK_VERBOSE"

echo "Creating the database tables for glance."
sudo glance-manage db_sync

echo "Restarting glance service."
sudo service glance-registry restart
sudo service glance-api restart

echo "Removing default SQLite database."
sudo rm -f /var/lib/glance/glance.sqlite

#------------------------------------------------------------------------------
# Verify the Image Service installation
# http://docs.openstack.org/liberty/install-guide-ubuntu/glance-verify.html
#------------------------------------------------------------------------------

# Our openstackrc.sh files already set OS_IMAGE_API_VERSION, we can skip this
# step in the install-guide.

echo "Waiting for glance to start."
until glance image-list >/dev/null 2>&1; do
    sleep 1
done

# cirros-0.3.4-x86_64-disk.img -> cirros-0.3.4-x86_64
img_name=$(basename $CIRROS_URL -disk.img)

echo "Adding CirrOS image as $img_name to glance."

glance image-create \
    --name "$img_name" \
    --file "$HOME/img/$(basename $CIRROS_URL)" \
    --disk-format qcow2 \
    --container-format bare \
    --visibility public \
    --progress

echo "Verifying that the image was successfully added to the service."

echo "glance image-list"
glance image-list
