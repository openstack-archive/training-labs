#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

indicate_current_auto

exec_logfile

# The install-guide wants to use the hostname as the name of the interface
# in the mgmt network. We cannot allow 127.0.0.1 to share the name.
HOST_NAME=$(hostname)-lo
HOST_FILE=/etc/hosts

if ! grep -q "^[^#].*$HOST_NAME" $HOST_FILE; then
    # No active entry for our hostname
    HOST_IP=127.0.1.1
    if grep -q "^$HOST_IP" $HOST_FILE; then
        # Fix the entry for the IP address we want to use
        sudo sed -i "s/^$HOST_IP.*/$HOST_IP $HOST_NAME/" $HOST_FILE
    else
        echo "$HOST_IP $HOST_NAME" | sudo tee -a $HOST_FILE
    fi
fi

# Add entries for the OpenStack training-labs cluster
cat "$CONFIG_DIR/hosts.multi" | sudo tee -a /etc/hosts
