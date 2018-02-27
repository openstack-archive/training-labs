# This file contains bash functions that are used by osbash on the host.

source "$LIB_DIR/functions.sh"

#-------------------------------------------------------------------------------
# Conditional execution
#-------------------------------------------------------------------------------
# TODO: Create a help function and display it under help by default or with
# option --help (-h).
# exec_cmd is used for conditional execution:
#
# OSBASH=exec_cmd
#
# Execute command only if OSBASH is set:
# ${OSBASH:-:} cmd args
#
# Execute command only if OSBASH is not set:
# ${OSBASH:+:} cmd args
#
# Disable actual call to VBoxManage (selectively override configuration):
# OSBASH= cmd args
#
# Enable call to VBoxManage (selectively override configuration):
# OSBASH=exec_cmd cmd args

function exec_cmd {
    local cmd=$1
    shift
    $cmd "$@"
}

#-------------------------------------------------------------------------------
function get_base_disk_name {
    echo "base-$VM_ACCESS-$OPENSTACK_RELEASE-$DISTRO"
}

# From DISTRO string (e.g., ubuntu-14.04-server-amd64), get first component
function get_distro_name {
    # Match up to first dash
    local re='([^-]*)'

    if [[ $DISTRO =~ $re ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Wrapper around vm_snapshot to deal with collisions with cluster rebuilds
# starting from snapshot. We could delete the existing snapshot first,
# rename the new one, or just skip the snapshot.
function vm_conditional_snapshot {
    local vm_name=$1
    local shot_name=$2

    # On Windows, don't test; take snapshots unconditionally
    if ! WBATCH= vm_snapshot_exists "$vm_name" "$shot_name"; then
        vm_snapshot "$vm_name" "$shot_name"
    fi
}

#-------------------------------------------------------------------------------
# Virtual VM keyboard using keycodes
#-------------------------------------------------------------------------------

function keyboard_send_escape {
    local vm_name=$1
    _keyboard_push_scancode "$vm_name" "$(esc2scancode)"
}

function keyboard_send_enter {
    local vm_name=$1
    _keyboard_push_scancode "$vm_name" "$(enter2scancode)"
}

function keyboard_send_backspace {
    local vm_name=$1
    _keyboard_push_scancode "$vm_name" "$(backspace2scancode)"
}

function keyboard_send_f6 {
    local vm_name=$1
    _keyboard_push_scancode "$vm_name" "$(f6_2scancode)"
}

# Turn strings into keycodes and send them to target VM
function keyboard_send_string {
    local vm_name=$1
    local str=$2
    local cnt=0

    # This loop is inefficient enough that we don't overrun the keyboard input
    # buffer when pushing scancodes to the VM.
    while IFS=  read -r -n1 char; do
        if [ -n "$char" ]; then
            SC=$(char2scancode "$char")
            if [ -n "$SC" ]; then
                _keyboard_push_scancode "$vm_name" "$SC"
            else
                echo >&2 "not found: $char"
            fi
        fi

        # Inject sleep into the wbatch files because the Windows batch file
        # is sometimes _too_ efficient and overruns the keyboard input buffer
        if [[ $((cnt % 50)) -eq 0 ]]; then
            OSBASH= ${WBATCH:-:} conditional_sleep 1
        fi
        cnt=$((cnt + 1))

    done <<< "$str"
}

#-------------------------------------------------------------------------------
# Conditional sleeping
#-------------------------------------------------------------------------------

function conditional_sleep {
    sec=$1

    # Don't sleep if we are just faking it for wbatch
    ${OSBASH:-:} sleep "$sec"
    ${WBATCH:-:} wbatch_sleep "$sec"
}

#-------------------------------------------------------------------------------
# Networking
#-------------------------------------------------------------------------------

function create_host_networks {
    get_host_network_config

    local index
    for index in "${!NET_NAME[@]}"; do
        create_network "$index"
    done
}

function configure_node_netifs {
    local vm_name=$1

    get_node_netif_config "$vm_name"

    local index
    local type
    local prio
    for index in "${!NODE_IF_TYPE[@]}"; do
        type=${NODE_IF_TYPE[index]}
        prio=${NODE_IF_PRIO[index]}
        if [ "$type" = "dhcp" ]; then
            vm_nic_base "$vm_name" "$index"
        elif [ "$type" = "manual" ]; then
            vm_nic_std "$vm_name" "$index"
        elif [ "$type" = "static" ]; then
            vm_nic_std "$vm_name" "$index"
        else
            echo >&2 "ERROR Unknown interface type: $type."
            exit 1
        fi
        if [ "$prio" -ne 0 ]; then
            # Elevate boot prio so this particular NIC is used for PXE booting
            vm_nic_set_boot_prio "$vm_name" "$index" "$prio"
        fi
    done
}

#-------------------------------------------------------------------------------
# ssh
#-------------------------------------------------------------------------------

# Check permission for osbash insecure private key
function check_osbash_private_key {
    local key_name="osbash_key"
    local osbash_key_dir=$LIB_DIR/osbash-ssh-keys
    local osbash_key_path=$osbash_key_dir/$key_name

    if ! ls -l "$osbash_key_path"|grep -q "^-r--------"; then
        echo "Adjusting permissions for $osbash_key_path"
        chmod 400 "$osbash_key_path"
    fi
}

function strip_top_dir {
    local full_path=$1
    echo "${full_path/$TOP_DIR\//}"
}

# Copy files or directories to VM (incl. implied directories; HOME is TOP_DIR)
function vm_scp_to_vm {
    local ssh_port=$1
    shift
    local ssh_ip=${SSH_IP:=127.0.0.1}

    check_osbash_private_key

    while (($#)); do
        local src_path=$1
        shift
        local target_path=$(strip_top_dir "$src_path")
        local target_dir=$(dirname "$target_path")
        vm_ssh "$ssh_port" "mkdir -p $target_dir"
        # To avoid getting stuck on broken ssh connection, disable connection
        # sharing (ControlPath) and use a timeout when connecting.
        scp -q -r \
            -i "$LIB_DIR/osbash-ssh-keys/osbash_key" \
            -o "UserKnownHostsFile /dev/null" \
            -o "StrictHostKeyChecking no" \
            -o ConnectTimeout=10 \
            -o ControlPath=none \
            -P "$ssh_port" \
            "$src_path" "$VM_SHELL_USER@$ssh_ip:$target_dir"
    done
}

# Execute commands via ssh
function vm_ssh {
    local ssh_port=$1
    shift
    local ssh_ip=${SSH_IP:=127.0.0.1}

    check_osbash_private_key

    # Some operating systems (e.g., Mac OS X) export locale settings to the
    # target that cause some Python clients to fail. Override with a standard
    # setting (LC_ALL=C).
    # To avoid getting stuck on broken ssh connection, disable connection
    # sharing (ControlPath) and use a timeout when connecting.
    LC_ALL=C ssh -q \
        -i "$LIB_DIR/osbash-ssh-keys/osbash_key" \
        -o "UserKnownHostsFile /dev/null" \
        -o "StrictHostKeyChecking no" \
        -o ConnectTimeout=10 \
        -o ControlPath=none \
        -p "$ssh_port" \
        "$VM_SHELL_USER@$ssh_ip" "$@"
}

function wait_for_ssh {
    local ssh_port=$1

    echo -e -n "${CStatus:-}Waiting for ssh server to respond on ${CData:-}${SSH_IP:-127.0.0.1}:$ssh_port${CReset:-}."
    while : ; do
        if vm_ssh "$ssh_port" exit ; then
            break
        else
            echo -n .
            sleep 1
        fi
    done
    echo
}

# Copy one script to VM and execute it via ssh; log output to separate file
function ssh_exec_script {
    local ssh_port=$1
    local script_path=$2

    vm_scp_to_vm "$ssh_port" "$script_path"

    local remote_path=$(strip_top_dir "$script_path")

    echo -en "\n$(date) start $remote_path"

    local script_name=$(basename "$script_path" .sh)
    local prefix=$(get_next_prefix "$LOG_DIR" "auto")
    local log_path=$LOG_DIR/${prefix}_${script_name}.auto

    local rc=0
    vm_ssh "$ssh_port" "bash $remote_path && rm -vf $remote_path" \
        > "$log_path" 2>&1 || rc=$?
    if [ $rc -ne 0 ]; then
        echo >&2
        echo -e "${CError:-}ERROR: ssh returned status ${CData:-}$rc${CError:-} for${CData:-} $remote_path${CReset:-}" |
            tee >&2 -a "$LOG_DIR/error.log"
        touch "$STATUS_DIR/error"
        return $rc
    fi

    echo -en "\n$(date)  done"
}

# Wait for sshd, prepare autostart dirs, and execute autostart scripts on VM
function ssh_process_autostart {
    local vm_name=$1

    # Run this function in sub-shell to protect our caller's environment
    # (which might be _our_ environment if we get called again)
    (
    source "$CONFIG_DIR/config.$vm_name"
    ssh_env_for_node "$vm_name"

    local ssh_port
    if [ -n "${PXE_TMP_NODE_IP:-""}" ]; then
        ssh_port=22
    elif [ ${PROVIDER:-""} = virtualbox ]; then
        ssh_port=$VM_SSH_PORT
    else
        ssh_port=22
    fi

    wait_for_ssh "$ssh_port"
    vm_ssh "$ssh_port" "rm -rf lib config autostart scripts"
    vm_scp_to_vm "$ssh_port" "$TOP_DIR/lib" "$TOP_DIR/config" "$TOP_DIR/scripts"

    local script_path=""
    for script_path in "$AUTOSTART_DIR/"*.sh; do
        ssh_exec_script "$ssh_port" "$script_path"
        rm -f "$script_path" >&2
    done
    touch "$STATUS_DIR/done"

    )
}

#-------------------------------------------------------------------------------
# Autostart mechanism
#-------------------------------------------------------------------------------

function autostart_reset {
    clean_dir "$AUTOSTART_DIR"
    clean_dir "$STATUS_DIR"
}

function process_begin_files {
    local processing=("$STATUS_DIR"/*.sh.begin)
    if [ -n "${processing[0]-}" ]; then
        local file
        for file in "${processing[@]}"; do
            echo >&2 -en "\nVM processing $(basename "$file" .begin)"
            rm "$file"
        done
    fi
}

# Wait until all autofiles are processed (indicated by a "$STATUS_DIR/done"
# file created either by osbashauto or ssh_process_autostart)
function wait_for_autofiles {
    shopt -s nullglob

    ${WBATCH:-:} wbatch_wait_auto
    # Remove autostart files and return if we are just faking it for wbatch
    ${OSBASH:+:} autostart_reset
    ${OSBASH:+:} return 0

    until [ -f "$STATUS_DIR/done" -o -f "$STATUS_DIR/error" ]; do
        # Note: begin files (created by indicate_current_auto) are only visible
        # if the STATUS_DIR directory is shared between host and VM
        ${WBATCH:-:} process_begin_files
        echo >&2 -n .
        sleep 1
    done
    # Check for remaining *.sh.begin files
    ${WBATCH:-:} process_begin_files
    if [ -f "$STATUS_DIR/done" ]; then
        rm "$STATUS_DIR/done"
    else
        echo -e >&2 "${CError:-}\nERROR occured. Exiting.${CReset:-}"
        exit 1
    fi
    echo
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Prepending numbers ensures scripts will be executed in the order they
# were added to the queue.

function _autostart_queue {
    local src_path=$SCRIPTS_DIR/$1
    local src_name=${1##*/}

    # If we get a target name, file will be renamed
    local target_name=${2:-$src_name}

    if [[ $target_name = *.sh ]]; then
        # Create target file name like 01_apt_init.sh
        local prefix=$(get_next_prefix "$AUTOSTART_DIR" "sh" 2)
        target_name="${prefix}_$target_name"
    fi

    if [ "$src_name" = "$target_name" ]; then
        echo >&2 -e "\t$src_name"
    else
        echo >&2 -e "\t$src_name -> $target_name"
    fi

    cp -- "$src_path" "$AUTOSTART_DIR/$target_name"
    ${WBATCH:-:} wbatch_cp_auto "$src_path" "$AUTOSTART_DIR/$target_name"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Print to the console which file requested guest scripts to run
function log_autostart_source {
    # If the caller doesn't provide a config file, log the caller's source file
    local src_file=${1:-${BASH_SOURCE[1]##*/}}
    echo >&2 "Copying autostart files set in $src_file"
}

# autostart <file> [<file> ...]
# e.g. autostart zero_empty.sh osbash/base_fixups.sh
function autostart {
    # Don't log this file -- log our caller's source file
    log_autostart_source "${BASH_SOURCE[1]##*/}"

    while (($#)); do
        local src_file=$1
        shift
        _autostart_queue "$src_file"
    done
}

# Parse options given to configuration commands. Return parsed values by
# setting variables to be used by caller.
function get_cmd_options {
    local OPTIND
    local opt

    while getopts :g:n: opt; do
        case $opt in
            g)
                vm_ui=$OPTARG
                ;;
            n)
                vm_name=$OPTARG
                ;;
            *)
                echo -e >&2 "${CError:-}Error: bad option ${CData:-}$OPTARG.${CReset:-}"
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))

    # Assign the remaining arguments back to args
    args=$@
}

# Parse command and arguments after a "cmd" token in config/scripts.*
function command_from_config {
    local cmd=$1
    shift

    # Local variables that may be changed by get_cmd_options
    local vm_name=${NODE_NAME:-""}
    local vm_ui=${VM_UI:-""}

    local args=$@
    case "$cmd" in
        boot)
            # Format: boot [-g <gui_type>] [-n <node_name>]
            # Boot with queued autostart files now, wait for end of scripts
            # processing
            get_cmd_options $args
            echo >&2 "VM_UI=$vm_ui _vm_boot_with_autostart $vm_name"
            VM_UI=$vm_ui _vm_boot_with_autostart "$vm_name"
            if [ -n "${PXE_TMP_NODE_IP:-""}" ]; then
                echo >&2 "Unsetting PXE_TMP_NODE_IP."
                unset PXE_TMP_NODE_IP
            fi
            ;;
        snapshot)
            # Format: snapshot [-n <node_name>] <snapshot_name>
            get_cmd_options $args
            local shot_name=$args
            echo >&2 vm_conditional_snapshot "$vm_name" "$shot_name"
            vm_conditional_snapshot "$vm_name" "$shot_name"
            ;;
        shutdown)
            # Format: shutdown [-n <node_name>]
            get_cmd_options $args
            echo >&2 "vm_acpi_shutdown $vm_name"
            vm_acpi_shutdown "$vm_name"
            echo >&2 vm_wait_for_shutdown "$vm_name"
            vm_wait_for_shutdown "$vm_name"
            conditional_sleep 1
            ;;
        wait_for_shutdown)
            # Format: wait_for_shutdown [-n <node_name>]
            get_cmd_options $args
            echo >&2 vm_wait_for_shutdown "$vm_name"
            vm_wait_for_shutdown "$vm_name"
            ;;
        snapshot_cycle)
            # Skip command if user disabled snapshot cycles
            if [ "${SNAP_CYCLE:-}" = "no" ]; then
                return
            fi
            # Format: snapshot_cycle [-g <gui_type>] [-n <node_name>]
            # comprises shutdown, boot, wait_for_shutdown, snapshot
            get_cmd_options $args
            local shot_name=$args
            echo >&2 snapshot_cycle "$vm_name" "$shot_name"
            _autostart_queue "shutdown.sh"
            _vm_boot_with_autostart "$vm_name"
            if [ -n "${PXE_TMP_NODE_IP:-""}" ]; then
                echo >&2 "Unsetting PXE_TMP_NODE_IP."
                unset PXE_TMP_NODE_IP
            fi
            vm_wait_for_shutdown "$vm_name"
            vm_conditional_snapshot "$vm_name" "$shot_name"
            ;;
        boot_set_tmp_node_ip)
            # format: boot_set_tmp_node_ip
            get_cmd_options $args
            echo >&2 PXE_TMP_NODE_IP=$PXE_INITIAL_NODE_IP
            PXE_TMP_NODE_IP=$PXE_INITIAL_NODE_IP
            ;;
        create_node)
            # Format: create_node [-n <node_name>]
            get_cmd_options $args
            echo >&2 vm_create_node "$vm_name"
            vm_create_node "$vm_name"
            ;;
        create_pxe_node)
            # Format: create_pxe_node [-n <node_name>]
            get_cmd_options $args
            if [ "$PROVIDER" = "kvm" ]; then
                echo -e >&2 "${CError:-}PXE booting with KVM is currently" \
                    "not supported.\nPlease file a bug if you need it." \
                    "${CReset:-}"
                exit 1
            fi
            # Set FIRST_DISK_SIZE to disable use of basedisk for PXE booting
            FIRST_DISK_SIZE=10000
            echo >&2 "PXE boot node, set FIRST_DISK_SIZE=$FIRST_DISK_SIZE."
            echo >&2 vm_create_node "$vm_name"
            vm_create_node "$vm_name"
            ;;
        queue_renamed)
            # Queue a script for autostart, replacing xxx with vm_name
            # Format: queue <script_name> [-n <node_name>]
            get_cmd_options $args
            local script_rel_path=$args
            local old_name=$(basename "$script_rel_path")
            # Replace xxx with vm_name
            local new_name=${old_name/xxx/$vm_name}
            echo >&2 _autostart_queue "$script_rel_path" "$new_name"
            _autostart_queue "$script_rel_path" "$new_name"
            ;;
        queue)
            # Queue a script for autostart
            # Format: queue <script_name>
            local script_rel_path=$args
            echo >&2 _autostart_queue "$script_rel_path"
            _autostart_queue "$script_rel_path"
            ;;
        cp_iso)
            # Format: cp_iso [-n <node_name>]
            get_cmd_options $args
            local iso_name=$(get_iso_name)
            # Run this function in sub-shell to protect our caller's environment
            # (which might be _our_ environment if we get called again)
            (
            source "$CONFIG_DIR/config.$vm_name"
            ssh_env_for_node "$vm_name"

            local ssh_port
            if [ ${PROVIDER:-""} = virtualbox ]; then
                ssh_port=$VM_SSH_PORT
            else
                ssh_port=22
            fi
                    echo >&2 "cp_iso $vm_name $args"
                    vm_scp_to_vm "$ssh_port" "$ISO_DIR/$iso_name"
            )
            ;;
        *)
            echo -e >&2 "${CError:-}Error: invalid cmd: ${CData:-}$cmd${CReset:-}"
            exit 1
            ;;
    esac
}

