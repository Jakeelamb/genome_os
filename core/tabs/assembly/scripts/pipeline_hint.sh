#!/usr/bin/env sh
set -e
d=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
echo "Nextflow assembly: choose an nf-core workflow (e.g. nf-core/mag) or an in-house repo."
echo "Typical run pattern:"
echo "  nextflow run <pipeline> -profile <conda|docker|singularity> --input ... --outdir ..."
echo ""
sh "$d/check_nextflow.sh"
