#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

source "$CONFIG_DIR/credentials"

#------------------------------------------------------------------------------
# Install Barbican, loosely following
# https://github.com/cloudkeep/barbican/wiki/Barbican-Quick-Start-Guide
# https://wiki.openstack.org/wiki/Barbican/Documentation#Installation_Guides
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

BARBICAN_DB_USER=barbican
BARBICAN_DBPASS=barbican_db_secret
BARBICAN_PASS=barbican_user_secret

echo "Setting up database for barbican."
setup_database barbican "$BARBICAN_DB_USER" "$BARBICAN_DBPASS"

# This script is not part of the standard install, cache may be stale by now.
sudo apt update

echo "Installing barbican packages."
sudo apt install -y barbican-api barbican-worker barbican-keystone-listener

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

barbican_admin_user=barbican

echo -e "\n>>> Creating a barbican user with admin privileges.\n"

openstack user create \
    --domain Default  \
    --password "$BARBICAN_PASS" \
    "$barbican_admin_user"

echo -e "\n>>> Adding admin role to service project for barbican user.\n"

openstack role add \
    --project service \
    --user "$barbican_admin_user" \
    admin

echo -e "\n>>> Creating the barbican service.\n"

openstack service create \
    --name barbican \
    --description "Barbican Service" \
    "key-manager"

echo -e "\n>>> Add endpoints for barbican.\n"

openstack endpoint create \
    --region RegionOne "key-manager" \
    public http://controller:9311/

openstack endpoint create \
    --region RegionOne "key-manager" \
    internal http://controller:9311/

# The Ubuntu package configures apache2 to have the admin endpoint on 9312
openstack endpoint create \
    --region RegionOne "key-manager" \
    admin http://controller:9312/

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Mostly follwoing
# https://docs.openstack.org/barbican/pike/configuration/keystone.html
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function get_database_url {
    local db_user=$BARBICAN_DB_USER
    local database_host=controller

    echo "mysql+pymysql://$db_user:$BARBICAN_DBPASS@$database_host/barbican"
}

database_url=$(get_database_url)
echo "Database connection: $database_url."

echo "Configuring barbican.conf."
conf=/etc/barbican/barbican.conf
#iniset_sudo $conf DEFAULT sql_connection "$database_url"
iniset_sudo $conf DEFAULT sql_connection "$database_url"

echo "Configuring keystone."

echo "Configuring RabbitMQ message queue access."
TRANSPORT_URL="rabbit://openstack:$RABBIT_PASS@controller"
iniset_sudo $conf DEFAULT transport_url "$TRANSPORT_URL"

sudo cp $conf $conf.bak

# Configure [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken username "$barbican_admin_user"
iniset_sudo $conf keystone_authtoken password "$BARBICAN_PASS"
iniset_sudo $conf keystone_authtoken user_domain_id default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken project_domain_id default
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:5000
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211

# Prevent error "inequivalent arg 'durable' for exchange 'openstack'"
iniset_sudo $conf oslo_messaging_rabbit  amqp_durable_queues False

# Listen for keystone events (such as project deletion) that are relevant
# for barbican.
iniset_sudo $conf keystone_notifications enable True

echo "Starting barbican-keystone-listener."
sudo /etc/init.d/barbican-keystone-listener start

echo "Removing default SQLite database."
sudo rm -v /var/lib/barbican/barbican.sqlite

echo "Showing barbican secret list."
barbican secret list

echo "Getting a token."
token=$(openstack token issue -cid -fvalue)

echo "token: $token"

echo "Using curl, storing a payload string into a barbican secret."
curl -s -H "X-Auth-Token: $token" \
    -X POST -H 'content-type:application/json' -H 'X-Project-Id:12345' \
    -d '{"payload": "my-secret-here", "payload_content_type": "text/plain"}' \
    http://localhost:9311/v1/secrets

echo "Getting URI for secret."
# Assuming the list contains only one item
uri=$(barbican secret list -c"Secret href" -fvalue)
echo "URI: $uri"

echo "Showing payload via curl."
curl -s -H "X-Auth-Token: $token" \
    -H 'Accept: text/plain' -H 'X-Project-Id: 12345' \
    "$uri"

echo "Showing payload using barbican client."
barbican secret get "$uri" --payload -fvalue

echo "Deleting secret."
barbican secret delete "$uri"

echo "Using the barbican client, creating a named barbican secret."
barbican secret store --name test_name

echo "Showing named barbican secret."
barbican secret list --name test_name -cName -fvalue

echo "Getting URI for secret."
uri=$(barbican secret list --name test_name -c"Secret href" -fvalue)

echo "Writing payload."
barbican secret update "$uri" "my_payload"

echo "Showing secret payload."
barbican secret get "$uri"

echo "Showing payload using barbican client."
barbican secret get "$uri" --payload -fvalue

echo "Deleting secret."
barbican secret delete "$uri"
