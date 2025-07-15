"""
Transform supplementary data spreadsheets into the ones for the web site

Authors:  Mike Lape, PhD; Kevin Ernst
Date:     3 January 2025
License:  GPL; see LICENSE.txt in the top-level directory

© 2025 Cincinnati Children's Hospital Medical Center and the author(s)
"""
import os
import sys
import logging
import pandas as pd

from .config import use_config

log = logging.getLogger(__name__)

if os.getenv('DEBUG') or os.getenv('DEBUG_TRANSFORM'):
    log.setLevel(logging.DEBUG)

# coerce these columns to numerical values
COERCE_NUMERIC = ['UKB FDR', 'UKB OR', 'TNX FDR', 'TNX OR']

# FIXME: this duplicates mappings in `conf/data.toml`
RENAME_COLUMNS = {
    # ICD
    'Disease': 'Disease',
    'ICD10': 'ICD10',
    'Pathogen': 'Pathogen',
    'Pair is Associated': 'Pair is Assoc?',
    'Standard Level': 'Std. Lev.',
    'UKB adj p': 'UKB FDR',
    'TNX adj p': 'TNX FDR',
    'UKB OR': 'UKB OR',
    'TNX OR': 'TNX OR',
    # PHE
    'Disease_Description': 'Disease',
    'phecode': 'Phecode',
    'pair_is_associated': 'Pair is Assoc?',
    'std_lev': 'Std. Lev.',
    'ukb_per_dis_bh_fdr_corr_nom_p': 'UKB FDR',
    'tnx_per_dis_bh_fdr_corr_p': 'TNX FDR',
    'ukb_OR': 'UKB OR',
    'tnx_OR': 'TNX OR',
}

# top level keys are column name; sub-dicts are the replacement maps
REPLACE_VALUES = {
    'Pathogen': {
        'bkv': 'BKV',
        'chlam': 'C. trach.',
        'c_trach': 'C. trach.',
        'C. trachomatis': 'C. trach.',
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
        'hiv': 'HIV',
    },
    'Std. Lev.': {
        'unk': 'Unknown',
        'exp_neg': 'Exp. Neg.',
        'Exp. Negative': 'Exp. Neg.',
    },
}

# drop entire rows if any of these columns contain the listed values
# (ref: GitLab mike/pathogen_ncd#50)
DROP_VALUES = {
    'Std. Lev.': ['NA'],
}


def coerce_numeric(col):
    cname = col.name
    # Fill in any empty TNX results, just pairs where replication didn't need
    # to be attempted, with -1 as a placeholder
    if cname.startswith("TNX"):
        log.debug(f"Filling column '{cname}' with -1 for n/a values")
        col.fillna(-1, inplace=True)

    # Convert all numerical value columns from str to float - apparently
    # pd.to_numeric is more robust than as_type(float)
    col = pd.to_numeric(col)  #, errors='coerce')

    # Round ORs to 2 decimal points
    if cname.endswith("OR"):
        if col.dtype in ['float64', 'int64']:
            log.debug(f"Rounding column '{cname}' to 2 decimal places")
            col = col.round(2)
        else:
            raise ValueError(f"Column '{cname}' contains non-numeric values.")

    # Put FDRs in Sci notation with 1 decimal point
    if cname.endswith("FDR"):
        if col.dtype in ['float64', 'int64']:
            col = col.map(lambda x: f'{x:.1e}')
        else:
            raise ValueError(f"Column '{cname}' contains non-numeric values.")

    # Finally, replace all remaining placeholder values
    if cname.startswith("TNX"):
        log.debug(f"Replacing -1's in column '{cname}' with 'n/a'")
        col = col.replace(-1, 'n/a').replace('-1.0e+00', 'n/a')

    return col


def write_out(df, outbasename):
    df.to_excel(f"{outbasename}.xlsx", index=False)
    df.to_csv(f"{outbasename}.tsv", index=False, sep="\t")


@use_config
def transform(source, config=None):
    xls = config['data']['datasources'][source]['infilename']
    sheetname = config['data']['datasources'][source]['sheetname']

    df = pd.read_excel(xls, sheet_name=sheetname, dtype={'phecode': 'string'})
    # FIXME: mike/pathogen_ncd#50
    if source == 'PHE':
        df['std_lev'] = df['std_lev'].fillna('NA')

    df.rename(columns=RENAME_COLUMNS, inplace=True)

    for column in REPLACE_VALUES.keys():
        newcol = df[column].replace(REPLACE_VALUES[column])
        df[column] = newcol

    for column in DROP_VALUES.keys():
        df = df[~df[column].isin(DROP_VALUES[column])]

    for column in COERCE_NUMERIC:
        newcol = coerce_numeric(df[column])
        df[column] = newcol

    outbasename = os.path.join(
        config['site']['deploydatadir'],
        config['data']['datasources'][source]['outbasefilename']
    )

    # select only the subset of columns specified in `conf/data.toml`
    cutcols = [x['name'] for x in
               config['data']['datasources'][source]['columns']]
    df = df[cutcols]

    write_out(df, outbasename)
    return df


def cross_check(icd, phe):
    """
    Make sure there are no pathogens in one workbook that aren't in the other
    """
    in_icd_not_phe = set(icd['Pathogen'].unique().tolist()).difference(
            set(phe['Pathogen'].unique().tolist()))
    if len(in_icd_not_phe) > 0:
        print(f"Pathogens in PHE set not in ICD: {in_icd_not_phe}",
              file=sys.stderr)
        return 1

    in_phe_not_icd = set(phe['Pathogen'].unique().tolist()).difference(
          set(icd['Pathogen'].unique().tolist()))
    if len(in_phe_not_icd) > 0:
        print(f"Pathogens in ICD set not in PHE: {in_phe_not_icd}",
              file=sys.stderr)
        return 1


if __name__ == '__main__':
    icd = transform('ICD')
    phe = transform('PHE')
    sys.exit(cross_check(icd, phe))
