#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/openstack"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Verify the Orchestration Service installation
# http://docs.openstack.org/mitaka/install-guide-ubuntu/launch-instance-heat.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create a template
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Verifying heat installation."
echo "Waiting for heat-engine to start."

AUTH="source $CONFIG_DIR/demo-openstackrc.sh"
if node_ssh controller "$AUTH; openstack stack list 2>&1 | " \
        "grep 'orchestration service not found'"; then
    echo "SUM HEAT NOT INSTALLED"
    exit 1
fi

until node_ssh controller "$AUTH; openstack stack list" >/dev/null 2>&1; do
    sleep 1
done

function check_for_other_vms {
    echo "Verifying that no other instance VMs are left."
    (
    source "$CONFIG_DIR/admin-openstackrc.sh"
    if [ "$(openstack server list --all-projects | wc -l)" -gt 4 ]; then
        echo "WARNING Existing VMs found. There may not be enough resources" \
             "for this test."
        openstack server list --all-projects
    fi
    )
}
check_for_other_vms

echo "Creating a test heat template."

# FIXME mykey is created in launch_instance_private_net.sh

# Note: unlike install-guide, we use m1.nano (default flavors like m1.tiny
#       are no longer installed)
node_ssh controller "cat > demo-template.yml" << HEAT
heat_template_version: 2015-10-15
description: Launch a basic instance with CirrOS image using the
             ``m1.nano`` flavor, ``mykey`` key,  and one network.

parameters:
  NetID:
    type: string
    description: Network ID to use for the instance.

resources:
  server:
    type: OS::Nova::Server
    properties:
      image: cirros
      flavor: m1.nano
      key_name: mykey
      networks:
      - network: { get_param: NetID }

outputs:
  instance_name:
    description: Name of the instance.
    value: { get_attr: [ server, name ] }
  instance_ip:
    description: IP address of the instance.
    value: { get_attr: [ server, first_address ] }
HEAT

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create m1.nano flavor
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Nova does no longer create default flavors:
# http://docs.openstack.org/releasenotes/nova/unreleased.html 2016-09-25
(
echo

source "$CONFIG_DIR/admin-openstackrc.sh"

if openstack flavor list | grep m1.nano; then
    echo "Proceeding, m1.nano flavor exists."
else
    echo "Creating m1.nano flavor which is just big enough for CirrOS."
    openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano
fi

echo "Current flavors:"
openstack flavor list
echo
)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create a stack
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

TEST_STACK_NAME=stack
DEMO_NET=provider
NET_ID=$(node_ssh controller "$AUTH; openstack network list" | awk "/ $DEMO_NET / { print \$2 }")

echo "NET_ID: $NET_ID"

node_ssh controller "$AUTH; openstack stack create -t demo-template.yml \
    --parameter 'NetID=$NET_ID' $TEST_STACK_NAME"

echo "Verifying successful creation of stack."

cnt=0
echo "openstack stack list"
until node_ssh controller "$AUTH; openstack stack list" 2>/dev/null | grep "CREATE_COMPLETE"; do
    cnt=$((cnt + 1))
    if [ $cnt -eq 60 ]; then
        # Print current stack list to help with debugging
        echo
        node_ssh controller "$AUTH; openstack stack list"
        echo "Heat stack creation failed. Exiting."
        echo "[Warning]: Please debug heat services on the
        controller node. Heat may not work."
        exit 1
    else
        sleep 1
        echo -n "."
    fi
done

echo "Showing the name and IP address of the instance."
node_ssh controller "$AUTH; openstack stack output show --all $TEST_STACK_NAME; nova list"

echo "Deleting the test stack."
heat_stack_id=$(node_ssh controller "$AUTH; openstack stack list" | awk "/ $TEST_STACK_NAME / {print \$2}")

# Log memory use
sed 's|^|SUM HEAT MEM |' <<< "$(free -m) "

node_ssh controller "$AUTH; openstack stack delete $heat_stack_id"

echo -n "Waiting for test stack to disappear."
while node_ssh controller "$AUTH; openstack stack list|grep $heat_stack_id" >/dev/null 2>&1; do
    sleep 1
    echo -n .
done
echo
