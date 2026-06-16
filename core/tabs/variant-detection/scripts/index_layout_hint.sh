#!/usr/bin/env sh
set -e
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
TABS=$(CDPATH= cd -- "$HERE/../.." && pwd)
BUNDLE="$TABS/open-genome"
CLI="$BUNDLE/lib/manifest_cli.py"

if ! test -f "$CLI"; then
	echo "Open Genome bundle not found at $BUNDLE" >&2
	exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
	echo "python3 required" >&2
	exit 1
fi

USER_MANIFEST="${XDG_CONFIG_HOME:-$HOME/.config}/open-genome/manifest.toml"
if ! test -f "$USER_MANIFEST"; then
	echo "Manifest not initialized; use Setup -> Show saved paths first."
	ref=""
else
	ref=$(python3 "$CLI" get paths.reference)
fi

echo "Reference from manifest: ${ref:-<unset>}"
echo ""
echo "Typical indexed layout next to reference FASTA:"
echo "  reference.fa  reference.fa.fai  reference.dict"
echo "  BWA: reference.fa.{amb,ann,bwt,pac,sa}"
echo "  samtools faidx produces .fai; Picard CreateSequenceDictionary produces .dict"
