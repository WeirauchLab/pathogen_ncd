# Name:     analysis_functions_pub.R
# Author:   Mike Lape
# Date:     01/17/2023
# Description:
#     This file contains the main analysis functions for calculating the 
#     antibody titer - disease associations for UKB data.  It contains a normal 
#     asymptotic only version and then a specialized version for our 
#     permutations. It also contains the code to run either a glm or firth model
#     for TNX data
#
#     This is the final update to the analysis functions where we add 
#     intelligent handling of ICD10 chap O diseases allowing for setting
#     control set to just all females, or all healthy birth codes.
#
HEALTHY_PREGNANCY_CODES = c("O80", "O81", "O82", "O83", "O84")

# step_analysis function. ####
# This function takes the name of a disease (unparsed) and the count of this
# disease (only used for progress notification to user) and generates all 
# logistic regression models for this disease and all 45 different antibodies
# using a backwards elimination step-wise method.
#
# Requirements:
#   step_ind_anti_analysis function
#
# Input:
#   dis_name [string]: unparsed disease, "other salmonella infections[A02]"
#   cnt      [int]   : count of which disease this is (used for progress output)
#   o_con    [string]: What should be used for controls for O diseases, either
#                      'all_females' or 'o_cons', which limits us to healthy
#                      birth codes as controls
#   DEBUG    [bool]: Boolean indicator if certain debug info should be printed.
# Output:
#   dataframe [1+ x 37] :
#         $Unparsed_Disease [string]: Unparsed disease name, input 'dis_name'
#         $Disease [string]: Disease name, "other salmonella infections"
#         $ICD10_Cat [string]: ICD chapter, "A"
#         $ICD10_Site [string]: ICD site code, "02"
#         $sex_specific_dis [bool]: Whether this is a sex-specific disease, F
#         $nCase [int]: Number of cases of this disease, 
#         $nControl [int]: Number of controls for this disease
#         $control_set [string]: Set of controls used for this analysis (
#                                "Both", "Female", "Male")
#         $n_mixed [int]: Number of people that are both case and control (
#                         relevant only for ICD10 O diseases, and these people
#                         are dropped from the analysis)
#         $Antigen [string]: Antibody for which this disease was modeled for 
#                            association.
#         $organism [string]: Organism abbreviation that produced the antigen
#         $p_val [float]: P-val of association between antibody level,
#                                 and disease status - from logistic regression.
#         $anti_or [string]: Odds ratio for this association
#         $anti_CI [string]: 95% confidence intervals for this OR
#         $model [string]: Logistic regression model formula with weights.
#         $r2_tjur [float]: Tjur's R2 or coefficient of determination.
#         $r2_mcfad [float]: Unadjusted McFadden's R2
#         $r2_adj_mcfad [float]: Adjusted McFadden's R2
#         $r2_coxsnell [float]: Cox & Snell's R2
#         $r2_nagelkerke [float]: Nagelkerke's R2
#         $cov_ps [string]: p-values for each covariate included in the
#                                   logistic regression model
#         $sig_covs [string]: String listing all covariates included in 
#                             fully adjusted model
#         $cov_adj_for  [string]: String listing just the covariates left after
#                                 backward elimination and thus adjusted for in
#                                 actual model.
#         $cov_ors [string]: String containing ORs and CIs for all covars
#                                that logistic regression model was adjusted for
#         $avg_age_case [float]: Average age of all cases
#         $avg_age_con [float]: Average age of all controls
#         $avg_titer_case [float]: Average titer level for cases
#         $avg_titer_con [float]: Average titer level for controls
#         $std_titer_case [float]: Standard deviation titer level for cases
#         $std_titer_case [float]: Standard deviation titer level for controls
#         $med_titer_case [float]: Median titer level for cases
#         $med_titer_case [float]: Median titer level for cases
#         $Warnings [string]: Text from any glm or CI warnings
#         $is_warning [bool]: whether a glm warning was thrown for model
#         $proc_time [string]: Amount of time the CPU took to process this pair
#         $date_time [string]: Date and time pair analysis was completed.
#         $perm_n [int]: Will always be -1 unless doing actual permutations
#
# Test:
#   val = analysis("other salmonella infections[A02]", 1)
#   
#
step_analysis <- function(dis_name, cnt = -1, o_con = 'all_females', 
                          DEBUG = FALSE)
{
  
  # Indicator to tell our code if we have a sex-specific code,
  # that is an ICD10 code that can only be diagnoses in men or women
  # but not both.  The default is FALSE, meaning it is not sex-specific
  # and both men and women can be diagnoses with this disease.
  is_sex_spec = FALSE
  
  # Create empty df to hold our associations for this disease 1 row for 
  # each of the antibodies we are testing [45]
  # This is a per-disease form of the res dataframe created earlier.
  dis_res = data.frame(matrix(nrow = 0, ncol = 37))

  # Give it proper colnames
  colnames(dis_res) = result_cols
  
  # Get the disease status data for the current disease we are looking at.
  curr_dis = dis_w_10[dis_name]
  
  # Current disease status message
  # ╠═ other salmonella infections[A02] [1/558]
  cat(paste("\U2560\U2550 ",dis_name, 
            " [", cnt, "/", ncol(dis_w_10),"]\n", sep = ''))
  
  # Collect the ICD10 data on this disease.
  icd_res = get_icd(dis_name)
  dis = icd_res$dis
  icd_cat = icd_res$cat
  icd_loc = icd_res$loc
  
  full_code = paste(icd_cat, icd_loc, sep = "")
  
  
  
  # Put together our data for this disease #####
  # First check if we are working on a sex-specific disease, by looking it up
  # in our sex_spec_dis lookup table
  # We will set the sex of this disease if true 
  # Female: 0
  # Male:   1
  if (full_code %in% sex_spec_dis$icd_code)
  {
    # We are processing a sex-specific disease so, set our flag and figure
    # out which sex this disease is specific to.
    is_sex_spec = TRUE

    
    if (sex_spec_dis[sex_spec_dis$icd_code == full_code, 'sex'] == "female")
    {
      dis_sex = 0
      dis_sex_str = "Female"
    } else
    {
      dis_sex = 1
      dis_sex_str = "Male"
    }
  } else
  {
    # If its not a sex-specific disease set the str to "both" and the dis
    # sex to indicator "-1"
    dis_sex_str = "Both"
    dis_sex = -1
  }
  
  control_str = 'all'
  mixed_cnt = 0
  
  # Get patient IDs for people that are cases and controls for this disease
  case_inds = rownames(which(curr_dis == TRUE, arr.ind = TRUE))
  control_inds = rownames(which(curr_dis == FALSE, arr.ind = TRUE))
  
  # If this is an ICD10 chap O disease consider controls
  if ((icd_cat == 'O') & (o_con == 'o_cons')) {
    
    control_inds = o_con_inds

    # Make sure someone isn't in both case_inds and control_inds!
    in_both = intersect(control_inds, case_inds)
    mixed_cnt = length(in_both)
    
    case_inds = case_inds[!(case_inds %in% in_both)]
    control_inds = control_inds[!(control_inds %in% in_both)]
    
    control_str = paste(HEALTHY_PREGNANCY_CODES, collapse = ',')

  # Otherwise is this a sex-specific disease?
  } else
  {
    # Check if we have sex-specific disease so if we do we can limit our cases
    # and controls to specific sex required.
    if (is_sex_spec)
    {
      
      sex_inds = row.names(cov_dat[cov_dat$sex == dis_sex, ])
      
      # Limit case and control patients to only those with sex matching dis_sex
      case_inds = case_inds[case_inds %in% sex_inds]
      control_inds = control_inds[control_inds %in% sex_inds]
     
      control_str =  dis_sex_str
    }
  }
  
  
  all_inds = c(case_inds,control_inds)
  curr_dis$id = row.names(curr_dis)
  
  curr_dis = curr_dis[all_inds, ]
  row.names(curr_dis) = curr_dis$id
  curr_dis$id <- NULL
  
  
  # Prepare the dataframe that will be used for all of our modeling, mod_df.
  # In this first step we merge the disease status data and covariate data.
  mod_df = merge(curr_dis, cov_dat, by = 0, all.x = TRUE, sort = FALSE)
  row.names(mod_df) = mod_df$Row.names
  mod_df$Row.names = NULL
  
  # Set up our disease column name so we can refer to it programmatically.
  # Just switching the actual disease name like "cholera..." to "mod_dis"
  # so we can more easily reference it in our code.  
  mod_df_names = names(mod_df)
  mod_df_names[1] = "mod_dis"
  names(mod_df) = mod_df_names
  
  # Switch mod_dis from logical vector to numeric with 0 = disease False, 
  # and 1 = disease True.
  mod_df$mod_dis = ifelse(mod_df$mod_dis == FALSE, 0, 1)  
  
  # Convert all covariates to ordered factors.
  mod_df$sex = as.factor(mod_df$sex)
  mod_df$ethnic = as.factor(mod_df$ethnic)
  mod_df$tdi_quant = as.factor(mod_df$tdi_quant)
  mod_df$num_in_house = as.factor(mod_df$num_in_house)
  mod_df$tobac = as.factor(mod_df$tobac)
  mod_df$alc = as.factor(mod_df$alc)
  mod_df$num_sex_part = as.factor(mod_df$num_sex_part)  
  mod_df$same_sex = as.factor(mod_df$same_sex)  
  
  
  # Create case and control specific dataframes, drop any subjects with any
  # NAs.  Right here na.omit should not affect anyone, if the data was cleaned
  # properly.
  case = na.omit(mod_df[case_inds , ])
  control = na.omit(mod_df[control_inds , ])
  
  # Debug message
  if (DEBUG == TRUE){
    
  
    cat(paste("\t\tis_sex_spec: ", is_sex_spec, " | is_o_dis: ", (icd_cat == 'O'),
                " | O-dis cons: ", o_con,
                "\n\t\tnCase: ", length(case_inds), " | nCon: ", length(control_inds),
                " | nAll: ", length(all_inds), 
                "\n\t\tnCase_mod: ", nrow(mod_df[mod_df$mod_dis == 1, ]), 
                " | nCon_mod: ", nrow(mod_df[mod_df$mod_dis == 0, ]),
              " | nrow(mod): ", nrow(mod_df), "\n"
                ))
  }
  
  # Calculate disease ~ covariate associations #####
  # Use helper function calc_dis_assoc to calculate association 
  # between this disease and all the covariates of interest, and making sure
  # to notify the function if our current disease is sex-specific.
  if ((o_con == 'o_cons') & 
      (full_code %in% HEALTHY_PREGNANCY_CODES)) {
    dis_covs = list()

  } else{
    dis_covs = calc_dis_assoc(mod_df, is_sex_spec)
    
  }
    
  
  # Start testing antibody titers ####
  # Here we finally start looping through all the different antibodies in 
  # ant_dat and do the modeling for association between our current disease and
  # each antibody.
  
  # Initialize a counter to update user on progress for each of 45 antibodies.
  ant_cnt = 1
  
  
  # Generate a list containing disease info that will be bound to each pair's
  # result list (used below).
  dis_info = c("unparsed_name" = dis_name, 
               "disease_name" = dis, 
               "icd_cat" = icd_cat,
               "icd_loc" = icd_loc,
               "dis_sex" = dis_sex_str)
  

  
  # Start looping through ant_dat
  for (y in names(ant_dat))
  {

    # If we have a healthy control as the disease we should return without
    # doing any sort of analysis since we won't have any cases!
    if ((o_con == 'o_cons') & 
        (full_code %in% HEALTHY_PREGNANCY_CODES)) {
      
          anti = ant_dict[ant_dict['Antigen'] == y,'Clean Ant Name']
          org = ant_dict[(grep(y, ant_dict$Antigen)),'Abbrev'][[1]]
          
          ret_ind_res = c("num_case" = length(case_inds), 
                          "num_con" = length(control_inds),
                          "antigen" = anti, "org" = org, 
                          "p_val" = 'no_analysis_done_on_icd_chap_o_control', 
                          "OR" = 'no_analysis_done_on_icd_chap_o_control', 
                          "CI" = 'no_analysis_done_on_icd_chap_o_control',  
                          "model" = 'no_analysis_done_on_icd_chap_o_control',
                          "tjur_r2.Tjur's R2" = 'no_analysis_done_on_icd_chap_o_control',
                          "mcfad_r2.McFadden's R2" = 'no_analysis_done_on_icd_chap_o_control',
                          "adj_mcfad_r2.adjusted McFadden's R2" = 'no_analysis_done_on_icd_chap_o_control', 
                          "nag_r2.Nagelkerke's R2" = 'no_analysis_done_on_icd_chap_o_control', 
                          "cox_r2.Cox & Snell's R2" = 'no_analysis_done_on_icd_chap_o_control',
                          "cov_ps" = 'no_analysis_done_on_icd_chap_o_control',
                          "sig_cov" = 'no_analysis_done_on_icd_chap_o_control',
                          "cov_adj" = 'no_analysis_done_on_icd_chap_o_control',
                          "cov_or" = 'no_analysis_done_on_icd_chap_o_control',
                          "case_age" = 'no_analysis_done_on_icd_chap_o_control', 
                          "con_age" = 'no_analysis_done_on_icd_chap_o_control',
                          "case_titer" = 'no_analysis_done_on_icd_chap_o_control', 
                          "con_titer" = 'no_analysis_done_on_icd_chap_o_control',
                          "case_titer_std" = 'no_analysis_done_on_icd_chap_o_control', 
                          "con_titer_std" = 'no_analysis_done_on_icd_chap_o_control',
                          "case_titer_med" = 'no_analysis_done_on_icd_chap_o_control', 
                          "con_titer_med" = 'no_analysis_done_on_icd_chap_o_control', 
                          "glm_warn_msg" = 'no_analysis_done_on_icd_chap_o_control', 
                          "glm_warn_bool" = 'no_analysis_done_on_icd_chap_o_control', 
                          "proc_time.elapsed" = 'no_analysis_done_on_icd_chap_o_control', 
                          "date_time" = 'no_analysis_done_on_icd_chap_o_control')
              
          ret_ind_res = append(ret_ind_res, c("control_set" = control_str))
          ret_ind_res = append(ret_ind_res, c("n_mixed" = mixed_cnt))
          
          
    } else {
      # Use the function ind_anti_analysis to create a logistic regression model
      # for the given disease and antibody.
      # is_warning, the first parameter to ind_anti_analysis refers to whether or 
      # not we have a glm_warning in the logistic regression model for a disease
      # antibody pair, but since this is our initial model, we set it to false.
      ret_ind_res =  step_ind_anti_analysis(y, mod_df, case_inds,
                                            control_inds, is_sex_spec, dis_sex,
                                            dis_covs, ant_cnt)  
      ret_ind_res = append(ret_ind_res, c("control_set" = control_str))
      ret_ind_res = append(ret_ind_res, c("n_mixed" = mixed_cnt))
      ret_ind_res = append(ret_ind_res, c("perm_n" = -1))
      
      
    }
    

    
    # Push the disease information list onto the front of our returned disease
    # antibody pair result list, ret_ind_res.
    ret_ind_res = append(dis_info, ret_ind_res)
    
    
    # Rearrange some columns
    ind_res_cols = c("unparsed_name", "disease_name", "icd_cat",  "icd_loc",
                     "dis_sex", 
                     "num_case", "num_con", 'control_set', 'n_mixed',
                     "antigen", "org", 
                     "p_val", "OR", "CI",  
                     "model", 
                     "tjur_r2.Tjur's R2", "mcfad_r2.McFadden's R2", 
                     "adj_mcfad_r2.adjusted McFadden's R2", 
                     "nag_r2.Nagelkerke's R2", 
                     "cox_r2.Cox & Snell's R2", 
                     "cov_ps", "sig_cov", "cov_adj",  "cov_or", 
                     "case_age", "con_age", 
                     "case_titer", "con_titer", 
                     "case_titer_std", "con_titer_std",  
                     "case_titer_med", "con_titer_med", 
                     "glm_warn_msg", "glm_warn_bool",                      
                     "proc_time.elapsed", "date_time", 'perm_n')
    
    ret_ind_res = ret_ind_res[ind_res_cols]         
  
    
    # Put the list containing all results for this disease-antibody pair into 
    # the larger matrix that contains results for this particular disease 
    # with all antibodies.
    dis_res[(nrow(dis_res) + 1), ] = ret_ind_res

    
    # Update our antibody counter for progress messages to user.
    ant_cnt = ant_cnt + 1
    
  }
  
  # Finished initial antibody loop ####
  # We have finished creating models for all antibodies paired to this disease

  # We finished all modeling for this disease (finished all 45 antibodies), so
  # now take dis_res and return it to whoever called this function.
  return(dis_res)
}

# step_ind_anti_analysis function. ####
# This function takes the name of an antibody along with a dataframe (mod_df)
# that has been prepared for a particular disease and has covariate data 
# included and generated a logistic regression model for this pair using a 
# step-wise backwards elimination procedure.
#
# Input:
#   y [string]: antibody name without "_init" on end of name
#   mod_df [dataframe]: df containing disease status and covariate columns
#   case_inds [list]: List of patient IDs who are considered cases
#   control_inds [list]: List of patient IDs who are considered controls
#   is_sex_spec [bool]: Boolean indicating whether this disease is sex-specific
#   dis_sex [int]: Integer code indicating if the disease is female-specific (0)
#                  male-specific (1), or not sex-specific (-1)
#   dis_covs [string]: String containing all covariates significantly associated
#                       with current disease.
#   ant_cnt [int]: count of which antibody this is (used for progress output)
#
# Output:
#   list [length(29)] :
#         [1] nCase [int]: Number of cases of this disease, 
#         [2] nControl [int]: Number of controls for this disease
#         [3] anti [string]: Antibody for which this disease was modeled for 
#                            association.
#         [4] organism [string]: Organism abbreviation that produced the antigen
#         [5] log_reg_p [float]: P-val of association between antibody level,
#                                 and disease status - from logistic regression.
#         [6] anti_or_str [string]: Odds ratio for this association
#         [7] anti_ci_str [string]: 95% confidence intervals for this OR
#         [8] log_reg_mod [string]: Logistic regression model formula with 
#                                   weights.
#         [9] tjur [float]: Tjur's R2 or coefficient of determination.
#         [10] mcfad [float]: Unadjusted McFadden's R2
#         [11] adj_mcfad [float]: Adjusted McFadden's R2
#         [12] nag [float]: Nagelkerke's R2
#         [13] cox [float]: Cox & Snell's R2
#         [14] log_reg_cov_ps [string]: p-values for each covariate included in 
#                                       the logistic regression model
#         [15] sig_covs [string]: String listing all covariates included in 
#                                 fully adjusted model
#         [16] cov_adj  [string]: String listing just the covariates left after
#                                 backward elimination and thus adjusted for in
#                                 actual model.
#         [17] other_ci_str [string]: String containing ORs and CIs for all 
#                                     covars that logistic regression model was 
#                                     adjusted for
#         [18] avg_age_case [float]: Average age of all cases
#         [19] avg_age_con [float]: Average age of all controls
#         [20] avg_titer_case [float]: Average titer level for cases
#         [21] avg_titer_con [float]: Average titer level for controls
#         [22] std_titer_case [float]: Standard deviation titer level for cases
#         [23] std_titer_case [float]: Standard deviation titer level for 
#                                      controls
#         [24] med_titer_case [float]: Median titer level for cases
#         [25] med_titer_case [float]: Median titer level for cases
#         [26] glm_warn [string]: Text from any glm or CI warnings
#         [27] is_warning [bool]: whether a glm warning was thrown for model
#         [28] tot_time [string]: Amount of time the CPU took to process this pair
#         [29] date_time [string]: Date and time pair analysis was completed.
#
#
#
step_ind_anti_analysis <- function(y, mod_df, 
                                   case_inds, control_inds, 
                                   is_sex_spec, dis_sex, dis_covs, ant_cnt)
{
  # We will measure processing time for this script using proc.time but will
  # also log when this analysis was run using Sys.time
  start_time = proc.time()
  date_time = as.character(Sys.time())
  
  # Get the antibody titer (Log10 transformed already) data for our current
  # antibody and push the row.names into the dataframe as the column "id"
  # for use in filtering below.
  curr_ant = ant_dat[y]
  curr_ant$id = row.names(curr_ant)
  
  # Limit our antigen data to only those patients that we have disease info
  # on.  First put all the IDs into a single list and then filter antibody
  # data, keeping only data for those people in all_inds, and finally remove
  # the "id" column created for this filtering.
  all_inds = append(case_inds, control_inds)
  curr_ant = curr_ant[curr_ant$id %in% all_inds,]
  curr_ant$id <- NULL
  
  # Add our antigen data onto our dataframe for modeling, mod_df, that already
  # contains the disease status data and the covariate data. Push this into
  # new variable called dat_df and remove extraneous Row.names column.
  dat_df = merge(curr_ant, mod_df, by = 0, all = TRUE, sort = FALSE)
  row.names(dat_df) = dat_df$Row.names
  dat_df$Row.names = NULL
  
  # Set up our antibody column name so we can refer to it programmatically.
  # Just switching the actual antibody name, "1gG antigen for Herpes Simplex 
  # virus-1_init" to "mod_ant" so we can more easily reference it in our code.  
  dat_df_names = names(dat_df)
  dat_df_names[1] = "mod_ant"
  names(dat_df) = dat_df_names
  
  
  # When merging the curr_ant for CagA for H Pylori, which has NAs for a bunch
  # of samples (known issue in source data), with our model data (mod_df) we
  # will end up with rows with NAs because we have the disease status but we 
  # have no antibody titer data for a patient.  We don't want these in the 
  # model so we remove them here.     
  dat_df = dat_df[!is.na(dat_df$mod_ant),]
  
  # Update case and control dataframes after previous step removing NA rows.
  case = na.omit(dat_df[case_inds , ])
  control = na.omit(dat_df[control_inds , ])
  
  # Update dat_df in global scope.
  dat_df <<- dat_df
  
  
  # Collect meta data #####
  # Get friendlier version of antibody name
  # "1gG antigen for Herpes Simplex virus-1" becomes
  #     "IgG"
  anti = ant_dict[ant_dict['Antigen'] == y,'Clean Ant Name']
  
  # Look up abbreviation for the organism the antigen is produced by in our
  # antigen dictionary.
  # Example: anti = "1gG antigen for Herpes Simplex virus-1", then 
  #             org = "HSV1"
  org = ant_dict[(grep(y, ant_dict$Antigen)),'Abbrev'][[1]]
  
  # Print out our progress
  # Example:
  #   ╚═ HSV1 IgG [4/45]
  cat(paste("   \U255A\U2550 ",org, " ", anti,
            " [", ant_cnt, "/", ncol(ant_dat),"]\n", sep = ''))

  # Calculate summary stats for cases and controls
  # Age - multiply by 10 to re-scale back to normal
  avg_age_case = round(mean((case[,'age']) * 10),2)
  avg_age_con = round(mean((control[,'age']) * 10),2)
  
  # Number of cases and controls    
  nCase = nrow(case)
  nControl = nrow(control)
  
  # Collect titer summary statistics - I'm not re-scaling these but if you 
  # wanted to do this you would just do 10^(case[,'mod_ant'])
  avg_titer_case = round(mean(case[,'mod_ant']),2)
  avg_titer_con  = round(mean(control[,'mod_ant']),2)
  std_titer_case = round(sd(case[,'mod_ant']),2)
  std_titer_con  = round(sd(control[,'mod_ant']),2)
  med_titer_case = round(median(case[,'mod_ant']),2)
  med_titer_con  = round(median(control[,'mod_ant']),2)
  
  # Confounder determination ####
  # Get the list of covariates with significant association with disease
  # status, as calculated by calc_dis_assoc() and get the list of those with
  # significant association with antibody titer as calculated by 
  # calc_ant_assoc(), and put together a final list of possible confounders
  # we should adjust our model for.
  # If a covariate is significantly associated with both the antibody level 
  # and the disease status then we are calling this a possible confounder 
  # and are adjusting our model for it.  
  # To get the list of covariates significantly associated with an antibody
  # we will use our lookup table produced earlier, ant_cov_assoc, the row in
  # which depends on the current antibody name and the sex-specific nature of
  # this disease.
  if (is_sex_spec)
  {
    # Female specific disease
    if (dis_sex == 0)
    {
      ant_covs = unlist(ant_cov_assoc[(ant_cov_assoc$antigen == y) &
                                        (ant_cov_assoc$sex == "female"), 
                                      'sig_covs'])
    } else
    {
      # For a disease to be is_sex_spec == TRUE and not dis_sex == 0, it has
      # to be a male-specific disease
      ant_covs = unlist(ant_cov_assoc[(ant_cov_assoc$antigen == y) &
                                        (ant_cov_assoc$sex == "male"), 
                                      'sig_covs'])
    }
  } else
  {
    # Not a sex-specific disease
    ant_covs = unlist(ant_cov_assoc[(ant_cov_assoc$antigen == y) &
                                      (ant_cov_assoc$sex == "both"), 
                                    'sig_covs'])
  }
  
  # Determine possible confounders by intersecting antibody covariates and 
  # disease covariate lists.
  covs = intersect(ant_covs, dis_covs)
  sig_covs = covs
  
  # Statistical Analysis #####
  # We are using a logistic regression model to calculate association between
  # antigen level and disease status.  We will also adjust for any possible 
  # confounders.

  
  # If this is a sex-specific disease, meaning only 1 sex is represented in the
  # data we have to drop the sex covariate as this would lead to a no contrasts
  # error.
  if (is_sex_spec)
  {
    covs = covs[covs != 'sex']
  }
  
  # We are building our actual glm model formula [log_form] inserting our
  # possible confounders as needed.
  if (length(covs) == 0)
  {
    log_form = as.formula(paste("mod_dis ~ mod_ant", sep = ''))
  } else
  {
    # Example: log_form: mod_dis ~ mod_ant + bmi + age
    log_form = as.formula(paste("mod_dis ~ mod_ant +  ", 
                                paste(covs, collapse = ' + '), sep = ''))
  }
  
  
  # StepAIC requires starting with a model, so we will use the fully adjusted
  # model that includes all confounders
  log_reg_res = suppressMessages(myTryCatch(
    glm(log_form, data = dat_df, family = binomial)))
  
  log_reg = log_reg_res$value

  # Only run step-wise method if we actually have covariates to consider.
  if (length(covs) > 0)
  {

    # Do the backwards elimination     
    step = stepAIC(log_reg, direction = "backward", trace = FALSE,
                   scope = list(lower = mod_dis ~ mod_ant, upper = log_form))
    

    # Extract our selected formula from stepAIC to use for modeling.
    log_form = step$formula
    
    # Extract what covs we are adjusting for from this log_form
    # Drop 'mod_dis ~ mod_ant + ' from log_form
    # This code will not work and is not needed anyways if we have just a 
    # univariate model
    cov_form = paste(deparse(log_form), collapse = '')
    cov_form = gsub("mod_dis ~ mod_ant", "", cov_form)
    
    # If we actually have covs in step form
    if (cov_form != "")
    {
      cov_arr = unlist(str_split(cov_form, "\\+"))
      cov_arr = sapply(cov_arr, killws)
      cov_arr = cov_arr[cov_arr != ""]
      names(cov_arr) <- NULL
      
      covs = cov_arr
    } else
    {
      covs = list()
    }

    
    # Re-run regression and collect results! Needed to actually catch any
    # warnings from this specific stepAIC optimized model.
    # using myTryCatch which is an awesome way to run code and catch any 
    # warnings and errors
    log_reg_res = suppressMessages(myTryCatch(
      glm(log_form, data = dat_df, family = binomial)))
    
    # extracting the actual logistic regression model from the myTryCatch 
    # results
    log_reg = log_reg_res$value
      
  }
  
  # Collect regression results ####
  
  # initialize glm warning msg to empty string. This str will carry any 
  # warning that pops up when running glm model, usually something about 
  # perfect separation, which will force us to re-run this model without 
  # considering covariates.
  glm_warn = ""
  
  
  # Determine if the glm threw a warning and handle it accordingly.
  # is_warning will appear in the results to let us know if the glm threw a 
  # warning.
  is_warning = FALSE
  
  # If warning is not null we have a warning and we need to handle it.
  if (!is.null(log_reg_res$warning))
  {
    # Dump the warning message into our glm warn status str
    glm_warn = paste(glm_warn, "log_reg_warn: ", log_reg_res$warning, 
                     sep = "")
    
    is_warning = TRUE
    
    # The warning message comes from glm with a trailing new line, we strip 
    # that off here otherwise it causes issues when printing our results out.
    glm_warn = gsub("[\r\n]", "", glm_warn)
  }
  
  
  # Extract the p-value of association between antigen level and disease 
  # status
  log_reg_p = coef(summary(log_reg))[2,4]
  
  # Get the p-values of association for any covariates included in the model
  log_reg_cov_ps =  tail(coef(summary(log_reg))[,4], -2)
  
  # Create a string that shows the model with weightings, for example:
  # "dis_status ~  -4.8682  +  (0.1172 * mod_ant) + (0.0492 * bmi)"
  log_reg_mod = extract_lin_form(log_reg)
  
  
  # Goodness of fit metrics ####
  # McFadden's pseudo R2, unadjusted and adjusted - McFadden, D. (1987)
  mcfad_res = r2_mcfadden(log_reg)
  mcfad     = mcfad_res$R2
  adj_mcfad = mcfad_res$R2_adjusted
  
  # Nagelkerke's pseudo-R2 - Nagelkerke, N. J. (1991)
  nag = r2_nagelkerke(log_reg)
  
  # Tjur's R2 or coefficient of determination - Tjur, T. (2009)
  tjur = r2_tjur(log_reg)
  
  # Cox and Snell's pseudo-R2 - Cox & Snell (1989)
  cox  = r2_coxsnell(log_reg)
  
  # Get pretty ORs and CIs ####
  or_ci_dat = calc_or_ci(log_reg)
  ant_or_str  = or_ci_dat$ant_or
  ant_ci_str  = or_ci_dat$ant_ci
  other_ci_str = or_ci_dat$other_ci
  ci_warn = gsub("[\r\n]", "", or_ci_dat$warn)
  
  # Put together data and return it ####
  # R float has limit just slightly smaller than 2.22e-308
  # So if the p-value is 0 (it overflowed R float) we need to manually
  # set to smallest number we can (2.22E-308)
  if (log_reg_p == 0)
  {
    log_reg_p = 2.22e-300
  }
  
  # Calculate total processing time for this disease-antibody pair modeling.
  tot_time = proc.time() - start_time
  
  # throw all results and data into list and return to caller.
  ind_res = c("num_case" = nCase, "num_con" = nControl,
              "antigen" = anti, "org" = org, 
              "p_val" = log_reg_p, "OR" = ant_or_str, 
              "CI" = ant_ci_str,  "model" = log_reg_mod,
              "tjur_r2" = tjur, "mcfad_r2" = mcfad, 
              "adj_mcfad_r2" = adj_mcfad, "cox_r2" = cox, "nag_r2" = nag,
              "cov_ps" = named_list_to_str(log_reg_cov_ps),
              "sig_cov" = paste(sig_covs, collapse = ", "),
              "cov_adj" = paste(covs, collapse = ", "),
              "cov_or" = other_ci_str,
              "case_age" = avg_age_case, "con_age" = avg_age_con,
              "case_titer" = avg_titer_case, "con_titer" = avg_titer_con,
              "case_titer_std" = std_titer_case, 
              "con_titer_std" = std_titer_con,
              "case_titer_med" = med_titer_case, 
              "con_titer_med" = med_titer_con, 
              "glm_warn_msg" = glm_warn, 
              "glm_warn_bool" = is_warning, 
              "proc_time" = tot_time['elapsed'], 
              "date_time" = date_time)
  
  return (ind_res)
}




