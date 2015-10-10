#!/bin/bash
set -o errexit -o nounset
TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/deploy.osbash"
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

for node in controller network compute; do
    (
    source "$CONFIG_DIR/config.$node"
    node_dir=$RESULTS_DIR/$node
    mkdir "$node_dir"

    ssh_env_for_node $node
    vm_ssh "$VM_SSH_PORT" "sudo tar cf - -C /var/log upstart" | tar xf - -C "$node_dir"
    )
done

ssh_env_for_node controller
if vm_ssh "$VM_SSH_PORT" 'ls log/test-*.*' >/dev/null 2>&1; then
    vm_ssh "$VM_SSH_PORT" 'cd log; tar cf - test-*.*' | tar xf - -C "$RESULTS_DIR/controller"
    vm_ssh "$VM_SSH_PORT" 'rm log/test-*.*'
fi
