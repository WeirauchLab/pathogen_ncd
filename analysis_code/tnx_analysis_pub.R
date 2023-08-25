# Name:     tnx_analysis_pub.R
# Author:   Mike Lape
# Date:     01/17/2023
# Description: 
#     This script will handle running the TriNetX analyis for a single input ICD10 code.
#

# Specify number of cores to run our tests across
NCORES = 1 

OUT_FILE_DATE = '01_17_2023'

# Type of LOINC tests being examined, only cat for this TNX analysis
TEST_TYPE = 'cat'

# Load required libraries ####
suppressMessages(library(dplyr) )
suppressMessages(library(stringr))
suppressMessages(library(MASS))
suppressMessages(library(data.table))
suppressMessages(library(readxl))
suppressMessages(library(logistf))
suppressMessages(library(glue))

# Get user input: ICD code ####

# Use commandArgs to get the paramters
args <- commandArgs(trailingOnly = TRUE)

# test if there is at least 4 arguments: if not, return an error
if ((length(args)== 0) | (length(args) < 2))
{
  stop("Please supply ICD10 code after --icd flag.", call.=FALSE)
}

if ("--icd" %in% args){
  INPUT_ICD = args[which(args == "--icd") + 1]
}


print(glue("ICD: {INPUT_ICD}"))


# Set some global constants ####
LOCAL_COPY_PATH =  "/data/pathogen_ncd"


# This is the dataframe we will use for our data to be fed into our logistic 
# regression models, so it will contain a column of titers for an antibody, a 
# column for disease status, and then all of the covariate data.  I hate that
# I had to do this but I'm making it global due to scoping issues with the 
# logistic regression model performance metrics not being able to obtain this
# data, yet seemingly needing it.
dat_df <- NA


# Source helper function file ####
path_to_help = "/code/antigen_research/antigen_R/helper_functions_pub.R"
path_to_analysis = "/code/antigen_research/antigen_R/analysis_functions_pub.R"

help_loc = paste(LOCAL_COPY_PATH, path_to_help, sep = "")
analysis_loc = paste(LOCAL_COPY_PATH, path_to_analysis, sep = "")
HOME = LOCAL_COPY_PATH

# Load in our helper functions - here is used to make sure we find the file.
source(help_loc)
source(analysis_loc)


RESULTS_DIR = paste(HOME, '/other/trinetx/new_dataset/results/tnx_results_',
                    OUT_FILE_DATE,  sep = '')


# Read in all data ####
# Pair directory
pair_dir = glue("{HOME}/other/trinetx/new_dataset/pair_data")

# Sex specific diseases
sex_spec_dis = read.csv(glue("{HOME}/procd/sex_specific_codes.txt"), 
                        sep = '\t')

# People with healthy pregnancy in record
health_preg = read.csv(glue("{HOME}/other/trinetx/new_dataset/procd_data/healthy_pregnancy_data.tsv"),
                       sep = '\t')

# Demo data
cov_dat = data.frame(fread(glue("{HOME}/other/trinetx/new_dataset/procd_data/procd_covs.tsv", 
                  sep = "\t", data.table = FALSE, showProgress = FALSE)))

# Org test info
org_test_info = read_excel(glue("{HOME}/other/trinetx/new_dataset/lab_test_data_analysis_latest_manual_review.xlsx"))
org_lookup = read_excel(glue("{HOME}/other/trinetx/collapsed_loincs_procd.xlsx"))

# Grab tag to org dict
tag_df = read.csv(glue("{HOME}/other/trinetx/new_dataset/procd_data/prev_res_to_org_test_lookup.txt"),
                  sep = '\t')


# grab UKB results
prev_res = read.csv(glue("{HOME}/results/emp_results_01_17_2023.tsv"),
                    sep = '\t')

# Processing Input ####
############
#
# Update covariate data
#
############
sel_cols = c('patient_id', 'sex', 'ethnic', 'age')
cov_dat = cov_dat[, sel_cols]


# As read in all covariates except for age, which is a float, are 
# typed as ints, so here we just convert them all to factors, except for 
# age and bmi
cov_dat$sex <- factor(cov_dat$sex)
cov_dat$ethnic <- as.factor(cov_dat$ethnic)

############
#
# Remove any weird characters from org names
#
############
prev_res$organism = gsub("[^[:alnum:]]", "", prev_res$org)

############
#
# Tag previous results with org tag and filter
#
############
# Merge in the tags that will match our test data
prev_res = merge.data.frame(prev_res, tag_df, by.x = 'organism', 
                            by.y = 'prev_name')

# Reset index after filtering
rownames(prev_res) <- 1:nrow(prev_res)

############
#
# Get list of people with healthy pregnancy in past
#
############
health_preg_ls = unique(health_preg$pat_id)
health_preg_ls = as.character(health_preg_ls)

