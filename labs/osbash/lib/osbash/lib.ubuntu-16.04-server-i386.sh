# Ubuntu 16.04 LTS i386 server

# Default scripts for all Ubuntu installs
: ${BASE_INSTALL_SCRIPTS:=scripts.ubuntu_base}

#-------------------------------------------------------------------------------
# Installation from ISO image
#-------------------------------------------------------------------------------

readonly ISO_URL_BASE=http://releases.ubuntu.com/16.04

ISO_URL=$ISO_URL_BASE/ubuntu-16.04.5-server-i386.iso
ISO_MD5=9ba5fefe27685ae69f991c45396080af

readonly _PS_ssh=https://opendev.org/openstack/training-labs/raw/branch/master/labs/osbash/lib/osbash/netboot/preseed-ssh-v6.cfg
readonly _PS_vbadd=https://opendev.org/openstack/training-labs/raw/branch/master/labs/osbash/lib/osbash/netboot/preseed-vbadd-v6.cfg
readonly _PS_all=https://opendev.org/openstack/training-labs/raw/branch/master/labs/osbash/lib/osbash/netboot/preseed-all-v6.cfg

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
    # "9e5fecc94b3925bededed0fdca1bd417 *ubuntu-14.04.3-server-i386.iso"
    local distro_info=$(wget -O - "$ISO_URL_BASE/MD5SUMS" | \
                        grep "server-i386.*\.iso" | tail -n1)

    # First part (removing everything after first space) is the md5sum
    ISO_MD5=${distro_info%% *}

    # Second part (keeping everything after ' *') is the ISO file name
    local iso_file=${distro_info#* \*}

    ISO_URL=$ISO_URL_BASE/$iso_file

    echo -e >&2 "${CStatus:-}New ISO_URL: ${CData:-}$ISO_URL${CReset:-}"
}

# ostype used by VirtualBox to choose icon and flags (64-bit, IOAPIC)
VBOX_OSTYPE=Ubuntu

# Boot the ISO image operating system installer
function distro_start_installer {
    local vm_name=$1

    # pick a _PS_* file
    local preseed=_PS_$VM_ACCESS

    echo "Using $preseed ${!preseed}"

    local boot_args=$(printf "$_BOOT_ARGS" "${!preseed}")

    if [ -n "${VM_PROXY:-""}" ]; then
        echo >&2 "Using proxy $VM_PROXY."
        boot_args="$boot_args mirror/http/proxy=$VM_PROXY http_proxy=$VM_PROXY"
    fi

    keyboard_send_enter "$vm_name"
    keyboard_send_f6 "$vm_name"
    keyboard_send_escape "$vm_name"
    for i in $(seq 1 83); do
        keyboard_send_backspace "$vm_name"
    done

    echo -e "${CStatus:-}Pushing boot command line${CReset:-}"
    keyboard_send_string "$vm_name" "$boot_args"

    echo "Initiating boot sequence"
    keyboard_send_enter "$vm_name"
}

# vim: set ai ts=4 sw=4 et ft=sh:
