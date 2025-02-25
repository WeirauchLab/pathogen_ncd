# Name:     ukb_phecode_translation_pub.R
# Author:   Mike Lape
# Date:     2024
# Description:
#
#   This script handles the translation of ICD data from UKB into Phecodes 
#   using the Phewas v0.99.6.1 library


# Run on R/4.0.2

# Start a timer
full_st = Sys.time()

# Load required libraries ####
suppressMessages(library(tidyr))
suppressMessages(library(dplyr))
suppressMessages(library(stringr))
suppressMessages(library(data.table))
suppressMessages(library(vroom))
suppressMessages(library(PheWAS))
suppressMessages(library(argparse))
suppressMessages(library(pryr))
suppressMessages(library(writexl))


# Get package versions
R_VERSION = R.version$version.string
PHEWAS_VERSION = as.character(packageVersion("PheWAS"))
SESSION_INFO = sessionInfo()

OUT_FILE_DATE = format(Sys.Date(), "%Y_%m_%d")

# Set some global constants ####
LOCAL_COPY_PATH =  "/data/pathogen_ncd"

# Important directories
CODE_DIR    = paste0(LOCAL_COPY_PATH, '/code/phecoding')
PHE_DIR     = paste0(LOCAL_COPY_PATH, '/phecode')
DIAG_DIR    = paste0(PHE_DIR, '/ukb/ukb_proc')
OUT_DIR     = paste0(PHE_DIR, '/phecode_results/ukb/translation')
LOG_DIR     = paste0(OUT_DIR, '/logs')
PHE_REF_DIR = paste0(PHE_DIR, '/ref_files') 

#Access the parsed arguments
INPUT_DIAG_FN <- paste0(PHE_DIR, '/ukb/ukb_proc/all_ukb_prepped_for_phecode.tsv')
INPUT_DIAG_FN = basename(INPUT_DIAG_FN)
CHUNK_NAME = gsub('_prepped_for_phecode.tsv', '', INPUT_DIAG_FN)

# Make any missing directories
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(LOG_DIR, recursive = TRUE, showWarnings = FALSE)

# Important files
# Sex data extracted from full demo data
SEX_FN = paste0(LOCAL_COPY_PATH, '/procd/cov_dat.csv')

# Full path to input diagnoses chunks file
INPUT_DIAG_FP = paste0(DIAG_DIR, '/', INPUT_DIAG_FN)

# Two output file paths
SINGLE_FN = paste0(OUT_DIR, '/', CHUNK_NAME, '_one_min_code_cnt_', OUT_FILE_DATE, '_phecode_translation.xlsx')
SINGLE_FN_TSV = paste0(OUT_DIR, '/', CHUNK_NAME, '_one_min_code_cnt_', OUT_FILE_DATE, '_phecode_translation.tsv')


# Log file
LOG_FN = paste0(LOG_DIR, "/", CHUNK_NAME, "_", OUT_FILE_DATE, ".log")
con <- file(LOG_FN, open = "wt")
close(con)

# Phecode ref files
PHE_VOCAB_FN     = paste0(PHE_REF_DIR, "/orig_phecode_map_1.2024.csv")
PHE_VOCAB_UKB_FN = paste0(PHE_REF_DIR, "/icd9cm_w_icd10_phecode_map_for_ukb.csv")
PHE_ANNO_FN      = paste0(PHE_REF_DIR, "/original_phecodes_pheinfo.csv")
PHE_EXCL_FN      = paste0(PHE_REF_DIR, "/original_phecodes_exclusion.csv")
PHE_SEX_SPEC_FN  = paste0(PHE_REF_DIR, "/original_phecodes_gender_restriction.csv")
PHE_ROLLUP_FN    = paste0(PHE_REF_DIR, "/phecode_rollup_map_1.2024.csv")


# Define some helper functions ####
# Helper function to return current date and time in square brackets
ts <- function() {
  ct <- Sys.time()
  ft <- format(ct, "%Y-%m-%d %H:%M:%S %Z")
  result <- paste0("[", ft, "]")
  return(result)
}

# Logging function
log_it <- function(log_msg) {
  cat(log_msg)
  str_log <- sub("[ \t\n\r]+$", "", log_msg)
  write(str_log, LOG_FN, append = TRUE)
}

# Start logging and getting going ####
log_it(paste0(ts(), "Setting up environment:"))
log_it(paste0('\t\t\t    R version:    ', R_VERSION))
log_it(paste0('\t\t\t    User Input:   ', INPUT_DIAG_FN))
log_it(paste0('\t\t\t    Work Base:    ', PHE_DIR))

