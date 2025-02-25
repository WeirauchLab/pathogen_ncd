# Name:     tnx_phecode_chunking_diags_pub.py
# Author:   Mike Lape
# Date:     2024
# Description:
#
#   The first part of this script contains commented out sections that contain
#   the Bash commands run to generate the input file for this python file 
#   since I couldn't think of anywhere else to put it. After that is a 
#   parallel python script that chunks the diagnosis data into chunks small
#   enough to be processed by the PheWAS library's functions, ~ 2.5 GB.



# Bash commands run before this script:
# cwd: /data/pathogen_ncd

# First, chunk the diagnosis file up 
# split -l 42000000 -d --verbose  ./trinetx/raw/diagnosis.csv  ./chunks/chunk_

# We only want diagnoses derived from the EHR data directly.
# Only print out columns where the 10th column (the source column) is EHR.
# ls ./chunks/chunk_ | parallel -j 56 --eta 'awk -F, "\$10 == \"\\\"EHR\\\"\"" \
# 	 {} > {}.out'

# Combine the results
# cat ./chunks/chunk_*.out | pv -cN Progress | cat > ./trinetx/procd/diagnosis_ehr_only.csv

# Clean up chunk files
# rm -rf chunks

# Grab only the columns we need (patient id, code type, code, date)
# parallel --jobs 56 --eta  --pipepart -a ./trinetx/procd/diagnosis_ehr_only.csv  \
# 	awk -F\",\" \'\{print \$1\",\"\$3\",\"\$4\",\"\$8\}\' >  \
# 		./trinetx/procd/diagnosis_ehr_only_4_cols.csv

# Sort our data so we can chunk it
# parsort --parallel=56 -t ','  -k1,1 -k3,3 -k4,4 \ 
# 	./trinetx/procd/diagnosis_ehr_only_4_cols.csv > ./trinetx/procd/diagnosis_ehr_only_4_cols_sorted.csv


import pandas as pd
import multiprocessing as mp
import os
import logging.handlers
from tqdm import tqdm
import csv
from datetime import datetime
import pytz

# Simple function to get a datetime stamp for logging 
def dt():
	# Get current date and time in Eastern time
	dt_east = datetime.now(pytz.timezone('US/Eastern'))
	dt_east_str = dt_east.strftime('[%Y-%m-%d %H:%M:%S %Z]')

	return dt_east_str


# Function to extract diagnoses for all the patients in a patient chunk
def process_patient_ids(df, patient_ids, chunk_lim, output_dir, proc_num, 
												log_queue):

  # The big diagnoses dataframe is handed in as input and we take only the 
	# diagnoses in our assigned chunk.
	patient_data = df[df['pat_id'].isin(patient_ids)]
	
  # Create a Pandas groupby object that we will loop over using the patient ID
  grouped = patient_data.groupby('pat_id')
	
	# Keeping track of all diagnoses collected for this patient chunk
  curr_chunk = []
	
  # Monitor the current size of the chunk file to know when we should write out
  # to file and start saving diagnoses for the next chunk  
  curr_size = 0

  # Essentially a file counter so we incremenent after writing out a file, so 
	# we have a new filename for the next chunk.
	file_index = 0

  # Now start the loop processing 1 patient at a time.
	for pid, data in tqdm(grouped, desc = f'Process {proc_num}', 
											 position = proc_num, leave = False):
		
    # Check the length of the current file to decide if we should put this 
		# patient's diagnoses in our current file or if we should open a new file.
		size = len(data)
		
		# If we have exceeded the chunk limit write out running chunk to a file
		# chunk_lim is ~ 2.5 GB or 48000000 diagnosis lines
		if curr_size + size > chunk_lim:
				
        # Put together file path for the file we are going to write out.
				output_file = os.path.join(output_dir, 
															 f'chunk_{proc_num}_{file_index}.csv')

				# Output all of the collected diagnoses in curr_chunk out to a CSV
        pd.concat(curr_chunk).to_csv(output_file, index = False, header = False, 
																		 quoting = csv.QUOTE_ALL)
				
        # Calculate filesize of file we just saved and log that.
				fs = os.path.getsize(output_file) / 1024 / 1024 / 1024
				log_queue.put(
					  ( 
							f'Process {proc_num}: Wrote chunk {file_index} with '
						  f'{curr_size} rows and to {output_file} of size {fs:.2f} GB'
						)
        )
				
				# Reset the curr_chunk, curr_size, and increment file index
				curr_chunk = []
				curr_size = 0
				file_index += 1
		
    # Otherwise if we have not exceeded our threshold in the current file
		# append the current diagnoses to curr_chunk and increment the size
		curr_chunk.append(data)
		curr_size += size

	# Once we get here, we have finished and we are writing out our last chunk
	if curr_chunk:
			
      # Name the file
			output_file = os.path.join(output_dir, 
															f'chunk_{proc_num}_{file_index}.csv')
			
      # And write it out just like we did all the other chunks.
      pd.concat(curr_chunk).to_csv(output_file, index = False, header = False, 
																	 quoting = csv.QUOTE_ALL)
			
      # Again calculate the filesize and log it out
			fs = os.path.getsize(output_file) / 1024 / 1024 / 1024
			log_queue.put(
				( 
					f'Process {proc_num}: Wrote final chunk {file_index} with {curr_size}'
		      f' rows to {output_file} of size {fs:.2f}'
				)
      )
	
	# Signal completion of this process
	log_queue.put(f'Process {proc_num} is finished')


