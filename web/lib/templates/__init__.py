"""
Makefile helper functions related to site generation and admin
"""
import os, sys, logging
from datetime import datetime as dt
from collections.abc import Iterable
from jinja2 import Environment, FileSystemLoader, pass_context

from . import filters
from . import globalfunctions
from ..config import use_config

DEFAULT_TEMPLATE_DIR = 'templates'
log = logging.getLogger(__name__)

if os.getenv('DEBUG') or os.getenv('DEBUG_TEMPLATES'):
    log.setLevel(logging.DEBUG)


class BackslashFriendlyFileSystemLoader(FileSystemLoader):
    """
    Work around pallets/jinja issue #711

    Jinja "template paths are not necessarily filesystem paths and […] use
    forward slashes," so just do a crude subsitution and hope for the best

    ref. https://github.com/pallets/jinja/issues/711#issuecomment-300070379
    and  https://github.com/pallets/jinja/blob/3.1.6/src/jinja2/loaders.py#L194
    """
    def get_source(self, environment, template):
        template = template.replace('\\', '/')
        return super().get_source(environment, template)


@use_config
def process_templates(templates=None, deploydir=None, config=None):
    """
    Process Jinja2 templates from ``templates``; write to ``deploydir``

    :param Union(str, list) templates: either 1) a template directory; 2) the
        name of a single template relative to the default template directory
        (``templates`` in the c.w.d.); or 3) a list of templates relative to
        the template directory
    :param str deploydir: where to write the processed templates
    :param dict config: parsed config passed in by the :py:deco:`use_config`
        decorator in :py:mod:`lib.config`
    """
    if not deploydir:
        deploydir = config['site']['deploydir']
        log.info(f"No 'deploydir' given, using default of '{deploydir}'")

    # use 'templates' in the c.w.d. by default, unless specified
    loader = BackslashFriendlyFileSystemLoader(DEFAULT_TEMPLATE_DIR)
    env = Environment(loader=loader)

    # - default to `templates` subdir in the current working directory
    # - if passed a custom template directory, iterate over that instead
    # - if passed a single string, wrap in a list, use default template dir.
    if not templates:
        templates = DEFAULT_TEMPLATE_DIR
    elif isinstance(templates, str) and os.path.isdir(templates):
        env.loader = BackslashFriendlyFileSystemLoader(templates)
    elif isinstance(templates, str) and not os.path.isdir(templates):
        templates = [templates]
    else:
        if not isinstance(templates, Iterable):
            raise RunTimeError(f"Unexpected value templates='{templates}'")

    # add parsed TOML config to the environment for all templates; so that
    # `name` from `site.toml` becomes `{{ site.name }}` in Jinja templates
    env.globals = config

    ##
    ##  Register custom filters and other globals
    ##  ref. https://jinja.palletsprojects.com/en/stable/api/#writing-filters
    ##
    for f in filters.__all__:
        env.filters[f] = getattr(filters, f)

    for g in globalfunctions.__all__:
        env.globals[g] = getattr(globalfunctions, g)()

    if isinstance(templates, str) and os.path.isdir(templates):
        print(f"Searching template directory '{templates}'...",
              file=sys.stderr)

        for (path, dirs, files) in os.walk(templates):
            relpath = os.path.relpath(path, templates)
            destpath = os.path.join(deploydir, relpath)
            os.makedirs(destpath, exist_ok=True)

            for f in files:
                if f.startswith('_') or f.endswith('.swp'):
                    continue

                destfile = os.path.join(destpath, f)
                # the templates are UTF-8, so force the output encoding for
                # Windows, where locale.getencoding() defaults to `cp1252`
                with open(destfile, 'w', encoding='utf-8') as df:
                    tpath = os.path.join(relpath, f)
                    t = env.get_template(tpath)
                    df.write(t.render())

                print(f"Wrote '{destfile}'.", file=sys.stderr)

            for d in dirs:
                # skip `_partials` and anything else with an underscore
                if d.startswith('_'):
                    dirs.remove(d)
    else:
        # it's a list of individual template names
        for template in templates:
            # assumed to be relative to `templates` subdir
            destpath = os.path.join(deploydir, os.path.dirname(template))
            os.makedirs(destpath, exist_ok=True)
            destfile = os.path.join(destpath, os.path.basename(template))

            # force output encoding for Windows
            with open(destfile, 'w', encoding='utf-8') as df:
                t = env.get_template(template)
                df.write(t.render())

            print(f"Wrote '{destfile}'.", file=sys.stderr)
