#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/openstack"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

function apt_download {
    echo "apt_download: $*"
    sudo apt install -y --download-only "$@"
}

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
apt_download nova-api nova-conductor nova-consoleauth \
    nova-novncproxy nova-scheduler

# Placement Controller
apt_download nova-placement-api

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

# PXE server
apt_download bind9 isc-dhcp-server apache2 tftpd-hpa inetutils-inetd vlan \
    iptables-persistent
