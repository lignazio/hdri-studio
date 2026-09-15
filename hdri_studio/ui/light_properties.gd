class_name LightProperties
extends ScrollContainer
## Pannello proprietà della luce selezionata.

## commit = true quando il valore è definitivo (fine drag, spinbox, opzioni): momento dello snapshot di undo.
signal changed(commit: bool)
signal light_renamed()
## L'utente vuole cambiare l'immagine della luce Texture (main apre la dialog).
signal texture_pick_requested()

var light: RigLight
var _box: VBoxContainer
var _syncing := false

var _name: LineEdit
var _enabled: CheckBox
var _solo: CheckBox
var _shape: OptionButton
var _rows := {}
var _falloff: OptionButton
var _blend: OptionButton
var _tint: ColorPickerButton
var _scrim_rows: Array = []
var _ring_rows: Array = []
var _gradient_rows: Array = []
var _texture_row: HBoxContainer
var _texture_label: Label
var _photometric: CheckBox
var _k_label: Label


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_box)

	var title := Label.new()
	title.text = "Proprietà"
	title.add_theme_font_size_override("font_size", 15)
	_box.add_child(title)

	var top := HBoxContainer.new()
	_box.add_child(top)
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.placeholder_text = "Nome"
	_name.text_submitted.connect(func(_t: String) -> void: _on_name())
	_name.focus_exited.connect(_on_name)
	top.add_child(_name)
	_enabled = CheckBox.new()
	_enabled.text = "On"
	_enabled.toggled.connect(func(v: bool) -> void: _set_prop("enabled", v, true, true))
	top.add_child(_enabled)
	_solo = CheckBox.new()
	_solo.text = "Solo"
	_solo.toggled.connect(func(v: bool) -> void: _set_prop("solo", v, true, true))
	top.add_child(_solo)

	_shape = _option("Forma", LightListPanel.SHAPE_LABELS, func(i: int) -> void:
		_set_prop("shape", i, true)
		_update_visibility())

	_section("Posizione")
	_row("azimuth", "Azimut", -180.0, 180.0, 0.1)
	_row("elevation", "Elevazione", -90.0, 90.0, 0.1)
	_row("roll", "Rotazione", -180.0, 180.0, 0.1)

	_section("Dimensione")
	_row("width", "Larghezza °", 0.5, 180.0, 0.1)
	_row("height", "Altezza °", 0.5, 180.0, 0.1)
	_row("softness", "Sfumatura °", 0.0, 45.0, 0.1)
	_ring_rows.append(_row("ring_inner", "Raggio interno", 0.0, 0.98, 0.01))
	_falloff = _option("Caduta", ["Lineare", "Morbida", "Gaussiana"], func(i: int) -> void: _set_prop("falloff", i, true))
	_gradient_rows.append(_falloff.get_parent())

	_texture_row = HBoxContainer.new()
	_box.add_child(_texture_row)
	var tl0 := Label.new()
	tl0.text = "Immagine"
	tl0.custom_minimum_size.x = 96
	_texture_row.add_child(tl0)
	_texture_label = Label.new()
	_texture_label.text = "—"
	_texture_label.clip_text = true
	_texture_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_texture_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texture_row.add_child(_texture_label)
	var tb := Button.new()
	tb.text = "Cambia…"
	tb.pressed.connect(func() -> void: texture_pick_requested.emit())
	_texture_row.add_child(tb)

	_section("Scrim")
	_scrim_rows.append(_row("scrim_offset_x", "Sorgente X", -1.0, 1.0, 0.01))
	_scrim_rows.append(_row("scrim_offset_y", "Sorgente Y", -1.0, 1.0, 0.01))
	_scrim_rows.append(_row("scrim_depth", "Profondità", 0.05, 5.0, 0.01))
	_scrim_rows.append(_row("scrim_source_size", "Sorgente Ø", 0.0, 3.0, 0.01))

	_section("Intensità e colore")
	_photometric = CheckBox.new()
	_photometric.text = "Fotometrico (illuminamento al centro)"
	_photometric.tooltip_text = "La luce è definita dall'illuminamento E che produce al centro della sfera su una superficie che la guarda.\nLa radianza è E / K, con K l'angolo solido proiettato della forma (immagine compresa).\nDue luci con lo stesso E espongono allo stesso modo qualunque sia la loro dimensione."
	_photometric.toggled.connect(func(v: bool) -> void:
		_set_prop("photometric", v, true)
		_update_visibility())
	_box.add_child(_photometric)
	_row("intensity", "Intensità", 0.01, 1000.0, 0.01, true)
	_row("illuminance", "Illuminamento", 0.01, 100000.0, 0.01, true)
	_k_label = Label.new()
	_k_label.modulate = Color(1, 1, 1, 0.6)
	_k_label.add_theme_font_size_override("font_size", 12)
	_box.add_child(_k_label)
	_row("ev", "EV", -10.0, 10.0, 0.1)
	_row("kelvin", "Kelvin", 1000.0, 25000.0, 10.0)
	var tint_row := HBoxContainer.new()
	_box.add_child(tint_row)
	var tl := Label.new()
	tl.text = "Tinta"
	tl.custom_minimum_size.x = 96
	tint_row.add_child(tl)
	_tint = ColorPickerButton.new()
	_tint.edit_alpha = false
	_tint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tint.color_changed.connect(func(c: Color) -> void: _set_prop("tint", c, false))
	_tint.popup_closed.connect(func() -> void: changed.emit(true))
	tint_row.add_child(_tint)
	_blend = _option("Fusione", ["Somma", "Massimo", "Moltiplica", "Normale"], func(i: int) -> void: _set_prop("blend", i, true))

	set_light(null)


