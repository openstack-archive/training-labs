#!/usr/bin/env bash

set -o errexit -o nounset

TOP_DIR=$(cd $(cat "../TOP_DIR" 2>/dev/null||echo $(dirname "$0"))/.. && pwd)

source "$TOP_DIR/config/paths"
source "$CONFIG_DIR/credentials"
source "$LIB_DIR/functions.guest.sh"

exec_logfile

indicate_current_auto

#-------------------------------------------------------------------------------
# Controller setup
#-------------------------------------------------------------------------------


DB_IP=$(get_node_ip_in_network "$(hostname)" "mgmt")
echo "Will bind MySQL server to $DB_IP."

#------------------------------------------------------------------------------
# Install and configure the database server
# https://docs.openstack.org/install-guide/environment-sql-database-ubuntu.html
#------------------------------------------------------------------------------

echo "Sourced MySQL password from credentials: $DATABASE_PASSWORD"

#sudo debconf-set-selections  <<< 'mysql-server mysql-server/root_password password '$DATABASE_PASSWORD''
#sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password '$DATABASE_PASSWORD''

echo "Installing MySQL (MariaDB)."
sudo apt install -y mariadb-server python-mysqldb

# Not in the install-guide
echo "Sanity check: check if password login works for root."
sudo mysql -u root -p"$DATABASE_PASSWORD" -e quit

# Not in install-guide
# To drop socket auth for root user and use root password:
# sudo mysql -u "root" -e "use mysql; update user set plugin='' where user='root'; update user set password=PASSWORD('$DATABASE_PASSWORD') where user='root'; flush privileges;"

conf=/etc/mysql/mariadb.conf.d/99-openstack.cnf

echo "Creating $conf."
echo '[mysqld]' | sudo tee $conf

echo "Configuring MySQL to accept requests from management network ($DB_IP)."
iniset_sudo $conf mysqld bind-address "$DB_IP"

iniset_sudo $conf mysqld default-storage-engine innodb
iniset_sudo $conf mysqld innodb_file_per_table on
iniset_sudo $conf mysqld max_connections 4096
iniset_sudo $conf mysqld collation-server utf8_general_ci
iniset_sudo $conf mysqld character-set-server utf8

echo "Restarting MySQL service."
# Close the file descriptor or the script will hang due to open ssh connection
sudo service mysql restart 2>/dev/null

# Difference to install-guide: not running mysql_secure_installation
