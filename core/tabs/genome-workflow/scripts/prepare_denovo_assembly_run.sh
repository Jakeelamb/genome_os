#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
workdir=$(open_genome_workdir)
samplesheet=$(open_genome_manifest_get sample.samplesheet)
threads=$(open_genome_paths_get threads)
test -n "$threads" || threads=16
assembler_memory="${OPEN_GENOME_DENOVO_MEMORY:-88 GB}"

if test -z "$samplesheet" || ! test -f "$samplesheet"; then
	echo "Missing Open Genome samplesheet: ${samplesheet:-unset}" >&2
	echo "Run Start Here -> Start guided setup first, then choose a folder with PacBio HiFi or ONT long-read files." >&2
	exit 1
fi

denovo_rows=$(python3 - "$samplesheet" <<'PY'
import csv
import sys
from pathlib import Path

samplesheet = Path(sys.argv[1])
count = 0
missing = []
with samplesheet.open("r", encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle)
    if "input_type" not in (reader.fieldnames or []):
        print("samplesheet is missing input_type column", file=sys.stderr)
        sys.exit(2)
    if "long_reads" not in (reader.fieldnames or []):
        print("samplesheet is missing long_reads column; rescan your input folder with the current Open Genome version", file=sys.stderr)
        sys.exit(2)
    for index, row in enumerate(reader, start=2):
        if (row.get("input_type") or "").strip() != "denovo_reads":
            continue
        reads = (row.get("long_reads") or "").strip()
        if not reads:
            missing.append(str(index))
            continue
        if not Path(reads).is_file():
            missing.append(f"{index}:{reads}")
            continue
        count += 1

if missing:
    print("denovo_reads rows have missing long_reads files: " + ", ".join(missing), file=sys.stderr)
    sys.exit(2)
print(count)
PY
)

if test "$denovo_rows" -eq 0; then
	echo "No de novo assembly inputs were found in the current samplesheet." >&2
	echo "Choose a folder containing long-read files named with hifi, ccs, pacbio, revio, ont, nanopore, or ultralong." >&2
	echo "Examples: HG002.hifi_reads.fastq.gz, sample.ccs.bam, sample.nanopore.fastq.gz" >&2
	exit 1
fi

outdir=$(open_genome_manifest_get workflow.denovo_outdir)
if test -z "$outdir"; then
	outdir="$workdir/denovo-assembly-results"
fi
pipeline_dir="$OPEN_GENOME_BUNDLE/pipelines/denovo-assembly"
mkdir -p "$outdir" "$workdir/nextflow-work-denovo-assembly" "$workdir/bin"

command_file="$workdir/bin/run_denovo_assembly_pipeline.sh"
params_file="$workdir/denovo-assembly.params.txt"
log_file="$workdir/denovo-assembly.nextflow.log"

cat >"$params_file" <<EOF
samplesheet=$samplesheet
outdir=$outdir
assembler_threads=$threads
assembler_memory=$assembler_memory
EOF

{
	printf '#!/usr/bin/env bash\n'
	printf 'set -euo pipefail\n'
	printf 'export NXF_HOME=%q\n' "$workdir/.nextflow"
	printf 'export NXF_CONDA_CACHEDIR=%q\n' "$workdir/nextflow-conda-cache"
	printf 'export NXF_SYNTAX_PARSER="${NXF_SYNTAX_PARSER:-v1}"\n'
	conda_exe=$(open_genome_manifest_get conda.conda_exe)
	if test -n "$conda_exe"; then
		printf 'export PATH=%q:$PATH\n' "$(dirname "$conda_exe")"
	fi
	printf 'nextflow -log %q run %q -profile opengenome -resume -w %q \\\n' "$log_file" "$pipeline_dir" "$workdir/nextflow-work-denovo-assembly"
	printf '  --samplesheet %q \\\n' "$samplesheet"
	printf '  --outdir %q \\\n' "$outdir"
	printf '  --assembler_threads %q \\\n' "$threads"
	printf '  --assembler_memory %q\n' "$assembler_memory"
} >"$command_file"
chmod 700 "$command_file"

open_genome_manifest_set workflow.engine denovo-assembly
open_genome_manifest_set workflow.pipeline_version v1
open_genome_manifest_set workflow.denovo_outdir "$outdir"
open_genome_manifest_set workflow.denovo_params_file "$params_file"
open_genome_manifest_set workflow.denovo_command_file "$command_file"

echo "Prepared Open Genome de novo assembly command:"
echo "  $command_file"
echo ""
echo "Samples ready for de novo assembly: $denovo_rows"
echo "Assembler: hifiasm"
echo "Best input: PacBio HiFi/CCS reads. ONT reads are accepted, but may need a future ONT-specific mode for best quality."
echo ""
sed -n '1,120p' "$command_file"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
