# Name:     tnx_phecode_generating_pairs_pub.py
# Author:   Mike Lape
# Date:     2024
# Description:
#
#   This code generates pairs of a single Phecode with all LOINC tests we need
#   to test it with. It will use submitArrayJobs 
# (https://github.com/ernstki/submitArrayJobs) which will handle running this 
# code for each individual Phecode.
#         

import csv
import glob
from tqdm import tqdm
import numpy as np
import pandas as pd
import argparse
import os
import sys
from datetime import datetime
import pytz
from pytz import timezone 

import warnings
warnings.simplefilter(action ='ignore', category=FutureWarning)

############################################
#                                          #
#           Helper Functions               #
#                                          #
############################################

# Returns the current date and time in Eastern time as a string
def dt():
  # Get current date and time in Eastern time
  dt_east = datetime.now(pytz.timezone('US/Eastern'))
  dt_east_str = dt_east.strftime('[%Y-%m-%d %H:%M:%S %Z]:')

  return dt_east_str

# Send messages to a log file as well as to the console
def log_message(message, filename):
	with open(filename, 'a') as f:
	# Write to the file
		f.write(message + '\n')
        
    # Write to stdout (console)
		sys.stdout.write(message + '\n')


def main():

	# Get Phecode
	parser = argparse.ArgumentParser(description = 'Script to generate TriNetX cohorts for phecode-org pairs')
	parser.add_argument('-p','--phe', help='Single Phecode code to find pairs for', required = True)
	args = vars(parser.parse_args())

	curr_phe = args['phe']
	curr_mcc_str = "mcc1"


	print(f"Starting work on {curr_mcc_str}: {curr_phe}")

	BASE_DIR = "/data/pathogen_ncd"

	# Setup our environment
	TNX_FN = "trinetx"
	TNX_FP = f"{BASE_DIR}/{TNX_FN}"
	TNX_STR = TNX_FN


	WORK_FN = f"phecode/tnx/phecode_lab_pair_final"
	WORK_FP = f"{BASE_DIR}/{WORK_FN}"
	WORK_STR = "phecode_lab_pair_final"

	CODE_FP = f"{WORK_FP}/code"
	CODE_STR = f"{WORK_STR}/code"

	PHE_FN = f"phecode/tnx/tnx_procd/{curr_mcc_str}"
	PHE_FP = f"{BASE_DIR}/{PHE_FN}"
	PHE_STR = f"translatiom/slices/{curr_mcc_str}"

	# Output information
	PAIR_FN = f"phe_{curr_mcc_str}_{curr_phe}_pairs.tsv"
	PAIR_FP = f"{WORK_FP}/{PAIR_FN}"
	PAIR_STR = f"{WORK_FN}/{PAIR_FN}"
	PAIR_DIR = f"{WORK_FP}/out/{curr_mcc_str}/{curr_phe}"

	SUMMARY_FN = f"summaries/phe_{curr_mcc_str}_{curr_phe}_pair_summary.tsv"
	SUMMARY_FP = f"{WORK_FP}/{SUMMARY_FN}"
	SUMMARY_STR = f"{WORK_FN}/{SUMMARY_FN}"
	SUMMARY_DIR = f"{WORK_FP}/out/{curr_mcc_str}/summaries"

	LOG_FN = f"logs/phe_{curr_mcc_str}_{curr_phe}_pair_log.log"
	LOG_FP = f"{WORK_FP}/{LOG_FN}"
	LOG_STR = f"{WORK_FN}/{LOG_FN}"
	LOG_DIR = f"{WORK_FP}/logs/{curr_mcc_str}"

	# Lab stuff
	LAB_FN = f"lab_data"
	LAB_FP = f"{TNX_FP}/{LAB_FN}"
	LAB_STR = f"{TNX_FN}/{LAB_FN}"

	# Manually reviewed labs to give us a final list of LOINC codes
	MAN_REV_LAB_FN = f"lab_test_data_analysis_latest_manual_review.xlsx"
	MAN_REV_LAB_FP = f"{TNX_FP}/{MAN_REV_LAB_FN}"
	MAN_REV_LAB_STR = f"{TNX_FN}/{MAN_REV_LAB_FN}"

	# Number of test results for each LOINC code - so should we even look at LOINC?
	LOINC_TEST_CNTS_FN = f"clean_loinc_counts.tsv"
	LOINC_TEST_CNTS_FP = f"{TNX_FP}/{LOINC_TEST_CNTS_FN}"
	LOINC_TEST_CNTS_STR = f"{TNX_FN}/{LOINC_TEST_CNTS_FN}"

	# LOINC codes we have more than 0 results for
	LOINC_CODES_WITH_N_FN = f"loincs_with_more_than_0_res_new_version.txt"
	LOINC_CODES_WITH_N_FP = f"{TNX_FP}/{LOINC_CODES_WITH_N_FN}"
	LOINC_CODES_WITH_N_STR = f"{TNX_FN}/{LOINC_CODES_WITH_N_FN}"

	# Columns and data types for the diagnosis and lab data
	DIAG_COLS = ['pat_id', 'vocab', 'icd_code', 'date', 'phecode']
	DTYPE_DICT = {'pat_id': str, 'vocab': str, 'icd_code': str,
								'date': str, 'phecode': str}

	LAB_COLS = ['pat_id', 'enc_id', 'code_system', 'code',
							'lab_date', 'lab_result_num',
							'lab_result_text', 'test_type',
							'derived_by_TriNetX', 'source_id']

	# Generate our output directory
	if not os.path.exists(PAIR_DIR):
		print(f"Creating output directory: {PAIR_DIR}")
		os.makedirs(PAIR_DIR, exist_ok = True)
	else:
		print(f"Using existing output directory: {PAIR_DIR}")

	if not os.path.exists(SUMMARY_DIR):
		print(f"Creating output directory: {SUMMARY_DIR}")
		os.makedirs(SUMMARY_DIR, exist_ok = True)
	else:
		print(f"Using existing output directory: {SUMMARY_DIR}")

	if not os.path.exists(LOG_DIR):
		print(f"Creating output directory: {LOG_DIR}")
		os.makedirs(LOG_DIR, exist_ok = True)
	else:
		print(f"Using existing output directory: {LOG_DIR}")

	vers_info = sys.version_info
	py_ver = f"{vers_info.major}.{vers_info.minor}.{vers_info.micro}"

	log_message(f'{dt()} Setting up environment:', LOG_FP)
	log_message(f'\t\t\t    Py version:                {py_ver}', LOG_FP)
	log_message(f'\t\t\t    Base Dir:                  {BASE_DIR}', LOG_FP)
	log_message(f'\t\t\t    TNX Dir:                   {TNX_STR}', LOG_FP)
	log_message(f'\t\t\t    Work Dir:                  {WORK_STR}', LOG_FP)
	log_message(f'\t\t\t    Code Dir:                  {CODE_STR}', LOG_FP)
	log_message(f'\t\t\t    Phecode Dir:               {PHE_STR}', LOG_FP)
	log_message(f'\t\t\t    Output Dir:                {PAIR_STR}', LOG_FP)
	log_message(f'\t\t\t    Summary Dir:               {SUMMARY_STR}', LOG_FP)
	log_message(f'\t\t\t    Log File:                  {LOG_STR}', LOG_FP)
	log_message(f'\t\t\t    Labs Dir:                  {LAB_STR}', LOG_FP)
	log_message(f'\t\t\t    Manual Rev LOINC File:     {MAN_REV_LAB_STR}', LOG_FP)
	log_message(f'\t\t\t    Lab Test Counts File:      {LOINC_TEST_CNTS_STR}', LOG_FP)
	log_message(f'\t\t\t    Lab Tests n > 0 File:      {LOINC_CODES_WITH_N_STR}', LOG_FP)
	log_message(f'\t\t\t    MCC:						           {curr_mcc_str}', LOG_FP)
	log_message(f'\t\t\t    Phecode being Processed:   {curr_phe}', LOG_FP)
	log_message(f'{dt()} Environment setup complete.', LOG_FP)
	log_message(f'{dt()} Starting the status logging process.', LOG_FP)
	log_message(f'{dt()} Starting the output writing process', LOG_FP)

	# Only using labs we have more than 0 results for after pre-processing data
	loincs = pd.read_csv(LOINC_CODES_WITH_N_FP, sep = "\t")
	loinc_ls = loincs['loinc'].drop_duplicates().tolist()

	# Read in the manual review info for all the labs and only keep the good ones
	man_rev_labs = pd.read_excel(MAN_REV_LAB_FP)
	man_rev_labs = man_rev_labs.loc[man_rev_labs['good'] == 'y', :]

	# Read in the lab count information
	lab_count_info = pd.read_csv(LOINC_TEST_CNTS_FP, sep='\t')

	# Drop outdated count column
	lab_count_info = lab_count_info.loc[:, lab_count_info.columns != 'count']

	# Merge in that info
	man_rev_labs = man_rev_labs.merge(lab_count_info, on = 'loinc', how = 'left')

	fin_ls = []
	meas_sum_ls = []

	print(f"Loading files...")

	# Run all with merge ####
	curr_fn = f"{PHE_FP}/{curr_mcc_str}_{curr_phe}.tsv"

	# Read in the Phecode data
	curr_dat = pd.read_csv(curr_fn, sep='\t', dtype=str)

	###########################################
	#     If no patients for Phecode BAIL     #
	###########################################
	if len(curr_dat) == 0:
			# Save summary of data!
			meas_sum_ls.append([curr_phe, 'NA', 'NA', 'NA',
													'no disease records', 'no disease records', 
													'no disease records', 'no disease records',
													'no disease records', 'no disease records', 
													'no disease records', 'no disease records',
													'no disease records', 'no disease records',
													'no disease records', 'no disease records', 
													'no disease records'])

			out_fn = f"{PAIR_DIR}/{curr_phe}_no_disease_records.tsv"

			with open(out_fn, 'w') as outfile:
					outfile.write(f'No lab results found for {curr_phe}')

			sys.exit()



	curr_dat = curr_dat.loc[curr_dat.iloc[:, 1] == 'True', :]
	curr_dat.columns = ['pat_id', 'status']
	curr_dat['diag_full_code'] = curr_phe

	# For now we just care about the patient ID because there will be different 
	# Phecodes codes in the file but the patient should only show up once.
	de_dupe = curr_dat.drop_duplicates(['pat_id'], keep='first')

	curr_dis = de_dupe.copy(deep=True)

	print(f"Starting to look for pairs, summary data is in\n\t{SUMMARY_FP}")
	pbar = tqdm(loinc_ls, total=len(loinc_ls))
	for curr_loinc in pbar:

			# Could be multiple files for this LOINC code so process them both
			file_ls = glob.glob(f"{LAB_FP}/{curr_loinc}*")
			for curr_lab_fn in file_ls:
					src_org = man_rev_labs.loc[man_rev_labs['loinc'] == curr_loinc, 
																'src'].to_list()[0]
					
					pbar.set_description(f"{curr_phe} | {curr_loinc} | {src_org}")

					suffix = 'single_thread'

					# Read in the lab data
					curr_lab = pd.read_csv(curr_lab_fn, names = LAB_COLS, 
														index_col = False, quoting = csv.QUOTE_NONE)

	###########################################
	#  If no lab results for LOINC code BAIL  #
	###########################################
					if len(curr_lab) == 0:
							# Grab summary of data!
							nrow = 0
							n_pats = 0
							use_n = 0
							no_use_n = 0
							case_n = 0
							con_n = 0
							non_null = 0
							n_vals_0 = 0
							n_vals_non_0 = 0
							n_unique = 0
							curr_val = 0
							n_cat_with_value = 0
							curr_val_con = 0
							test_type_dict = {}


							meas_sum_ls.append([curr_phe, curr_loinc, suffix, src_org,
																	nrow, n_pats, use_n, no_use_n,
																	case_n, con_n, test_type_dict, n_vals_0, 
																	n_vals_non_0,	n_unique, curr_val, 
																	n_cat_with_value, curr_val_con])

							out_fn = f"{PAIR_DIR}/{curr_phe}_{src_org}_{curr_loinc}_{suffix}.tsv"

							with open(out_fn, 'w') as outfile:
									outfile.write(f'No lab results found for {curr_lab_fn}')

							continue

					curr_lab = curr_lab.applymap(lambda x: str(x).lstrip('"').rstrip('"'))

					curr_lab.loc[:, 'lab_date'] = pd.to_datetime(curr_lab.loc[:, 
																															 'lab_date'], 
																															 format="%Y%m%d")

					# Rename some cols to prep for merging with diags
					curr_lab = curr_lab.rename(columns={'code': 'lab_code',
																							'derived_by_TriNetX': 'lab_derived_by_tri',
																							'source_id': 'lab_source_id',
																							'test_type': 'lab_test_type'
																							})

					# Grep commands to pull each LOINC weren't perfect, so when pulling
					# 587-6 it also picked up 26587-6 and 42587-6. So here filter all
					# the wrong ones out.
					curr_lab = curr_lab.loc[curr_lab['lab_code'] == curr_loinc, :]

					# For cat limit to Positive and Negative (drop Unknown and other odd responses)
					curr_lab = curr_lab.loc[((curr_lab['lab_result_text'] == 'Negative') |
																	(curr_lab['lab_result_text'] == 'Positive')), :]

					# Merge in diagnosis information for each lab test
					# Mix where 'diag_date' (diagnosis date) is NA are controls!
					# Mix where 'lab_date' is before 'diag_date' is useful case
					# Mix where no 'lab_date' before 'diag_date' not useful
					# We only ran earliest date for cases for the Phecode
					# so controls are not in curr_dis. However, upon this merge
					# all the non-cases (controls) have a NA for diag_date
					# So it still works.
					mix = curr_lab.merge(curr_dis, on='pat_id', how='left')

	##############################################
	#  If no patients with both lab and phecode  #
	##############################################
					# Don't process files that have no results
					if len(mix) == 0:

							# Grab summary of data!
							nrow = 0
							n_pats = 0
							use_n = 0
							no_use_n = 0
							case_n = 0
							con_n = 0
							non_null = 0
							n_vals_0 = 0
							n_vals_non_0 = 0
							n_unique = 0
							curr_val = 0
							n_cat_with_value = 0
							curr_val_con = 0
							test_type_dict = {}

							meas_sum_ls.append([curr_phe, curr_loinc, suffix, src_org,
																	nrow, n_pats, use_n, no_use_n,
																	case_n, con_n, test_type_dict, n_vals_0, 
																	n_vals_non_0, n_unique, curr_val, 
																	n_cat_with_value, curr_val_con])

							out_fn = f"{PAIR_DIR}/{curr_phe}_{src_org}_{curr_loinc}_{suffix}.tsv"

							with open(out_fn, 'w') as outfile:
									outfile.write(f'No results after merging labs with disease {curr_lab_fn}')

							continue



					mix = mix.sort_values('pat_id')

					# People with no Phecode 
					cons = mix.loc[mix['status'].isna(), :]

					# Take the latest test result
					cons = cons.sort_values(['pat_id', 'lab_date'],
																	ascending=[False, False]).drop_duplicates(
																		['pat_id'])

					# Grab the cases (the ones that have a valid 'date' which is the 
					# diag date)
					cases = mix.loc[~mix['status'].isna(), :]

					# List of all people with the Phecode!
					all_case_ls = cases['pat_id'].unique().tolist()

					# List of people with test result before diagnosis
					good_case_ls = cases['pat_id'].unique().tolist()

					# People that don't have a test result before diag
					bad_case_ls = list(set(all_case_ls).difference(set(good_case_ls)))

					# Sort within each patient so the latest test (closest to diag) is at 
					# top
					cases = cases.sort_values(['pat_id', 'lab_date'], 
															 ascending=[False, False])

					# Now drop all dupes leaving only the latest test (before diagnosis) 
					# result
					cases = cases.drop_duplicates(['pat_id'], keep='first')

					cons['use'] = True
					cons['is_case'] = False

					cases['use'] = True
					cases['is_case'] = True

					cases = cases.loc[:, ['pat_id', 'use', 'is_case', 'lab_code', 
													 'diag_full_code', 'lab_date', 'lab_result_num', 
													 'lab_result_text', 'lab_test_type', 
													 'lab_derived_by_tri', 'lab_source_id', 
													 'code_system']]

					cons = cons.loc[:, ['pat_id', 'use', 'is_case', 'lab_code', 
													 'diag_full_code', 'lab_date', 'lab_result_num', 
													 'lab_result_text', 'lab_test_type', 
													 'lab_derived_by_tri', 'lab_source_id', 
													 'code_system']]

					fin_mix = pd.concat([cases, cons])

	######################################################
	#  If no cases or controls (shouldn't hit here) BAIL #
	######################################################
					if len(fin_mix) == 0:
							# Grab summary of data!
							nrow = 0
							n_pats = 0
							use_n = 0
							no_use_n = 0
							case_n = 0
							con_n = 0
							non_null = 0
							n_vals_0 = 0
							n_vals_non_0 = 0
							n_unique = 0
							curr_val = 0
							n_cat_with_value = 0
							curr_val_con = 0
							test_type_dict = {}

							meas_sum_ls.append([curr_phe, curr_loinc, suffix, src_org,
																	nrow, n_pats, use_n, no_use_n, case_n, con_n, 
																	test_type_dict, n_vals_0, n_vals_non_0,
																	n_unique, curr_val, n_cat_with_value, 
																	curr_val_con])

							out_fn = f"{PAIR_DIR}/{curr_mcc_str}_{curr_phe}_{src_org}_{curr_loinc}_{suffix}.tsv"
							with open(out_fn, 'w') as outfile:
									outfile.write(f'No results after processing merged labs with disease {curr_lab_fn}')
							continue

					# Grab summary of data!
					nrow = len(fin_mix)
					n_pats = len(fin_mix.loc[:, 'pat_id'].unique().tolist())
					use_n = len(fin_mix.loc[fin_mix['use'] == True, 
														 'pat_id'].unique().tolist())
					
					no_use_n = len(bad_case_ls)

					use_df = fin_mix.loc[fin_mix['use'] == True, :]

					case_n = len(use_df.loc[use_df['is_case'] == True, 
														 'pat_id'].unique().tolist())
					con_n = len(use_df.loc[use_df['is_case'] == False, 
														'pat_id'].unique().tolist())

					test_type_dict = use_df['lab_test_type'].value_counts().to_dict()

					non_null = use_df[use_df['lab_result_num'].notnull()]
					n_vals_0 = use_df.loc[((use_df['lab_result_num'] == 0.0) |
																(use_df['lab_result_num'] == '')), :].shape[0]

					n_vals_non_0 = use_df.loc[((use_df['lab_result_num'] != 0.0) &
																		(use_df['lab_result_num'] != '')),
																		:].shape[0]

					n_unique = len(non_null['lab_result_num'].unique())

					curr_val = use_df['lab_result_num'].value_counts(dropna = False
																											).to_dict()

					n_cat_with_value = len(use_df.loc[((use_df['lab_result_text'].notnull()) &
																						(use_df['lab_result_text'] != '')),
																						  'pat_id'].unique().tolist())
					
					curr_val_con = use_df['lab_result_text'].value_counts(dropna = False).to_dict()

					meas_sum_ls.append([curr_phe, curr_loinc, suffix, src_org,
															nrow, n_pats, use_n, no_use_n, case_n, con_n, 
															test_type_dict, n_vals_0, n_vals_non_0,
															n_unique, curr_val, n_cat_with_value, 
															curr_val_con])

					fin_mix['phecode'] = curr_phe
					out_fn = f"{PAIR_DIR}/phe_{curr_phe}_{src_org}_{curr_loinc}_{suffix}.tsv"
					fin_mix.to_csv(out_fn, index=False, sep="\t")

	new_meas = pd.DataFrame(meas_sum_ls)

	new_meas.columns = ['dis', 'loinc_test', 'lab_suffix', 'org', 'nrow', 
										 'uniq_pats', 'n_to_use', 'n_to_skip',
											'case_n', 'con_n', 'test_type',
											'n_val_0', 'n_vals_non_0',
											'num_unique', 'num_values',
											'cat_n_values', 'cat_values']
	
	new_meas.to_csv(SUMMARY_FP, sep='\t', index = False)


	log_message(f'{dt()} Finished processing Phecode: {curr_phe}', LOG_FP)

if __name__ == '__main__':
  main()