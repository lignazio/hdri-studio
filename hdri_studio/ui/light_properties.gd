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
	# il pannello occupa tutta la larghezza della colonna, così la barra di scorrimento sta sul bordo;
	# il margine è dentro, e il testo resta a 16 px dal bordo o dalla barra
	add_child(UiStyle.pad(_box, UiStyle.MARGIN, 0, UiStyle.MARGIN, UiStyle.MARGIN))

	_box.add_child(UiStyle.title("Properties"))

	var top := HBoxContainer.new()
	_box.add_child(top)
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.placeholder_text = "Name"
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
	# la stessa icona monocroma della lista luci, non l'emoji a colori
	_locked.icon = LightIcons.lock()
	_locked.tooltip_text = "Lock the position: LightPaint, map and arrow keys will not move it"
	_locked.toggled.connect(func(v: bool) -> void: _set_prop("locked", v, true, true))
	top.add_child(_locked)

	_shape = _option("Shape", LightListPanel.SHAPE_LABELS, func(i: int) -> void:
		_set_prop("shape", i, true)
		_update_visibility())

	_section("Position")
	_row("azimuth", "Azimuth", -180.0, 180.0, 0.1)
	_row("elevation", "Elevation", -90.0, 90.0, 0.1)
	_row("roll", "Rotation", -180.0, 180.0, 0.1)

	_section("Size")
	_row("width", "Width °", 0.5, 180.0, 0.1)
	_row("height", "Height °", 0.5, 180.0, 0.1)
	_row("softness", "Softness °", 0.0, 45.0, 0.1)
	_corner_row = _row("corner_radius", "Corners °", 0.0, 45.0, 0.1)
	_ring_rows.append(_row("ring_inner", "Inner radius", 0.0, 0.98, 0.01))

	_gradient_rows.append_array(_section("Gradient"))
	_grad_type = _option("Type", ["Radial", "Linear"], func(i: int) -> void:
		_set_prop("gradient_type", i, true)
		_update_visibility())
	_gradient_rows.append(_grad_type.get_parent())
	_grad_shape = _option("Shape", ["Circular", "Rectangular"], func(i: int) -> void:
		_set_prop("gradient_shape", i, true)
		_update_visibility())
	_gradient_rows.append(_grad_shape.get_parent())
	_gradient_rows.append(_row("gradient_angle", "Angle", -180.0, 180.0, 0.1))
	_falloff = _option("Interpolation", ["Linear", "Smooth"], func(i: int) -> void: _set_prop("falloff", i, true))
	_gradient_rows.append(_falloff.get_parent())
	_grad_editor = GradientEditor.new()
	_grad_editor.changed.connect(func(commit: bool) -> void: changed.emit(commit))
	_box.add_child(_grad_editor)
	_gradient_rows.append(_grad_editor)

	_texture_row = HBoxContainer.new()
	_box.add_child(_texture_row)
	_texture_row.add_child(UiStyle.field_label("Image"))
	_texture_label = UiStyle.dim("No file")
	_texture_row.add_child(_texture_label)
	var tb := Button.new()
	tb.text = "Change…"
	tb.pressed.connect(func() -> void: texture_pick_requested.emit())
	_texture_row.add_child(tb)
	_texture_tools = HBoxContainer.new()
	_box.add_child(_texture_tools)
	_texture_tools.add_child(UiStyle.field_label(""))
	var fh := Button.new()
	fh.text = "↔ Mirror"
	fh.pressed.connect(func() -> void: _set_prop("texture_flip_h", not light.texture_flip_h, true))
	_texture_tools.add_child(fh)
	var fv := Button.new()
	fv.text = "↕ Mirror"
	fv.pressed.connect(func() -> void: _set_prop("texture_flip_v", not light.texture_flip_v, true))
	_texture_tools.add_child(fv)
	var rt := Button.new()
	rt.text = "Rotate 90°"
	rt.pressed.connect(func() -> void: _set_prop("texture_rotate", (light.texture_rotate + 1) % 4, true))
	_texture_tools.add_child(rt)
	var sd := Button.new()
	sd.text = "Save defaults"
	sd.tooltip_text = "Writes a .json sidecar next to the image with the size, intensity, Kelvin, softness and rotation of this light: the catalog will use them as defaults"
	sd.pressed.connect(func() -> void: sidecar_save_requested.emit())
	_texture_tools.add_child(sd)

	_scrim_rows.append_array(_section("Scrim"))
	_scrim_rows.append(_row("scrim_offset_x", "Source X", -1.0, 1.0, 0.01))
	_scrim_rows.append(_row("scrim_offset_y", "Source Y", -1.0, 1.0, 0.01))
	_scrim_rows.append(_row("scrim_depth", "Depth", 0.05, 5.0, 0.01))
	_scrim_rows.append(_row("scrim_source_size", "Source Ø", 0.0, 3.0, 0.01))

	_section("Intensity and color")
	_photometric = CheckBox.new()
	_photometric.text = "Photometric (illuminance at the center)"
	_photometric.tooltip_text = "The light is defined by the illuminance E it produces at the center of the sphere on a surface facing it.\nRadiance is E / K, where K is the projected solid angle of the shape (image included).\nTwo lights with the same E expose the same way whatever their size."
	_photometric.toggled.connect(func(v: bool) -> void:
		_set_prop("photometric", v, true)
		_update_visibility())
	_box.add_child(_photometric)
	_row("intensity", "Intensity", 0.01, 1000.0, 0.01, true)
	_row("illuminance", "Illuminance", 0.01, 100000.0, 0.01, true)
	_k_label = UiStyle.hint("")
	_box.add_child(_k_label)
	_row("ev", "EV", -10.0, 10.0, 0.1)
	# lo slider copre la pratica da studio (5600 K verso metà corsa); valori oltre si scrivono nello
	# spinbox. Il minimo del modello di colore è 1667 K (core/color_temp.gd), ma Range arrotonda il
	# passo a partire dal minimo: con 1670 i multipli di 10 restano esatti (1667 dava 5597 al posto di 5600)
	var krow_slider := _row("kelvin", "Kelvin", 1670.0, 12000.0, 10.0)
	krow_slider.spin.max_value = 25000.0
	var krow := HBoxContainer.new()
	_box.add_child(krow)
	krow.add_child(UiStyle.field_label(""))
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
	tint_row.add_child(UiStyle.field_label("Tint"))
	_tint = ColorPickerButton.new()
	_tint.edit_alpha = false
	_tint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tint.color_changed.connect(func(c: Color) -> void: _set_prop("tint", c, false))
	_tint.popup_closed.connect(func() -> void: changed.emit(true))
	tint_row.add_child(_tint)
	var gels := MenuButton.new()
	gels.text = "Gels"
	gels.flat = false
	for gname in ColorTemp.GELS:
		gels.get_popup().add_item(gname)
	gels.get_popup().index_pressed.connect(func(i: int) -> void:
		var c := ColorTemp.gel_color(ColorTemp.GELS.keys()[i])
		_tint.color = c
		_set_prop("tint", c, true))
	tint_row.add_child(gels)
	_blend = _option("Blend", ["Add", "Max", "Multiply", "Normal"], func(i: int) -> void: _set_prop("blend", i, true))

	_section("Separate light")
	_separate = CheckBox.new()
	_separate.text = "Separate → area light in 3D"
	_separate.tooltip_text = "Excluded from the exported HDRI: written as a separate EXR (planar projection) and recreated\nin the 3D software as an area light in the same direction, at this distance from the center.\nIt stays visible in the HDRI in the preview."
	_separate.toggled.connect(func(v: bool) -> void:
		_set_prop("separate", v, true, true)
		_update_visibility())
	_box.add_child(_separate)
	_separate_rows.append(_row("distance", "Distance (cm)", 1.0, 10000.0, 1.0, true))
	_separate_visible = CheckBox.new()
	_separate_visible.text = "Visible to the camera in 3D"
	_separate_visible.toggled.connect(func(v: bool) -> void: _set_prop("separate_visible", v, true))
	_box.add_child(_separate_visible)
	_separate_rows.append(_separate_visible)

	set_light(null)


## Sottotitolo di sezione con aria sopra (16 contro i 4 fra le righe: i gruppi si contano senza
## leggere). Restituisce [spaziatore, etichetta] per poterli nascondere con le righe della sezione.
func _section(text: String) -> Array:
	var sp := UiStyle.spacer(UiStyle.SPACE_GROUP - UiStyle.SPACE_ROW)
	_box.add_child(sp)
	var l := UiStyle.section(text)
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
	row.add_child(UiStyle.field_label(label))
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
	_k_label.text = tr("K = %.4f sr · resulting radiance %.3f") % [l.measured_k, l.radiance()] if l.photometric else ""
	_texture_label.text = l.texture_path.get_file() if l.texture_path != "" else "No file"
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
