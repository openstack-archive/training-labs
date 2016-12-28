#!/usr/bin/env bash
set -o errexit -o nounset

# This script copies the openrc.sh credentials files to the home directory
# in order to make them easier to find for the user.

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

indicate_current_auto

exec_logfile

cp -av "$CONFIG_DIR/admin-openstackrc.sh" "$HOME/admin-openrc.sh"
cp -av "$CONFIG_DIR/demo-openstackrc.sh" "$HOME/demo-openrc.sh"
