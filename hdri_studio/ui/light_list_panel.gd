class_name LightListPanel
extends VBoxContainer
## Lista delle luci con aggiungi / duplica / elimina.

signal selection_changed(index: int)
## La struttura del rig è cambiata (luce aggiunta/rimossa/duplicata).
signal structure_changed()

var rig: LightRig
var list: ItemList
var _add_menu: MenuButton
var _btn_dup: Button
var _btn_del: Button

const SHAPE_LABELS := ["Rettangolo", "Ellisse", "Anello", "Gradiente", "Scrim"]


func _init() -> void:
	var title := Label.new()
	title.text = "Luci"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 160
	list.item_selected.connect(func(i: int) -> void: selection_changed.emit(i))
	add_child(list)
	var row := HBoxContainer.new()
	add_child(row)
	_add_menu = MenuButton.new()
	_add_menu.text = "+ Aggiungi"
	_add_menu.flat = false
	for i in SHAPE_LABELS.size():
		_add_menu.get_popup().add_item(SHAPE_LABELS[i], i)
	_add_menu.get_popup().id_pressed.connect(_on_add)
	row.add_child(_add_menu)
	_btn_dup = Button.new()
	_btn_dup.text = "Duplica"
	_btn_dup.pressed.connect(_on_duplicate)
	row.add_child(_btn_dup)
	_btn_del = Button.new()
	_btn_del.text = "Elimina"
	_btn_del.pressed.connect(_on_delete)
	row.add_child(_btn_del)


func set_rig(r: LightRig) -> void:
	rig = r
	refresh()


func selected_index() -> int:
	var sel := list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func select(index: int) -> void:
	if index >= 0 and index < list.item_count:
		list.select(index)
	else:
		list.deselect_all()


func refresh() -> void:
	var prev := selected_index()
	list.clear()
	for l in rig.lights:
		var txt := l.name
		if not l.enabled:
			txt += "  (off)"
		if l.solo:
			txt += "  [solo]"
		list.add_item(txt)
	select(prev)
	_btn_dup.disabled = rig.lights.is_empty()
	_btn_del.disabled = rig.lights.is_empty()


func _on_add(shape_id: int) -> void:
	var l := RigLight.new()
	l.shape = shape_id as RigLight.Shape
	l.name = "%s %d" % [SHAPE_LABELS[shape_id], rig.lights.size() + 1]
	match l.shape:
		RigLight.Shape.SCRIM:
			l.width = 60.0
			l.height = 40.0
			l.intensity = 6.0
		RigLight.Shape.GRADIENT:
			l.width = 60.0
			l.height = 45.0
			l.softness = 0.0
		RigLight.Shape.RING:
			l.width = 30.0
			l.height = 30.0
			l.intensity = 4.0
		_:
			l.intensity = 4.0
	l.elevation = 30.0
	rig.add_light(l)
	refresh()
	select(rig.lights.size() - 1)
	structure_changed.emit()
	selection_changed.emit(rig.lights.size() - 1)


func _on_duplicate() -> void:
	var i := selected_index()
	if i < 0:
		return
	var copy := rig.lights[i].duplicate_light()
	copy.name += " copia"
	copy.azimuth = wrapf(copy.azimuth + 10.0, -180.0, 180.0)
	rig.lights.insert(i + 1, copy)
	refresh()
	select(i + 1)
	structure_changed.emit()
	selection_changed.emit(i + 1)


func _on_delete() -> void:
	var i := selected_index()
	if i < 0:
		return
	rig.lights.remove_at(i)
	refresh()
	var ni: int = mini(i, rig.lights.size() - 1)
	select(ni)
	structure_changed.emit()
	selection_changed.emit(ni)
