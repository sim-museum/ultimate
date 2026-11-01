"""Throws keyed by hand, for a right-handed thrower: the forehand (flick) and the hammer, which the CMU database
does not have; and the mark's stance. Each is a few key poses over time, built on the athlete's own idle pose (from mocap, so the rest of
the body stays human), sampled at FPS with eased interpolation of the pose controls.

Pose controls (body frame: right, forward, up, in metres from the ground under the idle hips; angles in degrees):
  hips: drop (m), shift (right, forward), yaw (+ turns right), lean (+ forward)
  spine: twist (+ shoulders turn right), bend (+ forward), side (+ leans right)
  rhand / lhand: wrist target; relbow / lelbow: the direction the elbow points
  rfoot / lfoot: ankle target (the foot keeps its idle orientation)
Everything not given keeps the previous key's value (the first key starts from the idle pose).
"""
import math

from mathutils import Matrix, Vector

FPS = 30

ARM = {"r": ("RightArm", "RightForeArm", "RightHand"), "l": ("LeftArm", "LeftForeArm", "LeftHand")}
LEG = {"r": ("RightUpLeg", "RightLeg", "RightFoot"), "l": ("LeftUpLeg", "LeftLeg", "LeftFoot")}
SPINE = ("LowerBack", "Spine", "Spine1")

# The forehand (flick): step out to the right, the elbow tucked by the hip, the forearm whipping forward at hip
# height, the wrist snapping; release in front of the right hip; follow through towards the target.
FOREHAND = {
    "release": 0.30,
    "keys": [
        (0.00, {"rhand": (0.28, 0.18, 0.95), "relbow": (0.6, -0.6, -0.6)}),
        (0.18, {"hips": {"drop": 0.09, "shift": (0.16, 0.0), "yaw": 22.0, "lean": 8.0},
                "spine": {"twist": 18.0, "bend": 8.0, "side": 8.0},
                "rfoot": (0.62, 0.12, None), "rhand": (0.55, -0.22, 0.88), "relbow": (0.3, -1.0, -0.4),
                "lhand": (-0.45, 0.02, 1.02), "lelbow": (-1.0, -0.2, -0.3)}),
        (0.30, {"hips": {"drop": 0.11, "shift": (0.20, 0.05), "yaw": 4.0, "lean": 10.0},
                "spine": {"twist": -4.0, "bend": 10.0, "side": 12.0},
                "rhand": (0.60, 0.45, 0.92), "relbow": (0.2, -0.3, -1.0)}),
        (0.45, {"hips": {"drop": 0.09, "shift": (0.18, 0.08), "yaw": -6.0, "lean": 9.0},
                "spine": {"twist": -16.0, "bend": 9.0, "side": 8.0},
                "rhand": (0.36, 0.72, 1.02), "relbow": (0.5, 0.2, -1.0)}),
        (1.00, {"hips": {"drop": 0.0, "shift": (0.0, 0.0), "yaw": 0.0, "lean": 0.0},
                "spine": {"twist": 0.0, "bend": 0.0, "side": 0.0},
                "rfoot": "idle", "rhand": (0.28, 0.20, 0.98), "relbow": (0.6, -0.6, -0.6),
                "lhand": "idle", "lelbow": None}),
    ],
}

# The hammer: the arm up beside the head with the disc behind it, then an overhand throw released above the head
# and ahead of it (the disc flies upside down), the arm following through across the body.
HAMMER = {
    "release": 0.45,
    "keys": [
        (0.00, {"rhand": (0.28, 0.18, 0.95), "relbow": (0.6, -0.6, -0.6)}),
        (0.30, {"hips": {"drop": 0.04, "shift": (0.0, -0.05), "yaw": 18.0, "lean": -4.0},
                "spine": {"twist": 22.0, "bend": -8.0, "side": -6.0},
                "lfoot": (-0.18, 0.28, None),
                "rhand": (0.26, -0.18, 1.90), "relbow": (1.0, 0.0, 0.4),
                "lhand": (-0.32, 0.45, 1.45), "lelbow": (-1.0, 0.0, -0.3)}),
        (0.45, {"hips": {"drop": 0.06, "shift": (0.0, 0.08), "yaw": 2.0, "lean": 6.0},
                "spine": {"twist": -4.0, "bend": 10.0, "side": -2.0},
                "rhand": (0.22, 0.38, 2.02), "relbow": (1.0, 0.0, 1.0),
                "lhand": (-0.30, 0.25, 1.05)}),
        (0.65, {"hips": {"drop": 0.08, "shift": (0.0, 0.14), "yaw": -10.0, "lean": 12.0},
                "spine": {"twist": -20.0, "bend": 26.0, "side": 4.0},
                "rhand": (-0.12, 0.55, 1.05), "relbow": (1.0, 0.0, -0.4)}),
        (1.20, {"hips": {"drop": 0.0, "shift": (0.0, 0.0), "yaw": 0.0, "lean": 0.0},
                "spine": {"twist": 0.0, "bend": 0.0, "side": 0.0},
                "lfoot": "idle", "rhand": (0.28, 0.20, 0.98), "relbow": (0.6, -0.6, -0.6),
                "lhand": "idle", "lelbow": None}),
    ],
}

THROWS = {"forehand": FOREHAND, "hammer": HAMMER}

# The mark's stance (ULTIMATE-2): low, feet wide, weight forward, both arms out wide at about waist height to take
# away the throwing lanes, a small bounce on the balls of the feet. A loop of 1 s, played over the locomotion while
# a player marks (or holds a cup spot); no release.
_MARK = {"hips": {"drop": 0.20, "shift": (0.0, 0.0), "yaw": 0.0, "lean": 22.0},
         "spine": {"twist": 0.0, "bend": 14.0, "side": 0.0},
         "rfoot": (0.36, 0.02, None), "lfoot": (-0.36, -0.02, None),
         "rhand": (0.85, 0.30, 0.85), "relbow": (1.0, -0.3, -0.5),
         "lhand": (-0.85, 0.30, 0.85), "lelbow": (-1.0, -0.3, -0.5)}
MARK = {
    "release": 0.0,
    "keys": [
        (0.00, _MARK),
        (0.50, {"hips": {"drop": 0.24}, "rhand": (0.88, 0.32, 0.80), "lhand": (-0.88, 0.32, 0.80)}),
        (1.00, {"hips": {"drop": 0.20}, "rhand": _MARK["rhand"], "lhand": _MARK["lhand"]}),
    ],
}
STANCES = {"mark": MARK}

# The catch (ULTIMATE-2): two hands, the pancake: both hands reach forward to meet the disc at chest height, close
# on it (the "release" here is the catch), and pull it in. Played on the upper body only, over the run.
CATCH = {
    "release": 0.25,
    "keys": [
        (0.00, {}),
        (0.15, {"spine": {"twist": 0.0, "bend": 6.0, "side": 0.0},
                "rhand": (0.14, 0.42, 1.48), "relbow": (0.6, -0.2, -0.8),
                "lhand": (-0.14, 0.42, 1.48), "lelbow": (-0.6, -0.2, -0.8)}),
        (0.25, {"rhand": (0.05, 0.40, 1.40), "lhand": (-0.05, 0.40, 1.40)}),
        (0.45, {"spine": {"bend": 3.0}, "rhand": (0.10, 0.26, 1.25), "lhand": (-0.10, 0.26, 1.25)}),
        (0.75, {"spine": {"twist": 0.0, "bend": 0.0, "side": 0.0}, "rhand": "idle", "lhand": "idle",
                "relbow": None, "lelbow": None}),
    ],
}
THROWS["catch"] = CATCH

# The layout (ULTIMATE-2): a full-length dive for a disc out of reach. A push off the right foot, the body flat out
# along the ground with the right arm reaching ahead (the "release" here is the catch, at full stretch) and the left
# trailing along the body (the 2026 final's replays: layouts are mostly one-handed), landing on the chest and thighs,
# then a push back up to the knees. Whole body (the game plays it in place of the run).
LAYOUT = {
    "release": 0.35,
    "keys": [
        (0.00, {}),
        (0.15, {"hips": {"drop": 0.15, "shift": (0.0, 0.25), "yaw": 0.0, "lean": 35.0},
                "spine": {"twist": 0.0, "bend": 10.0, "side": 0.0},
                "rhand": (0.18, 0.75, 1.15), "lhand": (-0.18, 0.75, 1.15),
                "relbow": (0.4, 0.0, -0.9), "lelbow": (-0.4, 0.0, -0.9),
                "rfoot": (0.12, -0.10, None), "lfoot": (-0.12, 0.35, 0.25)}),
        (0.35, {"hips": {"drop": 0.62, "shift": (0.0, 0.85), "lean": 82.0},
                "spine": {"bend": 6.0},
                "rhand": (0.10, 2.50, 0.55), "lhand": (-0.32, 0.95, 0.45), "lelbow": (-0.8, 0.0, -0.6),
                "rfoot": (0.12, -0.30, 0.45), "lfoot": (-0.15, -0.10, 0.40)}),
        (0.60, {"hips": {"drop": 0.80, "shift": (0.0, 1.05), "lean": 88.0},
                "rhand": (0.12, 2.55, 0.16), "lhand": (-0.32, 1.00, 0.14),
                "rfoot": (0.12, -0.25, 0.10), "lfoot": (-0.15, -0.20, 0.10)}),
        (1.00, {"hips": {"drop": 0.80, "shift": (0.0, 1.05), "lean": 88.0},
                "rhand": (0.20, 2.35, 0.12), "lhand": (-0.30, 1.20, 0.12)}),
        (1.50, {"hips": {"drop": 0.45, "shift": (0.0, 0.90), "lean": 20.0},
                "spine": {"bend": 15.0},
                "rhand": (0.25, 1.10, 0.75), "lhand": (-0.25, 1.10, 0.75),
                "rfoot": (0.15, 0.40, None), "lfoot": (-0.15, 0.35, None)}),
    ],
}
THROWS["layout"] = LAYOUT

# Releases at the heights of the game's own throws (ULTIMATE-7, the 2026 final's close-ups of marked handlers): the
# high releases over the mark (at the shoulder to head, 1.5 m) and the breaks stepped out under the marker's arm,
# released about knee height (0.55 m, wide of the body); and the fake (0.35-0.4 s, the disc whipped up beside the
# head and back). Until now the high releases borrowed the hip-height backhand and forehand. Each release comes no
# sooner than the sim's wind-up for the kind (match.gd WINDUP), so the clip can start in time.
HOLD = {"rhand": (0.28, 0.18, 0.95), "relbow": (0.6, -0.6, -0.6)}
IDLE_END = {"hips": {"drop": 0.0, "shift": (0.0, 0.0), "yaw": 0.0, "lean": 0.0},
            "spine": {"twist": 0.0, "bend": 0.0, "side": 0.0},
            "rfoot": "idle", "rhand": (0.28, 0.20, 0.98), "relbow": (0.6, -0.6, -0.6), "lhand": "idle", "lelbow": None}
