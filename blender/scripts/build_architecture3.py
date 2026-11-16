"""Run 3 architecture: «Гастроквартал и Большой парк» — the covered market, four new restaurants, the park bandstand,
the park gate. Concept: concept/locations/gastro_quarter_winter.png.
blender -b --factory-startup -P build_architecture3.py -- [--no-render] [--only market_hall]
Writes blender/architecture3.blend, assets/architecture/<name>.gltf, assets/architecture/architecture3_meta.json,
renders/previews/arch3_<name>.png. Conventions as in Task 1 (front -Y, pivot = base centre, MARK_/INT_ prefixes).
"""
import bpy
import sys
import os
import math
import json

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
import lib_render as R
from build_architecture import cut, accent_mat, restaurant, REST_COLORS
from build_architecture2 import relink, emit_mat

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None


# ---------------------------------------------------------------- food signs for the new restaurants
def food_sign3(kind, coll):
    o = []
    if kind == "dumplings":
        dough = emit_mat("EMIT_sign_dumplings", "#f6e7c8", "#fff1cf")
        o.append(cyl("sg_plate", 1.0, 0.12, (0, 0, 0.2), mat("plate_blue", "#4f7fc0"), n=24))
        for k, (x, z) in enumerate(((-0.45, 0.45), (0.45, 0.45), (0, 0.75))):
            o.append(sphere("sg_dump%d" % k, 0.42, (x, 0, z), dough, seg=14, rings=8, scale=(1.2, 0.8, 0.7)))
            o.append(torus("sg_pleat%d" % k, 0.3, 0.06, (x, 0, z + 0.2), dough, rot=(0, math.radians(90), 0)))
        for k in range(3):
            o.append(sphere("sg_steam%d" % k, 0.16 - k * 0.03, (0.2 * math.sin(k * 2), 0, 1.35 + k * 0.3), "white",
                            seg=8, rings=6))
    elif kind == "ramen":
        bowl = emit_mat("EMIT_sign_ramen", "#e2493b", "#ff6a4f")
        o.append(sphere("sg_bowl", 0.95, (0, 0, 0.7), bowl, seg=20, rings=10, scale=(1, 1, 0.6)))
        o.append(cyl("sg_broth", 0.88, 0.06, (0, 0, 1.0), mat("broth", "#e8a948"), n=20))
        o.append(sphere("sg_egg", 0.24, (0.35, -0.1, 1.08), mat("egg_white", "#fbf6ea"), seg=10, rings=6,
                        scale=(1, 1, 0.5)))
        o.append(sphere("sg_yolk", 0.12, (0.35, -0.14, 1.13), mat("yolk", "#f6a623"), seg=8, rings=6, scale=(1, 1, 0.5)))
        o.append(box("sg_nori", (0.35, 0.05, 0.5), (-0.45, 0.3, 0.95), mat("nori", "#24392e"), rot=(0, 0.2, 0)))
        for sx in (-1, 1):
            o.append(cyl("sg_chop%d" % sx, 0.035, 1.7, (sx * 0.12 + 0.2, 0.2, 0.95), "wood", n=6,
                         rot=(math.radians(-30), math.radians(25 + sx * 6), 0)))
    elif kind == "grill":
        fire = emit_mat("EMIT_sign_grill", "#f6a623", "#ff8a2a")
        o.append(box("sg_steak", (1.6, 0.25, 1.0), (0, 0, 0.3), mat("steak", "#8a3f22"), bevel=0.3, seg=3))
        for k in range(3):
            o.append(box("sg_mark%d" % k, (1.3, 0.05, 0.08), (0, -0.14, 0.55 + k * 0.25), mat("grill_mark", "#3a1c10"),
                         rot=(0, math.radians(20), 0)))
        for k, x in enumerate((-0.5, 0.0, 0.5)):
            o.append(sphere("sg_flame%d" % k, 0.3 - abs(x) * 0.15, (x, 0.1, 1.45 - abs(x) * 0.3), fire, seg=10, rings=8,
                            scale=(0.8, 0.6, 1.6)))
    elif kind == "pancakes":
        cake = emit_mat("EMIT_sign_pancakes", "#e9b45e", "#ffc76a")
        o.append(cyl("sg_plate", 1.0, 0.1, (0, 0, 0.1), "white", n=24))
        for k in range(4):
            o.append(cyl("sg_pc%d" % k, 0.8 - k * 0.02, 0.18, (0, 0, 0.2 + k * 0.2), cake, n=24))
        o.append(cyl("sg_syrup", 0.62, 0.06, (0, 0, 1.0), mat("syrup", "#b5651d"), n=20))
        o.append(box("sg_butter", (0.32, 0.32, 0.18), (0, 0, 1.04), mat("butter", "#f8e27a"), bevel=0.04))
        for k in range(3):
            o.append(sphere("sg_berry%d" % k, 0.13, (-0.45 + k * 0.45, -0.4, 1.0), mat("berry", "#e2313b"), seg=8, rings=6))
    for ob in o:
        ob.name = "%s_%s" % (kind, ob.name)
    return relink(o, coll)


REST3 = {"dumplings": ("cream", "blue"), "ramen": ("terracotta", "red"), "grill": ("yellow", "darkwood"),
         "pancakes": ("pink", "sun")}


def restaurant3(kind):
    """Task 1 restaurant shell (counter, awning, MARK_pickup/cook/parking) with a run 3 food sign."""
    REST_COLORS[kind] = REST3[kind]
    root, meta = restaurant(kind)
    coll = root.users_collection[0]
    d, h = 7.0, 4.4
    sign = food_sign3(kind, coll)
    for ob in sign:
        ob.location = (ob.location.x * 0.8, ob.location.y * 0.8 - d / 2 - 0.55, ob.location.z * 0.8 + h + 0.1)
        ob.scale = (0.8, 0.8, 0.8)
    # string of lights along the awning (winter garland look from the concept)
    bulbs = [sphere("gl_bulb%d" % k, 0.1, (-3.0 + k * 0.75, -d / 2 - 1.45, 3.0 - 0.2 * math.sin(k * math.pi / 8)),
                    "EMIT_lamp", seg=6, rings=4) for k in range(9)]
    relink(bulbs, coll)
    g = join(sign + bulbs, "restaurant_%s_sign" % kind)
    g.parent = root
    return root, meta


# ---------------------------------------------------------------- the covered market
MARKET_STALLS = [("veg", "green", "Овощи"), ("fish", "blue", "Рыба"), ("cheese", "sun", "Сыр")]


