# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

from importlib import import_module
import logging
import os
from os.path import basename, isfile, join
import re
import sys
import time

from glob import glob

import stacktrain.config.general as conf
import stacktrain.core.ssh as ssh
import stacktrain.batch_for_windows as wbatch
import stacktrain.core.functions_host as host
import stacktrain.core.helpers as hf
import stacktrain.core.iso_image as iso_image
# import stacktrain.kvm.install_node as inst_node
# import stacktrain.virtualbox.vm_create as vm
inst_node = import_module("stacktrain.%s.install_node" % conf.provider)
vm = import_module("stacktrain.%s.vm_create" % conf.provider)

logger = logging.getLogger(__name__)


def ssh_exec_script(vm_name, script_path):
    ssh.vm_scp_to_vm(vm_name, script_path)

    remote_path = hf.strip_top_dir(conf.top_dir, script_path)

    logger.info("Start %s", remote_path)

    script_name = os.path.splitext(os.path.basename(script_path))[0]
    prefix = host.get_next_prefix(conf.log_dir, "auto")
    log_name = "{}_{}.auto".format(prefix, script_name)
    log_path = os.path.join(conf.log_dir, log_name)
    try:
        ssh.vm_ssh(vm_name,
                   "bash {} && rm -vf {}".format(remote_path, remote_path),
                   log_file=log_path)
    except EnvironmentError:
        logger.error("Script failure: %s", script_name)
        sys.exit(1)

    logger.info("  done")


def ssh_process_autostart(vm_name):

    # If a KVM VM has been created by an earlier script run, its IP address
    # is not known
    if not conf.vm[vm_name].ssh_ip:
        vm.node_to_ip(vm_name)

    logger.info("Waiting for ssh server in VM %s to respond at %s:%s.",
                vm_name, conf.vm[vm_name].ssh_ip, conf.vm[vm_name].ssh_port)
    ssh.wait_for_ssh(vm_name)
    logger.info("    Connected to ssh server.")
    sys.stdout.flush()

    if conf.vm[vm_name].updated:
        ssh.vm_ssh(vm_name, "rm -rf autostart")
    else:
        logging.debug("Updating config, lib, scripts directories for VM %s.",
                      vm_name)
        ssh.vm_ssh(vm_name, "rm -rf autostart config lib scripts")
        ssh.vm_scp_to_vm(vm_name, conf.config_dir, conf.lib_dir,
                         conf.scripts_dir)

    for script_path in sorted(glob(join(conf.autostart_dir, "*.sh"))):
        ssh_exec_script(vm_name, script_path)
        os.remove(script_path)

    open(join(conf.status_dir, "done"), 'a').close()

# -----------------------------------------------------------------------------
# Autostart mechanism
# -----------------------------------------------------------------------------


def autostart_reset():
    logger.debug("Resetting autostart directories.")
    hf.clean_dir(conf.autostart_dir)
    hf.clean_dir(conf.status_dir)


def process_begin_files():
    for begin_file in sorted(glob(join(conf.status_dir, "*.sh.begin"))):
        match = re.match(r'.*/(.*).begin', begin_file)
        os.remove(begin_file)
        logger.info("\nVM processing %s.", match.group(1))


def autofiles_processing_done():
    err_path = join(conf.status_dir, "error")
    done_path = join(conf.status_dir, "done")
    return isfile(done_path) or isfile(err_path)


def wait_for_autofiles():
    if conf.wbatch:
        wbatch.wbatch_wait_auto()

    if not conf.do_build:
        # Remove autostart files and return if we are just faking it for wbatch
        autostart_reset()
        return

    while not autofiles_processing_done():
        if conf.wbatch:
            # wbatch uses begin files (ssh method does not need them)
            process_begin_files()
        print('D' if conf.verbose_console else '.', end='')
        sys.stdout.flush()
        time.sleep(1)

    # Check for remaining *.sh.begin files
    if conf.wbatch:
        process_begin_files()

    if isfile(join(conf.status_dir, "done")):
        os.remove(join(conf.status_dir, "done"))
    else:
        logger.error("Script failed. Exiting.")
        sys.exit(1)
    logger.info("Processing of scripts successful.")


def autostart_and_wait(vm_name):
    sys.stdout.flush()

    if not conf.wbatch:
        import multiprocessing
        # TODO multiprocessing logging to file
        # mlogger = multiprocessing.get_logger()
        try:
            sshp = multiprocessing.Process(target=ssh_process_autostart,
                                           args=(vm_name,))
            sshp.start()
        except Exception:
            logger.exception("ssh_process_autostart")
            raise

    # ssh_process_autostart has updated the directories
    conf.vm[vm_name].updated = True
    wait_for_autofiles()

    if not conf.wbatch:
        sshp.join()
        logger.debug("sshp exit code: %s", sshp.exitcode)
        if sshp.exitcode:
            logger.error("sshp returned error!")
            raise ValueError

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def _autostart_queue(src_rel_path, target_name=None):
    src_path = join(conf.scripts_dir, src_rel_path)
    src_name = basename(src_path)

    if not target_name:
        target_name = src_name

    if target_name.endswith(".sh"):
        prefix = host.get_next_prefix(conf.autostart_dir, "sh", 2)
        target_name = "{}_{}".format(prefix, target_name)

    if src_name == target_name:
        logger.info("\t%s", src_name)
    else:
        logger.info("\t%s -> %s", src_name, target_name)

    from shutil import copyfile

    copyfile(src_path, join(conf.autostart_dir, target_name))
    if conf.wbatch:
        wbatch.wbatch_cp_auto(src_path, join(conf.autostart_dir, target_name))

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def autostart_queue_and_rename(src_dir, src_file, target_file):
    _autostart_queue(join(src_dir, src_file), target_file)


