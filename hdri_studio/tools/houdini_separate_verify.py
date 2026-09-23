"""Verifica fisica delle luci separate in Karma: la stessa luce dentro l'HDRI e come area light
(creata dal plugin dal messaggio dell'app) devono illuminare allo stesso modo un piano diffuso al
centro. Controlla anche dove finisce la texture della luce vista dal centro (u a destra, v in alto,
come la mappa dell'app).

Uso:  Godot --path hdri_studio -s res://tools/separate_verify_export.gd
      hython hdri_studio/tools/houdini_separate_verify.py
"""
import json
import os
import sys

import hou
import OpenImageIO as oiio

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "out"))
TMP = os.path.join(OUT, "_houdini")
sys.path.insert(0, os.path.join(HERE, "..", "plugins", "houdini", "scripts", "python"))
import hdri_studio_link as hs  # noqa: E402

RES = 48
ok = True


def log(*a):
    print("[hsepv]", *a, flush=True)


def check(cond, label):
    global ok
    log(("✓ " if cond else "✗ ") + label)
    ok = ok and bool(cond)
    return cond


def scene(env_file):
    """Scena minima: env light con `env_file` e un piano diffuso al centro rivolto alla luce."""
    hou.hipFile.clear(suppress_save_prompt=True)
    obj = hou.node("/obj")
    env = obj.createNode("envlight", "env")
    env.parm("env_map").set(os.path.join(OUT, env_file))
    env.parm("light_contribprimary").set(0)  # solo illuminazione: lo sfondo non deve entrare
    geo = obj.createNode("geo", "target")
    grid = geo.createNode("grid")
    grid.parm("orient").set("xy")           # normale +Z
    grid.parmTuple("size").set((0.05, 0.05))
    geo.parmTuple("r").set((0, 180, 0))      # ...ruotata verso la luce (az 0 → −Z di Houdini)
    cam = obj.createNode("cam", "cam")
    cam.parmTuple("t").set((0, 0, -0.5))
    cam.parmTuple("r").set((0, 180, 0))      # guarda il piano dal lato della luce
    cam.parm("projection").set("ortho")
    cam.parm("orthowidth").set(0.02)
    rop = hou.node("/out").createNode("karma", "karma")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("override_camerares").set(1)
    rop.parm("resolutionx").set(RES)
    rop.parm("resolutiony").set(RES)
    rop.parm("samplesperpixel").set(256)
    return rop


def render(rop, name):
    os.makedirs(TMP, exist_ok=True)
    path = os.path.join(TMP, name + ".exr")
    rop.parm("picture").set(path)
    rop.render(verbose=False)
    buf = oiio.ImageBuf(path)
    px = buf.getpixel(RES // 2, RES // 2)
    return float(px[0])


def texture_probe():
    """Texture asimmetrica sulla luce, vista dal centro: dove finisce il quadrante luminoso."""
    import numpy as np
    from PIL import Image
    img = np.zeros((64, 64, 3), np.uint8)
    img[4:28, 4:28] = 255          # quadrante in alto a sinistra dell'immagine (v alto, u basso)
    path = os.path.join(TMP, "probe_tex.png")
    Image.fromarray(img).save(path)
    return path


def main():
    msg_path = os.path.join(OUT, "sepv_message.json")
    if not os.path.exists(msg_path):
        log("manca %s: lancia prima separate_verify_export.gd" % msg_path)
        sys.exit(2)
    msg = json.load(open(msg_path))

    rop = scene("sepv_hdri.exr")
    a = render(rop, "sepv_hdri")
    rop = scene("sepv_black.exr")
    hs.sync_separate_lights(msg)
    b = render(rop, "sepv_area")
    ratio = b / a if a > 0 else 0.0
    log("luce nell'HDRI → %.4f · area light → %.4f · rapporto %.3f" % (a, b, ratio))
    check(abs(ratio - 1.0) < 0.03, "la luce separata illumina come nell'HDRI (rapporto %.3f)" % ratio)

    # orientamento della texture: la luce riempie l'inquadratura, vista dal centro
    rop = scene("sepv_black.exr")
    hs.sync_separate_lights(msg)
    light = hou.node("/obj/%s" % hs.LIGHTS_SUBNET).children()[-1]
    light.parm("light_texture").set(texture_probe())
    light.parm("light_contribprimary").set(1)
    cam = hou.node("/obj/cam")
    cam.parmTuple("t").set((0, 0, 0))
    cam.parmTuple("r").set((0, 0, 0))   # dal centro verso la luce (−Z di Houdini)
    cam.parm("projection").set("perspective")
    cam.parm("focal").set(50.0)
    cam.parm("aperture").set(41.4)
    hou.node("/obj/target").parm("tdisplay").set(1)
    hou.node("/obj/target").parm("display").set(0)
    rop.parm("resolutionx").set(96)
    rop.parm("resolutiony").set(96)
    path = os.path.join(TMP, "probe_look.exr")
    rop.parm("picture").set(path)
    rop.render(verbose=False)
    buf = oiio.ImageBuf(path)
    w = h = 96
    best, bxy = -1.0, (0, 0)
    for y in range(h):
        for x in range(w):
            v = float(buf.getpixel(x, y)[0])
            if v > best:
                best, bxy = v, (x, y)
    side = "destra" if bxy[0] > w / 2 else "sinistra"
    vert = "alto" if bxy[1] < h / 2 else "basso"
    log("quadrante luminoso della texture: %s, %s %s (valore %.2f)" % (side, vert, bxy, best))
    check(best > 0.01, "la luce con texture si vede dal centro")
    check(side == "sinistra" and vert == "alto",
          "texture come la mappa dell'app (quadrante in alto a sinistra), non specchiata")


if __name__ == "__main__":
    main()
    log("TUTTO OK" if ok else "FALLITO")
    sys.exit(0 if ok else 1)
