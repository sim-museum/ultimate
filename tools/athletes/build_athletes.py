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
    ("throw", "79_92", 0.80, 2.20, False),
]

VARIANTS = {
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
    phen = {"age": 0.5, "cupsize": 0.5, "firmness": 0.6, "gender": 1.0, "proportions": 0.75,
            "height": v["phen"]["height"], "muscle": v["phen"]["muscle"], "weight": v["phen"]["weight"],
            "race": {"african": v["phen"]["african"], "asian": v["phen"]["asian"],
                     "caucasian": v["phen"]["caucasian"]}}
    info = {
        "name": name, "phenotype": phen, "rig": "cmu_mb",
        "proxy": "male_muscle_13290/male_muscle_13290.proxy",
        "skin_mhmat": f"{v['skin']}/{v['skin']}.mhmat", "skin_material_type": "MAKESKIN",
        "skin_material_settings": {},
        "eyes": "low-poly/low-poly.mhclo", "eyes_material_type": "MAKESKIN", "eyes_material_settings": {},
        "eyebrows": f"{v['eyebrows']}/{v['eyebrows']}.mhclo", "eyelashes": "eyelashes01/eyelashes01.mhclo",
        "hair": f"{v['hair']}/{v['hair']}.mhclo",
        "clothes": ["male_casualsuit04/male_casualsuit04.mhclo", "shoes05/shoes05.mhclo"],
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
    suit = next(o for o in bpy.data.objects if o.type == "MESH" and "casualsuit04" in o.name)
    body = next(o for o in bpy.data.objects if o.type == "MESH" and "male_muscle" in o.name)
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
    bm = bmesh.new()
    bm.from_mesh(suit.data)
    for f in bm.faces:
        f.material_index = 0 if f.calc_center_median().z > hip_z + 0.02 else 1
    bm.to_mesh(suit.data)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    suit.select_set(True)
    bpy.context.view_layer.objects.active = suit
    bpy.ops.mesh.separate(type="MATERIAL")
    for o in bpy.data.objects:
        if o.type == "MESH" and "casualsuit04" in o.name:
            o.name = "Jersey" if o.data.materials[0].name.startswith("Jersey") else "Shorts"
    # Show the legs the jeans used to hide: drop the body's mask modifiers (none hide anything we keep).
    for m in list(body.modifiers):
        if m.type == "MASK":
            body.modifiers.remove(m)
    # The proxy is the body drawn in the game; the full base mesh it was fitted to is not exported.
    if basemesh is not None:
        bpy.data.objects.remove(basemesh)
    body.name = "Body"
    log("kit: cut at z", round(cut_z, 3), "knee", round(knee_z, 3), "hip", round(hip_z, 3))


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


def retarget(rig, name, sk, frames):
    bones = rig.data.bones
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    legs_mpfb = bones["LeftUpLeg"].length + bones["LeftLeg"].length
    legs_cmu = (sk.bones["lfemur"]["length"] + sk.bones["ltibia"]["length"]) * cmu_amc.UNIT_M
    sc = legs_mpfb / legs_cmu
    toe_rest = min(bones["LeftToeBase"].tail_local.z, bones["LeftFoot"].tail_local.z)
    toes = sorted(f[2] for f in frames)
    ground = toe_rest - sc * toes[max(0, len(toes) // 10)]
    rest = {b.name: b.matrix_local.copy() for b in bones}
    align = {}
    for b in bones:
        s = BONE_SEG.get(b.name)
        if s is None or s == "root":
            align[b.name] = Matrix.Identity(3)
            continue
        db = (b.tail_local - b.head_local).normalized()
        a_s = Vector(K @ sk.bones[s]["direction"]).normalized()
        align[b.name] = db.rotation_difference(a_s).to_matrix()
    Km = Matrix(K.tolist())
    Kt = Km.transposed()
    order = []
    stack = [b for b in bones if b.parent is None]
    while stack:
        b = stack.pop(0)
        order.append(b)
        stack.extend(b.children)
    unmapped = [b.name for b in bones if b.name not in BONE_SEG]
    if unmapped:
        log("unmapped bones keep their rest pose:", unmapped)
    keys = {b.name: [] for b in bones}
    hips_loc = []
    for gl, hp, _ in frames:
        T = {}
        for b in order:
            s = BONE_SEG.get(b.name)
            rb = rest[b.name].to_3x3()
            if s is None:
                T[b.name] = (T[b.parent.name] @ rest[b.parent.name].to_3x3().inverted() @ rb) if b.parent else rb
                q = Quaternion()
            else:
                G = Km @ Matrix(gl[s].tolist()) @ Kt
                T[b.name] = G @ align[b.name] @ rb
                if b.parent is None:
                    q = (rb.inverted() @ T[b.name]).to_quaternion()
                else:
                    rp = rest[b.parent.name].to_3x3()
                    q = (rb.inverted() @ rp @ T[b.parent.name].inverted() @ T[b.name]).to_quaternion()
            prev = keys[b.name][-1] if keys[b.name] else None
            if prev is not None and prev.dot(q) < 0:
                q = -q
            keys[b.name].append(q)
        h = Vector(K @ (hp * sc)) + Vector((0, 0, ground))
        root = order[0]
        hips_loc.append(rest[root.name].to_3x3().inverted() @ (h - rest[root.name].translation))
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    n = len(frames)

    def curve(path, idx, values):
        fc = act.fcurve_ensure_for_datablock(rig, path, index=idx)
        fc.keyframe_points.add(n)
        co = []
        for i, v in enumerate(values):
            co += [i + 1, v]
        fc.keyframe_points.foreach_set("co", co)
        fc.update()

    for b in bones:
        path = f'pose.bones["{b.name}"].rotation_quaternion'
        for i in range(4):
            curve(path, i, [q[i] for q in keys[b.name]])
    root = order[0].name
    for i in range(3):
        curve(f'pose.bones["{root}"].location', i, [v[i] for v in hips_loc])
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, act)
    rig.animation_data.action = None
    return sc


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
    names = argv[1:] or list(VARIANTS)
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
        rig = bpy.data.objects["Athlete"]
        for (name, *_), (sk, frames, info) in clips:
            sc = retarget(rig, name, sk, frames)
            c = meta.setdefault(name, {k: v for k, v in info.items() if k != "velocity"})
            c["cmu_velocity"] = info["velocity"]
            # The clip's own speed for this body, measured from its planted foot (a still clip keeps 0).
            v = measured_velocity(rig, name) if info["loop"] and name != "idle" else {"right": 0.0, "forward": 0.0}
            if info["loop"] and name != "idle" and v["right"] == 0.0 and v["forward"] == 0.0:
                v = {k: x * sc for k, x in info["velocity"].items()}    # no clean foot plant found
            c.setdefault("velocity", {})[vn] = v
            log(f"{vn} {name}: measured {v['right']:+.2f} right {v['forward']:+.2f} forward"
                f" (CMU {info['velocity']['right']:+.2f} {info['velocity']['forward']:+.2f})")
        # Textures: at most 1024 px, saved as JPEG in the GLB (players are small on screen; the repo stays small).
        for img in bpy.data.images:
            w, h = img.size
            if max(w, h) > 1024:
                s = 1024 / max(w, h)
                img.scale(max(1, int(w * s)), max(1, int(h * s)))
        path = os.path.join(out_dir, f"athlete_{vn}.glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animation_mode="NLA_TRACKS",
                                  export_apply=False, export_yup=True, export_image_format="JPEG",
                                  export_image_quality=85)
        log("wrote", path, [o.name for o in bpy.data.objects])
    json.dump({"fps": FPS, "clips": meta, "variants": names}, open(os.path.join(out_dir, "clips.json"), "w"),
              indent=1)
    log("done")


main()
