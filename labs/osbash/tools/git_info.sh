#!/usr/bin/env bash

# Purpose: print current state of git tree (for logging purposes)
# Usage: git_info.sh

set -o errexit -o nounset

if ! GITEXE=$(which git); then
    echo "No git executable in path. Exiting."
    exit 1
fi

echo " $(git describe --all --long --dirty)"

# All active changes (un-/staged) to tracked files
git --no-pager diff HEAD -p --stat
