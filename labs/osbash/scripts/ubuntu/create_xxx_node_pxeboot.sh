#!/usr/bin/env bash

# This scripts executes on the pxeserver and configures the service
set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$CONFIG_DIR/openstack"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/config.pxeserver"

# Determine hostname from script name
re=".*create_(.*)_node_pxeboot.sh$"
if [[ $0 =~ $re ]]; then
    NODE_NAME=${BASH_REMATCH[1]}
    NODE_NAME="${NODE_NAME}"
else
    echo "ERROR Unable to determine hostname"
    exit 1
fi

exec_logfile

indicate_current_auto

PXE_NET_IP=$(get_node_ip_in_network "$(hostname)" "mgmt")
echo "IP on the management network: $PXE_NET_IP."

# -----------------------------------------------------------------------------
echo "Creating preseed file for training-labs."
TMPF=/var/www/html/ubuntu/preseed/training-labs.seed
sudo cp -v "$LIB_DIR/osbash/netboot/preseed-ssh-v5.cfg" "$TMPF"

set_iface_list
IFACE_1=$(ifnum_to_ifname 1)
echo "Using interface $IFACE_1."

# -----------------------------------------------------------------------------
function create_boot_entry {
    local entry_name=$1
    # If no static IP address for node is given, default to PXE_INITIAL_NODE_IP
    local node_ip=${2:-$PXE_INITIAL_NODE_IP}
    menu_file=/var/lib/tftpboot/pxelinux.cfg/default
    echo "Editing the boot menu at $menu_file."
    echo "  Entry name: $entry_name"
    echo "  IP address: $node_ip"
    cat << PXEMENU | sudo tee -a "$menu_file"

label $entry_name
        kernel ubuntu-installer/amd64/linux
        append preseed/url=http://$PXE_NET_IP/ubuntu/preseed/training-labs.seed vga=normal initrd=ubuntu-installer/amd64/initrd.gz debian-installer=en_US auto=true locale=en_US hostname=foobar debconf/frontend=noninteractive keyboard-configuration/modelcode=SKIP console-setup/ask_detect=false netcfg/choose_interface=$IFACE_1 priority=critical netcfg/get_ipaddress=$node_ip netcfg/get_netmask=255.255.255.0 netcfg/get_gateway=$PXE_GATEWAY netcfg/get_nameservers=$PXE_GATEWAY netcfg/disable_dhcp=true
PXEMENU
}

TMPF=/var/lib/tftpboot/pxelinux.cfg/default
echo "Editing the boot menu at $TMPF."

if [ ! -f "$TMPF" ]; then
    # File does not exist yet. The first node becomes the default.
    cat << PXEMENU | sudo tee "$TMPF"
include ubuntu-installer/amd64/boot-screens/menu.cfg
default ubuntu-installer/amd64/boot-screens/vesamenu.c32

menu hshift 13
menu width 49
menu margin 8
prompt 0

menu title training-labs PXE installer boot menu

# Comment out default line to get boot menu on PXE booted machines
default training_labs_generic

PXEMENU
    echo "Creating a menu entry to boot the node with a default IP address."
    create_boot_entry "training_labs_generic"
fi

NODE_IP=$(get_node_ip_in_network "$NODE_NAME" "mgmt")
echo "IP of $NODE_NAME on the management network: $NODE_IP"

echo "Creating a menu entry to boot the node with its management IP address."
create_boot_entry "$NODE_NAME" "$NODE_IP"
# -----------------------------------------------------------------------------
