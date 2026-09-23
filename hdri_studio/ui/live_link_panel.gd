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
var _target_label: Label
var _target := ""


func _init() -> void:
	add_child(UiStyle.title("Live link"))
	# il link usa il software scelto nel pannello Export: detto qui, altrimenti cambiando preset per
	# un export si cambia anche l'orientamento del link senza accorgersene
	_target_label = UiStyle.status()
	add_child(_target_label)

	# nell'ordine in cui si usa (GUIDA §5): prima il file, poi si attiva
	var prow := HBoxContainer.new()
	add_child(prow)
	var pick := Button.new()
	pick.text = "Export file…"
	pick.pressed.connect(func() -> void: pick_path_requested.emit())
	prow.add_child(pick)
	_path_label = UiStyle.dim("No file")
	prow.add_child(_path_label)

	var row := HBoxContainer.new()
	add_child(row)
	_enabled = CheckBox.new()
	_enabled.text = "Active"
	_enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enabled.toggled.connect(func(v: bool) -> void: toggled_link.emit(v))
	row.add_child(_enabled)
	var push := Button.new()
	push.text = "Send now"
	push.pressed.connect(func() -> void: push_now_requested.emit())
	row.add_child(push)

	_res = OptionButton.new()
	for it in ["1k × 512", "2k × 1k", "4k × 2k"]:
		_res.add_item(it)
	_res.selected = 1
	add_child(UiStyle.field_row("Live resolution", _res))

	add_child(UiStyle.spacer(UiStyle.SPACE_GROUP - UiStyle.SPACE_ROW))
	add_child(UiStyle.section("Separate lights"))
	_sep_flip_face = CheckBox.new()
	_sep_flip_face.text = "Flip facing (Z)"
	_sep_flip_face.tooltip_text = "Enable if the area lights in C4D light away from the center."
	_sep_flip_face.button_pressed = AppSettings.get_value("separate_flip_face", false)
	_sep_flip_face.toggled.connect(func(v: bool) -> void:
		AppSettings.set_value("separate_flip_face", v)
		separate_options_changed.emit())
	add_child(_sep_flip_face)
	_sep_flip_tex = CheckBox.new()
	_sep_flip_tex.text = "Mirror texture"
	_sep_flip_tex.tooltip_text = "Enable if the light texture in C4D looks mirrored compared to the app."
	_sep_flip_tex.button_pressed = AppSettings.get_value("separate_flip_tex", true)
	_sep_flip_tex.toggled.connect(func(v: bool) -> void:
		AppSettings.set_value("separate_flip_tex", v)
		separate_options_changed.emit())
	add_child(_sep_flip_tex)

	_status = UiStyle.status()
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
	_path_label.text = path.get_file() if path != "" else "No file"
	_path_label.tooltip_text = path


func live_resolution() -> Vector2i:
	return LIVE_RESOLUTIONS[_res.selected]


func set_status(text: String) -> void:
	_status.text = text


## Software di destinazione (dal pannello Export). Testo composto: main lo richiama al cambio di lingua.
func set_target(target: String) -> void:
	_target = target
	_target_label.text = tr("Target: %s (Export panel)") % target
