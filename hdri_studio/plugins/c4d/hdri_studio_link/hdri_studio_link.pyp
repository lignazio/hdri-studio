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
"HDRI Studio Lights" clonando una luce modello chiamata "HS_TEMPLATE" (un'Octane Area Light con un
ImageTexture nel suo slot texture: la prepari una volta, il plugin la clona, la posiziona, la scala e
le assegna l'EXR). Il null si può spostare sul soggetto: le luci lo seguono.

Installazione: Edit > Preferences > Plugins > aggiungi la cartella `plugins/c4d` (quella che contiene
`hdri_studio_link/`), riavvia Cinema 4D. Nel menu Extensions compare "HDRI Studio: ricarica texture".
"""
import os
import sys
import time

import c4d

sys.path.insert(0, os.path.dirname(__file__))
import link_core  # noqa: E402

# ID unici del plugin: valori alti fuori dagli intervalli usati dai moduli di Cinema 4D
# (1065932 collideva con C4d_objects). Per una distribuzione pubblica andrebbero richiesti su
# https://developers.maxon.net/forum/pid
PLUGIN_ID_LINK = 1099780031
PLUGIN_ID_RELOAD = 1099780032
PLUGIN_ID_PAINT = 1099780033
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
# Verso di emissione della luce modello lungo il suo asse Z locale. Misurato il 15/09/2026 con Octane:
# le area light emettono verso +Z, quindi la luce guarda il centro con la faccia +Z. Se una luce
# modello di altro tipo illuminasse dalla parte sbagliata, cambia questo segno.
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
    """Assegna `path` al primo parametro immagine trovato nella luce (tag Octane / shader) e preme Reload."""
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
    return False


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
    for e in entries:
        name = LIGHT_PREFIX + e["name"]
        wanted.add(name)
        obj = existing.get(name)
        if obj is None:
            if template is None:
                print("[hdri-studio] luce separata '%s': manca la luce modello '%s' nella scena" % (e["name"], TEMPLATE_NAME))
                continue
            obj = template.GetClone(c4d.COPYFLAGS_NONE)
            obj.SetName(name)
            obj.InsertUnder(root)
        F, R, U = _vec(e["forward"]), _vec(e["right"]), _vec(e["up"])
        d = float(e["distance"])
        # base propria (nessuno specchio sull'oggetto): se R×U = -F, il preset ha specchiato l'immagine
        # e la stessa cosa va fatta all'asse X della luce
        if (R.Cross(U) - F).GetLength() > 1e-3:
            R = -R
        if LIGHT_EMITS_ALONG_Z < 0:
            mat = c4d.Matrix(F * d, R, U, F)          # -Z guarda il centro, X = destra vista dal centro
        else:
            mat = c4d.Matrix(F * d, -R, U, -F)        # +Z guarda il centro
        obj.SetMl(mat)
        w, h = float(e["size"][0]), float(e["size"][1])
        if obj.IsInstanceOf(c4d.Olight):
            obj[c4d.LIGHT_AREADETAILS_SIZEX] = w
            obj[c4d.LIGHT_AREADETAILS_SIZEY] = h
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

    def GetTimer(self):
        return TIMER_MS

    def CoreMessage(self, id, bc):
        if id == c4d.MSG_TIMER:
            try:
                self._tick()
            except Exception as e:  # mai far cadere il timer
                print("[hdri-studio] errore: %r" % e)
        return True

    def _tick(self):
        doc = c4d.documents.GetActiveDocument()
        if doc is None:
            return
        for msg in self.client.poll():
            if msg.get("type") == "hdri_updated":
                path = msg.get("path", "")
                n = reload_file(doc, path)
                self.watch.touch(path)
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
        now = time.time()
        if now - self._last_scan >= MTIME_SCAN_S:
            self._last_scan = now
            paths = []
            for node in all_nodes(doc):
                paths.extend(image_paths(node))
            for p in self.watch.changed(paths):
                n = reload_file(doc, p)
                print("[hdri-studio] %s modificato su disco → %d nodi ricaricati" % (os.path.basename(p), n))


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
    c4d.plugins.RegisterToolPlugin(id=PLUGIN_ID_PAINT, str="HDRI Studio LightPaint", info=0, icon=None,
                                   help="Click sul modello: la luce selezionata in HDRI Studio si sposta sul riflesso",
                                   dat=LightPaintTool())
    print("[hdri-studio] plugin caricato (porta %d)" % link_core.DEFAULT_PORT)