def autostart_queue(*args):
    for script in args:
        _autostart_queue(script)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


def syntax_error_abort(line):
    logger.error("Syntax error: %s", line)
    sys.exit(1)


def get_vmname_arg(line, args):
    if len(args) == 3 and args[1] == "-n":
        vm_name = args[2]
        if vm_name not in conf.vm:
            conf.vm[vm_name] = conf.VMconfig(vm_name)
    else:
        syntax_error_abort(line)
    return vm_name


def get_two_args(line, args):
    if len(args) == 4 and args[1] == "-n":
        vm_name = args[2]
        arg2 = args[3]
        if vm_name not in conf.vm:
            conf.vm[vm_name] = conf.VMconfig(vm_name)
    else:
        syntax_error_abort(line)
    return vm_name, arg2


def command_from_config(line):
    # Drop trailing whitespace and newline
    line = line.rstrip()

    # Drop first argument ("cmd")
    args = line.split(" ")[1:]

    if args[0] == "boot":
        vm_name = get_vmname_arg(line, args)
        vm.vm_boot(vm_name)
        autostart_and_wait(vm_name)
        conf.vm[vm_name].pxe_tmp_ip = None
    elif args[0] == "snapshot":
        vm_name, shot_name = get_two_args(line, args)
        host.vm_conditional_snapshot(vm_name, shot_name)
    elif args[0] == "shutdown":
        vm_name = get_vmname_arg(line, args)
        vm.vm_acpi_shutdown(vm_name)
        vm.vm_wait_for_shutdown(vm_name)
    elif args[0] == "wait_for_shutdown":
        vm_name = get_vmname_arg(line, args)
        vm.vm_wait_for_shutdown(vm_name)
    elif args[0] == "snapshot_cycle":
        if not conf.snapshot_cycle:
            return
        vm_name, shot_name = get_two_args(line, args)
        _autostart_queue("shutdown.sh")
        vm.vm_boot(vm_name)
        autostart_and_wait(vm_name)
        conf.vm[vm_name].pxe_tmp_ip = None
        vm.vm_wait_for_shutdown(vm_name)
        host.vm_conditional_snapshot(vm_name, shot_name)
    elif args[0] == "boot_set_tmp_node_ip":
        vm_name = get_vmname_arg(line, args)
        logger.info("Setting temporary IP for PXE booting to %s.",
                    conf.pxe_initial_node_ip)
        conf.vm[vm_name].pxe_tmp_ip = conf.pxe_initial_node_ip
    elif args[0] == "create_node":
        vm_name = get_vmname_arg(line, args)
        inst_node.vm_create_node(vm_name)
        logger.info("Node %s created.", vm_name)
    elif args[0] == "create_pxe_node":
        vm_name = get_vmname_arg(line, args)
        conf.vm[vm_name].disks[0] = 10000
        inst_node.vm_create_node(vm_name)
        logger.info("PXE node %s created.", vm_name)
    elif args[0] == "queue_renamed":
        vm_name, script_rel_path = get_two_args(line, args)
        template_name = os.path.basename(script_rel_path)
        new_name = template_name.replace("xxx", vm_name)
        _autostart_queue(script_rel_path, new_name)
    elif args[0] == "queue":
        script_rel_path = args[1]
        _autostart_queue(script_rel_path)
    elif args[0] == "cp_iso":
        vm_name = get_vmname_arg(line, args)
        iso_path = iso_image.find_install_iso()
        ssh.vm_scp_to_vm(vm_name, iso_path)
    else:
        syntax_error_abort(line)


# Parse config/scripts.* configuration files
def autostart_from_config(cfg_file):
    cfg_path = join(conf.config_dir, cfg_file)

    if not isfile(cfg_path):
        logger.error("Config file not found:\n\t%s", cfg_path)
        raise Exception

    with open(cfg_path) as cfg:
        for line in cfg:
            if re.match('#', line):
                continue

            if re.match(r"\s?$", line):
                continue

            if not re.match(r"cmd\s", line):
                logger.error("Syntax error in line:\n\t%s", line)
                raise Exception

            if conf.jump_snapshot:
                ma = re.match(r"cmd\s+snapshot.*\s+(\S)$", line)
                if ma:
                    logger.info("Skipped forward to snapshot %s.",
                                conf.jump_snapshot)
                    del conf.jump_snapshot
                    continue

            command_from_config(line)
