"""Pure-Python plan of the Old Town level (no bpy). Blender coordinates: X east, Y north, metres.
Used by build_world.py (Blender) and can be imported by tools. Everything the game needs to know about
space is decided here: roads, lanes, blocks, rows of houses, landmarks, markers, surfaces, traffic.
"""
import math
import random

CELL = 2.0  # navigation grid cell (m)
BOUNDS = (-140.0, -100.0, 120.0, 150.0)  # x0, y0, x1, y1 of the grid (incl. water)

# ---------------------------------------------------------------- surfaces (rectangles, painted in order)
# (code, x0, y0, x1, y1). Later entries overwrite earlier ones.
# codes: '#' blocked, 'a' asphalt, 's' sidewalk, 'c' cobble, 'p' park path, 'g' grass, 't' stairs,
#        'q' quay (lower walkway z=-3), 'w' water, 'b' bridge deck, 'z' zebra crossing (asphalt + crossing)
SURF = [
    ("#", -140, -100, 120, 150),
    ("c", -100, -70, 80, 44),          # whole interior: cobble
    ("s", -104, -74, 84, -70), ("s", -104, 44, 84, 48), ("s", -104, -74, -100, 48), ("s", 80, -74, 84, 48),
    ("a", -116, 48, 96, 60),           # avenue (tram in the middle)
    ("a", 84, -86, 96, 60),            # east road
    ("a", -116, -86, 96, -74),         # south road
    ("a", -116, -86, -104, 60),        # west road
    ("s", -116, 60, 96, 64),           # avenue north sidewalk
    ("s", 96, -90, 100, 64), ("s", -120, -90, -116, 64), ("s", -120, -90, 100, -86),  # outer sidewalks
    ("g", -120, 64, 100, 84),          # park strip
    ("p", -120, 72, 100, 76),          # bike path along the park
    ("p", -46, 64, -40, 72), ("p", 30, 64, 36, 72),  # paths from the avenue crossings into the park
    ("p", -46, 76, -40, 84), ("p", 30, 76, 36, 84),
    ("t", -47, 84, -39, 89), ("t", 29, 84, 37, 89),  # stairs down to the quay
    ("q", -120, 89, 100, 95),          # lower quay walkway (z=-3)
    ("w", -140, 95, 120, 150),         # river
    ("b", 52, 84, 64, 110),            # bridge stub (blocked further on)
    ("#", 52, 96, 64, 110),            # barrier on the bridge (cannot pass)
    ("z", -46, 48, -40, 60), ("z", 30, 48, 36, 60),  # zebra crossings over the avenue
    ("z", 84, -42, 96, -36), ("z", -116, 18, -104, 24),
]

# lanes are just cobble; listed for names/addresses and GPS labels
STREETS = {
    "N": ("Северный переулок", (-100, 20, 80, 28)),
    "S": ("Южный переулок", (-100, -42, 80, -34)),
    "W": ("Западная улица", (-60, -70, -52, 44)),
    "E": ("Восточная улица", (30, -70, 38, 44)),
    "Q": ("Часовая площадь", (-52, -6, 30, 20)),
    "R": ("Ресторанная улица", (-52, -6, 30, 0)),
    "A": ("Набережный проспект", (-116, 48, 96, 60)),
}

