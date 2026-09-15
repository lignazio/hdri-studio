"""HDRI Studio — sonda per il reload delle texture in Cinema 4D (Octane o nativo).

Da eseguire nello Script Manager (Extensions > Script Manager > incolla > Execute) con la scena aperta.

Cerca in materiali, shader, oggetti e tag tutti i nodi che contengono un percorso .exr/.hdr.
Per ognuno stampa tipo di nodo e ID del parametro file, poi elenca tutti i PULSANTI della sua
descrizione e "preme" (MSG_DESCRIPTION_COMMAND) quelli che si chiamano Reload: in Octane è l'unico
meccanismo che forza la rilettura della texture. L'output della console dice quali ID usare nel plugin.
"""
import c4d

EXTS = (".exr", ".hdr")


def walk_shaders(sh, out):
    while sh:
        out.append(sh)
        walk_shaders(sh.GetDown(), out)
        sh = sh.GetNext()


def walk_objects(op, out):
    while op:
        out.append(op)
        walk_objects(op.GetDown(), out)
        op = op.GetNext()


def image_params(node):
    """Restituisce [(id, percorso)] per i parametri stringa del nodo che puntano a un'immagine."""
    bc = node.GetDataInstance()
    found = []
    if bc is None:
        return found
    for pid, val in bc:
        if isinstance(val, str) and val.lower().endswith(EXTS):
            found.append((pid, val))
        elif isinstance(val, c4d.BaseContainer):
            for pid2, val2 in val:
                if isinstance(val2, str) and val2.lower().endswith(EXTS):
                    found.append(((pid, pid2), val2))
    return found


def buttons(node):
    """Restituisce [(DescID, nome)] di tutti i parametri pulsante nella descrizione del nodo."""
    out = []
    desc = node.GetDescription(c4d.DESCFLAGS_DESC_NONE)
    if desc is None:
        return out
    for bc, paramid, groupid in desc:
        try:
            if paramid[0].dtype == c4d.DTYPE_BUTTON:
                out.append((paramid, bc.GetString(c4d.DESC_NAME)))
        except Exception:
            pass
    return out


def press(node, descid):
    return node.Message(c4d.MSG_DESCRIPTION_COMMAND, {"id": descid})


def main():
    doc = c4d.documents.GetActiveDocument()
    nodes = []
    mat = doc.GetFirstMaterial()
    while mat:
        nodes.append(mat)
        walk_shaders(mat.GetFirstShader(), nodes)
        mat = mat.GetNext()
    objs = []
    walk_objects(doc.GetFirstObject(), objs)
    for op in objs:
        nodes.append(op)
        walk_shaders(op.GetFirstShader(), nodes)
        tag = op.GetFirstTag()
        while tag:
            nodes.append(tag)
            walk_shaders(tag.GetFirstShader(), nodes)
            tag = tag.GetNext()

    hits = 0
    for node in nodes:
        for pid, path in image_params(node):
            hits += 1
            print("[hdri-studio] %-28s tipo=%d  param=%s  ->  %s" % (node.GetName(), node.GetType(), pid, path))
            btns = buttons(node)
            for descid, name in btns:
                pressed = ""
                if "reload" in name.lower():
                    pressed = "  -> PREMUTO, risposta=%s" % press(node, descid)
                print("[hdri-studio]     pulsante id=%d  nome=%r%s" % (descid[0].id, name, pressed))
            if not btns:
                print("[hdri-studio]     (nessun pulsante nella descrizione)")
            node.SetDirty(c4d.DIRTYFLAGS_DATA)
            node.Message(c4d.MSG_UPDATE)
    c4d.EventAdd(c4d.EVENT_FORCEREDRAW)
    print("[hdri-studio] %d nodi con immagine trovati" % hits)


if __name__ == "__main__":
    main()
