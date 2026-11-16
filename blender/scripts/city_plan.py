"""Run 2 plan: Business district «Сити» across the river (pure Python, Blender coords: X east, Y north, metres).
Glass towers around a central plaza with a food court, a ring road with traffic and four crossings,
an embankment with the bridge back to the Old Town (south) and the east road to «Берёзки».
Read by build_district.py; the same API as residential_plan.py.
"""
import random

LEVEL = "city"
TITLE = "Деловой центр «Сити»"
CELL = 2.0
BOUNDS = (-120.0, -112.0, 120.0, 112.0)
SURF_MAT = {"p": "plaza", "s": "sidewalk", "a": "asphalt", "z": "asphalt", "g": "grass", "b": "stone", "w": "water"}

SURF = [
    ("#", -120, -112, 120, 112),
    ("p", -116, -88, 116, 108),                     # plaza tiles everywhere inside
    ("a", -91, 59, 91, 71), ("a", -91, -71, 91, -59), ("a", -91, -71, -79, 71), ("a", 79, -71, 91, 71),
    ("s", -95, 71, 95, 75), ("s", -95, -75, 95, -71), ("s", -95, -75, -91, 75), ("s", 91, -75, 95, 75),
    ("s", -79, 55, 79, 59), ("s", -79, -59, 79, -55), ("s", -79, -59, -75, 59), ("s", 75, -59, 79, 59),
    ("a", 91, -6, 120, 6), ("s", 95, 6, 116, 9), ("s", 95, -9, 116, -6),   # east road to «Берёзки»
    ("g", -74, -50, -60, -20), ("g", 60, -50, 74, -20), ("g", -74, 20, -60, 50), ("g", 60, 20, 74, 50),  # lawns
    ("g", -28, 30, -8, 50), ("g", 8, 30, 28, 50), ("g", -30, -52, -12, -34), ("g", 12, -52, 30, -34),
    ("g", -74, -14, -40, 14), ("g", 40, -14, 74, 14),
    ("#", -120, -92, 120, -88),                     # embankment parapet line
    ("w", -120, -112, 120, -92),                    # river
    ("b", -6, -112, 6, -75),                        # bridge from the Old Town
    ("a", -6, -75, 6, -71),
    ("z", -5, 59, 5, 71), ("z", -5, -71, 5, -59), ("z", -91, -5, -79, 5), ("z", 79, -5, 91, 5),
]

STREETS = {
    "B": ("Стеклянный бульвар", (-75, -55, 75, 55)),
    "N": ("Северное кольцо", (-95, 59, 95, 100)),
    "W": ("Западное кольцо", (-120, -75, -79, 75)),
    "E": ("Восточное кольцо", (79, -75, 120, 75)),
}

# (asset, x, y, yaw, group, extra) — towers carry an address
BUILDINGS = [
    # inside the ring, lobbies facing the central plaza
    ("tower_a", -46, 40, 0, "house", dict(street="B", number=1)),
    ("tower_d", 44, 40, 0, "house", dict(street="B", number=3)),
    ("tower_c", -46, -39, 180, "house", dict(street="B", number=2)),
    ("tower_b", 44, -38, 180, "house", dict(street="B", number=4)),
    # outside the ring: north row facing the ring road, west and east columns
    ("tower_b", -58, 92, 0, "house", dict(street="N", number=10)),
    ("tower_c", 0, 90, 0, "house", dict(street="N", number=12)),
    ("tower_d", 58, 91, 0, "house", dict(street="N", number=14)),
    ("tower_a", -106, 38, 90, "house", dict(street="W", number=5)),
    ("tower_c", -106, -38, 90, "house", dict(street="W", number=7)),
    ("tower_a", 106, 40, -90, "house", dict(street="E", number=6)),
    ("tower_c", 106, -40, -90, "house", dict(street="E", number=8)),
    # plaza: food court (pickups wok/salad/burrito), sculpture
    ("food_court", 0, -18, 180, "restaurant", dict(food="court")),
    ("sculpture", 0, 16, 0, "landmark", {}),
    # courier point on the embankment, facing the south ring road
    ("courier_cafe", -50, -78, 180, "shop", {}),
    ("garage", -32, -80, 180, "shop", {}),
    ("snack_kiosk", -18, -78, 180, "shop", {}),
    ("police_booth", 22, -78, 180, "shop", {}),
]


def plan_props(seed=21):
    rs = random.Random(seed)
    P = []
    # ring sidewalks: lamps outside, trees inside
    for x in range(-88, 92, 14):
        P.append(("lamp_post", x, 73.0, 0)); P.append(("lamp_post", x + 7, -73.0, 180))
    for y in range(-68, 72, 14):
        P.append(("lamp_post", -93.0, y, 90)); P.append(("lamp_post", 93.0, y + 7, -90))
    for x in range(-72, 76, 12):
        if abs(x) > 8:
            P.append(("tree_round" if (x // 12) % 2 else "tree_round_b", x, 57.0, 0))
            P.append(("tree_round_b" if (x // 12) % 2 else "tree_round", x, -57.0, 0))
    for y in range(-48, 52, 12):
        if abs(y) > 8:
            P.append(("tree_round", -77.0, y, 0)); P.append(("tree_round_b", 77.0, y, 0))
    # lawns: trees and benches
    for (x0, y0, x1, y1) in ((-74, -50, -60, -20), (60, -50, 74, -20), (-74, 20, -60, 50), (60, 20, 74, 50)):
        for k in range(3):
            P.append(("tree_round" if k % 2 else "tree_round_b", rs.uniform(x0 + 4, x1 - 4), rs.uniform(y0 + 4, y1 - 4), 0))
    # plaza lawns: tree clumps, rows of trees along the boulevards, more lamps
    for (x0, y0, x1, y1) in ((-28, 30, -8, 50), (8, 30, 28, 50), (-30, -52, -12, -34), (12, -52, 30, -34),
                             (-74, -14, -40, 14), (40, -14, 74, 14)):
        for k in range(4):
            P.append(("tree_round" if k % 2 else "tree_round_b", rs.uniform(x0 + 3, x1 - 3), rs.uniform(y0 + 3, y1 - 3), 0))
        P.append(("bench", (x0 + x1) / 2, y0 - 1.2, 180))
    for y in (-46, -34, 34, 46):
        for x in (-34, 34):
            P.append(("lamp_post", x, y, 0))
    for x in (-60, -48, 48, 60):
        P.append(("lamp_post", x, 18, 0)); P.append(("lamp_post", x, -18, 0))
    # central plaza: fountain, planters, benches, cafe sets near the food court, lamps
    P.append(("fountain", -20.0, 4.0, 0))
    P.append(("fountain", 20.0, 4.0, 0))
    for (x, y, yaw) in ((-12, 26, 0), (12, 26, 0), (-30, -4, 90), (30, -4, -90), (-26, 12, 90), (26, 12, -90)):
        P.append(("planter_long", x, y, yaw))
    for (x, y, yaw) in ((-8, 6, 90), (8, 6, -90), (-36, 8, 90), (36, 8, -90)):
        P.append(("bench", x, y, yaw))
    for (x, y) in ((-16, -8), (-24, -10), (16, -8), (24, -10), (-20, -18), (20, -18)):
        P.append(("cafe_set_turq" if rs.random() < 0.5 else "cafe_set", x, y, rs.choice([0, 90])))
    for (x, y) in ((-28, 20), (28, 20), (-28, -14), (28, -14), (0, 30), (0, -40)):
        P.append(("lamp_post", x, y, 0))
    # bike racks + flower pots near the lobbies, trash bins
    for (x, y) in ((-38, 27), (52, 27), (-38, -26), (52, -26), (-66, 79), (8, 79), (66, 79)):
        P.append(("bike_rack", x, y, 0))
        P.append(("trash_bin", x + 2.5, y, 0))
    # courier point: chargers, bike rack
    for x in (-60.0, -57.0, -42.0):
        P.append(("charger_station", x, -76.5, 0))
    P.append(("bike_rack", -10.0, -77.0, 0))
    # embankment parapet + benches
    x = -118
    while x < 118:
        if not (-8 < x < 8):
            P.append(("parapet", x + 2, -88.4, 0))
        x += 4
    for x in (-100, -80, 40, 60, 80, 100):
        P.append(("bench", x, -85.5, 180))
    for x in range(-110, 116, 16):
        if abs(x) > 10:
            P.append(("tree_round", x + 4, -82.0, 0))
    # traffic lights at the four crossings
    for (x, y, yaw) in ((-6.5, 57.5, 90), (6.5, 72.5, -90), (-6.5, -72.5, 90), (6.5, -57.5, -90),
                        (-92.5, -6.5, 0), (-77.5, 6.5, 180), (77.5, -6.5, 0), (92.5, 6.5, 180)):
        P.append(("traffic_light", x, y, yaw))
    # the east road: closed by road works until «Берёзки» opens (the barrier is decoration; the exit zone is before it)
    for (x, y) in ((118, -3), (118, 3)):
        P.append(("barrier_works", x, y, 90))
    return P


def traffic_paths():
    """Right-hand traffic on the ring (centre lines x=±85, y=±65), lanes 3 m off the centre."""
    cw = [(-85 + 3, 65 - 3), (85 - 3, 65 - 3), (85 - 3, -65 + 3), (-85 + 3, -65 + 3)]
    ccw = [(-85 - 3, -65 - 3), (85 + 3, -65 - 3), (85 + 3, 65 + 3), (-85 - 3, 65 + 3)]
    return [dict(id="ring_inner", points=[list(p) for p in cw], loop=True),
            dict(id="ring_outer", points=[list(p) for p in ccw], loop=True)]


TRAM = None
CROSSINGS = [
    dict(id="C1", rect=(-5, 59, 5, 71), cycle=(14, 3, 12), offset=0.0),
    dict(id="C2", rect=(-5, -71, 5, -59), cycle=(14, 3, 12), offset=7.0),
    dict(id="C3", rect=(-91, -5, -79, 5), cycle=(14, 3, 12), offset=3.0),
    dict(id="C4", rect=(79, -5, 91, 5), cycle=(14, 3, 12), offset=10.0),
]
ROAD_MARKS = [  # dashed centre lines (x0, y0, x1, y1)
    (-85, 65, 85, 65), (-85, -65, 85, -65), (-85, -65, -85, 65), (85, -65, 85, 65), (95, 0, 120, 0)]
CURBS = []
WATER = dict(rect=(-140, -150, 140, -92), z=-4.2)
BRIDGE = dict(rect=(-6, -112, 6, -75))

# exits (zones the player rides into) and entry points (where the player appears when arriving from there)
EXITS = [dict(to="old_town", rect=(-6, -112, 6, -100), label="Мост в Старый город"),
         dict(to="berezki", rect=(110, -6, 117, 6), label="Шоссе в «Берёзки»")]
ENTRIES = {"old_town": (0.0, -92.0, 180.0), "berezki": (104.0, 0.0, -90.0)}
PLAYER_START = (-40.0, -73.5, 0.0)

NO_PARKING_DEPTH = 7.0   # red curb zone in front of every tower lobby (towing if a vehicle is left there)


def markers(rs, walk_cells, cell_pos):
    M = []
    for i, (x, y) in enumerate(((-20, -74), (30, -73), (0, 76))):
        M.append(("courier_spawn", x, y, 0, dict(id=i)))
    for k in range(30):
        x, y = cell_pos(rs.choice(walk_cells))
        M.append(("npc", x, y, rs.uniform(-180, 180), dict(id=k)))
    for k, (x, y) in enumerate(((0, 22), (-20, 10), (60, -84))):
        M.append(("tourist_group", x, y, 0, dict(id=k)))
    for k, (x, y) in enumerate(((-72, -52), (72, 52), (100, -60))):
        M.append(("thief", x, y, 0, dict(id=k)))
    M.append(("roadblock", 0.0, 65.0, 0, dict(rect=[-12, 59, 12, 71])))
    M.append(("police_patrol", 0.0, -50.0, 0, dict(route=[(0, -50), (-40, -50), (-40, 50), (40, 50), (40, -50)])))
    return M


LIGHTING_TWEAK = dict(fog_mult=0.8)
MAP_RECT = (-118.0, -100.0, 118.0, 108.0)
VIEWS = {"plaza": ((40, -60, 30), (0, 0, 8)), "towers": ((-20, 20, 12), (-46, 40, 20)),
         "foodcourt": ((0, 5, 6), (0, -18, 3)), "bridge": ((25, -105, 14), (0, -70, 4))}


def addresses(buildings, meta):
    """Door labels for towers: 'Стеклянный бульвар, 4' (towers: one lobby, lifts, guard)."""
    out = {}
    for i, b in enumerate(buildings):
        ex = b[5]
        if "number" in ex:
            st = STREETS[ex["street"]][0]
            out[i] = dict(street=ex["street"], street_name=st, number=ex["number"], corpus=0,
                          label_fmt="%s, %d" % (st, ex["number"]), bignum="%d" % ex["number"])
    return out
