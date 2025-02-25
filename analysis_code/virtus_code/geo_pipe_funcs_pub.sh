#!/bin/bash

# Name:     geo_pipe_funcs_pub.sh
# Author:   Mike Lape
# Date:     2023
# Description:
#
#   This file has all the functions used in the geo_virtus_pipe.sh script
#   Separating them into a separate file to save space but also so other scripts 
#   can use the function.
#   Use by adding the following to your script. 
#     source ./geo_pipe_funcs_pubs.sh
#


VIRTUS_HIT_THRESH=0
# define timestamp function ds
function ds() {
	date +"[%F %T]"
}

# Define our function to actually do work
function dl_file () {
	SECONDS=0

	# Specify fastq file name
	dl_path="${1}.fastq"
	dl_full_path=$(realpath "${dl_path}")

	echo -e "$(ds) Starting download of: "
	echo -e "		${dl_full_path}"

	# Keep track of the number of times that fasterq-dump fails
	fail_cnt=0
	fastq_ret=1

	while [[ "${fastq_ret}" -gt 0 && "${fail_cnt}" -lt "${MAX_DL_RETRIES}" ]] ; do

		# Now download the fastq
		# Can add -p option to show progress if desired
		fast_out=$(fasterq-dump "${1}" -p -o "${dl_path}" 2>&1)

		# Capture return of fasterq-dump
		if echo "${fast_out}" | grep -q 'err' ; then
			fastq_ret=1
		else
			fastq_ret=0
		fi
		# No matter if it failed or succeeded that was an attempt, so update cnt
		fail_cnt=$((fail_cnt+1))
  done

	# Now we can see based on fastq_ret whether we failed to dl and should quit
	if [[ "${fastq_ret}" -gt 0 ]]; then
	  echo -e "$(ds) Fasterq-dump failed to download file." >&2
	  return 1
	else
		duration=$SECONDS
		dur_str="$((duration / 60))m $((duration % 60))s."
		echo -e "$(ds) File successfully downloaded in ${dur_str}."
    return 0
	fi
}

# Function to calculate different stats of input fastq file
# $1: Path to 1st fastq file
function fq_stats () {

	# Number of reads
	tot_lines=$(wc -l "${1}" | awk '{print $1}')
	num_reads="$(( tot_lines / 4 ))"
    fq_size=$(du -h "${1}" | awk '{print $1}')

	# Read length stats
	# Calculate histogram in form of "read_len cnt"
	hist=$(awk 'NR%4 == 2 {lengths[length($0)]++} END {for (l in lengths) {print l"\t"lengths[l]}}' "${1}")

	# Mode
	mode_row=$(echo "${hist}" | sort -k2 -V -r | head -n1)
	mode_len=$(echo "${mode_row}" | awk '{print $1}')
	mode_cnt=$(echo "${mode_row}" | awk '{print $2}')

	# Mean
	# Loop over our histogram
	tot_base=0
	while read -r len cnt; do 
		# Multiply read length by number of reads of that length and add to tot_base
		tot_base=$(  bc <<< "scale=10; ${tot_base} + (${len} * ${cnt})")

	done < <(printf '%s\n' "${hist}")

	mean=$( bc <<< "scale=10; ${tot_base} / ${num_reads}" )

	# numerator for standard deviation calculation
	sd_num=0

	while read -r len cnt; do 

		# Multiply read length by number of reads of that length and add to tot_base	
		curr_num=$( bc <<< "scale=10; ${len} - ${mean}")

		# Square result
		curr_num=$( bc <<< "scale=10; ${curr_num} * ${curr_num}" )

		# Multiply by freq
		curr_num=$( bc <<< "scale=10; ${curr_num} * ${cnt}" )

		# Now add to running total
		sd_num=$( bc <<< "scale=10;  ${sd_num} + ${curr_num}" )

	done < <(printf '%s\\n' "$hist")

	# Calculate SD and round to 3 decimal points
	sd=$( bc <<< "scale=10; sqrt(${sd_num} / ${num_reads})")
	sd=$( printf "%.3f\\n" "$(echo "${sd}" | bc -l)")

	# Round mean to 2 decimal points after using it for SD calculation
	# Rounding: https://stackoverflow.com/a/26465573
	mean=$( printf "%.3f\\n" "$(echo "${mean}" | bc -l)")

	# Max read len
	max=$(echo "${hist}" | awk '{print $1}' | sort | tail -n1)

	# Min read len
	min=$(echo "${hist}" | awk '{print $1}' | sort | head -n1)
}

