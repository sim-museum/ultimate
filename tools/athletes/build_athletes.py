"""Build the ultimate athletes: MPFB humans (CC0) in a jersey and shorts, on MPFB's cmu_mb skeleton, with CMU motion
capture clips retargeted onto each one, exported as GLB for Godot.

    blender -b --python build_athletes.py -- OUT_DIR [VARIANT ...]

Per variant it writes OUT_DIR/athlete_<variant>.glb, and OUT_DIR/clips.json describes the clips (loop or not,
length, the clip's own velocity in the body frame, the release time of a throw).

Retargeting: for every frame, each MPFB bone gets the rotation its CMU segment has made away from the CMU rest
pose, after a one-time correction that turns the MPFB rest direction onto the CMU rest direction (the CMU rest
pose holds the arms out, MPFB's hang down). So every limb points where the capture says; twist follows the capture.
"""
import bpy
import json
import math
import os
import sys

import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cmu_amc  # noqa: E402
import keyed_throws  # noqa: E402

from bl_ext.user_default.mpfb.services.humanservice import HumanService as HS  # noqa: E402

CMU = os.path.expanduser(os.environ.get("CMU_DIR", "~/ultimate_re/cmu"))   # the CMU files (fetch_cmu.sh)
HZ = 120.0
FPS = 30
STEP = int(HZ / FPS)

# CMU segment that drives each MPFB cmu_mb bone.
BONE_SEG = {
    "Hips": "root", "LowerBack": "lowerback", "Spine": "upperback", "Spine1": "thorax",
    "Neck": "lowerneck", "Neck1": "upperneck", "Head": "head",
    "LHipJoint": "lhipjoint", "LeftUpLeg": "lfemur", "LeftLeg": "ltibia", "LeftFoot": "lfoot", "LeftToeBase": "ltoes",
    "RHipJoint": "rhipjoint", "RightUpLeg": "rfemur", "RightLeg": "rtibia", "RightFoot": "rfoot",
    "RightToeBase": "rtoes",
    "LeftShoulder": "lclavicle", "LeftArm": "lhumerus", "LeftForeArm": "lradius", "LeftHand": "lwrist",
    "LeftFingerBase": "lhand", "LThumb": "lthumb", "LeftHandIndex1": "lfingers",
    "RightShoulder": "rclavicle", "RightArm": "rhumerus", "RightForeArm": "rradius", "RightHand": "rwrist",
    "RightFingerBase": "rhand", "RThumb": "rthumb", "RightHandIndex1": "rfingers",
}

# name, trial, start s, end s, loop. A loop searches for the best cycle starting near `start` and ending before `end`.
CLIPS = [
    ("idle", "79_92", 0.05, 0.75, True),
    ("jog", "16_35", 0.10, 1.30, True),
    ("run", "09_01", 0.05, 1.20, True),
    ("backpedal", "76_11", 1.00, 2.70, True),
    ("diag_l", "102_24", 0.60, 1.45, True),
    ("diag_r", "102_25", 0.90, 1.85, True),
    ("backhand", "79_92", 0.80, 2.20, False),
    ("backhand2", "79_92", 2.55, 3.95, False),
]

# The game is women's ultimate. Five women with East Asian features (the white team is mostly East Asian players),
# four others; ponytails, braids, buns: hair tied back, as in the real game.
# "sleeves": the long-sleeved shirt, its forearms a separate piece the game tints dark (an undershirt).
# "knee": knee sleeves ("l", "r" or "both"); "headband": a band round the forehead (both tinted like the undershirt).
# The gold-standard broadcasts show knee sleeves, headbands and visors on many players.
DEFAULT_VARIANTS = ["as1", "as2", "as3", "as4", "as5", "w1", "w2", "w4", "w5"]
_F = {"gender": 0.0, "proxy": "female_muscle_13442"}
_ASIA = {"african": 0.03, "asian": 0.94, "caucasian": 0.03}
VARIANTS = {
    "as1": dict(_F, skin="young_asian_female", hair="ponytail01", eyebrows="eyebrow004", eyes="brown",
                sleeves=True, knee="both", headband=False, phen=dict(_ASIA, height=0.42, muscle=0.66, weight=0.40)),
    "as2": dict(_F, skin="young_asian_female", hair="braid01", eyebrows="eyebrow002", eyes="brown",
                sleeves=False, knee=None, headband=True, phen=dict(_ASIA, height=0.50, muscle=0.70, weight=0.42)),
    "as3": dict(_F, skin="young_asian_female", hair="bob01", eyebrows="eyebrow005", eyes="brownlight",
                sleeves=True, knee="r", headband=False, phen=dict(_ASIA, height=0.46, muscle=0.64, weight=0.41)),
    "as4": dict(_F, skin="young_asian_female", hair="ponytail01", eyebrows="eyebrow008", eyes="brown",
                sleeves=False, knee="both", headband=True, phen=dict(_ASIA, height=0.58, muscle=0.72, weight=0.43)),
    "as5": dict(_F, skin="young_asian_female", hair="short04", eyebrows="eyebrow003", eyes="brown",
                sleeves=True, knee=None, headband=False, phen=dict(_ASIA, height=0.52, muscle=0.68, weight=0.40)),
    "w1": dict(_F, skin="young_african_female", hair="braid01", eyebrows="eyebrow002", eyes="brown",
               sleeves=False, knee="l", headband=True, phen={"height": 0.55, "muscle": 0.68, "weight": 0.42, "african": 0.9, "asian": 0.05,
                                    "caucasian": 0.05}),
    "w2": dict(_F, skin="young_caucasian_female", hair="ponytail01", eyebrows="eyebrow007", eyes="blue",
               sleeves=True, knee="both", headband=False, phen={"height": 0.6, "muscle": 0.65, "weight": 0.4, "african": 0.05, "asian": 0.05,
                                   "caucasian": 0.9}),
    "w4": dict(_F, skin="young_caucasian_female2", hair="ponytail01", eyebrows="eyebrow010", eyes="green",
               sleeves=False, knee=None, headband=True, phen={"height": 0.65, "muscle": 0.62, "weight": 0.44, "african": 0.2, "asian": 0.1,
                                    "caucasian": 0.7}),
    "w5": dict(_F, skin="young_african_female", hair="afro01", eyebrows="eyebrow011", eyes="brown",
               sleeves=True, knee="r", headband=False, phen={"height": 0.62, "muscle": 0.7, "weight": 0.43, "african": 0.85, "asian": 0.05,
                                   "caucasian": 0.1}),
    "a": {"skin": "young_african_male", "hair": "short02", "eyebrows": "eyebrow001", "eyes": "brown",
          "phen": {"height": 0.62, "muscle": 0.75, "weight": 0.45, "african": 0.9, "asian": 0.05,
                   "caucasian": 0.05}},
    "b": {"skin": "young_caucasian_male", "hair": "short04", "eyebrows": "eyebrow006", "eyes": "blue",
          "phen": {"height": 0.55, "muscle": 0.7, "weight": 0.42, "african": 0.05, "asian": 0.05,
                   "caucasian": 0.9}},
    "c": {"skin": "young_asian_male", "hair": "short03", "eyebrows": "eyebrow003", "eyes": "brownlight",
          "phen": {"height": 0.5, "muscle": 0.72, "weight": 0.4, "african": 0.05, "asian": 0.9,
                   "caucasian": 0.05}},
    "d": {"skin": "young_caucasian_male2", "hair": "short01", "eyebrows": "eyebrow009", "eyes": "green",
          "phen": {"height": 0.68, "muscle": 0.65, "weight": 0.48, "african": 0.2, "asian": 0.1,
                   "caucasian": 0.7}},
}

# CMU (Y up, facing +Z, left +X) to Blender (Z up, facing -Y, left +X).
K = np.array([[1.0, 0, 0], [0, 0, -1.0], [0, 1.0, 0]])


def log(*a):
    print("[athletes]", *a, flush=True)


# ------------------------------------------------------------------------------------------------- the human