func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	_box.add_child(l)


func _row(prop: String, label: String, min_v: float, max_v: float, step: float, exp_edit := false) -> ParamRow:
	var r := ParamRow.new(label, min_v, max_v, step, exp_edit)
	_box.add_child(r)
	_rows[prop] = r
	r.value_changed.connect(func(v: float) -> void: _set_prop(prop, v, false))
	r.committed.connect(func() -> void: changed.emit(true))
	return r


func _option(label: String, items: Array, on_select: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	_box.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		ob.add_item(it)
	ob.item_selected.connect(on_select)
	row.add_child(ob)
	return ob


func _set_prop(prop: String, value: Variant, commit: bool, refresh_name := false) -> void:
	if _syncing or light == null:
		return
	match prop:
		"scrim_offset_x":
			light.scrim_offset.x = value
		"scrim_offset_y":
			light.scrim_offset.y = value
		_:
			light.set(prop, value)
	changed.emit(commit)
	if refresh_name:
		light_renamed.emit()


func _on_name() -> void:
	if _syncing or light == null or _name.text == light.name:
		return
	light.name = _name.text
	light_renamed.emit()
	changed.emit(true)


func set_light(l: RigLight) -> void:
	light = l
	_box.visible = l != null
	if l == null:
		return
	_syncing = true
	_name.text = l.name
	_enabled.button_pressed = l.enabled
	_solo.button_pressed = l.solo
	_shape.selected = l.shape
	for prop in _rows:
		var v: float
		match prop:
			"scrim_offset_x":
				v = l.scrim_offset.x
			"scrim_offset_y":
				v = l.scrim_offset.y
			_:
				v = l.get(prop)
		_rows[prop].set_value_silent(v)
	_falloff.selected = l.falloff
	_blend.selected = l.blend
	_tint.color = l.tint
	_photometric.button_pressed = l.photometric
	_k_label.text = "K = %.4f sr · radianza risultante %.3f" % [l.measured_k, l.radiance()] if l.photometric else ""
	_texture_label.text = l.texture_path.get_file() if l.texture_path != "" else "—"
	_texture_label.tooltip_text = l.texture_path
	_syncing = false
	_update_visibility()


## Aggiorna solo i valori (es. dopo un drag sulla mappa) senza ricostruire.
func sync_values() -> void:
	if light != null:
		set_light(light)


func _update_visibility() -> void:
	if light == null:
		return
	for r in _scrim_rows:
		r.visible = light.shape == RigLight.Shape.SCRIM
	for r in _ring_rows:
		r.visible = light.shape == RigLight.Shape.RING
	for r in _gradient_rows:
		r.visible = light.shape == RigLight.Shape.GRADIENT
	_texture_row.visible = light.shape == RigLight.Shape.TEXTURE
	_rows["intensity"].visible = not light.photometric
	_rows["illuminance"].visible = light.photometric
	_k_label.visible = light.photometric
	_rows["softness"].visible = light.shape != RigLight.Shape.GRADIENT
