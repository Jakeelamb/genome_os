#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
fasta=$(open_genome_manifest_get reference.fasta)
dbsnp=$(open_genome_manifest_get reference.dbsnp)

printf 'Existing coordinate-sorted BAM/CRAM path: '
read -r input || true
if test -z "$input" || ! test -f "$input"; then
	echo "Input BAM/CRAM does not exist." >&2
	exit 1
fi
if test -z "$fasta" || ! test -f "$fasta"; then
	echo "Reference FASTA is missing; configure/fetch/index GRCh38 first." >&2
	exit 1
fi

sample=$(basename "$input")
sample=${sample%.bam}
sample=${sample%.cram}
outdir="$workdir/gatk-existing-bam/$sample"
mkdir -p "$outdir"
command_file="$outdir/run_haplotypecaller.sh"
vcf="$outdir/$sample.g.vcf.gz"

{
	printf '#!/usr/bin/env bash\n'
	printf 'set -euo pipefail\n'
	printf 'gatk HaplotypeCaller -R %q -I %q -O %q -ERC GVCF' "$fasta" "$input" "$vcf"
	if test -n "$dbsnp" && test -f "$dbsnp"; then
		printf ' --dbsnp %q' "$dbsnp"
	fi
	printf '\n'
} >"$command_file"
chmod 700 "$command_file"

echo "Generated expert GATK command file:"
echo "  $command_file"
echo ""
sed -n '1,80p' "$command_file"
echo ""
echo "Run inside the opengenome environment after reviewing."
