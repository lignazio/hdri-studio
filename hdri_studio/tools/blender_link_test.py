"""Lato Blender del test del live link: registra l'add-on, si collega all'app (blender_link_host.gd),
riceve hdri_updated e separate_lights, verifica il piano emissivo creato e manda un lightpaint.

Uso:  Blender -b --python hdri_studio/tools/blender_link_test.py
"""
import os
import sys
import time

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "plugins", "blender"))
import hdri_studio_link as hs  # noqa: E402


def log(*a):
    print("[blender-link]", *a, flush=True)


def check(cond, label):
    log(("✓ " if cond else "✗ ") + label)
    return cond


bpy.ops.wm.read_factory_settings(use_empty=True)
hs.register()
ok = True
sent_paint = False
t_end = time.time() + 15.0
while time.time() < t_end:
    hs.tick()
    if hs.LINK.connected and not sent_paint and hs._state["last_msg"]:
        # punto +X di Blender con normale +X, vista lungo -X → riflesso +X (Blender) = +Z interno → az 0, el 0
        hs.LINK.send({"type": "lightpaint", "host": "blender", "point": hs.to_internal(Vector((1, 0, 0))),
                      "normal": hs.to_internal(Vector((1, 0, 0))), "view": hs.to_internal(Vector((-1, 0, 0)))})
        sent_paint = True
        log("inviato lightpaint (atteso nell'app: az 0, el 0)")
    time.sleep(0.05)

ok = check(hs.LINK.connected or sent_paint, "collegato all'app") and ok
col = bpy.data.collections.get(hs.COLLECTION)
planes = [o for o in col.objects if o.name.startswith(hs.LIGHT_PREFIX)] if col else []
ok = check(len(planes) == 1, "1 piano emissivo creato (%d)" % len(planes)) and ok
if planes:
    bpy.context.view_layer.update()  # in background matrix_world si aggiorna solo con il depsgraph
    p = planes[0]
    loc = p.matrix_world.translation
    ok = check((loc - Vector((1.5, 0, 0))).length < 1e-3, "piano a 1.5 m lungo +X di Blender (az 0 → +Z interno → +X Blender): %s" % (tuple(round(c, 3) for c in loc),)) and ok
    dims = p.dimensions
    import math
    w_exp = 2 * 1.5 * math.tan(math.radians(20))
    ok = check(abs(dims.x - w_exp) < 1e-3, "larghezza fisica %.3f m (attesa %.3f)" % (dims.x, w_exp)) and ok
    z_axis = p.matrix_world.to_3x3() @ Vector((0, 0, 1))
    ok = check(z_axis.dot(Vector((-1, 0, 0))) > 0.999, "la faccia +Z del piano guarda il centro") and ok
    mat = p.data.materials[0] if p.data.materials else None
    tex = mat.node_tree.nodes.get("HS_Texture") if mat else None
    ok = check(tex is not None and tex.image is not None and tex.image.filepath.lower().endswith(".exr"), "materiale emissivo con l'EXR della luce") and ok
    if tex and tex.image:
        tex.image.reload()
        px = tex.image.pixels[:]
        w, h = tex.image.size
        c = px[((h // 2) * w + w // 2) * 4]
        ok = check(c > 0.5, "l'EXR planare ha radianza al centro (%.2f)" % c) and ok
log("TUTTO OK" if ok else "FALLITO")
hs.unregister()
sys.exit(0 if ok else 1)
