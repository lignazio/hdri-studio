class_name Preview3D
extends SubViewportContainer
## Viewport 3D: sky dalla texture baked, sfera cromata esatta, glossy, diffusa.
## Trascina = orbita · rotella = zoom · Shift + trascina su una sfera = LightPaint:
## la luce selezionata si sposta dove serve per riflettersi sotto il cursore.

signal paint(direction: Vector3, commit: bool)
## Una voce del catalogo è stata lasciata sul preview: direction è il riflesso nel punto colpito,
## oppure Vector3.ZERO se non ha colpito nulla.
signal light_dropped(path: String, defaults: Dictionary, direction: Vector3)
## Click (senza trascinare) su una sfera o sul modello: direzione riflessa, per selezionare la luce.
signal pick(direction: Vector3)

const SPHERE_R := 1.0
const SPHERE_POS := [Vector3(-2.6, 0, 0), Vector3(0, 0, 0), Vector3(2.6, 0, 0)]
## Raggio della sfera in cui viene inscritto il modello caricato.
const MODEL_R := 1.3

enum ModelMaterial { ORIGINAL, CHROME, GLOSSY, DIFFUSE, GOLD, WHITE_GOLD, SILVER, PLATINUM, COPPER, BRUSHED, GLASS }
const MATERIAL_LABELS := ["Originale", "Cromato", "Glossy", "Diffuso", "Oro giallo", "Oro bianco", "Argento", "Platino", "Rame", "Spazzolato", "Vetro"]
## Riflettanza dei metalli lucidi (F0 lineare, valori tipici PBR).
const METAL_F0 := {
	ModelMaterial.GOLD: Color(1.0, 0.71, 0.29),
	ModelMaterial.WHITE_GOLD: Color(0.9, 0.87, 0.78),
	ModelMaterial.SILVER: Color(0.95, 0.93, 0.88),
	ModelMaterial.PLATINUM: Color(0.83, 0.81, 0.78),
	ModelMaterial.COPPER: Color(0.95, 0.64, 0.54),
}

var viewport: SubViewport
var camera: Camera3D
var env: Environment
var model_path := ""
var _sky_mats: Array[PanoramaSkyMaterial] = []
var _sky_flip := 0
var _chrome: ShaderMaterial
var _glossy: StandardMaterial3D
var _diffuse: StandardMaterial3D
var _metal_mats := {}
var _brushed: StandardMaterial3D
var _glass: StandardMaterial3D
var _spheres: Array[MeshInstance3D] = []
var _model_root: Node3D
var _model_meshes: Array[MeshInstance3D] = []
var _model_material := ModelMaterial.ORIGINAL
var _yaw := 0.35
var _pitch := 0.18
var _dist := 7.0
var _orbiting := false
var _painting := false
var _tumbling := false
var _press_pos := Vector2.ZERO
var _moved := false
var _model_yaw := 0.0
var _model_pitch := 0.0
var _model_scale := 1.0


func _init() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	add_child(viewport)


func setup(tex: Texture2D) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Due materiali identici alternati a ogni bake: il cielo rigenera la mappa di radianza (riflessi
	# glossy e luce diffusa) solo quando gli viene assegnato un materiale, non quando cambia il
	# contenuto della texture sul GPU.
	for i in 2:
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = tex
		mat.filter = true
		_sky_mats.append(mat)
	sky.sky_material = _sky_mats[0]
	sky.radiance_size = Sky.RADIANCE_SIZE_1024
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)

	var mesh := SphereMesh.new()
	mesh.radius = SPHERE_R
	mesh.height = SPHERE_R * 2.0
	mesh.radial_segments = 128
	mesh.rings = 64
	_chrome = ShaderMaterial.new()
	_chrome.shader = load("res://preview/chrome.gdshader")
	_chrome.set_shader_parameter("panorama", tex)
	_glossy = StandardMaterial3D.new()
	_glossy.albedo_color = Color(0.9, 0.9, 0.9)
	_glossy.metallic = 1.0
	_glossy.roughness = 0.35
	_diffuse = StandardMaterial3D.new()
	_diffuse.albedo_color = Color(0.8, 0.8, 0.8)
	_diffuse.roughness = 1.0
	# metalli lucidi: riflessi esatti dalla panoramica, tinti con la riflettanza del metallo
	for m in METAL_F0:
		var mm := ShaderMaterial.new()
		mm.shader = _chrome.shader
		mm.set_shader_parameter("panorama", tex)
		mm.set_shader_parameter("tint", METAL_F0[m])
		_metal_mats[m] = mm
	_brushed = StandardMaterial3D.new()
	_brushed.albedo_color = Color(0.9, 0.88, 0.84)
	_brushed.metallic = 1.0
	_brushed.roughness = 0.4
	_brushed.anisotropy_enabled = true
	_brushed.anisotropy = 0.85
	_glass = StandardMaterial3D.new()
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.albedo_color = Color(1.0, 1.0, 1.0, 0.08)
	_glass.metallic = 0.0
	_glass.roughness = 0.02
	_glass.metallic_specular = 0.6
	_glass.refraction_enabled = true
	_glass.refraction_scale = 0.04
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mats := [_chrome, _glossy, _diffuse]
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mats[i]
		mi.position = SPHERE_POS[i]
		viewport.add_child(mi)
		_spheres.append(mi)
	_model_root = Node3D.new()
	viewport.add_child(_model_root)

	camera = Camera3D.new()
	camera.fov = 35.0
	viewport.add_child(camera)
	_update_camera()


