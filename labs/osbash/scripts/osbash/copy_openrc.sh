#!/usr/bin/env bash
set -o errexit -o nounset

# This script copies the openrc.sh credentials files to the home directory
# in order to make them easier to find for the user.

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"
source "$CONFIG_DIR/credentials"

indicate_current_auto

exec_logfile

# We replace the hostname "controller" with the equivalent IP address to
# make the openrc file work on the user's host machine without them
# changing their /etc/hosts
CONTROLLER_MGMT_IP=$(get_node_ip_in_network "controller" "mgmt")

# Replace variables with constants and keep only lines starting with "export"

cat "$CONFIG_DIR/admin-openstackrc.sh" | sed -ne "
    s/\$ADMIN_PROJECT_NAME/$ADMIN_PROJECT_NAME/
    s/\$ADMIN_USER_NAME/$ADMIN_USER_NAME/
    s/\$ADMIN_PASS/$ADMIN_PASS/
    s/controller/$CONTROLLER_MGMT_IP/
    /^export/p
    " > "$HOME/admin-openrc.sh"

cat "$CONFIG_DIR/demo-openstackrc.sh" | sed -ne "
    s/\$DEMO_PROJECT_NAME/$DEMO_PROJECT_NAME/
    s/\$DEMO_USER_NAME/$DEMO_USER_NAME/
    s/\$DEMO_PASS/$DEMO_PASS/
    s/controller/$CONTROLLER_MGMT_IP/
    /^export/p
    " > "$HOME/demo-openrc.sh"
