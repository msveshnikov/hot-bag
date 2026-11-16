"""Run 2 architecture: Business district «Сити», residential district «Берёзки», the dream restaurant.
blender -b --factory-startup -P build_architecture2.py -- [--no-render] [--only tower_a,panel_a]
Writes blender/architecture2.blend (separate from Task 1's architecture.blend, which the Old Town links),
assets/architecture/<name>.gltf, assets/architecture/architecture2_meta.json, renders/previews/arch2_<name>.png

Conventions as in Task 1: front faces -Y, pivot = base centre. Deliverable entrances carry MARK_door_<k> and
MARK_plate_<k>; towers add MARK_guard (security guard) and MARK_bignum (big painted number, panels too);
pickups carry MARK_pickup_/MARK_cook_/MARK_parking_<kind> and INT_counter_<kind>.
"""
import bpy
import sys
import os
import math
import json

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
import lib_render as R
from build_architecture import cut, door_panel, accent_mat, food_sign, restaurant, REST_COLORS

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None


def relink(objs, coll):
    for ob in objs:
        if ob is None:
            continue
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        coll.objects.link(ob)
    return objs


def emit_mat(name, base, glow):
    return mat(name, base, emit=glow, emit_strength=0.0)


# ================================================================ business district
GLASS = {"sky": "#9fd0ec", "mint": "#a5e0d0", "blue": "#86b6e3", "teal": "#8fd6d6"}
TRIM = {"cream": "#f4ecdc", "white": "#f7f5f0", "sand": "#e9d9bb"}


def tower(name, w=16.0, d=14.0, floors=14, glass="sky", trim="cream", seed=1, crown="garden"):
    """Chunky rounded glass office tower with a lobby, revolving door, guard spot and floor bands."""
    rs = rnd(seed)
    coll = collection(name)
    FH, GH = 3.4, 5.0
    H = GH + FH * (floors - 1)
    gm = mat("glass_" + glass, GLASS[glass], rough=0.12, metal=0.15, tex="glass", tile=6)
    tm = mat("trim_" + trim, TRIM[trim], rough=0.6)
    lit = mat("EMIT_office_" + glass, GLASS[glass], rough=0.12, metal=0.15, emit="#ffe2a8", emit_strength=0.0)
    o = []
    rad = min(w, d) * 0.16
    o.append(box(name + "_body", (w, d, H - GH), (0, 0, GH), gm, bevel=rad, seg=5))
    # floor bands (spandrels) + roof cap
    for f in range(floors):
        z = GH + f * FH - 0.18
        o.append(box(name + "_band%d" % f, (w + 0.25, d + 0.25, 0.42), (0, 0, z), tm, bevel=rad + 0.12, seg=5))
    o.append(box(name + "_cap", (w + 0.5, d + 0.5, 0.9), (0, 0, H - 0.2), tm, bevel=rad + 0.25, seg=5))
    # vertical mullions on the flat parts of the 4 faces
    for (L, axis, off) in ((w, "x", -d / 2), (w, "x", d / 2), (d, "y", -w / 2), (d, "y", w / 2)):
        n = int((L - 2 * rad) / 2.4)
        for k in range(n + 1):
            t = -L / 2 + rad + k * (L - 2 * rad) / max(1, n)
            if axis == "x":
                loc = (t, off + math.copysign(0.07, off), GH)
                sz = (0.16, 0.16, H - GH)
            else:
                loc = (off + math.copysign(0.07, off), t, GH)
                sz = (0.16, 0.16, H - GH)
            o.append(box(name + "_mul", sz, loc, tm))
        # lit offices at night: random window panels
        for f in range(1, floors):
            for k in range(n):
                if rs.random() < 0.28:
                    t = -L / 2 + rad + (k + 0.5) * (L - 2 * rad) / max(1, n)
                    z = GH + (f - 1) * FH + 0.6
                    pw = (L - 2 * rad) / max(1, n) - 0.4
                    if axis == "x":
                        o.append(box(name + "_lit", (pw, 0.05, 2.3), (t, off + math.copysign(0.05, off), z), lit))
                    else:
                        o.append(box(name + "_lit", (0.05, pw, 2.3), (off + math.copysign(0.05, off), t, z), lit))
    # lobby: inset warm glass box + corner columns + canopy + revolving door
    lob = emit_mat("EMIT_lobby", "#f3dfb8", "#ffe2a8")
    o.append(box(name + "_lobby", (w - 1.6, d - 1.6, GH), (0, 0, 0), lob, bevel=rad * 0.8, seg=4))
    o.append(box(name + "_lobbyfloor", (w + 0.6, d + 0.6, 0.12), (0, 0, 0), "stone", bevel=0.05))
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(cyl(name + "_col", 0.45, GH, (sx * (w / 2 - rad * 0.7), sy * (d / 2 - rad * 0.7), 0), tm, n=12))
    yf = -(d - 1.6) / 2
    o.append(box(name + "_canopy", (7.0, 3.6, 0.35), (0, yf - 1.6, GH - 1.0), tm, bevel=0.15, seg=3))
    o.append(cyl(name + "_rev", 1.35, 2.7, (0, yf - 0.9, 0), mat("glass_door", "#d8eef7", rough=0.1, metal=0.2), n=20))
    o.append(cyl(name + "_revtop", 1.5, 0.4, (0, yf - 0.9, 2.7), "steel", n=20))
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        o.append(box(name + "_fin%d" % k, (1.3, 0.06, 2.6), (math.cos(a) * 0.65, yf - 0.9 + math.sin(a) * 0.65, 0.05),
                     "steel", rot=(0, 0, a)))
    o.append(cyl(name + "_revbase", 1.5, 0.08, (0, yf - 0.9, 0.0), "steel", n=20))
    # lobby sign stripe (glows at night) + planters by the door
    o.append(box(name + "_sign", (5.0, 0.2, 0.7), (0, yf - 3.42, GH - 1.15), emit_mat("EMIT_neon_teal", "#7fe3dc",
                                                                                     "#38e0d0"), bevel=0.08))
    for sx in (-1, 1):
        o.append(box(name + "_planter%d" % sx, (1.6, 1.0, 0.7), (sx * 3.6, yf - 1.6, 0), "stone", bevel=0.12))
        o.append(sphere(name + "_shrub%d" % sx, 0.6, (sx * 3.6, yf - 1.6, 1.1), "leaf", seg=10, rings=6,
                        scale=(1.3, 0.8, 0.8)))
    # crown
    if crown == "garden":
        o.append(box(name + "_roofbox", (w * 0.5, d * 0.5, 2.6), (0, 0, H + 0.7), tm, bevel=0.5, seg=3))
        for k in range(6):
            a = k * 1.05
            o.append(sphere(name + "_rtree%d" % k, 1.3, (math.cos(a) * w * 0.33, math.sin(a) * d * 0.33, H + 1.6),
                            ["leaf", "leaf2"][k % 2], seg=10, rings=6))
    elif crown == "spire":
        o.append(box(name + "_roofbox", (w * 0.6, d * 0.6, 4.0), (0, 0, H + 0.7), gm, bevel=1.0, seg=4))
        o.append(cyl(name + "_spire", 0.35, 9.0, (0, 0, H + 4.7), "steel", n=10, r2=0.05))
        o.append(sphere(name + "_spirelamp", 0.4, (0, 0, H + 13.7), emit_mat("EMIT_warn", "#ff6f5a", "#ff3b2f")))
    else:
        for k in range(3):
            o.append(box(name + "_ac%d" % k, (2.4, 1.8, 1.4), (-w * 0.25 + k * w * 0.25, d * 0.15, H + 0.7), "steel",
                         bevel=0.15))
        o.append(cyl(name + "_heli", w * 0.3, 0.2, (0, -d * 0.12, H + 0.7), "asphalt", n=24))
        o.append(torus(name + "_helir", w * 0.26, 0.12, (0, -d * 0.12, H + 0.92), "sun", n=24))
    # markers: deliverable lobby door (no stairs — towers have lifts), plate by the door, guard, big number
    o.append(empty("MARK_door_0", (0, yf - 3.2, 0), 180, coll))
    o.append(empty("MARK_plate_0", (2.4, yf - 0.06, 2.8), 0, coll))
    o.append(empty("MARK_guard", (-2.3, yf - 2.0, 0), 180, coll))
    o.append(empty("MARK_bignum", (0, -d / 2 - 0.3, H - 2.6), 0, coll))
    o.append(colbox(name, (w, d, H), (0, 0, 0), coll))
    relink(o, coll)
    root = finish_asset(o, name, coll)
    return root, dict(kind="tower", w=w + 0.6, d=d + 0.6 + 3.6, front_extra=3.6, floors=floors, h=H, doors=1,
                      lift=True)


def food_sign2(kind, coll):
    """Food-shaped signs for the run 2 pickups (~1.6 m, front -Y)."""
    o = []
    if kind == "wok":
        bowl = emit_mat("EMIT_sign_wok", "#e2493b", "#ff6a4f")
        o.append(sphere("sg_bowl", 0.95, (0, 0, 0.75), bowl, seg=20, rings=10, scale=(1, 1, 0.62)))
        o.append(cyl("sg_noodle", 0.85, 0.1, (0, 0, 1.05), mat("noodle", "#f3d27a"), n=20))
        for k in range(5):
            a = k * 1.2
            o.append(torus("sg_curl%d" % k, 0.18, 0.05, (math.cos(a) * 0.4, math.sin(a) * 0.4, 1.15), "noodle"))
        for sx in (-1, 1):
            o.append(cyl("sg_stick%d" % sx, 0.04, 1.6, (sx * 0.15, 0.2, 1.0), "wood", n=6,
                         rot=(math.radians(-25), math.radians(sx * 20), 0)))
    elif kind == "salad":
        bowl = emit_mat("EMIT_sign_salad", "#f7f3ea", "#fff6e0")
        o.append(sphere("sg_bowl", 0.95, (0, 0, 0.75), bowl, seg=20, rings=10, scale=(1, 1, 0.6)))
        for k in range(9):
            a = k * 0.7
            r = 0.25 + 0.45 * ((k * 37) % 10) / 10
            c = ["leaf", "leaf2", "#e8483b", "#f6c945", "leaf"][k % 5]
            o.append(sphere("sg_leaf%d" % k, 0.28 if k % 5 < 2 else 0.18, (math.cos(a) * r, math.sin(a) * r, 1.15),
                            mat("salad_" + str(c).lstrip("#"), c), seg=8, rings=6, scale=(1, 1, 0.7)))
    elif kind == "burrito":
        wrap = emit_mat("EMIT_sign_burrito", "#f0cf8a", "#ffd98a")
        o.append(cyl("sg_wrap", 0.55, 1.7, (-0.85, 0, 1.0), wrap, n=16, r2=0.62, rot=(0, math.radians(90), 0)))
        o.append(sphere("sg_fill", 0.5, (0.9, 0, 1.05), mat("filling", "#7cbf4a"), seg=10, rings=8, scale=(0.4, 1, 1)))
        o.append(sphere("sg_tom", 0.25, (0.95, -0.1, 1.25), mat("tomato", "#e8483b"), seg=8, rings=6))
    elif kind == "shawarma":
        meat = emit_mat("EMIT_sign_shawarma", "#c9773d", "#ffa24a")
        o.append(cyl("sg_spit", 0.55, 1.6, (0, 0, 0.2), meat, n=16, r2=0.35))
        o.append(cyl("sg_rod", 0.05, 2.2, (0, 0, 0.0), "steel", n=6))
        o.append(cyl("sg_top", 0.3, 0.12, (0, 0, 1.8), "steel", n=10))
    elif kind == "bakery":
        loaf = emit_mat("EMIT_sign_bakery", "#e3a85a", "#ffc46a")
        o.append(sphere("sg_loaf", 0.9, (0, 0, 0.8), loaf, seg=18, rings=10, scale=(1.3, 0.7, 0.6)))
        for k in range(3):
            o.append(box("sg_cut%d" % k, (0.08, 0.5, 0.35), (-0.5 + k * 0.5, -0.45, 1.05), mat("crumb", "#f6deb0"),
                         rot=(0, math.radians(30), 0)))
    elif kind == "grocery":
        basket = emit_mat("EMIT_sign_grocery", "#3f9fd9", "#58c0ff")
        o.append(box("sg_basket", (1.8, 1.0, 0.9), (0, 0, 0.4), basket, bevel=0.15))
        o.append(torus("sg_handle", 0.7, 0.07, (0, 0, 1.3), basket, rot=(math.radians(90), 0, 0)))
        for k, c in enumerate(("#e8483b", "#f6c945", "#7cbf4a")):
            o.append(sphere("sg_fruit%d" % k, 0.3, (-0.5 + k * 0.5, 0, 1.35), mat("fruit_" + c.lstrip("#"), c), seg=8,
                            rings=6))
    elif kind == "dream":
        pot = emit_mat("EMIT_sign_dream", "#ffd34f", "#ffd34f")
        o.append(sphere("sg_cloche", 0.9, (0, 0, 0.4), pot, seg=20, rings=10, scale=(1.1, 1, 0.75)))
        o.append(cyl("sg_plate", 1.2, 0.12, (0, 0, 0.3), "white", n=24))
        o.append(sphere("sg_knob", 0.18, (0, 0, 1.12), pot, seg=8, rings=6))
        for k in range(3):
            o.append(sphere("sg_steam%d" % k, 0.18, (-0.35 + k * 0.35, 0, 1.5 + (k % 2) * 0.25), "white", seg=8,
                            rings=6))
    return relink(o, coll)


