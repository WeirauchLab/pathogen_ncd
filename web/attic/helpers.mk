ifndef __HELPERS_MK
__HELPERS_MK = 1

##
##  helper functions used by all Makefiles in this project
##

define AUTOGEN_HELP_PL
    use Term::ANSIColor qw(:constants);
    $$max = 0;
    @targets = ();
    print "\n  ", UNDERLINE, "Makefile targets - $(PUBSHORTNAME)", RESET, "\n\n";
    while (<>) {
        push @targets, [$$1, $$2] if /^(\w.+):.*#\s*(.*)/;
        $$max = length($$1) if length($$1) > $$max;
    }
    foreach (@targets) {
        printf "    %s%smake %-$${max}s%s    %s\n", BOLD, BLUE, @$$_[0], RESET, @$$_[1];
    }
    print "\n";
endef
export AUTOGEN_HELP_PL

# collect all PUB* variables and turn them into '-D' options for m4
M4DEFINES = $(foreach V,$(filter PUB%,$(.VARIABLES)),-D $V='$($V)')

# sed's "inplace" (-i) option differs between platforms, macOS doesn't have
# a 'tac' (it has 'rev'), and 'stat' format specifiers differ
ifeq ($(shell uname -s),Linux)
	SEDINPLACE = sed -i
	TAC = tac
	STATSIZE = stat -c %s
	date_from_epoch = $(shell LC_ALL=C date --date="@$(1)" +'%e %B %Y' 2>/dev/null| sed 's/^ //')
else
	SEDINPLACE = sed -i ''
	TAC = tail -r
	STATSIZE = stat -f %z
	date_from_epoch = $(shell LC_ALL=C date -r $(1) +'%e %B %Y' 2>/dev/null| sed 's/^ //')
endif

# return file size of $1 in KB
kbsize = $(shell bc <<<"$$($(STATSIZE) '$1')/1024")

# separate arguments by commas (for SQL SELECT statements)
# source: https://stackoverflow.com/a/29319726/785213
commafy = $(foreach W,$(filter-out $(lastword $1),$1),$W,) $(lastword $1)

# (not currently used) create SUBSTR SQL statements from arguments
substrfy = $(foreach W,$(filter-out $(lastword $1),$1),SUBSTR($W,1,$(MAXLEN)) AS $W,) $(lastword $1)

# function to get Unix epoch seconds from a Git (annotated) tag
epoch_from_tag = $(shell git --no-pager log -1 --format=%at $(1))

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

endif  # __HELPERS_MK
