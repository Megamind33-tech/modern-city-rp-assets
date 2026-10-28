"""Character builder: Quaternius Universal Base Characters (CC0) + Universal Animation
Library 1/2 (CC0) -> re-paletted, reduced-rig, single-mesh characters with embedded clips.

Steps: import base body (+hair) -> enlarge head/hands (Living Diorama x1.1, child more)
-> merge finger weights into hands and drop finger/leaf bones (65 -> 23 bones)
-> decimate to budget -> paint palette regions from bone weights + height bands
(skin/top/bottom/shoes, crew hi-vis bands, painted eyes/brows) -> add helmet/beanie
-> import UAL clips + build procedural clips (wave, cheer, sad, work) -> NLA tracks named
with the final clip names. Front is turned to Blender +Y (Godot -Z) via the Armature
object's rotation; height via the Armature object's scale (not applied, so clips stay valid).
"""
import math, os
import bpy, bmesh
from mathutils import Vector, Matrix, Quaternion
import lib
from lib import P

SRC = os.path.join(lib.ROOT, "tools", "asset_sources")
UBC = os.path.join(SRC, "ubc", "Universal Base Characters[Standard]")
BASES = {"male": os.path.join(UBC, "Base Characters", "Godot - UE", "Superhero_Male_FullBody.gltf"),
         "female": os.path.join(UBC, "Base Characters", "Godot - UE", "Superhero_Female_FullBody.gltf")}
HAIR_DIR = os.path.join(UBC, "Hairstyles", "Rigged to Head Bone", "glTF (Godot -Unreal)")
UAL1 = os.path.join(SRC, "uanim", "Universal Animation Library[Standard]", "Unreal-Godot", "UAL1_Standard.glb")
UAL2 = os.path.join(SRC, "uanim2", "Universal Animation Library 2[Standard]", "Unreal-Godot", "UAL2_Standard.glb")

# final clip name -> (source library, source action) ; procedural ones use ("proc", base)
CLIPS = [
    ("idle", "UAL1", "Idle_Loop"),
    ("walk", "UAL1", "Walk_Loop"),
    ("run", "UAL1", "Jog_Fwd_Loop"),
    ("carry_walk", "UAL2", "Walk_Carry_Loop"),
    ("work", "proc", "Idle_Loop"),
    ("interact", "UAL1", "Interact"),
    ("wave", "proc", "Idle_Loop"),
    ("cheer", "proc", "Idle_Loop"),
    ("sad", "proc", "Idle_Loop"),
    ("pickup", "UAL1", "PickUp_Table"),
    ("talk", "UAL1", "Idle_Talking_Loop"),
    ("phone", "UAL2", "Idle_TalkingPhone_Loop"),
    ("kneel_work", "UAL1", "Fixing_Kneeling"),
    ("chop", "UAL2", "TreeChopping_Loop"),
]
LOOPING = {"idle", "walk", "run", "carry_walk", "work", "wave", "cheer", "sad", "talk", "phone", "kneel_work", "chop"}
KEEP_BONES = {"root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
              "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
              "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"}


def _import(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def _delete(objs):
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)


def _upd():
    bpy.context.view_layer.update()


