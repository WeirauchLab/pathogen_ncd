"""
Jinja filter functions

Author:   Kevin Ernst <kevin.ernst -at- cchmc.org>
License:  GPL; see LICENSE.txt in the top-level directory

© 2025 Cincinnati Children's Hospital Medical Center and the author(s)
"""
import os
from ..util import humansize

__all__ = ['filesize', 'slugify']


def filesize(filename):
    """Return filesize of given ``path`` in bytes"""
    return humansize(os.stat(filename).st_size)

def slugify(title):
    """Return a slugified title, for use as an anchor href"""
    import re
    slug = re.sub(r'\s+', '-', title.lower())
    slug = re.sub(r'[^[:alnum:]]', '', slug)
    return slug
