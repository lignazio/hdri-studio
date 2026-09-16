"""HDRI Studio Link — plugin per Cinema 4D (Octane e nativo).

Si collega all'app HDRI Studio (TCP locale, porta 47820). Quando l'app esporta un nuovo EXR manda
"hdri_updated" con il percorso: il plugin trova gli ImageTexture (o qualsiasi nodo) che puntano a
quel file e preme il loro pulsante Reload — in Octane è l'unico modo per far rileggere la texture.
Se l'app non è collegata, controlla ogni secondo la data di modifica dei file immagine usati nella
scena e ricarica quelli cambiati.

LightPaint: il tool "HDRI Studio LightPaint" (menu Extensions, o cercalo con Shift+C). Con il tool
attivo, click o trascina sul modello nel viewport: il plugin fa il picking (GeRayCollider sulle
mesh, cache dei generatori comprese) e manda punto, normale e direzione di vista all'app, che sposta
la luce selezionata dove serve per riflettersi in quel punto.

Luci separate (Fase 4): il messaggio "separate_lights" elenca le luci del rig marcate come separate,
con direzione, distanza, dimensione fisica e il loro EXR planare. Il plugin le ricrea sotto un null
"HDRI Studio Lights". Se nella scena c'è una luce modello "HS_TEMPLATE" la clona; altrimenti crea da
solo un'Octane Area Light di default (C4D Area Light + tag Octane Light scoperto per nome, ImageTexture
nello slot texture, Surface brightness attivo, Power 1) e ci carica l'EXR. Il null si può spostare sul
soggetto: le luci lo seguono. "HDRI Studio: diagnostica Octane" stampa i plugin e i parametri trovati.

Installazione: Edit > Preferences > Plugins > aggiungi la cartella `plugins/c4d` (quella che contiene
`hdri_studio_link/`), riavvia Cinema 4D. Nel menu Extensions compare "HDRI Studio: ricarica texture".
"""
import math
import os
import sys
import time

import c4d

sys.path.insert(0, os.path.dirname(__file__))
import link_core  # noqa: E402

# ID unici del plugin: valori alti fuori dagli intervalli usati dai moduli di Cinema 4D
# (1065932 collideva con C4d_objects). Per una distribuzione pubblica andrebbero richiesti su
# https://developers.maxon.net/forum/pid
PLUGIN_VERSION = "1.0 (Octane per ID)"
PLUGIN_ID_LINK = 1099780031
PLUGIN_ID_RELOAD = 1099780032
PLUGIN_ID_PAINT = 1099780033
PLUGIN_ID_DIAG = 1099780034
PLUGIN_ID_ENV = 1099780035
EXTS = (".exr", ".hdr")
TIMER_MS = 200
MTIME_SCAN_S = 1.0


# --- ricerca dei nodi con immagini ----------------------------------------------------------------

def _walk_shaders(sh, out):
    while sh:
        out.append(sh)
        _walk_shaders(sh.GetDown(), out)
        sh = sh.GetNext()


def _walk_objects(op, out):
    while op:
        out.append(op)
        _walk_objects(op.GetDown(), out)
        op = op.GetNext()


def all_nodes(doc):
    nodes = []
    mat = doc.GetFirstMaterial()
    while mat:
        nodes.append(mat)
        _walk_shaders(mat.GetFirstShader(), nodes)
        mat = mat.GetNext()
    objs = []
    _walk_objects(doc.GetFirstObject(), objs)
    for op in objs:
        nodes.append(op)
        _walk_shaders(op.GetFirstShader(), nodes)
        tag = op.GetFirstTag()
        while tag:
            nodes.append(tag)
            _walk_shaders(tag.GetFirstShader(), nodes)
            tag = tag.GetNext()
    return nodes


def image_paths(node):
    bc = node.GetDataInstance()
    found = []
    if bc is None:
        return found
    for pid, val in bc:
        if isinstance(val, str) and val.lower().endswith(EXTS):
            found.append(val)
        elif isinstance(val, c4d.BaseContainer):
            for _pid2, val2 in val:
                if isinstance(val2, str) and val2.lower().endswith(EXTS):
                    found.append(val2)
    return found


