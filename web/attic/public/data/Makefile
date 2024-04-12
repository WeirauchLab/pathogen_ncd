# for definitions of DB, TSV, HTML, colors, etc. (has an "include guard" so it
# won't be re-included if we are called from the parent Makefile)
include ../../config.mk
include ../../helpers.mk

READMEFILE = README.txt
SUMSFILE = MD5SUMS
PREFIX ?= $(PUBDBARCHIVEBASENAME)


help:  # prints this help
	@perl -e "$$AUTOGEN_HELP_PL" Makefile


zip: archives sums  # create .zip, .tar.gz archives [PREFIX=archive-prefix-, VERSION=x.y.z]
	@echo
	# compressed archives for release $(VERSION) created successfully


sums:  # re-compute checksums of *.zip, *.tar.gz
	@echo
	# computing checksums
	md5sum *.zip *.tar.gz > $(SUMSFILE)


archives: valid-prefix-or-bail valid-version-or-bail readme footer
	@echo
	# prepping temp directory
	mkdir "$(PREFIX)$(VERSION)"
	cp $(READMEFILE) $(PUBDBFILE) $(PUBTSVFILE) $(PUBHTMLTABLE) "$(PREFIX)$(VERSION)"
	
	@echo
	# creating .tar.gz archive for Unixen
	tar czvf "$(PREFIX)$(VERSION).tar.gz" "$(PREFIX)$(VERSION)"
	
	@echo
	# converting line endings to CR+LF (Windows) for the .zip version
	cd "$(PREFIX)$(VERSION)" && \
	unix2dos $(READMEFILE) $(PUBTSVFILE) $(PUBHTMLTABLE)
	
	@echo
	# creating .zip archive for the Windowsen
	@# Mac and Windows both create a subdir when extracting, so just add files
	cd "$(PREFIX)$(VERSION)" && \
	zip ../$(PREFIX)$(VERSION).zip *
	
	@echo
	@#@read -p "Remove build directory '$(PREFIX)$(VERSION)' [Y/n]? " &&
	@#if [[ -z $$REPLY || $${REPLY,,} =~ ^[yj] ]]; then
	rm -rf "$(PREFIX)$(VERSION)"
	@#else
	@#	echo "(not touching build temp directory)";
	@#fi


readme: $(READMEFILE)  # update the README
# valid-version-or-bail valid-releasedate-or-warn ← not used in README.txt.in
$(READMEFILE): ../../templates/$(READMEFILE).in
	@echo
	# updating README
	m4 --prefix-builtins $(M4DEFINES) $< > $@
	
	# update release date (second pass)
ifeq ($(PUBDBRELEASEDATE),)
	m4 -D PUBDBRELEASEDATE="$(PUBDBRELEASEDATE)" $@ > $@.tmp
	command mv $@.tmp $@
else
	m4 -D PUBDBRELEASEDATE="$(TODAY)" $@ > $@.tmp
	command mv $@.tmp $@
endif

footer: footer.md  # update the site footer
footer.md: ../../templates/footer.md.in
	@echo
	# updating '$@'
	m4 --prefix-builtins $(M4DEFINES) $< > $@


clean:  # remove build temp directories
	@echo
	# remove build temporary directories
	-rm -r $(SUMSFILE) $(PREFIX)[0-9]*.[0-9]*.[0-9]*

reallyclean: clean  # delete *all* generated files (run 'make' in parent to regenerate)
	@echo
	# remove all generated files
	-rm -r $(SUMSFILE) $(READMEFILE) $(PUBTSVFILE) $(PUBDBFILE) $(PUBHTMLTABLE)

purge: reallyclean  # (DESTRUCTIVE) deletes compressed archives, too
	@echo
	# remove compressed archives of database builds
	rm $(PUBDBZIP) $(PUBDBTARBALL) 


##
##  internals you can safely ignore
##

valid-prefix-or-bail:
ifeq ($(PREFIX),)
	@echo >&2; \
	echo "  $(UL)$(BOLD)$(RED)OH NOES!$(RESET)" >&2; \
	echo >&2; \
	echo "  Expected a valid identifier for 'PREFIX'. Try again like this:" >&2; \
	echo >&2; \
	echo "      $(BOLD)make <target> PREFIX=string$(RESET)" >&2; \
	echo >&2
	@false
else
	@if ! [[ $(PREFIX) =~ ^[-_a-zA-Z0-9]+$$ ]]; then \
		echo >&2; \
		echo "$(ERROR) - bad prefix;" \
			 "expected only alphanumerics, '-', and '_'." >&2; \
		exit 1; \
	fi
endif

valid-version-or-bail:
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
		echo "(!!) $(ERROR) - bad version;" \
			 "expected x.y[.z], where x, y, and z are all integers." >&2; \
		exit 1; \
	fi
endif

valid-releasedate-or-warn:
ifeq ($(RELEASEDATE),)
	@echo >&2; \
	echo "$(WARNING) - no RELEASEDATE given; defaulting to $(TODAY)"
endif