def bake_pose_into_mesh(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in meshes:
        e = ob.evaluated_get(dg)
        co = [v.co.copy() for v in e.data.vertices]
        for v, c in zip(ob.data.vertices, co):
            v.co = c


# ------------------------------------------------------------------ painting
def vgroup_dominant(ob):
    names = {g.index: g.name for g in ob.vertex_groups}
    dom = []
    for v in ob.data.vertices:
        best, w = None, -1
        for g in v.groups:
            if g.weight > w:
                best, w = names[g.group], g.weight
        dom.append(best)
    return dom


def paint(ob, look, H, eyes, pelvis_z, fwd):
    me = ob.data
    dom = vgroup_dominant(ob)
    pal = me.attributes.get("pal") or me.attributes.new("pal", "INT", "FACE")
    vals = []
    waist = pelvis_z + 0.07 * H / 1.8
    for p in me.polygons:
        c = p.center
        z = c.z
        counts = {}
        for vi in p.vertices:
            counts[dom[vi]] = counts.get(dom[vi], 0) + 1
        g = max(counts, key=counts.get) or ""
        if g in ("Head", "neck_01"):
            col = look["skin"]
        elif g.startswith("hand"):
            col = look.get("gloves", look["skin"])
        elif g.startswith(("upperarm", "lowerarm")):
            col = look.get("sleeves", look["top"])
            if look.get("short_sleeves") and g.startswith("lowerarm"):
                col = look["skin"]
        elif g.startswith(("foot", "ball")):
            col = look["shoes"]
        elif g.startswith("calf") and z < 0.09 * H:
            col = look["shoes"]
        elif z > waist:
            col = look["top"]
        else:
            col = look["bottom"]
        if look.get("hivis"):
            # chest band (on top garment) + shin bands (on trousers)
            if col == look["top"] and 0.585 * H < z < 0.63 * H and g not in ("Head", "neck_01"):
                col = "hi_vis"
            if col == look["bottom"] and 0.17 * H < z < 0.21 * H:
                col = "hi_vis"
            if g.startswith("lowerarm") and 0.3 * H < abs(c.x) < 0.335 * H:
                col = "hi_vis"
        vals.append(lib.pi(col))
    # painted eyes + brows (nearest front-facing head faces)
    if eyes:
        for e in eyes:
            for target, colname, rad in ((e, "hair_dark", 0.016 * H / 1.8), (e + Vector((0, 0, 0.032 * H / 1.8)), look["hair"], 0.013 * H / 1.8)):
                cands = sorted(((p.center - target).length, p.index) for p in me.polygons
                               if p.normal.dot(fwd) > 0.3 and dom[p.vertices[0]] == "Head")
                hit = [i for d, i in cands if d < rad] or [cands[0][1]]
                for i in hit:
                    vals[i] = lib.pi(colname)
    pal.data.foreach_set("value", vals)


def cut_bands(ob, look, H, pelvis_z):
    """bisect the body along region boundaries so painted bands get straight edges"""
    zs = [pelvis_z + 0.07 * H / 1.8, 0.09 * H]
    xs = []
    if look.get("hivis"):
        zs += [0.585 * H, 0.63 * H, 0.17 * H, 0.21 * H]
        xs += [0.3 * H, 0.335 * H, -0.3 * H, -0.335 * H]
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for z in zs:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z), plane_no=(0, 0, 1))
    for x in xs:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(x, 0, 0), plane_no=(1, 0, 0))
    bm.to_mesh(ob.data)
    bm.free()


def set_pal(ob, col):
    me = ob.data
    pal = me.attributes.get("pal") or me.attributes.new("pal", "INT", "FACE")
    pal.data.foreach_set("value", [lib.pi(col)] * len(me.polygons))


def decimate_to(ob, target):
    me = ob.data
    me.calc_loop_triangles()
    t = len(me.loop_triangles)
    if t <= target:
        return
    m = ob.modifiers.new("Dec", "DECIMATE")
    m.ratio = target / t
    lib.select_only([ob], ob)
    bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
    bpy.ops.object.modifier_apply(modifier=m.name)


# ------------------------------------------------------------------ accessories
def head_info(body):
    dom = vgroup_dominant(body)
    vs = [v.co for v, d in zip(body.data.vertices, dom) if d == "Head"]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


