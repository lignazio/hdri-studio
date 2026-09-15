"""HDRI Studio — sonda per il reload delle texture in Cinema 4D (Octane o nativo).

Da eseguire nello Script Manager (Extensions > Script Manager > incolla > Execute) con la scena aperta.

Cerca in materiali, shader, oggetti e tag tutti i parametri che contengono un percorso .exr/.hdr,
stampa nella console tipo di nodo e ID del parametro, poi riassegna lo stesso percorso e manda
MSG_UPDATE + EventAdd(): è il meccanismo che userà il plugin di live link per forzare Octane a
rileggere la texture. L'output della console dice quali ID usare nel plugin.
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
            bc = node.GetDataInstance()
            if isinstance(pid, tuple):
                sub = bc.GetContainerInstance(pid[0])
                sub.SetString(pid[1], path)
            else:
                bc.SetString(pid, path)
            node.SetDirty(c4d.DIRTYFLAGS_DATA)
            node.Message(c4d.MSG_UPDATE)
    c4d.EventAdd(c4d.EVENT_FORCEREDRAW)
    print("[hdri-studio] %d parametri immagine trovati e riassegnati" % hits)


if __name__ == "__main__":
    main()
