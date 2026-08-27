#!/bin/sh
# Build the Artix build-host image. Run once, and again when the Dockerfile
# changes.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

exec docker build -t fig-build "$root/docker"
