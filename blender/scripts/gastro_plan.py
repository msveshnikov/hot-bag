"""Run 3 plan: «Гастроквартал и Большой парк» (pure Python, Blender coords: X east, Y north, metres).
East half: a ring road around the restaurant quarter — the covered market on its square, a cobbled food street with
four restaurants (dumplings, ramen, grill, pancakes), old houses to deliver to. West half: the Big Park — a pond
(ice on snow days), a bandstand, a playground, paths and gates; motor vehicles are not allowed inside (park paths
'p' and grass 'g' are banned for the moped and the e-car). Deliveries into the park go to MARK_park_spot benches.
The Old Town is to the east. Same API as city_plan.py / berezki_plan.py, plus POND.
"""
import random
import math

LEVEL = "gastro"
TITLE = "Гастроквартал и Большой парк"
CELL = 2.0
BOUNDS = (-120.0, -112.0, 120.0, 112.0)
SURF_MAT = {"p": "park_path", "s": "sidewalk", "a": "asphalt", "z": "asphalt", "g": "grass", "c": "cobble"}

POND = dict(c=(-62.0, 4.0), r=(22.0, 15.0))

SURF = [
    ("#", -120, -112, 120, 112),
    ("c", -14, -108, 117, 108),                               # whole quarter: cobble
    ("g", -116, -104, -14, 104),                              # the Big Park
    # ring road around the quarter (centre lines y=±80, x=-6 and x=88)
    ("a", -11, 75, 93, 85), ("a", -11, -85, 93, -75), ("a", -11, -85, -1, 85), ("a", 83, -85, 93, 85),
    ("s", -14, 85, 96, 88), ("s", -14, -88, 96, -85), ("s", -14, -88, -11, 88), ("s", 93, -88, 96, 88),
    ("s", -1, 72, 83, 75), ("s", -1, -75, 83, -72), ("s", -1, -75, 2, 75), ("s", 80, -75, 83, 75),
    ("a", 93, -5, 120, 5), ("s", 96, 5, 116, 8), ("s", 96, -8, 116, -5),   # east road to the Old Town
    # park paths: loop around the pond, cross paths to the gates, a bike path along the edge
    ("p", -90, 22, -34, 26), ("p", -90, -18, -34, -14), ("p", -90, -18, -86, 26), ("p", -38, -18, -34, 26),
    ("p", -34, 2, -14, 6),                                    # east gate -> loop
    ("p", -64, 26, -60, 96),                                  # north gate -> bandstand -> loop
    ("p", -64, -96, -60, -18),                                # south path
    ("p", -112, -98, -16, -94), ("p", -112, 94, -16, 98), ("p", -112, -98, -108, 98),   # perimeter path
    ("p", -34, -52, -14, -48), ("p", -100, -52, -64, -48),    # second east gate, path to the playground
    ("p", -74, 40, -50, 60),                                  # bandstand clearing
    ("z", -11, -5, -1, 5), ("z", 83, -5, 93, 5), ("z", -5, 75, 5, 85), ("z", -5, -85, 5, -75),
    ("z", -11, -55, -1, -45),
]

STREETS = {
    "G": ("Гастрономическая улица", (2, -10, 80, 12)),
    "R": ("Рыночная площадь", (2, 12, 80, 72)),
    "N": ("Северная набережная", (-14, 85, 117, 108)),
    "S": ("Южная улица", (-14, -108, 117, -85)),
    "L": ("Переулок Пекарей", (2, -72, 80, -10)),
    "P": ("Большой парк", (-116, -104, -14, 104)),
}

