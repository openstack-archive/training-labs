#!/usr/bin/env bash
set -o errexit -o nounset

# This script copies the openrc.sh credentials files to the home directory
# in order to make them easier to find for the user.

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"
source "$CONFIG_DIR/credentials"

indicate_current_auto

exec_logfile

# We replace the hostname "controller" with the equivalent IP address to
# make the openrc file work on the user's host machine without them
# changing their /etc/hosts
MY_MGMT_IP=$(get_node_ip_in_network "$(hostname)" "mgmt")

# Replace variables with constants and remove lines used to fill in variables

cat "$CONFIG_DIR/admin-openstackrc.sh" | sed -e "
    /BASH_SOURCE/d
    /^source/d
    s/\$ADMIN_PROJECT_NAME/$ADMIN_PROJECT_NAME/
    s/\$ADMIN_USER_NAME/$ADMIN_USER_NAME/
    s/\$ADMIN_PASS/$ADMIN_PASS/
    s/controller/$MY_MGMT_IP/
    " > "$HOME/admin-openrc.sh"

cat "$CONFIG_DIR/demo-openstackrc.sh" | sed -e "
    /BASH_SOURCE/d
    /^source/d
    s/\$DEMO_PROJECT_NAME/$DEMO_PROJECT_NAME/
    s/\$DEMO_USER_NAME/$DEMO_USER_NAME/
    s/\$DEMO_PASS/$DEMO_PASS/
    s/controller/$MY_MGMT_IP/
    " > "$HOME/demo-openrc.sh"
