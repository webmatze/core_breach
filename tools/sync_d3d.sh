#!/bin/sh
# Copies the d3d engine (https://github.com/webmatze/d3d) into lib/d3d.
# Usage: tools/sync_d3d.sh [path-to-d3d-checkout]   (default: ../d3d)
set -e
cd "$(dirname "$0")/.."
SRC="${1:-../d3d}"
if [ ! -f "$SRC/app/d3d/d3d.rb" ]; then
  echo "d3d engine not found at $SRC/app/d3d" >&2
  exit 1
fi
rm -rf lib/d3d
mkdir -p lib/d3d
cp "$SRC"/app/d3d/*.rb lib/d3d/
# C source of the optional native extension (built with tools/build_ext.sh)
if [ -d "$SRC/app/d3d/ext" ]; then
  mkdir -p lib/d3d/ext
  cp "$SRC"/app/d3d/ext/*.c lib/d3d/ext/
fi
COMMIT=$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)
BRANCH=$(git -C "$SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
DIRTY=$(git -C "$SRC" status --porcelain -- app/d3d 2>/dev/null | grep -q . && echo " (with uncommitted changes)" || true)
cat > lib/d3d/SOURCE <<INFO
Vendored copy of the d3d engine. Do not edit here; change d3d and re-run tools/sync_d3d.sh.
repository: https://github.com/webmatze/d3d
branch: $BRANCH
commit: $COMMIT$DIRTY
INFO
echo "Synced d3d $BRANCH@$COMMIT$DIRTY into lib/d3d"