# perm_analysis function. ####
# Special version of analysis function used in ukb_titer_analysis.R
# This function takes the name of a disease (unparsed), and
# a list of
# all antibodies (by name) that the user wants to generate and generates all 
# logistic regression models for this disease and all 45 different antibodies
#
# Requirements:
#   perm_analysis function
#
# Input:
#   dis_name [string]: unparsed disease, "other salmonella infections[A02]"
#   curr_res_fn [string]: Path where we should write our permutation results
#   ant_list [list]  : list of antibodies to run analysis on - if you want full
#                      analysis just send names(ant_dat)
#   is_sex_spec [bool]: Flag indicating if disease is sex-specific
#
#   control_str [string]: The set of controls that should be used, can be 'all',
#                         'Female', 'Male', or 'O80,O81,O82,O83,O84' used 
#                         specifically for ICD10 O codes.
#   do_good_fit_checks [bool]: Flag on whether we should skip all the goodness
#                              of fit checks as they represent a significant
#                              amount of processing time. [Default: True]
#   DEBUG    [bool]: Boolean indicator if certain debug info should be printed.
# Output:
#   dataframe [1+ x 35] :
#         $Unparsed_Disease [string]: Unparsed disease name, input 'dis_name'
#         $Disease [string]: Disease name, "other salmonella infections"
#         $ICD10_Cat [string]: ICD chapter, "A"
#         $ICD10_Site [string]: ICD site code, "02"
#         $sex_specific_dis [bool]: Whether this is a sex-specific disease, F
#         $nCase [int]: Number of cases of this disease, 
#         $nControl [int]: Number of controls for this disease
#         $Antigen [string]: Antibody for which this disease was modeled for 
#                            association.
#         $organism [string]: Organism abbreviation that produced the antigen
#         $log_reg_p_val [float]: P-val of association between antibody level,
#                                 and disease status - from logistic regression.
#         $anti_or [string]: Odds ratio for this association
#         $anti_CI [string]: 95% confidence intervals for this OR
#         $log_reg_mod [string]: Logistic regression model formula with weights.
#         $r2_tjur [float]: Tjur's R2 or coefficient of determination.
#         $r2_mcfad [float]: Unadjusted McFadden's R2
#         $r2_adj_mcfad [float]: Adjusted McFadden's R2
#         $r2_coxsnell [float]: Cox & Snell's R2
#         $r2_nagelkerke [float]: Nagelkerke's R2
#         $log_reg_cov_ps [string]: p-values for each covariate included in the
#                                   logistic regression model
#         $cov_adj_for [string]: String listing all covariates included in model
#         $cov_adj_ors [string]: String containing ORs and CIs for all covars
#                                that logistic regression model was adjusted for
#         $avg_age_case [float]: Average age of all cases
#         $avg_age_con [float]: Average age of all controls
#         $avg_titer_case [float]: Average titer level for cases
#         $avg_titer_con [float]: Average titer level for controls
#         $std_titer_case [float]: Standard deviation titer level for cases
#         $std_titer_case [float]: Standard deviation titer level for controls
#         $med_titer_case [float]: Median titer level for cases
#         $med_titer_case [float]: Median titer level for cases
#         $Warnings [string]: Text from any glm or CI warnings
#         $is_warning [bool]: whether a glm warning was thrown for model
#         $vanilla_pair [bool]: Whether this pair was being run in vanilla mode
#                               after an initial glm warning
#         $vanilla_dis [bool]: Whether this pair was being run in vanilla mode
#                               due to disease surpassing VANILLA_LIMIT 
#         $proc_time [string]: Amount of time the CPU took to process this pair
#         $date_time [string]: Date and time pair analysis was completed.
#
# Test:
#   val = perm_analysis("other salmonella infections[A02]", 1, names(ant_dat),
#                       FALSE, 'all', TRUE, TRUE)
#   
perm_analysis <- function(dis_name, curr_res_fn, 
                          ant_list, 
                          is_sex_spec, control_str = 'all',
                          do_good_fit_checks = TRUE,
                          DEBUG = TRUE)
{

  
  # Create empty matrix to hold our associations for this disease 1 row for 
  # each of the antibodies we are testing [45]
  # This is a per-disease form of the res dataframe created earlier.
  curr_dis_res =  matrix(nrow = 0, ncol = 37)
  colnames(curr_dis_res) = result_cols
  
  # Get the disease status data for the current disease we are looking at.
  curr_dis = dis_w_10[dis_name]
  

  mixed_cnt = 0
  
  # Get patient IDs for people that are cases and controls for this disease
  orig_case_inds = rownames(which(curr_dis == TRUE, arr.ind = TRUE))
  orig_control_inds = rownames(which(curr_dis == FALSE, arr.ind = TRUE))
  
  # Set O con boolean to let us know if we are using ICD10 O control codes as
  # our control set or if we are just using either the sex-specific or all 
  # controls for disease.
  if (control_str == "O80,O81,O82,O83,O84"){
    o_con_bool = TRUE
  } else {
    o_con_bool = FALSE
  }
  
  # If this is an ICD10 chap O disease consider controls
  if ((icd_cat == 'O') & (o_con_bool == TRUE)) {
    
    orig_control_inds = o_con_inds
    
    # Make sure someone isn't in both case_inds and control_inds!
    in_both = intersect(orig_control_inds, orig_case_inds)
    mixed_cnt = length(in_both)
    
    orig_case_inds = orig_case_inds[!(orig_case_inds %in% in_both)]
    orig_control_inds = orig_control_inds[!(orig_control_inds %in% in_both)]
    
    # Otherwise is this a sex-specific disease?
  } else
  {
    # Check if we have sex-specific disease so if we do we can limit our cases
    # and controls to specific sex required.
    if (is_sex_spec)
    {
      
      sex_inds = row.names(cov_dat[cov_dat$sex == dis_sex, ])
      
      # Limit case and control patients to only those with sex matching dis_sex
      orig_case_inds = orig_case_inds[orig_case_inds %in% sex_inds]
      orig_control_inds = orig_control_inds[orig_control_inds %in% sex_inds]
      
      control_str =  dis_sex_str
    }
  }
  

  all_inds = c(orig_case_inds, orig_control_inds)
  curr_dis$id = row.names(curr_dis)
  
  curr_dis = curr_dis[all_inds, ]
  row.names(curr_dis) = curr_dis$id
  curr_dis$id <- NULL
  
  # Moved down for O-diseases since we alter curr_dis when we have an O-disease
  # First thing to do is to shuffle the disease status
  # Get the disease status data for the current disease we are looking at.
  # Shuffle 
  curr_dis_names = names(curr_dis)
  curr_dis_names[1] = "mod_dis"
  names(curr_dis) = curr_dis_names
  
  curr_dis$id = row.names(curr_dis)
  curr_dis = transform(curr_dis, mod_dis = sample(mod_dis))
  row.names(curr_dis) = curr_dis$id
  
  
  # Reset the case and control inds now that we have shuffled
  case_inds = rownames(which(curr_dis == TRUE, arr.ind = TRUE))
  control_inds = rownames(which(curr_dis == FALSE, arr.ind = TRUE))
  
  # Prepare the dataframe that will be used for all of our modeling, mod_df.
  # In this first step we merge the disease status data and covariate data.
  mod_df = merge(curr_dis, cov_dat, by = 0, all.x = TRUE, sort = FALSE)
  row.names(mod_df) = mod_df$Row.names
  mod_df$Row.names = NULL
  

  # Adding this for O diseases but shouldn't affect non-O diseases
  mod_df = mod_df[!(is.na(mod_df$mod_dis)),]
  
  
  # Switch mod_dis from logical vector to numeric with 0 = disease False, 
  # and 1 = disease True.
  mod_df$mod_dis = ifelse(mod_df$mod_dis == FALSE, 0, 1)  
  
  # Convert all covariates to ordered factors.
  mod_df$sex = as.factor(mod_df$sex)
  mod_df$ethnic = as.factor(mod_df$ethnic)
  mod_df$tdi_quant = as.factor(mod_df$tdi_quant)
  mod_df$num_in_house = as.factor(mod_df$num_in_house)
  mod_df$tobac = as.factor(mod_df$tobac)
  mod_df$alc = as.factor(mod_df$alc)
  mod_df$num_sex_part = as.factor(mod_df$num_sex_part)  
  mod_df$same_sex = as.factor(mod_df$same_sex)  
  
  
  # Create case and control specific dataframes, drop any subjects with any
  # NAs.  Right here na.omit should not affect anyone, if the data was cleaned
  # properly.
  case = na.omit(mod_df[case_inds , ])
  control = na.omit(mod_df[control_inds , ])
  
  
  # Debug message
  if (DEBUG == TRUE){
    cat(paste("is_sex_spec: ", is_sex_spec, " | is_o_dis: ", (icd_cat == 'O'),
              " | control string: ", control_str,
              "\nnCase: ", length(case_inds), " | nCon: ", length(control_inds),
              " | nAll: ", length(all_inds), 
              "\nnCase_mod: ", nrow(mod_df[mod_df$mod_dis == 1, ]), 
              " | nCon_mod: ", nrow(mod_df[mod_df$mod_dis == 0, ]),
              " | nrow(mod): ", nrow(mod_df), "\n"
              
    ))
  }
  
  

  # Current disease status message
  # ╠═ other salmonella infections[A02] [1/558]
  cat(paste("\U2560\U2550 ",curr_dis_name, 
            " [Perm ", curr_permute_num, " of ", N_PERMUTE,"]\n", sep = ''))
  
  

  # Start testing antibody titers ####
  # Here we finally start looping through all the different antibodies in 
  # ant_list and do the modeling for association between our current 
  # shuffled disease statuses and each antibody.
  
  # Initialize a counter to update user on progress for each of 45 antibodies.
  ant_cnt = 1
  
  # Generate a list containing disease info that will be bound to each pair's
  # result list (used below).
  dis_info = c("Unparsed_Disease" = curr_dis_name, 
               "Disease" = dis, 
               "ICD10_Cat" = icd_cat,
               "ICD10_Site" = icd_loc,
               "sex_specific_dis" = dis_sex_str)
  
  for (y in ant_list)
  {
    
    # Need to put "_init" back on end of antibody name for downstream analysis.
    #fixed_anti = paste(y, "_init", sep = "")
    
    ret_ind_res  =  perm_ind_anti_analysis(
                                            y                  = y,
                                            mod_df             = mod_df,
                                            case_inds          = case_inds, 
                                            control_inds       = control_inds,
                                            is_sex_spec        = is_sex_spec, 
                                            dis_sex            = dis_sex,
                                            ant_cnt            = ant_cnt, 
                                            tot_ants           = length(ant_list),
                                            do_good_fit_checks = FALSE)
      

    # Push the disease information list onto the front of our returned disease
    # antibody pair result list, ret_ind_res.
    ret_ind_res = append(dis_info, ret_ind_res)
    
    ret_ind_res = append(ret_ind_res, list("control_set" = control_str,
                                           "n_mixed" = mixed_cnt,
                                           "perm_n" = curr_permute_num
    ))
    
    ret_ind_res = as.data.frame(ret_ind_res)
    
    # For empirical p-value calculation we are ignoring glm warnings
    # Put the list containing all results for this disease-antibody pair into 
    # the larger matrix that contains results for this particular disease 
    # with all antibodies.
    curr_dis_res = rbind(curr_dis_res, ret_ind_res)
    
    # Update our antibody counter for progress messages to user.
    ant_cnt = ant_cnt + 1
    
  }
  
  # Rearrange some the columns
  curr_dis_res = curr_dis_res[, result_cols]
  
  # Take the returned disease results and write them out to our log file.
  write.table(curr_dis_res, curr_res_fn, sep = "\t", 
              col.names = F, row.names = FALSE,
              append = T, quote = F)
  
  curr_permute_num = curr_permute_num + 1
  

  
  # Finished antibody loop ####
  
  # We finished all modeling for this disease (finished all 45 antibodies), so
  # now take curr_dis_res, the matrix where we have been collecting results, and 
  # turn it into a dataframe and return it to whoever called this function.
  
  # Convert curr_dis_res to dataframe, give it proper colnames
  dis_res_df = as.data.frame(curr_dis_res)
  colnames(dis_res_df) = result_cols
  
  return(dis_res_df)
  
}


