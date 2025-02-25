# Name:     ukb_icd_analysis_pub.R
# Author:   Mike Lape
# Date:     01/17/2022
# Description:
#
#   This program reads in several files that have been previously prepared
#   using the jupyter notebook ukb_icd_data_cleaning_pub.ipynb, representing
#   covariate data, antibody data, both cancer and non-cancer disease data, 
#   and an antigen dictionary that maps antigen to organisms and such.  
#   
#   It calculates association between an antibody titer level and disease status
#   examining all diseases in input files (minor filtering within code) and all
#   antibodies in input files using a logistic regression model.
#   
#   This analysis uses a step-wise [Backward Elimination] logistic regression 
#   model where a fully adjusted model (adjusted for any covariate significantly
#   associated with both disease status and separately antibody titer) which is 
#   used to leave only the most important covariates.
# 
#       dis_status ~ antibody_titer + most important covs.
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


# Source helper function file ####
path_to_help = "/code/analysis/helper_functions_pub.R"
path_to_analysis = "/code/analysis/analysis_functions_pub.R"

help_loc = paste(LOCAL_COPY_PATH, path_to_help, sep = "")
analysis_loc = paste(LOCAL_COPY_PATH, path_to_analysis, sep = "")
HOME = LOCAL_COPY_PATH

# Load in our helper functions - here is used to make sure we find the file.
source(help_loc)
source(analysis_loc)

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
# statistical power required filtering after, dropping diseases that don't hit
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

# We need to identify healthy pregnancy cases so we have that cohort ready to be
# controls for any ICD10 O diseases tested
healthy_pregnancy_search_str = "\\[O80\\]|\\[O81\\]|\\[O82\\]|\\[O83\\]|\\[O84\\]"

o_cons = dis_w_10[grep(healthy_pregnancy_search_str, colnames(dis_w_10))]
o_con_inds = unique(rownames(which(o_cons == TRUE, arr.ind = T)))


# Now add the Tier 1 and Tier 2 standard diseases back in.
a_b_stds = c("A60", "B00", "B02", "B19", "B24", "B27")
std_dat = a_b[,grep(paste(a_b_stds, collapse = '|'), colnames(a_b))]

# Merge back in the A and B standand diseases, leaving us with 518 diseases!
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

# mod_res will contain the model results and metadata for each disease-antibody 
# pair
mod_res = data.frame(matrix(nrow = 0, ncol = 37))


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
# from dis_w_10 and process each one, one-by-one.

# re-initialize cnt variable, used for progress messages to user.
cnt = 1

for (x in colnames(dis_w_10))
{
  
  
  # Run disease analysis on disease x
  ret = step_analysis(x, cnt, o_con = 'o_cons', DEBUG = TRUE)
  
  # Take the returned disease results and put them in our global result df
  mod_res = rbind.data.frame(mod_res, ret)
  
  # Increment the disease counter to be used by analysis to show progress to 
  # user.
  cnt = cnt + 1
}

# Write this file out real quick
fn = paste("./results/mod_res_", OUT_FILE_DATE, ".csv", sep = '')
write.csv(mod_res, fn, row.names = F)

# Start some post-processing ####
# Add in ICD10 code column
mod_res$icd = paste(mod_res$ICD10_Cat, mod_res$ICD10_Site, sep = '')


# Create df of just our "unknown" pairs
mod_res_df = mod_res[!mod_res$ICD10_Cat %in% c("A", "B", "Q"),]

# Tier 1 and 2 positive control stuff ####
# Tier 1 will sometimes be labeled as 'Gold', Tier 2 as 'Silver' and control as 
# standard.
setwd("results/")

# This is just a list of tier 1 and tier 2 disease-pathogen pairs
std_dat = as.data.frame(read_excel('./misc/tier1_and_tier2_standards_w_notes.xlsx'))
std_dat$icd = paste(std_dat$ICD10_Cat, std_dat$ICD10_Site, sep = '')

# Where we will put our standard results
mod_stans = data.frame(matrix(nrow = 0, ncol = (ncol(mod_res_df) + 1), 
                                dimnames = list(c(),
                                    append(colnames(mod_res_df), "std_lev"))))


# Grabbing standard results ####
# Loop through our standards (dis-org pairs) and pull the results from our
# analysis and stuff them into this controls df.
pb <- txtProgressBar(min = 0, max = nrow(std_dat), style = 3)
cnt = 0
miss_cnt = 0

