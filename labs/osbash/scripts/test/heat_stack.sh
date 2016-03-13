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
# Verify the Orchestration Service installation
# http://docs.openstack.org/mitaka/install-guide-ubuntu/launch-instance-heat.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create a template
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Verifying heat installation."
echo "Waiting for heat-engine to start."

AUTH="source $CONFIG_DIR/demo-openstackrc.sh"
until node_ssh controller "$AUTH; heat stack-list" >/dev/null 2>&1; do
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

node_ssh controller "cat > demo-template.yml" << HEAT
heat_template_version: 2015-10-15
description: Launch a basic instance with CirrOS image using the
             ``m1.tiny`` flavor, ``mykey`` key,  and one network.

parameters:
  NetID:
    type: string
    description: Network ID to use for the instance.

resources:
  server:
    type: OS::Nova::Server
    properties:
      image: cirros
      flavor: m1.tiny
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
# Create a stack
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

TEST_STACK_NAME=stack
DEMO_NET=provider
NET_ID=$(node_ssh controller "$AUTH; openstack network list" | awk "/ $DEMO_NET / { print \$2 }")

node_ssh controller "$AUTH; heat stack-create -f demo-template.yml \
    -P 'NetID=$NET_ID' $TEST_STACK_NAME"

echo "Verifying successful creation of stack."

cnt=0
echo "heat stack-list"
until node_ssh controller "$AUTH; heat stack-list" 2>/dev/null | grep "CREATE_COMPLETE"; do
    cnt=$((cnt + 1))
    if [ $cnt -eq 60 ]; then
        # Print current stack list to help with debugging
        echo
        node_ssh controller "$AUTH; heat stack-list"
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
node_ssh controller "$AUTH; heat output-show --all $TEST_STACK_NAME; nova list"

echo "Deleting the test stack."
heat_stack_id=$(node_ssh controller "$AUTH; heat stack-list" | awk "/ $TEST_STACK_NAME / {print \$2}")

node_ssh controller "$AUTH; heat stack-delete $heat_stack_id"

echo -n "Waiting for test stack to disappear."
while node_ssh controller "$AUTH; heat stack-list|grep $heat_stack_id" >/dev/null 2>&1; do
    sleep 1
    echo -n .
done
echo
