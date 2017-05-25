"""

This library contains the functions that allow stacktrain to produce
Windows batch files.

"""

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import logging
import io
import ntpath
import os
import re

from string import Template
from shutil import copyfile

import stacktrain.config.general as conf
import stacktrain.core.helpers as hf

logger = logging.getLogger(__name__)

WBATCH_OUT_DIR = os.path.join(conf.top_dir, "wbatch")
# wbatch template dir
TPLT_DIR = os.path.join(conf.top_dir, "stacktrain/batch_for_windows_templates")

OUT_FILE = None


def wbatch_reset():
    """Clean Windows batch directory"""
    hf.clean_dir(WBATCH_OUT_DIR)
    copyfile(os.path.join(TPLT_DIR, "config_bat"),
             os.path.join(WBATCH_OUT_DIR, "config.bat"))

def init():
    """Initialize variables and directory for Windows batch script creation"""
    if conf.wbatch:
        if hasattr(conf, 'vm_access') and conf.vm_access == "all":
            logging.info("Already configured for shared folder access.")
        else:
            logging.info("Setting vm_access method to shared folder.")
            conf.vm_access = "shared_folder"
    else:
        logging.debug("Not building Windows batch files.")

    wbatch_reset()


def wbatch_new_file(file_name):
    """Create new Windows batch file"""
    global OUT_FILE

    hf.create_dir(WBATCH_OUT_DIR)
    OUT_FILE = os.path.join(WBATCH_OUT_DIR, file_name)
    open(OUT_FILE, "a").close()


def wbatch_close_file():
    global OUT_FILE

    OUT_FILE = None

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


class WbatchTemplate(Template):
    # Default delimiter "$" occurs directly after backslash (in Windows paths)
    delimiter = '#'
    idpattern = r'[A-Z][_A-Z0-9]*'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Note: Windows batch scripts with LF may seem to work, but (for instance) jump
#       labels don't work properly


def wbatch_write(*args):
    if OUT_FILE:
        with io.open(OUT_FILE, 'a', newline='\r\n') as out:
            try:
                string = unicode(*args).rstrip()
                out.write(string + "\n")
            except TypeError:
                logging.error("wbatch can't print %s: %s", type(str(*args)),
                              str(*args))
                logging.exception("Exception")
                import sys
                sys.exit(1)


def wbatch_write_template(template, replace=None):
    if replace is None:
        replace = {}

    with open(os.path.join(TPLT_DIR, template)) as tf:
        for line in tf:
            te = WbatchTemplate(line)
            wbatch_write(te.substitute(replace))

# -----------------------------------------------------------------------------
# Batch function calls
# -----------------------------------------------------------------------------


def wbatch_abort_if_vm_exists(vm_name):
    te = WbatchTemplate(u"CALL :vm_exists #VM_NAME")
    wbatch_write(te.substitute(VM_NAME=vm_name))


def wbatch_wait_poweroff(vm_name):
    te = WbatchTemplate(u"""ECHO %time% Waiting for VM #VM_NAME to power off.
CALL :wait_poweroff #VM_NAME
ECHO %time% VM #VM_NAME powered off.
""")
    wbatch_write(te.substitute(VM_NAME=vm_name))


def wbatch_wait_auto():
    te = WbatchTemplate(u"""ECHO %time% Waiting for autostart files to execute.
CALL :wait_auto
ECHO %time% All autostart files executed.
""")
    wbatch_write(te.substitute())

# -----------------------------------------------------------------------------
# Batch commands
# -----------------------------------------------------------------------------


def wbatch_delete_disk(disk_path):
    disk_name = os.path.basename(disk_path)
    te = WbatchTemplate(r"IF EXIST %IMGDIR%\#DISK DEL %IMGDIR%\#DISK")
    wbatch_write(te.substitute(DISK=disk_name))


def wbatch_rename_disk(src_name, target_name):
    te = WbatchTemplate(r"MOVE /y %IMGDIR%\#SRC %IMGDIR%\#TARGET")
    wbatch_write(te.substitute(SRC=src_name, TARGET=target_name))


def wbatch_cp_auto(src_path, target_path):
    src = wbatch_path_to_windows(src_path)
    target = os.path.basename(target_path)
    te = WbatchTemplate(r"COPY %TOPDIR%\#SRC %AUTODIR%\#TARGET")
    wbatch_write(te.substitute(SRC=src, TARGET=target))


