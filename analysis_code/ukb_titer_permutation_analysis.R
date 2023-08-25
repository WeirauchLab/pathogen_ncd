# Name:     ukb_titer_permutation_analysis.R
# Author:   Mike Lape
# Date:     2/7/2020
# Description:
#
#   This script can be used to calculate a null distribution for a specified
#   disease. It follows what Lisa Martin and I discussed. You provide an ICD10
#   code on the command line and it runs N_PERMUTE permutations of each
#   association between that disease and all 45 Abs. It does not calculate
#   any empirical p-values, we'll use the permutation p-values to generate
#   these in different file.
#

library(stringr)
library(performance)
library(MASS)
library(openxlsx)

OUT_FILE_DATE = '01_17_2023'

# Set some global constants ####
LOCAL_COPY_PATH =  "/data/pathogen_ncd"

# This is the dataframe we will use for our data to be fed into our logistic 
# regression models, so it will contain a column of titers for an antibody, a 
# column for disease status, and then all of the covariate data.  I hate that
# I had to do this but I'm making it global due to scoping issues with the 
# logistic regression model performance metrics not being able to obtain this
# data, yet seemingly needing it.
dat_df <- NA

# We are shuffling so if we set a seed this should theoretically be reprod.
OUR_SEED = 5
set.seed(OUR_SEED)


# Source helper function file ####
path_to_help = "/code/antigen_research/antigen_R/helper_functions_pub.R"
path_to_analysis = "/code/antigen_research/antigen_R/analysis_functions_pub.R"

help_loc = paste(LOCAL_COPY_PATH, path_to_help, sep = "")
analysis_loc = paste(LOCAL_COPY_PATH, path_to_analysis, sep = "")
HOME = LOCAL_COPY_PATH

# Load in our helper functions - here is used to make sure we find the file.
source(help_loc)
source(analysis_loc)


# Grab command line parameters ####
setwd(paste(HOME, 'procd/perm_p_sim_inputs/final', sep = "/"))

# Use commandArgs to get the paramters
args <- commandArgs(trailingOnly = TRUE)

