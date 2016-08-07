#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import importlib
import os
import errno
import logging

import stacktrain.config.general as conf
import stacktrain.config.virtualbox as cvb

import stacktrain.virtualbox.vm_create as vm
import stacktrain.core.iso_image as iso_image
import stacktrain.batch_for_windows as wbatch
import stacktrain.core.autostart as autostart
import stacktrain.core.cond_sleep as cs

distro_boot = importlib.import_module("stacktrain.distros.%s" %
                                      conf.distro_full)

logger = logging.getLogger(__name__)


def base_disk_exists():
    return os.path.isfile(cvb.get_base_disk_path())


def disk_delete_child_vms(disk):
    if not vm.disk_registered(disk):
        logger.warn("Disk not registered with VirtualBox:\n\t%s", disk)
        return 0

    while True:
        child_disk_uuid = vm.get_next_child_disk_uuid(disk)
        if not child_disk_uuid:
            break
        child_disk_path = vm.disk_to_path(child_disk_uuid)
        vm_name = vm.disk_to_vm(child_disk_uuid)
        if vm_name:
            logger.info("Deleting VM %s.", vm_name)
            vm.vm_delete(vm_name)
        else:
            logger.info("Unregistering and deleting:\n\t%s", child_disk_path)
            vm.disk_unregister(child_disk_uuid)
            os.remove(child_disk_path)


def base_disk_delete():
    base_disk_path = cvb.get_base_disk_path()

    if vm.disk_registered(base_disk_path):
        # Remove users of base disk
        logger.info("Unregistering and removing all disks attached to"
                    " base disk path.")
        disk_delete_child_vms(base_disk_path)
        logger.info("Unregistering old base disk.")
        vm.disk_unregister(base_disk_path)

    logger.info("Removing old base disk.")
    try:
        os.remove(base_disk_path)
    except OSError as err:
        if err.errno != errno.ENOENT:
            raise
        # File doesn't exist, that's fine.


def vm_install_base():
    vm_name = "base"
    conf.vm[vm_name] = conf.VMconfig(vm_name)

    base_disk_path = cvb.get_base_disk_path()
    base_build_disk = os.path.join(conf.img_dir, "tmp-disk.vdi")

    logger.info("Creating\n\t%s.", base_disk_path)

    if conf.wbatch:
        wbatch.wbatch_begin_base()
        wbatch.wbatch_delete_disk(base_build_disk)

    if conf.do_build:
        if base_disk_exists():
            logger.info("Deleting existing basedisk.")
            base_disk_delete()
        try:
            os.remove(base_build_disk)
        except OSError as err:
            if err.errno != errno.ENOENT:
                raise
            # File doesn't exist, that's fine.

    vm_config = conf.vm[vm_name]

    if conf.do_build:
        install_iso = iso_image.find_install_iso()
    else:
        install_iso = os.path.join(conf.img_dir, conf.iso_image.name)

    logger.info("Install ISO:\n\t%s", install_iso)

    vm.vm_create(vm_config)
    vm.vm_mem(vm_config)

    vm.vm_attach_dvd(vm_name, install_iso)

    if conf.wbatch:
        vm.vm_attach_guestadd_iso(vm_name)

    vm.create_vdi(base_build_disk, conf.base_disk_size)
    vm.vm_attach_disk(vm_name, base_build_disk)

    if conf.wbatch:
        # Automounted on /media/sf_bootstrap for first boot
        vm.vm_add_share_automount(vm_name, conf.share_dir, "bootstrap")
        # Mounted on /conf.share_name after first boot
        vm.vm_add_share(vm_name, conf.share_dir, conf.share_name)
    else:
        vm.vm_port(vm_name, "ssh", conf.vm[vm_name].ssh_port, 22)

    vm.vbm("modifyvm", vm_name, "--boot1", "dvd")
    vm.vbm("modifyvm", vm_name, "--boot2", "disk")

    autostart.autostart_reset()

    if conf.wbatch:
        autostart.autostart_queue("osbash/activate_autostart.sh")

    autostart.autostart_queue("osbash/base_fixups.sh")

    autostart.autostart_from_config(conf.base_install_scripts)

    autostart.autostart_queue("zero_empty.sh", "shutdown.sh")

    logger.info("Booting VM %s.", vm_name)
    vm.vm_boot(vm_name)

    # Note: It takes about 5 seconds for the installer in the VM to be ready
    #       on a fairly typical laptop. If we don't wait long enough, the
    #       installation will fail. Ideally, we would have a different method
    #       of making sure the installer is ready. For now, we just have to
    #       try and err on the side of caution.
    delay = 10
    logger.info("Waiting %d seconds for VM %s to come up.", delay, vm_name)
    cs.conditional_sleep(delay)

    logger.info("Booting into distribution installer.")
    distro_boot.distro_start_installer(vm_config)

    autostart.autostart_and_wait(vm_name)

    vm.vm_wait_for_shutdown(vm_name)

    # Detach disk from VM now or it will be deleted by vm_unregister_del
    vm.vm_detach_disk(vm_name)

    vm.vm_unregister_del(vm_name)
    del conf.vm[vm_name]

    logger.info("Compacting %s.", base_build_disk)
    vm.vbm("modifyhd", base_build_disk, "--compact")

    # This disk will be moved to a new name, and this name will be used for
    # a new disk next time the script runs.
    vm.disk_unregister(base_build_disk)

    logger.info("Base disk created.")

    logger.info("Moving base disk to:\n\t%s", base_disk_path)
    if conf.do_build:
        import shutil
        shutil.move(base_build_disk, base_disk_path)

    if conf.wbatch:
        wbatch.wbatch_rename_disk(os.path.basename(base_build_disk),
                                  os.path.basename(base_disk_path))
        wbatch.wbatch_end_file()

    logger.info("Base disk build ends.")
