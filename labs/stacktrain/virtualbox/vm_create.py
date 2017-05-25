#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

from time import sleep

import logging

import os
import re
import subprocess
import sys

import stacktrain.config.general as conf
import stacktrain.core.helpers as hf
import stacktrain.core.cond_sleep as cs
import stacktrain.batch_for_windows as wb

logger = logging.getLogger(__name__)

vm_group = "labs"
conf.vbox_ostype = None


def init():
    output = vbm("--version")
    # We only get an output if we are actually building the cluster
    if conf.do_build:
        logger.debug("VBoxManage version: %s", output)
        if re.search("kernel module is not load", output, flags=re.MULTILINE):
            logger.error("Kernel module for VirtualBox is not loaded."
                         " Aborting.")
            sys.exit(1)


def vbm_log(call_args, err_code=None):
    log_file = os.path.join(conf.log_dir, "vboxmanage.log")
    msg = ' '.join(call_args)
    if err_code:
        msg = "FAILURE ({}): ".format(err_code) + msg
    with open(log_file, 'a') as logf:
        if conf.do_build:
            logf.write("%s\n" % msg)
        else:
            logf.write("(not executed) %s\n" % msg)


def vbm(*args, **kwargs):
    # wbatch parameter can override conf.wbatch setting
    wbatch = kwargs.pop('wbatch', conf.wbatch)
    if wbatch:
        wb.wbatch_log_vbm(args)

    # FIXME caller expectations: where should stderr go (console, logfile)
    show_err = kwargs.pop('show_err', True)
    if show_err:
        errout = subprocess.STDOUT
    else:
        errout = open(os.devnull, 'w')

    vbm_exe = "VBoxManage"

    call_args = [vbm_exe] + list(args)

    vbm_log(call_args)

    if not conf.do_build:
        return

    try:
        output = subprocess.check_output(call_args, stderr=errout)
    except subprocess.CalledProcessError as err:
        if show_err:
            vbm_log(call_args, err_code=err.returncode)
            logger.warn("%s call failed.", vbm_exe)
            logger.warn(' '.join(call_args))
            logger.warn("call_args: %s", call_args)
            logger.warn("rc: %s", err.returncode)
            logger.warn("output:\n%s", err.output)
            logger.exception("Exception")
            logger.warn("--------------------------------------------------")
            import traceback
            traceback.print_exc(file=sys.stdout)
            sys.exit(45)
        else:
            logger.debug("%s call failed.", vbm_exe)
            logger.debug(' '.join(call_args))
            logger.debug("call_args: %s", call_args)
            logger.debug("rc: %s", err.returncode)
            logger.debug("output:\n%s", err.output)
        raise EnvironmentError

    return output


# -----------------------------------------------------------------------------
# VM status
# -----------------------------------------------------------------------------


def vm_exists(vm_name):
    output = vbm("list", "vms", wbatch=False)
    return True if re.search('"' + vm_name + '"', output) else False


def get_vm_state(vm_name):
    state = None
    try:
        output = vbm("showvminfo", "--machinereadable", vm_name, wbatch=False,
                     show_err=False)
    except EnvironmentError:
        # VBoxManage returns error status while the machine is changing
        # state (e.g., shutting down)
        logger.debug("Ignoring exceptions when checking for VM state.")
    else:
        ma = re.search(r'VMState="(.*)"', output)
        if ma:
            state = ma.group(1)

    logger.debug("get_vm_vmstate: %s", state)
    return state


def vm_is_running(vm_name):
    vm_state = get_vm_state(vm_name)
    if vm_state in ("running", "stopping"):
        logger.debug("vm_is_running: ;%s;", vm_state)
        return True
    else:
        return False


def vm_is_shut_down(vm_name):
    vm_state = get_vm_state(vm_name)
    if vm_state == "poweroff":
        logger.debug("vm_is_shut_down: ;%s;", vm_state)
        return True
    else:
        return False


# TODO move vm_wait_for_shutdown to functions_host
def vm_wait_for_shutdown(vm_name, timeout=None):
    if conf.wbatch:
        wb.wbatch_wait_poweroff(vm_name)
        cs.conditional_sleep(1)

    if not conf.do_build:
        return

    logger.info("Waiting for shutdown of VM %s.", vm_name)

    sec = 0
    while True:
        if vm_is_shut_down(vm_name):
            logger.info("Machine powered off.")
            break
        if timeout and sec > timeout:
            logger.info("Timeout reached, giving up.")
            break
        print('.', end='')
        sys.stdout.flush()
        delay = 1
        sleep(delay)
        sec += delay


def vm_power_off(vm_name):
    if vm_is_running(vm_name):
        logger.info("Powering off VM %s", vm_name)
        try:
            vbm("controlvm", vm_name, "poweroff")
        except EnvironmentError:
            logger.debug("vm_power_off got an error, hoping for the best.")
            # Give VirtualBox time to sort out whatever happened
            sleep(5)
    vm_wait_for_shutdown(vm_name, timeout=10)
    if vm_is_running(vm_name):
        logger.error("VM %s does not power off. Aborting.", vm_name)
        sys.exit(1)
    # VirtualBox VM needs a break before taking new commands
    cs.conditional_sleep(1)


def vm_acpi_shutdown(vm_name):
    logger.info("Shutting down VM  %s.", vm_name)
    vbm("controlvm", vm_name, "acpipowerbutton")
    # VirtualBox VM needs a break before taking new commands
    cs.conditional_sleep(1)


# Shut down all VMs in group VM_GROUP
# Note: This function must be called when no Windows batch file is open for
#       writing (wbatch_write will ignore all these calls).
def stop_running_cluster_vms():
    # Get VM ID from a line looking like this:
    # "My VM" {0a13e26d-9543-460d-82d6-625fa657b7c4}
    output = vbm("list", "runningvms")
    if not output:
        return
    for runvm in output.splitlines():
        mat = re.match(r'".*" {(\S+)}', runvm)
        if mat:
            vm_id = mat.group(1)
            output = vbm("showvminfo", "--machinereadable", vm_id)
            for line in output.splitlines():
                if re.match('groups="/{}'.format(vm_group), line):
                    # We may have waited quite some time for other VMs
                    # to shut down
                    if vm_is_running(vm_id):
                        logger.info("Shutting down VM %s.", vm_id)
                        vm_acpi_shutdown(vm_id)
                        vm_wait_for_shutdown(vm_id, timeout=5)
                        if vm_is_running(vm_id):
                            logger.info("VM will not shut down, powering it"
                                        " off.")
                            vm_power_off(vm_id)

# -----------------------------------------------------------------------------
# Host-only network functions
# -----------------------------------------------------------------------------


def hostonlyif_in_use(if_name):
    output = vbm("list", "-l", "runningvms", wbatch=False)
    return re.search("NIC.*Host-only Interface '{}'".format(if_name),
                     output, flags=re.MULTILINE)


def ip_to_hostonlyif(ip):
    ip_net_address = hf.ip_to_net_address(ip)

    if not conf.do_build:
        # Add placeholders for wbatch code
        for index, (net_name, net_address) in enumerate(
                conf.networks.iteritems()):
            if net_address == ip_net_address:
                if_name = "vboxnet{}".format(index)
                logger.debug("%s %s %s", net_address, net_name, if_name)
                return if_name

    output = vbm("list", "hostonlyifs", wbatch=False)
    host_net_address = None

    for line in output.splitlines():

        ma = re.match(r"Name:\s+(\S+)", line)
        if ma:
            if_name = ma.group(1)
            continue

        ma = re.match(r"IPAddress:\s+(\S+)", line)
        if ma:
            host_ip = ma.group(1)
            host_net_address = hf.ip_to_net_address(host_ip)

        if host_net_address == ip_net_address:
            return if_name


def create_hostonlyif():
    output = vbm("hostonlyif", "create", wbatch=False)
    # output is something like "Interface 'vboxnet3' was successfully created"
    ma = re.search(r"^Interface '(\S+)' was successfully created",
                   output, flags=re.MULTILINE)
    if ma:
        if_name = ma.group(1)
    else:
        logger.error("Host-only interface creation failed.")
        raise EnvironmentError
    return if_name


def create_network(net_name, ip_address):
    # The host-side interface is the default gateway of the network

    if_name = ip_to_hostonlyif(ip_address)

    if if_name:
        if hostonlyif_in_use(if_name):
            logger.info("Host-only interface %s (%s) in use. Using it, too.",
                        if_name, ip_address)
        # else: TODO destroy network if not in use?
    else:
        logger.info("Creating host-only interface.")
        if_name = create_hostonlyif()

    logger.info("Configuring host-only network %s with gw address %s (%s).",
                net_name, ip_address, if_name)
    vbm("hostonlyif", "ipconfig", if_name,
        "--ip", ip_address,
        "--netmask", "255.255.255.0",
        wbatch=False)
    return if_name

# -----------------------------------------------------------------------------
# VM create and configure
# -----------------------------------------------------------------------------


def vm_mem(vm_config):
    # Default RAM allocation is 512 MB per VM
    mem = vm_config.vm_mem or 512

    vbm("modifyvm", vm_config.vm_name, "--memory", str(mem))


def vm_cpus(vm_config):
    # Default RAM allocation is 512 MB per VM
    cpus = vm_config.vm_cpus or 1

    vbm("modifyvm", vm_config.vm_name, "--cpus", str(cpus))


def vm_port(vm_name, desc, hostport, guestport):
    natpf1_arg = "{},tcp,127.0.0.1,{},,{}".format(desc, hostport, guestport)
    vbm("modifyvm", vm_name, "--natpf1", natpf1_arg)


def vm_nic_base(vm_name, index):
    # We start counting interfaces at 0, but VirtualBox starts NICs at 1
    nic = index + 1
    vbm("modifyvm", vm_name,
        "--nictype{}".format(nic), "virtio",
        "--nic{}".format(nic), "nat")


def vm_nic_std(vm_name, iface, index):
    # We start counting interfaces at 0, but VirtualBox starts NICs at 1
    nic = index + 1
    hostif = ip_to_hostonlyif(iface["ip"])
    vbm("modifyvm", vm_name,
        "--nictype{}".format(nic), "virtio",
        "--nic{}".format(nic), "hostonly",
        "--hostonlyadapter{}".format(nic), hostif,
        "--nicpromisc{}".format(nic), "allow-all")


def vm_nic_set_boot_prio(vm_name, iface, index):
    # We start counting interfaces at 0, but VirtualBox starts NICs at 1
    nic = index + 1

    vbm("modifyvm", vm_name,
        "--nicbootprio{}".format(nic), str(iface["prio"]))


def vm_create(vm_config):
    vm_name = vm_config.vm_name

    if conf.wbatch:
        wb.wbatch_abort_if_vm_exists(vm_name)

    if conf.do_build:
        wbatch_tmp = conf.wbatch
        conf.wbatch = False
        vm_delete(vm_name)
        conf.wbatch = wbatch_tmp

    vbm("createvm", "--name", vm_name, "--register",
        "--ostype", conf.vbox_ostype, "--groups", "/" + vm_group)

    if conf.do_build:
        output = vbm("showvminfo", "--machinereadable", vm_name, wbatch=False)
        if re.search(r'longmode="off"', output):
            logger.info("Nodes run 32-bit OS, enabling PAE.")
            vbm("modifyvm", vm_name, "--pae", "on")

    vbm("modifyvm", vm_name, "--rtcuseutc", "on")
    vbm("modifyvm", vm_name, "--biosbootmenu", "disabled")
    vbm("modifyvm", vm_name, "--largepages", "on")
    vbm("modifyvm", vm_name, "--boot1", "disk")
    vbm("modifyvm", vm_name, "--boot3", "net")

    # Enough ports for three disks
    vbm("storagectl", vm_name, "--name", "SATA", "--add", "sata",
        "--portcount", str(3))
    vbm("storagectl", vm_name, "--name", "SATA", "--hostiocache", "on")
    vbm("storagectl", vm_name, "--name", "IDE", "--add", "ide")

    logger.info("Created VM %s.", vm_name)

# -----------------------------------------------------------------------------
# VM unregister, remove, delete
# -----------------------------------------------------------------------------


def vm_unregister_del(vm_name):
    logger.info("Unregistering and deleting VM: %s", vm_name)
    vbm("unregistervm", vm_name, "--delete")


