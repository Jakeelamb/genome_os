#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
printf 'Work directory (scratch and outputs): '
read -r path || true
open_genome_paths_set workdir "$path"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
