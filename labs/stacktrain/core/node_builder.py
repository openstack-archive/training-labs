import stacktrain.config.general as conf
import stacktrain.core.autostart as autostart
import stacktrain.batch_for_windows as wbatch


def build_nodes(cluster_cfg):
    config_name = "{}_{}".format(conf.distro, cluster_cfg)

    if conf.wbatch:
        wbatch.wbatch_begin_node(config_name)

    autostart.autostart_reset()
    autostart.autostart_from_config("scripts." + config_name)

    if conf.wbatch:
        wbatch.wbatch_end_file()
