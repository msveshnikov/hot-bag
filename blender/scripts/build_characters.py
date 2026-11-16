"""Task 2: cartoon humans with the shared skeleton + procedural animation library.
blender -b --factory-startup -P build_characters.py -- [--no-render] [--only courier_m,mentor] [--anims idle,walk]
Writes blender/characters.blend, assets/characters/<name>.gltf, renders/characters/*.png
"""
import bpy
import sys
import os
import math
import json

sys.path.insert(0, os.path.dirname(__file__))
from lib_geo import *  # noqa
from lib_char import *  # noqa
from lib_hero import courier_human, hero_hair_short, hero_hair_ponytail, hero_cap, hero_bag
import lib_render as R
from mathutils import Vector, Quaternion

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NO_RENDER = "--no-render" in ARGS
ONLY = ARGS[ARGS.index("--only") + 1].split(",") if "--only" in ARGS else None
ANIMS = ARGS[ARGS.index("--anims") + 1].split(",") if "--anims" in ARGS else None

# --- vehicle mount points (must match build_vehicles.py) ---
BIKE = dict(seat_hips=Vector((0, 0.30, 0.83)), crank=Vector((0, 0.15, 0.34)), crank_r=0.13,
            grip_y=-0.22, grip_z=1.0, grip_x=0.24, lean=32)
SCOOT = dict(deck_z=0.13, grip_y=-0.40, grip_z=1.02, grip_x=0.24, lean=14)

SPEEDS = {}


def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def relaxed_arms(q, amt=1.0):
    q["upper_arm_L"] = Q("Y", 20 * amt) @ q.get("upper_arm_L", Quaternion())
    q["upper_arm_R"] = Q("Y", -20 * amt) @ q.get("upper_arm_R", Quaternion())
    q["forearm_L"] = Q("X", -12 * amt) @ q.get("forearm_L", Quaternion())
    q["forearm_R"] = Q("X", -12 * amt) @ q.get("forearm_R", Quaternion())
    return q


def gait(ph, amp, knee, arm, lean=0.0, arm_bend=15, bounce=0.02, crouch=0.0):
    """ph in radians. Left leg forward at ph=pi/2."""
    q = {}
    hz = 0.0
    for s, sgn in (("L", 1), ("R", -1)):
        p = ph if s == "L" else ph + math.pi
        th = -amp * math.sin(p) - crouch
        # knee bends during swing (leg moving forward: cos(p) > 0)
        kb = knee * max(0.0, math.cos(p)) ** 1.5 + 6 + crouch * 1.6
        q["thigh_" + s] = Q("X", th)
        q["shin_" + s] = Q("X", kb)
        q["foot_" + s] = Q("X", -(th + kb) * 0.5 + 5)
        a = arm * math.sin(p)
        q["upper_arm_" + s] = Q("X", a) @ Q("Y", sgn * 18)
        q["forearm_" + s] = Q("X", -arm_bend - max(0, -a) * 0.6)
    q["hips"] = Q("Z", 6 * math.sin(ph) * (amp / 30))
    q["chest"] = Q("X", lean) @ Q("Z", -9 * math.sin(ph) * (amp / 30))
    q["head"] = Q("X", -lean * 0.6)
    hz = -bounce * abs(math.cos(ph)) - crouch * 0.004
    return q, Vector((0, 0, hz))


def make_action(rig, name, frames, fn, loop=True):
    """fn(t in [0,1)) -> (q dict, hips_off, extra dict). Keys frames 0..frames (last = first if loop)."""
    P = Poser(rig)
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    for f in range(frames + 1):
        t = (f % frames) / frames if loop else f / frames
        res = fn(t, P)
        q, ho = res[0], res[1]
        extra = res[2] if len(res) > 2 else {}
        P.key(f, q, ho, root_off=extra.get("root_off"), root_rot=extra.get("root_rot"))
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    rig.animation_data.action = None
    tr = rig.animation_data.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, 0, act)
    st.name = name
    tr.mute = True
    act.use_fake_user = True
    return act


def _fcurves(act):
    try:
        return list(act.fcurves)
    except Exception:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out += list(cb.fcurves)
        return out


