#! /bin/bash

PROJECT=$1
SAMPLE_SHEET=$2
PREFIX=$3
NUMBER_OF_BED_FILES=$4
if [[ ! $NUMBER_OF_BED_FILES ]]
	then
	NUMBER_OF_BED_FILES=500
fi

module load datamash

QUEUE_LIST=`qstat -f -s r \
	| egrep -v "^[0-9]|^-|^queue" \
	| cut -d @ -f 1 \
	| sort \
	| uniq \
	| egrep -v "bigmem.q|all.q|cgc.q|programmers.q|uhoh.q|rhel7.q|qtest.q" \
	| datamash collapse 1 \
	| awk '{print "-q",$1,"-l \x27hostname=!DellR730-03\x27"}'`

PRIORITY="-11"

##############FIXED DIRECTORIES###############

SCRIPT_DIR="/mnt/research/tools/LINUX/00_GIT_REPO_KURT/Holland_Joint_Call/scripts"
JAVA_1_7="/mnt/research/tools/LINUX/JAVA/jdk1.7.0_25/bin"
JAVA_1_8="/mnt/research/tools/LINUX/JAVA/jdk1.8.0_73/bin"
CORE_PATH="/mnt/research/active"
BEDTOOLS_DIR="/mnt/research/tools/LINUX/BEDTOOLS/bedtools-2.22.0/bin"
GATK_DIR="/mnt/research/tools/LINUX/GATK/GenomeAnalysisTK-3.3-0"
GATK_3_1_1_DIR="/mnt/research/tools/LINUX/GATK/GenomeAnalysisTK-3.1-1"
GATK_DIR_NIGHTLY="/mnt/research/tools/LINUX/GATK/GenomeAnalysisTK-nightly-2015-01-15-g92376d3"
GATK_3_6_DIR="/mnt/research/tools/LINUX/GATK/GenomeAnalysisTK-3.6"
SAMTOOLS_DIR="/mnt/research/tools/LINUX/SAMTOOLS/samtools-0.1.18/"
TABIX_DIR="/mnt/research/tools/LINUX/TABIX/tabix-0.2.6/"
CIDR_SEQSUITE_JAVA_DIR="/mnt/research/tools/LINUX/JAVA/jre1.7.0_45/bin"
CIDR_SEQSUITE_6_1_1_DIR="/mnt/research/tools/LINUX/CIDRSEQSUITE/6.1.1"

##############FIXED FILE PATHS################

KEY="/mnt/research/tools/PIPELINE_FILES/MISC/lee.watkins_jhmi.edu.key"
HAPMAP_VCF="/mnt/research/tools/PIPELINE_FILES/GATK_resource_bundle/2.8/b37/hapmap_3.3.b37.vcf"
OMNI_VCF="/mnt/research/tools/PIPELINE_FILES/GATK_resource_bundle/2.8/b37/1000G_omni2.5.b37.vcf"
ONEKG_SNPS_VCF="/mnt/research/tools/PIPELINE_FILES/GATK_resource_bundle/2.8/b37/1000G_phase1.snps.high_confidence.b37.vcf"
DBSNP_138_VCF="/mnt/research/tools/PIPELINE_FILES/GATK_resource_bundle/2.8/b37/dbsnp_138.b37.vcf"
ONEKG_INDELS_VCF="/mnt/research/tools/PIPELINE_FILES/GATK_resource_bundle/2.8/b37/Mills_and_1000G_gold_standard.indels.b37.vcf"
P3_1KG="/mnt/shared_resources/public_resources/1000genomes/Full_Project/Sep_2014/20130502/ALL.wgs.phase3_shapeit2_mvncall_integrated_v5.20130502.sites.vcf.gz"
ExAC="/mnt/shared_resources/public_resources/ExAC/Release_0.3/ExAC.r0.3.sites.vep.vcf.gz"
KNOWN_SNPS="/mnt/research/tools/PIPELINE_FILES/GATK_resource_bundle/2.8/b37/dbsnp_138.b37.excluding_sites_after_129.vcf"
VERACODE_CSV="/mnt/research/tools/LINUX/CIDRSEQSUITE/Veracode_hg18_hg19.csv"


