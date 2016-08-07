#!/usr/bin/env python

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import os

class GenericISOImage(object):
    """Base class for ISO images"""

    def __init__(self):
        self.url_base = None
        self.name = None
        self.md5 = None

    @property
    def url(self):
        """"Return path to ISO image"""
        return os.path.join(self.url_base, self.name)

    @url.setter
    def url(self, url):
        """Update url_base and name based on new URL"""
        self.url_base = os.path.dirname(url)
        self.name = os.path.basename(url)