def food_court(name="food_court"):
    """Plaza pavilion with three pickup windows (wok, salad, burrito) under one rounded roof."""
    coll = collection(name)
    o = []
    kinds = [("wok", "coral", "#f6b98a"), ("salad", "green", "#c4e3a6"), ("burrito", "sun", "#f8dc9a")]
    W, D, Hh = 18.0, 7.0, 4.0
    o.append(box(name + "_floor", (W + 1.0, D + 1.0, 0.15), (0, 0, 0), "stone", bevel=0.05))
    for i, (k, acc, wall) in enumerate(kinds):
        cx = -W / 3 + i * W / 3
        sw = W / 3 - 0.3
        body = box(name + "_stall%d" % i, (sw, D, Hh), (cx, 0, 0), mat("stall_" + k, wall), bevel=0.15, seg=3)
        cut(body, box("c", (sw - 1.6, 1.2, 1.7), (cx, -D / 2, 1.0), None))
        o.append(body)
        o.append(box(name + "_in%d" % i, (sw - 1.4, 2.4, 2.6), (cx, -D / 2 + 1.5, 0.4), mat("interior_warm", "#f0c48a")))
        o.append(box("INT_counter_" + k, (sw - 1.4, 0.7, 0.16), (cx, -D / 2 - 0.05, 1.0), "darkwood", bevel=0.04))
        for b in range(2):
            o.append(box(name + "_bag%d%d" % (i, b), (0.32, 0.22, 0.42), (cx - 0.8 + b * 0.5, -D / 2 - 0.05, 1.16),
                         mat("paper", "#d9b384"), bevel=0.02))
        n = 6
        for s in range(n):
            seg = box(name + "_aw%d_%d" % (i, s), (sw / n + 0.01, 1.4, 0.08), (cx - sw / 2 + (s + 0.5) * sw / n,
                                                                                 -D / 2 - 0.65, Hh - 0.6),
                      [accent_mat(acc), mat("awning_white", "white")][s % 2], rot=(math.radians(-20), 0, 0))
            o.append(seg)
        sign = food_sign2(k, coll)
        for ob in sign:
            ob.location = (ob.location.x * 0.75 + cx, ob.location.y * 0.75 - D / 2 + 0.2, ob.location.z * 0.75 + Hh + 0.6)
            ob.scale = (0.75, 0.75, 0.75)
        o += sign
        o.append(empty("MARK_pickup_" + k, (cx, -D / 2 - 1.3, 0), 180, coll))
        o.append(empty("MARK_cook_" + k, (cx, -D / 2 + 0.9, 0), 0, coll))
        o.append(empty("MARK_parking_" + k, (cx + 2.0, -D / 2 - 3.0, 0), 90, coll))
        o.append(point_light("LIGHT_" + name + k, (cx, -D / 2 - 0.4, Hh - 0.8), 50, coll=coll))
    # big curved roof
    roof = cyl(name + "_roof", 1.0, W + 1.4, (-(W + 1.4) / 2, 0, Hh + 0.1), mat("roof_wood", "#c7955c"), n=24,
               rot=(0, math.radians(90), 0))
    roof.scale = (0.9, (D + 2.0) / 2, 1.0)
    o.append(roof)
    o.append(colbox(name, (W, D, Hh), (0, 0, 0), coll))
    relink(o, coll)
    root = finish_asset(o, name, coll)
    return root, dict(kind="restaurant", w=W + 1.0, d=D + 1.0, h=Hh)