HIGH_FOREHAND = {
    "release": 0.35,
    "keys": [
        (0.00, dict(HOLD)),
        (0.05, dict(HOLD)),
        (0.23, {"hips": {"drop": 0.02, "shift": (0.05, 0.0), "yaw": 20.0, "lean": 0.0},
                "spine": {"twist": 18.0, "bend": 0.0, "side": -6.0},
                "rhand": (0.45, -0.20, 1.50), "relbow": (0.7, -0.4, 0.3), "lhand": (-0.40, 0.10, 1.10)}),
        (0.35, {"hips": {"yaw": 2.0}, "spine": {"twist": -4.0, "side": -8.0},
                "rhand": (0.42, 0.40, 1.58), "relbow": (0.6, 0.0, 0.2)}),
        (0.50, {"spine": {"twist": -16.0}, "rhand": (0.25, 0.70, 1.40), "relbow": (0.6, 0.3, -0.3)}),
        (1.05, dict(IDLE_END)),
    ],
}
HIGH_BACKHAND = {
    "release": 0.45,
    "keys": [
        (0.00, dict(HOLD)),
        (0.10, dict(HOLD)),
        (0.30, {"hips": {"drop": 0.02, "shift": (-0.05, 0.0), "yaw": -25.0, "lean": 0.0},
                "spine": {"twist": -30.0, "bend": 0.0, "side": 4.0},
                "rhand": (-0.45, -0.05, 1.50), "relbow": (-0.3, 0.9, 0.3), "lhand": (-0.35, 0.25, 1.20)}),
        (0.45, {"hips": {"yaw": 0.0}, "spine": {"twist": 0.0},
                "rhand": (-0.30, 0.45, 1.58), "relbow": (0.5, 0.3, 0.6)}),
        (0.60, {"spine": {"twist": 15.0}, "rhand": (0.25, 0.65, 1.40), "relbow": (0.6, 0.3, 0.0)}),
        (1.15, dict(IDLE_END)),
    ],
}
LOW_FOREHAND = {
    "release": 0.40,
    "keys": [
        (0.00, dict(HOLD)),
        (0.25, {"hips": {"drop": 0.30, "shift": (0.35, 0.05), "yaw": 25.0, "lean": 22.0},
                "spine": {"twist": 18.0, "bend": 25.0, "side": 15.0},
                "rfoot": (0.95, 0.20, None), "rhand": (0.75, -0.10, 0.58), "relbow": (0.3, -1.0, -0.3),
                "lhand": (-0.45, 0.05, 0.85)}),
        (0.40, {"hips": {"drop": 0.34, "shift": (0.42, 0.10), "yaw": 5.0, "lean": 24.0},
                "spine": {"twist": -5.0, "bend": 28.0, "side": 20.0},
                "rhand": (0.90, 0.45, 0.55), "relbow": (0.2, -0.3, -1.0)}),
        (0.58, {"hips": {"drop": 0.28, "shift": (0.38, 0.12), "yaw": -8.0, "lean": 18.0},
                "spine": {"twist": -15.0, "bend": 22.0, "side": 14.0},
                "rhand": (0.70, 0.75, 0.70), "relbow": (0.5, 0.2, -1.0)}),
        (1.20, dict(IDLE_END)),
    ],
}
LOW_BACKHAND = {
    "release": 0.40,
    "keys": [
        (0.00, dict(HOLD)),
        (0.25, {"hips": {"drop": 0.30, "shift": (-0.35, 0.10), "yaw": -30.0, "lean": 22.0},
                "spine": {"twist": -35.0, "bend": 25.0, "side": -15.0},
                "rfoot": (-0.70, 0.45, None), "rhand": (-0.75, -0.15, 0.60), "relbow": (-0.3, 0.9, 0.0),
                "lhand": (-0.20, -0.30, 0.90)}),
        (0.40, {"hips": {"drop": 0.34, "shift": (-0.42, 0.15), "yaw": -10.0, "lean": 24.0},
                "spine": {"twist": -10.0, "bend": 28.0, "side": -18.0},
                "rhand": (-0.80, 0.45, 0.55), "relbow": (-0.6, 0.6, -0.4)}),
        (0.58, {"hips": {"drop": 0.28, "shift": (-0.36, 0.15), "yaw": 5.0, "lean": 18.0},
                "spine": {"twist": 10.0, "bend": 22.0, "side": -12.0},
                "rhand": (-0.40, 0.80, 0.70), "relbow": (0.0, 0.6, -0.6)}),
        (1.20, dict(IDLE_END)),
    ],
}
FAKE = {
    "release": 0.18,             # the top of the fake
    "keys": [
        (0.00, dict(HOLD)),
        (0.18, {"hips": {"drop": 0.05, "shift": (0.05, 0.0), "yaw": 15.0, "lean": 0.0},
                "spine": {"twist": 15.0, "bend": 0.0, "side": -4.0},
                "rhand": (0.40, 0.05, 1.60), "relbow": (0.7, -0.3, 0.3), "lhand": (-0.35, 0.15, 1.00)}),
        (0.40, {"hips": {"drop": 0.0, "shift": (0.0, 0.0), "yaw": 0.0, "lean": 0.0},
                "spine": {"twist": 0.0, "bend": 0.0, "side": 0.0},
                "rhand": (0.28, 0.18, 0.95), "relbow": (0.6, -0.6, -0.6), "lhand": "idle", "lelbow": None}),
    ],
}
THROWS.update({"high_forehand": HIGH_FOREHAND, "high_backhand": HIGH_BACKHAND, "low_forehand": LOW_FOREHAND,
               "low_backhand": LOW_BACKHAND, "fake": FAKE})