def press_reload(node):
    """Preme tutti i pulsanti 'Reload' della descrizione del nodo. Restituisce quanti."""
    n = 0
    desc = node.GetDescription(c4d.DESCFLAGS_DESC_NONE)
    if desc is None:
        return 0
    for bc, paramid, _groupid in desc:
        try:
            if paramid[0].dtype != c4d.DTYPE_BUTTON:
                continue
            if "reload" not in bc.GetString(c4d.DESC_NAME).lower():
                continue
        except Exception:
            continue
        node.Message(c4d.MSG_DESCRIPTION_COMMAND, {"id": paramid})
        n += 1
    if n == 0:
        # nodi senza pulsante (bitmap shader nativo): basta segnarli sporchi
        node.SetDirty(c4d.DIRTYFLAGS_DATA)
        node.Message(c4d.MSG_UPDATE)
    return n


def reload_file(doc, path):
    """Ricarica tutti i nodi che usano `path`. Restituisce il numero di nodi toccati."""
    touched = 0
    for node in all_nodes(doc):
        if any(link_core.same_file(p, path) for p in image_paths(node)):
            press_reload(node)
            touched += 1
    if touched:
        c4d.EventAdd(c4d.EVENT_FORCEREDRAW)
    return touched


def reload_all(doc):
    touched = 0
    for node in all_nodes(doc):
        if image_paths(node):
            press_reload(node)
            touched += 1
    if touched:
        c4d.EventAdd(c4d.EVENT_FORCEREDRAW)
    return touched


# --- luci separate ---------------------------------------------------------------------------------

LIGHTS_NULL = "HDRI Studio Lights"
TEMPLATE_NAME = "HS_TEMPLATE"
LIGHT_PREFIX = "HS: "
# Verso di emissione della luce modello lungo il suo asse Z locale (+1 = la luce guarda il centro con
# la faccia +Z). L'app può invertirlo dal pannello Live link ("Inverti verso"): il messaggio porta
# face_sign, che moltiplica questo default.
LIGHT_EMITS_ALONG_Z = +1


def _find_by_name(op, name):
    while op:
        if op.GetName() == name:
            return op
        found = _find_by_name(op.GetDown(), name)
        if found is not None:
            return found
        op = op.GetNext()
    return None


def _children(op):
    out = []
    child = op.GetDown()
    while child:
        out.append(child)
        child = child.GetNext()
    return out


def _nodes_of(obj):
    """L'oggetto, i suoi tag e gli shader appesi a entrambi."""
    nodes = [obj]
    _walk_shaders(obj.GetFirstShader(), nodes)
    tag = obj.GetFirstTag()
    while tag:
        nodes.append(tag)
        _walk_shaders(tag.GetFirstShader(), nodes)
        tag = tag.GetNext()
    return nodes


def _set_image_path(obj, path):
    """Assegna `path` all'immagine della luce e preme Reload. Per l'Image Texture di Octane usa gli ID
    misurati (file, spazio colore Linear sRGB, Reload); per altri shader cerca un parametro che già
    contiene un .exr/.hdr o un parametro di tipo filename."""
    for node in _nodes_of(obj):
        if node.GetType() == OCTANE_IMAGE_TEXTURE_ID:
            node[OCT_IMG_FILE] = path
            node[OCT_IMG_COLOR_SPACE] = OCT_IMG_COLOR_SPACE_LINEAR_SRGB
            node.Message(c4d.MSG_DESCRIPTION_COMMAND, {"id": c4d.DescID(c4d.DescLevel(OCT_IMG_RELOAD))})
            return True
    for node in _nodes_of(obj):
        bc = node.GetDataInstance()
        if bc is None:
            continue
        for pid, val in bc:
            if isinstance(val, str) and val.lower().endswith(EXTS):
                bc.SetString(pid, path)
                press_reload(node)
                return True
            if isinstance(val, c4d.BaseContainer):
                for pid2, val2 in val:
                    if isinstance(val2, str) and val2.lower().endswith(EXTS):
                        val.SetString(pid2, path)
                        press_reload(node)
                        return True
    for node in _nodes_of(obj):
        if not node.IsInstanceOf(c4d.Xbase):
            continue
        pid = _param_by_name(node, [], dtype=c4d.DTYPE_FILENAME) or _param_by_name(node, ["file"], exclude=("filter",))
        if pid is not None:
            node[pid] = path
            _set_linear_colorspace(node)
            press_reload(node)
            return True
    return False


