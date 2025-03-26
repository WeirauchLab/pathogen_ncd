TITLE = Makefile tasks for Mike’s Pathogen/NCD project
SHELL = bash
THISMAKEFILE = $(firstword $(MAKEFILE_LIST))
PYTHON = venv/bin/python3
BIND = 127.0.0.1
PORT = 8080
CONTAINER = web
# the UID of the user running this Makefile; used to `chown` the bind mount for
# DEPLOYDIR so you can update it from the host side with `make deploy`; can't
# just read this from the environment because it's not exported by default; see
# https://unix.stackexchange.com/q/541417
#
# this whole rigmarole just to get a variable inside a Dockerfile is irritating
#LOCALUID = $(shell id -u)
config = $(shell python -m lib.config --json --get $(1) | jq -r)
deploydir = $(call config,site.deploydir)
datasubdir = $(call config,data.artifacts.subdir)
deploydatadir = $(deploydir)/$(datasubdir)

help: venv  # prints this help
	@$(PYTHON) -m lib.help $(THISMAKEFILE)

config: venv  # pretty-prints the parsed site and publication configs
	@$(PYTHON) -m lib.config$(if $(KEY), --get $(KEY))

site: deploy
deploy: .static_files_copied .downloads_created .templates_processed  # (alias: site) copies static assets, builds templates and downloads

# copies static assets like theme files and JavaScript libs in place
static: .static_files_copied
.static_files_copied: static/theme/* .datatables_installed .npm_installed
	rsync -av --copy-links --exclude=".*.swp" --exclude=node_modules \
		--exclude="package*.json" --no-perms$(if $(DRYRUN), --dry-run) \
		static/ $(deploydir)
	touch $@

datatables: .datatables_installed
# using the DataTables download builder was easier than trying to 'npm install'
# and then figure out which source files to include in <script> tags -- a
# complete nightmare
#
# instead, see https://datatables.net/download and right-click to copy the URL
# from the "Download files" button here, then run this target
DATATABLES_DOWNLOAD_BUILDER_URL	= https://datatables.net/download/builder?dt/dt-2.2.2/b-3.2.2/b-html5-3.2.2/fh-4.0.1
.datatables_installed:
	-rm static/vendor/DataTables.zip
	cd static/vendor && curl -sLOJ $(DATATABLES_DOWNLOAD_BUILDER_URL)
	cd static/vendor && unzip -ou DataTables.zip
	rm static/vendor/DataTables.zip
	touch $@

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
.templates_processed: templates/* templates/*/* venv
	$(PYTHON) -m lib.templates
	# create a symlink from theme/dot-htaccess to anywhere that needs it
	cd $(deploydatadir) && ln -sf ../theme/dot-htaccess .htaccess
	touch $@

data: downloads
downloads: .downloads_created  # [data] creates downloadable archives from supplemental datasets
.downloads_created: .transformed .converted .figures_created .archives_created $(deploydatadir)/SHA1SUMS
	touch $@

transform: .transformed
.transformed:
	@echo
	mkdir -p $(deploydatadir)
	$(PYTHON) -m lib.transform
	touch $@

convert: .converted
.converted:
	@echo
	mkdir -p $(deploydatadir)
	$(PYTHON) -m lib.convert
	touch $@

figuresinfile = $(call config,data.figures.infilename)
figuresoutfile = $(call config,data.figures.outfilename)
figures: .figures_created
.figures_created:
	@echo
	mkdir -p $(deploydatadir)
	cp -f $(figuresinfile) $(deploydatadir)/$(figuresoutfile)
	touch $@

resultsarchive = $(call config,data.artifacts.resultsarchive)
resultstarball = $(call config,data.artifacts.resultstarball)
supplementarchive = $(call config,data.artifacts.supplementarchive)

archives: .archives_created
.archives_created: $(deploydatadir)/$(resultsarchive) $(deploydatadir)/$(resultstarball) $(deploydatadir)/$(supplementarchive)
	touch $@

# this has to be processed first, so it can be put inside the archives, which
# need to be present before the other templates can be processed (since they
# refer to the file size of the archives)!
$(deploydatadir)/README.txt: templates/$(datasubdir)/README.txt
	$(PYTHON) -m lib.templates $(datasubdir)/README.txt

$(deploydatadir)/$(resultsarchive): $(deploydatadir)/README.txt
	@echo
	-rm $@
	mkdir -p $(deploydatadir)
	cd $(deploydatadir) && \
	zip -r $(resultsarchive) README.txt *Results.xlsx

pubyear = $(call config,pub.year)
archivesubdir = $(call config,data.artifacts.basename)_$(pubyear)

# like the .zip, except tarballs work better when everything's in a subdir
$(deploydatadir)/$(resultstarball): $(deploydatadir)/README.txt
	@echo
	-rm -r $@ $(deploydatadir)/$(archivesubdir)
	mkdir -p $(deploydatadir)
	cd $(deploydatadir) && \
	mkdir $(archivesubdir) && \
	cp README.txt *Results.tsv $(archivesubdir) && \
	tar czvf $(resultstarball) $(archivesubdir)
	rm -r $(deploydatadir)/$(archivesubdir)

$(deploydatadir)/$(supplementarchive): $(deploydatadir)/README.txt
	@echo
	-rm $@
	mkdir -p $(deploydatadir)
	zip --junk-paths $@ ../supplemental_data/supplemental_dataset_*.xlsx
	zip --junk-paths $@ $<

sums: checksums
checksum: checksums
checksums: $(deploydatadir)/SHA1SUMS  # [data] re-computes checksums of downloadable archives
$(deploydatadir)/SHA1SUMS:
	@echo
	# computing checksums
	cd $(deploydatadir) && \
	sha1sum *.zip *.tar.gz > SHA1SUMS

up: serve
## not currently used; see comments in `Dockerfile`
serve: venv  # [dev] (alias: up) serves site locally using Docker
ifneq ($(BUILD)$(REBUILD),)
	@#docker compose build --build-arg LOCALUID=$(LOCALUID) $(CONTAINER)
	docker compose build $(CONTAINER)
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
	$(PYTHON) -m webbrowser -t http://$(BIND):$(PORT) >/dev/null

check: lint
lint: venv  # [dev] (alias: check) checks all Python source files for syntax errors
	$(PYTHON) -m compileall -f lib

publicurl = $(call config,site.deploy.publicurl)
sitetitle = $(call config,site.title)

tests: test
test: isitup dothelinkswork  # [dev] run some simple functional tests on live web site

isup: isitup
isitup:  # [dev] (alias: isup) quick check to see if the site is up
	@echo
	# make sure the site is accessible
	curl -sfL $(publicurl) >/dev/null
	
	@echo
	# make sure the site's title is intact
	curl -s $(publicurl) | grep --color '$(sitetitle)'

puburl = $(call config,pub.url)
pubdoi = $(call config,pub.pubdoi)
linkcontains = $$(curl -s $(publicurl) | xmllint --html --xpath 'string(//a[contains(.,"$(1)")]/@href)' -)
dothelinkswork:
	@if ! which xmllint >/dev/null 2>&1; then \
		echo >&2; \
		echo "ERROR: required external utility 'xmllint' is missing." >&2; \
		echo "       Try installing from your distro's package manager." >&2; \
		exit 1; \
	fi
	
	@echo
	# make sure the main links are working; first the .zip file
	tarball=$(call linkcontains,Download Results); \
	curl -sSIL $(publicurl)/$$tarball | grep --color 'Content-Type:.*/zip'
	
	@echo
	# now the figures & tables
	figuresandtables=$(call linkcontains,Download Figures); \
	curl -sSIL $(publicurl)/$$figuresandtables \
 	  | grep --color 'Content-Type:.*/pdf'
	
	@echo
	# now the supplemental datasets
	supplemental=$(call linkcontains,Download Supplemental); \
	curl -sSIL $(publicurl)/$$supplemental | grep --color 'Content-Type:.*/zip'
	
	@echo
	# now the Unix .tar.gz file
	tarball=$(call linkcontains,Unix LF line endings); \
	curl -sSIL $(publicurl)/$$tarball | grep --color 'Content-Type:.*/x-gzip'
	
	@echo
	# make sure the publication link is working
	curl -s $(publicurl) \
	  | xmllint --html --xpath '//p[contains(.,"Please cite")]/a/@href' - \
	  | grep --color "$(puburl)"


clean:  # removes compiled bytecode and other detritus
	# Python precompiled bytecode inside the virtualenv
	-find venv -prune -name "*.pyc"
	# same within the helper library
	-rm -rf lib/__pycache__

distclean: clean cleanjs  # `make clean` plus removes checkpoint files and Node modules
	# remove all checkpoint files like `.transformed`, `.converted`, et al.
	-rm .*ed

cleanjs:
	-rm -rf static/node_modules


venv:
	@if ! [[ -x $(PYTHON) ]]; then \
		echo "Setting up virtual environment and installing dependencies…" >&2; \
		if [[ $$(python3 --version) =~ 3.([789]|[1-9][0-9]) ]]; then \
			python3 -m venv venv; \
		else \
			if [[ $$(uname -s) != Linux ]] || ! scl enable rh-python38 -- python3 -m venv venv; then \
				echo "ERROR: Please manually create a Python ≥3.7 virtualenv at 'venv' and try again." >&2; \
				exit 1; \
			fi; \
		fi; \
		if source venv/bin/activate && pip install -r requirements.txt; then \
			echo "Finished setting up virtualenv" >&2; \
		else \
			echo "ERROR: Unable to create the virtualenv. Please troubleshoot." >&2; \
			exit 1; \
		fi; \
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
