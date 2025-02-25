# Name:     ukb_phecode_analysis_pub.R
# Author:   Mike Lape
# Date:     06/13/2024
# Description:
#
#   This program reads in several files that have been previously prepared
#   using the jupyter notebook ukb_phecode_raw_data_proc.ipynb, representing
#   covariate data, antibody data, and an antigen dictionary that maps antigen 
#   to organisms and such. Outcomes will be Phecodes instead of ICD10 codes
#   which were prepared in ukb_phecode_translation_pub.R
#   
#   It calculates association between an antibody titer level and Phecode status
#   examining all Phecodes in input files (minor filtering within code) and all
#   antibodies in input files using a logistic regression model.
#   
#   This analysis uses a step-wise [Backward Elimination] logistic regression 
#   model where a fully adjusted model (adjusted for any covariate significantly
#   associated with both Phecode status and separately antibody titer) which is 
#   used to leave only the most important covariates.
# 
#       dis_status ~ antibody_titer + most important covs.
#
#


# Start a timer
full_st = Sys.time()

# Load libraries we will need.
suppressMessages(library(stringr))
suppressMessages(library(performance))
suppressMessages(library(MASS))
suppressMessages(library(readxl))
suppressMessages(library(progress))
suppressMessages(library(argparse))
suppressMessages(library(readxl))
suppressMessages(library(writexl))

# Get package versions ####
R_VERSION = R.version$version.string
PHEWAS_VERSION = as.character(packageVersion("PheWAS"))
SESSION_INFO = sessionInfo()


# Define some import constants ####
DATA_LOC = 'local'
DEBUG = TRUE
BASE_DIR =  "/data/pathogen_ncd"

# Statistical power information
OUT_FILE_DATE = format(Sys.Date(), "%Y_%m_%d")
STAT_POWER_N_CASE = 17
STAT_POWER_N_SAMPLE = 187


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


# Setup Phecode stuff ####
# Indicator of minimum code count being one.
ANALYSIS_TYPE = 'ONE'

# Setup environment
RES_DIR = paste0(BASE_DIR, "/phecode/ukb/ab_analysis")
LOG_DIR = paste0(RES_DIR, '/logs')
PHE_DIR     = paste0(BASE_DIR, '/phecode')
MANU_DIR = paste0(BASE_DIR, "/manuscript")
BASE_PHECODE_DIR = paste0(BASE_DIR, "/phecode/phecode_results/ukb/translation")
CODE_DIR    = paste0(BASE_DIR, '/code/phecoding')
PHE_REF_DIR = paste0(PHE_DIR, '/ref_files') 