def _set_linear_colorspace(node):
    """Spazio colore lineare per l'EXR: legge le voci del menu e sceglie quella con 'linear'
    (preferendo 'srgb'); se c'è un parametro Gamma lo porta a 1."""
    desc = node.GetDescription(c4d.DESCFLAGS_DESC_NONE)
    if desc is None:
        return
    for bc, pid, _g in desc:
        try:
            name = bc.GetString(c4d.DESC_NAME).lower()
            if pid[0].dtype == c4d.DTYPE_LONG and ("color" in name and "space" in name or "colorspace" in name):
                cycle = bc.GetContainer(c4d.DESC_CYCLE)
                best = None
                for cid, label in cycle:
                    lab = str(label).lower()
                    if "linear" in lab and (best is None or "srgb" in lab):
                        best = cid
                if best is not None:
                    node[pid] = best
            elif pid[0].dtype == c4d.DTYPE_REAL and name.strip() == "gamma":
                node[pid] = 1.0
        except Exception:
            pass


# --- luce di default (senza HS_TEMPLATE) --------------------------------------------------------------

# ID misurati su Octane per Cinema 4D 2026 (diagnostica del 16/09/2026); il nome esatto è il ripiego.
OCTANE_LIGHT_TAG_ID = 1029526      # tag "Octane Light"
OCTANE_IMAGE_TEXTURE_ID = 1029508  # shader "Image Texture"
# parametri del tag Octane Light (diagnostica del 16/09/2026)
OCT_LIGHT_POWER = 1151
OCT_LIGHT_TEXTURE = 1155
OCT_LIGHT_SURFACE_BRIGHTNESS = 1166
OCT_LIGHT_CAMERA_VISIBILITY = 1163
# parametri dello shader Image Texture (diagnostica del 16/09/2026)
OCT_IMG_FILE = 1100
OCT_IMG_RELOAD = 1127
OCT_IMG_COLOR_SPACE = 1118
OCT_IMG_COLOR_SPACE_LINEAR_SRGB = 2
# tag Octane Environment (diagnostica del 16/09/2026)
OCTANE_ENV_TAG_ID = 1029643
OCT_ENV_TEXTURE = 1150
OCT_ENV_POWER = 1151
OCT_ENV_IMPORTANCE_SAMPLING = 1153
OCT_ENV_TYPE = 1162
OCT_ENV_TYPE_PRIMARY = 0
ENV_SKY_NAME = "HDRI Studio Environment"
_state = {"last_env_path": ""}


def _plugin_exists(ptype, pid):
    return any(p.GetID() == pid for p in c4d.plugins.FilterPluginList(ptype, True))


def _find_plugin(ptype, exact_name, known_id=None):
    """ID del plugin: prima l'ID noto se è registrato, poi il nome esatto (senza spazi, minuscolo)."""
    if known_id is not None and _plugin_exists(ptype, known_id):
        return known_id
    want = exact_name.lower().replace(" ", "")
    for p in c4d.plugins.FilterPluginList(ptype, True):
        if p.GetName().lower().replace(" ", "") == want:
            return p.GetID()
    return None


def _param_by_name(node, words, dtype=None, exclude=()):
    """DescID del primo parametro della descrizione il cui nome contiene tutte le parole."""
    desc = node.GetDescription(c4d.DESCFLAGS_DESC_NONE)
    if desc is None:
        return None
    for bc, pid, _gid in desc:
        try:
            name = bc.GetString(c4d.DESC_NAME).lower()
            if not all(w in name for w in words) or any(x in name for x in exclude):
                continue
            if dtype is not None and pid[0].dtype != dtype:
                continue
            return pid
        except Exception:
            continue
    return None


