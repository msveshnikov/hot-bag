"""Task 3: the empty Old Town level.
blender -b --factory-startup -P build_world.py -- [--no-render]
Inputs: blender/architecture.blend, blender/props.blend, assets/architecture/architecture_meta.json
Outputs: blender/old_town.blend, assets/levels/old_town_ground.gltf, assets/levels/old_town_layout.json,
         assets/levels/old_town_map.png, renders/levels/*.png
Coordinates: planned in Blender (X east, Y north); JSON is written in Godot space (x, y, z) = (X, Z, -Y),
yaw in degrees about Godot +Y (same value as Blender yaw about +Z).
"""
import bpy
import sys
import os
import json
import math
import random

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
import lib_render as R
import old_town_plan as PL
from mathutils import Vector, Matrix, Euler

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
LEVEL = "old_town"

# every rideable surface is flush (no steps): a 3 cm sidewalk edge stopped the bicycle dead
Z = {"a": 0.0, "s": 0.0, "c": 0.0, "p": 0.0, "g": 0.0, "t": 0.0, "q": -3.0, "w": -4.2, "b": 0.0, "z": 0.0}
SURF_MAT = {"a": "asphalt", "s": "sidewalk", "c": "cobble", "p": "park_path", "g": "grass", "q": "stone",
            "w": "water", "z": "asphalt"}


def g3(x, y, z=0.0):
    """Blender -> Godot position."""
    return [round(x, 3), round(z, 3), round(-y, 3)]


# ---------------------------------------------------------------- library linking
def link_lib(blend):
    path = os.path.join(BLEND, blend)
    with bpy.data.libraries.load(path, link=True) as (src, dst):
        dst.collections = list(src.collections)
    return {c.name: c for c in dst.collections if c is not None}


def instance(coll_obj, name, x, y, yaw, parent_coll, z=0.0):
    e = bpy.data.objects.new(name, None)
    e.instance_type = "COLLECTION"
    e.instance_collection = coll_obj
    e.location = (x, y, z)
    e.rotation_euler = (0, 0, math.radians(yaw))
    parent_coll.objects.link(e)
    return e


def local_marks(coll_obj, root_name):
    """MARK_/INT_ objects inside a linked asset collection, positions relative to the asset root."""
    out = []

    def world_of(o):
        # linked library objects are not evaluated: compose the parent chain by hand
        if o.parent is None:
            return o.matrix_basis.copy()
        return world_of(o.parent) @ o.matrix_parent_inverse @ o.matrix_basis
    for o in coll_obj.all_objects:
        if o.name.startswith("MARK_") or o.name.startswith("INT_"):
            mw = world_of(o)
            out.append((o.name.split(".")[0], mw.translation.copy(), mw.to_euler().z))
    return out


# ---------------------------------------------------------------- ground from the nav grid
def greedy_rects(g, code):
    H, W = len(g), len(g[0])
    used = [[False] * W for _ in range(H)]
    rects = []
    for j in range(H):
        for i in range(W):
            if g[j][i] != code or used[j][i]:
                continue
            w = 1
            while i + w < W and g[j][i + w] == code and not used[j][i + w]:
                w += 1
            h = 1
            while j + h < H and all(g[j + h][i + k] == code and not used[j + h][i + k] for k in range(w)):
                h += 1
            for jj in range(j, j + h):
                for ii in range(i, i + w):
                    used[jj][ii] = True
            rects.append((i, j, w, h))
    return rects


def ground(g, coll):
    x0, y0 = PL.BOUNDS[0], PL.BOUNDS[1]
    C = PL.CELL
    objs = []
    paint = {}
    for j, row in enumerate(g):
        for i, c in enumerate(row):
            paint.setdefault(c, 0)
    for code in paint:
        if code in ("#",):
            continue
        rects = greedy_rects(g, code if code != "b" else "b")
        if not rects:
            continue
        bm_objs = []
        for (i, j, w, h) in rects:
            ax, ay = x0 + i * C, y0 + j * C
            if code == "t":
                continue  # stairs are assets
            thick = 0.3 if code not in ("w",) else 0.05
            mname = SURF_MAT.get(code, "cobble")
            o = box("g_%s" % code, (w * C, h * C, thick), (ax + w * C / 2, ay + h * C / 2, Z.get(code, 0) - thick), mname,
                    coll=coll)
            bm_objs.append(o)
        if not bm_objs:
            continue
        j_ = join(bm_objs, "ground_%s" % code + ("-col" if code not in ("w",) else ""))
        objs.append(j_)
    # cobble/sidewalk under the blocked interior (house footprints) so there is never a hole
    o = box("base_slab-col", (PL.BOUNDS[2] - PL.BOUNDS[0], 95.0 - PL.BOUNDS[1], 0.4),
            ((PL.BOUNDS[2] + PL.BOUNDS[0]) / 2, (95 + PL.BOUNDS[1]) / 2, -0.42), "cobble", coll=coll)
    objs.append(o)
    # tram rails + avenue markings
    rails = []
    for yy in (53.3, 54.7):
        rails.append(box("rail", (230, 0.12, 0.04), (-10, yy, 0.0), "steel", coll=coll))
    for x in range(-110, 92, 8):
        for yy in (51.0, 57.0):
            rails.append(box("dash", (3.0, 0.18, 0.012), (x, yy, 0.0), mat("road_white", "#f4f1ea"), coll=coll))
    for x in range(-84, 84, 6):
        rails.append(box("dash", (0.18, 3.0, 0.012), (90, x, 0.0), "road_white", coll=coll))
        rails.append(box("dash", (0.18, 3.0, 0.012), (-110, x, 0.0), "road_white", coll=coll))
    for x in range(-110, 92, 6):
        rails.append(box("dash", (3.0, 0.18, 0.012), (x, -80, 0.0), "road_white", coll=coll))
    # zebra stripes
    for (a, b, c, d) in [cr["rect"] for cr in PL.CROSSINGS]:
        horiz = (c - a) < (d - b)  # crossing over a road running along X -> stripes along Y
        if horiz:
            for k in range(int((d - b) / 1.2)):
                rails.append(box("zebra", (c - a - 0.6, 0.6, 0.012), ((a + c) / 2, b + 0.6 + k * 1.2, 0.0), "road_white",
                                 coll=coll))
        else:
            for k in range(int((c - a) / 1.2)):
                rails.append(box("zebra", (0.6, d - b - 0.6, 0.012), (a + 0.6 + k * 1.2, (b + d) / 2, 0.0), "road_white",
                                 coll=coll))
    objs.append(join(rails, "road_marks"))
    # curbs (low, cartoon) along the avenue
    curbs = [box("curb", (212, 0.3, 0.12), (-10, 48.0, 0.0), "stone", bevel=0.04, coll=coll),
             box("curb", (212, 0.3, 0.12), (-10, 60.0, 0.0), "stone", bevel=0.04, coll=coll)]
    objs.append(join(curbs, "curbs"))
    # walls for block edges without rows (garden walls) — keep courtyards closed
    walls = []
    W_ = [(-100, -34, -100, 20), (80, -34, 80, 20), (-100, -70, 80, -70), (-100, 28, -100, 44), (80, 28, 80, 44),
          (-100, -70, -100, -42), (80, -70, 80, -42), (-60, 28, -60, 44), (-52, 28, -52, 44), (30, 28, 30, 44),
          (38, 28, 38, 44), (-60, -70, -60, -42), (-52, -70, -52, -42), (30, -70, 30, -42), (38, -70, 38, -42),
          (-52, -34, -52, -6), (30, -34, 30, -6)]
    for (a, b, c, d) in W_:
        L = math.hypot(c - a, d - b)
        if L < 0.1:
            continue
        o = box("wall", (L, 0.6, 2.4), ((a + c) / 2, (b + d) / 2, 0.0), "brick", bevel=0.08, coll=coll,
                rot=(0, 0, math.atan2(d - b, c - a)))
        walls.append(o)
    wj = join(walls, "garden_walls-col")
    objs.append(wj)
    # quay walls (park -> quay drop, quay -> water)
    qw = []
    for (a, c) in ((-120, -47), (-39, 29), (37, 100)):
        qw.append(box("qw", (c - a, 1.0, 3.0), ((a + c) / 2, 88.5, -3.0), "stone", coll=coll))
    qw.append(box("qw2", (220, 1.0, 1.5), (-10, 95.5, -4.5), "stone", coll=coll))
    objs.append(join(qw, "quay_walls-col"))
    # invisible boundary walls around the playable area
    bw = []
    for (a, b, c, d) in ((-121, -91, 101, -90), (-121, -91, -120, 96), (100, -91, 101, 96), (-121, 95, 101, 96)):
        bw.append(box("bw", (c - a, d - b, 6.0), ((a + c) / 2, (b + d) / 2, -4.0), None, coll=coll))
    bwj = join(bw, "bounds-colonly")
    bwj.hide_render = True
    objs.append(bwj)
    return objs


def skyline(coll):
    """Backdrop: across-river houses band + far cartoon skyscrapers (no collision)."""
    rs = random.Random(3)
    objs = []
    x = -140
    while x < 130:
        w = rs.uniform(7, 11)
        h = rs.uniform(10, 18)
        c = rs.choice(["#f2b3a6", "#f5d36b", "#a9dcc0", "#f3e3c3", "#f6bf8f", "#a9d4ee", "#c9b6e3"])
        objs.append(box("bk", (w, 9, h), (x + w / 2, 162, 0.0), mat("bk_" + c, c, tex="plaster", tile=3), bevel=0.2,
                        coll=coll))
        objs.append(hip_roof("bkr", w, 9, h * 0.3, loc=(x + w / 2, 162, h), coll=coll))
        for f in range(int(h / 3)):
            for k in range(int(w / 2.5)):
                objs.append(box("bkw", (1.0, 0.1, 1.3), (x + 1.5 + k * 2.5, 157.4, 2 + f * 3.0), "EMIT_window",
                                coll=coll))
        x += w + 0.3
    for k in range(18):
        x = -200 + k * 24 + rs.uniform(-6, 6)
        h = rs.uniform(40, 110)
        w = rs.uniform(14, 24)
        c = rs.choice(["#9fc6e6", "#b7d6ee", "#8fb3d9", "#c9d9ea"])
        objs.append(box("sky", (w, w, h), (x, 300 + rs.uniform(-20, 30), 0.0), mat("sky_" + c, c, rough=0.3),
                        bevel=1.0, coll=coll))
        objs.append(box("skytop", (w * 0.6, w * 0.6, h * 0.12), (x, 300, h), mat("sky_" + c, c), bevel=0.5, coll=coll))
    return join(objs, "backdrop")


def footprint(meta, asset, x, y, yaw, pad=0.4):
    w, d = meta[asset]["w"], meta[asset]["d"]
    if abs(yaw) % 180 == 90:
        w, d = d, w
    return (x - w / 2 - pad, y - d / 2 - pad, x + w / 2 + pad, y + d / 2 + pad)


def main():
    reset()
    std_mats()
    lvl = collection("LEVEL")
    meta = json.load(open(os.path.join(ASSETS, "architecture", "architecture_meta.json"), encoding="utf-8"))
    ARCH = link_lib("architecture.blend")
    PROPS = link_lib("props.blend")
    ARCH2 = link_lib("architecture2.blend")      # run 2: the dream restaurant
    meta.update(json.load(open(os.path.join(ASSETS, "architecture", "architecture2_meta.json"), encoding="utf-8")))
    ARCH.update({k: v for k, v in ARCH2.items() if k == "restaurant_dream"})
    g, GW, GH = PL.grid()
    g_surface = [r[:] for r in g]

    instances = []
    markers = []
    addresses = []

    def place(asset, lib, x, y, yaw, group, extra=None):
        lib = ARCH if asset in ARCH else PROPS
        coll_obj = lib[asset]
        e = instance(coll_obj, "%s_%d" % (asset, len(instances)), x, y, yaw, lvl)
        sub = "architecture" if lib is ARCH else "props"
        instances.append(dict(asset=asset, gltf="res://assets/%s/%s.gltf" % (sub, asset), group=group,
                              pos=g3(x, y), yaw=yaw, **(extra or {})))
        rot = Matrix.Rotation(math.radians(yaw), 4, "Z")
        for (n, p, rz) in local_marks(coll_obj, asset):
            wp = Vector((x, y, 0)) + rot @ p
            markers.append(dict(name=n, inst=len(instances) - 1, pos=g3(wp.x, wp.y, wp.z),
                                yaw=round(math.degrees(rz) + yaw, 1)))
        return e

    # houses with addresses
    houses = PL.plan_rows(meta)
    for h in houses:
        st_name = PL.STREETS[h["street"]][0]
        place(h["asset"], ARCH, h["x"], h["y"], h["yaw"], "house",
              dict(street=h["street"], street_name=st_name, number=h["number"], floors=meta[h["asset"]]["floors"],
                   lift=False))
        PL.block_rect(g, footprint(meta, h["asset"], h["x"], h["y"], h["yaw"]))
    # landmarks
    for (a, x, y, yaw, kind) in PL.LANDMARKS:
        lib = ARCH if a in ARCH else PROPS
        place(a, lib, x, y, yaw, kind)
        if a in meta:
            PL.block_rect(g, footprint(meta, a, x, y, yaw))
        else:
            PL.block_rect(g, (x - 3, y - 3, x + 3, y + 3))
    for (k, x) in PL.RESTAURANTS:
        a = "restaurant_" + k
        y = PL.REST_FRONT - meta[a]["d"] / 2
        place(a, ARCH, x, y, 180, "restaurant", dict(food=k))
        PL.block_rect(g, footprint(meta, a, x, y, 180, pad=0.2))
    # run 2: the empty shop on the square that becomes the hero's restaurant (chapter 5)
    a = "restaurant_dream"
    y = PL.REST_FRONT - meta[a]["d"] / 2
    place(a, ARCH, PL.DREAM_X, y, 180, "restaurant", dict(food="dream"))
    PL.block_rect(g, footprint(meta, a, PL.DREAM_X, y, 180, pad=0.2))
    for (a, x, d, w) in PL.BASE:
        y = PL.BASE_FRONT + meta[a]["d"] / 2
        place(a, ARCH, x, y, 0, "shop")
        PL.block_rect(g, footprint(meta, a, x, y, 0, pad=0.2))
    # embankment pieces
    for x in (-43.0, 33.0):
        place("stairs_wide", ARCH, x, 84.0, 0, "stairs")
    place("bridge_stub", ARCH, 58.0, 84.0, 0, "bridge")
    # props
    big = {"fountain": 3.2, "police_booth": 1.4, "tram_stop": 2.2, "cafe_set": 1.0, "cafe_set_turq": 1.0, "bench": 0.6,
           "tree_round": 0.4, "tree_round_b": 0.4, "parapet": 0.5, "charger_station": 0.4, "bike_rack": 0.5,
           "barrier_works": 1.1}
    for (a, x, y, yaw) in PL.plan_props():
        place(a, PROPS, x, y, yaw, "prop")
        if a in big:
            r = big[a]
            PL.block_rect(g, (x - r, y - r, x + r, y + r))
    # back-drop rows around the loop (no markers kept, no addresses)
    rs = random.Random(11)
    for (x0, x1, y, yaw) in ((-126, 104, -95.5, 180),):
        x = x0
        while x < x1:
            hname = rs.choice(PL.HOUSE_TYPES)
            w = meta[hname]["w"]
            place(hname, ARCH, x + w / 2, y - meta[hname]["d"] / 2, yaw, "backdrop")
            x += w + 0.2
    for (y0, y1, x, yaw) in ((-90, 64, 106.0, -90), (-90, 64, -126.0, 90)):
        y = y0
        while y < y1:
            hname = rs.choice(PL.HOUSE_TYPES)
            w = meta[hname]["w"]
            d = meta[hname]["d"]
            place(hname, ARCH, x + (d / 2 if yaw == -90 else -d / 2), y + w / 2, yaw, "backdrop")
            y += w + 0.2
    markers = [m for m in markers if instances[m["inst"]]["group"] != "backdrop"]

    # geometry
    gcoll = collection("GROUND")
    gobjs = ground(g_surface, gcoll)
    bk = skyline(gcoll)
    gobjs.append(bk)

    # level-only markers
    def mk(kind, x, y, yaw=0.0, **kw):
        d = dict(name="MARK_" + kind, pos=g3(x, y), yaw=yaw)
        d.update(kw)
        markers.append(d)
    mk("player_start", 52.0, 23.0, 180)
    for i, (x, y) in enumerate(((60, 22), (-70, 24), (10, -38))):
        mk("courier_spawn", x, y, 0, id=i)
    rs = random.Random(5)
    walk = [(i, j) for j in range(GH) for i in range(GW) if g[j][i] in ("c", "s", "p")]
    for k in range(28):
        i, j = rs.choice(walk)
        mk("npc", PL.BOUNDS[0] + (i + 0.5) * PL.CELL, PL.BOUNDS[1] + (j + 0.5) * PL.CELL, rs.uniform(-180, 180), id=k)
    for k, (x, y) in enumerate(((-11, 18), (-11, -2), (-2, 76))):
        mk("tourist_group", x, y, 0, id=k)
    for k, (x, y) in enumerate(((-80, -38), (60, -38), (-56, -60))):
        mk("thief", x, y, 0, id=k)
    mk("roadblock", -56.0, -10.0, 90, rect=[-60, -14, -52, -6])
    mk("roadblock", 60.0, 24.0, 0, rect=[52, 20, 68, 28])
    mk("police_patrol", 20.0, 44.0, 0, route=[g3(20, 44), g3(-56, 44), g3(-56, 30), g3(20, 30)])
    for cr in PL.CROSSINGS:
        a, b, c, d = cr["rect"]
        mk("crossing", (a + c) / 2, (b + d) / 2, 0, id=cr["id"])

    # grid rows (top = smallest Y in Blender = largest Godot z? keep raw: row j = Blender y0 + j*cell)
    grid_rows = ["".join(r) for r in g]

    # lighting presets (Godot units): sun pitch/yaw degrees, colours hex, energies
    lighting = {
        "morning": dict(time=8.0, sun_pitch=-20, sun_yaw=-60, sun_color="#ffe2b8", sun_energy=1.3, sky_top="#8fc7ef",
                        sky_horizon="#f6dcc0", ambient="#c6d5e6", ambient_energy=0.55, fog_color="#eadfd0",
                        fog_density=0.0012, emission=0.0, lamps=False),
        "noon": dict(time=13.0, sun_pitch=-62, sun_yaw=-30, sun_color="#fff3dc", sun_energy=1.55, sky_top="#5fb2ef",
                     sky_horizon="#cfe9fb", ambient="#cfdcef", ambient_energy=0.55, fog_color="#d6e6f4",
                     fog_density=0.0008, emission=0.0, lamps=False),
        "evening": dict(time=19.0, sun_pitch=-12, sun_yaw=110, sun_color="#ffb070", sun_energy=1.0, sky_top="#6f86c9",
                        sky_horizon="#ffb58a", ambient="#d9b7a0", ambient_energy=0.55, fog_color="#f0c6a6",
                        fog_density=0.003, emission=1.2, lamps=True),
        "night": dict(time=22.5, sun_pitch=-50, sun_yaw=150, sun_color="#9fb4ff", sun_energy=0.42, sky_top="#16245a",
                      sky_horizon="#3d4f8f", ambient="#7d8fc9", ambient_energy=0.85, fog_color="#2a3a6e",
                      fog_density=0.0025, emission=3.0, lamps=True),
        "rain": dict(time=-1, sun_pitch=-50, sun_yaw=-40, sun_color="#d8e2ec", sun_energy=0.55, sky_top="#7d8fa3",
                     sky_horizon="#b4c0cc", ambient="#aab6c4", ambient_energy=0.65, fog_color="#a9b5c2",
                     fog_density=0.008, emission=0.6, lamps=True, wet=True),
    }
    x0, y0, x1, y1 = -122.0, -94.0, 102.0, 98.0   # map rectangle (Blender), includes the quay
    layout = dict(
        level=LEVEL, version=1, units="m", coords="godot",
        ground="res://assets/levels/old_town_ground.gltf",
        instances=instances, markers=markers,
        streets={k: dict(name=v[0], rect=[g3(v[1][0], v[1][1]), g3(v[1][2], v[1][3])]) for k, v in PL.STREETS.items()},
        grid=dict(origin=g3(PL.BOUNDS[0], PL.BOUNDS[1]), cell=PL.CELL, w=GW, h=GH,
                  note="row j = Blender y0 + j*cell = Godot z0 - j*cell; codes # a s c p g t q w b z",
                  rows=grid_rows),
        heights=Z,
        traffic=dict(paths=[dict(id=p["id"], loop=p["loop"], points=[g3(*q) for q in p["points"]])
                            for p in PL.traffic_paths()],
                     tram=dict(points=[g3(*q) for q in PL.TRAM["points"]], period=PL.TRAM["period"]),
                     crossings=[dict(id=c["id"], rect=[g3(c["rect"][0], c["rect"][1]), g3(c["rect"][2], c["rect"][3])],
                                     cycle=c["cycle"], offset=c["offset"]) for c in PL.CROSSINGS]),
        water=dict(y=Z["w"] + 0.02, rect=[g3(-140, 95), g3(120, 150)]),
        kill_y=-8.0,
        lighting=lighting,
        map=dict(image="res://assets/levels/old_town_map.png", rect=[x0, -y1, x1, -y0]),  # Godot x0,z0,x1,z1
        district=dict(id=LEVEL, title="Старый город",
                      exits=[dict(to=e["to"], label=e["label"], rect=[g3(*e["rect"][:2]), g3(*e["rect"][2:])])
                             for e in PL.EXITS],
                      entries={k: dict(pos=g3(v[0], v[1]), yaw=v[2]) for k, v in PL.ENTRIES.items()},
                      zones=[]),
    )
    os.makedirs(os.path.join(ASSETS, "levels"), exist_ok=True)
    with open(os.path.join(ASSETS, "levels", LEVEL + "_layout.json"), "w", encoding="utf-8") as f:
        json.dump(layout, f, ensure_ascii=False, separators=(",", ":"))
    print("layout: %d instances, %d markers, %d houses" % (len(instances), len(markers), len(houses)))

    # export ground glTF
    root = bpy.data.objects.new("old_town_ground", None)
    gcoll.objects.link(root)
    for o in gobjs:
        world_uv(o)
        o.parent = root
    export_gltf(root, os.path.join(ASSETS, "levels", "old_town_ground.gltf"))

    # renders
    R.setup_render((1280, 720))
    if not NO_RENDER:
        os.makedirs(os.path.join(RENDERS, "levels"), exist_ok=True)
        views = {"square": ((40, -40, 30), (-11, 10, 4)), "restaurants": ((-10, 25, 14), (-14, -8, 2)),
                 "avenue": ((-80, 30, 18), (-20, 60, 2)), "base": ((50, 12, 6), (52, 30, 2)),
                 "embankment": ((-60, 70, 10), (0, 88, -1))}
        for mood in ("day", "night", "rain"):
            R.mood(mood)
            for vn, (loc, tgt) in views.items():
                R.camera(loc=loc, target=tgt, lens=28)
                R.render(os.path.join(RENDERS, "levels", "%s_%s_%s.png" % (LEVEL, vn, mood)))
    # top-down map (orthographic, day)
    R.mood("day")
    R.sun(energy=3.5, rot=(25, 0, 30))
    bpy.context.scene.render.resolution_x = 1344
    bpy.context.scene.render.resolution_y = int(1344 * (y1 - y0) / (x1 - x0))
    R.camera(loc=((x0 + x1) / 2, (y0 + y1) / 2, 200), target=((x0 + x1) / 2, (y0 + y1) / 2, 0), ortho=(x1 - x0))
    cam = bpy.context.scene.camera
    cam.rotation_euler = (0, 0, 0)
    R.render(os.path.join(ASSETS, "levels", LEVEL + "_map.png"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, LEVEL + ".blend"))
    print("DONE")


if __name__ == "__main__":
    main()
