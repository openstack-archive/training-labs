#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# NoSQL database for Ubuntu
# http://docs.openstack.org/project-install-guide/telemetry/newton/database/environment-nosql-database-ubuntu.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install and configure components
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Installing the MongoDB packages."
sudo apt install -y mongodb-server mongodb-clients python-pymongo

echo "Configuring mongodb.conf."
conf=/etc/mongodb.conf
iniset_sudo_no_section $conf bind_ip "$(hostname_to_ip controller)"
iniset_sudo_no_section $conf smallfiles true

echo "Stopping mongodb."
sudo service mongodb stop

echo "Removing initial journal files (if any)."
sudo rm -vf /var/lib/mongodb/journal/prealloc.*

echo "Starting mongodb."
sudo service mongodb start

echo -n "Waiting for mongodb to start."
while sudo service mongodb status 2>/dev/null | grep "stop"; do
    sleep 2
    echo -n .
done
echo
