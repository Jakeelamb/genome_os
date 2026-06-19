#!/usr/bin/env sh
set -e
_OG_LIB_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=open_genome_lib.sh
. "$_OG_LIB_DIR/open_genome_lib.sh"

open_genome_bootstrap_manifest
current=$(open_genome_paths_get workdir)
if test -z "$current" || open_genome_is_temp_script_path "$current"; then
	current=$(open_genome_default_workdir)
fi

while :; do
	path=$(open_genome_choose_path "Choose output and work folder" dir "$current") || {
		echo "No output folder selected; keeping current setting." >&2
		exit 1
	}
	if open_genome_is_yes_no_answer "$path"; then
		echo "That looks like a yes/no answer, not a folder path." >&2
		continue
	fi
	parent=$(open_genome_nearest_existing_parent "$path") || {
		echo "Could not find an existing parent folder for: $path" >&2
		continue
	}
	if ! test -w "$parent"; then
		echo "Nearest existing parent is not writable: $parent" >&2
		echo "Try a folder under your home directory, for example: $(open_genome_default_workdir)" >&2
		continue
	fi
	if mkdir -p "$path"; then
		break
	fi
	echo "Could not create output folder: $path" >&2
done

open_genome_paths_set workdir "$path"
python3 "$OPEN_GENOME_MANIFEST_CLI" show
