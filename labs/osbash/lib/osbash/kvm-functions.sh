#-------------------------------------------------------------------------------
# virt-install / virsh
#-------------------------------------------------------------------------------

VIRSH=virsh
VIRT_INSTALL=virt_install

: ${VIRT_LOG:=$LOG_DIR/virt.log}

function virsh {
    mkdir -p "$(dirname "$VIRT_LOG")"

    echo "$VIRSH_CALL" "$@" >> "$VIRT_LOG"
    local rc=0
    $VIRSH_CALL "$@" || rc=$?
    if [ $rc -ne 0 ]; then
        echo -e >&2 "${CError:-}FAILURE ($rc): virsh: $@${CReset:-}"
        echo "FAILURE ($rc): $VIRSH_CALL $@" >> "$VIRT_LOG"
        return 1
    fi
}

function virt_install {
    mkdir -p "$(dirname "$VIRT_LOG")"

    echo "$VIRT_INSTALL_CALL" "$@" >> "$VIRT_LOG"
    local rc=0
    $VIRT_INSTALL_CALL "$@" || rc=$?
    if [ $rc -ne 0 ]; then
        echo -e >&2 "${CError:-}FAILURE ($rc): $VIRT_INSTALL_CALL $@${CReset:-}"
        echo "FAILURE ($rc): $VIRT_INSTALL_CALL $@" >> "$VIRT_LOG"
        return 1
    fi
}

function virsh_uses_kvm {
    $VIRSH capabilities | grep -q kvm
}

#-------------------------------------------------------------------------------
# VM status
#-------------------------------------------------------------------------------

function vm_exists {
    local vm_name=$1

    return $($VIRSH domstate "$vm_name" >/dev/null 2>&1)
}

function vm_is_running {
    local vm_name=$1

    return $($VIRSH domstate "$vm_name" 2>/dev/null | grep -q running)
}

function vm_wait_for_shutdown {
    local vm_name=$1

    echo -e >&2 -n "${CStatus:-}Machine shutting down${CReset:-}"
    while $VIRSH domstate "$vm_name" | grep -q -e running -e "in shutdown"; do
        echo -n .
        sleep 1
    done
    echo >&2 -e "${CStatus:-}\nMachine powered off.${CReset:-}"
}

function vm_power_off {
    local vm_name=$1
    if vm_is_running "$vm_name"; then
        echo -e >&2 "${CStatus:-}Powering off VM ${CData:-}\"$vm_name\"${CReset:-}"
        $VIRSH destroy "$vm_name"
    fi
}

function vm_snapshot {
    : # Not implemented
}

#-------------------------------------------------------------------------------
# Network functions
#-------------------------------------------------------------------------------

# Get the MAC address from a node name (default network)
function node_to_mac {
    local node=$1
    local rc=""
    local mac=""

    echo >&2 "Waiting for MAC address."
    while [ : ]; do
        mac=$($VIRSH dumpxml "$node"|grep -Po '[a-z0-9:]{17}'|head -n1) || rc=$?
        if [ -n "$mac" ]; then
            echo "$mac"
            echo >&2
            break
        fi
        sleep 1
        echo >&2 -n .
    done
}

# Get the IP address from a MAC address (default network)
function mac_to_ip {
    local mac=$1
    local rc=""
    local ip=""

    echo >&2 "Waiting for IP address."
    while [ : ]; do
        ip=$(sudo arp -n|grep "$mac"|awk '{print $1}') || rc=$?
        if [ -n "$ip" ]; then
            echo >&2
            echo "$ip"
            break
        fi
        sleep 1
        echo >&2 -n .
    done
}

# Get ssh IP address and port from node name (non-default networks)
function ssh_env_for_node {
    local node=$1

    # No port forwarding with KVM; ignore VM_SSH_PORT from config.<node>
    VM_SSH_PORT=22

    # IP address in management network
    local mgmt_ip="$(source "$CONFIG_DIR/config.$node"; \
                    get_node_ip_in_network "$node" "mgmt")"
    echo >&2 "Target node is at $mgmt_ip:$VM_SSH_PORT (mgmt network)."

    # Wait for VM to respond on management network
    SSH_IP=$mgmt_ip
    wait_for_ssh "$VM_SSH_PORT"

    # Get external IP address from a line like
    # "    inet 192.168.122.232/24 brd [...]"
    SSH_IP=$(vm_ssh $VM_SSH_PORT "ip addr show eth0" | \
                awk -F'[/ ]+' '/inet / { print $3 }')
    echo >&2 "Target node is at $SSH_IP:$VM_SSH_PORT."
}

