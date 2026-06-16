#!/usr/bin/env bash
# Create or update a locked conda env from modules/<id>/environment.yml
set -euo pipefail

MODULE_ID=${1:?usage: conda_install_module.sh <module_id>}
HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export OPEN_GENOME_BUNDLE=$(CDPATH= cd -- "$HERE/.." && pwd)
ENV_YML="$OPEN_GENOME_BUNDLE/modules/$MODULE_ID/environment.yml"
MANIFEST_CLI="$OPEN_GENOME_BUNDLE/lib/manifest_cli.py"
DEFAULT_MANIFEST="$OPEN_GENOME_BUNDLE/manifest.default.toml"

if ! test -f "$ENV_YML"; then
	echo "Unknown module '$MODULE_ID' (missing $ENV_YML)" >&2
	exit 1
fi

python3 "$MANIFEST_CLI" init "$DEFAULT_MANIFEST" || true
python3 "$MANIFEST_CLI" bootstrap "$DEFAULT_MANIFEST" || true

# shellcheck source=conda_resolve.sh
source "$HERE/conda_resolve.sh"

echo "Environment file: $ENV_YML"
env_name=$(grep -E '^name:' "$ENV_YML" | head -n1 | sed 's/^name:[[:space:]]*//;s/[[:space:]]*$//')
if test -z "$env_name"; then
	echo "environment.yml must declare a top-level 'name:'" >&2
	exit 1
fi

if "$OG_CONDA_EXE" env list 2>/dev/null | awk '{print $1}' | grep -qx "$env_name"; then
	echo "Updating existing env: $env_name"
	"$OG_CONDA_EXE" env update -n "$env_name" -f "$ENV_YML"
else
	echo "Creating env: $env_name"
	"$OG_CONDA_EXE" env create -f "$ENV_YML"
fi

echo "Done. Activate with: $OG_CONDA_EXE activate $env_name  (conda hook required)"
