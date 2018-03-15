#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

source "$CONFIG_DIR/credentials"

#------------------------------------------------------------------------------
# Install Mistral
# https://docs.openstack.org/mistral/pike/install/installation_guide.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

MISTRAL_DB_USER=mistral
MISTRAL_DBPASS=mistral_db_secret
MISTRAL_PASS=mistral_user_secret

echo "Setting up database for mistral."
setup_database mistral "$MISTRAL_DB_USER" "$MISTRAL_DBPASS"

# This script is not part of the standard install, cache may be stale by now.
sudo apt update

echo "Installing mistral packages."
sudo apt install -y debconf-utils

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Authentication server password:
echo mistral-common mistral/admin-password password admin_user_secret | \
    sudo debconf-set-selections

# Password for connection to the RabbitMQ server:
echo mistral-common mistral/rabbit_password password "$RABBIT_PASS" | \
    sudo debconf-set-selections

# Username for connection to the RabbitMQ server:
echo mistral-common mistral/rabbit_userid string openstack | \
    sudo debconf-set-selections

# Set up a database for Mistral?
echo mistral-common mistral/configure_db boolean false | \
    sudo debconf-set-selections

# IP address of your RabbitMQ host:
echo mistral-common mistral/rabbit_host string localhost | \
    sudo debconf-set-selections

# Authentication server username:
echo mistral-common mistral/admin-user string admin | \
    sudo debconf-set-selections

# Authentication server hostname:
echo mistral-common mistral/auth-host string controller | \
    sudo debconf-set-selections

# Authentication server tenant name:
echo mistral-common mistral/admin-tenant-name string admin | \
    sudo debconf-set-selections

sudo apt install -y mistral-common

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Register Mistral in the Keystone endpoint catalog?
echo mistral-api mistral/register-endpoint boolean false | \
    sudo debconf-set-selections

sudo apt install -y mistral-api
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo apt install -y mistral-engine mistral-executor

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

mistral_admin_user=mistral

echo -e "\n>>> Creating a mistral user with admin privileges.\n"

openstack user create \
    --domain Default  \
    --password "$MISTRAL_PASS" \
    "$mistral_admin_user"

echo -e "\n>>> Adding admin role to service project for mistral user.\n"

openstack role add \
    --project service \
    --user "$mistral_admin_user" \
    admin

echo -e "\n>>> Creating the mistral service.\n"

openstack service create \
    --name mistral \
    --description "Mistral Service" \
    "workflowv2"

echo -e "\n>>> Add endpoints for mistral.\n"

openstack endpoint create \
    --region RegionOne "workflowv2" \
    public http://controller:8989/v2

openstack endpoint create \
    --region RegionOne "workflowv2" \
    internal http://controller:8989/v2

openstack endpoint create \
    --region RegionOne "workflowv2" \
    admin http://controller:8989/v2

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function get_database_url {
    local db_user=$MISTRAL_DB_USER
    local database_host=controller

    #echo "mysql://$db_user:$MISTRAL_DBPASS@$database_host:3306/mistral"
    echo "mysql+pymysql://$db_user:$MISTRAL_DBPASS@$database_host/mistral"
}

database_url=$(get_database_url)
echo "Database connection: $database_url."

echo "Configuring mistral.conf."
conf=/etc/mistral/mistral.conf

echo "Configuring keystone."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Mistral Dashboard Installation Guide
# https://docs.openstack.org/mistral/pike/install/dashboard_guide.html
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Mistral Configuration Guide
# https://docs.openstack.org/mistral/pike/configuration/index.html
# https://github.com/openstack/mistral
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sudo cp $conf $conf.bak

# Disable deprecated options
sudo sed -i '/^admin_/ s/^/#/' $conf
sudo sed -i '/^auth_/ s/^/#/' $conf

# Configure [keystone_authtoken] section.
#iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000/v3
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:5000
#iniset_sudo $conf keystone_authtoken identity_uri http://controller:5000

#iniset_sudo $conf keystone_authtoken auth_verison v3

# mistral needs username, password (not admin_user, admin_password)
iniset_sudo $conf keystone_authtoken username "$mistral_admin_user"
#iniset_sudo $conf keystone_authtoken admin_user "$mistral_admin_user"
iniset_sudo $conf keystone_authtoken password "$MISTRAL_PASS"
#iniset_sudo $conf keystone_authtoken admin_password "$MISTRAL_PASS"

#iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
#iniset_sudo $conf keystone_authtoken admin_tenant_name "$SERVICE_PROJECT_NAME"


iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken user_domain_id default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken project_domain_id default
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211

echo "Configuring RabbitMQ message queue access."
TRANSPORT_URL="rabbit://openstack:$RABBIT_PASS@controller"
iniset_sudo $conf DEFAULT transport_url "$TRANSPORT_URL"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

iniset_sudo $conf database connection "$database_url"

iniset_sudo $conf oslo_policy policy_file "/etc/mistral/policy.json"

sudo mistral-db-manage --config-file /etc/mistral/mistral.conf upgrade head

sudo mistral-db-manage --config-file /etc/mistral/mistral.conf populate

sudo systemctl restart mistral-engine
sudo systemctl restart mistral-executor
sudo systemctl restart mistral-api

echo "Removing default SQLite database."
sudo rm -v /var/lib/mistral/mistral.sqlite

# https://docs.openstack.org/mistral/pike/install/mistralclient_guide.html
# Test:
echo -n "Waiting for mistral to come up."
until mistral workbook-list >/dev/null 2>&1; do
    sleep 1
    echo -n .
done
echo

echo "mistral workbook-list"
mistral workbook-list
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# https://github.com/openstack/mistral/blob/master/doc/source/quickstart.rst
cat << WORKFLOW > mistral-workflow.yaml
---
version: "2.0"

my_workflow:
  type: direct

  input:
    - names

  tasks:
    task1:
      with-items: name in <% $.names %>
      action: std.echo output=<% $.name %>
      on-success: task2

    task2:
      action: std.echo output="Done"
WORKFLOW

echo "Creating a workflow from file."
mistral workflow-create mistral-workflow.yaml

workflow_id=$(mistral workflow-get my_workflow -cID -fvalue)

echo "Starting the workflow."
mistral execution-create my_workflow \
        '{"names": ["John", "Mistral", "Ivan", "Crystal"]}'

echo "Getting execution_id."
execution_id=$(mistral execution-list | grep "$workflow_id" | awk '{print $2}')

echo "mistral execution-get $execution_id"
mistral execution-get "$execution_id"

echo "mistral task-list $execution_id"
mistral task-list "$execution_id"

echo "Getting task_id."
task_id=$(mistral task-list "$execution_id" -cID -cName | grep task1 | \
            awk '{print $2}')

echo "mistral task-get-result $task_id"
mistral task-get-result "$task_id"

echo "mistral action-execution-list $task_id"
mistral action-execution-list "$task_id"
