#!/bin/sh
# Boot the ISO with no screen, log in over the serial port, run
# tildesh-selftest, print what it said, and power the machine off.
#
# This is the unattended half of scripts/vm.sh. It answers "does the image
# still work" without anyone watching it boot.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

iso="${1:-$(ls -t "$root"/dist/*/*.iso "$root"/dist/*.iso 2>/dev/null | head -1)}"
[ -n "$iso" ] && [ -f "$iso" ] || { echo "vm-selftest.sh: no ISO. Build one first." >&2; exit 1; }

exec python3 "$root/scripts/vm-selftest.py" "$iso"
