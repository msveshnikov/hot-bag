"""Task 2: bicycle, e-scooter and city traffic for «Горячая сумка».
Moving parts are separate nodes with pivots on their axes (no baked motion):
  WHEEL_* spin about local X, STEER turns about local Z (Godot Y), CRANK spins about X.
blender -b --factory-startup -P build_vehicles.py -- [--no-render] [--only bicycle]
Mount points must match BIKE/SCOOT in build_characters.py.
"""
import bpy
import sys
import os
import math

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
import lib_render as R
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None


def node(name, loc, coll, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    coll.objects.link(e)
    if parent:
        e.parent = parent
    return e


def attach(objs, parent, coll):
    """Parent meshes to a pivot node keeping world placement."""
    bpy.context.view_layer.update()
    for o in objs:
        if o is None:
            continue
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
        apply_xform(o)
        world_uv(o)
        mw = o.matrix_world.copy()
        o.parent = parent
        bpy.context.view_layer.update()
        o.matrix_world = mw
        if o.type == "MESH":
            # bake parent-relative offset into mesh so the object origin sits on the pivot
            o.data.transform(o.matrix_basis)
            o.matrix_basis.identity()
            o.matrix_parent_inverse.identity()
            pw = parent.matrix_world.inverted()
            o.data.transform(pw @ mw @ o.matrix_world.inverted() if False else Matrix.Identity(4))
    return objs


def bake_children(parent):
    """Make each child mesh's transform identity relative to parent, vertices in parent space."""
    bpy.context.view_layer.update()
    pinv = parent.matrix_world.inverted()
    for o in parent.children:
        if o.type != "MESH":
            continue
        mw = o.matrix_world.copy()
        o.parent = parent
        o.matrix_parent_inverse.identity()
        o.matrix_basis.identity()
        o.data.transform(pinv @ mw)


def group(name, parent, objs, coll):
    """Join meshes into one object named <name>, expressed in parent's local space."""
    from lib_geo import join
    bpy.context.view_layer.update()
    objs = [o for o in objs if o is not None]
    for o in objs:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        coll.objects.link(o)
        apply_xform(o)
        world_uv(o)
    j = join(objs, name)
    pinv = parent.matrix_world.inverted()
    bpy.context.view_layer.update()
    j.data.transform(pinv)
    j.parent = parent
    j.matrix_parent_inverse.identity()
    j.matrix_basis.identity()
    return j


def wheel(name, r, w, loc, coll, parent, tire_m="black", rim_m="steel", spokes=True, hub_m=None, wide=1.0):
    n = node(name, loc, coll, parent)
    bpy.context.view_layer.update()
    parts = [torus(name + "_tire", r - 0.03 * wide, 0.035 * wide, loc, tire_m, n=24, nr=8, rot=(0, math.radians(90), 0))]
    if spokes:
        parts.append(torus(name + "_rim", r - 0.07, 0.012, loc, rim_m, n=24, nr=6, rot=(0, math.radians(90), 0)))
        parts.append(cyl(name + "_hub", 0.035, w, Vector(loc) + Vector((-w / 2, 0, 0)), rim_m, n=10,
                         rot=(0, math.radians(90), 0)))
        for k in range(8):
            a = k * math.pi / 4
            p0 = Vector(loc)
            p1 = Vector(loc) + Vector((0, math.cos(a) * (r - 0.07), math.sin(a) * (r - 0.07)))
            parts.append(tube_path(name + "_sp%d" % k, [p0, p1], 0.005, rim_m, n=4))
    else:
        parts.append(cyl(name + "_disc", r - 0.05, w * 0.8, Vector(loc) + Vector((-w * 0.4, 0, 0)), hub_m or rim_m, n=16,
                         rot=(0, math.radians(90), 0)))
    group(name + "_mesh", n, parts, coll)
    return n


# ------------------------------------------------------------------ bicycle
def bicycle(name="bicycle"):
    coll = collection(name)
    root = node(name, (0, 0, 0), coll)
    frame_m = mat("bike_frame", "#7d8c4a", rough=0.5)
    cream = mat("bike_cream", "#efe2c4", rough=0.5)
    brown = mat("bike_leather", "#7a4b2e")
    R_W = 0.3
    yf, yr = -0.52, 0.52
    crank = Vector((0, 0.15, 0.34))
    seat_top = Vector((0, 0.30, 0.74))
    head_bot = Vector((0, -0.40, 0.66))
    head_top = Vector((0, -0.37, 0.86))
    frame = [tube_path("st", [crank, seat_top + Vector((0, 0, -0.04))], 0.025, frame_m),
             tube_path("dt", [crank, Vector((0, -0.1, 0.45)), head_bot], 0.028, frame_m),
             tube_path("tt", [Vector((0, 0.22, 0.6)), Vector((0, -0.1, 0.62)), head_top + Vector((0, 0, -0.05))], 0.022,
                       frame_m),
             tube_path("cs", [crank, Vector((0, yr, R_W))], 0.016, frame_m),
             tube_path("ss", [seat_top + Vector((0, 0, -0.06)), Vector((0, yr, R_W))], 0.016, frame_m),
             tube_path("ht", [head_bot, head_top], 0.032, frame_m),
             # saddle
             sphere("saddle", 0.1, seat_top + Vector((0, 0.02, 0.02)), brown, scale=(1.0, 1.6, 0.4)),
             cyl("post", 0.014, 0.08, seat_top + Vector((0, 0, -0.06)), "steel", n=6),
             # rear mudguard + rack
             tube_path("rguard", [Vector((0, yr + math.sin(a) * (R_W + 0.05), R_W + math.cos(a) * (R_W + 0.05)))
                                  for a in [math.radians(x) for x in range(-40, 120, 10)]], 0.03, cream),
             box("rack", (0.22, 0.32, 0.02), (0, yr - 0.02, 0.66), "metal", bevel=0.005),
             tube_path("rackl", [Vector((0.1, yr + 0.12, 0.66)), Vector((0.1, yr, R_W))], 0.008, "metal"),
             tube_path("rackr", [Vector((-0.1, yr + 0.12, 0.66)), Vector((-0.1, yr, R_W))], 0.008, "metal"),
             box("chainguard", (0.02, 0.45, 0.1), (0.06, 0.34, 0.28), cream, bevel=0.02),
             cyl("taillight", 0.03, 0.03, (0, yr + 0.38, 0.6), mat("EMIT_brake", "#c8302a", emit="#ff3b2f",
                                                                    emit_strength=1.0), n=8,
                 rot=(math.radians(90), 0, 0))]
    group(name + "_frame", root, frame, coll)
    # crank + pedals
    cr = node("CRANK", crank, coll, root)
    parts = [cyl("chainring", 0.09, 0.02, crank + Vector((0.05, 0, 0)), "metal", n=16, rot=(0, math.radians(90), 0))]
    for sx, a in ((1, 0), (-1, math.pi)):
        p = crank + Vector((sx * 0.07, -math.sin(a) * 0.13, math.cos(a) * 0.13))
        parts.append(tube_path("arm%d" % sx, [crank + Vector((sx * 0.07, 0, 0)), p], 0.012, "metal", n=6))
        parts.append(box("pedal%d" % sx, (0.09, 0.07, 0.02), p + Vector((sx * 0.05, 0, -0.01)), "black"))
    group("CRANK_mesh", cr, parts, coll)
    # rear wheel
    wheel("WHEEL_rear", R_W, 0.05, (0, yr, R_W), coll, root, tire_m=mat("tire_old", "#3a3430"), rim_m="steel")
    # steering assembly (pivot on the head tube), front wheel inside it
    st = node("STEER", (0, -0.39, 0.75), coll, root)
    sparts = [tube_path("forkl", [head_bot, Vector((0.05, yf, R_W))], 0.016, frame_m),
              tube_path("forkr", [head_bot, Vector((-0.05, yf, R_W))], 0.016, frame_m),
              tube_path("stem", [head_top, Vector((0, -0.33, 0.95))], 0.02, "steel"),
              tube_path("bars", [Vector((0.26, -0.20, 1.0)), Vector((0.2, -0.28, 0.97)), Vector((0, -0.33, 0.95)),
                                 Vector((-0.2, -0.28, 0.97)), Vector((-0.26, -0.20, 1.0))], 0.016, "steel"),
              cyl("gripL", 0.024, 0.1, Vector((0.22, -0.22, 0.99)), brown, n=8, rot=(0, math.radians(90), 0)),
              cyl("gripR", 0.024, 0.1, Vector((-0.32, -0.22, 0.99)), brown, n=8, rot=(0, math.radians(90), 0)),
              sphere("bell", 0.035, Vector((0.14, -0.27, 1.02)), mat("brass", "#d8a93a", metal=0.6, rough=0.3)),
              tube_path("fguard", [Vector((0, yf + math.sin(a) * (R_W + 0.05), R_W + math.cos(a) * (R_W + 0.05)))
                                   for a in [math.radians(x) for x in range(-110, 40, 10)]], 0.03, cream),
              # wicker basket
              box("basket", (0.36, 0.28, 0.24), (0, -0.62, 0.78), mat("wicker", "#c99a55"), bevel=0.03),
              box("basketin", (0.3, 0.22, 0.02), (0, -0.62, 0.99), mat("wicker_dark", "#8a6436")),
              cyl("headlamp", 0.04, 0.06, Vector((0, -0.79, 0.85)), "EMIT_lamp", n=10, rot=(math.radians(90), 0, 0))]
    group("STEER_mesh", st, sparts, coll)
    wheel("WHEEL_front", R_W, 0.05, (0, yf, R_W), coll, st, tire_m=mat("tire_old", "#3a3430"), rim_m="steel")
    lh = point_light("LIGHT_head", (0, -0.85, 0.85), 40, color="#fff2cc", coll=coll)
    lh.parent = st
    lh.matrix_parent_inverse = st.matrix_world.inverted()
    m = node("MARK_seat", (0, 0.30, 0.0), coll, root)
    colb = colbox(name, (0.4, 1.7, 1.0), (0, 0, 0.1), coll)
    colb.parent = root
    return root


# ------------------------------------------------------------------ scooter
def scooter(name="scooter"):
    coll = collection(name)
    root = node(name, (0, 0, 0), coll)
    body_m = mat("scooter_body", "turq", rough=0.45)
    deck_m = mat("scooter_deck", "#2f3236", rough=0.8)
    RW = 0.11
    yf, yr = -0.47, 0.47
    parts = [box("deck", (0.17, 0.78, 0.06), (0, 0.04, 0.09), deck_m, bevel=0.025),
             box("deckside", (0.18, 0.8, 0.03), (0, 0.04, 0.075), body_m, bevel=0.012),
             tube_path("neckbase", [Vector((0, -0.35, 0.12)), Vector((0, yf + 0.03, 0.22))], 0.03, body_m),
             tube_path("rearfork", [Vector((0, 0.42, 0.12)), Vector((0, yr, RW))], 0.022, body_m),
             tube_path("rguard", [Vector((0, yr + math.sin(a) * (RW + 0.04), RW + math.cos(a) * (RW + 0.04)))
                                  for a in [math.radians(x) for x in range(-30, 110, 10)]], 0.03, body_m),
             cyl("kick", 0.008, 0.16, Vector((0.08, 0.15, 0.0)), "metal", n=6, rot=(math.radians(20), 0, 0)),
             cyl("taillight", 0.025, 0.02, (0, yr + 0.17, 0.14), mat("EMIT_brake", "#c8302a", emit="#ff3b2f",
                                                                   emit_strength=1.0), n=8,
                 rot=(math.radians(90), 0, 0))]
    group(name + "_frame", root, parts, coll)
    wheel("WHEEL_rear", RW, 0.06, (0, yr, RW), coll, root, spokes=False, hub_m="metal")
    st = node("STEER", (0, -0.44, 0.5), coll, root)
    sp = [tube_path("stem", [Vector((0, yf + 0.03, 0.2)), Vector((0, -0.42, 0.98))], 0.026, body_m),
          tube_path("fork", [Vector((0, yf + 0.03, 0.22)), Vector((0, yf, RW))], 0.022, body_m),
          tube_path("bar", [Vector((0.27, -0.4, 1.0)), Vector((-0.27, -0.4, 1.0))], 0.017, "black"),
          cyl("gripL", 0.024, 0.1, Vector((0.19, -0.4, 1.0)), body_m, n=8, rot=(0, math.radians(90), 0)),
          cyl("gripR", 0.024, 0.1, Vector((-0.29, -0.4, 1.0)), body_m, n=8, rot=(0, math.radians(90), 0)),
          box("display", (0.09, 0.05, 0.03), Vector((0, -0.43, 1.0)), "black", bevel=0.01),
          tube_path("fguard", [Vector((0, yf + math.sin(a) * (RW + 0.04), RW + math.cos(a) * (RW + 0.04)))
                               for a in [math.radians(x) for x in range(-100, 20, 10)]], 0.028, body_m),
          cyl("headlamp", 0.035, 0.05, Vector((0, -0.5, 0.42)), "EMIT_lamp", n=10, rot=(math.radians(90), 0, 0))]
    group("STEER_mesh", st, sp, coll)
    bat = box("EMIT_battery", (0.07, 0.01, 0.018), Vector((0, -0.452, 1.025)), mat("EMIT_battery", "#3bff6a",
                                                                                   emit="#3bff6a",
                                                                                   emit_strength=1.5))
    group("EMIT_battery", st, [bat], coll)
    wheel("WHEEL_front", RW, 0.06, (0, yf, RW), coll, st, spokes=False, hub_m="metal")
    # upgrades (Godot toggles): rack + bag, mudguards, big headlight, wide tyres
    acc = [box("rack", (0.26, 0.3, 0.02), (0, 0.42, 0.42), "metal", bevel=0.005),
           tube_path("rk1", [Vector((0.11, 0.3, 0.42)), Vector((0.08, 0.3, 0.12))], 0.01, "metal"),
           tube_path("rk2", [Vector((-0.11, 0.3, 0.42)), Vector((-0.08, 0.3, 0.12))], 0.01, "metal"),
           tube_path("rk3", [Vector((0.11, 0.55, 0.42)), Vector((0.03, yr, RW + 0.02))], 0.01, "metal"),
           tube_path("rk4", [Vector((-0.11, 0.55, 0.42)), Vector((-0.03, yr, RW + 0.02))], 0.01, "metal"),
           box("rackbag", (0.36, 0.3, 0.3), (0, 0.42, 0.44), mat("bag_turq", "turq", rough=0.5), bevel=0.04)]
    group("ACC_rack", root, acc, coll)
    wide = []
    for nm, y in (("f", yf), ("r", yr)):
        wide.append(torus("wt" + nm, RW + 0.01, 0.045, (0, y, RW + 0.01), "black", n=20, nr=8,
                          rot=(0, math.radians(90), 0)))
    group("ACC_wide_tires", root, wide, coll)
    group("ACC_headlight", st, [cyl("bighl", 0.06, 0.07, Vector((0, -0.48, 0.85)), "EMIT_lamp", n=12,
                                    rot=(math.radians(90), 0, 0)),
                                box("hlmount", (0.04, 0.05, 0.04), Vector((0, -0.45, 0.85)), "black")], coll)
    lh = point_light("LIGHT_head", (0, -0.6, 0.6), 30, color="#fff2cc", coll=coll)
    lh.parent = st
    lh.matrix_parent_inverse = st.matrix_world.inverted()
    node("MARK_stand", (0, 0.05, 0.0), coll, root)
    colb = colbox(name, (0.35, 1.2, 1.0), (0, 0, 0.05), coll)
    colb.parent = root
    return root


# ------------------------------------------------------------------ cars
def car(name, L=3.4, W=1.7, H=1.5, paint="#ef6a5b", paint_name="car_paint", cabin=(0.55, 0.0), kind="hatch",
        wheel_r=0.33, extra=None):
    coll = collection(name)
    root = node(name, (0, 0, 0), coll)
    pm = mat(paint_name, paint, rough=0.35)
    glass = mat("car_glass", "#3a5a78", rough=0.1)
    body_h = H * 0.5
    parts = [box("body", (W, L, body_h), (0, 0, wheel_r * 0.55), pm, bevel=min(0.25, body_h * 0.4), seg=3),
             box("bumperF", (W * 0.95, 0.2, 0.18), (0, -L / 2, wheel_r * 0.5), "metal", bevel=0.06),
             box("bumperR", (W * 0.95, 0.2, 0.18), (0, L / 2, wheel_r * 0.5), "metal", bevel=0.06)]
    cab_len = L * cabin[0]
    cab_y = cabin[1]
    top_z = wheel_r * 0.55 + body_h
    parts.append(box("cabin", (W * 0.86, cab_len, H - body_h - wheel_r * 0.55), (0, cab_y, top_z - 0.05), pm,
                     bevel=0.18, seg=3))
    ch = H - body_h - wheel_r * 0.55
    # windows (inset slightly outside the cabin)
    parts.append(box("wsF", (W * 0.76, 0.05, ch * 0.7), (0, cab_y - cab_len / 2 - 0.01, top_z + ch * 0.08), glass,
                     bevel=0.03, rot=(math.radians(-12), 0, 0)))
    parts.append(box("wsR", (W * 0.76, 0.05, ch * 0.6), (0, cab_y + cab_len / 2 + 0.01, top_z + ch * 0.12), glass,
                     bevel=0.03))
    for sx in (-1, 1):
        parts.append(box("wsS%d" % sx, (0.05, cab_len * 0.82, ch * 0.6), (sx * W * 0.435, cab_y, top_z + ch * 0.12),
                         glass, bevel=0.03))
        parts.append(box("hl%d" % sx, (0.28, 0.06, 0.14), (sx * W * 0.32, -L / 2 - 0.01, wheel_r * 0.55 + body_h * 0.6),
                         mat("EMIT_headlight", "#fff6d8", emit="#fff2c0", emit_strength=0.0), bevel=0.03))
        parts.append(box("tl%d" % sx, (0.24, 0.06, 0.12), (sx * W * 0.34, L / 2 + 0.01, wheel_r * 0.55 + body_h * 0.65),
                         mat("EMIT_brake", "#c8302a", emit="#ff3b2f", emit_strength=1.0), bevel=0.03))
        parts.append(box("mirror%d" % sx, (0.12, 0.06, 0.08), (sx * W * 0.52, cab_y - cab_len / 2 + 0.1, top_z + 0.05),
                         pm, bevel=0.02))
    if extra:
        parts += extra(W, L, H, top_z, ch, cab_y, cab_len, pm)
    group(name + "_body", root, parts, coll)
    wb = L * 0.32
    for nm, x, y in (("fl", 1, -wb), ("fr", -1, -wb), ("rl", 1, wb), ("rr", -1, wb)):
        wheel("WHEEL_" + nm, wheel_r, 0.22, (x * (W / 2 - 0.12), y, wheel_r), coll, root, spokes=False,
              hub_m=mat("hubcap", "#d9dde2", metal=0.5, rough=0.3), wide=2.2)
    colb = colbox(name, (W, L, H), (0, 0, 0.1), coll)
    colb.parent = root
    return root


def taxi_extra(W, L, H, top_z, ch, cab_y, cab_len, pm):
    return [box("taxisign", (0.5, 0.25, 0.18), (0, cab_y, top_z + ch - 0.02), mat("EMIT_taxi", "#fff2a8", emit="#ffd94a",
                                                                                emit_strength=0.0), bevel=0.05),
            box("checker", (W * 1.01, L * 0.4, 0.08), (0, 0, top_z - 0.15), "black")]


def van_extra(W, L, H, top_z, ch, cab_y, cab_len, pm):
    return [box("cargo", (W * 0.98, L * 0.6, ch + 0.2), (0, L * 0.18, top_z - 0.05), pm, bevel=0.15, seg=3),
            box("stripe", (W * 1.0, L * 0.6, 0.12), (0, L * 0.18, top_z + ch * 0.4), "white")]


def bus(name="bus"):
    def extra(W, L, H, top_z, ch, cab_y, cab_len, pm):
        out = []
        for k in range(6):
            y = -L / 2 + 1.6 + k * 1.45
            for sx in (-1, 1):
                out.append(box("bw%d%d" % (k, sx), (0.05, 1.2, 0.9), (sx * W * 0.495, y, top_z + 0.25), "car_glass",
                               bevel=0.04))
        out.append(box("door", (0.05, 1.0, 1.9), (-W * 0.5, -L / 2 + 1.6, 0.35), "car_glass", bevel=0.03))
        out.append(box("route", (1.2, 0.05, 0.3), (0, -L / 2 - 0.02, top_z + ch - 0.4),
                       mat("EMIT_neon_teal", "#7fe3dc", emit="#38e0d0", emit_strength=0.0), bevel=0.03))
        return out
    return car(name, L=10.0, W=2.5, H=3.1, paint="#f6c945", paint_name="bus_paint", cabin=(0.98, 0.0), wheel_r=0.48,
               extra=extra)


def tram(name="tram"):
    coll = collection(name)
    root = node(name, (0, 0, 0), coll)
    pm = mat("tram_red", "#d9483b", rough=0.4)
    cream = mat("tram_cream", "#f3e3c3", rough=0.5)
    L, W, H = 14.0, 2.4, 3.3
    parts = [box("lower", (W, L, 1.2), (0, 0, 0.35), pm, bevel=0.3, seg=3),
             box("upper", (W * 0.98, L * 0.99, 1.4), (0, 0, 1.5), cream, bevel=0.3, seg=3),
             box("roof", (W * 0.9, L * 0.95, 0.35), (0, 0, 2.9), pm, bevel=0.15),
             box("panto", (0.8, 0.8, 0.05), (0, -2, 3.55), "black"),
             tube_path("pantoarm", [Vector((0, -2, 3.25)), Vector((0, -1.5, 3.55)), Vector((0, -2.3, 3.8))], 0.03,
                       "black")]
    for k in range(7):
        y = -L / 2 + 1.4 + k * 1.85
        for sx in (-1, 1):
            parts.append(box("tw%d%d" % (k, sx), (0.05, 1.4, 0.9), (sx * W * 0.495, y, 1.75), "car_glass", bevel=0.05))
    for sy in (-1, 1):
        parts.append(box("tfront%d" % sy, (W * 0.8, 0.05, 1.0), (0, sy * L * 0.497, 1.7), "car_glass", bevel=0.05))
        for sx in (-1, 1):
            parts.append(cyl("thl%d%d" % (sy, sx), 0.12, 0.05, (sx * 0.8, sy * L * 0.5, 0.9),
                             mat("EMIT_headlight", "#fff6d8", emit="#fff2c0", emit_strength=0.0), n=10,
                             rot=(math.radians(90), 0, 0)))
    group(name + "_body", root, parts, coll)
    for k, y in enumerate((-4.5, 4.5)):
        b = node("WHEEL_bogie%d" % k, (0, y, 0.35), coll, root)
        group("bogie%d_mesh" % k, b, [box("bg%d" % k, (W * 0.8, 2.2, 0.5), (0, y, 0.1), "black", bevel=0.1)], coll)
    colb = colbox(name, (W, L, H), (0, 0, 0.1), coll)
    colb.parent = root
    return root


CAT = [("bicycle", bicycle), ("scooter", scooter),
       ("car_hatch", lambda: car("car_hatch")),
       ("car_taxi", lambda: car("car_taxi", L=3.8, paint="#f6c945", paint_name="taxi_paint", extra=taxi_extra)),
       ("car_van", lambda: car("car_van", L=4.4, W=1.9, H=2.1, paint="#f7f3ea", paint_name="van_paint",
                               cabin=(0.3, -1.1), extra=van_extra)),
       ("bus", bus), ("tram", tram)]


def main():
    reset()
    std_mats()
    mat("car_glass", "#3a5a78", rough=0.1)
    R.setup_render((480, 400))
    R.world()
    R.sun()
    R.ground_plane()
    built = []
    for name, fn in CAT:
        if ONLY and name not in ONLY:
            continue
        root = fn()
        saved = scale_lights_for_export(root)
        export_gltf(root, os.path.join(ASSETS, "vehicles", name + ".gltf"))
        restore_lights(saved)
        built.append(root)
        print("built", name)
    if not NO_RENDER:
        R.mood("day")
        for root in built:
            kids = [root] + list(root.children_recursive)
            R.isolate(kids)
            R.frame_objects([k for k in kids if k.type == "MESH"], yaw=-60, pitch=15, margin=1.0)
            R.render(os.path.join(RENDERS, "previews", "veh_%s.png" % root.name))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, "vehicles.blend"))
    print("DONE")


if __name__ == "__main__":
    main()
