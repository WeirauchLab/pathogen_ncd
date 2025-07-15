TITLE = Makefile tasks for Mike’s Pathogen/NCD project
SHELL = bash
THISMAKEFILE = $(firstword $(MAKEFILE_LIST))
PYTHON = venv/bin/python3
CONTAINER = web
# return non-zero for 4xx/5xx errors; silent except errors; follow redirects
CURL = curl -fsSL
# Using the DataTables download builder was easier than trying to 'npm install'
# and then figure out which source files to include in <script> tags -- a
# complete nightmare.
#
# Instead, visit[1] (don't worry about the version numbers, they're ignored),
# switch to the "Download" tab under Step 3, click the "CDN" tab, copy the base
# part of that URL (without the filename), use that to update
# `DATATABLES_CDN_URL` below, then run `make datatables` to build the relevant
# target.
#
# The minimized .js and .css files have URLs at the top that remind you how to
# re-download. The "Download Builder" (which delivers a .zip file) only
# supplies the latest release, though which is why we use the CDN URL here[2].
#
# [1]: https://datatables.net/download/#dt/dt-2.3.2/b-3.2.3/b-html5-3.2.3
# [2]: https://datatables.net/forums/discussion/comment/240517/#Comment_240517
DATATABLES_CDN_URL = https://cdn.datatables.net/v/dt/dt-2.3.2/b-3.2.3/b-html5-3.2.3
# for ColumnControl, add /cc-1.0.6
# fixed header didn't work well with the ICD/PHE tabs but add /fh-4.0.3 (or the
# latest version available from [1]) if you want it

# the UID of the user running this Makefile; used to `chown` the bind mount for
# DEPLOYDIR so you can update it from the host side with `make deploy`; can't
# just read this from the environment because it's not exported by default; see
# https://unix.stackexchange.com/q/541417 and comments in `Dockerfile`
#
# this whole rigmarole just to get a variable inside a Dockerfile is irritating
#LOCALUID = $(shell id -u)

# the seemingly-superfluous DEPLOYTO here makes sure DEPLOYTO is actually in
# the environment if you call e.g. `make site DEPLOYTO=dev` instead of
# `DEPLOYTO=dev make site`
config = $(shell $(if $(DEPLOYTO),DEPLOYTO=$(DEPLOYTO) )python -m lib.config --json --get $(1) | jq -r)
host = $(call config,site.deploy.host)
port = $(call config,site.deploy.port)
deploydir = $(call config,site.deploydir)
datasubdir = $(call config,data.artifacts.subdir)
deploydatadir = $(deploydir)/$(datasubdir)

help: venv  # prints this help
	@$(PYTHON) -m lib.help $(THISMAKEFILE)

conf: config
# don't get confused by `config` above, which is used with `call` as a function
config: venv  # (alias: conf) pretty-prints parsed TOML configs [try JSON=1, KEY=]
	@$(PYTHON) -m lib.config$(if $(JSON), --json)$(if $(KEY), --get $(KEY))

site: deploy
deploy: .static_files_copied .templates_processed $(deploydatadir)/SHA1SUMS  # (alias: site) copies HTML, assets, and downloads [try DEPLOYTO=]

# copies static assets like theme files and JavaScript libs in place
static: .static_files_copied
.static_files_copied: static/theme/* static/vendor/datatables.* .npm_installed
	# rsync static files but *don't* try to preserve owner/group/perms
	rsync -rv --copy-links$(if $(DRYRUN), --dry-run) \
	    --exclude=".*.swp" --exclude=node_modules --exclude="package*.json" \
		static/ $(deploydir)
	touch $@

datatables: static/vendor/datatables.min.js static/vendor/datatables.min.css
static/vendor/datatables.%:
	cd static/vendor && $(CURL) --remote-name $(DATATABLES_CDN_URL)/$(notdir $@)

# copy these libraries from static/node_modules to the static site so that it's
# not necessary to `npm install` for each fresh clone
VENDOR_THESE_JS_LIBS = \
	jquery/dist/jquery.min.js \
	jquery/dist/jquery.min.map \
	js-cookie/src/js.cookie.js \
	marked/marked.min.js

npm_install: .npm_installed
.npm_installed:
	cd static && npm install
	# vendor the libraries we need, since Windows can't deal with the symlinks
	cd static/vendor && \
	for f in $(VENDOR_THESE_JS_LIBS); do \
		cp ../node_modules/$$f . || exit 1; \
	done
	touch $@

process_templates: .templates_processed
.templates_processed: conf/*.toml templates/* templates/*/* venv
	$(PYTHON) -m lib.templates
	# copy theme/dot-htaccess to the 'data' directory
	cd $(deploydatadir) && cp ../theme/dot-htaccess .htaccess
	touch $@

data: downloads
downloads: .downloads_created  # [data] creates downloadable archives from supplemental datasets
.downloads_created: .transformed .archives_created .figures_created
	touch $@

transform: .transformed  # [data] transform supplementary data into formats needed for the web site
.transformed:
	@echo
	mkdir -p $(deploydatadir)
	$(PYTHON) -m lib.transform
	touch $@

figuresinfile = $(call config,data.figures.infilename)
figuresoutfile = $(call config,data.figures.outfilename)
figures: .figures_created
.figures_created: $(deploydatadir)/$(figuresoutfile)
$(deploydatadir)/$(figuresoutfile):
	@echo
	mkdir -p $(deploydatadir)
	cp -f $(figuresinfile) $(deploydatadir)/$(figuresoutfile)

supplementarchive = $(call config,data.artifacts.supplementarchive)

archives: .archives_created
.archives_created: $(deploydatadir)/$(supplementarchive)
	touch $@

# this has to be processed first, so it can be put inside the archives, which
# need to be present before the other templates can be processed (since they
# refer to the file size of the archives)!
$(deploydatadir)/README.txt: templates/$(datasubdir)/README.txt
	$(PYTHON) -m lib.templates $(datasubdir)/README.txt

$(deploydatadir)/$(supplementarchive): $(deploydatadir)/README.txt
	@echo
	-rm $@
	mkdir -p $(deploydatadir)
	zip --junk-paths $@ ../supplementary_data/supplementary_data_*.{xlsx,pdf}
	zip --junk-paths $@ $<

sums: checksums
checksum: checksums
checksums: $(deploydatadir)/SHA1SUMS  # [data] re-computes checksums of downloadable archives
$(deploydatadir)/SHA1SUMS: .downloads_created
	@echo
	# computing checksums
	cd $(deploydatadir) && \
	sha1sum *.zip > SHA1SUMS

up: serve
## not currently used; see comments in `Dockerfile`
serve: venv  # [dev] (alias: up) serves site locally using Docker
ifneq ($(BUILD)$(REBUILD),)
	@#docker compose build --build-arg LOCALUID=$(LOCALUID) $(CONTAINER)
	PORT=$(if $(PORT),$(PORT),$(port)) docker compose build $(CONTAINER)
endif
	docker compose up $(CONTAINER)
	#venv/bin/watchfiles \
	#	'sh -c "make site && python3 -m http.server -b $(BIND) -d $(DEPLOYDIR) $(PORT)"' \
	#	templates static

down: venv
	docker compose down $(CONTAINER)

n: notebook
nb: notebook
# (aliases: n, nb) runs a local Jupyter notebook in the 'web' dir.
notebook:  
	jupyter notebook

s: shell
sh: shell
shell: venv  # [dev] (alias: s, sh) starts a root shell in the container
	docker compose exec $(CONTAINER) /bin/sh

b: browse
browse: venv  # [dev] (alias: b) opens a web browser to the (local) server
	@# python -m webbrowser prints a '\g' (BEL) to the terminal -- huff!
	$(PYTHON) -m webbrowser -t http://$(host):$(port) >/dev/null

check: lint
lint: venv  # [dev] (alias: check) checks all Python source files for syntax errors
	$(PYTHON) -m compileall -f lib

publicurl = $(call config,site.deploy.publicurl)
pubtitle = $(call config,pub.title)

tests: test
test: isitup dothelinkswork arechecksumsok  # [dev] run some simple functional tests on live web site
	@echo -e "\nAll tests OK."

isup: isitup
isitup:  # [dev] (alias: isup) quick check to see if the site is up
	@echo
	# make sure the site is accessible
	$(CURL) $(publicurl) >/dev/null
	
	@echo
	# make sure the site's title is intact
	$(CURL) $(publicurl) | grep --color '$(pubtitle)'

