##
##  Makefile helper functions related to site generation and admin
##

def serve(root='public', addr='127.0.0.1', port='8000'):
    import subprocess
    # cheating
    subprocess.call(['python', '-m', 'http.server', '--bind', addr,
                     '--directory', root, port])
    

def process_templates(site_config="site.toml", pub_config="publication.toml",
                      template_dir="templates", public_dir="public"):
    import os, sys, tomli
    from jinja2 import Environment, FileSystemLoader  #, select_autoescape

    sitecfg = tomli.load(open(site_config, 'rb'))
    pubcfg = tomli.load(open(pub_config, 'rb'))
    env = Environment(loader=FileSystemLoader(template_dir))
                      #autoescape=select_autoescape())
    env.globals = { 'site': sitecfg, 'pub': pubcfg }

    for (path, dirs, files) in os.walk(template_dir):
        relpath = os.path.relpath(path, template_dir)
        destpath = os.path.join(public_dir, relpath)
        os.makedirs(destpath, exist_ok=True)
        for f in files:
            if f.endswith('.swp'):  # ugh
                continue

            template = os.path.join(path, f)
            html = os.path.join(destpath, f)
            print(f"Processing '{template}'...", file=sys.stderr)

            with open(html, 'w') as h:
                with open(template, 'r') as ts:
                    t = env.get_template(os.path.join(relpath, f))
                    h.write(t.render())
        for d in dirs:
            if d.startswith('_'):
                dirs.remove(d)