function virsh_define_network {
    local net=labs-$1
    local if_ip=$2

    echo >&2 "Defining network $net ($if_ip)."
    if ! $VIRSH net-info "$net" >/dev/null 2>&1; then
        local cfg=$LOG_DIR/kvm-net-$net.xml

        # FIXME Limit port forwarding to networks that need it.
        cat << NETCFG > "$cfg"
<network>
  <name>$net</name>
  <forward mode='nat'/>
  <ip address='$if_ip' netmask='255.255.255.0'>
  </ip>
</network>
NETCFG

        $VIRSH net-define "$cfg"
    fi
}

function virsh_start_network {
    local net=labs-$1

    if $VIRSH net-info "$net" 2>/dev/null|grep -q "Active:.*no"; then
        echo >&2 "Starting network $net."
        $VIRSH net-start "$net"
    fi
}

function virsh_stop_network {
    local net=labs-$1

    if $VIRSH net-info "$net" 2>/dev/null|grep -q "Active:.*yes"; then
        echo >&2 "Stopping network $net."
        $VIRSH net-destroy "$net"
    fi
}

function virsh_undefine_network {
    local net=labs-$1

    if $VIRSH net-info "$net" >/dev/null 2>&1; then
        echo >&2 "Undefining network $net."
        $VIRSH net-undefine "$net"
    fi
}

function vm_nic_base {
    KVM_NET_OPTIONS="${KVM_NET_OPTIONS:-} --network bridge=virbr0"
}

function vm_nic_std {
    local vm_name=$1
    local index=$2
    local netname=labs-$(ip_to_netname "${NODE_IF_IP[index]}")

    KVM_NET_OPTIONS="${KVM_NET_OPTIONS:-} --network network=$netname"
}

function create_network {
    local index=$1
    local net_name=${NET_NAME[index]}
    local if_ip=${NET_GW[index]}

    virsh_stop_network "$net_name"

    virsh_undefine_network "$net_name"

    virsh_define_network "$net_name" "$if_ip"

    virsh_start_network "$net_name"
}

#-------------------------------------------------------------------------------
# Disk functions
#-------------------------------------------------------------------------------

function disk_exists {
    local disk=$1

    return $($VIRSH vol-info --pool "$KVM_VOL_POOL" "$disk" >/dev/null 2>&1)
}

function base_disk_exists {
    disk_exists "$(get_base_disk_name)"
}

function disk_create {
    local disk=$1
    # Size in MB
    local size=$2

    if ! disk_exists "$disk"; then
        $VIRSH vol-create-as "$KVM_VOL_POOL" "$disk" "${size}M" --format qcow2
    fi
}

function disk_delete {
    local disk=$1

    if disk_exists "$disk"; then
        $VIRSH vol-delete --pool "$KVM_VOL_POOL" "$disk"
    fi
}

function base_disk_delete {
    disk_delete "$(get_base_disk_name)"
}

# Use virt-sparsify to compress disk image and make it sparse
function disk_compress {
    local disk_name=$1
    local disk_path=$($VIRSH vol-path --pool $KVM_VOL_POOL $disk_name)
    local pool_dir=$(dirname $disk_path)

    local spexe
    if ! spexe=$(which virt-sparsify); then
        echo -e >&2 "${CError:-}No virt-sparsify executable found." \
                "Consider installing libguestfs-tools.${CReset:-}"
        return 0
    fi

    echo -e >&2 "${CStatus:-}Compressing disk image, input file:${CReset:-}"
    sudo file "$disk_path"
    sudo ls -lh "$disk_path"
    sudo du -sh "$disk_path"

    sudo $spexe --compress "$disk_path" "$pool_dir/.$disk_name"
    sudo mv -vf "$pool_dir/.$disk_name" "$disk_path"

    echo -e >&2 "${CStatus:-}Output file:${CReset:-}"
    sudo file "$disk_path"
    sudo ls -lh "$disk_path"
    sudo du -sh "$disk_path"
}

#-------------------------------------------------------------------------------
# VM unregister, remove, delete
#-------------------------------------------------------------------------------

function vm_delete {
    local vm_name=$1

    echo >&2 -n "Asked to delete VM \"$vm_name\" "

    if vm_exists "$vm_name"; then
        echo >&2 "(found)"
        vm_power_off "$vm_name"
        $VIRSH undefine "$vm_name"
    else
        echo >&2 "(not found)"
    fi

    if disk_exists "$vm_name"; then
        echo >&2 -e "${CInfo:-}Disk exists: ${CData:-}$vm_name${CReset:-}"
        echo >&2 -e "Deleting disk $vm_name."
        disk_delete "$vm_name"
    fi
}

#-------------------------------------------------------------------------------
# Booting a VM
#-------------------------------------------------------------------------------

function vm_boot {
    local vm_name=$1

    echo -e >&2 "${CStatus:-}Starting VM ${CData:-}\"$vm_name\"${CReset:-}"
    $VIRSH start "$vm_name"
}

#-------------------------------------------------------------------------------

# vim: set ai ts=4 sw=4 et ft=sh:
