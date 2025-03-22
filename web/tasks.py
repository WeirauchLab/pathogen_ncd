import os, sys, shutil, logging, invoke
from lib.config import load_config
from lib.color import AnsiColors
from lib.attrdict import AttrDict

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

if os.getenv('DEBUG') or os.getenv('DEBUG_TASKS'):
    logger.setLevel(logging.DEBUG)

ansi = AnsiColors()
ansi.boldblue = ansi.bold + ansi.blue
c = AttrDict(load_config())
deploydir = c.site.deploydir
deploydatadir = c.site.deploydatadir


@invoke.task
def help(ctx):
    """prints help for all Invoke tasks"""
    print(f"""
  {ansi.ul}Invoke tasks for {c.site.shorttitle}{ansi.reset}
""")
    # _tasks is defined below, *after* entire script file is parsed
    tasks = [(n,d) for n,d in _tasks if not d.startswith('[hidden]')]
    maxlen = max([len(name) for name, _ in tasks])
    for name, desc in tasks:
        print("    {}{:<{}}{}    {}".format(
            ansi.boldblue, name, maxlen, ansi.reset, desc))

    print(f"""
  Source + issues:
    {c.site.issuesurl}
""")


@invoke.task
def config(ctx, key=None, json=False):
    """prints the configuration structure based on parsing conf/*.toml"""
    import pprint

    def json_print(c):
        import json
        json.dump(c, sys.stdout, indent=True)
        print();

    # if some day we switch to a TOML library that can write…
    #def toml_print(c):
    #    import tomlsomething
    #    tomlsomething.dump(c, sys.stdout, indent=True)
    #    print();

    printer = json_print if json else pprint.pprint

    if key:
        import re
        if not re.fullmatch('\w+(.\w+)*', key):
            raise RuntimeError(f"Invalid config key '{key}'")
        if isinstance(eval(f"c.{key}"), AttrDict):
            eval(f"printer(c.{key})")
        else:
            # this avoids extraneous quotes for fetching a single key value
            eval(f"print(c.{key})")
    else:
        printer(c)



class pushd:
    def __init__(self, newdir):
        self.olddir = os.getcwd(); self.newdir = newdir
    def __enter__(self):
        logger.debug(f"Entering into '{self.newdir}'…")
        os.chdir(self.newdir)
    def __exit__(self, exc_type, exc_value, traceback):
        os.chdir(self.olddir)
        logger.debug(f"Left '{self.newdir}'; c.w.d. is now '{self.olddir}'.")

@invoke.task
def npm_install(ctx):
    """[hidden] downloads third-party JavaScript libraries"""
    wd = os.getcwd()
    logger.info("Installing third-party JavaScript libraries to 'static'…")
    with pushd('static'):
        ctx.run("npm install")

@invoke.task(pre=[npm_install])
def build_assets(ctx):
    """[hidden] copy static assets into deploy destination directory"""
    import re
    def ignore(dir, contents):
        excludes = ['.*\.swp', 'package.*\.json', 'node_modules']
        return [x for x in contents
                if any([re.match(regex, x) for regex in excludes])]

    logger.info(f"Copying static assets to '{deploydir}'…")
    # specifying `symlinks=True` here will cause this to bomb with a bunch of
    # `[Errno 17]`s when the symlink already exists
    shutil.copytree('static', deploydir, ignore=ignore, dirs_exist_ok=True)

@invoke.task
def make_deploy_dir(ctx):
    """[hidden] create the deploy destination directory structure"""
    logger.info(f"Creating '{deploydatadir}' and any required subdirs…")
    os.makedirs(deploydatadir, exist_ok=True)

@invoke.task(pre=[make_deploy_dir])
def build_tsvs(ctx):
    """[hidden] creates .tsv files from from supplemental datasets"""
    from lib.transform import (transform_icd, transform_phe)
    from lib.convert import write_tsvs
    # FIXME: kinda gross; should use dependency inversion and specify the
    # transformers and converters in the TOML config instead
    logger.info("Transforming the ICD10 spreadsheet…")
    transform_icd()
    logger.info("Transforming the Phecode spreadsheet…")
    transform_phe()
    logger.info(f"Writing .tsv files to '{deploydatadir}'…")
    write_tsvs()

