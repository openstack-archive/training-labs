#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/openstack"
# Pick up VM_PROXY
source "$CONFIG_DIR/localrc"
source "$LIB_DIR/functions.guest.sh"

indicate_current_auto

exec_logfile

function set_yum_proxy {
    local YUM_FILE=/etc/yum.conf
    if [ -z "${VM_PROXY-}" ]; then
        return 0;
    fi
    echo "proxy=${VM_PROXY}" | sudo tee -a $YUM_FILE
}

set_yum_proxy

# Enable RDO repo
if [[ ${OPENSTACK_RELEASE:-} = kilo ]]; then
    sudo yum install -y "https://repos.fedorapeople.org/repos/openstack/openstack-kilo/rdo-release-kilo-1.noarch.rpm"
elif [[ ${OPENSTACK_RELEASE:-} = liberty ]]; then
    sudo yum install -y "https://repos.fedorapeople.org/repos/openstack/openstack-liberty/rdo-release-liberty-2.noarch.rpm"
else
    echo 2>&1 "ERROR Unknown OpenStack release."
    return 1
fi
