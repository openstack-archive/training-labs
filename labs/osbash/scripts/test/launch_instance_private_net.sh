#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/demo-openstackrc.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Launch a demo instance.
#------------------------------------------------------------------------------

# Packets from the instance VM destined for the Internet will have its
# floating IP address as the sender address. For your instance VM to
# get Internet access, you will probably have to configure masquerading
# on your host computer.

# On Linux, turning on masquerading may look something like this:

# echo "1" > /proc/sys/net/ipv4/ip_forward
# modprobe ip_tables
# modprobe ip_conntrack
# iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# iptables -A FORWARD -i eth0 -o vboxnet2 -m state \
#          --state RELATED,ESTABLISHED -j ACCEPT
# iptables -A FORWARD -i vboxnet2 -o eth0 -j ACCEPT

# Set this true if you have masquerading enabled to allow instance VMs access
# to the Internet.
: ${MASQUERADING:=true}

# Set this true if you want the instance to use the Google Public DNS name
# server. The default uses dnsmasq running on a node.
: ${EXT_DNS:=true}

DEMO_INSTANCE_NAME=private-instance

echo "SUM --- BEGIN"

function ssh_no_chk_node {
    ssh_no_chk -i "$HOME/.ssh/osbash_key" "$@"
}

function ssh_no_chk {
    echo "ssh $*"
    # Options set to disable strict host key checking and related messages.
    ssh \
        -o "UserKnownHostsFile /dev/null" \
        -o "StrictHostKeyChecking no" \
        -o LogLevel=error \
        "$@"
}

# Work around neutron client failing with unsupported locale settings
if [[ "$(neutron --help)" == "unsupported locale setting" ]]; then
    echo "Locale not supported on node, setting LC_ALL=C."
    export LC_ALL=C
fi

function wait_for_service {
    local node=$1
    local service=$2
    local cnt=0
    echo -n "Node $node, service $service:"
    until ssh_no_chk_node "$node" service "$service" status | \
            grep -q "active (running)"; do
        cnt=$((cnt + 1))
        if [ $((cnt % 150)) -eq 0 ]; then
            echo " does not seem to come up. Forcing restart."

            echo
            echo "SUM ERROR $service on node $node not coming up."
            ssh_no_chk_node "$node" \
                sudo service "$service" restart
            SERVICE_RESTARTS="${SERVICE_RESTARTS:-""}$service@$node "
        fi
        sleep 2
        echo -n .
    done
    echo " up"
}

echo "Running on host: $(hostname)"

echo "Checking network connection to compute1 node."
ping -c1 compute1
echo

echo "Checking services on controller node."
wait_for_service controller neutron-l3-agent
wait_for_service controller neutron-dhcp-agent
wait_for_service controller neutron-metadata-agent
echo

echo "Checking services on compute1 node."
wait_for_service compute1 nova-compute
echo

function wait_for_nova_compute {

    echo "  Waiting for nova-compute service in state 'up'."
    if ssh_no_chk_node compute1 service nova-compute status | \
            grep -q "start/running"; then
        echo -n "  Service is up, waiting (may take a few minutes)."
    fi

    local cnt=0
    local start=$(date +%s)
    (
    source "$CONFIG_DIR/admin-openstackrc.sh"
    until openstack compute service list --service nova-compute | grep -q "| up "; do
        cnt=$((cnt + 1))
        sleep 5
        if ssh_no_chk_node compute1 service nova-compute status | \
                grep -q "start/running"; then
            if [ $cnt -eq 300 ]; then
                # This should never happen.
                echo "SUM ABORT nova-compute status remains down while service is up."
                echo "Aborting."
                exit 1
            fi
            echo -n .
        else
            echo
            echo "SUM ERROR nova-compute on compute node has died."
            echo "Restarting nova-compute on compute node."
            ssh_no_chk_node compute1 \
                sudo service nova-compute restart
            echo "SUM ERROR nova-compute restart in wait_for_nova_compute"
        fi
    done
    )
    echo
}

