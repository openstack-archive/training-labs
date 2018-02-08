#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)
TACKER_DIR="$TOP_DIR/scripts/ubuntu/tacker"

source "$TOP_DIR/config/paths"
source "$LIB_DIR/functions.guest.sh"

OPENSTACK_RELEASE=pike

#------------------------------------------------------------------------------
# Install Tacker
# https://docs.openstack.org/tacker/pike/install/manual_installation.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

TACKER_DB_USER=tacker
TACKER_DBPASS=tacker_db_secret
TACKER_PASS=tacker_user_secret

# Tacker is not part of the standard install, cache may be stale by now
sudo apt update

echo "Installing git, pip, and virtualenv."
sudo apt install -y git python-pip virtualenv

echo -e "\n>>> Confirming Port Security configuration in ml2_conf.ini\n"

conf=/etc/neutron/plugins/ml2/ml2_conf.ini
# Get everything from [ml2] to an empty line
ML2=$(awk '/\[ml2\]/,/^$/' "$conf")
echo
if echo "$ML2" | grep "extension_drivers = port_security"; then
    echo ">>> Found extension driver \"port_security\" in file $conf."
    echo
else
    echo "ERROR Extension driver \"port_security\" not found in $conf."
    echo
    exit 1
fi

# Allow users in non-admin projects with 'admin' roles to create flavors.

echo -e "\n>>> Modifying the Heat service /etc/heat/policy.json file.\n"

# XXX heat removes policy.json in Queens (review.openstack.org/#/c/505360/);
# to change defaults, create policy.yaml and have heat.conf point to it:
# conf="/etc/heat/policy.yaml"
# touch "$conf"
# echo '"resource_types:OS::Nova::Flavor": "role:admin"' >> "$conf"
#sudo sed -i.bak 's/"resource_types:OS::Nova::Flavor.*/"resource_types:OS::Nova::Flavor": "role:admin",/' /etc/heat/policy.json

# Set up the tacker database

echo -e "\n>>> Setting up database tacker.\n"

setup_database tacker "$TACKER_DB_USER" "$TACKER_DBPASS"

echo "Sourcing the admin credentials."
source "$CONFIG_DIR/admin-openstackrc.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Verifying that mistral is available."
openstack endpoint list | grep workflowv2
mistral workbook-list
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

tacker_admin_user=tacker

echo -e "\n>>> Creating a tacker user with admin privileges.\n"

openstack user create \
    --domain Default  \
    --password "$TACKER_PASS" \
    "$tacker_admin_user"

echo -e "\n>>> Adding admin role to service project for tacker user.\n"

openstack role add \
    --project service \
    --user "$tacker_admin_user" \
    admin

echo "Creating the advsvc role."
openstack role create "advsvc"

echo -e "\n>>> Adding advsvc role to service project for tacker user.\n"
# The advanced services (advsvc) role was introduced in neutron by
# Change-Id: I94cb3383eb1fed793934719603f888dbbdbbd85a. It allows viewing
# networks of other projects and creating/updating/deleting ports there.

openstack role add \
    --project service \
    --user "$tacker_admin_user" \
    "advsvc"

echo -e "\n>>> Creating the tacker service.\n"

openstack service create \
    --name tacker \
    --description "Tacker Service" \
    "nfv-orchestration"

echo -e "\n>>> Add endpoints for tacker.\n"

openstack endpoint create \
    --region RegionOne "nfv-orchestration" \
    public http://controller:9890/

openstack endpoint create \
    --region RegionOne "nfv-orchestration" \
    internal http://controller:9890/

openstack endpoint create \
    --region RegionOne "nfv-orchestration" \
    admin http://controller:9890/

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install the tacker server
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# tosca-parser has been removed from upstream instructions
#echo -e "\n>>> Installing tosca-parser.\n"
#sudo pip install tosca-parser

mkdir ~/tacker

VENV_PATH=~/tacker/venv

# heat-translator pulls in a novaclient which breaks horizon; therefore,
# keep tacker and its dependencies in a virtualenv
virtualenv $VENV_PATH

# virtualenv activate breaks with nounset
set +o nounset
source $VENV_PATH/bin/activate
set -o nounset

# translator.hot needed by openstack infra_driver
echo -e "\n>>> Installing heat-translator.\n"
pip install heat-translator

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install the tacker server
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo -e "\n>>> Downloading tacker from git repository.\n"

cd ~/tacker
git clone https://github.com/openstack/tacker -b "stable/$OPENSTACK_RELEASE"

cd tacker
echo -e "\n>>> Changed to $(pwd) directory.\n"

echo -e "\n>>> Installing tacker.\n"
# Don't call sudo or virtualenv will be ignored
python setup.py install

# Create a log directory

echo -e "\n>>> Creating log directory.\n"

sudo mkdir /var/log/tacker

#tacker_conf=/usr/local/etc/tacker/tacker.conf
tacker_conf=$VENV_PATH/etc/tacker/tacker.conf
echo -e "\n>>> Copy the tacker.conf file to $tacker_conf.\n"

sudo cp -vf "$TACKER_DIR/tacker.conf" \
    "$tacker_conf"

