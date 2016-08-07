#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import logging
import os
import re
import sys

import stacktrain.core.cond_sleep as cs
import stacktrain.core.download as dl
import stacktrain.core.keycodes as kc
import stacktrain.config.general as conf
import stacktrain.distros.distro as distro

logger = logging.getLogger(__name__)

conf.base_install_scripts = "scripts.ubuntu_base"
conf.distro = "ubuntu"

# -----------------------------------------------------------------------------
# Installation from ISO image
# -----------------------------------------------------------------------------


class ISOImage(distro.GenericISOImage):

    def __init__(self):
        super(ISOImage, self).__init__()
        self.release_name = "ubuntu-14.04-amd64"
        self.url = ("http://releases.ubuntu.com/14.04/"
                    "ubuntu-14.04.4-server-amd64.iso")
        self.md5 = "2ac1f3e0de626e54d05065d6f549fa3a"

    # Fallback function to find current ISO image in case the file in ISO_URL
    # is neither on the disk nor at the configured URL. This mechanism was
    # added because old Ubuntu ISOs are removed from the server as soon as a
    # new ISO appears.

    def update_iso_image_variables(self):

        # Get matching line from distro repo's MD5SUMS file, e.g.
        # "9e5fecc94b3925bededed0fdca1bd417 *ubuntu-14.04.3-server-amd64.iso"
        md5_url = os.path.join(self.url_base, "MD5SUMS")
        logger.debug("About to download MD5SUM from %s", md5_url)
        try:
            txt = dl.downloader.download(md5_url)
        except EnvironmentError:
            logger.error("Can't find newer ISO image. Aborting.")
            sys.exit(1)

        ma = re.search(r"(.*) \*{0,1}(.*server-amd64.iso)", txt)
        if ma:
            self.md5 = ma.group(1)
            self.name = ma.group(2)
            logger.info("Using new ISO image:\n\t%s\n\t%s", self.name,
                        self.md5)
        else:
            logger.error("Failed to update ISO location. Exiting.")
            sys.exit(1)

        logger.info("New ISO URL:\n\t%s", self.url)

PRESEED_HOST_DIR = ("http://git.openstack.org/cgit/openstack/training-labs/"
                    "plain/labs/osbash/lib/osbash/netboot/")

PRESEED_URL = {}
PRESEED_URL['ssh'] = PRESEED_HOST_DIR + "preseed-ssh-v4.cfg"
PRESEED_URL['shared_folder'] = PRESEED_HOST_DIR + "preseed-vbadd.cfg"
PRESEED_URL['all'] = PRESEED_HOST_DIR + "preseed-all-v2.cfg"

# Arguments for ISO image installer
_BOOT_ARGS = ("/install/vmlinuz"
              " noapic"
              " preseed/url=%s"
              " debian-installer=en_US"
              " auto=true"
              " locale=en_US"
              " hostname=osbash"
              " fb=false"
              " debconf/frontend=noninteractive"
              " keyboard-configuration/modelcode=SKIP"
              " initrd=/install/initrd.gz"
              " console-setup/ask_detect=false")

# ostype used by VirtualBox to choose icon and flags (64-bit, IOAPIC)
conf.vbox_ostype = "Ubuntu_64"


def distro_start_installer(config):
    """Boot the ISO image operating system installer"""

    preseed = PRESEED_URL[conf.vm_access]

    logger.debug("Using %s", preseed)

    boot_args = _BOOT_ARGS % preseed

    if conf.vm_proxy:
        boot_args += " mirror/http/proxy=%s http_proxy=%s" % (conf.vm_proxy,
                                                              conf.vm_proxy)

    kc.keyboard_send_escape(config.vm_name)
    kc.keyboard_send_escape(config.vm_name)
    kc.keyboard_send_enter(config.vm_name)

    cs.conditional_sleep(1)

    logger.debug("Pushing boot command line: %s", boot_args)
    kc.keyboard_send_string(config.vm_name, boot_args)

    logger.info("Initiating boot sequence for %s.", config.vm_name)
    kc.keyboard_send_enter(config.vm_name)
