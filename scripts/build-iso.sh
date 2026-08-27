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

docker image inspect fig-build >/dev/null 2>&1 || "$root/scripts/build-host.sh"

mkdir -p "$root/dist" "$root/repo"

[ -f "$root/repo/fig.db" ] || {
	echo "build-iso.sh: no packages in repo/. Run packaging/build-packages.sh first." >&2
	exit 1
}

# The container gets its own /dev, populated once when it starts. A loop
# device the kernel allocates later exists in the host and not in here, and
# the EFI image is mounted over one, so the nodes are made up front.
inner='
	for i in 0 1 2 3 4 5 6 7; do
		[ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i
	done
	buildiso -p fig -i runit "$@"
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
