class_name LightListPanel
extends VBoxContainer
## Lista delle luci (Tree): icone per riga — occhio = visibile, pallino = solo, lucchetto = bloccata
## (bianca = attiva, grigia = off) — multi-selezione, riordino con drag & drop, aggiungi / duplica /
## elimina / specchia / ▲▼.

const BTN_ENABLED := 0
const BTN_SOLO := 1
const BTN_LOCKED := 2
const COL_ON := Color(1, 1, 1, 0.95)
## Spento: 0,4 (a 0,28 il contrasto era 2,5:1) e, per l'occhio, anche una forma diversa.
const COL_OFF := Color(1, 1, 1, 0.4)

signal selection_changed(index: int)
## Tutte le luci selezionate (la primaria è quella passata a selection_changed).
signal multi_selection_changed(indices: Array)
## La struttura del rig è cambiata (luce aggiunta/rimossa/duplicata).
signal structure_changed()
## Uno stato (visibile / solo / bloccata) è cambiato da un'icona della lista.
signal state_changed()
## L'utente ha scelto "Texture" dal menu: serve un file (main apre la dialog).
signal texture_light_requested()

var rig: LightRig
var list: Tree
var _root: TreeItem
var _syncing := false
var _add_menu: MenuButton
var _btn_dup: Button
var _btn_del: Button
var _btn_up: Button
var _btn_down: Button

const SHAPE_LABELS := ["Rectangle", "Ellipse", "Ring", "Gradient", "Scrim", "Texture"]


func _init() -> void:
	# niente titolo "Luci": è già il nome della scheda
	list = Tree.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 160
	list.hide_root = true
	list.columns = 1
	list.select_mode = Tree.SELECT_MULTI
	list.allow_reselect = true
	list.drop_mode_flags = Tree.DROP_MODE_INBETWEEN
	# riordino trascinando: il dato viaggia come Dictionary, il rilascio sposta la voce (o il gruppo
	# selezionato) prima o dopo la voce sotto il cursore
	list.set_drag_forwarding(_drag_data, _can_drop, _drop)
	list.multi_selected.connect(func(item: TreeItem, _col: int, sel: bool) -> void:
		if _syncing:
			return
		var i: int = item.get_metadata(0)
		var primary := i if sel else selected_index()
		selection_changed.emit(primary)
		multi_selection_changed.emit(selected_indices())
		_update_buttons())
	list.button_clicked.connect(_on_button)
	add_child(list)
	_root = list.create_item()
	var row := HBoxContainer.new()
	add_child(row)
	_add_menu = MenuButton.new()
	_add_menu.text = "+ Add"
	_add_menu.flat = false
	for i in SHAPE_LABELS.size():
		_add_menu.get_popup().add_item(SHAPE_LABELS[i], i)
	_add_menu.get_popup().id_pressed.connect(_on_add)
	row.add_child(_add_menu)
	_btn_dup = Button.new()
	_btn_dup.text = "Duplicate"
	_btn_dup.pressed.connect(_on_duplicate)
	row.add_child(_btn_dup)
	_btn_del = Button.new()
	_btn_del.text = "Delete"
	_btn_del.pressed.connect(_on_delete)
	row.add_child(_btn_del)
	var mir := Button.new()
	mir.text = "⇋"
	mir.tooltip_text = "Duplicate mirrored (left ↔ right)"
	mir.pressed.connect(_on_mirror)
	row.add_child(mir)
	_btn_up = Button.new()
	_btn_up.text = "▲"
	_btn_up.tooltip_text = "Move up (lights later in the list cover earlier ones with Normal blending)"
	_btn_up.pressed.connect(func() -> void: _move(-1))
	row.add_child(_btn_up)
	_btn_down = Button.new()
	_btn_down.text = "▼"
	_btn_down.tooltip_text = "Move down"
	_btn_down.pressed.connect(func() -> void: _move(1))
	row.add_child(_btn_down)


func set_rig(r: LightRig) -> void:
	rig = r
	refresh()


func _items() -> Array:
	return _root.get_children() if _root != null else []


func _item(index: int) -> TreeItem:
	var items := _items()
	return items[index] if index >= 0 and index < items.size() else null


## Rettangolo (in coordinate del Tree) della voce index — usato dai test.
func item_rect(index: int) -> Rect2:
	var it := _item(index)
	return list.get_item_area_rect(it) if it != null else Rect2()


