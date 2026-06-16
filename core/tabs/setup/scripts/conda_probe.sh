#!/usr/bin/env bash
set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TABS=$(CDPATH= cd -- "$HERE/../.." && pwd)
export OPEN_GENOME_BUNDLE="$TABS/open-genome"
# shellcheck source=../open-genome/lib/conda_resolve.sh
source "$OPEN_GENOME_BUNDLE/lib/conda_resolve.sh"
"$OG_CONDA_EXE" --version 2>&1 || true