function wait_for_nova_services {
    local start=$(date +%s)

    (
    source "$CONFIG_DIR/admin-openstackrc.sh"
    echo "Checking for nova services in openstack compute service list."

    echo -n "  nova-scheduler"
    until openstack compute service list --service nova-scheduler | \
            grep -q '| up '; do
        sleep 1
        echo -n .
    done
    echo

    echo -n "  nova-conductor"
    until openstack compute service list --service nova-conductor | \
            grep -q '| up '; do
        sleep 1
        echo -n .
    done
    echo

    echo -n "  nova-compute"
    if ! openstack compute service list --service nova-compute | \
            grep -q '| up '; then
        wait_for_nova_compute
    fi
    echo
    )

    echo
    echo "SUM wait for nova services: $(($(date +%s) - start))"
}

wait_for_nova_services

(
source "$CONFIG_DIR/admin-openstackrc.sh"
echo "All services are ready:"
openstack compute service list
echo
)

function show_compute_resource_usage {
    echo "openstack server list:"
    openstack server list
    (
    source "$CONFIG_DIR/admin-openstackrc.sh"
    echo "As admin user, openstack host list:"
    openstack host list
    echo "As admin user, openstack host show compute1:"
    openstack host show compute1
    )
}

function wait_for_neutron_agents {
    local agent_list=$LOG_DIR/test-agent.list
    local start=$(date +%s)
    echo -n "Waiting for agents in openstack network agent list."
    (
    source "$CONFIG_DIR/admin-openstackrc.sh"
    openstack network agent list | sort > "$agent_list"
    local out=$(grep " :-)  " "$agent_list" || rc=$?)
    if [ -n "$out" ]; then
        echo
        echo "$out"
    fi
    while : ; do
        openstack network agent list | sort > "$agent_list.new"
        out=$(comm -13 "$agent_list" "$agent_list.new")
        if [ -n "$out" ]; then
            echo
            echo "$out"
        fi
        if ! grep -q " XXX  " "$agent_list"; then
            break
        fi
        mv "$agent_list.new" "$agent_list"
        sleep 1
        echo -n .
    done
    echo
    echo "All agents are ready."
    openstack network agent list
    echo
    )
    echo "SUM wait for neutron agents: $(($(date +%s) - start))"
}

wait_for_neutron_agents

#------------------------------------------------------------------------------
# Launch an instance
# https://docs.openstack.org/install-guide/launch-instance.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create m1.nano flavor
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

(
echo
echo "Check if m1.nano flavor is existing or else, create the flavor."

source "$CONFIG_DIR/admin-openstackrc.sh"
echo "Current flavors:"
openstack flavor list

if openstack flavor list | grep m1.nano; then
    echo "Proceeding, m1.nano flavor exists."
else
    echo "Creating m1.nano flavor which is just big enough for CirrOS."
    openstack flavor create --id 0 --vcpus 1 --ram 64 --disk 1 m1.nano
fi
echo
)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Generate a key pair
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [ ! -f ~/.ssh/id_rsa ]; then
    echo "Generating an ssh key pair (saved to ~/.ssh/id_rsa*)."
    # For training cluster: no password protection on keys to make scripting
    # easier
    ssh-keygen -f ~/.ssh/id_rsa -N ""
fi

function check_demo_key {
    echo -n "Checking if 'mykey' is already in our OpenStack environment: "
    if openstack keypair show mykey >/dev/null 2>&1; then
        echo "yes."

        echo -n "Checking if the 'mykey' key pair matches our ssh key: "

        ssh_key=$(< ~/.ssh/id_rsa.pub awk '{print $2}')
        stored_key=$(openstack keypair show --public-key mykey | \
            awk '{print $2}')

        if [ "$ssh_key" != "$stored_key" ]; then
            echo "no."
            echo "Removing the 'mykey' from the OpenStack envirnoment."
            openstack keypair delete mykey
        else
            echo "yes."
        fi
    else
        echo "no."
    fi
}
check_demo_key

