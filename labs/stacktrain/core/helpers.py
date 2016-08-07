# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import errno
import logging
import os
import re
import subprocess
import sys
import time

logger = logging.getLogger(__name__)


def strip_top_dir(root_path_to_remove, full_path):
    if re.match(root_path_to_remove, full_path):
        return os.path.relpath(full_path, root_path_to_remove)
    else:
        # TODO error handling
        logger.error("Cannot strip path\n\t%s\n\tfrom\n\t%s", full_path,
                     root_path_to_remove)
        sys.exit(1)


def create_dir(dir_path):
    """Create directory (including parents if necessary)."""
    try:
        os.makedirs(dir_path)
    except OSError as err:
        if err.errno == errno.EEXIST and os.path.isdir(dir_path):
            pass
        else:
            raise


def clean_dir(dir_path):
    """Non-recursive removal of all files except README.*"""
    if not os.path.exists(dir_path):
        create_dir(dir_path)
    elif not os.path.isdir(dir_path):
        logging.error("This is not a directory: %s", dir_path)
        # TODO error handling
        raise Exception

    dir_entries = os.listdir(dir_path)
    for dir_entry in dir_entries:
        path = os.path.join(dir_path, dir_entry)
        if os.path.isfile(path):
            if not re.match(r'README.', dir_entry):
                os.remove(path)
    # files = [ f for f in os.listdir(dir_path) if
    #          os.path.isfile(os.path.join(dir_path, f))]


def fmt_time_diff(start, stop=None):
    stop = stop or time.time()
    return "%3d" % round(stop - start)


def wait_for_ping(ip):
    logger.debug("Waiting for ping returning from %s.", ip)
    devnull = open(os.devnull, 'w')
    while True:
        try:
            subprocess.call(["ping", "-c1", ip],
                            stdout=devnull, stderr=devnull)
            break
        except subprocess.CalledProcessError:
            time.sleep(1)
            print(".")
    logger.debug("Got ping reply from %s.", ip)


def ip_to_gateway(ip):
    return remove_last_octet(ip) + '1'


def ip_to_net_address(ip):
    return remove_last_octet(ip) + '0'


def remove_last_octet(ip):
    ma = re.match(r'(\d+\.\d+.\d+\.)\d+', ip)
    if ma:
        return ma.group(1)
    else:
        raise ValueError


def test_exe(*args):
    devnull = open(os.devnull, 'w')

    try:
        # subprocess.call(args.split(' '), stdout=devnull, stderr=devnull)
        subprocess.call(args, stdout=devnull, stderr=devnull)
    except OSError:
        return False

    return True
