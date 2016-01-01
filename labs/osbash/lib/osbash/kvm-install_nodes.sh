# This bash library contains the main function that creates a node VM.

# Boot node VM; wait until autostart files are processed and VM is shut down
function _vm_boot_with_autostart {
    local vm_name=$1

    if $VIRSH domstate "$vm_name" | grep -q "shut off"; then
        vm_boot "$vm_name"
    else
        echo >&2 "VM is already running."
        $VIRSH domstate "$vm_name"
    fi

    # Wait for ssh connection and execute scripts in autostart directory
    ssh_process_autostart "$vm_name" &

    wait_for_autofiles
    echo >&2 "VM \"$vm_name\": autostart files executed"
}

# Create a new node VM and run basic configuration scripts
function vm_init_node {
    # XXX Run this function in sub-shell to protect our caller's environment
    #     (which might be _our_ enviroment if we get called again)
    local vm_name=$1

    (
    source "$CONFIG_DIR/config.$vm_name"

    local base_disk_name=$(get_base_disk_name)

    configure_node_netifs "$vm_name"

    vm_delete "$vm_name"

    echo -e "${CStatus:-}Creating copy-on-write VM disk.${CReset:-}"
    $VIRSH vol-create-as "$KVM_VOL_POOL" "$vm_name" \
        "${BASE_DISK_SIZE:=10000}M" \
        --format qcow2 \
        --backing-vol "$base_disk_name" \
        --backing-vol-format qcow2

    local console_type
    if [ "$VM_UI" = "headless" ]; then
        console_type="--noautoconsole"
    elif [ "$VM_UI" = "vnc" ]; then
        console_type="--graphics vnc,listen=0.0.0.0"
    else
        # gui option: should open a console viewer
        console_type=""
    fi

    $VIRT_INSTALL \
        --name "$vm_name" \
        --ram "${VM_MEM:-512}" \
        --vcpus "${VM_CPUS:-1}" \
        --os-type=linux \
        --disk vol="$KVM_VOL_POOL/${vm_name},cache=none" \
        ${KVM_NET_OPTIONS:-""} \
        --import \
        $console_type \
        &
    )

    # Prevent "time stamp from the future" due to race between two sudos in
    # VIRT_INSTALL (background) above and VIRSH below
    sleep 1

    echo >&2 "Waiting for VM to be defined."
    while ! $VIRSH list|grep -q "$vm_name"; do
        sleep 1
        echo -n .
    done

    # Set VM group in description so we know which VMs are ours.
    set_vm_group "$vm_name"

    # The SSH_IP needs to get out, so it can't be set in a sub-shell
    local mac=$(node_to_mac "$vm_name")
    echo -e "${CInfo:-}MAC address for node $vm_name: ${CData:-}$mac${CReset:-}"

    SSH_IP=$(mac_to_ip "$mac")
    echo -e "${CInfo:-}IP address for node $vm_name:  ${CData:-}$SSH_IP${CReset:-}"

    echo "Node: $vm_name MAC: $mac IP: $SSH_IP" | tee -a "$LOG_DIR/ip.log"

    echo >&2 "Waiting for ping returning from $SSH_IP."
    while ! ping -c1 "$SSH_IP" > /dev/null; do
        echo -n .
        sleep 1
    done


    (
    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    # Rename to pass the node name to the script
    autostart_and_rename osbash init_xxx_node.sh "init_${vm_name}_node.sh"
    )
}

function vm_build_nodes {

    if virsh_uses_kvm; then
        echo -e "${CInfo:-}KVM support is available.${CReset:-}"
    else
        echo -e "${CError:-}No KVM support available. Using qemu.${CReset:-}"
    fi

    CONFIG_NAME=$(get_distro_name "$DISTRO")_$1
    echo -e "${CInfo:-}Configuration file: ${CData:-}$CONFIG_NAME${CReset:-}"

    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    autostart_reset
    autostart_from_config "scripts.$CONFIG_NAME"
    #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
}

# vim: set ai ts=4 sw=4 et ft=sh:
