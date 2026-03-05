#!/bin/bash
#
#SBATCH --job-name=pbsv
#SBATCH -p hi_end
#SBATCH -w marge
#SBATCH -c 16
#SBATCH -o pbsv.%j.out
#SBATCH -e pbsv.%j.err


date

source ~/scripts/activate_conda

# Directories and files
# Program will copy the files to the 
AKHAL_DIR=/home/akmuhammet/programs/akhal

HG002_VCF=/home/akmuhammet/data/hg002/HG002_GRCh38.pbsv.vcf.gz
PACBIO_FA=/home/akmuhammet/data/hg002/hg002v1.0.1_hifi_revio_pbmay24.fa

# cp -r /tmp/lcpan/alignment/human_v38.pggb.lcpan.gfa ~/programs/lcpan/results/latest/alignment/

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

    samtools view -bo "$hg002.$reads.$graph.bam" "$hg002.$reads.$graph.qual.sam"
    rm -f "$hg002.$reads.$graph.qual.sam"

    samtools sort -@ 16 -o "$hg002.$reads.$graph.sorted.bam" "$hg002.$reads.$graph.bam" 
    rm -rf "$hg002.$reads.$graph.bam"
    mv "$hg002.$reads.$graph.sorted.bam" "$hg002.$reads.$graph.bam"
    samtools index -@ 16 "$hg002.$reads.$graph.bam"
    
    pbsv discover "$hg002.$reads.$graph.bam" "$hg002.$reads.$graph.svsig.gz"
    pbsv call -j 16 -t DEL,INS,INV -m 20 -A 3 -O 3 --call-min-read-perc-one-sample 20 "$hg38.fa" "$hg002.$reads.$graph.svsig.gz" "$hg002.$reads.$graph.vcf"
    rm -f "$hg002.$reads.$graph.svsig.gz"

    bcftools query -f '%CHROM\t%POS0\t%END\n' "$hg002.$reads.$graph.vcf" > "$hg002.$reads.$graph.bed"

    local GOLD="HG002_GRCh38.pbsv.expanded.bed"
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
### Alignment experiment
### ---------------------------------------------------------------------------------
### ---------------------------------------------------------------------------------

PREFIX="human_v38"

echo -e "Method\tTP\tFP\tFN\tPrecision\tRecall\tF1" >> "stats.txt"

if [ ! -f "HG002_GRCh38.pbsv.expanded.bed" ]; then
    bcftools query -f '%CHROM\t%POS0\t%END\n' $HG002_VCF > HG002_GRCh38.pbsv.bed

    awk '{print $1"\t"$2}' "$PREFIX.fa.fai" > "$PREFIX.txt"
    bedtools slop -i HG002_GRCh38.pbsv.bed -g "$PREFIX.txt" -b 100 > HG002_GRCh38.pbsv.expanded.bed
    rm -f "$PREFIX.txt" HG002_GRCh38.pbsv.bed
fi

## Pacbio-HiFi SV detection
echo "Pacbio-HiFi pbsv"
pbsv_run "lcpan" "$PACBIO_FA" "hifi" "$PREFIX" "hg002"
# pbsv_run "vg" "$PACBIO_FA" "hifi" "$PREFIX" "hg002"

conda deactivate

date
