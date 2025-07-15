"""
Functions that get invoked and registered as globals in the Jinja template
environment

Author:   Kevin Ernst <kevin.ernst -at- cchmc.org>
License:  GPL; see LICENSE.txt in the top-level directory

© 2025 Cincinnati Children's Hospital Medical Center and the author(s)
"""
import os
from ..util import pushd

__all__ = ['gitinfo']
# how many parent directories to search looking for `.git`
GIT_CHECK_ANCESTORS = 2


def find_git_dir(ancestors=GIT_CHECK_ANCESTORS):
    """
    Recursively search c.w.d. and up to GIT_CHECK_ANCESTORS ancestor
    directories looking for a `.git` directory. Return the first found.

    :param int ancestors: how many ancestor directories to check
    :rtype: tuple
    """
    if not ancestors:
        raise FileNotFoundError(
            f"Found no `.git` directory in c.w.d. or {GIT_CHECK_ANCESTORS} "
            "ancestor directories"
        )
    if os.path.isdir('.git'):
        return os.path.abspath('.git')
    else:
        with pushd('..'):
            return find_git_dir(ancestors - 1)

def gitinfo(hashlen=7):
    """
    Return a tuple of Git branch information: branch name followed by the SHA1
    hash
    """
    try:
        gitdir = find_git_dir()
    except FileNotFoundError:
        return ('.git dir not found', None)

    with open(os.path.join(gitdir, 'HEAD')) as h:
        ref = h.readline().split(':')[1].strip()
        with open(os.path.join(gitdir, ref)) as r:
            sha1 = r.readline()

    return (ref.split('/')[-1], sha1[:hashlen])
