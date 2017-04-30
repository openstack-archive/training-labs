#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import importlib
import logging
import re
import os
import os.path
import subprocess
import time

import stacktrain.config.general as conf
import stacktrain.core.helpers as hf
import stacktrain.batch_for_windows as wbatch

logger = logging.getLogger(__name__)

vm = importlib.import_module("stacktrain.%s.vm_create" % conf.provider)


# Wrapper around vm_snapshot to deal with collisions with cluster rebuilds
# starting from snapshot. We could delete the existing snapshot first,
# rename the new one, or just skip the snapshot.


def vm_conditional_snapshot(vm_name, shot_name):
    if conf.wbatch:
        # We need to record the proper command for wbatch; if a snapshot
        # exists, something is wrong and the program will abort
        vm.vm_snapshot(vm_name, shot_name)
    # It is not wbatch, so it must be do_build
    elif not vm.vm_snapshot_exists(vm_name, shot_name):
        vm.vm_snapshot(vm_name, shot_name)

# -----------------------------------------------------------------------------
# Files
# -----------------------------------------------------------------------------


def get_next_file_number(dir_path, suffix=None):

    # Get number of files in directory
    entries = os.listdir(dir_path)
    cnt = 0
    for entry in entries:
        if not os.path.isfile(os.path.join(dir_path, entry)):
            continue
        if suffix and not re.match(r'.*\.' + suffix, entry):
            continue
        cnt += 1
    return cnt


def get_next_prefix(dir_path, suffix, digits=3):
    cnt = get_next_file_number(dir_path, suffix)

    return ('{:0' + str(digits) + 'd}').format(cnt)

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------


def create_host_networks():
    if conf.wbatch:
        wbatch.wbatch_begin_hostnet()
    cnt = 0

    # Iterate over values (IP addresses)
    for net_name, net_address in conf.networks.items():
        logger.info("Creating %s network: %s.", net_name, net_address)
        gw_address = hf.ip_to_gateway(net_address)
        if conf.do_build:
            iface = vm.create_network(net_name, gw_address)
        else:
            # TODO use a generator (yield) here
            # If we are here only for wbatch, ignore actual network interfaces;
            # just return a vboxnetX identifier (so it can be replaced with the
            # interface name used by Windows).
            iface = "vboxnet{}".format(cnt)
        cnt += 1
        if conf.wbatch:
            wbatch.wbatch_create_hostnet(gw_address, iface)

    if conf.wbatch:
        wbatch.wbatch_end_file()
