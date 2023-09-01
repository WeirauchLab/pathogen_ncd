##
##  Print help for Makefile targets in the file given as argv[1]
##
##  (I like the Perl version better)
##

def load_config(configs=None):
    """ load TOML configs and return dict of them all merged together """
    import re, sys, pprint, tomli

    cfg = {}
    idx = {}

    if configs is None:
        configs = { 'site': 'site.toml', 'pub': 'publication.toml' }
    for name, configfile in configs.items():
        cfg[name] = tomli.load(open(configfile, 'rb'))

    def interpolate(x):
        """ Simple, sequential interpolation of `{keyname}`s """
        if isinstance(x, dict):
            for k, v in x.items():
                if isinstance(v, (dict, list)):
                    interpolate(v)
                else:
                    if isinstance(v, str):
                        m = re.search(r'{(.*)}', v)
                        if m and idx.get(m[1]):
                            x[k] = v.replace(f"{{{m[1]}}}", idx[m[1]])
                    idx[k] = str(v)
        elif isinstance(x, list):
            for i in x:
                if isinstance(i, dict):
                    interpolate(i)

    interpolate(cfg)
    return cfg


def use_config(f, configs=None):
    """ Decorator that loads the TOML configs automatically """
    from functools import wraps
    @wraps(f)
    def wrapper(*args, **kwargs):
        return f(*args, **kwargs, config=load_config(configs))
    return wrapper


def ansi(code):
    """ Generates an ANSI escape code """
    return f"\033[{code}m"


@use_config
def make_help(makefile='Makefile', config=None):
    """
    Scan through a `Makefile` passed as the first argument and automatically
    generate help for each target found
    """
    import re, sys

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

        # 4 spaces, the target name right-padded to the max width of any target, 4
        # spaces, then the help
        fmt = f"    %s%-{str(maxlen)}s%s    %s"

        if targets:
            for t in targets:
                print(fmt % (ansi('1;34'), t[0], ansi(0), t[1]))
        if groups:
            for g in groups:
                print(f"\n  [{g}]")
                for t in groups[g]:
                    print(fmt % (ansi('1;34'), t[0], ansi(0), t[1]))

    print(f"\n  Report bugs at:\n    {config['site']['issuesurl']}\n")

# vim: sw=4 ts=4 expandtab
