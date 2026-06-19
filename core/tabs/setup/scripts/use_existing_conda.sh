#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

if command -v conda >/dev/null 2>&1; then
	exe=$(command -v conda)
elif command -v mamba >/dev/null 2>&1; then
	exe=$(command -v mamba)
else
	echo "No existing conda executable was detected." >&2
	echo "Install conda yourself, or run Start Here -> Advanced manual setup -> Install private conda." >&2
	exit 1
fi

echo "Open Genome found an existing conda-compatible executable:"
echo "  $exe"
echo ""
echo "This records the path in your Open Genome manifest. It does not install or update anything."
printf 'Use this executable for Open Genome? [Y/n] '
read -r answer || true
case "${answer:-Y}" in
	n | N | no | NO)
		echo "No changes made."
		exit 0
		;;
esac

open_genome_bootstrap_manifest
open_genome_manifest_set conda.conda_exe "$exe"
open_genome_manifest_set conda.prefer_mamba false

echo "Configured conda executable:"
echo "  $exe"
echo ""
echo "Conda version:"
"$exe" --version 2>&1 || true
echo ""
echo "No tools were installed or updated."
