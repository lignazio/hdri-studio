"""Genera bake/bake_glsl_source.gd con il sorgente di bake.glsl incorporato: nell'app esportata il
file .glsl non esiste (Godot esporta solo la risorsa importata) e questo è il fallback del baker.
Da rilanciare quando cambia bake.glsl (lo smoke test controlla che sia aggiornato).

    python3 hdri_studio/tools/embed_shader.py
"""
import os

here = os.path.dirname(os.path.abspath(__file__))
src_path = os.path.join(here, "..", "bake", "bake.glsl")
dst_path = os.path.join(here, "..", "bake", "bake_glsl_source.gd")
src = open(src_path, encoding="utf-8").read().replace("#[compute]", "")
escaped = src.replace("\\", "\\\\").replace('"', '\\"')
out = (
    "class_name BakeGlslSource\n"
    "extends RefCounted\n"
    "## GENERATO da tools/embed_shader.py: sorgente di bake/bake.glsl per l'app esportata. Non modificare a mano.\n\n"
    'const SOURCE := "' + escaped.replace("\n", "\\n") + '"\n'
)
open(dst_path, "w", encoding="utf-8").write(out)
print("scritto", os.path.relpath(dst_path), len(src), "byte")
