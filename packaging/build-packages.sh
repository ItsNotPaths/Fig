#!/bin/sh
# Build our packages and put them in repo/ as an Artix package repo that
# buildiso installs from.
#
# kippsrv and wweft are built on this machine, not in the container: kippsrv is
# Odin, which is in no Artix repo, and wweft's build needs protocol sources it
# vendors itself. The host and Artix carry the same glibc, and both binaries
# link nothing else that matters. `ldd` after a build is the check.
#
# hedl is built in the container, because it can be: it is C, and wlroots0.19
# and the rest are Artix packages. Only its source is staged here.
#
# The sibling repos are found beside this one. Override with KIPPSRV_DIR,
# WWEFT_DIR and HEDL_DIR.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KIPPSRV_DIR=${KIPPSRV_DIR:-$root/../kippsrv}
WWEFT_DIR=${WWEFT_DIR:-$root/../wweft}
HEDL_DIR=${HEDL_DIR:-$root/../hedl-wm}

stage="$root/vendor/stage"
repo="$root/repo"

say() { printf '==> %s\n' "$1"; }
die() { printf 'build-packages.sh: %s\n' "$1" >&2; exit 1; }

[ -d "$KIPPSRV_DIR" ] || die "no kippsrv at $KIPPSRV_DIR"
[ -d "$WWEFT_DIR" ]   || die "no wweft at $WWEFT_DIR"
[ -d "$HEDL_DIR" ]    || die "no hedl-wm at $HEDL_DIR"

# A version pacman can order: the commit's date, then its name. An uncommitted
# change gets a minute stamp on the end, so a package built twice from a tree
# that moved is two versions and not one.
version() {
	base=$(git -C "$1" log -1 --date=format:%Y%m%d --format=%cd.g%h 2>/dev/null) \
		|| base=$(date +%Y%m%d)
	if [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]; then
		base="$base.d$(date +%Y%m%d%H%M)"
	fi
	printf '%s' "$base"
}

# --------------------------------------------------------------------- build

say "kippsrv: make static"
# static links basu, so the binary needs no D-Bus library. libsystemd, which
# the default target links, does not exist on an Artix machine at all.
make -C "$KIPPSRV_DIR" static >/dev/null

say "wweft: build.sh"
( cd "$WWEFT_DIR" && ./build.sh >/dev/null )

# --------------------------------------------------------------------- stage

pkgs="kippsrv wweft hedl-wm ttf-iosevkaterm-nerd-mono tildesh-defaults tildesh-shell"
for p in $pkgs; do rm -rf "$stage/$p"; mkdir -p "$stage/$p"; done
mkdir -p "$repo"

install -Dm755 "$KIPPSRV_DIR/kippsrv" "$stage/kippsrv/usr/bin/kippsrv"
mkdir -p "$stage/kippsrv/usr/share/kippsrv"
cp -r "$KIPPSRV_DIR/lua" "$stage/kippsrv/usr/share/kippsrv/lua"

install -Dm755 "$WWEFT_DIR/build/wweft" "$stage/wweft/usr/bin/wweft"
mkdir -p "$stage/wweft/usr/share/wweft"
cp -r "$WWEFT_DIR/examples" "$stage/wweft/usr/share/wweft/examples"

# hedl-wm stages source, not a binary. Without .git, so the copy is small and
# the same tree twice is the same bytes twice.
tar -c -C "$HEDL_DIR" --exclude=.git . | tar -x -C "$stage/hedl-wm"

fonts="$root/vendor/fonts/iosevka"
[ -n "$(find "$fonts" -name '*.ttf' 2>/dev/null | head -1)" ] \
	|| die "no fonts in $fonts. Run ./download-deps.sh"
mkdir -p "$stage/ttf-iosevkaterm-nerd-mono/usr/share/fonts/TTF"
cp "$fonts"/*.ttf "$stage/ttf-iosevkaterm-nerd-mono/usr/share/fonts/TTF/"

# Plain files, kept in the tree beside their PKGBUILD.
cp -a "$root/packaging/tildesh-defaults/files/." "$stage/tildesh-defaults/"

# The shell. Surfaces and the theme engine are the user's, so they go through
# /etc/skel; the palettes and the vendored setters are the machine's.
#
# Not ~/.config/wweft: that is wweft's own directory, and these are no more
# wweft's configuration than a script is bash's. wweft is a renderer on PATH.
skel="$stage/tildesh-shell/etc/skel/.config/tildesh-shell"
share="$stage/tildesh-shell/usr/share/tildesh"
mkdir -p "$skel/lib" "$share/themes" "$share/theme-setters/helpers"
# The top of the directory is what a person edits: the settings files and the
# surfaces. Everything under lib/ is code they only open to change how
# something works.
cp "$root/DE-shell/"*.lua "$skel/"
cp "$root/DE-shell/surfaces/"*.lua "$skel/"
cp -r "$root/DE-shell/lib/." "$skel/lib/"
cp -r "$root/DE-shell/themes/." "$share/themes/"
cp "$root/DE-shell/vendor/setters/"* "$share/theme-setters/"
cp "$root/DE-shell/vendor/helpers/"* "$share/theme-setters/helpers/"
cp "$root/DE-shell/vendor/NOTICE" "$share/theme-setters/NOTICE"
# What the surfaces run. A surface names an intent, so these have to be found
# by name, which means PATH and not the shell's own directory.
install -Dm755 "$root/DE-shell/bin/"* -t "$stage/tildesh-shell/usr/bin/"
chmod +x "$share/theme-setters/"* "$share/theme-setters/helpers/"* 2>/dev/null || true

# ---------------------------------------------------------------- wrap + index
#
# makepkg refuses to run as root, so the container image carries a `builder`
# user. Every PKGBUILD but hedl-wm's copies what is already staged. That one
# compiles it, against the wlroots the image carries.

inner='
	set -eu
	for spec in $SPECS; do
		p=${spec%%:*}
		v=${spec#*:}
		rm -rf /tmp/$p && cp -r /packaging/$p /tmp/$p
		chown -R builder /tmp/$p
		su builder -c "cd /tmp/$p && PKGVER=$v STAGE=/stage/$p makepkg -f --nodeps --noconfirm"
		rm -f /repo/$p-*.pkg.tar.zst
		mv /tmp/$p/*.pkg.tar.zst /repo/
	done
	rm -f /repo/tildesh.db* /repo/tildesh.files*
	repo-add -q /repo/tildesh.db.tar.zst /repo/*.pkg.tar.zst
	chown -R "$HOST_UID:$HOST_GID" /repo
'

say "wrapping into $repo"
docker run --rm \
	-v "$root/packaging:/packaging:ro" \
	-v "$stage:/stage:ro" \
	-v "$repo:/repo" \
	-e SPECS="kippsrv:$(version "$KIPPSRV_DIR") \
wweft:$(version "$WWEFT_DIR") \
hedl-wm:$(version "$HEDL_DIR") \
ttf-iosevkaterm-nerd-mono:$(sed -n 's/^NERD_VERSION=v//p' "$root/download-deps.sh") \
tildesh-defaults:$(version "$root") \
tildesh-shell:$(version "$root")" \
	-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
	tildesh-build bash -c "$inner"

ls -1 "$repo"