def add_headwear(arm, body, kind, fwd):
    mn, mx = head_info(body)
    c = (mn + mx) / 2
    r = max(mx.x - mn.x, mx.y - mn.y) / 2
    b = lib.Builder()
    N = "Headwear"
    if kind == "helmet":  # fire/rescue helmet: dome + brim + comb
        b.sphere(N, r * 1.18, (c.x, c.y, mx.z - r * 0.55), "shirt_white", subdiv=2, scale=(1, 1.05, 0.95), flat_bottom=mx.z - r * 0.55)
        b.cyl(N, r * 1.35, 0.025 * r / 0.1, (c.x, c.y - fwd.y * r * 0.12, mx.z - r * 0.5), "shirt_white", segs=14, scale=(1, 1.12, 1))
        b.box(N, (r * 0.18, r * 2.0, r * 0.25), (c.x, c.y, mx.z + r * 0.55), "shirt_white")
        b.box(N, (r * 0.9, 0.012, r * 0.18), (c.x, c.y + fwd.y * r * 1.17, mx.z - r * 0.2), "hi_vis")
    elif kind == "beanie":
        b.sphere(N, r * 1.12, (c.x, c.y, mx.z - r * 0.6), "knit_red", subdiv=2, scale=(1, 1.05, 1.0), flat_bottom=mx.z - r * 0.6)
        b.cyl(N, r * 1.14, r * 0.3, (c.x, c.y, mx.z - r * 0.5), "red_dark", segs=12, scale=(1, 1.05, 1))
    objs = b.finish()
    ob = objs[0]
    # Builder wrote 'pal' ints already; skin fully to the Head bone
    vg = ob.vertex_groups.new(name="Head")
    vg.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    ob.parent = arm
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    return ob


# ------------------------------------------------------------------ animation
def load_library(path):
    objs = _import(path)
    acts = {a.name: a for a in bpy.data.actions}
    _delete(objs)
    return acts


def assign(arm, act):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and len(getattr(act, "slots", [])):
        ad.action_slot = act.slots[0]


def aim(arm, bname, target):
    pb = arm.pose.bones[bname]
    cur = (pb.tail - pb.head)
    q = cur.normalized().rotation_difference(Vector(target).normalized())
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ pb.matrix
    _upd()


def rot(arm, bname, axis, ang):
    pb = arm.pose.bones[bname]
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(ang, 4, Vector(axis)) @ Matrix.Translation(-h) @ pb.matrix
    _upd()


def proc_clip(arm, base, name, fwd, length=60):
    """sample base action, apply pose-space overrides, key into a new action"""
    side = Vector((1, 0, 0)) if fwd.y < 0 else Vector((-1, 0, 0))  # character's LEFT in armature space
    up = Vector((0, 0, 1))
    pitch_axis = up.cross(fwd)  # positive angle tilts the top forward
    f0, f1 = (int(v) for v in base.frame_range)
    frames = []
    for i in range(length + 1):
        t = i / length
        assign(arm, base)
        bpy.context.scene.frame_set(f0 + int((f1 - f0) * t) if f1 > f0 else f0)
        _upd()
        s = math.sin(t * math.tau)
        L, R = side, -side
        if name == "wave":
            aim(arm, "upperarm_r", R * 0.55 + up * 0.85 + fwd * 0.05)
            aim(arm, "lowerarm_r", R * (0.15 + 0.35 * math.sin(t * math.tau * 3)) + up * 1.0 + fwd * 0.1)
            aim(arm, "hand_r", R * (0.1 + 0.3 * math.sin(t * math.tau * 3)) + up)
            rot(arm, "Head", fwd.cross(up), 0.08)
        elif name == "cheer":
            pump = abs(math.sin(t * math.tau * 2))
            for sd, bs in ((L, "_l"), (R, "_r")):
                aim(arm, "upperarm" + bs, sd * 0.45 + up * 0.9 + fwd * 0.1)
                aim(arm, "lowerarm" + bs, sd * (0.15 + 0.1 * pump) + up * 1.0 + fwd * 0.15)
            pb = arm.pose.bones["pelvis"]
            pb.matrix = Matrix.Translation(up * 0.06 * pump) @ pb.matrix
            _upd()
            rot(arm, "Head", pitch_axis, -0.2)
        elif name == "sad":
            sway = 0.03 * s
            rot(arm, "spine_02", pitch_axis, 0.12)
            rot(arm, "spine_03", pitch_axis, 0.12)
            rot(arm, "neck_01", pitch_axis, 0.25)
            rot(arm, "Head", pitch_axis, 0.3 + sway)
            for sd, bs in ((L, "_l"), (R, "_r")):
                aim(arm, "upperarm" + bs, sd * 0.12 - up + fwd * 0.08)
                aim(arm, "lowerarm" + bs, sd * 0.05 - up + fwd * 0.35)
        elif name == "work":
            # standing two-handed tool use (chainsaw at waist height), small push/pull + buzz
            push = 0.05 * math.sin(t * math.tau * 2)
            buzz = 0.012 * math.sin(t * math.tau * 23)
            rot(arm, "spine_02", pitch_axis, 0.18 + push)
            for sd, bs, k in ((L, "_l", 0.25), (R, "_r", 0.12)):
                aim(arm, "upperarm" + bs, sd * k - up * 0.75 + fwd * 0.55)
                aim(arm, "lowerarm" + bs, -sd * 0.15 - up * (0.35 + buzz * 3) + fwd * 1.0)
            rot(arm, "Head", pitch_axis, 0.25)
        frames.append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy()) for pb in arm.pose.bones})
    act = bpy.data.actions.new(name)
    assign(arm, act)
    for i, fr in enumerate(frames):
        for pb in arm.pose.bones:
            loc, q = fr[pb.name]
            pb.location = loc
            pb.rotation_quaternion = q
            pb.keyframe_insert("location", frame=i)
            pb.keyframe_insert("rotation_quaternion", frame=i)
    return act


