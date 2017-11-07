#!/usr/bin/env bash

# This script executes on the pxeserver and installs the PXE services
set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$CONFIG_DIR/openstack"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/config.pxeserver"

exec_logfile

indicate_current_auto

PXE_NET_IP=$(get_node_ip_in_network "$(hostname)" "mgmt")
echo "IP on the management network: $PXE_NET_IP."

# IP minus the last octet, something like "10.0.0"
PXE_NET_PREFIX=$(remove_last_octet "$PXE_NET_IP")

# Network interface on the network of the default gateway
PXE_NET_IFACE=$(ip route | grep "$PXE_NET_PREFIX" | awk '{print $3}')
echo "Network interface on the network of the default gateway: $PXE_NET_IFACE."

echo "Editing /etc/hosts to include pxeserver"
echo "$PXE_NET_IP  pxeserver" | sudo tee -a /etc/hosts
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Installing the dhcp server."
sudo apt install -y isc-dhcp-server

echo "Setting dhcp server interface to $PXE_NET_IFACE."
sudo sed -i "s/^INTERFACES=.*/INTERFACES='$PXE_NET_IFACE'/" /etc/default/isc-dhcp-server

TMPF=/etc/dhcp/dhcpd.conf
echo "Editing $TMPF."

cat << DHCPD | sudo tee -a "$TMPF"
subnet ${PXE_NET_PREFIX}.0 netmask 255.255.255.0 {
  range ${PXE_NET_PREFIX}.230 ${PXE_NET_PREFIX}.240;
  option routers $PXE_GATEWAY;
  option domain-name-servers $PXE_GATEWAY;
  option broadcast-address ${PXE_NET_PREFIX}.255;
}

allow booting;
allow bootp;
option option-128 code 128 = string;
option option-129 code 129 = text;
next-server $PXE_NET_IP;
filename "pxelinux.0";
DHCPD

sudo sed -i 's/^#authoritative;/authoritative;/' "$TMPF"

echo "Restarting dhcp server."
sudo service isc-dhcp-server restart
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Setup the tftp server with inetd and apache
echo "Installing apache, tftpd, and inetd."
sudo apt install -y apache2 tftpd-hpa inetutils-inetd

TMPF=/etc/default/tftpd-hpa
echo "Editing $TMPF."

echo 'RUN_DAEMON="yes"' | sudo tee -a "$TMPF"
echo 'OPTIONS="-l -s /var/lib/tftpboot"' | sudo tee -a "$TMPF"

echo "Enabling tftpd in /etc/inetd.conf."
echo "tftp    dgram   udp    wait    root    /usr/sbin/in.tftpd /usr/sbin/in.tftpd -s /var/lib/tftpboot" | sudo tee -a /etc/inetd.conf

echo "Restarting tftpd server."
sudo service tftpd-hpa restart
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Extracting and configuring the Ubuntu boot image."

ISO_NAME=$(echo $IMG_DIR/ubuntu-*.iso | tail -1)
sudo mount -o loop "$ISO_NAME" /mnt/

sudo cp -fr /mnt/install/netboot/* /var/lib/tftpboot/

sudo mkdir -p /var/www/html/ubuntu
sudo cp -fr /mnt/* /var/www/html/ubuntu/

sudo rm -f /var/lib/tftpboot/pxelinux.cfg/default
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Configuring DNS server."
sudo apt -y install bind9

sudo cp /etc/bind/named.conf.options /etc/bind/named.conf.options.BK
sudo sed -i 's|// forwarders {|forwarders {\n\
\t\t8.8.8.8;\n\
\t\t8.8.4.4;\n\
\t};\n|' /etc/bind/named.conf.options

echo "Restarting DNS server."
sudo service bind9 restart
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
set_iface_list
IFACE_0=$(ifnum_to_ifname 0)
IFACE_1=$(ifnum_to_ifname 1)
echo "Creating a VLAN IP as gateway (interfaces $IFACE_0, $IFACE_1)."
sudo apt -y install vlan
sudo modprobe 8021q
sudo vconfig add "$IFACE_1" 10
sudo su -c 'echo "8021q" >> /etc/modules'

cat << VLAN_IP | sudo tee -a /etc/network/interfaces

auto $IFACE_1.10
iface $IFACE_1.10 inet static
      address $PXE_GATEWAY
      netmask 255.255.255.0
      vlan-raw-device $IFACE_1
VLAN_IP

sudo ifup "$IFACE_1".10

# Forward traffic from eth0.10 to eth0 and eth1

echo "Editing /etc/sysctl.conf: enabling IPv4 forwarding."
sudo sed -i 's/.*net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

# Reload changed file
sudo sysctl -p /etc/sysctl.conf

echo 1 | sudo tee -a /proc/sys/net/ipv4/ip_forward
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Configuring iptables."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

sudo iptables --table nat --append POSTROUTING --out-interface $IFACE_0 -j MASQUERADE
sudo iptables --append FORWARD --in-interface $IFACE_0 -j ACCEPT
sudo iptables --append FORWARD --in-interface $IFACE_1 -j ACCEPT

echo "Making iptable rules persistent."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt -y install iptables-persistent
