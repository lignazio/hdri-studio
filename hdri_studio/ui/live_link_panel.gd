class_name LiveLinkPanel
extends VBoxContainer
## Pannello del live link: attivazione, file di export automatico, risoluzione live, stato.

signal toggled_link(on: bool)
signal pick_path_requested()
signal push_now_requested()

const LIVE_RESOLUTIONS := [Vector2i(1024, 512), Vector2i(2048, 1024), Vector2i(4096, 2048)]

signal separate_options_changed()

var _enabled: CheckBox
var _path_label: Label
var _res: OptionButton
var _status: Label
var _sep_flip_face: CheckBox
var _sep_flip_tex: CheckBox


func _init() -> void:
	var title := Label.new()
	title.text = "Live link"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	var row := HBoxContainer.new()
	add_child(row)
	_enabled = CheckBox.new()
	_enabled.text = "Attivo"
	_enabled.toggled.connect(func(v: bool) -> void: toggled_link.emit(v))
	row.add_child(_enabled)
	var pick := Button.new()
	pick.text = "File di export…"
	pick.pressed.connect(func() -> void: pick_path_requested.emit())
	row.add_child(pick)
	var push := Button.new()
	push.text = "Invia ora"
	push.pressed.connect(func() -> void: push_now_requested.emit())
	row.add_child(push)

	_path_label = Label.new()
	_path_label.text = "—"
	_path_label.clip_text = true
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_path_label.modulate = Color(1, 1, 1, 0.7)
	add_child(_path_label)

	var rrow := HBoxContainer.new()
	add_child(rrow)
	var rl := Label.new()
	rl.text = "Risoluzione live"
	rl.custom_minimum_size.x = 110
	rrow.add_child(rl)
	_res = OptionButton.new()
	_res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in ["1k × 512", "2k × 1k", "4k × 2k"]:
		_res.add_item(it)
	_res.selected = 1
	rrow.add_child(_res)

	var sl := Label.new()
	sl.text = "Luci separate"
	sl.modulate = Color(1, 1, 1, 0.6)
	add_child(sl)
	_sep_flip_face = CheckBox.new()
	_sep_flip_face.text = "Inverti verso (Z)"
	_sep_flip_face.tooltip_text = "Se le area light in C4D illuminano via dal centro, attiva."
	_sep_flip_face.button_pressed = AppSettings.get_value("separate_flip_face", false)
	_sep_flip_face.toggled.connect(func(v: bool) -> void:
		AppSettings.set_value("separate_flip_face", v)
		separate_options_changed.emit())
	add_child(_sep_flip_face)
	_sep_flip_tex = CheckBox.new()
	_sep_flip_tex.text = "Specchia texture"
	_sep_flip_tex.tooltip_text = "Se la texture della luce in C4D appare specchiata rispetto all'app, attiva."
	_sep_flip_tex.button_pressed = AppSettings.get_value("separate_flip_tex", true)
	_sep_flip_tex.toggled.connect(func(v: bool) -> void:
		AppSettings.set_value("separate_flip_tex", v)
		separate_options_changed.emit())
	add_child(_sep_flip_tex)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)


func separate_flip_face() -> bool:
	return _sep_flip_face.button_pressed


func separate_flip_tex() -> bool:
	return _sep_flip_tex.button_pressed


func is_enabled() -> bool:
	return _enabled.button_pressed


func set_enabled(v: bool) -> void:
	_enabled.set_pressed_no_signal(v)


func set_path(path: String) -> void:
	_path_label.text = path if path != "" else "—"
	_path_label.tooltip_text = path


func live_resolution() -> Vector2i:
	return LIVE_RESOLUTIONS[_res.selected]


func set_status(text: String) -> void:
	_status.text = text
