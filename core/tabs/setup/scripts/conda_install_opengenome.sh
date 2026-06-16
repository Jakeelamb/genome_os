#!/usr/bin/env bash
set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TABS=$(CDPATH= cd -- "$HERE/../.." && pwd)
export OPEN_GENOME_BUNDLE="$TABS/open-genome"
exec bash "$OPEN_GENOME_BUNDLE/lib/conda_install_module.sh" opengenome
