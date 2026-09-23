"""HDRI Studio Link — add-on per Blender.

Si collega all'app HDRI Studio (TCP 127.0.0.1:47820, JSON-lines, lo stesso protocollo del plugin C4D):
- "hdri_updated": ricarica le immagini di Blender che puntano al file (image.reload()); fallback sulla
  data di modifica ogni secondo se l'app non è collegata.
- "separate_lights": crea/aggiorna piani emissivi (Emission strength 1 + l'EXR planare) nella
  collezione "HDRI Studio Lights", figli dell'empty "HDRI Studio Center": stessa direzione della luce,
  distanza D, dimensione fisica. Un piano emissivo ha la semantica della radianza (strength 1 = valore
  del pixel): niente calibrazione.
- LightPaint: operatore modale nel viewport (pannello HDRI Studio nella sidebar N): click o trascina sul
  modello → ray_cast → punto, normale interpolata e direzione di vista → l'app sposta la luce.

Coordinate: Blender è Z-up; la convenzione interna dell'app è Y-up con centro immagine +Z. Misurato in
Fase 0: Blender_x = interno_z, Blender_y = interno_x, Blender_z = interno_y (rotazione pura).

Installazione: Edit > Preferences > Add-ons > Install… > scegli la cartella zippata, oppure copia
`hdri_studio_link/` in `scripts/addons/`. Poi attiva "HDRI Studio Link".
"""
import math
import os
import sys
import time

import bpy
from bpy_extras import view3d_utils
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import link_core  # noqa: E402

bl_info = {
    "name": "HDRI Studio Link",
    "author": "Lucenti Studio",
    "version": (0, 1),
    "blender": (4, 2, 0),
    "location": "3D View > Sidebar > HDRI Studio",
    "description": "Live link with HDRI Studio: HDRI reload, separate lights, LightPaint",
    "category": "Lighting",
}

ADDON_VERSION = "0.1"
EXTS = (".exr", ".hdr")
TIMER_S = 0.2
MTIME_SCAN_S = 1.0
COLLECTION = "HDRI Studio Lights"
CENTER = "HDRI Studio Center"
LIGHT_PREFIX = "HS: "

LINK = link_core.LinkClient(hello={"type": "hello", "host": "blender", "version": bpy.app.version_string})
WATCH = link_core.MtimeWatcher()
_state = {"last_scan": 0.0, "was_connected": False, "last_msg": "", "lightpaint": False, "last_cam": None}


# --- coordinate ----------------------------------------------------------------------------------

def to_blender(v):
    """Vettore interno (Y-up, centro +Z) → Blender (Z-up): rotazione misurata in Fase 0."""
    return Vector((float(v[2]), float(v[0]), float(v[1])))


def to_internal(v):
    return [float(v.y), float(v.z), float(v.x)]


# --- reload ----------------------------------------------------------------------------------------

def _image_path(img):
    try:
        return bpy.path.abspath(img.filepath, library=img.library)
    except Exception:
        return ""


def reload_file(path):
    n = 0
    for img in bpy.data.images:
        p = _image_path(img)
        if p and link_core.same_file(p, path):
            img.reload()
            n += 1
    if n:
        _redraw()
    return n


def reload_all():
    n = 0
    for img in bpy.data.images:
        p = _image_path(img)
        if p and p.lower().endswith(EXTS) and os.path.exists(p):
            img.reload()
            n += 1
    _redraw()
    return n


def _redraw():
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type in ("VIEW_3D", "IMAGE_EDITOR", "NODE_EDITOR"):
                area.tag_redraw()


# --- luci separate -----------------------------------------------------------------------------------

def _collection():
    col = bpy.data.collections.get(COLLECTION)
    if col is None:
        col = bpy.data.collections.new(COLLECTION)
        bpy.context.scene.collection.children.link(col)
    return col


def _center(col):
    obj = bpy.data.objects.get(CENTER)
    if obj is None:
        obj = bpy.data.objects.new(CENTER, None)
        obj.empty_display_type = "SPHERE"
        obj.empty_display_size = 0.2
        col.objects.link(obj)
    return obj