# perm_ind_anti_analysis function. ####
# This function takes the name of an antibody along with a dataframe (mod_df)
# that has been prepared for a particular disease and has covariate data 
# included and generated a logistic regression model for this pair, while
# adjusting for any confounding covariates, unless do_vanilla flag is set to 
# TRUE, at which point it will generate a model for just disease ~ antibody 
# titer.
#
# Input:
#   y [string]: antibody name with "_init" on end of name
#   mod_df [dataframe]: df containing disease status and covariate columns
#   case_inds [list]: List of patient IDs who are considered cases
#   control_inds [list]: List of patient IDs who are considered controls
#   is_sex_spec [bool]: Boolean indicating whether this disease is sex-specific
#   dis_sex [int]: Integer code indicating if disease is female-specific (0)
#                  male-specific (1) or not sex-specific (-1)
#   ant_cnt [int]: count of which antibody this is (used for progress output)
#   tot_ants [int]: total number of antibodies we are analyzing (used for 
#                   progress output)
#   do_good_fit_checks [bool]: Flag on whether we should skip all the goodness
#                              of fit checks as they represent a significant
#
# Output:
#   list [length(29)] :
#         [1] nCase [int]: Number of cases of this disease, 
#         [2] nControl [int]: Number of controls for this disease
#         [3] anti [string]: Antibody for which this disease was modeled for 
#                            association.
#         [4] organism [string]: Organism abbreviation that produced the antigen
#         [5] log_reg_p [float]: P-val of association between antibody level,
#                                 and disease status - from logistic regression.
#         [6] anti_or_str [string]: Odds ratio for this association
#         [7] anti_ci_str [string]: 95% confidence intervals for this OR
#         [8] log_reg_mod [string]: Logistic regression model formula with 
#                                   weights.
#         [9] tjur [float]: Tjur's R2 or coefficient of determination.
#         [10] mcfad [float]: Unadjusted McFadden's R2
#         [11] adj_mcfad [float]: Adjusted McFadden's R2
#         [12] nag [float]: Nagelkerke's R2
#         [13] cox [float]: Cox & Snell's R2
#         [14] log_reg_cov_ps [string]: p-values for each covariate included in 
#                                       the logistic regression model
#         [15] covs [string]: String listing all covariates included in model
#         [16] other_ci_str [string]: String containing ORs and CIs for all 
#                                     covars that logistic regression model was 
#                                     adjusted for
#         [17] avg_age_case [float]: Average age of all cases
#         [18] avg_age_con [float]: Average age of all controls
#         [19] avg_titer_case [float]: Average titer level for cases
#         [20] avg_titer_con [float]: Average titer level for controls
#         [21] std_titer_case [float]: Standard deviation titer level for cases
#         [22] std_titer_case [float]: Standard deviation titer level for 
#                                      controls
#         [23] med_titer_case [float]: Median titer level for cases
#         [24] med_titer_case [float]: Median titer level for cases
#         [25] glm_warn [string]: Text from any glm or CI warnings
#         [26] is_warning [bool]: whether a glm warning was thrown for model
#         [27] do_vanilla [bool]: Whether this pair was being run in vanilla mode
#                               after an initial glm warning
#         [28] tot_time [string]: Amount of time the CPU took to process this pair
#         [29] date_time [string]: Date and time pair analysis was completed.
#
#
#
perm_ind_anti_analysis <- function(y, mod_df, case_inds, control_inds,
                                       is_sex_spec, dis_sex,
                                       ant_cnt, tot_ants, 
                                       do_good_fit_checks = TRUE)
{
  # We will measure processing time for this script using proc.time but will
  # also log when this analysis was run using Sys.time
  start_time = proc.time()
  date_time = as.character(Sys.time())
  
  # Get the antibody titer (Log10 transformed already) data for our current
  # antibody and push the row.names into the dataframe as the column "id"
  # for use in filtering below.
  curr_ant = ant_dat[y]
  curr_ant$id = row.names(curr_ant)
  
  # Limit our antigen data to only those patients that we have disease info
  # on.  First put all the IDs into a single list and then filter antibody
  # data, keeping only data for those people in all_inds, and finally remove
  # the "id" column created for this filtering.
  all_inds = append(case_inds, control_inds)
  curr_ant = curr_ant[curr_ant$id %in% all_inds,]
  curr_ant$id <- NULL
  
  # Add our antigen data onto our dataframe for modeling, mod_df, that already
  # contains the disease status data and the covariate data. Push this into
  # new variable called dat_df and remove extraneous Row.names column.
  dat_df = merge(curr_ant, mod_df, by = 0, all = TRUE, sort = FALSE)
  row.names(dat_df) = dat_df$Row.names
  dat_df$Row.names = NULL
  
  # Set up our antibody column name so we can refer to it programmatically.
  # Just switching the actual antibody name, "1gG antigen for Herpes Simplex 
  # virus-1_init" to "mod_ant" so we can more easily reference it in our code. 
  dat_df_names = names(dat_df)
  dat_df_names[1] = "mod_ant"
  names(dat_df) = dat_df_names
  
  # Convert mod_dis to factor instead of just logical
  dat_df$mod_dis <- as.factor(dat_df$mod_dis)
  
  # When merging the curr_ant for CagA for H Pylori, which has NAs for a bunch
  # of samples (known issue in source data), with our model data (mod_df) we
  # will end up with rows with NAs because we have the disease status but we 
  # have no antibody titer data for a patient.  We don't want these in the 
  # model so we remove them here.       
  dat_df = dat_df[!is.na(dat_df$mod_ant),]
  
  # Update case and control dataframes after previous step removing NA rows.
  case = na.omit(dat_df[case_inds , ])
  control = na.omit(dat_df[control_inds , ])
  
  # Update dat_df in global scope.
  dat_df <<- dat_df
  
  
  # Collect meta data #####
  # Get friendlier version of antibody name, by removing "_init" from end.
  # "1gG antigen for Herpes Simplex virus-1_init" becomes
  #     "1gG antigen for Herpes Simplex virus-1"
  anti = str_remove(y, "_init")
  
  clean_ant_name = ant_dict[(grep(anti, ant_dict$Antigen)),'Clean Ant Name'][[1]]
  
  # Look up abbreviation for the organism the antigen is produced by in our
  # antigen dictionary.
  # Example: anti = "1gG antigen for Herpes Simplex virus-1", then 
  #             org = "HSV1"
  org = ant_dict[(grep(anti, ant_dict$Antigen)),'Abbrev'][[1]]
  
  # Print out our progress
  # Example:
  #   ╚═ 1gG antigen for Herpes Simplex virus-1 [4/45]
  cat(paste("   \U255A\U2550 ",org, " ", clean_ant_name,
            " [", ant_cnt, "/", tot_ants,"]\n", sep = ''))

  
  # Calculate summary stats for cases and controls
  # Age - multiply by 10 to re-scale back to normal
  avg_age_case = round(mean((case[,'age']) * 10),2)
  avg_age_con = round(mean((control[,'age']) * 10),2)
  
  # Number of cases and controls    
  nCase = nrow(case)
  nControl = nrow(control)
  
  # Collect titer summary statistics - I'm not re-scaling these but if you 
  # wanted to do this you would just do 10^(case[,'mod_ant'])
  avg_titer_case = round(mean(case[,'mod_ant']),2)
  avg_titer_con  = round(mean(control[,'mod_ant']),2)
  std_titer_case = round(sd(case[,'mod_ant']),2)
  std_titer_con  = round(sd(control[,'mod_ant']),2)
  med_titer_case = round(median(case[,'mod_ant']),2)
  med_titer_con  = round(median(control[,'mod_ant']),2)
  
  
  # Get covs we need to adjust for ####
  # sig_covs: Covariates significantly associated with both disease and 
  #           antibodies
  # cov_adj_for: Actual covariates we modeled (this might be different
  #              than sig_covs because some sig_covs will be removed during 
  #              backwards elimination)
  
  cov_str = dis_prev_res[((dis_prev_res$Unparsed_Disease == curr_dis_name) &
                        (dis_prev_res$organism == org) &
                        (dis_prev_res$Antigen == clean_ant_name)), 
                        'cov_adj_for']
  
  # Happens for tier 1 with HIV Abs - we don't actually have a results 
  # entry, so just do univariate perms
  if (rlang::is_empty(cov_str)){
    covs = list()
    
  } else {
    if (cov_str != "")
    {
      cov_arr = unlist(str_split(cov_str, ","))
      cov_arr = sapply(cov_arr, killws)
      cov_arr = cov_arr[cov_arr != ""]
      names(cov_arr) <- NULL
      
      covs = cov_arr
    } else
    {
      covs = list()
    }
  }
  

  sig_cov_str = dis_prev_res[((dis_prev_res$Unparsed_Disease == curr_dis_name) &
                         (dis_prev_res$organism == org) &
                         (dis_prev_res$Antigen == clean_ant_name)), 
                         'sig_covs']


  if (rlang::is_empty(sig_cov_str)){
    sig_covs = list()
    
  } else {  
    if (sig_cov_str != "")
    {
      sig_cov_arr = unlist(str_split(sig_cov_str, ","))
      sig_cov_arr = sapply(sig_cov_arr, killws)
      sig_cov_arr = sig_cov_arr[sig_cov_arr != ""]
      names(sig_cov_arr) <- NULL
      
      sig_covs = sig_cov_arr
    } else
    {
      sig_covs = list()
    } 
  }
  
  # If this is a sex-specific disease, meaning only 1 sex is represented in the
  # data we have to drop the sex covariate as this would lead to a no contrasts
  # error.
  if (is_sex_spec)
  {
    covs = covs[covs != 'sex']
  }
  
  #  Statistical Analysis #####
  # We are using a logistic regression model to calculate association between
  # antibody level and disease status.  We will also adjust for any possible 
  # confounders.
  
  # We are building our actual glm model formula [log_form] inserting our
  # possible confounders as needed.
  if (length(covs) == 0)
  {
    log_form = as.formula(paste("mod_dis ~ mod_ant", sep = ''))
  } else
  {
    # Example: log_form: mod_dis ~ mod_ant + bmi + age
    log_form = as.formula(paste("mod_dis ~ mod_ant +  ", 
                                paste(covs, collapse = ' + '), sep = ''))
  }
  
  # Run regression (catch any warnings) ####
  
  # initialize glm warning msg to empty string. This str will carry any 
  # warning that pops up when running glm model, usually something about 
  # perfect separation, which will force us to re-run this model without 
  # considering covariates.
  glm_warn = ""
  
  # using myTryCatch which is an awesome way to run code and catch any 
  # warnings and errors
  log_reg_res = suppressMessages(myTryCatch(
    glm(log_form, data = dat_df, family = binomial)))
  
  # extracting the actual logistic regression model from the myTryCatch 
  # results
  log_reg = log_reg_res$value
  
  # Determine if the glm threw a warning and handle it accordingly.
  # is_warning will appear in the results to let us know if the glm threw a 
  # warning.
  is_warning = FALSE
  
  # If warning is not null we have a warning and we need to handle it.
  if (!is.null(log_reg_res$warning))
  {
    # Dump the warning message into our glm warn status str
    glm_warn = paste(glm_warn, "log_reg_warn: ", log_reg_res$warning, 
                     sep = "")
    
    is_warning = TRUE
    
    # The warning message comes from glm with a trailing new line, we strip 
    # that off here otherwise it causes issues when printing our results out.
    glm_warn = gsub("[\r\n]", "", glm_warn)
  }
  
  
  # Extract the p-value of association between antigen level and disease 
  # status
  log_reg_p = coef(summary(log_reg))[2,4]
  
  # Get the p-values of association for any covariates included in the model
  log_reg_cov_ps =  tail(coef(summary(log_reg))[,4], -2)
  
  # Create a string that shows the model with weightings, for example:
  # "dis_status ~  -4.8682  +  (0.1172 * mod_ant) + (0.0492 * bmi)"
  log_reg_mod = extract_lin_form(log_reg)
  
  
  # Goodness of fit metrics ####
  if (do_good_fit_checks == TRUE) {
    # McFadden's pseudo R2, unadjusted and adjusted - McFadden, D. (1987)
    mcfad_res = r2_mcfadden(log_reg)
    mcfad     = mcfad_res$R2
    adj_mcfad = mcfad_res$R2_adjusted
    
    # Nagelkerke's pseudo-R2 - Nagelkerke, N. J. (1991)
    nag = r2_nagelkerke(log_reg)
    
    # Tjur's R2 or coefficient of determination - Tjur, T. (2009)
    tjur = r2_tjur(log_reg)
    
    # Cox and Snell's pseudo-R2 - Cox & Snell (1989)
    cox  = r2_coxsnell(log_reg)
  } else {
    # McFadden's pseudo R2, unadjusted and adjusted - McFadden, D. (1987)
    mcfad_res = 'NAN'
    mcfad     = 'NAN'
    adj_mcfad = 'NAN'
    
    # Nagelkerke's pseudo-R2 - Nagelkerke, N. J. (1991)
    nag = 'NAN'
    
    # Tjur's R2 or coefficient of determination - Tjur, T. (2009)
    tjur = 'NAN'
    
    # Cox and Snell's pseudo-R2 - Cox & Snell (1989)
    cox  = 'NAN'
  }
  

  # Get pretty ORs and CIs ####
  or_ci_dat = calc_or_ci(log_reg)
  ant_or_str  = or_ci_dat$ant_or
  ant_ci_str  = or_ci_dat$ant_ci
  other_ci_str = or_ci_dat$other_ci
  ci_warn = gsub("[\r\n]", "", or_ci_dat$warn)
  
  # Put together data and return it ####
  # R float has limit just slightly smaller than 2.22e-308
  # So if the p-value is 0 (it overflowed R float) we need to manually
  # set to smallest number we can (2.22E-308)
  if (log_reg_p == 0)
  {
    log_reg_p = 2.22e-300
  }
  
  # Calculate total processing time for this disease-antibody pair modeling.
  tot_time = proc.time() - start_time
  
  elapsed_time = tot_time['elapsed']
  names(elapsed_time) <- NULL
  
  # throw all results and data into list and return to caller.
  
  ind_res = c("nCase" = nCase, "nControl" = nControl,
              "Antigen" = anti, "organism" = org, 
              "p_val" = log_reg_p, "anti_OR" = ant_or_str, 
              "anti_CI" = ant_ci_str,  "model" = log_reg_mod,
              "r2_tjur" = tjur, "r2_mcfad" = mcfad, 
              "r2_adj_mcfad" = adj_mcfad, "r2_nagelkerke" = nag, "r2_coxsnell" = cox,
              "cov_ps" = named_list_to_str(log_reg_cov_ps),
              "sig_covs" = paste(sig_covs, collapse = ", "),
              "cov_adj_for" = paste(covs, collapse = ", "), 
              "cov_ors" = other_ci_str,
              "avg_age_case" = avg_age_case, "avg_avg_con" = avg_age_con,
              "avg_titer_case" = avg_titer_case, "avg_titer_con" = avg_titer_con,
              "std_titer_case" = std_titer_case, 
              "std_titer_con" = std_titer_con,
              "med_titer_case" = med_titer_case, 
              "med_titer_con" = med_titer_con, 
              "Warnings" = glm_warn, 
              "is_warning" = is_warning, 
              "proc_time" = elapsed_time, 
              "date_time" = date_time)
  
  return (ind_res)
}

