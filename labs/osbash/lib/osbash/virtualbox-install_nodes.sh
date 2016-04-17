# This bash library contains the main function that creates a node VM.

# Boot node VM; wait until autostart files are processed and VM is shut down
function _vm_boot_with_autostart {
    local vm_name=$1

    vm_boot "$vm_name"

    # Wait for ssh connection and execute scripts in autostart directory
    # (for wbatch, osbashauto does the processing instead)
    ${WBATCH:+:} ssh_process_autostart "$vm_name" &

    wait_for_autofiles
    echo >&2 "VM \"$vm_name\": autostart files executed"
}

# Create a new node VM and run basic configuration scripts
function vm_init_node {
    # XXX Run this function in sub-shell to protect our caller's environment
    #     (which might be _our_ enviroment if we get called again)
    (
    source "$CONFIG_DIR/config.$vm_name"

    vm_name=$1

    vm_create "$vm_name"

    # Set VM_MEM in config/config.NODE_NAME to override
    vm_mem "$vm_name" "${VM_MEM:-512}"

    # Set VM_CPUS in config/config.NODE_NAME to override
    vm_cpus "$vm_name" "${VM_CPUS:-1}"

    configure_node_netifs "$vm_name"

    # Port forwarding
    if [ -n "${VM_SSH_PORT:-}" ]; then
        vm_port "$vm_name" ssh "$VM_SSH_PORT" 22
    fi
    if [ -n "${VM_WWW_PORT:-}" ]; then
        vm_port "$vm_name" http "$VM_WWW_PORT" 80
    fi

    vm_add_share "$vm_name" "$SHARE_DIR" "$SHARE_NAME"
    vm_attach_disk_multi "$vm_name" "$(get_base_disk_path)"

    if [ "${SECOND_DISK_SIZE:-0}" -gt 0 ]; then
        local second_disk_path=$DISK_DIR/$vm_name-sdb.vi
        create_vdi "$second_disk_path" "${SECOND_DISK_SIZE}"
        vm_attach_disk "$vm_name" "$second_disk_path" 1
    fi

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    # Rename to pass the node name to the script
    autostart_and_rename osbash init_xxx_node.sh "init_${vm_name}_node.sh"

    )
}

function vm_build_nodes {
    CONFIG_NAME=$(get_distro_name "$DISTRO")_$1
    echo -e "${CInfo:-}Configuration file: ${CData:-}$CONFIG_NAME${CReset:-}"

    ${WBATCH:-:} wbatch_begin_node "$CONFIG_NAME"
    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    autostart_reset
    autostart_from_config "scripts.$CONFIG_NAME"
    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    ${WBATCH:-:} wbatch_end_file
}

# vim: set ai ts=4 sw=4 et ft=sh:
