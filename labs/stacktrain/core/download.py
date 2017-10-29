# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import httplib
import logging
import os
import urllib2

import stacktrain.core.helpers as hf

logger = logging.getLogger(__name__)


class Downloader(object):

    def __init__(self):
        self._vm_proxy = None

    def get_urllib_proxy(self):
        res = None
        if urllib2._opener:  # pylint: disable=protected-access
            for handler in urllib2._opener.handlers:  # pylint: disable=W0212
                if isinstance(handler, urllib2.ProxyHandler):
                    logger.debug("get_urllib_proxy proxies: %s",
                                 handler.proxies)
                    res = handler.proxies
        logger.debug("get_urllib_proxy proxies: %s", res)
        return res

    @property
    def vm_proxy(self):
        logger.debug("Downloader getter vm_proxy %s (proxy: %s)",
                     self._vm_proxy, self.get_urllib_proxy())
        return self._vm_proxy

    @vm_proxy.setter
    def vm_proxy(self, value):
        if value:
            self._vm_proxy = value
            proxy_handler = urllib2.ProxyHandler({'http': self._vm_proxy})
        else:
            # Remove existing proxy setting
            logger.debug("Downloader unsetting vm_proxy.")
            proxy_handler = urllib2.ProxyHandler({})
            self._vm_proxy = None
        urllib2.install_opener(urllib2.build_opener(proxy_handler))
        logger.debug("Proxy now: %s", self.get_urllib_proxy())

    def download(self, url, target_path=None):
        try:
            logger.debug("Trying to download: %s to %s", url, target_path)
            logger.debug("Proxy: %s", self.get_urllib_proxy())
            response = urllib2.urlopen(url)
            if target_path:
                # Make sure target directory exits
                hf.create_dir(os.path.dirname(target_path))

                with open(target_path, 'wb') as out:
                    try:
                        out.write(response.read())
                    except urllib2.URLError as err:
                        # Download failed, remove empty file
                        os.remove(target_path)
            else:
                return response.read()
        except (urllib2.URLError, httplib.BadStatusLine) as err:
            logger.debug("download() failed, %s for %s", type(err), url)
            raise EnvironmentError

downloader = Downloader()
