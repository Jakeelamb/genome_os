#!/usr/bin/env sh
set -e
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
TABS=$(CDPATH= cd -- "$HERE/../.." && pwd)
BUNDLE="$TABS/open-genome"
echo "Bundled modules under $BUNDLE/modules:"
for d in "$BUNDLE/modules"/*/; do
	test -d "$d" || continue
	id=$(basename "$d")
	if test -f "$d/module.toml"; then
		printf "  - %s\n" "$id"
		sed -n '1,4p' "$d/module.toml" | sed 's/^/      /'
	else
		echo "  - $id (no module.toml)"
	fi
	echo ""
done
