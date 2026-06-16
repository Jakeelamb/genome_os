#!/usr/bin/env sh
set -e
echo "Nextflow / Java"
if command -v nextflow >/dev/null 2>&1; then
	nextflow -version 2>&1 | head -n 5
else
	echo "nextflow: not on PATH"
fi
if command -v java >/dev/null 2>&1; then
	java -version 2>&1 | head -n 1
else
	echo "java: not on PATH (Nextflow needs a JRE)"
fi
