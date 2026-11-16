"""Run 2/3: build a district level from a plan module (city_plan.py, berezki_plan.py, gastro_plan.py).
blender -b --factory-startup -P build_district.py -- --level city [--no-render]
Inputs: blender/architecture.blend, blender/architecture2.blend, blender/props.blend, architecture(2)_meta.json,
        assets/levels/old_town_layout.json (lighting presets are shared)
Outputs: blender/<level>.blend, assets/levels/<level>_ground.gltf, <level>_layout.json, <level>_map.png,
         renders/levels/<level>_*.png
Same JSON format as the Old Town (README "Формат данных"), plus a "district" block: title, exits, entries, zones.
"""
import bpy
import sys
import os
import json
import math
import random
import importlib

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
import lib_render as R
from build_world import link_lib, instance, local_marks, greedy_rects
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
LEVEL = ARGS[ARGS.index("--level") + 1] if "--level" in ARGS else "city"
PL = importlib.import_module(LEVEL + "_plan")

Z = {"a": 0.0, "s": 0.0, "c": 0.0, "p": 0.0, "g": 0.0, "t": 0.0, "q": -3.0, "w": -4.2, "b": 0.0, "z": 0.0}
PROP_BLOCK = {"fountain": 3.2, "police_booth": 1.4, "cafe_set": 1.0, "cafe_set_turq": 1.0, "bench": 0.6,
              "tree_round": 0.4, "tree_round_b": 0.4, "tree_birch": 0.4, "parapet": 0.5, "charger_station": 0.4,
              "bike_rack": 0.5, "barrier_works": 1.1, "planter_long": 1.0, "trash_bin": 0.3, "lamp_post": 0.2,
              "flower_pot": 0.4, "traffic_light": 0.2}
NO_BLOCK = {"park_gate"}   # walk-through props: their own pillars collide, the passage stays open on the grid


def g3(x, y, z=0.0):
    return [round(x, 3), round(z, 3), round(-y, 3)]


def grid():
    x0, y0, x1, y1 = PL.BOUNDS
    W = int((x1 - x0) / PL.CELL)
    H = int((y1 - y0) / PL.CELL)
    g = [["#"] * W for _ in range(H)]
    for code, a, b, c, d in PL.SURF:
        i0 = max(0, int((a - x0) / PL.CELL)); i1 = min(W, int(math.ceil((c - x0) / PL.CELL)))
        j0 = max(0, int((b - y0) / PL.CELL)); j1 = min(H, int(math.ceil((d - y0) / PL.CELL)))
        for j in range(j0, j1):
            for i in range(i0, i1):
                g[j][i] = code
    return g, W, H


def block_rect(g, rect, code="#"):
    x0, y0 = PL.BOUNDS[0], PL.BOUNDS[1]
    a, b, c, d = rect
    H = len(g); W = len(g[0])
    i0 = max(0, int((a - x0) / PL.CELL)); i1 = min(W, int(math.ceil((c - x0) / PL.CELL)))
    j0 = max(0, int((b - y0) / PL.CELL)); j1 = min(H, int(math.ceil((d - y0) / PL.CELL)))
    for j in range(j0, j1):
        for i in range(i0, i1):
            g[j][i] = code


def footprint(m, x, y, yaw, pad=0.4):
    w = m["w"]
    d = m["d"] - m.get("front_extra", 0.0)
    if abs(yaw) % 180 == 90:
        w, d = d, w
    return (x - w / 2 - pad, y - d / 2 - pad, x + w / 2 + pad, y + d / 2 + pad)


def local_to_world(x, y, yaw, lx, ly):
    a = math.radians(yaw)
    return (x + lx * math.cos(a) - ly * math.sin(a), y + lx * math.sin(a) + ly * math.cos(a))


# ---------------------------------------------------------------- ground
def ground(g, coll, zones):
    x0, y0 = PL.BOUNDS[0], PL.BOUNDS[1]
    C = PL.CELL
    mat("plaza", "#c9b6a2", tex="plaza", tile=4.0)
    objs = []
    codes = set(c for row in g for c in row)
    for code in codes:
        if code in ("#", "t"):
            continue
        rects = greedy_rects(g, code)
        parts = []
        for (i, j, w, h) in rects:
            ax, ay = x0 + i * C, y0 + j * C
            thick = 0.3 if code != "w" else 0.05
            mname = PL.SURF_MAT.get(code, "cobble")
            parts.append(box("g_%s" % code, (w * C, h * C, thick), (ax + w * C / 2, ay + h * C / 2, Z.get(code, 0) - thick),
                             mname, coll=coll))
        if parts:
            objs.append(join(parts, "ground_%s" % code + ("-col" if code != "w" else "")))
    bx0, by0, bx1, by1 = PL.BOUNDS
    pond = getattr(PL, "POND", None)
    if pond:
        (cx, cy), (rx, ry) = pond["c"], pond["r"]
        water = cyl("pond_water", 1.0, 0.06, (cx, cy, 0.0), mat("pond_water", "#5fb7d4", rough=0.08), n=48)
        water.scale = (rx, ry, 1.0)
        objs.append(water)
        rim = torus("pond_rim-col", 1.0, 0.035, (cx, cy, 0.12), mat("pond_stone", "#cfc4b3"), n=64, nr=8)
        rim.scale = (rx + 0.6, ry + 0.6, 12.0)
        objs.append(rim)
    objs.append(box("base_slab-col", (bx1 - bx0, by1 - by0, 0.4), ((bx0 + bx1) / 2, (by0 + by1) / 2, -0.42),
                    PL.SURF_MAT.get("p", "sidewalk"), coll=coll))
    marks = []
    white = mat("road_white", "#f4f1ea")
    for (a, b, c, d) in PL.ROAD_MARKS:
        L = math.hypot(c - a, d - b)
        ux, uy = (c - a) / L, (d - b) / L
        t = 2.0
        while t < L - 2.0:
            px, py = a + ux * t, b + uy * t
            if not any(cr["rect"][0] - 1 < px < cr["rect"][2] + 1 and cr["rect"][1] - 1 < py < cr["rect"][3] + 1
                       for cr in PL.CROSSINGS):
                marks.append(box("dash", (3.0 if abs(ux) > 0.5 else 0.18, 3.0 if abs(uy) > 0.5 else 0.18, 0.012),
                                 (px, py, 0.0), white, coll=coll))
            t += 6.0
    for cr in PL.CROSSINGS:
        a, b, c, d = cr["rect"]
        if (c - a) < (d - b):
            for k in range(int((d - b) / 1.2)):
                marks.append(box("zebra", (c - a - 0.6, 0.6, 0.012), ((a + c) / 2, b + 0.6 + k * 1.2, 0.0), white,
                                 coll=coll))
        else:
            for k in range(int((c - a) / 1.2)):
                marks.append(box("zebra", (0.6, d - b - 0.6, 0.012), (a + 0.6 + k * 1.2, (b + d) / 2, 0.0), white,
                                 coll=coll))
    # no-parking zones: red/white curb stripes around the rectangle
    red = mat("paint_red", "red")
    for z in zones:
        a, b, c, d = z["rect"]
        for (sx, sy, ex, ey) in ((a, b, c, b), (c, b, c, d), (c, d, a, d), (a, d, a, b)):
            L = math.hypot(ex - sx, ey - sy)
            n = max(1, int(L / 0.8))
            for k in range(n):
                t = (k + 0.5) / n
                px, py = sx + (ex - sx) * t, sy + (ey - sy) * t
                horiz = abs(ex - sx) > abs(ey - sy)
                marks.append(box("np", (L / n if horiz else 0.25, 0.25 if horiz else L / n, 0.014), (px, py, 0.0),
                                 red if k % 2 == 0 else white, coll=coll))
        cx, cy = (a + c) / 2, (b + d) / 2
        for s in (-1, 1):
            o = box("npx", (min(c - a, d - b) * 1.1, 0.22, 0.013), (cx, cy, 0.0), red, coll=coll)
            o.rotation_euler = (0, 0, math.radians(45 * s))
            marks.append(o)
    if marks:
        objs.append(join(marks, "road_marks"))
    if PL.WATER:
        wx0, wy0, wx1, wy1 = PL.WATER["rect"]
        # embankment wall along the water's north edge (the '#' strip in the plan) + quay face down to the water
        objs.append(box("embank-col", (bx1 - bx0, 4.0, 0.7), ((bx0 + bx1) / 2, wy1 + 2.0, 0.0), "stone", bevel=0.1,
                        coll=coll))
        objs.append(box("quay", (bx1 - bx0 + 40, 1.0, 4.4), ((bx0 + bx1) / 2, wy1 - 0.5, -4.2), "stone", coll=coll))
    if PL.BRIDGE:
        a, b, c, d = PL.BRIDGE["rect"]
        objs.append(box("bridge_deck-col", (c - a, d - b, 1.2), ((a + c) / 2, (b + d) / 2, -1.2), "stone", bevel=0.1,
                        coll=coll))
        for sx in (a, c):
            objs.append(box("bridge_rail-col", (0.6, d - b, 1.1), (sx, (b + d) / 2, 0.0), "stone", bevel=0.1, coll=coll))
        for k in range(3):
            yy = b + 5 + k * 7
            objs.append(cyl("bridge_pier", 2.0, 4.0, ((a + c) / 2, yy, -5.2), "stone", n=12))
    # invisible walls around the playable rectangle
    bw = []
    m = 3.0
    for (a, b, c, d) in ((bx0 + m - 1, by0 + m - 1, bx1 - m + 1, by0 + m), (bx0 + m - 1, by0 + m - 1, bx0 + m, by1 - m + 1),
                         (bx1 - m, by0 + m - 1, bx1 - m + 1, by1 - m + 1), (bx0 + m - 1, by1 - m, bx1 - m + 1, by1 - m + 1)):
        bw.append(box("bw", (c - a, d - b, 8.0), ((a + c) / 2, (b + d) / 2, -4.0), None, coll=coll))
    j = join(bw, "bounds-colonly")
    j.hide_render = True
    objs.append(j)
    return objs


