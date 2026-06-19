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

results="$tmp/existing-results"
report_dir="$results/report"
mkdir -p "$OPEN_GENOME_CONFIG_DIR" "$report_dir"
printf '<html>index</html>\n' >"$report_dir/report_index.html"
printf '<html>report</html>\n' >"$report_dir/open_genome_report.html"
printf 'sample\tfinding\n' >"$report_dir/findings.tsv"
printf '{}\n' >"$report_dir/evidence.json"

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST"
OPEN_GENOME_SELECTED_PATH="$results" sh "$HERE/set_results_path.sh" >/dev/null

assert_eq() {
	local expected=$1
	local actual=$2
	local label=$3
	if [[ "$actual" != "$expected" ]]; then
		printf 'not ok - %s\nexpected: %s\nactual:   %s\n' "$label" "$expected" "$actual" >&2
		exit 1
	fi
}

assert_eq "$results" "$(python3 "$MANIFEST_CLI" get workflow.outdir)" "sets workflow output directory"
assert_eq "$report_dir" "$(python3 "$MANIFEST_CLI" get results.report_dir)" "sets report directory"
assert_eq "$report_dir/report_index.html" "$(python3 "$MANIFEST_CLI" get results.report_html)" "sets HTML report path"
assert_eq "$report_dir/findings.tsv" "$(python3 "$MANIFEST_CLI" get results.findings_tsv)" "sets findings table"
assert_eq "$report_dir/evidence.json" "$(python3 "$MANIFEST_CLI" get results.evidence_json)" "sets evidence JSON"

printf 'ok - set results path records existing report outputs\n'
