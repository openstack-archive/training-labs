# This file contains bash functions that may be used by guest systems (VMs).

# Sourcing this file calls functions fix_path_env and source_deploy.

source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.sh"
source "$LIB_DIR/functions-common-devstack"

# Make devstack's operating system identification work with nounset
function init_os_ident {
    if [[ -z "${os_PACKAGE:-""}" ]]; then
        GetOSVersion
    fi
}

function source_deploy {
    if [ -n "${VM_SHELL_USER:-}" ]; then
        # Already sourced
        return 0
    fi
    if mountpoint -q /vagrant; then
        source "$CONFIG_DIR/deploy.vagrant"
    else
        source "$CONFIG_DIR/deploy.osbash"
    fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# If our sudo user's PATH is preserved (and does not contain sbin dirs),
# some commands won't be found. Observed with Vagrant shell provisioner
# scripts using sudo after "su - vagrant".
# Adding to the path seems preferable to messing with the vagrant user's
# sudoers environment (or working with a separate Vagrant user).

function fix_path_env {
    if is_root; then return 0; fi
    if echo 'echo $PATH'|sudo sh|grep -q '/sbin'; then return 0; fi
    export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
function zero_empty_space {
    echo "Filling empty disk space with zeros"
    sudo dd if=/dev/zero of=/filler bs=1M 2>/dev/null || true
    sudo rm /filler
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# For guest scripts to let osbash know they are running; used when osbashauto
# runs scripts inside of the VM (STATUS_DIR directory must be shared between
# host and VM).

function indicate_current_auto {
    if [ "${VM_SHELL_USER:-}" = "osbash" ]; then
        local scr_name=${1:-$(basename "$0")}
        local fpath=${2:-"/$STATUS_DIR/$scr_name.begin"}
        mkdir -p "$STATUS_DIR"
        touch "$fpath"
    fi
    log_point "script begin"
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Debug function to make a script halt execution until a tmp file is removed

function wait_for_file {
    # If no argument is passed, use empty string (to pass nounset option)
    local msg=${1-""}
    local wait_file=remove_to_continue
    [ -n "$msg" ] && wait_file=${wait_file}_${msg}
    echo >&2 "DEBUG wait_for_file pause; remove /tmp/$wait_file to continue."
    touch "/tmp/$wait_file"
    while [ -e "/tmp/$wait_file" ]; do
        sleep 1
    done
}
#-------------------------------------------------------------------------------
# Copy stdin/stderr to log file
#-------------------------------------------------------------------------------

function exec_logpath {
    local log_path=$1

    # Append all stdin and stderr to log file
    exec > >(tee -a "$log_path") 2>&1
}

function exec_logfile {
    local log_dir=${1:-/home/$VM_SHELL_USER/log}

    # Default extension is log
    local ext=${2:-log}

    mkdir -p "$log_dir"

    # Log name based on name of running script
    local base_name=$(basename "$0" .sh)

    local prefix=$(get_next_prefix "$log_dir" "$ext")
    local log_name="${prefix}_$base_name.$ext"

    exec_logpath "$log_dir/$log_name"
}

#-------------------------------------------------------------------------------
# Functions that need to run as root
#-------------------------------------------------------------------------------

# /sbin/mount.vboxsf often ends up as a broken symlink, resulting in errors
# when trying to mount the share in osbashauto.
function as_root_fix_mount_vboxsf_link {
    local file=/sbin/mount.vboxsf
    if [ -L $file -a ! -e $file ]; then
        echo "$file is a broken symlink:"
        ls -l "$file"
        echo "Trying to fix it."

        sdir="/usr/lib/VBoxGuestAdditions"
        if [ -L "$sdir" -a ! -e "$sdir" ]; then
          # /usr/lib/VBoxGuestAdditions is a convenient link into a directory
          # under /opt that changes its name with VirtualBox versions.
          # In some cases, the link was missing but /sbin/mount.vboxsf
          # pointed there.
          echo "$sdir is a broken symlink:"
          ls -l "sdir"
          shopt -s nullglob
          local new=(/opt/VBoxGuestAdditions*/lib/VBoxGuestAdditions)
          if [ -n "$new" ]; then
              ln -sv "$new" "$sdir"
          else
              echo "as_root_fix_mount_vboxsf_link: no VGA dir, aborting."
              return 1
          fi
        fi

        if [ -L $file -a ! -e $file ]; then
          # In some cases, /sbin/mount.vboxsf gets the path in
          # /usr/lib/VBoxGuestAdditions. Try to fix the link.
          echo "Trying harder."
          new_target=$(find "$sdir/" -name "mount.vboxsf")
          if [ -z "$new_target" ]; then
              echo "as_root_fix_mount_vboxsf_link: no mount.vboxsf, aborting."
              return 1
          else
              echo "Found new target: $new_target"
          fi
          ln -svf "$new_target" "$file"
        fi
    fi
}

function as_root_inject_sudoer {
    if grep -q "${VM_SHELL_USER}" /etc/sudoers; then
        echo "${VM_SHELL_USER} already in /etc/sudoers"
    else
        echo "${VM_SHELL_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        echo "Defaults:${VM_SHELL_USER} !requiretty" >> /etc/sudoers
    fi
}

# Change to a regular user to execute a guest script (and log its output)

function as_root_exec_script {
    local script_path=$1
    local script_name="$(basename "$script_path" .sh)"

    echo "$(date) start $script_path"

    local prefix=$(get_next_prefix "$LOG_DIR" "auto")
    local log_path=$LOG_DIR/${prefix}_$script_name.auto

    su - "$VM_SHELL_USER" -c "bash $script_path" >"$log_path" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "$(date) ERROR: status $rc for $script_path" |
            tee >&2 -a "$LOG_DIR/error.log"
    else
        echo "$(date)  done"
    fi
    return $rc
}

#-------------------------------------------------------------------------------
# Root wrapper around devstack functions for manipulating config files
#-------------------------------------------------------------------------------

# Return predictable temporary path for configuration file editing.
# Used to simplify debugging.
function get_iniset_tmpfile {
    local file=$1

    # Set tmpdir="$LOG_DIR" if you want the temporary files to survive reboots.
    local tmpdir="/tmp"
    local ext="iniset"

    local prefix=$(get_next_prefix "$tmpdir" "$ext")

    # Typical tmpfile path: /tmp/000_etc_keystone_keystone.conf.iniset
    local tmpfile=$tmpdir/$prefix$(echo "$file" | tr '/' '_').$ext

    # Create file owned by regular user so it can be edited without privileges
    touch "$tmpfile"

    echo "$tmpfile"
}

# Set an option in an INI file
# iniset config-file section option value
function iniset_sudo {
    if (($# != 4)); then
        echo -n "ERROR: $# instead of 4 arguments for iniset: $*"
        exit 1
    fi

    local file=$1
    shift
    local tmpfile=$(get_iniset_tmpfile "$file")
    # Create a temporary copy, work on it, and copy it back into place
    sudo cp -fv "$file" "$tmpfile"
    echo >&2 iniset "$tmpfile" "$@"
    iniset "$tmpfile" "$@"
    cat "$tmpfile" | sudo tee "$file" >/dev/null
}

# Comment an option in an INI file
# inicomment config-file section option
function inicomment_sudo {
    local file=$1
    shift
    local tmpfile=$(get_iniset_tmpfile "$file")
    # Create a temporary copy, work on it, and copy it back into place
    sudo cp -fv "$file" "$tmpfile"
    echo >&2 inicomment "$tmpfile" "$@"
    inicomment "$tmpfile" "$@"
    cat "$tmpfile" | sudo tee "$file" >/dev/null
}

# Determinate is the given option present in the INI file
# ini_has_option config-file section option
function ini_has_option_sudo {
    local file=$1
    shift
    local tmpfile=$(get_iniset_tmpfile "$file")
    # Create a temporary copy, work on it
    sudo cp -fv "$file" "$tmpfile"
    echo >&2 ini_has_option "$tmpfile" "$@"
    ini_has_option "$tmpfile" "$@"
}

#-------------------------------------------------------------------------------
# Functions for manipulating config files without section
#-------------------------------------------------------------------------------

function iniset_sudo_no_section {
    local file=$1
    shift
    local tmpfile=$(get_iniset_tmpfile "$file")
    # Create a temporary copy, work on it, and copy it back into place
    sudo cp -fv "$file" "$tmpfile"
    iniset_no_section "$tmpfile" "$@"
    cat "$tmpfile" | sudo tee "$file" >/dev/null
}

# ini_has_option_no_section config-file option
function ini_has_option_no_section {
    local xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local file=$1
    local option=$2
    local line
    line=$(sed -ne "/^$option[ \t]*=/ p;" "$file")
    $xtrace
    [ -n "$line" ]
}

# Set an option in an INI file
# iniset_no_section config-file option value
function iniset_no_section {
    local xtrace=$(set +o | grep xtrace)
    set +o xtrace
    local file=$1
    local option=$2
    local value=$3

    [[ -z $option ]] && return

    if ! ini_has_option_no_section "$file" "$option"; then
        # Add it
        sed -i -e "1 i\
$option = $value
" "$file"
    else
        local sep=$(echo -ne "\x01")
        # Replace it
        sed -i -e '/^'${option}'/ s'${sep}'^\('${option}'[ \t]*=[ \t]*\).*$'${sep}'\1'"${value}"${sep} "$file"
    fi
    $xtrace
}


#-------------------------------------------------------------------------------
# OpenStack helpers
#-------------------------------------------------------------------------------

function mysql_exe {
    local cmd="$1"
    echo "mysql cmd: $cmd."
    sudo mysql -u "root" -p"$DATABASE_PASSWORD" -e "$cmd"
}

function setup_database {
    local service=$1
    local db_user=$2
    local db_password=$3

    echo -n "Waiting for database server to come up."
    until mysql_exe quit >/dev/null 2>&1; do
        sleep 1
        echo -n .
    done
    echo

    mysql_exe "CREATE DATABASE $service"
    mysql_exe "GRANT ALL ON ${service}.* TO '$db_user'@'%' IDENTIFIED BY '$db_password';"
    mysql_exe "GRANT ALL ON ${service}.* TO '$db_user'@'localhost' IDENTIFIED BY '$db_password';"
}

# Wait for neutron to come up. Due to a race during the operating system boot
# process, the neutron server sometimes fails to come up. We restart the
# neutron server if it does not reply for too long.
function wait_for_neutron {
    (
    source $CONFIG_DIR/demo-openstackrc.sh
    echo -n "Waiting for neutron to come up."
    local cnt=0
    until openstack network list >/dev/null 2>&1; do
        if [ "$cnt" -eq 10 ]; then
            echo
            echo "ERROR No response from neutron. Restarting neutron-server."
            node_ssh controller "sudo service neutron-server restart"
            echo -n "Waiting for neutron to come up."
        elif [ "$cnt" -eq 20 ]; then
            echo
            echo "ERROR neutron does not seem to come up. Aborting."
            exit 1
        fi
        echo -n .
        sleep 1
        cnt=$((cnt + 1))
    done
    echo
    )
}

# Wait for keystone to come up
function wait_for_keystone {
    (
    source "$CONFIG_DIR/admin-openstackrc.sh"
    echo -n "Waiting for keystone to come up."
    until openstack user list >/dev/null 2>&1; do
        echo -n .
        sleep 1
    done
    echo
    )
}

#-------------------------------------------------------------------------------
# Network configuration
#-------------------------------------------------------------------------------

# Return the nth network interface name (not counting loopback; 0 -> eth0)
function ifnum_to_ifname {
    local if_num=$1

    # Skip loopback and start counting with next interface
    local iface=${IF_NAMES[$((if_num + 1))]}

    echo >&2 "ifnum_to_ifname: interface $if_num is $iface"
    echo "$iface"
}

# Get all network interfaces (e.g. eth0, p2p1, ens0, enp0s3) into an array
function set_iface_list {
    unset IF_NAMES
    local iface
    for iface in $(ip -o link show|awk '/: / {print $2}'|tr -d ':'); do
        IF_NAMES+=($iface)
    done
    echo "Set IF_NAMES to ${IF_NAMES[*]}"
}

function hostname_to_ip {
    local host_name=$1
    getent hosts "$host_name"|awk '{print $1}'
}

function config_network {
    init_os_ident
    if is_ubuntu; then
        source "$LIB_DIR/functions.ubuntu.sh"
    else
        source "$LIB_DIR/functions.fedora.sh"
    fi

    netcfg_init

    # Get network interface configuration (NET_IF_?) for this node
    unset -v NET_IF_0 NET_IF_1 NET_IF_2 NET_IF_3
    get_node_netif_config "$(hostname)"

    local index
    local iftype
    for index in "${!NODE_IF_TYPE[@]}"; do
        iftype=${NODE_IF_TYPE[index]}
        config_netif "$iftype" "$index" "${NODE_IF_IP[index]}"
    done
}

#-------------------------------------------------------------------------------
# Log points
#------------------------------------------------------------------------------

# Record current size of log files of interest so we can later split them
# accordingly.
# Log points can be set anywhere in a client script simply by adding a
# line: log_point "log point name"

function log_point {
    local caller=$(basename "$0" .sh)
    local commit_msg=$1
    local logdir=${2:-/var/log}
    local ext=lsl
    local prefix=$(get_next_prefix "$logdir" "$ext")

    local fname
    fname=${prefix}_$(echo "${caller}_-_$commit_msg"|tr ' ' '_').$ext

    (
    cd "$logdir"
    sudo bash -c "shopt -s nullglob; ls -l auth.log* keystone/* upstart/*.log mysql/* neutron/*" | \
        sudo tee "$logdir/$fname" > /dev/null
    )
}

#-------------------------------------------------------------------------------
# ssh wrapper functions
#-------------------------------------------------------------------------------

function no_chk_ssh {
    echo >&2 "ssh $*"
    # Options set to disable strict host key checking and related messages.
    ssh \
        -o "UserKnownHostsFile /dev/null" \
        -o "StrictHostKeyChecking no" \
        -o LogLevel=error \
        "$@"
}

# ssh from one node VM to another node in the cluster
function node_ssh {
    no_chk_ssh -i "$HOME/.ssh/osbash_key" "$@"
}

#-------------------------------------------------------------------------------
fix_path_env
source_deploy
#-------------------------------------------------------------------------------

# vim: set ai ts=4 sw=4 et ft=sh:
