from .config import use_config
from .util import BLUE, BOLD, BOLDUL, BOLDBLUE, RESET


@use_config
def make_help(makefile=None, config=None):
    """
    Scan through a `Makefile` passed as the first argument and automatically
    generate help for each target found
    """
    import re
    maxlen = 0
    groups = {}
    targets = []

    if not makefile:
        makefile = 'Makefile'

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

    print("\n  Problems? Try 'make -B [targetname]' to force a target to rebuild.")
    print(f"\n  Source + issues:\n    {config['site']['sourceurl']}\n")


if __name__ == '__main__':
    import os, sys
    if len(sys.argv) == 2 and os.path.exists(sys.argv[1]):
        make_help(sys.argv[1])
    else:
        make_help()