# ---------------------------------------------------------------- building rows
# A row: street code, start point, direction ('x+' along +X etc.), length, facing yaw (deg, Blender: 0 = front
# faces -Y/south, 180 = faces north, 90 = faces east, -90 = faces west), front line coordinate.
# Houses are placed so their front face sits on the front line.
ROWS = [
    # north blocks: face south onto Северный переулок (front line y=28)
    dict(street="N", axis="x", a0=-99, a1=-61, front=28.0, yaw=0),
    dict(street="N", axis="x", a0=-51, a1=-17, front=28.0, yaw=0),
    dict(street="N", axis="x", a0=-5, a1=29, front=28.0, yaw=0),
    # north blocks: back rows facing the avenue (front line y=44, facing north)
    dict(street="A", axis="x", a0=-99, a1=-61, front=44.0, yaw=180, depth_max=9.5),
    dict(street="A", axis="x", a0=-51, a1=29, front=44.0, yaw=180, depth_max=9.5, skip=(-20, -2)),
    dict(street="A", axis="x", a0=39, a1=79, front=44.0, yaw=180, depth_max=9.5),
    # west block (x -100..-60, y -34..20)
    dict(street="N", axis="x", a0=-99, a1=-61, front=20.0, yaw=180),
    dict(street="S", axis="x", a0=-99, a1=-61, front=-34.0, yaw=0),
    dict(street="W", axis="y", a0=-22, a1=8, front=-60.0, yaw=90, depth_max=10),
    # east block (x 38..80, y -34..20)
    dict(street="N", axis="x", a0=39, a1=79, front=20.0, yaw=180),
    dict(street="S", axis="x", a0=39, a1=79, front=-34.0, yaw=0),
    dict(street="E", axis="y", a0=-22, a1=8, front=38.0, yaw=-90, depth_max=10),
    # restaurant block south side (faces Южный переулок)
    dict(street="S", axis="x", a0=-51, a1=29, front=-34.0, yaw=0),
    # south blocks face north onto Южный переулок (front y=-42)
    dict(street="S", axis="x", a0=-99, a1=-61, front=-42.0, yaw=180),
    dict(street="S", axis="x", a0=-51, a1=29, front=-42.0, yaw=180),
    dict(street="S", axis="x", a0=39, a1=79, front=-42.0, yaw=180),
]

HOUSE_TYPES = ["house_a", "house_b", "house_c", "house_d", "house_e", "house_f", "house_g", "house_h", "house_i",
               "house_j", "house_k", "house_l"]

# landmarks (asset, x, y, yaw, kind)
LANDMARKS = [
    ("clock_tower", -11.0, 28.0 + 4.3, 0, "landmark"),
    ("fountain", -11.0, 7.0, 0, "prop"),
]
# restaurants on the north edge of the restaurant block, facing north onto the square (front line y=-6)
RESTAURANTS = [("pizza", -44.0), ("burger", -30.0), ("sushi", -16.0), ("coffee", -2.0), ("cake", 12.0)]
REST_FRONT = -6.0
# courier base on the north-east block, facing south (front line y=28)
BASE = [("courier_cafe", 46.0, 7.0, 5.0), ("garage", 61.0, 8.0, 8.0), ("snack_kiosk", 74.0, 3.0, 2.4)]
BASE_FRONT = 28.0


def house_dims(meta, name):
    m = meta[name]
    return m["w"], m["d"]


def plan_rows(meta, seed=42):
    """Fill every row with houses. Returns list of dicts: asset, x, y, yaw, street, number."""
    rs = random.Random(seed)
    out = []
    counters = {}
    for row in ROWS:
        a = row["a0"]
        while True:
            cand = [h for h in HOUSE_TYPES if meta[h]["w"] <= row["a1"] - a + 0.01 and
                    meta[h]["d"] <= row.get("depth_max", 99)]
            if not cand:
                break
            h = rs.choice(cand)
            w, d = meta[h]["w"], meta[h]["d"]
            c = a + w / 2
            if row.get("skip") and row["skip"][0] - w / 2 < c < row["skip"][1] + w / 2:
                a = row["skip"][1]
                continue
            yaw = row["yaw"]
            if row["axis"] == "x":
                # front faces -Y when yaw 0: centre is front + d/2 for yaw 0, front - d/2 for yaw 180
                y = row["front"] + d / 2 if yaw == 0 else row["front"] - d / 2
                x = c
            else:
                x = row["front"] - d / 2 if yaw == 90 else row["front"] + d / 2
                y = c
            st = row["street"]
            counters[st] = counters.get(st, 0) + 1
            out.append(dict(asset=h, x=x, y=y, yaw=yaw, street=st, number=counters[st] * 2 - (1 if yaw in (0, 90) else 0)))
            a += w + rs.choice([0.0, 0.0, 0.3])
    return out


# ---------------------------------------------------------------- props
def plan_props(seed=7):
    rs = random.Random(seed)
    P = []  # (asset, x, y, yaw)
    # avenue: lamps + trees on the park side, lamps on the south sidewalk
    for x in range(-110, 96, 14):
        P.append(("lamp_post", x, 46.5, 90))
        P.append(("lamp_post", x + 7, 62.0, -90))
    for x in range(-112, 98, 11):
        P.append(("tree_round" if (x // 11) % 2 else "tree_round_b", x + rs.uniform(-1, 1), 68.0 + rs.uniform(-1, 1), 0))
        P.append(("tree_round" if (x // 11) % 3 else "tree_round_b", x + 5 + rs.uniform(-1, 1), 80.5 + rs.uniform(-1, 1), 0))
    for x in range(-108, 96, 22):
        P.append(("bench", x, 77.2, 180))
        P.append(("trash_bin", x + 2.0, 77.4, 0))
    # embankment parapet along y=84 (segments 4 m) except stairs and bridge
    x = -118
    while x < 98:
        if not (-48 < x < -38 or 28 < x < 38 or 50 < x < 66):
            P.append(("parapet", x + 2, 84.4, 180))
        x += 4
    # square: cafe sets, flower pots, benches, lamps
    for (x, y) in ((-46, 14), (-40, 16), (-34, 14), (14, 15), (20, 13), (25, 16)):
        P.append(("cafe_set" if rs.random() < 0.5 else "cafe_set_turq", x, y, rs.choice([0, 90])))
    for (x, y) in ((-22, 0), (0, 0), (-22, 14), (0, 14), (-30, 23), (8, 23)):
        P.append(("flower_pot", x, y, 0))
    for (x, y, yaw) in ((-11, -1.5, 0), (-24, 7, -90), (2, 7, 90)):
        P.append(("bench", x, y, yaw))
    for (x, y) in ((-50, 2), (-50, 18), (28, 2), (28, 18), (-30, -4), (8, -4)):
        P.append(("lamp_post", x, y, 0))
    # string lights over the restaurant street
    for x in (-37.0, -23.0, -9.0, 5.0, 19.0):
        P.append(("string_lights", x, -3.0, 0))
    for (x, y) in ((-48, -1), (24, -1)):
        P.append(("menu_board", x, y, 180))
    # lanes: lamps every ~16 m, some flower pots / bins / crates / mailboxes
    for x in range(-96, 80, 16):
        if -52 < x < 30:
            continue
        P.append(("lamp_post", x, 21.0, 0))
        P.append(("lamp_post", x + 8, -38.0, 0))
    for y in range(-66, 44, 16):
        P.append(("lamp_post", -53.0, y, 90))
        P.append(("lamp_post", 37.0, y, -90))
    for _ in range(22):
        lane = rs.choice(["N", "S", "W", "E"])
        x0, y0, x1, y1 = STREETS[lane][1]
        if lane in ("N", "S"):
            x, y = rs.uniform(x0 + 4, x1 - 4), rs.choice([y0 + 1.0, y1 - 1.0])
        else:
            x, y = rs.choice([x0 + 1.0, x1 - 1.0]), rs.uniform(y0 + 4, y1 - 4)
        if -52 < x < 30 and -6 < y < 28:
            continue
        P.append((rs.choice(["flower_pot", "trash_bin", "crates", "mailbox", "bollard"]), x, y, rs.choice([0, 90, 180])))
    # base: chargers, bike rack, police booth on the avenue corner
    for x in (40.0, 43.0, 70.0):
        P.append(("charger_station", x, 26.5, 180))
    P.append(("bike_rack", 54.0, 25.5, 0))
    P.append(("police_booth", 20.0, 46.0, 0))
    # traffic lights at the 4 crossings (pole on the sidewalk, head toward the cars)
    for (x, y, yaw) in ((-47.5, 47.0, 90), (-38.5, 61.0, -90), (28.5, 47.0, 90), (37.5, 61.0, -90),
                        (82.5, -35.5, 0), (97.5, -42.5, 180), (-117.5, 25.5, 0), (-102.5, 16.5, 180)):
        P.append(("traffic_light", x, y, yaw))
    # tram stop on the avenue
    P.append(("tram_stop", -80.0, 62.2, 180))
    # road works at the closed ends + bridge
    for (x, y, yaw) in ((-118, 52, 90), (-118, 56, 90), (98, 52, 90), (98, 56, 90)):
        P.append(("barrier_works", x, y, yaw))
    for (x, y) in ((-117, 50), (97, 58), (-12, -60), (-14, -61)):
        P.append(("traffic_cone", x, y, 0))
    return P


# ---------------------------------------------------------------- traffic
def traffic_paths():
    """Right-hand traffic around the loop. Lanes 3 m off the road centre lines.
    Centre lines: avenue y=54, east x=90, south y=-80, west x=-110."""
    cw = [(-110 + 3, 54 - 3), (90 - 3, 54 - 3), (90 - 3, -80 + 3), (-110 + 3, -80 + 3)]   # inner lane, clockwise?
    ccw = [(-110 - 3, -80 - 3), (90 + 3, -80 - 3), (90 + 3, 54 + 3), (-110 - 3, 54 + 3)]
    # orientation check: drive on the right => inner lane goes counter-clockwise when seen from above? We simply
    # give both closed loops; Godot moves cars along point order.
    return [dict(id="loop_inner", points=[list(p) for p in cw[::-1]], loop=True),
            dict(id="loop_outer", points=[list(p) for p in ccw[::-1]], loop=True)]


TRAM = dict(id="tram", points=[[-130, 54], [110, 54]], loop=False, period=90.0)

# crossings: traffic light groups. Cars stop at 'stop' points when red. Pedestrian/bike crossing zone rect.
CROSSINGS = [
    dict(id="X1", rect=(-46, 48, -40, 60), cycle=(14, 3, 12), offset=0.0),
    dict(id="X2", rect=(30, 48, 36, 60), cycle=(14, 3, 12), offset=6.0),
    dict(id="X3", rect=(84, -42, 96, -36), cycle=(14, 3, 12), offset=3.0),
    dict(id="X4", rect=(-116, 18, -104, 24), cycle=(14, 3, 12), offset=9.0),
]


# ---------------------------------------------------------------- navigation grid
def grid():
    x0, y0, x1, y1 = BOUNDS
    W = int((x1 - x0) / CELL)
    H = int((y1 - y0) / CELL)
    g = [["#"] * W for _ in range(H)]
    for code, a, b, c, d in SURF:
        i0 = max(0, int((a - x0) / CELL)); i1 = min(W, int(math.ceil((c - x0) / CELL)))
        j0 = max(0, int((b - y0) / CELL)); j1 = min(H, int(math.ceil((d - y0) / CELL)))
        for j in range(j0, j1):
            for i in range(i0, i1):
                g[j][i] = code
    return g, W, H


def block_rect(g, rect, code="#"):
    x0, y0, x1, y1 = BOUNDS
    a, b, c, d = rect
    H = len(g); W = len(g[0])
    i0 = max(0, int((a - x0) / CELL)); i1 = min(W, int(math.ceil((c - x0) / CELL)))
    j0 = max(0, int((b - y0) / CELL)); j1 = min(H, int(math.ceil((d - y0) / CELL)))
    for j in range(j0, j1):
        for i in range(i0, i1):
            g[j][i] = code
