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
# Enable Compute service meters
# http://docs.openstack.org/mitaka/install-guide-ubuntu/ceilometer-nova.html
#------------------------------------------------------------------------------

echo "Installing ceilometer."
sudo apt-get install -y ceilometer-agent-compute

ceilometer_admin_user=$(service_to_user_name ceilometer)

conf=/etc/ceilometer/ceilometer.conf
echo "Configuring $conf."

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT rpc_backend rabbit

# Configure [oslo_messaging_rabbit] section.
iniset_sudo $conf oslo_messaging_rabbit rabbit_host controller
iniset_sudo $conf oslo_messaging_rabbit rabbit_userid openstack
iniset_sudo $conf oslo_messaging_rabbit rabbit_password "$RABBIT_PASS"

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT auth_strategy keystone

# Configure [keystone_authtoken] section.
iniset_sudo $conf keystone_authtoken auth_uri http://controller:5000
iniset_sudo $conf keystone_authtoken auth_url http://controller:35357
iniset_sudo $conf keystone_authtoken memcached_servers controller:11211
iniset_sudo $conf keystone_authtoken auth_type password
iniset_sudo $conf keystone_authtoken project_domain_name default
iniset_sudo $conf keystone_authtoken user_domain_name default
iniset_sudo $conf keystone_authtoken project_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf keystone_authtoken username "$ceilometer_admin_user"
iniset_sudo $conf keystone_authtoken password "$CEILOMETER_PASS"

# Configure [service_credentials] section.
iniset_sudo $conf service_credentials os_auth_url http://controller:5000/v2.0
iniset_sudo $conf service_credentials os_username "$ceilometer_admin_user"
iniset_sudo $conf service_credentials os_tenant_name "$SERVICE_PROJECT_NAME"
iniset_sudo $conf service_credentials os_password "$CEILOMETER_PASS"
iniset_sudo $conf service_credentials interface internalURL
iniset_sudo $conf service_credentials region_name "$REGION"

# Marked "optional" in install-guide
iniset_sudo $conf DEFAULT verbose True

echo "Configuring nova.conf."
conf=/etc/ceilometer/ceilometer.conf

# Configure [DEFAULT] section.
iniset_sudo $conf DEFAULT instance_usage_audit True
iniset_sudo $conf DEFAULT instance_usage_audit_period hour
iniset_sudo $conf DEFAULT notify_on_state_change vm_and_task_state
iniset_sudo $conf DEFAULT notification_driver messagingv2

echo "Restarting telemetry service."
sudo service ceilometer-agent-compute restart

echo "Restarting compute service."
sudo service nova-compute restart

#------------------------------------------------------------------------------
# Enable Block Storage meters
# http://docs.openstack.org/mitaka/install-guide-ubuntu/ceilometer-cinder.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Configure Cinder to use Telemetry
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

conf=/etc/cinder/cinder.conf
echo "Configuring $conf."

iniset_sudo $conf oslo_messaging_notifications driver messagingv2

echo "Restarting cinder-volumes service."
sudo service cinder-volume restart

#------------------------------------------------------------------------------
# Verify operation
# http://docs.openstack.org/mitaka/install-guide-ubuntu/ceilometer-verify.html
#------------------------------------------------------------------------------

echo "Verifying the Telemetry installation."

AUTH="source $CONFIG_DIR/admin-openstackrc.sh"

echo -n "Waiting for ceilometer to start."
until node_ssh controller "$AUTH; ceilometer meter-list" >/dev/null 2>&1; do
    sleep 1
    echo -n .
done
echo

echo "Listing available meters."
node_ssh controller "$AUTH; ceilometer meter-list"

echo "Downloading an image from the Image service."
IMAGE_ID=$(node_ssh controller "$AUTH; glance image-list | grep 'cirros' | awk '{ print \$2 }'")
echo "IMAGE_ID: $IMAGE_ID"
node_ssh controller "$AUTH; glance image-download \"$IMAGE_ID\"" > /tmp/cirros.img

echo "Listing available meters again to validate detection of the image download."
node_ssh controller "$AUTH; ceilometer meter-list"

echo "Retrieving usage statistics from the image.download meter."
node_ssh controller "$AUTH; ceilometer statistics -m image.download -p 60"

echo "Removing previously downloaded image file."
rm /tmp/cirros.img
