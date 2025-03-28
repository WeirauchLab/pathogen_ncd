"""
Jinja filter functions
"""
import os
from ..util import humansize

__all__ = ['filesize']


def filesize(filename):
    """Return filesize of given ``path`` in bytes"""
    return humansize(os.stat(filename).st_size)
