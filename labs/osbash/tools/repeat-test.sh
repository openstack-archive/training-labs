#!/bin/bash
set -o errexit -o nounset
TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)
source "$TOP_DIR/config/localrc"
source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/deploy.osbash"
source "$OSBASH_LIB_DIR/functions-host.sh"
source "$OSBASH_LIB_DIR/$PROVIDER-functions.sh"

if [ -f "$TOP_DIR/osbash.sh" ]; then
    BUILD_EXE=$TOP_DIR/osbash.sh
    OSBASH=exec_cmd
elif [ -f "$TOP_DIR/st.py" ]; then
    BUILD_EXE=$TOP_DIR/st.py
    # Stacktrain options
    ST_OPT=""
else
    echo "No build exe found."
    exit 1
fi

echo "Using $BUILD_EXE"

RESULTS_ROOT=$LOG_DIR/test-results

CONTROLLER_SNAPSHOT="controller_node_installed"

VERBOSE=${VERBOSE:=1}

function usage {
    echo "Usage: $0 {-b|-c|-t <SNAP>} [-s '<NODES>']"
    echo ""
    echo "-h        Help"
    echo "-c        Restore node VMs to current snapshot for each test"
    echo "-e        Enable snapshot cycles during build"
    echo "-t SNAP   Restore cluster to target snapshot for each test"
    echo "-r REP    Number of repetitions (default: endless loop)"
    echo "-s NODES  Start each named node VM after restoring the cluster"
    echo "-b        Rebuild cluster for each test, from scratch or snapshot"
    echo "          ($(basename $BUILD_EXE) -b cluster [...])"
}

while getopts :bcehqr:s:t: opt; do
    case $opt in
        b)
            REBUILD=yes
            ;;
        c)
            CURRENT=yes
            ;;
        h)
            usage
            exit 0
            ;;
        q)
            echo "Ignoring -q, it is the default now."
            ;;
        e)
            if [ -f "$TOP_DIR/osbash.sh" ]; then
                export SNAP_CYCLE=yes
            else
                ST_OPT="$ST_OPT -e"
            fi
            ;;
        r)
            REP=$OPTARG
            ;;
        s)
            START_VMS=$OPTARG
            ;;
        t)
            arg=$OPTARG
            for node in $(script_cfg_get_nodenames); do
                if vm_exists "$node"; then
                    if vm_snapshot_exists "$node" "$arg"; then
                        TARGET_SNAPSHOT=$arg
                        break
                    fi
                fi
            done
            if [ -z "${TARGET_SNAPSHOT:-""}" ]; then
                echo >&2 "No snapshot named $arg found."
                exit 1
            fi
            ;;
        :)
            echo "Error: -$OPTARG needs argument"
            ;;
        ?)
            echo "Error: invalid option -$OPTARG"
            echo
            usage
            exit 1
            ;;
    esac
done

if [ -z "${REBUILD:-}" -a -z "${CURRENT:-}" -a -z "${TARGET_SNAPSHOT:-}" ]; then
    usage
    exit 1
fi

# Remove processed options from arguments
shift $(( OPTIND - 1 ));

mkdir -p "$RESULTS_ROOT"

# Default to repeating forever
: ${REP:=-1}

function run_test {
        local script_name=$1
        local script_path=$TOP_DIR/scripts/test/$script_name
        local log_path=$LOG_DIR/test-$(basename "$script_name" .sh).log
        echo "Running test. Log file: $log_path"
        TEST_ONCE=$TOP_DIR/tools/test-once.sh
        if [ "${VERBOSE:-}" -eq 1 ]; then
            "$TEST_ONCE" "$script_path" 2>&1 | tee "$log_path" || rc=$?
        else
            "$TEST_ONCE" "$script_path" > "$log_path" 2>&1 || rc=$?
        fi

        echo "################################################################"
        if grep -q "$script_name returned status: 0" "$log_path"; then
            echo "# Test passed: $script_name"
        else
            echo "# ERROR: Test failed: $script_name"
        fi
        echo "################################################################"
}

cnt=0
until [ $cnt -eq $REP ]; do
    cnt=$((cnt + 1))

    dir_name=$(get_next_prefix "$RESULTS_ROOT" "")
    echo "####################################################################"
    echo "Starting test $dir_name."
    dir=$RESULTS_ROOT/$dir_name
    mkdir -p "$dir"

    (
    cd "$TOP_DIR"

    if [ -n "${TARGET_SNAPSHOT:-}" ]; then
        "$TOP_DIR/tools/restore-cluster.sh" -t "$TARGET_SNAPSHOT"
        if [ -n "${START_VMS:-}" ]; then
            # Start VMs as requested by user
            for vm_name in $START_VMS; do
                echo >&2 "$0: booting node $vm_name."
                vm_boot "$vm_name"
                # Sleeping for 10 s fixes some problems, but it might be
                # better to fix client scripts to wait for the services they
                # need instead of just failing.
            done
        fi
    fi

    # Log information about current state of source tree (ignore failure)
    "$TOP_DIR/tools/git_info.sh" > "$LOG_DIR/git_info.log" || rc=$?

    rc=0
    if [ -n "${REBUILD:-}" ]; then
        if [ -n "${TARGET_SNAPSHOT:-}" ]; then
            LEAVE_VMS_RUNNING=yes "$BUILD_EXE" ${ST_OPT:-} -t "$TARGET_SNAPSHOT" -b cluster || rc=$?
        else
            "$BUILD_EXE" ${ST_OPT:-} -b cluster || rc=$?
        fi
    fi
    echo "####################################################################"

    if [ $rc -ne 0 ]; then
        echo "ERROR: Cluster build failed. Skipping test."
    else
        for script_name in launch_instance_private_net.sh heat_stack.sh \
                test_horizon.sh; do
            run_test "$script_name"
        done
    fi
    )

    echo "Copying osbash and test log files into $dir."
    (
    cd "$LOG_DIR"
    cp -a *.auto *.log *.xml *.db *.cfg "$dir" || rc=$?
    )

    echo "Copying upstart log files into $dir."
    "$TOP_DIR/tools/get_node_logs.sh" "$dir"
done
