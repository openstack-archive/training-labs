# This bash library contains the main function that creates the base disk.

function vm_install_base {
    local base_disk_path=$(get_base_disk_path)
    local base_build_disk=$DISK_DIR/tmp-disk.vdi
    local vm_name=base

    echo >&2 "$(date) osbash vm_install starts."

    ${WBATCH:-:} wbatch_begin_base

    # Don't remove base_build_disk if we are just faking it for wbatch
    ${OSBASH:-:} rm -f "$base_build_disk"
    ${WBATCH:-:} wbatch_delete_disk "$base_build_disk"

    vm_create "$vm_name"
    (
    source "$CONFIG_DIR/config.$vm_name"

    vm_mem "$vm_name" "${VM_MEM}"
    )

    if [ -z "${INSTALL_ISO-}" ]; then

        if [  -z "$ISO_URL" ]; then
            echo -e >&2 "${CMissing:-}Either ISO URL or name needed (ISO_URL, INSTALL_ISO).${CReset:-}"
            exit 1
        fi
        # Don't look for ISO image if we are only doing wbatch
        ${OSBASH:-:} find_install-iso

        INSTALL_ISO=$ISO_DIR/$(get_iso_name)
    fi

    echo >&2 -e "${CInfo:-}Install ISO:\n\t${CData:-}$INSTALL_ISO${CReset:-}"

    ${OSBASH:-:} check_md5 "$INSTALL_ISO" "$ISO_MD5"

    $VBM storageattach "$vm_name" \
        --storagectl IDE \
        --port 0 \
        --device 0 \
        --type dvddrive \
        --medium "$INSTALL_ISO"

    ${WBATCH:-:} vm_attach_guestadd-iso "$vm_name"

    ${OSBASH:-:} mkdir -pv "$DISK_DIR"
    create_vdi "$base_build_disk" "${BASE_DISK_SIZE:=10000}"
    vm_attach_disk "$vm_name" "$base_build_disk"

    #---------------------------------------------------------------------------
    # Set up communication with base VM: ssh port forwarding by default,
    # VirtualBox shared folders for wbatch

    (
    # Get the VM_SSH_PORT for the base disk
    source "$CONFIG_DIR/config.$vm_name"

    # wbatch runs cannot use ssh, so skip port forwarding in that case
    ${WBATCH:+:} vm_port "$vm_name" ssh "$VM_SSH_PORT" 22
    )

    # Automounted on /media/sf_bootstrap for first boot
    ${WBATCH:-:} vm_add_share_automount "$vm_name" "$SHARE_DIR" bootstrap
    # Mounted on /$SHARE_NAME after first boot
    ${WBATCH:-:} vm_add_share "$vm_name" "$SHARE_DIR" "$SHARE_NAME"
    #---------------------------------------------------------------------------

    $VBM modifyvm "$vm_name" --boot1 dvd
    $VBM modifyvm "$vm_name" --boot2 disk

    # Configure autostart
    autostart_reset

    # For wbatch, install osbashauto as a boot service
    ${WBATCH:-:} autostart osbash/activate_autostart.sh

    autostart osbash/base_fixups.sh

    # By default, set by lib/osbash/lib.* to something like scripts.ubuntu_base
    autostart_from_config "$BASE_INSTALL_SCRIPTS"

    autostart zero_empty.sh shutdown.sh

    # Boot VM into distribution installer
    vm_boot "$vm_name"

    # Note: It takes about 5 seconds for the installer in the VM to be ready
    #       on a fairly typical laptop. If we don't wait long enough, the
    #       installation will fail. Ideally, we would have a different method
    #       of making sure the installer is ready. For now, we just have to
    #       try and err on the side of caution.
    local delay=10
    echo >&2 "Waiting $delay seconds for VM \"$vm_name\" to come up"
    conditional_sleep "$delay"

    distro_start_installer "$vm_name"

    echo -e >&2 "${CStatus:-}Installing operating system; waiting for reboot${CReset:-}"

    # Wait for ssh connection and execute scripts in autostart directory
    # (for wbatch, osbashauto does the processing instead)
    ${WBATCH:+:} ssh_process_autostart "$vm_name" &
    # After reboot
    wait_for_autofiles
    echo -e >&2 "${CStatus:-}Installation done for VM ${CData:-}$vm_name${CReset:-}"

    vm_wait_for_shutdown "$vm_name"

    # Detach disk from VM now or it will be deleted by vm_unregister_del
    vm_detach_disk "$vm_name"

    vm_unregister_del "$vm_name"

    echo >&2 "Compacting $base_build_disk"
    $VBM modifyhd "$base_build_disk" --compact

    # This disk will be moved to a new name, and this name will be used for
    # a new disk next time the script runs.
    disk_unregister "$base_build_disk"

    echo -e >&2 "${CStatus:-}Base disk created${CReset:-}"

    echo >&2 "Moving base disk to $base_disk_path"
    ${OSBASH:-:} mv -vf "$base_build_disk" "$base_disk_path"
    ${WBATCH:-:} wbatch_rename_disk "$base_build_disk" "$base_disk_path"

    ${WBATCH:-:} wbatch_end_file

    echo >&2 -e "${CData:-}$(date) ${CStatus:-}osbash vm_install ends\n${CReset:-}"
}

# vim: set ai ts=4 sw=4 et ft=sh:
