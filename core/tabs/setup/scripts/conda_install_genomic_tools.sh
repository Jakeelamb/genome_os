#!/usr/bin/env sh
set -e
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
TABS=$(CDPATH= cd -- "$HERE/../.." && pwd)
export OPEN_GENOME_BUNDLE="$TABS/open-genome"
exec bash "$OPEN_GENOME_BUNDLE/lib/conda_install_module.sh" genomic_tools
