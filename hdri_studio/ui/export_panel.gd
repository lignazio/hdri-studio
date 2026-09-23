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
var _colorspace: OptionButton


func _init() -> void:
	var title := Label.new()
	title.text = "Export"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	_res = _option("Resolution", ["2k × 1k", "4k × 2k", "8k × 4k"])
	_res.item_selected.connect(func(i: int) -> void: resolution_changed.emit(RESOLUTIONS[i]))
	_target = _option("Software", HdriExport.TARGETS.keys())
	_target.selected = HdriExport.TARGETS.keys().find(HdriExport.DEFAULT_TARGET)
	_shift = ParamRow.new("Rotation", -180.0, 180.0, 1.0)
	add_child(_shift)
	_half = CheckBox.new()
	_half.text = "EXR half (16 bit)"
	_half.button_pressed = true
	add_child(_half)
	_colorspace = _option("Color space", HdriExport.COLORSPACES)
	_colorspace.tooltip_text = "Primaries of the exported EXR. The preview stays Rec.709. With ACEScg the values are converted\n(Rec.709 → AP1 with Bradford adaptation) and the metadata declares AP1 primaries with a D60 white point."
	_codec = _option("Compression", [])
	var native := ExrCodec.available()
	for c in ExrCodec.CODECS:
		_codec.add_item(c + ("  (lossy)" if c in ExrCodec.LOSSY else ""))
		if not native and c != "PIZ":
			_codec.set_item_disabled(_codec.item_count - 1, true)
	_codec.tooltip_text = (tr("Written by OpenEXR %s. Lossless: PIZ, ZIP, ZIPS, RLE, NONE. Lossy: PXR24 (float → 24 bit), B44, B44A, DWAA, DWAB.\nThe live link always uses PIZ.") % ExrCodec.version()) if native \
		else "OpenEXR library not loaded: Godot only writes PIZ."

	var row := HBoxContainer.new()
	add_child(row)
	var b := Button.new()
	b.text = "Export EXR…"
	b.pressed.connect(func() -> void: export_requested.emit())
	row.add_child(b)
	var of := Button.new()
	of.text = "Open folder"
	of.tooltip_text = "Opens the folder of the last export in Finder/Explorer"
	of.pressed.connect(func() -> void: open_folder_requested.emit())
	row.add_child(of)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	add_child(sep)
	var row2 := HBoxContainer.new()
	add_child(row2)
	var bs := Button.new()
	bs.text = "Save rig…"
	bs.pressed.connect(func() -> void: save_rig_requested.emit())
	row2.add_child(bs)
	var bl := Button.new()
	bl.text = "Open rig…"
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
	return ExrCodec.CODECS[_codec.selected]


func acescg() -> bool:
	return _colorspace.selected == 1
