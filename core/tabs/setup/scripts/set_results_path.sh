#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

current=$(open_genome_manifest_get workflow.outdir)
if test -z "$current"; then
	current=$(open_genome_manifest_get results.report_dir)
fi
if test -z "$current"; then
	current=$(open_genome_workdir)
fi

path=$(open_genome_choose_path "Choose existing Open Genome results folder" dir "$current") || {
	echo "No results folder selected; keeping current setting." >&2
	exit 1
}
if ! test -d "$path"; then
	echo "Results path is not a directory: $path" >&2
	exit 1
fi

report=$(find "$path" -type f -name 'report_index.html' 2>/dev/null | sort | head -n 1 || true)
if test -z "$report"; then
	report=$(find "$path" -type f -name 'open_genome_report.html' 2>/dev/null | sort | head -n 1 || true)
fi
outdir=$path

if test -n "$report"; then
	report_dir=$(dirname -- "$report")
	case "$(basename -- "$report_dir")" in
		report) outdir=$(dirname -- "$report_dir") ;;
	esac
	open_genome_manifest_set results.report_dir "$report_dir"
	open_genome_manifest_set results.report_html "$report"
	if test -f "$report_dir/findings.tsv"; then
		open_genome_manifest_set results.findings_tsv "$report_dir/findings.tsv"
	fi
	if test -f "$report_dir/evidence.json"; then
		open_genome_manifest_set results.evidence_json "$report_dir/evidence.json"
	fi
else
	echo "No report_index.html or open_genome_report.html found under: $path" >&2
	echo "The results folder was still saved; Results -> Explain my results can list files there." >&2
fi

open_genome_manifest_set workflow.outdir "$outdir"

echo "Loaded existing results folder:"
echo "  $outdir"
if test -n "$report"; then
	echo "Report viewer:"
	echo "  $report"
fi
python3 "$OPEN_GENOME_MANIFEST_CLI" show