def _create_default_light(doc, root):
    """Octane Area Light di default: C4D Area Light rettangolare + tag Octane Light (scoperto per nome)
    con un ImageTexture nello slot texture, Surface brightness attivo, Power 1. Se il plugin Octane non
    si trova, resta una luce area nativa. Restituisce (oggetto, nota per la console)."""
    light = c4d.BaseObject(c4d.Olight)
    light[c4d.LIGHT_TYPE] = c4d.LIGHT_TYPE_AREA
    light[c4d.LIGHT_AREADETAILS_SHAPE] = c4d.LIGHT_AREADETAILS_SHAPE_RECTANGLE
    light.InsertUnder(root)
    tag_id = _find_plugin(c4d.PLUGINTYPE_TAG, "Octane Light", OCTANE_LIGHT_TAG_ID)
    if tag_id is None:
        return light, "tag 'Octane Light' non trovato fra i plugin: luce area nativa senza texture"
    tag = light.MakeTag(tag_id)
    notes = []
    sh_id = _find_plugin(c4d.PLUGINTYPE_SHADER, "Image Texture", OCTANE_IMAGE_TEXTURE_ID)
    if sh_id is not None:
        sh = c4d.BaseShader(sh_id)
        tag.InsertShader(sh)
        tag[OCT_LIGHT_TEXTURE] = sh
    else:
        notes.append("shader Image Texture non trovato")
    tag[OCT_LIGHT_SURFACE_BRIGHTNESS] = True
    tag[OCT_LIGHT_POWER] = 1.0
    return light, ("Octane Area Light di default" + ("; " + "; ".join(notes) if notes else ""))


# --- ambiente HDRI di default -----------------------------------------------------------------------

def _has_environment_tag(doc):
    for node in all_nodes(doc):
        if node.IsInstanceOf(c4d.Tbase) and node.GetType() == OCTANE_ENV_TAG_ID:
            return True
    return False


def create_environment(doc, path):
    """Sky + tag Octane Environment + Image Texture con l'EXR del live link (Linear sRGB).
    Restituisce una nota per la console."""
    tag_id = _find_plugin(c4d.PLUGINTYPE_TAG, "Octane Environment", OCTANE_ENV_TAG_ID)
    if tag_id is None:
        return "tag 'Octane Environment' non trovato fra i plugin"
    sky = c4d.BaseObject(c4d.Osky)
    sky.SetName(ENV_SKY_NAME)
    doc.InsertObject(sky)
    tag = sky.MakeTag(tag_id)
    notes = []
    tag[OCT_ENV_TYPE] = OCT_ENV_TYPE_PRIMARY
    tag[OCT_ENV_POWER] = 1.0
    tag[OCT_ENV_IMPORTANCE_SAMPLING] = True
    sh_id = _find_plugin(c4d.PLUGINTYPE_SHADER, "Image Texture", OCTANE_IMAGE_TEXTURE_ID)
    if sh_id is not None:
        sh = c4d.BaseShader(sh_id)
        tag.InsertShader(sh)
        tag[OCT_ENV_TEXTURE] = sh
        sh[OCT_IMG_FILE] = path
        sh[OCT_IMG_COLOR_SPACE] = OCT_IMG_COLOR_SPACE_LINEAR_SRGB
    else:
        notes.append("shader Image Texture non trovato")
    c4d.EventAdd(c4d.EVENT_FORCEREDRAW)
    return "ambiente HDRI creato ('%s')" % ENV_SKY_NAME + ("; " + "; ".join(notes) if notes else "")


def octane_diagnostics(doc):
    """Stampa in console cosa il plugin trova di Octane: serve a fissare la luce di default se nasce male."""
    print("[hdri-studio] --- diagnostica Octane ---")
    for ptype, label in ((c4d.PLUGINTYPE_TAG, "tag"), (c4d.PLUGINTYPE_SHADER, "shader"), (c4d.PLUGINTYPE_OBJECT, "oggetto")):
        for p in c4d.plugins.FilterPluginList(ptype, True):
            if "octane" in p.GetName().lower() or "imagetexture" in p.GetName().lower().replace(" ", ""):
                print("[hdri-studio] %-8s %-40s id=%d" % (label, p.GetName(), p.GetID()))
    tag_id = _find_plugin(c4d.PLUGINTYPE_TAG, "Octane Light", OCTANE_LIGHT_TAG_ID)
    print("[hdri-studio] tag Octane Light usato: %s" % tag_id)
    if tag_id is not None:
        tmp = c4d.BaseObject(c4d.Olight)
        tag = tmp.MakeTag(tag_id)
        desc = tag.GetDescription(c4d.DESCFLAGS_DESC_NONE)
        if desc is not None:
            for bc, pid, _g in desc:
                try:
                    print("[hdri-studio]   param id=%-6d dtype=%-8d %s" % (pid[0].id, pid[0].dtype, bc.GetString(c4d.DESC_NAME)))
                except Exception:
                    pass
    env_id = _find_plugin(c4d.PLUGINTYPE_TAG, "Octane Environment", OCTANE_ENV_TAG_ID)
    print("[hdri-studio] tag Octane Environment usato: %s" % env_id)
    if env_id is not None:
        tmp2 = c4d.BaseObject(c4d.Osky)
        etag = tmp2.MakeTag(env_id)
        edesc = etag.GetDescription(c4d.DESCFLAGS_DESC_NONE)
        if edesc is not None:
            for bc, pid, _g in edesc:
                try:
                    line = "[hdri-studio]   env param id=%-6d dtype=%-8d %s" % (pid[0].id, pid[0].dtype, bc.GetString(c4d.DESC_NAME))
                    cycle = bc.GetContainer(c4d.DESC_CYCLE)
                    if cycle is not None and len(cycle) > 0:
                        line += "  {" + ", ".join("%d=%s" % (cid, label) for cid, label in cycle) + "}"
                    print(line)
                except Exception:
                    pass
    sh_id = _find_plugin(c4d.PLUGINTYPE_SHADER, "Image Texture", OCTANE_IMAGE_TEXTURE_ID)
    print("[hdri-studio] shader Image Texture usato: %s" % sh_id)
    if sh_id is not None:
        sh = c4d.BaseShader(sh_id)
        desc = sh.GetDescription(c4d.DESCFLAGS_DESC_NONE)
        if desc is not None:
            for bc, pid, _g in desc:
                try:
                    line = "[hdri-studio]   shader param id=%-6d dtype=%-8d %s" % (pid[0].id, pid[0].dtype, bc.GetString(c4d.DESC_NAME))
                    cycle = bc.GetContainer(c4d.DESC_CYCLE)
                    if cycle is not None and len(cycle) > 0:
                        line += "  {" + ", ".join("%d=%s" % (cid, label) for cid, label in cycle) + "}"
                    print(line)
                except Exception:
                    pass
    print("[hdri-studio] --- fine diagnostica ---")


def _vec(a):
    return c4d.Vector(float(a[0]), float(a[1]), float(a[2]))


def sync_separate_lights(doc, msg):
    """Crea/aggiorna/rimuove le luci separate sotto il null; restituisce quante ne ha toccate."""
    entries = msg.get("lights", [])
    root = _find_by_name(doc.GetFirstObject(), LIGHTS_NULL)
    if root is None:
        if not entries:
            return 0
        root = c4d.BaseObject(c4d.Onull)
        root.SetName(LIGHTS_NULL)
        doc.InsertObject(root)
    template = _find_by_name(doc.GetFirstObject(), TEMPLATE_NAME)
    existing = {c.GetName(): c for c in _children(root)}
    wanted = set()
    touched = 0
    face = LIGHT_EMITS_ALONG_Z * int(msg.get("face_sign", 1))
    for e in entries:
        name = LIGHT_PREFIX + e["name"]
        wanted.add(name)
        obj = existing.get(name)
        if obj is None:
            if template is not None:
                obj = template.GetClone(c4d.COPYFLAGS_NONE)
                obj.InsertUnder(root)
            else:
                obj, note = _create_default_light(doc, root)
                print("[hdri-studio] luce separata '%s': nessun '%s' nella scena → %s" % (e["name"], TEMPLATE_NAME, note))
            obj.SetName(name)
        F, R, U = _vec(e["forward"]), _vec(e["right"]), _vec(e["up"])
        d = float(e["distance"])
        # base propria (nessuno specchio sull'oggetto): se R×U = -F, il preset ha specchiato l'immagine
        # e la stessa cosa va fatta all'asse X della luce
        if (R.Cross(U) - F).GetLength() > 1e-3:
            R = -R
        if face < 0:
            mat = c4d.Matrix(F * d, R, U, F)          # -Z guarda il centro, X = destra vista dal centro
        else:
            mat = c4d.Matrix(F * d, -R, U, -F)        # +Z guarda il centro
        obj.SetMl(mat)
        w, h = float(e["size"][0]), float(e["size"][1])
        if obj.IsInstanceOf(c4d.Olight):
            obj[c4d.LIGHT_AREADETAILS_SIZEX] = w
            obj[c4d.LIGHT_AREADETAILS_SIZEY] = h
        # visibilità alla camera sul tag Octane Light
        vis = bool(e.get("visible", True))
        tag = obj.GetFirstTag()
        while tag:
            if tag.GetType() == OCTANE_LIGHT_TAG_ID:
                tag[OCT_LIGHT_CAMERA_VISIBILITY] = vis
            tag = tag.GetNext()
        if not _set_image_path(obj, e["path"]):
            print("[hdri-studio] luce '%s': nessuno slot immagine trovato (metti un ImageTexture nella luce modello)" % name)
        touched += 1
    for name, obj in existing.items():
        if name not in wanted:
            obj.Remove()
            touched += 1
    c4d.EventAdd(c4d.EVENT_FORCEREDRAW)
    return touched


