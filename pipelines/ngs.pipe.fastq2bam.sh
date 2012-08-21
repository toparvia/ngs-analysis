#!/bin/bash
## 
## DESCRIPTION:   Trim, align, merge, recalibrate, realign, dedup
##                Assume single sample per lane
##
## USAGE:         ngs.pipe.fastq2bam.wes.sh
##                                            Sample_X(Sample directory)
##                                            ref.fa
##                                            dbsnp.vcf
##                                            mills.indel.sites.vcf
##                                            1000G.indel.vcf
##
## OUTPUT:        sample.bam
##

# Load analysis config
source $NGS_ANALYSIS_CONFIG

# Check correct usage
usage 5 $# $0

# Process input params
SAMPLEDIR=$1
REFERENCE=$2
DBSNP_VCF=$3
MILLS_INDEL_VCF=$4
INDEL_1000G_VCF=$5

# Set up pipeline variables
SAMPLENAME=`echo $SAMPLEDIR | cut -f2- -d'_'`
FASTQ_R1=`ls $SAMPLEDIR/*_*_L???_R1_???.fastq.gz` # Samplename_AAAAAA_L00N_R1_001.fastq.gz
FASTQ_R2=`ls $SAMPLEDIR/*_*_L???_R2_???.fastq.gz` # Samplename_AAAAAA_L00N_R2_001.fastq.gz
FASTQ_SE=`echo $FASTQ_R1 | sed 's/R1/SE/'`
SAMPLE_PREFIX=`$PYTHON $NGS_ANALYSIS_DIR/modules/util/illumina_fastq_extract_samplename.py $FASTQ_R1`

#==[ Fastq QC ]=====================================================================#

ngs.pipe.fastq.qc.sh $FASTQ_R1 $FASTQ_R2

#==[ Trim ]=========================================================================#

$NGS_ANALYSIS_DIR/modules/seq/sickle.pe.sh                   \
  $FASTQ_R1                                                  \
  $FASTQ_R2

#==[ Align ]========================================================================#

# Align
$NGS_ANALYSIS_DIR/modules/align/bwa.aln.sh                   \
  $FASTQ_R1.trimmed.fastq                                    \
  $SAMPLE_PREFIX.R1                                          \
  $REFERENCE
$NGS_ANALYSIS_DIR/modules/align/bwa.aln.sh                   \
  $FASTQ_R2.trimmed.fastq                                    \
  $SAMPLE_PREFIX.R2                                          \
  $REFERENCE
$NGS_ANALYSIS_DIR/modules/align/bwa.aln.sh                   \
  $FASTQ_SE.trimmed.fastq                                    \
  $SAMPLE_PREFIX.SE                                          \
  $REFERENCE

# Create sam
$NGS_ANALYSIS_DIR/modules/align/bwa.sampe.sh                 \
  $SAMPLE_PREFIX.R1.sai                                      \
  $SAMPLE_PREFIX.R2.sai                                      \
  $FASTQ_R1.trimmed.fastq                                    \
  $FASTQ_R2.trimmed.fastq                                    \
  $REFERENCE
$NGS_ANALYSIS_DIR/modules/align/bwa.samse.sh                 \
  $SAMPLE_PREFIX.SE.sai                                      \
  $FASTQ_SE.trimmed.fastq                                    \
  $REFERENCE

# Create bam
$NGS_ANALYSIS_DIR/modules/align/samtools.sam2sortedbam.sh    \
  $SAMPLE_PREFIX.PE.sam.gz
$NGS_ANALYSIS_DIR/modules/align/samtools.sam2sortedbam.sh    \
  $SAMPLE_PREFIX.SE.sam.gz

#==[ Process bam file ]=============================================================#

# Merge paired and single end bam files
$NGS_ANALYSIS_DIR/modules/align/samtools.mergebam.sh         \
  $SAMPLE_PREFIX.merged                                      \
  $SAMPLE_PREFIX.PE.sorted.bam                               \
  $SAMPLE_PREFIX.SE.sorted.bam

# Sort
$NGS_ANALYSIS_DIR/modules/align/picard.sortsam.sh            \
  $SAMPLE_PREFIX.merged.bam

# Add read group to bam file
$NGS_ANALYSIS_DIR/modules/align/picard.addreadgroup.sh       \
  $SAMPLE_PREFIX.merged.sorted.bam                           \
  $SAMPLENAME

# Dedup, realign, recalibrate
$NGS_ANALYSIS_DIR/pipelines/ngs.pipe.dedup.realign.recal.sh  \
  $SAMPLE_PREFIX.merged.sorted.rg.bam                        \
  $REFERENCE                                                 \
  $DBSNP_VCF                                                 \
  $MILLS_INDEL_VCF                                           \
  $INDEL_1000G_VCF