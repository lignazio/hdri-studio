class_name CatalogPanel
extends VBoxContainer
## Catalogo di HDRI lights: una cartella locale (ricorsiva) di EXR/HDR, con miniature.
## Click su una miniatura → light_requested(path, defaults). Il rig salva solo il percorso.
##
## Accanto a ogni immagine può esserci un sidecar `nome.json` (o `nome.exr.json`) con i default:
## {"name": "...", "width": 30, "height": 20, "intensity": 1, "ev": 0, "kelvin": 6500, "softness": 1, "roll": 0}

signal light_requested(path: String, defaults: Dictionary)
signal folder_pick_requested()
## Anteprima grande al passaggio del mouse (main la mostra sopra tutto).
signal hover_preview(texture: Texture2D, name: String, anchor: Rect2)
signal hover_end()

const META_PATH := "user://catalog_meta.json"

const EXTS := ["exr", "hdr"]
const COLUMNS := 2

var folder := ""
var thumbs := ThumbnailCache.new()
var _items: Array[Dictionary] = []
var _buttons := {}
var _sections := {}      # sottocartella relativa → {"header": Label, "grid": GridContainer}
var _list: VBoxContainer
var _subfolder: OptionButton
var _filter: LineEdit
var _meta := {}          # percorso relativo → {"fav": bool, "tags": [..]}
var _fav_only: CheckBox
var _tag_filter: OptionButton
var _menu: PopupMenu
var _menu_path := ""
var _tag_dialog: ConfirmationDialog
var _tag_edit: LineEdit
var _path_label: Label
var _status: Label


func _init() -> void:
	var title := Label.new()
	title.text = "HDRI light catalog"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	var pick := Button.new()
	pick.text = "Folder…"
	pick.pressed.connect(func() -> void: folder_pick_requested.emit())
	row.add_child(pick)
	var rescan := Button.new()
	rescan.text = "Refresh"
	rescan.pressed.connect(func() -> void: set_folder(folder))
	row.add_child(rescan)
	_path_label = Label.new()
	_path_label.text = "—"
	_path_label.clip_text = true
	_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_path_label.modulate = Color(1, 1, 1, 0.7)
	add_child(_path_label)
	_subfolder = OptionButton.new()
	_subfolder.item_selected.connect(func(_i: int) -> void: _apply_filter())
	add_child(_subfolder)
	var frow := HBoxContainer.new()
	add_child(frow)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter by name or tag…"
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_t: String) -> void: _apply_filter())
	frow.add_child(_filter)
	_fav_only = CheckBox.new()
	_fav_only.text = "★"
	_fav_only.tooltip_text = "Favorites only"
	_fav_only.toggled.connect(func(_v: bool) -> void: _apply_filter())
	frow.add_child(_fav_only)
	_tag_filter = OptionButton.new()
	_tag_filter.item_selected.connect(func(_i: int) -> void: _apply_filter())
	add_child(_tag_filter)
	var erow := ParamRow.new("Thumbnail EV", -4.0, 4.0, 0.5)
	erow.tooltip_text = "Thumbnail exposure relative to the automatic one (regenerates the thumbnails)"
	ThumbnailCache.exposure_ev = float(AppSettings.get_value("thumb_ev", 0.0))
	erow.set_value_silent(ThumbnailCache.exposure_ev)
	erow.committed.connect(func() -> void:
		ThumbnailCache.exposure_ev = erow.get_value()
		AppSettings.set_value("thumb_ev", ThumbnailCache.exposure_ev)
		set_folder(folder))
	add_child(erow)
	_menu = PopupMenu.new()
	_menu.add_check_item("★ Favorite", 0)
	_menu.add_item("Tag…", 1)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	_tag_dialog = ConfirmationDialog.new()
	_tag_dialog.title = "Tags (comma separated)"
	_tag_edit = LineEdit.new()
	_tag_edit.placeholder_text = "softbox, warm, large"
	_tag_edit.text_submitted.connect(func(_t: String) -> void: _tag_dialog.hide(); _on_tags_confirmed())
	_tag_dialog.add_child(_tag_edit)
	_tag_dialog.confirmed.connect(_on_tags_confirmed)
	add_child(_tag_dialog)
	_load_meta()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	thumbs.ready.connect(_on_thumb)
	set_process(true)


