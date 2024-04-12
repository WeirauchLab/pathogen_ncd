##
##  Utility functions that don't fit in any other bin
##

from .config import use_config


def ansi(code):
    """ Generates an ANSI escape code """
    return f"\033[{code}m"


@use_config
def make_help(makefile='Makefile', config=None):
    """
    Scan through a `Makefile` passed as the first argument and automatically
    generate help for each target found
    """
    import re

    BLUE = ansi(34)
    BOLD = ansi(1)
    UL = ansi(4)
    RESET = ansi(0)
    BOLDBLUE = ansi('1;34')
    BOLDUL = ansi('1;4')

    maxlen = 0
    groups = {}
    targets = []

    with open(makefile, 'r') as f:
        for line in f.readlines():
            titlematch = re.match(r'.*TITLE\s+=\s+(.*)', line)
            groupmatch = re.match(r'^(\w+):.*?# +\[(\w+)\] +(.*)$$', line)
            match = re.match(r'^(\w+):.*?# +(.*)$$', line)

            if titlematch:
                title = titlematch.group(1).strip()
                # bold and underline
                print("\n  %s%s%s\n" % (BOLDUL, title, RESET))
            if groupmatch:
                target, group, help = groupmatch.groups()
                if len(target) > maxlen:
                    maxlen = len(target)
                if not groups.get(group): groups[group] = []
                groups[group].append((target, help))
            elif match:
                target, help = match.groups()
                if len(target) > maxlen:
                    maxlen = len(target)
                targets.append((target, help))

        # 4 spaces, target name right-padded to the max width of any target,
        # 4 spaces, then the help
        fmt = f"    {BOLDBLUE}%-{str(maxlen)}s{RESET}    %s"

        if targets:
            for t in targets:
                print(fmt % (t[0], t[1]))
        if groups:
            for g in groups:
                print(f"\n  [{g}]")
                for t in groups[g]:
                    print(fmt % (t[0], t[1]))

    print(f"\n  {config['site']['sourceurl']}\n")

# vim: sw=4 ts=4 expandtab