############
#
# Look only at tests marked as good (good == 'y') and merge in all the LOINC DB
# info
#
############
org_test_info = org_test_info[org_test_info$good == 'y', ]
org_test_info = merge.data.frame(org_test_info, org_lookup, by.x = 'loinc', 
                                 by.y = 'LOINC_NUM')

# Start Testing ####

# Libraries our parallel code needs access to
lib_ls = c('tidyverse', 'stringr', 'MASS', 'data.table', 'readxl',
           'elrm', 'logistf')


# Number of samples in a cell of contingency table to switch to 'exact' method
EXACT_SWITCH = 5
EXACT_METHOD = 'firth'

# debug writes directly out
DEBUG = TRUE

# log puts messages in a file
LOG = TRUE

base_out_dir = paste(RESULTS_DIR, '/res', sep = '')
base_log_dir =  paste(RESULTS_DIR, '/logs', sep = '')
base_stat_dir =  paste(RESULTS_DIR, '/run_stats', sep = '')

# Minimum number of cases and controls to run with we will come back and remove
# those without 17 cases and < 187 total samples later, right now we just want
# to run this.
MIN_N_CASES = 10
MIN_N_CONS = 10 

# Make list of covs we have in TNX data
covs_we_have = colnames(cov_dat)
covs_we_have = covs_we_have[covs_we_have != 'patient_id']

# Result columns
result_cols =  c('disease_name', 'icd', 'dis_sex',  'con_str',
                 'num_case', 'num_con', 'n_mixed',
                 'org', 'test', 'anti', 'p_val', 'OR', 'CI', 'model', 
                 'mod_version', 'cov_adj', 'ukb_covs', 'cov_ps', 'cov_or',
                 'case_age', 'con_age', 'case_titer', 'con_titer', 
                 'case_titer_std', 'con_titer_std', 'case_titer_med', 
                 'con_titer_med', 
                 'n_con_neg', 'n_con_pos', 'n_case_neg', 'n_case_pos',
                 'glm_warn_msg', 'glm_warn_bool', 
                 'proc_time', 'date_time', 'test_id',  
                 'test_type', 'var_types', 'mod_method', 'note_str', 
                 'org_test_tag')



# US uses B20 for HIV, UK uses B24 for HIV.
if (INPUT_ICD == 'B20') {
  curr_prev_res = prev_res[((prev_res$icd == 'B24')),]
} else {
  curr_prev_res = prev_res[((prev_res$icd == INPUT_ICD)), ]
}


if (nrow(curr_prev_res) == 0) {
  print(glue("[ERORR]: Failed to pull row from prev_res for: {INPUT_ICD}"))
  quit("no", 1)
  
}


curr_icd = INPUT_ICD

# Dis-org pair info
pair_info = read.csv(glue("{HOME}/other/trinetx/new_dataset/pair_data/{curr_icd}/{curr_icd}_summaries.tsv"),
                     sep = '\t')

# Generate our output and log directories
#OUT_DIR = paste(base_out_dir, "/", curr_icd, sep = '')
#LOG_DIR = paste(base_log_dir, "/", curr_icd, sep = '')

# Put log and res files in main directory instead of sub ICD dirs
OUT_DIR = base_out_dir
LOG_DIR = base_log_dir
STAT_DIR = base_stat_dir

# Create the directories if needed
if (!dir.exists(OUT_DIR)){
  dir.create(OUT_DIR, recursive = TRUE)
}
if (!dir.exists(LOG_DIR)){
  dir.create(LOG_DIR, recursive = TRUE)
}    

if (!dir.exists(STAT_DIR)){
  dir.create(STAT_DIR, recursive = TRUE)
}    


# Create our results and log filenames
RES_FN = paste(OUT_DIR, "/", curr_icd, "_results.tsv", sep = '')
LOG_FN = paste(LOG_DIR, "/", curr_icd, "_debug.log", sep = '')
STAT_RES_FN = paste(STAT_DIR, "/", curr_icd, "_run_stats.log", sep = '')
  
if (LOG == TRUE) {
  write("Starting logging...", file = LOG_FN, append = TRUE)
}
if (DEBUG == TRUE) {
  cat("Starting debugging\n")
}  

# Generate df that will hold the results, columns included depend on type
# of test
res = data.frame(matrix(nrow = 0, ncol = length(result_cols)))
colnames(res) = result_cols
res <- res %>% mutate_if(is.logical, as.character)

