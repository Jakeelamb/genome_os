#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TABS=$(CDPATH= cd -- "$HERE/../.." && pwd)
export OPEN_GENOME_BUNDLE="$TABS/open-genome"

modules="
opengenome
"

echo "Installing/updating the recommended Open Genome conda environment."
echo "This downloads public tool packages only; it does not upload genome data."
for module in $modules; do
	echo ""
	echo "== $module =="
	bash "$OPEN_GENOME_BUNDLE/lib/conda_install_module.sh" "$module"
done

echo ""
echo "Recommended environment is installed or updated."
