#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/openstack"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

# Download CirrOS image
function get_cirros {
    local file_name=$(basename $CIRROS_URL)
    local remote_dir=$(dirname $CIRROS_URL)
    local md5_f=$file_name.md5sum

    mkdir -p "$IMG_DIR"

    # Download to IMG_DIR to cache the data if the directory is shared
    # with the host computer.
    if [ ! -f "$IMG_DIR/$md5_f" ]; then
        wget -O - "$remote_dir/MD5SUMS"|grep "$file_name" > "$IMG_DIR/$md5_f"
    fi

    if [ ! -f "$IMG_DIR/$file_name" ]; then
        wget --directory-prefix="$IMG_DIR" "$CIRROS_URL"
    fi

    # Make sure we have image and MD5SUM on the basedisk.
    if [ "$IMG_DIR" != "$HOME/img" ]; then
        mkdir -p "$HOME/img"
        cp -a "$IMG_DIR/$file_name" "$IMG_DIR/$md5_f" "$HOME/img"
    fi

    cd "$HOME/img"
    md5sum -c "$HOME/img/$md5_f"
    cd -
}

function apt_download {
    echo "apt_download: $@"
    sudo apt-get install -y --download-only "$@"
}

# Get cirros image.
get_cirros

# Download packages for all nodes

# MySQL, RabbitMQ
apt_download mariadb-server python-mysqldb rabbitmq-server

# NoSQL database (MongoDB)
apt_download mongodb-server mongodb-clients python-pymongo

# Other dependencies
apt_download python-argparse python-dev python-pip

# Keystone
apt_download keystone python-openstackclient apache2 \
    libapache2-mod-wsgi memcached python-memcache

# Glance
apt_download glance python-glanceclient

# Nova Controller
apt_download nova-api nova-cert nova-conductor nova-consoleauth \
    nova-novncproxy nova-scheduler python-novaclient

# Neutron Controller
apt_download neutron-server neutron-plugin-ml2 \
    neutron-linuxbridge-agent neutron-dhcp-agent \
    neutron-metadata-agent neutron-l3-agent python-neutronclient conntrack

# Cinder Controller
apt_download cinder-api cinder-scheduler python-cinderclient

# Horizon
apt_download openstack-dashboard

# Cinder Volumes
apt_download lvm2 cinder-volume

# Nova Compute
apt_download nova-compute nova-compute-qemu qemu sysfsutils

# Neutron Compute
apt_download neutron-linuxbridge-agent

# Heat
apt_download heat-api heat-api-cfn heat-engine python-heatclient

# ceilometer-install
apt_download ceilometer-api ceilometer-collector \
    ceilometer-agent-central ceilometer-agent-notification \
    python-ceilometerclient

# ceilometer-aodh
apt_download aodh-api aodh-evaluator aodh-notifier \
    aodh-listener aodh-expirer python-ceilometerclient

# ceilometer-nova
apt_download ceilometer-agent-compute

# ceilometer-swift
apt_download python-ceilometermiddleware

# Swift Controller
apt_download swift swift-proxy python-swiftclient \
    python-keystoneclient python-keystonemiddleware \
    memcached

# Swift Storage
apt_download xfsprogs rsync \
    swift swift-account swift-container swift-object

function pre-download_remote_config_files {
    # Swift controller
    wget --directory-prefix "$HOME" -O "swift-proxy-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/mitaka"

    # Swift storage
    wget --directory-prefix "$HOME" -O "swift-account-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/account-server.conf-sample?h=stable/mitaka"

    wget --directory-prefix "$HOME" -O "swift-container-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/container-server.conf-sample?h=stable/mitaka"

    wget --directory-prefix "$HOME" -O "swift-object-server.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/object-server.conf-sample?h=stable/mitaka"

    # Swift finalize
    wget --directory-prefix "$HOME" -O "swift-swift.conf" \
        "https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/mitaka"
}

pre-download_remote_config_files
