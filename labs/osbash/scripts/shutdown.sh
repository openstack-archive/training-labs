#!/usr/bin/env bash
set -o errexit -o nounset
TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

indicate_current_auto

exec_logfile

echo "Shutting down"

# Shutdown some time after returning so our caller has time to finish
sudo -b sh -c 'sleep 2; systemctl poweroff'
