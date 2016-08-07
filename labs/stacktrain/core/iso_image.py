# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import importlib
import logging
import os
import sys

import stacktrain.core.helpers as hf
import stacktrain.core.download as dl
import stacktrain.config.general as conf

distro_boot = importlib.import_module("stacktrain.distros.%s" %
                                      conf.distro_full)

logger = logging.getLogger(__name__)

conf.iso_image = distro_boot.ISOImage()

# -----------------------------------------------------------------------------
# Functions to get install ISO images
# -----------------------------------------------------------------------------


def iso_image_okay(iso_path):
    if os.path.isfile(iso_path):
        logger.debug("There is a file at given path:\n\t%s", iso_path)
        if md5_match(iso_path, conf.iso_image.md5):
            return True
        else:
            logger.warning("ISO image corrupt, removing:\n\t%s", iso_path)
            os.remove(iso_path)
    else:
        logger.warning("There is no file at given path:\n\t%s", iso_path)
    return False


def download_and_check(iso_path):
    if iso_image_okay(iso_path):
        logger.info("ISO image okay.")
        return True

    logger.info("Downloading\n\t%s\n\tto %s", conf.iso_image.url, iso_path)
    logger.info("This may take a while.")
    try:
        dl.downloader.download(conf.iso_image.url, iso_path)
        logger.info("Download succeeded.")
    except EnvironmentError:
        logger.warning("Download failed.")
        return False

    return iso_image_okay(iso_path)


def find_install_iso():
    iso_path = os.path.join(conf.img_dir, conf.iso_image.name)

    if download_and_check(iso_path):
        return iso_path

    logger.warn("Unable to get ISO image, trying to update URL.")

    conf.iso_image.update_iso_image_variables()
    iso_path = os.path.join(conf.img_dir, conf.iso_image.name)

    if download_and_check(iso_path):
        return iso_path

    logger.error("Download failed for:\n\t%s", conf.iso_image.url)
    sys.exit(1)


def md5_match(path, correct_md5):

    import hashlib
    with open(path, 'rb') as ff:
        hasher = hashlib.md5()
        while True:
            buf = ff.read(2**24)
            if not buf:
                break
            hasher.update(buf)
    actual_md5 = hasher.hexdigest()
    logger.debug("MD5 correct %s, actual %s", correct_md5, actual_md5)
    if correct_md5 == actual_md5:
        logger.debug("MD5 sum matched.")
        return True
    else:
        logger.warn("MD5 sum did not match.")
        return False