if ! openstack keypair show mykey 2>/dev/null; then
    echo "Adding the public key to our OpenStack environment."
    openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
fi


echo "Verifying addition of the public key."
openstack keypair list

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Add security group rules
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo
echo "Permitting ICMP (ping) to our instances."
openstack security group rule create --proto icmp default || rc=$?
if [ ${rc:-0} -ne 0 ]; then
    echo "Rule was already there."
fi

echo
echo "Permitting secure shell (SSH) access to our instances."
openstack security group rule create --proto tcp --dst-port 22 default || rc=$?
if [ ${rc:-0} -ne 0 ]; then
    echo "Rule was already there."
fi

echo
echo "Verifying security group rules."
openstack security group list
openstack security group show default

#------------------------------------------------------------------------------
# Launch an instance on the self-service network
# https://docs.openstack.org/install-guide/launch-instance-selfservice.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Determine instance options
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Listing available flavors."
openstack flavor list

echo "Listing available images."
openstack image list

# Wait for neutron to start
wait_for_neutron

echo "Listing available networks."
openstack network list

PRIVATE_SUBNET=selfservice

PRIVATE_NET_ID=$(openstack network list | awk "/ $PRIVATE_SUBNET / {print \$2}")
echo "ID for demo-net tenant network: $PRIVATE_NET_ID"

echo "Listing available security groups."
openstack security group list

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# XXX Network settings
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Settings for $PRIVATE_SUBNET:"
openstack subnet show $PRIVATE_SUBNET
echo

echo "Checking for DNS name servers in subnet $PRIVATE_SUBNET" \
     "(passed to booting instance VMs)."
current_dns_string=$(openstack subnet show -c dns_nameservers \
                        -fvalue $PRIVATE_SUBNET)
if [ "$EXT_DNS" = true ]; then
    if [ -n "$current_dns_string" ]; then
        echo "DNS name server already set ($current_dns_string)."
    else
        echo "Setting DNS name server for subnet $PRIVATE_SUBNET."
        openstack subnet set $PRIVATE_SUBNET --dns-nameserver 8.8.8.8
    fi
else
    echo "Clearing DNS name server(s) for subnet $PRIVATE_SUBNET."
    # Servers are comma separated (e.g., "8.8.4.4, 8.8.8.8")
    dns_servers=$(echo $current_dns_string | tr ' ,' '\n')
    for server in $dns_servers; do
        openstack subnet unset --dns-nameserver $server $PRIVATE_SUBNET
    done
fi

echo "Settings for $PRIVATE_SUBNET:"
openstack subnet show $PRIVATE_SUBNET
echo

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Clean out old instances
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

openstack server list
openstack server list | awk " / $DEMO_INSTANCE_NAME / {print \$2}" | while read instance; do
    echo "Removing instance $DEMO_INSTANCE_NAME ($instance)."
    openstack server delete "$instance"
done
echo -n "Waiting for removed instances to disappear (may take > 1 min)."
while openstack server list|grep -q "$DEMO_INSTANCE_NAME"; do
    sleep 1
    echo -n .
done
echo

function check_for_other_vms {
    echo "Verifying that no other instance VMs are left."
    (
    source "$CONFIG_DIR/admin-openstackrc.sh"
    if [ "$(openstack server list --all-projects | wc -l)" -gt 4 ]; then
        echo "SUM ERROR Unexpected VMs found. Aborting..."
        openstack server list --all-projects
        exit 1
    fi
    )
}
check_for_other_vms
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

NOVA_SCHED_LOG=/var/log/nova/nova-scheduler.log
NOVA_API_LOG=/var/log/nova/nova-api.log


VM_LAUNCHES=0

function request_instance {
    # Keep a copy of current state of nova-scheduler.log
    sudo cp -vf $NOVA_SCHED_LOG $NOVA_API_LOG /tmp

    if [ -n "${instance_info:-""}" ]; then
        rm -f "$instance_info"
    else
        instance_info=$LOG_DIR/test-instance.info
        echo "Instance info: $instance_info"
    fi

    echo "Requesting an instance."
    openstack server create \
        --flavor m1.nano \
        --image "$CIRROS_IMG_NAME" \
        --nic net-id="$PRIVATE_NET_ID" \
        --security-group default \
        --key-name mykey \
        "$DEMO_INSTANCE_NAME" > "$instance_info"
    VM_LAUNCHES=$(( VM_LAUNCHES + 1 ))
}

BOOT_LOG=$LOG_DIR/test-instance.boot
echo "Boot log: $BOOT_LOG"

function save_boot_log {
    local rc=0
    rm -f "$BOOT_LOG"
    openstack console log show "$DEMO_INSTANCE_NAME" >"$BOOT_LOG" 2>&1 || rc=$?
    if [ $rc -ne 0 ]; then
        echo >&2 "openstack console log show returned error status $rc"
    fi
    return $rc
}

function explain_instance_failure {
    cat << TXT_INSTANCE_FAILURE

  After deleting an instance, it can take nova up to a minute to realize that
  the compute node is free. Under tight space constraints, this becomes a
  common source of failure.

  As an admin, we could list hosts (including compute hosts):

  $ openstack host list

  And check resource usage in description of host 'compute':

  $ openstack host show compute1

  As a regular user, we would have to keep trying for up to a minute and hope
  it works soon.

  The fastest way to update the database, however, is to restart nova-compute
  on the compute node.

TXT_INSTANCE_FAILURE
}

function status_409_fixed {
    echo "Checking log files for cause of failure."

    if sudo comm -13 /tmp/nova-scheduler.log $NOVA_SCHED_LOG |
            grep "has not been heard from in a while"; then
        echo
        echo "SUM ERROR Missing connection with nova-compute on compute node."
        echo "(Did controller node boot after compute node?)"
        echo
    elif sudo comm -13 /tmp/nova-scheduler.log $NOVA_SCHED_LOG |
            grep "Filter RamFilter returned 0 hosts"; then
        echo "SUM ERROR Filter RamFilter returned 0 hosts"
        explain_instance_failure
        show_compute_resource_usage
    elif sudo comm -13 /tmp/nova-api.log $NOVA_API_LOG |
            grep "HTTP exception thrown:"; then
        # Just waiting should be enough to fix this
        echo -n "Waiting for HTTP status 409 to cure itself."
        local cnt=0
        until [ $cnt -eq 5 ]; do
            if ! console_status_409; then
                HTTP_EXCEPTIONS="${HTTP_EXCEPTIONS:-""}$cnt "
                echo "okay"
                # We can continue with this instance
                return 0
            fi
            cnt=$((cnt + 1))
            sleep 2
            echo -n .
        done
        HTTP_EXCEPTIONS="${HTTP_EXCEPTIONS:-""}${cnt}-fail "
        echo "failed"
    else
        echo "Unknown reason. See for yourself."
        echo "nova-scheduler.log:"
        sudo comm -13 /tmp/nova-scheduler.log $NOVA_SCHED_LOG
        echo "nova-api.log:"
        sudo comm -13 /tmp/nova-api.log $NOVA_API_LOG
        echo "SUM ABORT Unknown 409 error"
        exit 1
    fi
    # Not fixed, need to try with new VM
    return 1
}

function console_status_409 {
    ! save_boot_log 2>/dev/null &&
        grep -q "is not ready (HTTP 409)" "$BOOT_LOG"
}

function console_status_404 {
    ! save_boot_log 2>/dev/null &&
        grep -q "Unable to get console (HTTP 404)" "$BOOT_LOG"
}

function instance_status {
    openstack server list | awk "/$DEMO_INSTANCE_NAME/ {print \$6}"
}

function instance_status_is {
    local status=$1
    openstack server list | grep "$DEMO_INSTANCE_NAME" | grep -q "$status"
}

while : ; do
    echo "###################################################################"
    echo "Launching an instance VM ($VM_LAUNCHES)."
    request_instance > /dev/null

    if console_status_409; then
        echo "openstack console log show returned:"
        cat "$BOOT_LOG"
        echo

        if ! status_409_fixed; then

            echo "Instance build failed."
            echo "Deleting failed instance VM."
            openstack server delete "$DEMO_INSTANCE_NAME"

            echo "Checking nova-compute on the compute node."
            wait_for_nova_compute

            echo -n "Requesting new instance VMs until it works."
            cnt=0
            while : ; do
                request_instance >/dev/null
                if console_status_409; then
                    openstack server delete "$DEMO_INSTANCE_NAME"
                    cnt=$((cnt + 1))
                    if [ $cnt -eq 5 ]; then
                        echo
                        echo "SUM ERROR console status remains 409."
                        echo "Restarting nova-compute on compute node."
                        ssh_no_chk_node compute1 \
                            sudo service nova-compute restart
                        echo "SUM ERROR nova-compute restart (status 409)"
                    fi
                    sleep 2
                    echo -n .
                else
                    # Either no error or a different error
                    echo
                    break
                fi
            done
        fi
    fi

    if console_status_404; then
        echo "openstack console log show returned:"
        cat "$BOOT_LOG"
        echo

        echo -n "Waiting for console."
        # Console status 404 may persist after instance status becomes ERROR.
        while console_status_404 && instance_status_is BUILD; do
            sleep 1
            echo -n .
        done
        echo
        if ! console_status_404; then
            echo "Console status is no longer 404."
        fi

    fi

    echo -n "Waiting for instance to get out of BUILD status."
    while instance_status_is BUILD; do
        sleep 1
        echo -n .
    done
    echo

    if instance_status_is ERROR; then
        echo "Instance VM status: ERROR"

        if sudo comm -13 /tmp/nova-scheduler.log $NOVA_SCHED_LOG |
                grep "Filter RetryFilter returned 0 hosts"; then
            echo "SUM ERROR RetryFilter returned 0 hosts"
            show_compute_resource_usage
            echo "Restarting nova-compute on compute node."
            ssh_no_chk_node compute1 \
                sudo service nova-compute restart
            echo "SUM ERROR nova-compute restart (RetryFilter)"
        fi

        echo "Deleting failed instance VM."
        openstack server delete "$DEMO_INSTANCE_NAME"
    elif instance_status_is ACTIVE; then
        echo "Instance VM status: ACTIVE."
        break
    fi

    if [ $VM_LAUNCHES -eq 10 ]; then
        echo "SUM ABORT $VM_LAUNCHES launch attempts failed. Giving up."
        exit 1
    fi
done

if [ "${HTTP_EXCEPTIONS:-0}" != "0" ]; then
    echo "SUM ERROR HTTP exceptions: ${HTTP_EXCEPTIONS:-0}"
fi

echo -n "Waiting for DHCP discover."
until grep -q "Sending discover..." "$BOOT_LOG"; do
    sleep 2
    echo -n .
    save_boot_log
done
echo

echo -n "Waiting for DHCP success."
until grep -q "^Lease of" "$BOOT_LOG"; do
    DHCP_WAIT=$((${DHCP_WAIT:-0} + 1))
    if grep "No lease, failing" "$BOOT_LOG"; then
        echo "SUM ABORT DHCP wait: fail (${DHCP_WAIT:-0})"
        echo "Aborting."
        exit 1
    fi
    sleep 2
    echo -n .
    save_boot_log
done
echo
echo "SUM DHCP wait: ${DHCP_WAIT:-0}"
echo

