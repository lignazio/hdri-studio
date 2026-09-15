"""Fase 0 — verifica fisica degli EXR con Blender/Cycles.

Uso:  Blender -b --python tools/blender_verify.py -- <cartella out>

1. furnace.exr: legge il pixel centrale (deve essere 1.0) e renderizza una sfera diffusa bianca
   in quel world: il pixel centrale del render deve essere 1.0.
2. calibration.exr: sonda le sei direzioni degli assi di Blender e ricava la matrice che porta
   dalla convenzione interna di HDRI Studio a quella di Blender.
3. rect.exr: integra numericamente l'irradianza sul piano che guarda la luce, poi renderizza
   quel piano (albedo 1) in Cycles: il pixel deve valere E / pi.
"""
import sys, os, math
import bpy
import numpy as np
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "out"
OUT = os.path.abspath(OUT)
TMP = os.path.join(OUT, "_blender")
os.makedirs(TMP, exist_ok=True)


def log(*a):
    print("[verify]", *a, flush=True)


def load_img(name):
    img = bpy.data.images.load(os.path.join(OUT, name), check_existing=False)
    return img


def pixels(img):
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    return a[::-1]  # riga 0 = alto, come nel bake


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 256
    sc.cycles.use_denoising = False
    sc.render.resolution_x = 32
    sc.render.resolution_y = 32
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.render.image_settings.color_depth = "32"
    sc.render.image_settings.color_mode = "RGB"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.film_transparent = False
    return sc


def set_world(img):
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = img
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])
    bpy.context.scene.world = world


def white_diffuse():
    m = bpy.data.materials.new("white")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    d = nt.nodes.new("ShaderNodeBsdfDiffuse")
    d.inputs["Color"].default_value = (1, 1, 1, 1)
    d.inputs["Roughness"].default_value = 0.0
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(d.outputs["BSDF"], o.inputs["Surface"])
    return m


def add_camera(location, direction, ortho=False, fov_deg=5.0):
    cam_data = bpy.data.cameras.new("cam")
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = 0.05
    else:
        cam_data.lens_unit = "FOV"
        cam_data.angle = math.radians(fov_deg)
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(location)
    cam.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    return cam