def B(r, f, u):
    """Body frame (right, forward, up) to armature space (+X left, -Y forward, +Z up)."""
    return Vector((-r, -f, u))


# ------------------------------------------------------------------------------------------------- skeleton

def subtree(info, n):
    out = [n]
    for c in info.children[n]:
        out += subtree(info, c)
    return out


def rotate(info, T, n, Q):
    for x in subtree(info, n):
        T[x] = Q @ T[x]


def heads(info, T, h):
    """Bone heads in armature space from the rotations and the hips' head."""
    out = {info.root: h.copy()}
    for n in info.order[1:]:
        p = info.parent[n]
        D = T[p] @ info.rest3[p].inverted()
        out[n] = out[p] + D @ (info.head[n] - info.head[p])
    return out


def direction(T, n):
    return T[n].col[1].normalized()


def aim(info, T, n, d):
    d = d.normalized()
    rotate(info, T, n, direction(T, n).rotation_difference(d).to_matrix())


def two_bone(info, T, h, upper, lower, target, pole):
    """Point upper and lower so that lower's tail reaches target, the joint bending towards pole."""
    hd = heads(info, T, h)
    a = hd[upper]
    l1, l2 = info.length[upper], info.length[lower]
    to = target - a
    dist = min(max(to.length, abs(l1 - l2) + 1e-3), l1 + l2 - 1e-3)
    to_n = to.normalized()
    # The joint's angle off the line to the target (law of cosines), in the plane holding the pole.
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    ang = math.acos(max(-1.0, min(1.0, cos_a)))
    side = (pole - to_n * pole.dot(to_n))
    if side.length < 1e-6:
        side = Vector((0, 0, 1)) - to_n * to_n.z
    side.normalize()
    d1 = to_n * math.cos(ang) + side * math.sin(ang)
    aim(info, T, upper, d1)
    hd = heads(info, T, h)
    aim(info, T, lower, target - hd[lower])


# ----------------------------------------------------------------------------------------------------- pose

def lerp(a, b, s):
    if isinstance(a, (tuple, list)):
        return tuple(lerp(x, y, s) for x, y in zip(a, b))
    if isinstance(a, dict):
        return {k: lerp(a[k], b[k], s) for k in a}
    return a + (b - a) * s


def ease(s):
    return s * s * (3 - 2 * s)


def resolve(base_ctrl, keys):
    """Fill every key with every control (carried over from the previous key, or the idle pose's)."""
    out = []
    cur = dict(base_ctrl)
    for t, k in keys:
        cur = dict(cur)
        for name, v in k.items():
            if v == "idle":
                cur[name] = base_ctrl[name]
            elif v is None:
                cur[name] = base_ctrl.get(name)
            elif isinstance(v, dict):
                d = dict(cur.get(name) or {})
                d.update(v)
                cur[name] = d
            else:
                cur[name] = v
        out.append((t, cur))
    return out


