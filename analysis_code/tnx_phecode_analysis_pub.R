# Name:     tnx_phecode_analysis_pub.R
# Author:   Mike Lape
# Date:     07/24/2024
# Description:
#
#   This program reads in several files that have been previously prepared
#   through various means, representing covariate data, and prepared 
#   Phecode-LOINC test pair files. Outcomes will be Phecodes instead of ICD10 
#   codes.
#   
#   It calculates association between an categorical LOINC test result and 
#   Phecode status, examining a particular Phecode-LOINC test pair from input
#   files using a logistic regression model.
#   
#   This analysis attempts to match the test adjustments made for the UKB models
#   which is why we will read in those results, so we know which covariates we
#   need to adjust for. We also only run this for those Phecode-pathogen pairs
#   that were significant in the UKB Phecode analysis.
# 
#       dis_status ~ LOINC test result + covs UKB model was adjusted for
#
#


# Load required libraries ####
suppressMessages(library(dplyr) )
suppressMessages(library(stringr))
suppressMessages(library(MASS))
suppressMessages(library(data.table))
suppressMessages(library(readxl))
suppressMessages(library(logistf))
suppressMessages(library(glue))
suppressMessages(library(argparse))

AGE_FILT = TRUE

# Specify number of cores to run our tests across
NCORES = 1 

OUT_FILE_DATE = format(Sys.Date(), "%Y_%m_%d")

# Number in cell to switch over to exact method from glm, here we use firth
EXACT_SWITCH = 5
EXACT_METHOD = 'firth'

# Minimum number of cases and controls to run with
MIN_N_CASES = 10
MIN_N_CONS = 10 

# debug writes directly out
DEBUG = TRUE

# log puts messages in a file
LOG = TRUE

# Specify number of cores to run our tests across
NCORES = 1 

TEST_TYPE = 'cat'

REMOTE = TRUE

BASE_DIR = "/data/pathogen_ncd"

# Get user input ####
parser <- argparse::ArgumentParser()
parser$add_argument("--phecode", type = "character",
                    help = "Phecode to run analysis for", required = TRUE)

opt <- parser$parse_args()

# Access the parsed arguments
INPUT_PHECODE <- opt$phecode

# Dealing with minimum code count 
curr_phe = INPUT_PHECODE
curr_mcc = 1
curr_mcc_str = paste0("mcc", curr_mcc)
ANALYSIS_TYPE = "ONE"


print(glue("Phecode: {INPUT_PHECODE}"))


