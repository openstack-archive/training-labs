#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/openstack"
source "$LIB_DIR/functions.guest.sh"

indicate_current_auto

exec_logfile

# Upgrade installed packages
sudo yum -y update
