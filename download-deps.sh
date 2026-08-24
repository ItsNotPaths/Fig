#!/bin/sh
# Get everything tildesh builds against. Run this once after you clone.
#
# Nothing here is source. vendor/ is gitignored, and anything in it can be
# deleted and fetched again.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
vendor="$root/vendor"

ISO_PROFILES=https://gitea.artixlinux.org/artix/iso-profiles.git

# Nerd Fonts publishes one archive a typeface. IosevkaTerm holds 81 TTFs and
# Artix's ttf-iosevkaterm-nerd installs every one, for 1141 MB. Four of them
# are the four a terminal draws.
NERD_VERSION=v3.5.1
NERD_FACES="Regular Bold Italic BoldItalic"

force=0
[ "${1:-}" = "--force" ] && force=1

say() { printf '==> %s\n' "$1"; }

mkdir -p "$vendor"

# --------------------------------------------------------- artix iso-profiles
#
# Reference only. buildiso reads profile/, never this. It is here so that
# `diff profile/common/common.yaml vendor/iso-profiles/common/common.yaml`
# shows what we dropped and what upstream added since.

dir="$vendor/iso-profiles"
if [ "$force" = 1 ]; then rm -rf "$dir"; fi
if [ -d "$dir/.git" ]; then
	say "iso-profiles: updating"
	git -C "$dir" pull --quiet --ff-only
else
	say "iso-profiles: cloning"
	git clone --quiet --depth 1 "$ISO_PROFILES" "$dir"
fi

# --------------------------------------------------------------- the font
#
# Mono and not the proportional or Term variant: every glyph is one cell wide,
# which is what a terminal and a wweft grid both assume.

dir="$vendor/fonts/iosevka"
if [ "$force" = 1 ]; then rm -rf "$dir"; fi
if [ -n "$(find "$dir" -name '*.ttf' 2>/dev/null | head -1)" ]; then
	say "iosevka: already present"
else
	say "iosevka: fetching IosevkaTerm $NERD_VERSION"
	mkdir -p "$dir"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fsSL -o "$tmp/iosevka.tar.xz" \
		"https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_VERSION/IosevkaTerm.tar.xz"

	want=""
	for face in $NERD_FACES; do
		want="$want IosevkaTermNerdFontMono-$face.ttf"
	done
	# shellcheck disable=SC2086
	tar xJf "$tmp/iosevka.tar.xz" -C "$dir" --wildcards $want
	rm -rf "$tmp"
	trap - EXIT
	say "iosevka: $(du -sh "$dir" | cut -f1) in $(find "$dir" -name '*.ttf' | wc -l) faces"
fi

say "done"
