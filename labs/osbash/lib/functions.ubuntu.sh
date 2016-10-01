# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Ubuntu /etc/network/interfaces configuration
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

readonly UBUNTU_IF_FILE=/etc/network/interfaces

function config_netif {
    local if_type=$1
    local if_num=${2:-""}
    local ip_address=${3:-""}
    local template

    if [ "$if_type" = "dhcp" ]; then
        template="template-ubuntu-interfaces-dhcp"
    elif [ "$if_type" = "manual" ]; then
        template="template-ubuntu-interfaces-manual"
    else
        template="template-ubuntu-interfaces-static"
    fi

    local if_name="$(ifnum_to_ifname "$if_num")"

    # Empty line before this entry
    echo | sudo tee -a "$UBUNTU_IF_FILE"

    sed -e "
        s,%IF_NAME%,$if_name,g;
        s,%IP_ADDRESS%,$ip_address,g;
    " "$TEMPLATE_DIR/$template" | sudo tee -a "$UBUNTU_IF_FILE"
}

function netcfg_init {
    # Configuration functions will append to this file
    sudo cp -v  "$TEMPLATE_DIR/template-ubuntu-interfaces-loopback" \
                "$UBUNTU_IF_FILE"
}

function netcfg_show {
    echo ---------- "$UBUNTU_IF_FILE"
    cat "$UBUNTU_IF_FILE"
    echo ---------------------------------------------------------------
}
