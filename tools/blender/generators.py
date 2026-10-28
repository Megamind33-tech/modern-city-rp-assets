"""Parametric "Living Diorama" generators, authored directly on the palette.

Every generator returns the list of Blender objects (one per output node).
Authoring frame: metres, Z up, FRONT = +Y (exports to Godot -Z), pivot = base
centre on z=0. Colours are palette names (see palette.py).
"""
import math, random
import bmesh
from mathutils import Vector, Matrix
from lib import Builder, P

GEN = {}


def gen(fn):
    GEN[fn.__name__] = fn
    return fn


def run(name, params):
    return GEN[name](**params)


# =============================================================== shared bits
def window(b, node, x0, x1, z0, z1, face_y, frame="plaster", glass="glass", sill=True, depth=0.06, side=+1):
    """window on a wall whose outer face is at y=face_y (side=+1 front, -1 back)"""
    s = side
    b.box_mm(node, (x0 - 0.1, min(face_y, face_y + s * 0.04), z0 - 0.1), (x1 + 0.1, max(face_y, face_y + s * 0.04), z1 + 0.1), frame)
    b.box_mm(node, (x0, min(face_y, face_y + s * depth), z0), (x1, max(face_y, face_y + s * depth), z1), glass)
    # mullion
    xm = (x0 + x1) / 2
    b.box_mm(node, (xm - 0.04, min(face_y, face_y + s * (depth + 0.02)), z0), (xm + 0.04, max(face_y, face_y + s * (depth + 0.02)), z1), frame)
    if sill:
        b.box_mm(node, (x0 - 0.15, min(face_y, face_y + s * 0.14), z0 - 0.2), (x1 + 0.15, max(face_y, face_y + s * 0.14), z0 - 0.08), frame)


def side_window(b, node, y0, y1, z0, z1, face_x, frame="plaster", side=+1):
    s = side
    b.box_mm(node, (min(face_x, face_x + s * 0.04), y0 - 0.1, z0 - 0.1), (max(face_x, face_x + s * 0.04), y1 + 0.1, z1 + 0.1), frame)
    b.box_mm(node, (min(face_x, face_x + s * 0.06), y0, z0), (max(face_x, face_x + s * 0.06), y1, z1), "glass")
    b.box_mm(node, (min(face_x, face_x + s * 0.14), y0 - 0.15, z0 - 0.2), (max(face_x, face_x + s * 0.14), y1 + 0.15, z0 - 0.08), frame)


def ring(b, node, x0, y0, x1, y1, z0, z1, w, pal):
    """rectangular parapet ring (4 boxes)"""
    b.box_mm(node, (x0, y0, z0), (x1, y0 + w, z1), pal)
    b.box_mm(node, (x0, y1 - w, z0), (x1, y1, z1), pal)
    b.box_mm(node, (x0, y0 + w, z0), (x0 + w, y1 - w, z1), pal)
    b.box_mm(node, (x1 - w, y0 + w, z0), (x1, y1 - w, z1), pal)


# =============================================================== station hall
@gen
def station_hall(seed=1):
    b = Builder(seed)
    B = "Body"
    W0, W1, D0, D1, H = -11.0, 11.0, -5.0, 5.0, 6.0
    TX = 7.4  # tower starts here
    # plinth + main brick volume (flat roof slate on top)
    b.box_mm(B, (W0 - 0.05, D0 - 0.05, 0), (W1 + 0.05, D1 + 0.05, 0.3), "concrete")
    b.box_mm(B, (W0, D0, 0), (TX, D1, H), "brick", face_pal={"+z": "slate"})
    b.box_mm(B, (TX, D0, 0), (W1, 1.4, H), "brick", face_pal={"+z": "slate"})
    # navy trim band + cream coping
    ring(b, B, W0 - 0.08, D0 - 0.08, TX + 0.01, D1 + 0.08, H - 0.45, H - 0.01, 0.3, "navy")
    ring(b, B, W0 - 0.12, D0 - 0.12, TX + 0.01, D1 + 0.12, H, H + 0.2, 0.3, "cream")
    ring(b, B, TX - 0.29, D0 - 0.08, W1 + 0.08, 1.4, H - 0.45, H - 0.01, 0.3, "navy")
    ring(b, B, TX - 0.29, D0 - 0.12, W1 + 0.12, 1.4, H, H + 0.2, 0.3, "cream")
    # tower
    T0, T1, TH = 1.4, 5.4, 10.0
    b.box_mm(B, (TX, T0, 0), (W1, T1, TH), "brick")
    b.box_mm(B, (TX - 0.08, T0 - 0.08, TH - 0.5), (W1 + 0.08, T1 + 0.08, TH), "navy")
    b.box_mm(B, (TX - 0.12, T0 - 0.12, TH), (W1 + 0.12, T1 + 0.12, TH + 0.12), "cream")
    cx, cy = (TX + W1) / 2, (T0 + T1) / 2
    b.cyl(B, 2.75, 0.9, (cx, cy, TH + 0.12 + 0.45), "slate", segs=4, r2=0.05, rot=(0, 0, 45))
    # tower emblem (red roundel with cream centre) + window + louvre
    b.cyl(B, 0.75, 0.08, (cx, T1 + 0.04, 8.2), "signal_red", segs=12, rot=(90, 0, 0))
    b.cyl(B, 0.48, 0.1, (cx, T1 + 0.06, 8.2), "cream", segs=12, rot=(90, 0, 0))
    b.box_mm(B, (cx - 0.08, T1, 7.9), (cx + 0.08, T1 + 0.13, 8.5), "navy")
    window(b, B, cx - 0.6, cx + 0.6, 3.2, 5.6, T1)
    window(b, B, cx - 0.5, cx + 0.5, 1.0, 2.4, T1)
    # two appliance bays (frames + sign); doors are separate nodes
    bays = [(-8.4, "BayDoor1"), (-3.4, "BayDoor2")]
    BW, BH = 4.2, 4.6
    for x, node in bays:
        b.box_mm(B, (x - BW / 2 - 0.35, D1, 0.3), (x - BW / 2, D1 + 0.14, BH + 0.35), "cream")
        b.box_mm(B, (x + BW / 2, D1, 0.3), (x + BW / 2 + 0.35, D1 + 0.14, BH + 0.35), "cream")
        b.box_mm(B, (x - BW / 2 - 0.35, D1, BH), (x + BW / 2 + 0.35, D1 + 0.14, BH + 0.35), "cream")
        # dark bay interior so an opened door reads as a hole
        b.box_mm(B, (x - BW / 2, D1 - 0.02, 0.0), (x + BW / 2, D1 + 0.001, BH), "tyre")
        # roller door: red panel, window strip, slat lines
        b.box_mm(node, (x - BW / 2, D1 - 0.02, 0.02), (x + BW / 2, D1 + 0.06, BH), "signal_red")
        b.box_mm(node, (x - BW / 2 + 0.25, D1 + 0.05, 2.9), (x + BW / 2 - 0.25, D1 + 0.09, 3.35), "glass")
        for zz in (1.1, 2.0, 3.8):
            b.box_mm(node, (x - BW / 2 + 0.05, D1 + 0.05, zz), (x + BW / 2 - 0.05, D1 + 0.08, zz + 0.07), "red_dark")
        b.pivots[node] = (x, D1, BH)  # pivot at top-centre of opening: scale/translate up to open
    # sign board over the bays
    b.box_mm(B, (-10.9, D1, 5.0), (-0.9, D1 + 0.18, 5.5), "navy")
    b.box_mm(B, (-9.4, D1 + 0.18, 5.15), (-2.4, D1 + 0.22, 5.35), "cream")
    b.box_mm(B, (-10.6, D1 + 0.18, 5.15), (-9.9, D1 + 0.22, 5.35), "signal_red")
    # office section: door + windows
    b.box_mm(B, (0.2, D1, 0.3), (1.6, D1 + 0.1, 2.6), "cream")
    b.box_mm(B, (0.35, D1, 0.3), (1.45, D1 + 0.14, 2.45), "door_navy")
    b.box_mm(B, (0.0, D1, 2.6), (1.8, D1 + 0.9, 2.72), "navy")  # door canopy
    b.box_mm(B, (0.1, D1, 0.0), (1.7, D1 + 0.5, 0.3), "concrete")
    window(b, B, 2.4, 4.4, 1.0, 2.4, D1)
    window(b, B, 5.0, 6.9, 1.0, 2.4, D1)
    for x0 in (0.0, 2.6, 5.0):
        window(b, B, x0, x0 + 1.8, 3.4, 4.8, D1)
    # back + sides
    for x0 in (-9.5, -5.5, -1.5, 2.5, 6.5):
        window(b, B, x0, x0 + 1.6, 3.4, 4.6, D0, side=-1)
    window(b, B, 8.4, 10.0, 1.0, 2.4, D0, side=-1)
    b.box_mm(B, (-0.6, D0 - 0.12, 0.3), (0.6, D0, 2.45), "door_navy")
    for y0 in (-3.5, 0.5):
        side_window(b, B, y0, y0 + 1.8, 3.4, 4.6, W0, side=-1)
    side_window(b, B, -3.0, -1.4, 3.4, 4.6, W1, side=+1)
    side_window(b, B, 2.6, 4.2, 6.5, 8.6, W1, side=+1)
    # roof kit: AC box + vent
    b.box_mm(B, (-6, -3, H), (-4.4, -1.8, H + 0.7), "steel")
    b.box_mm(B, (2, 0, H), (2.6, 0.6, H + 0.5), "steel")
    # downpipes
    for x in (W0 + 0.15, TX - 0.2):
        b.box_mm(B, (x - 0.07, D1, 0.0), (x + 0.07, D1 + 0.14, H - 0.45), "navy")
    return b.finish()


# =============================================================== houses
ROOF_PITCH = 35.0
WALL_H = 6.0
HX, HY = 3.5, 4.0          # half footprint (7 x 8)
OV_F, OV_S = 0.35, 0.25    # eave / verge overhang
ROOF_T = 0.16


def roof_slope_point(x, t, off=0.0):
    """point on the FRONT roof slope top surface. t=0 at front eave edge, 1 at ridge."""
    tanp = math.tan(math.radians(ROOF_PITCH))
    ye = HY + OV_F
    ze = WALL_H - OV_F * tanp
    zr = WALL_H + HY * tanp
    y = ye * (1 - t)
    z = ze + (zr - ze) * t
    n = Vector((0, math.sin(math.radians(ROOF_PITCH)), math.cos(math.radians(ROOF_PITCH))))
    return Vector((x, y, z)) + n * off


def gable_roof(b, node, pal, x0=-HX - OV_S, x1=HX + OV_S):
    tanp = math.tan(math.radians(ROOF_PITCH))
    ye = HY + OV_F
    ze = WALL_H - OV_F * tanp
    zr = WALL_H + HY * tanp
    dz = ROOF_T / math.cos(math.radians(ROOF_PITCH))
    prof = [(ye, ze), (0, zr), (-ye, ze), (-ye, ze - dz), (0, zr - dz), (ye, ze - dz)]
    b.extrude(node, prof, x0, x1, pal)
    # ridge cap
    b.box(node, (x1 - x0 + 0.04, 0.22, 0.14), ((x0 + x1) / 2, 0, zr + 0.02), "slate" if pal != "slate" else "roof_brown", rot=(0, 0, 0))
    return zr


def gable_fill(b, node, pal, x0=-HX, x1=HX):
    tanp = math.tan(math.radians(ROOF_PITCH))
    zr = WALL_H + HY * tanp
    b.extrude(node, [(HY, WALL_H), (0, zr - 0.05), (-HY, WALL_H)], x0, x1, pal)


def door(b, node, xc, pal, face_y=HY, z0=0.35, w=1.0, h=2.1, hood="roof"):
    b.box_mm(node, (xc - w / 2 - 0.12, face_y, z0), (xc + w / 2 + 0.12, face_y + 0.06, z0 + h + 0.12), "plaster")
    b.box_mm(node, (xc - w / 2, face_y, z0), (xc + w / 2, face_y + 0.1, z0 + h), pal)
    b.box_mm(node, (xc + w / 2 - 0.2, face_y + 0.1, z0 + 1.0), (xc + w / 2 - 0.12, face_y + 0.14, z0 + 1.08), "amber")  # knob
    b.box_mm(node, (xc - w / 2 - 0.25, face_y, 0), (xc + w / 2 + 0.25, face_y + 0.45, 0.2), "concrete")  # step


