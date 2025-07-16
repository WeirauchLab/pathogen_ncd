# Pathogens and non-communicable diseases web site

_See [the parent directory's README](../README.md) for citation information._

Deployment steps (from a fresh clone):

```bash
cd web                     # you're probably already here
python3 -m venv venv       # create and activate a Python3 virtualenv,
source venv/bin/activate   # then install required Python dependencies
pip install -r requirements.txt
make deploy                # build and deploy the site into `local.deploy`
make serve                 # bring up a web server in a Docker container
make browse                # opens the local web server in your browser
```

If you set up [autoenv][] under your user profile, copy `dot-autoenv` to
`.autoenv`, and add

```bash
export AUTOENV_ENV_FILENAME=.autoenv
```

to your `.bashrc`, the Python virtualenv will automatically be activated when
you enter the `web` subdirectory.

## Installation on Windows

It's assumed you'll already have Python ≥3.8 installed, and set up so that
`python` and/or `python3` are in your `%PATH%` / `$PATH`.

```powershell
cd path\to\where\you\cloned\pathogen_ncd
cd web
python -m venv venv

# required for PowerShell only; actually case-insensitive, but whatever
Set-ExecutionPolicy -ExecutionPolicy allsigned -scope process -force

venv\scripts\activate
pip install -r requirements.txt
pip install invoke colorama

invoke -l      # or `invoke help`
invoke deploy  # builds static site in `local.deploy`

# start a local dev server and open new browser tab to the site
invoke serve --browse
```

A [`make.cmd`](make.cmd) wrapper script is provided for Windows, if you're in
the habit of typing `make`. This is just a rudimentary wrapper around `python
-m invoke` that displays the `help` output by default. In PowerShell, you must
invoke this as `./make` because PowerShell.


## Notes on local deployment

If you have [Docker][] available, you can also run `docker compose up` in the
`web` subdirectory.

By default, both the `invoke serve` (which uses `http.server` from the Python
standard library) and the Docker container serve the site at
<http://localhost:8000>. If you need to change this, see `conf/site.toml` and
`compose.yml`, respectively.


## Deploying to a "real" web server

Replace `gateway` and `vm` with actual hostnames, and run this command on one
of the lab's VMs in order to deploy to the public web sites:

```bash
ssh -tA gateway ssh vm
cd path/to/where/you/cloned/pathogen_ncd
```

For example, let's say you want to deploy to the production VM. First, SSH to
the VM as shown above, then either update the `deployto` key in
[`conf/site.toml`](conf/site.toml) to `prod` or set `DEPLOYTO=prod` in
`.autoenv` (see above). Now,

```bash
make deploy
```

will build the JS/CSS assets, static HTML pages from templates, and the
downloads, and copy these to the appropriate directory under the web root on
the production server.


### Testing and troubleshooting

It is a good idea to run

```bash
make test
```

once you've run the `deploy` target. The tests it runs are pretty rudimentary,
but they're enough to make sure that the important links (the data download
links and the link to the actual publication) work correctly on the live site.

If things don't look right, try

```bash
make distclean && make deploy

# or, where `-B` = "force rebuild all"
make distclean && make -B deploy
```

before [filing an issue][issuetracker].


## Credits

### Apaxy theme for Apache `mod_autoindex` by Adam Whitcroft

See [the old adamwhitcroft.com/apaxy website][waybackapaxy],
`static/theme/README.md`, and `static/theme/License.md` for full details.

[autoenv]: https://github.com/hyperupcall/autoenv
[docker]: https://docs.docker.com/desktop/setup/install/windows-install
[waybackapaxy]: https://web.archive.org/web/20170827153848/http://adamwhitcroft.com/apaxy
[issuetracker]: https://tfinternal.research.cchmc.org/gitlab/mike/pathogen_ncd/issues
