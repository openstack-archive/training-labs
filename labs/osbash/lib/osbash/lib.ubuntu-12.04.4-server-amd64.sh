# Ubuntu 12.04.4 LTS amd64 server

# Default scripts for all Ubuntu installs
: ${BASE_INSTALL_SCRIPTS:=scripts.ubuntu_base}

#-------------------------------------------------------------------------------
# Booting the operating system installer
#-------------------------------------------------------------------------------

readonly ISO_URL=http://releases.ubuntu.com/12.04/ubuntu-12.04.4-server-amd64.iso

# Note: Ubuntu 12.04 LTS cannot pull a preseed file over HTTPS
readonly _PS_ssh=https://opendev.org/openstack/training-labs/raw/branch/master/labs/osbash/lib/osbash/netboot/preseed-ssh-v2.cfg
readonly _PS_vbadd=https://opendev.org/openstack/training-labs/raw/branch/master/labs/osbash/lib/osbash/netboot/preseed-vbadd.cfg
readonly _PS_all=https://opendev.org/openstack/training-labs/raw/branch/master/labs/osbash/lib/osbash/netboot/preseed-all-v2.cfg

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

# ostype used by VirtualBox to choose icon and flags (64-bit, IOAPIC)
VBOX_OSTYPE=Ubuntu_64

function distro_start_installer {
    local vm_name=$1

    # pick a _PS_* file
    local preseed=_PS_$VM_ACCESS

    echo "Using $preseed ${!preseed}"

    local boot_args=$(printf "$_BOOT_ARGS" "${!preseed}")

    keyboard_send_escape "$vm_name"
    keyboard_send_escape "$vm_name"
    keyboard_send_enter "$vm_name"

    conditional_sleep 1

    echo -e "${CStatus:-}Pushing boot command line${CReset:-}"
    keyboard_send_string "$vm_name" "$boot_args"

    echo "Initiating boot sequence"
    keyboard_send_enter "$vm_name"
}

# vim: set ai ts=4 sw=4 et ft=sh:
