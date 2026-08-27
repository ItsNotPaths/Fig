#!/bin/sh
# Get everything fig builds against. Run this once after you clone.
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

# The package tools. Four are scriptable and answer a question about what is
# installed; three are fzf panels a person drives. They call each other by
# name, so all of them go on PATH, and so do the two helpers the panels source.
OMARCHY_PKG="omarchy-pkg-add omarchy-pkg-aur-accessible omarchy-pkg-aur-add
omarchy-pkg-aur-install omarchy-pkg-drop omarchy-pkg-install
omarchy-pkg-missing omarchy-pkg-present omarchy-pkg-remove
omarchy-show-done omarchy-sudo-keepalive"

# yay and mise. Neither is in an Artix repo, and neither is worth compiling:
# both publish a prebuilt x86_64 binary with every release. packaging/ wraps
# what lands here, the same way it wraps the font.
#
# mise is taken as the musl build, which is static-pie and links nothing. The
# glibc build is the same size and would tie the package to a libc version for
# no gain.
YAY_VERSION=v13.0.1
MISE_VERSION=v2026.8.12

# wlay. Monitor arrangement with the outputs drawn as rectangles, and the only
# graphical one that is not GTK: GLFW and nuklear, straight onto
# wlr-output-management, which hedl already creates. It has never tagged a
# release, so the pin is a commit.
WLAY=https://github.com/atx/wlay.git
WLAY_VERSION=ed316060ac3ac122c0d3d8918293e19dfe9a6c90

force=0
[ "${1:-}" = "--force" ] && force=1

say() { printf '==> %s\n' "$1"; }
die() { printf 'download-deps.sh: %s\n' "$1" >&2; exit 1; }

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

# --------------------------------------------------------------- yay + mise
#
# Released binaries, unpacked flat. yay links libc and libresolv and nothing
# else: version 13 dropped go-alpm and drives pacman as a command, so it is not
# tied to a libalpm soname. mise links nothing at all.

# name, archive flag, path of the binary inside the unpacked tree, url.
fetch_release() {
	name=$1 flag=$2 bin=$3 url=$4
	dir="$vendor/$name"
	if [ "$force" = 1 ]; then rm -rf "$dir"; fi
	if [ -x "$dir/$bin" ]; then
		say "$name: already present"
		return
	fi
	say "$name: fetching"
	rm -rf "$dir"
	mkdir -p "$dir"
	curl -fsSL "$url" | tar "x${flag}" -C "$dir" --strip-components=1
	[ -x "$dir/$bin" ] || die "$name: no $bin in the archive"
}

fetch_release yay z yay \
	"https://github.com/Jguer/yay/releases/download/$YAY_VERSION/yay_${YAY_VERSION#v}_x86_64.tar.gz"

fetch_release mise J bin/mise \
	"https://github.com/jdx/mise/releases/download/$MISE_VERSION/mise-$MISE_VERSION-linux-x64-musl.tar.xz"

# --------------------------------------------------------------------- wlay
#
# Source, not a binary: nobody publishes one. nuklear and wlr-protocols are
# submodules and their commits are recorded in wlay's tree, so a recursive
# checkout at the pin gets the same three trees every time.

dir="$vendor/wlay"
if [ "$force" = 1 ]; then rm -rf "$dir"; fi
if [ -f "$dir/main.c" ]; then
	say "wlay: already present"
else
	say "wlay: cloning $(printf '%.7s' "$WLAY_VERSION")"
	rm -rf "$dir"
	git clone --quiet "$WLAY" "$dir"
	git -C "$dir" checkout --quiet "$WLAY_VERSION"
	git -C "$dir" submodule update --quiet --init --recursive
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

say "omarchy: package tools"
mkdir -p "$shell/vendor/pkg"
for f in $OMARCHY_PKG; do cp "$dir/bin/$f" "$shell/vendor/pkg/$f"; done
chmod +x "$shell/vendor/pkg"/*

# --------------------------------------------------------- our edits to them
#
# The vendored files are somebody else's and are not committed. What is
# committed is the difference: one patch for each file we changed, applied
# here, on top of the copy that was just made.
#
# A patch is much less to carry than a fork of the file, and it fails loudly.
# When upstream moves the lines under it, `git apply` refuses and says which
# patch, which is the moment to look. A copy would have swallowed the change
# in silence.
#
# `patches/make.sh` is how one is made or remade. See vendor/NOTICE.
patches="$shell/vendor/patches"
if [ -n "$(find "$patches" -name '*.patch' 2>/dev/null | head -1)" ]; then
	say "omarchy: patches"
	for p in "$patches"/*.patch; do
		git -C "$shell/vendor" apply "$p" \
			|| die "$(basename "$p") does not apply. Upstream moved: remake it with patches/make.sh"
		say "  $(basename "$p" .patch)"
	done
else
	say "omarchy: no patches, the vendored files are upstream's"
fi

say "done"