# ------------------------------------------------------------------ the animation library
def A_idle(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    q["chest"] = Q("X", 1.5 * math.sin(ph))
    q["head"] = Q("Z", 4 * math.sin(ph)) @ Q("X", -1.5 * math.sin(ph))
    q["upper_arm_L"] = Q("X", 2 * math.sin(ph)) @ q["upper_arm_L"]
    q["upper_arm_R"] = Q("X", -2 * math.sin(ph)) @ q["upper_arm_R"]
    return q, Vector((0, 0, -0.004 * (1 + math.sin(ph))))


def A_walk(t, P):
    return gait(2 * math.pi * t, 26, 45, 22)


def A_run(t, P):
    q, h = gait(2 * math.pi * t, 42, 85, 40, lean=12, arm_bend=75, bounce=0.05)
    return q, h + Vector((0, 0, 0.02))


def A_tired_walk(t, P):
    q, h = gait(2 * math.pi * t, 18, 35, 8, lean=16, arm_bend=5, bounce=0.03)
    q["head"] = Q("X", 12)
    return q, h - Vector((0, 0, 0.03))


def A_climb_stairs(t, P):
    q, h = gait(2 * math.pi * t, 30, 95, 25, lean=18, arm_bend=40, bounce=0.04, crouch=10)
    return q, h


def A_sneak(t, P):
    q, h = gait(2 * math.pi * t, 20, 50, 10, lean=22, arm_bend=60, bounce=0.01, crouch=25)
    return q, h - Vector((0, 0, 0.05))


def bike_pose(t, P, pedal=True):
    q = {}
    ho = BIKE["seat_hips"] - Vector(SK["hips"][0])
    q["hips"] = Q("X", 0)
    q["spine"] = Q("X", BIKE["lean"] * 0.5)
    q["chest"] = Q("X", BIKE["lean"] * 0.5)
    q["head"] = Q("X", -BIKE["lean"] * 0.8)
    ang = 2 * math.pi * t if pedal else 0.0
    c = BIKE["crank"]
    for s, sx, off in (("L", 1, 0.0), ("R", -1, math.pi)):
        a = ang + off
        pedal_pt = c + Vector((sx * 0.12, -math.sin(a) * BIKE["crank_r"], math.cos(a) * BIKE["crank_r"]))
        ankle = pedal_pt + Vector((0, 0.03, 0.06))
        P.ik2(q, ("thigh_" + s, "shin_" + s), ankle, Vector((0, -1, 0.3)), ho, end="foot_" + s,
              end_dir=Vector((0, -1, -0.15)))
        grip = Vector((sx * BIKE["grip_x"], BIKE["grip_y"], BIKE["grip_z"]))
        P.ik2(q, ("upper_arm_" + s, "forearm_" + s), grip, Vector((sx * 0.6, 0.6, -0.4)), ho, end="hand_" + s,
              end_dir=Vector((sx * 0.2, -1.0, -0.3)))
    return q, ho


def A_ride_bike(t, P):
    return bike_pose(t, P, True)


def A_ride_bike_idle(t, P):
    q, ho = bike_pose(0.25, P, False)
    q["chest"] = Q("X", 1.5 * math.sin(2 * math.pi * t)) @ q["chest"]
    return q, ho


def scooter_pose(t, P, sway=True):
    q = {}
    ho = Vector((0, 0.04, SCOOT["deck_z"] - 0.03))
    ph = 2 * math.pi * t
    q["spine"] = Q("X", SCOOT["lean"] * 0.5)
    q["chest"] = Q("X", SCOOT["lean"] * 0.5 + (1.5 * math.sin(ph) if sway else 0))
    q["head"] = Q("X", -SCOOT["lean"] * 0.7)
    q["hips"] = Q("Z", -12)
    for s, sx, fy in (("L", 1, -0.10), ("R", -1, 0.22)):
        ankle = Vector((sx * 0.07, fy, SCOOT["deck_z"] + 0.07))
        P.ik2(q, ("thigh_" + s, "shin_" + s), ankle, Vector((0, -1, 0.2)), ho, end="foot_" + s,
              end_dir=Vector((0, -1, -0.25)))
        grip = Vector((sx * SCOOT["grip_x"], SCOOT["grip_y"], SCOOT["grip_z"]))
        P.ik2(q, ("upper_arm_" + s, "forearm_" + s), grip, Vector((sx * 0.6, 0.6, -0.4)), ho, end="hand_" + s,
              end_dir=Vector((sx * 0.2, -1.0, -0.3)))
    return q, ho


def A_ride_scooter(t, P):
    return scooter_pose(t, P, True)


def blend_pose(qa, ha, qb, hb, k):
    q = {}
    for bn in set(qa) | set(qb):
        q[bn] = qa.get(bn, Quaternion()).slerp(qb.get(bn, Quaternion()), k)
    return q, ha.lerp(hb, k)


def A_mount_bike(t, P):
    qa, ha = A_idle(0, P)
    qb, hb = bike_pose(0.25, P, False)
    k = smooth01(t)
    q, h = blend_pose(qa, ha, qb, hb, k)
    # lift the right leg over the frame mid-way
    lift = math.sin(math.pi * k)
    q["thigh_R"] = Q("X", -55 * lift) @ Q("Y", -25 * lift) @ q.get("thigh_R", Quaternion())
    return q, h + Vector((0, 0, 0.08 * lift))


def A_dismount_bike(t, P):
    return A_mount_bike(1 - t, P)


def A_mount_scooter(t, P):
    qa, ha = A_idle(0, P)
    qb, hb = scooter_pose(0, P, False)
    k = smooth01(t)
    q, h = blend_pose(qa, ha, qb, hb, k)
    return q, h + Vector((0, 0, 0.06 * math.sin(math.pi * k)))


def A_dismount_scooter(t, P):
    return A_mount_scooter(1 - t, P)


def A_pickup_bag(t, P):
    k = math.sin(math.pi * t)
    q = relaxed_arms({}, 1 - k)
    q["spine"] = Q("X", 25 * k)
    q["chest"] = Q("X", 20 * k)
    q["head"] = Q("X", -15 * k)
    for s in ("L", "R"):
        q["upper_arm_" + s] = Q("X", -70 * k) @ q.get("upper_arm_" + s, Quaternion())
        q["forearm_" + s] = Q("X", -20 * k)
        q["thigh_" + s] = Q("X", -25 * k)
        q["shin_" + s] = Q("X", 40 * k)
        q["foot_" + s] = Q("X", -15 * k)
    return q, Vector((0, 0, -0.08 * k))


def hold_front(q, k=1.0):
    for s, sx in (("L", 1), ("R", -1)):
        q["upper_arm_" + s] = Q("X", -40 * k) @ Q("Y", sx * 8 * k)
        q["forearm_" + s] = Q("X", -55 * k) @ Q("Y", -sx * 20 * k)
    return q


def A_carry(t, P):
    q, h = gait(2 * math.pi * t, 26, 45, 0)
    return hold_front(q), h


def A_carry_idle(t, P):
    q, h = A_idle(t, P)
    return hold_front(q), h


def A_hand_over(t, P):
    k = math.sin(math.pi * t)
    q = hold_front({}, 1.0)
    for s in ("L", "R"):
        q["upper_arm_" + s] = Q("X", -35 * k) @ q["upper_arm_" + s]
        q["forearm_" + s] = Q("X", 35 * k) @ q["forearm_" + s]
    q["spine"] = Q("X", 10 * k)
    q["head"] = Q("X", -5 * k)
    return q, Vector((0, 0, 0))


def A_take_bag(t, P):
    k = math.sin(math.pi * min(1, t * 1.6)) if t < 0.62 else 0
    q = relaxed_arms({}, 1 - k)
    q["upper_arm_R"] = Q("X", -75 * k) @ Q("Y", -10)
    q["forearm_R"] = Q("X", -10 * k)
    q["chest"] = Q("X", 8 * k)
    if t >= 0.5:
        q = hold_front(q, smooth01((t - 0.5) * 2))
    return q, Vector((0, 0, 0))


def A_knock_door(t, P):
    q = relaxed_arms({})
    knock = abs(math.sin(3 * 2 * math.pi * t))
    q["upper_arm_R"] = Q("X", -75) @ Q("Y", 10)
    q["forearm_R"] = Q("X", -60 - 35 * knock)
    q["chest"] = Q("X", 4)
    return q, Vector((0, 0, 0))


def A_ring_intercom(t, P):
    k = math.sin(math.pi * t)
    q = relaxed_arms({}, 1 - k)
    q["upper_arm_R"] = Q("X", -80 * k) @ Q("Y", -20 * (1 - k))
    q["forearm_R"] = Q("X", -30 * k)
    q["head"] = Q("X", -6 * k)
    return q, Vector((0, 0, 0))


def A_phone_check(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    q["upper_arm_L"] = Q("X", -35) @ Q("Y", -10)
    q["forearm_L"] = Q("X", -95) @ Q("Y", -40)
    q["head"] = Q("X", 18) @ Q("Z", 3 * math.sin(ph))
    q["chest"] = Q("X", 4)
    return q, Vector((0, 0, 0))


def A_phone_call(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    q["upper_arm_R"] = Q("X", -30) @ Q("Y", -55)
    q["forearm_R"] = Q("X", -140) @ Q("Y", 20)
    q["head"] = Q("Z", -8) @ Q("Y", -6 + 4 * math.sin(ph))
    q["upper_arm_L"] = Q("X", 10 * math.sin(ph)) @ q["upper_arm_L"]
    return q, Vector((0, 0, 0))


def A_fall_tumble(t, P):
    k = smooth01(t)
    q = {}
    flail = math.sin(6 * math.pi * t) * (1 - k)
    q["root"] = Q("X", 85 * k)
    q["upper_arm_L"] = Q("X", -100 * k + 30 * flail) @ Q("Y", 30)
    q["upper_arm_R"] = Q("X", -100 * k - 30 * flail) @ Q("Y", -30)
    q["thigh_L"] = Q("X", 20 * flail)
    q["thigh_R"] = Q("X", -20 * flail)
    q["head"] = Q("X", -30 * k)
    return q, Vector((0, 0, 0)), {"root_off": Vector((0, -0.6 * k, 0.12 * k + 0.25 * math.sin(math.pi * t)))}


def A_get_up(t, P):
    return A_fall_tumble(1 - t, P)


def A_lying(t, P):
    return A_fall_tumble(1.0, P)


def A_celebrate(t, P):
    ph = 2 * math.pi * t
    q = {}
    jump = max(0, math.sin(ph))
    for s, sx in (("L", 1), ("R", -1)):
        q["upper_arm_" + s] = Q("Y", sx * (-130 + 15 * math.sin(2 * ph))) @ Q("X", -10)
        q["forearm_" + s] = Q("X", -20)
        q["thigh_" + s] = Q("X", -20 * jump)
        q["shin_" + s] = Q("X", 35 * jump)
    q["head"] = Q("X", -10)
    return q, Vector((0, 0, 0.18 * jump))


def A_eat_snack(t, P):
    ph = 2 * math.pi * t
    k = 0.5 + 0.5 * math.sin(ph)
    q = relaxed_arms({})
    q["upper_arm_R"] = Q("X", -35 * k) @ Q("Y", -25)
    q["forearm_R"] = Q("X", -120 * k)
    q["head"] = Q("X", -4 * k)
    return q, Vector((0, 0, 0))


def sit_pose(q=None):
    q = q or {}
    for s in ("L", "R"):
        q["thigh_" + s] = Q("X", -88)
        q["shin_" + s] = Q("X", 88)
        q["foot_" + s] = Q("X", 0)
    return q, Vector((0, 0.05, -0.27))


def A_sit(t, P):
    q, h = sit_pose(relaxed_arms({}))
    q["chest"] = Q("X", -3 + 1.5 * math.sin(2 * math.pi * t))
    q["upper_arm_L"] = Q("X", -25) @ q["upper_arm_L"]
    q["upper_arm_R"] = Q("X", -25) @ q["upper_arm_R"]
    q["forearm_L"] = Q("X", -30)
    q["forearm_R"] = Q("X", -30)
    return q, h


def A_sip_coffee(t, P):
    q, h = A_sit(t, P)
    k = max(0, math.sin(2 * math.pi * t))
    q["upper_arm_R"] = Q("X", -40 - 20 * k) @ Q("Y", -25)
    q["forearm_R"] = Q("X", -70 - 50 * k)
    q["head"] = Q("X", -8 * k)
    return q, h


def A_talk(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    q["upper_arm_R"] = Q("X", -30 - 15 * math.sin(2 * ph)) @ Q("Y", -15)
    q["forearm_R"] = Q("X", -50 + 20 * math.sin(3 * ph))
    q["upper_arm_L"] = Q("X", -15 - 10 * math.sin(ph + 1)) @ q["upper_arm_L"]
    q["forearm_L"] = Q("X", -40)
    q["head"] = Q("Z", 8 * math.sin(ph)) @ Q("X", 4 * math.sin(2 * ph))
    q["chest"] = Q("Z", 3 * math.sin(ph))
    return q, Vector((0, 0, 0))


def A_laugh(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    b = abs(math.sin(4 * ph))
    q["chest"] = Q("X", -6 - 5 * b)
    q["head"] = Q("X", -15 - 6 * b)
    q["upper_arm_L"] = Q("X", -20) @ q["upper_arm_L"]
    q["forearm_L"] = Q("X", -70)
    return q, Vector((0, 0, -0.01 * b))


def A_point(t, P):
    k = smooth01(min(1, t * 3)) if t < 0.8 else smooth01((1 - t) * 5)
    q = relaxed_arms({}, 1 - k)
    q["upper_arm_R"] = Q("X", -85 * k) @ Q("Y", -10 * (1 - k))
    q["forearm_R"] = Q("X", -5 * k)
    q["head"] = Q("Z", -10 * k)
    return q, Vector((0, 0, 0))


def A_happy(t, P):
    q, h = A_celebrate(t, P)
    return q, h * 0.5


def A_angry(t, P):
    ph = 2 * math.pi * t
    q = {}
    shake = math.sin(4 * ph)
    for s, sx in (("L", 1), ("R", -1)):
        q["upper_arm_" + s] = Q("X", -40 + 10 * shake * sx) @ Q("Y", sx * 15)
        q["forearm_" + s] = Q("X", -100)
    stomp = max(0, math.sin(ph))
    q["thigh_R"] = Q("X", -25 * stomp)
    q["shin_R"] = Q("X", 35 * stomp)
    q["chest"] = Q("X", 8)
    q["head"] = Q("X", 6) @ Q("Z", 6 * shake)
    return q, Vector((0, 0, 0))


def A_wait_impatient(t, P):
    ph = 2 * math.pi * t
    q = {}
    for s, sx in (("L", 1), ("R", -1)):  # arms crossed
        q["upper_arm_" + s] = Q("X", -25) @ Q("Y", sx * 10)
        q["forearm_" + s] = Q("X", -90) @ Q("Z", -sx * 60)
    tap = max(0, math.sin(4 * ph))
    q["foot_R"] = Q("X", -20 * tap)
    q["head"] = Q("Z", 10 * math.sin(ph))
    return q, Vector((0, 0, 0))


def A_open_door(t, P):
    k = math.sin(math.pi * t)
    q = relaxed_arms({}, 1 - k)
    q["upper_arm_R"] = Q("X", -70 * k) @ Q("Y", -10)
    q["forearm_R"] = Q("X", -20 * k)
    q["chest"] = Q("X", 6 * k)
    return q, Vector((0, 0, 0))


def A_whistle(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    q["upper_arm_R"] = Q("X", -35) @ Q("Y", -30)
    q["forearm_R"] = Q("X", -130)
    q["chest"] = Q("X", -4 * abs(math.sin(3 * ph)))
    q["upper_arm_L"] = Q("X", -60) @ Q("Y", 10)  # stop gesture
    q["forearm_L"] = Q("X", -40)
    return q, Vector((0, 0, 0))


def A_write_ticket(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    q["upper_arm_L"] = Q("X", -30) @ Q("Y", -10)
    q["forearm_L"] = Q("X", -90) @ Q("Z", 30)
    q["upper_arm_R"] = Q("X", -30) @ Q("Y", 10)
    q["forearm_R"] = Q("X", -85 + 6 * math.sin(4 * ph)) @ Q("Z", -30)
    q["head"] = Q("X", 20)
    return q, Vector((0, 0, 0))


def A_cook_idle(t, P):
    ph = 2 * math.pi * t
    q = relaxed_arms({})
    q["upper_arm_R"] = Q("X", -40 + 8 * math.sin(2 * ph)) @ Q("Z", 10 * math.cos(2 * ph))
    q["forearm_R"] = Q("X", -50)
    q["upper_arm_L"] = Q("X", -30) @ q["upper_arm_L"]
    q["forearm_L"] = Q("X", -60)
    q["head"] = Q("X", 12)
    return q, Vector((0, 0, 0))


def A_photo(t, P):
    q = relaxed_arms({})
    for s, sx in (("L", 1), ("R", -1)):
        q["upper_arm_" + s] = Q("X", -40) @ Q("Y", -sx * 15)
        q["forearm_" + s] = Q("X", -110) @ Q("Y", sx * 20)
    q["head"] = Q("X", -5 + 3 * math.sin(2 * math.pi * t))
    return q, Vector((0, 0, 0))


LIB = [  # name, frames, fn, loop
    ("idle", 48, A_idle, True), ("walk", 24, A_walk, True), ("run", 16, A_run, True),
    ("tired_walk", 30, A_tired_walk, True), ("climb_stairs", 20, A_climb_stairs, True),
    ("sneak", 30, A_sneak, True),
    ("ride_bike", 24, A_ride_bike, True), ("ride_bike_idle", 48, A_ride_bike_idle, True),
    ("ride_scooter", 48, A_ride_scooter, True),
    ("mount_bike", 14, A_mount_bike, False), ("dismount_bike", 14, A_dismount_bike, False),
    ("mount_scooter", 10, A_mount_scooter, False), ("dismount_scooter", 10, A_dismount_scooter, False),
    ("pickup_bag", 24, A_pickup_bag, False), ("carry", 24, A_carry, True), ("carry_idle", 48, A_carry_idle, True),
    ("hand_over", 24, A_hand_over, False), ("take_bag", 30, A_take_bag, False),
    ("knock_door", 24, A_knock_door, True), ("ring_intercom", 18, A_ring_intercom, False),
    ("phone_check", 48, A_phone_check, True), ("phone_call", 48, A_phone_call, True),
    ("fall_tumble", 20, A_fall_tumble, False), ("lying", 2, A_lying, True), ("get_up", 24, A_get_up, False),
    ("celebrate", 24, A_celebrate, True), ("happy", 24, A_happy, True), ("angry", 24, A_angry, True),
    ("eat_snack", 36, A_eat_snack, True), ("sit", 48, A_sit, True), ("sip_coffee", 60, A_sip_coffee, True),
    ("talk", 48, A_talk, True), ("laugh", 36, A_laugh, True), ("point", 30, A_point, False),
    ("wait_impatient", 48, A_wait_impatient, True), ("open_door", 20, A_open_door, False),
    ("whistle", 36, A_whistle, True), ("write_ticket", 36, A_write_ticket, True),
    ("cook_idle", 48, A_cook_idle, True), ("photo", 48, A_photo, True),
]
# walk/run speeds at playback 1.0 where feet don't slide (measured below)
SPEED_ANIMS = {"walk": 24, "run": 16, "tired_walk": 30, "climb_stairs": 20, "sneak": 30, "carry": 24}


def measure_speed(rig, act_name, frames):
    """Average backward speed of the planted foot -> forward speed for no sliding."""
    P = Poser(rig)
    fn = dict((n, f) for n, _, f, _ in LIB)[act_name]
    xs = []
    for f in range(frames):
        q, ho = fn(f / frames, P)[:2]
        D, Pp = P.fk(q, ho)
        tipL = P.tip(D, Pp, "foot_L")
        tipR = P.tip(D, Pp, "foot_R")
        xs.append((tipL.y, tipL.z, tipR.y, tipR.z))
    # stance foot = the lower one; integrate its y velocity
    dist = 0.0
    for i in range(frames):
        a, b = xs[i], xs[(i + 1) % frames]
        if a[1] <= a[3]:
            dist += max(0.0, b[0] - a[0])
        else:
            dist += max(0.0, b[2] - a[2])
    return round(dist / (frames / FPS), 3)


# ------------------------------------------------------------------ roster
def lashes(B):
    m = mat("lash", "#2b2320")
    for sx in (-1, 1):
        B.add(box("lash%d" % sx, (0.06, 0.01, 0.012), (sx * 0.075, -0.2, 1.53), m, rot=(0, math.radians(sx * -15), 0)),
              "head")


def sunglasses_forehead(B):
    m = mat("sunglass", "#1d1f24", rough=0.2)
    for sx in (-1, 1):
        B.add(sphere("sgl%d" % sx, 0.045, (sx * 0.07, -0.18, 1.6), m, seg=8, rings=6, scale=(1.2, 0.4, 0.8)), "head")
    B.add(box("sglb", (0.06, 0.01, 0.01), (0, -0.2, 1.61), m), "head")


def bald_sides(c):
    def f(B):
        m = mat("hair_" + c.lstrip("#"), c)
        for sx in (-1, 1):
            B.add(sphere("bs%d" % sx, 0.1, (sx * 0.17, 0.05, 1.45), m, seg=8, rings=6, scale=(0.6, 1.2, 0.8)), "head")
    return f


def toque(B):
    m = mat("chef_white", "#fbfbf8")
    B.add(cyl("tq", 0.2, 0.12, (0, 0, 1.6), m, n=16), "head")
    B.add(sphere("tqp", 0.2, (0, 0, 1.82), m, seg=14, rings=8, scale=(1.1, 1.1, 0.9)), "head")


def police_cap(B):
    m = mat("police_blue", "#3f5f9c")
    B.add(cyl("pc", 0.22, 0.1, (0, 0, 1.6), m, n=16), "head")
    B.add(cyl("pct", 0.25, 0.04, (0, 0.01, 1.7), m, n=16), "head")
    B.add(cyl("pcv", 0.13, 0.02, (0, -0.2, 1.6), "black", n=12), "head")
    B.add(cyl("pcb", 0.03, 0.01, (0, -0.22, 1.66), mat("gold", "#e2b23c"), n=6, rot=(math.radians(90), 0, 0)), "head")


def beanie(c):
    def f(B):
        m = mat("beanie_" + c.lstrip("#"), c)
        B.add(sphere("bn", 0.225, (0, 0.01, 1.55), m, seg=14, rings=8, scale=(1, 1, 0.8)), "head")
        B.add(torus("bnr", 0.2, 0.03, (0, 0.01, 1.5), m), "head")
    return f


def sun_hat(B):
    m = mat("straw", "#e8cf8a")
    B.add(cyl("sh", 0.38, 0.03, (0, 0, 1.6), m, n=20), "head")
    B.add(sphere("sht", 0.2, (0, 0.01, 1.62), m, seg=14, rings=8, scale=(1, 1, 0.7)), "head")
    B.add(torus("shb", 0.2, 0.02, (0, 0.01, 1.63), "coral"), "head")


def camera_strap(B):
    B.add(box("cam", (0.14, 0.08, 0.09), (0, -0.2, 1.0), mat("camera", "#2b2b30"), bevel=0.01), "chest")
    B.add(cyl("lens", 0.035, 0.05, (0, -0.24, 1.0), "black", n=10, rot=(math.radians(90), 0, 0)), "chest")


def laptop(B):
    B.add(box("lap", (0.32, 0.03, 0.22), (0.31, -0.02, 0.8), mat("laptop", "#a5adb6", metal=0.4), bevel=0.01), "hand_L")


def baby(B):
    sk = mat("skin_baby", "#f6cfae")
    B.add(sphere("bbody", 0.1, (0, -0.2, 1.0), mat("baby_cloth", "#f6c945"), seg=10, rings=8, scale=(1, 0.9, 1.2)),
          "chest")
    B.add(sphere("bhead", 0.08, (0, -0.22, 1.15), sk, seg=10, rings=8), "chest")
    B.add(box("sling", (0.3, 0.06, 0.25), (0, -0.17, 0.95), mat("sling", "#8fd3b0"), bevel=0.03), "chest")


def knitting(B):
    B.add(sphere("yarn", 0.06, (0.3, -0.12, 0.75), "coral", seg=8, rings=6), "hand_L")


def whistle_cord(B):
    B.add(tube_path("cord", [(-0.1, -0.13, 1.15), (0.0, -0.17, 1.02), (0.1, -0.13, 1.15)], 0.006, "black", n=4),
          "chest")


def guard_gear(B):
    m = mat("sunglass", "#1d1f24", rough=0.2)
    for sx in (-1, 1):
        B.add(sphere("gsg%d" % sx, 0.05, (sx * 0.075, -0.2, 1.52), m, seg=8, rings=6, scale=(1.25, 0.4, 0.8)), "head")
    B.add(box("gsgb", (0.08, 0.012, 0.012), (0, -0.215, 1.53), m), "head")
    cm = mat("guard_cap", "#22252b")
    B.add(cyl("gc", 0.22, 0.1, (0, 0, 1.6), cm, n=16), "head")
    B.add(cyl("gct", 0.24, 0.04, (0, 0.01, 1.7), cm, n=16), "head")
    B.add(cyl("gcv", 0.13, 0.02, (0, -0.2, 1.6), "black", n=12), "head")
    B.add(tube_path("earpiece", [(0.2, 0.0, 1.45), (0.18, 0.05, 1.3), (0.14, 0.06, 1.18)], 0.008, "black", n=4), "head")


def courier_accs(B):
    for f in (hero_hair_short("#5b3a26"), hero_hair_ponytail("#6b3e22"), hair_curly("#2e2420"), hair_bun("#6b3e22"),
              hero_cap("#22b8b0"), helmet_bike(), helmet_half(), helmet_retro(), hero_bag(), held_box(), held_phone()):
        f(B)


JACKET = None


def jacket_mat():
    return mat("jacket", "turq", rough=0.6)


ROSTER = {
    "courier_m": dict(skin="#f2c39b", top="jacket", top_m=None, pants="#56483f", shoes="#c07a45", hero=True,
                      extras=[courier_accs, wrist_phone], hair_c="#5b3a26"),
    "courier_f": dict(skin="#f0bf98", top="jacket", top_m=None, pants="#56483f", shoes="#c07a45", hero=True,
                      female=True, extras=[courier_accs, wrist_phone], hair_c="#6b3e22"),
    "mentor": dict(skin="#e3ad86", top="jacket", top_c="#5fa9a3", pants="#4c5560", shoes="#6b4a2e", belly=0.07,
                   mustache="#d8d8d8", hair_c="#c9c9c9", gloves="#3a3a3a",
                   extras=[hair_short("#c9c9c9", "hair"), sunglasses_forehead, delivery_bag("bag", "#4f8f8a", True)]),
    "oldman": dict(skin="#efc0a0", top="robe", top_c="#7e9fc9", pants="#7e9fc9", shoes="#a5604a", belly=0.05,
                   hair_c="#d9d9d9", expression="angry", pant_cuff=False, extras=[bald_sides("#d9d9d9")]),
    "office": dict(skin="#d9a27b", top="shirt", top_c="#f2f2ef", tie="coral", pants="#3b4a66", shoes="#2b2b30",
                   hair_c="#2b2320", extras=[hair_short("#2b2320", "hair"), laptop]),
    "student": dict(skin="#f2c39b", top="hoodie", top_c="#9a86c9", pants="#4a6fa5", shoes="#f4efe6",
                    hair_c="#3a2a20", extras=[hair_curly("#3a2a20", "hair")]),
    "mom": dict(skin="#f0c4a2", top="tshirt", top_c="#f2a7a0", pants="#5a6ea0", shoes="#f4efe6", hair_c="#6b3e22",
                extras=[hair_bun("#6b3e22", "hair"), baby, lashes]),
    "grandma": dict(skin="#f1c9ae", top="cardigan", top_c="#b9a3d8", pants="#7a5a8a", skirt="#7a5a8a",
                    shoes="#5a3a2e", hair_c="#e2e2e2", glasses=True, height=0.9,
                    extras=[hair_bun("#e2e2e2", "hair"), knitting, lashes]),
    "tourist": dict(skin="#f5c8a8", top="tshirt", top_c="#f6c945", pants="#d9c48a", shorts=True, shoes="#3f7fc9",
                    hair_c="#c9a25a", extras=[sun_hat, camera_strap]),
    "cook": dict(skin="#e8b48f", top="cook", top_c="#fbfbf8", pants="#3a3a40", shoes="#2b2b30", hair_c="#2b2320",
                 extras=[toque]),
    "police": dict(skin="#e3ad86", top="uniform", top_c="#3f5f9c", pants="#2f4776", shoes="#1d1f24", belly=0.05,
                   hair_c="#3a2a20", mustache="#3a2a20", extras=[police_cap, whistle_cord]),
    "guard": dict(skin="#d9a27b", top="uniform", top_c="#2f3440", pants="#2a2d33", shoes="#1d1f24", belly=0.06,
                  hair_c="#2b2320", extras=[guard_gear]),
    "thief": dict(skin="#e8b48f", top="hoodie", top_c="#3a3d48", pants="#2b2d33", shoes="#55585e", hair_c="#2b2320",
                  extras=[beanie("#2b2b30")]),
}


def build(name, spec):
    coll = collection(name)
    if spec.get("top_m") is None and spec.get("top") == "jacket" and name.startswith("courier"):
        spec = dict(spec, top_m=jacket_mat())
    rig, meshes = (courier_human if spec.get("hero") else human)(name, coll, spec)
    if spec.get("height"):
        rig.scale = (spec["height"],) * 3
    lib = [x for x in LIB if (ANIMS is None or x[0] in ANIMS)]
    for an, frames, fn, loop in lib:
        make_action(rig, an, frames, fn, loop)
    return rig, meshes


def export_char(rig, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for c in rig.children:
        c.select_set(True)
    bpy.context.view_layer.objects.active = rig
    tex_rel = os.path.relpath(TEX, os.path.dirname(path)).replace("\\", "/")
    kw = dict(filepath=path, export_format="GLTF_SEPARATE", use_selection=True, export_apply=False,
              export_texture_dir=tex_rel, export_animations=True, export_yup=True, export_skins=True,
              export_frame_range=False, export_force_sampling=True, export_def_bones=False)
    for mode in ("NLA_TRACKS", "ACTIONS"):
        try:
            bpy.ops.export_scene.gltf(export_animation_mode=mode, **kw)
            print("exported", path, mode)
            return
        except TypeError as e:
            print("export retry", e)
    bpy.ops.export_scene.gltf(**kw)


def render_char(rig, meshes, name):
    P = Poser(rig)
    poses = [("idle", A_idle, 0.0), ("walk", A_walk, 0.25), ("run", A_run, 0.3), ("ride_bike", A_ride_bike, 0.1),
             ("ride_scooter", A_ride_scooter, 0.0), ("phone_check", A_phone_check, 0.0), ("sit", A_sit, 0.0),
             ("celebrate", A_celebrate, 0.25)]
    rig.animation_data.action = None
    for tr in rig.animation_data.nla_tracks:
        tr.mute = True
    out = []
    R.isolate([rig] + meshes)
    vis = [m for m in meshes if not m.name.startswith(("ACC_", "HELD_"))] + \
          [m for m in meshes if m.name in ("ACC_cap", "ACC_bag", "hair") or
           m.name == ("ACC_hair_ponytail" if name == "courier_f" else "ACC_hair_short")]
    for m in meshes:
        m.hide_render = m not in vis
    for pn, fn, t in poses:
        q, ho = fn(t, P)[:2]
        extra = fn(t, P)[2] if len(fn(t, P)) > 2 else {}
        P.key(0, q, ho, root_off=extra.get("root_off"), root_rot=extra.get("root_rot"))
        bpy.context.scene.frame_set(0)
        R.camera(loc=(1.6, -3.0, 1.5), target=(0, 0, 0.85), lens=45)
        p = os.path.join(RENDERS, "characters", "%s_%s.png" % (name, pn))
        R.render(p)
        out.append(p)
    # front view
    q, ho = A_idle(0, P)
    P.key(0, q, ho)
    R.camera(loc=(0, -3.4, 1.0), target=(0, 0, 0.88), lens=45)
    p = os.path.join(RENDERS, "characters", "%s_front.png" % name)
    R.render(p)
    for vn, loc in (("side", (-3.4, 0, 1.0)), ("back", (0, 3.4, 1.0)), ("three_q", (1.9, -2.6, 1.3))):
        R.camera(loc=loc, target=(0, 0, 0.88), lens=45)
        R.render(os.path.join(RENDERS, "characters", "%s_%s.png" % (name, vn)))
    rig.animation_data.action = None
    return out


def main():
    for name, spec in ROSTER.items():
        if ONLY and name not in ONLY:
            continue
        # fresh scene per character so object names (ACC_*, HELD_*) never get .001 suffixes
        reset()
        std_mats()
        R.setup_render((360, 420))
        R.world("#d9dde2")
        R.sun(energy=3.0)
        R.ground_plane(color="#c9ccd1")
        rig, meshes = build(name, spec)
        if name == "courier_m":
            for an, fr in SPEED_ANIMS.items():
                if ANIMS is None or an in ANIMS:
                    SPEEDS[an] = measure_speed(rig, an, fr)
        export_char(rig, os.path.join(ASSETS, "characters", name + ".gltf"))
        print("built", name)
        if not NO_RENDER:
            render_char(rig, meshes, name)
        if name in ("courier_m",):
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND, "characters_%s.blend" % name))
    if SPEEDS:
        json.dump(dict(speeds_mps=SPEEDS, fps=FPS, bike=dict((k, list(v) if hasattr(v, "x") else v) for k, v in BIKE.items()),
                       scooter=SCOOT),
                  open(os.path.join(ASSETS, "characters", "anim_speeds.json"), "w"), indent=1)
        print("speeds", SPEEDS)
    print("DONE")


if __name__ == "__main__":
    main()