log_it(paste0('\t\t\t    Chunk Path:   ', 
             gsub(PHE_DIR, '', INPUT_DIAG_FP)))
log_it(paste0('\t\t\t    Chunk Name:   ', 
             gsub(PHE_DIR, '', CHUNK_NAME)))
log_it(paste0('\t\t\t    Log File:     ', 
             gsub(PHE_DIR, '', LOG_FN)))
log_it(paste0('\t\t\t    Single Ouput: ', 
             gsub(PHE_DIR, '', SINGLE_FN)))
log_it(paste0('\t\t\t    Single Ouput TSV: ', 
              gsub(PHE_DIR, '', SINGLE_FN_TSV)))

log_it(paste0(ts(), "Loading all the Phecoding data\n"))
log_it(paste0('\t\t\t    PheWAS Vers:        ', PHEWAS_VERSION))
log_it(paste0('\t\t\t    Ref File Home       ', PHE_REF_DIR))
log_it(paste0('\t\t\t    UKB Vocab File:     ', 
             gsub(PHE_REF_DIR, '', PHE_VOCAB_UKB_FN)))
log_it(paste0('\t\t\t    Annotation File:    ', 
             gsub(PHE_REF_DIR, '', PHE_ANNO_FN)))
log_it(paste0('\t\t\t    Exclusion File:     ', 
             gsub(PHE_REF_DIR, '', PHE_EXCL_FN)))
log_it(paste0('\t\t\t    Sex-Specific File:  ', 
             gsub(PHE_REF_DIR, '', PHE_SEX_SPEC_FN)))
log_it(paste0('\t\t\t    Rollup File:        ', 
             gsub(PHE_REF_DIR, '', PHE_ROLLUP_FN), '\n'))


# Setup PheWAS stuff ####
# Trying to closely follow the instructions from their site:
# https://wei-lab.app.vumc.org/phecode


# Table connecting ICD/SNOMED code to Phecode
# Map for international codes (ICD10 not ICD10-CM)
vocab_ukb_map <- vroom(PHE_VOCAB_UKB_FN, 
                       .name = janitor::make_clean_names, 
                       delim = ",", progress = FALSE,
                       col_types = 
                         c(vocabulary_id = "c", 
                           code = "c", 
                           phecode = "c")
)



# This contains descriptions for each Phecode including the default color for
# PheWAS plots, which is not important for us
anno_file <- vroom(PHE_ANNO_FN, 
                   .name = janitor::make_clean_names, 
                   delim = ",", progress = FALSE, 
                   col_types = 
                     c(phecode = "c", 
                       description = "c", 
                       groupnum = "double", 
                       group = "c", 
                       color = "c")
)

# I think this is one column of Phecodes and another column of Phecodes from 
# which this person should be excluded.
exlude_map <- vroom(PHE_EXCL_FN, 
                    .name = janitor::make_clean_names, 
                    delim = ",", progress = FALSE, 
                    col_types = 
                      c(code = "c", 
                        exclusion_criteria = "c")
)

# Phecode with a column for T/F for whether this Phecode represents a male
# only disease and another T/F for if this Phecode is female only
#  Male only    34
#  Female only  130
sex_spec_map <- vroom(PHE_SEX_SPEC_FN, 
                      .name = janitor::make_clean_names, 
                      delim = ",", progress = FALSE, 
                      col_types = 
                        c(phecode = "c", 
                          male_only = "logical", 
                          female_only = "logical")
)

# Has 2 columns a Phecode and then a Phecode unrolled, but specifically for row 
# 2 below I don't understand how the unrolled code of 008 is shorter than the 
# presumed rolled code of 008.5, unless we just use these terms differently
# code   phecode_unrolled
# <chr>  <chr>           
# 1 008    008             
# 2 008.5  008             
# 3 008.5  008.5           
# 4 008.51 008             
# 5 008.51 008.5           
# 6 008.51 008.51
rollup_map <- vroom(PHE_ROLLUP_FN, 
                    .name = janitor::make_clean_names, 
                    delim = ",", progress = FALSE, 
                    col_types = 
                      c(code = "c", 
                        phecode_unrolled = "c")
)


# Apparently createPhenotypes wants these all ref data as dataframes
vocab_ukb_map  <- as.data.frame(vocab_ukb_map)
anno_file      <- as.data.frame(anno_file)
exlude_map     <- as.data.frame(exlude_map)
sex_spec_map   <- as.data.frame(sex_spec_map)
rollup_map     <- as.data.frame(rollup_map)

log_it(paste(ts(), "Finished loading Phecoding data\n"))


