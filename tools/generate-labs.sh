#!/bin/bash -
#
#   DESCRIPTION
#
#       User by tox.ini to create required scripts and tar balls for
#       hosting the contents of this project.
#
# Note: Execute this script from the root of the repository for expected
#       results.

set -o nounset  # Treat unset variables as an error

# This variable is fed by openstack-ci post job as a trigger.
# The value here will be stable/<release-name>
release=$1
# Replace '/' with '-' for renaming stable/<release-name> to
# stalbe-<release-name>
release=${release////-}

# Create required folders
mkdir -p ./build/dist/

# Create tarball of labs scripts for Linux/OS X users
tar --exclude=*.iso \
    --exclude=*.vdi \
    --exclude=*.log \
    --exclude=*.auto \
    -czf build/dist/labs-${release}.tgz labs/osbash


# Generate Windows batch scripts
labs/osbash/osbash.sh -w cluster
# Create zip file of labs scripts for Windows users
zip -r build/dist/labs-${release}.zip labs/osbash \
    -x *.iso \*.vdi \*.log \*.auto