# Parse config/scripts.* configuration files
function autostart_from_config {
    local config_file=$1
    local config_path=$CONFIG_DIR/$config_file

    if [ ! -f "$config_path" ]; then
        echo -e >&2 "${CMissing:-}Config file not found: ${CData:-}$config_file${CReset:-}"
        return 1
    fi

    log_autostart_source "$config_file"

    # Open file on file descriptor 3 so programs we call in this loop (ssh)
    # are free to mess with the standard file descriptors.
    exec 3< "$config_path"
    while read -r field_1 field_2 <&3; do
        if [[ $field_1 =~ (^$|^#) ]]; then
            # Skip empty lines and lines that are commented out
            continue
        elif [ "$field_1" == "cmd" ]; then
            if [ -n "${JUMP_SNAPSHOT:-""}" ]; then
                if [[ $field_2 =~ ^snapshot.*${JUMP_SNAPSHOT} ]]; then
                    echo >&2 "Skipped forward to snapshot $JUMP_SNAPSHOT."
                    unset JUMP_SNAPSHOT
                fi
            else
                command_from_config $field_2
            fi
        else
            # Syntax error
            echo -e -n >&2 "${CError:-}ERROR in ${CInfo:-}$config_file: ${CData:-}'$field_1${CReset:-}"
            if [ -n "$field_2" ]; then
                echo >&2 " $field_2'"
            else
                echo >&2 "'"
            fi
            exit 1
        fi
    done
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Get node names from scripts config file
function script_cfg_get_nodenames {
    local config_name=$(get_distro_name "$DISTRO")_cluster
    local scripts_cfg="$CONFIG_DIR/scripts.$config_name"
    local node

    node_names=""

    while read -r line; do
        if [[ $line =~ ^cmd\ .*\ -n\ ([^ ]*)\ .* ]]; then
            node=${BASH_REMATCH[1]}
            if ! [[ $node_names =~ $node ]]; then
                node_names="$node_names $node"
            fi
        fi
    done < "$scripts_cfg"
    echo $node_names
    echo >&2 $node_names
}

#-------------------------------------------------------------------------------
# Functions to get install ISO images
#-------------------------------------------------------------------------------

function download {
    local url=$1
    local dest_dir=$2
    local dest_file=$3
    local rc=0

    if [ -n "${VM_PROXY:-""}" ]; then
        echo "Using VM_PROXY as http_proxy: $VM_PROXY"
        export http_proxy=$VM_PROXY
    fi

    local wget_exe=$(which wget)
    mkdir -pv "$dest_dir"
    if [ -n "$wget_exe" ]; then
        $wget_exe --output-document "$dest_dir/$dest_file" "$url"||rc=$?
    else
        # Mac OS X has curl instead of wget
        local curl_exe=$(which curl)
        if [ -n "$curl_exe" ]; then
            $curl_exe "$url" -o "$dest_dir/$dest_file"||rc=$?
        fi
    fi
    if [ $rc -ne 0 ]; then
        echo -e >&2 "${CError:-}Unable to download ${CData:-}$url${CError:-}.${CReset:-}"
        return 1
    fi
}

function get_iso_name {
    basename "${ISO_URL:-}"
}

# If ISO image is missing from IMG_DIR, try downloading it.
function download_iso_if_necessary {
    local iso_name=$(get_iso_name)
    if [ ! -f "$ISO_DIR/$iso_name" ]; then
        echo >&2 "$iso_name not in $ISO_DIR; downloading."
        if ! download "$ISO_URL" "$ISO_DIR" "$iso_name"; then
            echo -e >&2 "${CError:-}Download failed.${CReset:-}"
            # Remove empty file
            rm "$ISO_DIR/$iso_name"
            return 1
        fi
    else
        echo >&2 "$iso_name already in $ISO_DIR."
    fi
}

# Get ISO image for installation. If the download fails, get an alternative URL
# and try again.
function find_install-iso {
    if ! download_iso_if_necessary; then
        # No local ISO file and download failed
        echo -e >&2 "${CStatus:-}Trying to find alternative.${CReset:-}"
        update_iso_variables

        if ! download_iso_if_necessary; then
            echo -e >&2 "${CError:-}Exiting.${CReset:-}"
            exit 1
        fi
    fi
}

function check_md5 {
    local file=$1
    local csum=$2
    local md5exe
    if [ ! -f "$file" ]; then
        echo -e >&2 "${CError:-}File $file not found. Aborting.${CReset:-}"
        exit 1
    fi
    if ! md5exe=$(which md5sum); then
        # On Mac OS X, the tool is called md5
        if ! md5exe=$(which md5); then
            echo -e >&2 "${CError:-}Neither md5sum nor md5 executable found." \
                " Aborting.${CReset:-}"
            exit 1
        fi
    fi
    echo -e >&2 -n "${CStatus:-}Verifying MD5 checksum: ${CReset:-}"
    if $md5exe "$file" | grep -q "$csum"; then
        echo >&2 "okay."
    else
        echo -e >&2 "${CError:-}Verification failed. File corrupt:${CReset:-}"
        echo >&2 "$file"
        echo -e >&2 "${CError:-}Please remove file and re-run osbash script.${CReset:-}"
        exit 1
    fi
}

# vim: set ai ts=4 sw=4 et ft=sh:
