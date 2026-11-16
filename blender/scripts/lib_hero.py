"""Run 2: the hero courier rebuilt closer to concept/characters/courier_hero.png.
Same 20-bone skeleton and the same part/bone/ACC_/HELD_ layout as lib_char.human(), so every animation,
the bike/scooter IK and the Godot code keep working. Only the shapes changed:
boxy hoodie jacket with two reflective bands on chest and sleeves, hood, big head with the concept face
(big brown eyes, thick brows, rosy nose, open smile), cargo pants with rolled cuffs, chunky sneakers,
a long-brim cap and a big square backpack with trim, cloche icon and visible shoulder straps.
"""
import math
from mathutils import Vector
from lib_geo import box, cyl, sphere, torus, tube_path, prism, mat, smooth
from lib_char import SK, Body, build_armature, skin, V


def rbox(nm, size, loc, m, r=0.04, seg=4, rot=None):
    """Soft rounded box (loc = centre of the bottom face)."""
    ob = box(nm, size, loc, m, bevel=r, seg=seg, rot=rot)
    smooth(ob, angle=70)
    return ob


def ring_on(nm, a, b, t, R, r, m, n=16):
    """Torus wrapped around a limb segment a->b at fraction t."""
    a, b = V(a), V(b)
    ob = torus(nm, R, r, (0, 0, 0), m, n=n, nr=6)
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    ob.location = a.lerp(b, t)
    return ob


def hero_face(B, hair_c, female=False):
    y0 = -0.196
    zc = 1.47
    white = mat("eye_white", "#ffffff", rough=0.3)
    iris = mat("eye_iris", "#5a3b26", rough=0.25)
    pupil = mat("eye_pupil", "#1d1715", rough=0.2)
    brow_m = mat("hair_" + hair_c.lstrip("#"), hair_c)
    for sx in (-1, 1):
        ex = sx * 0.078
        B.add(sphere("eye%d" % sx, 0.058, (ex, y0 + 0.03, zc + 0.045), white, seg=14, rings=10,
                     scale=(0.95, 0.5, 1.22)), "head")
        B.add(sphere("iris%d" % sx, 0.038, (ex - sx * 0.004, y0 + 0.004, zc + 0.038), iris, seg=12, rings=8,
                     scale=(1, 0.45, 1.2)), "head")
        B.add(sphere("pup%d" % sx, 0.022, (ex - sx * 0.004, y0 - 0.004, zc + 0.038), pupil, seg=10, rings=6,
                     scale=(1, 0.45, 1.2)), "head")
        B.add(sphere("hl%d" % sx, 0.011, (ex - sx * 0.016, y0 - 0.012, zc + 0.062), white, seg=6, rings=4), "head")
        pts = [(ex + sx * k * 0.03, y0 + 0.012 + abs(k) * 0.006, zc + 0.128 - abs(k) * 0.012) for k in (-1.2, 0, 1.2)]
        B.add(tube_path("brow%d" % sx, pts, 0.012, brow_m, n=6), "head")
        B.add(sphere("cheek%d" % sx, 0.036, (sx * 0.125, y0 + 0.04, zc - 0.035), mat("cheek", "#f29a8a"), seg=8,
                     rings=6, scale=(1, 0.35, 0.65)), "head")
        if female:
            B.add(box("lash%d" % sx, (0.03, 0.01, 0.01), (ex + sx * 0.05, y0 + 0.02, zc + 0.085),
                      mat("lash", "#2b2320"), rot=(0, math.radians(sx * -35), 0)), "head")
    B.add(sphere("nose", 0.04, (0, y0 - 0.025, zc - 0.012), mat("nose", "#f0a487", rough=0.6), seg=12, rings=8,
                 scale=(1.05, 0.95, 0.85)), "head")
    # open smile: D-shaped mouth with a flat top, teeth, tongue
    pts = [(0.062, 0.0)] + [(math.cos(a) * 0.062, math.sin(a) * 0.05)
                            for a in [-k * math.pi / 10 for k in range(1, 10)]] + [(-0.062, 0.0)]
    B.add(prism("mouth", pts, 0.03, (0, y0 + 0.028, zc - 0.068), mat("mouth", "#7a2a2a"), axis="Y"), "head")
    B.add(box("teeth", (0.1, 0.031, 0.016), (0, y0 + 0.026, zc - 0.083), mat("teeth", "#fbfbf6")), "head")
    B.add(sphere("tongue", 0.03, (0, y0 + 0.022, zc - 0.11), mat("tongue", "#e0776f"), seg=8, rings=6,
                 scale=(1.2, 0.35, 0.5)), "head")


def courier_human(name, coll, spec):
    rig = build_armature(name, coll)
    B = Body(name, coll)
    sk = skin(spec.get("skin", "#f2c39b"))
    jk = spec.get("top_m") or mat("jacket", "turq", rough=0.6)
    refl = mat("reflective", "#d8e3e6", rough=0.3)
    seam = mat("seam", "#2f3b3c", rough=0.7)
    pants = mat("cloth_" + spec.get("pants", "#56483f").lstrip("#"), spec.get("pants", "#56483f"))
    cuff_m = mat("pants_cuff", "#776a60")
    shoes = mat("cloth_" + spec.get("shoes", "#c8763a").lstrip("#"), spec.get("shoes", "#c8763a"))
    sole = mat("sole", "#f4efe6")
    female = spec.get("female", False)
    wsc = 0.94 if female else 1.0

    # ---- torso
    B.add(rbox("pelvis", (0.33 * wsc, 0.22, 0.16), (0, 0.0, 0.64), pants, r=0.07), "hips")
    B.add(rbox("belly", (0.37 * wsc, 0.25, 0.24), (0, 0.0, 0.76), jk, r=0.09), "spine")
    B.add(rbox("hem", (0.375 * wsc, 0.255, 0.05), (0, 0.0, 0.745), jk, r=0.024), "spine")
    B.add(rbox("chest", (0.40 * wsc, 0.26, 0.26), (0, 0.0, 0.98), jk, r=0.1), "chest")
    B.add(sphere("shoulders", 0.2 * wsc, (0, 0.0, 1.17), jk, seg=16, rings=8, scale=(1.05, 0.66, 0.36)), "chest")
    for z in (1.04, 1.115):
        B.add(rbox("stripe", (0.408 * wsc, 0.268, 0.028), (0, 0.0, z), refl, r=0.012, seg=2), "chest")
    B.add(box("zip", (0.012, 0.012, 0.42), (0, -0.131, 0.77), seam), "chest")
    B.add(box("zip_pull", (0.02, 0.012, 0.035), (0.008, -0.136, 1.1), mat("zip", "#d9d9d9")), "chest")
    for sx in (-1, 1):
        B.add(box("pocket%d" % sx, (0.012, 0.01, 0.1), (sx * 0.1, -0.127, 0.8), seam,
                  rot=(0, math.radians(sx * 18), 0)), "spine")
    B.add(sphere("hood", 0.14, (0, 0.085, 1.21), jk, seg=14, rings=8, scale=(1.25, 0.75, 0.6)), "chest")
    B.add(torus("collar", 0.072, 0.03, (0, -0.005, 1.205), jk), "chest")
    B.capsule("neck", (0, 0, 1.17), (0, 0, 1.3), 0.052, 0.052, sk, "neck", caps=False)

    # ---- head
    B.add(sphere("head", 0.215, (0, 0, 1.47), sk, seg=24, rings=16, scale=(1.0, 0.95, 1.04)), "head")
    for sx in (-1, 1):
        B.add(sphere("ear%d" % sx, 0.055, (sx * 0.208, 0.012, 1.455), sk, seg=10, rings=8, scale=(0.42, 0.72, 1.0)),
              "head")
        B.add(sphere("earin%d" % sx, 0.03, (sx * 0.222, 0.0, 1.455), mat("ear_in", "#e59b7c"), seg=8, rings=6,
                     scale=(0.3, 0.6, 0.9)), "head")
    hero_face(B, spec.get("hair_c", "#5b3a26"), female)

    # ---- arms
    cuffm = mat("jacket_cuff", "#1d8a84")
    for s, sx in (("L", 1), ("R", -1)):
        ua0, ua1 = SK["upper_arm_" + s][0], SK["upper_arm_" + s][1]
        fa0, fa1 = SK["forearm_" + s][0], SK["forearm_" + s][1]
        B.add(sphere("shoulder" + s, 0.075, ua0, jk, seg=12, rings=8), "clavicle_" + s)
        B.capsule("uarm" + s, ua0, ua1, 0.07, 0.062, jk, "upper_arm_" + s)
        B.capsule("farm" + s, fa0, fa1, 0.062, 0.056, jk, "forearm_" + s)
        B.add(ring_on("uband" + s, ua0, ua1, 0.55, 0.066, 0.013, refl), "upper_arm_" + s)
        B.add(ring_on("fband" + s, fa0, fa1, 0.35, 0.06, 0.013, refl), "forearm_" + s)
        B.add(ring_on("cuff" + s, fa0, fa1, 0.97, 0.05, 0.016, cuffm), "forearm_" + s)
        hp = V(SK["hand_" + s][0]) + (V(SK["hand_" + s][1]) - V(SK["hand_" + s][0])) * 0.5
        B.add(sphere("hand" + s, 0.062, hp, sk, seg=12, rings=8, scale=(0.72, 0.95, 1.15)), "hand_" + s)
        B.add(sphere("thumb" + s, 0.025, hp + Vector((-sx * 0.005, -0.05, 0.025)), sk, seg=8, rings=6,
                     scale=(1, 1, 1.5)), "hand_" + s)
        for k in range(3):
            B.add(sphere("fing%d%s" % (k, s), 0.018, hp + Vector((sx * 0.012, -0.03 + k * 0.025, -0.06)), sk, seg=6,
                         rings=4, scale=(0.9, 0.9, 1.4)), "hand_" + s)

    # ---- legs
    for s, sx in (("L", 1), ("R", -1)):
        B.capsule("thigh" + s, SK["thigh_" + s][0], SK["thigh_" + s][1], 0.088, 0.078, pants, "thigh_" + s)
        B.capsule("shin" + s, SK["shin_" + s][0], (sx * 0.10, 0, 0.16), 0.077, 0.077, pants, "shin_" + s)
        B.add(cyl("pcuff" + s, 0.086, 0.075, (sx * 0.10, 0, 0.1), cuff_m, n=14, bevel=0.012), "shin_" + s)
        B.add(rbox("cargo" + s, (0.04, 0.11, 0.12), (sx * 0.178, 0.0, 0.42), pants, r=0.015, seg=2), "thigh_" + s)
        B.add(box("cargoflap" + s, (0.045, 0.115, 0.02), (sx * 0.18, 0.0, 0.53), seam), "thigh_" + s)
        B.add(rbox("sole" + s, (0.135, 0.29, 0.04), (sx * 0.10, -0.06, 0.0), sole, r=0.018, seg=3), "foot_" + s)
        B.add(rbox("shoe" + s, (0.13, 0.26, 0.11), (sx * 0.10, -0.045, 0.03), shoes, r=0.048), "foot_" + s)
        B.add(sphere("toe" + s, 0.066, (sx * 0.10, -0.15, 0.06), shoes, seg=12, rings=8, scale=(1.0, 0.9, 0.62)),
              "foot_" + s)
        B.add(rbox("tongue" + s, (0.07, 0.06, 0.05), (sx * 0.10, -0.06, 0.11), shoes, r=0.02, seg=2,
                   rot=(math.radians(-25), 0, 0)), "foot_" + s)
        for k in range(3):
            B.add(box("lace%d%s" % (k, s), (0.07, 0.014, 0.012), (sx * 0.10, -0.075 - k * 0.028, 0.128 - k * 0.012),
                      sole), "foot_" + s)
    for fn in spec.get("extras", []):
        fn(B)
    # concept proportions: a bigger head (everything on the head bone, incl. hair/caps/helmets, around the neck)
    k = spec.get("head_k", 1.12)
    piv = Vector((0, 0, 1.3))
    for ob, bone, _sep in B.parts:
        if bone == "head":
            ob.location = piv + (Vector(ob.location) - piv) * k
            ob.scale = Vector(ob.scale) * k
    return rig, B.finish(rig)


def hero_hair_short(c, sep="ACC_hair_short"):
    def f(B):
        m = mat("hair_" + c.lstrip("#"), c)
        B.add(sphere("hs", 0.222, (0, 0.03, 1.53), m, seg=18, rings=10, scale=(1.02, 1.0, 0.86)), "head", sep)
        for sx in (-1, 1):
            B.add(sphere("hside%d" % sx, 0.075, (sx * 0.185, 0.03, 1.52), m, seg=10, rings=8, scale=(0.55, 1.1, 1.0)),
                  "head", sep)
        B.add(sphere("hnape", 0.12, (0, 0.15, 1.46), m, seg=12, rings=8, scale=(1.3, 0.55, 0.8)), "head", sep)
        for k in range(3):
            B.add(sphere("hfr%d" % k, 0.05, (-0.07 + k * 0.07, -0.175, 1.6 - abs(k - 1) * 0.01), m, seg=8, rings=6,
                         scale=(1.2, 0.6, 0.7)), "head", sep)
    return f


def hero_hair_ponytail(c, sep="ACC_hair_ponytail"):
    def f(B):
        m = mat("hair_" + c.lstrip("#"), c)
        B.add(sphere("hp", 0.225, (0, 0.035, 1.53), m, seg=18, rings=10, scale=(1.03, 1.0, 0.88)), "head", sep)
        for sx in (-1, 1):
            for k in range(4):
                B.add(sphere("hw%d%d" % (sx, k), 0.062 - k * 0.006,
                             (sx * (0.19 + 0.012 * (k % 2)), 0.02 + k * 0.012, 1.5 - k * 0.075), m, seg=10, rings=8,
                             scale=(0.7, 1.0, 1.05)), "head", sep)
        for k in range(3):
            B.add(sphere("hfr%d" % k, 0.05, (-0.07 + k * 0.07, -0.175, 1.6 - abs(k - 1) * 0.012), m, seg=8, rings=6,
                         scale=(1.2, 0.6, 0.7)), "head", sep)
        B.add(sphere("hpt0", 0.06, (0, 0.215, 1.57), m, seg=10, rings=8), "head", sep)
        B.add(tube_path("hptail", [(0, 0.23, 1.57), (0, 0.29, 1.53), (0.02, 0.3, 1.44), (0.0, 0.27, 1.36)], 0.055, m,
                        n=10), "head", sep)
        B.add(sphere("hpt1", 0.065, (0.015, 0.295, 1.47), m, seg=10, rings=8, scale=(1, 1, 1.3)), "head", sep)
        B.add(torus("hptie", 0.04, 0.014, (0, 0.235, 1.565), mat("hair_tie", "#ef6a5b"),
                    rot=(math.radians(70), 0, 0)), "head", sep)
    return f


def hero_cap(c, sep="ACC_cap"):
    def f(B):
        m = mat("cap_" + c.lstrip("#"), c, rough=0.6)
        B.add(sphere("cp", 0.232, (0, 0.015, 1.605), m, seg=18, rings=10, scale=(1.0, 1.04, 0.64)), "head", sep)
        B.add(sphere("cpv", 0.2, (0, -0.2, 1.64), m, seg=18, rings=8, scale=(0.84, 0.68, 0.08)), "head", sep)
        B.add(sphere("cpb", 0.024, (0, 0.015, 1.752), m, seg=8, rings=5), "head", sep)
        icon = mat("bag_icon", "#fff6e6")
        B.add(sphere("cpi", 0.03, (0, -0.2, 1.69), icon, seg=8, rings=5, scale=(1.1, 0.35, 0.75)), "head", sep)
        B.add(box("cpib", (0.07, 0.01, 0.008), (0, -0.204, 1.672), icon), "head", sep)
    return f


def hero_bag(sep="ACC_bag", c="turq"):
    def f(B):
        m = mat("bag_" + c, c, rough=0.5)
        trim = mat("bag_trim", "#2c3234", rough=0.6)
        y = 0.31
        w, d, h, z0 = 0.5, 0.36, 0.52, 0.76
        B.add(rbox("bag", (w, d, h), (0, y, z0), m, r=0.05), "chest", sep)
        for zz in (z0 - 0.005, z0 + h - 0.03):
            B.add(rbox("bagrim", (w + 0.02, d + 0.02, 0.035), (0, y, zz), trim, r=0.015, seg=2), "chest", sep)
        for sx in (-1, 1):
            for sy in (-1, 1):
                B.add(cyl("bagedge", 0.016, h, (sx * w / 2, y + sy * d / 2, z0), trim, n=6), "chest", sep)
        B.add(box("baglidline", (w + 0.012, d + 0.012, 0.012), (0, y, z0 + h - 0.1), trim), "chest", sep)
        icon = mat("bag_icon", "#fff6e6")
        by = y + d / 2 + 0.004
        B.add(box("iconbase", (0.22, 0.012, 0.018), (0, by, z0 + 0.17), icon), "chest", sep)
        B.add(sphere("icon", 0.09, (0, by, z0 + 0.19), icon, seg=14, rings=8, scale=(1.05, 0.12, 0.72)), "chest", sep)
        B.add(sphere("iconknob", 0.016, (0, by, z0 + 0.258), icon, seg=6, rings=4), "chest", sep)
        for k in range(3):
            x = -0.04 + k * 0.04
            pts = [(x + 0.012 * math.sin(t * 2.4), by + 0.004, z0 + 0.29 + t * 0.022) for t in range(6)]
            B.add(tube_path("steam%d" % k, pts, 0.006, icon, n=5), "chest", sep)
        strap = mat("bag_strap", "#3a4244", rough=0.7)
        for sx in (-1, 1):
            B.add(tube_path("strap%d" % sx, [(sx * 0.11, 0.14, 1.12), (sx * 0.12, 0.05, 1.22), (sx * 0.125, -0.12, 1.17),
                                             (sx * 0.135, -0.138, 1.0), (sx * 0.14, -0.12, 0.84),
                                             (sx * 0.17, 0.05, 0.8), (sx * 0.2, 0.14, 0.82)], 0.022, strap, n=6),
                  "chest", sep)
        B.add(box("chest_strap", (0.26, 0.014, 0.025), (0, -0.142, 1.02), strap), "chest", sep)
    return f
