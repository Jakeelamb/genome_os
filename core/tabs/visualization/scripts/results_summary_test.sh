#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
MANIFEST_CLI="$REPO/core/tabs/open-genome/lib/manifest_cli.py"
DEFAULT_MANIFEST="$REPO/core/tabs/open-genome/manifest.default.toml"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export OPEN_GENOME_CONFIG_DIR="$tmp/config"
export XDG_DATA_HOME="$tmp/data"
export XDG_CACHE_HOME="$tmp/cache"

workdir="$tmp/work"
outdir="$workdir/open-genome-results"
report_dir="$outdir/report"
mkdir -p "$OPEN_GENOME_CONFIG_DIR" "$report_dir" "$outdir/annotations" "$outdir/nextflow-work-opengenome/cache"
printf '<html>index</html>\n' >"$report_dir/report_index.html"
printf '<html>report</html>\n' >"$report_dir/open_genome_report.html"
printf 'sample\tfinding\n' >"$report_dir/findings.tsv"
printf '{}\n' >"$report_dir/evidence.json"
printf '##fileformat=VCFv4.2\n' >"$outdir/annotations/sample.annotated.vcf"
printf '##scratch\n' >"$outdir/nextflow-work-opengenome/cache/internal.vcf"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST"
python3 "$MANIFEST_CLI" set paths.workdir "$workdir"
python3 "$MANIFEST_CLI" set workflow.outdir "$outdir"

output=$(bash "$HERE/results_summary.sh")

grep -q "Status: READY" <<<"$output"
grep -q "Nothing is uploaded" <<<"$output"
grep -q "Open the report: Results -> Open my report" <<<"$output"
grep -q "Raw variant files: 1" <<<"$output"
if grep -q "nextflow-work" <<<"$output"; then
	printf 'not ok - summary should hide Nextflow scratch paths\n%s\n' "$output" >&2
	exit 1
fi
if [[ "$(python3 "$MANIFEST_CLI" get results.report_html)" != "$report_dir/report_index.html" ]]; then
	printf 'not ok - summary records report_html in manifest\n' >&2
	exit 1
fi

printf 'ok - results summary is user-facing and hides scratch files\n'
