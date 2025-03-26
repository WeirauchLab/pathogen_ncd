"""
Makefile helper functions related to site generation and admin
"""
import os
import sys
import logging

from .config import use_config

log = logging.getLogger(__name__)

if os.getenv('DEBUG') or os.getenv('DEBUG_TEMPLATES'):
    log.setLevel(logging.DEBUG)


@use_config
def process_templates(templates=None, deploydir=None, config=None):
    """
    Process Jinja2 templates from ``templates``; write to ``deploydir``
    """
    from datetime import datetime as dt
    from collections.abc import Iterable
    from jinja2 import Environment, FileSystemLoader, pass_context
    from .util import filesize

    if not deploydir:
        deploydir = config['site']['deploydir']
        log.info(f"No 'deploydir' given, using default of '{deploydir}'")

    if not templates:
        # default to `templates` subdir in the current working directory
        templates = 'templates'
    elif isinstance(templates, str) and not os.path.isdir(templates):
        # wrap in a list
        templates = [templates]

    if isinstance(templates, str) and os.path.isdir(templates):
        print(f"Searching template directory '{templates}'...",
              file=sys.stderr)
        env = Environment(loader=FileSystemLoader(templates))
        # FIXME: duplication
        env.globals = config
        env.filters['filesize'] = lambda p: filesize(p)

        for (path, dirs, files) in os.walk(templates):
            # path relative to `templates` directory
            relpath = os.path.relpath(path, templates)

            # corresponding destination path in "deploy" directory
            destpath = os.path.join(deploydir, relpath)
            os.makedirs(destpath, exist_ok=True)

            for f in files:
                if f.endswith('.swp'):  # ugh
                    continue

                destfile = os.path.join(destpath, f)
                # the templates are UTF-8, so force this encoding for Windows,
                # which defaults to cp1252
                with open(destfile, 'w', encoding='utf-8') as df:
                    # https://github.com/pallets/jinja/issues/711#issuecomment-300070379
                    tpath = os.path.join(relpath, f).replace('\\', '/')
                    t = env.get_template(tpath)
                    df.write(t.render(), )

                print(f"Wrote '{destfile}'.", file=sys.stderr)

            for d in dirs:
                # skip `_partials` and anything else beginning with an underscore
                if d.startswith('_'):
                    dirs.remove(d)

    else:
        assert isinstance(templates, list)
        env = Environment(loader=FileSystemLoader('.'))
        # FIXME: duplication
        env.globals = config
        # create a `filesize` filter that can be used in templates
        env.filters['filesize'] = lambda p: filesize(p)

        for template in templates:
            # assumed to be relative to `templates` subdir
            destpath = os.path.join(deploydir, os.path.dirname(template))
            os.makedirs(destpath, exist_ok=True)
            destfile = os.path.join(destpath, os.path.basename(template))

            with open(destfile, 'w') as df:
                # https://github.com/pallets/jinja/issues/711 again, *sigh*
                tpath = os.path.join('templates', template).replace('\\', '/')
                t = env.get_template(tpath)
                df.write(t.render())

            print(f"Wrote '{destfile}'.", file=sys.stderr)


if __name__ == '__main__':
    process_templates(sys.argv[1:])