# Bring in UKB data ####
col_types <- cols(
  "eid" = col_character(),
  "diag_date" = col_date(format = "%Y-%m-%d"),
  "icd_code" = col_character(),
  "vocab" = col_character(),
  "src" = col_character(),
  
)

cov_cols_types <- cols(
  "eid" = col_character(),
  "sex" = col_integer(),
  "bmi" = col_double(),
  "age" = col_double(),
  "ethnic" = col_integer(),
  "tdi_quant" = col_integer(),
  "num_in_house" = col_integer(),
  "tobac" = col_integer(),
  "alc" = col_integer(),
  "num_sex_part" = col_integer(),
  "same_sex" = col_integer(),
  "is_dead" = col_character(),
  "date_of_visit" = col_date(format = "%Y-%m-%d")
  
)

# Calculate covariate data file size
fn_info = file.info(INPUT_DIAG_FP)
fs_in_gb = round(fn_info$size / 1024 / 1024 / 1024, 2)
log_it(paste0(ts(), " Reading in our patient data chunk:\n\t\t\t\t", 
           CHUNK_NAME, " [", fs_in_gb, " GB]\n"))

# We need to bring in our own colnames
dat <- vroom(INPUT_DIAG_FP,  
             delim = "\t", 
             col_types = col_types,
             progress = FALSE
)

dat <- as.data.frame(dat)

dat <- dat[, c('eid', 'vocab', 'icd_code', 'diag_date')]
colnames(dat) <- c('id', 'vocabulary_id', 'code', 'index')

pat_list = unique(dat$id)
n_pats = length(pat_list)

log_it(paste0(ts(), " Finished reading in patient data chunk\n\t\t\t\t[", 
           prettyNum(nrow(dat), big.mark = ","), " encounters | ", 
           prettyNum(n_pats, big.mark = ","), " patients]\n"))

# Update our vocabulary to match the PheWAS vocabulary
dat$vocabulary_id <- gsub("ICD9", "ICD9CM", dat$vocabulary_id)
# Get some file information to log out
fn_info = file.info(SEX_FN)
fs_in_gb = round(fn_info$size / 1024 / 1024 / 1024, 2)
log_it(paste0(ts(), " Reading in all patient sex data:\n\t\t\t\t", 
           basename(SEX_FN), " [", fs_in_gb, " GB]\n"))


sex <- vroom(SEX_FN, 
                 .name = janitor::make_clean_names, 
                 delim = ",", 
                 col_types = cov_cols_types,
                 progress = FALSE
)
sex <- as.data.frame(sex)
sex <- sex[, c('eid', 'sex')]
colnames(sex) <- c('id', 'sex')

sex$sex <- ifelse(sex$sex == 0, 'F', 'M')


log_it(paste0(ts(), " Finished reading in all patient sex data\n\t\t\t\t[", 
           prettyNum(length(unique(sex$id)), big.mark = ","), " patients]\n"))

# Limit to our current patients
################################################################
pat_list = unique(sex$id)
n_pats = length(pat_list)

miss_people = setdiff(pat_list, unique(dat$id))
n_miss = length(miss_people)
miss_df = dat[dat$id %in% miss_people, ]

# Limit our data to IDs in sex (these are the 9,429 we can still use)
dat = dat[dat$id %in% pat_list, ]

log_it(paste0(ts(), " Limiting encounter data to ", 
        prettyNum(length(unique(sex$id)), big.mark = ","), 
        " useable patients.\n\t\t\t\t[", 
        prettyNum(nrow(dat), big.mark = ","), " encounters | ", 
        prettyNum(n_pats, big.mark = ","), " patients]\n\t\t\t\t", 
        "Number of encounters lost: ", 
        prettyNum(nrow(miss_df), big.mark = ","), "\n\t\t\t\t", 
        "Number of patients lost: ", 
        prettyNum(n_miss, big.mark = ","), "\n"))


# Collect stats
sex_tab = as.data.frame(table(sex$sex))
colnames(sex_tab) <- c('sex', 'cnt')

sex_ls = c('F', 'M', 'Unknown')
cnt_ls = c()
for (curr_sex in sex_ls) {
  if (curr_sex %in% sex_tab$sex) {
    curr_cnt = sex_tab[sex_tab$sex == curr_sex, 'cnt']
  } else {
    curr_cnt = 0
  }
  
  cnt_ls = append(cnt_ls, curr_cnt)
}

# Creating table of sex information for log
sex_tab_str = as.data.frame(cbind(sex_ls, cnt_ls))
colnames(sex_tab_str) = c('Sex', 'Count')
sex_tab_str$Count <- as.numeric(sex_tab_str$Count)
sex_tab_str[nrow(sex_tab_str) + 1, ] = c('Total', sum(sex_tab_str$Count))
sex_tab_str$Count <- formatC(sex_tab_str$Count, format = "d", big.mark = ",")

