#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

dataset_dir=/tmp/open-genome-human-real-set/sequencing
workdir=/tmp/open-genome-human-real-work
samplesheet=$workdir/samples/open_genome_samplesheet.csv
vcf=$dataset_dir/HG002_GRCh38_1_22_v4.2.1_benchmark.vcf.gz
tbi=$vcf.tbi

echo "Try sample data"
echo ""
echo "This wires the public GIAB/NIST HG002 benchmark VCF as the Open Genome input dataset."
echo "It does not set or replace the reference genome path."
echo ""

if ! test -s "$vcf" || ! test -s "$tbi"; then
	echo "Missing real HG002 dataset files under:"
	echo "  $dataset_dir"
	echo ""
	echo "Expected:"
	echo "  $vcf"
	echo "  $tbi"
	echo ""
	echo "Create the dataset first, or re-run the dataset preparation step used during debugging." >&2
	exit 1
fi

open_genome_bootstrap_manifest
mkdir -p "$workdir/samples"
open_genome_paths_set workdir "$workdir"

python3 "$OPEN_GENOME_BUNDLE/lib/sample_scan.py" "$dataset_dir" --out "$samplesheet"

echo ""
echo "Debug dataset configured:"
echo "  Work folder: $workdir"
echo "  Dataset:     $dataset_dir"
echo "  Samplesheet: $samplesheet"
echo ""
echo "Reference was not changed. Use Start Here -> Advanced manual setup to choose or download a reference separately."
python3 "$OPEN_GENOME_MANIFEST_CLI" show