func selected_indices() -> Array:
	var out: Array = []
	var it := list.get_next_selected(null)
	while it != null:
		out.append(it.get_metadata(0))
		it = list.get_next_selected(it)
	out.sort()
	return out


func selected_index() -> int:
	var sel := selected_indices()
	return sel[0] if sel.size() > 0 else -1


func select(index: int) -> void:
	_syncing = true
	list.deselect_all()
	var it := _item(index)
	if it != null:
		it.select(0)
	_syncing = false
	_update_buttons()


func select_many(indices: Array) -> void:
	_syncing = true
	list.deselect_all()
	for i in indices:
		var it := _item(i)
		if it != null:
			it.select(0)
	_syncing = false
	_update_buttons()


func refresh() -> void:
	var prev_all := selected_indices()
	_syncing = true
	list.clear()
	_root = list.create_item()
	for i in rig.lights.size():
		var l: RigLight = rig.lights[i]
		var it := _root.create_child()
		it.set_text(0, l.name + ("  ⇗" if l.separate else ""))
		it.set_metadata(0, i)
		it.set_custom_color(0, COL_ON if l.enabled else Color(1, 1, 1, 0.45))
		it.add_button(0, LightIcons.eye() if l.enabled else LightIcons.eye_off(), BTN_ENABLED, false, "Visible (H)")
		it.add_button(0, LightIcons.dot(), BTN_SOLO, false, "Solo")
		it.add_button(0, LightIcons.lock(), BTN_LOCKED, false, "Locked: LightPaint, map and arrow keys will not move it")
		it.set_button_color(0, 0, COL_ON if l.enabled else COL_OFF)
		it.set_button_color(0, 1, COL_ON if l.solo else COL_OFF)
		it.set_button_color(0, 2, COL_ON if l.locked else COL_OFF)
	_syncing = false
	select_many(prev_all)
	_update_buttons()


func _on_button(item: TreeItem, _col: int, id: int, mouse: int) -> void:
	if mouse != MOUSE_BUTTON_LEFT:
		return
	var i: int = item.get_metadata(0)
	var l: RigLight = rig.lights[i]
	match id:
		BTN_ENABLED:
			l.enabled = not l.enabled
		BTN_SOLO:
			l.solo = not l.solo
		BTN_LOCKED:
			l.locked = not l.locked
	refresh()
	state_changed.emit()


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
	l.name = "%s %d" % [tr(SHAPE_LABELS[shape_id]), rig.lights.size() + 1]
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


func _drag_data(at_position: Vector2) -> Variant:
	var it := list.get_item_at_position(at_position)
	if it == null:
		return null
	var i: int = it.get_metadata(0)
	var moving: Array = selected_indices() if i in selected_indices() else [i]
	var preview := Label.new()
	preview.text = "  ".join(moving.map(func(k: int) -> String: return rig.lights[k].name))
	preview.modulate = Color(1, 1, 1, 0.85)
	list.set_drag_preview(preview)
	return {"type": "light_reorder", "indices": moving}


func _can_drop(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type", "") == "light_reorder"


func _drop(at_position: Vector2, data: Variant) -> void:
	var moving: Array = data["indices"]
	moving.sort()
	# destinazione: prima o dopo la voce sotto il cursore (metà superiore / inferiore), altrimenti in fondo
	var target_item := list.get_item_at_position(at_position)
	var insert_at := rig.lights.size()
	if target_item != null:
		var target: int = target_item.get_metadata(0)
		var r := list.get_item_area_rect(target_item)
		insert_at = target if at_position.y < r.position.y + r.size.y * 0.5 else target + 1
	var block: Array = []
	for k in moving:
		block.append(rig.lights[k])
	# tolgo le voci spostate (dal fondo) correggendo la destinazione per quelle che stavano prima
	var removed_before := 0
	for k in moving:
		if k < insert_at:
			removed_before += 1
	var rev := moving.duplicate()
	rev.reverse()
	for k in rev:
		rig.lights.remove_at(k)
	insert_at -= removed_before
	insert_at = clampi(insert_at, 0, rig.lights.size())
	var new_idx: Array = []
	for n in block.size():
		rig.lights.insert(insert_at + n, block[n])
		new_idx.append(insert_at + n)
	refresh()
	select_many(new_idx)
	structure_changed.emit()
	selection_changed.emit(new_idx[0])
	multi_selection_changed.emit(new_idx)


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
		copy.name += " " + tr("copy")
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