puburl = $(call config,pub.url)
pubdoi = $(call config,pub.pubdoi)
linkcontains = $$($(CURL) $(publicurl) | xmllint --html --xpath 'string(//a[contains(.,"$(1)")]/@href)' -)
dothelinkswork:
	@if ! which xmllint >/dev/null 2>&1; then \
		echo >&2; \
		echo "ERROR: required external utility 'xmllint' is missing." >&2; \
		echo "       Try installing from your distro's package manager." >&2; \
		exit 1; \
	fi
	
	@echo
	# now the figures & tables
	figuresandtables=$(call linkcontains,Download Supplementary Figures & Tables); \
	$(CURL) -I $(publicurl)/$$figuresandtables \
 	  | grep --color 'Content-Type:.*/pdf'
	
	@echo
	# now the supplemental datasets
	supplemental=$(call linkcontains,Download Supplementary Datasets); \
	$(CURL) -I $(publicurl)/$$supplemental | grep --color 'Content-Type:.*/zip'
	
	@echo
	# make sure the publication link is working
	$(CURL) $(publicurl) \
	  | xmllint --html --xpath '//p[contains(.,"Please cite")]/a/@href' - \
	  | grep --color "$(puburl)"

arechecksumsok:
	@echo
	# make sure checksums for all downloads match computed
	$(CURL) -O $(publicurl)/$(datasubdir)/SHA1SUMS
	$(CURL) -O $(publicurl)/$(datasubdir)/$(supplementarchive)
	sha1sum -c SHA1SUMS
	-rm SHA1SUMS $(supplementarchive)


clean:  # removes compiled bytecode and other detritus
	# remove Python precompiled bytecode
	-rm -rf __pycache__ lib/__pycache__
	-rm $(supplementarchive) SHA1SUMS

cleanjs:
	-rm -rf static/node_modules

distclean: clean cleanjs  # 'make clean' plus removes checkpoint files and Node.js modules
	# remove all checkpoint files like `.transformed`, `.converted`, et al.
	-rm .*ed
	-rm -rf .ipynb_checkpoints

reallyclean: distclean  # 'make distclean' plus remove local deploy dir
	@echo
	@if [[ "$(call config,site.deployto)" != prod ]]; then \
		read -p "This will remove the local deploy dir, '$(deploydir)', OK? [Y/n] "; \
		if [[ -n $$REPLY && $$REPLY =~ ^[Nn] ]]; then \
			echo -e "OK, not removing the deploy directory. Quitting.\n" >&2; \
			exit 1; \
		fi; \
		rm -rf $(deploydir); \
	else \
		echo -e "Sorry, this target only works for non-production deployments." >&2; \
		echo -e "To prevent mishaps, you must remove '$(deploydir)' yourself." >&2; \
		exit 1; \
	fi

venv: venv/bin/activate
	@if [[ $$(realpath $$(which python)) != $$(realpath $(PYTHON)) ]] || \
	    ! python -c 'import tomli' 2>/dev/null ; then \
		echo -e "\n  Please activate the virtualenv with 'source $<', then try again.\n" >&2; \
		exit 1; \
	fi

venv/bin/activate:
	@echo "Setting up virtual environment…" >&2; \
	if [[ $$(python3 --version) =~ 3.([789]|[1-9][0-9]) ]]; then \
		python3 -m venv venv; \
	else \
		if [[ $$(uname -s) != Linux ]] || ! scl enable rh-python38 -- python3 -m venv venv; then \
			echo -e "\nERROR: Unable to create the virtual environment.\n" >&2; \
			echo -e "       Please manually create a Python ≥3.7 virtualenv at 'venv'.\n" >&2; \
			exit 1; \
		fi; \
	fi; \
	echo -e "\nFinished setting up the Python virtual environment." >&2; \
	echo -e "Don't forget to activate it with 'source $@'.\n" >&2
	
	@echo "Installing Python dependencies…" >&2; \
	if source venv/bin/activate && pip install -r requirements.txt; then \
		echo -e "Finished installing Python dependencies." >&2; \
	else \
		echo -e "  ERROR: Unable to install dependencies. Please troubleshoot.\n" >&2; \
		exit 1; \
	fi


##
##  internals
##
# create new tagged DB release [VERSION=x.y.z] (default: bump minor)
#dbuild: user-provided-version work-tree-is-tidy db-build-not-dupe
#	@echo
#	cd $(LOCALDATADIR) && \
#	make zip RELEASEDATE='$(TODAY)' VERSION='$(VERSION)'
#	
#	@echo
#	# updating 'PUBDBVER' version string in config.mk
#	$(SEDINPLACE) 's/\( *PUBDBVER *= *\)\([0-9.][0-9.]*\)/\1$(VERSION)/' config.mk
#	
#	@echo
#	# adding modified files to the Git index
#	git add $(LOCALDATADIR)/$(PUBTSVFILE) MD5SUMS config.mk
#
#	@echo
#	# confirm commit looks OK
#	git -c color.ui=always status
#	@read -p "About to commit these changes, OK [Y/n]? " && \
#	if ! [[ -z $$REPLY || $${REPLY,,} =~ [yj] ]]; then \
#		echo "OK, bailing out ask you requested."; \
#		exit 1; \
#	fi
#	
#	@echo
#	# making new commit for DB build v$(VERSION)'
#	git commit -m"$(DBBUILDCOMMITMSG)$(VERSION)"
#
#	@echo
#	# adding annotated tag '$(PUBDBVERTAGPREFIX)$(VERSION)' for this release
#	@read -ep $$'One-line (≤50 char) description of what changed in this build:\n  > ' && \
#	git tag --annotate -m"$$REPLY" $(PUBDBVERTAGPREFIX)$(VERSION)
#	
#	@echo; \
#	echo "  $(UL)$(BOLD)$(BLUE)SUPER!$(RESET)"; \
#	echo; \
#	echo "  Created new $(PKGNAME) database build v$(VERSION)."; \
#	echo; \
#	echo "  Now, it would be a really good idea to:"; \
#	echo; \
#	echo "      $(BOLD)make site$(RESET)"; \
#	echo; \
#	echo "  to update the web site index."; \
#	echo; \
#	echo "  Then push the new commit/tag to your default Git remote, like this:"; \
#	echo; \
#	echo "      $(BOLD)git push && git push --tags$(RESET)"; \
#	echo; \
#	echo "  so a new release shows up on GitLab/GitHub."; \
#	echo
#
#user-provided-version:
#ifeq ($(VERSION),)
#	@echo >&2; \
#	echo "  $(UL)$(BOLD)$(RED)OH NOES!$(RESET)"; \
#	echo >&2; \
#	echo "  Expected a value for 'VERSION'. Try again like this:"; \
#	echo >&2; \
#	echo "      $(BOLD)make <target> VERSION=x.y.z$(RESET)" >&2; \
#	echo >&2; \
#	echo "  FYI, the current code version is $(BOLD)$(PUBSOURCEVER)$(RESET); DB build" \
#	     "is $(BOLD)$(PUBDBVER)$(RESET)."; \
#	echo >&2
#	@false
#else
#	@# FIXME: increment patchlevel by one if VERSION not provided
#	@if ! [[ $(VERSION) =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$$ ]]; then \
#		echo >&2; \
#		echo "(!!) $(ERROR) - bad build version;" \
#			 "expected x.y[.z], where x, y, and z are all integers." >&2; \
#		exit 1; \
#	fi
#endif
#
#work-tree-is-tidy:
#	@# For a DB release, the .tsv is the only "dirty" file allowed
#	# checking if Git work tree is clean
#	@if git status --porcelain | grep -v $(LOCALDATADIR)/$(PUBTSVFILE) | grep .; then \
#		echo >&2; \
#		echo "(!!) $(ERROR) - Git working tree is dirty;" \
#		     "commit changes and try again." >&2; \
#		exit 1; \
#	fi
#
#db-build-not-dupe:
#	@echo	
#	# checking that tag '$(PUBDBVERTAGPREFIX)$(VERSION)' doesn't already exist
#	@if git tag | grep $(PUBDBVERTAGPREFIX)$(VERSION); then \
#		echo >&2; \
#		echo "(!!) $(ERROR) - database build $(VERSION)" \
#		     "already exists." >&2; \
#		exit 1; \
#	fi
# vim: ft=make sw=4 ts=4 noet
