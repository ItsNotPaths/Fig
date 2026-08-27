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
up="$root/vendor/omarchy/bin"

[ -d "$up" ] || { echo "no $up. Run ./download-deps.sh" >&2; exit 1; }

# Which of the three directories holds it. They are named by what the file is
# for, and a name appears in exactly one of them.
where() {
	for d in pkg setters helpers; do
		[ -f "$vendor/$d/$1" ] && { printf '%s' "$d"; return 0; }
	done
	return 1
}

one() {
	name=$1
	dir=$(where "$name") || { echo "$name: not vendored" >&2; return 1; }
	[ -f "$up/$name" ] || { echo "$name: not in the omarchy clone" >&2; return 1; }

	out="$here/$name.patch"
	if cmp -s "$up/$name" "$vendor/$dir/$name"; then
		rm -f "$out"
		echo "$name: same as upstream, no patch"
		return 0
	fi

	# The labels are what `git apply` reads, so they are the paths as seen
	# from vendor/ and not the paths these two files actually have.
	diff -u --label "a/$dir/$name" --label "b/$dir/$name" \
		"$up/$name" "$vendor/$dir/$name" > "$out" || true
	echo "$name: $(grep -c '^[+-][^+-]' "$out") changed lines"
}

if [ $# -gt 0 ]; then
	for n in "$@"; do one "$n"; done
else
	for p in "$here"/*.patch; do
		[ -e "$p" ] || { echo "no patches yet"; exit 0; }
		one "$(basename "$p" .patch)"
	done
fi
