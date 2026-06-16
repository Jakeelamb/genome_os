#!/usr/bin/env sh
set -e
if command -v bwa >/dev/null 2>&1; then
	bwa 2>&1 | head -n 3
else
	echo "bwa: not on PATH"
fi