def build(info, idle_pose, spec):
    T0, h0 = idle_pose
    T0 = {n: m.copy() for n, m in T0.items()}
    hd0 = heads(info, T0, h0)
    origin = Vector((h0.x, h0.y, 0.0))
    # Scale the authored distances (for a hips height of about 1.0 m) to this body.
    k = h0.z / 1.0

    def P(c):
        r, f, u = c
        return origin + B(r * k, f * k, u * k)

    def body_of(v):
        d = v - origin
        return (-d.x / k, -d.y / k, d.z / k)

    feet0 = {s: hd0[LEG[s][2]] for s in "rl"}
    hands0 = {s: hd0[ARM[s][2]] for s in "rl"}
    base_ctrl = {
        "hips": {"drop": 0.0, "shift": (0.0, 0.0), "yaw": 0.0, "lean": 0.0},
        "spine": {"twist": 0.0, "bend": 0.0, "side": 0.0},
        "rfoot": body_of(feet0["r"]), "lfoot": body_of(feet0["l"]),
        "rhand": body_of(hands0["r"]), "lhand": body_of(hands0["l"]),
        "relbow": None, "lelbow": None,
    }
    keys = resolve(base_ctrl, spec["keys"])
    for i, (t, c) in enumerate(keys):
        for s in "rl":
            f = c[s + "foot"]
            if f[2] is None:
                c[s + "foot"] = (f[0], f[1], base_ctrl[s + "foot"][2])
    poses = []
    t_end = keys[-1][0]
    n = int(round(t_end * FPS)) + 1
    for fi in range(n):
        t = fi / FPS
        j = max(i for i, (kt, _) in enumerate(keys) if kt <= t + 1e-9)
        if j == len(keys) - 1:
            c = keys[j][1]
        else:
            (ta, ca), (tb, cb) = keys[j], keys[j + 1]
            s = ease((t - ta) / (tb - ta))
            c = {}
            for name in ca:
                a, b = ca[name], cb[name]
                if a is None or b is None:
                    c[name] = b if s >= 0.5 else a
                else:
                    c[name] = lerp(a, b, s)
        poses.append(pose(info, T0, h0, c, P))
    return poses


def pose(info, T0, h0, c, P):
    T = {n: m.copy() for n, m in T0.items()}
    hp = c["hips"]
    up = Vector((0, 0, 1))
    h = h0 + B(hp["shift"][0], hp["shift"][1], -hp["drop"])
    # The hips: turn (yaw) and lean, carrying everything above and below.
    Q = Matrix.Rotation(math.radians(-hp["yaw"]), 3, up)
    rotate(info, T, info.root, Q)
    right = B(1, 0, 0)
    fwd = B(0, 1, 0)
    rotate(info, T, info.root, Matrix.Rotation(math.radians(hp["lean"]), 3, Q @ right * -1.0))
    # The spine: twist, bend and side lean, a third in each of its three bones.
    sp = c["spine"]
    for n in SPINE:
        axis = direction(T, n)
        rotate(info, T, n, Matrix.Rotation(math.radians(-sp["twist"] / 3), 3, axis))
        rotate(info, T, n, Matrix.Rotation(math.radians(sp["bend"] / 3), 3, (Q @ right) * -1.0))
        rotate(info, T, n, Matrix.Rotation(math.radians(sp["side"] / 3), 3, Q @ fwd))
    # The head keeps looking where it looked (towards the target), whatever the torso does.
    for n in ("Neck1", "Head"):
        if n in T:
            T[n] = T0[n].copy()
    # Arms: two-bone IK to the wrist target, the elbow towards its pole.
    for s in "rl":
        up_b, lo_b, hand_b = ARM[s]
        tgt = P(c[s + "hand"])
        pole = c[s + "elbow"]
        if pole is not None:
            pole_v = B(*pole)
        else:                       # keep the elbow bending the way it bends now
            hd = heads(info, T, h)
            pole_v = hd[lo_b] - (hd[up_b] + hd[hand_b]) * 0.5
        two_bone(info, T, h, up_b, lo_b, tgt, pole_v)
        # The hand follows the forearm (a straight wrist).
        aim(info, T, hand_b, direction(T, lo_b))
    # Legs: two-bone IK to the ankle targets, the knees forward; the feet keep their idle orientation.
    for s in "rl":
        up_b, lo_b, foot_b = LEG[s]
        tgt = P(c[s + "foot"])
        foot_T0 = T0[foot_b]
        two_bone(info, T, h, up_b, lo_b, tgt, Q @ fwd)
        R = (foot_T0 @ T[foot_b].inverted())
        rotate(info, T, foot_b, R)
    return T, h
