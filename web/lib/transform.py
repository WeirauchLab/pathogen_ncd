"""
Transform supplemental data spreadsheets into the ones for the web site

Author:  Mike Lape, PhD.
Date:    3 January 2025
"""
import os
import pandas as pd

from .config import use_config

# Convert and fix numerical columns
NUM_COLS = ['UKB FDR', 'UKB OR', 'TNX FDR', 'TNX OR']

# Update Pathogen names
PATHOGEN_MAP = {
    'bkv': 'BKV',
    'chlam': 'C. trach.',
    'c_trach': 'C. trach.',
    'cmv': 'CMV', 
    'ebv': 'EBV',
    'hbv': 'HBV',
    'hcv': 'HCV',
    'hhv6': 'HHV-6',
    'hhv_6': 'HHV-6',
    'hhv7': 'HHV-7',
    'hhv_7': 'HHV-7',
    'hpv16': 'HPV-16',
    'hpv_16': 'HPV-16',    
    'hpv18': 'HPV-18',
    'hpv_18': 'HPV-18',
    'hpylori': 'H. pylori',
    'h_pylor': 'H. pylori',
    'hsv1': 'HSV-1',
    'hsv_1': 'HSV-1',
    'hsv2': 'HSV-2',
    'hsv_2': 'HSV-2',
    'htlv': 'HTLV-1',
    'jcv': 'JCV',
    'kshv': 'KSHV',
    'mcv': 'MCV',
    'tox': 'T. gondii',
    't_gond': 'T. gondii',    
    'vzv': 'VZV',
    'hiv': 'HIV'
}

# Updated standard level column values
STD_REP_MAP = {
    'unk': 'Unknown',
    'exp_neg': 'Exp. Neg.'
}


@use_config
def transform_icd(config=None):
    xls = config['data']['datasources']['ICD10']['infilename']
    outxls = config['data']['datasources']['ICD10']['outfilename']
    sheet_name = config['data']['datasources']['ICD10']['sheetname']
    # FIXME: likely some duplication with helpers.data and helpers.site here
    outpath = os.path.join(config['site']['deploydatadir'], outxls)
    icd = pd.read_excel(xls, sheet_name=sheet_name, dtype=str)

    icd_col_map = {
        'Disease': 'Disease',
        'ICD10': 'ICD10',
        'Pathogen': 'Pathogen',
        'Pair is Associated': 'Pair is Assoc?',
        'Standard Level': 'Std. Lev.',
        'UKB adj p': 'UKB FDR',
        'TNX adj p': 'TNX FDR',
        'UKB OR': 'UKB OR',
        'TNX OR': 'TNX OR',
    }

    #icd = icd.loc[:, icd_col_map.keys()].copy()
    #icd.columns = icd_col_map.values()

    icd = icd.rename(columns=icd_col_map).copy(deep = True)


    # Fill in any empty TNX results, just pairs where
    # replication didn't need to be attempted, with -1 as
    # a placeholder
    icd[['TNX FDR', 'TNX OR']] = icd[['TNX FDR', 'TNX OR']].fillna(-1)

    # Convert all 4 value columns from str to float - 
    # apparently pd.to_numeric is more robust than as_type(float)
    for col in NUM_COLS:
        icd[col] = pd.to_numeric(icd[col], errors='coerce')

    # Round ORs to 2 decimal points
    icd[['UKB OR', 'TNX OR']] = icd[['UKB OR', 'TNX OR']].round(2)

    # Put FDRs in Sci notation with 1 decimal point
    if icd['UKB FDR'].dtype in ['float64', 'int64']:
        icd['UKB FDR'] = icd['UKB FDR'].map(lambda x: f'{x:.1e}')
    else:
        raise ValueError("UKB FDR column contains non-numeric values.")

    if icd['TNX FDR'].dtype in ['float64', 'int64']:
        icd['TNX FDR'] = icd['TNX FDR'].map(lambda x: f'{x:.1e}')
    else:
        raise ValueError("TNX FDR column contains non-numeric values.")

    # Finally, replace our placeholder with an empty string
    icd['TNX OR']  = icd['TNX OR'].replace(-1, '')
    icd['TNX FDR'] = icd['TNX FDR'].replace('-1.0e+00', '')

    icd.loc[:, 'Pathogen'] = \
        icd.loc[:, 'Pathogen'].replace(PATHOGEN_MAP)

    icd['Std. Lev.'] = icd['Std. Lev.'].replace(STD_REP_MAP)
    icd.to_excel(outpath, index = False)
    return icd