# --- picking per il LightPaint ----------------------------------------------------------------------

def _polygon_objects(op, out):
    """Raccoglie i PolygonObject renderizzabili: mesh vere e cache dei generatori/deformatori
    (ricetta standard Maxon: deform cache → cache → oggetto, saltando i control object)."""
    while op:
        if op.GetEditorMode() != c4d.MODE_OFF:
            _collect(op, out)
        op = op.GetNext()


def _collect(op, out):
    cache = op.GetDeformCache()
    if cache is not None:
        _collect(cache, out)
    else:
        cache = op.GetCache()
        if cache is not None:
            _collect(cache, out)
        elif not op.GetBit(c4d.BIT_CONTROLOBJECT) and op.IsInstanceOf(c4d.Opolygon):
            out.append(op)
    child = op.GetDown()
    while child is not None:
        _collect(child, out)
        child = child.GetNext()


def _smooth_normal(poly, hit, phong_cache):
    """Normale interpolata (Phong) nel punto colpito; None se l'oggetto non ha normali Phong."""
    key = id(poly)
    if key not in phong_cache:
        try:
            phong_cache[key] = poly.CreatePhongNormals()
        except Exception:
            phong_cache[key] = None
    normals = phong_cache[key]
    if not normals:
        return None
    fid = hit["face_id"]
    cp = poly.GetPolygon(fid)
    pts = poly.GetAllPoints()
    idx = [cp.a, cp.b, cp.c, cp.d]
    base = fid * 4
    if hit.get("tri_face_id", 0) == 0 or cp.c == cp.d:
        tri = (0, 1, 2)
    else:
        tri = (0, 2, 3)
    p0, p1, p2 = (pts[idx[k]] for k in tri)
    n0, n1, n2 = (normals[base + k] for k in tri)
    # coordinate baricentriche del punto colpito nel triangolo
    v0, v1, v2 = p1 - p0, p2 - p0, hit["hitpos"] - p0
    d00, d01, d11 = v0.Dot(v0), v0.Dot(v1), v1.Dot(v1)
    d20, d21 = v2.Dot(v0), v2.Dot(v1)
    denom = d00 * d11 - d01 * d01
    if abs(denom) < 1e-12:
        return None
    v = (d11 * d20 - d01 * d21) / denom
    w = (d00 * d21 - d01 * d20) / denom
    u = 1.0 - v - w
    n = n0 * u + n1 * v + n2 * w
    if n.GetLength() < 1e-9:
        return None
    return n.GetNormalized()


def pick(doc, bd, mx, my):
    """Ray dal pixel (mx, my) della vista bd → (punto, normale, direzione) in coordinate mondo, o None."""
    ray_p = bd.SW(c4d.Vector(mx, my, 0.0))
    ray_far = bd.SW(c4d.Vector(mx, my, 10000.0))
    ray_d = (ray_far - ray_p).GetNormalized()
    polys = []
    _polygon_objects(doc.GetFirstObject(), polys)
    best = None
    phong_cache = {}
    rc = c4d.utils.GeRayCollider()
    for poly in polys:
        if poly.GetPolygonCount() == 0:
            continue
        mg = poly.GetMg()
        mi = ~mg
        p_loc = mi * ray_p
        d_loc = mi.MulV(ray_d).GetNormalized()
        if not rc.Init(poly, True):
            continue
        if not rc.Intersect(p_loc, d_loc, 1.0e12):
            continue
        hit = rc.GetNearestIntersection()
        if hit is None:
            continue
        p_w = mg * hit["hitpos"]
        dist = (p_w - ray_p).GetLength()
        if best is None or dist < best[0]:
            n_loc = _smooth_normal(poly, hit, phong_cache) or hit["f_normal"]
            n_w = mg.MulV(n_loc).GetNormalized()
            if n_w.Dot(ray_d) > 0.0:
                n_w = -n_w
            best = (dist, p_w, n_w)
    if best is None:
        return None
    return best[1], best[2], ray_d


