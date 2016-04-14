# This file contains bash functions that may be used by both guest and host
# systems.

# Non-recursive removal of all files except README.*
function clean_dir {
    local target_dir=$1
    if [ ! -e "$target_dir" ]; then
        mkdir -pv "$target_dir"
    elif [ ! -d "$target_dir" ]; then
        echo >&2 "Not a directory: $target_dir"
        return 1
    fi
    shopt -s nullglob
    local entries=("$target_dir"/*)
    if [ -n "${entries[0]-}" ]; then
        for f in "${entries[@]}"; do
            # Skip directories
            if [ ! -f "$f" ]; then
                continue
            fi

            # Skip README.*
            if [[ $f =~ /README\. ]]; then
                continue
            fi

            rm -f "$f"
        done
    fi
}

function is_root {
    if [ $EUID -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function yes_or_no {
    local prompt=$1
    local input=""
    while : ; do
        read -p "$prompt (Y/n): " input
        case "$input" in
            N|n)
                return 1
                ;;
            ""|Y|y)
                return 0
                ;;
            *)
                echo -e "${CError:-}Invalid input: ${CData:-}$input${CReset:-}"
                ;;
        esac
    done
}

#-------------------------------------------------------------------------------
# Network helpers
#-------------------------------------------------------------------------------

function get_host_network_config {
    source "$CONFIG_DIR/openstack"

    local line
    # Iterate over all NETWORK_? variables
    for hostnet in "${!NETWORK_@}"; do
        line=(${!hostnet})
        NET_NAME+=(${line[0]})
        NET_IP+=(${line[1]})
        # Set .1 (e.g., 203.0.113.1) as the default gateway address
        NET_GW+=($(remove_last_octet ${line[1]}).1)
    done
}

function get_node_netif_config {
    local vm_name=$1
    source "$CONFIG_DIR/config.$vm_name"

    local net_if=""
    local line
    # Iterate over all NET_IF_? variables
    for net_if in "${!NET_IF_@}"; do
        local if_num=${net_if##*_}
        line=(${!net_if})
        NODE_IF_TYPE[$if_num]=${line[0]}
        NODE_IF_IP[$if_num]=${line[1]:-""}
        # Default boot priority is 0 for all interfaces
        NODE_IF_PRIO[$if_num]=${line[2]:=0}
    done
}

function remove_last_octet {
    # Remove last period and everything after it
    echo "${1%.*}"
}

function netname_to_network {
    local net_name=$1
    local index

    if [ -z "${NET_NAME+1}" ]; then
        # NET_NAME array is undefined
        get_host_network_config
    fi

    for index in "${!NET_NAME[@]}"; do
        if [ "$net_name" = "${NET_NAME[index]}" ]; then
            echo "${NET_IP[index]}"
            return 0
        fi
    done
    echo >&2 "ERROR: No network named $net_name."
    exit 1
}

function ip_to_netname {
    local ip=$1
    local ip_net=$(remove_last_octet "$ip").0
    local index

    if [ -z "${NET_NAME+1}" ]; then
        # NET_NAME array is undefined
        get_host_network_config
    fi

    for index in "${!NET_IP[@]}"; do
        # Remove last octet
        if [ "$ip_net" = "${NET_IP[index]}" ]; then
            echo "${NET_NAME[index]}"
            return 0
        fi
    done

    echo >&2 "ERROR: No network for IP address $ip. Exiting."
    exit 1
}

function get_node_ip_in_network {
    local vm_name=$1
    local netname=$2
    local ip

    if [ -z "${NET_NAME+1}" ]; then
        # NET_NAME array is undefined
        get_host_network_config
    fi

    get_node_netif_config "$vm_name"

    for ip in "${NODE_IF_IP[@]}"; do
        if [ -z "$ip" ]; then
            # This interface has no IP address. Next.
            continue
        elif [ "$(ip_to_netname "$ip")" = "$netname" ]; then
            echo >&2 "Success. Node $vm_name in $netname: $ip."
            echo "$ip"
            return 0
        fi
    done

    echo >&2 "ERROR: Node $vm_name not in network $netname. Exiting."
    exit 1
}

#-------------------------------------------------------------------------------
# Helpers to incrementally number files via name prefixes
#-------------------------------------------------------------------------------

function get_next_file_number {
    local dir=$1
    local ext=${2:-""}

    # Get number of *.log files in directory
    shopt -s nullglob
    if [ -n "$ext" ]; then
        # Count files with specific extension
        local files=("$dir/"*".$ext")
    else
        # Count all files
        local files=("$dir/"*)
    fi
    echo "${#files[*]}"
}

function get_next_prefix {
    local dir=$1
    local ext=$2
    # Number of digits in prefix string (default 3)
    local digits=${3:-3}

    # Get number of *.$ext files in $dir
    local cnt=$(get_next_file_number "$dir" "$ext")

    printf "%0${digits}d" "$cnt"
}

# vim: set ai ts=4 sw=4 et ft=sh:
