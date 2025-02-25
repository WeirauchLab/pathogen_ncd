#!/bin/bash

# Name:     geo_virtus_pipe_pub.sh
# Author:   Mike Lape
# Date:     2023
# Description:
#
#		Script to be used with submitArrayJobs 
#		[https://github.com/ernstki/submitArrayJobs] that will run VIRTUS on a 
#       single GSE ID whether single end or paired end. Then normalizes result
#		and outputs the normalized hit rates.
#
# 	Requirements:
#			geo_pipe_funcs_pub.sh 
#
#		Usage with sAJ:
#   	VAR1: Line with GSE ID, SRX ID, SRR ID, and possible SRR ID2 all space
#     	    separated
#   	VAR2: Disease abbreviation used in directory names, ms or sle, etc.
#



HOME="/data/pathogen_ncd"
SINGULARITY_HOME="${HOME}/singularity"


# set TRACE=1 in the environment to enable execution tracing
(( TRACE )) && set -x

# Capture the starttime
start=$(date +%s)

# Cutadapt requires a certain python version and my preferred is not it.
# Just to make sure nothing gets in the way, just purge all loaded modules.
module purge

# VIRTUS and cutadapt (installed on this version) needs python 
module load python3/3.7.8

# Required for fasterq-dump
module load sratoolkit/2.9.6.1

# cwltool needs these guys
module load singularity/3.7.0
module load nodejs

# Load in all of our functions!
source ./geo_pipe_funcs_pub.sh

# Tell Singularity where it can find container image caches (so we don't have 
# to go through the proxy)
export SINGULARITYENV_TMPDIR="${SINGULARITY_HOME}"
export SINGULARITY_CACHEDIR="${SINGULARITY_HOME}"
export CWL_SINGULARITY_CACHE="${SINGULARITY_HOME}"

# Resources to give to VIRTUS
# RAM in GB
RAM="150"
CORES="16"

CURR_DIS="VAR2"

# VIRTUS executable path
VIRT_SE="${HOME}/virtus/code/VIRTUS/workflow/VIRTUS.SE.cwl"
VIRT_PE="${HOME}/virtus/code/VIRTUS/workflow/VIRTUS.PE.cwl"

# UKB orgs + Human index file
STAR_VIR="${HOME}/virtus/procd/indices/manual/STAR_index_virus"
STAR_HUMAN="${HOME}/virtus/procd/indices/local/STAR_index_human"
SALMON_IDX="${HOME}/virtus/procd/indices/local/salmon_index_human"

# Set result directory
RES_DIR="${HOME}/virtus/results/${CURR_DIS}"

# Set data directory (where to store temp files)
WORK_DIR="${HOME}/virtus/data/${CURR_DIS}"

# Logging directory (where to dump log files) - plan to place these right next 
# to where LSF logs should go.
LOG_DIR="${HOME}/virtus/code/${CURR_DIS}/logs"

# Set scratch dir (where we store fastq files from previously failed runs
BASE_SCRATCH_DIR="${HOME}/virtus/scratch/${CURR_DIS}_files"

# Mode of sequencing of file(s) of interest (SE by default PE if paired-end)
MODE="SE"

# Table to convert NC IDs to organism names
CONV_TAB="${HOME}/virtus/procd/ncbi_id_conv_table.txt"

# Maximum number of times to try to re-run fasterq-dump to download the fastq
# file for analysis.
MAX_DL_RETRIES=5

# Grab out input
line="VAR1"

echo -e "$(ds) Reading input..."

# Split up our input line
set -- $(awk  '{print $1, $2, $3, $4}' <<< "${line}")

# Assign all the parts to proper variables
gse=$1
srx=$2
srr=$3
srr2=$4

# Setup the environment
WORK_DIR="${WORK_DIR}/${gse}/${srr}"
RES_DIR="${RES_DIR}/${gse}"
SCRATCH_DIR="${BASE_SCRATCH_DIR}/${gse}"
SCRATCH_SRR_DIR="${SCRATCH_DIR}/${srr}"
virtus_out_dir="${WORK_DIR}/out"
virtus_tmp_dir="${WORK_DIR}/tmp"

# Verify our output dirs exist before trying to create files.
if ! [[ -z "${RES_DIR}" ]]; then
	mkdir -pv "${RES_DIR}"
fi
if ! [[ -z "${WORK_DIR}" ]]; then
	mkdir -pv "${WORK_DIR}"
fi
if ! [[ -z  "${LOG_DIR}" ]]; then
	mkdir -pv "${LOG_DIR}"
fi
if ! [[ -z "${SCRATCH_DIR}" ]]; then
	mkdir -pv "${SCRATCH_DIR}"
fi
if ! [[ -z  "${SCRATCH_SRR_DIR}" ]]; then
	mkdir -pv "${SCRATCH_SRR_DIR}"
fi
if ! [[ -z  "${virtus_out_dir}" ]]; then
	mkdir -pv "${virtus_out_dir}"
fi
if ! [[ -z  "${virtus_tmp_dir}" ]]; then
	mkdir -pv "${virtus_tmp_dir}"
fi

# Setup output and tmp files
virtus_out="${RES_DIR}/${srr}_virtus_out.tsv"
virtus_out_orig="${RES_DIR}/${srr}_virtus_out_orig.tsv"

# Generate out log files
outf="${LOG_DIR}/${gse}_${srx}.out"
errf="${LOG_DIR}/${gse}_${srx}.err"

# Apparently weird way to wipe out file contents.
> "${outf}"
> "${errf}"

# Catch up on some much needed logging
info_str="
$(ds) Starting geo_virtus_pipe run
\tResources:\n\t\tRAM: ${RAM} GB\n\t\tCores: ${CORES}
\tDisease: ${CURR_DIS}
\tInput line:\n\t\t${line}
\tIndices indicies:
\t\tHuman [Star]: ${STAR_HUMAN}
\t\tHuman [Salmon]: ${SALMON_IDX}
\t\tOrg [STAR]: ${STAR_VIR} 
\tOutput locations:
\t\tResults: ${RES_DIR}
\t\tData: ${WORK_DIR}
\t\tLogs: \n\t\t\t\t$(realpath "${outf}")\n\t\t\t\t$(realpath "${errf}")

\n\tParsed Run Info:
\t\tGSE: ${gse}
\t\tSRX: ${srx}
\t\tSRR: ${srr}
\t\tSRR2: ${srr2}

\n\tFinal results location:
\t\t${virtus_out}
"

echo -e "${info_str}" | tee -a "${outf}" "${errf}"


# Set our working directory and move there.
# Grab the cwd first so we can return there after our work
orig_work_dir=$(pwd)

cd "${WORK_DIR}" || exit

# Specify fastq file name
path1="${WORK_DIR}/${srr}.fastq"

# Specify the names of what the download files would be so we can check scratch
# to see if the files are already downloaded.
scratch_path="${SCRATCH_DIR}/${srr}/${srr}.fastq"
scratch_path_p1="${SCRATCH_DIR}/${srr}/${srr}_1.fastq"
scratch_path_p2="${SCRATCH_DIR}/${srr}/${srr}_2.fastq"

# Now check if those files exist
if [[ -f "${scratch_path}" ]]; then

	MODE="SE"

	path1="${WORK_DIR}/${srr}.fastq"

	echo -e "$(ds) Found fastq file already downloaded:\\n\\t\\t\\t${scratch_path}"	 >> "${outf}"
	echo -e "\\t\\t\\tMoving it to working directory for reuse...\\n\\t\\t\\t\\t${path1}"	>> "${outf}"
	
	cp -v "${scratch_path}" "${path1}" 	>> "${outf}"

elif [[ -f "${scratch_path_p1}" && -f "${scratch_path_p2}" ]]; then 
  
	MODE="PE"

	path1="${WORK_DIR}/${srr}_1.fastq"
	path2="${WORK_DIR}/${srr}_2.fastq"

	echo -e "$(ds) Found fastq files already downloaded:\\n\\t\\t\\t${scratch_path_p1}\\n\\t\\t\\t${scratch_path_p2}"	>> "${outf}"
	echo -e "\\t\\t\\tMoving them to working directory for reuse...\\n\\t\\t\\t\\t${path1}\\n\\t\\t\\t\\t${path2}" >> "${outf}"

	
	cp -v "${scratch_path_p1}" "${path1}"	 >> "${outf}"
	cp -v "${scratch_path_p2}" "${path2}"	 >> "${outf}"

# If we don't have a previous download we need to download!  
else   
  # Now download the fastq
  dl_file "${srr}" >> "${outf}"
  ret_stat=$?

  # Check if download failed and if so kill the program!
  if [[ "${ret_stat}" -ne 0  ]]; then
    echo -e "Failed to download file!" | tee -a "${outf}" "${errf}"
    exit 1
  fi
  # Do we have a second SRR associated with this SRX?
  if ! [ -z "${srr2}" ]; then 

    echo -e "$(ds) We have a second SRR, processing..." >> "${outf}"

    # Specify fastq file name
    cat_path="${WORK_DIR}/${srr2}.fastq"

    # Download the file
    echo -e "$(ds) Downloading second fastq file: ${cat_path}" >> "${outf}"
    dl_file "${srr2}" >> "${outf}"

    # Cat this file onto the other srr
    echo -e "$(ds) Merging second fastq file into first fastq file"
    cat "${cat_path}" >> "${path1}"
  
    # Now clean up (remove fastq file)
    echo -e "$(ds) Removing second fastq file..." >> "${outf}"

    rm -v "${cat_path}" >> "${outf}"

    echo -e "$(ds) Finished processing second fastq file, back to processing" >> "${outf}"

  fi

  # Check if paired end - count number of fastq files we downloaded
  # if file has SRR_ pattern, assume it's paired end.
  pe_chk=$(basename "${path1}")
  pe_chk="${pe_chk%.fastq}_"

  num_pe_file=$(find "${WORK_DIR}" -maxdepth 1 -type f -iname "${pe_chk}*" | wc -l)

  # We have paired ends!
  if [ "${num_pe_file}" -gt 1 ] ; then
  
    MODE="PE"
  
    # Define our pe fastq file names
    path1="${WORK_DIR}/${srr}_1.fastq"
    path2="${WORK_DIR}/${srr}_2.fastq"

  fi