# run_glm function. ####
# Function to run regular logistic regression using glm
#
# Requirements:
#   extract_lin_form [function, 'helper_functions_pub.R']
#   get_small [function, 'helper_functions_pub.R']
#   myTryCatch [function, 'helper_functions_pub.R']
#   calc_or_ci [function, 'helper_functions_pub.R']
#
# Input:
#  dat_df [df]: Dataframe containing data to run model on including covariates
#  covs_to_use [list]: List of covariates to adjust model for
#  LOG [bool]: Boolean specifying if we should output messages to log file 
#              [Default: TRUE]
#  DEBUG [bool]: Boolean specifying if we should output messages to console
#              [Default: FALSE]
#  LOG_FN [str]: Path to log file that we should write messages to
#
# Output:
#  named list [length: 12] :
#    p_val [float]: P-val of association between antibody level, and disease 
#                   status - from logistic regression.
#    OR [string]: Odds ratio for this association
#    CI [string]: 95% confidence intervals for this OR
#    model [string]: Logistic regression model formula with weights.
#    cov_adj [string]: String listing all covariates included in model
#    cov_ps [string]: p-values for each covariate included in the logistic
#                     regression model
#    cov_or [string]: String containing ORs and CIs for all covars
#                     that logistic regression model was adjusted for
#    glm_warn_msg [string]: Warning message output by glm if applicable
#    glm_warn_bool [bool]: Boolean indicating if glm threw warning
#    var_types [string]: String listing type of each variable in input dat_df
#    mod_method [string]: String indicating type of model run [glm, elrm, firth]
#    note_str [string]: More detailed notes collected from model
run_glm <- function(dat_df, covs_to_use, LOG, DEBUG, LOG_FN)
{
  
  mod_method = 'glm'
  note_str = ''
  
  chk = c('mod_dis', 'mod_ant')
  chk = append(chk, covs_to_use)
  
  msg_str = "\t\tRunning GLM"
  if (LOG == TRUE) {
    write(msg_str, file = LOG_FN, append = TRUE)
  }
  
  if (DEBUG == TRUE) {
    cat(paste0(msg_str, '\n'))
  } 
  # Match UKB Statistical model #####  
  if (length(covs_to_use) == 0)
  {
    log_form = as.formula(paste("mod_dis ~ mod_ant", sep = ''))
  } else
  {
    log_form = as.formula(paste("mod_dis ~ mod_ant +  ", 
                                paste(covs_to_use, collapse = ' + '), sep = ''))
  }
  
  
  # Run regression (catch any warnings) ####
  
  # initialize glm warning msg to empty string. This str will carry any 
  # warning that pops up when running glm model, usually something about 
  # perfect separation, which will force us to re-run this model without 
  # considering covariates.
  glm_warn = ""
  
  # using myTryCatch which is an awesome way to run code and catch any 
  # warnings and errors
  log_reg_res = suppressMessages(myTryCatch(
    glm(log_form, data = dat_df, family = binomial)))
  
  
  # extracting the actual logistic regression model from the myTryCatch 
  # results
  log_reg = log_reg_res$value
  
  # Determine if the glm threw a warning and handle it accordingly.
  # is_warning will appear in the results to let us know if the glm threw a 
  # warning.
  is_warning = FALSE
  
  # If warning is not null we have a warning and we need to handle it.
  if (!is.null(log_reg_res$warning))
  {
    # Dump the warning message into our glm warn status str
    glm_warn = paste(glm_warn, "log_reg_warn: ", log_reg_res$warning, 
                     sep = "")
    
    is_warning = TRUE
    
    # The warning message comes from glm with a trailing new line, we strip 
    # that off here otherwise it causes issues when printing our results out.
    glm_warn = gsub("[\r\n]", "", glm_warn)
  }
  
  # If error is not null we have a warning and we need to handle it.
  if (!is.null(log_reg_res$error))
  {
    # Dump the warning message into our glm warn status str
    glm_warn = paste(glm_warn, "log_reg_error: ", log_reg_res$error, 
                     sep = "")
    
    is_warning = TRUE
    
    # The warning message comes from glm with a trailing new line, we strip 
    # that off here otherwise it causes issues when printing our results out.
    glm_warn = gsub("[\r\n]", "", glm_warn)
  }
  
  # Extract the p-value of association between antigen level and disease 
  # status
  log_reg_p = coef(summary(log_reg))[2,4]
  
  # Get the p-values of association for any covariates included in the model
  log_reg_cov_ps =  tail(coef(summary(log_reg))[,4], -2)
  
  # Create a string that shows the model with weightings, for example:
  # "dis_status ~  -4.8682  +  (0.1172 * mod_ant) + (0.0492 * bmi)"
  log_reg_mod = extract_lin_form(log_reg)
  
  
  # Get pretty ORs and CIs ####
  or_ci_dat = calc_or_ci(log_reg)
  ant_or_str  = or_ci_dat$ant_or
  ant_ci_str  = or_ci_dat$ant_ci
  other_ci_str = or_ci_dat$other_ci
  ci_warn = gsub("[\r\n]", "", or_ci_dat$warn)
  
  
  # Put together data and return it ####
  # R float has limit just slightly smaller than 2.22e-308
  # So if the p-value is 0 (it overflowed R float) we need to manually
  # set to smallest number we can (2.22E-308)
  if (log_reg_p == 0)
  {
    log_reg_p = 2.22e-300
  }
  
  types = sapply(dat_df[, chk], class)
  type_str = paste(names(types), types, collapse = ", ")
  
  
  mod_res = c("p_val" = log_reg_p, "OR" = ant_or_str, 
              "CI" = ant_ci_str,  "model" = log_reg_mod,
              "cov_adj" = paste(covs_to_use, collapse = ", "), 
              "cov_ps" = named_list_to_str(log_reg_cov_ps),
              "cov_or" = other_ci_str,
              "glm_warn_msg" = glm_warn, 
              "glm_warn_bool" = is_warning, 
              "var_types" = type_str, 
              "mod_method" = mod_method,
              "note_str" = note_str)
  
  
  return(mod_res)
  
}

