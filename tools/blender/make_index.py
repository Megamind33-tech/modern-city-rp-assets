#!/usr/bin/env python3
"""Merge tools/blender/build/<id>.json reports into game/assets/asset_index.json
and (re)write ASSET_MANIFEST.csv rows from tools/blender/assets.json."""
import csv, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
spec = json.load(open(os.path.join(HERE, "assets.json")))
PROC = {"source": "Procedural generator (tools/blender/generators.py)", "source_url": "tools/blender/generators.py",
        "license": "CC0 (original work)", "author": "EMERGENCY CREW asset pipeline"}

index = {"assets": {}, "notes": {
    "orientation": "front faces -Z, +Y up, metres, pivot at base centre (y=0 ground)",
    "materials": "surface 'palette' (albedo res://assets/palette.png x COLOR_0 baked AO); 'palette_emissive' on light nodes",
    "overlays": "roof_damage / roof_patch are authored in house_* local space: give them the same transform as the house"}}
rows = []
for s0 in spec["assets"]:
    s = dict(spec.get("defaults", {}).get(s0["category"], {}))
    s.update(s0)
    p = os.path.join(HERE, "build", s["id"] + ".json")
    if not os.path.exists(p):
        continue
    r = json.load(open(p))
    e = {k: r[k] for k in ("path", "category", "tris", "size_m", "nodes", "animations")}
    for k in ("rig", "skeleton", "bones", "notes"):
        if r.get(k):
            e[k] = r[k]
    index["assets"][s["id"]] = e
    m = dict(PROC) if "generator" in s else {}
    m.update(s.get("manifest", {}))
    rows.append({
        "asset_id": s["id"], "purpose": s.get("purpose", ""), "source": m.get("source", ""),
        "source_url": m.get("source_url", ""), "license": m.get("license", ""), "author": m.get("author", ""),
        "format": "glb", "tris": r["tris"], "texture": "palette.png (shared 256x256 atlas)",
        "rig": r.get("rig", "none"), "animations": " ".join(r.get("animations", [])) or "none",
        "optimization": m.get("optimization", "palette remap; weighted normals%s; AO->COLOR_0; budget %s" % (
            "; bevel" if s.get("hard_surface", True) and s.get("bevel", 0.02) else "", s.get("budget", "-"))),
        "integration": "ready"})
json.dump(index, open(os.path.join(ROOT, "game", "assets", "asset_index.json"), "w"), indent=1)
man = os.path.join(ROOT, "ASSET_MANIFEST.csv")
header = open(man).readline().strip().split(",")
with open(man, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=header)
    w.writeheader()
    for r in rows:
        w.writerow(r)
print("index:", len(index["assets"]), "assets; manifest rows:", len(rows))
