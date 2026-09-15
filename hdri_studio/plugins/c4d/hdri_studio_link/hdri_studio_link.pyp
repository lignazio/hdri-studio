"""HDRI Studio Link — plugin per Cinema 4D (Octane e nativo).

Si collega all'app HDRI Studio (TCP locale, porta 47820). Quando l'app esporta un nuovo EXR manda
"hdri_updated" con il percorso: il plugin trova gli ImageTexture (o qualsiasi nodo) che puntano a
quel file e preme il loro pulsante Reload — in Octane è l'unico modo per far rileggere la texture.
Se l'app non è collegata, controlla ogni secondo la data di modifica dei file immagine usati nella
scena e ricarica quelli cambiati.

Installazione: Edit > Preferences > Plugins > aggiungi la cartella `plugins/c4d` (quella che contiene
`hdri_studio_link/`), riavvia Cinema 4D. Nel menu Extensions compare "HDRI Studio: ricarica texture".
"""
import os
import sys
import time

import c4d

sys.path.insert(0, os.path.dirname(__file__))
import link_core  # noqa: E402

PLUGIN_ID_LINK = 1065931
PLUGIN_ID_RELOAD = 1065932
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


# --- plugin ---------------------------------------------------------------------------------------

class HdriStudioLink(c4d.plugins.MessageData):
    def __init__(self):
        version = c4d.GetC4DVersion()
        self.client = link_core.LinkClient(hello={
            "type": "hello", "host": "c4d", "version": "%d.%d" % (version // 1000, version % 1000)})
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
    print("[hdri-studio] plugin caricato (porta %d)" % link_core.DEFAULT_PORT)
