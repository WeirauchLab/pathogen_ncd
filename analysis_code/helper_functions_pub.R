# Name:     helper_functions_pub.R
# Author:   Mike Lape
# Date:     5/4/2020
# Description:
#
#     This file contains helper functions for the antibody titer - disease
#     association scripts including the asymptotic p-value calculation script
#     and the permutation scripts.
#

# Load libraries ####
# readxl is required for load_data, which uses it to read in one excel sheet.
library(readxl)

# Set some global constants ####
# Seed that we will set before using RNG
OUR_SEED = 5

# SIG_LEVEL: Significance level threshold to use for automated covariate 
#            association analysis.
SIG_LEVEL = 0.05

LOCAL_COPY_PATH =  "/data/pathogen_ncd"

######################
# Generic utilities  #
######################
# killws function. ####
# This is a gsub function to remove leading and trailing whitespace. For some
# reason trimws wasn't cutting it.
# 
# Reference:
#   SO: https://stackoverflow.com/a/45052703/12689788
# 
# Input:
#   string with leading or trailing whitespace [string]: " foo_bar "
#
# Output:
#   string: "foo_bar"
#
# Test:
#   val = kill_ws(" foo_bar ")
#       
#     val:      "foo_bar"
#
killws <- function(our_str)
{
  return(gsub("(^\\s+)|(\\s+$)", "", our_str))
}

# myTryCatch function. ####
# Very cool try catch implementation that will run a given command and capture
# output, warnings, and errors.
# 
# Reference:
#   SO: https://stackoverflow.com/a/24569739/12689788
# 
# Input:
#   Risky expression: sketchy_fun()
# 
#                     sketchy_fun <- function() { 
#                                                 cat("OK Test")
#                                                 warning("Test Warning")
#                                                 stop("Test error")
#                                                 }
#
# Output:
#   stdout: "OK Test"
#   list:
#         $value [string]: Returned value of function if any, in test we print
#                          out "OK Test" and don't return anything
#         $warning [simpleWarning]: Warning message with extra info
#         $error [simpleError]: Error message with extra info
#
# Test:
#   val = myTryCatch(sketchy_fun())
#       
#     stdout:       "OK Test"
#     val$value:    NULL
#     val$warning:  <simpleWarning in sketchy_fun(): Test Warning>
#     val$error:    <simpleError in sketchy_fun(): Test error>
#
myTryCatch <- function(expr) {
  warn <- err <- NULL
  value <- withCallingHandlers(
    tryCatch(expr, error=function(e) {
      err <<- e
      NULL
    }), warning=function(w) {
      warn <<- w
      invokeRestart("muffleWarning")
    })
  list(value=value, warning=warn, error=err)
}



###########################
# Data manipulation - I/O #
###########################
# load_data function. ####
# This function loads in all of our data files.  It contains logic to detect
# if the script is running on the HPC or my personal machine and adapt file
# paths accordingly. It will also set the working directory based on logic.
# 
# Requirements:
#   readxl: library (loaded at top of file)
#   killws: function defined elsewhere in this file
#
# Input:
#   BASE_DIR: Path to base directory where code can find all input files
#
# Output:
#   list:
#         $cov_dat [df - 9,429 x 10]:    Covariate df, columns for age, bmi, etc.
#         $ant_dat [df - 9,429 x 45]:    Antibody titer dataframe (MFIs)
#         $dis_dat [df - 9,429 x 1,127]: Binary disease status (non-cancer)
#         $roll_dat [df - 9,429 x 127]:  Binary disease status for 3-char ICD10
#                                        cancer diagnoses.
#         $ant_dict [df - 45 x 8]:       Metadata about each antibody studied.
#         $sex_spec_dis[df - 144 x 3]:   df documenting whether a disease is 
#                                        specific to one sex, e.g. ovarian cancer
#   *changes working directory
# Test:
#   val = load_data()
#       
# 
load_data <- function(BASE_DIR)
{

  # Create data file paths
  cov_dat_path    = paste(BASE_DIR, "/procd/cov_dat.csv", sep = "")
  ant_dat_path    = paste(BASE_DIR, "/procd/clean_antigen_data.csv",
                          sep = "")
  dis_dat_path    = paste(BASE_DIR, "/procd/dis_dat.csv", sep = "")
  roll_dat_path   = paste(BASE_DIR, "/procd/rolled_code.csv", sep = "")
  
  # Create dictionary file paths
  ant_dict_path       = paste(BASE_DIR, "/dicts/viral_dict.xlsx", sep = "")
  sex_spec_dis_path   = paste(BASE_DIR, "/dicts/sex_specific_codes.txt",
                              sep = "")
  
  setwd(BASE_DIR)

  
  # Set strings as factors globally to FALSE (I think this is default in 
  # next version of R)
  options(stringsAsFactors = FALSE)
  
  # Start ingesting data files
  cov_dat   = read.csv(cov_dat_path, check.names = FALSE, row.names = 1)
  ant_dat   = read.csv(ant_dat_path, check.names = FALSE, row.names = 1)
  dis_dat   = read.csv(dis_dat_path, check.names = FALSE, row.names = 1)
  roll_dat  = read.csv(roll_dat_path, check.names = FALSE, row.names = 1)

  # Ingest the dictionaries
  ant_dict  = suppressMessages(read_excel(ant_dict_path, col_names = TRUE))
  
  # Convert ant_dict to plain old df
  ant_dict = as.data.frame(ant_dict)
  
  sex_spec_dis  = read.csv(sex_spec_dis_path, check.names = FALSE, 
                           header = 1, sep = '\t')
  
  sex_spec_dis$icd_code = killws(sex_spec_dis$icd_code)
  
  return(list(cov_dat      = cov_dat, 
              ant_dat      = ant_dat, 
              dis_dat      = dis_dat, 
              roll_dat     = roll_dat,
              ant_dict     = ant_dict,
              sex_spec_dis = sex_spec_dis,
              cov_dat_path = cov_dat_path,
              ant_dat_path = ant_dat_path, 
              dis_dat_path = dis_dat_path,
              roll_dat_path = roll_dat_path, 
              ant_dict_path = ant_dict_path, 
              sex_spec_dis_path = sex_spec_dis_path))
}





#########################
# Dealing with models   #
#########################
# get_or_w_ci function. ####
# Converts an input odds ratio, a number, and 95% confidence intervals, a list
# of length 2, with the first element being the lower bound 95% CI and the 
# second element being the upper bound 95% CI into the visually more pleasing 
# form of: OR [LB-UB].  Also contains logic to round values or convert to 
# scientific notation if needed.
#
# Requirements:
#   get_small: function defined elsewhere in this file

# 
# Input:
#   or [number]: odds ratio, e.g. 1.12429
#   ci [list]: length of 2
#             1] [number]: lower bound of 95% confidence intervals, 0.6034085
#             2] [number]: upper bound of 95% confidence intervals, 2.3156143
#
# Output:
#   string: Pretty version of OR [LB - UB], e.g. "1.050 [0.294-2.903]"
#
# Test:
#     ant_or:  1.12429 
#     ant_ci: 
#             1] 0.6034085 
#             2] 2.3156143
#
#   val = get_or_w_ci(log_reg)
#       
#     val  :  "1.124 [0.603-2.316]"
#  
get_or_w_ci <- function(or, ci)
{
  
  if (is.na(or) == TRUE)
  {
    ret_or = NA
    ci_lb = NA
    ci_ub = NA
    
    ret_ci = paste(ret_or, " [", ci_lb, "-", ci_ub, "]", sep = "")
    return(ret_ci)
  }
  
  # Rounds OR to 3 decimal places
  ret_or = get_small(or,3) 
  
  # Now clean up the CI
  # Deal with small numbers - put very small numbers in scientific notation,
  # if we didn't do this when we round the LB could end up equal to 0.
  # Also CI calculation can return NA for a bound, so we catch that and handle
  # it.
  # ci[1] is the lower bound, the 2.5% - first look at lower bound.
  if (is.na(ci[1]))
  {  # If we got an NA then just set our lb to NA
    ci_lb = NA
  } else if (ci[1] < 0.001)
  { 
    # If its a really small number  (if it would equal 0 when rounding with 
    # 3 decimal points) convert to scientific notation
    ci_lb = formatC(ci[1], format = "e", digits = 2)
  } else
  {  
    # Otherwise just round it.
    ci_lb = format(round(ci[1], digits = 3), nsmall = 2, scientific = FALSE)
    
  }
  
  # Deal with upper bound! - very similar to lower bound code.
  if (is.na(ci[2]))
  {
    ci_ub = NA
  } else if (ci[2] > 1000)
  {
    # If its a really big number, convert to scientific notation
    ci_ub = formatC(ci[2], format = "e", digits = 2)
    
  } else
  {
    # Otherwise just round it.
    ci_ub = format(round(ci[2], digits = 3), nsmall = 3, scientific = FALSE)
  }
  
  # Return a pretty string with OR [2.5% - 97.5%]
  ret_ci = paste(ret_or, " [", ci_lb, "-",ci_ub , "]", sep = "")
  
  return(ret_ci)
}

# get_or function. ####
# Converts an input odds ratio, a number, into the visually more pleasing 
# rounded form of input OR .  Also contains logic to round values or convert to 
# scientific notation if needed.
#
# Input:
#   or [number]: odds ratio, e.g. 1.12429
#
# Output:
#   string: Pretty version of OR, e.g. "1.124"
#
# Test:
#     ant_or:  1.12429 
#
#   val = get_or(or)
#       
#     val  :  "1.124"
#  
get_or <- function(or)
{
  
  # Rounds OR to 3 decimal places
  ret_or = format(round(or, digits = 3), nsmall = 3)

  return(ret_or)
}

# get_ci function. ####
# Converts an input 95% confidence intervals, a list of length 2, with the 
# first element being the lower bound 95% CI and the second element being the 
# upper bound 95% CI into the visually more pleasing form of: [LB-UB].  
# Also contains logic to round values or convert to scientific notation if 
# needed.
#
# Input:
#   ci [list]: length of 2
#             1] [number]: lower bound of 95% confidence intervals, 0.6034085
#             2] [number]: upper bound of 95% confidence intervals, 2.3156143
#
# Output:
#   string: Pretty version of CIs [LB - UB], e.g. "[0.294-2.903]"
#
# Test:
#     ant_ci: 
#             1] 0.6034085 
#             2] 2.3156143
#
#   val = get_ci(ant_ci)
#       
#     val  :  "[0.603-2.316]"
#  
get_ci <- function(ci)
{
  
  # Clean up the CI
  # Deal with small numbers - put very small numbers in scientific notation,
  # if we didn't do this when we round the LB could end up equal to 0.
  # Also CI calculation can return NA for a bound, so we catch that and handle
  # it.
  # ci[1] is the lower bound, the 2.5% - first look at lower bound.
  if (is.na(ci[1]))
  {  # If we got an NA then just set our lb to NA
    ci_lb = NA
  } else if (ci[1] < 0.001)
  { 
    # If its a really small number  (if it would equal 0 when rounding with 
    # 3 decimal points) convert to scientific notation
    ci_lb = formatC(ci[1], format = "e", digits = 2)
  } else
  {  
    # Otherwise just round it.
    ci_lb = format(round(ci[1], digits = 3), nsmall = 2, scientific = FALSE)
    
  }
  
  # Deal with upper bound! - very similar to lower bound code.
  if (is.na(ci[2]))
  {
    ci_ub = NA
  } else if (ci[2] > 1000)
  {
    # If its a really big number, convert to scientific notation
    ci_ub = formatC(ci[2], format = "e", digits = 2)
    
  } else
  {
    # Otherwise just round it.
    ci_ub = format(round(ci[2], digits = 3), nsmall = 3, scientific = FALSE)
  }
  
  # Return a pretty string with OR [2.5% - 97.5%]
  ret_ci = paste("[", ci_lb, "-",ci_ub , "]", sep = "")
  
  return(ret_ci)
}

# get_small function. ####
# Either rounds the input number to the given precision, or if rounding to this
# precision would cause the result to be 0, e.g. 0.001 rounded to 2 decimals,
# this function will convert it to scientific notation and return that value.
#
# Input:
#   num [number]: number to round or convert
#   prec [int]: precision desired, i.e. number of integers after decimal point
#   sci_digits [int]: number of decimal places you want if returning sci not.
# Output:
#   string: Rounded or scientific notation version of input number
#
# Test:
#     num: 0.00154
#     prec: 3
#
#   val = get_small(num, prec)
#       
#     val  :  "0.002"
#  
get_small <- function(num, prec, sci_digits = 1)
{
  low_bound = 1/(10^prec)
  up_bound = 10^prec
  
  if (is.na(num) == TRUE)
  {
    return(NA)
  }
  
  if (num < low_bound)
  { 
    # If its a really small number  (if it would equal 0 when rounding with 
    # 3 decimal points) convert to scientific notation
    ret = formatC(num, format = "e", digits = sci_digits)
  } else if (num > up_bound)
  {  
    ret = formatC(num, format = "e", digits = sci_digits)
    
  } else {
    # Otherwise just round it.
    ret = format(round(num, digits = prec), nsmall = prec, scientific = FALSE)
    
  }

  return(ret)
}

# calc_or_ci function. ####
# This calculates odds ratio and 95% CIs for antibody and all covariates and 
# hands back a list of strings, representing the antibody association OR, the 
# the antibody association CI, the OR [LB-UB] for all covariates as one string,
# and any warning messages.
#
# Requirements:
#   get_or_w_ci: function defined elsewhere in this file
#
# Input:
#   log_reg_obj [glm]: logistic regression model 
#   ants [list]: legacy option no longer used     
#
# Output:
#   list:
#         $ant_or [string]  : Antibody odds ratio, "1.124"
#         $ant_ci [string]  : Antibody 95% confidence intervals, "[0.603-2.316]"
#         $other_ci [string]: ORs and CIs for covariates in form 
#                             "cov: OR [LB-UB], ..."
#         $warn [string]    : Any warning information raised by confint function
#
# Test:
#   log_reg in example is glm for params:
#     disease:  "other salmonella infections[A02]"
#     antibody: "1gG antigen for Herpes Simplex virus-1"
#
#   val = calc_or_ci(log_reg)
#       
#     val$ant_or   :  "1.124"
#     val$ci       :  "[0.603-2.316]"
#     val$other_ci :  "bmi: 1.050 [0.294-2.903], age: 0.709 [0.356-1.415]"
#     warn         :  ""
#  
calc_or_ci <- function(log_reg_obj, ants = c())
{
  # Conf interval calculations can throw warnings so we create a string to catch
  # any of these.
  ci_warn = ""
  
  # Extract the odds ratios for intercept, antibody, and all covariates from
  # input logistic regression model.
  ors <- exp(coef(log_reg_obj))
  
  
  # Calculate the 95% confidence intervals for intercept, antibody, and all 
  # covariates in the input model. We use myTryCatch to catch any CI warnings 
  # and handle accordingly.
  ci = suppressMessages(
    myTryCatch(
      exp(confint.default(log_reg_obj))))
  
  # If we get an error from the CI myTryCatch we will run the CI calculations
  # again one by one to figure out which one is causing the issue for which we
  # will set the CIs to 1,1
  if (!is.null(ci$error))
  {
    # Dump the warning message into our warning string
    ci_warn = paste(ci_warn, "ci_calc: ", ci$error, sep = "")
    
    # Get the OR names so we can loop through them
    or_names = names(ors)
    
    # Manually create CI result matrix (2.5% and 97.5% columns) and initially
    # set each value to 1.
    ci_res = matrix(1, nrow = length(or_names), ncol = 2,
                    dimnames = list(c(or_names), c("2.5%", "97.5%")))
    
    # For each covariate we will calculate the CI for just it.
    for (a in or_names)
    {
      ci = suppressMessages(
        myTryCatch(
          exp(confint.default(log_reg_obj, parm = a))))
      
      # If we get an error when running just this covariate, we found our 
      # troublemaker. So, we will set its CIs to 1. If we don't get an error,
      # then just passthrough the calculated confidence intervals.
      if (!is.null(ci$error))
      {
        ci_res[a,1] = 1
        ci_res[a,2] = 1
      } else
      {
        ci_res[a,1] = ci$value[1]
        ci_res[a,2] = ci$value[2]
      }
    }
    
  } else
  {
    
    # If there was no error in ci calculation then just shove the results in 
    # ci_res
    ci_res = ci$value
    
  }
  
  # Get name of mod_ant column
  ant_name = grep('mod_ant', names(ors), value = TRUE)
  
  # Extract the antigen OR and CIs
  ant_ors <- ors[ant_name]
  ant_ci <- ci_res[ant_name,]
  
  # Get "pretty" versions of antibody OR and CIs, e.g. "1.050 [0.294-2.903]"
  ant_ci_p = get_or_w_ci(ant_ors, ant_ci)
  
  # We ended up needing to put the OR in one output column and CIs in another
  # so we split our string from above into 2 smaller strings. "1.050" and
  # "[0.294-2.903]"
  ant_or_str = unlist(str_split(ant_ci_p, " "))[1]
  ant_ci_str = unlist(str_split(ant_ci_p, " "))[2]
  
  # Handle case where there are more covariates in the model and get their 
  # OR and CIs
  other_ci_str = ""
  if (length(names(ors)) > 2 )
  {
    # Now loop over our covars and collect create 1 string with their ORs and 
    # CIs
    for (z in 3:length(names(ors)))
    {
      # Extract current covariate name, OR, and CIs
      curr_name = names(ors)[z]
      curr_or = ors[z]
      curr_ci = ci_res[z,]
      
      # Transform our OR and CI into nice string: 'OR [LB - UB]'
      ret_ci = get_or_w_ci(curr_or, curr_ci)
      
      # If this is our first item going in other_ci_str, we don't
      # want to prepend a comma
      if (other_ci_str == "")
      {
        other_ci_str = paste(curr_name, ": ", ret_ci, sep = '')
      } else
      {
        # other_ci_str already has results so add a comma then these results.
        other_ci_str = paste(other_ci_str, ", ", 
                             curr_name, ": ", ret_ci, sep = '')
      }
    }
  }
  
  # Return list of results, including the antibody OR string, the antibody CI
  # string, the string containing the OR [LB-UB] for all covariates, and then
  # the CI warning string.
  return(list(ant_or   = ant_or_str, 
              ant_ci   = ant_ci_str, 
              other_ci = other_ci_str,
              warn     = ci_warn))
 
  }




# named_list_to_str function. ####
# Give this function a named list of numbers and it will return a string 
# in the form name_col_1 : value_col_1, name_col_2 : value_col_2,...
# Note: values will be in scientific notation with 2 decimal points
# This is used for converting the p-values of covariates in a logistic 
# regression model to scientific notation and printing them in a nice way.
#
# Input:
#   ls [named list]:
#               $name1 [number] : First number, e.g. p-value
#               $name2 [number] : Second number, e.g. p-value
#               ...
#
# Output:
#   string: "name1 : 5.00e-2, name2 : 1.00e-2"
#
# Test:
#   log_reg_cov_ps: 
#                   $sex1:  0.01734365
#                   $bmi :  0.34776128
#   val = named_list_to_str(log_reg_cov_ps)
#       
#     val: "sex1 : 1.73e-02, bmi : 3.48e-01"
#
# 
named_list_to_str = function(ls)
{
  return(paste(
    names(ls), 
    formatC(ls, format = "e", digits = 2), 
    sep = " : ", collapse = ", "))
}

# extract_lin_form function. ####
# This function will take a lm or glm model and will hand back a string with 
# the full formula with coefs. FYI: sex = 0 is female, sex = 1 is male.
#
# Input:
#   linear or logistic regression model [lm or glm]: test_model
#   ants [list]: legacy option no longer used     
#   method [string]: Type of model object being input, default is 'glm', but 
#   could also be 'firth'
#
# Output:
#   string: "dis_status ~  -4.8682  +  (0.1172 * mod_ant) + (0.0492 * bmi)"
#
# Test:
#   log_reg in example is glm for params:
#     disease:  "other salmonella infections[A02]"
#     antibody: "1gG antigen for Herpes Simplex virus-1"
#
#   val = extract_lin_form(log_reg)
#       
#     val: "dis_status ~  -4.8682  +  (0.1172 * mod_ant) + (0.0492 * bmi) + 
#               (-0.3436 * age)"
#
extract_lin_form = function(mod, ants = c(), method = 'glm')
{
  # Extract the coefficients of model and store for use.
  if (method == 'firth') {
    coef_df = as.data.frame(exp(coef(mod)))
    p_vals = summary(mod)$prob
    
  } else {
    coef_df = as.data.frame(exp(coef(mod)))
    p_vals = coef(summary(mod))[,4]
  }

  # glm model (assumes logistic regression)
  # Generate return string containing model with paste weights
  # Examples: "dis_status ~  -4.8682  +  (0.1172 * mod_ant) + 
  #                             (0.0492 * bmi) + (-0.3436 * age)"
  ret = paste("dis_status ~  ", get_small(coef_df[1,],3),
              "[", get_small(p_vals[1], 3), "]", sep = "")
  
  # Remove the intercept
  rest_coefs = tail(coef_df, -1)
  rest_ps = tail(p_vals, -1)
  
  # Put in other covariates
  if (nrow(rest_coefs) > 0 )
  {
    for (z in 1:nrow(rest_coefs))
    {
      cov_name = rownames(rest_coefs)[z]
      if (cov_name == "sex1")
      {
        cov_name = "male"
      } else if (cov_name == "sex0") {
        cov_name = "female"
      }
      ret = paste(ret, " + (", get_small(rest_coefs[z,1],3), " * ", 
                  cov_name, "[", get_small(rest_ps[z], 3), "])", sep = "")
    }
  }
  
  return(ret)
}



###################
#     Misc.       #
###################
# get_icd function. ####
# This function extracts the disease name and ICD10 code from the unparsed 
# disease field
#
# Input:
#   unparsed disease [string]: "abnormalities of forces of labour[O62]"
#
# Output:
#   list:
#         $dis [string]: Disease name, "abnormalities of forces of labour"
#         $cat [string]: ICD category/chapter, "O"
#         $loc [string]: ICD numeric code, "62"
#
# Test:
#   val = get_icd("abnormalities of forces of labour[O62]")
#       
#     val$dis:  "abnormalities of forces of labour"
#     val$cat:  "O"
#     val$loc:  "62"
#
get_icd <- function(dis_name)
{
  
  # If we have a proper ICD10 code in our disease name
  if (grepl('\\[', dis_name))
  {
    # Extract some info from disease names
    # Disease name
    dis = unlist(strsplit(dis_name, "\\[[[:alpha:]]\\d\\d\\]"))[1]
    
    dirt_code = tail(unlist(strsplit(dis_name, "\\[")), n = 1)
    
    # Grab ICD10 code
    full_code = gsub("\\]", "", unlist(strsplit(dirt_code, "\\["))[1])
    
    # Category = M
    # Code = 32
    icd_cat = unlist(strsplit(full_code, "[[:digit:]]"))[1]
    icd_loc = unlist(strsplit(full_code, "[[:alpha:]]"))[2]
    
  } else
  {
    dis = dis_name
    icd_cat = "NA"
    icd_loc = "NA"
  }
  
  return(list(dis = dis, cat = icd_cat, loc = icd_loc))
}

#########################
# Association testing   #
#########################
# calc_ant_assoc function. ####
# This function calculates association between antibody level and 
# any of the main covariates. It takes a second parameter, is_sex_part, with a
# default value of False, which tells the function if the input data
# is already sex partitioned.  If it is we need to skip the check
# for association with sex as this will fail.
#
# Uses the following test for each covariate
# Sex:	                        t-test
# Age:	                        linear regression
# BMI:	                        linear regression
# Race:	                        ANOVA
# Townsend Deprivation Index:	ANOVA
# Number in House:	            ANOVA
# Tobacco Use:	                ANOVA
# Alcohol Use:	                ANOVA
# Number of Sex Partners:	    ANOVA
# Same-sex Intercourse:   	    ANOVA
#
# Input:
#   input_df: dataframe containing column "mod_ant" with antibody titers and 
#             additional columns for each covariate that we will test.
#   is_sex_part: boolean indicating whether incoming data had been partitioned
#                based on sex, which tells this function whether to skip the 
#                association test for covariate sex.
#   
# Output:
#   list:
#         Each element is name of significantly associated covariate with this
#         antibody
#         NOTE: can return empty list if no significantly associated covariates.
#
# Test:
#   ant_df prepared for HSV1 antibody: "1gG antigen for Herpes Simplex virus-1" 
#   val = calc_ant_assoc(ant_df, FALSE)
#     val[1]:   "bmi"
#     val[2]:   "age"
#     val[3]:   "ethnic"
#     val[4]:   "tdi_quant"
#     val[5]:   "num_in_house"
#     val[6]:   "tobac"
#     val[7]:   "alc"
#     val[8]:   "num_sex_part"
#
calc_ant_assoc <- function(input_df, is_sex_part = FALSE)
{
  # Empty list that we will throw the significantly associated covariate names
  # into.
  covs = list()
  
  # We need to handle the covariate/mod_ant association carefully if this is for
  # a sex-specific disease.
  
  # If not a sex-specific disease (so just normal)
  if (!is_sex_part)
  {
    # Calculate association between antigen level and sex using t.test since 
    # sex is our 1 covariate that is binary
    #
    ant_assoc = t.test(mod_ant ~ sex, data = input_df)$p.value
    
    # Then test to see if this mod_ant/sex association is significant(SIG_LEVEL
    # is defined at top of script as global constant). any handles the case 
    # where have multiple p-values, not the case for this test, but
    # code was re-used when possible if it didn't cause an issue such as here.
    # If there is a significant association add sex to "covs" list.
    if (any(ant_assoc < SIG_LEVEL))
    {
      covs = append(unlist(covs), "sex")
    }
  }
  
  # BMI - linear regression between bmi and antibody level
  #   extracting p-value for BMI
  ant_assoc = summary(lm(mod_ant ~ bmi, data = input_df))$coefficients[2,4]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(unlist(covs), "bmi")
  }   
  
  # age - linear regression between age and antibody level (same as bmi)
  ant_assoc = summary(lm(mod_ant ~ age, data = input_df))$coefficients[2,4]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(unlist(covs), "age")
  }
  
  # Ethnic
  # Ethnicity is a categorical with 4 levels so we use ANOVA
  ant_assoc = summary(aov(mod_ant ~ ethnic, data = input_df))[[1]][["Pr(>F)"]][1]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(unlist(covs), "ethnic")
  }
  
  
  # TDI quantile - a categorical with 3 levels, use ANOVA
  ant_assoc = summary(aov(mod_ant ~ tdi_quant, data = input_df))[[1]][["Pr(>F)"]][1]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(unlist(covs), "tdi_quant")
  } 
  
  
  # Number in house - categorical with 6 levels, use ANOVA
  ant_assoc = summary(aov(mod_ant ~ num_in_house, data = input_df))[[1]][["Pr(>F)"]][1]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(covs, "num_in_house")
  } 
  
  # Tobacco Use - categorical with 3 levels, use ANOVA
  ant_assoc = summary(aov(mod_ant ~ tobac, data = input_df))[[1]][["Pr(>F)"]][1]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(covs, "tobac")
  } 
  
  
  # Alcohol use - categorical with 3 levels, use ANOVA
  ant_assoc = summary(aov(mod_ant ~ alc, data = input_df))[[1]][["Pr(>F)"]][1]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(covs, "alc")
  } 
  
  # Num sex partners - categorical with 6 levels, use ANOVA
  ant_assoc = summary(aov(mod_ant ~ num_sex_part, data = input_df))[[1]][["Pr(>F)"]][1]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(covs, "num_sex_part")
  } 
  
  # Same sex - categorical with 3 levels, use ANOVA
  ant_assoc = summary(aov(mod_ant ~ same_sex, data = input_df))[[1]][["Pr(>F)"]][1]
  
  if (any(ant_assoc < SIG_LEVEL))
  {
    covs = append(covs, "same_sex")
  }
  
  # Return the list of covariates that were found to be significantly associated
  # with the antibody level.
  return(covs)
  
}