def build_human(name, v):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    phen = {"age": 0.5, "cupsize": 0.5, "firmness": 0.6, "gender": v.get("gender", 1.0), "proportions": 0.75,
            "height": v["phen"]["height"], "muscle": v["phen"]["muscle"], "weight": v["phen"]["weight"],
            "race": {"african": v["phen"]["african"], "asian": v["phen"]["asian"],
                     "caucasian": v["phen"]["caucasian"]}}
    info = {
        "name": name, "phenotype": phen, "rig": "cmu_mb",
        "proxy": "{0}/{0}.proxy".format(v.get("proxy", "male_muscle_13290")),
        "skin_mhmat": f"{v['skin']}/{v['skin']}.mhmat", "skin_material_type": "MAKESKIN",
        "skin_material_settings": {},
        "eyes": "low-poly/low-poly.mhclo", "eyes_material_type": "MAKESKIN", "eyes_material_settings": {},
        "eyebrows": f"{v['eyebrows']}/{v['eyebrows']}.mhclo", "eyelashes": "eyelashes01/eyelashes01.mhclo",
        "hair": f"{v['hair']}/{v['hair']}.mhclo",
        "clothes": ["{0}/{0}.mhclo".format("male_casualsuit02" if v.get("sleeves") else "male_casualsuit04"),
                    "shoes05/shoes05.mhclo"],
        "teeth": "", "tongue": "", "targets": [], "expressions": [], "makeup": [],
        "alternative_materials": {}, "color_adjustments": {},
    }
    settings = HS.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    settings["load_clothes"] = True
    basemesh = HS.deserialize_from_dict(info, settings)
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    rig.name = "Athlete"
    rig.data.name = "Athlete"
    return basemesh, rig


def make_kit():
    """The T-shirt and jeans become a jersey and shorts: the jeans are cut above the knee, the two pieces go to
    separate objects with plain white materials (Godot tints them per team), and no body is hidden under the
    shorts' legs any more."""
    import bmesh
    suit = next(o for o in bpy.data.objects if o.type == "MESH" and "casualsuit0" in o.name)
    body = next(o for o in bpy.data.objects if o.type == "MESH" and "_muscle_" in o.name)
    basemesh = next((o for o in bpy.data.objects if o.type == "MESH" and o.name.endswith(".body")), None)
    # The body's knee height in this pose (rest): the LeftLeg bone's head.
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    knee_z = (rig.matrix_world @ rig.data.bones["LeftLeg"].head_local).z
    hip_z = (rig.matrix_world @ rig.data.bones["LeftUpLeg"].head_local).z
    cut_z = knee_z + 0.38 * (hip_z - knee_z)
    for m in list(suit.modifiers):
        if m.type not in ("ARMATURE",):
            bpy.context.view_layer.objects.active = suit
            bpy.ops.object.modifier_apply(modifier=m.name)
    bm = bmesh.new()
    bm.from_mesh(suit.data)
    bm.verts.ensure_lookup_table()
    # Islands: the shirt and the jeans are separate pieces of cloth.
    island = {}
    k = 0
    for v in bm.verts:
        if v in island:
            continue
        stack = [v]
        island[v] = k
        while stack:
            x = stack.pop()
            for e in x.link_edges:
                o = e.other_vert(x)
                if o not in island:
                    island[o] = k
                    stack.append(o)
        k += 1
    mean_z = {}
    for v, i in island.items():
        mean_z.setdefault(i, []).append(v.co.z)
    mean_z = {i: sum(z) / len(z) for i, z in mean_z.items()}
    big = sorted(mean_z, key=lambda i: -len([1 for v in island if island[v] == i]))
    log("kit islands", len(mean_z), "largest mean z", [(i, round(mean_z[i], 2)) for i in big[:4]])
    # Jersey: islands centred above the hips; shorts: the rest.
    jersey_islands = {i for i, z in mean_z.items() if z > hip_z + 0.05}
    # Cut the jeans' legs above the knee.
    dead = [v for v in bm.verts if island[v] not in jersey_islands and v.co.z < cut_z]
    bmesh.ops.delete(bm, geom=dead, context="VERTS")
    bm.to_mesh(suit.data)
    bm.free()
    # Materials: one white material per piece.
    jersey_mat = bpy.data.materials.new("Jersey")
    shorts_mat = bpy.data.materials.new("Shorts")
    for mat, col in ((jersey_mat, (1, 1, 1, 1)), (shorts_mat, (1, 1, 1, 1))):
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Roughness"].default_value = 0.85
    suit.data.materials.clear()
    suit.data.materials.append(jersey_mat)
    suit.data.materials.append(shorts_mat)
    # The long-sleeved shirt: the jersey's own sleeve ends at mid upper arm; the rest of the arm is an undershirt
    # (its own piece, which the game tints dark).
    long_sleeves = "casualsuit02" in suit.name
    shoulder_x = abs(rig.data.bones["LeftArm"].head_local.x)
    if long_sleeves:
        sleeves_mat = bpy.data.materials.new("Sleeves")
        sleeves_mat.use_nodes = True
        sleeves_mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.7
        suit.data.materials.append(sleeves_mat)
    bm = bmesh.new()
    bm.from_mesh(suit.data)
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z <= hip_z + 0.02:
            f.material_index = 1
        elif long_sleeves and abs(c.x) > shoulder_x + 0.11:
            f.material_index = 2
        else:
            f.material_index = 0
    bm.to_mesh(suit.data)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    suit.select_set(True)
    bpy.context.view_layer.objects.active = suit
    bpy.ops.mesh.separate(type="MATERIAL")
    for o in bpy.data.objects:
        if o.type == "MESH" and "casualsuit0" in o.name:
            o.name = o.data.materials[0].name.split(".")[0]          # Jersey, Shorts or Sleeves
    # Show the legs the jeans used to hide: drop the body's mask modifiers (none hide anything we keep).
    for m in list(body.modifiers):
        if m.type == "MASK":
            body.modifiers.remove(m)
    # The proxy is the body drawn in the game; the full base mesh it was fitted to is not exported.
    if basemesh is not None:
        bpy.data.objects.remove(basemesh)
    body.name = "Body"
    log("kit: cut at z", round(cut_z, 3), "knee", round(knee_z, 3), "hip", round(hip_z, 3))