def backdrop(coll):
    """Far skyline ring: glass towers for the business district, panel silhouettes for the residential one."""
    rs = random.Random(5)
    objs = []
    bx0, by0, bx1, by1 = PL.BOUNDS
    cx, cy = (bx0 + bx1) / 2, (by0 + by1) / 2
    glassy = LEVEL == "city"
    for k in range(40):
        a = k / 40 * 2 * math.pi + rs.uniform(-0.05, 0.05)
        r = rs.uniform(175, 260)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        if glassy:
            h = rs.uniform(45, 130); w = rs.uniform(16, 28)
            c = rs.choice(["#9fc6e6", "#b7d6ee", "#8fb3d9", "#a9dcd0", "#c9d9ea"])
            objs.append(box("sky", (w, w, h), (x, y, -1.0), mat("sky_" + c, c, rough=0.3), bevel=2.0, coll=coll))
        else:
            h = rs.uniform(25, 48); w = rs.uniform(22, 40)
            c = rs.choice(["#efe4cc", "#f1e2b0", "#ece6dc", "#f2d6bf"])
            o = box("pnl", (w, 12, h), (x, y, -1.0), mat("bkp_" + c, c, tex="panel", tile=5.8), coll=coll)
            o.rotation_euler = (0, 0, a + math.pi / 2)
            objs.append(o)
            for f in range(int(h / 6)):
                lw = box("pw", (w * 0.8, 12.2, 0.9), (x, y, 2 + f * 6.0), "EMIT_window", coll=coll)
                lw.rotation_euler = (0, 0, a + math.pi / 2)
                objs.append(lw)
    return join(objs, "backdrop")


def main():
    reset()
    std_mats()
    lvl = collection("LEVEL")
    meta = json.load(open(os.path.join(ASSETS, "architecture", "architecture_meta.json"), encoding="utf-8"))
    meta.update(json.load(open(os.path.join(ASSETS, "architecture", "architecture2_meta.json"), encoding="utf-8")))
    meta.update(json.load(open(os.path.join(ASSETS, "architecture", "architecture3_meta.json"), encoding="utf-8")))
    ARCH = link_lib("architecture.blend")
    ARCH2 = link_lib("architecture2.blend")
    ARCH3 = link_lib("architecture3.blend")
    PROPS = link_lib("props.blend")
    g, GW, GH = grid()
    g_surface = [r[:] for r in g]
    instances, markers = [], []
    zones = []

    def lib_of(asset):
        for lib, sub in ((ARCH3, "architecture"), (ARCH2, "architecture"), (ARCH, "architecture"), (PROPS, "props")):
            if asset in lib:
                return lib, sub
        raise KeyError(asset)

    def place(asset, x, y, yaw, group, extra=None):
        lib, sub = lib_of(asset)
        coll_obj = lib[asset]
        instance(coll_obj, "%s_%d" % (asset, len(instances)), x, y, yaw, lvl)
        instances.append(dict(asset=asset, gltf="res://assets/%s/%s.gltf" % (sub, asset), group=group,
                              pos=g3(x, y), yaw=yaw, **(extra or {})))
        rot = Matrix.Rotation(math.radians(yaw), 4, "Z")
        for (n, p, rz) in local_marks(coll_obj, asset):
            wp = Vector((x, y, 0)) + rot @ p
            markers.append(dict(name=n, inst=len(instances) - 1, pos=g3(wp.x, wp.y, wp.z),
                                yaw=round(math.degrees(rz) + yaw, 1)))

    addrs = PL.addresses(PL.BUILDINGS, meta)
    for i, (asset, x, y, yaw, group, extra) in enumerate(PL.BUILDINGS):
        ex = dict(extra)
        m = meta.get(asset, {})
        if i in addrs:
            ex.update(addrs[i])
            ex.update(floors=m.get("floors", 9), lift=bool(m.get("lift", True)))
        place(asset, x, y, yaw, group, ex)
        if m and asset not in NO_BLOCK:
            block_rect(g, footprint(m, x, y, yaw))
        if m.get("kind") == "tower" and PL.NO_PARKING_DEPTH > 0:
            # red zone in front of the lobby (local: canopy area in front of the body)
            d_body = m["d"] - m.get("front_extra", 0.0)
            pts = [local_to_world(x, y, yaw, lx, ly) for lx in (-6.0, 6.0)
                   for ly in (-d_body / 2 - 0.6, -d_body / 2 - 0.6 - PL.NO_PARKING_DEPTH)]
            xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
            zones.append(dict(kind="no_parking", rect=(min(xs), min(ys), max(xs), max(ys)), inst=len(instances) - 1))
    for (a, x, y, yaw) in PL.plan_props():
        place(a, x, y, yaw, "prop")
        r = PROP_BLOCK.get(a)
        if r:
            block_rect(g, (x - r, y - r, x + r, y + r))
    pond = getattr(PL, "POND", None)
    if pond:   # the pond is not walkable (nav grid); the surface below stays grass for the ground mesh
        (pcx, pcy), (prx, pry) = pond["c"], pond["r"]
        bx0, by0 = PL.BOUNDS[0], PL.BOUNDS[1]
        for j in range(GH):
            for i in range(GW):
                x, y = bx0 + (i + 0.5) * PL.CELL, by0 + (j + 0.5) * PL.CELL
                if ((x - pcx) / (prx + 1.0)) ** 2 + ((y - pcy) / (pry + 1.0)) ** 2 < 1.0:
                    g[j][i] = "#"
    # geometry
    gcoll = collection("GROUND")
    gobjs = ground(g_surface, gcoll, zones)
    gobjs.append(backdrop(gcoll))

    def mk(kind, x, y, yaw=0.0, **kw):
        d = dict(name="MARK_" + kind, pos=g3(x, y), yaw=yaw)
        d.update(kw)
        markers.append(d)
    x, y, yaw = PL.PLAYER_START
    mk("player_start", x, y, yaw)
    for frm, (x, y, yaw) in PL.ENTRIES.items():
        mk("entry_" + frm, x, y, yaw)
    rs = random.Random(5)
    walk = [(i, j) for j in range(GH) for i in range(GW) if g[j][i] in ("p", "s")]

    def cell_pos(c):
        return PL.BOUNDS[0] + (c[0] + 0.5) * PL.CELL, PL.BOUNDS[1] + (c[1] + 0.5) * PL.CELL
    for (kind, x, y, yaw, kw) in PL.markers(rs, walk, cell_pos):
        if "route" in kw:
            kw = dict(kw, route=[g3(*p) for p in kw["route"]])
        mk(kind, x, y, yaw, **kw)
    for cr in PL.CROSSINGS:
        a, b, c, d = cr["rect"]
        mk("crossing", (a + c) / 2, (b + d) / 2, 0, id=cr["id"])

    lighting = json.load(open(os.path.join(ASSETS, "levels", "old_town_layout.json"), encoding="utf-8"))["lighting"]
    fm = PL.LIGHTING_TWEAK.get("fog_mult", 1.0)
    for k in lighting:
        lighting[k]["fog_density"] = round(lighting[k]["fog_density"] * fm, 5)
    mx0, my0, mx1, my1 = PL.MAP_RECT

    def rect_g(r):
        return [g3(r[0], r[1]), g3(r[2], r[3])]
    layout = dict(
        level=LEVEL, version=1, units="m", coords="godot",
        ground="res://assets/levels/%s_ground.gltf" % LEVEL,
        instances=instances, markers=markers,
        streets={k: dict(name=v[0], rect=rect_g(v[1])) for k, v in PL.STREETS.items()},
        grid=dict(origin=g3(PL.BOUNDS[0], PL.BOUNDS[1]), cell=PL.CELL, w=GW, h=GH,
                  note="row j = Blender y0 + j*cell = Godot z0 - j*cell; codes # a s c p g t q w b z",
                  rows=["".join(r) for r in g]),
        heights=Z,
        traffic=dict(paths=[dict(id=p["id"], loop=p["loop"], points=[g3(*q) for q in p["points"]])
                            for p in PL.traffic_paths()],
                     tram=None,
                     crossings=[dict(id=c["id"], rect=rect_g(c["rect"]), cycle=c["cycle"], offset=c["offset"])
                                for c in PL.CROSSINGS]),
        water=dict(y=PL.WATER["z"] + 0.02, rect=rect_g(PL.WATER["rect"])) if PL.WATER else {},
        kill_y=-8.0,
        lighting=lighting,
        map=dict(image="res://assets/levels/%s_map.png" % LEVEL, rect=[mx0, -my1, mx1, -my0]),
        district=dict(id=LEVEL, title=PL.TITLE,
                      exits=[dict(to=e["to"], label=e["label"], rect=rect_g(e["rect"])) for e in PL.EXITS],
                      entries={k: dict(pos=g3(v[0], v[1]), yaw=v[2]) for k, v in PL.ENTRIES.items()},
                      zones=[dict(kind=z["kind"], inst=z["inst"], rect=rect_g(z["rect"])) for z in zones]),
    )
    with open(os.path.join(ASSETS, "levels", LEVEL + "_layout.json"), "w", encoding="utf-8") as f:
        json.dump(layout, f, ensure_ascii=False, separators=(",", ":"))
    print("layout: %d instances, %d markers, %d zones" % (len(instances), len(markers), len(zones)))

    root = bpy.data.objects.new(LEVEL + "_ground", None)
    gcoll.objects.link(root)
    for o in gobjs:
        world_uv(o)
        o.parent = root
    export_gltf(root, os.path.join(ASSETS, "levels", LEVEL + "_ground.gltf"))

    R.setup_render((1280, 720))
    if not NO_RENDER:
        os.makedirs(os.path.join(RENDERS, "levels"), exist_ok=True)
        for mood in ("day", "night"):
            R.mood(mood)
            for vn, (loc, tgt) in PL.VIEWS.items():
                R.camera(loc=loc, target=tgt, lens=28)
                R.render(os.path.join(RENDERS, "levels", "%s_%s_%s.png" % (LEVEL, vn, mood)))
    R.mood("day")
    R.sun(energy=3.5, rot=(25, 0, 30))
    bpy.context.scene.render.resolution_x = 1344
    bpy.context.scene.render.resolution_y = int(1344 * (my1 - my0) / (mx1 - mx0))
    R.camera(loc=((mx0 + mx1) / 2, (my0 + my1) / 2, 300), target=((mx0 + mx1) / 2, (my0 + my1) / 2, 0), ortho=(mx1 - mx0))
    bpy.context.scene.camera.rotation_euler = (0, 0, 0)
    bpy.context.scene.camera.data.clip_end = 1000
    R.render(os.path.join(ASSETS, "levels", LEVEL + "_map.png"))
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, LEVEL + ".blend"))
    print("DONE")


if __name__ == "__main__":
    main()
