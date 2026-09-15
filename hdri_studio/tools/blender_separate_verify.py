"""Verifica fisica delle luci separate in Cycles: la stessa luce nell'HDRI e come piano emissivo
(creato dall'add-on dal messaggio dell'app) devono illuminare ugualmente un piano diffuso al centro.

Uso:  Godot --path hdri_studio -s res://tools/separate_verify_export.gd
      Blender -b --python hdri_studio/tools/blender_separate_verify.py
"""
import json
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out")
sys.path.insert(0, os.path.join(HERE, "..", "plugins", "blender"))
sys.path.insert(0, HERE)
import hdri_studio_link as hs  # noqa: E402
import blender_verify as bv    # noqa: E402  (riusa scena, world, materiali, render)

bv.OUT = os.path.abspath(OUT)
bv.TMP = os.path.join(bv.OUT, "_blender")
os.makedirs(bv.TMP, exist_ok=True)


def render_case(world_file, with_plane):
    sc = bv.reset_scene()
    sc.cycles.samples = 512
    bv.set_world(bv.load_img(world_file))
    if with_plane:
        hs.register()
        msg = json.load(open(os.path.join(bv.OUT, "sepv_message.json")))
        hs.sync_separate_lights(msg)
        bpy.context.view_layer.update()
    # piano diffuso al centro rivolto alla luce (az 0 → +Z interno → +X Blender)
    bpy.ops.mesh.primitive_plane_add(size=0.05)
    p = bpy.context.active_object
    p.rotation_euler = Vector((1, 0, 0)).to_track_quat("Z", "Y").to_euler()
    p.data.materials.append(bv.white_diffuse())
    bv.add_camera((0.5, 0, 0), (-1, 0, 0), ortho=True)
    c = bv.render_center("sepv_plane" if with_plane else "sepv_hdri")
    if with_plane:
        hs.unregister()
    return float(c[0])


a = render_case("sepv_hdri.exr", False)
b = render_case("sepv_black.exr", True)
ratio = b / a if a > 0 else 0.0
print("[sepv] luce nell'HDRI → %.4f · piano emissivo → %.4f · rapporto %.3f (atteso ~1, E/π teorico 0.5632)" % (a, b, ratio), flush=True)
ok = abs(ratio - 1.0) < 0.03
print("[sepv] %s" % ("TUTTO OK" if ok else "FALLITO"), flush=True)
sys.exit(0 if ok else 1)
