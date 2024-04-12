##
##  Helper functions for processing the TOML configs
##
import os, logging

CONFDIR = os.path.abspath(
        os.path.join(os.path.dirname(__file__), '..', 'conf'))
logfmt = '%(asctime)s [%(levelname)s] %(message)s'
logging.basicConfig(format=logfmt)
log = logging.getLogger(__name__)
config_list = {}

# crudely emulating pass-by-reference for the recursive funtion; see
# https://realpython.com/python-pass-by-reference/#replicating-pass-by-reference-with-python
cfg = {}
idx = {}

if os.getenv('DEBUG'):
    log.setLevel(logging.DEBUG)


def use_config(f, configs=None):
    """ Decorator that loads the TOML configs automatically """
    from functools import wraps

    @wraps(f)
    def wrapper(*args, **kwargs):
        return f(*args, **kwargs, config=load_config(configs))

    return wrapper


def load_config(configs=None):
    """ load TOML configs and return dict of them all merged together """
    import os, tomli
    global cfg
    global config_list

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
            cfg[name] = tomli.load(open(configfile, 'rb'))
        except tomli.TOMLDecodeError as e:
            raise RuntimeError(f"Error parsing '{configfile}': {e}") \
                from None

    interpolate(cfg)
    post_process(cfg)
    return cfg


def post_process(cfg):
    """ post-processing for a few "magic" config values """
    from datetime import datetime as dt

    cfg['site']['today'] = cfg['publication']['releasedate'] \
            = dt.now().strftime('%Y-%m-%d')
    # set site.urlbase appropriate to whatever `deployto` is set to
    cfg['site']['urlbase'] = \
            cfg['site']['deploy'][cfg['site']['deployto']]['urlbase']

    return cfg


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

    global idx

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
                            if match in idx:
                                log.debug("  ✓ Found '%s': '%s' in index",
                                           match, idx[match])
                                v = v.replace(f"{{{match}}}", idx[match])
                            else:
                                log.debug("  ✗ No match for '%s' in index",
                                           match)
                                v = f"{{¡{match}!}}"

                            # update the real dictionary key in-place
                            x[k] = v

                log.debug("Added '%s': '%s' to index", k, v)
                idx[k] = v
