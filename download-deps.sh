#!/bin/sh
# Get everything tildesh builds against. Run this once after you clone.
#
# Nothing it writes is source. vendor/ is gitignored and so is everything this
# puts under DE-shell, and all of it can be deleted and fetched again.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
vendor="$root/vendor"

ISO_PROFILES=https://gitea.artixlinux.org/artix/iso-profiles.git

# The theme engine's data. The palettes, the templates and the setters are
# omarchy's, unmodified, so a theme written for omarchy works here and an
# upstream fix arrives as a diff. They are fetched rather than committed
# because they are 590 KB of somebody else's text, and because a pinned tag
# says which version we took better than a copy does.
OMARCHY=https://github.com/basecamp/omarchy.git
OMARCHY_VERSION=v4.0.0

# What we take out of it. A palette is every file at the top of its directory
# except the pictures: omarchy ships photographs and previews, and this image
# ships one mark in backgrounds/, which is ours. The setters are named one by
# one because the split between a setter and the helper it calls is ours.
OMARCHY_SETTERS="omarchy-theme-set-browser omarchy-theme-set-claude
omarchy-theme-set-keyboard omarchy-theme-set-obsidian omarchy-theme-set-pi
omarchy-theme-set-tmux omarchy-theme-set-vscode"
OMARCHY_HELPERS="omarchy-cmd-present omarchy-theme-color omarchy-theme-osc
omarchy-theme-refresh omarchy-theme-set-keyboard-asus-rog
omarchy-theme-set-keyboard-f16 omarchy-toggle-enabled"

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

# ------------------------------------------------------------- omarchy
#
# Into DE-shell, not vendor/, because the tree is what build-packages.sh reads
# and what a person edits beside. Every path written here is gitignored, and
# `DE-shell/vendor/check.sh` reports what has drifted since.

dir="$vendor/omarchy"
if [ "$force" = 1 ]; then rm -rf "$dir"; fi
if [ -d "$dir/.git" ]; then
	say "omarchy: already present"
else
	say "omarchy: cloning $OMARCHY_VERSION"
	rm -rf "$dir"
	git clone --quiet --depth 1 --branch "$OMARCHY_VERSION" "$OMARCHY" "$dir"
fi

shell="$root/DE-shell"
say "omarchy: palettes"
for t in "$dir"/themes/*/; do
	name=$(basename "$t")
	mkdir -p "$shell/themes/$name"
	for f in "$t"*; do
		[ -f "$f" ] || continue
		case "$f" in *.png | *.jpg | *.jpeg) continue ;; esac
		cp "$f" "$shell/themes/$name/"
	done
done

say "omarchy: templates"
mkdir -p "$shell/lib/theme/templates"
cp "$dir"/default/themed/*.tpl "$shell/lib/theme/templates/"

say "omarchy: setters"
mkdir -p "$shell/vendor/setters" "$shell/vendor/helpers"
for f in $OMARCHY_SETTERS; do cp "$dir/bin/$f" "$shell/vendor/setters/$f"; done
for f in $OMARCHY_HELPERS; do cp "$dir/bin/$f" "$shell/vendor/helpers/$f"; done
chmod +x "$shell/vendor/setters"/* "$shell/vendor/helpers"/*

say "done"