fi


# Set result vars to empty string for testing
# run_virtus commands will set it
v_res=""

# Single end processing
if [[ "${MODE}" == "SE" ]]; then

	# Collect raw fastq stats
	SECONDS=0

	fq_stats "${path1}"

	duration=$SECONDS
	dur_str="$((duration / 60))m $((duration % 60))s."
	echo -e "$(ds) Finished calculating raw fastq file stats in ${dur_str}." >> "${outf}"
	print_fq_stats $(basename "${path1}") >> "${outf}"

	# VIRTUS uses fastp to do trimming, so we don't have to!
	echo -e "$(ds) Starting VIRTUS\\n\\t\\tMode: ${MODE}\\n\\t\\t\\tInput: ${path1}" >> "${outf}"
	run_virtus "${MODE}" "${path1}" >> "${outf}"

# Paired end processing
else

	# Collect raw fastq stats for R1
	SECONDS=0

	fq_stats "${path1}"

	duration=$SECONDS
	dur_str="$((duration / 60))m $((duration % 60))s."
	echo -e "$(ds) Finished calculating raw fastq file stats for pair 1 in ${dur_str}." >> "${outf}"
	print_fq_stats $(basename "${path1}") >> "${outf}"


	# Collect raw fastq stats for R2
	SECONDS=0

	fq_stats "${path2}"

	duration=$SECONDS
	dur_str="$((duration / 60))m $((duration % 60))s."
	echo -e "$(ds) Finished calculating raw fastq file stats for pair 2 in ${dur_str}." >> "${outf}"
	print_fq_stats $(basename "${path2}") >> "${outf}"
	
	# VIRTUS uses fastp to do trimming, so we don't have to!
	echo -e "$(ds) Starting VIRTUS\\n\\t\\tMode: ${MODE}\\n\\t\\t\\tInput:\\n\\t\\t\\t\\t${path1}\\n\\t\\t\\t\\t${path2}" >> "${outf}"
	run_virtus "PE" "${path1}" "${path2}" >> "${outf}"

fi

# Check VIRTUS process return code
if [[ "${virt_ret}" -ne 0 ]]; then
		echo -e "$(ds) VIRTUS failed for some reason, moving fastq files to scratch then exiting." | tee -a "${outf}" "${errf}"
    clean_fail >> "${outf}"
    exit 1
fi

# Post-processing VIRTUS output
echo -e "$(ds) VIRTUS run verified a success, starting post-processing..." >> "${outf}"

# Move results file over to results dir.
cp -v  "${virtus_out_dir}/virus.counts.final.tsv"  "${virtus_out}" >> "${outf}"

# Create copy of original file before altering
cp -v "${virtus_out}" "${virtus_out_orig}" >> "${outf}"

# Start post processing!

# We want to grab the denominator that VIRTUS uses to calculate rates
# Final STAR human alignment log:
hu_log="${virtus_out_dir}/Log.final.out"

# Grep for uniquely mapped reads, use awk to get actual value
# then use xargs to strip trailing and leading space
# per https://stackoverflow.com/a/12973694
uniq=$(grep 'Uniquely mapped reads number' "${hu_log}" | awk -F"|" '{print $2}' | xargs)
mult=$(grep 'Number of reads mapped to multiple loci' "${hu_log}" | awk -F"|" '{print $2}' | xargs)

tot_mapped=$(( uniq + mult ))

# Join our result file and our conversion table
# On Column 1 in our result file (NC ID)
# On Column 3 in our conv table file (NC ID)
# Output: NC ID, Friendly Name, Overlapped Reads, Overlap Rate
# Both files need to be sorted first, but the <() is a nifty trick
# Then sort by the overlapped reads column.
join -t $'\t' -1 1 -2 3 -o 1.1,2.1,1.2,1.3,2.4  \
    <( sort -k1 "${virtus_out}")                \
    <( sort -k3 "${CONV_TAB}")                  \
    | sort -k3                                  \
    | sponge "${virtus_out}"

# Add line with total number of human reads mapped
sed -i "s/$/\\t$tot_mapped/" "${virtus_out}"

# Add header line
sed -i "1i virus_id\\tvirus_name\\tnum_hit\\trate_hit\\tgenome_len\\tmapped_human" "${virtus_out}"

echo -e "$(ds) Post-processing complete, cleaning up environment..." >> "${outf}"

clean_success >> "${outf}"

echo -e "$(ds) All files have been cleaned and we are done." >> "${outf}"
echo -e "\\t\\tFinal results:\\n  ${virtus_out}" >> "${outf}"
echo -e "\\t\\tRaw results:\\n  ${virtus_out_orig}" >> "${outf}"

end=$(date +%s)
runtime=$((end-start))
dur_str="$((runtime / 60))m $((runtime % 60))s."

echo -e "$(ds) Entire process was completed in ${dur_str}." >> "${outf}"

cd "${orig_work_dir}" || exit