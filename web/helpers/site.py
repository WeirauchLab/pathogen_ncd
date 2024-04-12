##
##  Makefile helper functions related to site generation and admin
##

from .config import use_config, config_list


@use_config
def process_templates(template_dir="templates", deploy_dir="local.deploy",
                      config=None):
    """
    Process Jinja2 templates from `template_dir`; copy to `deploy_dir`
    """
    import os, sys
    from jinja2 import Environment, FileSystemLoader, pass_context

    env = Environment(loader=FileSystemLoader(template_dir))

    env.globals = {}
    for config_name, _ in config_list.items():
        env.globals.update({config_name: config[config_name]})

    # as a shorter nickname for the above
    env.globals.update({'pub': config['publication']})

    def filesize(value):
        return os.stat(f"static/data/{value}").st_size

    env.filters['filesize'] = filesize

    for (path, dirs, files) in os.walk(template_dir):
        # path relative to `templates` directory
        relpath = os.path.relpath(path, template_dir)

        # corresponding destination path in "deploy" directory
        destpath = os.path.join(deploy_dir, relpath)
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
