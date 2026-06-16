#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR=$(CDPATH= cd -- "$HERE/../../setup/scripts" && pwd)
# shellcheck source=../../setup/scripts/open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
command_file=$(open_genome_manifest_get workflow.command_file)
if test -z "$command_file" || ! test -f "$command_file"; then
	echo "No Sarek command file found. Run 'Prepare Sarek germline run' first." >&2
	exit 1
fi

echo "About to run local Sarek command:"
echo "  $command_file"
echo ""
echo "This runs on local files. Nextflow may download public pipeline/tool dependencies."
printf 'Continue? [y/N] '
read -r answer || true
case "$answer" in
	y | Y | yes | YES) ;;
	*) echo "Aborted."; exit 0 ;;
esac

open_genome_resolve_conda
export PATH="$(dirname "$OG_CONDA_EXE"):$PATH"
workdir=$(open_genome_workdir)
open_genome_manifest_set workflow.last_run_dir "$workdir/nextflow-work"
"$OG_CONDA_EXE" run -n opengenome bash "$command_file"
