#!/bin/bash
set -o errexit -o nounset
TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/localrc"
source "$CONFIG_DIR/deploy.osbash"
source "$CONFIG_DIR/openstack"
source "$OSBASH_LIB_DIR/functions-host.sh"
source "$OSBASH_LIB_DIR/$PROVIDER-functions.sh"

function usage {
    echo "Purpose: Get logs from cluster node VMs."
    echo "Usage: $0 [<target_root>]"
    exit 1
}

if [ $# = 0 ]; then
    usage
else
    RESULTS_DIR=$1
    if [ ! -d "$RESULTS_DIR" ]; then
        echo >&2 "Error: no such directory: $RESULTS_DIR"
        exit 1
    fi
fi

for node in $(script_cfg_get_nodenames); do
    (
    source "$CONFIG_DIR/config.$node"
    node_dir=$RESULTS_DIR/$node

    ssh_env_for_node $node
    if vm_ssh "$VM_SSH_PORT" exit; then
        echo "Getting server log files from $node node."
        mkdir "$node_dir"
        vm_ssh "$VM_SSH_PORT" "sudo tar cf - -C /var log --exclude=installer" | tar xf - -C "$node_dir"
        vm_ssh "$VM_SSH_PORT" "dmesg" > "$node_dir"/dmesg
    else
        echo "VM $node does not reply."
        continue
    fi

    echo -e "Splitting log files into:\n\t$node_dir/split_logs"
    "$TOP_DIR/tools/log_snapshot_split.py" \
        --logdir "$node_dir/log" \
        --resultdir "$node_dir/split_logs" \
        "$node_dir/log"
    )
done

echo "Getting test log files from controller node."
ssh_env_for_node controller
if vm_ssh "$VM_SSH_PORT" 'ls log/test-*.*' >/dev/null 2>&1; then
    vm_ssh "$VM_SSH_PORT" 'cd log; tar cf - test-*.*' | tar xf - -C "$RESULTS_DIR/controller"
    vm_ssh "$VM_SSH_PORT" 'rm log/test-*.*'
else
    echo "VM controller does not reply or no test log files found."
fi