@gen
def house(walls="butter", roof="slate", door_col="door_navy", trim="plaster", door_x=-1.7,
          bay=False, porch=False, chimney_x=2.6, cross_gable=False, plinth="concrete", seed=1,
          flower_box=False):
    b = Builder(seed)
    B, R = "Body", "Roof"
    b.box_mm(B, (-HX - 0.06, -HY - 0.06, 0), (HX + 0.06, HY + 0.06, 0.35), plinth)
    b.box_mm(B, (-HX, -HY, 0.35), (HX, HY, WALL_H), walls)
    gable_fill(b, B, walls)
    # storey band
    b.box_mm(B, (-HX - 0.05, -HY - 0.05, 3.0), (HX + 0.05, HY + 0.05, 3.15), trim)
    door(b, B, door_x, door_col)
    if porch:
        b.box_mm(B, (door_x - 1.0, HY, 2.55), (door_x + 1.0, HY + 1.1, 2.7), roof)
        for sx in (-0.9, 0.9):
            b.box_mm(B, (door_x + sx - 0.07, HY + 0.9, 0.0), (door_x + sx + 0.07, HY + 1.04, 2.55), trim)
    else:
        b.box_mm(B, (door_x - 0.75, HY, 2.6), (door_x + 0.75, HY + 0.55, 2.72), trim)
    # ground floor front window / bay
    if bay:
        x0, x1 = 0.0, 2.8
        b.box_mm(B, (x0, HY, 0.35), (x1, HY + 0.7, 2.7), walls, face_pal={"+z": roof})
        window(b, B, x0 + 0.25, x1 - 0.25, 1.0, 2.35, HY + 0.7)
        b.box_mm(B, (x0 - 0.05, HY, 2.7), (x1 + 0.05, HY + 0.8, 2.85), roof)
    else:
        window(b, B, 0.2, 2.6, 1.0, 2.4, HY)
    if flower_box:
        b.box_mm(B, (0.2, HY + 0.12, 0.7), (2.6, HY + 0.4, 0.85), "light_wood")
        for i in range(5):
            b.sphere(B, 0.14, (0.45 + i * 0.47, HY + 0.26, 0.95), "flower_pink" if i % 2 else "flower_yellow", subdiv=1)
    # upper front windows
    if cross_gable:
        # front-projecting gable on the left half (keeps right roof slope free)
        gx0, gx1 = -HX, -0.2
        b.box_mm(B, (gx0, HY, 0.35), (gx1, HY + 0.8, WALL_H), walls)
        gw = (gx1 - gx0) / 2
        tanp = math.tan(math.radians(ROOF_PITCH + 10))
        gzr = WALL_H + gw * tanp
        gxc = (gx0 + gx1) / 2
        # gable triangle (profile in x,z extruded along y)
        verts = [(gx0, HY, WALL_H), (gx1, HY, WALL_H), (gxc, HY, gzr), (gx0, HY + 0.8, WALL_H), (gx1, HY + 0.8, WALL_H), (gxc, HY + 0.8, gzr)]
        b.poly(B, verts, [[0, 1, 2], [3, 5, 4], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]], walls)
        # its little roof (two slabs) in the Roof node
        for sgn in (-1, 1):
            ang = math.radians(ROOF_PITCH + 10)
            L = gw / math.cos(ang) + 0.25
            cxs = gxc + sgn * (gw / 2 + 0.05)
            b.box(R, (L, 1.6, ROOF_T), (cxs, HY + 0.25, (WALL_H + gzr) / 2 + 0.12), roof, rot=(0, sgn * (ROOF_PITCH + 10), 0))
        window(b, B, gx0 + 0.6, gx1 - 0.6, 3.7, 5.1, HY + 0.8)
        window(b, B, 0.6, 2.6, 3.7, 5.1, HY)
    else:
        window(b, B, -2.8, -0.8, 3.7, 5.1, HY)
        window(b, B, 0.6, 2.6, 3.7, 5.1, HY)
    # sides + back
    for sx in (-1, 1):
        side_window(b, B, -1.0, 0.4, 3.8, 5.0, sx * HX, side=sx)
    window(b, B, -2.6, -1.0, 1.0, 2.2, -HY, side=-1)
    window(b, B, 0.8, 2.6, 3.8, 5.0, -HY, side=-1)
    b.box_mm(B, (1.2, -HY - 0.1, 0.35), (2.2, -HY, 2.45), door_col)
    # downpipe
    b.box_mm(B, (HX - 0.2, HY, 0.0), (HX - 0.06, HY + 0.14, WALL_H), "slate")
    # roof + chimney (Roof node, so it can be hidden/swapped)
    zr = gable_roof(b, R, roof)
    b.box_mm(R, (chimney_x - 0.4, -0.6, WALL_H), (chimney_x + 0.4, 0.2, zr + 0.9), "brick")
    b.box_mm(R, (chimney_x - 0.48, -0.68, zr + 0.8), (chimney_x + 0.48, 0.28, zr + 0.95), "plaster")
    for dx in (-0.18, 0.18):
        b.cyl(R, 0.11, 0.35, (chimney_x + dx, -0.2, zr + 1.12), "terracotta", segs=6)
    # gutter along front + back eave
    for sy in (1, -1):
        p = roof_slope_point(0, 0, 0)
        b.box_mm(B, (-HX - OV_S, sy * (p.y) - 0.08, p.z - 0.22), (HX + OV_S, sy * (p.y) + 0.08, p.z - 0.08), "slate")
    return b.finish()


@gen
def roof_damage(seed=3):
    """Overlay in HOUSE local space: tarp on the right half of the front slope + a fallen limb."""
    b = Builder(seed)
    rng = random.Random(seed)
    # tarp: bumpy grid on slope, x 0.3..3.2, t 0.12..0.72
    nx, nt = 5, 4
    x0, x1, t0, t1 = 0.3, 3.3, 0.12, 0.74
    verts, faces = [], []
    for j in range(nt + 1):
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            t = t0 + (t1 - t0) * j / nt
            edge = i in (0, nx) or j in (0, nt)
            off = 0.04 if edge else 0.04 + rng.uniform(0.03, 0.12)
            verts.append(tuple(roof_slope_point(x, t, off)))
    for j in range(nt):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append([a, a + 1, a + nx + 2, a + nx + 1])
    fs = b.poly("Tarp", verts, faces, "tarp_blue")
    bm = b.bm("Tarp")
    res = bmesh.ops.solidify(bm, geom=fs, thickness=0.03)
    # weights (sandbags) holding the tarp
    for (x, t) in ((0.6, 0.25), (3.0, 0.3), (1.8, 0.66)):
        p = roof_slope_point(x, t, 0.2)
        b.box("Tarp", (0.45, 0.3, 0.2), p, "gravel", rot=(-ROOF_PITCH, 0, rng.uniform(-20, 20)))
    # ropes to the eave
    for x in (0.4, 3.2):
        a = roof_slope_point(x, t0, 0.05)
        e = roof_slope_point(x, 0.0, 0.0) + Vector((0, 0.05, -0.15))
        mid = (a + e) / 2
        L = (a - e).length
        ang = math.degrees(math.atan2(a.z - e.z, a.y - e.y))
        b.box("Tarp", (0.04, L, 0.04), mid, "cream", rot=(ang, 0, 0))
    # fallen limb across left part of slope
    a = roof_slope_point(-3.4, 0.08, 0.22)
    c = roof_slope_point(-0.2, 0.82, 0.22)
    d = c - a
    L = d.length
    mid = (a + c) / 2
    rot_q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    M = Matrix.Translation(mid) @ rot_q.to_matrix().to_4x4()
    bm = b.bm("Limb")
    before = set(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, segments=7, radius1=0.22, radius2=0.12, depth=L, matrix=M)
    b._tag(bm, before, "bark")
    # broken end + side branches with leaf clumps
    b.cyl("Limb", 0.2, 0.04, a - d.normalized() * (0.0), "light_wood", segs=7, rot=tuple(math.degrees(v) for v in rot_q.to_euler()))
    for f, side in ((0.55, 1), (0.8, -1)):
        p = a + d * f
        tip = p + Vector((side * 1.1, -0.3, 0.6))
        dd = tip - p
        q = Vector((0, 0, 1)).rotation_difference(dd.normalized())
        bm = b.bm("Limb")
        before = set(bm.faces)
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=0.08, radius2=0.04, depth=dd.length,
                              matrix=Matrix.Translation((p + tip) / 2) @ q.to_matrix().to_4x4())
        b._tag(bm, before, "bark")
        b.sphere("Limb", 0.6, tip, "leaf", subdiv=2, scale=(1.2, 1.0, 0.75), jitter=0.08)
    b.sphere("Limb", 0.75, c + Vector((0.3, 0, 0.2)), "leaf_light", subdiv=2, scale=(1.3, 1.1, 0.7), jitter=0.1)
    return b.finish()


