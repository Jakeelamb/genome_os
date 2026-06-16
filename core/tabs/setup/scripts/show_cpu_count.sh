#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

cpus=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "?")
echo "Logical CPUs reported: $cpus"

open_genome_bootstrap_manifest
printf 'Optional: set max threads in manifest (empty to clear): '
read -r threads || true
open_genome_paths_set threads "${threads:-}"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