def _v(vec):
    return [vec.x, vec.y, vec.z]


class LightPaintTool(c4d.plugins.ToolData):
    """Click o drag sul modello: manda all'app punto, normale e direzione di vista."""

    def __init__(self):
        self.last_hit = None

    def GetState(self, doc):
        return c4d.CMD_ENABLED

    def MouseInput(self, doc, data, bd, win, msg):
        if msg[c4d.BFM_INPUT_CHANNEL] != c4d.BFM_INPUT_MOUSELEFT:
            return True
        mx = msg[c4d.BFM_INPUT_X]
        my = msg[c4d.BFM_INPUT_Y]
        self._paint(doc, bd, mx, my)
        win.MouseDragStart(c4d.KEY_MLEFT, mx, my, c4d.MOUSEDRAGFLAGS_DONTHIDEMOUSE | c4d.MOUSEDRAGFLAGS_NOMOVE)
        while True:
            result, dx, dy, channels = win.MouseDrag()
            if result != c4d.MOUSEDRAGRESULT_CONTINUE:
                break
            if dx == 0 and dy == 0:
                continue
            mx += dx
            my += dy
            self._paint(doc, bd, mx, my)
        win.MouseDragEnd()
        return True

    def _paint(self, doc, bd, mx, my):
        hit = pick(doc, bd, mx, my)
        if hit is None:
            return
        p, n, d = hit
        self.last_hit = (p, n)
        cam = bd.GetSceneCamera(doc) or bd.GetEditorCamera()
        LINK.send({"type": "lightpaint", "host": "c4d", "point": _v(p), "normal": _v(n),
                   "view": _v(d), "camera": _v(cam.GetMg().off)})
        c4d.DrawViews(c4d.DRAWFLAGS_ONLY_ACTIVE_VIEW | c4d.DRAWFLAGS_NO_THREAD | c4d.DRAWFLAGS_NO_ANIMATION)

    def Draw(self, doc, data, bd, bh, bt, flags):
        if self.last_hit is not None:
            p, n = self.last_hit
            bd.SetMatrix_Matrix(None, c4d.Matrix())
            bd.SetPen(c4d.Vector(1.0, 0.8, 0.2))
            bd.DrawLine(p, p + n * 20.0, 0)
            bd.DrawHandle(p, c4d.DRAWHANDLE_BIG, 0)
        return c4d.TOOLDRAW_HANDLES


# --- plugin ---------------------------------------------------------------------------------------

