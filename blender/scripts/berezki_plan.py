"""Run 2 plan: residential district «Берёзки» (pure Python, Blender coords: X east, Y north, metres).
Identical prefab panel blocks around four green courtyards, a ring road with traffic, a supermarket, a shawarma and
a bakery kiosk, a courier point by the west entrance. House numbers are deliberately confusing: «7 к.3» stands far
from «7 к.1». Same API as city_plan.py.
"""
import random

LEVEL = "berezki"
TITLE = "Спальный район «Берёзки»"
CELL = 2.0
BOUNDS = (-120.0, -112.0, 120.0, 112.0)
SURF_MAT = {"p": "park_path", "s": "sidewalk", "a": "asphalt", "z": "asphalt", "g": "grass"}

SURF = [
    ("#", -120, -112, 120, 112),
    ("g", -110, -104, 110, 104),
    ("a", -93, 75, 93, 85), ("a", -93, -85, 93, -75), ("a", -93, -85, -83, 85), ("a", 83, -85, 93, 85),
    ("s", -96, 85, 96, 88), ("s", -96, -88, 96, -85), ("s", -96, -88, -93, 88), ("s", 93, -88, 96, 88),
    ("s", -83, 72, 83, 75), ("s", -83, -75, 83, -72), ("s", -83, -75, -80, 75), ("s", 80, -75, 83, 75),
    ("a", -120, -5, -93, 5), ("s", -116, 5, -96, 8), ("s", -116, -8, -96, -5),   # west road from the Old Town
    ("a", -5, 85, 5, 112), ("s", 5, 88, 8, 108), ("s", -8, 88, -5, 108),         # north road to «Сити»
    ("a", -80, -3, 80, 3), ("a", -3, -72, 3, 72),                                # inner driveways (no traffic)
    # yard footpaths in front of the entrances
    ("p", 22, 50, 58, 57), ("p", 56, 18, 63, 42), ("p", 17, 18, 43, 24),
    ("p", -58, 50, -22, 57), ("p", -50, 18, -18, 24),
    ("p", -56, -57, -20, -50), ("p", -50, -33, -30, -27),
    ("p", 22, -57, 58, -50), ("p", 22, -26, 48, -20), ("p", 56, -48, 63, -28),
    ("p", 3, -40, 80, -36), ("p", -80, 36, -3, 40), ("p", -40, 3, -36, 50), ("p", 36, -50, 40, -3),
    ("z", -93, -5, -83, 5), ("z", -5, 75, 5, 85), ("z", -5, -85, 5, -75), ("z", 83, -5, 93, 5),
]

STREETS = {"B": ("Берёзовая", (-96, -88, 96, 88))}

# panel blocks: (asset, x, y, yaw, group, extra); numbers are shown on the plates and big corner numbers
BUILDINGS = [
    ("panel_d", -40, 63, 0, "house", dict(street="B", number=7, corpus=1)),
    ("panel_a", 40, 63, 0, "house", dict(street="B", number=7, corpus=3)),
    ("panel_c", 70, 30, -90, "house", dict(street="B", number=13, corpus=0)),
    ("panel_b", 30, 12, 180, "house", dict(street="B", number=9, corpus=1)),
    ("panel_b", -35, 12, 180, "house", dict(street="B", number=5, corpus=0)),
    ("panel_a", -38, -63, 180, "house", dict(street="B", number=7, corpus=2)),
    ("panel_c", -40, -20, 0, "house", dict(street="B", number=9, corpus=2)),
    ("panel_d", 40, -63, 180, "house", dict(street="B", number=11, corpus=0)),
    ("panel_b", 35, -14, 0, "house", dict(street="B", number=11, corpus=2)),
    ("panel_c", 70, -38, -90, "house", dict(street="B", number=7, corpus=4)),
    # shops and pickups
    ("supermarket", -70, -40, -90, "restaurant", dict(food="grocery")),
    ("kiosk_shawarma", 10, -68, 0, "restaurant", dict(food="shawarma")),
    ("kiosk_bakery", 18, -68, 0, "restaurant", dict(food="bakery")),
    # courier point by the west entrance, facing the ring road
    ("courier_cafe", -74, 42, -90, "shop", {}),
    ("garage", -74, 26, -90, "shop", {}),
    ("snack_kiosk", -77, 14, -90, "shop", {}),
    ("police_booth", 70, -70, 0, "shop", {}),
    # yards
    ("playground", 36, 36, 0, "prop", {}),
    ("playground", -40, -42, 90, "prop", {}),
    ("playground", 45, -40, 0, "prop", {}),
    ("garages_row", 60, 8, 180, "prop", {}),
    ("garages_row", -60, -8, 0, "prop", {}),
    ("dumpsters", -20, 30, 0, "prop", {}),
    ("dumpsters", -15, -60, 0, "prop", {}),
    ("dumpsters", 20, 45, 90, "prop", {}),
    ("bus_stop", -14, -70, 0, "prop", {}),
]


def plan_props(seed=33):
    rs = random.Random(seed)
    P = []
    for x in range(-90, 92, 16):
        P.append(("lamp_post", x, 86.5, 0)); P.append(("lamp_post", x + 8, -86.5, 180))
    for y in range(-80, 82, 16):
        P.append(("lamp_post", -94.5, y, 90)); P.append(("lamp_post", 94.5, y + 8, -90))
    # courtyards: few lamps (dark yards at night), many birches, benches
    for (x, y) in ((20, 36), (-22, 36), (-22, -38), (24, -40), (0, 50), (0, -50)):
        P.append(("lamp_post", x, y, 0))
    yards = [(6, 26, 78, 48), (-78, 26, -6, 48), (-78, -48, -6, -28), (6, -50, 78, -28), (6, 6, 16, 70),
             (-16, 6, -6, 70), (-78, 6, -54, 22), (50, -24, 78, -6)]
    for k in range(46):
        x0, y0, x1, y1 = yards[k % len(yards)]
        P.append(("tree_birch" if rs.random() < 0.75 else "tree_round", rs.uniform(x0, x1), rs.uniform(y0, y1), 0))
    for (x, y, yaw) in ((28, 30, 90), (44, 30, -90), (-46, -48, 0), (-34, -48, 0), (39, -46, 90), (51, -46, -90)):
        P.append(("bench", x, y, yaw))
    for (x, y) in ((24, 46), (-30, 46), (-28, -50), (30, -50), (8, -64), (-74, 6)):
        P.append(("trash_bin", x, y, 0))
    for (x, y) in ((-60, 46), (60, 46), (-60, -30), (60, -46)):
        P.append(("flower_pot", x, y, 0))
    # courier point: chargers on the sidewalk, bike rack
    for y in (30.0, 33.0, 36.0):
        P.append(("charger_station", -81.5, y, 90))
    P.append(("bike_rack", -81.5, 20.0, 90))
    # traffic lights at the crossings
    for (x, y, yaw) in ((-94.5, -6.5, 0), (-81.5, 6.5, 180), (-6.5, 73.5, 90), (6.5, 86.5, -90),
                        (-6.5, -86.5, 90), (6.5, -73.5, -90), (81.5, -6.5, 0), (94.5, 6.5, 180)):
        P.append(("traffic_light", x, y, yaw))
    for (x, y, yaw) in ((-118, -2.5, 90), (-118, 2.5, 90), (-2.5, 110, 0), (2.5, 110, 0)):
        P.append(("barrier_works", x, y, yaw))
    return P


def traffic_paths():
    cw = [(-88 + 2.5, 80 - 2.5), (88 - 2.5, 80 - 2.5), (88 - 2.5, -80 + 2.5), (-88 + 2.5, -80 + 2.5)]
    ccw = [(-88 - 2.5, -80 - 2.5), (88 + 2.5, -80 - 2.5), (88 + 2.5, 80 + 2.5), (-88 - 2.5, 80 + 2.5)]
    return [dict(id="ring_inner", points=[list(p) for p in cw], loop=True),
            dict(id="ring_outer", points=[list(p) for p in ccw], loop=True)]


TRAM = None
CROSSINGS = [
    dict(id="B1", rect=(-93, -5, -83, 5), cycle=(14, 3, 12), offset=0.0),
    dict(id="B2", rect=(-5, 75, 5, 85), cycle=(14, 3, 12), offset=6.0),
    dict(id="B3", rect=(-5, -85, 5, -75), cycle=(14, 3, 12), offset=3.0),
    dict(id="B4", rect=(83, -5, 93, 5), cycle=(14, 3, 12), offset=9.0),
]
ROAD_MARKS = [(-88, 80, 88, 80), (-88, -80, 88, -80), (-88, -80, -88, 80), (88, -80, 88, 80)]
WATER = None
BRIDGE = None

EXITS = [dict(to="old_town", rect=(-118, -5, -110, 5), label="Дорога в Старый город"),
         dict(to="city", rect=(-5, 104, 5, 111), label="Шоссе в «Сити»")]
ENTRIES = {"old_town": (-104.0, 0.0, 90.0), "city": (0.0, 98.0, 0.0)}
PLAYER_START = (-81.5, 24.0, 90.0)
NO_PARKING_DEPTH = 0.0


def markers(rs, walk_cells, cell_pos):
    M = []
    for i, (x, y) in enumerate(((-81, 46), (0, -73), (81, 0))):
        M.append(("courier_spawn", x, y, 0, dict(id=i)))
    for k in range(30):
        x, y = cell_pos(rs.choice(walk_cells))
        M.append(("npc", x, y, rs.uniform(-180, 180), dict(id=k)))
    for k, (x, y) in enumerate(((-60, 40), (60, -20), (-20, -40))):
        M.append(("thief", x, y, 0, dict(id=k)))
    M.append(("roadblock", 0.0, 40.0, 0, dict(rect=[-3, 30, 3, 50])))
    M.append(("police_patrol", 60.0, -73.5, 0, dict(route=[(60, -73.5), (-60, -73.5), (-81.5, -60), (-81.5, 60)])))
    return M


LIGHTING_TWEAK = dict(fog_mult=1.0)
MAP_RECT = (-112.0, -100.0, 112.0, 108.0)
VIEWS = {"yard": ((10, 0, 14), (40, 40, 6)), "street": ((-100, -30, 10), (-70, -40, 4)),
         "kiosks": ((14, -90, 8), (14, -68, 3)), "overview": ((-60, -100, 60), (10, 10, 0))}


def addresses(buildings, meta):
    out = {}
    for i, b in enumerate(buildings):
        ex = b[5]
        if "number" in ex:
            st = STREETS[ex["street"]][0]
            c = int(ex.get("corpus", 0))
            num = "%d" % ex["number"] + (" к.%d" % c if c else "")
            out[i] = dict(street=ex["street"], street_name=st, number=ex["number"], corpus=c,
                          label_fmt="%s, %s" % (st, num), bignum="%d" % ex["number"] + ("к%d" % c if c else ""))
    return out