@gen
def roof_patch(seed=4):
    """Repaired state overlay in HOUSE local space: new tiles where the tarp was."""
    b = Builder(seed)
    N = "Patch"
    x0, x1, t0, t1 = 0.3, 3.3, 0.12, 0.74
    rows = 6
    for r in range(rows):
        ta = t0 + (t1 - t0) * r / rows
        tb = t0 + (t1 - t0) * (r + 1) / rows
        p0 = roof_slope_point((x0 + x1) / 2, ta, 0.03)
        p1 = roof_slope_point((x0 + x1) / 2, tb, 0.03)
        L = (p1 - p0).length
        b.box(N, (x1 - x0 - (0.1 if r % 2 else 0), L + 0.05, 0.06), (p0 + p1) / 2 + Vector((0, 0, 0.0)),
              "asphalt_light" if r % 2 else "slate", rot=(-ROOF_PITCH - 4, 0, 0))
    # fresh timber flashing strips at the sides
    for x in (x0 - 0.06, x1 + 0.06):
        p0 = roof_slope_point(x, t0, 0.04)
        p1 = roof_slope_point(x, t1, 0.04)
        b.box(N, (0.1, (p1 - p0).length, 0.07), (p0 + p1) / 2, "light_wood", rot=(-ROOF_PITCH, 0, 0))
    return b.finish()


# =============================================================== nature
def _branch(b, node, p0, p1, r0, r1, pal="bark", segs=6):
    d = Vector(p1) - Vector(p0)
    q = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bm = b.bm(node)
    before = set(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=d.length,
                          matrix=Matrix.Translation((Vector(p0) + Vector(p1)) / 2) @ q.to_matrix().to_4x4())
    b._tag(bm, before, pal)


@gen
def tree_oak(seed=1, height=8.0, spread=3.4, trunk_h=3.2, blobs=7, trunk_r=0.42):
    b = Builder(seed)
    rng = random.Random(seed)
    N = "Tree"
    b.cyl(N, trunk_r * 1.45, 0.5, (0, 0, 0.25), "bark", segs=7, r2=trunk_r)
    b.cyl(N, trunk_r, trunk_h, (0, 0, 0.5 + trunk_h / 2), "bark", segs=7, r2=trunk_r * 0.7)
    top = 0.5 + trunk_h
    crown_c = Vector((0, 0, top + (height - top) * 0.45))
    for k in range(3):
        a = k * 2.1 + rng.uniform(-0.3, 0.3)
        tip = Vector((math.cos(a) * spread * 0.55, math.sin(a) * spread * 0.55, top + 1.6))
        _branch(b, N, (0, 0, top - 0.3), tip, trunk_r * 0.55, 0.1, segs=5)
    r_main = (height - top) * 0.42
    b.sphere(N, r_main, crown_c + Vector((0, 0, 0.3)), "leaf", subdiv=2, scale=(1.15, 1.15, 0.95), jitter=0.15)
    for k in range(blobs - 1):
        a = k / (blobs - 1) * math.tau + rng.uniform(-0.3, 0.3)
        rr = spread * rng.uniform(0.5, 0.7)
        p = Vector((math.cos(a) * rr, math.sin(a) * rr, crown_c.z + rng.uniform(-0.9, 0.9)))
        r = r_main * rng.uniform(0.55, 0.75)
        b.sphere(N, r, p, "leaf_light" if p.z > crown_c.z + 0.2 else "leaf", subdiv=2,
                 scale=(1, 1, 0.85), jitter=0.12)
    return b.finish()


@gen
def tree_street(seed=5, height=6.2):
    b = Builder(seed)
    rng = random.Random(seed)
    N = "Tree"
    b.box_mm(N, (-0.6, -0.6, 0), (0.6, 0.6, 0.03), "asphalt_light")  # tree pit grate
    b.cyl(N, 0.17, 2.8, (0, 0, 1.4), "bark", segs=6, r2=0.12)
    for k in range(3):
        a = k * 2.2
        _branch(b, N, (0, 0, 2.6), (math.cos(a) * 0.8, math.sin(a) * 0.8, 3.6), 0.08, 0.04, segs=4)
    b.sphere(N, 1.35, (0, 0, 3.9), "leaf_light", subdiv=2, scale=(1, 1, 1.1), jitter=0.1)
    b.sphere(N, 1.05, (0.25, -0.15, 5.0), "leaf_light", subdiv=2, jitter=0.1)
    b.sphere(N, 0.95, (-0.35, 0.3, 4.6), "leaf", subdiv=2, jitter=0.1)
    # small stake + tie (young street tree)
    b.box_mm(N, (0.24, -0.04, 0), (0.32, 0.04, 1.6), "light_wood")
    b.box_mm(N, (-0.1, -0.03, 1.4), (0.3, 0.03, 1.46), "slate")
    return b.finish()


@gen
def bush(seed=6):
    b = Builder(seed)
    rng = random.Random(seed)
    N = "Bush"
    b.sphere(N, 0.62, (0, 0, 0.5), "grass_dark", subdiv=2, scale=(1.2, 1.0, 0.85), jitter=0.06, flat_bottom=0.0)
    b.sphere(N, 0.5, (0.6, 0.15, 0.4), "leaf", subdiv=2, jitter=0.05, flat_bottom=0.0)
    b.sphere(N, 0.45, (-0.6, -0.1, 0.36), "leaf", subdiv=2, jitter=0.05, flat_bottom=0.0)
    for k in range(5):
        a = rng.uniform(0, math.tau)
        b.sphere(N, 0.08, (math.cos(a) * 0.6, math.sin(a) * 0.45, rng.uniform(0.55, 0.85)),
                 "flower_pink" if k % 2 else "flower_yellow", subdiv=1)
    return b.finish()


# =============================================================== props
@gen
def traffic_cone():
    b = Builder()
    N = "Cone"
    b.box_mm(N, (-0.21, -0.21, 0), (0.21, 0.21, 0.05), "tyre")
    H = 0.7
    r = lambda z: 0.18 + (0.035 - 0.18) * (z - 0.05) / (H - 0.05)
    for z0, z1, pal in ((0.05, 0.33, "cone_orange"), (0.33, 0.47, "line_white"), (0.47, H, "cone_orange")):
        b.cyl(N, r(z0), z1 - z0, (0, 0, (z0 + z1) / 2), pal, segs=10, r2=r(z1))
    return b.finish()


@gen
def chainsaw():
    b = Builder()
    N = "Chainsaw"
    # body (amber), engine side cover, handles (tyre black), guide bar (steel) pointing +Y
    b.box_mm(N, (-0.11, -0.2, 0.02), (0.11, 0.14, 0.24), "amber")
    b.box_mm(N, (0.11, -0.12, 0.06), (0.14, 0.1, 0.2), "tyre")  # side cover / sprocket
    b.box_mm(N, (-0.12, -0.17, 0.0), (0.12, 0.12, 0.03), "tyre")  # base
    b.box_mm(N, (-0.06, -0.28, 0.06), (0.06, -0.2, 0.2), "tyre")  # rear handle
    b.box_mm(N, (-0.05, -0.2, 0.24), (0.05, 0.08, 0.3), "tyre")  # top handle
    b.box_mm(N, (-0.05, 0.05, 0.12), (0.05, 0.1, 0.3), "tyre")
    b.box_mm(N, (-0.03, 0.14, 0.2), (0.03, 0.17, 0.34), "warning_red")  # chain brake
    b.box_mm(N, (-0.015, 0.14, 0.07), (0.015, 0.5, 0.17), "steel")  # bar
    b.cyl(N, 0.05, 0.03, (0, 0.5, 0.12), "steel", segs=8, rot=(0, 90, 0))
    b.box_mm(N, (-0.02, 0.14, 0.055), (0.02, 0.5, 0.07), "tyre")  # chain
    b.box_mm(N, (-0.02, 0.14, 0.17), (0.02, 0.5, 0.185), "tyre")
    b.cyl(N, 0.05, 0.05, (0.0, -0.05, 0.25), "cream", segs=6)  # fuel cap
    return b.finish()


def _log(b, node, length, r, centre, segs=12, axis="X", rings=True, rot_extra=0):
    rot = (0, 90, rot_extra) if axis == "X" else (90, 0, rot_extra)
    fs = b.cyl(node, r, length, centre, "bark", segs=segs, rot=rot, cap_pal="light_wood")
    bm = b.bm(node)
    lay = bm.faces.layers.int["pal"]
    caps = [f for f in fs if len(f.verts) == segs]
    if rings:
        res = bmesh.ops.inset_individual(bm, faces=caps, thickness=r * 0.35, depth=0.0)
        for f in res["faces"]:
            f[lay] = P["light_wood"]
        for f in caps:
            f[lay] = P["sand"]
        res2 = bmesh.ops.inset_individual(bm, faces=caps, thickness=r * 0.3, depth=0.0)
        for f in res2["faces"]:
            f[lay] = P["sand"]
        for f in caps:
            f[lay] = P["light_wood"]


@gen
def log_section():
    b = Builder()
    _log(b, "Log", 1.0, 0.36, (0, 0, 0.36), segs=12)
    return b.finish()


@gen
def log_pile(seed=7):
    b = Builder(seed)
    rng = random.Random(seed)
    r = 0.3
    for i, y in enumerate((-0.62, 0.0, 0.62)):
        _log(b, "Logs", 1.6 + rng.uniform(-0.1, 0.1), r, (rng.uniform(-0.08, 0.08), y, r), segs=9)
    _log(b, "Logs", 1.5, r, (0.05, -0.31, r + 0.52), segs=9)
    return b.finish()


@gen
def root_plate(seed=8):
    """upturned root plate: soil disc facing +Y, trunk stub lying back along -Y"""
    b = Builder(seed)
    rng = random.Random(seed)
    N = "RootPlate"
    fs = b.cyl(N, 1.15, 0.55, (0, 0, 1.0), "soil", segs=10, rot=(90, 0, 0), cap_pal="soil")
    for v in {v for f in fs for v in f.verts}:
        v.co += Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.06, 0.06), rng.uniform(-0.1, 0.1)))
    b.cyl(N, 0.42, 1.6, (0, -1.0, 0.75), "bark", segs=7, rot=(90 - 10, 0, 0), r2=0.46)
    b.cyl(N, 0.42, 0.04, (0, -1.79, 0.61), "light_wood", segs=7, rot=(90 - 10, 0, 0))
    for k in range(6):
        a = k / 6 * math.tau + rng.uniform(-0.3, 0.3)
        p0 = Vector((math.cos(a) * 0.5, 0.2, 1.0 + math.sin(a) * 0.5))
        p1 = Vector((math.cos(a) * 1.25, 0.4 + rng.uniform(0, 0.15), 1.0 + math.sin(a) * 1.1))
        p1.z = max(p1.z, 0.1)
        _branch(b, N, p0, p1, 0.17, 0.06, segs=5)
    for k in range(5):
        a = rng.uniform(0.25, math.pi - 0.25)
        b.sphere(N, 0.22, (math.cos(a) * 1.1, rng.uniform(-0.2, 0.2), 1.0 + math.sin(a) * 1.05), "grass_dark", subdiv=1, scale=(1, 1, 0.7))
    return b.finish()


