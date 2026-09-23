"""Lato Houdini del test del live link: importa il plugin, si collega all'app (blender_link_host.gd),
riceve hdri_updated e separate_lights e verifica l'area light creata e il reload dell'environment.

Uso:  Godot --path hdri_studio -s res://tools/blender_link_host.gd -- --target Houdini
      hython hdri_studio/tools/houdini_link_test.py
"""
import os
import sys
import time

import hou

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "plugins", "houdini", "scripts", "python"))
import hdri_studio_link as hs  # noqa: E402

TIMEOUT_S = 30.0
ok = True


def log(*a):
    print("[houdini-link]", *a, flush=True)


def check(cond, label):
    global ok
    log(("✓ " if cond else "✗ ") + label)
    ok = ok and bool(cond)
    return cond


def near(a, b, eps=1e-3):
    return abs(float(a) - float(b)) <= eps


def main():
    hou.hipFile.clear(suppress_save_prompt=True)
    hs.start()
    t0 = time.time()
    seen = {"hdri": False, "lights": False}
    sub = None
    while time.time() - t0 < TIMEOUT_S and not all(seen.values()):
        hs.tick()
        if hs._state.get("last_path"):
            seen["hdri"] = True
        sub = hou.node("/obj/" + hs.LIGHTS_SUBNET)
        if sub is not None and [n for n in sub.children() if n.name().startswith(hs.LIGHT_PREFIX)]:
            seen["lights"] = True
        time.sleep(0.2)

    check(hs.LINK.connected, "collegato all'app")
    check(seen["hdri"], "ricevuto hdri_updated (%s)" % os.path.basename(hs._state.get("last_path", "")))
    if not check(seen["lights"], "area light creata dal messaggio separate_lights"):
        return
    lights = [n for n in sub.children() if n.name().startswith(hs.LIGHT_PREFIX)]
    check(len(lights) == 1, "una sola luce separata (%d)" % len(lights))
    light = lights[0]

    check(light.parm("light_type").evalAsString() == "grid", "area light di tipo grid")
    check(light.parm("normalizearea").eval() == 0, "niente normalizzazione dell'area (radianza)")
    check(near(light.parm("light_intensity").eval(), 1.0), "intensità 1")
    tex = light.parm("light_texture").evalAsString()
    check(tex.lower().endswith(".exr") and os.path.exists(tex), "texture EXR della luce (%s)" % os.path.basename(tex))

    # host: az 0, el 0, 150 cm, 40°×20° → interno +Z, in Houdini −Z a 1,5 m
    m = light.worldTransform()
    pos = hou.Vector3(m.at(3, 0), m.at(3, 1), m.at(3, 2))
    check(near(pos[0], 0.0) and near(pos[1], 0.0) and near(pos[2], -1.5, 1e-2),
          "luce a 1,5 m su −Z di Houdini (az 0 → centro immagine) %s" % (tuple(round(c, 3) for c in pos),))
    # le grid light emettono lungo il proprio −Z: deve puntare al centro
    zl = hou.Vector3(m.at(2, 0), m.at(2, 1), m.at(2, 2))
    to_center = hou.Vector3(-pos[0], -pos[1], -pos[2]).normalized()
    check(near((-zl).dot(to_center), 1.0, 1e-3), "la luce emette verso il centro (%.4f)" % (-zl).dot(to_center))
    check(near(m.determinant(), 1.0, 1e-3), "base destrorsa, nessuno specchio (det %.4f)" % m.determinant())
    w = 2.0 * 1.5 * (3.141592653589793 / 180.0 * 20.0)  # 40° di larghezza a 1,5 m, approx. planare
    check(abs(light.parm("areasize1").eval() - 1.092) < 0.02,
          "larghezza fisica %.3f m (attesa ~1.092, tan: %.3f)" % (light.parm("areasize1").eval(), w))

    # environment: nessun nodo usava l'EXR, quindi lo creiamo e il reload deve trovarlo
    path = hs._state["last_path"]
    env = hs.create_environment(path)
    check(env.parm("env_map").evalAsString() == path, "environment light con l'EXR del live link")
    check(env.parm("light_contribprimary").eval() == 1, "dome visibile dalla camera")
    check(hs.reload_file(path) >= 1, "il reload ora trova il nodo che usa il file")
    hs.set_visible_camera(False)
    check(light.parm("light_contribprimary").eval() == 0, "luci separate nascoste alla camera")


if __name__ == "__main__":
    main()
    hs.stop()
    log("TUTTO OK" if ok else "FALLITO")
    sys.exit(0 if ok else 1)
