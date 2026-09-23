class_name BackgroundPanel
extends VBoxContainer
## Layer di base: gradiente/colore e HDRI importata.

signal changed(commit: bool)
signal base_hdri_requested()
## Ruota tutte le luci di delta gradi (commit a fine drag).
signal rotate_all(delta: float, commit: bool)

var rig: LightRig
var _syncing := false
var _mode: OptionButton
var _zenith: ColorPickerButton
var _horizon: ColorPickerButton
var _nadir: ColorPickerButton
var _base_label: Label
var _base_enabled: CheckBox
var _base_rot: ParamRow
var _base_ev: ParamRow
var _base_blur: ParamRow
var _base_flip: CheckBox


func _init() -> void:
	add_child(UiStyle.title("Set"))
	var rot := ParamRow.new("Rotate all", -180.0, 180.0, 1.0)
	rot.tooltip_text = "Rotates every light around the vertical axis; returns to 0 when you release the slider"
	var last := [0.0]
	rot.value_changed.connect(func(v: float) -> void:
		rotate_all.emit(v - last[0], false)
		last[0] = v)
	rot.committed.connect(func() -> void:
		rotate_all.emit(0.0, true)
		last[0] = 0.0
		rot.set_value_silent(0.0))
	add_child(rot)

	# Set e Sfondo sono due pannelli: fra loro l'unica linea, dentro solo spazio
	add_child(UiStyle.separator())
	add_child(UiStyle.title("Background"))

	_mode = OptionButton.new()
	for it in ["Black", "Solid color", "Gradient"]:
		_mode.add_item(it)
	_mode.item_selected.connect(func(i: int) -> void: _apply(func() -> void: rig.background = i as LightRig.Background, true))
	add_child(UiStyle.field_row("Type", _mode))

	_zenith = _color_row("Zenith", func(c: Color) -> void: rig.bg_zenith = c)
	_horizon = _color_row("Horizon", func(c: Color) -> void: rig.bg_horizon = c)
	_nadir = _color_row("Nadir", func(c: Color) -> void: rig.bg_nadir = c)

	add_child(UiStyle.spacer(UiStyle.SPACE_GROUP - UiStyle.SPACE_ROW))
	add_child(UiStyle.section("Base HDRI"))
	var brow := HBoxContainer.new()
	add_child(brow)
	var btn := Button.new()
	btn.text = "Load…"
	btn.pressed.connect(func() -> void: base_hdri_requested.emit())
	brow.add_child(btn)
	_base_enabled = CheckBox.new()
	_base_enabled.text = "Enabled"
	_base_enabled.toggled.connect(func(v: bool) -> void: _apply(func() -> void: rig.base_enabled = v, true))
	brow.add_child(_base_enabled)
	_base_flip = CheckBox.new()
	_base_flip.text = "Mirror"
	_base_flip.toggled.connect(func(v: bool) -> void: _apply(func() -> void: rig.base_flip = v, true))
	brow.add_child(_base_flip)
	_base_label = UiStyle.dim("No file")
	add_child(_base_label)
	_base_rot = ParamRow.new("Rotation", -180.0, 180.0, 0.1)
	_base_rot.value_changed.connect(func(v: float) -> void: _apply(func() -> void: rig.base_rotation = v, false))
	_base_rot.committed.connect(func() -> void: changed.emit(true))
	add_child(_base_rot)
	_base_ev = ParamRow.new("EV", -10.0, 10.0, 0.1)
	_base_ev.value_changed.connect(func(v: float) -> void: _apply(func() -> void: rig.base_ev = v, false))
	_base_ev.committed.connect(func() -> void: changed.emit(true))
	add_child(_base_ev)
	_base_blur = ParamRow.new("Blur", 0.0, 1.0, 0.01)
	_base_blur.tooltip_text = "Blurs the base HDRI (mipmaps): at 1 only the dominant color is left"
	_base_blur.value_changed.connect(func(v: float) -> void: _apply(func() -> void: rig.base_blur = v, false))
	_base_blur.committed.connect(func() -> void: changed.emit(true))
	add_child(_base_blur)


func _color_row(label: String, setter: Callable) -> ColorPickerButton:
	var b := ColorPickerButton.new()
	b.edit_alpha = false
	# alta come le altre righe: prima le righe colore avevano un passo di 27 px contro 35
	b.custom_minimum_size.y = 28
	b.color_changed.connect(func(c: Color) -> void: _apply(func() -> void: setter.call(c), false))
	b.popup_closed.connect(func() -> void: changed.emit(true))
	add_child(UiStyle.field_row(label, b))
	return b


func _apply(fn: Callable, commit: bool) -> void:
	if _syncing or rig == null:
		return
	fn.call()
	changed.emit(commit)


func set_rig(r: LightRig) -> void:
	rig = r
	_syncing = true
	_mode.selected = r.background
	_zenith.color = r.bg_zenith
	_horizon.color = r.bg_horizon
	_nadir.color = r.bg_nadir
	_base_enabled.button_pressed = r.base_enabled
	_base_flip.button_pressed = r.base_flip
	_base_label.text = r.base_hdri_path.get_file() if r.base_hdri_path != "" else "No file"
	_base_label.tooltip_text = r.base_hdri_path
	_base_rot.set_value_silent(r.base_rotation)
	_base_ev.set_value_silent(r.base_ev)
	_base_blur.set_value_silent(r.base_blur)
	_syncing = false