def market_hall(name="market_hall"):
    """Covered market: brick end walls, iron ribs and a glass barrel roof, three open stalls along the front (-Y)
    with pickups MARK_pickup_veg/fish/cheese, crates of produce, lamps and a garland."""
    coll = collection(name)
    o = []
    W, D, Hw = 30.0, 16.0, 5.0
    iron = mat("iron_green", "#2f4a43", rough=0.45, metal=0.5)
    glass = mat("market_glass", "#bfe3ef", rough=0.08, alpha=0.45)
    brick = mat("market_brick", "#c4664a", tex="plaster", tile=3)
    floor = mat("market_floor", "#d8cdb8", tex="cobble", tile=3)
    o.append(box(name + "_floor", (W, D, 0.12), (0, 0, 0), floor))
    # end walls with a big arched window
    for sx in (-1, 1):
        wall = box(name + "_end%d" % sx, (0.8, D, Hw), (sx * (W / 2 - 0.4), 0, 0), brick, bevel=0.1)
        o.append(wall)
        o.append(prism(name + "_gable%d" % sx, [(-D / 2, 0)] + [(math.cos(a) * D / 2, math.sin(a) * 4.5)
                                                              for a in [math.pi * k / 12 for k in range(1, 12)]]
                       + [(D / 2, 0)], 0.8, (sx * (W / 2 - 0.4), 0, Hw), brick, axis="Y", rot=(0, 0, math.radians(90))))
        o.append(cyl(name + "_rose%d" % sx, 1.6, 0.1, (sx * (W / 2 + 0.02), 0, Hw + 2.0), "EMIT_window", n=20,
                     rot=(0, math.radians(90), 0)))
    # back wall (lower), front open with iron columns
    o.append(box(name + "_back", (W - 1.6, 0.6, Hw), (0, D / 2 - 0.3, 0), brick, bevel=0.08))
    for k in range(7):
        x = -W / 2 + 2.2 + k * (W - 4.4) / 6
        o.append(cyl(name + "_col%d" % k, 0.22, Hw, (x, -D / 2 + 0.3, 0), iron, n=10))
        o.append(cyl(name + "_colcap%d" % k, 0.36, 0.25, (x, -D / 2 + 0.3, Hw - 0.25), iron, n=10))
    o.append(box(name + "_beam", (W - 0.6, 0.4, 0.5), (0, -D / 2 + 0.3, Hw - 0.1), iron))
    # barrel roof: glass half-cylinder + iron ribs
    roof = cyl(name + "_glassroof", D / 2, W - 1.2, (-(W - 1.2) / 2, 0, Hw + 0.3), glass, n=28,
               rot=(0, math.radians(90), 0))
    roof.scale = (1.0, 1.0, 4.5 / (D / 2))
    o.append(roof)
    for k in range(9):
        x = -W / 2 + 1.4 + k * (W - 2.8) / 8
        pts = [(x, math.cos(a) * (D / 2 + 0.05), Hw + 0.3 + math.sin(a) * 4.55) for a in
               [math.pi * j / 16 for j in range(17)]]
        o.append(tube_path(name + "_rib%d" % k, pts, 0.12, iron, n=8))
    o.append(tube_path(name + "_ridge", [(-W / 2 + 0.6, 0, Hw + 4.85), (W / 2 - 0.6, 0, Hw + 4.85)], 0.14, iron))
    o.append(box(name + "_lantern", (6.0, 2.0, 1.0), (0, 0, Hw + 4.7), iron, bevel=0.1))
    # stalls along the front
    for i, (k, acc, _title) in enumerate(MARKET_STALLS):
        cx = -9.0 + i * 9.0
        y0 = -D / 2 + 1.2
        o.append(box(name + "_stall%d" % i, (6.5, 1.4, 0.95), (cx, y0, 0.0), "wood", bevel=0.05))
        o.append(box("INT_counter_" + k, (6.6, 1.5, 0.12), (cx, y0, 0.95), "darkwood", bevel=0.03))
        for sx in (-1, 1):
            o.append(cyl(name + "_post%d%d" % (i, sx), 0.08, 2.6, (cx + sx * 3.1, y0 - 0.6, 0.0), "wood", n=6))
        n = 8
        for s in range(n):
            seg = box(name + "_aw%d_%d" % (i, s), (6.6 / n + 0.01, 1.8, 0.08), (cx - 3.3 + (s + 0.5) * 6.6 / n, y0 - 0.5, 2.6),
                      [accent_mat(acc), mat("awning_white", "white")][s % 2], rot=(math.radians(-16), 0, 0))
            o.append(seg)
        # produce
        if k == "veg":
            cols = ["#e8483b", "#f28c28", "#7cbf4a", "#f6c945", "#9b4f9e"]
            for c in range(5):
                o.append(box(name + "_crate%d" % c, (1.1, 0.8, 0.3), (cx - 2.5 + c * 1.25, y0 - 0.1, 1.07), "wood", bevel=0.03))
                for b in range(4):
                    o.append(sphere(name + "_veg%d_%d" % (c, b), 0.16, (cx - 2.8 + c * 1.25 + (b % 2) * 0.5,
                                                                        y0 - 0.3 + (b // 2) * 0.35, 1.45),
                                    mat("veg_" + cols[c].lstrip("#"), cols[c]), seg=8, rings=6))
        elif k == "fish":
            o.append(box(name + "_ice", (5.6, 1.1, 0.15), (cx, y0 - 0.1, 1.07), mat("ice", "#e6f4fa", rough=0.15)))
            for f in range(6):
                fx = cx - 2.3 + f * 0.9
                o.append(sphere(name + "_fish%d" % f, 0.18, (fx, y0 - 0.1, 1.3), mat("fish_silver", "#a9b8c4", rough=0.3,
                                                                                    metal=0.3),
                                seg=10, rings=6, scale=(0.9, 2.4, 0.6)))
                o.append(prism(name + "_tail%d" % f, [(-0.15, 0), (0.15, 0), (0, 0.25)], 0.04, (fx + 0.08, y0 + 0.35, 1.3),
                               "fish_silver", axis="Z"))
        else:
            for c in range(6):
                o.append(cyl(name + "_wheel%d" % c, 0.35, 0.25, (cx - 2.5 + c * 1.0, y0 - 0.1, 1.07),
                             mat("cheese", "#f6cc3a"), n=16))
            for c in range(4):
                o.append(prism(name + "_wedge%d" % c, [(0, 0), (0.6, 0), (0.0, 0.35)], 0.35,
                               (cx - 2.0 + c * 1.3, y0 - 0.5, 1.07), "cheese", axis="Z"))
        o.append(empty("MARK_pickup_" + k, (cx, -D / 2 - 1.7, 0), 180, coll))
        o.append(empty("MARK_cook_" + k, (cx, y0 + 1.3, 0), 0, coll))
        o.append(empty("MARK_parking_" + k, (cx + 3.5, -D / 2 - 3.2, 0), 90, coll))
        o.append(point_light("LIGHT_" + name + k, (cx, y0 - 0.5, 3.6), 70, coll=coll))
    # hanging lamps + garland across the front
    for k in range(6):
        x = -12.5 + k * 5.0
        o.append(cyl(name + "_lampcord%d" % k, 0.02, 1.4, (x, -1.0, Hw + 1.4), "black", n=4))
        o.append(sphere(name + "_lampshade%d" % k, 0.45, (x, -1.0, Hw + 1.3), iron, seg=12, rings=6, scale=(1, 1, 0.5)))
        o.append(sphere(name + "_lampbulb%d" % k, 0.2, (x, -1.0, Hw + 1.15), "EMIT_lamp", seg=8, rings=6))
    for k in range(30):
        x = -W / 2 + 0.8 + k * (W - 1.6) / 29
        o.append(sphere(name + "_gb%d" % k, 0.11, (x, -D / 2 - 0.05, Hw - 0.35 - 0.35 * math.sin(k * math.pi / 5) ** 2),
                        "EMIT_lamp", seg=6, rings=4))
    # sign board over the middle
    o.append(box(name + "_board", (8.0, 0.3, 1.4), (0, -D / 2 + 0.1, Hw + 0.4), accent_mat("turq"), bevel=0.2, seg=3))
    o.append(box(name + "_boardtrim", (8.4, 0.25, 0.18), (0, -D / 2 + 0.05, Hw + 0.32), mat("gold_trim", "#d8a93a", metal=0.6, rough=0.3)))
    # back rooms: back and end walls are solid, front is open to walk in; colliders
    o.append(colbox(name + "_b", (W, 1.0, Hw + 2), (0, D / 2 - 0.5, 0), coll))
    for sx in (-1, 1):
        o.append(colbox(name + "_e%d" % sx, (1.0, D, Hw + 2), (sx * (W / 2 - 0.5), 0, 0), coll))
    for i in range(3):
        o.append(colbox(name + "_s%d" % i, (6.6, 1.5, 1.1), (-9.0 + i * 9.0, -D / 2 + 1.2, 0), coll))
    relink(o, coll)
    root = finish_asset(o, name, coll)
    return root, dict(kind="restaurant", food="market", w=W, d=D, h=Hw + 5.0)


# ---------------------------------------------------------------- park
def bandstand(name="bandstand"):
    """Octagonal park bandstand (concept: white columns, turquoise roof, garland)."""
    coll = collection(name)
    o = []
    r = 4.0
    o.append(cyl(name + "_base", r + 0.4, 0.8, (0, 0, 0), "stone", n=8))
    for k in range(3):
        o.append(box(name + "_step%d" % k, (2.4, 0.5, 0.27 * (k + 1)), (0, -r - 1.2 + k * 0.45, 0), "stone"))
    o.append(cyl(name + "_floor", r + 0.2, 0.08, (0, 0, 0.8), "wood", n=8))
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        x, y = math.cos(a) * r, math.sin(a) * r
        o.append(cyl(name + "_col%d" % k, 0.16, 3.2, (x, y, 0.8), "trim_white", n=8))
        if k not in (5, 6):   # the front gap faces -Y
            nx, ny = math.cos(a + math.pi / 4) * r, math.sin(a + math.pi / 4) * r
            o.append(tube_path(name + "_rail%d" % k, [(x, y, 1.75), (nx, ny, 1.75)], 0.05, "trim_white", n=4))
    roof = cyl(name + "_roof", r + 1.0, 1.9, (0, 0, 4.0), mat("roof_turq", "turq", rough=0.5), n=8, r2=0.25)
    o.append(roof)
    o.append(cyl(name + "_eave", r + 1.05, 0.25, (0, 0, 3.9), "trim_white", n=8))
    o.append(sphere(name + "_finial", 0.3, (0, 0, 6.1), mat("gold_trim", "#d8a93a", metal=0.6, rough=0.3), seg=10, rings=6))
    for k in range(16):
        a = k * math.pi / 8
        o.append(sphere(name + "_gb%d" % k, 0.1, (math.cos(a) * (r + 0.9), math.sin(a) * (r + 0.9), 3.8), "EMIT_lamp",
                        seg=6, rings=4))
    o.append(point_light("LIGHT_" + name, (0, 0, 3.6), 80, coll=coll))
    o.append(empty("MARK_tourist_spot", (0, -r - 3.0, 0), 180, coll))
    o.append(colbox(name, (2 * r + 0.8, 2 * r + 0.8, 1.6), (0, 0, 0), coll))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="landmark", w=2 * r + 1, d=2 * r + 1, h=6.4)


def park_gate(name="park_gate"):
    """Stone pillars with lamps and an open iron gate + a 'no motor vehicles' sign. Pass-through 5 m wide."""
    coll = collection(name)
    o = []
    iron = mat("iron_black", "#2b2e33", rough=0.4, metal=0.6)
    for sx in (-1, 1):
        x = sx * 3.2
        o.append(box(name + "_pillar%d" % sx, (1.1, 1.1, 3.6), (x, 0, 0), "stone", bevel=0.08))
        o.append(box(name + "_cap%d" % sx, (1.4, 1.4, 0.3), (x, 0, 3.6), "trim_white", bevel=0.06))
        o.append(sphere(name + "_ball%d" % sx, 0.4, (x, 0, 4.25), "stone", seg=12, rings=8))
        # open gate leaf swung back
        for k in range(7):
            o.append(cyl(name + "_bar%d%d" % (sx, k), 0.035, 2.4, (x - sx * 0.6, 0.4 + k * 0.32, 0.1), iron, n=6))
        o.append(box(name + "_leaf%d" % sx, (0.08, 2.2, 0.08), (x - sx * 0.6, 1.4, 2.4), iron))
        o.append(box(name + "_leafb%d" % sx, (0.08, 2.2, 0.08), (x - sx * 0.6, 1.4, 0.3), iron))
        o.append(cyl(name + "_lamppost%d" % sx, 0.06, 0.8, (x, -0.6, 3.0), iron, n=6))
        o.append(sphere(name + "_lamp%d" % sx, 0.22, (x, -0.6, 3.9), "EMIT_lamp", seg=10, rings=6))
        o.append(colbox(name + "_p%d" % sx, (1.1, 1.1, 3.6), (x, 0, 0), coll))
    # arch over the entrance
    pts = [(math.cos(a) * 3.2, 0, 3.7 + math.sin(a) * 1.0) for a in [math.pi * k / 12 for k in range(13)]]
    o.append(tube_path(name + "_arch", pts, 0.09, iron, n=8))
    o.append(box(name + "_plaque", (2.0, 0.12, 0.5), (0, -0.05, 4.4), mat("plaque_turq", "turq"), bevel=0.05))
    # sign: no motor vehicles (red ring, white disc, black moped silhouette)
    o.append(cyl(name + "_signpole", 0.04, 2.0, (-2.2, -0.9, 0), iron, n=6))
    o.append(cyl(name + "_signring", 0.34, 0.04, (-2.2, -0.92, 2.2), mat("paint_red", "red"), n=20,
                 rot=(math.radians(90), 0, 0)))
    o.append(cyl(name + "_signdisc", 0.27, 0.05, (-2.2, -0.93, 2.2), "white", n=20, rot=(math.radians(90), 0, 0)))
    for wx in (-0.1, 0.1):
        o.append(cyl(name + "_signwheel%d" % int(wx * 10), 0.05, 0.06, (-2.2 + wx, -0.97, 2.12), "black", n=10,
                     rot=(math.radians(90), 0, 0)))
    o.append(box(name + "_signbody", (0.2, 0.06, 0.08), (-2.2, -0.97, 2.15), "black"))
    relink(o, coll)
    return finish_asset(o, name, coll), dict(kind="prop", w=7.6, d=2.0, h=4.8)


def catalogue():
    C = [("restaurant_" + k, (lambda kk=k: restaurant3(kk))) for k in REST3]
    C += [("market_hall", market_hall), ("bandstand", bandstand), ("park_gate", park_gate)]
    return C


def main():
    reset()
    std_mats()
    R.setup_render((512, 512))
    R.world()
    R.sun()
    R.ground_plane()
    meta_path = os.path.join(ASSETS, "architecture", "architecture3_meta.json")
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
            R.render(os.path.join(RENDERS, "previews", "arch3_%s.png" % root.name))
    json.dump(meta_all, open(meta_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    for ob in bpy.data.objects:   # previews isolate objects; the linked library must render everything
        ob.hide_render = ob.name.endswith("-colonly")
    if not ONLY:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, "architecture3.blend"))
    print("DONE")


if __name__ == "__main__":
    main()