# Helper function to return current date and time in square brackets
get_dt <- function() {
  return(format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
}


# Setup Phecode stuff ####
# ICD codes in record
TNX_DIR = paste0(BASE_DIR, "/trinetx")
MANU_DIR = paste0(BASE_DIR, "/manuscript")
BASE_PHECODE_DIR = paste0(BASE_DIR, "/phecode/")
PHECODE_DIAG_DIR = paste0(BASE_PHECODE_DIR, "/tnx/translation/out")

UKB_RES_DIR = paste0({BASE_PHECODE_DIR}, "/ukb/path_analysis")

ORIG_RES_FN = paste0(UKB_RES_DIR, 
                       "/ukb_phecode_results_MCC_of_", ANALYSIS_TYPE, 
                       "_2024_10_22_with_std_lev.xlsx")
  
RES_DIR = paste0(BASE_PHECODE_DIR, '/tnx/path_analysis/res')
LOG_DIR =  paste0(BASE_PHECODE_DIR, '/tnx/path_analysis/logs')
STAT_DIR =  paste0(BASE_PHECODE_DIR, '/tnx/path_analysis/run_stats')

PHECODE_PAIR_DIR = paste0(BASE_PHECODE_DIR, "/tnx/phecode_lab_pair_final/out")
  
# Create the directories if needed
if (!dir.exists(RES_DIR)){
  dir.create(RES_DIR, recursive = TRUE)
}
if (!dir.exists(LOG_DIR)){
  dir.create(LOG_DIR, recursive = TRUE)
}    
if (!dir.exists(STAT_DIR)){
  dir.create(STAT_DIR, recursive = TRUE)
}    

# Set some global constants ####


# UKB Results
ORIG_RES = as.data.frame(read_excel(ORIG_RES_FN))

# Dis-org pair info
pair_info = read.csv(glue("{PHECODE_PAIR_DIR}/summaries/phe_{curr_mcc_str}_{curr_phe}_pair_summary.tsv"),
                     colClasses = c("dis" = "character"), sep = '\t')

# Create our results and log filenames
RES_FN = paste(RES_DIR, "/phe_", curr_mcc_str, "_", curr_phe, "_results_test.tsv", 
               sep = '')
LOG_FN = paste(LOG_DIR, "/phe_", curr_mcc_str, "_", curr_phe, "_debug_test.log", 
               sep = '')
STAT_RES_FN = paste(STAT_DIR, "/phe_", curr_mcc_str, "_", curr_phe, 
                    "_run_stats_test.tsv", sep = '')

# Start logging and getting going ####
setting_str = paste0("[", get_dt(), "]: Starting logging...:",
                     "Settings:",
                     "\n\tPhecode:\t\t", curr_phe,
                     "\n\tAnalysis Type:\t\t", ANALYSIS_TYPE,
                     "\n\tPair Dir:\t\t", PHECODE_PAIR_DIR,
                     "\n\tUKB Res:\t\t", ORIG_RES_FN,
                     "\n\tImputed Age:\t\t", IMPUTED_AGE,
                     "\n\tFilter Age:\t\t", AGE_FILT,
                     "\n\tInclude BMI:\t\t", USE_BMI,
                     "\n\tEthnicity Matching:\t", ETHNIC_FILT,
                     "\n======================================================\n",
                     "Output Files:",
                     "\n\tResults:\t\t", RES_FN,
                     "\n\tLog File:\t\t", LOG_FN,
                     "\n\tTest Stats:\t\t", STAT_RES_FN,
                     "\n======================================================")



if (LOG == TRUE) {
  write("Starting logging...", file = LOG_FN, append = FALSE)
  write(setting_str, file = LOG_FN, append = TRUE)
  
}
if (DEBUG == TRUE) {
  cat("Starting debugging\n")
  cat(paste0(setting_str, "\n"))
  
}  



# This is the dataframe we will use for our data to be fed into our logistic 
# regression models, so it will contain a column of titers for an antibody, a 
# column for disease status, and then all of the covariate data.  I hate that
# I had to do this but I'm making it global due to scoping issues with the 
# logistic regression model performance metrics not being able to obtain this
# data, yet seemingly needing it.
dat_df <- NA


# Source helper function file ####
path_to_help = "/code/analysis/helper_functions_pub.R"
path_to_analysis = "/code/analysis/analysis_functions_pub.R"

help_loc = paste(BASE_DIR, path_to_help, sep = "")
analysis_loc = paste(BASE_DIR, path_to_analysis, sep = "")
HOME = BASE_DIR

# Load in our helper functions - here is used to make sure we find the file.
source(help_loc)
source(analysis_loc)

# Read in all data ####

# Demo data
cov_dat = data.frame(fread(glue("{TNX_DIR}/procd_data/procd_covs.tsv", 
                                sep = "\t", data.table = FALSE, showProgress = FALSE)))

# Org test info
org_test_info = read_excel(glue("{TNX_DIR}/lab_test_data_analysis_latest_manual_review.xlsx"))

org_lookup = read_excel(glue("{TNX_DIR}/collapsed_loincs_procd.xlsx"))

# Grab tag to org dict
tag_df = read.csv(glue("{TNX_DIR}/procd_data/prev_res_to_org_test_lookup.txt"),
                  sep = '\t')


# Processing Input ####
############
#
# Update covariate data
#
############
sel_cols = c('patient_id', 'sex', 'ethnic', 'age')
cov_dat = cov_dat[, sel_cols]

# As read in all covariates except for age and bmi, which are floats, are 
# typed as ints, so here we just convert them all to factors, except for 
# age and bmi
cov_dat$sex <- factor(cov_dat$sex)
cov_dat$ethnic <- as.factor(cov_dat$ethnic)
# If we want to try to match the UKB age range of 51 - 82
if (AGE_FILT == TRUE) {
  
  # Age is scaled by 10 so 51 = 5.1 and 86 = 8.2
  cov_dat = cov_dat[((cov_dat$age >= 5.1) & 
                       (cov_dat$age <= 8.6)), ]
}

############
#
# Remove any weird characters from org names
#
############
prev_res = ORIG_RES
prev_res <- prev_res %>% rename(organism = org)

# Check both organism as well as tag
prev_res$organism = gsub("[^[:alnum:]]", "", prev_res$organism)


# Fix a few org names
prev_res$organism <- gsub("ctrach", "chlam", prev_res$organism)
prev_res$organism <- gsub("hpylor", "hpylori", prev_res$organism)
prev_res$organism <- gsub("tgond", "tox", prev_res$organism)

prev_res$organism = gsub("[^[:alnum:]]", "", prev_res$organism)


# Reset index after filtering
row.names(prev_res) <- 1:nrow(prev_res)


############
#
# Look only at tests marked as good (good == 'y') and cat merge in all the 
# LOINC DB info
#
############
org_test_info = org_test_info[((org_test_info$final_type == 'cat') &
                                 (org_test_info$good == 'y')),]
org_test_info = merge.data.frame(org_test_info, org_lookup, by.x = 'loinc', 
                                 by.y = 'LOINC_NUM')



if (DEBUG == TRUE) {
  cat(paste0("\nAnalysis Date:                                ", OUT_FILE_DATE,
             "\nPhecode analysis type:                        ", ANALYSIS_TYPE,
             "\nInput Phecode:                                ", INPUT_PHECODE))
}


# Start Testing ####
# Make list of covs we have in TNX data
covs_we_have = colnames(cov_dat)
covs_we_have = covs_we_have[covs_we_have != 'patient_id']

# Create output df ####

# res will contain the model results and metadata for each Phecode-antibody pair
mod_res = data.frame(matrix(nrow = 0, ncol = 45))


result_cols =  c('Disease_Description',
                 'Disease_Group', 'phecode',
                 'dis_sex_str',
                 'num_case', 'num_con', 'n_mixed', 'nNA', 'con_str',
                 'org', 'test', 'anti', 'p_val', 'OR', 'CI', 'model', 
                 'mod_version', 'cov_adj', 'ukb_covs', 'cov_ps', 'cov_or',
                 'case_age', 'con_age', 'case_titer', 'con_titer', 
                 'case_titer_std', 'con_titer_std', 'case_titer_med', 
                 'con_titer_med', 
                 'n_con_neg', 'n_con_pos', 'n_case_neg', 'n_case_pos',
                 'log_trans', 'glm_warn_msg', 'glm_warn_bool', 
                 'proc_time', 'date_time', 'test_id',  
                 'test_type', 'var_types', 'mod_method', 'note_str', 
                 'org_test_tag')


colnames(mod_res) = result_cols

# Should be 20 for normal organism
curr_prev_res = prev_res[((prev_res$phecode == INPUT_PHECODE)), ]

if (nrow(curr_prev_res) == 0) {
  print(glue("[ERORR]: Failed to pull row from prev_res for: {INPUT_PHECODE}"))
  quit("no", 1)
  
}


#####################################################
#                                                   #
#                                                   #
#         Starting the analysis                     #
#                                                   #
#                                                   #
#####################################################
# Start analysis ####
# Generate df that will hold the results, columns included depend on type
# of test
res = data.frame(matrix(nrow = 0, ncol = length(result_cols)))
colnames(res) = result_cols
res <- res %>% mutate_if(is.logical, as.character)


stat_cols = c('phecode', 'org', 'anti', 'tot_tests', 'tot_tests_w_case_num',
              'test_success', 'test_warn', 'test_error', 
              'success_tests', 'warn_tests', 'error_tests')

stat_res = data.frame(matrix(nrow = 0, ncol = length(stat_cols)))
colnames(stat_res) = stat_cols
stat_res <- stat_res %>% mutate_if(is.logical, as.character)
stat_res$tot_tests = as.numeric(stat_res$tot_tests)
stat_res$tot_tests_w_case_num = as.numeric(stat_res$tot_tests_w_case_num)
stat_res$test_success = as.numeric(stat_res$test_success)
stat_res$test_warn = as.numeric(stat_res$test_warn)
stat_res$test_error = as.numeric(stat_res$test_error)

# Write the headers for these files now
write.table(res, RES_FN, row.names = FALSE,  sep = "\t",
            col.names = TRUE, append = FALSE)

write.table(stat_res, STAT_RES_FN, row.names = FALSE, sep = "\t",
            col.names = TRUE, append = FALSE)


rownames(curr_prev_res) <- NULL

# Loop through each of our UKB results for this ICD that we are testing in TNX 
# data.
pb <- txtProgressBar(max = nrow(curr_prev_res), style = 3)

for (row_ind in 1:nrow(curr_prev_res)) {
  
  # Generate df that will hold the results, columns included depend on type
  # of test
  res = data.frame(matrix(nrow = 0, ncol = length(result_cols)))
  colnames(res) = result_cols
  res <- res %>% mutate_if(is.logical, as.character)
  
  
  stat_res = data.frame(matrix(nrow = 0, ncol = length(stat_cols)))
  colnames(stat_res) = stat_cols
  stat_res <- stat_res %>% mutate_if(is.logical, as.character)
  stat_res$tot_tests = as.numeric(stat_res$tot_tests)
  stat_res$tot_tests_w_case_num = as.numeric(stat_res$tot_tests_w_case_num)
  stat_res$test_success = as.numeric(stat_res$test_success)
  stat_res$test_warn = as.numeric(stat_res$test_warn)
  stat_res$test_error = as.numeric(stat_res$test_error)
  
  setTxtProgressBar(pb,row_ind)
  
  curr_row = curr_prev_res[row_ind, ]
  
  # Extract disease and org information for current result we are attempting to 
  # replicate
  curr_phe = INPUT_PHECODE
  curr_tag = curr_row[,'tag']
  curr_anti = curr_row[,'anti']
  curr_dis_descr = curr_row[, 'Disease_Description']
  curr_dis_group = curr_row[,'Disease_Group']
  
  # The tags with 'underscores' will need these removed to find pair data files
  curr_fn_tag = gsub('_', '', curr_tag)
  curr_fn_anti = gsub(' ', '_', curr_anti)
  
  
  # Send message about what we are starting to work on.
  curr_dt = get_dt()
  msg_str = paste0("[",curr_dt,"|", curr_phe, "] ", curr_dis_descr, " [", 
                   curr_dis_group, "]",
                   "\n\t", curr_tag, "/",
                   curr_fn_tag, " ", curr_fn_anti, '\n')
  if (LOG == TRUE) {
    write(msg_str, file = LOG_FN, append = TRUE)    
  }
  
  if (DEBUG == TRUE) {
    cat(paste0(msg_str, '\n'))
  } 
  
  # If we are looking at hpv16 or 18 also include LOINC tests that cover both
  # orgs "hpv16, hpv18", as well as tests for all high risk strains "hpv_hr".
  # Otherwise grab the LOINC tests we have for the current org we are looking at  
  if (curr_tag == 'hpv16'){
    # See what tests we have in TNX for the current organism and test type
    curr_test_df =  org_test_info[((org_test_info$tag == curr_tag) |
                                     (org_test_info$tag == 'hpv16, hpv18') |
                                     (org_test_info$tag == 'hpv_hr')), ]
    
  } else if (curr_tag == 'hpv18') {
    # See what tests we have in TNX for the current organism and test type
    curr_test_df =  org_test_info[((org_test_info$tag == curr_tag) |
                                     (org_test_info$tag == 'hpv16, hpv18') |
                                     (org_test_info$tag == 'hpv18, hpv45') |
                                     (org_test_info$tag == 'hpv_hr')), ]
    
  } else {
    curr_test_df =  org_test_info[((org_test_info$tag == curr_tag)), ]
    
  }
  
  
  # Remove any weird dupes
  curr_test_df = unique(curr_test_df)
  
  # Send message about what we are starting to work on.
  curr_dt = get_dt()
  msg_str = paste0("[",curr_dt,"] ","Found ", nrow(curr_test_df), " ", 
                   TEST_TYPE, " tests for ", curr_phe, 
                   ' x ' , curr_tag, ' - ', curr_fn_anti, '\n')
  
  if (LOG == TRUE) {
    write(msg_str, file = LOG_FN, append = TRUE)    
  }
  
  if (DEBUG == TRUE) {
    cat(paste0(msg_str, '\n'))
  } 
  
  
  # If we don't have a test for this org, message user and assemble placeholder
  # results that clearly indicate we have no tests
  if (nrow(curr_test_df) == 0){
    
    curr_dt = get_dt()
    msg_str = paste0("\t[",curr_dt," | WARNING]: No tests for ", curr_phe, 
                      ' x ', curr_tag)
    
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)   
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    
    fail_stats = list("phecode" = curr_phe, 
                      "org" = curr_tag,
                      "anti" = curr_anti,
                      "tot_tests" = 0,
                      "tot_tests_w_case_num" = 0,
                      "test_success" = 0,
                      "test_warn" = 0,
                      "test_error" = 0,
                      "success_tests" = '',
                      "warn_tests" = '',
                      "error_tests" = ''
    )
    
    stat_res = dplyr::bind_rows(stat_res, fail_stats)
    
    fail_res = c("Disease_Description" = curr_dis_descr,
                 "Disease_Group" = curr_dis_group,
                 "phecode" = curr_phe,
                 "dis_sex" = '', 
                 "con_str" = '', 
                 "org" = curr_tag,
                 "anti" = curr_anti)
    
    # Append current test results to our running results for this disease
    res = dplyr::bind_rows(res, fail_res)
    res[nrow(res), is.na(res[nrow(res), ])] = 'no_tests'
    next  
  }   
  
  
  # Add ICD column so we can merge with pair info to get numbers
  curr_test_df$phecode = curr_phe
  
  # Merge the current test df with the pair info df to see which of these 
  # tests we have dis-test pair data for
  # all.x means left join
  curr_test_df = merge.data.frame(x = curr_test_df, 
                                  y = pair_info[, c('dis', 'loinc_test', 
                                                    'org', 'case_n', 'con_n')], 
                                  all.x = TRUE,
                                  by.x = c('phecode', 'loinc'), 
                                  by.y = c('dis', 'loinc_test'))
  
  # We now have count info (pos/neg results) for each test for this org paired
  # with this disease  
  curr_test_bf_case_filt = nrow(curr_test_df)
  
  # Keep only the tests we have enough cases and controls for pair data for
  curr_test_df = curr_test_df[((curr_test_df$case_n >= MIN_N_CASES) & 
                                 (curr_test_df$con_n  >= MIN_N_CONS)), ]
  
  curr_test_after_case_filt = nrow(curr_test_df)
  
  # Send message about what we are starting to work on.
  curr_dt = get_dt()
  msg_str = paste0("[",curr_dt,"] ", nrow(curr_test_df), " of ", 
                   curr_test_bf_case_filt, 
                   " tests meet minimum case/con thresh ", MIN_N_CASES,
                   '/', MIN_N_CONS, '\n')
  
  if (LOG == TRUE) {
    write(msg_str, file = LOG_FN, append = TRUE)    
  }
  
  if (DEBUG == TRUE) {
    cat(paste0(msg_str, '\n'))
  } 
  
  
  # We have no tests that meet our min num cases and controls threshold, so 
  # message user and assemble placeholder results that clearly indicate we have 
  # no tests to run
  if (nrow(curr_test_df) == 0){
    curr_dt = get_dt()
    msg_str = paste0("\t[",curr_dt," | WARNING]: No tests for ", curr_phe, ' x ', curr_tag)
    
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)   
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    
    fail_stats = list("phecode" = curr_phe, 
                      "org" = curr_tag,
                      "anti" = curr_anti,
                      "tot_tests" = curr_test_bf_case_filt,
                      "tot_tests_w_case_num" = 0,
                      "test_success" = 0,
                      "test_warn" = 0,
                      "test_error" = 0,
                      "success_tests" = '',
                      "warn_tests" = '',
                      "error_tests" = ''
    )
    
    stat_res = dplyr::bind_rows(stat_res, fail_stats)
    
    
    fail_res = c("Disease_Description" = curr_dis_descr,
                 "Disease_Group" = curr_dis_group,
                 "phecode" = curr_phe,
                 "dis_sex" = '', 
                 "con_str" = '', 
                 "org" = curr_tag,
                 "anti" = curr_anti)
    
    
    # Append current test results to our running results for this disease
    res = dplyr::bind_rows(res, fail_res)
    res[nrow(res), is.na(res[nrow(res), ])] = 'no_tests'
    
    next
  }
  
  
  # If we get here we are going to run tests, so we need to figure out
  # which covs we actually have and what UKB wants us to adjust for.
  
  # Reset covs_we_have in case we ever have to use that code within loop
  covs_we_have = colnames(cov_dat)
  covs_we_have = covs_we_have[covs_we_have != 'patient_id']
  
  # Figure out which covs we need
  ukb_cov_str = curr_row$'cov_adj_for'
  
  # split out on comma and remove any extra whitespace
  mod_covs = unlist(str_split(ukb_cov_str, ","))
  mod_covs = sapply(mod_covs, killws, USE.NAMES = FALSE)
  
  
  # Intersect our mod_covs with what we have access to in TNX and
  # only use those covs that are also in TNX (covs_to_use)
  covs_to_use = intersect(mod_covs, covs_we_have)
  
  # Also we can grab sex-specific disease info before we start testing
  
  # Grab sex-specific disease info and control set from UKB results
  curr_sex_spec = curr_row$sex_specific_dis
  curr_con_grp  = curr_row$control_set
  
  # If its not a sex-specific disease
  if (curr_sex_spec == 'Both') {
    
    # If its not a sex-specific disease set the str to "both" and the dis
    # sex to indicator "-1"
    dis_sex_str = "Both"
    dis_sex = -1  
    
    # If it is a sex-specific disease, set the dis_sex and dis_sex_str to 
    # correct value
  } else {
    
    if (curr_sex_spec == 'Female') {
      
      dis_sex = 0
      dis_sex_str = "Female"
      
    } else {
      
      dis_sex = 1
      dis_sex_str = "Male"
      
    }
  }
  
  
  # Generate a list containing disease info that will be bound to each pair's
  # result list (used below).
  dis_info = c("Disease_Description" = curr_dis_descr,
               "Disease_Group" = curr_dis_group,
               "phecode" = curr_phe,
               "dis_sex_str" = dis_sex_str, 
               "con_str" = curr_con_grp)
  
  success_test_cnt = 0
  warn_test_cnt    = 0
  error_test_cnt   = 0
  
  success_test_ls  = c()
  warn_test_ls     = c()
  error_test_ls    = c()
  
  # Now start looping through each LOINC test we have that we have enough data
  # to test this disease-LOINC pair
  for (y in 1:nrow(curr_test_df)) {
    
    # We will measure processing time for this script using proc.time but will
    # also log when this analysis was run using Sys.time
    start_time = proc.time()
    date_time = as.character(Sys.time())
    
    # Get data for this test
    curr_test = curr_test_df[y,]
    curr_test_id = curr_test$loinc
    curr_test_name = curr_test$LONG_COMMON_NAME
    
    curr_test_tag = curr_test$tag
    
    curr_test_type = curr_test$final_type
    VAL_COL = 'lab_result_text'
    
    
    # Get the test ID so we can find the right column in our test df
    curr_test_id = curr_test$loinc
    
    # Send user a status update, that we are now working on this test.
    curr_dt = get_dt()
    msg_str = paste0("\n\n[",curr_dt,"|", curr_phe, "] ", curr_dis_descr, 
                    " [",  curr_dis_group, "]","\n\t", curr_tag, "/",
                     curr_fn_tag, " ", curr_fn_anti, '\n',
                     "\t", curr_test_id, ' [', curr_test_type, ']: ', 
                     curr_test_name)
    
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)  
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    
    # Special naming scheme for high risk HPV
    if ((curr_test_tag == 'hpv_hr') | (curr_test_tag == 'hpv18, hpv45')) {
      pair_fn = paste(PHECODE_PAIR_DIR, "/", curr_phe, "/phe_", 
                      curr_phe, "_hpv_high_risk_", curr_test_id, 
                      "_single_thread.tsv", sep = '')         
      
    } else if (curr_test_tag == 'hpv16, hpv18') {
      
      pair_fn = paste(PHECODE_PAIR_DIR, "/", curr_phe, "/phe_", 
                      curr_phe, "_hpv16_18_", curr_test_id, 
                      "_single_thread.tsv", sep = '')          
      
    } else {
      # See if we have pair data for test
      pair_fn = paste(PHECODE_PAIR_DIR, "/", curr_phe, "/phe_", 
                      curr_phe, "_", curr_fn_tag, "_", curr_test_id, 
                      "_single_thread.tsv", sep = '')      
    }
    
    
    
    # If the file doesn't exist for some reason just move to next organism test
    if (file.exists(pair_fn) == FALSE) {
      curr_dt = get_dt()
      msg_str = paste0("\t\t[",curr_dt," | ERROR]: File for ", curr_test_id, ' [', curr_test_type, ']: ', 
                       curr_test_name, " does not exist: \n\t\t\t", pair_fn)
      if (LOG == TRUE) {
        write(msg_str, file = LOG_FN, append = TRUE)
      }
      
      if (DEBUG == TRUE) {
        cat(paste0(msg_str, '\n'))
      } 
      
      error_test_cnt = error_test_cnt + 1
      error_test_ls = append(error_test_ls, curr_test_id)
      next
    }
    
    # If we are here then the pairs file exists so let's read it in.
    pair_dat = read.csv(pair_fn, sep = '\t')
    
    # extract just the disease status and test result
    mod_df = pair_dat[, c('pat_id', 'is_case', VAL_COL)]
    
    # Rename columns to match our prev code
    colnames(mod_df)[colnames(mod_df) == 'is_case'] <- 'mod_dis'
    colnames(mod_df)[colnames(mod_df) == VAL_COL] <- 'mod_ant'
    
    # Merge in covariate data - NA's will be introduced for patient IDs
    # that appear in mod_df but not cov_dat
    dat_df = merge(mod_df, cov_dat, all.x = TRUE,
                   by.x = 'pat_id', by.y = 'patient_id')
    
    # Move person_id into row name
    row.names(dat_df) = dat_df$pat_id
    dat_df$pat_id <- NULL
    
    # Switch mod_dis from logical vector to numeric with 0 = disease False, 
    # and 1 = disease True.
    dat_df$mod_dis = ifelse(dat_df$mod_dis == 'False', 0, 1)  
    
    # Make sure we have enough cases and controls, as there could be NAs in 
    # some covariate columns we would be trying to use
    chk = c('mod_dis', 'mod_ant')
    chk = append(chk, covs_to_use)
    
    n_case_bf_cov_chk = sum(dat_df$mod_dis == 1)
    n_con_bf_cov_chk = sum(dat_df$mod_dis == 0)
    
    # remove any rows in dat_df that have NAs in the columns we need!
    dat_df = dat_df[complete.cases(dat_df[,chk]),]
    
    n_case_af_cov_chk = sum(dat_df$mod_dis == 1)
    n_con_af_cov_chk = sum(dat_df$mod_dis == 0)
    
    curr_dt = get_dt()
    msg_str = paste0("\t\t[",curr_dt," | Before - cov filtering] nCase: ", n_case_bf_cov_chk,  ' | nCon: ',
                     n_con_bf_cov_chk, '\n\t\t\t[After  - cov filtering] nCase: ',
                     n_case_af_cov_chk, ' | nCon: ', n_con_af_cov_chk)
    if (LOG == TRUE) {
      
      write(msg_str, file = LOG_FN, append = TRUE)
    }
    
    if (DEBUG == TRUE) {
      cat(paste(msg_str, '\n', sep = ''))
    } 
    
    
    # Switch mod_dis from string 'Negative'/'Positive' values to integers
    
    # This should have been taken care of in data cleaning and I think it was,
    # but just to be sure
    dat_df = dat_df[((dat_df$mod_ant == 'Negative') | 
                       (dat_df$mod_ant == 'Positive')),]
    
    dat_df$mod_ant <- as.character(dat_df$mod_ant)
    dat_df[dat_df$mod_ant == 'Negative', 'mod_ant'] = 0
    dat_df[dat_df$mod_ant == 'Positive', 'mod_ant'] = 1
    dat_df$mod_ant <- as.numeric(dat_df$mod_ant)
    
    curr_dt = get_dt()
    msg_str = paste0("\t\t\t[",curr_dt,"] Sex-spec: ", curr_sex_spec, " | dis_sex: ", dis_sex, 
                     " | dis_sex_str : ", dis_sex_str, "| Con group: ", curr_con_grp)
    
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    # Keep track of the number of people that appear in both cases and controls.
    mixed_cnt = 0
    
    # Get patient IDs for people that are cases and controls for this disease
    case_inds = rownames(dat_df[which(dat_df$mod_dis == 1, arr.ind = TRUE), ])
    control_inds = rownames(dat_df[which(dat_df$mod_dis == 0, arr.ind = TRUE), ])
    
    curr_dt = get_dt()
    msg_str = paste0("\t\t[",curr_dt," | Before - sex filtering] nCase: ", length(case_inds), " | nCon: ", 
                     length(control_inds))
    
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    # Filter dat_df by sex if needed
    if (dis_sex_str != 'Both'){
      
      # Get person_ids for all people of the sex we need.
      sex_inds = rownames(dat_df[dat_df$sex == dis_sex, ])
      # Limit case and control patients to only those with sex matching dis_sex
      case_inds = case_inds[case_inds %in% sex_inds]
      control_inds = control_inds[control_inds %in% sex_inds]
    }
    
    curr_dt = get_dt()
    msg_str = paste0("\t\t[",curr_dt," | After - sex filtering] nCase: ", length(case_inds), " | nCon: ", 
                     length(control_inds))
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    if (dis_sex_str != 'Both'){
      msg_str = paste0("\t\tsex_inds: ", length(sex_inds))
      if (LOG == TRUE) {
        write(msg_str, file = LOG_FN, append = TRUE)
      }
      if (DEBUG == TRUE) {
        cat(paste0(msg_str, '\n'))
      } 
    }
    
    # Filter all of our data based on our possibly updated lists of cases and 
    # controls
    all_inds = c(case_inds, control_inds)
    dat_df = dat_df[all_inds,]
    
    # Create case and control-specific dataframes
    case = na.omit(dat_df[case_inds , ])
    control = na.omit(dat_df[control_inds , ]) 
    
    
    # Super complicated command to figure out if any columns in our df
    # have only 1 unique value and thus are not appropriate for use in
    # log reg.  If you don't remove this column the glm will
    # throw an error: contrasts can be applied only to factors with 2 or more 
    # levels
    if ((sum(lapply(lapply(lapply(dat_df, na.omit), unique), length) < 2)) > 0)
    {
      
      rem_me = colnames(dat_df)[lapply(lapply(lapply(dat_df, na.omit), unique), 
                                        length) < 2]
      # If rem_me (columns with only 1 unique value) is either mod_ant or mod_dis
      # we just quit bc there's no point!
      if (('mod_ant' %in% rem_me) | ('mod_dis' %in% rem_me))
      {
        if (DEBUG == TRUE) {
          if ('mod_ant' %in% rem_me) {
            curr_dt = get_dt()
            msg_str = paste0("\t\t[",curr_dt," | WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
                             curr_test_name, " mod_ant in remove (lapply) skipping - only 1 level!")
            if (LOG == TRUE) {
              write(msg_str, file = LOG_FN, append = TRUE)
            }
            
            if (DEBUG == TRUE) {
              cat(msg_str)
              
            }
            
          } else {
            curr_dt = get_dt()
            msg_str = paste0("\t\t[",curr_dt," | WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
                             curr_test_name, " mod_dis in remove (lapply) skipping - only 1 level!")            
            if (LOG == TRUE) {
              write(msg_str, file = LOG_FN, append = TRUE)
            }
            
            if (DEBUG == TRUE) {
              cat(msg_str)
              
            }
          }
          
        }
        warn_test_cnt = warn_test_cnt + 1
        warn_test_ls = append(warn_test_ls, curr_test_id)
        next
      }
      
      # Get list of cols to keep (bc I suck at R)
      keep_me = setdiff(colnames(dat_df), rem_me)
      
      # Select only the columns that we want to keep
      dat_df = dat_df[,keep_me]
      
      # Also update covs we have...
      covs_we_have = setdiff(covs_we_have, rem_me)
      
    }
    
    
    # Update covs_to_use based on covs_we_have after weird filtering above
    covs_to_use = intersect(mod_covs, covs_we_have)
    
    
    # Update case and control dataframes after previous step removing NA rows.
    case = na.omit(dat_df[case_inds , ])
    control = na.omit(dat_df[control_inds , ])
    
    
    # Only have 1 unique test result value (all negatives or all positives) 
    # so can't so a log reg on this!
    if (length(unique(dat_df$mod_ant)) == 1 )
    {
      curr_dt = get_dt()
      msg_str = paste0("\t\t[",curr_dt," | WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
                       curr_test_name, " All samples had same value for antibody titer!")
      if (LOG == TRUE) {
        write(msg_str, file = LOG_FN, append = TRUE)
      }
      
      if (DEBUG == TRUE) {
        cat(msg_str)
        
      }
      warn_test_cnt = warn_test_cnt + 1
      warn_test_ls = append(warn_test_ls, curr_test_id)
      next
    }
    
    
    # Collect meta data #####
    org = curr_tag
    
    # Update case and control dataframes after previous step removing NA rows.
    case = dat_df[dat_df$mod_dis == TRUE,]
    control = dat_df[dat_df$mod_dis == FALSE,]
    
    # Number of cases and controls    
    nCase = nrow(case)
    nControl = nrow(control)
    
    # Calculate summary stats for cases and controls
    # Age - multiply by 10 to re-scale back to normal
    if ('age' %in% colnames(dat_df)) {
      avg_age_case = round(mean((case[,'age']) * 10, na.rm = TRUE),2)
      avg_age_con = round(mean((control[,'age']) * 10, na.rm = TRUE),2)      
    } else {
      avg_age_case = "NA"
      avg_age_con = "NA"
    }
    
    
    # Collect summary statistics  
    tab_res = table(dat_df$mod_dis, dat_df$mod_ant)
    
    con_neg = tab_res['0', '0']
    con_pos = tab_res['0', '1']
    case_neg = tab_res['1', '0']
    case_pos = tab_res['1', '1']
    
    tab_res_str = paste('Con Neg: ', con_neg, 
                        ' | Con Pos: ', con_pos, 
                        ' | Case Neg: ', case_neg,
                        ' | Case Pos: ', case_pos, sep = '')
    
    avg_titer_case = 'NA'
    avg_titer_con  = 'NA'
    std_titer_case = 'NA'
    std_titer_con  = 'NA'
    med_titer_case = 'NA'
    med_titer_con  = 'NA'
    
    
    
    # Run analysis #####
    
    # Reset ind_res
    ind_res = c()
    
    # Last check to see if we have enough cases and controls to run analysis
    if ((nCase < MIN_N_CASES) | (nControl < MIN_N_CONS)) {
      curr_dt = get_dt()
      msg_str = paste0("\t\t[",curr_dt," | WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
                       curr_test_name, " Not enough cases or cons right before starting stats")
      
      if (LOG == TRUE) {
        write(msg_str, file = LOG_FN, append = TRUE)
      }
      
      if (DEBUG == TRUE) {
        cat(msg_str)
      }
      warn_test_cnt = warn_test_cnt + 1
      warn_test_ls = append(warn_test_ls, curr_test_id)
      next
    }
    
    # Reset a bunch of vars
    log_reg_p = 'NA'
    ant_or_str = 'NA'
    ant_ci_str = 'NA'
    log_reg_mod = 'NA'
    log_reg_cov_ps = 'NA'
    other_ci_str = 'NA'
    glm_warn = 'NA'
    is_warning= 'NA'
    mod_method = 'NA'
    note_str = 'NA'
    type_str = 'NA'
    
    # If we have numerical test we just run glm, but if we have CAT and have a
    # cell with <= our EXACT_SWITCH requirement, we will switch to an exact
    # logistic regression model (firth or elrm)
    if (curr_test_type == 'cat'){
      
      if (sum(tab_res <= EXACT_SWITCH) > 0) {
        curr_dt = get_dt()
        msg_str = paste0("\t\t[",curr_dt,"] Running exact test as one cell fell below ", 
                         EXACT_SWITCH, " | ", tab_res_str)
      if (LOG == TRUE) {
        write(msg_str, file = LOG_FN, append = TRUE)
      }
      
      if (DEBUG == TRUE) {
        cat(paste0(msg_str, '\n'))
      } 
      
      mod_res = run_firth(dat_df, covs_to_use, LOG, DEBUG, LOG_FN)

    # Do regular log reg.
    } else {
      mod_res = run_glm(dat_df, covs_to_use, LOG, DEBUG, LOG_FN)
      
    }

    
    # Put together data and return it ####
    
    # Calculate total processing time for this disease-antibody pair modeling.
    tot_time = proc.time() - start_time
    
    
    
    # throw all results and data into list and return to caller.
    ind_res = c("num_case" = nCase, "num_con" = nControl, "n_mixed" = mixed_cnt,
                "org" = org, "test" = curr_test_name, "anti" = curr_anti,
                "p_val" = mod_res[['p_val']], "OR" = mod_res[['OR']], 
                "CI" = mod_res[['CI']],  "model" = mod_res[['model']],
                "mod_version"  = 'ukb_match',
                "cov_adj" = mod_res[['cov_adj']], 
                "ukb_covs" = ukb_cov_str,
                "cov_ps" = mod_res[['cov_ps']],
                "cov_or" = mod_res[['cov_or']],
                "case_age" = avg_age_case, "con_age" = avg_age_con,
                "case_titer" = avg_titer_case, "con_titer" = avg_titer_con,
                "case_titer_std" = std_titer_case, 
                "con_titer_std" = std_titer_con,
                "case_titer_med" = med_titer_case, 
                "con_titer_med" = med_titer_con, 
                "n_con_neg" = con_neg, "n_con_pos" = con_pos,
                "n_case_neg" = case_neg, "n_case_pos" = case_pos,
                "glm_warn_msg" = mod_res[['glm_warn_msg']], 
                "glm_warn_bool" = mod_res[['glm_warn_bool']], 
                "proc_time" = tot_time[['elapsed']], 
                "date_time" = date_time,
                "test_id" = curr_test_id,
                "test_type" = curr_test_type,
                "var_types" = mod_res[['var_types']],
                "mod_method" = mod_res[['mod_method']],
                "note_str" = mod_res[['note_str']], 
                "org_test_tag"   = curr_test_tag)
    
    
    
    # Push the disease information list onto the front of our returned disease
    # organism pair result list
    ind_res = append(dis_info, ind_res)
    
    # Append current test results to our running results for this disease
    res = dplyr::bind_rows(res, ind_res)
    
    curr_dt = get_dt()
    msg_str = paste0("\n\t\t[",curr_dt," | SUCCESS]: ", curr_test_id, ' [', curr_test_type, ']: ', 
                     curr_test_name)
    
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)   
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    success_test_cnt = success_test_cnt + 1
    success_test_ls = append(success_test_ls, curr_test_id)
    
  }
  
  
  
  # Add row with success/warn/error info to stats_res df
  
  fail_stats = list("phecode" = curr_phe,  
                    "org" = curr_tag,
                    "anti" = curr_anti,
                    "tot_tests" = curr_test_bf_case_filt,
                    "tot_tests_w_case_num" = curr_test_after_case_filt,
                    "test_success" = success_test_cnt,
                    "test_warn" = warn_test_cnt,
                    "test_error" = error_test_cnt,
                    "success_tests" = paste(success_test_ls, collapse = ", "),
                    "warn_tests" = paste(warn_test_ls, collapse = ", "),
                    "error_tests" = paste(error_test_ls, collapse = ", ")
  )
  
  stat_res = dplyr::bind_rows(stat_res, fail_stats)
  
  
  
  # After we finish each disease write the results out to the results file
  # and return df to caller.
  write.table(res, RES_FN, row.names = FALSE,  sep = "\t",
              col.names = FALSE, append = TRUE)
  
  write.table(stat_res, STAT_RES_FN, row.names = FALSE, sep = "\t",
              col.names = FALSE, append = TRUE)
}


close(pb)

# Log total processing time.
curr_dt = get_dt()
msg_str = paste0("[",curr_dt, "]: Finished processing Phecode: ",  
                 curr_mcc_str, ":", curr_phe)
if (LOG == TRUE) {
  write(msg_str, file = LOG_FN, append = TRUE)
}

if (DEBUG == TRUE) {
  cat(msg_str)
}

