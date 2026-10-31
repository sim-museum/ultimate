"""Render frames of clips from an exported athlete GLB, for checking by eye.

    blender -b --python render_clips.py -- ATHLETE.glb OUT_DIR CLIP[:N] [CLIP[:N] ...] [--front]

Writes OUT_DIR/<clip>_<k>.png: N frames spread over the clip, from the side (or the front with --front).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
front = "--front" in argv
argv = [a for a in argv if a != "--front"]
glb, out_dir, specs = argv[0], argv[1], argv[2:]
os.makedirs(out_dir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
scene = bpy.context.scene
rig = next(o for o in scene.objects if o.type == "ARMATURE")
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 360
scene.render.resolution_y = 480
scene.render.film_transparent = False
world = bpy.data.worlds.new("w")
scene.world = world
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.6
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
floor = bpy.data.meshes.new("floor")
floor.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
fo = bpy.data.objects.new("floor", floor)
scene.collection.objects.link(fo)
actions = {a.name: a for a in bpy.data.actions}
print("actions:", sorted(actions))
for spec in specs:
    name, _, n = spec.partition(":")
    n = int(n or 6)
    act = next((a for k, a in actions.items() if k == name or k.startswith(name)), None)
    if act is None:
        print("no action", name)
        continue
    rig.animation_data_create()
    for t in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(t)
    rig.animation_data.action = act
    if hasattr(rig.animation_data, "action_slot") and act.slots:
        rig.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    for k in range(n):
        f = f0 + (f1 - f0) * k / max(1, n - 1)
        scene.frame_set(int(round(f)))
        hips = rig.matrix_world @ rig.pose.bones["Hips"].head
        target = Vector((hips.x, hips.y, 0.95))
        if front:
            cam.location = target + Vector((0, -6, 0))
            cam.rotation_euler = (math.radians(90), 0, 0)
        else:
            cam.location = target + Vector((6, 0, 0))
            cam.rotation_euler = (math.radians(90), 0, math.radians(90))
        scene.render.filepath = os.path.join(out_dir, f"{name}_{k}.png")
        bpy.ops.render.render(write_still=True)
print("rendered")
