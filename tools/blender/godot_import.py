#!/usr/bin/env python3
"""Write Godot .import settings for every pipeline glb so that:
  * embedded palette images are discarded (no per-asset *_palette.png copies),
  * glTF materials `palette` / `palette_emissive` map to the shared external
    materials res://assets/materials/palette(.tres|_emissive.tres)
    (albedo = palette.png x vertex colour AO, nearest filtering),
  * palette.png stays lossless (no VRAM compression smearing cells).
Run after a Godot import created the .import files (or before: missing files are created)."""
import glob, json, os, re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAME = os.path.join(ROOT, "game")
SUB = ('_subresources={\n"materials": {\n'
       '"palette": {\n"use_external/enabled": true,\n"use_external/path": "res://assets/materials/palette.tres"\n},\n'
       '"palette_emissive": {\n"use_external/enabled": true,\n"use_external/path": "res://assets/materials/palette_emissive.tres"\n}\n}\n}')
SET = {"gltf/embedded_image_handling": "0", "meshes/ensure_tangents": "false"}


LOOP = None


def anim_block(glb):
    """loop_mode=1 for looping character clips (names from the build report)"""
    rep = os.path.join(ROOT, "tools", "blender", "build", os.path.splitext(os.path.basename(glb))[0] + ".json")
    if not os.path.exists(rep):
        return ""
    clips = json.load(open(rep)).get("animations", [])
    if not clips:
        return ""
    import sys
    sys.path.insert(0, os.path.join(ROOT, "tools", "blender"))
    loops = {"idle", "walk", "run", "carry_walk", "work", "wave", "cheer", "sad", "talk", "phone", "kneel_work", "chop"}
    items = ",\n".join('"%s": {\n"settings/loop_mode": %d\n}' % (c, 1 if c in loops else 0) for c in clips)
    return ',\n"animations": {\n' + items + "\n}"


def patch(path):
    if not os.path.exists(path):
        open(path, "w").write('[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[params]\n\n')
    s = open(path).read()
    s = re.sub(r"_subresources=\{.*?\n\}(?=\n[a-z]|\n*$)", "", s, flags=re.S) if "_subresources=" in s else s
    s = re.sub(r"_subresources=\{\}\n?", "", s)
    for k, v in SET.items():
        if re.search("^" + re.escape(k) + "=", s, flags=re.M):
            s = re.sub("^" + re.escape(k) + "=.*$", k + "=" + v, s, flags=re.M)
        else:
            s = s.rstrip("\n") + "\n" + k + "=" + v + "\n"
    sub = SUB
    ab = anim_block(path[:-len(".import")])
    if ab:
        sub = SUB[:-2] + ab + "\n}"
    s = s.rstrip("\n") + "\n" + sub + "\n"
    open(path, "w").write(s)


for glb in glob.glob(os.path.join(GAME, "assets", "**", "*.glb"), recursive=True):
    patch(glb + ".import")
    stem = os.path.splitext(glb)[0]
    for junk in glob.glob(stem + "_palette*.png*"):
        os.remove(junk)
pi = os.path.join(GAME, "assets", "palette.png.import")
if os.path.exists(pi):
    s = open(pi).read()
    s = re.sub(r"^detect_3d/compress_to=.*$", "detect_3d/compress_to=0", s, flags=re.M)
    s = re.sub(r"^compress/mode=.*$", "compress/mode=0", s, flags=re.M)
    open(pi, "w").write(s)
print("patched import settings")