def wbatch_sleep(seconds):
    te = WbatchTemplate(r"TIMEOUT /T #SECONDS /NOBREAK")
    wbatch_write(te.substitute(SECONDS=seconds))

# -----------------------------------------------------------------------------
# Templated parts
# -----------------------------------------------------------------------------


def wbatch_file_header(product):
    replace = {"PRODUCT": product}
    wbatch_write_template("template-file_header_bat", replace)


def wbatch_end_file():
    wbatch_write_template("template-end_file_bat")
    wbatch_close_file()


def wbatch_elevate_privileges():
    wbatch_write_template("template-elevate_privs_bat")


def wbatch_find_vbm():
    wbatch_write_template("template-find_vbm_bat")


def wbatch_mkdirs():
    autodir = wbatch_path_to_windows(conf.autostart_dir)
    imgdir = wbatch_path_to_windows(conf.img_dir)
    logdir = wbatch_path_to_windows(conf.log_dir)
    statusdir = wbatch_path_to_windows(conf.status_dir)
    replace = {"AUTODIR": autodir,
               "IMGDIR":  imgdir,
               "LOGDIR": logdir,
               "STATUSDIR": statusdir}
    wbatch_write_template("template-mkdirs_bat", replace)


def wbatch_begin_hostnet():
    wbatch_new_file("create_hostnet.bat")
    wbatch_file_header("host-only networks")
    wbatch_write_template("template-begin_hostnet_bat")
    # Creating networks requires elevated privileges
    wbatch_elevate_privileges()
    wbatch_find_vbm()


def wbatch_create_hostnet(if_ip, adapter):
    replace = {"IFNAME": adapter,
               "IFIP": if_ip}
    wbatch_write_template("template-create_hostnet_bat", replace)


def wbatch_begin_base():
    # Disable E1101 (no-member) in pylint
    iso_name = os.path.basename(conf.iso_image.name)  # pylint: disable=E1101
    if not iso_name:
        logging.error("Windows batch file needs install ISO URL.")
        raise ValueError

    wbatch_new_file("create_base.bat")
    wbatch_file_header("base disk")
    wbatch_find_vbm()
    wbatch_mkdirs()
    replace = {"INSTALLFILE": conf.iso_image.name,  # pylint: disable=no-member
               "ISOURL": conf.iso_image.url}        # pylint: disable=no-member
    wbatch_write_template("template-begin_base_bat", replace)


def wbatch_begin_node(node_name):
    wbatch_new_file("create_{}_node.bat".format(node_name))
    wbatch_file_header("{} VM".format(node_name))
    wbatch_find_vbm()
    wbatch_mkdirs()
    basedisk = "{}.vdi".format(conf.get_base_disk_name())

    replace = {"BASEDISK": basedisk}
    wbatch_write_template("template-begin_node_bat", replace)


# -----------------------------------------------------------------------------
# VBoxManage call handling
# -----------------------------------------------------------------------------

def wbatch_log_vbm(*args):
    argl = list(*args)
    for index, arg in enumerate(argl):
        if re.match("--hostonlyadapter", arg):
            # The next arg is the host-only interface name -> change it.
            # We use the vboxnet interface name as a variable name for the
            # Windows batch scripts. This is a reference to the variable,
            # therefore the string must be somethin like "%vboxnet0%".
            argl[index+1] = '"' + "%{}%".format(argl[index+1]) + '"'
        elif re.match("--hostpath", arg):
            # The next arg is the shared dir -> change it
            argl[index+1] = r'%SHAREDIR%'
        elif re.search(r"\.(iso|vdi)$", arg):
            # Fix path of ISO or VDI image
            img_name = os.path.basename(arg)
            argl[index] = ntpath.join("%IMGDIR%", img_name)

    # Have Windows echo what we are about to do
    wbatch_write("ECHO VBoxManage " + " ". join(argl))

    wbatch_write('"%VBM%" ' + " ". join(argl))

    # Abort if VBoxManage call raised errorlevel
    wbatch_write("IF %errorlevel% NEQ 0 GOTO :vbm_error")

    # Blank line for readability
    wbatch_write()

# -----------------------------------------------------------------------------
# Windows path name helpers
# -----------------------------------------------------------------------------


def wbatch_path_to_windows(full_path):
    rel_path = hf.strip_top_dir(conf.top_dir, full_path)

    # Convert path to backslash-type as expected by Windows batch files
    rel_path = ntpath.normpath(rel_path)
    return rel_path
