#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import importlib
import logging
import os
import re
import time

import stacktrain.config.general as conf

import stacktrain.kvm.vm_create as vm
import stacktrain.core.iso_image as iso_image
import stacktrain.core.autostart as autostart
import stacktrain.core.cond_sleep as cs
import stacktrain.core.helpers as hf

distro_boot = importlib.import_module("stacktrain.distros.%s" %
                                      conf.distro_full)

logger = logging.getLogger(__name__)


def base_disk_exists():
    return vm.disk_exists(conf.get_base_disk_name())


def base_disk_delete():
    base_disk_name = conf.get_base_disk_name()

    base_disk_path = vm.get_disk_path(base_disk_name)
    output = vm.virsh("list", "--uuid", "--all")
    for uuid in output.splitlines():
        if uuid == "":
            continue
        logger.debug("Candidate for deletion: %s", uuid)
        domstats = vm.virsh("domstats", uuid, "--block", "--backing")
        if re.search("block.*path.*{}".format(base_disk_path), domstats):
          logger.info("Deleting VM %s", uuid)
          vm.vm_delete(uuid)
    vm.disk_delete(base_disk_name)


def vm_install_base():
    vm_name = "base"

    conf.vm[vm_name] = conf.VMconfig(vm_name)

    base_disk_name = conf.get_base_disk_name()

    vm.vm_delete(vm_name)

    if base_disk_exists():
        logger.info("Deleting existing basedisk.")
        base_disk_delete()

    vm_config = conf.vm[vm_name]

    if conf.do_build:
        install_iso = iso_image.find_install_iso()
    else:
        install_iso = os.path.join(conf.img_dir, conf.iso_image.name)

    logger.info("Install ISO:\n\t%s", install_iso)

    autostart.autostart_reset()

    autostart.autostart_queue("osbash/base_fixups.sh")

    autostart.autostart_from_config(conf.base_install_scripts)

    autostart.autostart_queue("zero_empty.sh", "shutdown.sh")

    base_disk_size = 10000
    vm.disk_create(base_disk_name, base_disk_size)

    libvirt_connect_uri = "qemu:///system"
    virt_install_call = ["sudo", "virt-install",
                         "--connect={}".format(libvirt_connect_uri)]
    call_args = virt_install_call
    call_args.extend(["--name", vm_name])
    call_args.extend(["--ram", str(vm_config.vm_mem)])
    call_args.extend(["--vcpus", str(1)])
    call_args.extend(["--os-type", "linux"])
    call_args.extend(["--cdrom", install_iso])

    call_args.extend(["--disk", "vol={}/{},cache=none".format(vm.kvm_vol_pool,
                                                              base_disk_name)])

    if conf.vm_ui == "headless":
        call_args.extend(("--graphics", "none", "--noautoconsole"))
    elif conf.vm_ui == "vnc":
        call_args.extend(("--graphics", "vnc,listen=127.0.0.1"))
    # Default (no extra argument) is gui option: should open a console viewer
    call_args.append("--wait=-1")

    import subprocess
    errout = subprocess.STDOUT
    logger.debug("virt-install call: %s", ' '.join(call_args))
    logger.debug("virt-install call: %s", call_args)
    vm.virsh_log(call_args)
    subprocess.Popen(call_args, stderr=errout)

    while True:
        if vm.vm_is_running(vm_name):
            break
        print('.', end='')
        time.sleep(1)

    delay = 5
    logger.info("\nWaiting %d seconds for VM %s to come up.", delay, vm_name)
    cs.conditional_sleep(delay)

    logger.info("Booting into distribution installer.")
    distro_boot.distro_start_installer(vm_config)

    # Prevent "time stamp from the future" due to race between two sudos for
    # virt-install (background) above and virsh below
    time.sleep(1)

    logger.info("Waiting for VM %s to be defined.", vm_name)
    while True:
        if vm.vm_is_running(vm_name):
            break
        time.sleep(1)
        print(".")

    ssh_ip = vm.node_to_ip(vm_name)
    conf.vm[vm_name].ssh_ip = ssh_ip

    logger.info("Waiting for ping returning from %s.", ssh_ip)
    hf.wait_for_ping(ssh_ip)

    autostart.autostart_and_wait(vm_name)

    vm.vm_wait_for_shutdown(vm_name)

    logger.info("Compacting %s.", base_disk_name)
    vm.disk_compress(base_disk_name)

    vm.virsh("undefine", vm_name)

    del conf.vm[vm_name]

    logger.info("Base disk created.")

    logger.info("stacktrain base disk build ends.")
