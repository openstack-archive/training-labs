#!/usr/bin/env python

"""
Main program for stacktrain.
"""

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import argparse
import importlib
import logging
import os
import sys
import time

import stacktrain.core.helpers as hf
import stacktrain.config.general as conf
import stacktrain.core.report as report
import stacktrain.batch_for_windows as wbatch

# -----------------------------------------------------------------------------


def enable_verbose_console():
    '''Replace our default console log handler with a more verbose version'''
    logger = logging.getLogger()

    for x in logger.handlers:
        if type(x) is logging.StreamHandler:
            logger.removeHandler(x)

    console_log_handler = logging.StreamHandler()
    console_log_handler.setLevel(logging.DEBUG)

    # All console messages are the same color (except with colored level names)
    console_formatter = logging.Formatter('%(asctime)s %(process)s'
                                          ' \x1b[0;32m%(levelname)s'
                                          '\t%(message)s\x1b[0m', datefmt="%H:%M:%S")
    console_log_handler.setFormatter(console_formatter)

    logger.addHandler(console_log_handler)


def configure_logging():
    """Configure root logger"""
    logger = logging.getLogger()

    logger.setLevel(logging.DEBUG)

    # Level name colored differently (both console and file)
    logging.addLevelName(logging.WARNING, '\x1b[0;33m%s\x1b[0m' %
                         logging.getLevelName(logging.WARNING))
    logging.addLevelName(logging.ERROR, '\x1b[0;31m%s\x1b[0m' %
                         logging.getLevelName(logging.ERROR))

    # Configure console logging
    console_log_handler = logging.StreamHandler()
    console_log_handler.setLevel(logging.INFO)
    # All console messages are the same color (except with colored level names)
    console_formatter = logging.Formatter('\x1b[0;32m%(levelname)s'
                                          '\t%(message)s\x1b[0m')
    console_log_handler.setFormatter(console_formatter)
    logger.addHandler(console_log_handler)

    # Configure log file
    hf.clean_dir(conf.log_dir)
    log_file = os.path.join(conf.log_dir, 'stacktrain.log')
    file_log_handler = logging.FileHandler(log_file)
    file_log_handler.setLevel(logging.DEBUG)
    file_formatter = logging.Formatter('%(process)s %(asctime)s.%(msecs)03d'
                                       ' %(name)s %(levelname)s %(message)s',
                                       datefmt="%H:%M:%S")
    file_log_handler.setFormatter(file_formatter)
    logger.addHandler(file_log_handler)

    logger.debug("Root logger configured.")


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="stacktrain main program.")
    parser.add_argument('-w', '--wbatch', action='store_true',
                        help='Create Windows batch files')
    parser.add_argument('--verbose-console', action='store_true',
                        help='Include time, PID, and DEBUG level messages')
    parser.add_argument('-b', '--build', action='store_true',
                        help='Build cluster on local machine')
    parser.add_argument('-q', '--quick', action='store_true',
                        help='Disable snapshot cycles during build (default)')
    parser.add_argument('-e', '--enable-snap-cycles', action='store_true',
                        help='Enable snapshot cycles during build')
    parser.add_argument('-t', '--jump-snapshot', metavar='TARGET_SNAPSHOT',
                        help='Jump to target snapshot and continue build')
    parser.add_argument('-g', '--gui', metavar='GUI_TYPE',
                        help=('GUI type during build (headless, '
                              'vnc [KVM only], '
                              'separate|gui [VirtualBox only]'))
    parser.add_argument('target', metavar='TARGET',
                        help="usually basedisk or cluster")
    parser.add_argument('-p', '--provider', metavar='PROVIDER', nargs='?',
                        help='Either virtualbox (VirtualBox) or kvm (KVM)')
    parser.add_argument('--verbose', action='store_true')
    return parser.parse_args()


