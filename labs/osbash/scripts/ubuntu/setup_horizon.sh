#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Set up OpenStack Dashboard (horizon)
# http://docs.openstack.org/liberty/install-guide-ubuntu/horizon-install.html
#------------------------------------------------------------------------------

echo "Installing horizon."
sudo apt-get install -y openstack-dashboard

echo "Purging Ubuntu theme."
sudo dpkg --purge openstack-dashboard-ubuntu-theme

# Edit the /etc/openstack-dashboard/local_settings.py file.
conf=/etc/openstack-dashboard/local_settings.py
auth_host=controller

echo "Setting OPENSTACK_HOST = \"$auth_host\"."
iniset_sudo_no_section $conf "OPENSTACK_HOST" "\"$auth_host\""

echo -n "Allowed hosts: "
iniset_sudo_no_section $conf "ALLOWED_HOSTS" "['*', ]"

memcached_conf=/etc/memcached.conf
# Port is a number on line starting with "-p "
port=$(grep -Po -- '(?<=^-p )\d+' $memcached_conf)

# Interface is an IP address on line starting with "-l "
interface=$(grep -Po -- '(?<=^-l )[\d\.]+' $memcached_conf)

echo "memcached listening on $interface:$port."

# Line should read something like: 'LOCATION' : '127.0.0.1:11211',
if grep "LOCATION.*$interface:$port" $conf; then
    echo "$conf agrees."
else
    echo >&2 "$conf disagrees. Aborting."
    exit 1
fi

# Configure user as the default role for users created via dashboard.
iniset_sudo_no_section $conf "OPENSTACK_KEYSTONE_DEFAULT_ROLE" '"user"'
iniset_sudo_no_section $conf "TIME_ZONE" '"UTC"'

echo "Reloading apache and memcached service."
sudo service apache2 reload