func _process(_delta: float) -> void:
	thumbs.poll()


func _exit_tree() -> void:
	thumbs.shutdown()


func set_folder(path: String) -> void:
	folder = path
	_path_label.text = path if path != "" else "—"
	_path_label.tooltip_text = path
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	_sections.clear()
	_items.clear()
	_subfolder.clear()
	_subfolder.add_item("All folders")
	if path == "" or not DirAccess.dir_exists_absolute(path):
		_status.text = "Pick a folder with your EXR/HDR files."
		return
	_scan(path)
	# ordine: per sottocartella, poi per nome
	_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["folder"] != b["folder"]:
			return a["folder"].naturalnocasecmp_to(b["folder"]) < 0
		return a["name"].naturalnocasecmp_to(b["name"]) < 0)
	for it in _items:
		_add_button(it)
	for sub in _sections:
		_subfolder.add_item(sub if sub != "" else "(root)")
	_rebuild_tag_filter()
	_apply_filter()
	_status.text = tr("%d images in %d folders") % [_items.size(), _sections.size()]


func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan(full)
		elif entry.get_extension().to_lower() in EXTS:
			var rel := dir_path.trim_prefix(folder).trim_prefix("/").trim_prefix("\\")
			_items.append({"path": full, "name": entry.get_basename(), "folder": rel, "sidecar": _sidecar(full)})
		entry = dir.get_next()
	dir.list_dir_end()


static func _sidecar(path: String) -> Dictionary:
	for candidate in [path.get_basename() + ".json", path + ".json"]:
		if FileAccess.file_exists(candidate):
			var d = JSON.parse_string(FileAccess.get_file_as_string(candidate))
			if d is Dictionary:
				return d
	return {}


func _section_grid(sub: String) -> GridContainer:
	if _sections.has(sub):
		return _sections[sub]["grid"]
	var header := Label.new()
	header.text = sub if sub != "" else "(root)"
	header.add_theme_font_size_override("font_size", 13)
	header.modulate = Color(1.0, 0.8, 0.2, 0.9)
	_list.add_child(header)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(grid)
	_sections[sub] = {"header": header, "grid": grid}
	return grid


func _add_button(it: Dictionary) -> void:
	var b := Button.new()
	b.text = _label(it)
	b.tooltip_text = it["path"]
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = true
	b.custom_minimum_size = Vector2(120, 92)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: light_requested.emit(it["path"], _defaults(it)))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_menu_path = it["path"]
			_menu.set_item_checked(0, _meta_of(it["path"]).get("fav", false))
			_menu.position = Vector2i(b.get_global_mouse_position()) + Vector2i(get_window().position)
			_menu.popup())
	b.mouse_entered.connect(func() -> void:
		hover_end.emit()
		if b.icon != null:
			hover_preview.emit(b.icon, b.text, b.get_global_rect()))
	b.mouse_exited.connect(func() -> void: hover_end.emit())
	# trascinabile sulla mappa o sul preview 3D: il dato viaggia come Dictionary
	b.set_drag_forwarding(func(_at: Vector2) -> Variant:
		var preview := TextureRect.new()
		preview.texture = b.icon
		preview.custom_minimum_size = Vector2(96, 48)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.modulate.a = 0.85
		b.set_drag_preview(preview)
		return {"type": "catalog_light", "path": it["path"], "defaults": _defaults(it)},
		Callable(), Callable())
	_section_grid(it["folder"]).add_child(b)
	b.set_meta("folder", it["folder"])
	_buttons[it["path"]] = b
	var tex := thumbs.request(it["path"])
	if tex != null:
		b.icon = tex


func _on_thumb(path: String, tex: ImageTexture, _size: Vector2i) -> void:
	if _buttons.has(path):
		_buttons[path].icon = tex


## Default per la luce: sidecar se c'è, altrimenti 30° di larghezza e altezza dall'aspetto.
func _defaults(it: Dictionary) -> Dictionary:
	var d: Dictionary = it["sidecar"].duplicate()
	if not d.has("name"):
		d["name"] = it["name"]
	if not d.has("width"):
		d["width"] = 30.0
	if not d.has("height"):
		var size := thumbs.image_size(it["path"])
		var aspect := float(size.x) / float(size.y) if size.y > 0 else 1.0
		d["height"] = clampf(float(d["width"]) / aspect, 0.5, 180.0)
	return d


