class_name LightProperties
extends ScrollContainer
## Pannello proprietà della luce selezionata.

## commit = true quando il valore è definitivo (fine drag, spinbox, opzioni): momento dello snapshot di undo.
signal changed(commit: bool)
signal light_renamed()
## L'utente vuole cambiare l'immagine della luce Texture (main apre la dialog).
signal texture_pick_requested()
signal sidecar_save_requested()

var light: RigLight
var _box: VBoxContainer
var _syncing := false

var _name: LineEdit
var _enabled: CheckBox
var _solo: CheckBox
var _locked: CheckBox
var _shape: OptionButton
var _rows := {}
var _falloff: OptionButton
var _blend: OptionButton
var _tint: ColorPickerButton
var _scrim_rows: Array = []
var _ring_rows: Array = []
var _gradient_rows: Array = []
var _texture_row: HBoxContainer
var _texture_tools: HBoxContainer
var _texture_label: Label
var _photometric: CheckBox
var _k_label: Label
var _separate: CheckBox
var _separate_visible: CheckBox
var _separate_rows: Array = []
var _grad_type: OptionButton
var _grad_shape: OptionButton
var _grad_editor: GradientEditor
var _corner_row: ParamRow


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
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
	_locked = CheckBox.new()
	_locked.text = "🔒"
	_locked.tooltip_text = "Blocca la posizione: LightPaint, mappa e frecce non la spostano"
	_locked.toggled.connect(func(v: bool) -> void: _set_prop("locked", v, true, true))
	top.add_child(_locked)

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
	_corner_row = _row("corner_radius", "Angoli °", 0.0, 45.0, 0.1)
	_ring_rows.append(_row("ring_inner", "Raggio interno", 0.0, 0.98, 0.01))

	_gradient_rows.append_array(_section("Gradiente"))
	_grad_type = _option("Tipo", ["Radiale", "Lineare"], func(i: int) -> void:
		_set_prop("gradient_type", i, true)
		_update_visibility())
	_gradient_rows.append(_grad_type.get_parent())
	_grad_shape = _option("Forma", ["Circolare", "Rettangolare"], func(i: int) -> void:
		_set_prop("gradient_shape", i, true)
		_update_visibility())
	_gradient_rows.append(_grad_shape.get_parent())
	_gradient_rows.append(_row("gradient_angle", "Angolo", -180.0, 180.0, 0.1))
	_falloff = _option("Interpolazione", ["Lineare", "Morbida"], func(i: int) -> void: _set_prop("falloff", i, true))
	_gradient_rows.append(_falloff.get_parent())
	_grad_editor = GradientEditor.new()
	_grad_editor.changed.connect(func(commit: bool) -> void: changed.emit(commit))
	_box.add_child(_grad_editor)
	_gradient_rows.append(_grad_editor)

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
	_texture_tools = HBoxContainer.new()
	_box.add_child(_texture_tools)
	var ttl := Label.new()
	ttl.custom_minimum_size.x = 96
	_texture_tools.add_child(ttl)
	var fh := Button.new()
	fh.text = "↔ Specchia"
	fh.pressed.connect(func() -> void: _set_prop("texture_flip_h", not light.texture_flip_h, true))
	_texture_tools.add_child(fh)
	var fv := Button.new()
	fv.text = "↕ Specchia"
	fv.pressed.connect(func() -> void: _set_prop("texture_flip_v", not light.texture_flip_v, true))
	_texture_tools.add_child(fv)
	var rt := Button.new()
	rt.text = "Ruota 90°"
	rt.pressed.connect(func() -> void: _set_prop("texture_rotate", (light.texture_rotate + 1) % 4, true))
	_texture_tools.add_child(rt)
	var sd := Button.new()
	sd.text = "Salva default"
	sd.tooltip_text = "Scrive accanto all'immagine un sidecar .json con dimensione, intensità, Kelvin, sfumatura e rotazione di questa luce: il catalogo li userà come default"
	sd.pressed.connect(func() -> void: sidecar_save_requested.emit())
	_texture_tools.add_child(sd)

	_scrim_rows.append_array(_section("Scrim"))
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
	var krow := HBoxContainer.new()
	_box.add_child(krow)
	var kl := Label.new()
	kl.custom_minimum_size.x = 96
	krow.add_child(kl)
	for k in [3200, 4300, 5600, 6500]:
		var kb := Button.new()
		kb.text = str(k)
		kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kb.pressed.connect(func() -> void:
			_rows["kelvin"].set_value_silent(k)
			_set_prop("kelvin", float(k), true))
		krow.add_child(kb)
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
	var gels := MenuButton.new()
	gels.text = "Gelatine"
	gels.flat = false
	for gname in ColorTemp.GELS:
		gels.get_popup().add_item(gname)
	gels.get_popup().index_pressed.connect(func(i: int) -> void:
		var c := ColorTemp.gel_color(ColorTemp.GELS.keys()[i])
		_tint.color = c
		_set_prop("tint", c, true))
	tint_row.add_child(gels)
	_blend = _option("Fusione", ["Somma", "Massimo", "Moltiplica", "Normale"], func(i: int) -> void: _set_prop("blend", i, true))

	_section("Luce separata")
	_separate = CheckBox.new()
	_separate.text = "Separata → area light nel 3D"
	_separate.tooltip_text = "Esclusa dall'HDRI esportata: scritta come EXR singolo (proiezione planare) e ricreata\nnel software 3D come area light nella stessa direzione, a questa distanza dal centro.\nNel preview resta visibile nell'HDRI."
	_separate.toggled.connect(func(v: bool) -> void:
		_set_prop("separate", v, true, true)
		_update_visibility())
	_box.add_child(_separate)
	_separate_rows.append(_row("distance", "Distanza (cm)", 1.0, 10000.0, 1.0, true))
	_separate_visible = CheckBox.new()
	_separate_visible.text = "Visibile alla camera nel 3D"
	_separate_visible.toggled.connect(func(v: bool) -> void: _set_prop("separate_visible", v, true))
	_box.add_child(_separate_visible)
	_separate_rows.append(_separate_visible)

	set_light(null)


## Sottotitolo di sezione con un po' d'aria sopra. Restituisce [spaziatore, etichetta] per poterli
## nascondere insieme alle righe della sezione.
func _section(text: String) -> Array:
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(sp)
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	_box.add_child(l)
	return [sp, l]


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
	_locked.button_pressed = l.locked
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
	_falloff.selected = mini(l.falloff, 1)
	_grad_type.selected = l.gradient_type
	_grad_shape.selected = l.gradient_shape
	_grad_editor.set_light(l)
	_blend.selected = l.blend
	_tint.color = l.tint
	_photometric.button_pressed = l.photometric
	_separate.button_pressed = l.separate
	_separate_visible.button_pressed = l.separate_visible
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
	_texture_tools.visible = light.shape == RigLight.Shape.TEXTURE
	_rows["intensity"].visible = not light.photometric
	_rows["illuminance"].visible = light.photometric
	_k_label.visible = light.photometric
	for r in _separate_rows:
		r.visible = light.separate
	if light.shape == RigLight.Shape.GRADIENT:
		_rows["gradient_angle"].visible = light.gradient_type == RigLight.GradientType.LINEAR
	var rect_like: bool = light.shape in [RigLight.Shape.RECT, RigLight.Shape.SCRIM, RigLight.Shape.TEXTURE] \
		or (light.shape == RigLight.Shape.GRADIENT and light.gradient_shape == RigLight.GradientShape.RECTANGULAR)
	_corner_row.visible = rect_like