def _plane_mesh(name, w, h, flip_u):
    me = bpy.data.meshes.new(name)
    hw, hh = w * 0.5, h * 0.5
    verts = [(-hw, -hh, 0.0), (hw, -hh, 0.0), (hw, hh, 0.0), (-hw, hh, 0.0)]
    me.from_pydata(verts, [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap")
    uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    for loop in me.loops:
        u, v = uvs[loop.vertex_index]
        if flip_u:
            u = 1.0 - u
        uv.data[loop.index].uv = (u, v)
    me.update()
    return me


def _material(name, path):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.name = "HS_Texture"
        tex.extension = "CLIP"
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.inputs["Strength"].default_value = 1.0
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    tex = mat.node_tree.nodes.get("HS_Texture")
    img = None
    for candidate in bpy.data.images:
        if link_core.same_file(_image_path(candidate), path):
            img = candidate
            break
    if img is None:
        try:
            img = bpy.data.images.load(path, check_existing=True)
        except RuntimeError:
            img = None
    if img is not None:
        img.reload()
        tex.image = img
    return mat


def sync_separate_lights(msg):
    """Crea/aggiorna/rimuove i piani emissivi. Restituisce quanti ha toccato."""
    entries = msg.get("lights", [])
    scale = float(msg.get("unit_scale", 0.01))  # l'app lavora in cm, Blender in m
    flip_u = bool(msg.get("texture_flipped", False))
    col = _collection()
    center = _center(col)
    existing = {o.name: o for o in col.objects if o.name.startswith(LIGHT_PREFIX)}
    wanted = set()
    touched = 0
    for e in entries:
        name = LIGHT_PREFIX + e["name"]
        wanted.add(name)
        w, h = float(e["size"][0]) * scale, float(e["size"][1]) * scale
        F, R, U = to_blender(e["forward"]), to_blender(e["right"]), to_blender(e["up"])
        d = float(e["distance"]) * scale
        obj = existing.get(name)
        me = _plane_mesh(name, w, h, flip_u)
        if obj is None:
            obj = bpy.data.objects.new(name, me)
            col.objects.link(obj)
            obj.parent = center
        else:
            old = obj.data
            obj.data = me
            if old.users == 0:
                bpy.data.meshes.remove(old)
        # il piano guarda il centro con la faccia +Z (Blender emette da entrambi i lati):
        # X = destra vista dal centro, Y = alto, Z = -F → base propria (R × U = -F nel frame interno)
        rot = Matrix((R, U, -F)).transposed()
        mat = Matrix.Translation(F * d) @ rot.to_4x4()
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = mat
        obj.data.materials.clear()
        obj.data.materials.append(_material(name, e["path"]))
        obj.visible_camera = bool(e.get("visible", True)) and bpy.context.scene.hdri_studio_visible_camera
        touched += 1
    for name, obj in existing.items():
        if name not in wanted:
            me = obj.data
            bpy.data.objects.remove(obj)
            if me and me.users == 0:
                bpy.data.meshes.remove(me)
            touched += 1
    _redraw()
    return touched


# --- timer ------------------------------------------------------------------------------------------

def _send_camera():
    """Vista 3D attiva (o camera di scena): direzione, alto e FOV orizzontale, quando cambiano."""
    if not LINK.connected:
        return
    fwd = up = None
    fov = 40.0
    for win in bpy.context.window_manager.windows:
        for area in win.screen.areas:
            if area.type != "VIEW_3D":
                continue
            rv3d = area.spaces.active.region_3d
            if rv3d is None:
                continue
            m = rv3d.view_matrix.inverted()
            fwd = -(m.to_3x3() @ Vector((0, 0, 1)))
            up = m.to_3x3() @ Vector((0, 1, 0))
            if rv3d.view_perspective == "CAMERA" and bpy.context.scene.camera:
                cam = bpy.context.scene.camera
                cm = cam.matrix_world
                fwd = -(cm.to_3x3() @ Vector((0, 0, 1)))
                up = cm.to_3x3() @ Vector((0, 1, 0))
                fov = math.degrees(cam.data.angle_x)
            else:
                fov = math.degrees(2.0 * math.atan(36.0 / (2.0 * area.spaces.active.lens)))
            break
        if fwd is not None:
            break
    if fwd is None:
        return
    key = tuple(round(c, 4) for c in (*fwd, *up)) + (round(fov, 2),)
    if key == _state["last_cam"]:
        return
    _state["last_cam"] = key
    LINK.send({"type": "camera", "host": "blender", "forward": to_internal(fwd), "up": to_internal(up), "fov": fov})


def tick():
    try:
        _send_camera()
        for msg in LINK.poll():
            t = msg.get("type")
            if t == "hdri_updated":
                path = msg.get("path", "")
                n = reload_file(path)
                WATCH.touch(path)
                _state["last_msg"] = "%s → %d images" % (os.path.basename(path), n)
            elif t == "separate_lights":
                n = sync_separate_lights(msg)
                for e in msg.get("lights", []):
                    WATCH.touch(e.get("path", ""))
                if n:
                    _state["last_msg"] = "separate lights: %d" % n
        if LINK.connected != _state["was_connected"]:
            _state["was_connected"] = LINK.connected
            _redraw()
        now = time.time()
        if now - _state["last_scan"] >= MTIME_SCAN_S:
            _state["last_scan"] = now
            paths = [p for p in (_image_path(i) for i in bpy.data.images) if p and p.lower().endswith(EXTS)]
            for p in WATCH.changed(paths):
                n = reload_file(p)
                _state["last_msg"] = "%s changed → %d images" % (os.path.basename(p), n)
    except Exception as e:  # mai far cadere il timer
        print("[hdri-studio] error: %r" % e)
    return TIMER_S


# --- LightPaint ---------------------------------------------------------------------------------------

def _smooth_normal(obj_eval, poly_index, hit_local):
    """Normale interpolata: media dei vertici del poligono pesata con l'inverso della distanza."""
    me = obj_eval.data
    if poly_index < 0 or poly_index >= len(me.polygons):
        return None
    poly = me.polygons[poly_index]
    if not poly.use_smooth:
        return None
    n = Vector((0.0, 0.0, 0.0))
    for vi in poly.vertices:
        v = me.vertices[vi]
        d = (v.co - hit_local).length
        n += v.normal / max(d, 1e-6)
    if n.length < 1e-9:
        return None
    return n.normalized()


def pick(context, event):
    region = context.region
    rv3d = context.region_data
    coord = (event.mouse_region_x, event.mouse_region_y)
    origin = view3d_utils.region_2d_to_origin_3d(region, rv3d, coord)
    direction = view3d_utils.region_2d_to_vector_3d(region, rv3d, coord)
    depsgraph = context.evaluated_depsgraph_get()
    hit, loc, normal, index, obj, mw = context.scene.ray_cast(depsgraph, origin, direction)
    if not hit or obj is None:
        return None
    if obj.name.startswith(LIGHT_PREFIX):
        return None
    try:
        obj_eval = obj.evaluated_get(depsgraph)
        hit_local = mw.inverted() @ loc
        sn = _smooth_normal(obj_eval, index, hit_local)
        if sn is not None:
            normal = (mw.to_3x3().inverted().transposed() @ sn).normalized()
    except Exception:
        pass
    if normal.dot(direction) > 0.0:
        normal = -normal
    return loc, normal, direction


class HDRISTUDIO_OT_lightpaint(bpy.types.Operator):
    bl_idname = "hdri_studio.lightpaint"
    bl_label = "HDRI Studio LightPaint"
    bl_description = "Click or drag on the model: the light selected in HDRI Studio moves onto the reflection"
    bl_options = {"REGISTER"}

    _pressed = False

    def invoke(self, context, event):
        if context.area.type != "VIEW_3D":
            self.report({"WARNING"}, "Use it in the 3D viewport")
            return {"CANCELLED"}
        context.window_manager.modal_handler_add(self)
        _state["lightpaint"] = True
        context.workspace.status_text_set("LightPaint: click/drag on the model · Esc or right click to exit")
        return {"RUNNING_MODAL"}

    def modal(self, context, event):
        if event.type in {"RIGHTMOUSE", "ESC"}:
            _state["lightpaint"] = False
            context.workspace.status_text_set(None)
            return {"FINISHED"}
        if event.type == "LEFTMOUSE":
            self._pressed = event.value == "PRESS"
            if self._pressed:
                self._paint(context, event)
            return {"RUNNING_MODAL"}
        if event.type == "MOUSEMOVE" and self._pressed:
            self._paint(context, event)
            return {"RUNNING_MODAL"}
        return {"PASS_THROUGH"}

    def _paint(self, context, event):
        hit = pick(context, event)
        if hit is None:
            return
        p, n, d = hit
        LINK.send({"type": "lightpaint", "host": "blender", "point": to_internal(p),
                   "normal": to_internal(n), "view": to_internal(d)})


class HDRISTUDIO_OT_reload(bpy.types.Operator):
    bl_idname = "hdri_studio.reload"
    bl_label = "Reload textures"
    bl_description = "Reload every EXR/HDR image in the scene"

    def execute(self, context):
        n = reload_all()
        self.report({"INFO"}, "HDRI Studio: %d images reloaded" % n)
        return {"FINISHED"}


class HDRISTUDIO_PT_panel(bpy.types.Panel):
    bl_label = "HDRI Studio"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "HDRI Studio"

    def draw(self, context):
        col = self.layout.column()
        col.label(text=("Connected to the app" if LINK.connected else "App not connected (using file timestamps)"),
                  icon="LINKED" if LINK.connected else "UNLINKED")
        if _state["last_msg"]:
            col.label(text=_state["last_msg"])
        col.operator("hdri_studio.lightpaint", icon="BRUSH_DATA",
                     text="LightPaint (active)" if _state["lightpaint"] else "LightPaint")
        col.operator("hdri_studio.reload", icon="FILE_REFRESH")
        col.prop(context.scene, "hdri_studio_visible_camera")


classes = (HDRISTUDIO_OT_lightpaint, HDRISTUDIO_OT_reload, HDRISTUDIO_PT_panel)


def register():
    for c in classes:
        bpy.utils.register_class(c)
    bpy.types.Scene.hdri_studio_visible_camera = bpy.props.BoolProperty(
        name="Separate lights visible to camera", default=True,
        update=lambda self, ctx: _apply_visibility())
    if not bpy.app.timers.is_registered(tick):
        bpy.app.timers.register(tick, first_interval=TIMER_S, persistent=True)
    print("[hdri-studio] add-on %s loaded from %s (port %d)" % (ADDON_VERSION, os.path.dirname(__file__), link_core.DEFAULT_PORT))


def _apply_visibility():
    vis = bpy.context.scene.hdri_studio_visible_camera
    col = bpy.data.collections.get(COLLECTION)
    if col:
        for o in col.objects:
            if o.name.startswith(LIGHT_PREFIX):
                o.visible_camera = vis


def unregister():
    if bpy.app.timers.is_registered(tick):
        bpy.app.timers.unregister(tick)
    LINK.close()
    del bpy.types.Scene.hdri_studio_visible_camera
    for c in reversed(classes):
        bpy.utils.unregister_class(c)
