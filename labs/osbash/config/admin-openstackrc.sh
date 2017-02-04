# The variables in this file are exported for use by OpenStack client
# applications.

# Use BASH_SOURCE so the file works when sourced from a shell, too; use
# $0 to make it work on zsh
CONFIG_DIR=$(dirname "${BASH_SOURCE[0]:-$0}")
source "$CONFIG_DIR/openstack"
source "$CONFIG_DIR/credentials"

#------------------------------------------------------------------------------
# OpenStack client environment scripts
# http://docs.openstack.org/newton/install-guide-ubuntu/keystone-openrc.html
#------------------------------------------------------------------------------
export OS_USERNAME=$ADMIN_USER_NAME
export OS_PASSWORD=$ADMIN_PASS
export OS_PROJECT_NAME=$ADMIN_PROJECT_NAME
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
