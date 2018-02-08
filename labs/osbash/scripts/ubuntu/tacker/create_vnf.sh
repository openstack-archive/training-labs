#!/usr/bin/env bash

set -o errexit -o nounset

# This script creates a simple test VNF (a CirrOS instance).

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

VNF_NAME=vnf-sample
VNFD_NAME=vnfd-sample

# FIXME When starting from a snapshot after setup_tacker, we need to wait
#       for about 30 seconds before vnf-create or it will fail (time out).
#       Log files don't show anything interesting happening during that time.
# Good: 30 30
# Bad: 10 20 25
echo "Sleeping for 30 seconds."
sleep 30

echo "Sourcing the nfv user credentials."
source "$HOME/nfv-openrc.sh"

echo "Verifying that default vim is configured and reachable."
tacker vim-list -fvalue -cid -cis_default -cstatus | grep "True REACHABLE"

echo "openstack image list"
openstack image list

echo "tacker vim-list --column id --column name --column type"
tacker vim-list --column id --column name --column type

#------------------------------------------------------------------------------
# Create vnfd
#------------------------------------------------------------------------------

cfg_file=~/tacker/tacker/config/tosca-cirros-vnfd.yaml
mkdir -p "$(dirname $cfg_file)"

# From https://docs.openstack.org/tacker/latest/install/getting_started.html
cat << VNFD > "$cfg_file"
tosca_definitions_version: tosca_simple_profile_for_nfv_1_0_0

description: Demo example

metadata:
  template_name: sample-tosca-vnfd

topology_template:
  node_templates:
    VDU1:
      type: tosca.nodes.nfv.VDU.Tacker
      capabilities:
        nfv_compute:
          properties:
            num_cpus: 1
            mem_size: 64 MB
            disk_size: 1 GB
      properties:
        image: cirros
        availability_zone: nova
        mgmt_driver: noop
        monitoring_policy:
          name: ping
          parameters:
            count: 3
            interval: 10
          actions:
            failure: respawn
        config: |
          param0: key1
          param1: key2
        user_data_format: RAW
        user_data: |
          #!/bin/sh
          cat << EOF > /user-data-test
          # File created by create_vnf.sh to demonstrate the use of user data.
          EOF
          date >> /user-data-test

    CP1:
      type: tosca.nodes.nfv.CP.Tacker
      properties:
        management: true
        order: 0
        anti_spoofing_protection: false
      requirements:
        - virtualLink:
            node: VL1
        - virtualBinding:
            node: VDU1

    VL1:
      type: tosca.nodes.nfv.VL
      properties:
        network_name: net_mgmt
        vendor: Tacker
VNFD

# Replace devstack network name with training-labs network name
sed -i 's/net_mgmt/provider/' "$cfg_file"

echo "Creating vnfd with $cfg_file."
tacker vnfd-create --vnfd-file "$cfg_file" "$VNFD_NAME"

tacker vnfd-list

VNFD_ID=$(tacker vnfd-show "$VNFD_NAME" -cid -fvalue)
echo "Got vnfdid $VNFD_ID."

echo "Calling tacker vnfd-events-list."
tacker vnfd-events-list

echo "Calling tacker vnfd-show $VNFD_ID."
tacker vnfd-show "$VNFD_ID"

#------------------------------------------------------------------------------
# Create vnf
#------------------------------------------------------------------------------
echo "Creating vnf: tacker vnf-create --vnfd-id $VNFD_ID $VNF_NAME"
tacker vnf-create --vnfd-id "$VNFD_ID" "$VNF_NAME"

echo -n "Waiting for vnf to become active (this can take a while)."
cnt=0
while true; do
    status=$(tacker vnf-show -cstatus "$VNF_NAME" -fvalue)
    if [ "$status" = "ACTIVE" ]; then
        break
    elif [ "$status" = "ERROR" ]; then
        echo "ERROR vnf is in error state. Aborting."
        exit 1
    fi
    sleep 1
    echo -n .
    cnt=$((cnt + 1))
    if [ $cnt -eq 60 ]; then
        tacker vnf-show "$VNF_NAME"
        echo "vnf not active. Aborting."
        exit 1
    fi
done
echo "vnf is active."

tacker vnf-show "$VNF_NAME"

echo "Showing vnf events."
tacker vnf-events-list

echo "Showing all events."
tacker events-list

#------------------------------------------------------------------------------
IP=$(tacker vnf-show "$VNF_NAME" -cmgmt_url -fvalue | \
        grep -Po "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}")
echo "IP address of vnf: $IP"
ROUTER_NAMESPACE=$(ip netns | grep qrouter | awk '{print $1}')
echo "Router namespace ID: $ROUTER_NAMESPACE"

echo "sudo ip netns exec $ROUTER_NAMESPACE ping -c1 $IP"
sudo ip netns exec "$ROUTER_NAMESPACE" ping -c1 "$IP"

echo "Script $(basename "$0") completed successfully."
