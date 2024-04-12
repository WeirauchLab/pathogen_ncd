<!--[![site status](https://tfinternal.research.cchmc.org/gitlab/tftools/teds-viral-tf-survey/badges/master/pipeline.svg)](https://tfinternal.research.cchmc.org/gitlab/tftools/teds-viral-tf-survey/commits/master)-->
# Pathogens and NCD survey web site

Deployment steps (from a fresh clone):

```bash
cd web                     # you're probably already here
python3 -m venv venv       # create and activate a Python3 virtualenv,
source venv/bin/activate   # then install required Python dependencies
pip install -r requirements.txt
make site                  # build the site into `local.deploy`
make serve                 # bring up a web server in a Docker container
make browse                # opens the local web server in your browser
```

There is some duplication among `docker.yml`, the `Makefile`, and `site.toml`
with regard to the local web server port, but this could probably be resolved
in time.
