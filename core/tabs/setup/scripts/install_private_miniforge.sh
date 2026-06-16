#!/usr/bin/env bash
set -euo pipefail

HERE=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_OG_LIB_DIR="$HERE"
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest

root=$(open_genome_manifest_get conda.install_root)
if test -z "$root"; then
	root="$(open_genome_data_dir)/miniforge"
fi

case "$(uname -s)-$(uname -m)" in
	Linux-x86_64) asset="Miniforge3-Linux-x86_64.sh" ;;
	Linux-aarch64 | Linux-arm64) asset="Miniforge3-Linux-aarch64.sh" ;;
	Darwin-x86_64) asset="Miniforge3-MacOSX-x86_64.sh" ;;
	Darwin-arm64) asset="Miniforge3-MacOSX-arm64.sh" ;;
	*)
		echo "Unsupported platform for automatic Miniforge install: $(uname -s)-$(uname -m)" >&2
		exit 1
		;;
esac

conda_bin="$root/bin/conda"
mamba_bin="$root/bin/mamba"
if test -x "$conda_bin" || test -x "$mamba_bin"; then
	echo "Private Miniforge already exists: $root"
else
	echo "Open Genome will install private Miniforge under:"
	echo "  $root"
	echo ""
	echo "This downloads public installer code only; it does not upload genome data."
	printf 'Continue? [y/N] '
	read -r answer || true
	case "$answer" in
		y | Y | yes | YES) ;;
		*) echo "Aborted."; exit 0 ;;
	esac

	tmp_dir=$(mktemp -d)
	trap 'rm -rf "$tmp_dir"' EXIT
	installer="$tmp_dir/$asset"
	url="https://github.com/conda-forge/miniforge/releases/latest/download/$asset"
	if command -v curl >/dev/null 2>&1; then
		curl -L --fail --show-error --output "$installer" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "$installer" "$url"
	else
		echo "curl or wget is required to download Miniforge." >&2
		exit 1
	fi
	bash "$installer" -b -p "$root"
fi

if test -x "$conda_bin"; then
	exe="$conda_bin"
elif test -x "$mamba_bin"; then
	exe="$mamba_bin"
else
	echo "Install completed but no conda/mamba executable was found under $root/bin" >&2
	exit 1
fi

open_genome_manifest_set conda.install_root "$root"
open_genome_manifest_set conda.conda_exe "$exe"
open_genome_manifest_set conda.prefer_mamba false

echo "Configured Open Genome conda executable:"
echo "  $exe"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
