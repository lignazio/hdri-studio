class_name GradientEditor
extends VBoxContainer
## Editor delle tacche di un gradiente: barra con anteprima, maniglie trascinabili, click sulla barra
## aggiunge una tacca (con il colore interpolato lì), tasto destro o Canc la toglie, colore per tacca.

signal changed(commit: bool)

const BAR_H := 26.0
const HANDLE_H := 12.0
const PICK_PX := 8.0

var light: RigLight
var _bar: Control
var _selected := -1
var _dragging := false
var _color: ColorPickerButton
var _pos_row: ParamRow
var _syncing := false


func _init() -> void:
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, BAR_H + HANDLE_H + 6)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.focus_mode = Control.FOCUS_CLICK
	_bar.draw.connect(_draw_bar)
	_bar.gui_input.connect(_bar_input)
	add_child(_bar)
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = "Tacca"
	l.custom_minimum_size.x = 96
	row.add_child(l)
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color.color_changed.connect(func(c: Color) -> void: _set_color(c, false))
	_color.popup_closed.connect(func() -> void: changed.emit(true))
	row.add_child(_color)
	var inv := Button.new()
	inv.text = "Inverti"
	inv.tooltip_text = "Specchia le tacche (0 ↔ 1)"
	inv.pressed.connect(_invert)
	row.add_child(inv)
	_pos_row = ParamRow.new("Posizione", 0.0, 1.0, 0.001)
	_pos_row.value_changed.connect(func(v: float) -> void: _set_pos(v, false))
	_pos_row.committed.connect(func() -> void: _sort_keep_selection(); changed.emit(true))
	add_child(_pos_row)
	var hint := Label.new()
	hint.text = "click sulla barra: nuova tacca · trascina: sposta · tasto destro / Canc: elimina"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.5)
	add_child(hint)


func set_light(l: RigLight) -> void:
	light = l
	_selected = clampi(_selected, -1, l.gradient_stops.size() - 1) if l != null else -1
	if light != null and _selected < 0 and not light.gradient_stops.is_empty():
		_selected = 0
	_sync_controls()
	_bar.queue_redraw()


func _stops() -> Array:
	return light.gradient_stops if light != null else []


func _sync_controls() -> void:
	_syncing = true
	var has := light != null and _selected >= 0 and _selected < _stops().size()
	_color.disabled = not has
	_pos_row.visible = has
	if has:
		var s: Array = _stops()[_selected]
		_color.color = Color(s[1], s[2], s[3])
		_pos_row.set_value_silent(s[0])
	_syncing = false


# --- disegno ---------------------------------------------------------------------------------------

func _bar_rect() -> Rect2:
	return Rect2(4, 2, _bar.size.x - 8, BAR_H)


func _draw_bar() -> void:
	var r := _bar_rect()
	_bar.draw_rect(Rect2(r.position - Vector2(1, 1), r.size + Vector2(2, 2)), Color(0, 0, 0, 0.6))
	if light == null:
		return
	var n := maxi(int(r.size.x / 2.0), 2)
	for i in n:
		var t := float(i) / float(n - 1)
		var c := light.gradient_color(t)
		c = Color(_srgb(c.r), _srgb(c.g), _srgb(c.b))
		var x := r.position.x + r.size.x * float(i) / float(n)
		_bar.draw_rect(Rect2(x, r.position.y, r.size.x / float(n) + 1.0, r.size.y), c)
	var stops := _stops()
	for k in stops.size():
		var s: Array = stops[k]
		var x := r.position.x + r.size.x * float(s[0])
		var y := r.end.y + 2
		var col := Color(1.0, 0.8, 0.2) if k == _selected else Color(1, 1, 1)
		var tri := PackedVector2Array([Vector2(x, y), Vector2(x - 6, y + HANDLE_H), Vector2(x + 6, y + HANDLE_H)])
		_bar.draw_colored_polygon(tri, Color(0, 0, 0, 0.7))
		_bar.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), col, 1.5)
		_bar.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(col, 0.5), 1.0)


static func _srgb(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


# --- input ---------------------------------------------------------------------------------------

func _pick(px: float) -> int:
	var r := _bar_rect()
	var best := -1
	var bd := PICK_PX
	var stops := _stops()
	for k in stops.size():
		var x: float = r.position.x + r.size.x * float(stops[k][0])
		var d := absf(px - x)
		if d < bd:
			bd = d
			best = k
	return best


func _bar_input(ev: InputEvent) -> void:
	if light == null:
		return
	if ev is InputEventMouseButton and ev.pressed:
		_bar.grab_focus()
		var r := _bar_rect()
		var k := _pick(ev.position.x)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if k >= 0:
				_selected = k
				_dragging = true
			elif r.grow(4).has_point(ev.position):
				var t := clampf((ev.position.x - r.position.x) / r.size.x, 0.0, 1.0)
				var c := light.gradient_color(t)
				light.gradient_stops.append([t, c.r, c.g, c.b])
				_sort_stops()
				_selected = _index_at(t)
				_dragging = true
				changed.emit(false)
			_sync_controls()
			_bar.queue_redraw()
			_bar.accept_event()
		elif ev.button_index == MOUSE_BUTTON_RIGHT and k >= 0:
			_remove(k)
			_bar.accept_event()
	elif ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and _dragging:
		_dragging = false
		_sort_keep_selection()
		changed.emit(true)
		_bar.accept_event()
	elif ev is InputEventMouseMotion and _dragging and _selected >= 0:
		var r := _bar_rect()
		var t := clampf((ev.position.x - r.position.x) / r.size.x, 0.0, 1.0)
		light.gradient_stops[_selected][0] = t
		_sync_controls()
		_bar.queue_redraw()
		changed.emit(false)
		_bar.accept_event()
	elif ev is InputEventKey and ev.pressed and (ev.keycode == KEY_DELETE or ev.keycode == KEY_BACKSPACE) and _selected >= 0:
		_remove(_selected)
		_bar.accept_event()


func _remove(k: int) -> void:
	if _stops().size() <= 1:
		return
	light.gradient_stops.remove_at(k)
	_selected = clampi(_selected - (1 if k <= _selected else 0), 0, _stops().size() - 1)
	_sync_controls()
	_bar.queue_redraw()
	changed.emit(true)


func _set_color(c: Color, commit: bool) -> void:
	if _syncing or _selected < 0:
		return
	var s: Array = light.gradient_stops[_selected]
	s[1] = c.r
	s[2] = c.g
	s[3] = c.b
	_bar.queue_redraw()
	changed.emit(commit)


func _set_pos(v: float, commit: bool) -> void:
	if _syncing or _selected < 0:
		return
	light.gradient_stops[_selected][0] = v
	_bar.queue_redraw()
	changed.emit(commit)


func _invert() -> void:
	for s in light.gradient_stops:
		s[0] = 1.0 - s[0]
	_sort_keep_selection()
	changed.emit(true)


func _sort_stops() -> void:
	light.gradient_stops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _index_at(t: float) -> int:
	var stops := _stops()
	for k in stops.size():
		if is_equal_approx(stops[k][0], t):
			return k
	return stops.size() - 1


func _sort_keep_selection() -> void:
	var sel: Array = light.gradient_stops[_selected] if _selected >= 0 else []
	_sort_stops()
	if not sel.is_empty():
		_selected = light.gradient_stops.find(sel)
	_sync_controls()
	_bar.queue_redraw()