func set_texture(tex: Texture2D) -> void:
	for m in _sky_mats:
		m.panorama = tex
	_chrome.set_shader_parameter("panorama", tex)
	for mm in _metal_mats.values():
		mm.set_shader_parameter("panorama", tex)
	notify_sky_changed()


## La texture del cielo è cambiata sul GPU (nuovo bake): fa rigenerare la mappa di radianza.
func notify_sky_changed() -> void:
	_sky_flip = 1 - _sky_flip
	env.sky.sky_material = _sky_mats[_sky_flip]


func set_exposure(k: float) -> void:
	env.tonemap_exposure = k


func set_fov(deg: float) -> void:
	camera.fov = deg


## Punto di vista dal software 3D: direzione di vista e alto (coordinate interne), FOV orizzontale.
## Usa solo la direzione: la camera del preview resta alla distanza corrente dal centro.
func set_view_from_host(forward: Vector3, up: Vector3, fov_h_deg: float) -> void:
	if forward.length() < 1e-6:
		return
	var f := forward.normalized()
	var pos := -f * _dist
	camera.look_at_from_position(pos, Vector3.ZERO, up.normalized() if up.length() > 1e-6 else Vector3.UP)
	# Godot usa il FOV verticale: converto dall'orizzontale con l'aspetto del viewport
	var aspect := float(viewport.size.x) / maxf(float(viewport.size.y), 1.0)
	var fov_v := rad_to_deg(2.0 * atan(tan(deg_to_rad(fov_h_deg) * 0.5) / aspect))
	camera.fov = clampf(fov_v, 5.0, 150.0)
	# tiene coerenti yaw/pitch dell'orbita con la nuova posizione
	_yaw = atan2(pos.x, pos.z)
	_pitch = -asin(clampf(pos.y / _dist, -1.0, 1.0))


func set_clipping(on: bool, threshold: float) -> void:
	_chrome.set_shader_parameter("clip_threshold", threshold if on else -1.0)
	for mm in _metal_mats.values():
		mm.set_shader_parameter("clip_threshold", threshold if on else -1.0)


## Materiale della sfera centrale (quando non c'è un modello): stessi preset del modello.
func set_center_sphere_material(mode: ModelMaterial) -> void:
	var prev := _model_material
	_model_material = mode
	var mat: Material = _glossy
	match mode:
		ModelMaterial.CHROME: mat = _chrome
		ModelMaterial.DIFFUSE: mat = _diffuse
		ModelMaterial.BRUSHED: mat = _brushed
		ModelMaterial.GLASS: mat = _glass
		_:
			if _metal_mats.has(mode):
				mat = _metal_mats[mode]
	_spheres[1].material_override = mat
	_model_material = prev


func set_model_scale(s: float) -> void:
	_model_scale = s
	_apply_model_transform()


func _apply_model_transform() -> void:
	_model_root.transform = Transform3D(Basis.from_euler(Vector3(_model_pitch, _model_yaw, 0.0)).scaled(Vector3.ONE * _model_scale), Vector3.ZERO)


# --- modello -------------------------------------------------------------------------------------

## Carica un GLB/GLTF al posto della sfera centrale, lo centra e lo scala dentro MODEL_R,
## e gli aggiunge collisioni trimesh per il LightPaint.
func load_model(path: String) -> bool:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(path, state)
	if err != OK:
		push_warning("Modello non caricabile: %s (%s)" % [path, error_string(err)])
		return false
	var scene := gltf.generate_scene(state)
	if scene == null:
		return false
	clear_model()
	_model_root.add_child(scene)
	_model_meshes.clear()
	_collect_meshes(scene)
	if _model_meshes.is_empty():
		clear_model()
		return false
	# bounding box in coordinate del modello
	var aabb := AABB()
	var first := true
	for mi in _model_meshes:
		var b: AABB = mi.global_transform * mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var radius := maxf(aabb.size.length() * 0.5, 1e-4)
	var s := MODEL_R / radius
	scene.scale = Vector3.ONE * s
	scene.position = -aabb.get_center() * s
	for mi in _model_meshes:
		mi.create_trimesh_collision()
	model_path = path
	_spheres[1].visible = false
	set_model_material(_model_material)
	return true


