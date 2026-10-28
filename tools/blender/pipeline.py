"""EMERGENCY CREW asset pipeline (Blender 5.2, headless).

  blender -b --factory-startup -P tools/blender/pipeline.py -- --ids traffic_cone,log_section
  blender -b --factory-startup -P tools/blender/pipeline.py -- --batch A

Each spec in tools/blender/assets.json is either built by a parametric generator
("generator": "<name>") or imported from a source file ("source": {...}). The
result goes through finalize(): transforms applied, scale normalised, pivot at
base centre (z=0), palette remap (UVs collapsed to cell centres, materials
`palette` / `palette_emissive`), bevel + weighted normals (hard surface), budget
decimation, AO baked to COLOR_0, glb export to game/assets/<category>/<id>.glb.
A per-asset report is written to tools/blender/build/<id>.json.
"""
import argparse, json, math, os, sys, time
import bpy, bmesh
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
from lib import P  # noqa: E402
import palette as PAL  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "build")


# ------------------------------------------------------------ importing sources
def import_source(path):
    ext = os.path.splitext(path)[1].lower()
    before = set(bpy.data.objects)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise RuntimeError("unsupported source " + path)
    return [o for o in bpy.data.objects if o not in before]


def _image_pixels(img):
    import numpy as np
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4), w, h


def _mat_color_source(mat):
    """(image or None, base rgb 0..255) for a material"""
    if mat is None:
        return None, (200, 200, 200)
    col = (200, 200, 200)
    img = None
    if mat.use_nodes:
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            inp = bsdf.inputs["Base Color"]
            c = inp.default_value
            col = tuple(int(255 * (x if x > 0.0031308 else x) ** (1 / 2.2)) for x in c[:3])
            stack = [l.from_node for l in inp.links]
            while stack:
                n = stack.pop()
                if n.type == "TEX_IMAGE" and n.image:
                    img = n.image
                    break
                for i in n.inputs:
                    stack += [l.from_node for l in i.links]
    else:
        col = tuple(int(255 * x ** (1 / 2.2)) for x in mat.diffuse_color[:3])
    return img, col


def palettize_imported(ob, spec):
    """write face attr 'pal' from material colour / texture sample at face UV centroid"""
    import numpy as np
    overrides = spec.get("material_map", {})  # material name substring -> palette idx/name
    me = ob.data
    cache = {}
    uvl = me.uv_layers.active
    pal = me.attributes.get("pal") or me.attributes.new("pal", "INT", "FACE")
    vals = [0] * len(me.polygons)
    for p in me.polygons:
        mat = ob.material_slots[p.material_index].material if ob.material_slots else None
        mname = mat.name if mat else ""
        hit = next((v for k, v in overrides.items() if k.lower() in mname.lower()), None)
        if hit is not None:
            vals[p.index] = lib.pi(hit)
            continue
        if mname not in cache:
            img, col = _mat_color_source(mat)
            px = _image_pixels(img) if img is not None and img.size[0] > 0 else None
            cache[mname] = (px, col)
        px, col = cache[mname]
        if px is not None and uvl is not None:
            arr, w, h = px
            u = sum(uvl.data[li].uv[0] for li in p.loop_indices) / p.loop_total
            v = sum(uvl.data[li].uv[1] for li in p.loop_indices) / p.loop_total
            x = int((u % 1.0) * (w - 1))
            y = int((v % 1.0) * (h - 1))
            c = arr[y, x, :3]
            rgb = tuple(int(255 * max(0, min(1, float(k))) ** (1 / 2.2)) for k in c)
        else:
            rgb = col
        vals[p.index] = lib.nearest_palette(rgb)
    pal.data.foreach_set("value", vals)


# ------------------------------------------------------------ finalize stages
def apply_transforms(meshes):
    lib.select_only(meshes)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def normalise(objs, spec):
    """uniform scale to target size, then pivot at base centre"""
    meshes = [o for o in objs if o.type == "MESH"]
    roots = [o for o in objs if o.parent is None]
    mn, mx = lib.bbox(meshes)
    size = mx - mn
    s = 1.0
    if "target_height" in spec:
        s = spec["target_height"] / size.z
    elif "target_length" in spec:
        ax = {"x": 0, "y": 1, "z": 2}[spec.get("length_axis", "y")]
        s = spec["target_length"] / size[ax]
    off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    M = Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation(-off)
    for r in roots:
        r.matrix_world = M @ r.matrix_world
    return s


