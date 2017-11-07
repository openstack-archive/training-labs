#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

indicate_current_auto

exec_logfile

# Wait for removal of /tmp/remove_to_continue
wait_for_file
