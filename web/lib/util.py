"""
Utility functions that don't fit in any other bin
"""
def ansi(code):
    """ Generates an ANSI escape code """
    return f"\033[{code}m"


BLUE = ansi(34)
BOLD = ansi(1)
UL = ansi(4)
RESET = ansi(0)
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


def filesize(filename):
    """ Return filesize of given ``path`` in bytes """
    import os
    return humansize(os.stat(filename).st_size)

# vim: sw=4 ts=4 expandtab