# load gcc 5.1.0 for programs like verifyBamID
## this will get pushed out to all of the compute nodes since I specify env var to pushed out with qsub
module load gcc/5.1.0

# explicitly setting this b/c not everybody has had the $HOME directory transferred and I'm not going to through
# and figure out who does and does not have this set correctly
umask 0007

############################################################################
#################Start of Combine Gvcf Functions############################
############################################################################

CREATE_PROJECT_INFO_ARRAY ()
{
PROJECT_INFO_ARRAY=(`sed 's/\r//g' $SAMPLE_SHEET | awk 'BEGIN{FS=","} NR>1 {print $1,$12,$18,$16}' | sed 's/,/\t/g' | sort -k 1,1 | awk '$1=="'$PROJECT'" {print $1,$2,$3,$4}' | sort | uniq`)

PROJECT_NAME=${PROJECT_INFO_ARRAY[0]}
REF_GENOME=${PROJECT_INFO_ARRAY[1]}
PROJECT_DBSNP=${PROJECT_INFO_ARRAY[2]}
PROJECT_BAIT_BED=${PROJECT_INFO_ARRAY[3]}
}

###############################################################################################

# LIKE THE CMG GRANT. FIND THE LAST LIST OF GVCF FILES AND APPEND TO IT, CREATING A NEW LIST FILE

