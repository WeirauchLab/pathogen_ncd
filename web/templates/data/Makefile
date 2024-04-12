TITLE = Makefile tasks for Pathogen/NCD data files
SHELL = bash
THIS = $(firstword $(MAKEFILE_LIST))
export PYTHONPATH = $(abspath ../..)
PYTHON = ../../venv/bin/python3
BASENAME = {{ data.basename }}
ARCHIVEBASENAME = {{ data.archivebasename }}
BUILD = {{ data.build }}
RELEASEDATE = {{ site.releasedate }}


help:  # prints this help
	@$(PYTHON) -c 'from helpers import make_help; make_help("$(THIS)")'


zip: archives sums  # create .zip, .tar.gz archives [BASENAME=archive-prefix-, BUILD=x.y.z]
	@echo
	# compressed archives for release $(BUILD) created successfully


sums:  # re-compute checksums of *.zip, *.tar.gz
	@echo
	# computing checksums
	md5sum *.zip *.tar.gz > MD5SUMS


archives: valid-prefix-or-bail valid-build-or-bail
	@echo
	# prepping temp directory
	mkdir "$(ARCHIVEBASENAME)$(BUILD)"
	cp README.txt $(BASENAME).{sqlite,html,tsv} "$(ARCHIVEBASENAME)$(BUILD)"
	
	@echo
	# creating .tar.gz archive for Unixen
	tar czvf "$(ARCHIVEBASENAME)$(BUILD).tar.gz" "$(ARCHIVEBASENAME)$(BUILD)"
	
	#@echo
	## converting line endings to CR+LF (Windows) for the .zip version
	#cd "$(BASENAME)$(BUILD)" && \
	#unix2dos README.txt $(BASENAME).{tsv,html}
	
	@echo
	# creating .zip archive for the Windowsen
	@# Mac and Windows both create a subdir when extracting, so just add files
	cd "$(ARCHIVEBASENAME)$(BUILD)" && \
	zip ../$(ARCHIVEBASENAME)$(BUILD).zip *
	
	@echo
	@#@read -p "Remove build directory '$(BASENAME)$(BUILD)' [Y/n]? " &&
	@#if [[ -z $$REPLY || $${REPLY,,} =~ ^[yj] ]]; then
	rm -rf "$(ARCHIVEBASENAME)$(BUILD)"
	@#else
	@#	echo "(not touching build temp directory)";
	@#fi

clean:  # remove build temp directories
	@echo
	# remove build temporary directories
	-rm -r MD5SUMS $(BASENAME)[0-9]*.[0-9]*.[0-9]*

reallyclean: clean  # delete *all* generated files (run 'make' in parent to regenerate)
	@echo
	# remove all generated files
	-rm -r MD5SUMS README.txt $(PUBTSVFILE) $(PUBDBFILE) $(PUBHTMLTABLE)

purge: reallyclean  # (DESTRUCTIVE) deletes compressed archives, too
	@echo
	# remove compressed archives of database builds
	rm $(PUBDBZIP) $(PUBDBTARBALL) 


##
##  internals you can safely ignore
##

valid-build-or-bail:
ifeq ($(BASENAME),)
	@echo >&2; \
	echo "  $(UL)$(BOLD)$(RED)OH NOES!$(RESET)" >&2; \
	echo >&2; \
	echo "  Expected a valid identifier for 'BASENAME'. Try again like this:" >&2; \
	echo >&2; \
	echo "      $(BOLD)make <target> BASENAME=string$(RESET)" >&2; \
	echo >&2
	@false
else
	@if ! [[ $(BASENAME) =~ ^[-_a-zA-Z0-9]+$$ ]]; then \
		echo >&2; \
		echo "$(ERROR) - bad prefix;" \
			 "expected only alphanumerics, '-', and '_'." >&2; \
		exit 1; \
	fi
endif

valid-version-or-bail:
ifeq ($(BUILD),)
	@echo >&2; \
	echo "  $(UL)$(BOLD)$(RED)OH NOES!$(RESET)"; \
	echo >&2; \
	echo "  Expected a value for 'BUILD'. Try again like this:"; \
	echo >&2; \
	echo "      $(BOLD)make <target> BUILD=x.y.z$(RESET)" >&2; \
	echo >&2; \
	echo "  FYI, the current code version is $(BOLD)$(PUBSOURCEVER)$(RESET); DB build" \
	     "is $(BOLD)$(PUBDBVER)$(RESET)."; \
	echo >&2
	@false
else
	@# FIXME: increment patchlevel by one if BUILD not provided
	@if ! [[ $(BUILD) =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$$ ]]; then \
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


##
##  ANSI terminal colors (see 'man tput')
##

# don't set these if there isn't a $TERM environment variable
ifneq ($(strip $(TERM)),)
	BOLD := $(shell tput bold)
	RED := $(shell tput setaf 1)
	GREEN := $(shell tput setaf 2)
	YELLOW := $(shell tput setaf 3)
	BLUE := $(shell tput setaf 4)
	MAGENTA := $(shell tput setaf 5)
	UL := $(shell tput sgr 0 1)
	RESET := $(shell tput sgr0 )
endif

# the string "(default)", in green
DEFAULT := ($(GREEN)default$(RESET))
ERROR := $(BOLD)$(RED)ERROR$(RESET)
WARNING := $(BOLD)$(YELLOW)WARNING$(RESET)
DESTRUCTIVE := ($(BOLD)$(RED)destructive$(RESET))
