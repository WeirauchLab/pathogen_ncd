"""
Helper functions for processing the TOML configs

Author:   Kevin Ernst <kevin.ernst -at- cchmc.org>
License:  GPL; see LICENSE.txt in the top-level directory

© 2025 Cincinnati Children's Hospital Medical Center and the author(s)
"""
import os, sys, logging

log = logging.getLogger(__name__)

if os.getenv('DEBUG') or os.getenv('DEBUG_CONFIG'):
    log.setLevel(logging.DEBUG)

CONFDIR = os.path.abspath(
        os.path.join(os.path.dirname(__file__), '..', 'conf'))

# crudely emulating pass-by-reference for the recursive funtion; see
# https://realpython.com/python-pass-by-reference/#replicating-pass-by-reference-with-python
index = {}
config_list = {}


def use_config(f, configs=None):
    """ Decorator that loads the TOML configs automatically """
    from functools import wraps

    @wraps(f)
    def wrapper(*args, **kwargs):
        return f(*args, **kwargs, config=load_config(configs))

    return wrapper


def load_config(configs=None):
    """ Load TOML configs and return dict of them all merged together """
    if sys.version_info.minor < 11:
        import tomli as tomllib
    else:
        import tomllib

    config = {}

    if configs is None:
        import glob
        configs = glob.glob(os.path.join(CONFDIR, '*.toml'))

    for f in configs:
        config_list.update({
            # site.toml, pub.toml, data.toml…
            os.path.basename(os.path.splitext(f)[0]): f
        })

    for name, configfile in config_list.items():
        try:
            toml = pre_process(configfile)
            config[name] = tomllib.loads(toml)
        except tomllib.TOMLDecodeError as e:
            raise RuntimeError(f"Error parsing '{configfile}': {e}") \
                from None

    interpolate(config)
    post_process(config)
    return config

def pre_process(tomlfile):
    """
    Do any necessary pre-processing before handing off to TOML library
    """
    import re
    newtoml = []
    t = open(tomlfile, 'r')
    for line in t.readlines():
        # Bash-style expansion to yield a default, e.g., ${var:-default}
        matches = re.search(r'\$\{(\w+)(?::-?(.*?))?\}', line)
        if matches:
            envvar = matches[1]
            default = matches[2] if matches[2] else ""
            line = line.replace(matches[0], os.getenv(envvar, default))
            log.info(f"Substituted ${envvar} in '{tomlfile}' input line '{line.strip()}'")
        newtoml += [line]
    t.close()
    return "\n".join(newtoml)

def interpolate(x):
    """
    Simple, sequential interpolation of ``{keyname}``s

    Key names must be globally unique if you expect to interpolate them (e.g.,
    ``shortname``); accessing them hierarchically (e.g., ``site.shortname``)
    is not supported.

    If a duplicate key name is encountered, its value is clobbered
    unceremoniously. This means that every unique key name will have the
    _last_ value assigned, according to the order the configs were parsed in
    ``load_config``.
    """
    import re

    if isinstance(x, list):
        for i in x:
            if isinstance(i, dict):
                interpolate(i)
    elif isinstance(x, dict):
        for k, v in x.items():
            if isinstance(v, (dict, list)):
                interpolate(v)
            else:
                if isinstance(v, str):
                    matches = re.findall(r'{(.*?)}', v)
                    if matches:
                        log.debug("Key '%s': '%s' contains tokens: %s", k, v,
                                  matches)

                        for match in matches:
                            if match in index:
                                log.debug("  ✓ Found '%s': '%s' in index",
                                           match, index[match])
                                v = v.replace(f"{{{match}}}",
                                              str(index[match]))
                            else:
                                log.debug("  ✗ No match for '%s' in index",
                                           match)
                                v = f"{{¡{match}!}}"

                            # update the real dictionary key in-place
                            x[k] = v

                log.debug("Added '%s': '%s' to index", k, v)
                index[k] = v


def post_process(config):
    """ post-processing for a few "magic" config values """
    from datetime import datetime as dt

    # a couple of dates for convenience
    today = dt.now().strftime('%Y-%m-%d')
    config['date'] = {
        'today': today,
        'releasedate': config['data']['releasedate'],
        'currentyear': dt.now().year,
    }

    # make 'pub' an alias for 'publication'
    config['pub'] = config['publication']

    # set site.urlbase appropriate to whatever `deployto` is set to
    config['site']['urlbase'] = \
            config['site']['deploy'][config['site']['deployto']]['urlbase']

    # record the active deployment settings in config['site']['deploy']
    deployto = config['site']['deployto']
    for k, v in config['site']['deploy'][deployto].items():
        config['site']['deploy'][k] = v

    # create `site.deploydir` and `site.datadir` for convenience
    deploydir = config['site']['deploy']['deploydir']
    config['site']['deploydir'] = deploydir
    config['site']['deploydatadir'] = \
        f"{deploydir}/{config['data']['artifacts']['subdir']}"


if __name__ == '__main__':
    import json, pprint, argparse
    from .config import load_config
    from .attrdict import AttrDict

    c = AttrDict(load_config())
    parser = argparse.ArgumentParser()
    parser.add_argument('-g', '--get')
    parser.add_argument('-j', '--json', '--as-json', action='store_true')
    opts = parser.parse_args()

    def json_print(c):
        import json
        json.dump(c, sys.stdout, indent=True)
        print();

    printer = json_print if opts.json else pprint.pprint

    if opts.get:
        eval(f"printer(c.{opts.get})")
    else:
        printer(c)
