#!/bin/bash -
#
#   DESCRIPTION
#
#       User by tox.ini to create required scripts and tar balls for
#       hosting the contents of this project.
#

set -o nounset  # Treat unset variables as an error

# Create tarball of labs scripts for Linux/OS X users
tar --exclude=*.iso \
    --exclude=*.vdi \
    --exclude=*.log \
    --exclude=*.auto \
    -czf build/labs.tgz labs/osbash


# Generate Windows batch scripts
labs/osbash/osbash.sh -w cluster
# Create zip file of labs scripts for Windows users
zip -r build/labs.zip labs/osbash \
    -x *.iso *.vdi *.log *.auto

