#!/usr/bin/env bash
# Stamps build/web/maktub_sw.js after `flutter build web`: sets BUILD_ID (hash of
# every shipped file) and the precache list.
# Usage: scripts/sellar-service-worker.sh [build/web dir]
set -euo pipefail

dir="${1:-apps/frontend/build/web}"
[ -f "$dir/maktub_sw.js" ] || { echo "No existe $dir/maktub_sw.js (¿corrió flutter build web?)" >&2; exit 1; }

sha() { if command -v sha256sum >/dev/null; then sha256sum; else shasum -a 256; fi; }

cd "$dir"
# Shell = everything shipped except the workers themselves, build bookkeeping and
# the CanvasKit variants: only the JS-renderer ones (Chromium build and generic) are listed.
files=$(find . -type f \
  ! -name maktub_sw.js ! -name flutter_service_worker.js ! -name .last_build_id \
  ! -path './canvaskit/*' | sed 's|^\./||' | LC_ALL=C sort)
files="$files
canvaskit/canvaskit.js
canvaskit/canvaskit.wasm
canvaskit/chromium/canvaskit.js
canvaskit/chromium/canvaskit.wasm"

build_id=$(echo "$files" | while read -r f; do sha < "$f"; done | sha | cut -c1-16)
list=$(printf './\n%s\n' "$files" | sed "s|.*|'&'|" | paste -sd, -)

sed -i.bak \
  -e "s|BUILD_ID = '__BUILD_ID__'|BUILD_ID = '$build_id'|" \
  -e "s|PRECACHE_URLS = \['__PRECACHE_URLS__'\]|PRECACHE_URLS = [$list]|" \
  maktub_sw.js
rm -f maktub_sw.js.bak
echo "maktub_sw.js sellado: BUILD_ID=$build_id, $(echo "$files" | wc -l | tr -d ' ') archivos"
