"""Task 1: street props and food props for «Горячая сумка».
blender -b --factory-startup -P build_props.py -- [--no-render] [--only bench,tree_round]
Writes blender/props.blend, assets/props/<name>.gltf (food props in assets/props/food/), previews.
"""
import bpy
import sys
import os
import math
import json

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
import lib_render as R

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None


def P(name):
    return name, collection(name)


def tree_round(name="tree_round", seed=1, h=4.5, r=2.0):
    name, coll = P(name)
    rs = rnd(seed)
    o = [cyl(name + "_trunk", 0.22, h * 0.55, (0, 0, 0), "darkwood", n=10, r2=0.16),
         cyl(name + "_root", 0.4, 0.3, (0, 0, 0), "darkwood", n=10, r2=0.2)]
    for k in range(4):
        a = k * 2.1 + rs.random()
        rr = r * rs.uniform(0.6, 0.85)
        o.append(sphere(name + "_crown%d" % k, rr, (math.cos(a) * r * 0.45, math.sin(a) * r * 0.45,
                                                     h * 0.62 + rs.uniform(0, 0.8)),
                        ["leaf", "leaf2"][k % 2], seg=12, rings=8))
    o.append(sphere(name + "_top", r * 0.7, (0, 0, h * 0.62 + r * 0.7), "leaf", seg=12, rings=8))
    o.append(colbox(name, (0.5, 0.5, 2.5), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def relink(objs, coll):
    for ob in objs:
        if ob is None:
            continue
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        coll.objects.link(ob)
    return objs


def bush(name="bush"):
    name, coll = P(name)
    o = [sphere(name + "_%d" % k, 0.55 - k * 0.08, (k * 0.4 - 0.4, 0, 0.45), ["leaf", "leaf2"][k % 2], seg=10, rings=7)
         for k in range(3)]
    return finish_asset(relink(o, coll), name, coll)


def bench(name="bench"):
    name, coll = P(name)
    o = []
    for k in range(3):
        o.append(box(name + "_seat%d" % k, (1.8, 0.14, 0.06), (0, -0.2 + k * 0.17, 0.45), "wood", bevel=0.02))
    for k in range(2):
        o.append(box(name + "_back%d" % k, (1.8, 0.05, 0.14), (0, 0.22, 0.62 + k * 0.2), "wood", bevel=0.02))
    for s in (-1, 1):
        o.append(box(name + "_leg%d" % s, (0.08, 0.5, 0.45), (s * 0.75, 0, 0), "black", bevel=0.02))
        o.append(box(name + "_arm%d" % s, (0.08, 0.5, 0.06), (s * 0.85, 0, 0.62), "black", bevel=0.02))
        o.append(box(name + "_bl%d" % s, (0.06, 0.06, 0.5), (s * 0.75, 0.22, 0.45), "black"))
    o.append(empty("MARK_sit", (0, -0.05, 0), 0, coll))
    o.append(empty("INT_bench", (0, -0.6, 0), 180, coll))
    o.append(colbox(name, (1.9, 0.55, 0.6), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def lamp_post(name="lamp_post"):
    name, coll = P(name)
    o = [cyl(name + "_base", 0.22, 0.5, (0, 0, 0), "black", n=10, r2=0.14),
         cyl(name + "_pole", 0.08, 3.6, (0, 0, 0.5), "black", n=8),
         tube_path(name + "_arm", [(0, 0, 3.9), (0.3, 0, 4.15), (0.7, 0, 4.15)], 0.05, "black"),
         cyl(name + "_cap", 0.3, 0.25, (0.7, 0, 4.25), "black", n=8, r2=0.05),
         cyl(name + "_glass", 0.22, 0.45, (0.7, 0, 3.8), "EMIT_lamp", n=8, r2=0.28),
         cyl(name + "_bot", 0.12, 0.12, (0.7, 0, 3.68), "black", n=8)]
    o.append(point_light("LIGHT_" + name, (0.7, 0, 3.7), 120, coll=coll))
    o.append(colbox(name, (0.4, 0.4, 3.5), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def traffic_light(name="traffic_light"):
    """Pole on the sidewalk, head faces -Y (toward oncoming traffic). TLAMP_* are separate meshes
    so Godot can light them per instance."""
    name, coll = P(name)
    o = [cyl(name + "_pole", 0.08, 3.4, (0, 0, 0), "black", n=8),
         box(name + "_head", (0.45, 0.35, 1.2), (0, 0, 2.9), "black", bevel=0.08)]
    for k, (c, m) in enumerate((("red", "TL_red"), ("yellow", "TL_yellow"), ("green", "TL_green"))):
        z = 3.78 - k * 0.37
        lamp = cyl("TLAMP_" + c, 0.13, 0.06, (0, -0.18, z), m, n=12, rot=(math.radians(90), 0, 0))
        visor = cyl(name + "_visor%d" % k, 0.17, 0.18, (0, -0.2, z), "black", n=12, rot=(math.radians(90), 0, 0),
                    cap=False)
        o += [lamp, visor]
    # pedestrian button box
    o.append(box(name + "_btn", (0.15, 0.12, 0.25), (0, -0.1, 1.1), "sun", bevel=0.02))
    o.append(colbox(name, (0.3, 0.3, 3.0), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def charger(name="charger_station"):
    name, coll = P(name)
    o = [box(name + "_body", (0.6, 0.45, 1.6), (0, 0, 0), mat("paint_turq", "turq", rough=0.5), bevel=0.15, seg=3),
         box("INT_charger", (0.42, 0.06, 0.5), (0, -0.23, 0.95), "EMIT_screen", bevel=0.03),
         box(name + "_cap", (0.66, 0.5, 0.12), (0, 0, 1.6), "trim_white", bevel=0.05),
         prism(name + "_bolt", [(0.0, 0.18), (0.1, 0.0), (0.02, 0.0), (0.08, -0.18), (-0.08, 0.02), (0.0, 0.02)], 0.03,
               (0, -0.27, 1.25), mat("EMIT_neon_teal", "#7fe3dc", emit="#38e0d0", emit_strength=0.0), axis="Y"),
         tube_path(name + "_cable", [(0.3, -0.1, 0.9), (0.45, -0.2, 0.6), (0.4, -0.3, 0.4)], 0.025, "black"),
         box(name + "_pad", (1.6, 2.2, 0.03), (0.0, -1.3, 0), mat("EMIT_pad", "#5ad7cc", emit="#38e0d0",
                                                                      emit_strength=0.0), bevel=0.01)]
    o.append(empty("MARK_charger", (0, -1.3, 0), 180, coll))
    o.append(colbox(name, (0.6, 0.45, 1.6), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def bike_rack(name="bike_rack"):
    name, coll = P(name)
    o = []
    for k in range(4):
        x = -1.5 + k * 1.0
        o.append(tube_path(name + "_hoop%d" % k, [(x, -0.3, 0), (x, -0.3, 0.7), (x, -0.15, 0.85), (x, 0.15, 0.85),
                                                  (x, 0.3, 0.7), (x, 0.3, 0)], 0.035, "steel"))
    o.append(empty("MARK_parking", (0, -1.0, 0), 90, coll))
    o.append(colbox(name, (3.2, 0.7, 0.9), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def trash_bin(name="trash_bin"):
    name, coll = P(name)
    o = [cyl(name + "_b", 0.3, 0.85, (0, 0, 0), mat("paint_green", "green"), n=14, r2=0.34),
         cyl(name + "_lid", 0.37, 0.12, (0, 0, 0.85), "black", n=14, r2=0.3)]
    o.append(colbox(name, (0.6, 0.6, 1.0), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def flower_pot(name="flower_pot", seed=3):
    name, coll = P(name)
    rs = rnd(seed)
    o = [box(name + "_pot", (1.0, 1.0, 0.6), (0, 0, 0), "wood", bevel=0.06),
         sphere(name + "_soil", 0.5, (0, 0, 0.55), "leaf2", scale=(1, 1, 0.5), seg=10, rings=6)]
    for k in range(7):
        c = rs.choice(["coral", "pink", "sun", "red", "lilac", "white"])
        o.append(sphere(name + "_f%d" % k, 0.15, (rs.uniform(-.35, .35), rs.uniform(-.35, .35), 0.75 + rs.uniform(0, .15)),
                        mat("flower_" + c, c), seg=8, rings=6))
    o.append(colbox(name, (1.0, 1.0, 0.7), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def cafe_set(name="cafe_set", umb="coral"):
    name, coll = P(name)
    o = [cyl(name + "_top", 0.45, 0.06, (0, 0, 0.72), "trim_white", n=16),
         cyl(name + "_leg", 0.05, 0.72, (0, 0, 0), "black", n=6),
         cyl(name + "_foot", 0.25, 0.04, (0, 0, 0), "black", n=10),
         cyl(name + "_pole", 0.03, 2.3, (0, 0, 0.75), "trim_white", n=6),
         cyl(name + "_umb", 1.4, 0.55, (0, 0, 2.5), mat("paint_" + umb, umb), n=12, r2=0.05),
         cyl(name + "_cup", 0.05, 0.08, (0.15, 0, 0.78), "white", n=8)]
    for s in (-1, 1):
        cx = s * 0.75
        o.append(cyl(name + "_chair%d" % s, 0.24, 0.45, (cx, 0, 0), mat("rattan", "#c9944f"), n=10))
        o.append(box(name + "_cb%d" % s, (0.08, 0.45, 0.5), (cx + s * 0.22, 0, 0.45), "rattan", bevel=0.03))
    o.append(empty("MARK_sit_a", (-0.75, 0, 0), 90, coll))
    o.append(empty("MARK_sit_b", (0.75, 0, 0), -90, coll))
    o.append(colbox(name, (2.0, 1.0, 0.9), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def barrier_works(name="barrier_works"):
    name, coll = P(name)
    o = []
    for k in range(4):
        o.append(box(name + "_s%d" % k, (0.6, 0.12, 0.3), (-0.9 + k * 0.6, 0, 0.8),
                     [mat("paint_red", "red"), mat("paint_white", "white")][k % 2]))
    for s in (-1, 1):
        o.append(box(name + "_leg%d" % s, (0.1, 0.6, 0.85), (s * 1.0, 0, 0), "black", bevel=0.02))
    o.append(cyl(name + "_lamp", 0.1, 0.15, (1.0, 0, 0.95), mat("EMIT_warn", "#ffb43a", emit="#ffa020",
                                                                emit_strength=1.0), n=8))
    o.append(colbox(name, (2.2, 0.6, 1.0), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def cone(name="traffic_cone"):
    name, coll = P(name)
    o = [box(name + "_base", (0.45, 0.45, 0.06), (0, 0, 0), "black", bevel=0.02),
         cyl(name + "_c", 0.17, 0.7, (0, 0, 0.06), mat("paint_orange", "orange"), n=12, r2=0.03),
         cyl(name + "_stripe", 0.125, 0.12, (0, 0, 0.32), mat("paint_white", "white"), n=12, r2=0.1)]
    return finish_asset(relink(o, coll), name, coll)


def bollard(name="bollard"):
    name, coll = P(name)
    o = [cyl(name + "_b", 0.12, 0.8, (0, 0, 0), "black", n=10),
         sphere(name + "_top", 0.14, (0, 0, 0.82), "black", seg=10, rings=6)]
    o.append(colbox(name, (0.25, 0.25, 0.9), (0, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def fountain(name="fountain"):
    name, coll = P(name)
    o = [cyl(name + "_basin", 3.0, 0.8, (0, 0, 0), "stone", n=24, bevel=0.1),
         cyl(name + "_water", 2.7, 0.05, (0, 0, 0.62), "water", n=24),
         cyl(name + "_col", 0.45, 1.6, (0, 0, 0.6), "stone", n=12),
         cyl(name + "_bowl", 1.1, 0.4, (0, 0, 2.0), "stone", n=16, r2=1.3),
         cyl(name + "_w2", 1.15, 0.05, (0, 0, 2.35), "water", n=16),
         # cartoon fish statue on top
         sphere(name + "_fish", 0.45, (0, 0, 2.9), "stone", scale=(1.4, 0.7, 0.9)),
         prism(name + "_tail", [(0, 0), (0.5, 0.4), (0.5, -0.4)], 0.2, (0.55, 0, 2.9), "stone", axis="Y",
               rot=(0, 0, 0))]
    o.append(empty("ANIM_fountain_spout", (-0.6, 0, 2.95), 0, coll))
    o.append(colbox(name, (6.0, 6.0, 0.9), (-3 + 3, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def mailbox(name="mailbox"):
    name, coll = P(name)
    o = [box(name + "_b", (0.45, 0.35, 0.6), (0, 0, 0.7), mat("paint_sun", "sun"), bevel=0.1, seg=3),
         cyl(name + "_p", 0.05, 0.7, (0, 0, 0), "black", n=6),
         box(name + "_slot", (0.25, 0.02, 0.04), (0, -0.18, 1.1), "black")]
    return finish_asset(relink(o, coll), name, coll)


def crates(name="crates"):
    name, coll = P(name)
    o = [box(name + "_a", (0.6, 0.45, 0.4), (0, 0, 0), "wood", bevel=0.03),
         box(name + "_b", (0.6, 0.45, 0.4), (0.05, 0.02, 0.4), "wood", bevel=0.03, rot=(0, 0, 0.2)),
         box(name + "_c", (0.6, 0.45, 0.4), (0.7, 0, 0), "wood", bevel=0.03)]
    for k, c in enumerate(("red", "orange", "leaf")):
        o.append(sphere(name + "_fruit%d" % k, 0.12, (0.6 + k * 0.15, 0, 0.45), mat("fruit_" + c, c), seg=8, rings=6))
    o.append(colbox(name, (1.3, 0.5, 0.8), (0.35, 0, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


def menu_board(name="menu_board"):
    name, coll = P(name)
    o = [prism(name + "_a", [(-0.3, 0), (0.3, 0), (0.0, 1.0)], 0.6, (0, 0, 0), "wood", axis="Y",
               rot=(0, 0, math.radians(90)))]
    o.append(box(name + "_slate", (0.5, 0.03, 0.6), (0, -0.17, 0.2), "black", rot=(math.radians(-17), 0, 0)))
    return finish_asset(relink(o, coll), name, coll)


def string_lights(name="string_lights", length=10.0):
    name, coll = P(name)
    pts = [(-length / 2 + length * k / 20, 0, -0.6 * math.sin(math.pi * k / 20)) for k in range(21)]
    o = [tube_path(name + "_wire", pts, 0.012, "black", n=4)]
    for k in range(1, 20, 2):
        x, y, z = pts[k]
        o.append(sphere(name + "_b%d" % k, 0.07, (x, y, z - 0.08), "EMIT_lamp", seg=6, rings=4))
    return finish_asset(relink(o, coll), name, coll)


def tram_stop(name="tram_stop"):
    name, coll = P(name)
    o = [box(name + "_roof", (4.0, 1.6, 0.12), (0, 0, 2.5), mat("paint_turq", "turq"), bevel=0.05),
         box(name + "_back", (4.0, 0.06, 1.8), (0, 0.7, 0.5), mat("glass_light", "#bfe4f2", alpha=0.5)),
         box(name + "_bench", (2.5, 0.4, 0.08), (0, 0.4, 0.45), "wood")]
    for s in (-1, 1):
        o.append(cyl(name + "_post%d" % s, 0.05, 2.5, (s * 1.9, 0.7, 0), "steel", n=6))
    o.append(colbox(name, (4.0, 0.2, 2.4), (0, 0.7, 0), coll))
    return finish_asset(relink(o, coll), name, coll)


# ---------------------------------------------------------------- food props (held / delivered)
def pizza_box(name="pizza_box"):
    name, coll = P(name)
    o = [box(name + "_b", (0.38, 0.38, 0.06), (0, 0, 0), mat("cardboard", "#d6a96b"), bevel=0.01),
         box(name + "_lbl", (0.16, 0.16, 0.005), (0, 0, 0.06), "red")]
    return finish_asset(relink(o, coll), name, coll)


def paper_bag(name="paper_bag"):
    name, coll = P(name)
    o = [box(name + "_b", (0.28, 0.18, 0.34), (0, 0, 0), mat("paper", "#d9b384"), bevel=0.01),
         box(name + "_fold", (0.29, 0.19, 0.04), (0, 0, 0.34), mat("paper_dark", "#c79c68"), bevel=0.01),
         box(name + "_sticker", (0.1, 0.005, 0.1), (0, -0.092, 0.18), "turq")]
    return finish_asset(relink(o, coll), name, coll)


def cup_holder(name="cup_holder"):
    name, coll = P(name)
    o = [box(name + "_tray", (0.26, 0.26, 0.05), (0, 0, 0), mat("cardboard", "#d6a96b"))]
    for k, (x, y) in enumerate(((-0.06, -0.06), (0.06, 0.06))):
        o.append(cyl(name + "_cup%d" % k, 0.045, 0.16, (x, y, 0.03), "white", n=10, r2=0.055))
        o.append(cyl(name + "_lid%d" % k, 0.058, 0.02, (x, y, 0.19), "coral", n=10))
        o.append(cyl(name + "_straw%d" % k, 0.007, 0.1, (x + 0.01, y, 0.2), "sun", n=4))
    return finish_asset(relink(o, coll), name, coll)


def cake_box(name="cake_box"):
    name, coll = P(name)
    o = [box(name + "_b", (0.3, 0.3, 0.22), (0, 0, 0), mat("paint_pinkbox", "pink"), bevel=0.01),
         box(name + "_rib1", (0.31, 0.03, 0.225), (0, 0, 0), "coral"),
         box(name + "_rib2", (0.03, 0.31, 0.225), (0, 0, 0), "coral"),
         torus(name + "_bow", 0.04, 0.012, (0, 0, 0.235), "coral", rot=(math.radians(90), 0, 0))]
    return finish_asset(relink(o, coll), name, coll)


def sushi_box(name="sushi_box"):
    name, coll = P(name)
    o = [box(name + "_b", (0.3, 0.2, 0.06), (0, 0, 0), "black", bevel=0.01),
         box(name + "_lid", (0.3, 0.2, 0.01), (0, 0, 0.07), mat("glass_light", "#bfe4f2", alpha=0.5))]
    for k in range(4):
        o.append(cyl(name + "_r%d" % k, 0.03, 0.04, (-0.1 + k * 0.066, 0, 0.02), "white", n=8))
        o.append(cyl(name + "_s%d" % k, 0.015, 0.042, (-0.1 + k * 0.066, 0, 0.02), "salmon", n=6))
    return finish_asset(relink(o, coll), name, coll)


def ice_cream_tub(name="ice_cream_tub"):
    name, coll = P(name)
    o = [cyl(name + "_t", 0.08, 0.12, (0, 0, 0), "white", n=12, r2=0.1),
         cyl(name + "_lid", 0.105, 0.02, (0, 0, 0.12), mat("paint_mint", "mint"), n=12),
         sphere(name + "_scoop", 0.06, (0, 0, 0.16), "pink", seg=8, rings=6)]
    return finish_asset(relink(o, coll), name, coll)


def lunch_crate(name="lunch_crate"):
    name, coll = P(name)
    o = [box(name + "_c", (0.6, 0.4, 0.3), (0, 0, 0), mat("paint_turq", "turq"), bevel=0.03)]
    for k in range(6):
        o.append(box(name + "_box%d" % k, (0.17, 0.12, 0.08), (-0.2 + (k % 3) * 0.2, -0.08 + (k // 3) * 0.16, 0.3),
                     mat("cardboard", "#d6a96b"), bevel=0.005))
    return finish_asset(relink(o, coll), name, coll)


STREET = [("tree_round", tree_round), ("tree_round_b", lambda: tree_round("tree_round_b", seed=5, h=5.5, r=2.4)),
          ("bush", bush), ("bench", bench), ("lamp_post", lamp_post), ("traffic_light", traffic_light),
          ("charger_station", charger), ("bike_rack", bike_rack), ("trash_bin", trash_bin),
          ("flower_pot", flower_pot), ("cafe_set", cafe_set),
          ("cafe_set_turq", lambda: cafe_set("cafe_set_turq", "turq")),
          ("barrier_works", barrier_works), ("traffic_cone", cone), ("bollard", bollard), ("fountain", fountain),
          ("mailbox", mailbox), ("crates", crates), ("menu_board", menu_board), ("string_lights", string_lights),
          ("tram_stop", tram_stop)]
FOOD = [("pizza_box", pizza_box), ("paper_bag", paper_bag), ("cup_holder", cup_holder), ("cake_box", cake_box),
        ("sushi_box", sushi_box), ("ice_cream_tub", ice_cream_tub), ("lunch_crate", lunch_crate)]


def main():
    reset()
    std_mats()
    mat("salmon", "#f27b4a")
    R.setup_render((384, 384))
    R.world()
    R.sun()
    R.ground_plane()
    built = []
    for group, lst, sub in (("street", STREET, ""), ("food", FOOD, "food")):
        for name, fn in lst:
            if ONLY and name not in ONLY:
                continue
            root = fn()
            saved = scale_lights_for_export(root)
            export_gltf(root, os.path.join(ASSETS, "props", sub, name + ".gltf"))
            restore_lights(saved)
            built.append(root)
            print("built", name)
    if not NO_RENDER:
        R.mood("day")
        for root in built:
            kids = [root] + list(root.children_recursive)
            R.isolate(kids)
            R.frame_objects([k for k in kids if k.type == "MESH"], yaw=-30, pitch=20)
            R.render(os.path.join(RENDERS, "previews", "prop_%s.png" % root.name))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, "props.blend"))
    print("DONE")


if __name__ == "__main__":
    main()