def sculpture(name="sculpture"):
    coll = collection(name)
    o = [box(name + "_base", (3.4, 3.4, 1.2), (0, 0, 0), "stone", bevel=0.2, seg=3)]
    sm = mat("chrome", "#c9d2da", rough=0.2, metal=0.8)
    o.append(torus(name + "_r1", 1.5, 0.38, (0, 0, 3.0), sm, n=28, nr=12, rot=(math.radians(90), 0, 0.3)))
    o.append(torus(name + "_r2", 1.4, 0.38, (0.6, 0, 3.4), sm, n=28, nr=12, rot=(math.radians(90), 0, 1.6)))
    o.append(torus(name + "_r3", 1.1, 0.34, (-0.3, 0, 4.4), sm, n=28, nr=12, rot=(0.6, 0.4, 0)))
    o.append(colbox(name, (3.4, 3.4, 4.0), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="landmark", w=3.4, d=3.4, h=6.0)


def planter_long(name="planter_long"):
    coll = collection(name)
    o = [box(name + "_box", (6.0, 1.4, 0.7), (0, 0, 0), "stone", bevel=0.15, seg=3)]
    for k in range(5):
        c = ["leaf", "leaf2"][k % 2]
        o.append(sphere(name + "_shrub%d" % k, 0.55, (-2.4 + k * 1.2, 0, 1.0), c, seg=10, rings=6, scale=(1, 0.9, 0.8)))
    for k in range(4):
        col = ["coral", "pink", "sun", "lilac"][k]
        o.append(sphere(name + "_fl%d" % k, 0.18, (-1.8 + k * 1.2, -0.5, 1.15), mat("flower_" + col, col), seg=6,
                        rings=4))
    o.append(colbox(name, (6.0, 1.4, 0.8), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="prop", w=6.0, d=1.4, h=1.4)


# ================================================================ residential district
PANEL_COLORS = {"cream": "#f1e6cf", "yellow": "#f3e2a6", "white": "#ece9e1", "peach": "#f2d2b6"}
STRIPES = {"mint": "#8fd3b0", "coral": "#ef8a7b", "sky": "#7ec3e8", "sun": "#f6c945"}


def panel_block(name, w=30.0, d=12.0, floors=9, entrances=3, color="cream", stripe="mint", seed=1, balconies=True):
    """Prefab panel apartment block («панелька»): window grid, coloured stripes, balconies, entrances with canopies,
    intercoms, lit door lamps; lifts inside (meta lift=True)."""
    rs = rnd(seed)
    coll = collection(name)
    FH, PL = 2.9, 1.0
    H = PL + floors * FH + 0.7
    fm = mat("panel_" + color, PANEL_COLORS[color], tex="panel", tile=5.8)
    sm = mat("stripe_" + stripe, STRIPES[stripe], rough=0.7)
    o = [box(name + "_body", (w, d, H), (0, 0, 0), fm, bevel=0.2, seg=2)]
    o.append(box(name + "_plinth", (w + 0.2, d + 0.2, PL + 0.1), (0, 0, 0), mat("plinth_grey", "#a9a49c", tex="stone",
                                                                                tile=3), bevel=0.06))
    o.append(box(name + "_parapet", (w + 0.3, d + 0.3, 0.5), (0, 0, H - 0.5), mat("panel_trim", "#d9d3c6"), bevel=0.08))
    cols = max(3, int(w / 2.6))
    xs = [-w / 2 + (k + 0.5) * w / cols for k in range(cols)]
    door_xs = [-w / 2 + (i + 0.5) * w / entrances for i in range(entrances)]
    # vertical colour stripes: at both ends of the front and one per staircase (above each entrance)
    for sx in (-1, 1):
        o.append(box(name + "_endstripe%d" % sx, (1.2, 0.12, H - PL - 0.6), (sx * (w / 2 - 0.6), -d / 2 - 0.04, PL), sm))
    win_glass = "EMIT_window"
    frame = mat("win_frame", "#f7f5f0")
    for side in (-1, 1):
        yf = side * d / 2
        for f in range(floors):
            z = PL + f * FH + 0.75
            for k, x in enumerate(xs):
                # stairwell column above the entrances: narrow staircase windows, half a floor up
                stair = side == -1 and any(abs(x - dx) < w / cols * 0.5 for dx in door_xs)
                if stair and f == 0:
                    continue
                zz = z + (FH * 0.5 if stair else 0.0)
                if stair and f == floors - 1:
                    continue
                ww = 0.7 if stair else 1.3
                o.append(box(name + "_wf", (ww + 0.2, 0.1, 1.5), (x, yf + side * 0.04, zz - 0.1), frame))
                o.append(box(name + "_wg", (ww, 0.06, 1.3), (x, yf + side * 0.08, zz), win_glass))
        # balconies on the front, every other column, skipping stairwells
        if side == -1 and balconies:
            for k, x in enumerate(xs):
                if k % 2 == 1 or any(abs(x - dx) < w / cols * 0.8 for dx in door_xs):
                    continue
                bc = rs.choice([sm, frame, mat("balc_white", "#f2efe8")])
                for f in range(1, floors):
                    z = PL + f * FH - 0.15
                    o.append(box(name + "_bslab", (2.2, 1.1, 0.12), (x, yf - 0.55, z), "panel_trim"))
                    o.append(box(name + "_bfront", (2.2, 0.1, 1.0), (x, yf - 1.08, z + 0.1), bc))
    # stair stripes above each entrance (front)
    for i, dx in enumerate(door_xs):
        o.append(box(name + "_sstripe%d" % i, (1.6, 0.1, H - PL - 3.6), (dx, -d / 2 - 0.05, PL + 3.0), sm))
    # entrances
    yf = -d / 2
    for i, dx in enumerate(door_xs):
        c = box(name + "_cut%d" % i, (1.5, 1.2, 2.3), (dx, yf, PL - 0.6), None)
        cut(o[0], c)
        vest = box(name + "_vest%d" % i, (1.7, 1.2, 2.5), (dx, yf + 0.7, PL - 0.6), mat("vestibule", "#6b5446"))
        for p in vest.data.polygons:
            p.flip()
        o.append(vest)
        dp = door_panel("INT_door_%s_%d" % (name, i), 1.4, 2.2, mat("door_metal", "#6e5a4c", rough=0.5), coll)
        dp.location = (dx - 0.7, yf + 0.12, PL - 0.6)
        o.append(dp)
        o.append(box(name + "_steps%d" % i, (2.6, 1.6, PL - 0.6), (dx, yf - 0.75, 0.0), "stone", bevel=0.04))
        o.append(box(name + "_canopy%d" % i, (2.8, 1.8, 0.2), (dx, yf - 0.9, PL + 1.9), "panel_trim", bevel=0.05))
        for sx in (-1, 1):
            o.append(cyl(name + "_post%d%d" % (i, sx), 0.06, 1.9, (dx + sx * 1.2, yf - 1.65, PL), "metal", n=6))
        ic = box("INT_intercom_%s_%d" % (name, i), (0.24, 0.08, 0.36), (dx + 1.0, yf - 0.04, PL + 0.7), "metal",
                 bevel=0.02)
        o.append(ic)
        o.append(cyl(name + "_dlamp%d" % i, 0.14, 0.25, (dx, yf - 0.12, PL + 1.65), "EMIT_lamp", n=8))
        o.append(box(name + "_bench%d" % i, (1.6, 0.45, 0.45), (dx + (2.3 if i % 2 else -2.3), yf - 1.2, 0), "wood",
                     bevel=0.04))
        o.append(empty("MARK_door_%d" % i, (dx, yf - 2.6, 0), 180, coll))
        o.append(empty("MARK_plate_%d" % i, (dx - 1.05, yf - 0.06, PL + 1.0), 0, coll))
        o.append(empty("MARK_sit_a", (dx + (2.3 if i % 2 else -2.3), yf - 1.25, 0), 180, coll))
    # roof: lift machine rooms + antennas
    for dx in door_xs:
        o.append(box(name + "_liftroom", (3.0, 3.6, 2.2), (dx, d * 0.1, H), "panel_trim", bevel=0.1))
    for k in range(2):
        o.append(cyl(name + "_ant%d" % k, 0.05, 2.5, (rs.uniform(-w / 3, w / 3), -d * 0.2, H), "metal", n=5))
    o.append(empty("MARK_bignum", (-w / 2 + 0.6, -d / 2 - 0.15, H - 3.2), 0, coll))
    o.append(colbox(name, (w, d, H), (0, 0, 0), coll))
    relink(o, coll)
    root = finish_asset(o, name, coll)
    return root, dict(kind="panel", w=w, d=d + 1.8, front_extra=1.8, floors=floors, h=H, doors=entrances, lift=True)


def pavilion(name, kind, w=6.0, d=4.0, h=3.2, wall="#f3e2a6", acc="coral"):
    """Small pickup pavilion/kiosk/shop (shawarma, bakery, grocery)."""
    coll = collection(name)
    o = []
    body = box(name + "_body", (w, d, h), (0, 0, 0), mat("pav_" + kind, wall), bevel=0.2, seg=3)
    cut(body, box("c", (w - 1.8, 1.2, 1.5), (0, -d / 2, 1.0), None))
    o.append(body)
    o.append(box(name + "_in", (w - 1.6, 1.4, 2.0), (0, -d / 2 + 0.9, 0.6), mat("interior_warm", "#f0c48a")))
    o.append(box("INT_counter_" + kind, (w - 1.6, 0.6, 0.14), (0, -d / 2 - 0.05, 1.0), "darkwood", bevel=0.03))
    n = 6
    for s in range(n):
        o.append(box(name + "_aw%d" % s, (w / n + 0.01, 1.3, 0.08), (-w / 2 + (s + 0.5) * w / n, -d / 2 - 0.6, h - 0.5),
                     [accent_mat(acc), mat("awning_white", "white")][s % 2], rot=(math.radians(-20), 0, 0)))
    o.append(box(name + "_roof", (w + 0.4, d + 0.4, 0.3), (0, 0, h), "trim_white", bevel=0.1))
    sign = food_sign2(kind, coll)
    for ob in sign:
        ob.location = (ob.location.x * 0.7, ob.location.y * 0.7, ob.location.z * 0.7 + h + 0.3)
        ob.scale = (0.7, 0.7, 0.7)
    o += sign
    o.append(empty("MARK_pickup_" + kind, (0, -d / 2 - 1.2, 0), 180, coll))
    o.append(empty("MARK_cook_" + kind, (0, -d / 2 + 0.8, 0), 0, coll))
    o.append(empty("MARK_parking_" + kind, (w / 2 + 1.2, -d / 2 - 2.4, 0), 90, coll))
    o.append(point_light("LIGHT_" + name, (0, -d / 2 - 0.4, h - 0.6), 40, coll=coll))
    o.append(colbox(name, (w, d, h), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="restaurant", food=kind, w=w, d=d + 1.2, h=h)


def supermarket(name="supermarket"):
    coll = collection(name)
    w, d, h = 16.0, 10.0, 5.0
    o = []
    body = box(name + "_body", (w, d, h), (0, 0, 0), mat("market_wall", "#e9eef2"), bevel=0.2, seg=3)
    cut(body, box("c", (w - 3.0, 1.2, 3.0), (0, -d / 2, 0.3), None))
    o.append(body)
    o.append(box(name + "_glass", (w - 3.0, 0.08, 3.0), (0, -d / 2 + 0.4, 0.3), "EMIT_window"))
    o.append(box(name + "_in", (w - 2.8, 1.6, 3.4), (0, -d / 2 + 1.3, 0.1), mat("interior_cool", "#d9ecf5")))
    o.append(box("INT_counter_grocery", (2.4, 0.6, 0.14), (-w / 2 + 3.0, -d / 2 - 0.4, 1.0), "darkwood"))
    o.append(box(name + "_ctr", (2.4, 0.6, 1.0), (-w / 2 + 3.0, -d / 2 - 0.4, 0.0), mat("paint_blue", "blue")))
    o.append(box(name + "_band", (w + 0.3, 0.4, 1.2), (0, -d / 2 - 0.1, h - 1.3), mat("paint_blue", "blue"), bevel=0.1))
    sign = food_sign2("grocery", coll)
    for ob in sign:
        ob.location = (ob.location.x * 0.8 + 3.0, ob.location.y * 0.8 - d / 2 - 0.4, ob.location.z * 0.8 + h - 0.4)
        ob.scale = (0.8, 0.8, 0.8)
    o += sign
    for k in range(4):
        o.append(box(name + "_cart%d" % k, (0.6, 0.9, 0.7), (w / 2 - 1.5 - k * 0.3, -d / 2 - 1.2, 0.2), "steel"))
    o.append(empty("MARK_pickup_grocery", (-w / 2 + 3.0, -d / 2 - 1.5, 0), 180, coll))
    o.append(empty("MARK_cook_grocery", (-w / 2 + 3.0, -d / 2 + 0.6, 0), 0, coll))
    o.append(empty("MARK_parking_grocery", (-w / 2 + 6.0, -d / 2 - 3.0, 0), 90, coll))
    o.append(point_light("LIGHT_" + name, (0, -d / 2 - 0.6, h - 1.6), 60, coll=coll))
    o.append(colbox(name, (w, d, h), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="restaurant", food="grocery", w=w, d=d + 1.5, h=h)


def playground(name="playground"):
    coll = collection(name)
    o = [box(name + "_sand", (12.0, 9.0, 0.08), (0, 0, 0), mat("rubber_mat", "#e98b6f"), bevel=0.04)]
    # slide tower + slide
    o.append(box(name + "_tower", (2.0, 2.0, 2.0), (-3.0, 0, 0), mat("paint_yellow", "yellow"), bevel=0.12))
    o.append(pyramid(name + "_troof", 2.4, 2.4, 1.2, mat("paint_red", "red"), (-3.0, 0, 3.2)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(cyl(name + "_tp", 0.08, 1.2, (-3.0 + sx * 0.9, sy * 0.9, 2.0), "metal", n=6))
    sl = box(name + "_slide", (1.0, 4.2, 0.12), (-3.0, -2.9, 0.9), mat("paint_blue", "blue"), bevel=0.05)
    sl.rotation_euler = (math.radians(-28), 0, 0)
    o.append(sl)
    # swings
    for sx in (-1, 1):
        o.append(cyl(name + "_sw%d" % sx, 0.08, 2.6, (2.0 + sx * 1.6, 0, 0), mat("paint_green", "green"), n=6))
    o.append(cyl(name + "_swbar", 0.08, 3.4, (0.3, 0, 2.6), mat("paint_green", "green"), n=6,
                 rot=(0, math.radians(90), 0)))
    for k in (-0.7, 0.7):
        o.append(box(name + "_seat%d" % int(k * 10), (0.5, 0.3, 0.06), (2.0 + k, 0, 0.6), "wood"))
        for sy in (-1, 1):
            o.append(cyl(name + "_rope", 0.015, 2.0, (2.0 + k, sy * 0.12, 0.62), "metal", n=4))
    # sandbox + spring rider
    o.append(box(name + "_sbox", (2.6, 2.6, 0.3), (2.5, 3.0, 0), "wood", bevel=0.05))
    o.append(box(name + "_sandin", (2.3, 2.3, 0.05), (2.5, 3.0, 0.27), mat("sand", "#f2dc9b")))
    o.append(sphere(name + "_rider", 0.4, (-2.5, 3.2, 0.8), mat("paint_coral", "coral"), seg=10, rings=6,
                    scale=(1.4, 0.7, 0.8)))
    o.append(cyl(name + "_spring", 0.1, 0.6, (-2.5, 3.2, 0), "metal", n=6))
    o.append(colbox(name + "_t", (2.0, 2.0, 3.0), (-3.0, 0, 0), coll))
    o.append(colbox(name + "_s", (3.8, 0.4, 2.6), (2.0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="prop", w=12.0, d=9.0, h=3.2)


def garages_row(name="garages_row", n=6):
    coll = collection(name)
    w = 3.4
    o = []
    cols = ["#7e9fc9", "#8fd3b0", "#c9a77c", "#ef8a7b", "#9aa4ad", "#f6c945"]
    for k in range(n):
        x = -n * w / 2 + (k + 0.5) * w
        o.append(box(name + "_g%d" % k, (w - 0.05, 6.0, 2.6), (x, 0, 0), mat("garage_wall", "#cfc8bb", tex="stone",
                                                                            tile=3), bevel=0.06))
        o.append(box(name + "_door%d" % k, (2.6, 0.1, 2.1), (x, -3.02, 0.0), mat("gdoor_" + cols[k % 6].lstrip("#"),
                                                                                 cols[k % 6], rough=0.5)))
    o.append(box(name + "_roof", (n * w + 0.3, 6.4, 0.25), (0, 0, 2.6), "slate"))
    o.append(colbox(name, (n * w, 6.0, 2.6), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="prop", w=n * w, d=6.0, h=2.9)


def tree_birch(name="tree_birch", seed=4, h=7.0):
    coll = collection(name)
    rs = rnd(seed)
    bark = mat("birch_bark", "#f2efe6")
    o = [cyl(name + "_trunk", 0.2, h * 0.7, (0, 0, 0), bark, n=10, r2=0.12)]
    for k in range(7):
        z = 0.6 + k * h * 0.09
        a = rs.uniform(0, 6.28)
        o.append(box(name + "_mark%d" % k, (0.2, 0.05, 0.08), (math.cos(a) * 0.17, math.sin(a) * 0.17, z), "black",
                     rot=(0, 0, a + 1.57)))
    for k in range(4):
        a = k * 1.6 + rs.random()
        o.append(sphere(name + "_crown%d" % k, rs.uniform(1.0, 1.4), (math.cos(a) * 0.8, math.sin(a) * 0.8,
                                                                      h * 0.62 + rs.uniform(0, 1.2)),
                        mat("leaf_birch", "#9ccc5a"), seg=10, rings=7, scale=(1, 1, 1.3)))
    o.append(sphere(name + "_top", 1.1, (0, 0, h * 0.9), mat("leaf_birch2", "#86b94c"), seg=10, rings=7,
                    scale=(1, 1, 1.4)))
    o.append(colbox(name, (0.4, 0.4, 2.5), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="prop", w=0.5, d=0.5, h=h)


def dumpsters(name="dumpsters"):
    coll = collection(name)
    o = [box(name + "_pad", (5.0, 2.4, 0.1), (0, 0, 0), "stone")]
    for k, c in enumerate(("#4f8f5a", "#3f7fc9", "#d9a03b")):
        x = -1.6 + k * 1.6
        o.append(box(name + "_bin%d" % k, (1.3, 1.1, 1.2), (x, 0, 0.1), mat("bin_" + c.lstrip("#"), c), bevel=0.08))
        o.append(box(name + "_lid%d" % k, (1.4, 1.2, 0.12), (x, 0, 1.3), mat("bin_" + c.lstrip("#"), c), bevel=0.05))
    o.append(colbox(name, (5.0, 1.4, 1.4), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="prop", w=5.0, d=2.4, h=1.4)


def bus_stop(name="bus_stop"):
    coll = collection(name)
    o = [box(name + "_floor", (5.0, 2.0, 0.12), (0, 0, 0), "stone")]
    o.append(box(name + "_back", (4.8, 0.1, 2.3), (0, 0.9, 0.1), mat("glass_door", "#d8eef7", rough=0.1, metal=0.2)))
    o.append(box(name + "_roof", (5.2, 2.2, 0.15), (0, 0.1, 2.5), mat("paint_blue", "blue"), bevel=0.05))
    for sx in (-1, 1):
        o.append(cyl(name + "_post%d" % sx, 0.06, 2.5, (sx * 2.4, 0.9, 0), "metal", n=6))
    o.append(box(name + "_bench", (3.0, 0.5, 0.45), (0, 0.55, 0.1), "wood"))
    o.append(box(name + "_ad", (1.2, 0.12, 1.8), (2.2, 0.85, 0.3), "EMIT_window"))
    o.append(empty("MARK_sit_a", (0, 0.5, 0), 180, coll))
    o.append(colbox(name, (4.8, 0.3, 2.4), (0, 0.9, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="prop", w=5.2, d=2.2, h=2.6)


# ================================================================ Old Town: the dream restaurant
def dream_restaurant(name="restaurant_dream"):
    """The empty shop on Часовая площадь («Сдаётся») that becomes the hero's own restaurant in chapter 5.
    ACC_closed: boarded window + 'for rent' board; ACC_open: food sign, garland, flower boxes. Godot toggles them."""
    REST_COLORS["dream"] = ("cream", "turq")   # food_sign("dream") draws nothing: our signs are ACC_ parts
    root, meta = restaurant("dream")
    coll = root.users_collection[0]
    acc_closed = []
    plank = mat("plank", "#b58a5a")
    for k in range(4):
        acc_closed.append(box("cl_plank%d" % k, (3.8, 0.12, 0.3), (-0.9, -3.75, 1.2 + k * 0.45), plank,
                              rot=(0, math.radians(8 if k % 2 else -8), 0)))
    acc_closed.append(box("cl_board", (2.2, 0.12, 1.4), (0, -3.85, 4.5), mat("rent_board", "#f6c945"), bevel=0.08))
    acc_closed.append(box("cl_key", (0.9, 0.14, 0.18), (0, -3.95, 5.2), "black"))
    acc_closed.append(torus("cl_keyring", 0.25, 0.07, (-0.6, -3.95, 5.2), "black", rot=(math.radians(90), 0, 0)))
    for ob in acc_closed:
        ob.name = "ACC_closed_" + ob.name
    closed = join(acc_closed, "ACC_closed")
    sign = food_sign2("dream", coll)
    for ob in sign:
        ob.location = (ob.location.x * 0.8, ob.location.y * 0.8 - 3.95, ob.location.z * 0.8 + 4.5)
        ob.scale = (0.8, 0.8, 0.8)
    acc_open = list(sign)
    for k in range(9):
        acc_open.append(sphere("op_bulb%d" % k, 0.12, (-3.0 + k * 0.75, -4.4, 3.95 - 0.25 * math.sin(k * math.pi / 8)),
                               "EMIT_lamp", seg=6, rings=4))
    for sx in (-1, 1):
        acc_open.append(box("op_fbox%d" % sx, (1.2, 0.4, 0.4), (sx * 2.3, -4.0, 0.0), "darkwood"))
        for k in range(3):
            acc_open.append(sphere("op_fl%d%d" % (sx, k), 0.2, (sx * 2.3 - 0.35 + k * 0.35, -4.0, 0.55),
                                   mat("flower_coral", "coral"), seg=6, rings=4))
    for ob in acc_open:
        apply_xform(ob)
    opened = join(acc_open, "ACC_open")
    for ob in (closed, opened):
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        coll.objects.link(ob)
        ob.parent = root
    return root, dict(kind="restaurant", food="dream", w=meta["w"], d=meta["d"], h=meta["h"])


# ================================================================ catalogue
def catalogue():
    C = [
        ("tower_a", lambda: tower("tower_a", 16, 14, 14, "sky", "cream", 1, "garden")),
        ("tower_b", lambda: tower("tower_b", 18, 16, 20, "blue", "white", 2, "spire")),
        ("tower_c", lambda: tower("tower_c", 14, 14, 10, "mint", "sand", 3, "roof")),
        ("tower_d", lambda: tower("tower_d", 20, 14, 24, "teal", "cream", 4, "roof")),
        ("food_court", food_court),
        ("sculpture", sculpture),
        ("planter_long", planter_long),
        ("panel_a", lambda: panel_block("panel_a", 30, 12, 9, 3, "cream", "mint", 1)),
        ("panel_b", lambda: panel_block("panel_b", 22, 12, 12, 2, "yellow", "coral", 2)),
        ("panel_c", lambda: panel_block("panel_c", 15, 14, 16, 1, "white", "sky", 3, balconies=True)),
        ("panel_d", lambda: panel_block("panel_d", 30, 12, 9, 3, "peach", "sun", 4)),
        ("kiosk_shawarma", lambda: pavilion("kiosk_shawarma", "shawarma", 6.0, 4.0, 3.2, "#f6e2b0", "red")),
        ("kiosk_bakery", lambda: pavilion("kiosk_bakery", "bakery", 6.0, 4.0, 3.2, "#f6d7c2", "coral")),
        ("supermarket", supermarket),
        ("playground", playground),
        ("garages_row", garages_row),
        ("tree_birch", tree_birch),
        ("dumpsters", dumpsters),
        ("bus_stop", bus_stop),
        ("restaurant_dream", dream_restaurant),
    ]
    return C


def main():
    reset()
    std_mats()
    R.setup_render((512, 512))
    R.world()
    R.sun()
    R.ground_plane()
    meta_path = os.path.join(ASSETS, "architecture", "architecture2_meta.json")
    meta_all = json.load(open(meta_path, encoding="utf-8")) if os.path.exists(meta_path) else {}
    built = []
    for name, fn in catalogue():
        if ONLY and name not in ONLY:
            continue
        root, meta = fn()
        meta_all[name] = meta
        saved = scale_lights_for_export(root)
        export_gltf(root, os.path.join(ASSETS, "architecture", name + ".gltf"))
        restore_lights(saved)
        built.append(root)
        print("built", name, meta)
    if not NO_RENDER:
        for root in built:
            kids = [root] + list(root.children_recursive)
            R.isolate(kids)
            R.frame_objects([k for k in kids if k.type == "MESH" and not k.name.endswith("-colonly")], yaw=-30,
                            pitch=18)
            R.mood("day")
            R.render(os.path.join(RENDERS, "previews", "arch2_%s.png" % root.name))
    json.dump(meta_all, open(meta_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    if not ONLY:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, "architecture2.blend"))
    print("DONE")


if __name__ == "__main__":
    main()
