"""HDRI Studio Link — plugin per Houdini.

Si collega all'app HDRI Studio (TCP 127.0.0.1:47820, JSON-lines, lo stesso protocollo dei plugin
C4D e Blender):
- "hdri_updated": svuota la cache delle texture e ricarica i nodi che usano quel file (di solito
  l'env_map di un Environment Light); se nessuno lo usa, lo dice in console e il comando
  "Create HDRI environment" della shelf crea l'envlight al volo. Fallback sulla data di modifica
  ogni secondo quando l'app non è collegata.
- "separate_lights": crea/aggiorna area light (grid) con la texture della luce, dentro il subnet
  "HDRI_Studio_Lights", figlie del null "HDRI_Studio_Center": stessa direzione della luce,
  distanza D, dimensione fisica. Intensità 1 senza normalizzazione dell'area = radianza del pixel,
  come il piano emissivo in Blender.

Coordinate: Houdini è Y-up come la convenzione interna dell'app, ma il centro dell'immagine cade
su −Z e l'asse +X interno su −X (misurato con tools/houdini_calibrate.py): una rotazione di 180°
attorno a Y, quindi interno (x, y, z) → Houdini (−x, y, −z).

Il LightPaint non c'è: per ora il link è HDRI + luci separate.

Installazione: copia `HDRIStudio.json` in $HOUDINI_USER_PREF_DIR/packages/ e correggi il percorso
di questa cartella. Il link parte da solo (scripts/123.py e 456.py).
"""
import os
import time

import hou

try:
    from . import link_core
except ImportError:  # importato come modulo semplice (test headless)
    import link_core

PLUGIN_VERSION = "0.1"
EXTS = (".exr", ".hdr", ".rat")
MTIME_SCAN_S = 1.0
LIGHTS_SUBNET = "HDRI_Studio_Lights"
CENTER = "HDRI_Studio_Center"
LIGHT_PREFIX = "HS_"
ENV_NAME = "HDRI_Studio_Environment"

LINK = link_core.LinkClient(hello={"type": "hello", "host": "houdini", "version": hou.applicationVersionString()})
WATCH = link_core.MtimeWatcher()
_state = {"last_scan": 0.0, "was_connected": False, "last_msg": "", "running": False, "visible_camera": True}


# --- coordinate ----------------------------------------------------------------------------------

def to_houdini(v):
    """Vettore interno (Y-up, centro immagine +Z) → Houdini: 180° attorno a Y."""
    return hou.Vector3(-float(v[0]), float(v[1]), -float(v[2]))


# --- reload --------------------------------------------------------------------------------------

def _file_parms(node):
    for p in node.parms():
        t = p.parmTemplate()
        if isinstance(t, hou.StringParmTemplate) and t.stringType() == hou.stringParmType.FileReference:
            yield p


def _all_nodes():
    for root in ("/obj", "/mat", "/shop", "/stage", "/img"):
        n = hou.node(root)
        if n is not None:
            yield from n.allSubChildren(top_down=True, recurse_in_locked_nodes=False)


def _clear_texture_cache():
    for cmd in ("texcache -c", "texcache -r"):
        try:
            hou.hscript(cmd)
        except hou.Error:
            pass


def nodes_using(path):
    """Parametri file che puntano a `path` (stesso file, non stessa stringa)."""
    found = []
    for node in _all_nodes():
        try:
            for p in _file_parms(node):
                value = p.evalAsString()
                if value and link_core.same_file(value, path):
                    found.append(p)
        except hou.Error:
            continue
    return found


def reload_file(path):
    """Ricarica i nodi che usano `path`. Restituisce quanti parametri ha toccato."""
    parms = nodes_using(path)
    _clear_texture_cache()
    for p in parms:
        try:  # rimettere lo stesso valore non sporca il nodo: passa da vuoto
            value = p.evalAsString()
            p.set("")
            p.set(value)
        except hou.Error:
            pass
    _update_viewport()
    return len(parms)


def reload_all():
    """Ricarica ogni parametro file che punta a un EXR/HDR esistente."""
    _clear_texture_cache()
    n = 0
    for node in _all_nodes():
        try:
            for p in _file_parms(node):
                value = p.evalAsString()
                if value.lower().endswith(EXTS) and os.path.exists(value):
                    p.set("")
                    p.set(value)
                    n += 1
        except hou.Error:
            continue
    _update_viewport()
    print("[hdri-studio] %d file parameters reloaded" % n)
    return n


def _update_viewport():
    if hou.isUIAvailable():
        try:
            hou.ui.triggerUpdate()
        except (hou.Error, AttributeError):
            pass


# --- ambiente HDRI -------------------------------------------------------------------------------

def create_environment(path=""):
    """Crea (o aggiorna) l'Environment Light con l'EXR del live link. Restituisce il nodo."""
    path = path or _state.get("last_path", "")
    env = hou.node("/obj/" + ENV_NAME)
    if env is None:
        env = hou.node("/obj").createNode("envlight", ENV_NAME)
        env.moveToGoodPosition()
    if path:
        env.parm("env_map").set(path)
    # senza questo il dome illumina ma non si vede dalla camera (default di Houdini)
    env.parm("light_contribprimary").set(1)
    print("[hdri-studio] environment %s → %s" % (env.path(), path or "(no file yet)"))
    return env


# --- luci separate -------------------------------------------------------------------------------

def _lights_subnet():
    sub = hou.node("/obj/" + LIGHTS_SUBNET)
    if sub is None:
        sub = hou.node("/obj").createNode("subnet", LIGHTS_SUBNET)
        sub.moveToGoodPosition()
    return sub


