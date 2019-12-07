#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Install and configure controller node
# https://docs.openstack.org/neutron/train/install/controller-install-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Setting up database for neutron."
setup_database neutron "$NEUTRON_DB_USER" "$NEUTRON_DBPASS"

source "$CONFIG_DIR/admin-openstackrc.sh"

neutron_admin_user=neutron

# Wait for keystone to come up
wait_for_keystone

echo "Creating neutron user and giving it admin role under service tenant."
openstack user create \
    --domain default  \
    --password "$NEUTRON_PASS" \
    "$neutron_admin_user"

openstack role add \
    --project "$SERVICE_PROJECT_NAME" \
    --user "$neutron_admin_user" \
    "$ADMIN_ROLE_NAME"

echo "Registering neutron with keystone so that other services can locate it."
openstack service create \
    --name neutron \
    --description "OpenStack Networking" \
    network

openstack endpoint create \
    --region "$REGION" \
    network \
    public http://controller:9696

openstack endpoint create \
    --region "$REGION" \
    network \
    internal http://controller:9696

openstack endpoint create \
    --region "$REGION" \
    network \
    public http://controller:9696
