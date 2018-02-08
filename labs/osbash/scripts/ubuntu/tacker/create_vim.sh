#!/usr/bin/env bash

set -o errexit -o nounset

# This script creates an NFV demo user and a NFV project with a VIM.
# The tacker server is assumed to be up and running.

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
TACKER_DIR="$TOP_DIR/scripts/ubuntu/tacker"

source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"
source "$CONFIG_DIR/credentials"

#------------------------------------------------------------------------------

DEFAULT_VIM_PROJECT_NAME="nfv"
DEFAULT_VIM_USER="nfv_user"
DEFAULT_VIM_PASSWORD="nfv_user_secret"

(
source "$HOME/admin-openrc.sh"

echo "Creating nfv demo project."
openstack project create --domain default \
    --description "NFV demo Project" \
    "$DEFAULT_VIM_PROJECT_NAME"

echo "Creating nfv demo user ($DEFAULT_VIM_USER)."
openstack user create --domain default \
    --password "$DEFAULT_VIM_PASSWORD" \
    "$DEFAULT_VIM_USER"

echo "Granting admin role to nfv user in nfv project."
openstack role add \
    --project "$DEFAULT_VIM_PROJECT_NAME" \
    --user "$DEFAULT_VIM_USER" \
    "admin"

# XXX advsvc role does not seem to be necessary for nfv_user
# echo "Granting advsvc role to nfv_user in nfv project."
# openstack role add \
#     --project "$DEFAULT_VIM_PROJECT_NAME" \
#     --user "$DEFAULT_VIM_USER" \
#     "advsvc"
)

CONTROLLER_MGMT_IP=$(get_node_ip_in_network "controller" "mgmt")

cat "$CONFIG_DIR/demo-openstackrc.sh" | sed -ne "
    s/\$DEMO_PROJECT_NAME/$DEFAULT_VIM_PROJECT_NAME/
    s/\$DEMO_USER_NAME/$DEFAULT_VIM_USER/
    s/\$DEMO_PASS/$DEFAULT_VIM_PASSWORD/
    s/controller/$CONTROLLER_MGMT_IP/
    /^export/p
    " > "$HOME/nfv-openrc.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Register default VIM
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo -e "\n>>> Registering the controller node as the VIM that will be\n" \
        "    used as a default VIM for VNF deployments."
echo -e "    This is required when the optional argument 'cim-id' is not\n" \
        "    provided by the user during 'vnf-create'.\n"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Generate the config.yaml file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

conf="$TACKER_DIR/nvf-demo-vim-config.yaml"

echo -e "\n>>> Creating $conf."

cat << EOM > "$conf"
auth_url: http://$CONTROLLER_MGMT_IP:5000/v3/
username: $DEFAULT_VIM_USER
password: $DEFAULT_VIM_PASSWORD
project_name: $DEFAULT_VIM_PROJECT_NAME
project_domain_name: Default
user_domain_name: Default
EOM

source "$HOME/nfv-openrc.sh"

echo -e "\n>>> Registering VIM."

tacker vim-register --is-default \
       --config-file "$conf" \
       --description "Controller node is VIM" demo-vim

echo -n "Waiting for VIM to become reachable."
cnt=0
while ! tacker vim-show demo-vim | grep "^| status.*REACHABLE"; do
    sleep 1
    echo -n .
    cnt=$((cnt + 1))
    if [ $cnt -eq 20 ]; then
        tacker vim-show demo-vim
        echo "VIM not reachable. Aborting."
        exit 1
    fi
done
echo "VIM is reachable."

tacker vim-show demo-vim

echo "Calling vim-events-list."
tacker vim-events-list
