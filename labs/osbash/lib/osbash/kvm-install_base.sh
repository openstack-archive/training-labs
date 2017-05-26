# This bash library contains the main function that creates the base disk.

function vm_install_base {
    local base_disk_name=$(get_base_disk_name)
    local vm_name=base

    echo >&2 "$(date) osbash vm_install starts."

    if virsh_uses_kvm; then
        echo -e "${CInfo:-}KVM support is available.${CReset:-}"
    else
        echo -e "${CError:-}No KVM support available. Using qemu.${CReset:-}"
    fi

    vm_delete "$vm_name"

    if [ -z "${INSTALL_ISO-}" ]; then

        if [  -z "$ISO_URL" ]; then
            echo -e >&2 "${CMissing:-}Either ISO URL or name needed (ISO_URL, INSTALL_ISO).${CReset:-}"
            exit 1
        fi

        find_install-iso

        INSTALL_ISO=$ISO_DIR/$(get_iso_name)
    fi

    echo >&2 -e "${CInfo:-}Install ISO:\n\t${CData:-}$INSTALL_ISO${CReset:-}"

    check_md5 "$INSTALL_ISO" "$ISO_MD5"

    # Configure autostart
    autostart_reset

    autostart osbash/base_fixups.sh

    # By default, set by lib/osbash/lib.* to something like scripts.ubuntu_base
    autostart_from_config "$BASE_INSTALL_SCRIPTS"

    autostart zero_empty.sh shutdown.sh

    disk_create "$base_disk_name" "${BASE_DISK_SIZE:=10000}"

    local console_type
    if [ "$VM_UI" = "headless" ]; then
        console_type="--noautoconsole"
    elif [ "$VM_UI" = "vnc" ]; then
        console_type="--graphics vnc,listen=0.0.0.0"
    else
        # gui option: should open a console viewer
        console_type=""
    fi

    # Boot VM into distribution installer
    (
    source "$CONFIG_DIR/config.$vm_name"
    $VIRT_INSTALL \
        --disk "vol=$KVM_VOL_POOL/$base_disk_name,cache=none" \
        --cdrom "$INSTALL_ISO" \
        --name $vm_name \
        --os-type linux \
        --ram "${VM_MEM}" \
        --vcpus 1 \
        --virt-type kvm \
        $console_type \
        --wait=-1 \
        &
    )

    local delay=10
    echo >&2 "Waiting $delay seconds for VM \"$vm_name\" to come up."
    conditional_sleep "$delay"

    distro_start_installer "$vm_name"

    echo -e >&2 "${CStatus:-}Installing operating system; waiting for reboot.${CReset:-}"

    # Prevent "time stamp from the future" due to race between two sudos in
    # VIRT_INSTALL (background) above and VIRSH below
    sleep 1

    echo >&2 "Waiting for VM to be defined."
    until vm_is_running "$vm_name"; do
        sleep 1
        echo -n .
    done

    SSH_IP=$(node_to_ip "$vm_name")

    echo >&2 "Waiting for ping returning from $SSH_IP."
    while ! ping -c1 "$SSH_IP" > /dev/null; do
        echo -n .
        sleep 1
    done

    # Wait for ssh connection and execute scripts in autostart directory
    ssh_process_autostart "$vm_name" &
    # After reboot
    wait_for_autofiles
    echo -e >&2 "${CStatus:-}Installation done for VM ${CData:-}$vm_name${CReset:-}"

    vm_wait_for_shutdown "$vm_name"

    disk_compress "$base_disk_name"

    # Just undefine the VM without deleting the base disk
    $VIRSH undefine "$vm_name"

    echo -e >&2 "${CStatus:-}Base disk created${CReset:-}"

    echo >&2 -e "${CData:-}$(date) ${CStatus:-}osbash vm_install ends\n${CReset:-}"
}

# vim: set ai ts=4 sw=4 et ft=sh:
