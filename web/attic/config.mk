SHELL = bash
# uncomment to help debugging
#MAKEFLAGS = --warn-undefined-variables
DEPLOYHOST = $(shell hostname -s)
DIRNAME = $(shell tr A-Z a-z <<<"$(PUBAUTHORLASTNAME)")$(PUBYEAR)
DEPLOYDIR = /var/www/html/pubs/$(DIRNAME)
SOURCEURL = https://tfinternal.research.cchmc.org/gitlab/mike/pathogen_ncd
ISDEVSERVER = $(shell test `hostname -s` = bmitfwebd1 && echo 1)
PUBLICURL = https://$(if $(ISDEVSERVER),tfwebdev.research,tf).cchmc.org/pubs/$(DIRNAME)
# where to find data files *here* in the source repository
LOCALDATADIR = public/data
# the (relative) path to those same files when they're deployed to the server
DEPLOYDATADIR = data
TODAY := $(shell LC_ALL=C date +'%e %B %Y' | sed 's/^ //')
THISYEAR := $(shell date +%Y)

# the default sheet name unless supplied
XLSSHEET = Sheet1

# commit message for new DB build (version # is appended)
DBBUILDCOMMITMSG = Release database build v
# don't display archives any older than this on the home page (expects 'x.y')
DBARCHIVECUTOFF = 0.0

# error messages if things go wrong
DBMISSINGMSG = [missing]
DBERRORMSG = [error]

##
##  all PUB* variables are available to use in .m4 templates
##

# all variables that start with 'PUB' are automatically made available to 'm4'
# when building files from *.in templates (e.g., index.html.in → index.in)
PUBSHORTNAME = pathogen_ncd
PUBPROPERNAME = After the Infection: A Survey of Pathogens and Non-communicable Human Disease

# version string for the repository (code + web site)
PUBSOURCEVER = 0.1.0
# version string for the database builds ('make dbuild')
PUBDBVER = 0.0.1
# updates © in the site footer dynamically to always show the current year
PUBSITECOPYRIGHTYEAR = $(THISYEAR)

PUBSOURCEURL = $(SOURCEURL)
PUBPUBLICURL = $(PUBLICURL)
PUBPUBLICATIONNAME = medRxiv
PUBYEAR = 2023
PUBCOPYRIGHTYEAR = $(THISYEAR)
PUBBRIEFTITLE = Pathogenic Organisms and NCDs
PUBTITLE = After the Infection: A Survey of Pathogens and Non-communicable Human Disease
PUBDOI = 10.1101/2023.09.14.23295428
PUBURL = https://www.medrxiv.org/content/$(PUBDOI)
PUBAUTHORLASTNAME = Lape
PUBCITEBRIEF = $(PUBAUTHORLASTNAME) et al., "$(PUBTITLE)", $(PUBPUBLICATIONNAME) ($(PUBYEAR))

PUBCONTACT1 = Matthew Weirauch
PUBEMAIL1 = Matthew.Weirauch@cchmc.org
PUBCONTACT2 = Leah Kottyan
PUBEMAIL2 = Leah.Kottyan@cchmc.org
PUBADMINEMAIL = tftoolsadmin@cchmc.org
# FIXME: URL-encode this somewhere else
PUBEMAILSUBJECT = $(subst $(space),%20,$(PUBBRIEFTITLE))
# workaround for subst()ing a literal space (see above)
null =
space = $(null) $(null)


##
##  downloads and other site internals
##

# table with the data; XMLHttpRequest'd into the index at time of access
PUBDBTABLE = $(PUBSHORTNAME)
PUBDBSQLITE = $(PUBSHORTNAME).sqlite

# what to tag new DB builds in Git (version # is appended)
PUBDBVERTAGPREFIX = db-build-
# what to name the archive file (version # is appended)
PUBDBARCHIVEBASENAME = $(PUBSHORTNAME)-$(PUBDBVERTAGPREFIX)
# the target of the "Download Supplemental Tables"
PUBSUPPLEMENTZIP = $(PUBSHORTNAME)-supplement.zip
# what file extensions from the `supplemental_data` directory should go *in*
# the supplement .zip file?
PUBSUPPLEMENTEXTS = *.xlsx *.pdf *.txt

# the *current* database archive name
PUBDBZIP = $(PUBDBARCHIVEBASENAME)$(PUBDBVER).zip
PUBDBTARBALL = $(PUBDBARCHIVEBASENAME)$(PUBDBVER).tar.gz
# loaded in as DataTables' 'columnDefs' via XHR
PUBCOLUMNCONFIG = columns.json