dir.create(RES_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(LOG_DIR, recursive = TRUE, showWarnings = FALSE)

# Log file
LOG_FN = paste0(LOG_DIR, "/phecode_ab_analysis_", "MCC_", ANALYSIS_TYPE, "_", 
                OUT_FILE_DATE, ".log")
con <- file(LOG_FN, open = "wt")
close(con)

# Function to get the latest file version matching some search term in a 
# particular search directory.
find_latest_file <- function(search_dir = "", prev_stub = "")
{
  # List all files that match the pattern and have a .tsv extension
  match_files <- list.files(search_dir, pattern = paste0("^", prev_stub, 
                            ".*\\.xlsx$"), full.names = TRUE)
  
  # Check if any files were found
  if (length(match_files) == 0) {
    return(NA)  # Return NA if no files match
  }
  
  # Get file information, including modification times
  file_info <- file.info(match_files)
  
  # Find the newest file
  latest_fp <- rownames(file_info)[which.max(file_info$mtime)]
  
  return(latest_fp)
}

# Find the latest diagnosis directory
DIAG_FN = find_latest_file(search_dir = BASE_PHECODE_DIR, 
                             prev_stub  = 'all_ukb_one_min_code_cnt_')

# Load in gender restriction dats from Phecodes.org
PHE_SEX_SPEC_FN = paste0(PHE_REF_DIR, 
                          '/original_phecodes_gender_restriction.csv')

SEX_REF = read.csv(PHE_SEX_SPEC_FN, sep = ",", 
                   colClasses=c("phecode" = "character",
                                "male_only" = "logical",
                                "female_only" = "logical"))

# Load table with Phecode lookup table that has more info on each Phecode.
LOOKUP_FN = paste0(PHE_REF_DIR, '/original_phecodes_pheinfo.csv')
LOOKUP = read.csv(LOOKUP_FN, sep = ",", 
                   colClasses=c("phecode" = "character",
                                "description" = "character",
                                "groupnum" = "character",
                                "group" = "character", 
                                "color" = "character"))

# Load Phecodes to ICD(9 and 10) codes map file
ICD_PHE_FN = paste0(PHE_REF_DIR, 
                    '/icd9cm_w_icd10_phecode_map_for_ukb.csv')
ICD_PHE_MAP = read.csv(ICD_PHE_FN, sep = ",",
                            colClasses=c("vocabulary_id" = "character",
                                        "code" = "character",
                                        "phecode" = "character")
                       )
colnames(ICD_PHE_MAP) = c('vocab', 'icd', 'phecode')

# Conversion of UKB ICD9 to ICD10 pulled from 'first occurrences' mapping 
# Excel file.
ICD_MAP_FN = paste0(PHE_REF_DIR, 
                    '/ukb_primarycare_codings/all_lkps_maps_v4.xlsx')

# There are 16,160 rows in this Excel sheet before it has a couple of lines
# with attribution causing NA lines to be added
ICD_MAP = as.data.frame(read_excel(ICD_MAP_FN, sheet = 'icd9_icd10',
                            col_types=c("text", "text", "text", "text"),
                            n_max = 16160))

colnames(ICD_MAP) = c('icd9', 'icd9_descr', 'icd10', 'icd10_desc')

# Read in ICD results set (supplemental dataset 2).
ORIG_RES_FN = paste0(MANU_DIR, 
                     "/supplemental_datasets/supplemental_dataset_2.xlsx")

ORIG_RES = as.data.frame(read_excel(ORIG_RES_FN, sheet = 'Results'))

# Setup output filenames
RAW_RES_FN = paste0(RES_DIR, "/phecode_RAW_res_MCC_of_", ANALYSIS_TYPE,
                "_", OUT_FILE_DATE, ".csv", sep = '')

OUT_FN_SLUG = paste0(RES_DIR, "/ukb_phecode_results_MCC_of_", ANALYSIS_TYPE, 
                     "_", OUT_FILE_DATE)

CSV_RES_FN  = paste0(OUT_FN_SLUG, ".csv")
XLSX_RES_FN = paste0(OUT_FN_SLUG, ".xlsx")
HTML_RES_FN = paste0(OUT_FN_SLUG, ".html")


# Start logging and getting going ####
log_it(paste0(ts(), "Setting up environment:"))
log_it(paste0('\t\t\t    R version:    ', R_VERSION))
log_it(paste0('\t\t\t    Debug:    ', DEBUG))
log_it(paste0('\t\t\t    User Input:   ', DIAG_FN))
log_it(paste0('\t\t\t    Analysis Type:    ', ANALYSIS_TYPE))
log_it(paste0('\t\t\t    Data Location:    ', DATA_LOC))
log_it(paste0('\t\t\t    Log File:    ', LOG_FN))
log_it(paste0('\t\t\t    Raw Output:    ', RAW_RES_FN))
log_it(paste0('\t\t\t    Output CSV:    ', CSV_RES_FN))
log_it(paste0('\t\t\t    Output XLSX:    ', XLSX_RES_FN))
log_it(paste0('\t\t\t    Output HTML:    ', HTML_RES_FN))


log_it(paste0(ts(), " Loading all the Phecoding data\n"))
log_it(paste0('\t\t\t    Ref File Home       ', PHE_REF_DIR))
log_it(paste0('\t\t\t    Sex-Specific File:  ', 
              gsub(PHE_REF_DIR, '', PHE_SEX_SPEC_FN)))
log_it(paste0('\t\t\t    Lookup File:        ', 
              gsub(PHE_REF_DIR, '', LOOKUP_FN), '\n'))
log_it(paste0('\t\t\t    Mapping File:        ', 
              gsub(PHE_REF_DIR, '', ICD_PHE_FN), '\n'))
log_it(paste0('\t\t\t    GP Map File:        ', 
              gsub(PHE_REF_DIR, '', ICD_MAP_FN), '\n'))


# Set some global constants ####

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

# Read in all data  #####   
# A lot of the disease names and antigens are not syntactically valid
# names in R, so using check.names = FALSE, because it mangles
# the column names, when I actually go to do calculations I'll use
# make.names to get syntactically valid column names

loaded_dat = load_data(BASE_DIR)

cov_dat = loaded_dat$cov_dat
ant_dat = loaded_dat$ant_dat
dis_dat = loaded_dat$dis_dat
roll_dat = loaded_dat$roll_dat
ant_dict = loaded_dat$ant_dict
sex_spec_dis = loaded_dat$sex_spec_dis


log_it(paste0('\t\t\t    UKB Cov File:  ', 
              gsub(BASE_DIR, '', loaded_dat$cov_dat_path)))
log_it(paste0('\t\t\t    UKB Antibody File:        ', 
              gsub(BASE_DIR, '', loaded_dat$ant_dat_path), '\n'))
log_it(paste0('\t\t\t    Antibody Map File:        ', 
              gsub(BASE_DIR, '', loaded_dat$ant_dict_path), '\n'))



# Processing Input ####

# Figure out min number of codes required for Phecode for this analysis
all_dis = as.data.frame(read_excel(DIAG_FN))

row.names(all_dis) = all_dis$id
all_dis$id <- NULL

# As read in all covariates except for age and bmi, which are floats, are 
# typed as ints, so here we just convert them all to factors, except for 
# age and bmi
cov_dat$sex <- as.factor(cov_dat$sex)
cov_dat$ethnic <- as.factor(cov_dat$ethnic)
cov_dat$tdi_quant <- as.factor(cov_dat$tdi_quant)
cov_dat$num_in_house <- as.factor(cov_dat$num_in_house)
cov_dat$tobac <- as.factor(cov_dat$tobac)
cov_dat$alc <- as.factor(cov_dat$alc)
cov_dat$num_sex_part <- as.factor(cov_dat$num_sex_part)
cov_dat$same_sex <- as.factor(cov_dat$same_sex)


# Now applying to the sero-status columns of ant_dat.
ant_dat <- ant_dat[,1:45]
raw_ant_dat  = ant_dat[,1:45]

# This loop uses very simple logic to go through each different column of 
# raw_ant_dat and detect if raw_ant_dat if it contains the actual raw MFI values
# or if they have already been Log10 transformed.
# If they've already been transformed, notify the user and don't do anything,
# otherwise complete the Log10 transformation and overwrite the raw MFI column.
for (x in 1:ncol(raw_ant_dat))
{
  curr_anti = colnames(raw_ant_dat)[x]
  cat(paste("\U2560\U2550 ",curr_anti,
            " [", x, "/", ncol(raw_ant_dat),"]\n", sep = ''))
  
  curr_col = raw_ant_dat[,x]
  
  # Our highest raw titer is 19,010, which is 4.27898 after Log10 transform
  # So if our max is > 5 then this columns needs to be log transformed still
  # if not, then this column has already been transformed.
  # Also note, the lowest max value across all columns is 2,203 which is
  # 3.343 in log terms
  max_col_val = max(curr_col, na.rm = TRUE)
  if (max_col_val > 5)
  {
    # Not log transformed - overwrite our current column with log10 transformed
    # data
    raw_ant_dat[,x] = log10(raw_ant_dat[,x])
    cat(paste("   \U255A\U2550 Log10 Transforming\n", sep = ''))
  }  else
  {
    cat(paste("   \U255A\U2550 Already Transformed\n", sep = ''))
  }
}

# Modeling code was written using ant_dat variable - so since we are interested
# in antibody titer and disease association set ant_dat equal to the df that
# contains our antibody titer data, as opposed to sero-status for organism.
ant_dat = raw_ant_dat

# Fix antibody names (removing _init from them, and correcting 2 specific ones)
colnames(ant_dat) = str_remove(colnames(ant_dat), "_init")
colnames(ant_dat) = gsub("K8.1 antigen for Kaposi's Sarcoma-Associated Herpesviru", 
                         "K8.1 antigen for Kaposi's Sarcoma-Associated Herpesvirus", 
                         colnames(ant_dat))
colnames(ant_dat) = gsub("LANA antigen for Kaposi's Sarcoma-Associated Herpesviru",
                         "LANA antigen for Kaposi's Sarcoma-Associated Herpesvirus",
                         colnames(ant_dat))

org_list = as.character(unlist(unique(ant_dict['Abbrev'])))



# Limit to only those diseases with 17 or more cases and 187 or more samples.
sum_true  <- colSums(all_dis == TRUE, na.rm = TRUE)
sum_false <- colSums(all_dis == FALSE, na.rm = TRUE)

cols_w_power_list <- colnames(all_dis)[sum_true >= STAT_POWER_N_CASE & 
                               ((sum_true + sum_false) >= STAT_POWER_N_SAMPLE)]
cols_w_power = all_dis[, cols_w_power_list]

if (DEBUG == TRUE) {
  cat(paste0("\nAnalysis Date:                                   ", OUT_FILE_DATE,
             "\nPhecode analysis type:                           ", ANALYSIS_TYPE,
             "\nInput Phecodes:                                  ", 
             length(colnames(all_dis)), 
             "\nPhecodes with at least 17 cases and 187 samples: ", 
             length(cols_w_power_list), "\n\n"
  ))
}

# Unify indices (some participants left UKB, and were removed from some datasets
# but not others).
dis_idx = row.names(cols_w_power)
cov_idx = row.names(cov_dat)
ant_idx = row.names(ant_dat)
common_idx = intersect(dis_idx, intersect(cov_idx, ant_idx))

cols_w_power = cols_w_power[common_idx, ]
cov_dat = cov_dat[common_idx, ]
ant_dat = ant_dat[common_idx, ]


# Create output df ####

# res will contain the model results and metadata for each Phecode-antibody pair
mod_res = data.frame(matrix(nrow = 0, ncol = 36))


result_cols =  c('Disease_Description',
                 'Disease_Group', 'Phecode',
                 'sex_specific_dis', 
                 'nCase', 'nControl', 'nNA', 'control_set', 
                 'Antigen', 'organism',
                 'p_val', 'anti_OR', 'anti_CI',
                 'model', 'r2_tjur', 'r2_mcfad', 
                 'r2_adj_mcfad', 'r2_nagelkerke', 'r2_coxsnell',
                 'cov_ps', 'sig_covs',
                 'cov_adj_for', 'cov_ors',
                 'avg_age_case', 'avg_avg_con',
                 'avg_titer_case', 'avg_titer_con',
                 'std_titer_case', 'std_titer_con',
                 'med_titer_case', 'med_titer_con',
                 'Warnings', 'is_warning', 
                 'proc_time', 'date_time', 'perm_n')


colnames(mod_res) = result_cols


# Antigen ~ covariate association analysis ####
# Associations between each antibody (titer - continuous) and each covariate (
# continuous or categorical) will be pre-calculated, and the resulting list of
# significantly associated covariates for each antibody will be put in a lookup 
# table for use later in the analysis.
# There is also extra logic added to deal with sex-specific diseases, where
# the antibody-sex covariate association test will be skipped.
# Offloads association calculations to helper functions file, 
# calc_ant_assoc function.

cat("Pre-analyzing antigen ~ covariate associations...\n")

# Create our association lookup table with columns:
#   antigen: name of antibody
#   sex: sex this result is applicable to: "male", "female", "both"
#   sig_covs: comma-sep list of covariates significantly associated w/ antibody.
ant_cov_assoc = data.frame(matrix(nrow = 0, ncol = 3))
colnames(ant_cov_assoc) = c("antigen", "sex", "sig_covs")

# Antibody counter, used to send progress to user.
ant_cnt = 1
for (y in names(ant_dat))
{
  # Grab antibody data for the y'th antibody
  curr_ant = ant_dat[y]
  
  # Clean up antigen name
  # Antibody names from UKB have _init on them if this data was from initial
  # antibody screening, which is all we are using, e.g. "1gG antigen for Herpes 
  # Simplex virus-1_init", so we remove that trailing "_init"
  anti = str_remove(y, "_init")
  
  # Grab corresponding organisms abbreviation, e.g. HSV1.
  org = ant_dict[(grep(anti, ant_dict$Antigen)),'Abbrev'][[1]]
  
  # Print out our progress to user
  cat(paste("   \U255A\U2550 ",anti,
            " [", ant_cnt, "/", ncol(ant_dat),"]\n", sep = ''))
  
  # Create empty list to store significantly associated covariates.
  covs = list()
  
  # Merge our current antibody data with the cov_dat df for use in association
  # calculations.
  ant_df =  merge(curr_ant, cov_dat, by = 0, all = TRUE, sort = FALSE)
  
  # Merge causes us to lose the dataframe row names but also adds a new column
  # containing those old row names. So here we take that column and make it
  # the dataframe row names again and then remove that column
  row.names(ant_df) = ant_df$Row.names
  ant_df$Row.names = NULL
  
  # Changing the antibody column name from the actual antibody name to a 
  # placeholder name, "mod_ant", so we can address this column in loops.
  ant_df_names = names(ant_df)
  ant_df_names[1] = "mod_ant"
  names(ant_df) = ant_df_names
  
  # Convert all covariates to factors.
  ant_df$sex = as.factor(ant_df$sex)
  ant_df$ethnic = as.factor(ant_df$ethnic)
  ant_df$tdi_quant = as.factor(ant_df$tdi_quant)
  ant_df$num_in_house = as.factor(ant_df$num_in_house)
  ant_df$tobac = as.factor(ant_df$tobac)
  ant_df$alc = as.factor(ant_df$alc)
  ant_df$num_sex_part = as.factor(ant_df$num_sex_part)  
  ant_df$same_sex = as.factor(ant_df$same_sex)  
  
  # Do our association calculations across both sexes. Then collapse returned
  # list of significantly associated covariates into comma-separated string
  # and finally add a row for this antibody and a sex of "both" to the lookup
  # table with this string of significant covariates.
  covs = calc_ant_assoc(ant_df, FALSE)
  cov_str = paste(covs, collapse = ', ')
  ant_cov_assoc[nrow(ant_cov_assoc) + 1, ] = list(anti, "both", list(covs))
  
  
  # Repeat above process but only for females.  First extract female only data
  # sex == 0.
  f_ant_df = ant_df[ant_df$sex == 0, ]
  covs = calc_ant_assoc(f_ant_df, TRUE)
  cov_str = paste(covs, collapse = ', ')
  ant_cov_assoc[nrow(ant_cov_assoc) + 1, ] = list(anti, "female", list(covs))
  
  # Repeat above process but only for males  First extract male only data
  # sex == 1.
  m_ant_df = ant_df[ant_df$sex == 1, ]
  covs = calc_ant_assoc(m_ant_df, TRUE)
  cov_str = paste(covs, collapse = ', ')
  ant_cov_assoc[nrow(ant_cov_assoc) + 1, ] = list(anti, "male", list(covs))
  
  # increment our antibody counter used to send progress messages to user.
  ant_cnt = ant_cnt + 1
}


# Start analysis #####
# Here is where the real work begins.  We will loop through our list of diseases
# from cols_w_power and process each one, one-by-one.

# re-initialize cnt variable, used for progress messages to user.
cnt = 1

for (x in colnames(cols_w_power))
{

  
  # Run disease analysis on Phecode x
  # We don't have healthy pregnancy info for Phecodes so o_con is all_females
  ret = phecode_step_analysis(x, cnt, o_con = 'all_females', DEBUG = DEBUG)
  
  # Take the returned disease results and put them in our global result df
  mod_res = rbind.data.frame(mod_res, ret)
  
  # Increment the disease counter to be used by analysis to show progress to 
  # user.
  cnt = cnt + 1
}

# Write this file out real quick
write.csv(mod_res, RAW_RES_FN, row.names = F)



# Wrapping up ####
all = mod_res

# Create a list of 3-char ICD10 codes that are included in Phecode
icd_conv = data.frame(matrix(nrow = 0, ncol = 7))
colnames(icd_conv) = c('phecode', 'ICD10(s)', 'ICD_not_in_orig',
                       'ICD_in_orig', 'is_interesting',
                       'Translated_ICD9',
                        'Untranslated_ICD9')

orig_icd10_ls = unique(ORIG_RES$ICD10)

curr_phe_ls = unique(all$Phecode)
pb <- progress_bar$new(format = 
                         "(:spin) [:bar] :percent [:elapsedfull | ETA: :eta]",
                       total = length(curr_phe_ls), complete = "=", 
                       incomplete = "-", current = ">", clear = FALSE, 
                       width = 80)   
for (curr_phe in curr_phe_ls) {


  curr_icd_dat = ICD_PHE_MAP[(ICD_PHE_MAP$phecode == curr_phe),]
  
  curr_icd9 = curr_icd_dat[curr_icd_dat$vocabulary_id == 'ICD9CM', ]
  curr_icd9_ls = curr_icd_dat$code
  
  # Remove any ICD10-looking codes from the ICD9 list (I think ICD10 got added
  # as ICD9 at some point)
  curr_icd9_ls = curr_icd9_ls[!grepl("^[A-Za-z]", curr_icd9_ls)]
  curr_icd10 = curr_icd_dat[curr_icd_dat$vocabulary_id == 'ICD10', ]
  curr_icd10_ls = curr_icd10$code

  
  UNTRANS_CT = 0
  TRANS_CT = 0
  trans_icd10 = c()
  for (curr_icd9_val in curr_icd9_ls) {
    curr_conv_dat = ICD_MAP[ICD_MAP$icd9 == curr_icd9_val, ]
    
    if (nrow(curr_conv_dat) == 0) {
      UNTRANS_CT = UNTRANS_CT + 1
      next
    } else {
      trans_icd_ls = curr_conv_dat$icd10

      TRANS_CT = TRANS_CT + 1        
      trans_icd10 = c(trans_icd10, trans_icd_ls)

    }
  }
  
  curr_icd10_ls = append(curr_icd10_ls, trans_icd10)
  curr_icd10_3char_ls = unique(
    unlist(
      lapply(curr_icd10_ls, function(x) substr(x, 1, 3))
    )
  )
  # Remove any ICD9 codes that tranlated to UNDEFINED
  curr_icd10_3char_ls = curr_icd10_3char_ls[curr_icd10_3char_ls != 'UND']
  
  diff = setdiff(curr_icd10_3char_ls, orig_icd10_ls)
  if (length(diff) == 0) {
    diff_str = ''
  } else {
    diff_str = paste(diff, collapse = ', ')
  }
  
  
  inter = intersect(curr_icd10_3char_ls, orig_icd10_ls)
  if (length(inter) == 0) {
    inter_str = ''
  } else {
    inter_str = paste(inter, collapse = ', ')
  }
  
  
  if (inter_str == "") {
    interested = 'N'
    # If only 1 ICD10 and we did look at it interest is Y
  } else if (length(inter) == 1) {
    interested = '?'
    
    # Otherwise if there is some overlap but not exact interested is ?
  } else {
    if (length(curr_icd10_3char_ls)) {
    interested = 'Y'
    } else {
      interested = '?'
    }
  }
  
  
  curr_icd10_3char_str = paste(curr_icd10_3char_ls, collapse = ', ')
  
  icd_conv[(nrow(icd_conv) + 1), ] = c(curr_phe, curr_icd10_3char_str, 
                                       diff_str, inter_str, interested,
                                       TRANS_CT, UNTRANS_CT)

  pb$tick()
}


all = merge(all, icd_conv, by.x = "Phecode", by.y = "phecode", all.x = TRUE)

# Fix some data types:
all$nCase = as.integer(as.character(all$nCase))
all$nControl = as.integer(as.character(all$nControl))
all$nNA = as.integer(as.character(all$nNA))

all$p_val           = as.numeric(as.character(all$p_val))
all$avg_age_case    = as.numeric(as.character(all$avg_age_case))
all$avg_avg_con     = as.numeric(as.character(all$avg_avg_con))
all$avg_titer_case  = as.numeric(as.character(all$avg_titer_case))
all$avg_titer_con   = as.numeric(as.character(all$avg_titer_con))
all$std_titer_case  = as.numeric(as.character(all$std_titer_case))
all$std_titer_con   = as.numeric(as.character(all$std_titer_con))
all$med_titer_case  = as.numeric(as.character(all$med_titer_case))
all$med_titer_con   = as.numeric(as.character(all$med_titer_con))
all$proc_time       = as.numeric(as.character(all$proc_time))
all$r2_tjur         = as.numeric(as.character(all$r2_tjur))
all$r2_mcfad        = as.numeric(as.character(all$r2_mcfad))
all$r2_adj_mcfad    = as.numeric(as.character(all$r2_adj_mcfad))
all$r2_nagelkerke   = as.numeric(as.character(all$r2_nagelkerke))
all$r2_coxsnell     = as.numeric(as.character(all$r2_coxsnell))

# Add column to indicate if unadjusted p-value is significant
all$p_sig = all$p_val < 0.05

# Insert column saying if the OR is > 1 or < 1

# This will give warning:
#    NAs introduced by coercion
# This is because the ICD10 O control diseases: 
#   no_analysis_done_on_icd_chap_o_control
all$anti_OR  = as.numeric(as.character(all$anti_OR))
all$risk     = all$anti_OR > 1
all$protect  = all$anti_OR < 1
all[all$anti_OR == 1, c('risk', 'protect')] = FALSE



# Set effect direction (if OR == 1, then effect = NA, and the p-value should 
# not be significant anyways)
all$effect = "NA"
all[((all$risk == TRUE) & (all$protect == FALSE)), 'effect'] = 'Risk'
all[((all$risk == FALSE) & (all$protect == TRUE)), 'effect'] = 'Protect'

# Fix the weird Â char
all$organism = killws(gsub("Â", "", all$organism))

# Move some columns around
col_ls = c("Phecode", "Disease_Description", "Disease_Group", "ICD10(s)",
           "organism", "Antigen", "p_sig", "sex_specific_dis", 
           "stat_power", "nCase", "nControl", "nNA", "nSamp",
           "control_set", "p_val", "anti_OR", "sig_covs", "cov_adj_for",
           "anti_CI", "model", 
           "cov_ps", "cov_ors",
           "avg_age_case",   "avg_avg_con",
           "avg_titer_case", "avg_titer_con",
           "std_titer_case", "std_titer_con",
           "med_titer_case", "med_titer_con",
           "Warnings", "is_warning", "proc_time", "date_time", "perm_n",
           "risk", "protect", "effect", 
           "r2_tjur", "r2_mcfad",
           "r2_adj_mcfad", "r2_nagelkerke", "r2_coxsnell",
           'ICD_not_in_orig', 'ICD_in_orig', 'is_interesting',
           "Translated_ICD9", "Untranslated_ICD9")


# Mark all pairs that have statistical power
all$nSamp = as.integer(all$nCase) + as.integer(all$nControl)
all$nSamp = as.integer(all$nSamp)

all$stat_power = 'False'
all[((all$nCase >= STAT_POWER_N_CASE) & 
     (all$nSamp >= STAT_POWER_N_SAMPLE)), 'stat_power'] = 'True'

all = all[, col_ls]

# Write out final file in CSV and XLSX
write.table(all, CSV_RES_FN, sep = ',', row.names = FALSE)
write_xlsx(all, path = XLSX_RES_FN, col_names = T)

# Save HTML doc ####
# Round p-values for better display

# Change to factor so you can sort doc
all$p_sig = as.factor(all$p_sig)
all$effect = as.factor(all$effect)


library(DT)
dt = datatable(all, options = list(autoWidth = TRUE), 
               filter = list(position = 'top', clear = FALSE))
html_dir = dirname(HTML_RES_FN)
cwd = getwd()

setwd(html_dir)
htmlwidgets::saveWidget(dt, HTML_RES_FN)

setwd(cwd)

# Calculate the time this took and log it
full_end = Sys.time()
proc_time = full_end - full_st
proc_time = as.numeric(proc_time, units = "mins")
proc_time = round(proc_time, 3)
log_it(paste0(ts(), " Done with all work in ", proc_time, " minutes.\n"))


# Long line
log_it(paste0(strrep("=", 80), "\n"))
log_it(paste0(ts(), " All session info follows\n"))

# Dump the session information into the log
con <- file(LOG_FN, open = "at")
sink(con, type = "output", split = TRUE)
sink(con, type = "message", append = TRUE)
sessionInfo()
sink(type = "message")
sink()
close(con)

# Log a separator from the dumped session info.
log_it(paste0(strrep("=", 80),'\n'))

# Finally log out where all the files are.
log_it("\nAll done, remember where theose output files are!")
log_it(paste0('\t\t\t    Log File:     ', 
              gsub(PHE_DIR, '', LOG_FN)))
log_it(paste0('\t\t\t    Single Ouput: ', 
              gsub(PHE_DIR, '', OUT_FN_SLUG)))

log_it(paste0('\t\t\t    Raw Ouput: ',
              gsub(RES_DIR, '', RAW_RES_FN)))

log_it(paste0('\t\t\t    CSV Ouput: ',
              gsub(RES_DIR, '', CSV_RES_FN)))

log_it(paste0('\t\t\t    XLSX Ouput: ',
              gsub(RES_DIR, '', XLSX_RES_FN)))

log_it(paste0('\t\t\t    HTML Ouput: ',
              gsub(RES_DIR, '', HTML_RES_FN)))