# This bash library contains the main function that creates a node VM.

# Boot node VM; wait until autostart files are processed
function _vm_boot_with_autostart {
    local vm_name=$1

    vm_boot "$vm_name"

    # Wait for ssh connection and execute scripts in autostart directory
    # (for wbatch, osbashauto does the processing instead)
    ${WBATCH:+:} ssh_process_autostart "$vm_name" &

    wait_for_autofiles
    echo >&2 "VM \"$vm_name\": autostart files executed"
}

# Create a new node VM
function vm_create_node {
    # XXX Run this function in sub-shell to protect our caller's environment
    #     (which might be _our_ environment if we get called again)
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

    if [ "${FIRST_DISK_SIZE:-0}" -gt 0 ]; then
        # Used for PXE build (does not use basedisk)
        local first_disk_path=$DISK_DIR/$vm_name-sda.vdi
        create_vdi "$first_disk_path" "${FIRST_DISK_SIZE}"
        # Port 0 is default
        vm_attach_disk "$vm_name" "$first_disk_path"
    else
        # Use copy-on-write disk over basedisk
        vm_attach_disk_multi "$vm_name" "$(get_base_disk_path)"
    fi

    if [ "${SECOND_DISK_SIZE:-0}" -gt 0 ]; then
        local second_disk_path=$DISK_DIR/$vm_name-sdb.vdi
        create_vdi "$second_disk_path" "${SECOND_DISK_SIZE}"
        # Use port 1
        vm_attach_disk "$vm_name" "$second_disk_path" 1
    fi
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
