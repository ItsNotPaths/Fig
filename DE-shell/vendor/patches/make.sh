#!/bin/sh
# Turn an edit you already made into a patch this tree keeps.
#
#   1. edit DE-shell/vendor/pkg/omarchy-pkg-install
#   2. ./DE-shell/vendor/patches/make.sh omarchy-pkg-install
#
# The pristine copy is vendor/omarchy/, which download-deps.sh cloned at the
# pinned tag, so the diff is always against the version we took and never
# against whatever is installed on this machine.
#
# With no argument it remakes every patch that already exists, which is what
# to run after moving the omarchy pin.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
vendor=$(dirname "$here")
root=$(CDPATH= cd -- "$vendor/../.." && pwd)
up="$root/vendor/omarchy"

[ -d "$up/bin" ] || { echo "no $up/bin. Run ./download-deps.sh" >&2; exit 1; }

# Which directory holds it. They are named by what the file is for, and a name
# appears in exactly one of them. hw/scripts holds subdirectories, so a name
# there may be `intel/thermald.sh` and not a bare basename.
where() {
	for d in pkg setters helpers hw/bin hw/scripts; do
		[ -f "$vendor/$d/$1" ] && { printf '%s' "$d"; return 0; }
	done
	return 1
}

# Where the pristine copy of that file is in the clone. Everything is under
# bin/ except the hardware scripts, which upstream keeps in install/hardware/.
pristine() {
	case "$1" in
	hw/scripts) printf '%s' "$up/install/hardware" ;;
	*)          printf '%s' "$up/bin" ;;
	esac
}

one() {
	name=$1
	dir=$(where "$name") || { echo "$name: not vendored" >&2; return 1; }
	src=$(pristine "$dir")/$name
	[ -f "$src" ] || { echo "$name: not in the omarchy clone" >&2; return 1; }

	# A name may carry a directory, so the patch file cannot.
	out="$here/$(echo "$name" | tr / -).patch"
	if cmp -s "$src" "$vendor/$dir/$name"; then
		rm -f "$out"
		echo "$name: same as upstream, no patch"
		return 0
	fi

	# The labels are what `git apply` reads, so they are the paths as seen
	# from vendor/ and not the paths these two files actually have.
	diff -u --label "a/$dir/$name" --label "b/$dir/$name" \
		"$src" "$vendor/$dir/$name" > "$out" || true
	echo "$name: $(grep -c '^[+-][^+-]' "$out") changed lines"
}

if [ $# -gt 0 ]; then
	for n in "$@"; do one "$n"; done
else
	for p in "$here"/*.patch; do
		[ -e "$p" ] || { echo "no patches yet"; exit 0; }
		# A patch names its target on its first line, so the file name does
		# not have to survive the round trip. Reading it back beats guessing
		# where a `/` became a `-`, which fails on any name holding a dash.
		t=$(sed -n '1s|^--- a/||p' "$p")
		[ -n "$t" ] || { echo "$(basename "$p"): no ---, skipped" >&2; continue; }
		case "$t" in
		hw/bin/*)     one "${t#hw/bin/}" ;;
		hw/scripts/*) one "${t#hw/scripts/}" ;;
		*)            one "${t#*/}" ;;
		esac
	done
fi
