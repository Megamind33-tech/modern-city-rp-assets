#!/usr/bin/env bash
# Builds a signed debug APK headlessly. Usage: tools/build_android.sh [debug|release]
# Requires: godot 4.7.2 on PATH with export templates, ANDROID_HOME (default /opt/android-sdk), JDK 17+.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-debug}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
GODOT="${GODOT:-godot}"
VER="$($GODOT --version | cut -d. -f1-3)"
mkdir -p "$ROOT/build" "$ROOT/logs"

# Editor settings: point Godot at the SDK and JDK (generated once).
SETTINGS_DIR="$HOME/.config/godot"
SETTINGS="$(ls "$SETTINGS_DIR"/editor_settings-4*.tres 2>/dev/null | head -1 || true)"
if [ -z "$SETTINGS" ]; then
  flock /tmp/godot.lock "$GODOT" --headless --path "$ROOT/game" --editor --quit >/dev/null 2>&1 || true
  SETTINGS="$(ls "$SETTINGS_DIR"/editor_settings-4*.tres | head -1)"
fi
python3 - "$SETTINGS" "$ANDROID_HOME" "$JAVA_HOME" <<'PY'
import sys, re
path, sdk, jdk = sys.argv[1:]
s = open(path).read()
for key, val in (("export/android/android_sdk_path", sdk), ("export/android/java_sdk_path", jdk)):
    line = f'{key} = "{val}"'
    s = re.sub(rf'^{re.escape(key)} = .*$', line, s, flags=re.M) if key in s else s.replace("[resource]\n", f"[resource]\n{line}\n", 1)
open(path, "w").write(s)
PY

# Debug keystore (never committed).
KS="$ROOT/build/debug.keystore"
if [ ! -f "$KS" ]; then
  keytool -genkeypair -v -keystore "$KS" -storepass android -alias androiddebugkey -keypass android \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KS" GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android

OUT="$ROOT/build/EmergencyCrew-$MODE.apk"
LOG="$ROOT/logs/export_android_$MODE.log"
flock /tmp/godot.lock "$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
flock /tmp/godot.lock "$GODOT" --headless --path "$ROOT/game" "--export-$MODE" "Android" "$OUT" >"$LOG" 2>&1 || { tail -30 "$LOG"; exit 1; }
[ -f "$OUT" ] || { echo "export produced no APK"; tail -30 "$LOG"; exit 1; }
"$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -1)apksigner" verify --print-certs "$OUT" | head -3
ls -la "$OUT"
