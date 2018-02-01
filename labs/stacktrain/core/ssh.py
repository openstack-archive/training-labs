# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import logging
import os
import time

import subprocess
import sys
import traceback

import stacktrain.config.general as conf

import stacktrain.core.helpers as hf

logger = logging.getLogger(__name__)


def get_osbash_private_key():
    key_path = os.path.join(conf.lib_dir, "osbash-ssh-keys", "osbash_key")
    if os.path.isfile(key_path):
        mode = os.stat(key_path).st_mode & 0o777
        if mode != 0o400:
            logger.warning("Adjusting permissions for key file (0400):\n\t%s",
                           key_path)
            os.chmod(key_path, 0o400)
    else:
        logger.error("Key file not found at:\n\t%s", key_path)
        sys.exit(1)
    return key_path


def vm_scp_to_vm(vm_name, *args):
    """
    Copy files or directories (incl. implied directories) to a VM's osbash
    home directory
    """

    key_path = get_osbash_private_key()

    for src_path in args:
        target_path = hf.strip_top_dir(conf.top_dir, src_path)

        target_dir = os.path.dirname(target_path)
        if not target_dir:
            target_dir = '.'

        vm_ssh(vm_name, "mkdir", "-p", target_dir)

        target_port = str(conf.vm[vm_name].ssh_port)

        try:
            full_target = "{}@{}:{}".format(conf.vm_shell_user,
                                            conf.vm[vm_name].ssh_ip,
                                            target_dir)
            logger.debug("Copying from\n\t%s\n\tto\n\t%s (port: %s)",
                         src_path, full_target, target_port)
            # To avoid getting stuck on broken ssh connection, disable
            # connection sharing (ControlPath) and use a timeout when
            # connecting.
            subprocess.check_output(["scp", "-q", "-r",
                                     "-i", key_path,
                                     "-o", "UserKnownHostsFile=/dev/null",
                                     "-o", "StrictHostKeyChecking=no",
                                     "-o", "ConnectTimeout=10",
                                     "-o", "ControlPath=none",
                                     "-P", target_port,
                                     src_path, full_target])
        except subprocess.CalledProcessError as err:
            logger.error("Copying from\n\t%s\n\tto\n\t%s",
                         src_path, full_target)
            logger.error("\trc=%s: %s", err.returncode, err.output)
            sys.exit(1)


def vm_ssh(vm_name, *args, **kwargs):
    key_path = get_osbash_private_key()

    live_log = kwargs.pop('log_file', None)
    show_err = kwargs.pop('show_err', True)

    try:
        target = "{}@{}".format(conf.vm_shell_user, conf.vm[vm_name].ssh_ip)
        target_port = str(conf.vm[vm_name].ssh_port)

        # To avoid getting stuck on broken ssh connection, disable
        # connection sharing (ControlPath) and use a timeout when connecting.
        full_args = ["ssh", "-q",
                     "-i", key_path,
                     "-o", "UserKnownHostsFile=/dev/null",
                     "-o", "StrictHostKeyChecking=no",
                     "-o", "ConnectTimeout=10",
                     "-o", "ControlPath=none",
                     "-p", target_port,
                     target] + list(args)
        logger.debug("vm_ssh: %s", ' '.join(full_args))

        ssh_log = os.path.join(conf.log_dir, "ssh.log")
        with open(ssh_log, 'a') as logf:
            print(' '.join(full_args), file=logf)

        if live_log:
            logger.debug("Writing live log for ssh call at %s.", live_log)
            hf.create_dir(os.path.dirname(live_log))
            # Unbuffered log file
            with open(live_log, 'a', 0) as live_logf:
                ret = subprocess.call(full_args,
                                      stderr=subprocess.STDOUT,
                                      stdout=live_logf)
                if ret:
                    err_msg = "ssh returned status {}.".format(ret)
                    logger.error("%s", err_msg)

                    # Indicate error in status dir
                    open(os.path.join(conf.status_dir, "error"), 'a').close()

                    raise EnvironmentError

            output = None
        else:
            try:
                output = subprocess.check_output(full_args,
                                                 stderr=subprocess.STDOUT)
            except subprocess.CalledProcessError:
                if show_err:
                    logger.exception("vm_ssh: Aborting.")
                    traceback.print_exc(file=sys.stdout)
                    sys.exit(1)
                raise EnvironmentError

    except subprocess.CalledProcessError as err:
        logger.debug("ERROR ssh %s", full_args)
        logger.debug("ERROR rc %s", err.returncode)
        logger.debug("ERROR output %s", err.output)
        raise EnvironmentError
    return output


def wait_for_ssh(vm_name):
    while True:
        try:
            vm_ssh(vm_name, "exit", show_err=False)
            break
        except EnvironmentError:
            time.sleep(1)
