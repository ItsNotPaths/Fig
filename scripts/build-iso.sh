#!/bin/sh
# Build the fig ISO. Everything happens inside the Artix container, so the
# only thing the host needs is docker.
#
# buildiso chroots, mounts and makes loop devices, which is why the container
# is --privileged. Its chroot copies and its pacman cache live in named
# volumes, so a second build reuses both.
#
# Any extra argument is passed to buildiso. The useful ones:
#   -q   query the settings and pretend to build
#   -c   keep the work dir, so the next run reuses the chroots
#   -x   build the chroot only
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Rebuilt when the Dockerfile moved under it, not only when it is missing.
want=$(sha256sum "$root/docker/Dockerfile" | cut -c1-16)
have=$(docker image inspect fig-build --format '{{index .Config.Labels "fig.dockerfile"}}' 2>/dev/null || true)
[ "$have" = "$want" ] || "$root/scripts/build-host.sh"

mkdir -p "$root/dist" "$root/repo"

[ -f "$root/repo/fig.db" ] || {
	echo "build-iso.sh: no packages in repo/. Run packaging/build-packages.sh first." >&2
	exit 1
}

# The container gets its own /dev, populated once when it starts. A loop
# device the kernel allocates later exists in the host and not in here, and
# the EFI image is mounted over one, so the nodes are made up front.
# buildiso is run one phase at a time rather than all at once, so that the
# offline mirror can be laid into the ISO root between the boot files and the
# image itself. artools names the sequence in its own warnings: -x, then -sc,
# then -bc, then -zc. Each phase-only run exits 1 when it finishes, which is
# why none of them is the script's exit status.
#
# The mirror is every package the built rootfs holds, copied out of the pacman
# cache and out of repo/, with a database over the top. It sits beside the
# squashfs and not inside it: these files are already zstd, and asking
# mksquashfs to compress them again at level 15 costs minutes and saves
# nothing. fig-install reads it from the mounted ISO, so an install needs no
# network at all.
inner='
	set -e
	for i in 0 1 2 3 4 5 6 7; do
		[ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i
	done

	work=/var/lib/artools/buildiso/fig/artix
	isoroot=/var/lib/artools/buildiso/fig/iso
	mirror=$isoroot/fig-mirror

	phase() { buildiso -p fig -i runit "$@" || true; }

	phase "$@" -x
	[ -d "$work/rootfs/var/lib/pacman" ] || { echo "no rootfs after -x" >&2; exit 1; }
	phase -sc
	phase -bc
	[ -d "$isoroot/boot" ] || { echo "no boot files after -bc" >&2; exit 1; }

	echo "==> offline mirror"
	rm -rf "$mirror"; mkdir -p "$mirror"
	missing=0
	pacman -r "$work/rootfs" -Qq 2>/dev/null | while read -r n; do
		v=$(pacman -r "$work/rootfs" -Q "$n" 2>/dev/null | cut -d" " -f2)
		f=$(ls /var/cache/pacman/pkg/"$n"-"$v"-*.pkg.tar.* /repo/"$n"-"$v"-*.pkg.tar.* \
			2>/dev/null | grep -v "\.sig$" | head -1)
		if [ -n "$f" ]; then cp -n "$f" "$mirror/"; else echo "  missing: $n $v"; fi
	done
	# Everything fig builds, whether or not the image preinstalls it. The
	# list above is what the live system holds, which is not the same
	# question as what an installed machine can still reach offline. A
	# package that stops being preinstalled would otherwise leave the mirror
	# without anyone deciding that it should.
	for f in /repo/*.pkg.tar.*; do
		[ -e "$f" ] || continue
		case "$f" in *.sig) continue ;; esac
		cp -n "$f" "$mirror/"
	done
	echo "==> $(ls "$mirror" | wc -l) packages, $(du -sh "$mirror" | cut -f1)"
	repo-add -q "$mirror/fig-mirror.db.tar.gz" "$mirror"/*.pkg.tar.* >/dev/null

	buildiso -p fig -i runit -zc
	rc=$?
	chown -R "$HOST_UID:$HOST_GID" /out
	exit $rc
'

docker run --rm --privileged \
	-v "$root/profile:/workspace/iso-profiles:ro" \
	-v "$root/dist:/out" \
	-v "$root/repo:/repo:ro" \
	-v fig-chroots:/var/lib/artools \
	-v fig-pkgcache:/var/cache/pacman/pkg \
	-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
	fig-build sh -c "$inner" -- "$@"

ls -lh "$root/dist"
