class_name Preview3D
extends SubViewportContainer
## Viewport 3D: sky dalla texture baked, sfera cromata esatta, glossy, diffusa.
## Trascina = orbita · rotella = zoom · Shift + trascina su una sfera = LightPaint:
## la luce selezionata si sposta dove serve per riflettersi sotto il cursore.

signal paint(direction: Vector3, commit: bool)

const SPHERE_R := 1.0
const SPHERE_POS := [Vector3(-2.6, 0, 0), Vector3(0, 0, 0), Vector3(2.6, 0, 0)]

var viewport: SubViewport
var camera: Camera3D
var env: Environment
var _chrome: ShaderMaterial
var _yaw := 0.35
var _pitch := 0.18
var _dist := 7.0
var _orbiting := false
var _painting := false


func _init() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	add_child(viewport)


func setup(tex: Texture2D) -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = tex
	mat.filter = true
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
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
	mesh.radial_segments = 96
	mesh.rings = 48
	_chrome = ShaderMaterial.new()
	_chrome.shader = load("res://preview/chrome.gdshader")
	_chrome.set_shader_parameter("panorama", tex)
	var glossy := StandardMaterial3D.new()
	glossy.albedo_color = Color(0.9, 0.9, 0.9)
	glossy.metallic = 1.0
	glossy.roughness = 0.35
	var diffuse := StandardMaterial3D.new()
	diffuse.albedo_color = Color(0.8, 0.8, 0.8)
	diffuse.roughness = 1.0
	var mats := [_chrome, glossy, diffuse]
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mats[i]
		mi.position = SPHERE_POS[i]
		viewport.add_child(mi)

	camera = Camera3D.new()
	camera.fov = 35.0
	viewport.add_child(camera)
	_update_camera()


func set_texture(tex: Texture2D) -> void:
	(env.sky.sky_material as PanoramaSkyMaterial).panorama = tex
	_chrome.set_shader_parameter("panorama", tex)


func set_exposure(k: float) -> void:
	env.tonemap_exposure = k


func _update_camera() -> void:
	var p := Vector3(0, 0, _dist).rotated(Vector3.RIGHT, -_pitch).rotated(Vector3.UP, _yaw)
	camera.look_at_from_position(p, Vector3.ZERO, Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					if event.shift_pressed and _try_paint(event.position, false):
						_painting = true
					else:
						_orbiting = true
				else:
					if _painting:
						_try_paint(event.position, true)
					_painting = false
					_orbiting = false
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
		if _painting:
			_try_paint(event.position, false)
			accept_event()
		elif _orbiting:
			_yaw -= event.relative.x * 0.005
			_pitch = clampf(_pitch + event.relative.y * 0.005, -1.4, 1.4)
			_update_camera()
			accept_event()


## Raggio dal cursore → sfera più vicina → direzione riflessa. Restituisce false se non colpisce nulla.
func _try_paint(pos: Vector2, commit: bool) -> bool:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	var best_t := INF
	var best_n := Vector3.ZERO
	for c in SPHERE_POS:
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
		return false
	# Riflessione GLSL: r = d - 2 (d·n) n (Vector3.reflect ha il segno opposto)
	paint.emit(d - 2.0 * d.dot(best_n) * best_n, commit)
	return true