def set_conf_vars(args):
    """Store command line args in configuration variables"""
    logger = logging.getLogger(__name__)

    conf.verbose_console = args.verbose_console
    if conf.verbose_console:
        enable_verbose_console()

    if not args.wbatch and not args.build:
        logger.error("Neither -b nor -w given, nothing to do. Exiting.")
        sys.exit(1)

    conf.do_build = args.build
    conf.wbatch = args.wbatch

    # Arguments override configuration
    logger.debug("Provider: %s (config), %s (args)", conf.provider,
                 args.provider)
    conf.provider = args.provider or conf.provider
    conf.check_provider()
    logger.info("Using provider %s.", conf.provider)

    gui_opts = ["headless"]
    if conf.provider == "virtualbox":
        gui_opts.extend(("separate", "gui"))
        # For VirtualBox, default to headless...
        conf.vm_ui = args.gui or "headless"
        # ...unless it it is for Windows batch files
        if conf.wbatch:
            # With VirtualBox 5.1.6, console type "headless" often gives no
            # access to the VM console which on Windows is the main method
            # for interacting with the cluster. Use "separate" for Windows
            # batch files, which works at least on 5.0.26 and 5.1.6.
            if conf.vm_ui == "headless":
                conf.vm_ui = "separate"
            if args.gui == "headless":
                # headless was set by user, let them know
                logger.warning('Overriding UI type "headless" with '
                               '"separate" for Windows batch files.')
    elif conf.provider == "kvm":
        gui_opts.append("vnc")
        # For kvm, default to vnc
        conf.vm_ui = args.gui or "vnc"

    if conf.vm_ui not in gui_opts:
        logger.warning('Valid options for provider %s: %s.', conf.provider,
                       ", ".join(gui_opts))
        logger.error('Invalid gui option: "%s". Aborting.', args.gui)
        sys.exit(1)

    if os.environ.get('SNAP_CYCLE') == 'yes':
        logger.info("Picked up SNAP_CYCLE=yes from environment.")
        conf.snapshot_cycle = True

    if args.enable_snap_cycles:
        conf.snapshot_cycle = True

    if args.jump_snapshot:
        conf.jump_snapshot = args.jump_snapshot

    conf.leave_vms_running = bool(os.environ.get('LEAVE_VMS_RUNNING') == 'yes')

    wbatch.init()


def abort_if_root_user():
    if not os.geteuid():
        print("Please run this program as a regular user, not as root or"
              " with sudo. Aborting.")
        sys.exit(1)


def main():
    abort_if_root_user()

    configure_logging()
    logger = logging.getLogger(__name__)

    logger.debug("Call args: %s", sys.argv)
    logger.debug(report.get_git_info())
    args = parse_args()
    set_conf_vars(args)

    import stacktrain.core.autostart as autostart
    import stacktrain.core.node_builder as node_builder
    import stacktrain.core.functions_host as host

    # W0612: variable defined but not used
    # pylint_: disable=W0612
    # Only for the benefit of sfood
    # import stacktrain.virtualbox.install_base

    logger.debug("importing stacktrain.%s.install_base", conf.provider)
    install_base = importlib.import_module("stacktrain.%s.install_base" %
                                           conf.provider)
    logger.debug("importing stacktrain.%s.vm_create", conf.provider)
    vm = importlib.import_module("stacktrain.%s.vm_create" %
                                 conf.provider)

    vm.init()

    logger.info("stacktrain start at %s", time.strftime("%c"))

    # OS X sets LC_CTYPE to UTF-8 which results in errors when exported to
    # (remote) environments
    if "LC_CTYPE" in os.environ:
        logger.debug("Removing LC_CTYPE from environment.")
        del os.environ["LC_CTYPE"]
    # To be on the safe side, ensure a sane locale
    os.environ["LC_ALL"] = "C"

    logger.debug("Environment %s", os.environ)

    autostart.autostart_reset()

    if conf.wbatch:
        wbatch.wbatch_reset()

    if conf.do_build and not conf.leave_vms_running:
        vm.stop_running_cluster_vms()

    if conf.do_build and install_base.base_disk_exists():
        if args.target == "basedisk":
            print("Basedisk exists: %s" % conf.get_base_disk_name())
            print("\tDestroy and recreate? [y/N] ", end='')
            ans = raw_input().lower()
            if ans == 'y':
                logger.info("Deleting existing basedisk.")
                start_time = time.time()
                install_base.vm_install_base()
                logger.info("Basedisk build took %s seconds",
                            hf.fmt_time_diff(start_time))
            elif conf.wbatch:
                logger.info("Windows batch file build only.")
                tmp_do_build = conf.do_build
                conf.do_build = False
                install_base.vm_install_base()
                conf.do_build = tmp_do_build
            else:
                print("Nothing to do.")
            print("Done, returning now.")
            return
        elif conf.wbatch:
            logger.info("Windows batch file build only.")
            tmp_do_build = conf.do_build
            conf.do_build = False
            install_base.vm_install_base()
            conf.do_build = tmp_do_build
    else:
        start_time = time.time()
        install_base.vm_install_base()
        logger.info("Basedisk build took %s seconds",
                    hf.fmt_time_diff(start_time))

    if args.target == "basedisk":
        print("We are done.")
        return

    host.create_host_networks()

    start_time = time.time()
    node_builder.build_nodes(args.target)
    logger.info("Cluster build took %s seconds", hf.fmt_time_diff(start_time))

    report.print_summary()


if __name__ == "__main__":
    sys.exit(main())
