#!/bin/bash
#
#SBATCH --job-name=pbsv
#SBATCH -p lo_mem
#SBATCH -w maggie
#SBATCH -c 16
#SBATCH -o pbsv.%j.out
#SBATCH -e pbsv.%j.err


date

source ~/scripts/activate_conda

# Directories and files
# Program will copy the files to the 
AKHAL_DIR=/home/akmuhammet/programs/akhal

PACBIO_SUB_FA=/home/akmuhammet/data/hg002/hg002v1.0.1_hifi_revio_pbmay24.chr1_10_22.subsampled.fa
ONT_SUB_FA=/home/akmuhammet/data/hg002/hg002v1.0_ont_r10_ul_dorado.chr1_10_22.subsampled.fa

pbsv_run() {
    local graph=$1
    local fa=$2
    local reads=$3  
    local hg38=$4
    local hg002=$5
    local out="pbsv.$hg002.$reads.$graph.out"

    /bin/time -v ${AKHAL_DIR}/akhal gaf2sam \
        "$hg38.pggb.$graph.gfa" \
        "$hg002.$reads.$graph.gaf"  \
        "$fa" \
        "$hg002.$reads.$graph.sam" \
        --simple > "$out" 2>&1
    
    /bin/time -v ${AKHAL_DIR}/akhal sampoke \
        "$hg38.fa" \
        "$hg002.$reads.$graph.sam" \
        "$hg002.$reads.$graph.qual.sam" >> "$out" 2>&1
    rm -f "$hg002.$reads.$graph.sam"

    samtools view -@ 16 -bS "$hg002.$reads.$graph.qual.sam" | samtools sort -@ 16 -m 2G --reference "$hg38.fa" -o "$hg002.$reads.$graph.bam" && samtools index "$hg002.$reads.$graph.bam" >> "$out" 2>&1
    rm -f "$hg002.$reads.$graph.qual.sam"

    pbsv discover "$hg002.$reads.$graph.bam" "$hg002.$reads.$graph.svsig.gz"
    pbsv call -j 16 -t DEL,INS,INV -m 20 -A 3 -O 3 --call-min-read-perc-one-sample 20 "$hg38.fa" "$hg002.$reads.$graph.svsig.gz" "$hg002.$reads.$graph.vcf"
    rm -f "$hg002.$reads.$graph.svsig.gz"

    bcftools query -f '%CHROM\t%POS0\t%END\n' "$hg002.$reads.$graph.vcf" > "$hg002.$reads.$graph.bed"

    local GOLD="HG002_GRCh38.chr1_10_22.pbsv.expanded.bed"
    local GOLD_COUNT=$(wc -l < "$GOLD")
    local PRED="$hg002.$reads.$graph.bed"
    
    local FN=$(bedtools intersect -a "$GOLD" -b "$PRED" -v | wc -l)
    local TP=$((GOLD_COUNT - FN))
    local FP=$(bedtools intersect -v -a "$PRED" -b "$GOLD" | wc -l)

    local PRECISION=$(echo "scale=5; $TP / ($TP + $FP)" | bc)
    local RECALL=$(echo "scale=5; $TP / ($TP + $FN)" | bc)
    local F1=$(echo "scale=5; 2 * $PRECISION * $RECALL / ($PRECISION + $RECALL)" | bc)

    echo -e "$reads.$graph\t${TP}\t${FP}\t${FN}\t0${PRECISION}\t0${RECALL}\t0${F1}" >> "stats.txt"
}

### ---------------------------------------------------------------------------------
### ---------------------------------------------------------------------------------
### Alignment experiment (chr1_10_22)
### ---------------------------------------------------------------------------------
### ---------------------------------------------------------------------------------

PREFIX="hg38.chr1_10_22"

echo -e "Method\tTP\tFP\tFN\tPrecision\tRecall\tF1" >> "stats.txt"

## Pacbio-HiFi SV detection
echo "Pacbio-HiFi pbsv"
pbsv_run "lcpan" "$PACBIO_SUB_FA" "hifi" "$PREFIX" "hg002.chr1_10_22"
pbsv_run "vg" "$PACBIO_SUB_FA" "hifi" "$PREFIX" "hg002.chr1_10_22"

## ONT SV detection
echo "ONT pbsv"
pbsv_run "lcpan" "$ONT_SUB_FA" "ont" "$PREFIX" "hg002.chr1_10_22"
pbsv_run "vg" "$ONT_SUB_FA" "ont" "$PREFIX" "hg002.chr1_10_22"

conda deactivate

date