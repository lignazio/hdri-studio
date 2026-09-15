class_name ExportPanel
extends VBoxContainer
## Risoluzione, formato, preset di orientamento, export e file di rig.

signal export_requested()
signal open_folder_requested()
signal save_rig_requested()
signal load_rig_requested()
signal resolution_changed(res: Vector2i)

const RESOLUTIONS := [Vector2i(2048, 1024), Vector2i(4096, 2048), Vector2i(8192, 4096)]

var _res: OptionButton
var _half: CheckBox
var _target: OptionButton
var _shift: ParamRow
var _status: Label
var _codec: OptionButton
var _blender_label: Label

signal blender_pick_requested()


func _init() -> void:
	var title := Label.new()
	title.text = "Export"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	_res = _option("Risoluzione", ["2k × 1k", "4k × 2k", "8k × 4k"])
	_res.item_selected.connect(func(i: int) -> void: resolution_changed.emit(RESOLUTIONS[i]))
	_target = _option("Software", HdriExport.TARGETS.keys())
	_target.selected = HdriExport.TARGETS.keys().find(HdriExport.DEFAULT_TARGET)
	_shift = ParamRow.new("Rotazione", -180.0, 180.0, 1.0)
	add_child(_shift)
	_half = CheckBox.new()
	_half.text = "EXR half (16 bit)"
	_half.button_pressed = true
	add_child(_half)
	_codec = _option("Compressione", [])
	for c in ExrConvert.CODECS:
		_codec.add_item(c if c == "PIZ" else c + "  (via Blender)")
	_codec.tooltip_text = "PIZ è nativo. Gli altri codec riconvertono il file con Blender in background dopo l'export.\nLossless: ZIP, ZIPS, RLE, NONE. Lossy: PXR24, B44, B44A, DWAA, DWAB."
	var brow := HBoxContainer.new()
	add_child(brow)
	_blender_label = Label.new()
	_blender_label.clip_text = true
	_blender_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_blender_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blender_label.modulate = Color(1, 1, 1, 0.6)
	_blender_label.add_theme_font_size_override("font_size", 12)
	brow.add_child(_blender_label)
	var bb := Button.new()
	bb.text = "Blender…"
	bb.tooltip_text = "Eseguibile di Blender per la riconversione (rilevato automaticamente se installato nel percorso standard)"
	bb.pressed.connect(func() -> void: blender_pick_requested.emit())
	brow.add_child(bb)
	refresh_blender()

	var row := HBoxContainer.new()
	add_child(row)
	var b := Button.new()
	b.text = "Esporta EXR…"
	b.pressed.connect(func() -> void: export_requested.emit())
	row.add_child(b)
	var of := Button.new()
	of.text = "Apri cartella"
	of.tooltip_text = "Apre nel Finder/Esplora la cartella dell'ultimo export"
	of.pressed.connect(func() -> void: open_folder_requested.emit())
	row.add_child(of)
	var sep := HSeparator.new()
	add_child(sep)
	var row2 := HBoxContainer.new()
	add_child(row2)
	var bs := Button.new()
	bs.text = "Salva rig…"
	bs.pressed.connect(func() -> void: save_rig_requested.emit())
	row2.add_child(bs)
	var bl := Button.new()
	bl.text = "Apri rig…"
	bl.pressed.connect(func() -> void: load_rig_requested.emit())
	row2.add_child(bl)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)


func _option(label: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 96
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		ob.add_item(it)
	row.add_child(ob)
	return ob


func resolution() -> Vector2i:
	return RESOLUTIONS[_res.selected]


func set_resolution(res: Vector2i) -> void:
	var i := RESOLUTIONS.find(res)
	_res.selected = i if i >= 0 else 1


func half() -> bool:
	return _half.button_pressed


func target() -> String:
	return _target.get_item_text(_target.selected)


func extra_shift() -> float:
	return _shift.get_value()


func set_status(text: String) -> void:
	_status.text = text


func codec() -> String:
	return ExrConvert.CODECS[_codec.selected]


func refresh_blender() -> void:
	var b := ExrConvert.find_blender()
	_blender_label.text = ("Blender: " + b.get_file()) if b != "" else "Blender non trovato: solo PIZ"
	_blender_label.tooltip_text = b
