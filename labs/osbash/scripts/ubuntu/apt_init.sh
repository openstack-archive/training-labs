#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/openstack"
source "$CONFIG_DIR/localrc"
source "$LIB_DIR/functions.guest.sh"

indicate_current_auto

exec_logfile

function set_apt_proxy {
    local PRX_KEY="Acquire::http::Proxy"
    local APT_FILE=/etc/apt/apt.conf

    if [ -f $APT_FILE ] && grep -q $PRX_KEY $APT_FILE; then
        # apt proxy has already been set (by preseed/kickstart)
        if [ -n "${VM_PROXY-}" ]; then
            # Replace with requested proxy
            sudo sed -i "s#^\($PRX_KEY\).*#\1 \"$VM_PROXY\";#" $APT_FILE
        else
            # No proxy requested -- remove
            sudo sed -i "s#^$PRX_KEY.*##" $APT_FILE
        fi
    elif [ -n "${VM_PROXY-}" ]; then
        # Proxy requested, but none configured: add line
        echo "$PRX_KEY \"$VM_PROXY\";" | sudo tee -a $APT_FILE
    fi
}

set_apt_proxy

# Get apt index files
sudo apt-get update

# ---------------------------------------------------------------------------
# Enable the OpenStack repository
# http://docs.openstack.org/newton/install-guide-ubuntu/environment-packages.html
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# NOTE: Using pre-release staging ppa is not documented in install-guide
# https://launchpad.net/~ubuntu-cloud-archive/+archive/ubuntu/newton-staging
#--------------------------------------------------------------------------

echo "Installing packages needed for add-apt-repository."
sudo apt-get -y install software-properties-common

case "$OPENSTACK_RELEASE" in
    newton)
        REPO=cloud-archive:newton
        SRC_FILE=cloudarchive-newton.list
        ;;
    newton-proposed)
        REPO=cloud-archive:newton-proposed
        SRC_FILE=cloudarchive-newton-proposed.list
        ;;
    newton-staging)
        REPO=ppa:ubuntu-cloud-archive/newton-staging
        SRC_FILE=ubuntu-cloud-archive-ubuntu-newton-staging-xenial.list
        ;;
    *)
        echo >&2 "Unknown OpenStack release: $OPENSTACK_RELEASE. Aborting."
        exit 1
        ;;
esac

echo "Adding cloud repo: $REPO"
sudo add-apt-repository "$REPO"

# Get index files only for ubuntu-cloud repo but keep standard lists
if [ -f "/etc/apt/sources.list.d/$SRC_FILE" ]; then
    sudo apt-get update \
        -o Dir::Etc::sourcelist="sources.list.d/$SRC_FILE" \
        -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"
else
    echo "ERROR: apt source not found: /etc/apt/sources.list.d/$SRC_FILE"
    exit 1
fi

# Disable automatic updates (they compete with our scripts for the dpkg lock)
sudo systemctl disable apt-daily.service
sudo systemctl disable apt-daily.timer
