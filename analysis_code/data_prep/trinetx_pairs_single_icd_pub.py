import csv
import glob
from tqdm import tqdm
import numpy as np
import pandas as pd
import argparse
import os
import sys

import warnings
warnings.simplefilter(action ='ignore', category=FutureWarning)

# Get ICD code to work on from the command line from command line
parser = argparse.ArgumentParser(description = 'Script to generate TriNetX cohorts for dis-org pairs')
parser.add_argument('-i','--icd', help='Single ICD10 code to find pairs for', required = True)
args = vars(parser.parse_args())

curr_icd = args['icd']
print(f"Starting work on {curr_icd}")

# Create the list of ICDs and LOINC codes
BASE_DIR = "***REMOVED***/other/trinetx"
meta_dir = BASE_DIR
icd_dir = f"{BASE_DIR}/new_dataset/icd_data"
lab_dir = f"{BASE_DIR}/new_dataset/lab_data"
pair_dir = f"{BASE_DIR}/new_dataset/pair_data/{curr_icd}"

# Only consider labs we have more than 0 results for after our pre-processing steps
loincs = pd.read_csv(f"{meta_dir}/loincs_with_more_than_0_res_new_version.txt", sep = "\t")
loinc_ls = loincs['loinc'].drop_duplicates().tolist()

# Run full loop ####
summary_fn = f"{pair_dir}/{curr_icd}_summaries.tsv"

if not os.path.exists(pair_dir):
    print(f"Creating output directory: {pair_dir}")
    os.makedirs(pair_dir)
else:
    print(f"Using existing output directory: {pair_dir}")

diag_cols = ['pat_id', 'enc_id', 'vocab', 'full_code',
             'principal_diag_indicator', 'admit_diag',
             'reason_for_visit', 'date', 'derived_by_tri',
             'source_id', 'icd_3_char', 'icd_sub_cat']

dtype_dict = {'pat_id': str, 'enc_id': str, 'vocab': str, 'full_code': str,
              'principal_diag_indicator': str, 'admit_diag': str,
              'reason_for_visit': str, 'date': str,
              'derived_by_tri': str, 'source_id': str, 'icd_3_char': str,
              'icd_sub_cat': str, }

# Read in the labs data we need.
fin_labs = pd.read_excel(f"{BASE_DIR}/new_dataset/lab_test_data_analysis_latest_manual_review.xlsx")
fin_labs = fin_labs.loc[fin_labs['good'] == 'y', :]

# Read in the labs data we need.
lab_info = pd.read_csv(f"{meta_dir}/clean_loinc_counts.tsv", sep='\t')
# Drop outdated count column
lab_info = lab_info.loc[:, lab_info.columns != 'count']

# Merge in that info
fin_labs = fin_labs.merge(lab_info, on = 'loinc', how = 'left')


lab_cols = ['pat_id', 'enc_id', 'code_system', 'code',
            'lab_date', 'lab_result_num',
            'lab_result_text', 'test_type',
            'derived_by_TriNetX', 'source_id']

fin_ls = []
meas_sum_ls = []

print(f"Loading files...")

# Run all with merge ####
curr_fn = f"{icd_dir}/{curr_icd}_only.csv"

# Read in the diagnoses
curr_dat = pd.read_csv(curr_fn, names=diag_cols, dtype=dtype_dict)
curr_dat.loc[:, 'date'] = pd.to_datetime(curr_dat.loc[:, 'date'], format="%Y%m%d")
curr_dat = curr_dat.loc[curr_dat['source_id'] == 'EHR', :]

# If we have no disease data for ICD10 code write error message out to file and exit
if len(curr_dat) == 0:
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

    meas_sum_ls.append([curr_icd, 'NA', 'NA', 'NA',
                        'no disease records', 'no disease records', 'no disease records', 'no disease records',
                        'no disease records', 'no disease records', 'no disease records',
                        'no disease records', 'no disease records',
                        'no disease records', 'no disease records', 'no disease records', 'no disease records'])

    out_fn = f"{pair_dir}/{curr_icd}_no_disease_records.tsv"

    with open(out_fn, 'w') as outfile:
        outfile.write(f'No lab results found for {curr_icd}')

    sys.exit()

# The 3 char ICD10 got screwed up and is comma sep with sub code
if sum(curr_dat.loc[:, 'icd_3_char'].str.contains(',')) > 0:
    curr_dat.loc[:, 'icd_3_char_tmp'] = curr_dat.loc[:, 'icd_3_char'].str.split(',', expand = True).iloc[:, 0]
    curr_dat.loc[:, 'icd_sub_cat'] = curr_dat.loc[:, 'icd_3_char'].str.split(',', expand = True).iloc[:, 1]
    curr_dat.loc[:, 'icd_3_char'] = curr_dat.loc[:, 'icd_3_char_tmp']
    curr_dat = curr_dat.drop('icd_3_char_tmp', axis = 1)


