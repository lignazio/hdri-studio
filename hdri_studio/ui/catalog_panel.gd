class_name CatalogPanel
extends VBoxContainer
## Catalogo di HDRI lights: una cartella locale (ricorsiva) di EXR/HDR, con miniature.
## Click su una miniatura → light_requested(path, defaults). Il rig salva solo il percorso.
##
## Accanto a ogni immagine può esserci un sidecar `nome.json` (o `nome.exr.json`) con i default:
## {"name": "...", "width": 30, "height": 20, "intensity": 1, "ev": 0, "kelvin": 6500, "softness": 1, "roll": 0}

signal light_requested(path: String, defaults: Dictionary)
signal folder_pick_requested()

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
var _path_label: Label
var _status: Label


func _init() -> void:
	var title := Label.new()
	title.text = "Catalogo HDRI lights"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	var row := HBoxContainer.new()
	add_child(row)
	var pick := Button.new()
	pick.text = "Cartella…"
	pick.pressed.connect(func() -> void: folder_pick_requested.emit())
	row.add_child(pick)
	var rescan := Button.new()
	rescan.text = "Aggiorna"
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
	_filter = LineEdit.new()
	_filter.placeholder_text = "Filtra per nome…"
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _apply_filter())
	add_child(_filter)
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
	_subfolder.add_item("Tutte le cartelle")
	if path == "" or not DirAccess.dir_exists_absolute(path):
		_status.text = "Scegli una cartella con i tuoi EXR/HDR."
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
		_subfolder.add_item(sub if sub != "" else "(radice)")
	_apply_filter()
	_status.text = "%d immagini in %d cartelle" % [_items.size(), _sections.size()]


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
	header.text = sub if sub != "" else "(radice)"
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
	b.text = it["sidecar"].get("name", it["name"])
	b.tooltip_text = it["path"]
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = true
	b.custom_minimum_size = Vector2(120, 92)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: light_requested.emit(it["path"], _defaults(it)))
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
	var visible_per_section := {}
	for path in _buttons:
		var b: Button = _buttons[path]
		var sub: String = b.get_meta("folder")
		b.visible = (all_folders or sub == only) and (q == "" or b.text.to_lower().contains(q) or path.get_file().to_lower().contains(q))
		if b.visible:
			visible_per_section[sub] = true
	for sub in _sections:
		var show: bool = visible_per_section.has(sub)
		_sections[sub]["header"].visible = show
		_sections[sub]["grid"].visible = show