# run_firth function. ####
# Function to run Firth logistic regression using logistf
#
# Requirements:
#   logistf [library]
#   extract_lin_form [function, 'helper_functions_pub.R']
#   get_small [function, 'helper_functions_pub.R']
#
# Input:
#  dat_df [df]: Dataframe containing data to run model on including covariates
#  covs_to_use [list]: List of covariates to adjust model for
#  LOG [bool]: Boolean specifying if we should output messages to log file 
#              [Default: TRUE]
#  DEBUG [bool]: Boolean specifying if we should output messages to console
#              [Default: FALSE]
#  LOG_FN [str]: Path to log file that we should write messages to
#
# Output:
#  named list [length: 12] :
#    p_val [float]: P-val of association between antibody level, and disease 
#                   status - from logistic regression.
#    OR [string]: Odds ratio for this association
#    CI [string]: 95% confidence intervals for this OR
#    model [string]: Logistic regression model formula with weights.
#    cov_adj [string]: String listing all covariates included in model
#    cov_ps [string]: p-values for each covariate included in the logistic
#                     regression model
#    cov_or [string]: String containing ORs and CIs for all covars
#                     that logistic regression model was adjusted for
#    glm_warn_msg [string]: Warning message output by glm if applicable
#    glm_warn_bool [bool]: Boolean indicating if glm threw warning
#    var_types [string]: String listing type of each variable in input dat_df
#    mod_method [string]: String indicating type of model run [glm, elrm, firth]
#    note_str [string]: More detailed notes collected from model
run_firth <- function(dat_df, covs_to_use, LOG, DEBUG, LOG_FN)
{
  
  mod_method = 'firth'
  note_str = ''
  
  chk = c('mod_dis', 'mod_ant')
  chk = append(chk, covs_to_use)
  
  if (LOG == TRUE) {
    write("\t\tRunning Firth", file = LOG_FN, append = TRUE)
  }
  
  if (DEBUG == TRUE) {
    cat("\t\tRunning Firth\n")
  }
  
  # Implementing Dan's Default * 100 method for Firth control iters
  def_n_iter = 25
  def_n_pl_iter = 100
  
  n_iter = def_n_iter * 100
  n_pl_iter = def_n_pl_iter * 100
  
  # Create the control objects to hand into logistf
  our_control = logistf.control(maxit = n_iter)
  our_pl_control = logistpl.control(maxit = n_pl_iter)
  
  # Match UKB Statistical model #####  
  if (length(covs_to_use) == 0)
  {
    log_form = as.formula(paste("mod_dis ~ mod_ant", sep = ''))
  } else
  {
    log_form = as.formula(paste("mod_dis ~ mod_ant +  ", 
                                paste(covs_to_use, collapse = ' + '), sep = ''))
  }
  
  # using myTryCatch which is an awesome way to run code and catch any 
  # warnings and errors
  log_reg_res = suppressMessages(myTryCatch(
    logistf(formula = log_form, data = dat_df, 
            control = our_control, plcontrol = our_pl_control)))
  
  # extracting the actual logistic regression model from the myTryCatch 
  # results
  log_reg = log_reg_res$value
  
  # Determine if the glm threw a warning and handle it accordingly.
  # is_warning will appear in the results to let us know if the glm threw a 
  # warning.
  glm_warn = ''
  is_warning = FALSE
  
  # If warning is not null we have a warning and we need to handle it.
  if (!is.null(log_reg_res$warning))
  {
    # Dump the warning message into our glm warn status str
    glm_warn = paste(glm_warn, "log_reg_warn: ", log_reg_res$warning, 
                     sep = "")
    
    is_warning = TRUE
    
    # The warning message comes from glm with a trailing new line, we strip 
    # that off here otherwise it causes issues when printing our results out.
    glm_warn = gsub("[\r\n]", "", glm_warn)
  }
  
  # If error is not null we have a warning and we need to handle it.
  if (!is.null(log_reg_res$error))
  {
    # Dump the warning message into our glm warn status str
    glm_warn = paste(glm_warn, "log_reg_error: ", log_reg_res$error, 
                     sep = "")
    
    is_warning = TRUE
    
    # The warning message comes from glm with a trailing new line, we strip 
    # that off here otherwise it causes issues when printing our results out.
    glm_warn = gsub("[\r\n]", "", glm_warn)
  }
  
  # Collect the results ####
  if (!is.null(log_reg)) {
    # Get all p-vals
    all_ps = log_reg$prob
    
    # Extract the p-value of association between antigen level and disease 
    # status
    log_reg_p = unname(all_ps['mod_ant'])
    
    
    # Remove Intercept and mod_ant from all_p's names so we can grab
    # just the covariate p-values
    all_p_names = names(all_ps) 
    
    all_p_names = all_p_names[all_p_names != '(Intercept)']
    all_p_names = all_p_names[all_p_names != 'mod_ant']
    
    # Get the p-values of association for any covariates included in the model
    log_reg_cov_ps =  all_ps[all_p_names]
    
    # Create a string that shows the model with weightings, for example:
    # "dis_status ~  -4.8682  +  (0.1172 * mod_ant) + (0.0492 * bmi)"
    
    if (grepl("linux", Sys.info()[1], ignore.case = T)) {
      sink("/dev/null")
    } else {
      sink("NUL")
    }
    log_reg_mod = extract_lin_form(log_reg, method = 'firth')
    sink()
    
    ors = exp(coef(log_reg))
    low = exp(log_reg$ci.lower)
    up = exp(log_reg$ci.upper)
    
    ant_or_str = get_small(unname(ors['mod_ant']), 3)
    ant_ci_str = paste('[', get_small(low['mod_ant'],3), '-', 
                       get_small(up['mod_ant'], 3), ']', sep = '')
    
    other_ci_str = ''
    for (curr_name in all_p_names) {
      
      curr_or = get_small(ors[curr_name], 3)
      curr_low = get_small(low[curr_name], 3)
      curr_hi  = get_small(up[curr_name], 3)
      
      
      if (other_ci_str == '') {
        other_ci_str = paste(curr_name, ": ", curr_or, " [", 
                             curr_low, "-", curr_hi, "]", sep = '')
      } else {
        other_ci_str = paste(other_ci_str, ", ", curr_name, ": ", 
                             curr_or, " [", curr_low, "-", curr_hi, "]", sep = '')
      }
      
    }
    
    firth_n = log_reg$n
    firth_dof = log_reg$df
    firth_log_like = named_list_to_str(log_reg$loglik)
    firth_iter = named_list_to_str(log_reg$iter)
    firth_conv_at_last = named_list_to_str(log_reg$conv)
    firth_method = log_reg$method
    firth_con_str = paste(names(log_reg$control), log_reg$control, sep = ' : ', collapse = ', ')
    firth_mod_con_str = paste(names(log_reg$modcontrol), log_reg$modcontrol, sep = ' : ', collapse = ', ')
    
    note_str = paste('n=', firth_n, 
                     ' | DoF=', firth_dof,
                     ' | n iters: ', firth_iter,
                     ' | Conv at last: ', firth_conv_at_last, 
                     ' | Log Likes: ', firth_log_like,
                     ' | Method: ', firth_method,
                     ' | control: ', firth_con_str, 
                     ' | mod control: ', firth_mod_con_str, 
                     sep = '')
    
    # Put together data and return it ####
    # R float has limit just slightly smaller than 2.22e-308
    # So if the p-value is 0 (it overflowed R float) we need to manually
    # set to smallest number we can (2.22E-308)
    if (log_reg_p == 0)
    {
      log_reg_p = 2.22e-300
    }
    # Some sort of firth error where we weren't given a model back (probably out of iterations)
  } else {
    log_reg_p = 'NA' 
    ant_or_str = 'NA' 
    ant_ci_str = 'NA'  
    log_reg_mod = 'NA'
    log_reg_cov_ps = 'NA'
    other_ci_str = 'NA'
    note_str = 'NA'
  }
  
  
  types = sapply(dat_df[, chk], class)
  type_str = paste(names(types), types, collapse = ", ")
  
  
  # Firth will only be used for cat so we can return those results
  # throw all results and data into list and return to caller.
  mod_res = c("p_val" = log_reg_p, "OR" = ant_or_str, 
              "CI" = ant_ci_str,  "model" = log_reg_mod,
              "cov_adj" = paste(covs_to_use, collapse = ", "), 
              "cov_ps" = named_list_to_str(log_reg_cov_ps),
              "cov_or" = other_ci_str,
              "glm_warn_msg" = glm_warn, 
              "glm_warn_bool" = is_warning, 
              "var_types" = type_str, 
              "mod_method" = mod_method,
              "note_str" = note_str)
  
  
  return(mod_res)
}