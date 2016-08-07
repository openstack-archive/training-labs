import time
import stacktrain.config.general as conf

import stacktrain.batch_for_windows as wbatch

# -----------------------------------------------------------------------------
# Conditional sleeping
# -----------------------------------------------------------------------------


def conditional_sleep(seconds):
    # Don't sleep if we are just faking it for wbatch
    if conf.do_build:
        time.sleep(seconds)

    if conf.wbatch:
        wbatch.wbatch_sleep(seconds)
