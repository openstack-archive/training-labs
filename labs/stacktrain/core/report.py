# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import logging
import sys
import subprocess
import time

from urlparse import urlparse, urlunparse

import stacktrain.config.general as conf
import stacktrain.core.download as dl
import stacktrain.core.helpers as hf

logger = logging.getLogger(__name__)


def get_git_info():
    git_exe = "git"
    if not hf.test_exe("git"):
        logger.debug("No git executable found. Unable to log git status.")
        return None

    summary_args = ["git", "describe", "--all", "--long", "--dirty"]
    diff_args = ["git", "--no-pager", "diff", "HEAD", "-p", "--stat"]
    try:
        result = "git status: "
        result += subprocess.check_output(summary_args)
        result += subprocess.check_output(diff_args).rstrip()
    except subprocess.CalledProcessError:
        result = None
    return result


def print_summary():
    print("Your cluster nodes:")
    for vm_name, vmc in conf.vm.items():
        logger.info("VM name: %s", vm_name)

        if vmc.ssh_port != 22:
            port_opt = " -p {}".format(vmc.ssh_port)
        else:
            port_opt = ""

        logger.info("\tSSH login: ssh%s %s@%s", port_opt, conf.vm_shell_user,
                    vmc.ssh_ip)
        logger.info("\t           (password: %s)", "osbash")
        if vm_name == "controller":
            if vmc.http_port:
                port_opt = ":{}".format(vmc.http_port)
            else:
                port_opt = ""
            dashboard_url = "http://{}{}/horizon/".format(vmc.ssh_ip, port_opt)
            logger.info("\tDashboard: Assuming horizon is on %s VM.",
                        vmc.vm_name)
            logger.info("\t           %s", dashboard_url)

            logger.info("\t           User  : %s (password: %s)",
                        conf.demo_user, conf.demo_password)
            logger.info("\t           User  : %s (password: %s)",
                        conf.admin_user, conf.admin_password)

    for name, address in conf.networks.items():
        logger.info("Network: %s", name)
        logger.info("         Network address: %s", address)
