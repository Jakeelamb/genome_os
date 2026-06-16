#!/usr/bin/env sh
set -e
if command -v picard >/dev/null 2>&1; then
	echo "picard on PATH"
	picard 2>&1 | head -n 3 || true
elif command -v gatk >/dev/null 2>&1; then
	echo "gatk on PATH (often bundles Picard-equivalent tasks)"
	gatk --version 2>&1 | head -n 3
else
	echo "picard / gatk: not on PATH"
fi
