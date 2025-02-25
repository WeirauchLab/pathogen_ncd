# Name:     ukb_icd_emp_p_calculations_pub.py
# Author:   Mike Lape
# Date:     3/7/2020
# Description:
#
#   This program takes an ICD10 code as it's input then goes and collects all
#   of the permutations files. It verifies we have all 450K results that we 
#   should for the null distribution, then calculates a BH FDR and adds that
#   to the result file which it writes out in the end.
#

# Data manipulation
import numpy as np
import pandas as pd

# Data science
import math
from statsmodels.stats.multitest import multipletests as mt

import tqdm
import argparse


# Misc libraries
import os
import glob

HOME_DIR =  "/data/pathogen_ncd"

# Create the parser
parser = argparse.ArgumentParser()

# Add an argument
parser.add_argument('--icd', type=str, required=True)

# Parse the argument
args = parser.parse_args()

curr_icd = args.icd

res_dir = f'{HOME_DIR}/results'
res = pd.read_csv(f'{res_dir}/ukb_mod_results_01_17_2023.csv', low_memory = False)
res = res.rename(columns = {'organism' : 'org', 'Antigen' : 'anti'})

org_ab_ls = res.loc[:, ['org', 'anti']].drop_duplicates().values.tolist()

perm_res_dir = f'{res_dir}/perm_p_sims/final'
perm_proc_dir = f'{HOME_DIR}/procd/perm_p_sim_inputs/final'
perm_res_out_dir = f'{res_dir}/perm_p_sims/emp_calcs'

fin_cols = ['Unparsed_Disease', 'Disease', 'ICD10_Cat', 'ICD10_Site',
            'sex_specific_dis', 'nCase', 'nControl', 'control_set', 'n_mixed',
            'anti', 'org', 'p_val', 'anti_OR', 'anti_CI', 'model', 'r2_tjur',
            'r2_mcfad', 'r2_adj_mcfad', 'r2_nagelkerke', 'r2_coxsnell', 'cov_ps',
            'sig_covs', 'cov_adj_for', 'cov_ors', 'avg_age_case', 'avg_avg_con',
            'avg_titer_case', 'avg_titer_con', 'std_titer_case', 'std_titer_con',
            'med_titer_case', 'med_titer_con', 'Warnings', 'is_warning',
            'vanilla_pair', 'vanilla_dis', 'proc_time', 'date_time', 'mod_version',
            'icd', 'std_lev', 'p_sig', 'risk', 'protect', 'effect',
            'tot_dis_perms', 'perms_lt_mod_3_p', 'mod_3_emp_p']
fin_res_ls = []

out_fn = f'{perm_res_out_dir}/{curr_icd}_emp_p_results.tsv'

# Grab current disease analysis results
curr_dis_res = res.loc[res['icd'] == curr_icd,]

# Find permutation result file
curr_search = f"{perm_res_dir}/{curr_icd}_perms_10000_pid*.tsv"

curr_fn_ls = glob.glob(curr_search)

if len(curr_fn_ls) != 1:
    print(f"Found {len(curr_fn_ls)} permutation files for {curr_icd}")
    #continue

# Read in perm result file for dis
curr_fn = curr_fn_ls[0]
curr_perms = pd.read_csv(curr_fn, sep="\t", low_memory = False)

# 10,000 permutations for 45 Abs should be 450,000 results
# if not we need to warn and look into this more closely
tot_perms = len(curr_perms)
if tot_perms != 450000:
    print(f"{curr_fn} only has {tot_perms} perms, not the expected 450k!")
    #continue

# Create null distribution for disease
p_dist = curr_perms.loc[:, 'p_val'].values.tolist()
tot_perms = len(p_dist)
# Loop through each dis-Ab pair calculating en empirical p-value
fin_res_ls = []
for curr_org, curr_ab in tqdm.tqdm(org_ab_ls):

    curr_res = curr_dis_res.loc[((curr_dis_res['org'] == curr_org) &
                                 (curr_dis_res['anti'] == curr_ab)), :]

    if len(curr_res) == 0:
        print(f"No res for {curr_icd} {curr_org} {curr_ab}")
        continue

    curr_res = curr_res.iloc[0]

    b = tot_perms
    B = sum(p_dist <= curr_res['p_val'])
    emp_p = (B + 1) / (b + 1)

    curr_res_ls = curr_res.tolist()
    curr_res_ls.extend([b, B, emp_p])
    fin_res_ls.append(curr_res_ls)

# Stuff current disease results in a df and do disease-wide MCC
fin_res = pd.DataFrame(fin_res_ls, columns = fin_cols)


bon = mt(fin_res.loc[:, 'mod_3_emp_p'], method = 'bonferroni')[1]
bh = mt(fin_res.loc[:, 'mod_3_emp_p'], method = 'fdr_bh')[1]

fin_res['bon'] = bon
fin_res['bh_fdr'] = bh

fin_res.to_csv(out_fn, sep = '\t', index = False)