# ------------------------------------------------------------------ main
def build(spec):
    look = spec["look"]
    H = spec.get("height", 1.75)
    objs = _import(BASES[look.get("base", "male")])
    arm = next(o for o in objs if o.type == "ARMATURE")
    meshes = [o for o in objs if o.type == "MESH"]
    stray = [o for o in meshes if o.parent is None]  # stray icosphere
    meshes = [o for o in meshes if o.parent is not None]
    _delete(stray)
    body = max(meshes, key=lambda o: len(o.data.polygons))
    eyes_ob = next((o for o in meshes if o.name.startswith("Eyes")), None)
    _delete([o for o in meshes if o not in (body, eyes_ob)])
    # hair (rigged to Head in the same skeleton space)
    hair_obs = []
    head_rest = arm.data.bones["Head"].matrix_local.copy()
    for hname in look.get("hair_meshes", []):
        ho = _import(os.path.join(HAIR_DIR, hname + ".gltf"))
        harm = next(o for o in ho if o.type == "ARMATURE")
        hm = [o for o in ho if o.type == "MESH" and o.parent is not None]
        _delete([o for o in ho if o.type == "MESH" and o.parent is None])
        ho = [o for o in ho if o in hm or o == harm]
        corr = arm.matrix_world @ head_rest @ (harm.matrix_world @ harm.data.bones["Head"].matrix_local).inverted()
        for m in hm:
            mw = m.matrix_world.copy()
            m.parent = None
            m.matrix_world = corr @ mw
            for md in list(m.modifiers):
                m.modifiers.remove(md)
            lib.select_only([m], m)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            m.data.transform(arm.matrix_world.inverted())
            m.matrix_world = arm.matrix_world.copy()
            m.parent = arm
            md = m.modifiers.new("Armature", "ARMATURE")
            md.object = arm
            hair_obs.append(m)
        _delete([o for o in ho if o not in hm])
    for m in hair_obs:
        set_pal(m, look["hair"])
    # enlarge head / hands (bake into mesh, rest pose untouched)
    hs = spec.get("head_scale", 1.1)
    arm.pose.bones["Head"].scale = (hs, hs, hs)
    for s in ("hand_l", "hand_r"):
        arm.pose.bones[s].scale = (1.1, 1.1, 1.1)
    _upd()
    all_m = [body] + hair_obs + ([eyes_ob] if eyes_ob else [])
    bake_pose_into_mesh(all_m)
    for pb in arm.pose.bones:
        pb.scale = (1, 1, 1)
    _upd()
    # facing: eyes in front of the head
    hmn, hmx = head_info(body)
    eyes = []
    if eyes_ob:
        vs = [v.co for v in eyes_ob.data.vertices]
        for sgn in (-1, 1):
            side = [v for v in vs if v.x * sgn > 0]
            eyes.append(sum(side, Vector()) / len(side))
        _delete([eyes_ob])
    fwd = Vector((0, -1, 0)) if (eyes and eyes[0].y < (hmn.y + hmx.y) / 2) else Vector((0, 1, 0))
    # bones: merge fingers -> hands, drop leaf/finger bones
    for side in ("l", "r"):
        hand = body.vertex_groups.get("hand_" + side)
        for ob in [body] + hair_obs:
            hv = ob.vertex_groups.get("hand_" + side) or ob.vertex_groups.new(name="hand_" + side)
            for g in list(ob.vertex_groups):
                if g.name.endswith("_" + side) and any(g.name.startswith(f) for f in ("index", "middle", "pinky", "ring", "thumb")):
                    for v in ob.data.vertices:
                        for vg in v.groups:
                            if vg.group == g.index and vg.weight > 0:
                                hv.add([v.index], vg.weight, "ADD")
                    ob.vertex_groups.remove(g)
    for ob in [body] + hair_obs:
        for g in list(ob.vertex_groups):
            if g.name not in KEEP_BONES:
                ob.vertex_groups.remove(g)
    lib.select_only([arm], arm)
    bpy.ops.object.mode_set(mode="EDIT")
    for eb in list(arm.data.edit_bones):
        if eb.name not in KEEP_BONES:
            arm.data.edit_bones.remove(eb)
    bpy.ops.object.mode_set(mode="OBJECT")
    # budget: hair first, body gets the rest
    budget = spec.get("budget", 3000)
    hair_budget = spec.get("hair_budget", 450)
    for m in hair_obs:
        decimate_to(m, hair_budget // max(1, len(hair_obs)))
    head_extra = 260 if look.get("headwear") else 0
    used = 0
    for m in hair_obs:
        m.data.calc_loop_triangles()
        used += len(m.data.loop_triangles)
    cut_reserve = 420 if look.get("hivis") else 160
    decimate_to(body, int(budget * 0.97) - used - head_extra - cut_reserve)
    pelvis_z = (arm.matrix_world @ arm.data.bones["pelvis"].head_local).z
    rest_h = max((arm.matrix_world @ v.co).z for v in body.data.vertices)
    cut_bands(body, look, rest_h, pelvis_z)
    paint(body, look, rest_h, eyes, pelvis_z, fwd)
    extra = []
    if look.get("headwear"):
        extra.append(add_headwear(arm, body, look["headwear"], fwd))
    # join everything into one skinned mesh "Body"
    lib.select_only([body] + hair_obs + extra, body)
    if len(hair_obs + extra):
        bpy.ops.object.join()
    body.name = body.data.name = "Body"
    for m in list(body.modifiers):
        if m.type == "ARMATURE":
            m.object = arm
    if not any(m.type == "ARMATURE" for m in body.modifiers):
        body.modifiers.new("Armature", "ARMATURE").object = arm
    # animations
    arm.name = "Armature"
    lib_acts = {}
    lib_acts["UAL1"] = load_library(UAL1)
    lib_acts["UAL2"] = load_library(UAL2)
    ad = arm.animation_data or arm.animation_data_create()
    clips = []
    for name, src, base in CLIPS:
        if src == "proc":
            act = proc_clip(arm, lib_acts["UAL1"][base], name, fwd)
        else:
            act = lib_acts[src][base].copy()
            act.name = name
        act.use_fake_user = False
        tr = ad.nla_tracks.new()
        tr.name = name
        st = tr.strips.new(name, int(act.frame_range[0]), act)
        if hasattr(st, "action_slot") and len(getattr(act, "slots", [])):
            st.action_slot = act.slots[0]
        clips.append(name)
    ad.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    # orientation + height on the armature object (clips stay in bone space)
    s = H / rest_h
    arm.scale = (s, s, s)
    arm.rotation_mode = "XYZ"
    if fwd.y < 0:
        arm.rotation_euler = (0, 0, math.pi)
    spec["_clip_names"] = clips
    spec["_rig"] = "Quaternius UE-style humanoid, %d bones" % len(arm.data.bones)
    spec["recentre"] = False
    return [arm, body]