# Sorts oldest diagnosis at top so we can just drop dupes at that point
curr_dat = curr_dat.sort_values(['pat_id', 'icd_3_char', 'date'], ascending = [True, True, True])

# For now we just care about the 3-char diagnosis.
de_dupe = curr_dat.drop_duplicates(['pat_id', 'icd_3_char'], keep='first')
de_dupe = de_dupe.drop('enc_id', axis=1)

curr_dis = de_dupe.copy(deep=True)

# Rename some columns in prep of merging with lab tests
curr_dis = curr_dis.rename(columns={'vocab': 'diag_vocab',
                                    'full_code': 'diag_full_code',
                                    'date': 'diag_date',
                                    'derived_by_tri': 'diag_derived_by_tri',
                                    'source_id': 'diag_source_id'
                                    })
print(f"Starting to look for pairs, summary data is in\n\t{summary_fn}")
pbar = tqdm(loinc_ls, total=len(loinc_ls))
for curr_loinc in pbar:
    # Could be multiple files for this LOINC code so process them both
    for curr_lab_fn in glob.glob(f"{lab_dir}/{curr_loinc}*"):
        src_org = fin_labs.loc[fin_labs['loinc'] == curr_loinc, 'src'].to_list()[0]
        pbar.set_description(f"{curr_icd} | {curr_loinc} | {src_org}")

        # This is an artifact of early processing where files were named differently, they should all have a suffix
        # of 'single_thread' now.
        if '_only.csv' in curr_lab_fn:
            suffix = 'only'
        else:
            suffix = 'single_thread'

        curr_lab = pd.read_csv(curr_lab_fn, names=lab_cols, index_col=False,
                               quoting=csv.QUOTE_NONE)

        # If we have no lab tests for that LOINC code, write results out and move on
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

            meas_sum_ls.append([curr_icd, curr_loinc, suffix, src_org,
                                nrow, n_pats, use_n, no_use_n,
                                case_n, con_n, test_type_dict, n_vals_0, n_vals_non_0,
                                n_unique, curr_val, n_cat_with_value, curr_val_con])

            out_fn = f"{pair_dir}/{curr_icd}_{src_org}_{curr_loinc}_{suffix}.tsv"

            with open(out_fn, 'w') as outfile:
                outfile.write(f'No lab results found for {curr_lab_fn}')

            continue

        curr_lab = curr_lab.applymap(lambda x: str(x).lstrip('"').rstrip('"'))

        curr_lab.loc[:, 'lab_date'] = pd.to_datetime(curr_lab.loc[:, 'lab_date'], format="%Y%m%d")

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

        # Apply some filters to the data
        is_cat = fin_labs.loc[fin_labs['loinc'] == curr_loinc, 'final_type'].iloc[0] == 'cat'

        # For cat limit to Positive and Negative (drop Unknown and other odd responses)

        curr_lab = curr_lab.loc[((curr_lab['lab_result_text'] == 'Negative') |
                                 (curr_lab['lab_result_text'] == 'Positive')), :]


        # Merge in diagnosis information for each lab test
        # Mix where 'diag_date' (diagnosis date) is NA are controls!
        # Mix where 'lab_date' is before 'diag_date' is useful case
        # Mix where no 'lab_date' before 'diag_date' not useful
        mix = curr_lab.merge(curr_dis, on='pat_id', how='left')

        # Don't process further if we don't have anybody with a diagnosis and this lab test
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

            meas_sum_ls.append([curr_icd, curr_loinc, suffix, src_org,
                                nrow, n_pats, use_n, no_use_n,
                                case_n, con_n, test_type_dict, n_vals_0, n_vals_non_0,
                                n_unique, curr_val, n_cat_with_value, curr_val_con])

            out_fn = f"{pair_dir}/{curr_icd}_{src_org}_{curr_loinc}_{suffix}.tsv"

            with open(out_fn, 'w') as outfile:
                outfile.write(f'No results after merging labs with disease {curr_lab_fn}')


            continue

        mix = mix.sort_values('pat_id')

        # People with no diagnosis - controls
        cons = mix.loc[mix['diag_date'].isna(), :]

        # Take the latest test result
        cons = cons.sort_values(['pat_id', 'lab_date'],
                                ascending=[False, False]).drop_duplicates(['pat_id'])

        # Grab the cases (the ones that have a valid 'date' which is the diag date)
        cases = mix.loc[~mix['diag_date'].isna(), :]

        # List of all people with a diagnosis!
        all_case_ls = cases['pat_id'].unique().tolist()

        # Only grab cases that have a lab test encounter before diagnosis date
        # And only keep those lab test encounters earlier than diagnosis date
        cases = cases.loc[cases['lab_date'] < cases['diag_date'], :]

        # List of people with test result before diagnosis
        good_case_ls = cases['pat_id'].unique().tolist()

        # People that don't have a test result before diag
        bad_case_ls = list(set(all_case_ls).difference(set(good_case_ls)))

        # Sort within each patient so the latest test (closest to diag) is at top
        cases = cases.sort_values(['pat_id', 'lab_date'], ascending=[False, False])

        # Now drop all dupes leaving only the latest test result before the diag
        cases = cases.drop_duplicates(['pat_id'], keep='first')

        cons['use'] = True
        cons['is_case'] = False

        cases['use'] = True
        cases['is_case'] = True

        cases = cases.loc[:, ['pat_id', 'use', 'is_case', 'lab_code', 'diag_full_code', 'icd_3_char',
                              'diag_date', 'lab_date', 'lab_result_num', 'lab_result_text',
                              'lab_test_type', 'lab_derived_by_tri', 'lab_source_id',
                              'code_system', 'diag_vocab', 'principal_diag_indicator',
                              'admit_diag', 'reason_for_visit', 'diag_derived_by_tri', 'diag_source_id']]

        cons = cons.loc[:, ['pat_id', 'use', 'is_case', 'lab_code', 'diag_full_code', 'icd_3_char',
                            'diag_date', 'lab_date', 'lab_result_num', 'lab_result_text',
                            'lab_test_type', 'lab_derived_by_tri', 'lab_source_id',
                            'code_system', 'diag_vocab', 'principal_diag_indicator',
                            'admit_diag', 'reason_for_visit', 'diag_derived_by_tri', 'diag_source_id']]

        # Bring cases and controls back together
        fin_mix = pd.concat([cases, cons])

        # If we went through that processing and have no results, write out warning message and move on
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

            meas_sum_ls.append([curr_icd, curr_loinc, suffix, src_org,
                                nrow, n_pats, use_n, no_use_n,
                                case_n, con_n, test_type_dict, n_vals_0, n_vals_non_0,
                                n_unique, curr_val, n_cat_with_value, curr_val_con])

            out_fn = f"{pair_dir}/{curr_icd}_{src_org}_{curr_loinc}_{suffix}.tsv"
            with open(out_fn, 'w') as outfile:
                outfile.write(f'No results after processing merged labs with disease {curr_lab_fn}')
            continue

        # If we got here we have good data, so let's grab summary data
        nrow = len(fin_mix)
        n_pats = len(fin_mix.loc[:, 'pat_id'].unique().tolist())
        use_n = len(fin_mix.loc[fin_mix['use'] == True, 'pat_id'].unique().tolist())
        no_use_n = len(bad_case_ls)

        use_df = fin_mix.loc[fin_mix['use'] == True, :]

        case_n = len(use_df.loc[use_df['is_case'] == True, 'pat_id'].unique().tolist())
        con_n = len(use_df.loc[use_df['is_case'] == False, 'pat_id'].unique().tolist())

        test_type_dict = use_df['lab_test_type'].value_counts().to_dict()

        # At this time we were still thinking about using the continuous lab tests, which is why we collect
        # this summary info for lab_result_num
        non_null = use_df[use_df['lab_result_num'].notnull()]
        n_vals_0 = use_df.loc[((use_df['lab_result_num'] == 0.0) |
                               (use_df['lab_result_num'] == '')), :].shape[0]

        n_vals_non_0 = use_df.loc[((use_df['lab_result_num'] != 0.0) &
                                   (use_df['lab_result_num'] != '')), :].shape[0]

        n_unique = len(non_null['lab_result_num'].unique())

        curr_val = use_df['lab_result_num'].value_counts(dropna=False).to_dict()

        n_cat_with_value = len(use_df.loc[((use_df['lab_result_text'].notnull()) &
                                           (use_df['lab_result_text'] != '')), 'pat_id'].unique().tolist())
        curr_val_con = use_df['lab_result_text'].value_counts(dropna=False).to_dict()


        # Add the summary of the data for this LOINC test to the list and move onto next
        meas_sum_ls.append([curr_icd, curr_loinc, suffix, src_org,
                            nrow, n_pats, use_n, no_use_n,
                            case_n, con_n, test_type_dict, n_vals_0, n_vals_non_0,
                            n_unique, curr_val, n_cat_with_value, curr_val_con])

        # Save the pair data out to file for later analysis
        out_fn = f"{pair_dir}/{curr_icd}_{src_org}_{curr_loinc}_{suffix}.tsv"
        fin_mix.to_csv(out_fn, index=False, sep="\t")

# Collect the summary data for all LOINC tests and write out to a file
new_meas = pd.DataFrame(meas_sum_ls)

new_meas.columns = ['dis', 'loinc_test', 'lab_suffix', 'org', 'nrow', 'uniq_pats', 'n_to_use', 'n_to_skip',
                    'case_n', 'con_n', 'test_type',
                    'n_val_0', 'n_vals_non_0',
                    'num_unique', 'num_values',
                    'cat_n_values', 'cat_values']
new_meas.to_csv(summary_fn, sep='\t', index = False)