_VERSION = c4d.GetC4DVersion()
LINK = link_core.LinkClient(hello={
    "type": "hello", "host": "c4d", "version": "%d.%d" % (_VERSION // 1000, _VERSION % 1000)})


class HdriStudioLink(c4d.plugins.MessageData):
    def __init__(self):
        self.client = LINK
        self.watch = link_core.MtimeWatcher()
        self._last_scan = 0.0
        self._was_connected = False
        self._last_cam = None

    def GetTimer(self):
        return TIMER_MS

    def CoreMessage(self, id, bc):
        if id == c4d.MSG_TIMER:
            try:
                self._tick()
            except Exception as e:  # mai far cadere il timer
                print("[hdri-studio] errore: %r" % e)
        return True

    def _send_camera(self, doc):
        """Camera attiva della vista: direzione, alto e FOV orizzontale, solo quando cambiano."""
        if not self.client.connected:
            return
        bd = doc.GetActiveBaseDraw()
        if bd is None:
            return
        cam = bd.GetSceneCamera(doc) or bd.GetEditorCamera()
        if cam is None:
            return
        mg = cam.GetMg()
        try:
            fov = math.degrees(cam[c4d.CAMERAOBJECT_FOV])
        except Exception:
            fov = 40.0
        key = (round(mg.v3.x, 4), round(mg.v3.y, 4), round(mg.v3.z, 4),
               round(mg.v2.x, 4), round(mg.v2.y, 4), round(mg.v2.z, 4), round(fov, 2))
        if key == self._last_cam:
            return
        self._last_cam = key
        self.client.send({"type": "camera", "host": "c4d", "forward": _v(mg.v3), "up": _v(mg.v2),
                          "position": _v(mg.off), "fov": fov})

    def _tick(self):
        doc = c4d.documents.GetActiveDocument()
        if doc is None:
            return
        for msg in self.client.poll():
            if msg.get("type") == "hdri_updated":
                path = msg.get("path", "")
                n = reload_file(doc, path)
                self.watch.touch(path)
                if n == 0 and path and not _has_environment_tag(doc) and _state["last_env_path"] != path:
                    _state["last_env_path"] = path
                    print("[hdri-studio] nessun ambiente Octane nella scena → %s" % create_environment(doc, path))
                    n = 1
                elif n == 0 and path and _has_environment_tag(doc):
                    print("[hdri-studio] %s: nessun nodo usa questo file; l'Octane Environment esistente punta altrove (carica lì l'EXR del live link, o usa 'HDRI Studio: crea ambiente HDRI')" % os.path.basename(path))
                print("[hdri-studio] %s → %d nodi ricaricati" % (os.path.basename(path), n))
            elif msg.get("type") == "separate_lights":
                n = sync_separate_lights(doc, msg)
                for e in msg.get("lights", []):
                    self.watch.touch(e.get("path", ""))
                if n:
                    print("[hdri-studio] luci separate: %d aggiornate" % n)
        if self.client.connected != self._was_connected:
            self._was_connected = self.client.connected
            print("[hdri-studio] %s" % ("collegato all'app" if self.client.connected else "app non raggiungibile, uso la data dei file"))
        self._send_camera(doc)
        now = time.time()
        if now - self._last_scan >= MTIME_SCAN_S:
            self._last_scan = now
            paths = []
            for node in all_nodes(doc):
                paths.extend(image_paths(node))
            for p in self.watch.changed(paths):
                n = reload_file(doc, p)
                print("[hdri-studio] %s modificato su disco → %d nodi ricaricati" % (os.path.basename(p), n))


class DiagCommand(c4d.plugins.CommandData):
    def Execute(self, doc):
        octane_diagnostics(doc)
        c4d.gui.MessageDialog("HDRI Studio: diagnostica stampata nella console (Extensions > Console).")
        return True


class EnvCommand(c4d.plugins.CommandData):
    def Execute(self, doc):
        path = _state.get("last_env_path") or ""
        # ultimo EXR visto dal live link, altrimenti il primo .exr usato nella scena
        if not path:
            for node in all_nodes(doc):
                for p in image_paths(node):
                    path = p
                    break
                if path:
                    break
        if not path:
            c4d.gui.MessageDialog("HDRI Studio: attiva prima il live link nell'app (serve il percorso dell'EXR).")
            return True
        note = create_environment(doc, path)
        print("[hdri-studio] %s" % note)
        c4d.gui.MessageDialog("HDRI Studio: %s" % note)
        return True


class ReloadCommand(c4d.plugins.CommandData):
    def Execute(self, doc):
        n = reload_all(doc)
        c4d.gui.MessageDialog("HDRI Studio: ricaricati %d nodi con texture." % n)
        return True


if __name__ == "__main__":
    c4d.plugins.RegisterMessagePlugin(id=PLUGIN_ID_LINK, str="HDRI Studio Link", info=0, dat=HdriStudioLink())
    c4d.plugins.RegisterCommandPlugin(id=PLUGIN_ID_RELOAD, str="HDRI Studio: ricarica texture",
                                      info=0, icon=None, help="Preme Reload su tutti i nodi con texture EXR/HDR",
                                      dat=ReloadCommand())
    c4d.plugins.RegisterCommandPlugin(id=PLUGIN_ID_ENV, str="HDRI Studio: crea ambiente HDRI",
                                      info=0, icon=None, help="Sky + Octane Environment + Image Texture con l'EXR del live link",
                                      dat=EnvCommand())
    c4d.plugins.RegisterCommandPlugin(id=PLUGIN_ID_DIAG, str="HDRI Studio: diagnostica Octane",
                                      info=0, icon=None, help="Stampa in console i plugin e i parametri Octane trovati",
                                      dat=DiagCommand())
    c4d.plugins.RegisterToolPlugin(id=PLUGIN_ID_PAINT, str="HDRI Studio LightPaint", info=0, icon=None,
                                   help="Click sul modello: la luce selezionata in HDRI Studio si sposta sul riflesso",
                                   dat=LightPaintTool())
    print("[hdri-studio] plugin %s caricato da %s (porta %d)" % (PLUGIN_VERSION, os.path.dirname(__file__), link_core.DEFAULT_PORT))