echo -n "Waiting for metadata success."
until grep -q "successful after" "$BOOT_LOG"; do
    if grep "failed to read iid from metadata" "$BOOT_LOG"; then
        echo "SUM ABORT failed to get metadata"
        echo "Aborting."
        exit 1
    fi
    sleep 2
    echo -n .
    save_boot_log
done
echo

echo -n "Waiting for login prompt."
until grep -q "$DEMO_INSTANCE_NAME login:" "$BOOT_LOG"; do
    sleep 2
    echo -n .
    save_boot_log
done
echo

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Access the instance using a virtual console
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Obtaining a VNC session URL for our instance."
openstack console url show "$DEMO_INSTANCE_NAME"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Access the instance remotely
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo
echo "Creating a floating IP address on the public network."
floating_ip=$(openstack floating ip create provider | awk '/ floating_ip_address / {print $4}')
openstack floating ip list

echo
echo "Associating the floating IP address with our instance."
openstack server add floating ip "$DEMO_INSTANCE_NAME" "$floating_ip"

echo
echo "Checking the status of your floating IP address."
openstack server list

echo
echo -n "Verifying network connectivity to instance VM (may take 2+ min)."
# Since Juno, the floating IP often takes a long time to become pingable.
# Hopefully, this will be fixed, but for the time being we just ping the
# floating IP until we get a reply (or we reach a time limit and give up).
function patient_ping {
    local ip=$1
    local cnt=0

    while : ; do
        echo -n .
        sleep 1

        # Ping the instance VM every ten seconds
        if [[ $((cnt % 10)) -eq 0 ]]; then
            if ping -c1 "$ip" > /dev/null ; then
                echo
                ping -c1 "$ip"
                echo "SUM ping instance VM after $cnt seconds."
                break
            fi
        fi

        # Abort if it takes too long
        if [[ $cnt -gt 600 ]]; then
            echo
            echo "SUM ERROR no ping for instance VM in $cnt seconds. Aborting."
            exit 1
        fi

        cnt=$((cnt + 1))
    done
}

patient_ping "$floating_ip"

echo
echo "Accessing our instance using SSH from the controller node."
ssh_no_chk "cirros@$floating_ip" uptime

echo
echo "Interface configuration on instance VM."
ssh_no_chk "cirros@$floating_ip" /sbin/ip addr

echo
echo "Routing information on instance VM."
ssh_no_chk "cirros@$floating_ip" /sbin/route -n

echo
echo "/etc/resolv.conf on instance VM."
ssh_no_chk "cirros@$floating_ip" cat /etc/resolv.conf

echo
echo "Pinging our own floating IP from inside the instance."
ssh_no_chk "cirros@$floating_ip" ping -c1 "$floating_ip"

function test_internet {
    if [ "$MASQUERADING" = true ]; then
        local ext_ping=1
        echo
        echo "Pinging Google Public DNS name server."
        until ssh_no_chk "cirros@$floating_ip" ping -c1 8.8.8.8; do
            if [ $ext_ping -eq 3 ]; then
                echo "Failed. Giving up."
                echo "Check IP masquerading (Internet sharing) for the VMs" \
                     "on the host system."
                echo "SUM ERROR ping Internet: failed ($ext_ping)"
                ext_ping="$ext_ping (failed)"
                return 0
            fi
            echo
            echo "Trying again in 1 s."
            sleep 1
            ext_ping=$((ext_ping + 1))
        done
        echo "SUM ping Internet: $ext_ping"

        echo
        echo "Testing DNS name resolution within instance VM."
        ssh_no_chk "cirros@$floating_ip" ping -c1 openstack.org
    fi
}

test_internet

# Log memory use
sed 's|^|SUM MEM |' <<< "$(free -m) "

echo
echo "Summary"
echo "======="
echo "SUM service restarts: ${SERVICE_RESTARTS:--}"
echo "SUM instance launches: $VM_LAUNCHES"
echo "SUM END"

echo
echo "Try this, it should work:"
echo "Command: 'ssh cirros@$floating_ip' [ password: 'gocubsgo' ]"

