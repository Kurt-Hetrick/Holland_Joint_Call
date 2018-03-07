#$ -S /bin/bash
#$ -q rnd.q,prod.q,test.q
#$ -cwd
#$ -V
#$ -p -1000

JAVA_1_7=$1
GATK_DIR=$2
REF_GENOME=$3
CORE_PATH=$4

PROJECT=$5
PREFIX=$6

START_APPLY_VQSR_SNV=`date '+%s'`

CMD=$JAVA_1_7'/java -jar'
CMD=$CMD' '$GATK_DIR'/GenomeAnalysisTK.jar'
CMD=$CMD' -T ApplyRecalibration'
CMD=$CMD' -R '$REF_GENOME
CMD=$CMD' --input:VCF '$CORE_PATH'/'$PROJECT'/MULTI_SAMPLE/'$PREFIX'.raw.HC.vcf'
CMD=$CMD' --ts_filter_level 99.9'
CMD=$CMD' -recalFile '$CORE_PATH'/'$PROJECT'/MULTI_SAMPLE/'$PREFIX'.HC.SNP.recal'
CMD=$CMD' -tranchesFile '$CORE_PATH'/'$PROJECT'/MULTI_SAMPLE/'$PREFIX'.HC.SNP.tranches'
CMD=$CMD' --disable_auto_index_creation_and_locking_when_reading_rods'
CMD=$CMD' -mode SNP'
CMD=$CMD' -o '$CORE_PATH'/'$PROJECT'/TEMP/'$PREFIX'.HC.SNP.VQSR.vcf'

END_APPLY_VQSR_SNV=`date '+%s'`

HOSTNAME=`hostname`

echo $PROJECT",F01,APPLY_VQSR_SNV,"$HOSTNAME","$START_APPLY_VQSR_SNV","$END_APPLY_VQSR_SNV \
>> $CORE_PATH/$PROJECT/REPORTS/$PROJECT".WALL.CLOCK.TIMES.csv"

echo $CMD >> $CORE_PATH/$PROJECT/command_lines.txt
echo >> $CORE_PATH/$PROJECT/command_lines.txt
echo $CMD | bash