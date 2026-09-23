"""Misura l'orientamento dell'HDRI in Houdini: carica out/calibration.exr in un envlight e renderizza
con Karma sei inquadrature strette lungo gli assi del mondo + una larga sul centro dell'immagine.
Dai dischi colorati (+X rosso, −X rosso scuro, +Y verde, −Y verde scuro, +Z blu = centro immagine,
−Z blu scuro) e dal punto bianco (az +25°, el +12°) ricava la corrispondenza degli assi e se
l'immagine risulta specchiata, cioè che cosa deve fare il preset "Houdini" di HdriExport.TARGETS.

Uso:  hython hdri_studio/tools/houdini_calibrate.py [cartella_di_lavoro]
"""
import os
import sys

import hou
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
EXR = os.path.join(HERE, "..", "out", "calibration.exr")
# direzione di vista (mondo Houdini) → rotazione della camera, che di suo guarda verso −Z
VIEWS = {
    "+X": (0.0, -90.0, 0.0),
    "-X": (0.0, 90.0, 0.0),
    "+Y": (90.0, 0.0, 0.0),
    "-Y": (-90.0, 0.0, 0.0),
    "+Z": (0.0, 180.0, 0.0),
    "-Z": (0.0, 0.0, 0.0),
}
# colore del disco → asse nella convenzione interna dell'app (Y in alto, centro immagine +Z)
MARKERS = {
    (255, 0, 0): "+X", (64, 0, 0): "-X",
    (0, 255, 0): "+Y", (0, 64, 0): "-Y",
    (0, 0, 255): "+Z", (0, 0, 64): "-Z",
}


def marker(rgb):
    """Il marker più vicino al colore letto, o None se è sfondo."""
    best, dist = None, 1e9
    for c, axis in MARKERS.items():
        d = sum((a - b) ** 2 for a, b in zip(c, rgb))
        if d < dist:
            best, dist = axis, d
    return best if dist < 3 * 40 ** 2 else None


def build(out_dir):
    hou.hipFile.clear(suppress_save_prompt=True)
    obj = hou.node("/obj")
    env = obj.createNode("envlight", "hs_calib_env")
    env.parm("env_map").set(os.path.abspath(EXR))
    env.parm("light_contribprimary").set(1)  # senza questo il dome non si vede dalla camera
    cam = obj.createNode("cam", "hs_calib_cam")
    cam.parmTuple("t").set((0, 0, 0))
    rop = hou.node("/out").createNode("karma", "hs_calib_karma")
    rop.parm("camera").set(cam.path())
    rop.parm("engine").set("cpu")
    rop.parm("override_camerares").set(1)
    os.makedirs(out_dir, exist_ok=True)
    return cam, rop


def shot(cam, rop, out_dir, name, rot, res, focal):
    cam.parm("focal").set(focal)
    cam.parm("aperture").set(41.4)
    cam.parmTuple("r").set(rot)
    rop.parm("resolutionx").set(res)
    rop.parm("resolutiony").set(res)
    path = os.path.join(out_dir, "houdini_calib_%s.png" % name)
    rop.parm("picture").set(path)
    rop.render(verbose=False)
    return Image.open(path).convert("RGB")


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "out")
    cam, rop = build(out_dir)

    print("[houdini] assi (dove guarda la camera → marker dell'app):")
    axes = {}
    for name, rot in VIEWS.items():
        im = shot(cam, rop, out_dir, name.replace("+", "p").replace("-", "m"), rot, 48, 200.0)
        rgb = im.getpixel((im.size[0] // 2, im.size[1] // 2))
        axes[name] = marker(rgb)
        print("[houdini]   mondo %s  →  %s  (rgb %s)" % (name, axes[name] or "?", rgb))

    # inquadratura larga sul centro dell'immagine: dove finisce il punto bianco (az +25, el +12)
    center_view = next((v for v, a in axes.items() if a == "+Z"), "-Z")
    im = shot(cam, rop, out_dir, "dot", VIEWS[center_view], 160, 24.0)
    px = im.load()
    w, h = im.size
    best, bxy = -1, (0, 0)
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            lum = r + g + b
            if r > 200 and g > 200 and b > 200 and lum > best:
                best, bxy = lum, (x, y)
    side = "destra" if bxy[0] > w / 2 else "sinistra"
    vert = "alto" if bxy[1] < h / 2 else "basso"
    print("[houdini] punto bianco (az +25, el +12) a %s e in %s del centro %s" % (side, vert, bxy))
    print("[houdini] preset: flip=%s, shift=0, mirror_x=false" % ("true" if side == "sinistra" else "false"))
    print("[houdini] (il preview dell'app lo mostra a destra: se qui è a sinistra serve il flip)")


if __name__ == "__main__":
    main()
