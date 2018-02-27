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
# Use OpenStack client environment script
# http://docs.openstack.org/mitaka/install-guide-ubuntu/keystone-openrc.html
#------------------------------------------------------------------------------

# Test in subshell environment to keep our environment clean
(
echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

echo "Requesting an authentication token."
openstack token issue
)

(
echo "Sourcing the demo user credentials."
source "$CONFIG_DIR/demo-openstackrc.sh"

echo "Requesting an authentication token."
openstack token issue
)