def make_accessories(v):
    """Knee sleeves and a headband, cut from the body's own skin: the faces in a band round the knee (or the
    forehead) are copied, pushed out along their normals, and kept as their own piece with the body's skin weights,
    so they bend with the leg (or the head) exactly. Plain white materials: the game tints them."""
    import bmesh
    body = bpy.data.objects["Body"]
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    pieces = []
    if v.get("knee"):
        sides = ["Left", "Right"] if v["knee"] == "both" else (["Left"] if v["knee"] == "l" else ["Right"])
        for side in sides:
            knee = rig.matrix_world @ rig.data.bones[f"{side}Leg"].head_local
            pieces.append(("KneeSleeves", lambda c, k=knee: k.z - 0.07 < c.z < k.z + 0.09
                           and math.hypot(c.x - k.x, c.y - k.y) < 0.11, 0.004, (knee.z - 0.06, knee.z + 0.08)))
    if v.get("headband"):
        top = max((body.matrix_world @ vx.co).z for vx in body.data.vertices)
        head = rig.matrix_world @ rig.data.bones["Head"].head_local
        pieces.append(("Headband", lambda c, t=top, h=head: t - 0.085 < c.z < t - 0.05
                       and math.hypot(c.x - h.x, c.y - h.y) < 0.14, 0.009, (top - 0.08, top - 0.052)))
    made = {}
    for name, inside, push, (lo, hi) in pieces:
        o = body.copy()
        o.data = body.data.copy()
        bpy.context.collection.objects.link(o)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        mw = o.matrix_world
        dead = [f for f in bm.faces if not inside(mw @ f.calc_center_median())]
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        bm.normal_update()
        # Straight edges: the kept faces overhang the band in a zigzag; pull their corners onto its edges.
        mwi = mw.inverted()
        for vx in bm.verts:
            w = mw @ (vx.co + vx.normal * push)
            w.z = min(max(w.z, lo), hi)
            vx.co = mwi @ w
        bm.to_mesh(o.data)
        bm.free()
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        mat.use_backface_culling = False
        mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.6
        o.data.materials.clear()
        o.data.materials.append(mat)
        made.setdefault(name, []).append(o)
    # One object per kind (both knees together).
    for name, objs in made.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        bpy.context.view_layer.objects.active.name = name
        log("accessory", name, len(bpy.context.view_layer.objects.active.data.polygons), "faces")


