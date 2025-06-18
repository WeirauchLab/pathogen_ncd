TITLE = Pathogen N.C.D. supplemental data
SHELL = bash
FIND = find -type f -regex '[^~].*.\(pdf\|\(xls\|doc\|ppt\)x\)$$'
METAREGEX = (origResourceName|^(pdf|meta|dc):.*(author|publisher|creator)): .+
# less specific, but PDFs have `dc:language` and `dc:format` which are benign
#METAREGEX = (origResourceName|^(meta|dc):.+): .+

ifneq ($(TERM),)
BOLD := $(shell tput bold)
RED := $(shell tput setaf 1)
GREEN := $(shell tput setaf 2)
DIM := $(shell tput dim)
RESET := $(shell tput sgr0)
endif

.ONESHELL:

help:  # prints this help
	@perl -e "$$AUTOGEN_HELP_PL" $(MAKEFILE_LIST)

check:  # check if any data files contain sensitive metadata
	@source /etc/profile.d/lsf.sh
	module load tika
	count=0
	while read f; do \
		meta=$$( tika -m "$$f" | grep -E '$(METAREGEX)' ); \
		echo -ne "\n$(DIM)# $$f"; \
		if [[ -z $$meta ]]; then \
			echo " - OK$(RESET)"; \
		else \
			if [[ $$f =~ control ]]; then \
				echo " - EXPECTED FAIL$(RESET)"; \
			else \
				echo "$(RESET)"; \
				count=$$(( count + 1 )); \
			fi; \
			echo "$$meta" | sed -E "s/([^:]+: )(.*)/\1$(RED)\2$(RESET)/"; \
		fi; \
	done < <( $(FIND) )
	exit $$count

clean: cleanpdfs
cleanpdfs:  # remove metadata from PDFs (requires `pdftk`)
	@if ! type pdftk &>/dev/null; then
		echo "ERROR: required utility 'pdftk' not found in the PATH." >&2; \
		exit 1; \
	fi
	for pdf in *.pdf; do \
		pdftk "$$pdf" cat output "$$pdf".new || exit 1; \
		mv "$$pdf"{.new,}; \
	done


##
##  internals you can safely ignore
##
define AUTOGEN_HELP_PL
    use Term::ANSIColor qw(:constants);
    $$max = 0;
    @targets = ();
    print "\n  ", UNDERLINE, "Makefile targets - $(TITLE)", RESET, "\n\n";
    while (<>) {
        push @targets, [$$1, $$2] if /^(\w.+):[^=].*#\s*(.*)/;
        $$max = length($$1) if length($$1) > $$max;
    }
    foreach (@targets) {
        printf "    %s%smake %-$${max}s%s    %s\n", BOLD, BLUE, @$$_[0], RESET, @$$_[1];
    }
    print "\n";
endef
export AUTOGEN_HELP_PL
