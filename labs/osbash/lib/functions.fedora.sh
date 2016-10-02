# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Fedora /etc/sysconfig/network-scripts/ifcfg-* configuration
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function config_netif {
    local if_type=$1
    local if_num=${2:-""}
    local ip_address=${3:-""}
    local template

    if [ "$if_type" = "dhcp" ]; then
        template="template-fedora-ifcfg-dhcp"
    else
        template="template-fedora-ifcfg-static"
    fi

    local if_name="$(ifnum_to_ifname "$if_num")"

    local if_file=/etc/sysconfig/network-scripts/ifcfg-$if_name

    sed -e "
        s,%IF_NAME%,$if_name,g;
        s,%IP_ADDRESS%,$ip_address,g;
    " "$TEMPLATE_DIR/$template" | sudo tee "$if_file"
}

function netcfg_init {
    : # Not needed for Fedora
}

function netcfg_show {
    local cfg
    for cfg in /etc/sysconfig/network-scripts/ifcfg-*; do
        echo ---------- "$cfg"
        cat "$cfg"
    done
    echo ---------------------------------------------------------------
}
