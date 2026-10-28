#!/usr/bin/env bash
# Download + unpack the CC0 source packs into tools/asset_sources/ (gitignored) if missing.
# All three are Quaternius CC0 packs ("name your own price", free download on itch.io).
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC=tools/asset_sources

itch_fetch() {  # <game_url> <outdir> <file regex>
  local G=$1 OUT=$2 RX=$3 J; J=$(mktemp); mkdir -p "$OUT"
  local P T U
  P=$(curl -sS -c "$J" -b "$J" "$G")
  T=$(echo "$P" | grep -oE 'name="csrf_token" value="[^"]+"' | head -1 | sed 's/.*value="//;s/"$//')
  U=$(curl -sS -c "$J" -b "$J" -X POST --data-urlencode "csrf_token=$T" "$G/download_url" | python3 -c 'import sys,json;print(json.load(sys.stdin)["url"])')
  curl -sS -L -c "$J" -b "$J" "$U" | python3 -c '
import sys,re
for m in re.finditer(r"data-upload_id=\"(\d+)\".{0,3000}?title=\"([^\"]+)\"",sys.stdin.read(),re.S): print(m.group(1)+"\t"+m.group(2))' |
  while IFS=$'\t' read -r id name; do
    echo "$name" | grep -qE "$RX" || continue
    F=$(curl -sS -c "$J" -b "$J" -X POST --data-urlencode "csrf_token=$T" "$G/file/$id?source=view_game&as_props=1&after_download_lightbox=true" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("url",""))')
    echo "fetch $name"; curl -sS -L -o "$OUT/$name" "$F"; (cd "$OUT" && unzip -oq "$name")
  done
  rm -f "$J"
}

[ -d "$SRC/uanim/Universal Animation Library[Standard]" ] || itch_fetch https://quaternius.itch.io/universal-animation-library "$SRC/uanim" 'Standard'
[ -d "$SRC/uanim2/Universal Animation Library 2[Standard]" ] || itch_fetch https://quaternius.itch.io/universal-animation-library-2 "$SRC/uanim2" 'Standard'
[ -d "$SRC/ubc/Universal Base Characters[Standard]" ] || itch_fetch https://quaternius.itch.io/universal-base-characters "$SRC/ubc" 'Standard'
echo "sources ok"
