# Ubuntu 14.04 LTS amd64 server

# Default scripts for all Ubuntu installs
: ${BASE_INSTALL_SCRIPTS:=scripts.ubuntu_base}

#-------------------------------------------------------------------------------
# Installation from ISO image
#-------------------------------------------------------------------------------

readonly ISO_URL_BASE=http://releases.ubuntu.com/14.04/

ISO_URL=$ISO_URL_BASE/ubuntu-14.04.4-server-amd64.iso
ISO_MD5=2ac1f3e0de626e54d05065d6f549fa3a

readonly _PS_ssh=http://git.openstack.org/cgit/openstack/training-labs/plain/labs/osbash/lib/osbash/netboot/preseed-ssh-v2.cfg
readonly _PS_vbadd=http://git.openstack.org/cgit/openstack/training-labs/plain/labs/osbash/lib/osbash/netboot/preseed-vbadd.cfg
readonly _PS_all=http://git.openstack.org/cgit/openstack/training-labs/plain/labs/osbash/lib/osbash/netboot/preseed-all-v2.cfg

# Arguments for ISO image installer
readonly _BOOT_ARGS="/install/vmlinuz
    noapic
    preseed/url=%s
    debian-installer=en_US
    auto=true
    locale=en_US
    hostname=osbash
    fb=false
    debconf/frontend=noninteractive
    keyboard-configuration/modelcode=SKIP
    initrd=/install/initrd.gz
    console-setup/ask_detect=false"

# Fallback function to find current ISO image in case the file in ISO_URL is
# neither on the disk nor at the configured URL.
# This mechanism was added because old Ubuntu ISOs are removed from the server
# as soon as a new ISO appears.
function update_iso_variables {
    # Get matching line from distro repo's MD5SUMS file, e.g.
    # "9e5fecc94b3925bededed0fdca1bd417 *ubuntu-14.04.3-server-amd64.iso"
    local distro_info=$(wget -O - $ISO_URL_BASE/MD5SUMS|grep server-amd64)

    # First part (removing everything after first space) is the md5sum
    ISO_MD5=${distro_info%% *}

    # Second part (keeping everything after ' *') is the ISO file name
    local iso_file=${distro_info#* \*}

    ISO_URL=$ISO_URL_BASE/$iso_file

    echo -e >&2 "${CStatus:-}New ISO_URL: ${CData:-}$ISO_URL${CReset:-}"
}

# ostype used by VirtualBox to choose icon and flags (64-bit, IOAPIC)
VBOX_OSTYPE=Ubuntu_64

# Boot the ISO image operating system installer
function vbox_distro_start_installer {
    local vm_name=$1

    # pick a _PS_* file
    local preseed=_PS_$VM_ACCESS

    echo "Using $preseed ${!preseed}"

    local boot_args=$(printf "$_BOOT_ARGS" "${!preseed}")

    vbox_kbd_escape_key "$vm_name"
    vbox_kbd_escape_key "$vm_name"
    vbox_kbd_enter_key "$vm_name"

    vbox_sleep 1

    echo -e "${CStatus:-}Pushing boot command line${CReset:-}"
    vbox_kbd_string_input "$vm_name" "$boot_args"

    echo "Initiating boot sequence"
    vbox_kbd_enter_key "$vm_name"
}

#-------------------------------------------------------------------------------
# Installation from Internet server (if ISO image cannot be used, e.g. with KVM)
#-------------------------------------------------------------------------------

readonly DISTRO_URL=http://archive.ubuntu.com/ubuntu/dists/trusty/main/installer-amd64/

# Extra arguments for virt-install
readonly EXTRA_ARGS="locale=en_US.UTF-8
    console-keymaps-at/keymap=us
    console-setup/ask_detect=false
    console-setup/layoutcode=us
    keyboard-configuration/layout=USA
    keyboard-configuration/variant=US
    netcfg/get_hostname=osbash
    netcfg/get_domainname=local
    mirror/country=CH
    mirror/http/directory=/ubuntu
    mirror/http/mirror=ch.archive.ubuntu.com
    mirror/protocol=http
    mirror/http/proxy=
    preseed/url=${_PS_ssh}"

# vim: set ai ts=4 sw=4 et ft=sh:
