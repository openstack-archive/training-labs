#!/usr/bin/env python

# TODO rename vm_create

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import logging
import os
import re
import subprocess
import sys
import time

import stacktrain.config.general as conf

import stacktrain.core.cond_sleep as cs
import stacktrain.core.helpers as hf

logger = logging.getLogger(__name__)

kvm_vol_pool = "default"
vm_group = "OpenStack training-labs"


def init():
    output = virsh("--version")
    logger.debug("Virsh version: %s", output)
    try:
        output = virsh("list", show_err=False)
    except EnvironmentError:
        logger.error("Failed to connect to libvirt/KVM. Is service running?"
                     " Aborting.")
        sys.exit(1)
    try:
        virsh("pool-info", kvm_vol_pool, show_err=False)
    except EnvironmentError:
        logger.error("Storage pool '%s' not found. It should be created"
                     " automatically when the virt-manager GUI is started"
                     " for the first time.", kvm_vol_pool)
        sys.exit(1)


def virsh_log(call_args, err_code=None):
    log_file = os.path.join(conf.log_dir, "virsh.log")
    msg = ' '.join(call_args)
    if err_code:
        msg = "FAILURE ({}): ".format(err_code) + msg
    with open(log_file, 'a') as logf:
        if conf.do_build:
            logf.write("%s\n" % msg)
        else:
            logf.write("(not executed) %s\n" % msg)
            return


def virsh(*args, **kwargs):

    show_err = kwargs.pop('show_err', True)

    virsh_exe = "virsh"
    libvirt_connect_uri = "qemu:///system"
    virsh_call = ["sudo", virsh_exe,
                  "--connect={}".format(libvirt_connect_uri)]

    call_args = virsh_call + list(args)

    virsh_log(call_args)

    try:
        output = subprocess.check_output(call_args, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as err:
        virsh_log(call_args, err_code=err.returncode)
        if show_err:
            logger.warn(' '.join(call_args))
            logger.warn("call_args: %s", call_args)
            logger.warn("rc: %s", err.returncode)
            logger.warn("output:\n%s", err.output)
            logger.exception("virsh: Aborting.")
            logger.warn("-----------------------------------------------")
            sys.exit(1)
        else:
            logger.debug("call_args: %s", call_args)
            logger.debug("rc: %s", err.returncode)
            logger.debug("output:\n%s", err.output)
        raise EnvironmentError

    return output

# -----------------------------------------------------------------------------
# VM status
# -----------------------------------------------------------------------------


def vm_exists(vm_name):
    try:
        virsh("domstate", vm_name, show_err=False)
    except EnvironmentError:
        return False
    return True


def vm_is_running(vm_name):
    try:
        output = virsh("domstate", vm_name, show_err=False)
    except EnvironmentError:
        # VM probably does not exist
        return False
    return True if output and re.search(r'running', output) else False


def vm_is_shut_down(vm_name):
    # cond = re.compile(r'(running|in shutdown)')
    cond = re.compile(r'(shut off)')
    output = virsh("domstate", vm_name)
    return True if cond.search(output) else False


def vm_wait_for_shutdown(vm_name, timeout=None):
    logger.info("Waiting for shutdown of VM %s.", vm_name)

    cnt = 0
    while True:
        if vm_is_shut_down(vm_name):
            logger.debug("Machine powered off.")
            break
        if timeout and cnt > timeout:
            logger.debug("Timeout reached, giving up.")
            break
        print('W' if conf.verbose_console else '.', end='')
        sys.stdout.flush()
        time.sleep(1)
        cnt += 1


def vm_power_off(vm_name):
    # TODO check: may need to check for "shut off" instead of "running"
    if vm_is_running(vm_name):
        logger.debug("Powering off VM %s", vm_name)
        virsh("destroy", vm_name)
    else:
        logger.debug("vm_power_off: VM %s not running", vm_name)


def vm_acpi_shutdown(vm_name):
    if vm_is_running(vm_name):
        logger.info("Shutting down VM  %s.", vm_name)
        virsh("shutdown", vm_name)
    else:
        logger.debug("vm_acpi_shutdown: VM %s not running", vm_name)


def set_vm_group(vm_name):
    logger.debug("Setting VM group (title, description) for %s.", vm_name)
    # We are not changing a running VM here; to do that, add "--live" (which
    # produces an error if the VM is not running)
    virsh("desc", vm_name, "--config", "--title",
          "--new-desc", "{}: {}".format(vm_name, vm_group))
    long_desc = "All VMs with '{}' in their description title get shut down " \
                "when a new cluster build starts."
    virsh("desc", vm_name, "--config",
          "--new-desc", long_desc.format(vm_group))


def get_vm_group(vm_name):
    return virsh("desc", vm_name, "--title")


# TODO move this to functions_host, call get_running_vms_list, shutdown,
#      poweroff, wait_for_shutdown
def stop_running_cluster_vms():
    output = virsh("list", "--uuid")
    if output == "\n":
        return
    for vm_id in output.splitlines():
        if vm_id == "":
            continue
        logger.debug("Candidate for shutdown vm_id:%s:", vm_id)
        if re.match(".*{}".format(vm_group), get_vm_group(vm_id)):
            logger.info("Shutting down VM %s.", vm_id)
            vm_acpi_shutdown(vm_id)
            vm_wait_for_shutdown(vm_id, timeout=5)
            if not vm_is_shut_down(vm_id):
                logger.info("VM will not shut down, powering it off.")
                vm_power_off(vm_id)

# -----------------------------------------------------------------------------
# Network functions
# -----------------------------------------------------------------------------


def log_xml_dump(vm_name, desc, xml=None):
    if not xml:
        # No XML dump provided, so get it now
        xml = virsh("dumpxml", vm_name)
    fpath = os.path.join(conf.log_dir, "vm_{}_{}.xml".format(vm_name, desc))
    with open(fpath, 'w') as xf:
        xf.write(xml)


# Get the MAC address from a node name (default network)
def node_to_mac(node):

    logger.info("Waiting for MAC address.")
    while True:
        dump = virsh("dumpxml", node)
        ma = re.search(r'([a-z0-9:]{17})', dump)
        if ma:
            # FIXME what if there are two matching lines?
            mac = ma.group(1)
            break
        time.sleep(1)
        print('M' if conf.verbose_console else '.', end='')
        sys.stdout.flush()
    return mac


# Get the IP address from a MAC address (default network)
def mac_to_ip(mac):

    logger.info("Waiting for IP address.")
    while True:
        lines = subprocess.check_output(["sudo", "arp", "-n"])
        ma = re.search(r"(\S+).*{}".format(mac), lines)
        if ma:
            ip = ma.group(1)
            logger.debug("mac_to_ip: %s -> %s", mac, ip)
            return ip
        time.sleep(1)
        print('I' if conf.verbose_console else '.', end='')
        sys.stdout.flush()


def node_to_ip(vm_name):

    # TODO refactor node_to_ip()

    # Store vm_name, IP address, and MAC address in text file for later use
    # by shell script tools (e.g., tools/test-once.sh)
    node_ip_db = os.path.join(conf.log_dir, "node_ip.db")

    logger.debug("node_to_ip %s.", vm_name)
    if conf.vm[vm_name].pxe_tmp_ip:
        ip = conf.vm[vm_name].pxe_tmp_ip
        logger.debug("Using IP address %s for PXE booting.", ip)
        # Return IP address, but don't cache in conf or file
        return ip
    elif conf.vm[vm_name].ssh_ip:
        # Return IP address cached in conf
        return conf.vm[vm_name].ssh_ip

    mac = node_to_mac(vm_name)
    logger.debug("MAC address for %s: %s", vm_name, mac)

    if os.path.exists(node_ip_db):
        with open(node_ip_db, 'r') as dbfile:
            for line in dbfile:
                ma = re.match(r"{} ([0-9\.]+) ".format(mac), line)
                if ma:
                    ip = ma.group(1)
                    logger.debug("IP address for %s:  %s (cached)", vm_name,
                                 ip)
                    #conf.vm[vm_name].ssh_ip = ip
                    return ip

    ip = mac_to_ip(mac)
    logger.debug("IP address for %s:  %s", vm_name, ip)

    # Update cache file
    with open(node_ip_db, 'a') as out:
        out.write("{} {} {}\n".format(mac, ip, vm_name))

    conf.vm[vm_name].ssh_ip = ip

    # Return IP address to caller
    return ip


def log_iptables(tables, desc=""):
    if not hasattr(log_iptables, "cnt"):
        log_iptables.cnt = 0
    log_name = "kvm-iptables-save_{}_{}".format(log_iptables.cnt, desc)
    with open(os.path.join(conf.log_dir, log_name), 'w') as logf:
        logf.write(tables)
    log_iptables.cnt += 1


def get_iptables(desc=""):
    errout = subprocess.STDOUT

    output = subprocess.check_output(("sudo", "iptables-save"), stderr=errout)
    log_iptables(output, desc=desc)

    return output


def set_iptables(tables):
    errout = subprocess.STDOUT
    log_iptables(tables, desc="done")
    p1 = subprocess.Popen(["sudo", "iptables-restore"],
                          stdin=subprocess.PIPE, stderr=errout)
    p1.communicate(input=tables)


def virsh_destroy_network(net_name):
    if virsh_network_defined(net_name) and virsh_network_active(net_name):
        network = "labs-{}".format(net_name)
        virsh("net-destroy", network)


def virsh_stop_network(net_name):

    # Undo our changes to iptables before letting libvirt deal with it
    iptables_forward_new_connections(False)

    logger.debug("Stopping network %s.", net_name)
    virsh_destroy_network(net_name)


def iptables_forward_new_connections(forward_new_conns):
    # Save, update, and restore iptables configuration made by libvirt
    replace = [" RELATED", " NEW,RELATED"]

    if forward_new_conns:
        fnc_desc = "add_forwarding"
    else:
        fnc_desc = "remove_forwarding"
        replace[0], replace[1] = replace[1], replace[0]

    logger.debug("Replacing %s with %s.", replace[0], replace[1])
    output = get_iptables(desc=fnc_desc)
    changed = ""
    # Keep "\n", we will need them
    for line in output.splitlines(True):
        if re.search("FORWARD.*virbr[^0]", line):
            changed += re.sub(replace[0], replace[1], line)
        else:
            changed += line

    set_iptables(changed)


def virsh_start_network(net_name):
    network = "labs-{}".format(net_name)

    if virsh_network_active(net_name):
        return

    logger.debug("Starting network %s.", net_name)
    network = "labs-{}".format(net_name)
    virsh("net-start", network)

    # Forward new connections, too (except on virbr0); this allows our
    # NAT networks to talk to each other
    iptables_forward_new_connections(True)


def virsh_undefine_network(net_name):
    net = "labs-{}".format(net_name)
    if virsh_network_defined(net_name):
        logger.debug("Undefining network %s.", net_name)
        virsh("net-undefine", net)


def virsh_vm_defined(vm_name):
    try:
        virsh("domstate", vm_name, show_err=False)
    except EnvironmentError:
        return False
    return True


def virsh_network_defined(net_name):
    net = "labs-{}".format(net_name)
    try:
        virsh("net-info", net, show_err=False)
    except EnvironmentError:
        # logger.error("virsh_network_defined %s", type(err))
        # logger.exception("Exception")
        return False
    return True


def virsh_network_active(net_name):
    network = "labs-{}".format(net_name)
    # Returns exception if network does not exist
    output = virsh("net-info", network, show_err=False)

    ma = re.search("Active:.*yes", output)
    return True if ma else False


def virsh_define_network(net_name, ip_address):

    network = "labs-{}".format(net_name)
    if not virsh_network_defined(net_name):
        logger.debug("Defining network %s (%s)", network, ip_address)
        xml_content = ("<network>\n"
                       "  <name>%s</name>\n"
                       "  <forward mode='nat'/>\n"
                       "  <ip address='%s' netmask='255.255.255.0'>\n"
                       "  </ip>\n"
                       "</network>\n")
        xml_content = xml_content % (network, ip_address)
        xml_file = os.path.join(conf.log_dir, "kvm-net-{}.xml".format(network))
        with open(xml_file, 'w') as xf:
            xf.write(xml_content)
        virsh("net-define", xml_file)


def create_network(net_name, ip_address):
    logger.debug("Creating network %s (%s)", net_name, ip_address)
    virsh_stop_network(net_name)
    virsh_undefine_network(net_name)
    virsh_define_network(net_name, ip_address)
    virsh_start_network(net_name)

# -----------------------------------------------------------------------------
# VM create and configure
# -----------------------------------------------------------------------------


def ip_to_netname(ip):
    ip_net = hf.ip_to_net_address(ip)

    for net_name, net_address in conf.networks.items():
        if net_address == ip_net:
            logger.debug("ip_to_netname %s -> %s", ip, net_name)
            return net_name
    logger.error("ip_to_netname: no netname found for %s.", ip)
    raise ValueError


# virt-xml(1) looks like it was made for this, but version 1.4.0 has issues:
# changing the boot device from hd to network works, but completely removing it
# did not. To set the order at the device level, we could then do:
# virt-xml controller --edit 2 --disk boot_order=1
# virt-xml controller --edit 1 --network boot_order=2
# But for now, we have to edit the XML file here.
# TODO make vm_boot_order_pxe more configurable
def vm_boot_order_pxe(vm_name):
    output = virsh("dumpxml", vm_name)

    logger.debug("vm_boot_order_pxe: Editing XML dump.")
    changed = ""
    # TODO boot_network should not be defined here
    boot_network = "labs-mgmt"

    # Track if every replace pattern matches exactly once
    sanity_check = 0

    # Keep "\n", we will need them
    for line in output.splitlines(True):
        if re.search(r"<boot dev='hd'/>", line):
            # Example: <boot dev='hd'/>
            logger.debug("Found boot order line, dropping it.")
            sanity_check += 1
        elif re.search(r"      <source network=['\"]{}['\"]/>".format(boot_network),
                       line):
            # <source network='labs-mgmt'/>
            logger.debug("Found network interface, adding boot order.")
            changed += line
            changed += "      <boot order='2'/>\n"
            sanity_check += 10
        elif re.search(r"<target dev=['\"]hda['\"].*/>", line):
            # Example: <target dev='hda' bus='ide'/>
            logger.debug("Found hd interface, adding boot order.")
            changed += line
            changed += "      <boot order='1'/>\n"
            sanity_check += 100
        else:
            changed += line

    if sanity_check != 111:
        logger.error("vm_boot_order_pxe failed (%s). Aborting.", sanity_check)
        logger.debug("vm_boot_order_pxe original XML file:\n%s.", output)
        sys.exit(1)

    # Create file we use to redefine the VM to use PXE booting
    xml_file = os.path.join(conf.log_dir,
                            "vm_{}_inject_pxe.xml".format(vm_name))
    with open(xml_file, 'w') as xf:
        xf.write(changed)
    virsh("define", xml_file)

# -----------------------------------------------------------------------------
# VM unregister, remove, delete
# -----------------------------------------------------------------------------


def vm_delete(vm_name):
    logger.info("Asked to delete VM %s.", vm_name)
    if vm_exists(vm_name):
        logger.info("\tfound")
        vm_power_off(vm_name)
        # virt-install restarts VM after poweroff, we may need to power off
        # twice
        cs.conditional_sleep(1)
        vm_power_off(vm_name)

        # Take a break before undefining the VM
        cs.conditional_sleep(1)

        virsh("undefine", "--snapshots-metadata", "--remove-all-storage",
              vm_name)
    else:
        logger.info("\tnot found")

# -----------------------------------------------------------------------------
# Disk functions
# -----------------------------------------------------------------------------


def disk_exists(disk):
    try:
        virsh("vol-info", "--pool", kvm_vol_pool, disk, show_err=False)
    except EnvironmentError:
        return False
    return True


def disk_create_cow(disk, base_disk):
    # size in MB
    if not disk_exists(disk):
        virsh("vol-create-as", kvm_vol_pool, disk,
              "{}M".format(conf.base_disk_size),
              "--format", "qcow2",
              "--backing-vol", base_disk,
              "--backing-vol-format", "qcow2")


def disk_create(disk, size):
    # size in MB
    if not disk_exists(disk):
        virsh("vol-create-as", kvm_vol_pool, disk, "{}M".format(size),
              "--format", "qcow2")


def disk_delete(disk):
    if disk_exists(disk):
        logger.debug("Deleting disk %s.", disk)
        virsh("vol-delete", "--pool", kvm_vol_pool, disk)


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Attaching and detaching disks from VMs
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def disk_compress(disk_name):
    spexe = "virt-sparsify"
    if not hf.test_exe(spexe):
        logger.warn("No virt-sparsify executable found.")
        logger.warn("Consider installing libguestfs-tools.")
        return

    disk_path = get_disk_path(disk_name)
    pool_dir = os.path.dirname(disk_path)

    logger.info("Compressing disk image, input file:\n\t%s", disk_path)

    stat = os.stat(disk_path)
    mode = stat.st_mode
    logger.debug("mode\t%s", oct(mode))
    uid = stat.st_uid
    logger.debug("uid\t%s", uid)
    gid = stat.st_gid
    logger.debug("gid\t%s", gid)
    size = stat.st_size
    logger.debug("size\t%s", size)

    tmp_file = os.path.join(pool_dir, ".{}".format(disk_name))

    # virt-sparsify uses about 10 GB additional, temporary work space.
    # The default (/tmp) is often too small (especially if it is a RAM
    # disk). We use the pool_dir instead.
    subprocess.call(["sudo", spexe, "--tmp", pool_dir, "--compress",
                    disk_path, tmp_file])

    logger.info("Restoring owner.")
    # No root wrapper, so use sudo with shell commands
    subprocess.call(["sudo", "chown", "-v", "--reference={}".format(disk_path),
                     tmp_file])
    logger.info("Restoring permissions.")
    subprocess.call(["sudo", "chmod", "-v", "--reference={}".format(disk_path),
                     tmp_file])
    logger.info("Moving temporary file into final location.")
    subprocess.call(["sudo", "mv", "-v", "-f", tmp_file, disk_path])

#    os.chown(tmp_file, uid, gid)
#    os.chmod(tmp_file, mode)

#    import shutil
#    shutil.move(tmp_file, disk_path)

    stat = os.stat(disk_path)
    mode = stat.st_mode
    logger.debug("mode\t%s", oct(mode))
    uid = stat.st_uid
    logger.debug("uid\t%s", uid)
    gid = stat.st_gid
    logger.debug("gid\t%s", gid)
    new_size = stat.st_size
    logger.debug("size\t%s", new_size)

    compression = "%0.0f" % round((1-new_size/size)*100) + "%"
    # logger.info("size\t%s (compressed by %s%)", new_size, compression)
    logger.info("size\t%s (compressed by %s)", new_size, compression)


def get_disk_path(disk_name):
    # Result comes with trailing newlines
    return virsh("vol-path", "--pool", kvm_vol_pool, disk_name).rstrip()

# -----------------------------------------------------------------------------
# Snapshots
# -----------------------------------------------------------------------------


def vm_snapshot_list(vm_name):
    output = None
    if vm_exists(vm_name):
        # try:
        output = virsh("snapshot-list", vm_name, show_err=False)
        # except EnvironmentError:
        #    # No snapshots
        #    # output = None
    return output


def vm_snapshot_exists(vm_name, shot_name):
    snap_list = vm_snapshot_list(vm_name)
    if snap_list:
        return re.search('^ {}'.format(shot_name), snap_list)
    else:
        return False


def vm_snapshot(vm_name, shot_name):
    virsh("snapshot-create-as", vm_name, shot_name,
          "{}: {}".format(vm_name, shot_name))

# -----------------------------------------------------------------------------
# Booting a VM
# -----------------------------------------------------------------------------


def vm_boot(vm_name):
    if conf.vm[vm_name].pxe_tmp_ip:
        logger.warn("Patching XML dump to enable PXE booting with KVM on %s.",
                    vm_name)
        logger.error("Configuring PXE booting.")
        vm_boot_order_pxe(vm_name)
        # Log the current configuration of the VM
        log_xml_dump(vm_name, "pxe_enabled")

    logger.info("Starting VM %s", vm_name)
    virsh("start", vm_name)
    logger.info("Waiting for VM %s to run.", vm_name)
    while not vm_is_running(vm_name):
        time.sleep(1)
        print('R' if conf.verbose_console else '.', end='')
        sys.stdout.flush()

    # Our caller assumes that conf.vm[vm_name].ssh_ip is set
    node_to_ip(vm_name)