# Requires you to have run fq_stats first, otherwise will fail
# $1: Fastq file name for which we have stats.
function print_fq_stats () {
	echo -e "Fastq stats for ${1}:"
	echo -e "\\t\\tFastq file size (GB):\\t\\t\\t${fq_size}"
	echo -e "\\t\\tNumber of reads:\\t\\t${num_reads}"
	echo -e "\\t\\tAverage read length:\\t\\t${mean}"
	echo -e "\\t\\tSTDEV read length:\\t\\t${sd}"
	echo -e "\\t\\tMin-Max read length:\\t\\t${min} - ${max}"
	echo -e "\\t\\tMode read length:\\t\\t${mode_len} [Frq: ${mode_cnt}]"
}

# $1: Type of data, SE or PE
# $2: Path to 1st fastq file
# $3: Path to 2nd fastq file - if needed
function run_virtus () {

	if [[ "$1" = "SE" ]] ; then

		virt_cmd="cwltool 								\
              --basedir . 								\
              --outdir ./out 							\
              --tmpdir-prefix ./tmp/${srr} 				\
              --singularity  							\
              ${VIRT_SE} 								\
              --fastq $2 								\
              --genomeDir_human ${STAR_HUMAN} 			\
              --genomeDir_virus ${STAR_VIR} 			\
              --salmon_index_human ${SALMON_IDX} 		\
              --salmon_quantdir_human salmon_out        \
              --hit_cutoff  ${VIRTUS_HIT_THRESH}        \
              --nthreads ${CORES}"
	else

		virt_cmd="cwltool 								\
              --basedir . 								\
              --outdir ./out 							\
              --tmpdir-prefix ./tmp/${srr} 				\
              --singularity  							\
              ${VIRT_PE} 								\
              --fastq1 $2 								\
              --fastq2 $3 								\
              --genomeDir_human ${STAR_HUMAN} 			\
              --genomeDir_virus ${STAR_VIR} 			\
              --salmon_index_human ${SALMON_IDX} 		\
              --salmon_quantdir_human salmon_out        \
              --hit_cutoff  ${VIRTUS_HIT_THRESH}        \
              --nthreads ${CORES}"

	fi

	SECONDS=0
	
	echo -e "$(ds) Starting VIRTUS, enabling stdout:\\n\\t\\t\\t${virt_cmd}"

	eval "${virt_cmd}" 2>&1
  
  virt_ret=$?

	duration=$SECONDS
	dur_str="$((duration / 60))m $((duration % 60))s."

	echo -e "$(ds) Finished running VIRTUS in ${dur_str}. Verifying run..."
}

# Function to clean up VIRTUS files in working directory
function clean_virtus () {
	# Clean up, by deleting larger files
	# Remove any BAM files larger than 75M
	echo -e "\\t\\tRemoving BAM files larger than 75MB"
	find "${WORK_DIR}" -type f -iname '*.bam'  | grep -v 'virusAligned.filtered.sortedByCoord.out.bam' | xargs rm -v

	# Remove any fq files larger than 75M
	echo -e "\\t\\tRemoving additional fastq files larger than 75MB"
	#find "${WORK_DIR}" -type f -iname '*.fastq' -o -iname '*.fq' -size +75M -exec rm {} \;
  # Replace with a simpler command
  find "${WORK_DIR}" -type f -size +75M | grep '.fastq.gz\|.fastq\|fq.gz\|fq' | xargs rm -v

	echo -e "\\t\\tRemoving SIF files"
	find "${WORK_DIR}" -type f -iname '*.sif'  -exec rm {} \;
}

# Clean up files when VIRTUS fails (move fq to scratch and clean work dir)
clean_fail () {
		# If we failed move the files for next run!
		#if [ "${MODE}" = "PE" ] ; then

			#mv -v "${path1}" "${SCRATCH_DIR}/"
			#mv -v "${path2}" "${SCRATCH_DIR}/"
		#else
			#mv -v "${path1}" "${SCRATCH_DIR}/"
		#fi

    # And clean up VIRTUS environment
    clean_virtus
}

# Clean up files when VIRTUS succeeds (delete fq and clean work dir)
clean_success () {
		# We have paired ends!
		if [ "${MODE}" = "PE" ] ; then

      echo -e "\\t\\tRemoving the SRR fastq files"
      rm -v "${path1}"
      rm -v "${path2}"

		else
      echo -e "$\\t\\tRemoving the SRR fastq file"
      rm -v "${path1}"
		fi

    clean_virtus
}