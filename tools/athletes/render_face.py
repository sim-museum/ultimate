"""Render a close-up of an athlete GLB's face (front and three-quarter), for checking by eye.
    blender -b --python render_face.py -- ATHLETE.glb OUT_PREFIX"""
import math, sys
import bpy
from mathutils import Vector
glb, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
rig = next(o for o in sc.objects if o.type == "ARMATURE")
head = rig.matrix_world @ rig.pose.bones["Head"].head
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "TEXTURE"
sc.render.resolution_x = 360
sc.render.resolution_y = 360
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 0.42
sc.collection.objects.link(cam)
sc.camera = cam
t = head + Vector((0, 0, 0.08))
for name, ang in (("front", 0.0), ("three_q", 35.0)):
    a = math.radians(ang)
    cam.location = t + Vector((3 * math.sin(a), -3 * math.cos(a), 0))
    cam.rotation_euler = (math.radians(90), 0, a)
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