@gen
def canopy_cluster(seed=9):
    b = Builder(seed)
    rng = random.Random(seed)
    N = "Canopy"
    # fallen crown lying along X (~4 m), broken end at -X
    _branch(b, N, (-2.0, 0, 0.3), (1.6, 0.2, 0.55), 0.26, 0.12, segs=7)
    b.cyl(N, 0.25, 0.04, (-2.0, 0, 0.3), "light_wood", segs=7, rot=(0, 90, 0))
    for (x, y, z, r) in ((-0.6, 0.6, 1.0, 0.9), (0.4, -0.6, 0.9, 0.95), (1.4, 0.3, 1.1, 1.0), (0.0, 0.1, 1.5, 1.0), (1.9, -0.4, 0.7, 0.75), (-1.2, -0.3, 0.7, 0.7)):
        _branch(b, N, (x * 0.8, 0.0, 0.45), (x, y, z), 0.08, 0.04, segs=4)
        b.sphere(N, r, (x, y, z), rng.choice(("leaf", "leaf", "leaf_light")), subdiv=2, scale=(1.1, 1.0, 0.8), jitter=0.1, flat_bottom=0.0)
    return b.finish()


# =============================================================== vehicles
@gen
def rescue_truck():
    b = Builder()
    B = "Body"
    WR, WW = 0.48, 0.34
    # wheels (tyre + steel hub)
    for y in (1.85, -1.65):
        for sx in (-1, 1):
            x = sx * (1.2 - WW / 2)
            b.cyl(B, WR, WW, (x, y, WR), "tyre", segs=14, rot=(0, 90, 0))
            b.cyl(B, 0.26, 0.04, (x + sx * WW / 2, y, WR), "steel", segs=8, rot=(0, 90, 0))
    # chassis + side skirts
    b.box_mm(B, (-0.85, -3.0, 0.35), (0.85, 3.0, 1.0), "tyre")
    for y0, y1 in ((-1.05, 1.25), (-3.1, -2.25)):
        b.box_mm(B, (-1.2, y0, 0.55), (1.2, y1, 1.05), "signal_red")
    # rear body (locker body)
    b.box_mm(B, (-1.2, -3.1, 1.0), (1.2, 1.3, 2.55), "signal_red", face_pal={"+z": "line_white"})
    # cab
    b.box_mm(B, (-1.2, 1.3, 1.0), (1.2, 3.1, 2.6), "signal_red", face_pal={"+z": "line_white"})
    b.box_mm(B, (-1.2, 2.45, 0.5), (1.2, 3.1, 1.05), "signal_red")
    b.box_mm(B, (-1.0, 3.08, 1.6), (1.0, 3.13, 2.45), "glass")  # windscreen
    b.box_mm(B, (-0.06, 3.1, 1.6), (0.06, 3.15, 2.45), "signal_red")
    for sx in (-1, 1):
        b.box_mm(B, (sx * 1.2 - 0.03, 1.5, 1.6), (sx * 1.2 + 0.03, 2.9, 2.4), "glass")  # side windows
        b.box_mm(B, (sx * 1.2 - 0.04, 1.42, 1.08), (sx * 1.2 + 0.04, 1.48, 2.5), "red_dark")  # door seam
        # mirrors
        b.box_mm(B, (sx * 1.2, 2.85, 2.0), (sx * 1.3, 2.95, 2.06), "navy")
        b.box_mm(B, (sx * 1.26, 2.8, 1.75), (sx * 1.34, 2.96, 2.15), "navy")
        # headlights + indicators
        b.box_mm(B, (sx * 0.95 - 0.18, 3.1, 0.75), (sx * 0.95 + 0.18, 3.14, 0.95), "line_white")
        b.box_mm(B, (sx * 0.62 - 0.08, 3.1, 0.75), (sx * 0.62 + 0.08, 3.14, 0.9), "amber")
        # tail lights
        b.box_mm(B, (sx * 1.0 - 0.12, -3.14, 1.15), (sx * 1.0 + 0.12, -3.1, 1.45), "warning_red")
        # lockers (roller shutters) per side
        xs = sx * 1.2
        for y0, y1 in ((-2.95, -1.75), (-1.65, -0.45), (-0.35, 1.15)):
            b.box_mm(B, (min(xs, xs + sx * 0.04), y0, 1.36), (max(xs, xs + sx * 0.04), y1, 2.3), "red_dark")
            b.box_mm(B, (min(xs, xs + sx * 0.06), y0 + 0.4, 1.45), (max(xs, xs + sx * 0.06), y1 - 0.4, 1.52), "steel")
        # white top band
        b.box_mm(B, (min(xs, xs + sx * 0.03), -3.1, 2.36), (max(xs, xs + sx * 0.03), 3.1, 2.52), "line_white")
        # amber band (battenburg-style blocks alternate amber / white)
        n = 10
        for i in range(n):
            y0 = -3.1 + i * 6.2 / n
            b.box_mm(B, (min(xs, xs + sx * 0.03), y0, 1.04), (max(xs, xs + sx * 0.03), y0 + 6.2 / n, 1.3),
                     "amber" if i % 2 == 0 else "line_white")
    # front grille + bumper + amber stripe front/back
    b.box_mm(B, (-0.7, 3.1, 1.08), (0.7, 3.14, 1.45), "navy")
    b.box_mm(B, (-1.22, 3.1, 0.45), (1.22, 3.28, 0.7), "steel")
    b.box_mm(B, (-1.2, 3.1, 1.48), (1.2, 3.13, 1.58), "amber")
    b.box_mm(B, (-1.2, -3.13, 1.02), (1.2, -3.1, 1.12), "amber")
    b.box_mm(B, (-1.22, -3.25, 0.5), (1.22, -3.1, 0.7), "steel")
    # rear shutter
    b.box_mm(B, (-0.95, -3.14, 1.25), (0.95, -3.1, 2.35), "steel")
    # roof ladder
    for sx in (-1, 1):
        b.box_mm(B, (sx * 0.42 - 0.04, -3.0, 2.68), (sx * 0.42 + 0.04, 1.2, 2.74), "steel")
        for y in (-2.6, 0.8):
            b.box_mm(B, (sx * 0.42 - 0.04, y - 0.05, 2.55), (sx * 0.42 + 0.04, y + 0.05, 2.68), "slate")
    for k in range(9):
        y = -2.85 + k * 0.5
        b.box_mm(B, (-0.42, y - 0.025, 2.69), (0.42, y + 0.025, 2.73), "steel")
    # light bar base + emissive lights (separate nodes)
    b.box_mm(B, (-0.85, 2.45, 2.6), (0.85, 2.85, 2.68), "navy")
    b.box_mm("LightL", (-0.82, 2.48, 2.68), (-0.06, 2.82, 2.82), "emissive_blue")
    b.box_mm("LightR", (0.06, 2.48, 2.68), (0.82, 2.82, 2.82), "emissive_blue")
    b.box_mm(B, (-0.06, 2.5, 2.68), (0.06, 2.8, 2.78), "navy")
    return b.finish()