log_it(paste0(ts(), " Finished collecting sex information for patients.",
           "\n\t\t\t _____________________\n\t\t\t|   Sex   |",
           "   Count   |",
           "\n\t\t\t|---------|-----------|\n"))
for (i in 1:nrow(sex_tab_str)) {
  if (sex_tab_str[i, 1] == 'Total') {
    log_it(sprintf("\t\t\t| %-7s | %-9s |", sex_tab_str[i, 1],
                   formatC(as.numeric(sex_tab_str[i, 2]),
                           format = "d", big.mark = ",")))
  } else {
    log_it(sprintf("\t\t\t| %-7s | %-9s |\n", sex_tab_str[i, 1],
                   formatC(as.numeric(sex_tab_str[i, 2]),
                           format = "d", big.mark = ",")))

  }

}
log_it("\t\t\t|_____________________|\n\n")


# Switch to NA per Phecode docs
if ('Unknown' %in% unique(sex_tab$sex)){
  sex[sex$sex == 'Unknown', 'sex'] <- NA
}


# Convert to Phecodes ####
st = Sys.time()
log_it(paste0(ts(), " Starting min code count of 1\nUsing command:\n\t"))

# Write out our createPhenotypes function call to the log
call_str = 'createPhenotypes(
                              id.vocab.code.index = dat, 
                              min.code.count = 1, 
                              add.phecode.exclusions = T, 
                              translate = T, 
                              aggregate.fun=PheWAS:::default_code_agg, 
                              id.sex = sex, 
                              full.population.ids = pat_list,
                              vocabulary.map = vocab_ukb_map, 
                              rollup.map = rollup_map, 
                              exclusion.map = exlude_map, 
                              sex.restriction = sex_spec_map,
                              map.codes.make.distinct = FALSE)\n'

log_it(paste0("\n\t\t", call_str))

# Capture stdout 
con <- file(LOG_FN, open = "at")
sink(con, type = "output", split = TRUE)
sink(con, type = "message", append = TRUE)

# Use PheWAS library to convert our UKB ICD data to Phecodes
single_min_code <- createPhenotypes(
  id.vocab.code.index = dat, 
  min.code.count = 1, 
  add.phecode.exclusions = T, 
  translate = T, 
  aggregate.fun=PheWAS:::default_code_agg, 
  id.sex = sex, 
  full.population.ids = pat_list,
  vocabulary.map = vocab_ukb_map, 
  rollup.map = rollup_map, 
  exclusion.map = exlude_map, 
  sex.restriction = sex_spec_map,
  map.codes.make.distinct = FALSE)

sink(type = "message")
sink()
close(con)

end = Sys.time()
log_it(paste0(ts(), "Finished min code count of 1\n"))

# Calculate how long the translation process took
proc_time = end - st
proc_time = as.numeric(proc_time, units = "mins")
proc_time = round(proc_time, 3)
log_it(paste0("Processing of min code count of 1 for ", CHUNK_NAME, " took ", 
              proc_time, " mins.\n"))


single_min_code_dt <- as.data.table(single_min_code)
single_min_code_dt <- single_min_code_dt %>%
      mutate_all(~ ifelse(is.na(.), "NA", .))

# Save out translated data
write_xlsx(single_min_code_dt, path = SINGLE_FN, col_names  = T)
write.table(single_min_code_dt, file = SINGLE_FN_TSV, col.names  = T,
            sep = "\t")

# Calculate total time processing took
full_end = Sys.time()
proc_time = full_end - full_st
proc_time = as.numeric(proc_time, units = "mins")
proc_time = round(proc_time, 3)
log_it(paste0(ts(), "Done with all work in ", proc_time, " minutes.\n"))


# Long line
log_it(paste0(strrep("=", 80), "\n"))
log_it(paste0(ts(), "All session info follows\n"))

con <- file(LOG_FN, open = "at")
sink(con, type = "output", split = TRUE)
sink(con, type = "message", append = TRUE)
sessionInfo()
sink(type = "message")
sink()
close(con)

log_it(paste0(strrep("=", 80),'\n'))


log_it("\nAll done, remember where theose output files are!")
log_it(paste0('\t\t\t    Log File:     ', 
              gsub(PHE_DIR, '', LOG_FN)))
log_it(paste0('\t\t\t    Single Ouput: ', 
              gsub(PHE_DIR, '', SINGLE_FN)))
log_it(paste0('\t\t\t    Single Ouput TSV: ', 
              gsub(PHE_DIR, '', SINGLE_FN_TSV)))