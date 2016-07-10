#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd "$(dirname "$0")/.." && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$CONFIG_DIR/openstack"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#------------------------------------------------------------------------------
# Set up keystone for controller node
# http://docs.openstack.org/mitaka/install-guide-ubuntu/keystone-install.html
#------------------------------------------------------------------------------

echo "Setting up database for keystone."
setup_database keystone "$KEYSTONE_DB_USER" "$KEYSTONE_DBPASS"

# Create a "shared secret" used as OS_TOKEN, together with OS_URL, before
# keystone can be used for authentication
echo -n "Using openssl to generate a random admin token: "
ADMIN_TOKEN=$(openssl rand -hex 10)
echo "$ADMIN_TOKEN"


echo "Disabling the keystone service from starting automatically after installation."
# Will not be re-enabled because apache2 wsgi serves these ports now
echo "manual" | sudo tee /etc/init/keystone.override

echo "Installing keystone packages."
sudo apt-get install -y keystone apache2 libapache2-mod-wsgi

conf=/etc/keystone/keystone.conf
echo "Configuring [DEFAULT] section in $conf."

echo "Setting admin_token to bootstrap authentication."
iniset_sudo $conf DEFAULT admin_token "$ADMIN_TOKEN"

function get_database_url {
    local db_user=$KEYSTONE_DB_USER
    local database_host=controller

    echo "mysql+pymysql://$db_user:$KEYSTONE_DBPASS@$database_host/keystone"
}

database_url=$(get_database_url)

echo "Configuring [database] section in /etc/keystone/keystone.conf."

echo "Setting database connection: $database_url."
iniset_sudo $conf database connection "$database_url"

echo "Configuring the Fernet token provider."
iniset_sudo $conf token provider fernet

echo "Creating the database tables for keystone."
sudo keystone-manage db_sync

echo "Initializing Fernet keys."
sudo keystone-manage fernet_setup \
    --keystone-user keystone \
    --keystone-group keystone

# Configure Apache HTTP server.

conf=/etc/apache2/apache2.conf
echo "Configuring ServerName option in $conf to reference controller node."
echo "ServerName controller" | sudo tee -a $conf

echo "Creating /etc/apache2/sites-available/wsgi-keystone.conf."
cat << WSGI | sudo tee -a /etc/apache2/sites-available/wsgi-keystone.conf
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

WSGI

echo "Enabling the identity service virtual hosts."
sudo ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled

echo "Restarting apache."
sudo service apache2 restart

echo "Removing default SQLite database."
sudo rm -f /var/lib/keystone/keystone.db

#------------------------------------------------------------------------------
# Create the service entity and API endpoints
# http://docs.openstack.org/mitaka/install-guide-ubuntu/keystone-services.html
#------------------------------------------------------------------------------

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Using OS_TOKEN, OS_URL for authentication."
export OS_TOKEN=$ADMIN_TOKEN
export OS_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create the service entity and API endpoints
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo "Creating keystone service."
openstack service create \
    --name keystone \
    --description "OpenStack Identity" \
    identity

echo "Creating endpoints for keystone."
openstack endpoint create --region "$REGION" \
    identity public http://controller:5000/v3

openstack endpoint create --region "$REGION" \
    identity internal http://controller:5000/v3

openstack endpoint create --region "$REGION" \
    identity admin http://controller:35357/v3

#------------------------------------------------------------------------------
# Create projects, users, and roles
# http://docs.openstack.org/mitaka/install-guide-ubuntu/keystone-users.html
#------------------------------------------------------------------------------

# Wait for keystone to come up
wait_for_keystone

echo "Creating default domain."
openstack domain create \
    --description "Default Domain" \
    default

echo "Creating admin project."
openstack project create --domain default \
    --description "Admin Project" \
    "$ADMIN_PROJECT_NAME"

echo "Creating admin user."
openstack user create --domain default \
    --password "$ADMIN_PASS" \
    "$ADMIN_USER_NAME"

echo "Creating admin role."
openstack role create "$ADMIN_ROLE_NAME"