echo -e "\n>>> Populating the tacker database\n"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "Installing packages needed by tacker."
# Needed by tacker-db-manage
pip install -r ~/tacker/tacker/requirements.txt
# needed by mysqldb
sudo apt install -y libmysqlclient-dev
# module mysqldb, needed by tacker-db-manage
pip install mysql-python
# module memcache needed by tacker
pip install python-memcached
# networking-sfc (OpenStack Service Function Chaining) needed for
# tacker's VNF Forwarding Graph (VNFFG)
echo "Installing python-networking-sfc."
sudo apt install -y python-networking-sfc
# The first neutron in PATH is $VENV_PATH/bin/neutron which cannot find
# the networking-sfc extensions. Call /usr/bin/neutron instead.
echo "New commands added by python-networking-sfc:"
echo "Checking neutron client."
/usr/bin/neutron --help | grep flow-classifier-
echo "Checking openstack client."
openstack help sfc
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#/usr/local/bin/tacker-db-manage \
/home/osbash/tacker/venv/bin/tacker-db-manage \
    --config-file $tacker_conf \
    upgrade head

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install the tacker client
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Alternative: sudo apt install python-tackerclient

echo -e "\n>>> Cloning tacker-client repository.\n"

cd ~/tacker
git clone https://github.com/openstack/python-tackerclient \
    -b "stable/$OPENSTACK_RELEASE"

echo -e "\n>>> Installing tacker-client.\n"

cd python-tackerclient

python setup.py install

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Install tacker horizon
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo -e "\n>>> Cloning tacker-horizon repository.\n"

cd ~/tacker
git clone https://github.com/openstack/tacker-horizon \
    -b "stable/$OPENSTACK_RELEASE"

echo -e "\n>>> Install horizon module.\n"

cd tacker-horizon

python setup.py install

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo -e "\n>>> Creating symlinks to virtual env for apache (tacker_horizon).\n"

sudo ln -sv $VENV_PATH/lib/python2.7/site-packages/tacker_horizon \
    /usr/local/lib/python2.7/dist-packages/

sudo ln -sv $VENV_PATH/lib/python2.7/site-packages/tacker_horizon-*.egg-info \
    /usr/local/lib/python2.7/dist-packages/
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo -e "\n>>> Enabling tacker horizon in dashboard.\n"

sudo cp -v tacker_horizon/enabled/* \
    /usr/share/openstack-dashboard/openstack_dashboard/enabled/

echo -e "\n>>> Restarting Apache server.\n"

sudo systemctl restart apache2

echo -e "\n>>> Verifying that horizon is still working."
if ! wget -O - localhost/horizon | grep "Login - OpenStack Dashboard"; then
    echo "ERROR We seem to have broken horizon. Aborting."
    exit 1
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Start Tacker server
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo -e "\n>>> Creating tacker user.\n"

sudo useradd --system --user-group --shell /bin/false \
    --home-dir /var/lib/tacker tacker

echo -e "\n>>> Creating /etc/tacker.\n"

sudo mkdir -p /etc/tacker
sudo chown tacker:tacker /etc/tacker

echo -e "\n>>> Copying systemd unit file into place.\n"

sudo cp -vf "$TACKER_DIR/systemd-tacker.service" \
    /etc/systemd/system/tacker-server.service

sudo sed -i -e "
    s,%VENV_PATH%,$VENV_PATH,g;
" /etc/systemd/system/tacker-server.service

sudo cp -vf "$TACKER_DIR/systemd-tacker.service" \
    /etc/systemd/system/tacker-conductor.service

sudo sed -i -e "
    s,%VENV_PATH%,$VENV_PATH,g;
    s/tacker-server/tacker-conductor/g;
" /etc/systemd/system/tacker-conductor.service

#------------------------------------------------------------------------------
# Add vim_ping_action to mistral
#------------------------------------------------------------------------------

echo -e "\n>>> Creating symlinks to virtual env for mistral.\n"

sudo ln -sv $VENV_PATH/lib/python2.7/site-packages/tacker \
    /usr/local/lib/python2.7/dist-packages/

# Help mistral find the entry point for vim_ping_action
sudo ln -sv $VENV_PATH/lib/python2.7/site-packages/tacker-*.egg-info \
    /usr/local/lib/python2.7/dist-packages/

echo -e "\n>>> Populating mistral DB.\n"
# Taken from commit message "vim monitor using rpc"
# tacker repo, commit it 60187643b586568e9c6f51c45d8b91ab697ed3fc
sudo /usr/bin/mistral-db-manage \
    --config-file /etc/mistral/mistral.conf \
    populate

echo -e "\n>>> Restarting mistral.\n"
sudo systemctl restart mistral-api
sudo systemctl restart mistral-engine
sudo systemctl restart mistral-executor
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo -e "\n>>> Starting tacker server.\n"
sudo systemctl enable tacker-server
sudo systemctl start tacker-server

echo -e "\n>>> Starting tacker conductor.\n"
sudo systemctl enable tacker-conductor
sudo systemctl start tacker-conductor

echo -e "\n>>> Waiting for tacker to come up.\n"

until tacker ext-list; do
    sleep 1
done

echo -e "\n>>> Connection established, tacker is up.\n"