CREATE_GVCF_LIST()
{
OLD_GVCF_LIST=$(ls -tr $CORE_PATH/$PROJECT/*.samples.gvcf.list | tail -n1)

TOTAL_SAMPLES=(`(cat $OLD_GVCF_LIST ; awk 'BEGIN{FS=","} NR>1{print $1,$8}' $SAMPLE_SHEET | sort | uniq | awk 'BEGIN{OFS="/"}{print "'$CORE_PATH'",$1,"GVCF",$2".genome.vcf"}') | sort | uniq | wc -l`)

(cat $OLD_GVCF_LIST ; awk 'BEGIN{FS=","} NR>1{print $1,$8}' $SAMPLE_SHEET | sort | uniq | awk 'BEGIN{OFS="/"}{print "'$CORE_PATH'",$1,"GVCF",$2".genome.vcf"}') | sort | uniq \
>| $CORE_PATH'/'$PROJECT'/'$TOTAL_SAMPLES'.samples.gvcf.list'

GVCF_LIST=(`echo $CORE_PATH'/'$PROJECT'/'$TOTAL_SAMPLES'.samples.gvcf.list'`)
}

###############################################################################################

FORMAT_AND_SCATTER_BAIT_BED() {
BED_FILE_PREFIX=(`echo SPLITTED_BED_FILE_`)

awk 1 $PROJECT_BAIT_BED | sed -r 's/\r//g ; s/chr//g ; s/[[:space:]]+/\t/g' >| $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_BED_FILE.bed
(awk '$1~/^[0-9]/' $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_BED_FILE.bed | sort -k1,1n -k2,2n ; \
awk '$1=="X"' $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_BED_FILE.bed | sort -k 2,2n ; \
awk '$1=="Y"' $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_BED_FILE.bed | sort -k 2,2n ; \
awk '$1=="MT"' $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_BED_FILE.bed | sort -k 2,2n) \
>| $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_AND_SORTED_BED_FILE.bed

# Determining how many records will be in each mini-bed file.  The +1 at the end is to round up the number of records per mini-bed file to ensure all records are captured.  So the last mini-bed file will be smaller.
INTERVALS_DIVIDED=`wc -l $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_AND_SORTED_BED_FILE.bed | awk '{print $1"/""'$NUMBER_OF_BED_FILES'"}' | bc | awk '{print $0+1}'`

split -l $INTERVALS_DIVIDED -a 4 -d  $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/FORMATTED_AND_SORTED_BED_FILE.bed $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/$BED_FILE_PREFIX

ls $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/$BED_FILE_PREFIX* | awk '{print "mv",$0,$0".bed"}' | bash
}

COMBINE_GVCF(){
echo \
 qsub $QUEUE_LIST \
 -N 'A01_COMBINE_GVCF_'$PROJECT'_'$BED_FILE_NAME \
 -p $PRIORITY \
 -j y -o $CORE_PATH/$PROJECT/LOGS/A01_COMBINE_GVCF_$BED_FILE_NAME.log \
 $SCRIPT_DIR/A01_COMBINE_GVCF.sh \
 $JAVA_1_7 $GATK_DIR $REF_GENOME \
 $KEY $CORE_PATH $PROJECT_NAME $GVCF_LIST \
 $PREFIX $BED_FILE_NAME
 }

GENOTYPE_GVCF(){
echo \
 qsub $QUEUE_LIST \
 -N B02_GENOTYPE_GVCF_$PROJECT'_'$BED_FILE_NAME \
 -p $PRIORITY \
 -hold_jid A01_COMBINE_GVCF_$PROJECT'_'$BED_FILE_NAME \
 -j y -o $CORE_PATH/$PROJECT/LOGS/B02_GENOTYPE_GVCF_$BED_FILE_NAME.log \
 $SCRIPT_DIR/B02_GENOTYPE_GVCF.sh \
 $JAVA_1_7 $GATK_DIR $REF_GENOME \
 $KEY $CORE_PATH $PROJECT_NAME \
 $PREFIX $BED_FILE_NAME
}

VARIANT_ANNOTATOR(){
echo \
 qsub $QUEUE_LIST \
 -N C03_VARIANT_ANNOTATOR_$PROJECT'_'$BED_FILE_NAME \
 -p $PRIORITY \
 -hold_jid B02_GENOTYPE_GVCF_$PROJECT'_'$BED_FILE_NAME \
 -j y -o $CORE_PATH/$PROJECT/LOGS/C03_VARIANT_ANNOTATOR_$BED_FILE_NAME.log \
 $SCRIPT_DIR/C03_VARIANT_ANNOTATOR.sh \
 $JAVA_1_7 $GATK_DIR $REF_GENOME \
 $KEY $CORE_PATH $PROJECT_NAME \
 $PREFIX $BED_FILE_NAME $PROJECT_DBSNP
}

##############################################################################
#####################End of Combine Gvcf Functions############################
##############################################################################

##############################################################################
##################Start of VQSR and Refinement Functions######################
##############################################################################

GENERATE_CAT_VARIANTS_HOLD_ID(){
CAT_VARIANTS_HOLD_ID=$CAT_VARIANTS_HOLD_ID'C03_VARIANT_ANNOTATOR_'$PROJECT'_'$BED_FILE_NAME','
}

CAT_VARIANTS(){
echo \
 qsub $QUEUE_LIST \
 -N D04_CAT_VARIANTS_$PROJECT \
 -p $PRIORITY \
 -hold_jid $CAT_VARIANTS_HOLD_ID \
 -j y -o $CORE_PATH/$PROJECT/LOGS/D04_CAT_VARIANTS.log \
 $SCRIPT_DIR/D04_CAT_VARIANTS.sh \
 $JAVA_1_7 $GATK_DIR $REF_GENOME \
 $CORE_PATH $PROJECT_NAME $PREFIX
 }

VARIANT_RECALIBRATOR_SNV() {
echo \
 qsub $QUEUE_LIST \
 -N E05A_VARIANT_RECALIBRATOR_SNV_$PROJECT \
 -p $PRIORITY \
 -hold_jid D04_CAT_VARIANTS_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/E05A_VARIANT_RECALIBRATOR_SNV.log \
 $SCRIPT_DIR/E05A_VARIANT_RECALIBRATOR_SNV.sh \
 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME $HAPMAP_VCF $OMNI_VCF $ONEKG_SNPS_VCF $DBSNP_138_VCF \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

VARIANT_RECALIBRATOR_INDEL() {
echo \
 qsub $QUEUE_LIST \
 -N E05B_VARIANT_RECALIBRATOR_INDEL_$PROJECT \
 -p $PRIORITY \
 -hold_jid D04_CAT_VARIANTS_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/E05B_VARIANT_RECALIBRATOR_INDEL.log \
 $SCRIPT_DIR/E05B_VARIANT_RECALIBRATOR_INDEL.sh \
 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME $ONEKG_INDELS_VCF \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

APPLY_RECALIBRATION_SNV(){
echo \
 qsub $QUEUE_LIST \
 -N F06_APPLY_RECALIBRATION_SNV_$PROJECT \
 -p $PRIORITY \
 -hold_jid E05A_VARIANT_RECALIBRATOR_SNV_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/F06_APPLY_RECALIBRATION_SNV.log \
 $SCRIPT_DIR/F06_APPLY_RECALIBRATION_SNV.sh \
 $JAVA_1_7 $GATK_DIR $REF_GENOME \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

APPLY_RECALIBRATION_INDEL(){
echo \
 qsub $QUEUE_LIST \
 -N G07_APPLY_RECALIBRATION_INDEL_$PROJECT \
 -p $PRIORITY \
 -hold_jid F06_APPLY_RECALIBRATION_SNV_$PROJECT','E05B_VARIANT_RECALIBRATOR_INDEL_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/G07_APPLY_RECALIBRATION_INDEL.log \
 $SCRIPT_DIR/G07_APPLY_RECALIBRATION_INDEL.sh \
 $JAVA_1_7 $GATK_DIR $REF_GENOME \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

BGZIP_AND_TABIX_RECAL_VCF(){
echo \
 qsub $QUEUE_LIST \
 -N H08A_BGZIP_AND_TABIX_RECAL_VCF_$PROJECT \
 -p $PRIORITY \
 -hold_jid G07_APPLY_RECALIBRATION_INDEL_$PROJECT','F06_APPLY_RECALIBRATION_SNV_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/H08A_BGZIP_AND_TABIX_RECAL_VCF.log \
 $SCRIPT_DIR/H08A_BGZIP_AND_TABIX_RECAL_VCF.sh \
 $TABIX_DIR \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

CALCULATE_GENOTYPE_POSTERIORS(){
echo \
 qsub $QUEUE_LIST \
 -N H08B_CALCULATE_GENOTYPE_POSTERIORS_$PROJECT \
 -p $PRIORITY \
 -hold_jid G07_APPLY_RECALIBRATION_INDEL_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/H08B_CALCULATE_GENOTYPE_POSTERIORS.log \
 $SCRIPT_DIR/H08B_CALCULATE_GENOTYPE_POSTERIORS.sh \
 $JAVA_1_7 $GATK_DIR_NIGHTLY $KEY $REF_GENOME $P3_1KG $ExAC \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

VARIANT_ANNOTATOR_REFINED(){
echo \
 qsub $QUEUE_LIST \
 -N I09_VARIANT_ANNOTATOR_REFINED_$PROJECT \
 -p $PRIORITY \
 -hold_jid H08B_CALCULATE_GENOTYPE_POSTERIORS_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/I09_VARIANT_ANNOTATOR_REFINED.log \
 $SCRIPT_DIR/I09_VARIANT_ANNOTATOR_REFINED.sh \
 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME $PROJECT_DBSNP \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

BGZIP_AND_TABIX_REFINED_VCF(){
echo \
 qsub $QUEUE_LIST \
 -N J10_BGZIP_AND_TABIX_REFINED_VCF_$PROJECT \
 -p $PRIORITY \
 -hold_jid I09_VARIANT_ANNOTATOR_REFINED_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/J10_BGZIP_AND_TABIX_REFINED_VCF.log \
 $SCRIPT_DIR/J10_BGZIP_AND_TABIX_REFINED_VCF.sh \
 $TABIX_DIR \
 $CORE_PATH $PROJECT_NAME $PREFIX
}

###########################################################################
#################End of VQSR and Refinement Functions######################
###########################################################################
#
###########################################################################
###################Start of Vcf Splitter Functions#########################
###########################################################################

CREATE_SAMPLE_INFO_ARRAY ()
{
SAMPLE_INFO_ARRAY=(`sed 's/\r//g' $SAMPLE_SHEET \
| awk 'BEGIN{FS=","} NR>1 {print $1,$8,$17,$15,$18,$12}' \
| sed 's/,/\t/g' \
| sort -k 8,8 \
| uniq \
| awk '$2=="'$SAMPLE'" {print $1,$2,$3,$4,$5,$6}'`)

PROJECT_SAMPLE=${SAMPLE_INFO_ARRAY[0]}
SM_TAG=${SAMPLE_INFO_ARRAY[1]}
TARGET_BED=${SAMPLE_INFO_ARRAY[2]}
TITV_BED=${SAMPLE_INFO_ARRAY[3]}
DBSNP=${SAMPLE_INFO_ARRAY[4]} #Not used unless we implement HC_BAM
SAMPLE_REF_GENOME=${SAMPLE_INFO_ARRAY[5]}

UNIQUE_ID_SM_TAG=$(echo $SM_TAG | sed 's/@/_/g') # If there is an @ in the qsub or holdId name it breaks
}

SELECT_PASSING_VARIANTS_PER_SAMPLE(){
echo \
 qsub $QUEUE_LIST \
 -N K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid I09_VARIANT_ANNOTATOR_REFINED_$PROJECT \
 -j y -o $CORE_PATH/$PROJECT/LOGS/K11_SELECT_VARIANTS_FOR_SAMPLE_$SM_TAG.log \
 $SCRIPT_DIR/K11_SELECT_VARIANTS_FOR_SAMPLE.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $PREFIX
}

BGZIP_AND_TABIX_SAMPLE_VCF(){
echo \
 qsub $QUEUE_LIST \
 -N L12A_BGZIP_AND_TABIX_SAMPLE_VCF_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12A_BGZIP_AND_TABIX_SAMPLE_VCF_$SAMPLE.log \
 $SCRIPT_DIR/L12A_BGZIP_AND_TABIX_SAMPLE_VCF.sh \
 $TABIX_DIR \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG
}

PASSING_VARIANTS_ON_TARGET_BY_SAMPLE(){
echo \
 qsub $QUEUE_LIST \
 -N L12B_PASSING_VARIANTS_ON_TARGET_BY_SAMPLE_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12B_PASSING_VARIANTS_ON_TARGET_BY_SAMPLE_$SAMPLE.log \
 $SCRIPT_DIR/L12B_PASSING_VARIANTS_ON_TARGET_BY_SAMPLE.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $TARGET_BED
}

PASSING_SNVS_ON_BAIT_BY_SAMPLE(){
echo \
 qsub $QUEUE_LIST \
 -N L12C_PASSING_SNVS_ON_BAIT_BY_SAMPLE_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12C_PASSING_SNVS_ON_BAIT_BY_SAMPLE_$SAMPLE.log \
 $SCRIPT_DIR/L12C_PASSING_SNVS_ON_BAIT_BY_SAMPLE.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG
}

PASSING_SNVS_ON_TARGET_BY_SAMPLE(){
echo \
 qsub $QUEUE_LIST \
 -N L12D_PASSING_SNVS_ON_TARGET_BY_SAMPLE_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12D_PASSING_SNVS_ON_TARGET_BY_SAMPLE_$SAMPLE.log \
 $SCRIPT_DIR/L12D_PASSING_SNVS_ON_TARGET_BY_SAMPLE.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $TARGET_BED
}

CONCORDANCE_ON_TARGET_PER_SAMPLE(){
echo \
 qsub $QUEUE_LIST \
 -N L12D-1_CONCORDANCE_ON_TARGET_PER_SAMPLE_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid L12D_PASSING_SNVS_ON_TARGET_BY_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12D-1_CONCORDANCE_ON_TARGET_PER_SAMPLE_$SAMPLE.log \
 $SCRIPT_DIR/L12D-1_CONCORDANCE_ON_TARGET_PER_SAMPLE.sh \
 $CIDR_SEQSUITE_JAVA_DIR $CIDR_SEQSUITE_6_1_1_DIR $VERACODE_CSV \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $TARGET_BED
}

PASSING_INDELS_ON_BAIT_BY_SAMPLE(){
echo \
 qsub $QUEUE_LIST \
 -N L12E_PASSING_INDELS_ON_BAIT_BY_SAMPLE_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12E_PASSING_INDELS_ON_BAIT_BY_SAMPLE_$SAMPLE.log \
 $SCRIPT_DIR/L12E_PASSING_INDELS_ON_BAIT_BY_SAMPLE.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG
}

PASSING_INDELS_ON_TARGET_BY_SAMPLE(){
echo \
 qsub $QUEUE_LIST \
 -N L12F_PASSING_INDELS_ON_TARGET_BY_SAMPLE_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12F_PASSING_INDELS_ON_TARGET_BY_SAMPLE_$SAMPLE.log \
 $SCRIPT_DIR/L12F_PASSING_INDELS_ON_TARGET_BY_SAMPLE.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $TARGET_BED
}

PASSING_SNVS_TITV_ALL(){
echo \
 qsub $QUEUE_LIST \
 -N L12G_PASSING_SNVS_TITV_ALL_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12G_PASSING_SNVS_TITV_ALL_$SAMPLE.log \
 $SCRIPT_DIR/L12G_PASSING_SNVS_TITV_ALL.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $TITV_BED
}

TITV_ALL(){
echo \
 qsub $QUEUE_LIST \
 -N L12G-1_TITV_ALL_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid L12G_PASSING_SNVS_TITV_ALL_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12G-1_TITV_ALL_$SAMPLE.log \
 $SCRIPT_DIR/L12G-1_TITV_ALL.sh \
 $SAMTOOLS_DIR \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG
}

PASSING_SNVS_TITV_KNOWN(){
echo \
 qsub $QUEUE_LIST \
 -N L12H_PASSING_SNVS_TITV_KNOWN_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12H_PASSING_SNVS_TITV_KNOWN_$SAMPLE.log \
 $SCRIPT_DIR/L12H_PASSING_SNVS_TITV_KNOWN.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME $KNOWN_SNPS \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $TITV_BED
}

TITV_KNOWN(){
echo \
 qsub $QUEUE_LIST \
 -N L12H-1_TITV_KNOWN_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid L12H_PASSING_SNVS_TITV_KNOWN_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12H-1_TITV_KNOWN_$SAMPLE.log \
 $SCRIPT_DIR/L12H-1_TITV_KNOWN.sh \
 $SAMTOOLS_DIR \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG
}

PASSING_SNVS_TITV_NOVEL(){
echo \
 qsub $QUEUE_LIST \
 -N L12I_PASSING_SNVS_TITV_NOVEL_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid K11_SELECT_VARIANTS_FOR_SAMPLE_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12I_PASSING_SNVS_TITV_NOVEL_$SAMPLE.log \
 $SCRIPT_DIR/L12I_PASSING_SNVS_TITV_NOVEL.sh \
 $JAVA_1_7 $GATK_DIR $KEY $SAMPLE_REF_GENOME $KNOWN_SNPS \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG $TITV_BED
}

TITV_NOVEL(){
echo \
 qsub $QUEUE_LIST \
 -N L12I-1_TITV_NOVEL_$UNIQUE_ID_SM_TAG \
 -p $PRIORITY \
 -hold_jid L12I_PASSING_SNVS_TITV_NOVEL_$UNIQUE_ID_SM_TAG \
 -j y -o $CORE_PATH/$PROJECT/LOGS/L12I-1_TITV_NOVEL_$SAMPLE.log \
 $SCRIPT_DIR/L12I-1_TITV_NOVEL.sh \
 $SAMTOOLS_DIR \
 $CORE_PATH $PROJECT_SAMPLE $SM_TAG
}

##########################################################################
##### BREAKOUTS FOR VARIANT SUMMARY STATS ################################
##########################################################################

GENERATE_STUDY_HAPMAP_SAMPLE_LISTS () 
{
	HAP_MAP_SAMPLE_LIST=(`echo $CORE_PATH'/'$PROJECT'/MULTI_SAMPLE/VARIANT_SUMMARY_STAT_VCF/'$PREFIX'_hapmap_samples.list'`)
	MENDEL_SAMPLE_LIST=(`echo $CORE_PATH'/'$PROJECT'/MULTI_SAMPLE/VARIANT_SUMMARY_STAT_VCF/'$PREFIX'_study_samples.list'`)
	echo \
	 qsub $QUEUE_LIST \
	 -N J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
 	 -hold_jid I09_VARIANT_ANNOTATOR_REFINED_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS.log' \
	 $SCRIPT_DIR/J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS.sh \
	 $CORE_PATH $PROJECT $PREFIX
}


SELECT_SNVS_ALL () 
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10B_SELECT_SNPS_FOR_ALL_SAMPLES_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10B_SELECT_SNPS_FOR_ALL_SAMPLES.log' \
	 $SCRIPT_DIR/J10B_SELECT_ALL_SAMPLES_SNP.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX
}

SELECT_PASS_STUDY_ONLY_SNP () 
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10C_SELECT_PASS_STUDY_ONLY_SNP_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10C_SELECT_PASS_STUDY_ONLY_SNP.log' \
	 $SCRIPT_DIR/J10C_SELECT_PASS_STUDY_ONLY_SNP.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX $HAP_MAP_SAMPLE_LIST
}

SELECT_PASS_HAPMAP_ONLY_SNP ()
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10D_SELECT_PASS_HAPMAP_ONLY_SNP_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10D_SELECT_PASS_HAPMAP_ONLY_SNP.log' \
	 $SCRIPT_DIR/J10D_SELECT_PASS_HAPMAP_ONLY_SNP.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX $MENDEL_SAMPLE_LIST
}

SELECT_INDELS_ALL ()
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10E_SELECT_INDELS_FOR_ALL_SAMPLES_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10E_SELECT_INDELS_FOR_ALL_SAMPLES.log' \
	 $SCRIPT_DIR/J10E_SELECT_ALL_SAMPLES_INDELS.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX
}

SELECT_PASS_STUDY_ONLY_INDELS ()
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10F_SELECT_PASS_STUDY_ONLY_INDEL_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10F_SELECT_PASS_STUDY_ONLY_INDEL.log' \
	 $SCRIPT_DIR/J10F_SELECT_PASS_STUDY_ONLY_INDEL.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX $HAP_MAP_SAMPLE_LIST
}

SELECT_PASS_HAPMAP_ONLY_INDELS ()
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10G_SELECT_PASS_HAPMAP_ONLY_INDEL_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10G_SELECT_PASS_HAPMAP_ONLY_INDEL.log' \
	 $SCRIPT_DIR/J10G_SELECT_PASS_HAPMAP_ONLY_INDEL.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX $MENDEL_SAMPLE_LIST
}


SELECT_SNVS_ALL_PASS () 
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10H_SELECT_SNP_FOR_ALL_SAMPLES_PASS_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10H_SELECT_SNP_FOR_ALL_SAMPLES_PASS.log' \
	 $SCRIPT_DIR/J10H_SELECT_ALL_SAMPLES_SNP_PASS.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX
}

SELECT_INDEL_ALL_PASS () 
{
	echo \
	 qsub $QUEUE_LIST \
	 -N J10I_SELECT_INDEL_FOR_ALL_SAMPLES_PASS_$PROJECT \
	 -p $PRIORITY \
	 -hold_jid J10_GENERATE_STUDY_HAPMAP_SAMPLE_LISTS_$PROJECT \
	 -j y -o $CORE_PATH/$PROJECT/LOGS/$PREFIX'_J10H_SELECT_INDEL_FOR_ALL_SAMPLES_PASS.log' \
	 $SCRIPT_DIR/J10I_SELECT_ALL_SAMPLES_INDEL_PASS.sh \
	 $JAVA_1_7 $GATK_DIR $KEY $REF_GENOME \
	 $CORE_PATH $PROJECT $PREFIX
}

##########################################################################
######################End of Functions####################################
##########################################################################

## Check to see if bed file directory has been created from a previous run.  If so, remove it to not interfere with current run ##
if [ -d $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT ]
then
	rm -rf $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT
fi

mkdir -p $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT
mkdir -p $CORE_PATH/$PROJECT/TEMP/AGGREGATE

CREATE_PROJECT_INFO_ARRAY
FORMAT_AND_SCATTER_BAIT_BED
CREATE_GVCF_LIST

for BED_FILE in $(ls $CORE_PATH/$PROJECT/TEMP/BED_FILE_SPLIT/SPLITTED_BED_FILE*);
 do
BED_FILE_NAME=$(basename $BED_FILE .bed)
COMBINE_GVCF
GENOTYPE_GVCF
VARIANT_ANNOTATOR
GENERATE_CAT_VARIANTS_HOLD_ID
 done

CAT_VARIANTS
VARIANT_RECALIBRATOR_SNV
VARIANT_RECALIBRATOR_INDEL
APPLY_RECALIBRATION_SNV
APPLY_RECALIBRATION_INDEL
BGZIP_AND_TABIX_RECAL_VCF
CALCULATE_GENOTYPE_POSTERIORS
VARIANT_ANNOTATOR_REFINED
BGZIP_AND_TABIX_REFINED_VCF

for SAMPLE in $(awk 'BEGIN {FS=","} NR>1 {print $8}' $SAMPLE_SHEET | sort | uniq )
do
CREATE_SAMPLE_INFO_ARRAY
SELECT_PASSING_VARIANTS_PER_SAMPLE
BGZIP_AND_TABIX_SAMPLE_VCF
PASSING_VARIANTS_ON_TARGET_BY_SAMPLE
PASSING_SNVS_ON_BAIT_BY_SAMPLE
PASSING_SNVS_ON_TARGET_BY_SAMPLE
PASSING_INDELS_ON_BAIT_BY_SAMPLE
PASSING_INDELS_ON_TARGET_BY_SAMPLE
PASSING_SNVS_TITV_ALL
TITV_ALL
PASSING_SNVS_TITV_KNOWN
TITV_KNOWN
PASSING_SNVS_TITV_NOVEL
TITV_NOVEL
CONCORDANCE_ON_TARGET_PER_SAMPLE
done

GENERATE_STUDY_HAPMAP_SAMPLE_LISTS
SELECT_SNVS_ALL
SELECT_PASS_STUDY_ONLY_SNP
SELECT_PASS_HAPMAP_ONLY_SNP
SELECT_INDELS_ALL
SELECT_PASS_STUDY_ONLY_INDELS
SELECT_PASS_HAPMAP_ONLY_INDELS
SELECT_SNVS_ALL_PASS
SELECT_INDEL_ALL_PASS
