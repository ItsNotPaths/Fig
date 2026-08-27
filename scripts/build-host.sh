#!/bin/sh
# Build the Artix build-host image.
#
# The image is stamped with the Dockerfile's own hash, so build-iso.sh can
# tell a stale image from a current one. It could not before, and the rename
# from tildesh to fig proved why: the repo in the baked pacman.conf kept its
# old name through every later build, because the image already existed and
# nothing ever asked whether it still matched.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

stamp=$(sha256sum "$root/docker/Dockerfile" | cut -c1-16)

exec docker build -t fig-build --label "fig.dockerfile=$stamp" "$root/docker"
