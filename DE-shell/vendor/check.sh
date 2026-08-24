#!/bin/sh
# What upstream changed since we took these. Needs omarchy installed.
set -u
cd "$(dirname "$0")"
UP=${OMARCHY_PATH:-/usr/share/omarchy}/bin

[ -d "$UP" ] || { echo "no $UP, nothing to compare against"; exit 0; }

drift=0
while read -r sum name; do
	[ -f "$UP/$name" ] || { echo "gone upstream: $name"; drift=$((drift + 1)); continue; }
	now=$(sha256sum "$UP/$name" | cut -d' ' -f1)
	[ "$now" = "$sum" ] || { echo "changed upstream: $name"; drift=$((drift + 1)); }
done < MANIFEST

# The themes and the templates are data and travel the same way.
for f in ../themes/*/colors.toml; do
	n=$(basename "$(dirname "$f")")
	u=${OMARCHY_PATH:-/usr/share/omarchy}/themes/$n/colors.toml
	[ -f "$u" ] || continue
	cmp -s "$f" "$u" || { echo "changed upstream: themes/$n/colors.toml"; drift=$((drift + 1)); }
done
for f in ../theme/templates/*.tpl; do
	u=${OMARCHY_PATH:-/usr/share/omarchy}/default/themed/$(basename "$f")
	[ -f "$u" ] || continue
	cmp -s "$f" "$u" || { echo "changed upstream: $(basename "$f")"; drift=$((drift + 1)); }
done

[ "$drift" -eq 0 ] && echo "vendored files match upstream" || echo "$drift drifted"
exit 0
