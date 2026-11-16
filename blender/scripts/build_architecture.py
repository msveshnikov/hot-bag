"""Task 1: Old Town architecture for «Горячая сумка».
blender -b --factory-startup -P build_architecture.py -- [--no-render] [--only house_a,clock_tower]
Writes blender/architecture.blend, assets/architecture/<name>.gltf, renders/previews/arch_<name>.png
"""
import bpy
import sys
import os
import math

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
import lib_render as R

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None

FLOOR_H = 3.0
GROUND_H = 3.6

FACADES = {
    "pink": "#f2b3a6", "yellow": "#f5d36b", "mint": "#a9dcc0", "cream": "#f3e3c3", "peach": "#f6bf8f",
    "sky": "#a9d4ee", "lilac": "#c9b6e3", "terracotta": "#e08a5f", "white": "#f5efe4", "sage": "#c4d39a",
}
ACCENTS = ["coral", "turq", "sun", "blue", "green", "darkwood", "red"]


def facade_mat(cname):
    return mat("plaster_" + cname, FACADES[cname], tex="plaster", tile=3)


def accent_mat(c):
    return mat("paint_" + c, c, rough=0.6)


def cut(target, cutter):
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = cutter
    apply_mods(target)
    bpy.data.objects.remove(cutter)


def arch_trim(name, cx, yf, z0, R, coll, r=0.1, m="trim_white", fan=True):
    """Semicircular trim (and glass fanlight) above an opening on a facade facing -Y."""
    pts = [(cx + math.cos(a) * R, yf - 0.08, z0 + math.sin(a) * R)
           for a in [math.pi * k / 12 for k in range(13)]]
    o = [tube_path(name, pts, r, m)]
    if fan:
        semi = [(math.cos(math.pi * k / 12) * (R - 0.12), math.sin(math.pi * k / 12) * (R - 0.12)) for k in range(13)]
        f = prism(name + "_fan", semi, 0.05, (cx, yf - 0.02, z0), "EMIT_window", axis="Y")
        o.append(f)
    for ob in o:
        for c in ob.users_collection:
            c.objects.unlink(ob)
        coll.objects.link(ob)
    return o


def door_panel(name, w, h, m, coll, hinge_left=True):
    """Door with pivot on the hinge (left edge seen from the front), front at -Y."""
    ob = box(name, (w, 0.08, h), (0, 0, 0), m, bevel=0.02, coll=coll)
    # move mesh so hinge is at origin
    off = w / 2 if hinge_left else -w / 2
    for v in ob.data.vertices:
        v.co.x += off
    knob = sphere(name + "_knob", 0.05, (w - 0.15 if hinge_left else -w + 0.15, -0.07, 1.0), "steel", coll=coll)
    j = join([ob, knob], name)
    return j


def window(prefix, x, z, y_front, coll, w=1.1, h=1.5, rs=None, accent=None, flowers=False, shutters=False,
           back=False):
    """Window on the front (y_front, facing -Y) or back face. Returns list of objects."""
    s = -1 if not back else 1
    objs = []
    objs.append(box(prefix + "_frame", (w + 0.24, 0.14, h + 0.24), (x, y_front + s * 0.05, z - 0.12), "trim_white",
                    bevel=0.04, coll=coll))
    objs.append(box(prefix + "_glass", (w, 0.06, h), (x, y_front + s * 0.1, z), "EMIT_window", coll=coll))
    # mullion cross
    objs.append(box(prefix + "_mv", (0.07, 0.05, h), (x, y_front + s * 0.13, z), "trim_white", coll=coll))
    objs.append(box(prefix + "_mh", (w, 0.05, 0.07), (x, y_front + s * 0.13, z + h * 0.62), "trim_white", coll=coll))
    objs.append(box(prefix + "_sill", (w + 0.4, 0.3, 0.12), (x, y_front + s * 0.15, z - 0.16), "trim_white",
                    bevel=0.04, coll=coll))
    if shutters and accent:
        for sx in (-1, 1):
            objs.append(box(prefix + "_sh%d" % sx, (w * 0.5, 0.06, h + 0.1), (x + sx * (w * 0.5 + 0.2),
                                                                                  y_front + s * 0.06, z - 0.05),
                            accent_mat(accent), bevel=0.02, coll=coll))
    if flowers and rs:
        objs.append(box(prefix + "_fbox", (w + 0.2, 0.3, 0.28), (x, y_front + s * 0.28, z - 0.42), "darkwood",
                        bevel=0.04, coll=coll))
        for k in range(4):
            c = rs.choice(["coral", "pink", "sun", "red", "lilac"])
            objs.append(sphere(prefix + "_fl%d" % k, 0.17, (x - w * 0.4 + k * w * 0.27, y_front + s * 0.3, z - 0.08),
                               mat("flower_" + c, c), seg=6, rings=4, coll=coll))
    return objs


