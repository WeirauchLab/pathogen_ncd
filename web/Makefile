TITLE = Makefile tasks for Mike’s Pathogen/NCD project
SHELL = python
THIS = $(firstword $(MAKEFILE_LIST))
comma = ,
# these are the defaults
#TEMPLATES = templates
#PUBLIC = public
#SITECFG = site.toml
#PUBCFG = publication.toml
.ONESHELL:

help:  # prints this help
	@from helpers import make_help
	make_help('$(THIS)')

site:  # make public web site
	from helpers import process_templates
	process_templates()

serve:  # serve the site locally
	from helpers import serve
	serve($(if $(PORT),port='$(PORT)'))

devsetup: SHELL=bash
devsetup:  # set up a fresh local dev environment
	[[ -d venv ]] || python3 -m venv venv
	source venv/bin/activate
	pip install -r requirements.txt
	# FIXME: add to "dev" section of `pyproject.toml` or `setup.py` someday
	pip install ipython visidata
	
clean: SHELL=bash
clean:  # remove compiled bytecode and other detritus
	find . -path venv -prune -name "*.pyc"

##
##  internals
##

#site: db dbzip index data-readme data-footer $(MAKEFILE_LIST)  # build the web site
#	@echo
#	# created the database and associated static files for the web site
#
#
#deploy: site  # deploy the site to DEPLOYHOST (default: this host)
#	@echo
#	# limit to the host you're logged in to, for now
#	test $$(hostname -s) = $(DEPLOYHOST)
#	
#	# deploying the site to $(DEPLOYHOST)
#	rsync -av --exclude=".*.swp" --no-perms$(if $(DRYRUN), --dry-run) public/ $(DEPLOYDIR)
#
#
#index: public/index.html  # just rebuild the JavaScript + index.html
#public/index.html: \
#	templates/index.html.in public/js/index.js $(LOCALDATADIR)/meta.html \
#	$(LOCALDATADIR)/authors.html $(LOCALDATADIR)/$(PUBCOLUMNCONFIG) \
#	$(LOCALDATADIR)/$(PUBDBZIP) $(LOCALDATADIR)/$(PUBDBTARBALL) \
#	$(LOCALDATADIR)/$(PUBHTMLTABLE) .tsvcols .jsoncols
#	@echo
#	# make sure column names in the spreadsheet haven't changed
#	diff .tsvcols .jsoncols 
#	
#	@echo
#	# make sure the column widths sum up to at least *close* to 100
#	test $(COLUMNSUM) -gt 80 -a $(COLUMNSUM) -le 100
#	
#	@echo
#	# substitute macros into HTML index
#	m4 --prefix-builtins -DDEPLOYDATADIR='$(DEPLOYDATADIR)' $(M4DEFINES) $< > $@
#
#.tsvcols: $(LOCALDATADIR)/$(PUBTSVFILE)
#	head -1 $< | tr \\t \\n > $@
#
#.jsoncols: $(LOCALDATADIR)/$(PUBCOLUMNCONFIG)
#	jq -r '.[] | .name' $< | tail -n+3 > $@
#
#
#public/js/index.js: templates/index.js.in $(LOCALDATADIR)/$(PUBCOLUMNCONFIG)
#	@echo
#	# build the JavaScript for the index
#	m4 --prefix-builtins -DLOCALDATADIR="$(LOCALDATADIR)" $(M4DEFINES) $< > $@
#
#$(LOCALDATADIR)/%.html: $(LOCALDATADIR)/meta.json templates/%.tt bin/process.pl 
#	@echo
#	# build "meta" and "author" HTML fragments
#	bin/process.pl $< $*
#
#
#data-readme: $(LOCALDATADIR)/README.txt
#$(LOCALDATADIR)/README.txt: templates/README.txt.in $(MAKEFILE_LIST)
#	@echo
#	# updating the 'data' directory's README
#	cd $(LOCALDATADIR) && \
#	make readme PUBDBRELEASEDATE='$(PUBDBRELEASEDATE)' VERSION='$(if $(DBVER),$(DBVER),$(PUBDBVER))'
#
#data-footer: $(LOCALDATADIR)/footer.md
#$(LOCALDATADIR)/footer.md: templates/footer.md.in $(MAKEFILE_LIST)
#	@echo
#	# updating the 'data' directory's footer
#	cd $(LOCALDATADIR) && \
#	make footer VERSION='$(if $(DBVER),$(DBVER),$(PUBDBVER))'
#
#
#db: $(LOCALDATADIR)/$(PUBDBFILE) $(LOCALDATADIR)/$(PUBHTMLTABLE)  # create SQLite database [XLS=input.xls] (default: first match for *.xlsx)
#	@echo
#	# done building SQL database (and HTML table) from Excel spreadsheet
#
#
#dbzip: $(LOCALDATADIR)/$(PUBDBZIP) $(LOCALDATADIR)/$(PUBDBTARBALL)  # create compressed database bundles
#
#$(LOCALDATADIR)/$(PUBDBZIP):
#$(LOCALDATADIR)/$(PUBDBTARBALL):
#	cd $(LOCALDATADIR) && make zip VERSION='$(if $(DBVER),$(DBVER),$(PUBDBVER))'
#
#
## TODO: release versioning from Makefile or 'bumpversion'?
#release: did-provide-ver work-tree-not-dirty  # make a tagged Git release  [VERSION=x.y.z] (default: bump minor)
#	$(info unimplemented)
#
#
#drebuild:  # rebuild DB build [DBVER=x.y.z]
#	@echo
#	# rebuild archive for database build $(VERSION) without checking into Git
#ifeq ($(PUBDBRELEASEDATE),$(PUBDBMISSINGMSG))
#	# NOTE: no DB build tags found in Git history; using today as release date
#	cd $(LOCALDATADIR) && \
#	make zip RELEASEDATE='$(TODAY)' VERSION='$(if $(DBVER),$(DBVER),$(PUBDBVER))'
#else
#	cd $(LOCALDATADIR) && \
#	make zip RELEASEDATE='$(PUBDBRELEASEDATE)' VERSION='$(if $(DBVER),$(DBVER),$(PUBDBVER))'
#endif
#	
#	@echo; \
#	echo "  $(UL)$(BOLD)$(BLUE)OKAY!$(RESET)"; \
#	echo; \
#	echo "  Rebuilt $(PKGNAME) database build v$(if $(DBVER),$(DBVER),$(PUBDBVER))."; \
#	echo; \
#	echo "  Now, it would be a really good idea to:"; \
#	echo; \
#	echo "      $(BOLD)make site$(RESET)"; \
#	echo; \
#	echo "  to update the web site index."; \
#	echo
#
#
#dbuild: user-provided-version work-tree-is-tidy db-build-not-dupe  # create new tagged DB release [VERSION=x.y.z] (default: bump minor)
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
#
#$(LOCALDATADIR)/$(PUBHTMLTABLE): $(LOCALDATADIR)/$(PUBDBFILE) $(MAKEFILE_LIST)
#	@echo
#	# generating the .html version of the table from the SQLite database
#	
#	@if [[ ! -f $< ]]; then \
#		echo >&2; \
#		echo "(!!) $(ERROR) - no database file '$<'; try 'make db'." >&2; \
#		exit 1; \
#	fi
#	
#	@echo
#	# '$$TABLEFIXSED' adds <thead> and <tbody> tags
#	sqlite3 -html -header $< <<<"$$SELECTSQL" \
#	  | sed "$$TABLEFIXSED" \
#	  | tidy -i -q -f /dev/null --show-body-only yes \
#	  | sed '/^$$/d' \
#	  > $@
#	
#	@echo
#	# make sure the output file's not empty
#	test -s $@
#	
#
#$(LOCALDATADIR)/$(PUBDBFILE): $(LOCALDATADIR)/$(PUBTSVFILE) $(MAKEFILE_LIST)
#	@echo
#	# building SQLite database from the tab-delimited version
#	-sqlite3 $@ <<<"DROP TABLE IF EXISTS $(PUBDBTABLE);"
#	sqlite3 $@ <<<"$$IMPORTSQL"
#
#
## make the tab-delimited version from the Excel version
## requires 'catdoc' and Miller (https://github.com/johnkerl/miller)
#$(LOCALDATADIR)/$(PUBTSVFILE): $(XLSFILE)
#	@echo
#	@if [[ ! -f '$<' ]]; then \
#		echo >&2; \
#		echo "(!!) $(ERROR) - missing Excel spreadsheet." >&2; \
#		exit 1; \
#	fi
#	
#	# make sure 'in2csv' is available
#	@if ! which in2csv >/dev/null 2>&1; then \
#		echo >&2; \
#		echo "(!!) $(ERROR) - need 'in2csv' from csvkit;" \
#		     "use the supplied 'requirements.txt'." >&2; \
#		exit 1; \
#	fi
#	
#	@echo
#	# convert to tab-delimited, normalize header row
#	@# FIXME: does '--no-inference' not do what I thought? (see #39)
#	in2csv --format xls --sheet "$(XLSSHEET)" '$<' \
#		| mlr --icsv --otsv cat \
#		| sed '1{s/[^-A-Za-z0-9_\/[:space:]]//g; s/[- \/]/_/g}' \
#		> $@
#
#
#.PHONY: test tests
#tests: test
#test: site-is-up site-links-work  # run tests on live site
#
#site-is-up:
#	@echo
#	# make sure the site is accessible
#	curl -sfL $(PUBLICURL) >/dev/null
#	
#	@echo
#	# make sure the site's title is intact
#	curl -sfL $(PUBLICURL) | grep -q "$(PUBPROPERNAME)"
#
#site-links-work:
#	@if ! which xidel >/dev/null 2>&1; then \
#		echo >&2; \
#		echo "(!!) $(ERROR) - need Xidel 0.9.8 from https://www.videlibri.de/xidel.html" >&2; \
#		exit 1; \
#	fi
#	
#	@echo
#	# make sure the main links are working; first the .tar.gz file
#	tarball=$$( xidel -e '//a[contains(.,"download database")]/@href' $(PUBLICURL) ); \
#	curl -sSIL $(PUBLICURL)/$$tarball | grep 'Content-Type:.*/x-gzip'
#	
#	@echo
#	# now the Windows .zip format
#	zipfile=$$( xidel -e '//a[contains(.,"windows format")]/@href' $(PUBLICURL) ); \
#	curl -sSIL $(PUBLICURL)/$$zipfile | grep 'Content-Type:.*/zip'
#	
#	@echo
#	# make sure the publication link is working
#	xidel -e '//p[contains(.,"please cite")]/a[@href="$(PUBURL)"]' $(PUBLICURL) \
#	  | grep "$(PUBURL)"
#
#
#clean:  # clean generated HTML and JavaScript files
#	-rm public/index.html public/js/index.js \
#	    $(LOCALDATADIR)/{meta,authors}.html $(LOCALDATADIR)/index.html
#	@echo >&2; \
#	echo "  $(UL)$(BOLD)$(RED)HO THERE!$(RESET)" >&2; \
#	echo >&2; \
#	echo "  The $(BOLD)make clean$(RESET) target breaks the web site!" >&2; \
#	echo >&2; \
#	echo "  If you have done this *inside* the production site, you need to run" >&2; \
#	echo >&2; \
#	echo "      $(BOLD)make site$(RESET)" >&2; \
#	echo >&2; \
#	echo "  $(UL)right now$(RESET) to regenerate the site index!" >&2; \
#	echo >&2; \
#
#reallyclean: clean  # remove all generated files in public/data, too
#	cd $(LOCALDATADIR) && make reallyclean
#
#
###
###  helper functions for this Makefile only
###
#
## error messages if things go wrong
#DBMISSINGMSG = [missing]
#DBERRORMSG = [error]
#
## what do all the percentages add up to?
#COLUMNSUM := $(shell \
#	jq 'map(.width | select(.) | sub("%"; "")? | tonumber) | add' \
#		$(LOCALDATADIR)/$(PUBCOLUMNCONFIG) \
#)
#
## get a database build release history from Git tags (script in 'bin' dir.)
## later, this will get tucked into the 'index.html' by an M4 macro
## FIXME: write to a temp file, so 'make' can compare timestamps
#define GITPREVIOUSRELEASES
#bin/git-previous-releases -p -r -x "$(PUBDBVERTAGPREFIX)" -s $(DBARCHIVECUTOFF) | \
#	awk -F $$'\t' '{ \
#		printf "<dl>"; \
#		printf "<dt>" $$1 "<a href=\"$(DEPLOYDATADIR)/$(PUBDBZIP)\">.zip</a>, "; \
#		printf "<a href=\"$(DEPLOYDATADIR)/$(PUBDBTARBALL)\">.tar.gz</a></dt>"; \
#		printf "<dd>" $$2 "</dd>"; \
#		printf "</dl>\n" \
#	}'
#endef
#
## FIXME: redirect to a file instead; make's '$(shell …)' always strips newlines
#PUBDBRELEASEHISTORY := $(shell $(GITPREVIOUSRELEASES))
#
#PUBDBRELEASEDATE = $(call date_from_epoch,$(call epoch_from_tag,$(PUBDBVERTAGPREFIX)$(PUBDBVER)))
#
## there weren't *any* matching tags, maybe it's a brand new repo w/ no history?
#ifeq ($(PUBDBRELEASEDATE),)
#	PUBDBRELEASEDATE = $(DBMISSINGMSG)
#endif
#
## compute sizes (in KB) of both archive types
#ifeq ($(shell test -f '$(LOCALDATADIR)/$(PUBDBZIP)' && echo 1),1)
#	# macOS/BSD 'date' does not support GNU long options like '--reference'
#	PUBDBZIPSIZE = $(call kbsize,$(LOCALDATADIR)/$(PUBDBZIP)) KB
#else
#	PUBDBZIPSIZE = $(DBMISSINGMSG)
#endif
#
#ifeq ($(shell test -f '$(LOCALDATADIR)/$(PUBDBTARBALL)' && echo 1),1)
#	PUBDBTARBALLSIZE = $(call kbsize,$(LOCALDATADIR)/$(PUBDBTARBALL)) KB
#else
#	PUBDBTARBALLSIZE = $(DBMISSINGMSG)
#endif
#
#
## counts of records from the SQLite database; used to update the HTML index
#RECCOUNTSQL = SELECT COUNT(*) FROM $(PUBDBTABLE);
#DISEASECOUNTSQL = SELECT COUNT(DISTINCT disease) FROM $(PUBDBTABLE);
#
#ifeq ($(shell test -f '$(LOCALDATADIR)/$(PUBDBFILE)' && echo 1),1)
#	PUBRECCOUNT := $(shell sqlite3 $(LOCALDATADIR)/$(PUBDBFILE) <<<"$(RECCOUNTSQL)")
#	PUBDISEASECOUNT := $(shell sqlite3 $(LOCALDATADIR)/$(PUBDBFILE) <<<"$(DISEASECOUNTSQL)")
#else
#	PUBRECCOUNT = $(DBERRORMSG)
#	PUBDISEASECOUNT = $(DBERRORMSG)
#endif


# SQLite has kind of a built-in AUTOINCREMENT key for each record: 'rowid'
DBCOLUMNS = rowid *
#DBCOLUMNS = Viral_family Species Name Aliases Notes

# add <thead> and <tbody> tags to output of 'sqlite --html'
# FIXME: using an ERB or Jinja template might be more straightforward
define TABLEFIXSED
	# add <THEAD> at the top
	1i<THEAD>

	# add a blank column for the record detail control
	s/<TR><TH>/<TR><TH><\/TH><TH>/

	# look for a <th> at the beginning of a line (maybe indented)
	/^ *<TH>/ {
		:a
		# take the next line into the pattern buffer
		N
		# if it's the last <th>, add thead close / tbody open tags
		s/<\/TH>\n<\/TR>/&<\/THEAD><TBODY>/
		# if a substitution was made, branch (to end)
		t
		# otherwise, go back to ":a"
		ba
	}

	# add a blank column for the record detail control
	s/<TR><TD>/<TR><TD class="details-control"><\/TD><TD>/

	# tack on </TBODY> at the end
	$$a</TBODY>
endef
export TABLEFIXSED

user-provided-version:
ifeq ($(VERSION),)
	@echo >&2; \
	echo "  $(UL)$(BOLD)$(RED)OH NOES!$(RESET)"; \
	echo >&2; \
	echo "  Expected a value for 'VERSION'. Try again like this:"; \
	echo >&2; \
	echo "      $(BOLD)make <target> VERSION=x.y.z$(RESET)" >&2; \
	echo >&2; \
	echo "  FYI, the current code version is $(BOLD)$(PUBSOURCEVER)$(RESET); DB build" \
	     "is $(BOLD)$(PUBDBVER)$(RESET)."; \
	echo >&2
	@false
else
	@# FIXME: increment patchlevel by one if VERSION not provided
	@if ! [[ $(VERSION) =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$$ ]]; then \
		echo >&2; \
		echo "(!!) $(ERROR) - bad build version;" \
			 "expected x.y[.z], where x, y, and z are all integers." >&2; \
		exit 1; \
	fi
endif

work-tree-is-tidy:
	@# For a DB release, the .tsv is the only "dirty" file allowed
	# checking if Git work tree is clean
	@if git status --porcelain | grep -v $(LOCALDATADIR)/$(PUBTSVFILE) | grep .; then \
		echo >&2; \
		echo "(!!) $(ERROR) - Git working tree is dirty;" \
		     "commit changes and try again." >&2; \
		exit 1; \
	fi

db-build-not-dupe:
	@echo	
	# checking that tag '$(PUBDBVERTAGPREFIX)$(VERSION)' doesn't already exist
	@if git tag | grep $(PUBDBVERTAGPREFIX)$(VERSION); then \
		echo >&2; \
		echo "(!!) $(ERROR) - database build $(VERSION)" \
		     "already exists." >&2; \
		exit 1; \
	fi

# vim: ts=4 sw=4 noet
=======
#
#
## read the TSV into SQLite
#define IMPORTSQL
#.mode tab
#.import $(LOCALDATADIR)/$(PUBTSVFILE) $(PUBDBTABLE)
#endef
#export IMPORTSQL
#
## SQLite has kind of a built-in AUTOINCREMENT key for each record: 'rowid'
#DBCOLUMNS = rowid *
##DBCOLUMNS = Viral_family Species Name Aliases Notes
#
#define SELECTSQL
#SELECT $(call commafy,$(DBCOLUMNS)) FROM $(PUBDBTABLE);
#endef
#export SELECTSQL
#
## add <thead> and <tbody> tags to output of 'sqlite --html'
## FIXME: using an ERB or Jinja template might be more straightforward
#define TABLEFIXSED
#	# add <THEAD> at the top
#	1i<THEAD>
#
#	# add a blank column for the record detail control
#	s/<TR><TH>/<TR><TH><\/TH><TH>/
#
#	# look for a <th> at the beginning of a line (maybe indented)
#	/^ *<TH>/ {
#		:a
#		# take the next line into the pattern buffer
#		N
#		# if it's the last <th>, add thead close / tbody open tags
#		s/<\/TH>\n<\/TR>/&<\/THEAD><TBODY>/
#		# if a substitution was made, branch (to end)
#		t
#		# otherwise, go back to ":a"
#		ba
#	}
#
#	# add a blank column for the record detail control
#	s/<TR><TD>/<TR><TD class="details-control"><\/TD><TD>/
#
#	# tack on </TBODY> at the end
#	$$a</TBODY>
#endef
#export TABLEFIXSED
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
# vim: ft=python sw=4 ts=4 noet
