import os

import stacktrain.config.general as conf

conf.provider = "virtualbox"
conf.share_name = "osbash"
conf.share_dir = conf.top_dir
conf.vm_ui = "headless"


def get_base_disk_path():
    return os.path.join(conf.img_dir, conf.get_base_disk_name() + ".vdi")
