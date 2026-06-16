#!/usr/bin/env sh
set -e
if command -v samtools >/dev/null 2>&1; then
	samtools 2>&1 | head -n 5
else
	echo "samtools: not on PATH"
fi