# =============================================================== Batch C street props
@gen
def lamp_post():
    b = Builder()
    N = "Body"
    b.cyl(N, 0.2, 0.5, (0, 0, 0.25), "navy", segs=8, r2=0.14)
    b.cyl(N, 0.085, 4.2, (0, 0, 2.6), "navy", segs=8, r2=0.07)
    b.cyl(N, 0.11, 0.12, (0, 0, 1.2), "amber", segs=8)  # decorative collar
    b.cyl(N, 0.09, 0.2, (0, 0, 4.75), "navy", segs=8)
    # lantern: base plate, glass (emissive node), cap
    b.cyl(N, 0.22, 0.08, (0, 0, 4.9), "navy", segs=4, rot=(0, 0, 45))
    b.cyl("Light", 0.2, 0.5, (0, 0, 5.19), "emissive_amber", segs=4, r2=0.26, rot=(0, 0, 45))
    b.cyl(N, 0.34, 0.24, (0, 0, 5.56), "navy", segs=4, r2=0.06, rot=(0, 0, 45))
    b.cyl(N, 0.04, 0.12, (0, 0, 5.72), "navy", segs=6)
    return b.finish()


@gen
def bench():
    b = Builder()
    N = "Body"
    L = 1.8
    for x in (-0.75, 0.75):  # cast frames
        b.box_mm(N, (x - 0.05, -0.25, 0.0), (x + 0.05, -0.17, 0.45), "navy")
        b.box_mm(N, (x - 0.05, 0.17, 0.0), (x + 0.05, 0.25, 0.45), "navy")
        b.box_mm(N, (x - 0.05, -0.27, 0.4), (x + 0.05, 0.27, 0.47), "navy")
        b.box(N, (0.1, 0.07, 0.55), (x, -0.27, 0.72), "navy", rot=(-12, 0, 0))
        b.box_mm(N, (x - 0.05, -0.05, 0.6), (x + 0.05, 0.3, 0.66), "navy")  # armrest
    for k, y in enumerate((-0.17, -0.02, 0.13)):
        b.box_mm(N, (-L / 2, y - 0.065, 0.47), (L / 2, y + 0.065, 0.52), "light_wood")
    for z in (0.62, 0.8):
        b.box(N, (L, 0.04, 0.12), (0, -0.3 + (z - 0.62) * -0.2, z), "light_wood", rot=(-12, 0, 0))
    return b.finish()


@gen
def litter_bin():
    b = Builder()
    N = "Body"
    b.cyl(N, 0.26, 0.85, (0, 0, 0.43), "door_green", segs=10, r2=0.28)
    b.cyl(N, 0.3, 0.06, (0, 0, 0.88), "door_green", segs=10)
    b.cyl(N, 0.22, 0.14, (0, 0, 0.97), "door_green", segs=10, r2=0.12)
    b.cyl(N, 0.285, 0.07, (0, 0, 0.6), "amber", segs=10)  # band
    b.box_mm(N, (-0.12, 0.2, 0.84), (0.12, 0.32, 0.9), "tyre")  # slot at front
    return b.finish()


@gen
def flower_tub(seed=31):
    b = Builder(seed)
    rng = random.Random(seed)
    N = "Body"
    b.cyl(N, 0.45, 0.5, (0, 0, 0.25), "dark_wood", segs=10, r2=0.5)
    for z in (0.12, 0.38):
        b.cyl(N, 0.47 + (z - 0.12) * 0.15, 0.05, (0, 0, z), "slate", segs=10)
    b.cyl(N, 0.46, 0.04, (0, 0, 0.5), "soil", segs=10)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        b.sphere(N, 0.2, (math.cos(a) * 0.22, math.sin(a) * 0.22, 0.6), "leaf", subdiv=1, jitter=0.03)
    for k in range(7):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.05, 0.33)
        b.sphere(N, 0.08, (math.cos(a) * r, math.sin(a) * r, 0.72 + rng.uniform(0, 0.08)),
                 ("flower_pink", "flower_yellow", "line_white")[k % 3], subdiv=1)
    return b.finish()


@gen
def fence_section():
    b = Builder()
    N = "Body"
    L = 2.0
    for x in (-0.95, 0.95):
        b.box_mm(N, (x - 0.05, -0.05, 0), (x + 0.05, 0.05, 1.05), "plaster")
        b.cyl(N, 0.07, 0.06, (x, 0, 1.08), "plaster", segs=4, r2=0.01, rot=(0, 0, 45))
    for z in (0.25, 0.75):
        b.box_mm(N, (-L / 2, -0.06, z - 0.04), (L / 2, -0.02, z + 0.04), "plaster")
    n = 9
    for i in range(n):
        x = -0.8 + i * 1.6 / (n - 1)
        b.box_mm(N, (x - 0.045, 0.0, 0.05), (x + 0.045, 0.03, 0.88), "plaster")
        b.poly(N, [(x - 0.045, 0.0, 0.88), (x + 0.045, 0.0, 0.88), (x, 0.0, 0.96), (x - 0.045, 0.03, 0.88), (x + 0.045, 0.03, 0.88), (x, 0.03, 0.96)],
               [[0, 1, 2], [3, 5, 4], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]], "plaster")
    return b.finish()


@gen
def utility_pole():
    b = Builder()
    N = "Body"
    b.cyl(N, 0.15, 8.0, (0, 0, 4.0), "dark_wood", segs=7, r2=0.11)
    b.box_mm(N, (-1.0, -0.06, 7.3), (1.0, 0.06, 7.45), "dark_wood")
    b.box(N, (0.06, 0.06, 1.2), (-0.5, 0, 7.0), "dark_wood", rot=(0, -40, 0))
    b.box(N, (0.06, 0.06, 1.2), (0.5, 0, 7.0), "dark_wood", rot=(0, 40, 0))
    for x in (-0.85, -0.3, 0.3, 0.85):
        b.cyl(N, 0.05, 0.18, (x, 0, 7.54), "steel", segs=6, r2=0.03)
    b.cyl(N, 0.22, 0.6, (0, -0.32, 6.0), "concrete", segs=8)  # transformer can
    b.box_mm(N, (-0.04, -0.2, 5.9), (0.04, -0.1, 6.1), "slate")
    b.box_mm(N, (-0.12, 0.13, 2.0), (0.12, 0.15, 2.25), "line_yellow")  # warning plate
    for z in range(3, 7):
        b.box_mm(N, (-0.02, -0.18, z * 0.8), (0.02, 0.18, z * 0.8 + 0.03), "steel")  # climbing steps
    return b.finish()