func _apply_filter() -> void:
	var q := _filter.text.strip_edges().to_lower()
	var only := ""
	var all_folders := _subfolder.selected <= 0
	if not all_folders:
		only = _sections.keys()[_subfolder.selected - 1]
	var tag_only := ""
	if _tag_filter.selected > 0:
		tag_only = _tag_filter.get_item_text(_tag_filter.selected)
	var visible_per_section := {}
	for path in _buttons:
		var b: Button = _buttons[path]
		var sub: String = b.get_meta("folder")
		var m := _meta_of(path)
		var tags: Array = m.get("tags", [])
		var tag_text := " ".join(tags).to_lower()
		var text_ok: bool = q == "" or b.text.to_lower().contains(q) or path.get_file().to_lower().contains(q) or tag_text.contains(q)
		var fav_ok: bool = not _fav_only.button_pressed or m.get("fav", false)
		var tag_ok: bool = tag_only == "" or tags.has(tag_only)
		b.visible = (all_folders or sub == only) and text_ok and fav_ok and tag_ok
		if b.visible:
			visible_per_section[sub] = true
	for sub in _sections:
		var show: bool = visible_per_section.has(sub)
		_sections[sub]["header"].visible = show
		_sections[sub]["grid"].visible = show


# --- preferiti e tag (user://catalog_meta.json, chiave = percorso relativo alla cartella) ---------

func _rel(path: String) -> String:
	return path.trim_prefix(folder).trim_prefix("/").trim_prefix("\\")


func _meta_of(path: String) -> Dictionary:
	return _meta.get(_rel(path), {})


func _set_meta(path: String, m: Dictionary) -> void:
	_meta[_rel(path)] = m
	_save_meta()
	if _buttons.has(path):
		var it := {"path": path, "name": path.get_file().get_basename(), "sidecar": _sidecar(path)}
		_buttons[path].text = _label(it)
	_rebuild_tag_filter()
	_apply_filter()


func _label(it: Dictionary) -> String:
	var name: String = it["sidecar"].get("name", it["name"])
	return ("★ " + name) if _meta_of(it["path"]).get("fav", false) else name


func _load_meta() -> void:
	var txt := FileAccess.get_file_as_string(META_PATH)
	var d = JSON.parse_string(txt) if txt != "" else null
	_meta = d if d is Dictionary else {}


func _save_meta() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_meta, "\t"))


func _all_tags() -> Array:
	var s := {}
	for rel in _meta:
		for tg in _meta[rel].get("tags", []):
			s[tg] = true
	var arr := s.keys()
	arr.sort()
	return arr


func _rebuild_tag_filter() -> void:
	var cur := _tag_filter.get_item_text(_tag_filter.selected) if _tag_filter.selected > 0 else ""
	_tag_filter.clear()
	_tag_filter.add_item("All tags")
	var i := 1
	for tg in _all_tags():
		_tag_filter.add_item(tg)
		if tg == cur:
			_tag_filter.selected = i
		i += 1


func _on_menu(id: int) -> void:
	if _menu_path == "":
		return
	var m := _meta_of(_menu_path).duplicate()
	if id == 0:
		m["fav"] = not m.get("fav", false)
		_set_meta(_menu_path, m)
	elif id == 1:
		_tag_edit.text = ", ".join(m.get("tags", []))
		_tag_dialog.popup_centered()
		_tag_edit.grab_focus()


func _on_tags_confirmed() -> void:
	if _menu_path == "":
		return
	var m := _meta_of(_menu_path).duplicate()
	var tags: Array = []
	for part in _tag_edit.text.split(","):
		var tg := part.strip_edges().to_lower()
		if tg != "" and not tags.has(tg):
			tags.append(tg)
	m["tags"] = tags
	_set_meta(_menu_path, m)


func set_favorite(path: String, fav: bool) -> void:
	var m := _meta_of(path).duplicate()
	m["fav"] = fav
	_set_meta(path, m)


func set_tags(path: String, tags: Array) -> void:
	var m := _meta_of(path).duplicate()
	m["tags"] = tags
	_set_meta(path, m)
