#!/usr/bin/env sh
set -e
command -v gatk >/dev/null 2>&1 && gatk --list 2>&1 | head -n 5 || echo "gatk: not on PATH"