# Create stat results df so we can more easily monitor the tests happening.
stat_cols = c('icd', 'org', 'anti', 'tot_tests', 'tot_tests_w_case_num',
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
  curr_icd = INPUT_ICD
  curr_tag = curr_row[,'test_tag']
  curr_anti = curr_row[,'anti']
  curr_dis_name = curr_row[,'Disease']
  
  # The tags with 'underscores' will need these removed to find pair data files
  curr_fn_tag = gsub('_', '', curr_tag)
  curr_fn_anti = gsub(' ', '_', curr_anti)
  

  # Send message about what we are starting to work on.
  msg_str = paste0("[", curr_icd, "] ", curr_dis_name, "\n\t", curr_tag, "/",
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
  
  
  # Limit to CAT tests
  curr_test_df = curr_test_df[curr_test_df$final_type == TEST_TYPE, ]
  
  # Remove any weird dupes
  curr_test_df = unique(curr_test_df)
  
  # Send message about what we are starting to work on.
  msg_str = paste0("Found ", nrow(curr_test_df), " ", TEST_TYPE, 
                   " tests for ", curr_icd, 
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
    
    msg_str = paste0("\t[WARNING]: No tests for ", curr_icd, ' x ', curr_tag)
    
    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)   
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    
    fail_stats = list("icd" = curr_icd, 
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
    
    fail_res = c("disease_name" = curr_dis_name, 
                 "icd" = curr_icd,
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
  curr_test_df$icd = curr_icd
  
  # Merge the current test df with the pair info df to see which of these 
  # tests we have dis-test pair data for
  # all.x means left join
  curr_test_df = merge.data.frame(x = curr_test_df, 
                                  y = pair_info[, c('dis', 'loinc_test', 
                                                    'org', 'case_n', 'con_n')], 
                                  all.x = TRUE,
                                  by.x = c('icd', 'loinc'), 
                                  by.y = c('dis', 'loinc_test'))
  
  # We now have count info (pos/neg results) for each test for this org paired
  # with this disease
  curr_test_bf_case_filt = nrow(curr_test_df)
  
  # Keep only the tests we have enough cases and controls for pair data for
  curr_test_df = curr_test_df[((curr_test_df$case_n >= MIN_N_CASES) & 
                                 (curr_test_df$con_n  >= MIN_N_CONS)), ]
  
  curr_test_after_case_filt = nrow(curr_test_df)
  
  # Send message about what we are starting to work on.
  msg_str = paste0(nrow(curr_test_df), " of the ", TEST_TYPE, 
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
    msg_str = paste0("\t[WARNING]: No tests for ", curr_icd, ' x ', curr_tag)

    if (LOG == TRUE) {
      write(msg_str, file = LOG_FN, append = TRUE)   
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    
    fail_stats = list("icd" = curr_icd, 
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
    
    
    fail_res = c("disease_name" = curr_dis_name, 
                 "icd" = curr_icd,
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
  dis_info = c("disease_name" = curr_dis_name, 
               "icd" = curr_icd,
               "dis_sex" = dis_sex_str, 
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
    
    # Set the column we should be looking for
    curr_test_type = curr_test$final_type
    if (curr_test_type == 'num') {
      VAL_COL = 'lab_result_num'
    } else {
      VAL_COL = 'lab_result_text'
    }
    

    
    # Send user a status update, that we are now working on this test.
    msg_str = paste0("\n\n[", curr_icd, "] ", curr_dis_name, "\n\t", curr_tag, "/",
                     curr_fn_tag, " ", curr_fn_anti, '\n',
                     "\t", curr_test_id, ' [', curr_test_type, ']: ', 
                     curr_test_name)
    
    if (LOG == TRUE) {
      
      write(msg_str, file = LOG_FN, append = TRUE)  
    }
    
    if (DEBUG == TRUE) {
      cat(paste0(msg_str, '\n'))
    } 
    
    
    # Legacy code from when we were considering continuous tests
    log_trans = FALSE
    
    # Get the filename that contains our disease-loinc test pair individual
    # level data.
    
    # Special naming scheme for high risk HPV
    if ((curr_test_tag == 'hpv_hr') | (curr_test_tag == 'hpv18, hpv45')) {
      pair_fn = paste(pair_dir, "/", curr_icd, "/", 
                      curr_icd, "_hpv_high_risk_", curr_test_id, 
                      "_single_thread.tsv", sep = '')         
      
    } else if (curr_test_tag == 'hpv16, hpv18') {
      
      pair_fn = paste(pair_dir, "/", curr_icd, "/", 
                      curr_icd, "_hpv16_18_", curr_test_id, 
                      "_single_thread.tsv", sep = '')          
      
    } else {
      # See if we have pair data for test
      pair_fn = paste(pair_dir, "/", curr_icd, "/", 
                      curr_icd, "_", curr_fn_tag, "_", curr_test_id, 
                      "_single_thread.tsv", sep = '')      
    }
    

    
    # If the file doesn't exist for some reason just move to next organism test
    if (file.exists(pair_fn) == FALSE) {
      msg_str = paste0("\t\t[ERROR]: File for ", curr_test_id, ' [', curr_test_type, ']: ', 
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
    
    # Merge in covariate data
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
    
    
    msg_str = paste0('\t\t[Before - cov filtering] nCase: ', n_case_bf_cov_chk,  ' | nCon: ',
                     n_con_bf_cov_chk, '\n\t\t[After  - cov filtering] nCase: ',
                     n_case_af_cov_chk, ' | nCon: ', n_con_af_cov_chk)
    if (LOG == TRUE) {
      
      write(msg_str, file = LOG_FN, append = TRUE)
    }
    
    if (DEBUG == TRUE) {
      cat(paste(msg_str, '\n', sep = ''))
    } 
    
    
    # Switch mod_ant from string 'Negative'/'Positive' values to integers
    if (curr_test_type == 'cat') {
      # This should have been taken care of in data cleaning and I think it was,
      # but just to be sure
      dat_df = dat_df[((dat_df$mod_ant == 'Negative') | 
                         (dat_df$mod_ant == 'Positive')),]
      
      dat_df$mod_ant <- as.character(dat_df$mod_ant)
      dat_df[dat_df$mod_ant == 'Negative', 'mod_ant'] = 0
      dat_df[dat_df$mod_ant == 'Positive', 'mod_ant'] = 1
      dat_df$mod_ant <- as.numeric(dat_df$mod_ant)
    }
    
    msg_str = paste0("\t\t\tSex-spec: ", curr_sex_spec, " | dis_sex: ", dis_sex, 
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
    
    msg_str = paste0("\t\t[Before - sex filtering] nCase: ", length(case_inds), " | nCon: ", 
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
      
      
      # If the test needs specifically healthy pregnancy controls, pull in the
      # list of patient IDs with a healthy pregnancy in their record
      if (curr_con_grp == 'O80,O81,O82,O83,O84') {
        
        # Only keep controls that have had a healthy pregnancy
        control_inds = intersect(control_inds, health_preg_ls)
        
        # Make sure someone isn't in both case_inds and control_inds!
        in_both = intersect(control_inds, case_inds)
        mixed_cnt = length(in_both)
        
        case_inds = case_inds[!(case_inds %in% in_both)]
        control_inds = control_inds[!(control_inds %in% in_both)]
        
        # Only keep people that are of the sex needed
        case_inds = case_inds[(case_inds %in% sex_inds)]
        control_inds = control_inds[(control_inds %in% sex_inds)]
        
        # Just regular sex-specific filtering, so filter by sex 
      } else {
        
        # Limit case and control patients to only those with sex matching dis_sex
        case_inds = case_inds[case_inds %in% sex_inds]
        control_inds = control_inds[control_inds %in% sex_inds]
        
      }
      
    }
    
    msg_str = paste0("\t\t[After  - sex filtering] nCase: ", length(case_inds), " | nCon: ", 
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
    # throw an error: contrasts can be applied only to factors with 2 or more levels
    if ((sum(lapply(lapply(lapply(dat_df, na.omit), unique), length) < 2)) > 0)
    {
      
      rem_me = colnames(dat_df)[lapply(lapply(lapply(dat_df, na.omit), unique), length) < 2]
      
      # If rem_me (columns with only 1 unique value) is either mod_ant or mod_dis
      # we just quit bc there's no point!
      if (('mod_ant' %in% rem_me) | ('mod_dis' %in% rem_me))
      {
        if (DEBUG == TRUE) {
          if ('mod_ant' %in% rem_me) {
            msg_str = paste0("\t\t[WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
                        curr_test_name, " mod_ant in remove (lapply) skipping - only 1 level!")
            if (LOG == TRUE) {
              write(msg_str, file = LOG_FN, append = TRUE)
            }
            
            if (DEBUG == TRUE) {
              cat(msg_str)
              
            }
            
          } else {
            msg_str = paste0("\t\t[WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
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
      msg_str = paste0("\t\t[WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
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
    avg_age_case = round(mean((case[,'age']) * 10, na.rm = TRUE),2)
    avg_age_con = round(mean((control[,'age']) * 10, na.rm = TRUE),2)
    
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
    
    # Legacy from when we were considering continuous tests
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
      msg_str = paste0("\t\t[WARNING]: ",  curr_test_id, ' [', curr_test_type, ']: ', 
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
    
    # If we have a cell with <= our EXACT_SWITCH requirement, we will switch 
    # to an exact logistic regression model (firth)

    if (sum(tab_res <= EXACT_SWITCH) > 0) {
      msg_str = paste0("\t\tRunning exact test as one cell fell below ", 
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
    
    
    msg_str = paste0("\n\t\t[SUCCESS]: ", curr_test_id, ' [', curr_test_type, ']: ', 
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
  
  fail_stats = list("icd" = curr_icd, 
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
