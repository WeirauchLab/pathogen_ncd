# Pathogens and Non-communicable Human Disease Survey
[![DOI](https://zenodo.org/badge/688303993.svg)](https://zenodo.org/badge/latestdoi/688303993)

Analysis code to complement Lape, _et al._ "After the Infection: A Survey of
Pathogens and Non-communicable Human Disease" (2023). See [below](#how-to-cite)
for citation information.

This code is made available along with explanatory flowcharts to enable
replication of the results reported in the associated manuscript.
[UK Biobank][ukb] data and [TriNetX][] data must be obtained from the
respective organizations.

## Abstract

> There are many well-established relationships between pathogens and human
> disease, but far fewer when focusing on non-communicable diseases (NCDs). We
> leverage data from The UK Biobank and TriNetX to perform a systematic survey
> across 20 pathogens and 426 diseases, focused primarily on NCDs. To this end,
> we assess association between disease status and infection history proxies. We
> identify 206 pathogen-disease pairs that replicate in both cohorts. We
> replicate many established relationships, including Helicobacter pylori with
> several gastroenterological diseases, and connections between Epstein-Barr
> virus with multiple sclerosis and lupus. Overall, our approach identified
> evidence of association for 15 of the pathogens and 96 distinct diseases,
> including a currently controversial link between human cytomegalovirus (CMV)
> and ulcerative colitis (UC). We validate this connection through two
> orthogonal analyses, revealing increased CMV gene expression in UC patients
> and enrichment for UC genetic risk signal near human genes that have altered
> expression upon CMV infection. Collectively, these results form a foundation
> for future investigations into mechanistic roles played by pathogens in
> disease.


## General Notes

All patient identifiers are generic and don't correspond to actual identifiers
from either UK BioBank (UKB) or TriNetX (TNX). They are present just to make it
easier to follow what input and output files will look like.

## Software Versions

### Code languages employed

* R v4.2.2
* Python v3.7.8

### R Libraries

* MASS v7.3-58.1
* performance v0.10.2
* logistf v1.24.1
* dplyr v1.1.0
* data.table v1.14.8
* openxlsx v4.2.5.2
* readxl v1.4.2
* stringr v1.5.0
* glue v1.6.2
* DT v0.27

### Python Libraries

* numpy  v1.22.3
* pandas v1.4.2
* scipy  v1.8.0
* sklearn  v1.0.2
* statsmodels v0.13.2
* matplotlib v3.7.1
* seaborn  v0.11.2
* tabulate v0.8.9
* tqdm v4.64.0
* xlrd v2.0.1

### Other 3rd party software

* [GNU Parallel][parallel] v20220122

        Tange, O. (2022, January 22). GNU Parallel 20220122 ('20 years').
        Zenodo. https://doi.org/10.5281/zenodo.5893336

# Flowcharts for main analysis using diagnoses and serology data

## Key for Diagrams

<table class="tg">
<thead>
  <tr valign-"top">
    <th>Color</th>
    <th>Shape</th>
  </tr>
</thead>
<tbody>
  <tr valign="top">
    <td class="tg-c3ow"><img src="./flow_diagram_of_code/color_key.jpg" alt="Color Key" width="150"/></td>
    <td class="tg-c3ow"><img src="./flow_diagram_of_code/shape_key.jpg" alt="Shape Key" width="250"/></td>
  </tr>
</tbody>
</table>

## Data Prep

### UK Biobank Data

<img src="./flow_diagram_of_code/ukb_data_prep.SVG" alt="UKB Data Prep" width="600"/>

---

### TriNetX Data

<img src="./flow_diagram_of_code/tnx_data_prep.SVG" alt="TNX Data Prep" width="600"/>


## Analysis

### UK Biobank

<img src="./flow_diagram_of_code/ukb_analysis.SVG" alt="UKB analysis" width="600"/>

---

#### Permutations and Empirical P-values

<img src="./flow_diagram_of_code/ukb_perm_1.SVG" alt="UKB Permutations" width="600"/>
<br />
<img src="./flow_diagram_of_code/ukb_perm_2.SVG" alt="UKB Permutations Continued" width="600"/>

---

### TriNetX

<img src="./flow_diagram_of_code/tnx_analysis.SVG" alt="TNX Data Prep" width="600"/>

## Results Post-processing

<img src="./flow_diagram_of_code/post_proc.SVG" alt="TNX Data Prep" width="600"/>

## How to Cite

Code from this repository may be cited as:

    Michael Lape, _et al_.(2023). WeirauchLab/pathogen_ncd: Preprint release
    (preprint). Zenodo. https://doi.org/10.5281/zenodo.8423556

The associated manuscript is pending publication. In the meantime, you may
cite [the preprint on medRxiv][medrxiv]:

    After the Infection: A Survey of Pathogens and Non-communicable Human Disease
    Michael Lape, _et al. medRxiv 2023.09.14.23295428;
    doi: https://doi.org/10.1101/2023.09.14.23295428 


## Feedback

Please contact [Dr. Matthew Weirauch][matt] via email with any questions or
concerns.

## Contributors

| Name       | Institution              | Remarks
|------------|--------------------------|------------------
| Mike Lape  | University of Cincinnati | _primary author_


## License

Source code is &copy;2023 Cincinnati Children's Hospital Medical Center and
Mike Lape.

Released under the terms of the GNU General Public License, Version 3. See
[`LICENSE.txt`](LICENSE.txt)

[ukb]: https://trinetx.com
[trinetx]: https://www.ukbiobank.ac.uk
[parallel]: https://www.gnu.org/software/parallel
[matt]: mailto:Matthew.Weirauch@cchmc.org
[medrxiv]: https://doi.org/10.1101/2023.09.14.23295428
