"""Render a labelled contact sheet of exported glbs (front 3/4 view, neutral sky).

  blender -b --factory-startup -P tools/blender/render_sheet.py -- --batch A [--ids a,b] [--out docs/asset_renders/A.png]

Tiles are rendered by Cycles (CPU) from the *exported* .glb files (so the sheet
also proves the export round-trips) and stitched + labelled with Pillow via the
system python3 (tools/blender/stitch.py).
"""
import argparse, json, math, os, subprocess, sys, tempfile
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def fix_materials():
    """multiply imported COLOR_0 (baked AO) into base colour, nearest filtering"""
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
        if not bsdf or not tex:
            continue
        tex.interpolation = "Closest"
        ca = nt.nodes.new("ShaderNodeVertexColor")
        ca.layer_name = "Color"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(tex.outputs["Color"], mix.inputs[6])
        nt.links.new(ca.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def setup_scene(res):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("sky")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.78, 0.83, 0.9, 1)
    bg.inputs[1].default_value = 0.9
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.2
    sun.color = (1.0, 0.94, 0.85)
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(150))
    sc.collection.objects.link(so)
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, -0.002))
    g = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.53, 0.5, 1)
    g.data.materials.append(gm)
    cam = bpy.data.cameras.new("cam")
    cam.lens = 50
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    return co


def pose(objs, clip, t=0.5):
    for a in [o for o in objs if o.type == "ARMATURE"]:
        act = next((x for x in bpy.data.actions if x.name == clip or x.name.startswith(clip + "_")), None)
        if act is None:
            continue
        ad = a.animation_data or a.animation_data_create()
        ad.action = act
        if hasattr(ad, "action_slot") and len(getattr(act, "slots", [])):
            ad.action_slot = act.slots[0]
        f0, f1 = act.frame_range
        bpy.context.scene.frame_set(int(f0 + (f1 - f0) * t))


def frame(co, objs, view=(0.75, 1.0, 0.65)):
    mn, mx = lib.bbox([o for o in objs if o.type == "MESH" and o.visible_get() and not o.name.startswith("Icosphere")])
    c = (mn + mx) / 2
    r = max((mx - mn).length / 2, 0.2)
    d = Vector(view).normalized()
    dist = r / math.sin(math.radians(15)) * 1.0
    co.location = c + d * dist
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    co.data.clip_end = dist * 4


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", default="")
    ap.add_argument("--ids", default="")
    ap.add_argument("--out", default="")
    ap.add_argument("--tile", default="400x300")
    ap.add_argument("--view", default="0.75,1.0,0.65")
    ap.add_argument("--pose", default="idle")
    ap.add_argument("--clips", default="", help="asset id: render one tile per clip")
    a = ap.parse_args(argv)
    with open(os.path.join(HERE, "assets.json")) as f:
        specs = json.load(f)["assets"]
    ids = [i for i in a.ids.split(",") if i] or [s["id"] for s in specs if s.get("batch") == a.batch]
    tiles = [(i, a.pose) for i in ids]
    if a.clips:
        rep = json.load(open(os.path.join(HERE, "build", a.clips + ".json")))
        tiles = [(a.clips, c) for c in rep["animations"]]
    cat = {s["id"]: s["category"] for s in specs}
    tw, th = (int(v) for v in a.tile.split("x"))
    tmp = tempfile.mkdtemp(prefix="sheet_")
    labels = []
    for i, clip in tiles:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        co = setup_scene((tw, th))
        before = set(bpy.data.objects)
        for part in i.split("+"):  # "house_a+roof_damage" renders overlays together
            bpy.ops.import_scene.gltf(filepath=os.path.join(lib.ASSETS, cat[part], part + ".glb"))
        objs = [o for o in bpy.data.objects if o not in before]
        for o in objs:
            if o.type == "MESH" and o.name.startswith("Icosphere"):  # glTF importer bone-shape helper
                o.hide_render = True
        fix_materials()
        pose(objs, clip)
        frame(co, objs, tuple(float(v) for v in a.view.split(",")))
        out = os.path.join(tmp, "%s_%s.png" % (i, clip))
        bpy.context.scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        tris = 0
        for part in i.split("+"):
            rep = os.path.join(HERE, "build", part + ".json")
            tris += json.load(open(rep))["tris"] if os.path.exists(rep) else 0
        labels.append((out, f"{clip}" if a.clips else f"{i}  ({tris} tris)"))
    out = a.out or os.path.join(lib.ROOT, "docs", "asset_renders", (a.batch or "sheet") + ".png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    lst = os.path.join(tmp, "list.json")
    json.dump({"tiles": labels, "out": out, "title": a.batch}, open(lst, "w"))
    subprocess.check_call(["python3", "-I", os.path.join(HERE, "stitch.py"), lst])
    print("SHEET", out)


if __name__ == "__main__":
    main()
