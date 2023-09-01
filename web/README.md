<!--[![site status](https://tfinternal.research.cchmc.org/gitlab/tftools/teds-viral-tf-survey/badges/master/pipeline.svg)](https://tfinternal.research.cchmc.org/gitlab/tftools/teds-viral-tf-survey/commits/master)-->
# Pathogens and NCD survey web site

Deployment steps (from a fresh clone):

```bash
cd web                     # you're probably already here
python3 -m venv venv       # create virtualenv if not already done
source venv/bin/activate   # activate the virtualenv for this shell
pip install csvkit         # required to convert Excel sheets to TSV
cp path/to/samples.xlsx .  # there needs to be a <something>.xlsx
make -B site               # -B = "force rebuild all"; inspect for errors
make drebuild              # (re)build .zip and .tar.gz DB releases
make deploy                # copy necessary files to production web server
```
