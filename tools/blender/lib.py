"""Shared Blender helpers for the EMERGENCY CREW asset pipeline.

Conventions (see ART_BIBLE.md):
  * Blender units = metres, Z up. Asset FRONT faces Blender +Y, which the glTF
    exporter (+Y up) writes as -Z -> in Godot the front faces -Z.
  * Every face carries an int face attribute "pal" = palette index (0..63).
    finalize() collapses UVs to the palette cell centre and assigns the shared
    materials `palette` / `palette_emissive`.
"""
import math, os, random, sys
import bpy, bmesh
from mathutils import Matrix, Vector, Euler

sys.path.insert(0, os.path.dirname(__file__))
import palette as PAL  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "game", "assets")
PALETTE_PNG = os.path.join(ASSETS, "palette.png")
P = PAL.NAME_TO_INDEX  # name -> index


def pi(c):
    """palette index from int or name"""
    return c if isinstance(c, int) else P[c]


# ---------------------------------------------------------------- builder
class Builder:
    """Accumulates bmesh geometry per output node with a per-face palette index."""

    def __init__(self, seed=1, recalc=True):
        self.recalc = recalc
        self.nodes = {}
        self.pivots = {}
        self.rng = random.Random(seed)

    def bm(self, node):
        if node not in self.nodes:
            b = bmesh.new()
            b.faces.layers.int.new("pal")
            self.nodes[node] = b
        return self.nodes[node]

    def _tag(self, b, before, pal, matrix=None, face_pal=None):
        lay = b.faces.layers.int["pal"]
        new = [f for f in b.faces if f not in before]
        for f in new:
            f[lay] = pi(pal)
        if face_pal:
            # face_pal: {"+z": pal, "-y": pal, ...} chosen by face normal in world
            b.normal_update()
            for f in new:
                n = f.normal
                for k, v in face_pal.items():
                    ax = "xyz".index(k[1])
                    s = 1 if k[0] == "+" else -1
                    if n[ax] * s > 0.7:
                        f[lay] = pi(v)
        return new

    @staticmethod
    def mat(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
        R = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
        S = Matrix.Diagonal((*scale, 1.0))
        return Matrix.Translation(Vector(loc)) @ R @ S

    def box(self, node, size, loc, pal, rot=(0, 0, 0), face_pal=None):
        b = self.bm(node)
        before = set(b.faces)
        bmesh.ops.create_cube(b, size=1.0, matrix=self.mat(loc, rot, size))
        return self._tag(b, before, pal, face_pal=face_pal)

    def box_mm(self, node, mn, mx, pal, face_pal=None):
        """axis aligned box from min/max corners"""
        size = [mx[i] - mn[i] for i in range(3)]
        loc = [(mx[i] + mn[i]) / 2 for i in range(3)]
        return self.box(node, size, loc, pal, face_pal=face_pal)

    def cyl(self, node, r, h, loc, pal, segs=8, r2=None, rot=(0, 0, 0), cap_pal=None, scale=(1, 1, 1)):
        """cylinder/frustum along local Z centred at loc"""
        b = self.bm(node)
        before = set(b.faces)
        bmesh.ops.create_cone(b, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                              radius2=r if r2 is None else r2, depth=h,
                              matrix=self.mat(loc, rot, scale))
        new = self._tag(b, before, pal)
        if cap_pal is not None:
            lay = b.faces.layers.int["pal"]
            for f in new:
                if len(f.verts) == segs:
                    f[lay] = pi(cap_pal)
        return new

    def sphere(self, node, r, loc, pal, subdiv=1, scale=(1, 1, 1), jitter=0.0, rot=(0, 0, 0), flat_bottom=None):
        b = self.bm(node)
        before = set(b.faces)
        res = bmesh.ops.create_icosphere(b, subdivisions=subdiv, radius=r, matrix=self.mat(loc, rot, scale))
        if jitter:
            for v in res["verts"]:
                v.co += Vector([self.rng.uniform(-jitter, jitter) for _ in range(3)])
        if flat_bottom is not None:
            for v in res["verts"]:
                v.co.z = max(v.co.z, flat_bottom)
        return self._tag(b, before, pal)

    def extrude(self, node, profile_yz, x0, x1, pal, cap_pal=None):
        """extrude a closed (y,z) profile along X from x0 to x1"""
        n = len(profile_yz)
        verts = [(x0, y, z) for y, z in profile_yz] + [(x1, y, z) for y, z in profile_yz]
        faces = [list(range(n))[::-1], list(range(n, 2 * n))]
        pals = [cap_pal if cap_pal is not None else pal] * 2
        for i in range(n):
            j = (i + 1) % n
            faces.append([i, j, n + j, n + i])
            pals.append(pal)
        return self.poly(node, verts, faces, pal, face_pals=pals)

    def poly(self, node, verts, faces, pal, face_pals=None):
        b = self.bm(node)
        lay = b.faces.layers.int["pal"]
        vs = [b.verts.new(Vector(v)) for v in verts]
        out = []
        for i, f in enumerate(faces):
            face = b.faces.new([vs[k] for k in f])
            face[lay] = pi(face_pals[i] if face_pals else pal)
            out.append(face)
        return out

    def finish(self):
        objs = []
        col = bpy.context.scene.collection
        for name, b in self.nodes.items():
            bmesh.ops.remove_doubles(b, verts=b.verts, dist=1e-5)
            if self.recalc:
                bmesh.ops.recalc_face_normals(b, faces=b.faces)
            b.normal_update()
            me = bpy.data.meshes.new(name)
            b.to_mesh(me)
            b.free()
            ob = bpy.data.objects.new(name, me)
            col.objects.link(ob)
            if name in self.pivots:
                pv = Vector(self.pivots[name])
                me.transform(Matrix.Translation(-pv))
                ob.location = pv
                ob["keep_location"] = True
            objs.append(ob)
        self.nodes = {}
        return objs


# ---------------------------------------------------------------- materials
def get_palette_image():
    img = bpy.data.images.get("palette.png")
    if img is None:
        img = bpy.data.images.load(PALETTE_PNG)
        img.name = "palette.png"
    return img


def palette_material(emissive=False):
    name = "palette_emissive" if emissive else "palette"
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = get_palette_image()
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    if emissive:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
    return m


# ---------------------------------------------------------------- colour
def srgb_to_lab(rgb):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


_PAL_LAB = None


def nearest_palette(rgb255, allowed=None):
    """nearest palette cell by CIELAB distance (perceived colour)"""
    global _PAL_LAB
    if _PAL_LAB is None:
        _PAL_LAB = [srgb_to_lab(PAL.rgb(i)) for i in range(64)]
    L = srgb_to_lab(rgb255)
    best, bd = 0, 1e9
    for i in (allowed or range(64)):
        if i in PAL.EMISSIVE and allowed is None:
            continue  # never map to emissive cells implicitly
        d = sum((a - b) ** 2 for a, b in zip(L, _PAL_LAB[i]))
        if d < bd:
            best, bd = i, d
    return best


# ---------------------------------------------------------------- utils
def tris(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for o in objs:
        if o.type != "MESH":
            continue
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        me.calc_loop_triangles()
        n += len(me.loop_triangles)
        e.to_mesh_clear()
    return n


def bbox(objs):
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        if o.type != "MESH":
            continue
        e = o.evaluated_get(dg)
        me = e.to_mesh()
        for v in me.vertices:
            w = e.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
        e.to_mesh_clear()
    return mn, mx


def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