# Logging function takes the queue and the file to write the logs to.
def listener_func(queue, log_file):
		
  # Open logging file
	with open(log_file, 'w') as f:
		f.write(f'{dt()} Logging queue opened\n')
		f.flush()

		# Now start listening to queue to write out to log
		while True:
			item = queue.get()
			
      # Kill signal to send to break out of this while loop and finish this
			# process gracefully.
			if item is None:  
					break
			
      # Make sure item is a string and then write it out, we use flush so we 
			# can see the log writes more quickly.
			item_str = str(item)
			f.write(f'{dt()} {item_str}\n')
			f.flush()

if __name__ == '__main__':

	BASE_DIR = '/data/pathogen_ncd'

	# The big diagnosis file (144 GB)
	DIAG_FN = f'{BASE_DIR}/phecode/tnx/tnx_raw/diagnosis_ehr_only_4_cols_sorted.csv'
	
	# Where to put everything
	OUTPUT_DIR = f'{BASE_DIR}/phecode/tnx/tnx_procd/py_diags'
	LOG_FILE = f'{OUTPUT_DIR}/mp_chunking_log.log'

	# ~ number of encounters for 2.5 GB file
	n_enc_chunk_lim = 48000000  

	# Setup logging process and kick it off
	log_queue = mp.Queue()
	listener = mp.Process(target = listener_func, args=(log_queue, LOG_FILE))
	listener.start()

	# Set up types of diagnosis data
	types = {'pat_id' : str, 'vocab': str, 'code' : str, 'date' : str}

	log_queue.put('Started the logging process ')
	log_queue.put('Loading CSV file into memory...')
	
  # Read in the TNX diagnosis file prepared by the bash commands at top of this
	# script.
	diags = pd.read_csv(DIAG_FN, names = ['pat_id', 'vocab', 'code', 'date'],
					   					engine = 'pyarrow', dtype = types)
	
  log_queue.put('CSV file loaded into memory.')

	# Put all the patient IDs in a list then generate patient ID chunks based on
	# how many cores we have access to.
    pat_id_ls = diags['pat_id'].unique().tolist()
	num_cores = 55  
	pat_id_chunks = [pat_id_ls[i::num_cores] for i in range(num_cores)]

	processes = []

	log_queue.put(f'Starting {num_cores} processes...')

  # Using multiprocessing Process to kick off separate processes to handle each
  # patient ID chunk. 
	for i, curr_pat_id_chunk in enumerate(pat_id_chunks):
			log_queue.put(f'Starting process {i}')
			p = mp.Process(target = process_patient_ids, args=(diags, 
                          curr_pat_id_chunk, n_enc_chunk_lim, OUTPUT_DIR, i, 
													log_queue))
			processes.append(p)
			p.start()

  # After all processes finish run join on all the processes.
	for p in processes:
			p.join()

  # Send the kill signal to the logging process (None) and join.
	log_queue.put('All processes completed.')
	log_queue.put(None)
	listener.join()
