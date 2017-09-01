from __future__ import print_function

import collections
import logging
from os.path import dirname, join, realpath
import os
import platform
import re
import sys

import stacktrain.core.download as dl
import stacktrain.core.helpers as hf

logger = logging.getLogger(__name__)

do_build = False
wbatch = False

vm = {}

vm_ui = "gui"

# Default access method is ssh; Windows batch files use shared folders instead
vm_access = "ssh"

# If set, scripts before this snapshot are skipped
jump_snapshot = None

# -----------------------------------------------------------------------------


def check_provider():
    if provider == "virtualbox":
        if do_build and not hf.test_exe("VBoxManage", "-v"):
            logger.error("VBoxManage not found. Is VirtualBox installed?")
            logger.error("Aborting.")
            sys.exit(1)
    elif provider == "kvm":
        if platform.uname()[0] != "Linux":
            logger.error("Provider kvm only supported on Linux. Aborting.")
            sys.exit(1)
        if not hf.test_exe("virsh", "-v"):
            logger.error("virsh not found. Aborting.")
            sys.exit(1)
        if wbatch:
            logger.error("Cannot build Windows batch files with provider kvm."
                         "Aborting.")
            sys.exit(1)
    else:
        logger.error("Unknown provider: %s", provider)
        logger.error("Aborting.")
        sys.exit(1)

# -----------------------------------------------------------------------------


def remove_quotation_marks(line):
    """Removes single or double quotation marks"""
    # Remove quotation marks (if any)
    ma = re.search(r"(?P<quote>['\"])(.+)(?P=quote)", line)
    if ma:
        line = ma.group(2)
    return line


class CfgFileParser(object):
    def __init__(self, cfg_file):
        self.file_path = os.path.join(config_dir, cfg_file)

        self.cfg_vars = {}
        with open(self.file_path) as cfg:
            for line in cfg:
                if re.match(r"^\s*$", line):
                    # Line contains only white space
                    continue
                ma = re.match(r"^: \${(\S+):=(.*)}$", line)
                if ma:
                    # Special bash config style syntax
                    # e.g., ": ${OPENSTACK_RELEASE=mitaka}"
                    key = ma.group(1)
                    value = remove_quotation_marks(ma.group(2))
                    self.cfg_vars[key] = value
                    continue
                if re.match(r"^(#|:)", line):
                    # Line starts with comment
                    continue
                ma = re.match(r"^(\S+)=(.*)$", line)
                if ma:
                    key = ma.group(1)
                    value = remove_quotation_marks(ma.group(2))
                    self.cfg_vars[key] = value

    def get_value(self, var_name):
        """Return value for given key (or None if it does not exist)"""
        try:
            return self.cfg_vars[var_name]
        except KeyError:
            return None

    def get_numbered_value(self, var_name_root):
        """Return dictionary of key:value pairs where key starts with arg"""
        pairs = {}
        for key in self.cfg_vars:
            if key.startswith(var_name_root):
                key_id = key.replace(var_name_root, "")
                value = self.cfg_vars[key]
                pairs[key_id] = value
        return pairs


# -----------------------------------------------------------------------------
# top_dir is training-labs/labs
top_dir = dirname(dirname(dirname(realpath(__file__))))

# Parsing osbash's config/paths is not worth it; neither is having these
# paths in a config file for users to change
img_dir = join(top_dir, "img")
log_dir = join(top_dir, "log")
status_dir = join(log_dir, "status")

osbash_dir = join(top_dir, "osbash")
config_dir = join(top_dir, "config")
scripts_dir = join(top_dir, "scripts")
autostart_dir = join(top_dir, "autostart")
lib_dir = join(top_dir, "lib")

# -----------------------------------------------------------------------------
# config/localrc
cfg_localrc = CfgFileParser("localrc")
vm_proxy = cfg_localrc.get_value("VM_PROXY")
dl.downloader.vm_proxy = vm_proxy

provider = cfg_localrc.get_value("PROVIDER")
logger.debug("Checking provider given by config/localarc: %s", provider)
check_provider()
distro_full = cfg_localrc.get_value("DISTRO")
# ubuntu-14.04-server-amd64 -> ubuntu_14_04_server_amd64
distro_full = re.sub(r'[-.]', '_', distro_full)

# -----------------------------------------------------------------------------
# config/deploy.osbash
cfg_deploy_osbash = CfgFileParser("deploy.osbash")
vm_shell_user = cfg_deploy_osbash.get_value("VM_SHELL_USER")

# -----------------------------------------------------------------------------
# config/credentials
cfg_credentials = CfgFileParser("credentials")
admin_user = cfg_credentials.get_value("ADMIN_USER_NAME")
admin_password = cfg_credentials.get_value("ADMIN_PASS")
demo_user = cfg_credentials.get_value("DEMO_USER_NAME")
demo_password = cfg_credentials.get_value("DEMO_PASS")

# -----------------------------------------------------------------------------
# config/openstack
cfg_openstack = CfgFileParser("openstack")
openstack_release = cfg_openstack.get_value("OPENSTACK_RELEASE")
pxe_initial_node_ip = cfg_openstack.get_value("PXE_INITIAL_NODE_IP")

# Get all variables starting with NETWORK_
networks_cfg = cfg_openstack.get_numbered_value("NETWORK_")

