"""
Utility functions that don't fit in any other bin
"""
import os
import logging

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


def ansi(code):
    """ Generates an ANSI escape code """
    return f"\033[{code}m"


GREEN = ansi(32)
BLUE = ansi(34)
BOLD = ansi(1)
UL = ansi(4)
RESET = ansi(0)
BOLDGREEN = ansi('1;32')
BOLDBLUE = ansi('1;34')
BOLDUL = ansi('1;4')


def humansize(bytesize):
    if bytesize % 1024 == bytesize:
        return bytesize
    if bytesize % 1024**2 == bytesize:
        return "{:0.1f} KiB".format(bytesize / 1024)
    if bytesize % 1024**3 == bytesize:
        return "{:0.1f} MiB".format(bytesize / 1024**2)
    if bytesize % 1024**4 == bytesize:
        return "{:0.1f} GiB".format(bytesize / 1024**3)
    return "{:0.1f} TiB".format(bytesize / 1024**4)


class pushd:
    """
    Context manager for changing into a directory to do some stuff, then
    returning to the previous one.
    """
    def __init__(self, newdir):
        self.olddir = os.getcwd(); self.newdir = newdir
    def __enter__(self):
        logger.debug(f"Entering into '{self.newdir}'…")
        os.chdir(self.newdir)
    def __exit__(self, exc_type, exc_value, traceback):
        os.chdir(self.olddir)
        logger.debug(f"Left '{self.newdir}'; c.w.d. is now '{self.olddir}'.")