def render_center(name):
    path = os.path.join(TMP, name + ".exr")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path, check_existing=False)
    p = pixels(img)
    h, w = p.shape[:2]
    c = p[h // 2 - 2:h // 2 + 2, w // 2 - 2:w // 2 + 2, :3].mean(axis=(0, 1))
    return c


# --- convenzione interna --------------------------------------------------------------------

def dir_internal(az_deg, el_deg):
    az, el = math.radians(az_deg), math.radians(el_deg)
    c = math.cos(el)
    return np.array([-c * math.sin(az), math.sin(el), c * math.cos(az)])


def dirs_from_image(w, h):
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    phi = (u - 0.5) * 2 * np.pi
    theta = (0.5 - v) * np.pi
    P, T = np.meshgrid(phi, theta)
    c = np.cos(T)
    d = np.stack([-c * np.sin(P), np.sin(T), c * np.cos(P)], axis=-1)
    domega = (2 * np.pi / w) * (np.pi / h) * c
    return d, domega


# --- 1. furnace -----------------------------------------------------------------------------

def test_furnace():
    sc = reset_scene()
    img = load_img("furnace.exr")
    p = pixels(img)
    log("furnace.exr size", img.size, "pixel centrale", p[p.shape[0] // 2, p.shape[1] // 2, :3],
        "min", p[..., :3].min(), "max", p[..., :3].max())
    set_world(img)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, segments=64, ring_count=32)
    sph = bpy.context.active_object
    sph.data.materials.append(white_diffuse())
    bpy.ops.object.shade_smooth()
    add_camera((0, -5, 0), (0, 1, 0), ortho=True)
    c = render_center("furnace")
    log("FURNACE  sfera diffusa bianca in ambiente 1.0 → render", c, "atteso 1.0")
    return c


# --- 2. calibrazione orientamento -------------------------------------------------------------

MARKERS = {
    "+X": (1.0, 0.0, 0.0), "-X": (0.25, 0.0, 0.0),
    "+Y": (0.0, 1.0, 0.0), "-Y": (0.0, 0.25, 0.0),
    "+Z": (0.0, 0.0, 1.0), "-Z": (0.0, 0.0, 0.25),
}
AXES = {"+X": (1, 0, 0), "-X": (-1, 0, 0), "+Y": (0, 1, 0), "-Y": (0, -1, 0), "+Z": (0, 0, 1), "-Z": (0, 0, -1)}


def nearest_marker(c):
    best, bd = None, 1e9
    for k, m in MARKERS.items():
        d = np.linalg.norm(np.array(c) - np.array(m))
        if d < bd:
            best, bd = k, d
    return best, bd


def test_calibration():
    sc = reset_scene()
    sc.cycles.samples = 16
    img = load_img("calibration.exr")
    set_world(img)
    mapping = {}
    for bl_axis, d in AXES.items():
        for o in list(bpy.data.objects):
            bpy.data.objects.remove(o)
        add_camera((0, 0, 0), d, fov_deg=4.0)
        c = render_center("calib_" + bl_axis.replace("+", "p").replace("-", "m"))
        k, dist = nearest_marker(c)
        mapping[bl_axis] = k
        log("CALIB  Blender %s guarda → colore %s → marker interno %s (dist %.3f)" % (bl_axis, np.round(c, 3), k, dist))
    # matrice M tale che d_blender = M · d_interno: colonna j = dove finisce l'asse interno j
    M = np.zeros((3, 3))
    for bl_axis, internal in mapping.items():
        sign_b = 1 if bl_axis[0] == "+" else -1
        ib = "XYZ".index(bl_axis[1])
        sign_i = 1 if internal[0] == "+" else -1
        ii = "XYZ".index(internal[1])
        M[ib, ii] = sign_b * sign_i
    log("CALIB  matrice interno→Blender:\n" + str(M) + "\n  det = %.0f" % np.linalg.det(M))
    return M


# --- 3. singola luce --------------------------------------------------------------------------

def test_single_light(M):
    sc = reset_scene()
    img = load_img("rect.exr")
    p = pixels(img)[..., :3]
    h, w = p.shape[:2]
    d, dom = dirs_from_image(w, h)
    F = dir_internal(45.0, 30.0)  # stesso az/el del rig 'rect' nello spike
    cosT = np.clip(d @ F, 0, None)
    L = p.mean(axis=-1)
    E = float((L * cosT * dom).sum())
    omega = float(((L > 0) * dom).sum())
    log("RECT   dall'EXR: angolo solido %.4f sr, radianza max %.2f, irradianza sul piano E = %.4f → E/pi = %.4f"
        % (omega, L.max(), E, E / math.pi))
    # angolo solido teorico del quadrilatero sferico 30°x20° (integrazione fine, indipendente dall'EXR)
    W2, H2 = 8192, 4096
    d2, dom2 = dirs_from_image(W2, H2)
    R = np.array([-1.0, 0, 0]); U = np.array([0, 1.0, 0])
    # frame della luce come nello shader
    up = np.array([0, 1.0, 0]); R = np.cross(F, up); R /= np.linalg.norm(R); U = np.cross(R, F)
    ax = np.arctan2(d2 @ R, d2 @ F); ay = np.arctan2(d2 @ U, d2 @ F)
    inside = (np.abs(ax) < math.radians(15)) & (np.abs(ay) < math.radians(10))
    omega_t = float((inside * dom2).sum())
    E_t = 10.0 * float((inside * np.clip(d2 @ F, 0, None) * dom2).sum())
    log("RECT   teorico:  angolo solido %.4f sr, E = %.4f → E/pi = %.4f" % (omega_t, E_t, E_t / math.pi))

    set_world(img)
    Fb = M @ F
    bpy.ops.mesh.primitive_plane_add(size=1.0)
    plane = bpy.context.active_object
    plane.rotation_euler = Vector(Fb).to_track_quat("Z", "Y").to_euler()
    plane.data.materials.append(white_diffuse())
    add_camera(Vector(Fb) * 2.0, -Vector(Fb), ortho=True)
    c = render_center("rect")
    log("RECT   render Cycles del piano (albedo 1) rivolto alla luce:", np.round(c, 4), "atteso %.4f" % (E / math.pi))
    return c


if __name__ == "__main__":
    log("Blender", bpy.app.version_string, "| out:", OUT)
    test_furnace()
    M = test_calibration()
    test_single_light(M)
    log("fine")
