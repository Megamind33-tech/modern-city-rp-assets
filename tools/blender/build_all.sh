#!/usr/bin/env bash
# Rebuild every asset idempotently: palette -> glbs -> index/manifest -> contact sheets.
#   tools/blender/build_all.sh            # everything
#   tools/blender/build_all.sh A          # one batch (A|B|C)
set -euo pipefail
cd "$(dirname "$0")/../.."
BATCHES=${1:-A,B,C}
python3 tools/blender/palette.py
[ -f tools/blender/fetch_sources.sh ] && bash tools/blender/fetch_sources.sh
blender -b --factory-startup -P tools/blender/pipeline.py -- --batch "$BATCHES" 2>&1 | grep -E 'BUILT|FAILED|Error|OVER' || true
python3 tools/blender/make_index.py
python3 tools/blender/godot_import.py   # shared palette materials + import settings
for b in ${BATCHES//,/ }; do
  blender -b --factory-startup -P tools/blender/render_sheet.py -- --batch "$b" 2>&1 | grep -E 'SHEET|Error' || true
done
echo "validate: flock /tmp/godot.lock godot --headless --path game --import"