def house(name, w=8.0, d=10.0, floors=4, color="pink", roof="gable", ground="plain", doors=1, seed=1,
          accent=None, dormers=True, bay=False):
    """Old Town house. Front faces -Y, base centre at origin.
    ground: plain | cafe | shop. doors: entrances with INT_door / INT_intercom / MARK_door / MARK_plate."""
    rs = rnd(seed)
    coll = collection(name)
    accent = accent or rs.choice(ACCENTS)
    H = GROUND_H + FLOOR_H * (floors - 1)
    fm = facade_mat(color)
    objs = []
    body = box(name + "_body", (w, d, H), (0, 0, 0), fm, bevel=0.18, seg=3, coll=coll)
    yf = -d / 2

    # entrance openings + vestibules
    door_xs = []
    if doors == 1:
        door_xs = [rs.choice([-1, 1]) * (w / 2 - 1.6) if ground != "plain" else 0.0]
    elif doors >= 2:
        door_xs = [-w / 2 + 1.6 + i * (w - 3.2) / (doors - 1) for i in range(doors)]
    dw, dh = 1.3, 2.4
    for i, dx in enumerate(door_xs):
        c = box(name + "_cut%d" % i, (dw, 1.4, dh), (dx, yf, 0.0), None, coll=coll)
        cut(body, c)
    # shop / cafe window opening
    shop_x = None
    if ground in ("cafe", "shop"):
        shop_x = (-door_xs[0] * 0.25) if door_xs else 0.0
        sw = w - 4.2
        c = box(name + "_cutshop", (sw, 1.0, 2.2), (shop_x if abs(shop_x) < 0.01 else -math.copysign(1.0, door_xs[0]) * 0.9,
                                                    yf, 0.6), None, coll=coll)
        shop_center = c.location.x
        cut(body, c)
        objs.append(box(name + "_shopglass", (sw, 0.08, 2.2), (shop_center, yf + 0.35, 0.6), "EMIT_window", coll=coll))
        objs.append(box(name + "_shopin", (sw, 0.6, 2.6), (shop_center, yf + 0.75, 0.3), mat("interior_warm", "#f0c48a"),
                        coll=coll))
        objs.append(box(name + "_shopsill", (sw + 0.3, 0.4, 0.6), (shop_center, yf - 0.05, 0.0), "darkwood", bevel=0.05,
                        coll=coll))
        # striped awning
        n = 7
        aw_c = [accent_mat(accent), mat("awning_white", "white")]
        for k in range(n):
            seg = box(name + "_aw%d" % k, (sw / n + 0.01, 1.6, 0.08),
                      (shop_center - sw / 2 + (k + 0.5) * sw / n, yf - 0.75, 3.05), aw_c[k % 2], coll=coll)
            seg.rotation_euler = (math.radians(-18), 0, 0)
            objs.append(seg)
        objs.append(box(name + "_awfront", (sw + 0.05, 0.08, 0.3), (shop_center, yf - 1.52, 2.55), aw_c[0], coll=coll))
    objs.append(body)

    for i, dx in enumerate(door_xs):
        vest = box(name + "_vest%d" % i, (dw + 0.4, 1.4, dh + 0.3), (dx, yf + 0.7 + 0.2, 0.0),
                   mat("vestibule", "#6b5446"), coll=coll)
        for p in vest.data.polygons:  # flip normals so we see the inside
            p.flip()
        objs.append(vest)
        # frame + arch
        objs.append(box(name + "_dfl%d" % i, (0.2, 0.25, dh + 0.1), (dx - dw / 2 - 0.1, yf - 0.05, 0), "trim_white",
                        bevel=0.04, coll=coll))
        objs.append(box(name + "_dfr%d" % i, (0.2, 0.25, dh + 0.1), (dx + dw / 2 + 0.1, yf - 0.05, 0), "trim_white",
                        bevel=0.04, coll=coll))
        objs += arch_trim(name + "_darch%d" % i, dx, yf, dh, dw / 2 + 0.1, coll)
        objs.append(box(name + "_step%d" % i, (dw + 0.8, 0.7, 0.15), (dx, yf - 0.3, 0), "stone", bevel=0.03, coll=coll))
        dp = door_panel("INT_door_%s_%d" % (name, i), dw, dh, accent_mat(rs.choice(["darkwood", "turq", "coral", "blue",
                                                                                     "green"])), coll)
        dp.location = (dx - dw / 2, yf + 0.12, 0.0)
        objs.append(dp)
        ic = box("INT_intercom_%s_%d" % (name, i), (0.22, 0.08, 0.34), (dx + dw / 2 + 0.45, yf - 0.04, 1.3), "metal",
                 bevel=0.02, coll=coll)
        ic_s = box(name + "_ics%d" % i, (0.14, 0.02, 0.08), (0, -0.05, 0.22), "EMIT_screen", coll=coll)
        ic_s.parent = ic
        objs.append(ic)
        objs.append(ic_s)
        objs.append(empty("MARK_door_%d" % i, (dx, yf - 1.3, 0), 180, coll))
        objs.append(empty("MARK_plate_%d" % i, (dx + dw / 2 + 0.45, yf - 0.1, 2.0), 0, coll))
        # door lamp
        objs.append(cyl(name + "_dlamp%d" % i, 0.13, 0.32, (dx, yf - 0.25, dh + 0.55), "EMIT_lamp", n=8))

    # cornices
    objs.append(box(name + "_corn1", (w + 0.25, d + 0.25, 0.3), (0, 0, GROUND_H - 0.25), "trim_white", bevel=0.08,
                    coll=coll))
    objs.append(box(name + "_corn2", (w + 0.45, d + 0.45, 0.35), (0, 0, H - 0.35), "trim_white", bevel=0.1, coll=coll))
    objs.append(box(name + "_plinth", (w + 0.12, d + 0.12, 0.6), (0, 0, 0), "stone", bevel=0.05, coll=coll))

    # upper windows front + back
    nwin = max(2, int((w - 0.8) / 2.3))
    xs = [-w / 2 + (k + 0.5) * w / nwin for k in range(nwin)]
    shutters = rs.random() < 0.4
    for f in range(1, floors):
        z = GROUND_H + (f - 1) * FLOOR_H + 0.75
        for k, x in enumerate(xs):
            objs += window("%s_w%d_%d" % (name, f, k), x, z, yf, coll, rs=rs, accent=accent,
                           flowers=rs.random() < 0.35, shutters=shutters)
    if bay and floors >= 3:
        # green bay window column on the front (like the art)
        bw = 2.4
        bx = xs[len(xs) // 2]
        bh = (floors - 1) * FLOOR_H - 0.6
        objs.append(box(name + "_bay", (bw, 1.0, bh), (bx, yf - 0.45, GROUND_H + 0.2), accent_mat("mint"), bevel=0.15,
                        seg=3, coll=coll))
        for f in range(1, floors):
            z = GROUND_H + (f - 1) * FLOOR_H + 0.75
            objs.append(box(name + "_bayg%d" % f, (bw - 0.5, 0.06, 1.4), (bx, yf - 0.97, z), "EMIT_window", coll=coll))
        objs.append(pyramid(name + "_bayroof", bw + 0.3, 1.3, 0.7, "roof_slate", (bx, yf - 0.45, GROUND_H + 0.2 + bh)))
    # ground floor windows where no door/shop
    if ground == "plain":
        for k, x in enumerate(xs):
            if all(abs(x - dx) > 1.6 for dx in door_xs):
                objs += window("%s_wg_%d" % (name, k), x, 1.0, yf, coll, rs=rs, accent=accent, flowers=rs.random() < 0.5)

    # roof
    rh = min(w, d) * rs.uniform(0.38, 0.5)
    roof_m = rs.choice(["roof_tiles", "roof_tiles", "roof_tiles_brown", "roof_tiles_dark", "roof_slate"])
    mat("roof_tiles_brown", "#ffd2b4", tex="roof_tiles", tile=2.0)
    mat("roof_tiles_dark", "#b88a80", tex="roof_tiles", tile=2.0)
    if roof == "gable":
        r = gable_roof(name + "_roof", w, d, rh, overhang=0.45, loc=(0, 0, H), coll=coll, m=roof_m)
        # gable end walls
        for sx in (-1, 1):
            g = prism(name + "_gable%d" % sx, [(-d / 2, 0), (d / 2, 0), (0, rh)], 0.3,
                      (sx * (w / 2 - 0.15), 0, H), fm, axis="Y", coll=coll, rot=(0, 0, math.radians(90)))
            objs.append(g)
    else:
        r = hip_roof(name + "_roof", w, d, rh, overhang=0.45, loc=(0, 0, H), coll=coll, m=roof_m)
    objs.append(r)
    if dormers and w >= 7:
        for k in range(max(1, nwin - 2)):
            x = -w / 2 + (k + 1) * w / (nwin - 1) if nwin > 2 else 0
            objs.append(box(name + "_dorm%d" % k, (1.4, 1.6, 1.4), (x, -d / 4, H + 0.1), fm, bevel=0.1, coll=coll))
            objs.append(gable_roof(name + "_dormr%d" % k, 1.4, 1.6, 0.7, overhang=0.15, loc=(x, -d / 4, H + 1.5),
                                   coll=coll))
            objs.append(box(name + "_dormg%d" % k, (0.8, 0.06, 0.8), (x, -d / 4 - 0.82, H + 0.45), "EMIT_window",
                            coll=coll))
    for k in range(rs.randint(1, 2)):
        cx = rs.uniform(-w / 3, w / 3)
        objs.append(box(name + "_chim%d" % k, (0.7, 0.7, rh + 1.2), (cx, d / 5, H), "brick", bevel=0.06, coll=coll))
        objs.append(box(name + "_chimc%d" % k, (0.9, 0.9, 0.18), (cx, d / 5, H + rh + 1.2), "stone", bevel=0.04,
                        coll=coll))

    objs.append(colbox(name, (w + 0.1, d + 0.1, H), (0, 0, 0), coll))
    # cartoon crooked lean on everything above the ground floor
    lean = rs.uniform(-0.45, 0.45)
    for o in objs:
        if o.type == "MESH" and not o.name.endswith("-colonly") and not o.name.startswith("INT_"):
            apply_xform(o)
            for v in o.data.vertices:
                if v.co.z > GROUND_H:
                    t = (v.co.z - GROUND_H) / (H + rh)
                    v.co.x += lean * t * 2
    meta = dict(kind="house", w=w, d=d, floors=floors, h=H, doors=len(door_xs), ground=ground, lift=False)
    root = finish_asset(objs, name, coll)
    root["meta"] = str(meta)
    return root, meta


def clock_tower(name="clock_tower"):
    coll = collection(name)
    objs = []
    objs.append(box(name + "_base", (8, 8, 20), (0, 0, 0), "stone", bevel=0.25, seg=3, coll=coll))
    objs.append(box(name + "_plinth", (8.6, 8.6, 1.2), (0, 0, 0), "stone", bevel=0.1, coll=coll))
    # arched gate on the front
    c = box("cut", (3.2, 2, 4.2), (0, -4, 0), None, coll=coll)
    cut(objs[0], c)
    objs.append(box(name + "_gatein", (3.4, 1.0, 4.4), (0, -3.2, 0), mat("vestibule", "#6b5446"), coll=coll))
    objs += arch_trim(name + "_gatearch", 0.0, -4.0, 4.2, 1.7, coll, r=0.25, m="stone", fan=False)
    objs.append(box(name + "_band", (8.6, 8.6, 0.6), (0, 0, 13.5), "trim_white", bevel=0.1, coll=coll))
    objs.append(box(name + "_upper", (7.4, 7.4, 8), (0, 0, 20), mat("plaster_cream", "cream", tex="plaster", tile=3),
                    bevel=0.25, seg=3, coll=coll))
    objs.append(box(name + "_gallery", (9.0, 9.0, 0.5), (0, 0, 28), "stone", bevel=0.1, coll=coll))
    for i in range(4):
        a = i * math.pi / 2
        dx, dy = math.sin(a), -math.cos(a)
        # clock faces on 4 sides at z=23.5
        face = cyl(name + "_face%d" % i, 2.4, 0.25, (dx * 3.7, dy * 3.7, 23.8), "EMIT_clock", n=32,
                   rot=(math.radians(90), 0, a))
        rim = torus(name + "_rim%d" % i, 2.4, 0.2, (dx * 3.95, dy * 3.95, 23.8), mat("gold", "#e2b23c", rough=0.4,
                                                                                     metal=0.6),
                    rot=(math.radians(90), 0, a))
        objs += [face, rim]
        for k in range(12):
            b = k * math.pi / 6
            px = math.cos(a) * math.cos(b) * 1.95
            py = math.sin(a) * math.cos(b) * 1.95
            objs.append(box(name + "_tick%d_%d" % (i, k), (0.18, 0.1, 0.3),
                            (dx * 4.0 + px, dy * 4.0 + py, 23.8 + math.sin(b) * 1.95 - 0.15), "black", coll=coll))
        if i == 0:
            hh = box("ANIM_clock_hour", (0.22, 0.08, 1.3), (0, 0, 0), "black", coll=coll)
            mh = box("ANIM_clock_minute", (0.16, 0.08, 1.9), (0, 0, 0), "black", coll=coll)
            hh.location = (0, -4.15, 23.8)
            mh.location = (0, -4.22, 23.8)
            mh.rotation_euler = (0, math.radians(120), 0)
            objs += [hh, mh]
    # windows on the upper stage
    for i in range(4):
        a = i * math.pi / 2
        for s in (-1, 1):
            x = math.cos(a) * s * 2.2 + math.sin(a) * 3.75
            y = math.sin(a) * s * 2.2 - math.cos(a) * 3.75
            w = box(name + "_uw%d%d" % (i, s), (1.0, 0.1, 1.8), (x, y, 20.8), "EMIT_window", coll=coll)
            w.rotation_euler = (0, 0, a)
            objs.append(w)
    # roof: steep pyramid + corner spires + golden ball
    objs.append(pyramid(name + "_roof", 9.4, 9.4, 11, "roof_slate", (0, 0, 28.5)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            objs.append(cyl(name + "_turret%d%d" % (sx, sy), 0.9, 3.0, (sx * 4.2, sy * 4.2, 28.5), "stone", n=10))
            objs.append(cyl(name + "_spire%d%d" % (sx, sy), 1.1, 4.0, (sx * 4.2, sy * 4.2, 31.5), "roof_slate", n=10,
                            r2=0.02))
            objs.append(sphere(name + "_ball%d%d" % (sx, sy), 0.25, (sx * 4.2, sy * 4.2, 35.6), "gold", seg=8, rings=6))
    objs.append(sphere(name + "_topball", 0.55, (0, 0, 39.8), "gold", seg=12, rings=8))
    objs.append(cyl(name + "_mast", 0.08, 2.0, (0, 0, 39.5), "gold", n=6))
    # red banners
    for s in (-1, 1):
        objs.append(box(name + "_banner%d" % s, (1.0, 0.08, 2.6), (s * 2.6, -4.12, 15.0), mat("paint_red", "red"),
                        coll=coll))
        objs.append(cyl(name + "_bannerpole%d" % s, 0.06, 1.3, (s * 2.6, -4.2, 17.6), "gold", n=6,
                        rot=(0, math.radians(90), 0)))
    objs.append(empty("MARK_tourist_spot", (0, -8, 0), 180, coll))
    objs.append(colbox(name, (8.6, 8.6, 30), (0, 0, 0), coll))
    root = finish_asset(objs, name, coll)
    return root, dict(kind="landmark", w=8.6, d=8.6, h=40)


# ---------------------------------------------------------------- restaurants
def food_sign(kind, coll):
    """Food-shaped sign, ~1.6 m, centred at origin, front -Y. Emissive material EMIT_sign_<kind>."""
    o = []
    if kind == "pizza":
        crust = mat("EMIT_sign_pizza_crust", "#e7b56a", emit="#ffcf7a", emit_strength=0)
        top = mat("EMIT_sign_pizza", "#f2c240", emit="#ffd34f", emit_strength=0)
        pep = mat("pepperoni", "#c8402f")
        o.append(prism("sg_slice", [(-0.9, 0.9), (0.9, 0.9), (0, -0.8)], 0.22, (0, 0, 0), top, axis="Y"))
        o.append(cyl("sg_crust", 0.18, 2.0, (-1.0, 0, 0.92), crust, n=10, rot=(0, math.radians(90), 0)))
        for (x, z) in ((-0.35, 0.45), (0.3, 0.5), (0.0, 0.0)):
            o.append(cyl("sg_pep", 0.18, 0.06, (x, -0.13, z), pep, n=12, rot=(math.radians(90), 0, 0)))
        for ob in o:
            ob.location.z += 0.8
    elif kind == "burger":
        bun = mat("EMIT_sign_burger", "#e09a45", emit="#ffb14f", emit_strength=0)
        o.append(cyl("sg_bb", 0.85, 0.3, (0, 0, 0.2), bun, n=20))
        o.append(cyl("sg_pat", 0.9, 0.28, (0, 0, 0.5), mat("patty", "#6b3a22"), n=20))
        o.append(cyl("sg_let", 0.95, 0.1, (0, 0, 0.78), mat("lettuce", "#7ccf4a"), n=14))
        o.append(box("sg_cheese", (1.6, 1.6, 0.06), (0, 0, 0.78), mat("cheese", "#f6cc3a"), rot=(0, 0, math.radians(45))))
        o.append(sphere("sg_tb", 0.88, (0, 0, 0.85), bun, scale=(1, 1, 0.6)))
        for k in range(6):
            a = k * 1.05
            o.append(sphere("sg_ses", 0.06, (math.cos(a) * 0.45, math.sin(a) * 0.45 - 0.1, 1.33), "white", seg=6, rings=4))
    elif kind == "sushi":
        nori = mat("nori", "#24392e")
        rice = mat("EMIT_sign_sushi", "#f7f3ea", emit="#fff6e0", emit_strength=0)
        for s, x in ((0, -0.6), (1, 0.6)):
            o.append(cyl("sg_n%d" % s, 0.55, 0.6, (x, 0.3, 0.8), nori, n=18, rot=(math.radians(90), 0, 0)))
            o.append(cyl("sg_r%d" % s, 0.45, 0.62, (x, 0.31, 0.8), rice, n=18, rot=(math.radians(90), 0, 0)))
            o.append(cyl("sg_f%d" % s, 0.2, 0.64, (x, 0.32, 0.8), mat("salmon", "#f27b4a"), n=10,
                         rot=(math.radians(90), 0, 0)))
    elif kind == "coffee":
        cup = mat("EMIT_sign_coffee", "#fbf7ef", emit="#fff7e6", emit_strength=0)
        o.append(cyl("sg_cup", 0.62, 1.1, (0, 0, 0.15), cup, n=20, r2=0.75))
        o.append(cyl("sg_cof", 0.7, 0.05, (0, 0, 1.22), mat("coffee", "#6b3f25"), n=20))
        o.append(torus("sg_handle", 0.32, 0.09, (0.78, 0, 0.75), cup, rot=(math.radians(90), 0, 0)))
        o.append(cyl("sg_saucer", 1.0, 0.12, (0, 0, 0.05), cup, n=24))
        for k in range(3):
            o.append(sphere("sg_steam%d" % k, 0.2 - k * 0.03, (math.sin(k * 2) * 0.2, 0, 1.55 + k * 0.35), "white", seg=8,
                            rings=6))
    elif kind == "cake":
        sp = mat("EMIT_sign_cake", "#f6a9c0", emit="#ff8fb5", emit_strength=0)
        cr = mat("cream_icing", "#fff3e6")
        o.append(cyl("sg_l1", 0.9, 0.55, (0, 0, 0.0), sp, n=24))
        o.append(cyl("sg_i1", 0.92, 0.12, (0, 0, 0.55), cr, n=24))
        o.append(cyl("sg_l2", 0.65, 0.45, (0, 0, 0.67), sp, n=24))
        o.append(cyl("sg_i2", 0.67, 0.1, (0, 0, 1.12), cr, n=24))
        o.append(sphere("sg_berry", 0.24, (0, 0, 1.38), mat("berry", "#e2313b"), scale=(1, 1, 1.2)))
        o.append(cyl("sg_candle", 0.05, 0.35, (0.3, 0, 1.2), "sun", n=6))
    for ob in o:
        ob.name = "%s_%s" % (kind, ob.name)
        for c in ob.users_collection:
            c.objects.unlink(ob)
        coll.objects.link(ob)
    return o


REST_COLORS = {"pizza": ("peach", "red"), "burger": ("yellow", "coral"), "sushi": ("white", "darkwood"),
               "coffee": ("cream", "turq"), "cake": ("pink", "coral")}


def restaurant(kind):
    name = "restaurant_" + kind
    coll = collection(name)
    fcol, acc = REST_COLORS[kind]
    w, d, h = 6.6, 7.0, 4.4
    fm = facade_mat(fcol)
    objs = []
    body = box(name + "_body", (w, d, h), (0, 0, 0), fm, bevel=0.15, seg=3, coll=coll)
    # big pickup window opening + door
    cut(body, box("c1", (3.4, 1.2, 2.0), (-0.9, -d / 2, 0.9), None, coll=coll))
    cut(body, box("c2", (1.2, 1.2, 2.4), (2.2, -d / 2, 0.0), None, coll=coll))
    objs.append(body)
    objs.append(box(name + "_inside", (6.0, 3.0, 3.4), (0, -d / 2 + 2.0, 0.0), mat("interior_warm", "#f0c48a"),
                    coll=coll))
    for p in objs[-1].data.polygons:
        p.flip()
    objs.append(box(name + "_kitchen", (3.2, 0.6, 1.4), (-0.9, -d / 2 + 2.6, 0.0), "steel", coll=coll))
    # pickup counter (interactive)
    ctr = box("INT_counter_" + kind, (3.6, 0.7, 0.18), (-0.9, -d / 2 - 0.05, 0.9), "darkwood", bevel=0.04, coll=coll)
    objs.append(ctr)
    objs.append(box(name + "_ctrbase", (3.6, 0.3, 0.9), (-0.9, -d / 2 + 0.2, 0.0), accent_mat(acc), bevel=0.04,
                    coll=coll))
    # paper bags waiting on the counter
    for k in range(2):
        objs.append(box(name + "_bag%d" % k, (0.32, 0.22, 0.42), (-1.8 + k * 0.5, -d / 2 - 0.05, 1.08),
                        mat("paper", "#d9b384"), bevel=0.02, coll=coll))
    dp = door_panel("INT_door_" + name, 1.2, 2.4, accent_mat(acc), coll)
    dp.location = (2.2 - 0.6, -d / 2 + 0.15, 0)
    objs.append(dp)
    # glass above pickup window
    objs.append(box(name + "_transom", (3.4, 0.06, 0.6), (-0.9, -d / 2 + 0.1, 2.9), "EMIT_window", coll=coll))
    # striped awning
    n = 8
    sw = w - 0.4
    for k in range(n):
        seg = box(name + "_aw%d" % k, (sw / n + 0.01, 1.4, 0.08), (-sw / 2 + (k + 0.5) * sw / n, -d / 2 - 0.65, 3.55),
                  [accent_mat(acc), mat("awning_white", "white")][k % 2], coll=coll)
        seg.rotation_euler = (math.radians(-20), 0, 0)
        objs.append(seg)
    objs.append(box(name + "_awf", (sw + 0.05, 0.08, 0.3), (0, -d / 2 - 1.32, 3.05), accent_mat(acc), coll=coll))
    # roof with tiles
    objs.append(gable_roof(name + "_roof", w, d, 2.0, overhang=0.35, loc=(0, 0, h), coll=coll))
    for sx in (-1, 1):
        objs.append(prism(name + "_gable%d" % sx, [(-d / 2, 0), (d / 2, 0), (0, 2.0)], 0.3, (sx * (w / 2 - 0.15), 0, h),
                          fm, axis="Y", coll=coll, rot=(0, 0, math.radians(90))))
    objs.append(box(name + "_cornice", (w + 0.3, d + 0.3, 0.3), (0, 0, h - 0.3), "trim_white", bevel=0.08, coll=coll))
    # sign board + food sign
    objs.append(box(name + "_board", (3.2, 0.25, 2.2), (0, -d / 2 - 0.2, h - 0.2), accent_mat(acc), bevel=0.2, seg=3,
                    coll=coll))
    sign = food_sign(kind, coll)
    for ob in sign:
        ob.location = (ob.location.x * 0.8, ob.location.y * 0.8 - d / 2 - 0.55, ob.location.z * 0.8 + h + 0.1)
        ob.scale = (0.8, 0.8, 0.8)
    objs += sign
    # menu board
    objs.append(box(name + "_menu", (0.7, 0.08, 1.0), (2.8, -d / 2 - 0.9, 0.3), "black", bevel=0.03, coll=coll,
                    rot=(math.radians(-10), 0, 0)))
    objs.append(empty("MARK_pickup_" + kind, (-0.9, -d / 2 - 1.2, 0), 180, coll))
    objs.append(empty("MARK_cook_" + kind, (-0.9, -d / 2 + 0.9, 0), 0, coll))
    objs.append(empty("MARK_parking_" + kind, (2.6, -d / 2 - 2.6, 0), 90, coll))
    objs.append(point_light("LIGHT_" + name, (-0.9, -d / 2 - 0.4, 3.0), 60, coll=coll))
    objs.append(colbox(name, (w, d, h + 1.5), (0, 0, 0), coll))
    root = finish_asset(objs, name, coll)
    return root, dict(kind="restaurant", food=kind, w=w, d=d, h=h)


# ---------------------------------------------------------------- base, shops, misc
def courier_cafe(name="courier_cafe"):
    coll = collection(name)
    objs = []
    w, d, h = 7.0, 5.0, 3.6
    fm = facade_mat("mint")
    body = box(name + "_body", (w, d, h), (0, 0, 0), fm, bevel=0.15, coll=coll)
    cut(body, box("c", (4.4, 1.0, 1.6), (-0.8, -d / 2, 1.0), None, coll=coll))
    objs.append(body)
    objs.append(box(name + "_in", (4.6, 1.6, 2.4), (-0.8, -d / 2 + 0.9, 0.6), mat("interior_warm", "#f0c48a"), coll=coll))
    objs.append(box("INT_counter_cafe", (4.6, 0.6, 0.15), (-0.8, -d / 2 - 0.05, 1.0), "darkwood", coll=coll))
    objs.append(box(name + "_coffee", (0.6, 0.4, 0.6), (-2.2, -d / 2 + 0.5, 1.0), "steel", coll=coll))
    for k in range(10):
        seg = box(name + "_aw%d" % k, (w / 10 + 0.01, 1.6, 0.08), (-w / 2 + (k + 0.5) * w / 10, -d / 2 - 0.75, 3.1),
                  [accent_mat("turq"), mat("awning_white", "white")][k % 2], coll=coll)
        seg.rotation_euler = (math.radians(-18), 0, 0)
        objs.append(seg)
    objs.append(box(name + "_roof", (w + 0.4, d + 0.4, 0.4), (0, 0, h), "trim_white", bevel=0.12, coll=coll))
    objs.append(box(name + "_sign", (2.6, 0.2, 0.9), (0, -d / 2 - 0.12, h + 0.2), mat("EMIT_neon_teal", "#7fe3dc",
                                                                                      emit="#38e0d0",
                                                                                      emit_strength=0.0),
                    bevel=0.12, coll=coll))
    # steaming cup on the sign
    objs.append(cyl(name + "_signcup", 0.3, 0.5, (0, -d / 2 - 0.3, h + 0.4), "white", n=12))
    objs.append(empty("MARK_mentor", (2.4, -d / 2 - 2.2, 0), 200, coll))
    objs.append(empty("MARK_shop_cafe", (-0.8, -d / 2 - 1.1, 0), 180, coll))
    objs.append(colbox(name, (w, d, h), (0, 0, 0), coll))
    root = finish_asset(objs, name, coll)
    return root, dict(kind="shop", w=w, d=d, h=h)


def garage(name="garage"):
    coll = collection(name)
    objs = []
    w, d, h = 8.0, 8.0, 4.8
    body = box(name + "_body", (w, d, h), (0, 0, 0), "brick", bevel=0.15, coll=coll)
    cut(body, box("c", (4.6, 1.2, 3.4), (-1.0, -d / 2, 0.0), None, coll=coll))
    objs.append(body)
    objs.append(box(name + "_in", (4.8, 3.0, 3.6), (-1.0, -d / 2 + 1.6, 0.0), mat("garage_in", "#8c8f94"), coll=coll))
    for p in objs[-1].data.polygons:
        p.flip()
    # half-open roll-up door with stripes
    for k in range(5):
        objs.append(box(name + "_roll%d" % k, (4.6, 0.12, 0.28), (-1.0, -d / 2 + 0.1, 2.0 + k * 0.28),
                        [mat("paint_yellow", "yellow"), mat("paint_dark", "dark")][k % 2], coll=coll))
    objs.append(box("INT_shop_garage", (2.0, 0.8, 1.0), (-2.0, -d / 2 + 1.2, 0.0), "metal", bevel=0.05, coll=coll))
    # tire stack + toolboard
    for k in range(3):
        objs.append(torus(name + "_tire%d" % k, 0.38, 0.15, (2.4, -d / 2 - 0.6, 0.15 + k * 0.3), "black"))
    objs.append(box(name + "_tools", (2.0, 0.1, 1.2), (-1.0, -d / 2 + 3.0, 1.5), "wood", coll=coll))
    objs.append(box(name + "_sign", (3.6, 0.25, 1.0), (-1.0, -d / 2 - 0.15, 3.7), accent_mat("blue"), bevel=0.15, coll=coll))
    objs.append(torus(name + "_signwheel", 0.35, 0.1, (-1.0, -d / 2 - 0.35, 4.2), "white", rot=(math.radians(90), 0, 0)))
    objs.append(box(name + "_roof", (w + 0.4, d + 0.4, 0.4), (0, 0, h), "trim_white", bevel=0.12, coll=coll))
    objs.append(empty("MARK_shop_garage", (-1.0, -d / 2 - 1.6, 0), 180, coll))
    objs.append(colbox(name + "_l", (w / 2 - 3.3 + 1.0, d, h), (-w / 2 + (w / 2 - 3.3 + 1.0) / 2 - 0.0, 0, 0), coll))
    objs.append(colbox(name + "_r", (w / 2 - 1.3, d, h), (w / 2 - (w / 2 - 1.3) / 2, 0, 0), coll))
    objs.append(colbox(name + "_b", (w, d - 3.2, h), (0, 1.6, 0), coll))
    root = finish_asset(objs, name, coll)
    return root, dict(kind="shop", w=w, d=d, h=h)


def kiosk(name="snack_kiosk"):
    coll = collection(name)
    objs = []
    objs.append(box(name + "_body", (3.0, 2.4, 2.6), (0, 0, 0), accent_mat("sun"), bevel=0.2, seg=3, coll=coll))
    cut(objs[0], box("c", (2.2, 1.0, 1.0), (0, -1.2, 1.1), None, coll=coll))
    objs.append(box(name + "_in", (2.4, 1.0, 1.4), (0, -0.6, 0.9), mat("interior_warm", "#f0c48a"), coll=coll))
    objs.append(box("INT_shop_kiosk", (2.4, 0.5, 0.12), (0, -1.25, 1.05), "darkwood", coll=coll))
    objs.append(cyl(name + "_roof", 2.2, 0.5, (0, 0, 2.6), accent_mat("coral"), n=20, r2=0.3))
    objs.append(sphere(name + "_donut_sign", 0.45, (0, -0.4, 3.4), mat("EMIT_neon_pink", "#ff8fb0", emit="#ff6f9d",
                                                                        emit_strength=0.0), scale=(1, 0.5, 1)))
    objs.append(empty("MARK_shop_kiosk", (0, -2.2, 0), 180, coll))
    objs.append(colbox(name, (3.0, 2.4, 2.6), (0, 0, 0), coll))
    return finish_asset(objs, name, coll), dict(kind="shop", w=3, d=2.4, h=3.5)


def police_booth(name="police_booth"):
    coll = collection(name)
    objs = []
    objs.append(box(name + "_body", (2.4, 2.4, 2.8), (0, 0, 0), mat("paint_white", "white"), bevel=0.2, seg=3, coll=coll))
    objs.append(box(name + "_band", (2.45, 2.45, 0.4), (0, 0, 1.6), accent_mat("blue"), coll=coll))
    objs.append(box(name + "_win", (1.6, 0.06, 0.8), (0, -1.24, 1.9), "EMIT_window", coll=coll))
    objs.append(box(name + "_roof", (2.8, 2.8, 0.25), (0, 0, 2.8), accent_mat("blue"), bevel=0.08, coll=coll))
    objs.append(cyl(name + "_light", 0.22, 0.4, (0, 0, 3.05), mat("EMIT_police", "#5d8bff", emit="#4a7dff",
                                                                   emit_strength=0.0), n=10))
    objs.append(empty("MARK_police", (0, -2.0, 0), 180, coll))
    objs.append(colbox(name, (2.4, 2.4, 2.8), (0, 0, 0), coll))
    return finish_asset(objs, name, coll), dict(kind="booth", w=2.4, d=2.4, h=3.4)


def bridge_stub(name="bridge_stub"):
    """Stone arch bridge section 10 m wide, 26 m long along +Y, deck at z=0, water below at z=-3."""
    coll = collection(name)
    objs = []
    L, W = 26.0, 10.0
    objs.append(box(name + "_deck", (W, L, 1.2), (0, L / 2, -1.2), "stone", bevel=0.1, coll=coll))
    objs.append(box(name + "_road", (W - 1.6, L, 0.06), (0, L / 2, 0.0), "cobble", coll=coll))
    for s in (-1, 1):
        objs.append(box(name + "_par%d" % s, (0.6, L, 1.0), (s * (W / 2 - 0.3), L / 2, 0.0), "stone", bevel=0.1,
                        coll=coll))
        for k in range(6):
            objs.append(sphere(name + "_ball%d%d" % (s, k), 0.32, (s * (W / 2 - 0.3), 1 + k * 4.8, 1.25), "stone", seg=8,
                               rings=6))
    # arch underneath
    objs.append(box(name + "_pier", (W, 3.0, 4.0), (0, 13.0, -5.0), "stone", bevel=0.2, coll=coll))
    # barrier "road works" across the bridge at y=6
    for k in range(5):
        objs.append(box(name + "_bar%d" % k, (1.8, 0.2, 0.3), (-3.6 + k * 1.8, 6.0, 0.8),
                        [mat("paint_red", "red"), mat("paint_white", "white")][k % 2], coll=coll))
    for k in range(4):
        objs.append(box(name + "_leg%d" % k, (0.15, 0.4, 0.8), (-4.0 + k * 2.65, 6.0, 0.0), "metal", coll=coll))
    objs.append(colbox(name + "_block", (W, 0.6, 2.0), (0, 6.0, 0.0), coll))
    objs.append(colbox(name + "_parl", (0.6, L, 1.0), (-(W / 2 - 0.3), L / 2, 0), coll))
    objs.append(colbox(name + "_parr", (0.6, L, 1.0), ((W / 2 - 0.3), L / 2, 0), coll))
    objs.append(colbox(name + "_floor", (W, L, 1.2), (0, L / 2, -1.2), coll))
    return finish_asset(objs, name, coll), dict(kind="bridge", w=W, d=L, h=1)


def parapet(name="parapet"):
    """4 m embankment parapet segment along X, front -Y (the water side is +Y)."""
    coll = collection(name)
    objs = [box(name + "_wall", (4.0, 0.6, 0.9), (0, 0, 0), "stone", bevel=0.08, coll=coll),
            box(name + "_cap", (4.0, 0.8, 0.15), (0, 0, 0.9), "stone", bevel=0.05, coll=coll),
            box(name + "_post", (0.8, 0.8, 1.3), (-1.6, 0, 0), "stone", bevel=0.12, coll=coll),
            sphere(name + "_postball", 0.38, (-1.6, 0, 1.6), "stone", seg=10, rings=8)]
    # iron railing between posts
    objs.append(tube_path(name + "_rail", [(-1.2, 0, 1.25), (2.0, 0, 1.25)], 0.04, "black"))
    for k in range(5):
        objs.append(cyl(name + "_bal%d" % k, 0.03, 0.3, (-0.9 + k * 0.7, 0, 1.0), "black", n=6))
    objs.append(colbox(name, (4.0, 0.8, 1.3), (0, 0, 0), coll))
    return finish_asset(objs, name, coll), dict(kind="wall", w=4, d=0.8, h=1.3)


def stairs_wide(name="stairs_wide", width=5.0, rise=3.0, steps=12):
    """Embankment stairs going DOWN toward +Y: top edge at y=0 z=0, bottom at y=run z=-rise."""
    coll = collection(name)
    objs = []
    run = steps * 0.4
    for i in range(steps):
        objs.append(box(name + "_s%d" % i, (width, 0.4 + 0.02, rise - i * rise / steps),
                        (0, 0.2 + i * 0.4, -rise), "stone", bevel=0.03, coll=coll))
    for s in (-1, 1):
        objs.append(prism(name + "_cheek%d" % s, [(0, 0), (run, -rise), (run, -rise - 0.0), (0, -rise), ], 0.01,
                          (0, 0, 0), "stone", axis="Y") if False else None)
        objs.append(box(name + "_side%d" % s, (0.5, run, 0.9), (s * (width / 2 + 0.25), run / 2, -rise + 0.0), "stone",
                        bevel=0.06, coll=coll))
    # ramp collision so characters/vehicles slide up smoothly (a rotated thin box)
    ang = math.atan2(rise, run)
    ramp = colbox(name + "_ramp", (width, math.hypot(run, rise), 0.2), (0, run / 2, -rise / 2 - 0.1), coll)
    ramp.rotation_euler = (-ang, 0, 0)
    for o in ramp.data.vertices:
        o.co.z -= 0.1
    objs.append(ramp)
    objs.append(empty("MARK_stairs_top", (0, -0.5, 0), 0, coll))
    objs.append(empty("MARK_stairs_bottom", (0, run + 0.5, -rise), 180, coll))
    return finish_asset(objs, name, coll), dict(kind="stairs", w=width, d=run, h=rise)


def quay_wall(name="quay_wall", length=8.0, height=3.0):
    coll = collection(name)
    objs = [box(name + "_w", (length, 1.0, height), (0, 0, -height), "stone", bevel=0.1, coll=coll)]
    objs.append(colbox(name, (length, 1.0, height), (0, 0, -height), coll))
    return finish_asset(objs, name, coll), dict(kind="wall", w=length, d=1, h=height)


# ---------------------------------------------------------------- catalogue
def catalogue():
    C = []
    # 12 houses: (name, w, d, floors, colour, roof, ground, doors, seed, bay)
    H = [
        ("house_a", 8, 10, 4, "pink", "gable", "plain", 1, 1, False),
        ("house_b", 7, 10, 5, "yellow", "gable", "plain", 1, 2, False),
        ("house_c", 9, 10, 4, "mint", "hip", "plain", 2, 3, True),
        ("house_d", 8, 11, 6, "cream", "gable", "cafe", 1, 4, False),
        ("house_e", 10, 10, 4, "peach", "hip", "plain", 2, 5, False),
        ("house_f", 7, 9, 5, "sky", "gable", "plain", 1, 6, True),
        ("house_g", 8, 10, 4, "lilac", "gable", "shop", 1, 7, False),
        ("house_h", 9, 11, 5, "terracotta", "hip", "plain", 2, 8, False),
        ("house_i", 7, 10, 4, "white", "gable", "plain", 1, 9, False),
        ("house_j", 8, 10, 6, "sage", "gable", "plain", 1, 10, True),
        ("house_k", 10, 11, 5, "yellow", "hip", "cafe", 2, 11, False),
        ("house_l", 8, 10, 4, "pink", "hip", "plain", 1, 12, False),
    ]
    for (n, w, d, f, c, r, g, dn, s, bay) in H:
        C.append((n, (lambda n=n, w=w, d=d, f=f, c=c, r=r, g=g, dn=dn, s=s, bay=bay:
                      house(n, w, d, f, c, r, g, dn, s, bay=bay))))
    C.append(("clock_tower", clock_tower))
    for k in ("pizza", "burger", "sushi", "coffee", "cake"):
        C.append(("restaurant_" + k, (lambda k=k: restaurant(k))))
    C += [("courier_cafe", courier_cafe), ("garage", garage), ("snack_kiosk", kiosk), ("police_booth", police_booth),
          ("bridge_stub", bridge_stub), ("parapet", parapet), ("stairs_wide", stairs_wide), ("quay_wall", quay_wall)]
    return C


def main():
    import json
    reset()
    std_mats()
    R.setup_render((512, 512))
    R.world()
    R.sun()
    R.ground_plane()
    cat = catalogue()
    meta_all = {}
    meta_path = os.path.join(ASSETS, "architecture", "architecture_meta.json")
    if os.path.exists(meta_path):
        meta_all = json.load(open(meta_path, encoding="utf-8"))
    x = 0.0
    built = []
    for name, fn in cat:
        if ONLY and name not in ONLY:
            continue
        root, meta = fn()
        meta_all[name] = meta
        saved = scale_lights_for_export(root)
        export_gltf(root, os.path.join(ASSETS, "architecture", name + ".gltf"))
        restore_lights(saved)
        built.append(root)
        print("built", name)
    if not NO_RENDER:
        for root in built:
            kids = [root] + list(root.children_recursive)
            R.isolate(kids)
            R.frame_objects([k for k in kids if k.type == "MESH"], yaw=-30, pitch=18)
            R.mood("day")
            R.render(os.path.join(RENDERS, "previews", "arch_%s.png" % root.name))
        # night check on the first few
        for root in built[:3]:
            kids = [root] + list(root.children_recursive)
            R.isolate(kids)
            R.frame_objects([k for k in kids if k.type == "MESH"], yaw=-30, pitch=18)
            R.mood("night")
            R.render(os.path.join(RENDERS, "previews", "arch_%s_night.png" % root.name))
    json.dump(meta_all, open(meta_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, "architecture.blend"))
    print("DONE")


if __name__ == "__main__":
    main()
