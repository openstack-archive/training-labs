#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import logging
import sys

import stacktrain.config.general as conf

import stacktrain.kvm.vm_create as vm
import stacktrain.core.functions_host as host

logger = logging.getLogger(__name__)

# TODO could vm_create_code become generic enough for base_disk install?


def vm_create_node(vm_name):

    try:
        vm_config = conf.vm[vm_name]
    except Exception:
        logger.exception("Failed to import VM configuration config.vm_%s.",
                         vm_name)
        raise

    base_disk_name = conf.get_base_disk_name()

    vm.vm_delete(vm_name)

    libvirt_connect_uri = "qemu:///system"
    virt_install_call = ["sudo", "virt-install",
                         "--connect={}".format(libvirt_connect_uri)]
    call_args = virt_install_call + ["--name", vm_name,
                                     "--ram", str(vm_config.vm_mem),
                                     "--vcpus", str(vm_config.vm_cpus),
                                     "--os-type={}".format("linux"),
                                     "--import"]

    for index, iface in enumerate(conf.vm[vm_name].net_ifs):
        if iface["typ"] == "dhcp":
            call_args.extend(["--network", "bridge=virbr0"])
        elif iface["typ"] == "manual":
            net_name = "labs-{}".format(vm.ip_to_netname(iface["ip"]))
            call_args.extend(["--network", "network={}".format(net_name)])
        elif iface["typ"] == "static":
            net_name = "labs-{}".format(vm.ip_to_netname(iface["ip"]))
            call_args.extend(["--network", "network={}".format(net_name)])
        else:
            logger.error("Unknown interface type: %s", iface.typ)
            sys.exit(1)

    for index, disk in enumerate(conf.vm[vm_name].disks):
        # Turn number into letter (0->a, 1->b, etc.)
        disk_letter = chr(index + ord('a'))
        if disk is None:
            continue
        disk_name = "{}-sd{}".format(vm_name, disk_letter)
        if disk == "base":
            logger.info("Creating copy-on-write VM disk.")
            vm.disk_create_cow(disk_name, base_disk_name)
        else:
            size = disk
            logger.info("Adding empty disk to %s: %s", vm_name, disk_name)
            vm.disk_create(disk_name, size)
        call_args.extend(["--disk",
                          "vol={}/{},cache=none".format(vm.kvm_vol_pool,
                                                        disk_name)])

    if conf.vm_ui == "headless":
        call_args.extend(("--graphics", "none", "--noautoconsole"))
        call_args.append("--noreboot")
    elif conf.vm_ui == "vnc":
        # Only local connections allowed (0.0.0.0 would allow external
        # connections as well)
        call_args.extend(("--graphics", "vnc,listen=127.0.0.1"))
        call_args.append("--noreboot")
    # Default UI uses virt-viewer which doesn't fly with --noreboot

    import subprocess
    errout = subprocess.STDOUT
    logger.debug("virt-install call: %s", call_args)
    vm.virsh_log(call_args)
    subprocess.Popen(call_args, stderr=errout)

    # Prevent "time stamp from the future" due to race between two sudos for
    # virt-install (background) above and virsh below
    import time
    time.sleep(1)

    logger.info("Waiting for VM %s to be defined.", vm_name)
    while True:
        if vm.virsh_vm_defined(vm_name):
            logger.debug("VM %s is defined now.", vm_name)
            vm.log_xml_dump(vm_name, "defined")
            break
        time.sleep(1)
        print(".", end='')
        sys.stdout.flush()

    # Set VM group in description so we know which VMs are ours
    # (not with virt-install because older versions give an error for
    # --metadata title=TITLE)
    vm.set_vm_group(vm_name)
    vm.log_xml_dump(vm_name, "in_group")
