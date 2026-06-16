#!/usr/bin/env bash
# Resolve conda. Requires OPEN_GENOME_BUNDLE.
set -euo pipefail

if test -z "${OPEN_GENOME_BUNDLE:-}"; then
	echo "OPEN_GENOME_BUNDLE is not set" >&2
	exit 1
fi

MANIFEST_CLI="$OPEN_GENOME_BUNDLE/lib/manifest_cli.py"
USER_MANIFEST="${OPEN_GENOME_CONFIG_DIR:-$HOME/.config/open-genome}/manifest.toml"

if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 is required." >&2
	exit 1
fi

exe_override=""
if test -f "$USER_MANIFEST"; then
	exe_override=$(python3 "$MANIFEST_CLI" get conda.conda_exe 2>/dev/null || true)
fi

if test -n "${exe_override:-}"; then
	export OG_CONDA_EXE="$exe_override"
elif command -v conda >/dev/null 2>&1; then
	export OG_CONDA_EXE="conda"
elif command -v mamba >/dev/null 2>&1; then
	export OG_CONDA_EXE="mamba"
else
	echo "Neither conda nor mamba found on PATH (set conda.conda_exe in $USER_MANIFEST)." >&2
	exit 1
fi

echo "Using: $OG_CONDA_EXE"