def assign_palette_uv_and_materials(ob):
    me = ob.data
    pal = me.attributes.get("pal")
    n = len(me.polygons)
    vals = [P["steel"]] * n
    if pal is not None:
        pal.data.foreach_get("value", vals)
    for uv in list(me.uv_layers):
        me.uv_layers.remove(uv)
    uvl = me.uv_layers.new(name="UVMap")
    loop_uv = [0.0] * (len(me.loops) * 2)
    mat_idx = [0] * n
    for p in me.polygons:
        u, v = PAL.uv(vals[p.index] % 64)
        for li in p.loop_indices:
            loop_uv[li * 2] = u
            loop_uv[li * 2 + 1] = v
        mat_idx[p.index] = 1 if vals[p.index] in PAL.EMISSIVE else 0
    uvl.data.foreach_set("uv", loop_uv)
    me.materials.clear()
    me.materials.append(lib.palette_material(False))
    has_em = any(mat_idx)
    if has_em:
        me.materials.append(lib.palette_material(True))
    me.polygons.foreach_set("material_index", mat_idx)
    if has_em and not any(m == 0 for m in mat_idx):
        # all faces emissive: single slot
        me.materials.pop(index=0)
        me.polygons.foreach_set("material_index", [0] * n)


def apply_mods(ob):
    lib.select_only([ob], ob)
    for m in list(ob.modifiers):
        if m.type == "ARMATURE":
            continue
        bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
        bpy.ops.object.modifier_apply(modifier=m.name)


def hard_surface(meshes, spec, budget):
    width = spec.get("bevel", 0.03)
    if width > 0:
        for ob in meshes:
            if ob.get("no_bevel"):
                continue
            m = ob.modifiers.new("Bevel", "BEVEL")
            m.width = width
            m.segments = 1
            m.limit_method = "ANGLE"
            m.angle_limit = math.radians(40)
            m.use_clamp_overlap = True
        if budget and lib.tris(meshes) > budget:
            print("  bevel would exceed budget -> skipped")
            for ob in meshes:
                for m in [m for m in ob.modifiers if m.type == "BEVEL"]:
                    ob.modifiers.remove(m)
        for ob in meshes:
            apply_mods(ob)
    for ob in meshes:
        ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
        m = ob.modifiers.new("WN", "WEIGHTED_NORMAL")
        m.keep_sharp = True
        m.weight = 50
        m.mode = "FACE_AREA"
        apply_mods(ob)


def flat_shade(meshes):
    for ob in meshes:
        ob.data.polygons.foreach_set("use_smooth", [False] * len(ob.data.polygons))


def decimate(meshes, budget):
    t = lib.tris(meshes)
    if not budget or t <= budget:
        return
    ratio = budget / t * 0.97
    print(f"  decimating {t} -> ~{int(t * ratio)}")
    for ob in meshes:
        if ob.get("no_decimate"):
            continue
        m = ob.modifiers.new("Dec", "DECIMATE")
        m.ratio = ratio
        m.use_collapse_triangulate = True
        apply_mods(ob)


def bake_ao(meshes, spec, size):
    if spec.get("ao", True) is False:
        for ob in meshes:
            me = ob.data
            a = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
            a.data.foreach_set("color", [1.0] * (len(me.loops) * 4))
            me.color_attributes.active_color = a
        return
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = spec.get("ao_samples", 48)
    if sc.world is None:
        sc.world = bpy.data.worlds.new("World")
    dist = spec.get("ao_distance", max(0.15, min(1.2, max(size) * 0.2)))
    sc.world.light_settings.distance = dist
    # ground plane so contact areas darken (removed afterwards)
    bpy.ops.mesh.primitive_plane_add(size=max(size) * 4 + 4, location=(0, 0, -0.001))
    ground = bpy.context.active_object
    strength = spec.get("ao_strength", 0.5)
    for ob in meshes:
        me = ob.data
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        a = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        me.color_attributes.active_color = a
        lib.select_only([ob], ob)
        try:
            bpy.ops.object.bake(type="AO", target="VERTEX_COLORS", use_clear=True, margin=0)
        except Exception as e:  # keep going with white
            print("  AO bake failed", ob.name, e)
            a.data.foreach_set("color", [1.0] * (len(me.loops) * 4))
            continue
        a = me.color_attributes.active_color
        c = [0.0] * (len(me.loops) * 4)
        a.data.foreach_get("color", c)
        for i in range(0, len(c), 4):
            ao = c[i]
            v = 1.0 - strength * (1.0 - ao)
            c[i] = c[i + 1] = c[i + 2] = v
            c[i + 3] = 1.0
        a.data.foreach_set("color", c)
        print(f"  AO {ob.name}: min {min(c[0::4]):.2f} mean {sum(c[0::4]) / max(1, len(c) // 4):.2f}")
    bpy.data.objects.remove(ground, do_unlink=True)