func clear_model() -> void:
	for c in _model_root.get_children():
		c.queue_free()
	_model_meshes.clear()
	model_path = ""
	_spheres[1].visible = true


func has_model() -> bool:
	return not _model_meshes.is_empty()


func set_model_material(mode: ModelMaterial) -> void:
	_model_material = mode
	var mat: Material = null
	match mode:
		ModelMaterial.CHROME:
			mat = _chrome
		ModelMaterial.GLOSSY:
			mat = _glossy
		ModelMaterial.DIFFUSE:
			mat = _diffuse
		ModelMaterial.BRUSHED:
			mat = _brushed
		ModelMaterial.GLASS:
			mat = _glass
		_:
			if _metal_mats.has(mode):
				mat = _metal_mats[mode]
	for mi in _model_meshes:
		mi.material_override = mat


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		_model_meshes.append(n)
	for c in n.get_children():
		_collect_meshes(c)


func _update_camera() -> void:
	var p := Vector3(0, 0, _dist).rotated(Vector3.RIGHT, -_pitch).rotated(Vector3.UP, _yaw)
	camera.look_at_from_position(p, Vector3.ZERO, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press_pos = event.position
					_moved = false
					if event.shift_pressed and _try_paint(event.position, false):
						_painting = true
					else:
						_orbiting = true
				else:
					if _painting:
						_try_paint(event.position, true)
					elif _orbiting and not _moved:
						var r := _hit_reflection(event.position)
						if r != Vector3.ZERO:
							pick.emit(r)
					_painting = false
					_orbiting = false
				accept_event()
			MOUSE_BUTTON_RIGHT:
				_tumbling = event.pressed and has_model()
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(2.5, _dist * 0.9)
				_update_camera()
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(30.0, _dist / 0.9)
				_update_camera()
				accept_event()
	elif event is InputEventMouseMotion:
		if event.position.distance_to(_press_pos) > 4.0:
			_moved = true
		if _painting:
			_try_paint(event.position, false)
			accept_event()
		elif _orbiting and _moved:
			_yaw -= event.relative.x * 0.005
			_pitch = clampf(_pitch + event.relative.y * 0.005, -1.4, 1.4)
			_update_camera()
			accept_event()
		elif _tumbling:
			_model_yaw += event.relative.x * 0.01
			_model_pitch = clampf(_model_pitch + event.relative.y * 0.01, -PI, PI)
			_apply_model_transform()
			accept_event()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == "catalog_light"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	light_dropped.emit(data["path"], data["defaults"], reflection_at(at_position))


## Direzione riflessa nel punto sotto il cursore (modello o sfere), Vector3.ZERO se nulla.
func reflection_at(pos: Vector2) -> Vector3:
	var r := _hit_reflection(pos)
	return r


## Raggio dal cursore → modello (raycast fisico) o sfera più vicina → direzione riflessa.
## Restituisce false se non colpisce nulla.
func _try_paint(pos: Vector2, commit: bool) -> bool:
	var r := _hit_reflection(pos)
	if r == Vector3.ZERO:
		return false
	paint.emit(r, commit)
	return true


func _hit_reflection(pos: Vector2) -> Vector3:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	var best_t := INF
	var best_n := Vector3.ZERO
	if has_model():
		var space := viewport.find_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + d * 200.0))
		if not hit.is_empty():
			best_t = (hit["position"] - o).length()
			best_n = hit["normal"]
	for i in SPHERE_POS.size():
		if not _spheres[i].visible:
			continue
		var c: Vector3 = SPHERE_POS[i]
		var oc: Vector3 = o - c
		var b := oc.dot(d)
		var disc := b * b - (oc.dot(oc) - SPHERE_R * SPHERE_R)
		if disc < 0.0:
			continue
		var t := -b - sqrt(disc)
		if t > 0.0 and t < best_t:
			best_t = t
			best_n = (o + d * t - c).normalized()
	if best_t == INF:
		return Vector3.ZERO
	# Riflessione GLSL: r = d - 2 (d·n) n (Vector3.reflect ha il segno opposto)
	return d - 2.0 * d.dot(best_n) * best_n
