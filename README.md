Holland_Joint_Call

This submitter and it's subscripts are used for joint calling the Holland_MendelianDisorders_SeqWholeExome_033117_1 exome project.

The HOLLAND_JOINT_CALL_SUBMITTER.sh takes in the following arguments:

PROJECT - The name of the project directory found in /mnt/research/active (just the project name, not the full path)
SAMPLE_SHEET - The sample sheet with the samples to be joint called (fully qualified path)
PREFIX - The prefix of the multi-sample vcf that will be generated
NUMBER_OF_BED_FILES - The number of bed files to split on.  If left blank, the default will be 500

**If these scripts are used you must change the SCRIPT_DIR on line 18 in the MASTER_SUBMITTER.sh to where the SCRIPTS folder lives.**

The setup splits based on bed file as opposed to chromosome.  This allows for each step to run more efficiently and take up less time per job slot.  Utilizing a larger number of job submissions that run faster allows us to use the cluster more efficiently.  
		The bait bed file is found from the sample sheet and is checked for formatting and to ensure it's sorted properly.  Then this bed file is split and stored in the TEMP/BED_FILE_SPLIT directory.

When submitted, the HOLLAND_JOINT_CALL_SUBMITTER.sh looks in the Holland_MendelianDisorders_SeqWholeExome_033117_1 for the most recently created ".list" file. It counts the number of records in that file as well the number of unique SM_TAG records in the $SAMPLE_SHEET. It then appends the fuly qualified paths of the SM_TAG gvcf files of the samples in the $SAMPLE_SHEET to the previously existing list, creating a new list file named as "total_sample_count_to_date".samples.gvcf.list.

*If* the run accompanying this new ".list" file is not used for release. Then this file has to be deleted before resubmitted a new pipeline.
