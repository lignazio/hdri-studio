class_name MapView
extends Control
## Mappa equirettangolare con le maniglie delle luci: click seleziona, drag sposta azimut/elevazione.

signal light_selected(index: int)
signal light_moved(index: int, azimuth: float, elevation: float, commit: bool)

const HANDLE_R := 7.0
const PICK_R := 14.0

var rig: LightRig
var selected := -1
var _tex_rect: TextureRect
var _overlay: Control
var _dragging := -1
var _map_mat: ShaderMaterial


func _init() -> void:
	custom_minimum_size = Vector2(400, 200)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tex_rect = TextureRect.new()
	_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_mat = ShaderMaterial.new()
	_map_mat.shader = load("res://preview/map_view.gdshader")
	_tex_rect.material = _map_mat
	add_child(_tex_rect)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func set_texture(tex: Texture2D) -> void:
	_tex_rect.texture = tex


func set_exposure(k: float) -> void:
	_map_mat.set_shader_parameter("exposure", k)


func set_rig(r: LightRig) -> void:
	rig = r
	refresh()


func set_selected(i: int) -> void:
	selected = i
	refresh()


func refresh() -> void:
	_overlay.queue_redraw()


## Rettangolo effettivo della mappa (aspetto 2:1 centrato).
func _map_rect() -> Rect2:
	var s := size
	var w := s.x
	var h := w * 0.5
	if h > s.y:
		h = s.y
		w = h * 2.0
	return Rect2((s.x - w) * 0.5, (s.y - h) * 0.5, w, h)


func _uv_to_pos(uv: Vector2) -> Vector2:
	var r := _map_rect()
	return r.position + uv * r.size


func _pos_to_uv(p: Vector2) -> Vector2:
	var r := _map_rect()
	return (p - r.position) / r.size


static func light_uv(l: RigLight) -> Vector2:
	return Vector2(l.azimuth / 360.0 + 0.5, 0.5 - l.elevation / 180.0)


func _draw_overlay() -> void:
	if rig == null:
		return
	var r := _map_rect()
	_overlay.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
	# meridiano e orizzonte
	_overlay.draw_line(r.position + Vector2(r.size.x * 0.5, 0), r.position + Vector2(r.size.x * 0.5, r.size.y), Color(1, 1, 1, 0.12))
	_overlay.draw_line(r.position + Vector2(0, r.size.y * 0.5), r.position + Vector2(r.size.x, r.size.y * 0.5), Color(1, 1, 1, 0.12))
	var font := get_theme_default_font()
	for i in rig.lights.size():
		var l: RigLight = rig.lights[i]
		var p := _uv_to_pos(light_uv(l))
		var col := Color(1.0, 0.8, 0.2) if i == selected else Color(1, 1, 1, 0.85)
		if not l.enabled:
			col.a = 0.35
		_overlay.draw_circle(p, HANDLE_R + 1.5, Color(0, 0, 0, 0.6))
		_overlay.draw_arc(p, HANDLE_R, 0.0, TAU, 24, col, 2.0)
		if i == selected:
			_overlay.draw_circle(p, 2.5, col)
		_overlay.draw_string_outline(font, p + Vector2(HANDLE_R + 4, 4), l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8))
		_overlay.draw_string(font, p + Vector2(HANDLE_R + 4, 4), l.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _pick(p: Vector2) -> int:
	if rig == null:
		return -1
	var best := -1
	var bd := PICK_R
	for i in rig.lights.size():
		var d := p.distance_to(_uv_to_pos(light_uv(rig.lights[i])))
		if d < bd:
			bd = d
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var i := _pick(event.position)
			if i >= 0:
				_dragging = i
				if i != selected:
					light_selected.emit(i)
			elif selected >= 0 and _map_rect().has_point(event.position):
				# click sul vuoto: sposta la luce selezionata lì
				_dragging = selected
				_move_to(event.position, false)
			accept_event()
		elif _dragging >= 0:
			_move_to(event.position, true)
			_dragging = -1
			accept_event()
	elif event is InputEventMouseMotion and _dragging >= 0:
		_move_to(event.position, false)
		accept_event()


func _move_to(p: Vector2, commit: bool) -> void:
	var uv := _pos_to_uv(p)
	uv.x = wrapf(uv.x, 0.0, 1.0)
	uv.y = clampf(uv.y, 0.0, 1.0)
	var az := (uv.x - 0.5) * 360.0
	var el := (0.5 - uv.y) * 180.0
	light_moved.emit(_dragging, az, el, commit)