@gen
def mailbox():
    b = Builder()
    N = "Body"
    b.cyl(N, 0.28, 0.12, (0, 0, 0.06), "tyre", segs=12)
    b.cyl(N, 0.25, 1.2, (0, 0, 0.72), "red_dark", segs=12)
    b.cyl(N, 0.29, 0.08, (0, 0, 1.33), "red_dark", segs=12)
    b.sphere(N, 0.27, (0, 0, 1.37), "red_dark", subdiv=2, scale=(1, 1, 0.55), flat_bottom=1.37)
    b.box_mm(N, (-0.16, 0.22, 1.08), (0.16, 0.27, 1.14), "tyre")  # slot (front)
    b.box_mm(N, (-0.1, 0.235, 0.78), (0.1, 0.26, 0.92), "cream")  # collection plate
    return b.finish()


@gen
def road_barrier():
    b = Builder()
    N = "Body"
    L = 2.0
    for x in (-0.85, 0.85):
        b.box_mm(N, (x - 0.04, -0.04, 0.0), (x + 0.04, 0.04, 1.0), "line_white")
        b.box_mm(N, (x - 0.12, -0.32, 0.0), (x + 0.12, 0.32, 0.08), "tyre")  # feet
    n = 8
    for i in range(n):
        x0 = -L / 2 + i * L / n
        b.box_mm(N, (x0, 0.04, 0.72), (x0 + L / n, 0.08, 0.92), "warning_red" if i % 2 == 0 else "line_white")
        b.box_mm(N, (x0, 0.04, 0.32), (x0 + L / n, 0.08, 0.44), "line_white" if i % 2 == 0 else "warning_red")
    b.box_mm(N, (-0.07, -0.03, 0.92), (0.07, 0.07, 1.04), "tyre")
    b.cyl("Light", 0.07, 0.1, (0, 0.02, 1.1), "emissive_amber", segs=8)
    return b.finish()


@gen
def station_board():
    """community/job board by the station: navy frame, cream board, pinned notes, little roof"""
    b = Builder()
    N = "Body"
    for x in (-0.85, 0.85):
        b.box_mm(N, (x - 0.06, -0.06, 0), (x + 0.06, 0.06, 2.1), "navy")
    b.box_mm(N, (-0.85, -0.04, 0.85), (0.85, 0.04, 1.95), "navy")
    b.box_mm(N, (-0.78, 0.04, 0.92), (0.78, 0.07, 1.88), "cream")
    notes = [(-0.55, 1.6, "line_white"), (-0.15, 1.65, "butter"), (0.35, 1.55, "pale_blue"), (-0.45, 1.15, "peach"), (0.1, 1.2, "line_white"), (0.55, 1.15, "sage")]
    for x, z, col in notes:
        b.box_mm(N, (x - 0.15, 0.07, z - 0.18), (x + 0.15, 0.09, z + 0.18), col)
        b.box_mm(N, (x - 0.02, 0.09, z + 0.12), (x + 0.02, 0.11, z + 0.16), "signal_red")
    b.box_mm(N, (-0.78, 0.07, 1.76), (0.78, 0.1, 1.88), "signal_red")  # header strip
    b.box(N, (1.95, 0.5, 0.06), (0, 0.1, 2.12), "slate", rot=(-15, 0, 0))
    return b.finish()


@gen
def resident_car(color="denim"):
    b = Builder()
    B = "Body"
    WR = 0.32
    for y in (1.25, -1.2):
        for sx in (-1, 1):
            b.cyl(B, WR, 0.22, (sx * 0.76, y, WR), "tyre", segs=12, rot=(0, 90, 0))
            b.cyl(B, 0.17, 0.03, (sx * 0.875, y, WR), "steel", segs=8, rot=(0, 90, 0))
    b.box_mm(B, (-0.85, -1.9, 0.3), (0.85, 1.95, 0.85), color)  # lower body
    b.box_mm(B, (-0.86, -1.9, 0.3), (0.86, 1.95, 0.4), "slate")  # sill
    # cabin (tapered with poly)
    z0, z1 = 0.85, 1.45
    cab = [(-0.8, -1.75, z0), (0.8, -1.75, z0), (0.8, 0.75, z0), (-0.8, 0.75, z0),
           (-0.68, -1.55, z1), (0.68, -1.55, z1), (0.68, 0.1, z1), (-0.68, 0.1, z1)]
    b.poly(B, cab, [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]], "glass",
           face_pals=[color, color, "glass", "glass", "glass", "glass"])
    b.box_mm(B, (-0.7, -1.45, z1 - 0.01), (0.7, -0.05, z1 + 0.05), color)  # roof
    for sx in (-1, 1):
        b.box_mm(B, (sx * 0.81 - 0.03, -0.45, 0.85), (sx * 0.81 + 0.03, -0.35, 1.4), color)  # B pillar
        b.box_mm(B, (sx * 0.62 - 0.14, 1.95, 0.62), (sx * 0.62 + 0.14, 1.98, 0.75), "line_white")
        b.box_mm(B, (sx * 0.62 - 0.14, -1.93, 0.62), (sx * 0.62 + 0.14, -1.9, 0.75), "warning_red")
        b.box_mm(B, (sx * 0.85, 0.55, 0.95), (sx * 0.98, 0.65, 1.05), color)  # mirror
    b.box_mm(B, (-0.88, 1.95, 0.3), (0.88, 2.05, 0.48), "slate")
    b.box_mm(B, (-0.88, -2.0, 0.3), (0.88, -1.9, 0.48), "slate")
    b.box_mm(B, (-0.25, 1.95, 0.5), (0.25, 1.99, 0.62), "tyre")  # grille
    b.box_mm(B, (-0.2, -1.94, 0.45), (0.2, -1.9, 0.55), "line_yellow")  # plate
    return b.finish()


@gen
def radio_handset():
    b = Builder()
    N = "Body"
    b.box_mm(N, (-0.035, -0.022, 0.0), (0.035, 0.022, 0.15), "tyre")
    b.box_mm(N, (-0.026, 0.022, 0.085), (0.026, 0.026, 0.125), "glass")  # display (front)
    for i in range(3):
        b.box_mm(N, (-0.022 + i * 0.016, 0.022, 0.03), (-0.012 + i * 0.016, 0.026, 0.07), "steel")
    b.cyl(N, 0.008, 0.11, (0.02, 0.0, 0.205), "tyre", segs=6)  # antenna
    b.cyl(N, 0.011, 0.02, (-0.018, 0.0, 0.16), "amber", segs=6)  # channel knob
    b.box_mm(N, (-0.04, -0.01, 0.06), (-0.035, 0.012, 0.11), "amber")  # PTT
    return b.finish()