# calc_dis_assoc function. ####
# This function calculates association between disease status and 
# any of the main covariates. Becuase disease status is binary and most 
# covariates are categorical, we will mostly use chi-squared tests for 
# determining association. The function takes a second parameter, is_sex_part, 
# with a default value of False, which tells the function if the input data
# is already sex partitioned.  If it is we need to skip the check
# for association with sex as this will fail. 
# 
# Uses the following test for each covariate
# Sex:	                        Chi-squared
# Age:	                        t-test
# BMI:	                        t-test
# Race:	                        Chi-squared
# Townsend Deprivation Index:	Chi-squared
# Number in House:	            Chi-squared
# Tobacco Use:	                Chi-squared
# Alcohol Use:	                Chi-squared
# Number of Sex Partners:	    Chi-squared
# Same-sex Intercourse:   	    Chi-squared
#
# Input:
#   input_df: dataframe containing column "mod_dis" with disease status and 
#             additional columns for each covariate that we will test.
#   is_sex_part: boolean indicating whether incoming data had been partitioned
#                based on sex, which tells this function whether to skip the 
#                association test for covariate sex.
#   
# Output:
#   list:
#         Each element is name of significantly associated covariate with this
#         antibody
#         NOTE: can return empty list if no significantly associated covariates.
#
# Test:
#   mod_df prepared for disease: "other salmonella infections[A02]" 
#   val = calc_dis_assoc(mod_df, FALSE)
#     val[1]:   "bmi"
#     val[2]:   "age"
#
calc_dis_assoc <- function(input_df, is_sex_part = FALSE)
{
  
  # Empty list that we will throw the significantly associated covariate names
  # into.
  dis_covs = list()
  
  # We need to handle the covariate/mod_ant association carefully if this is for
  # a sex-specific disease.
  
  # If not a sex-specific disease (so just normal)
  if (is_sex_part == FALSE)
  {
    # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
    # for reproducible results.
    set.seed(OUR_SEED)
    
    # Sex is binary and disease status is binary, so chisq.test!
    dis_assoc = (chisq.test(input_df$mod_dis, input_df$sex, 
                            simulate.p.value = T))$p.value
    
    # Then test to see if this mod_dis/sex association is significant(SIG_LEVEL
    # is defined at top of script as global constant). any handles the case 
    # where have multiple p-values, not the case for this test, but
    # code was re-used when possible if it didn't cause an issue such as here.
    # If there is a significant association add sex to "covs" list.
    if (dis_assoc < SIG_LEVEL)
    {
      dis_covs = append(unlist(dis_covs), "sex")
    }
  }
  
  # Using t-test for BMI and Age since they are continuous and our disease
  # status is binary.
  
  # BMI is continuous, use t.test
  dis_assoc = (t.test(bmi ~ mod_dis, data = input_df))$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "bmi")
  }	   
  
  # Age is continuous, use t.test
  dis_assoc = (t.test(age ~ mod_dis, data = input_df))$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "age")
  }
  
  # Ethnic
  # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
  # for reproducible results.
  set.seed(OUR_SEED)
  
  # Ethnicity is a categorical with 4 levels, use chisq.test
  dis_assoc = (chisq.test(input_df$mod_dis, input_df$ethnic, 
                          simulate.p.value = T))$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "ethnic")
  }
  
  # TDI quantile - a categorical with 3 levels, use chisq.test
  # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
  # for reproducible results.
  set.seed(OUR_SEED)
  
  dis_assoc = chisq.test(input_df$mod_dis, input_df$tdi_quant, 
                         simulate.p.value = T)$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "tdi_quant")
  } 
  
  # Number in house - categorical with 6 levels, use chisq.test
  # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
  # for reproducible results.
  set.seed(OUR_SEED)
  
  dis_assoc = chisq.test(input_df$mod_dis, input_df$num_in_house, 
                         simulate.p.value = T)$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "num_in_house")
  } 
  
  # Tobacco Use - categorical with 3 levels, use chisq.test
  # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
  # for reproducible results.
  set.seed(OUR_SEED)
  
  dis_assoc = chisq.test(input_df$mod_dis, input_df$tobac, 
                         simulate.p.value = T)$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "tobac")
  } 
  
  # Alcohol use - categorical with 3 levels, use chisq.test
  # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
  # for reproducible results.
  set.seed(OUR_SEED)
  
  dis_assoc = chisq.test(input_df$mod_dis, input_df$alc, 
                         simulate.p.value = T)$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "alc")
  } 
  
  # Num sex partners - categorical with 6 levels, use chisq.test
  # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
  # for reproducible results.
  set.seed(OUR_SEED)
  
  dis_assoc = chisq.test(input_df$mod_dis, input_df$num_sex_part, 
                         simulate.p.value = T)$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "num_sex_part")
  } 
  
  # Same sex - categorical with 3 levels, use chisq.test
  # Chi.sq test is using simulate.p.values which is stochastic, so we set seed 
  # for reproducible results.
  set.seed(OUR_SEED)
  
  dis_assoc = chisq.test(input_df$mod_dis, input_df$same_sex, 
                         simulate.p.value = T)$p.value
  
  if (dis_assoc < SIG_LEVEL)
  {
    dis_covs = append(unlist(dis_covs), "same_sex")
  }
  
  # Return the list of covariates that were found to be significantly associated
  # with this disease status.
  return(dis_covs)
}