def _center(sub):
    null = sub.node(CENTER)
    if null is None:
        null = sub.createNode("null", CENTER)
        null.moveToGoodPosition()
    return null


def sync_separate_lights(msg):
    """Crea/aggiorna/rimuove le area light delle luci separate. Restituisce quante ne ha toccate."""
    entries = msg.get("lights", [])
    scale = float(msg.get("unit_scale", 0.01))  # l'app lavora in cm, Houdini in metri
    sub = _lights_subnet()
    center = _center(sub)
    existing = {n.name(): n for n in sub.children() if n.name().startswith(LIGHT_PREFIX)}
    wanted = set()
    touched = 0
    for e in entries:
        name = LIGHT_PREFIX + _safe(e["name"])
        wanted.add(name)
        light = existing.get(name)
        if light is None:
            light = sub.createNode("hlight::2.0", name)
            light.moveToGoodPosition()
        light.setInput(0, center)
        light.parm("light_type").set("grid")
        w, h = float(e["size"][0]) * scale, float(e["size"][1]) * scale
        light.parm("areasize1").set(w)
        light.parm("areasize2").set(h)
        light.parm("light_texture").set(e["path"])
        light.parm("light_intensity").set(1.0)
        light.parm("light_exposure").set(0.0)
        light.parmTuple("light_color").set((1.0, 1.0, 1.0))
        # niente normalizzazione: intensità 1 = radianza del pixel, come il piano emissivo in Blender
        light.parm("normalizearea").set(0)
        light.parm("light_contribprimary").set(
            1 if (bool(e.get("visible", True)) and _state["visible_camera"]) else 0)
        light.setWorldTransform(_transform(e, scale))
        touched += 1
    for name, node in existing.items():
        if name not in wanted:
            node.destroy()
            touched += 1
    _update_viewport()
    return touched


def _transform(entry, scale):
    """La luce sta a distanza D lungo F e illumina il centro: le grid light di Houdini emettono
    lungo il proprio −Z, quindi Z locale = +F. La base (−R, U, F) è destrorsa come (R, U, −F)."""
    F, R, U = (to_houdini(entry["forward"]), to_houdini(entry["right"]), to_houdini(entry["up"]))
    d = float(entry["distance"]) * scale
    x, y, z = -R, U, F
    t = F * d
    return hou.Matrix4((
        (x[0], x[1], x[2], 0.0),
        (y[0], y[1], y[2], 0.0),
        (z[0], z[1], z[2], 0.0),
        (t[0], t[1], t[2], 1.0)))


def _safe(name):
    return "".join(c if (c.isalnum() or c == "_") else "_" for c in name.strip())


def set_visible_camera(on):
    """Le luci separate si vedono dalla camera (riflessi e illuminazione restano comunque)."""
    _state["visible_camera"] = bool(on)
    sub = hou.node("/obj/" + LIGHTS_SUBNET)
    if sub is not None:
        for n in sub.children():
            if n.name().startswith(LIGHT_PREFIX):
                n.parm("light_contribprimary").set(1 if on else 0)
    _update_viewport()


# --- timer ---------------------------------------------------------------------------------------

def tick():
    """Un giro di polling: chiamato dall'event loop di Houdini (o a mano nei test headless)."""
    try:
        for msg in LINK.poll():
            t = msg.get("type")
            if t == "hdri_updated":
                path = msg.get("path", "")
                _state["last_path"] = path
                n = reload_file(path)
                WATCH.touch(path)
                _state["last_msg"] = "%s → %d nodes" % (os.path.basename(path), n)
                if n == 0:
                    print("[hdri-studio] %s: no node uses this file yet "
                          "(shelf: 'Create HDRI environment')" % os.path.basename(path))
                else:
                    print("[hdri-studio] %s" % _state["last_msg"])
            elif t == "separate_lights":
                n = sync_separate_lights(msg)
                for e in msg.get("lights", []):
                    WATCH.touch(e.get("path", ""))
                if n:
                    _state["last_msg"] = "separate lights: %d" % n
                    print("[hdri-studio] %s" % _state["last_msg"])
        if LINK.connected != _state["was_connected"]:
            _state["was_connected"] = LINK.connected
            print("[hdri-studio] %s" % ("connected to the app" if LINK.connected
                                        else "app unreachable, using file timestamps"))
        now = time.time()
        if now - _state["last_scan"] >= MTIME_SCAN_S:
            _state["last_scan"] = now
            paths = []
            for node in _all_nodes():
                try:
                    for p in _file_parms(node):
                        v = p.evalAsString()
                        if v.lower().endswith(EXTS):
                            paths.append(v)
                except hou.Error:
                    continue
            for p in WATCH.changed(paths):
                n = reload_file(p)
                _state["last_msg"] = "%s changed → %d nodes" % (os.path.basename(p), n)
                print("[hdri-studio] %s" % _state["last_msg"])
    except Exception as e:  # mai far cadere il callback dell'event loop
        print("[hdri-studio] error: %r" % e)


def start():
    """Attacca il polling all'event loop di Houdini (solo con la UI: in hython si chiama tick())."""
    if _state["running"]:
        return
    if hou.isUIAvailable():
        hou.ui.addEventLoopCallback(tick)
    _state["running"] = True
    print("[hdri-studio] plugin %s loaded from %s (port %d)"
          % (PLUGIN_VERSION, os.path.dirname(__file__), link_core.DEFAULT_PORT))


def stop():
    if not _state["running"]:
        return
    if hou.isUIAvailable():
        try:
            hou.ui.removeEventLoopCallback(tick)
        except (hou.Error, ValueError):
            pass
    LINK.close()
    _state["running"] = False
    print("[hdri-studio] link stopped")


def toggle():
    stop() if _state["running"] else start()
    return _state["running"]
