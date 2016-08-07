#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import logging
import os

import stacktrain.config.general as conf
import stacktrain.config.virtualbox as cvb

import stacktrain.virtualbox.vm_create as vm
import stacktrain.core.functions_host as host

logger = logging.getLogger(__name__)

# TODO could vm_create_code become generic enough for base_disk install?


def configure_node_netifs(vm_name):

    for index, iface in enumerate(conf.vm[vm_name].net_ifs):
        if iface["typ"] == "dhcp":
            vm.vm_nic_base(vm_name, index)
        elif iface["typ"] == "manual":
            vm.vm_nic_std(vm_name, iface, index)
        elif iface["typ"] == "static":
            vm.vm_nic_std(vm_name, iface, index)
        else:
            logger.error("Unknown interface type: %s", iface.typ)
            raise ValueError
        if iface["prio"]:
            # Elevate boot prio so this particular NIC is used for PXE booting
            # Set whether or not we use PXE booting (disk has always priority
            # if it contains a bootable image)
            vm.vm_nic_set_boot_prio(vm_name, iface, index)


def vm_create_node(vm_name):

    try:
        vm_config = conf.vm[vm_name]
    except Exception:
        logger.error("Failed to import VM configuration config.vm_%s.",
                     vm_name)
        raise

    vm.vm_create(vm_config)

    vm.vm_mem(vm_config)

    vm.vm_cpus(vm_config)

    configure_node_netifs(vm_name)

    if conf.vm[vm_name].ssh_port:
        vm.vm_port(vm_name, "ssh", conf.vm[vm_name].ssh_port, 22)

    if conf.vm[vm_name].http_port:
        vm.vm_port(vm_name, "http", conf.vm[vm_name].http_port, 80)

    if conf.wbatch:
        vm.vm_add_share(vm_name, conf.share_dir, conf.share_name)

    for index, disk in enumerate(conf.vm[vm_name].disks):
        # Turn number into letter (0->a, 1->b, etc.)
        disk_letter = chr(index + ord('a'))
        port = index
        if disk is None:
            continue
        elif disk == "base":
            vm.vm_attach_disk_multi(vm_name, cvb.get_base_disk_path())
        else:
            size = disk
            disk_name = "{}-sd{}.vdi".format(vm_name, disk_letter)
            disk_path = os.path.join(conf.img_dir, disk_name)
#            print("Adding additional disk to {}:\n\t{}".format(vm_name,
#                                                               disk_path))
            vm.create_vdi(disk_path, size)
            vm.vm_attach_disk(vm_name, disk_path, port)
