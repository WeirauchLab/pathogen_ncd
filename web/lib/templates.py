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
def process_templates(templatedir="templates", deploydir=None, config=None):
    """
    Process Jinja2 templates from ``templatedir``; write to ``deploydir``
    """
    from datetime import datetime as dt
    from jinja2 import Environment, FileSystemLoader, pass_context
    from .util import filesize

    if not deploydir:
        deploydir = config['site']['deploydir']
        log.info(f"No 'deploydir' given, using default of '{deploydir}'")

    env = Environment(loader=FileSystemLoader(templatedir))
    env.globals = config

    # create a `filesize` filter that can be used in templates
    env.filters['filesize'] = lambda p: filesize(p)

    for (path, dirs, files) in os.walk(templatedir):
        # path relative to `templates` directory
        relpath = os.path.relpath(path, templatedir)

        # corresponding destination path in "deploy" directory
        destpath = os.path.join(deploydir, relpath)
        os.makedirs(destpath, exist_ok=True)

        for f in files:
            if f.endswith('.swp'):  # ugh
                continue

            destfile = os.path.join(destpath, f)
            print(f"Writing '{destfile}'...", file=sys.stderr)

            with open(destfile, 'w') as df:
                t = env.get_template(os.path.join(relpath, f))
                df.write(t.render())

        for d in dirs:
            # skip `_partials` and anything else beginning with an underscore
            if d.startswith('_'):
                dirs.remove(d)


if __name__ == '__main__':
    process_templates()