echo "Adding admin role to admin project."
openstack role add \
    --project "$ADMIN_PROJECT_NAME" \
    --user "$ADMIN_USER_NAME" \
    "$ADMIN_ROLE_NAME"

echo "Creating service project."
openstack project create --domain default \
    --description "Service Project" \
    "$SERVICE_PROJECT_NAME"

echo "Creating demo project."
openstack project create --domain default \
    --description "Demo Project" \
    "$DEMO_PROJECT_NAME"

echo "Creating demo user."
openstack user create --domain default \
    --password "$DEMO_PASS" \
    "$DEMO_USER_NAME"

echo "Creating the user role."
openstack role create \
    "$USER_ROLE_NAME"

echo "Linking user role to demo project and user."
openstack role add \
    --project "$DEMO_PROJECT_NAME" \
    --user "$DEMO_USER_NAME" \
    "$USER_ROLE_NAME"

#------------------------------------------------------------------------------
# Verify operation
# http://docs.openstack.org/mitaka/install-guide-ubuntu/keystone-verify.html
#------------------------------------------------------------------------------

echo "Verifying keystone installation."

# Disable temporary authentication token mechanism
conf=/etc/keystone/keystone-paste.ini

for section in pipeline:public_api pipeline:admin_api pipeline:api_v3; do
    if ini_has_option_sudo $conf $section admin_token_auth; then
        echo "Disabling admin_token_auth in section $section."
        inicomment_sudo $conf $section admin_token_auth
    fi
done

# From this point on, we are going to use keystone for authentication
unset OS_TOKEN OS_URL

echo "Requesting an authentication token as an admin user."
openstack \
    --os-auth-url http://controller:35357/v3 \
    --os-project-domain-name default \
    --os-user-domain-name default \
    --os-project-name "$ADMIN_PROJECT_NAME" \
    --os-username "$ADMIN_USER_NAME" \
    --os-auth-type password \
    --os-password "$ADMIN_PASS" \
    token issue

#echo "Requesting project list."
#openstack \
#    --os-auth-url http://controller:35357 \
#    --os-project-domain-name default \
#    --os-user-domain-name default \
#    --os-project-name "$ADMIN_PROJECT_NAME" \
#    --os-username "$ADMIN_USER_NAME" \
#    --os-auth-type password \
#    --os-password "$ADMIN_PASS" \
#    project list
#
#echo "Requesting user list."
#openstack \
#    --os-auth-url http://controller:35357/v3 \
#    --os-project-domain-name default \
#    --os-user-domain-name default \
#    --os-project-name "$ADMIN_PROJECT_NAME" \
#    --os-username "$ADMIN_USER_NAME" \
#    --os-auth-type password \
#    --os-password "$ADMIN_PASS" \
#    user list
#
#echo "Requesting role list."
#openstack \
#    --os-auth-url http://controller:35357/v3 \
#    --os-project-domain-name default \
#    --os-user-domain-name default \
#    --os-project-name "$ADMIN_PROJECT_NAME" \
#    --os-username "$ADMIN_USER_NAME" \
#    --os-auth-type password \
#    --os-password "$ADMIN_PASS" \
#    role list

echo "Requesting an authentication token for the demo user."
openstack \
    --os-auth-url http://controller:5000/v3 \
    --os-project-domain-name default \
    --os-user-domain-name default \
    --os-project-name "$DEMO_PROJECT_NAME" \
    --os-username "$DEMO_USER_NAME" \
    --os-auth-type password \
    --os-password "$DEMO_PASS" \
    token issue

#echo "Verifying that an admin-only request by the demo user is denied."
#openstack \
#    --os-auth-url http://controller:5000/v3 \
#    --os-project-domain-name default \
#    --os-user-domain-name default \
#    --os-project-name "$DEMO_PROJECT_NAME" \
#    --os-username "$DEMO_USER_NAME" \
#    --os-auth-type password \
#    --os-password "$DEMO_PASS" \
#    user list || rc=$?
#
#echo rc=$rc
#if [ $rc -eq 0 ]; then
#    echo "The request was not denied. This is an error. Exiting."
#    exit 1
#else
#    echo "The request was correctly denied."
#fi
