"""
Jinja filter functions

Author:   Kevin Ernst <kevin.ernst -at- cchmc.org>
License:  GPL; see LICENSE.txt in the top-level directory

© 2025 Cincinnati Children's Hospital Medical Center and the author(s)
"""
import os
from ..util import humansize

__all__ = ['filesize']


def filesize(filename):
    """Return filesize of given ``path`` in bytes"""
    return humansize(os.stat(filename).st_size)
