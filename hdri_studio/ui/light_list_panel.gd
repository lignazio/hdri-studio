class_name LightListPanel
extends VBoxContainer
## Lista delle luci con aggiungi / duplica / elimina.

signal selection_changed(index: int)
## Tutte le luci selezionate (la primaria è quella passata a selection_changed).
signal multi_selection_changed(indices: Array)
## La struttura del rig è cambiata (luce aggiunta/rimossa/duplicata).
signal structure_changed()
## L'utente ha scelto "Texture" dal menu: serve un file (main apre la dialog).
signal texture_light_requested()

var rig: LightRig
var list: ItemList
var _add_menu: MenuButton
var _btn_dup: Button
var _btn_del: Button
var _btn_up: Button
var _btn_down: Button

const SHAPE_LABELS := ["Rettangolo", "Ellisse", "Anello", "Gradiente", "Scrim", "Texture"]


func _init() -> void:
	var title := Label.new()
	title.text = "Luci"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 160
	list.select_mode = ItemList.SELECT_MULTI
	list.multi_selected.connect(func(i: int, sel: bool) -> void:
		var primary := i if sel else selected_index()
		selection_changed.emit(primary)
		multi_selection_changed.emit(selected_indices())
		_update_buttons())
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
	var mir := Button.new()
	mir.text = "⇋"
	mir.tooltip_text = "Duplica specchiata (sinistra ↔ destra)"
	mir.pressed.connect(_on_mirror)
	row.add_child(mir)
	_btn_up = Button.new()
	_btn_up.text = "▲"
	_btn_up.tooltip_text = "Sposta su (le luci dopo nell'elenco coprono quelle prima con la fusione Normale)"
	_btn_up.pressed.connect(func() -> void: _move(-1))
	row.add_child(_btn_up)
	_btn_down = Button.new()
	_btn_down.text = "▼"
	_btn_down.tooltip_text = "Sposta giù"
	_btn_down.pressed.connect(func() -> void: _move(1))
	row.add_child(_btn_down)


func set_rig(r: LightRig) -> void:
	rig = r
	refresh()


func selected_index() -> int:
	var sel := list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func selected_indices() -> Array:
	var out: Array = []
	for i in list.get_selected_items():
		out.append(i)
	out.sort()
	return out


func select(index: int) -> void:
	if index >= 0 and index < list.item_count:
		list.select(index, true)
	else:
		list.deselect_all()
	_update_buttons()


func select_many(indices: Array) -> void:
	list.deselect_all()
	for i in indices:
		if i >= 0 and i < list.item_count:
			list.select(i, false)
	_update_buttons()


func refresh() -> void:
	var prev_all := selected_indices()
	list.clear()
	for l in rig.lights:
		var txt := l.name
		if not l.enabled:
			txt += "  (off)"
		if l.solo:
			txt += "  [solo]"
		if l.separate:
			txt += "  ⇗"
		list.add_item(txt)
	select_many(prev_all)
	_update_buttons()


func _update_buttons() -> void:
	_btn_dup.disabled = rig.lights.is_empty()
	_btn_del.disabled = rig.lights.is_empty()
	var sel := selected_index()
	_btn_up.disabled = sel <= 0
	_btn_down.disabled = sel < 0 or sel >= rig.lights.size() - 1


func _on_add(shape_id: int) -> void:
	if shape_id == RigLight.Shape.TEXTURE:
		texture_light_requested.emit()
		return
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
			l.gradient_stops = [[0.0, 1.0, 1.0, 1.0], [1.0, 0.0, 0.0, 0.0]]
		RigLight.Shape.RING:
			l.width = 30.0
			l.height = 30.0
			l.intensity = 4.0
		_:
			l.intensity = 4.0
	l.elevation = 30.0
	l.corner_radius = 3.0
	add_and_select(l)


## Aggiunge una luce già configurata (dal catalogo o da file) e la seleziona.
func add_and_select(l: RigLight) -> void:
	rig.add_light(l)
	refresh()
	select(rig.lights.size() - 1)
	structure_changed.emit()
	selection_changed.emit(rig.lights.size() - 1)


func _move(delta: int) -> void:
	var i := selected_index()
	var j := i + delta
	if i < 0 or j < 0 or j >= rig.lights.size():
		return
	var l: RigLight = rig.lights[i]
	rig.lights.remove_at(i)
	rig.lights.insert(j, l)
	refresh()
	select(j)
	_update_buttons()
	structure_changed.emit()
	selection_changed.emit(j)


func _on_duplicate() -> void:
	var sel := selected_indices()
	if sel.is_empty():
		return
	var copies: Array = []
	for i in sel:
		var copy: RigLight = rig.lights[i].duplicate_light()
		copy.name += " copia"
		copy.azimuth = wrapf(copy.azimuth + 10.0, -180.0, 180.0)
		copies.append(copy)
	var at: int = sel[sel.size() - 1] + 1
	var new_idx: Array = []
	for k in copies.size():
		rig.lights.insert(at + k, copies[k])
		new_idx.append(at + k)
	refresh()
	select_many(new_idx)
	structure_changed.emit()
	selection_changed.emit(new_idx[0])
	multi_selection_changed.emit(new_idx)


func _on_delete() -> void:
	var sel := selected_indices()
	if sel.is_empty():
		return
	sel.reverse()
	for i in sel:
		rig.lights.remove_at(i)
	refresh()
	var ni: int = mini(sel[sel.size() - 1], rig.lights.size() - 1)
	select(ni)
	structure_changed.emit()
	selection_changed.emit(ni)
	multi_selection_changed.emit([ni] if ni >= 0 else [])


func _on_mirror() -> void:
	var sel := selected_indices()
	if sel.is_empty():
		return
	var new_idx: Array = []
	for i in sel:
		rig.lights.append(rig.lights[i].mirrored())
		new_idx.append(rig.lights.size() - 1)
	refresh()
	select_many(new_idx)
	structure_changed.emit()
	selection_changed.emit(new_idx[0])
	multi_selection_changed.emit(new_idx)


## Accende/spegne tutte le selezionate (in blocco, verso lo stato opposto della primaria).
func toggle_selected_enabled() -> void:
	var sel := selected_indices()
	if sel.is_empty():
		return
	var target: bool = not rig.lights[selected_index()].enabled
	for i in sel:
		rig.lights[i].enabled = target
	refresh()
