class_name ExportPanel
extends VBoxContainer
## Risoluzione, formato, preset di orientamento, export e file di rig.

signal export_requested()
signal save_rig_requested()
signal load_rig_requested()
signal resolution_changed(res: Vector2i)

const RESOLUTIONS := [Vector2i(2048, 1024), Vector2i(4096, 2048), Vector2i(8192, 4096)]

var _res: OptionButton
var _half: CheckBox
var _target: OptionButton
var _shift: ParamRow
var _status: Label


func _init() -> void:
	var title := Label.new()
	title.text = "Export"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	_res = _option("Risoluzione", ["2k × 1k", "4k × 2k", "8k × 4k"])
	_res.item_selected.connect(func(i: int) -> void: resolution_changed.emit(RESOLUTIONS[i]))
	_target = _option("Software", HdriExport.TARGETS.keys())
	_shift = ParamRow.new("Rotazione", -180.0, 180.0, 1.0)
	add_child(_shift)
	_half = CheckBox.new()
	_half.text = "EXR half (16 bit)"
	_half.button_pressed = true
	add_child(_half)

	var row := HBoxContainer.new()
	add_child(row)
	var b := Button.new()
	b.text = "Esporta EXR…"
	b.pressed.connect(func() -> void: export_requested.emit())
	row.add_child(b)
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