# (asset, x, y, yaw, group, extra) — houses carry street + number (doors come from the house assets)
BUILDINGS = [
    # the covered market on its square, front (stalls) facing south
    ("market_hall", 40, 56, 0, "restaurant", dict(food="market")),
    # restaurants on the south side of the food street, facing north
    ("restaurant_dumplings", 12, -14, 180, "restaurant", dict(food="dumplings")),
    ("restaurant_ramen", 26, -14, 180, "restaurant", dict(food="ramen")),
    ("restaurant_grill", 54, -14, 180, "restaurant", dict(food="grill")),
    ("restaurant_pancakes", 68, -14, 180, "restaurant", dict(food="pancakes")),
    # houses on the north side of the food street, facing south (backs to the market square)
    ("house_c", 8, 18, 0, "house", dict(street="G", number=1)),
    ("house_h", 76, 18, 0, "house", dict(street="G", number=3)),
    # Переулок Пекарей: two rows facing each other across the lane y=-40
    ("house_a", 10, -27, 180, "house", dict(street="L", number=2)),
    ("house_e", 24, -26, 180, "house", dict(street="L", number=4)),
    ("house_j", 40, -27, 180, "house", dict(street="L", number=6)),
    ("house_k", 58, -26, 180, "house", dict(street="L", number=8)),
    ("house_b", 73, -27, 180, "house", dict(street="L", number=10)),
    ("house_d", 10, -55, 0, "house", dict(street="L", number=1)),
    ("house_g", 25, -55, 0, "house", dict(street="L", number=3)),
    ("house_h", 42, -55, 0, "house", dict(street="L", number=5)),
    ("house_f", 58, -55, 0, "house", dict(street="L", number=7)),
    ("house_l", 73, -55, 0, "house", dict(street="L", number=9)),
    # outside the ring: north and south rows facing the ring road
    ("house_k", 10, 98, 0, "house", dict(street="N", number=11)),
    ("house_d", 26, 98, 0, "house", dict(street="N", number=13)),
    ("house_e", 42, 98, 0, "house", dict(street="N", number=15)),
    ("house_j", 58, 98, 0, "house", dict(street="N", number=17)),
    ("house_c", 74, 98, 0, "house", dict(street="N", number=19)),
    ("house_i", 10, -98, 180, "house", dict(street="S", number=20)),
    ("house_h", 26, -98, 180, "house", dict(street="S", number=22)),
    ("house_a", 42, -98, 180, "house", dict(street="S", number=24)),
    ("house_k", 58, -98, 180, "house", dict(street="S", number=26)),
    ("house_g", 74, -98, 180, "house", dict(street="S", number=28)),
    # courier point by the east road (from the Old Town)
    ("courier_cafe", 101, 22, 0, "shop", {}),
    ("garage", 111, 24, 0, "shop", {}),
    ("snack_kiosk", 101, -14, 180, "shop", {}),
    ("police_booth", 110, -16, 180, "shop", {}),
    # the park
    ("bandstand", -62, 50, 0, "landmark", {}),
    ("playground", -86, -60, 0, "prop", {}),
    ("park_gate", -16, 4, -90, "prop", {}),
    ("park_gate", -16, -50, -90, "prop", {}),
    ("park_gate", -62, 101, 180, "prop", {}),
]


def plan_props(seed=47):
    rs = random.Random(seed)
    P = []
    # ring sidewalks: lamps and trees
    for x in range(-6, 92, 14):
        P.append(("lamp_post", x, 86.5, 0)); P.append(("lamp_post", x + 7, -86.5, 180))
    for y in range(-80, 82, 14):
        P.append(("lamp_post", -12.5, y, 90)); P.append(("lamp_post", 94.5, y + 7, -90))
    for x in range(6, 80, 12):
        P.append(("tree_round" if (x // 12) % 2 else "tree_round_b", x, 73.5, 0))
    # market square: cafe sets, planters, a fountain, lamps, bike racks
    P.append(("fountain", 40.0, 30.0, 0))
    for (x, y) in ((20, 36), (26, 30), (54, 36), (60, 30), (20, 24), (60, 24)):
        P.append(("cafe_set_turq" if rs.random() < 0.5 else "cafe_set", x, y, rs.choice([0, 90])))
    for (x, y) in ((14, 42), (66, 42), (28, 44), (52, 44)):
        P.append(("lamp_post", x, y, 0))
    for (x, y, yaw) in ((8, 32, 90), (76, 32, -90)):
        P.append(("planter_long", x, y, yaw))
    # food street: lamps both sides, cafe sets in front of the restaurants, menus
    for x in range(4, 80, 10):
        P.append(("lamp_post", x, 9.5, 0)); P.append(("lamp_post", x + 5, -7.5, 180))
    for (x, y) in ((19, -4), (40, -4), (61, -4)):
        P.append(("cafe_set", x, y, 0))
    for (x, y) in ((33, -8), (47, -8)):
        P.append(("flower_pot", x, y, 0))
    P.append(("bike_rack", 40.0, 9.0, 0))
    # Переулок Пекарей
    for x in range(6, 80, 16):
        P.append(("lamp_post", x, -36.5, 0))
    for (x, y) in ((17, -44), (49, -36), (66, -44)):
        P.append(("trash_bin", x, y, 0))
    # courier point: chargers, bike rack
    for x in (96.5, 99.5, 102.5):
        P.append(("charger_station", x, 9.5, 0))
    P.append(("bike_rack", 108.0, 9.5, 0))
    # the park: trees everywhere on the grass (not on paths / pond), benches around the pond, lamps on paths
    cx, cy = POND["c"]
    rx, ry = POND["r"]
    placed = 0
    tries = 0
    while placed < 110 and tries < 3000:
        tries += 1
        x, y = rs.uniform(-112, -18), rs.uniform(-100, 100)
        if ((x - cx) / (rx + 6)) ** 2 + ((y - cy) / (ry + 6)) ** 2 < 1.0:
            continue
        if any(a - 2 < x < c + 2 and b - 2 < y < d + 2 for (code, a, b, c, d) in SURF if code == "p"):
            continue
        if -98 < x < -74 and -70 < y < -50:   # playground
            continue
        if -76 < x < -48 and 38 < y < 62:     # bandstand clearing
            continue
        P.append((rs.choice(["tree_round", "tree_round_b", "tree_birch", "tree_round"]), x, y, 0))
        placed += 1
    for k in range(10):
        a = k / 10 * 2 * math.pi + 0.3
        x, y = cx + math.cos(a) * (rx + 3.5), cy + math.sin(a) * (ry + 3.5)
        if -36 < x < -32:
            continue
        P.append(("bench", x, y, math.degrees(a) - 90))   # facing the pond
    for (x, y) in ((-88, 24), (-36, 24), (-88, -16), (-36, -16), (-62, 30), (-62, 70), (-62, 90), (-62, -40),
                   (-62, -80), (-24, 4), (-24, -50), (-90, -50), (-110, 0), (-110, 60), (-110, -60), (-40, 96),
                   (-90, 96), (-40, -96), (-90, -96)):
        P.append(("lamp_post", x, y, 0))
    for (x, y, yaw) in ((-70, 46, 90), (-54, 46, -90), (-80, -46, 0), (-30, 8, 180), (-30, -46, 180)):
        P.append(("bench", x, y, yaw))
    for (x, y) in ((-66, 42), (-40, -12), (-84, 20), (-28, -54)):
        P.append(("trash_bin", x, y, 0))
    # traffic lights at the crossings
    for (x, y, yaw) in ((-12.5, -6.5, 0), (0.5, 6.5, 180), (81.5, -6.5, 0), (94.5, 6.5, 180),
                        (-6.5, 73.5, 90), (6.5, 86.5, -90), (-6.5, -86.5, 90), (6.5, -73.5, -90)):
        P.append(("traffic_light", x, y, yaw))
    return P


def traffic_paths():
    """Right-hand traffic on the ring (centre lines x=-6 / 88, y=±80), lanes 2.5 m off the centre."""
    cw = [(-6 + 2.5, 80 - 2.5), (88 - 2.5, 80 - 2.5), (88 - 2.5, -80 + 2.5), (-6 + 2.5, -80 + 2.5)]
    ccw = [(-6 - 2.5, -80 - 2.5), (88 + 2.5, -80 - 2.5), (88 + 2.5, 80 + 2.5), (-6 - 2.5, 80 + 2.5)]
    return [dict(id="ring_inner", points=[list(p) for p in cw], loop=True),
            dict(id="ring_outer", points=[list(p) for p in ccw], loop=True)]


TRAM = None
CROSSINGS = [
    dict(id="G1", rect=(-11, -5, -1, 5), cycle=(14, 3, 12), offset=0.0),
    dict(id="G2", rect=(83, -5, 93, 5), cycle=(14, 3, 12), offset=6.0),
    dict(id="G3", rect=(-5, 75, 5, 85), cycle=(14, 3, 12), offset=3.0),
    dict(id="G4", rect=(-5, -85, 5, -75), cycle=(14, 3, 12), offset=9.0),
    dict(id="G5", rect=(-11, -55, -1, -45), cycle=(14, 3, 12), offset=4.0),
]
ROAD_MARKS = [(-6, 80, 88, 80), (-6, -80, 88, -80), (-6, -80, -6, 80), (88, -80, 88, 80), (93, 0, 120, 0)]
WATER = None
BRIDGE = None

EXITS = [dict(to="old_town", rect=(110, -5, 117, 5), label="Проспект в Старый город")]
ENTRIES = {"old_town": (104.0, 0.0, -90.0)}
PLAYER_START = (104.0, 12.0, 0.0)
NO_PARKING_DEPTH = 0.0

PARK_SPOTS = [
    (-62.0, -14.0, 0, "Большой парк, у пруда (южный берег)"),
    (-62.0, 24.0, 180, "Большой парк, у пруда (северный берег)"),
    (-62.0, 40.0, 180, "Большой парк, у эстрады"),
    (-86.0, -50.0, 0, "Большой парк, детская площадка"),
    (-36.0, 4.0, 90, "Большой парк, восточные ворота"),
    (-110.0, 30.0, 90, "Большой парк, западная аллея"),
    (-62.0, 94.0, 180, "Большой парк, северные ворота"),
]


def markers(rs, walk_cells, cell_pos):
    M = []
    for i, (x, y) in enumerate(((0, 73.5), (40, -73.5), (94, 40))):
        M.append(("courier_spawn", x, y, 0, dict(id=i)))
    for k in range(34):
        x, y = cell_pos(rs.choice(walk_cells))
        M.append(("npc", x, y, rs.uniform(-180, 180), dict(id=k)))
    for k, (x, y) in enumerate(((40, 18), (-62, -26), (-60, 34))):
        M.append(("tourist_group", x, y, 0, dict(id=k)))
    for k, (x, y) in enumerate(((20, -40), (70, 40), (100, -30))):
        M.append(("thief", x, y, 0, dict(id=k)))
    for k, (x, y, yaw, label) in enumerate(PARK_SPOTS):
        M.append(("park_spot", x, y, yaw, dict(id=k, label=label)))
    M.append(("roadblock", 40.0, -40.0, 0, dict(rect=[34, -44, 46, -36])))
    M.append(("police_patrol", 40.0, 0.0, 0, dict(route=[(4, 2), (78, 2), (78, -40), (4, -40)])))
    return M


LIGHTING_TWEAK = dict(fog_mult=0.9)
MAP_RECT = (-118.0, -108.0, 118.0, 108.0)
VIEWS = {"market": ((40, 12, 8), (40, 50, 6)), "foodstreet": ((-2, 2, 6), (40, -10, 3)),
         "park": ((-20, -30, 16), (-62, 10, 2)), "overview": ((60, -110, 70), (0, 0, 0))}


def addresses(buildings, meta):
    """Old-town style houses: 'Переулок Пекарей, 4, под. 1' (doors come from the house assets)."""
    out = {}
    for i, b in enumerate(buildings):
        ex = b[5]
        if "number" in ex:
            st = STREETS[ex["street"]][0]
            out[i] = dict(street=ex["street"], street_name=st, number=ex["number"], corpus=0,
                          label_fmt="%s, %d" % (st, ex["number"]), bignum="%d" % ex["number"])
    return out
