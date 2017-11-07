#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#-------------------------------------------------------------------------------
# Install the message broker service (RabbitMQ).
# https://docs.openstack.org/install-guide/environment-messaging-ubuntu.html
#-------------------------------------------------------------------------------

echo "Installing RabbitMQ."
sudo apt install -y rabbitmq-server

echo -n "Waiting for RabbitMQ to start."
until sudo rabbitmqctl status >/dev/null; do
    sleep 1
    echo -n .
done
echo

echo ---------------------------------------------------------------
echo "sudo rabbitmqctl status"
sudo rabbitmqctl status
echo - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "sudo rabbitmqctl report"
sudo rabbitmqctl report
echo ---------------------------------------------------------------

echo "Adding openstack user to messaging service."
sudo rabbitmqctl add_user openstack "$RABBIT_PASS"

echo "Permitting configuration, write and read access for the openstack user."
sudo rabbitmqctl set_permissions openstack ".*" ".*" ".*"
