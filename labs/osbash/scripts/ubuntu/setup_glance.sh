#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Install the Image Service (glance).
# https://docs.openstack.org/glance/train/install/install-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Setting up database for glance."
setup_database glance "$GLANCE_DB_USER" "$GLANCE_DBPASS"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

glance_admin_user=glance

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

echo "Registering glance with keystone so that other services can locate it."
openstack service create \
    --name glance \
    --description "OpenStack Image" \
    image

echo "Creating the Image service API endpoints."
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
sudo apt install -y glance

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
iniset_sudo $conf keystone_authtoken www_authenticate_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:5000
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name Default
iniset_sudo $conf keystone_authtoken user_domain_name Default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$glance_admin_user"
iniset_sudo $conf keystone_authtoken password "$GLANCE_PASS"

# Paste_deploy
iniset_sudo $conf paste_deploy flavor "keystone"

# glance_store
iniset_sudo $conf glance_store stores "file,http"
iniset_sudo $conf glance_store default_store file
iniset_sudo $conf glance_store filesystem_store_datadir /var/lib/glance/images/

echo "Creating the database tables for glance."
sudo glance-manage db_sync

echo "Restarting glance service."
sudo service glance-api restart

#------------------------------------------------------------------------------
# Verify the Image Service installation
# https://docs.openstack.org/glance/train/install/verify.html
#------------------------------------------------------------------------------

echo -n "Waiting for glance to start."
until openstack image list >/dev/null 2>&1; do
    sleep 1
    echo -n .
done
echo

echo "Adding pre-downloaded CirrOS image as $CIRROS_IMG_NAME to glance."

# XXX install-guide changed from openstack to glance client, but did not
#     change --public to --visibility public
glance image-create --name "$CIRROS_IMG_NAME" \
    --file "$HOME/img/$(basename $CIRROS_URL)" \
    --disk-format qcow2 --container-format bare \
    --visibility public

echo "Verifying that the image was successfully added to the service."

echo "glance image-list"
glance image-list