for (x in 1:nrow(std_dat))
{
  curr_icd = std_dat[x,'icd']
  curr_org = std_dat[x, 'organism']
  
  # Get standard level of pair
  curr_lev = std_dat[((std_dat$icd == curr_icd) & 
                        (std_dat$organism == curr_org)), 'Standard']
  
  # Get analysis results for this pair
  curr_res = mod_res[((mod_res$icd == curr_icd) & 
                          (mod_res$organism == curr_org)),]
  
  # If we don't have res for this dis-org pair for some reason notify user and
  # move on
  if (nrow(curr_res) == 0)
  {
    miss_cnt = miss_cnt + 1
    print(paste("Missing pair [", miss_cnt, "]:", curr_icd, 
                " with ", curr_org, sep = ''))
    next
  } 
  
  
  # If we have multiple antibody results for this pathogen
  if (nrow(curr_res) > 1)
  {
    for (y in 1:nrow(curr_res))
    {
      curr_res_single = curr_res[y,]
      curr_res_single$std_level = curr_lev
      mod_stans[(nrow(mod_stans) + 1), ] = curr_res_single
    }
  } else {
    curr_res$std_level = curr_lev
    mod_stans[(nrow(mod_stans) + 1), ] = curr_res
  }
  
  cnt = cnt + 1
  setTxtProgressBar(pb, cnt)
}


# Expected Negatives ####
# Expected negatives will sometimes be labeled as 'True Negatives'
# Pull the true negative results out
gs_dis = c('A60', 'B00', 'B02', 'B19', 'B24', 'B27')

mod_tn = data.frame(matrix(nrow = 0, ncol = ncol(mod_res), 
                           dimnames = list(c(),colnames(mod_res))))

# Loop over tier 1 standard diseases and org_list putting their results in tn
# as long as they are not in stans, which would mean they're a tier 1 standard.
pb <- txtProgressBar(min = 0, max = length(gs_dis), style = 3)
cnt = 0
for (x in gs_dis)
{
  for (y in org_list)
  {
    # check if in stans
    chk = mod_stans[((mod_stans$icd == x) & (mod_stans$organism == y)),]
    
    if (nrow(chk) > 0)
    {
      cat(paste("Found GS: ", x, " with ", y, sep = ''))
      next
    } 
    
    curr_tn = mod_res[((mod_res$icd == x) & 
                           (mod_res$organism == y)),]
    
    # If we have multiple antibodies for pathogen
    if (nrow(curr_tn) > 1)
    {
      for (z in 1:nrow(curr_tn))
      {
        curr_tn_single = curr_tn[z,]
        mod_tn[(nrow(mod_tn) + 1), ] = curr_tn_single
      }
    } else {
      mod_tn[(nrow(mod_tn) + 1), ] = curr_tn
    }
    
  }
  cnt = cnt + 1
  setTxtProgressBar(pb, cnt)
}

# Give our TN dfs the 'std_lev' column so it can be merged with std
mod_tn$std_lev = 'true_neg'

# Now append the tn df onto the stands df
mod_stans = rbind(mod_stans, mod_tn)


# Wrapping up ####

# Remove any standard results from our result files - this is dumb
pb <- txtProgressBar(min = 0, max = nrow(std_dat), style = 3)
cnt = 0
miss_cnt = 0

for (x in 1:nrow(std_dat))
{
  curr_icd = std_dat[x,'icd']
  curr_org = std_dat[x, 'organism']
  
  # Get standard level:
  mod_res_df = mod_res_df[!((mod_res_df$icd == curr_icd) &
                                  (mod_res_df$organism == curr_org)),]
  
  cnt = cnt + 1
  setTxtProgressBar(pb, cnt)
}

# Tag everything left in mod_res_df as unk
mod_res_df$std_lev = 'unk'


# Remove HIV from true negatives!
mod_stans = mod_stans[!(((mod_stans$icd == 'B24') | 
                               (mod_stans$organism == 'HIV')) & 
                              (mod_stans$std_lev == 'true_neg')),]


# Merge unknown and standards together
all = rbind.data.frame(mod_res_df, mod_stans)
all = all[!duplicated(all[,c('organism', 'Antigen', 'icd')]),]

# Add column to indicate if unadjusted p-value is significant
all$p_sig = all$p_val < 0.05

# Insert column saying if the OR is > 1 or < 1
all$anti_OR = as.numeric(as.character(all$anti_OR))
all$risk = all$anti_OR > 1
all$protect = all$anti_OR < 1
all$effect = ifelse(all$risk == TRUE, "Risk", "Protect")

# Fix the weird Â char
all$organism = killws(gsub("Â", "", all$organism))


# Write out final file in CSV and XLSX
write.table(all, paste('./ukb_mod_results_', OUT_FILE_DATE, '.csv', sep = ''),
            sep = ',', row.names = FALSE)

write.xlsx(all, paste('./ukb_mod_results_', OUT_FILE_DATE, '.xlsx', sep = ''))

# Save HTML doc ####
# Round p-values for better display

all$p_val = sapply(as.numeric(all$p_val), get_small,  3)

# Change to factor so you can sort doc
all$std_lev = as.factor(all$std_lev)
all$p_sig = as.factor(all$p_sig)
all$effect = as.factor(all$effect)


library(DT)
dt = datatable(all, options = list(autoWidth = TRUE), 
               filter = list(position = 'top', clear = FALSE))
htmlwidgets::saveWidget(dt, paste0('./ukb_mod_results_', OUT_FILE_DATE, '.html))