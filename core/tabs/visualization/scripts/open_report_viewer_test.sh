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
export OPEN_GENOME_OPEN_REPORT_DRY_RUN=1

report_dir="$tmp/results/report"
scratch_dir="$tmp/results/nextflow-work-opengenome/cache"
mkdir -p "$OPEN_GENOME_CONFIG_DIR" "$report_dir" "$scratch_dir"
printf '<html>index</html>\n' >"$report_dir/report_index.html"
printf '<html>report</html>\n' >"$report_dir/open_genome_report.html"
printf '<html>scratch index</html>\n' >"$scratch_dir/report_index.html"
printf '<html>scratch</html>\n' >"$scratch_dir/open_genome_report.html"
printf 'sample\tfinding\n' >"$report_dir/findings.tsv"
printf '{}\n' >"$report_dir/evidence.json"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST"
python3 "$MANIFEST_CLI" set workflow.outdir "$tmp/results"
python3 "$MANIFEST_CLI" set results.report_html "$scratch_dir/open_genome_report.html"

output=$(bash "$HERE/open_report_viewer.sh")

if ! grep -q "$report_dir/report_index.html" <<<"$output"; then
	printf 'not ok - report viewer finds report under workflow.outdir\n%s\n' "$output" >&2
	exit 1
fi
if grep -q "nextflow-work" <<<"$output"; then
	printf 'not ok - report viewer should ignore scratch reports\n%s\n' "$output" >&2
	exit 1
fi
if [[ "$(python3 "$MANIFEST_CLI" get results.report_html)" != "$report_dir/report_index.html" ]]; then
	printf 'not ok - report viewer records report_html in manifest\n' >&2
	exit 1
fi

printf 'ok - report viewer finds and records existing HTML report\n'
