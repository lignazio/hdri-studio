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
	var stitle := Label.new()
	stitle.text = "Set"
	stitle.add_theme_font_size_override("font_size", 15)
	add_child(stitle)
	var rot := ParamRow.new("Ruota tutto", -180.0, 180.0, 1.0)
	rot.tooltip_text = "Ruota tutte le luci attorno all'asse verticale; torna a 0 quando lasci lo slider"
	var last := [0.0]
	rot.value_changed.connect(func(v: float) -> void:
		rotate_all.emit(v - last[0], false)
		last[0] = v)
	rot.committed.connect(func() -> void:
		rotate_all.emit(0.0, true)
		last[0] = 0.0
		rot.set_value_silent(0.0))
	add_child(rot)

	var sep0 := HSeparator.new()
	sep0.add_theme_constant_override("separation", 14)
	add_child(sep0)
	var title := Label.new()
	title.text = "Sfondo"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	var mrow := HBoxContainer.new()
	add_child(mrow)
	var ml := Label.new()
	ml.text = "Tipo"
	ml.custom_minimum_size.x = 96
	mrow.add_child(ml)
	_mode = OptionButton.new()
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in ["Nero", "Colore uniforme", "Gradiente"]:
		_mode.add_item(it)
	_mode.item_selected.connect(func(i: int) -> void: _apply(func() -> void: rig.background = i as LightRig.Background, true))
	mrow.add_child(_mode)

	_zenith = _color_row("Zenit", func(c: Color) -> void: rig.bg_zenith = c)
	_horizon = _color_row("Orizzonte", func(c: Color) -> void: rig.bg_horizon = c)
	_nadir = _color_row("Nadir", func(c: Color) -> void: rig.bg_nadir = c)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 14)
	add_child(sep)
	var t2 := Label.new()
	t2.text = "HDRI di base"
	t2.modulate = Color(1, 1, 1, 0.6)
	add_child(t2)
	var brow := HBoxContainer.new()
	add_child(brow)
	var btn := Button.new()
	btn.text = "Carica…"
	btn.pressed.connect(func() -> void: base_hdri_requested.emit())
	brow.add_child(btn)
	_base_enabled = CheckBox.new()
	_base_enabled.text = "Attiva"
	_base_enabled.toggled.connect(func(v: bool) -> void: _apply(func() -> void: rig.base_enabled = v, true))
	brow.add_child(_base_enabled)
	_base_flip = CheckBox.new()
	_base_flip.text = "Specchia"
	_base_flip.toggled.connect(func(v: bool) -> void: _apply(func() -> void: rig.base_flip = v, true))
	brow.add_child(_base_flip)
	_base_label = Label.new()
	_base_label.text = "—"
	_base_label.clip_text = true
	_base_label.modulate = Color(1, 1, 1, 0.7)
	add_child(_base_label)
	_base_rot = ParamRow.new("Rotazione", -180.0, 180.0, 0.1)
	_base_rot.value_changed.connect(func(v: float) -> void: _apply(func() -> void: rig.base_rotation = v, false))
	_base_rot.committed.connect(func() -> void: changed.emit(true))
	add_child(_base_rot)
	_base_ev = ParamRow.new("EV", -10.0, 10.0, 0.1)
	_base_ev.value_changed.connect(func(v: float) -> void: _apply(func() -> void: rig.base_ev = v, false))
	_base_ev.committed.connect(func() -> void: changed.emit(true))
	add_child(_base_ev)
	_base_blur = ParamRow.new("Sfocatura", 0.0, 1.0, 0.01)
	_base_blur.tooltip_text = "Sfoca l'HDRI di base (mipmap): a 1 resta solo la dominante"
	_base_blur.value_changed.connect(func(v: float) -> void: _apply(func() -> void: rig.base_blur = v, false))
	_base_blur.committed.connect(func() -> void: changed.emit(true))
	add_child(_base_blur)


func _color_row(label: String, setter: Callable) -> ColorPickerButton:
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	row.add_child(l)
	var b := ColorPickerButton.new()
	b.edit_alpha = false
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.color_changed.connect(func(c: Color) -> void: _apply(func() -> void: setter.call(c), false))
	b.popup_closed.connect(func() -> void: changed.emit(true))
	row.add_child(b)
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
	_base_label.text = r.base_hdri_path.get_file() if r.base_hdri_path != "" else "—"
	_base_rot.set_value_silent(r.base_rotation)
	_base_ev.set_value_silent(r.base_ev)
	_base_blur.set_value_silent(r.base_blur)
	_syncing = false
