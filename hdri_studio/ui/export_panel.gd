class_name ExportPanel
extends VBoxContainer
## Risoluzione, formato, preset di orientamento, export e file di rig.

signal export_requested()
signal open_folder_requested()
signal save_rig_requested()
signal load_rig_requested()
signal resolution_changed(res: Vector2i)
## Il software di destinazione è cambiato (lo usa anche il live link).
signal target_changed(target: String)

const RESOLUTIONS := [Vector2i(2048, 1024), Vector2i(4096, 2048), Vector2i(8192, 4096)]

var _res: OptionButton
var _half: CheckBox
var _target: OptionButton
var _shift: ParamRow
var _status: Label
var _codec: OptionButton
var _colorspace: OptionButton
var _export_btn: Button


func _init() -> void:
	add_child(UiStyle.title("Export"))

	_res = _option("Resolution", ["2k × 1k", "4k × 2k", "8k × 4k"])
	_res.item_selected.connect(func(i: int) -> void: resolution_changed.emit(RESOLUTIONS[i]))
	_target = _option("Software", HdriExport.TARGETS.keys())
	_target.selected = HdriExport.TARGETS.keys().find(HdriExport.DEFAULT_TARGET)
	_target.item_selected.connect(func(_i: int) -> void: target_changed.emit(target()))
	# "Rotazione" c'era già due volte nella colonna (Ruota tutto, HDRI di base): questa è un'altra cosa
	_shift = ParamRow.new("Extra rotation", -180.0, 180.0, 1.0)
	_shift.tooltip_text = "Added to the orientation preset of the chosen software"
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

	add_child(UiStyle.spacer(UiStyle.SPACE_INLINE - UiStyle.SPACE_ROW))
	var row := HBoxContainer.new()
	add_child(row)
	# l'azione per cui esiste l'app: l'unico pulsante d'accento, largo quanto la colonna
	_export_btn = Button.new()
	_export_btn.text = "Export EXR…"
	_export_btn.theme_type_variation = "AccentButton"
	_export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_btn.pressed.connect(func() -> void: export_requested.emit())
	row.add_child(_export_btn)
	var of := Button.new()
	of.text = "Open folder"
	of.flat = true
	of.tooltip_text = "Opens the folder of the last export in Finder/Explorer"
	of.pressed.connect(func() -> void: open_folder_requested.emit())
	row.add_child(of)
	add_child(UiStyle.spacer(UiStyle.SPACE_GROUP - UiStyle.SPACE_ROW))
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
	_status = UiStyle.status()
	add_child(_status)


func _option(label: String, items: Array) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(it)
	add_child(UiStyle.field_row(label, ob))
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


## Durante un export il pulsante non si può ripremere (il bake blocca la finestra per qualche secondo).
func set_busy(busy: bool) -> void:
	_export_btn.disabled = busy


func codec() -> String:
	return ExrCodec.CODECS[_codec.selected]


func acescg() -> bool:
	return _colorspace.selected == 1