def vm_delete(vm_name):
    logger.info("Asked to delete VM %s ", vm_name)
    if vm_exists(vm_name):
        logger.info("\tfound")
        vm_power_off(vm_name)
        hd_path = vm_get_disk_path(vm_name)
        if hd_path:
            logger.info("\tDisk attached: %s", hd_path)
            vm_detach_disk(vm_name)
            disk_unregister(hd_path)
            try:
                os.remove(hd_path)
            except OSError:
                # File is probably gone already
                pass
        vm_unregister_del(vm_name)
    else:
        logger.info("\tnot found")

# -----------------------------------------------------------------------------
# VM shared folders
# -----------------------------------------------------------------------------


def vm_add_share_automount(vm_name, share_dir, share_name):
    vbm("sharedfolder", "add", vm_name,
        "--name", share_name,
        "--hostpath", share_dir,
        "--automount")


def vm_add_share(vm_name, share_dir, share_name):
    vbm("sharedfolder", "add", vm_name,
        "--name", share_name,
        "--hostpath", share_dir)

# -----------------------------------------------------------------------------
# Disk functions
# -----------------------------------------------------------------------------


def get_next_child_disk_uuid(disk):
    if not disk_registered(disk):
        return

    output = vbm("showhdinfo", disk, wbatch=False)

    child_uuid = None

    line = re.search(r'^Child UUIDs:\s+(\S+)$', output, flags=re.MULTILINE)
    try:
        child_uuid = line.group(1)
    except AttributeError:
        # No more child UUIDs
        pass

    return child_uuid


def disk_to_vm(disk):
    output = vbm("showhdinfo", disk, wbatch=False)

    line = re.search(r'^In use by VMs:\s+(\S+)', output, flags=re.MULTILINE)
    try:
        vm_name = line.group(1)
    except AttributeError:
        # No VM attached to disk
        return None
    return vm_name


def disk_to_path(disk):
    output = vbm("showhdinfo", disk, wbatch=False)

    # Note: path may contain whitespace
    line = re.search(r'^Location:\s+(\S.*)$', output, flags=re.MULTILINE)
    try:
        disk_path = line.group(1)
    except AttributeError:
        logger.error("No disk path found for disk %s.", disk)
        raise
    return disk_path

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Creating, registering and unregistering disk images with VirtualBox
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def disk_registered(disk):
    """disk can be either a path or a disk UUID"""
    output = vbm("list", "hdds", wbatch=False)
    return re.search(disk, output)


def disk_unregister(disk):
    logger.info("Unregistering disk\n\t%s", disk)
    vbm("closemedium", "disk", disk)


def create_vdi(path, size):

    # Make sure target directory exists
    hf.create_dir(os.path.dirname(path))

    logger.info("Creating disk (size: %s MB):\n\t%s", size, path)
    vbm("createhd",
        "--format", "VDI",
        "--filename", path,
        "--size", str(size))

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Attaching and detaching disks from VMs
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def vm_get_disk_path(vm_name):
    output = vbm("showvminfo", "--machinereadable", vm_name, wbatch=False)
    line = re.search(r'^"SATA-0-0"="(.*vdi)"$', output, flags=re.MULTILINE)
    try:
        path = line.group(1)
    except AttributeError:
        logger.info("No disk path found for VM %s.", vm_name)
        path = None
    return path


def vm_detach_disk(vm_name, port=0):
    logger.info("Detaching disk from VM %s.", vm_name)
    vbm("storageattach", vm_name,
        "--storagectl", "SATA",
        "--port", str(port),
        "--device", "0",
        "--type", "hdd",
        "--medium", "none")
    # VirtualBox VM needs a break before taking new commands
    cs.conditional_sleep(1)


def vm_attach_dvd(vm_name, iso, port=0):
    logger.info("Attaching to VM %s:\n\t%s", vm_name, iso)
    vbm("storageattach", vm_name,
        "--storagectl", "IDE",
        "--port", str(port),
        "--device", "0",
        "--type", "dvddrive",
        "--medium", iso)


def vm_attach_disk(vm_name, disk, port=0):
    """disk can be either a path or a disk UUID"""
    logger.info("Attaching to VM %s:\n\t%s", vm_name, disk)
    vbm("storageattach", vm_name,
        "--storagectl", "SATA",
        "--port", str(port),
        "--device", "0",
        "--type", "hdd",
        "--medium", disk)