# test if there is at least 4 arguments: if not, return an error
if ((length(args)== 0) | (length(args) < 4)) 
{
  stop("Please supply ICD10 code after --icd flag and a number of 
         permutations to run after the --perm flag!", call.=FALSE)
} 

if(args[1] == "--icd")
{
  curr_icd = args[2]
} else if (args[1] == "--perm")
{
  N_PERMUTE = args[2]
} 

if(args[3] == "--icd")
{
  curr_icd = args[4]
} else if (args[3] == "--perm")
{
  N_PERMUTE = args[4]
}


# Convert input N_PERMUTE from string to int
N_PERMUTE = strtoi(N_PERMUTE, base = 10)


# Switch to our results dir
res_dir = (paste(HOME, 'results/perm_p_sims/final/', sep = "/"))

setwd(res_dir)


# Read in all data  #####   
# A lot of the disease names and antigens are not syntactically valid
# names in R, so using check.names = FALSE, because it mangles
# the column names, when I actually go to do calculations I'll use
# make.names to get syntactically valid column names

loaded_dat = load_data(LOCAL_COPY_PATH)

cov_dat = loaded_dat$cov_dat
ant_dat = loaded_dat$ant_dat
dis_dat = loaded_dat$dis_dat
roll_dat = loaded_dat$roll_dat
ant_dict = loaded_dat$ant_dict
sex_spec_dis = loaded_dat$sex_spec_dis

# Processing Input ####

# Combine all disease data (non-cancer and cancer) by eid in column 1 
# Currently only considering the 3-character ICD10 code diagnoses data 
# (roll_dat) not the more granular spec_dat.
all_dis = merge(dis_dat,roll_dat, by=0, all=TRUE, sort = FALSE)

# Set the row names back to normal and drop the Row.names column that merge 
# added.
row.names(all_dis) = all_dis$Row.names
all_dis$Row.names = NULL

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

# Python has boolean values of False and True whereas R uses FALSE and TRUE, so
# here we are just converting the python booleans to R booleans
# Doing this for all_dis df, looping over and applying to each column/separate
# disease.
for (x in colnames(all_dis))
{
  all_dis[,x] = ifelse(all_dis[,x] == "True", TRUE, FALSE)
}

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


# Limit to only those diseases with 10 or more cases for now, we will do the 
# actual statistical power required post-hoc, dropping diseases that don't hit
# the >= 17 cases and >= 187 total samples later.
# all_dis:  1,254 diseases
# dis_w_10: 558 diseases
dis_w_10 = all_dis[,colSums(all_dis) >= 10]


# Code used to do analysis on only non ICD10 chapters A, B, and Q diseases
# dis_w_10: 558 diseases
# Chap A: 14 diseases
# Chap B: 23 diseases
# Chap Q:  9 diseases
# dis_w_10 filtered = 512 diseases.
dis_chaps = str_sub(colnames(dis_w_10), start = -4, end = -4)
a_b = dis_w_10[, colnames(dis_w_10)[(dis_chaps == 'A' | dis_chaps == 'B')]]
q =   dis_w_10[, colnames(dis_w_10)[dis_chaps == 'Q']]
dis_w_10 = dis_w_10[, colnames(dis_w_10)[
  (dis_chaps != 'A' & dis_chaps != 'B' & dis_chaps != 'Q')]]

healthy_pregnancy_search_str = "\\[O80\\]|\\[O81\\]|\\[O82\\]|\\[O83\\]|\\[O84\\]"

o_cons = dis_w_10[grep(healthy_pregnancy_search_str, colnames(dis_w_10))]
o_con_inds = unique(rownames(which(o_cons == TRUE, arr.ind = T)))



# Now add the gold and silver standard diseases back in.
a_b_stds = c("A60", "B00", "B02", "B19", "B24", "B27")
std_dat = a_b[,grep(paste(a_b_stds, collapse = '|'), colnames(a_b))]

# Leaving us with 518 diseases!
dis_w_10 = merge(std_dat, dis_w_10, by = 0, all = TRUE, sort = FALSE)
row.names(dis_w_10) = dis_w_10$Row.names
dis_w_10$Row.names = NULL


# Unify indices (some participants left UKB, and were removed from some datasets
# but not others).

dis_idx = row.names(dis_w_10)
cov_idx = row.names(cov_dat)
ant_idx = row.names(ant_dat)
common_idx = intersect(dis_idx, intersect(cov_idx, ant_idx))

dis_w_10 = dis_w_10[common_idx, ]
cov_dat = cov_dat[common_idx, ]
ant_dat = ant_dat[common_idx, ]



# Create output df ####
# Create empty df to hold our associations for this disease 1 row for 
# each of the antibodies we are testing [45]
# This is a per-permutation.
dis_res = data.frame(matrix(nrow = 0, ncol = 37))


result_cols =  c('Unparsed_Disease',
                 'Disease', 'ICD10_Cat', 'ICD10_Site',
                 'sex_specific_dis', 
                 'nCase', 'nControl', 'control_set', 'n_mixed',
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




# Give it proper colnames
colnames(dis_res) = result_cols

# Antigen ~ covariate association analysis ####
# Associations between each antibody (titer - continuous) and each covariate (
# continuous or categorical) will be pre-calculated, and the resulting list of
# significantly associated covariates for each antibody will be put in a lookup 
# table for use later in the analysis.
# There is also extra logic added to deal with sex-specific diseases, where
# the antibody-sex covariate association test will be skipped.
# Offloads association calculations to helper_function.R calc_ant_assoc antigen.

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


# Create Output and Log Files #####

# We are switching to a new naming mechanism
# Disease_pid.log
# Disease_pid.result
#
# We are putting the pid in the file just in case we need unique 
# names down the line.

# Get PID of this process so we can tag our output files with it 
pid = Sys.getpid()

# Give our current grid item its log and result file names - absolute paths
curr_res_fn = paste(res_dir, curr_icd, "_perms_", N_PERMUTE, "_pid_",
                    pid, "_", OUT_FILE_DATE, "_result.tsv", sep = "")
                    
print(paste("Result file: ", curr_res_fn, sep = ""))

# Write header into our output file
write.table(dis_res, curr_res_fn, sep = "\t", 
            append = F, row.names = FALSE, quote = F)


# Read in latest analytical results
prev_res_fn = "./results/tri_mod_results_01_17_2023.csv"
prev_res = read.csv(prev_res_fn)

# Change the column name for sex specific disease for analytical results
colnames(prev_res)[5] = "dis_sex"

# We don't need to run analysis on healthy control pregnancies 
# So write message to log file and then stop further processing
if (curr_icd == "O80" | curr_icd == "O81" | curr_icd == "O82" | 
    curr_icd == "O83" | curr_icd == "O84")
{
  o_out_str = 'ICD10 chapter O control disease (healthy pregnancy) skipping!'
  o_out_ls = rep(o_out_str, ncol(dis_res))
  dis_res[(nrow(dis_res) + 1), ] = o_out_ls
  
  write.table(dis_res, curr_res_fn, sep = "\t", 
              col.names = F, row.names = FALSE,
              append = T, quote = F)
  
  stop(o_out_str)
  
}

# Start processing data #####

# Look at the results for our disease of interest and collect some information
dis_prev_res = prev_res[prev_res$icd == curr_icd, ]

curr_dis_name = head(dis_prev_res$Unparsed_Disease, 1)

# Extract the control set the original analysis used so we can
# set up our data for permutations appropriately.
curr_dis_con_set = head(dis_prev_res$control_set, 1)

# Indicator to tell our code if we have a sex-specific code,
# that is an ICD10 code that can only be diagnoses in men or women
# but not both.  The default is FALSE, meaning it is not sex-specific
# and both men and women can be diagnoses with this disease.
curr_dis_sex = head(dis_prev_res$dis_sex, 1)


if (curr_dis_sex == 'Both') {
  dis_sex_str = "Both"
  curr_is_sex_spec = FALSE
  dis_sex = -1
  control_str = 'all'
  
  
} else if (curr_dis_sex == 'Female') {
  
  dis_sex = 0
  dis_sex_str = "Female"
  curr_is_sex_spec = TRUE
  
  control_str = curr_dis_con_set

} else {
  dis_sex = 1
  dis_sex_str = "Male"
  curr_is_sex_spec = TRUE
  control_str = 'male'
  
}

# Run perms for all Abs
curr_ant_list = names(ant_dat)


# Collect the ICD10 data on this disease.
icd_res = get_icd(curr_dis_name)
dis = icd_res$dis
icd_cat = icd_res$cat
icd_loc = icd_res$loc

full_code = paste(icd_cat, icd_loc, sep = "")

# Start permuting! #####

# perm_analysis will handle writing the results out to results file.
curr_permute_num = 1

while (curr_permute_num <= N_PERMUTE){

      perm_analysis(dis_name           = curr_dis_name, 
                    curr_res_fn        = curr_res_fn,
                    ant_list           = curr_ant_list, 
                    is_sex_spec        = curr_is_sex_spec,
                    control_str        = control_str,
                    do_good_fit_checks = FALSE,
                    DEBUG              = FALSE)
  


  curr_permute_num = curr_permute_num + 1
}