# Network order matters (the cluster should work either way, but the
# networks may end up assigned to different interfaces)
networks = collections.OrderedDict()

for index, value in networks_cfg.items():
    ma = re.match(r'(\S+)\s+([\.\d]+)', value)
    if ma:
        name = ma.group(1)
        address = ma.group(2)
        networks[name] = address
    else:
        logger.error("Syntax error in NETWORK_%s: %s", index, value)
        sys.exit(1)

# -----------------------------------------------------------------------------
snapshot_cycle = False

# Base disk size in MB
base_disk_size = 10000

distro = ""


def get_base_disk_name():
    return "base-{}-{}-{}".format(vm_access, openstack_release,
                                  iso_image.release_name)


class VMconfig(object):

    def __init__(self, vm_name):
        self.vm_name = vm_name
        self.disks = []
        self._ssh_ip = None
        self._ssh_port = None
        self.http_port = None
        self.get_config_from_file()
        # Did this run already update VM's config, lib directories?
        self.updated = False
        self.pxe_tmp_ip = None
        if provider == "virtualbox":
            # TODO is IPaddress class worth using?
            # self._ssh_ip = IPaddress("127.0.0.1")
            self._ssh_ip = "127.0.0.1"
        elif provider == "kvm":
            # Override whatever we got from config file
            self._ssh_port = 22
        else:
            logger.error("No provider defined. Aborting.")
            sys.exit(1)
        logger.debug(self.__repr__())

    def __repr__(self):
        repr = "<VMconfig: vm_name=%r" % self.vm_name
        repr += " disks=%r" % self.disks
        repr += " ssh_ip=%r" % self.ssh_ip
        repr += " ssh_port=%r" % self.ssh_port
        if self.pxe_tmp_ip:
            repr += " pxe_tmp_ip=%r" % self.pxe_tmp_ip
            repr += " _ssh_port=%r" % self._ssh_port
            repr += " _ssh_ip=%r" % self._ssh_ip
        repr += " http_port=%r" % self.http_port
        repr += " vm_mem=%r" % self.vm_mem
        repr += " vm_cpus=%r" % self.vm_cpus
        repr += " net_ifs=%r" % self.net_ifs
        repr += ">"
        return repr

    def get_config_from_file(self):
        cfg_vm = CfgFileParser("config." + self.vm_name)

        if provider == "virtualbox":
            # Port forwarding only on VirtualBox
            self._ssh_port = cfg_vm.get_value("VM_SSH_PORT")
            if self._ssh_port:
                logger.debug("Port forwarding ssh: %s", self._ssh_port)

            self.http_port = cfg_vm.get_value("VM_WWW_PORT")
            if self.http_port:
                logger.debug("Port forwarding http: %s", self.http_port)

        self.vm_mem = cfg_vm.get_value("VM_MEM") or 512
        self.vm_cpus = cfg_vm.get_value("VM_CPUS") or 1

        net_if_cfg = cfg_vm.get_numbered_value("NET_IF_")

        # Create array of required size
        self.net_ifs = [{} for _ in range(len(net_if_cfg))]

        for key in net_if_cfg:
            self._parse_net_line(int(key), net_if_cfg[key])

        # If the size of the first disk is given, it's not using the base
        # disk (i.e. probably building via PXE booting)
        self.disks.append(cfg_vm.get_value("FIRST_DISK_SIZE") or "base")
        logger.debug("Disks: %s", self.disks[-1])

        self.disks.append(cfg_vm.get_value("SECOND_DISK_SIZE"))
        if self.disks[1]:
            logger.debug("      %s", self.disks[1])

        self.disks.append(cfg_vm.get_value("THIRD_DISK_SIZE"))
        if self.disks[2]:
            logger.debug("       %s", self.disks[2])

    def _parse_net_line(self, index, line):
        args = re.split(r'\s+', line)
        self.net_ifs[index]["typ"] = args[0]

        if len(args) > 1:
            self.net_ifs[index]["ip"] = args[1]

        if len(args) > 2:
            self.net_ifs[index]["prio"] = args[2]
        else:
            self.net_ifs[index]["prio"] = 0

    @property
    def ssh_ip(self):
        return self.pxe_tmp_ip or self._ssh_ip

    @ssh_ip.setter
    def ssh_ip(self, value):
        self._ssh_ip = value

    # TODO make all callers expect int, not str
    @property
    def ssh_port(self):
        return "22" if self.pxe_tmp_ip else self._ssh_port

    @ssh_port.setter
    def ssh_port(self, value):
        self._ssh_port = int(value)


class IPaddress(object):
    def __init__(self, ip):
        self.ip = ip

    def __repr__(self):
        return "<IPaddress ip=%s>" % self.ip

    def __str__(self):
        return self.ip

    @property
    def network(self):
        """Return /24 subnet address"""
        return self.remove_last_octet(self.ip) + '0'

#    @c_class_network.setter
#    def c_class_network(self, network):
#        self._ssh_ip = ssh_ip

    def same_c_class_network(self, ip):
        return self.remove_last_octet(self.ip) == self.remove_last_octet(ip)

    @staticmethod
    def remove_last_octet(ip):
        ma = re.match(r'(\d+\.\d+.\d+\.)\d+', ip)
        if ma:
            return ma.group(1)
        else:
            raise ValueError