# disk can be either a path or a disk UUID
def vm_attach_disk_multi(vm_name, disk, port=0):
    vbm("modifyhd", "--type", "multiattach", disk)

    logger.info("Attaching to VM %s (multi):\n\t%s", vm_name, disk)
    vbm("storageattach", vm_name,
        "--storagectl", "SATA",
        "--port", str(port),
        "--device", "0",
        "--type", "hdd",
        "--medium", disk)

# -----------------------------------------------------------------------------
# VirtualBox guest add-ons
# -----------------------------------------------------------------------------


def vm_attach_guestadd_iso(vm_name):
    if conf.wbatch:
        # Record the calls for wbatch (this should always work because the
        # Windows VirtualBox always comes with the guest additions)
        # TODO better way of disabling do_build temporarily
        tmp_do_build = conf.do_build
        conf.do_build = False
        # An existing drive is needed to make additions shortcut work
        # (at least VirtualBox 4.3.12 and below)
        vm_attach_dvd(vm_name, "emptydrive", port=1)
        vm_attach_dvd(vm_name, "additions", port=1)
        conf.do_build = tmp_do_build
    # If we are just faking it for wbatch, we are already done here
    if not conf.do_build:
        return

    if not hasattr(conf, "guestadd_iso") or not conf.guestadd_iso:
        # No location configured, asking VirtualBox for one

        tmp_wbatch = conf.wbatch
        conf.wbatch = False
        # An existing drive is needed to make additions shortcut work
        # (at least VirtualBox 4.3.12 and below)
        vm_attach_dvd(vm_name, "emptydrive", port=1)
        try:
            vm_attach_dvd(vm_name, "additions", port=1)
        except Exception:
            # TODO Implement search and guessing if still needed.
            # We only need it on Linux if the VirtualBox package does not
            # include the guest additions, the user has not provided an ISO,
            # and the cluster must be built using shared folders (i.e. only
            # for wbatch testing on Linux)
            logger.error("VirtualBox guest additions not found.")
            sys.exit(1)
        conf.wbatch = tmp_wbatch

# -----------------------------------------------------------------------------
# Snapshots
# -----------------------------------------------------------------------------


def vm_snapshot_list(vm_name):
    output = None
    if vm_exists(vm_name):
        try:
            output = vbm("snapshot", vm_name, "list", "--machinereadable",
                         show_err=False)
        except EnvironmentError:
            # No snapshots
            pass
    return output


def vm_snapshot_exists(vm_name, shot_name):
    snap_list = vm_snapshot_list(vm_name)
    if snap_list:
        return re.search('SnapshotName.*="{}"'.format(shot_name), snap_list)
    else:
        return False


def vm_snapshot(vm_name, shot_name):
    vbm("snapshot", vm_name, "take", shot_name)

    # VirtualBox VM needs a break before taking new commands
    cs.conditional_sleep(1)

# -----------------------------------------------------------------------------
# Booting a VM
# -----------------------------------------------------------------------------


def vm_boot(vm_name):
    log_str = "Starting VM {}".format(vm_name)

    if conf.do_build:
        # Save latest VM config before booting
        output = vbm("showvminfo", "--machinereadable", vm_name, wbatch=False)
        log_file = os.path.join(conf.log_dir, "vm_{}.cfg".format(vm_name))
        with open(log_file, 'w') as logf:
            logf.write(output)

    if conf.vm_ui:
        if conf.wbatch and conf.vm_ui == "headless":
            # With VirtualBox 5.1.6, console type "headless" often gives no
            # access to the VM console which on Windows is the main method for
            # interacting with the cluster. Use "separate" which works at least
            # on 5.0.26 and 5.1.6.
            logger.warning('Overriding UI type "headless" with "separate" for '
                           'Windows batch files.')
            conf.vm_ui = "separate"
        log_str += " with {} GUI".format(conf.vm_ui)
        logger.info(log_str)
        vbm("startvm", vm_name, "--type", conf.vm_ui)
    else:
        logger.info(log_str)
        vbm("startvm", vm_name)