def export(objs, spec):
    cat = spec["category"]
    out_dir = os.path.join(lib.ASSETS, cat)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, spec["id"] + ".glb")
    lib.select_only(objs)
    anims = bool(spec.get("animations"))
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False,
        export_yup=True, export_vertex_color="ACTIVE", export_normals=True,
        export_texcoords=True, export_materials="EXPORT", export_image_format="AUTO",
        export_animations=anims, export_animation_mode=spec.get("anim_mode", "NLA_TRACKS"), export_force_sampling=True,
        export_def_bones=False, export_skins=True, export_extras=False,
        export_cameras=False, export_lights=False)
    return path


def finalize(objs, spec):
    budget = spec.get("budget")
    meshes = [o for o in objs if o.type == "MESH"]
    skinned = any(o.find_armature() for o in meshes)
    if not skinned:
        apply_transforms([m for m in meshes if not m.get("keep_location")])
    if spec.get("recentre", "generator" not in spec):
        normalise(objs, spec)
    if not skinned:
        lib.select_only(meshes)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        for o in meshes:  # bake location into mesh unless the node keeps a pivot
            if not o.get("keep_location"):
                o.data.transform(Matrix.Translation(o.location))
                o.location = (0, 0, 0)
    if spec.get("hard_surface", False):
        hard_surface(meshes, spec, budget)
    elif spec.get("smooth"):
        for ob in meshes:
            ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
    else:
        flat_shade(meshes)
    if not skinned:
        decimate(meshes, budget)
    arms = [o for o in objs if o.type == "ARMATURE"]
    for a in arms:
        a.data.pose_position = "REST"

    for ob in meshes:
        assign_palette_uv_and_materials(ob)
    mn, mx = lib.bbox(meshes)
    size = mx - mn
    bake_ao(meshes, spec, size)
    for a in arms:
        a.data.pose_position = "POSE"
    path = export(objs, spec)
    t = lib.tris(meshes)
    rep = {
        "id": spec["id"], "category": spec["category"],
        "path": "res://assets/%s/%s.glb" % (spec["category"], spec["id"]),
        "tris": t, "budget": budget,
        # Godot axes: x = Blender x, y = Blender z, z = Blender y
        "size_m": [round(size.x, 3), round(size.z, 3), round(size.y, 3)],
        "nodes": sorted(o.name for o in objs if o.parent is None or o.parent.type != "ARMATURE" or o.type == "MESH"),
        "animations": spec.get("_clip_names", []),
    }
    if arms:
        rep["rig"] = spec.get("_rig", "armature")
        rep["skeleton"] = arms[0].name
        rep["bones"] = len(arms[0].data.bones)
    os.makedirs(BUILD, exist_ok=True)
    with open(os.path.join(BUILD, spec["id"] + ".json"), "w") as f:
        json.dump(rep, f, indent=1)
    flag = "" if not budget or t <= budget else "  OVER BUDGET"
    print(f"BUILT {spec['id']}: {t} tris (budget {budget}) size {rep['size_m']}{flag}")
    return rep


# ------------------------------------------------------------ driver
def load_specs():
    with open(os.path.join(HERE, "assets.json")) as f:
        data = json.load(f)
    return data["assets"], data.get("defaults", {})


def build(spec):
    lib.reset_scene()
    if "generator" in spec:
        import generators
        objs = generators.run(spec["generator"], spec.get("params", {}))
    elif "custom" in spec:
        import importlib
        mod, fn = spec["custom"].rsplit(".", 1)
        objs = getattr(importlib.import_module(mod), fn)(spec)
    else:
        src = spec["source"]
        path = os.path.join(lib.ROOT, src["path"])
        objs = import_source(path)
        for o in [o for o in objs if o.type == "MESH"]:
            palettize_imported(o, spec)
    return finalize(objs, spec)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", default="")
    ap.add_argument("--batch", default="")
    a = ap.parse_args(argv)
    specs, defaults = load_specs()
    ids = [i for i in a.ids.split(",") if i]
    todo = [s for s in specs if (not ids or s["id"] in ids) and (not a.batch or s.get("batch") in a.batch.split(","))]
    failed = []
    for s in todo:
        spec = dict(defaults.get(s["category"], {}))
        spec.update(s)
        t0 = time.time()
        try:
            build(spec)
        except Exception:
            import traceback
            traceback.print_exc()
            failed.append(s["id"])
        print(f"  ({time.time() - t0:.1f}s)")
    if failed:
        print("FAILED:", ",".join(failed))
        sys.exit(1)


if __name__ == "__main__":
    main()