@use_config
def transform_phe(config=None):
    xls = config['data']['datasources']['PHE']['infilename']
    outxls = config['data']['datasources']['PHE']['outfilename']
    sheet_name = config['data']['datasources']['PHE']['sheetname']
    # FIXME: likely some duplication with helpers.data and helpers.site here
    outpath = os.path.join(config['site']['deploydatadir'], outxls)
    phe = pd.read_excel(xls, sheet_name=sheet_name, dtype=str)

    # map of original column names to desired ones
    phe_col_map = {
        'Disease_Description': 'Disease',
        'phecode': 'Phecode',
        'Pathogen': 'Pathogen',
        'pair_is_associated': 'Pair is Assoc?',
        'std_lev': 'Std. Lev.',
        'ukb_per_dis_bh_fdr_corr_nom_p': 'UKB FDR',
        'tnx_per_dis_bh_fdr_corr_p': 'TNX FDR',
        'ukb_OR': 'UKB OR',
        'tnx_OR': 'TNX OR'
    }

    #phe = phe.loc[:, phe_col_map.keys()].copy()
    #phe.columns = phe_col_map.values()

    phe = phe.rename(columns=phe_col_map).copy(deep = True)


    # Fill in any empty TNX results, just pairs where
    # replication didn't need to be attempted, with -1 as
    # a placeholder
    phe[['TNX FDR', 'TNX OR']] = phe[['TNX FDR', 'TNX OR']].fillna(-1)

    # Convert all 4 value columns from str to float - 
    # apparently pd.to_numeric is more robust than as_type(float)
    for col in NUM_COLS:
        phe[col] = pd.to_numeric(phe[col], errors='coerce')

    # Round ORs to 2 decimal points
    phe.loc[: , ['UKB OR', 'TNX OR']] = \
        phe.loc[: , ['UKB OR', 'TNX OR']].round(2)

    # Put FDRs in scientific notation with 1 decimal point
    if phe['UKB FDR'].dtype in ['float64', 'int64']:
        phe['UKB FDR'] = phe['UKB FDR'].map(lambda x: f'{x:.1e}')
    else:
        raise ValueError("UKB FDR column contains non-numeric values.")

    if phe['TNX FDR'].dtype in ['float64', 'int64']:
        phe['TNX FDR'] = phe['TNX FDR'].map(lambda x: f'{x:.1e}')
    else:
        raise ValueError("TNX FDR column contains non-numeric values.")

    # Finally, replace our placeholder with an empty string
    phe['TNX OR']  = phe['TNX OR'].replace(-1, '')
    phe['TNX FDR'] = phe['TNX FDR'].replace('-1.0e+00', '')

    phe.loc[:, 'Pathogen'] = \
        phe.loc[:, 'Pathogen'].replace(PATHOGEN_MAP)

    phe['Std. Lev.'] = phe['Std. Lev.'].replace(STD_REP_MAP)
    phe.to_excel(outpath, index=False)
    return phe


def cross_check(icd, phe):
    """
    Make sure there are no pathogens in one workbook that aren't in the other
    """
    assert len(set(icd['Pathogen'].unique().tolist())
            .difference(set(phe['Pathogen'].unique().tolist()))) == 0
    assert len(set(phe['Pathogen'].unique().tolist())
          .difference(set(icd['Pathogen'].unique().tolist()))) == 0


if __name__ == '__main__':
    icd = transform_icd()
    phe = transform_phe()
    cross_check(icd, phe)