@invoke.task
def update_readme(ctx):
    """[hidden] create README.txt for inside the downloadable archives"""
    from lib.templates import process_templates
    logger.info("Updating 'README.txt' with values from TOML configs…")
    process_templates('data/README.txt')

@invoke.task(pre=[make_deploy_dir, build_tsvs, update_readme])
def build_downloads(ctx):
    """[hidden] creates downloadable archives from supplemental datasets"""
    import glob, zipfile, tarfile
    logger.info("Creating .zip containing README and the .tsv files…")

    resultsarchive= os.path.join(deploydatadir,
                                 c.data.artifacts.resultsarchive)
    logger.info(f"Creating results archive '{resultsarchive}'…")
    with zipfile.ZipFile(resultsarchive, 'w') as z:
        for xlsx in glob.glob(os.path.join(deploydatadir, '*Results.xlsx')):
            z.write(xlsx, arcname=os.path.basename(xlsx))
        z.write(os.path.join(deploydatadir, 'README.txt'), 'README.txt')

    resultstarball = os.path.join(deploydatadir,
                                  c.data.artifacts.resultstarball)
    assert resultstarball.endswith('.gz')
    logger.info(f"Creating results tarball '{resultstarball}'…")
    archivesubdir = f"{c.data.artifacts.basename}_{c.pub.year}"
    # apparently, `w:gz` doesn't work with the context manager
    tarball = tarfile.open(resultstarball, 'w:gz')
    for tsv in glob.glob(os.path.join(deploydatadir, '*.tsv')):
        tarball.add(
            tsv,
            arcname=os.path.join(archivesubdir, os.path.basename(tsv))
        )
    tarball.add(os.path.join(deploydatadir, 'README.txt'),
            arcname=os.path.join(archivesubdir, 'README.txt'))
    tarball.close()

    logger.info("Copying figures and tables PDF into place…")
    shutil.copy(c.data.figures.infilename,
            os.path.join(deploydatadir, c.data.figures.outfilename))

    supplarchive = os.path.join(deploydatadir,
                                c.data.artifacts.supplementarchive)
    logger.info(f"Writing supplemental .xlsx files to '{supplarchive}'…")
    with zipfile.ZipFile(supplarchive, 'w') as z:
        for xlsx in glob.glob('../supplemental_data/supp*_dataset*.xlsx'):
            z.write(xlsx, arcname=os.path.basename(xlsx))
        z.write(os.path.join(deploydatadir, 'README.txt'), 'README.txt')

@invoke.task
def process_templates(ctx):
    """[hidden] converts Jinja 2 templates into static files"""
    from lib.templates import process_templates
    logger.info("Processing templates…")
    process_templates()
    logger.info("Creating '.htaccess' symlink for the 'data' directory…")
    with pushd(deploydatadir):
        if not os.path.islink('.htaccess'):
            os.symlink('../theme/dot-htaccess', '.htaccess')

@invoke.task(pre=[build_assets, build_downloads, process_templates])
def deploy(ctx):
    """builds static assets, templates, and downloads"""
    pass

@invoke.task(pre=[deploy])
def build(ctx):
    """[hidden] an alias for 'deploy'"""
    pass

@invoke.task(pre=[deploy])
def site(ctx):
    """[hidden] an alias for 'deploy'"""
    pass


@invoke.task
def serve(ctx, port=c.site.deploy.port, bind='127.0.0.1'):
    """serves the site locally using Python's http.server module"""
    import http.server, socketserver

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs, directory=deploydir)

    # the DIY way:
    #with socketserver.TCPServer((bind, port), Handler) as httpd:
    #    print("Now, you *know* this isn't suitable for production use, right?",
    #          file=sys.stderr)
    #    print(f"Serving '{deploydir}' at http://{bind}:{port}…",
    #          file=sys.stderr)
    #    # cribbed from
    #    # https://github.com/python/cpython/blob/3.11/Lib/http/server.py#L1250
    #    try:
    #        httpd.serve_forever()
    #    except KeyboardInterrupt:
    #        print("\nKeyboard interrupt received, exiting.", file=sys.stderr)
    #        sys.exit(0)

    http.server.test(HandlerClass=Handler, port=port, bind=bind)


# this needs to stay at the bottom, *after* all the functions are defined
_tasks = [(g, globals()[g].__doc__) for g in globals()
          if isinstance(globals()[g], invoke.tasks.Task)]