# ---------------------------------------------------------------------------------------------- the motion

def rot_y(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])


def best_loop(feats, a0, a1, b_min, b_max):
    best = None
    for a in range(a0, a1 + 1):
        for b in range(a + b_min, min(len(feats) - 1, a + b_max) + 1):
            d = float(np.sum((feats[a] - feats[b]) ** 2))
            if best is None or d < best[0]:
                best = (d, a, b)
    return best


def clip_frames(name, trial, t0, t1, loop):
    sk = cmu_amc.Skeleton(os.path.join(CMU, trial.split("_")[0] + ".asf"))
    frames = cmu_amc.read_amc(os.path.join(CMU, trial + ".amc"), sk)
    res = [cmu_amc.fk(sk, f) for f in frames]
    i0, i1 = int(t0 * HZ), min(len(res) - 1, int(t1 * HZ))
    # Pose features in the pelvis frame (for finding the loop).
    feats = []
    for g, end, pos in res:
        f = g["root"] @ np.array([0, 0, 1.0])
        yaw = math.degrees(math.atan2(f[0], f[2]))
        r = rot_y(-yaw)
        feats.append(np.concatenate([r @ (end[s] - pos) for s in
                                     ("lfoot", "rfoot", "lwrist", "rwrist", "head", "ltibia", "rtibia")]))
    if loop:
        span = i1 - i0
        d, a, b = best_loop(feats, i0, i0 + max(1, span // 3), max(int(0.45 * HZ), span // 3), span)
        log(f"{name}: loop {a / HZ:.2f}-{b / HZ:.2f} s ({(b - a) / HZ:.2f} s), mismatch {d:.4f}")
    else:
        a, b = i0, i1
    # Facing: the mean pelvis heading over the clip, turned to face +Z (Blender -Y).
    yaws = []
    for g, _, _ in res[a:b + 1]:
        f = g["root"] @ np.array([0, 0, 1.0])
        yaws.append(math.atan2(f[0], f[2]))
    yaw = math.degrees(math.atan2(np.mean(np.sin(yaws)), np.mean(np.cos(yaws))))
    ry = rot_y(-yaw)
    T = (b - a) / HZ
    p_a, p_b = ry @ res[a][2], ry @ res[b][2]
    vel = (p_b - p_a) / T if loop else np.zeros(3)
    vel[1] = 0.0
    # Body-frame velocity in game terms: x right, z forward (CMU: +X left, +Z forward).
    v_body = {"right": float(-vel[0]), "forward": float(vel[2])}
    out = []
    for i in range(a, b + 1 if not loop else b, STEP):
        g, end, pos = res[i]
        gl = {s: ry @ m for s, m in g.items()}
        p = ry @ pos
        t = (i - a) / HZ
        hp = p - p_a - vel * t
        hp[1] = p[1]
        toes = min((ry @ end["ltoes"])[1], (ry @ end["rtoes"])[1], (ry @ end["lfoot"])[1], (ry @ end["rfoot"])[1])
        out.append((gl, hp, toes))
    release = None
    if not loop:
        # The release: the right wrist's peak speed.
        sp = [np.linalg.norm(res[i + 1][1]["rwrist"] - res[i - 1][1]["rwrist"]) * HZ / 2 for i in range(a + 1, b)]
        k = int(np.argmax(sp))
        release = (k + 1) / HZ
        log(f"{name}: release at {release:.2f} s, wrist {max(sp):.1f} m/s")
    return sk, out, {"loop": loop, "length": len(out) / FPS, "velocity": v_body, "release": release,
                     "source": f"CMU {trial} {a / HZ:.2f}-{b / HZ:.2f} s"}


class RigInfo:
    """The rest pose of the athlete's skeleton in armature space (Blender: +X left, -Y forward, +Z up)."""

    def __init__(self, rig):
        self.rig = rig
        bones = rig.data.bones
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.rest3 = {n: m.to_3x3() for n, m in self.rest.items()}
        self.head = {b.name: b.head_local.copy() for b in bones}
        self.length = {b.name: b.length for b in bones}
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.children = {b.name: [c.name for c in b.children] for b in bones}
        self.order = []
        stack = [b.name for b in bones if b.parent is None]
        while stack:
            n = stack.pop(0)
            self.order.append(n)
            stack.extend(self.children[n])
        self.root = self.order[0]


def mocap_poses(info, sk, frames):
    """Armature-space rotations T[bone] (3x3) and the hips' head position for each mocap frame, and the leg scale."""
    rig = info.rig
    bones = rig.data.bones
    legs_mpfb = bones["LeftUpLeg"].length + bones["LeftLeg"].length
    legs_cmu = (sk.bones["lfemur"]["length"] + sk.bones["ltibia"]["length"]) * cmu_amc.UNIT_M
    sc = legs_mpfb / legs_cmu
    toe_rest = min(bones["LeftToeBase"].tail_local.z, bones["LeftFoot"].tail_local.z)
    toes = sorted(f[2] for f in frames)
    ground = toe_rest - sc * toes[max(0, len(toes) // 10)]
    align = {}
    for n in info.order:
        s = BONE_SEG.get(n)
        if s is None or s == "root":
            align[n] = Matrix.Identity(3)
            continue
        db = (bones[n].tail_local - bones[n].head_local).normalized()
        a_s = Vector(K @ sk.bones[s]["direction"]).normalized()
        align[n] = db.rotation_difference(a_s).to_matrix()
    Km = Matrix(K.tolist())
    Kt = Km.transposed()
    poses = []
    for gl, hp, _ in frames:
        T = {}
        for n in info.order:
            s = BONE_SEG.get(n)
            rb = info.rest3[n]
            if s is None:
                p = info.parent[n]
                T[n] = (T[p] @ info.rest3[p].inverted() @ rb) if p else rb
            else:
                G = Km @ Matrix(gl[s].tolist()) @ Kt
                T[n] = G @ align[n] @ rb
        h = Vector(K @ (hp * sc)) + Vector((0, 0, ground))
        poses.append((T, h))
    return poses, sc


def write_action(info, name, poses):
    """Key a clip from armature-space poses (T, hips head) at one frame per 1/FPS s and push it to an NLA track."""
    rig = info.rig
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    keys = {n: [] for n in info.order}
    hips_loc = []
    for T, h in poses:
        for n in info.order:
            rb = info.rest3[n]
            p = info.parent[n]
            if p is None:
                q = (rb.inverted() @ T[n]).to_quaternion()
            else:
                q = (rb.inverted() @ info.rest3[p] @ T[p].inverted() @ T[n]).to_quaternion()
            prev = keys[n][-1] if keys[n] else None
            if prev is not None and prev.dot(q) < 0:
                q = -q
            keys[n].append(q)
        r = info.root
        hips_loc.append(info.rest3[r].inverted() @ (h - info.rest[r].translation))
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    n_frames = len(poses)

    def curve(path, idx, values):
        fc = act.fcurve_ensure_for_datablock(rig, path, index=idx)
        fc.keyframe_points.add(n_frames)
        co = []
        for i, v in enumerate(values):
            co += [i + 1, v]
        fc.keyframe_points.foreach_set("co", co)
        fc.update()

    for n in info.order:
        path = f'pose.bones["{n}"].rotation_quaternion'
        for i in range(4):
            curve(path, i, [q[i] for q in keys[n]])
    for i in range(3):
        curve(f'pose.bones["{info.root}"].location', i, [v[i] for v in hips_loc])
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    rig.animation_data.action = None


def retarget(rig, name, sk, frames, info=None):
    info = info or RigInfo(rig)
    poses, sc = mocap_poses(info, sk, frames)
    write_action(info, name, poses)
    return sc, poses


def measured_velocity(rig, name):
    """The clip's own ground speed on this body: minus the planted foot's velocity in the armature frame (the
    lower toe, while it is near its lowest), as game terms (right, forward). Blender: -Y forward, +X left."""
    tracks = rig.animation_data.nla_tracks
    for tr in tracks:
        tr.mute = tr.name != name
    strip = tracks[name].strips[0]
    f0, f1 = int(strip.frame_start), int(strip.frame_end)
    scene = bpy.context.scene
    pts = []
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        feet = [rig.pose.bones[b].head.copy() for b in ("LeftToeBase", "RightToeBase")]
        pts.append(min(feet, key=lambda v: v.z))
    low = min(p.z for p in pts)
    vs = []
    for a, b in zip(pts, pts[1:]):
        if a.z < low + 0.03 and b.z < low + 0.03 and (a - b).length < 0.3:
            vs.append((b - a) * FPS)
    for tr in tracks:
        tr.mute = False
    if not vs:
        return {"right": 0.0, "forward": 0.0}
    vx = float(np.median([v.x for v in vs]))
    vy = float(np.median([v.y for v in vs]))
    # Ground speed = -foot velocity. Forward is -Y; right is -X.
    return {"right": vx, "forward": vy}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[0] if argv else "athletes_out")
    names = argv[1:] or DEFAULT_VARIANTS
    os.makedirs(out_dir, exist_ok=True)
    # The clips are keyed one frame per 1/FPS s: the scene (and so the glTF exporter) must run at FPS, or the
    # clips are stretched (Blender's default is 24 fps: 25% longer, played 20% slow).
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    meta = {}
    clips = [(c, clip_frames(*c)) for c in CLIPS]
    for vn in names:
        build_human(f"athlete_{vn}", VARIANTS[vn])
        make_kit()
        make_accessories(VARIANTS[vn])
        rig = bpy.data.objects["Athlete"]
        info = RigInfo(rig)
        mocap = {}
        for (name, *_), (sk, frames, cinfo) in clips:
            sc, poses = retarget(rig, name, sk, frames, info)
            mocap[name] = poses
            c = meta.setdefault(name, {k: v for k, v in cinfo.items() if k != "velocity"})
            c["cmu_velocity"] = cinfo["velocity"]
            # The clip's own speed for this body, measured from its planted foot (a still clip keeps 0).
            moving = cinfo["loop"] and name != "idle"
            v = measured_velocity(rig, name) if moving else {"right": 0.0, "forward": 0.0}
            if moving and v["right"] == 0.0 and v["forward"] == 0.0:
                v = {k: x * sc for k, x in cinfo["velocity"].items()}    # no clean foot plant found
            c.setdefault("velocity", {})[vn] = v
            log(f"{vn} {name}: measured {v['right']:+.2f} right {v['forward']:+.2f} forward"
                f" (CMU {cinfo['velocity']['right']:+.2f} {cinfo['velocity']['forward']:+.2f})")
        # The throws CMU does not have, keyed by hand from the idle pose (keyed_throws.py).
        for name, spec in keyed_throws.THROWS.items():
            poses = keyed_throws.build(info, mocap["idle"][0], spec)
            write_action(info, name, poses)
            meta[name] = {"loop": False, "length": len(poses) / FPS, "velocity": {vn: {"right": 0.0, "forward": 0.0}},
                          "release": spec["release"], "source": "keyed (keyed_throws.py)"}
            log(f"{vn} {name}: keyed, {len(poses)} frames, release {spec['release']:.2f} s")
        # Textures: at most 1024 px, saved as JPEG in the GLB (players are small on screen; the repo stays small).
        for img in bpy.data.images:
            w, h = img.size
            if max(w, h) > 1024:
                s = 1024 / max(w, h)
                img.scale(max(1, int(w * s)), max(1, int(h * s)))
        # Hair, eyebrows and eyelashes keep their alpha (PNG: the strands are cut out of cards); the rest is JPEG.
        for img in bpy.data.images:
            keep_alpha = any(k in img.name.lower() for k in ("hair", "pony", "braid", "bob", "short0", "afro",
                                                              "long0", "eyebrow", "eyelash"))
            img.file_format = "PNG" if keep_alpha else "JPEG"
        path = os.path.join(out_dir, f"athlete_{vn}.glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animation_mode="NLA_TRACKS",
                                  export_apply=False, export_yup=True, export_image_format="AUTO",
                                  export_image_quality=85)
        log("wrote", path, [o.name for o in bpy.data.objects])
    json.dump({"fps": FPS, "clips": meta, "variants": names}, open(os.path.join(out_dir, "clips.json"), "w"),
              indent=1)
    log("done")


main()
