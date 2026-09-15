class_name PresetPanel
extends VBoxContainer
## Libreria di preset: una cartella di rig (<nome>.json + <nome>.png come miniatura).
## Carica sostituisce il rig, Aggiungi appende le luci del preset a quello corrente.

signal load_requested(path: String)
signal merge_requested(path: String)
signal save_requested(name: String)
signal folder_pick_requested()

const DEFAULT_FOLDER := "user://presets"

var folder := ""
var _list: VBoxContainer
var _path_label: Label
var _status: Label
var _buttons := {}
var _selected := ""
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _delete_dialog: ConfirmationDialog
var _btn_load: Button
var _btn_merge: Button
var _btn_delete: Button


func _init() -> void:
	var title := Label.new()
	title.text = "Preset di studio"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	var save := Button.new()
	save.text = "Salva preset…"
	save.pressed.connect(func() -> void:
		_name_edit.text = ""
		_name_dialog.popup_centered()
		_name_edit.grab_focus())
	row.add_child(save)
	var pick := Button.new()
	pick.text = "Cartella…"
	pick.pressed.connect(func() -> void: folder_pick_requested.emit())
	row.add_child(pick)
	_path_label = Label.new()
	_path_label.clip_text = true
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_path_label.modulate = Color(1, 1, 1, 0.7)
	add_child(_path_label)
	var row2 := HBoxContainer.new()
	add_child(row2)
	_btn_load = Button.new()
	_btn_load.text = "Carica"
	_btn_load.tooltip_text = "Sostituisce il rig corrente con il preset"
	_btn_load.pressed.connect(func() -> void: if _selected != "": load_requested.emit(_selected))
	row2.add_child(_btn_load)
	_btn_merge = Button.new()
	_btn_merge.text = "Aggiungi luci"
	_btn_merge.tooltip_text = "Aggiunge le luci del preset al rig corrente"
	_btn_merge.pressed.connect(func() -> void: if _selected != "": merge_requested.emit(_selected))
	row2.add_child(_btn_merge)
	_btn_delete = Button.new()
	_btn_delete.text = "Elimina"
	_btn_delete.pressed.connect(func() -> void: if _selected != "": _delete_dialog.popup_centered())
	row2.add_child(_btn_delete)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)

	_name_dialog = ConfirmationDialog.new()
	_name_dialog.title = "Nome del preset"
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "es. Still life gioiello"
	_name_edit.text_submitted.connect(func(_t: String) -> void: _name_dialog.hide(); _on_save_confirmed())
	_name_dialog.add_child(_name_edit)
	_name_dialog.confirmed.connect(_on_save_confirmed)
	add_child(_name_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.dialog_text = "Eliminare il preset?"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)
	_update_buttons()


func set_folder(path: String) -> void:
	folder = path if path != "" else ProjectSettings.globalize_path(DEFAULT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	_path_label.text = folder
	_path_label.tooltip_text = folder
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	var names: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir != null:
		dir.list_dir_begin()
		var e := dir.get_next()
		while e != "":
			if not dir.current_is_dir() and e.get_extension().to_lower() == "json":
				names.append(e.get_basename())
			e = dir.get_next()
		dir.list_dir_end()
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for n in names:
		_add_button(n)
	if not _buttons.has(_selected):
		_selected = ""
	_update_buttons()
	_status.text = "%d preset" % names.size()


func _add_button(name: String) -> void:
	var path := folder.path_join(name + ".json")
	var b := Button.new()
	b.text = name
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.expand_icon = true
	b.custom_minimum_size.y = 56
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	var png := folder.path_join(name + ".png")
	if FileAccess.file_exists(png):
		var img := Image.load_from_file(png)
		if img != null:
			b.icon = ImageTexture.create_from_image(img)
	b.pressed.connect(func() -> void: _select(path))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			_select(path)
			load_requested.emit(path))
	_list.add_child(b)
	_buttons[path] = b


func _select(path: String) -> void:
	_selected = path
	for p in _buttons:
		_buttons[p].set_pressed_no_signal(p == path)
	_update_buttons()


func _update_buttons() -> void:
	var has := _selected != ""
	_btn_load.disabled = not has
	_btn_merge.disabled = not has
	_btn_delete.disabled = not has


func _on_save_confirmed() -> void:
	var n := _name_edit.text.strip_edges()
	if n != "":
		save_requested.emit(n)


func _on_delete_confirmed() -> void:
	if _selected == "":
		return
	DirAccess.remove_absolute(_selected)
	DirAccess.remove_absolute(_selected.get_basename() + ".png")
	_selected = ""
	refresh()


## Nome file sicuro per il preset.
static func slug(name: String) -> String:
	var s := ""
	for ch in name.strip_edges():
		s += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == " " or ch == "-") else "_"
	return s.strip_edges()


func preset_path(name: String) -> String:
	return folder.path_join(slug(name) + ".json")
