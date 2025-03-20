<!--[![site status](https://tfinternal.research.cchmc.org/gitlab/tftools/teds-viral-tf-survey/badges/master/pipeline.svg)](https://tfinternal.research.cchmc.org/gitlab/tftools/teds-viral-tf-survey/commits/master)-->
# Pathogens and non-communicable diseases web site

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

If you set up [autoenv][] under your user profile and set

```bash
export AUTOENV_ENV_FILENAME=.autoenv
```

the Python virtualenv will automatically be activated when you enter the `web`
subdirectory.


## Deployment

Modify [`conf/site.toml`](conf/site.toml) and update the `deployto` key to
point to the appropriate <code>[deploy.<em>something</em>]</code> section of
the config file. Note that modifying this file for deployment, _e.g._ to
production will always make the Git work tree "dirty" on the production server.
A better solution could be found, where the deployment settings aren't tracked
in the Git repo, but… sometimes you've got to say something's "good enough."

Replace `gateway` and `vm` with actual hostnames, and run this command on one
of the lab's VMs in order to deploy to the public web sites:


```bash
ssh -tA gateway ssh vm
cd path/to/your/clone
make deploy
```

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
make clean && make deploy

# or, where `-B` = "force rebuild all"
make clean && make -B deploy
```

before [filing an issue][issuetracker].


## Bugs and other shortcomings

There is some duplication among `docker.yml`, the `Makefile`, and `site.toml`
with regard to the local web server port, but this could probably be resolved
in time.


## Credits

### Apaxy theme for Apache `mod_autoindex` by Adam Whitcroft

See [the old adamwhitcroft.com/apaxy website][waybackapaxy],
`static/theme/README.md`, and `static/theme/License.md` for full details.

[autoenv]: https://github.com/hyperupcall/autoenv
[waybackapaxy]: https://web.archive.org/web/20170827153848/http://adamwhitcroft.com/apaxy/
[issuetracker]: https://tfinternal.research.cchmc.org/gitlab/mike/pathogen_ncd/issues
