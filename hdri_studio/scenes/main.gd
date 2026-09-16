extends Control
## HDRI Studio — app principale (Fase 1).
## Layout: [luci + proprietà] | [preview 3D / mappa] | [sfondo + export].
## Ogni modifica marca il rig come dirty; il bake avviene al massimo una volta per frame.

const PREVIEW_RES := Vector2i(2048, 1024)
const PREVIEW_EV_STEP := 0.5
## Attesa dopo l'ultima modifica prima dell'export automatico del live link.
const LIVE_DEBOUNCE_MS := 300

var baker: HdriBaker
var rig: LightRig
var tex_rd: Texture2DRD
var undo := UndoStack.new()

var preview: Preview3D
var map_view: MapView
var light_list: LightListPanel
var props: LightProperties
var bg_panel: BackgroundPanel
var export_panel: ExportPanel
var link_panel: LiveLinkPanel
var link: LiveLink
var catalog: CatalogPanel
var presets: PresetPanel
var _hover: PanelContainer
var _hover_tex: TextureRect
var _hover_label: Label
var status: Label

var _dirty := true
var _preview_ev := 0.0
var _selected := -1
var _selection: Array = []
var _map_cpu: Image
var _map_cpu_dirty := true
var _map_cpu_ms := 0
var _hover_az := INF
var _hover_el := INF
var _ev_row: ParamRow
var meter := LightMeter.new()
var _meter_mode: OptionButton
var _meter_az: SpinBox
var _meter_el: SpinBox
var _meter_label: Label
var _meter_dirty := true
var _clip_check: CheckBox
var _clip_row: ParamRow
var _link_camera: CheckBox
var _rig_path := ""
var _screenshot_frames := -1
var _file_dialog: FileDialog
var _live_dirty := false
var _live_deadline := 0
var _link_hosts := {}
var _model_label: Label
## Luci separate scritte dall'ultimo export (per il messaggio al plugin).
var _last_separate: Array = []
var _convert_pid := -1
var _convert_files: Array = []
var _last_export_path := ""
var _autosave_ms := 0
var _live_change_ms := 0
var _live_full_pending := false
const AUTOSAVE_MS := 60000
## Sotto questa pausa fra due modifiche il live link esporta a metà risoluzione, poi rifinisce.
const LIVE_FAST_WINDOW_MS := 1500


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	baker = HdriBaker.new(false)
	baker.supersample = 1
	baker.set_resolution(PREVIEW_RES.x, PREVIEW_RES.y)
	tex_rd = Texture2DRD.new()
	tex_rd.texture_rd_rid = baker.texture

	link = LiveLink.new()
	add_child(link)
	link.message_received.connect(_on_link_message)
	link.clients_changed.connect(func(n: int) -> void:
		if n == 0:
			_link_hosts.clear()
		_update_link_status())

	rig = _default_rig()
	_build_layout()
	_bind_rig()
	undo.reset(rig.to_dict())
	_select(0)

	# riapre l'ultimo rig salvato/aperto
	var args := OS.get_cmdline_user_args()
	var last: String = AppSettings.get_value("last_rig", "")
	if last != "" and FileAccess.file_exists(last) and not ("--fresh" in args or "--screenshot" in args or "--selftest" in args):
		load_rig_from(last)
	_autosave_ms = Time.get_ticks_msec()
	if "--screenshot" in OS.get_cmdline_user_args():
		_screenshot_frames = 12
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest.call_deferred()


## Verifica da riga di comando (anche nell'app esportata): bake, export EXR, rilettura.
func _selftest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var path := "user://selftest.exr"
	var err := export_to(path, {"resolution": Vector2i(1024, 512), "quiet": true})
	var back := Image.new()
	var err2 := back.load_exr_from_buffer(FileAccess.get_file_as_bytes(path))
	var c := back.get_pixel(back.get_width() / 2, back.get_height() / 2) if err2 == OK else Color.BLACK
	print("[selftest] export %s · rilettura %s · %dx%d · pixel centro %s · %s" % [
		error_string(err), error_string(err2), back.get_width(), back.get_height(), c,
		"OK" if err == OK and err2 == OK else "FALLITO"])
	get_tree().quit(0 if err == OK and err2 == OK else 1)


# --- layout ------------------------------------------------------------------------------------

func _build_layout() -> void:
	# split trascinabili: [sinistra | [centro | destra]], centro = [preview / mappa]
	var root := HSplitContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var rest := HSplitContainer.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# colonna sinistra: tab Luci / Catalogo
	var left := _column(root, 300)
	root.add_child(rest)
	root.split_offset = 360  # larghezza iniziale della colonna sinistra (assoluta: solo il secondo figlio espande)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tabs)
	var lights_tab := VBoxContainer.new()
	lights_tab.name = "Luci"
	lights_tab.add_theme_constant_override("separation", 8)
	tabs.add_child(lights_tab)
	light_list = LightListPanel.new()
	light_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	light_list.custom_minimum_size.y = 220
	lights_tab.add_child(light_list)
	lights_tab.add_child(_separator())
	props = LightProperties.new()
	lights_tab.add_child(props)
	catalog = CatalogPanel.new()
	catalog.name = "Catalogo"
	tabs.add_child(catalog)
	catalog.set_folder(AppSettings.get_value("catalog_folder", ""))
	presets = PresetPanel.new()
	presets.name = "Preset"
	tabs.add_child(presets)
	presets.set_folder(AppSettings.get_value("preset_folder", ""))

	# centro
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	rest.add_child(center)
	var vsplit := VSplitContainer.new()
	vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(vsplit)
	preview = Preview3D.new()
	preview.setup(tex_rd)
	preview.custom_minimum_size.y = 200
	vsplit.add_child(preview)
	map_view = MapView.new()
	map_view.custom_minimum_size.y = 220
	map_view.set_texture(tex_rd)
	vsplit.add_child(map_view)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.modulate = Color(1, 1, 1, 0.7)
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	center.add_child(status)

	# colonna destra
	var right := _column(rest, 300, true)
	bg_panel = BackgroundPanel.new()
	right.add_child(bg_panel)
	right.add_child(_separator())
	export_panel = ExportPanel.new()
	right.add_child(export_panel)
	right.add_child(_separator())
	link_panel = LiveLinkPanel.new()
	right.add_child(link_panel)
	right.add_child(_separator())
	_build_model_panel(right)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	add_child(_file_dialog)

	# anteprima grande al passaggio del mouse sulle miniature del catalogo, sopra tutto
	var hover_layer := CanvasLayer.new()
	hover_layer.layer = 10
	add_child(hover_layer)
	_hover = PanelContainer.new()
	_hover.visible = false
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hv := VBoxContainer.new()
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.add_child(hv)
	_hover_tex = TextureRect.new()
	_hover_tex.custom_minimum_size = Vector2(384, 192)
	_hover_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hover_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hover_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(_hover_tex)
	_hover_label = Label.new()
	_hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(_hover_label)
	hover_layer.add_child(_hover)

	# segnali
	light_list.selection_changed.connect(_select)
	light_list.multi_selection_changed.connect(func(idx: Array) -> void:
		_selection = idx.duplicate()
		map_view.set_selected(_selected, _selection))
	preview.pick.connect(_pick_light_by_reflection)
	map_view.hover_changed.connect(func(az: float, el: float) -> void:
		_hover_az = az
		_hover_el = el
		_update_status())
	light_list.structure_changed.connect(func() -> void: _on_light_changed(true))
	light_list.texture_light_requested.connect(func() -> void: _pick_texture_file(true))
	props.texture_pick_requested.connect(func() -> void: _pick_texture_file(false))
	catalog.light_requested.connect(_add_texture_light)
	map_view.light_dropped.connect(func(path: String, defaults: Dictionary, az: float, el: float) -> void:
		_add_texture_light(path, defaults, az, el))
	preview.light_dropped.connect(func(path: String, defaults: Dictionary, dir: Vector3) -> void:
		if dir == Vector3.ZERO:
			_add_texture_light(path, defaults)
		else:
			_add_texture_light(path, defaults, rad_to_deg(atan2(-dir.x, dir.z)), rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))))
	catalog.folder_pick_requested.connect(_pick_catalog_folder)
	catalog.hover_preview.connect(_show_hover)
	catalog.hover_end.connect(func() -> void: _hover.visible = false)
	presets.save_requested.connect(_save_preset)
	presets.load_requested.connect(_load_preset)
	presets.merge_requested.connect(_merge_preset)
	presets.folder_pick_requested.connect(_pick_preset_folder)
	export_panel.blender_pick_requested.connect(_pick_blender)
	props.changed.connect(_on_light_changed)
	props.light_renamed.connect(func() -> void: light_list.refresh(); map_view.refresh())
	map_view.light_selected.connect(func(i: int) -> void: light_list.select(i); _select(i))
	map_view.light_moved.connect(_on_map_move)
	preview.paint.connect(_on_paint)
	bg_panel.changed.connect(_on_light_changed)
	bg_panel.rotate_all.connect(func(delta: float, commit: bool) -> void:
		if delta != 0.0:
			rig.rotate_all(delta)
			props.sync_values()
		_on_light_changed(commit))
	bg_panel.base_hdri_requested.connect(_pick_base_hdri)
	export_panel.export_requested.connect(_export_exr)
	export_panel.open_folder_requested.connect(func() -> void:
		var dir := _last_export_path.get_base_dir() if _last_export_path != "" else String(AppSettings.get_value("export_dir", ""))
		if dir != "":
			OS.shell_open(dir))
	props.sidecar_save_requested.connect(_save_sidecar)
	export_panel.save_rig_requested.connect(_save_rig)
	export_panel.load_rig_requested.connect(_load_rig)
	export_panel.resolution_changed.connect(func(r: Vector2i) -> void: rig.resolution = r)
	link_panel.toggled_link.connect(_set_link_enabled)
	link_panel.pick_path_requested.connect(_pick_live_path)
	link_panel.push_now_requested.connect(func() -> void: _live_export())
	link_panel.separate_options_changed.connect(func() -> void: _live_export())
	_update_status()
	_update_link_status()


func _build_model_panel(parent: Container) -> void:
	var ptitle := Label.new()
	ptitle.text = "Preview"
	ptitle.add_theme_font_size_override("font_size", 15)
	parent.add_child(ptitle)
	parent.add_child(_spacer(2))
	_ev_row = ParamRow.new("Esposizione EV", -8.0, 8.0, 0.1)
	_ev_row.value_changed.connect(func(v: float) -> void:
		_preview_ev = v
		_apply_preview_exposure())
	parent.add_child(_ev_row)
	var fov_row := ParamRow.new("FOV °", 10.0, 120.0, 1.0)
	fov_row.set_value_silent(35.0)
	fov_row.value_changed.connect(func(v: float) -> void: preview.set_fov(v))
	parent.add_child(fov_row)
	var scale_row := ParamRow.new("Scala modello", 0.1, 5.0, 0.01, true)
	scale_row.set_value_silent(1.0)
	scale_row.value_changed.connect(func(v: float) -> void: preview.set_model_scale(v))
	parent.add_child(scale_row)
	var hint := Label.new()
	hint.text = "tasto destro sul preview: ruota il modello"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.5)
	parent.add_child(hint)
	# clipping: falsi colori sopra una soglia (mappa e sfera cromata)
	var crow := HBoxContainer.new()
	parent.add_child(crow)
	_clip_check = CheckBox.new()
	_clip_check.text = "Clipping"
	_clip_check.tooltip_text = "Evidenzia in magenta i pixel oltre la soglia, sulla mappa e sulla sfera cromata"
	_clip_check.toggled.connect(func(_v: bool) -> void: _apply_clipping())
	crow.add_child(_clip_check)
	_clip_row = ParamRow.new("Soglia", 0.1, 10000.0, 0.1, true)
	_clip_row.set_value_silent(1.0)
	_clip_row.value_changed.connect(func(_v: float) -> void: _apply_clipping())
	_clip_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(_clip_row)
	_link_camera = CheckBox.new()
	_link_camera.text = "Camera dal live link"
	_link_camera.tooltip_text = "Il preview segue la camera attiva del software 3D collegato (direzione, alto e FOV)"
	_link_camera.button_pressed = AppSettings.get_value("link_camera", false)
	_link_camera.toggled.connect(func(v: bool) -> void: AppSettings.set_value("link_camera", v))
	parent.add_child(_link_camera)

	# esposimetro
	parent.add_child(_spacer(6))
	var mtitle := Label.new()
	mtitle.text = "Esposimetro"
	mtitle.add_theme_font_size_override("font_size", 15)
	parent.add_child(mtitle)
	var meter_row := HBoxContainer.new()
	parent.add_child(meter_row)
	_meter_mode = OptionButton.new()
	for it in ["Verso la camera", "Verso l'alto", "Az / El"]:
		_meter_mode.add_item(it)
	_meter_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meter_mode.item_selected.connect(func(_i: int) -> void: _update_meter())
	meter_row.add_child(_meter_mode)
	_meter_az = SpinBox.new()
	_meter_az.min_value = -180
	_meter_az.max_value = 180
	_meter_az.suffix = "°"
	_meter_az.value_changed.connect(func(_v: float) -> void: _update_meter())
	meter_row.add_child(_meter_az)
	_meter_el = SpinBox.new()
	_meter_el.min_value = -90
	_meter_el.max_value = 90
	_meter_el.suffix = "°"
	_meter_el.value_changed.connect(func(_v: float) -> void: _update_meter())
	meter_row.add_child(_meter_el)
	_meter_label = Label.new()
	_meter_label.tooltip_text = "E = ∫ L·cosθ dω su tutta l'HDRI per una superficie al centro rivolta nella direzione scelta.\nEV100 = log2(E / 2.5): con radianze in unità fotometriche coerenti è l'EV di un esposimetro a luce incidente."
	parent.add_child(_meter_label)
	parent.add_child(_spacer(6))
	var title := Label.new()
	title.text = "Modello nel preview"
	title.add_theme_font_size_override("font_size", 15)
	parent.add_child(title)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var load_btn := Button.new()
	load_btn.text = "Carica GLB…"
	load_btn.pressed.connect(_pick_model)
	row.add_child(load_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Rimuovi"
	clear_btn.pressed.connect(func() -> void:
		preview.clear_model()
		_model_label.text = "—")
	row.add_child(clear_btn)
	var mrow := HBoxContainer.new()
	parent.add_child(mrow)
	var ml := Label.new()
	ml.text = "Materiale"
	ml.custom_minimum_size.x = 96
	mrow.add_child(ml)
	var mat := OptionButton.new()
	mat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in Preview3D.MATERIAL_LABELS:
		mat.add_item(it)
	mat.tooltip_text = "Materiale del modello caricato; senza modello, della sfera centrale"
	mat.item_selected.connect(func(i: int) -> void:
		if preview.has_model():
			preview.set_model_material(i as Preview3D.ModelMaterial)
		else:
			# senza modello vale per la sfera centrale; Originale = il suo glossy di partenza
			preview.set_center_sphere_material(i as Preview3D.ModelMaterial))
	mrow.add_child(mat)
	_model_label = Label.new()
	_model_label.text = "—"
	_model_label.clip_text = true
	_model_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_model_label.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(_model_label)


func _pick_model() -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.glb, *.gltf ; glTF"], "Modello per il preview", func(path: String) -> void:
		if preview.load_model(path):
			_model_label.text = path.get_file()
		else:
			_model_label.text = "Impossibile caricare " + path.get_file())


static func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _separator() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 16)
	return s


func _column(parent: Container, width: float, scroll := false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width * 0.8
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	if scroll:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		margin.add_child(sc)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(box)
	else:
		margin.add_child(box)
	return box


# --- stato ------------------------------------------------------------------------------------

func _bind_rig() -> void:
	light_list.set_rig(rig)
	map_view.set_rig(rig)
	bg_panel.set_rig(rig)
	export_panel.set_resolution(rig.resolution)
	link_panel.set_path(rig.live_export_path)
	if rig.base_hdri_path != "":
		baker.set_base_image_from_file(rig.base_hdri_path)
	_dirty = true
	_schedule_live()


func _select(i: int) -> void:
	_selected = i if i >= 0 and i < rig.lights.size() else -1
	if not (_selected in _selection):
		_selection = [_selected] if _selected >= 0 else []
	props.set_light(rig.lights[_selected] if _selected >= 0 else null)
	map_view.set_selected(_selected, _selection)


## Click su un riflesso nel preview: seleziona la luce (l'ultima nell'elenco) che lo produce.
func _pick_light_by_reflection(dir: Vector3) -> void:
	for i in range(rig.lights.size() - 1, -1, -1):
		var l: RigLight = rig.lights[i]
		if l.enabled and l.contains(dir):
			light_list.select(i)
			_selection = [i]
			_select(i)
			return


## Sposta tutte le luci selezionate di (daz, del) gradi.
func _nudge(daz: float, del: float, commit: bool) -> void:
	if _selection.is_empty():
		return
	for i in _selection:
		var l: RigLight = rig.lights[i]
		if l.locked:
			continue
		l.azimuth = wrapf(l.azimuth + daz, -180.0, 180.0)
		l.elevation = clampf(l.elevation + del, -90.0, 90.0)
	props.sync_values()
	_on_light_changed(commit)


func _on_light_changed(commit: bool) -> void:
	_dirty = true
	_live_full_pending = true
	_schedule_live()
	map_view.refresh()
	light_list.refresh()
	if commit:
		_commit()


func _on_map_move(i: int, az: float, el: float, commit: bool) -> void:
	var l: RigLight = rig.lights[i]
	var daz := wrapf(az - l.azimuth, -180.0, 180.0)
	var del := el - l.elevation
	if i in _selection and _selection.size() > 1:
		# trascinare una luce del gruppo sposta tutto il gruppo
		for j in _selection:
			var o: RigLight = rig.lights[j]
			if o.locked:
				continue
			o.azimuth = wrapf(o.azimuth + daz, -180.0, 180.0)
			o.elevation = clampf(o.elevation + del, -90.0, 90.0)
	else:
		l.azimuth = az
		l.elevation = el
	props.sync_values()
	_on_light_changed(commit)


func _on_paint(dir: Vector3, commit: bool) -> void:
	if _selected < 0:
		# nessuna luce selezionata: il LightPaint ne crea una nuova
		var nl := RigLight.new()
		nl.name = "Paint %d" % (rig.lights.size() + 1)
		nl.intensity = 4.0
		nl.softness = 1.0
		light_list.add_and_select(nl)
	var l: RigLight = rig.lights[_selected]
	if l.locked:
		export_panel.set_status("La luce \"%s\" è bloccata (🔒): il LightPaint non la sposta" % l.name)
		return
	l.azimuth = rad_to_deg(atan2(-dir.x, dir.z))
	l.elevation = rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	props.sync_values()
	_on_light_changed(commit)


func _commit() -> void:
	undo.push(rig.to_dict())
	_update_status()


func _restore(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	rig = LightRig.from_dict(snapshot)
	_bind_rig()
	_select(clampi(_selected, -1, rig.lights.size() - 1))
	light_list.select(_selected)
	_update_status()


func _process(_delta: float) -> void:
	if _dirty:
		baker.bake(rig)
		preview.notify_sky_changed()
		_dirty = false
		_map_cpu_dirty = true
		_meter_dirty = true
		if _hover_az != INF:
			_update_status()
	if _meter_dirty and Time.get_ticks_msec() - _map_cpu_ms > 300:
		_meter_dirty = false
		_update_meter()
		if _selected >= 0 and _selected < rig.lights.size() and rig.lights[_selected].photometric:
			props.sync_values()
	if _live_dirty and Time.get_ticks_msec() >= _live_deadline:
		_live_dirty = false
		_live_export()
	if Time.get_ticks_msec() - _autosave_ms > AUTOSAVE_MS:
		_autosave_ms = Time.get_ticks_msec()
		_autosave()
	if _convert_pid >= 0 and not OS.is_process_running(_convert_pid):
		var code := OS.get_process_exit_code(_convert_pid)
		_convert_pid = -1
		if code == 0:
			# Blender riscrive l'header: i metadati vanno reiniettati
			var rig_json := JSON.stringify(rig.to_dict())
			for f in _convert_files:
				HdriExport.inject_metadata(f, rig_json)
		export_panel.set_status("Riconversione %s: %s (%d file)" % [export_panel.codec(), "fatta" if code == 0 else "fallita (codice %d)" % code, _convert_files.size()])
	if _screenshot_frames >= 0:
		_screenshot_frames -= 1
		if _screenshot_frames == 0:
			var img := get_viewport().get_texture().get_image()
			var shot := "res://out/app.png" if OS.has_feature("editor") else "user://app.png"
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot.get_base_dir()))
			img.save_png(ProjectSettings.globalize_path(shot))
			print("Screenshot salvato: " + ProjectSettings.globalize_path(shot))
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var step := 10.0 if event.shift_pressed else 1.0
		match event.keycode:
			KEY_LEFT:
				_nudge(-step, 0.0, false)
				accept_event()
				return
			KEY_RIGHT:
				_nudge(step, 0.0, false)
				accept_event()
				return
			KEY_UP:
				_nudge(0.0, step, false)
				accept_event()
				return
			KEY_DOWN:
				_nudge(0.0, -step, false)
				accept_event()
				return
	if event is InputEventKey and not event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		_commit() # fine di una sequenza di frecce: uno snapshot di undo
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed() and event.keycode == KEY_Z:
			_restore(undo.redo() if event.shift_pressed else undo.undo())
			accept_event()
		elif event.is_command_or_control_pressed() and event.keycode == KEY_D:
			light_list._on_duplicate()
			accept_event()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			light_list._on_delete()
			accept_event()
		elif event.keycode == KEY_H:
			light_list.toggle_selected_enabled()
			_on_light_changed(true)
			accept_event()
		elif event.keycode == KEY_Q or event.keycode == KEY_E:
			_preview_ev += PREVIEW_EV_STEP if event.keycode == KEY_E else -PREVIEW_EV_STEP
			_ev_row.set_value_silent(_preview_ev)
			_apply_preview_exposure()
			accept_event()


func _apply_preview_exposure() -> void:
	var k := pow(2.0, _preview_ev)
	preview.set_exposure(k)
	map_view.set_exposure(k)
	_update_status()


func _update_status() -> void:
	var name := _rig_path.get_file() if _rig_path != "" else "rig senza nome"
	var hover := ""
	if _hover_az != INF:
		hover = "   |   az %.1f° el %.1f°" % [_hover_az, _hover_el]
		var c := _map_value(_hover_az, _hover_el)
		if c != Color.TRANSPARENT:
			hover += " · RGB %.3f %.3f %.3f" % [c.r, c.g, c.b]
	status.text = "  %s · %d luci · export %dx%d · preview %+.1f EV%s   |   click su un riflesso: seleziona · Shift+trascina: LightPaint · frecce: sposta (Shift 10°) · H: on/off · ⌘D duplica · Canc elimina · ⌘Z undo" % [
		name, rig.lights.size(), rig.resolution.x, rig.resolution.y, _preview_ev, hover]


func _apply_clipping() -> void:
	var on := _clip_check.button_pressed
	var thr := _clip_row.get_value()
	map_view.set_clipping(on, thr)
	preview.set_clipping(on, thr)


## Esposimetro: E ed EV100 per la normale scelta, dalla copia CPU del bake.
func _update_meter() -> void:
	if _meter_label == null:
		return
	if _map_cpu == null or _map_cpu_dirty:
		_map_cpu = baker.get_image()
		_map_cpu_dirty = false
		_map_cpu_ms = Time.get_ticks_msec()
	meter.update(_map_cpu)
	var n: Vector3
	match _meter_mode.selected:
		0:
			n = preview.camera.global_position.normalized()
		1:
			n = Vector3.UP
		_:
			n = LightMeter.dir(_meter_az.value, _meter_el.value)
	var e := meter.illuminance(n)
	_meter_az.visible = _meter_mode.selected == 2
	_meter_el.visible = _meter_mode.selected == 2
	_meter_label.text = "E = %.3f · EV100 %+.1f" % [e, LightMeter.ev100(e)]


## Valore del bake in (az, el), da una copia CPU aggiornata al massimo ogni 300 ms.
func _map_value(az: float, el: float) -> Color:
	var now := Time.get_ticks_msec()
	if _map_cpu == null or (_map_cpu_dirty and now - _map_cpu_ms > 300):
		_map_cpu = baker.get_image()
		_map_cpu_dirty = false
		_map_cpu_ms = now
	if _map_cpu == null:
		return Color.TRANSPARENT
	var x := int(fposmod(az / 360.0 + 0.5, 1.0) * _map_cpu.get_width())
	var y := int(clampf(0.5 - el / 180.0, 0.0, 0.9999) * _map_cpu.get_height())
	return _map_cpu.get_pixel(x, y)


# --- file ----------------------------------------------------------------------------------------

func _dialog(mode: FileDialog.FileMode, filters: PackedStringArray, title: String, on_file: Callable) -> void:
	_file_dialog.file_mode = mode
	_file_dialog.filters = filters
	_file_dialog.title = title
	for c in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(c["callable"])
	for c in _file_dialog.dir_selected.get_connections():
		_file_dialog.dir_selected.disconnect(c["callable"])
	if mode == FileDialog.FILE_MODE_OPEN_DIR:
		_file_dialog.dir_selected.connect(on_file, CONNECT_ONE_SHOT)
	else:
		_file_dialog.file_selected.connect(on_file, CONNECT_ONE_SHOT)
	_file_dialog.popup_centered_ratio(0.6)


## Nuova luce Texture dal catalogo (o da file): defaults dal sidecar o dall'aspetto dell'immagine.
## az/el: posizione iniziale (NAN = default).
func _add_texture_light(path: String, defaults: Dictionary, az := NAN, el := NAN) -> void:
	var l := RigLight.new()
	l.shape = RigLight.Shape.TEXTURE
	l.texture_path = path
	l.name = defaults.get("name", path.get_file().get_basename())
	l.width = float(defaults.get("width", 30.0))
	l.height = float(defaults.get("height", -1.0))
	l.intensity = float(defaults.get("intensity", 1.0))
	l.ev = float(defaults.get("ev", 0.0))
	l.kelvin = float(defaults.get("kelvin", 6500.0))
	l.softness = float(defaults.get("softness", 0.5))
	l.roll = float(defaults.get("roll", 0.0))
	l.azimuth = az if not is_nan(az) else 0.0
	l.elevation = el if not is_nan(el) else 30.0
	if baker.texture_layer(path) < 0:
		export_panel.set_status("Immagine non leggibile: " + path.get_file())
		return
	if l.height <= 0.0:
		# altezza dall'aspetto dell'immagine (come fa il catalogo con le miniature)
		var sz := baker.texture_size(path)
		var aspect := float(sz.x) / float(sz.y) if sz.y > 0 else 1.0
		l.height = clampf(l.width / aspect, 0.5, 180.0)
	light_list.add_and_select(l)


## Scegli un EXR/HDR: new_light = true crea una luce Texture, altrimenti cambia l'immagine della selezionata.
func _pick_texture_file(new_light: bool) -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.exr ; OpenEXR", "*.hdr ; Radiance HDR"], "Immagine della luce", func(path: String) -> void:
		if new_light:
			_add_texture_light(path, {})
		elif _selected >= 0:
			var l: RigLight = rig.lights[_selected]
			if baker.texture_layer(path) < 0:
				export_panel.set_status("Immagine non leggibile: " + path.get_file())
				return
			l.texture_path = path
			props.sync_values()
			_on_light_changed(true))


func _show_hover(tex: Texture2D, name: String, anchor: Rect2) -> void:
	_hover_tex.texture = tex
	_hover_label.text = name
	_hover.visible = true
	_hover.reset_size()
	# a destra della miniatura, dentro la finestra
	var size := Vector2(400, 230)
	var pos := Vector2(anchor.end.x + 8, anchor.position.y)
	var win := get_viewport().get_visible_rect().size
	pos.y = clampf(pos.y, 0.0, win.y - size.y)
	if pos.x + size.x > win.x:
		pos.x = anchor.position.x - size.x - 8
	_hover.position = pos


func _pick_blender() -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_FILE, [], "Eseguibile di Blender", func(path: String) -> void:
		AppSettings.set_value("blender_path", path)
		export_panel.refresh_blender())


func _pick_preset_folder() -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_DIR, [], "Cartella dei preset", func(path: String) -> void:
		AppSettings.set_value("preset_folder", path)
		presets.set_folder(path))


## Salva il rig corrente come preset con miniatura dal preview.
func _save_preset(name: String) -> void:
	var path := presets.preset_path(name)
	var err := rig.save_json(path)
	if err != OK:
		presets._status.text = "Errore: " + error_string(err)
		return
	var img := baker.get_image()
	img.resize(256, 128, Image.INTERPOLATE_BILINEAR)
	HdriExport.save_preview_png(img, path.get_basename() + ".png", 1.0)
	presets.refresh()
	presets._select(path)


func _load_preset(path: String) -> void:
	var prev: String = AppSettings.get_value("last_rig", "")
	if load_rig_from(path):
		_rig_path = "" # un preset caricato non è "il file del rig"
		AppSettings.set_value("last_rig", prev)
		_update_status()


func _merge_preset(path: String) -> void:
	var r := LightRig.load_json(path)
	if r == null:
		return
	for l in r.lights:
		rig.lights.append(l)
	light_list.refresh()
	light_list.select(rig.lights.size() - 1)
	_select(rig.lights.size() - 1)
	_on_light_changed(true)


func _pick_catalog_folder() -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_DIR, [], "Cartella del catalogo", func(path: String) -> void:
		AppSettings.set_value("catalog_folder", path)
		catalog.set_folder(path))


func _pick_base_hdri() -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.exr ; OpenEXR", "*.hdr ; Radiance HDR"], "HDRI di base", func(path: String) -> void:
		if baker.set_base_image_from_file(path):
			rig.base_hdri_path = path
			rig.base_enabled = true
			bg_panel.set_rig(rig)
			_on_light_changed(true)
		else:
			export_panel.set_status("Impossibile leggere " + path.get_file()))


func _export_exr() -> void:
	var dir: String = AppSettings.get_value("export_dir", "")
	if dir != "" and DirAccess.dir_exists_absolute(dir):
		_file_dialog.current_dir = dir
	_file_dialog.current_file = (_rig_path.get_file().get_basename() if _rig_path != "" else "hdri") + ".exr"
	_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.exr ; OpenEXR", "*.hdr ; Radiance HDR"], "Esporta HDRI (EXR o HDR)", export_to)


## Autosave di sicurezza: user://autosave/<data-ora>.json, ne tiene 10.
func _autosave() -> void:
	var dir := "user://autosave"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	rig.save_json(dir.path_join("rig_" + stamp + ".json"))
	var d := DirAccess.open(dir)
	if d == null:
		return
	var files: Array[String] = []
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		if e.begins_with("rig_") and e.ends_with(".json"):
			files.append(e)
		e = d.get_next()
	d.list_dir_end()
	files.sort()
	while files.size() > 10:
		DirAccess.remove_absolute(dir.path_join(files.pop_front()))


## Scrive il sidecar JSON accanto all'immagine della luce Texture selezionata.
func _save_sidecar() -> void:
	if _selected < 0:
		return
	var l: RigLight = rig.lights[_selected]
	if l.shape != RigLight.Shape.TEXTURE or l.texture_path == "":
		return
	var side := {"name": l.name, "width": l.width, "height": l.height, "intensity": l.intensity,
		"ev": l.ev, "kelvin": l.kelvin, "softness": l.softness, "roll": l.roll}
	var path := l.texture_path.get_basename() + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		export_panel.set_status("Sidecar non scrivibile: " + path.get_file())
		return
	f.store_string(JSON.stringify(side, "\t"))
	f.close() # il catalogo lo rilegge subito
	export_panel.set_status("Default salvati in " + path.get_file())
	catalog.set_folder(catalog.folder)


## Bake a piena risoluzione con supersampling, preset di orientamento, scrittura EXR.
## opts: "resolution" (Vector2i), "half" (bool), "target" (String), "shift" (float), "quiet" (bool).
func export_to(path: String, opts := {}) -> Error:
	var ext := path.get_extension().to_lower()
	if ext != "exr" and ext != "hdr":
		path += ".exr"
		ext = "exr"
	var as_hdr := ext == "hdr"
	var t0 := Time.get_ticks_msec()
	var res: Vector2i = opts.get("resolution", export_panel.resolution())
	var half: bool = opts.get("half", export_panel.half())
	var target: String = opts.get("target", export_panel.target())
	var shift: float = opts.get("shift", export_panel.extra_shift())
	if not opts.get("quiet", false):
		rig.resolution = res
	tex_rd.texture_rd_rid = RID() # la texture di preview sta per essere liberata
	baker.set_resolution(res.x, res.y)
	baker.supersample = 2
	baker.bake(rig, false, false) # le luci separate non entrano nell'HDRI
	var img := baker.get_image()
	img = HdriExport.apply_orientation(img, target, shift)
	var rig_json := JSON.stringify(rig.to_dict())
	var err := _write_image(img, path, half, as_hdr, rig_json)
	# luci separate: un file planare ciascuna, accanto all'HDRI
	_last_separate.clear()
	for l in rig.separate_lights():
		var lp := HdriExport.separate_path(path, l.name)
		var limg := baker.bake_planar(l, 1024)
		if link_panel.separate_flip_tex():
			limg.flip_x()
		var lerr := _write_image(limg, lp, half, as_hdr, rig_json)
		if lerr == OK:
			_last_separate.append({"light": l, "path": ProjectSettings.globalize_path(lp)})
		else:
			push_warning("Luce separata non scritta: %s (%s)" % [lp, error_string(lerr)])
	# torna alla risoluzione di preview e riaggancia la texture
	baker.supersample = 1
	baker.set_resolution(PREVIEW_RES.x, PREVIEW_RES.y)
	tex_rd.texture_rd_rid = baker.texture
	preview.set_texture(tex_rd)
	map_view.set_texture(tex_rd)
	_dirty = true
	if opts.get("quiet", false):
		return err
	if err == OK:
		_last_export_path = ProjectSettings.globalize_path(path)
		AppSettings.set_value("export_dir", _last_export_path.get_base_dir())
		export_panel.set_status("Esportato %s (%dx%d, %s, %s) in %.1f s" % [
			path.get_file(), res.x, res.y, "RGBE" if as_hdr else ("half" if half else "float32"),
			target, (Time.get_ticks_msec() - t0) / 1000.0])
		if not as_hdr:
			_start_conversion(path, half)
	else:
		export_panel.set_status("Errore export: " + error_string(err))
	_update_status()
	return err


## Scrive EXR (con i metadati: chromaticities Rec.709 e rig JSON) oppure Radiance .hdr.
func _write_image(img: Image, path: String, half: bool, as_hdr: bool, rig_json: String) -> Error:
	if as_hdr:
		return HdriExport.save_hdr(path, img.get_width(), img.get_height(), baker.rgbe_bytes(img))
	var err := HdriExport.save_exr(img, path, half)
	if err == OK:
		var merr := HdriExport.inject_metadata(path, rig_json)
		if merr != OK:
			push_warning("Metadati EXR non scritti in %s (%s)" % [path.get_file(), error_string(merr)])
	return err


## Riconversione con un altro codec via Blender (solo export manuale, in background).
func _start_conversion(path: String, half: bool) -> void:
	var codec := export_panel.codec()
	if codec == "PIZ":
		return
	var pairs: Array = []
	var files: Array = [ProjectSettings.globalize_path(path)]
	for e in _last_separate:
		files.append(e["path"])
	for f in files:
		pairs.append(f)
		pairs.append(f)
	_convert_pid = ExrConvert.start(pairs, codec, half)
	_convert_files = files
	if _convert_pid < 0:
		export_panel.set_status("Riconversione %s non avviata: Blender non trovato (pannello Export → Blender…)" % codec)
	else:
		export_panel.set_status("Esportato in PIZ, riconversione %s in corso con Blender…" % codec)


# --- live link ----------------------------------------------------------------------------------

func _set_link_enabled(on: bool) -> void:
	if on:
		if link.start() != OK:
			link_panel.set_enabled(false)
	else:
		link.stop()
	_update_link_status()
	_schedule_live()


func _pick_live_path() -> void:
	_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.exr ; OpenEXR"], "File del live link", func(path: String) -> void:
		if path.get_extension().to_lower() != "exr":
			path += ".exr"
		rig.live_export_path = path
		link_panel.set_path(path)
		_commit()
		_live_export())


func _schedule_live() -> void:
	if link_panel != null and link_panel.is_enabled() and rig.live_export_path != "":
		_live_dirty = true
		_live_change_ms = Time.get_ticks_msec()
		_live_deadline = _live_change_ms + LIVE_DEBOUNCE_MS


## Export alla risoluzione live sul file del link e notifica ai client collegati.
func _live_export() -> void:
	if rig.live_export_path == "":
		link_panel.set_status("Scegli prima il file di export.")
		return
	var t0 := Time.get_ticks_msec()
	# risoluzione adattiva: durante una sequenza di modifiche ravvicinate esporta a metà risoluzione,
	# poi, dopo una pausa, rifinisce alla risoluzione live piena
	var res := link_panel.live_resolution()
	var fast := Time.get_ticks_msec() - _live_change_ms < LIVE_FAST_WINDOW_MS and _live_full_pending
	if fast:
		res = Vector2i(maxi(res.x / 2, 512), maxi(res.y / 2, 256))
	var err := export_to(rig.live_export_path, {
		"resolution": res, "half": true,
		"target": export_panel.target(), "shift": export_panel.extra_shift(), "quiet": true})
	if fast:
		_live_dirty = true
		_live_deadline = Time.get_ticks_msec() + LIVE_FAST_WINDOW_MS
	else:
		_live_full_pending = false
	if err != OK:
		link_panel.set_status("Errore export live: " + error_string(err))
		return
	link.notify_hdri(rig.live_export_path, export_panel.target())
	link.broadcast(separate_message())
	_update_link_status("ultimo invio %s in %d ms · %d luci separate" % [Time.get_time_string_from_system(), Time.get_ticks_msec() - t0, _last_separate.size()])


## Messaggio per il plugin con le luci separate: direzione e basi già nelle coordinate del software
## (X invertita per C4D salvo il preset "nativo", che specchia l'immagine invece degli assi),
## distanza e dimensione fisica del rettangolo.
func separate_message() -> Dictionary:
	var target := export_panel.target()
	var t: Dictionary = HdriExport.TARGETS.get(target, HdriExport.TARGETS["Godot / Blender"])
	var mirror_x: bool = t.get("mirror_x", false)
	var shift: float = t["shift"] + export_panel.extra_shift()
	var entries: Array = []
	for e in _last_separate:
		var l: RigLight = e["light"]
		var lz := l.duplicate_light()
		lz.azimuth = wrapf(l.azimuth + shift, -180.0, 180.0)
		var fr := lz.frame()
		var vecs: Array = []
		for v in fr:
			var c: Vector3 = v
			if mirror_x:
				c.x = -c.x
			vecs.append([c.x, c.y, c.z])
		var size := l.physical_size()
		entries.append({
			"name": l.name, "path": e["path"], "distance": l.distance, "visible": l.separate_visible,
			"size": [size.x, size.y], "forward": vecs[0], "right": vecs[1], "up": vecs[2],
			"azimuth": lz.azimuth, "elevation": l.elevation, "roll": l.roll,
		})
	return {"type": "separate_lights", "lights": entries, "target": target,
		"face_sign": -1 if link_panel.separate_flip_face() else 1,
		"texture_flipped": link_panel.separate_flip_tex(), "unit_scale": 0.01}


func _on_link_message(msg: Dictionary, client_id: int) -> void:
	match msg.get("type", ""):
		"hello":
			_link_hosts[client_id] = "%s %s" % [msg.get("host", "?"), msg.get("version", "")]
			_update_link_status()
			# il plugin appena collegato riceve subito l'HDRI corrente e le luci separate
			if rig.live_export_path != "" and FileAccess.file_exists(rig.live_export_path):
				link.notify_hdri(rig.live_export_path, export_panel.target())
				link.broadcast(separate_message())
		"lightpaint":
			_lightpaint_from_host(msg)
		"camera":
			if _link_camera != null and _link_camera.button_pressed:
				var f := _vec(msg.get("forward", []))
				var u := _vec(msg.get("up", []))
				if msg.get("host", "c4d") == "c4d":
					f.x = -f.x
					u.x = -u.x
				preview.set_view_from_host(f, u, float(msg.get("fov", 40.0)))
				_meter_dirty = true


## LightPaint dal software 3D: punto, normale e direzione di vista (o posizione camera) nelle
## coordinate dell'host. Cinema 4D è left-handed: (x, y, z) → (−x, y, z) per passare alla convenzione interna.
func _lightpaint_from_host(msg: Dictionary) -> void:
	if _selected < 0:
		return
	var p := _vec(msg.get("point", []))
	var n := _vec(msg.get("normal", []))
	var v := _vec(msg.get("view", []))
	if v == Vector3.ZERO:
		v = p - _vec(msg.get("camera", []))
	if n == Vector3.ZERO or v == Vector3.ZERO:
		return
	if msg.get("host", "c4d") == "c4d":
		n.x = -n.x
		v.x = -v.x
	v = v.normalized()
	n = n.normalized()
	var r := v - 2.0 * v.dot(n) * n
	_on_paint(r, true)


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a.size() >= 3 else Vector3.ZERO


func _update_link_status(extra := "") -> void:
	if link_panel == null:
		return
	if not link.is_listening():
		link_panel.set_status("Spento. Attivalo e scegli il file: ogni modifica viene esportata e il plugin C4D ricarica la texture.")
		return
	var hosts := []
	for k in _link_hosts:
		hosts.append(_link_hosts[k])
	var txt := "In ascolto su 127.0.0.1:%d · %d client" % [link.port, link.client_count()]
	if not hosts.is_empty():
		txt += " (%s)" % ", ".join(hosts)
	if extra != "":
		txt += " · " + extra
	link_panel.set_status(txt)


func _save_rig() -> void:
	_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.json ; Rig HDRI Studio"], "Salva rig", save_rig_to)


func save_rig_to(path: String) -> Error:
	if path.get_extension().to_lower() != "json":
		path += ".json"
	var err := rig.save_json(path)
	if err == OK:
		_rig_path = path
		AppSettings.set_value("last_rig", ProjectSettings.globalize_path(path))
		export_panel.set_status("Rig salvato: " + path.get_file())
	else:
		export_panel.set_status("Errore salvataggio: " + error_string(err))
	_update_status()
	return err


func _load_rig() -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Rig HDRI Studio", "*.exr ; EXR esportato da HDRI Studio"], "Apri rig (JSON o EXR con metadati)", load_rig_from)


func load_rig_from(path: String) -> bool:
	var r: LightRig = null
	if path.get_extension().to_lower() == "exr":
		var js := HdriExport.read_string_attribute(path, HdriExport.RIG_ATTR)
		var d = JSON.parse_string(js) if js != "" else null
		if d is Dictionary:
			r = LightRig.from_dict(d)
	else:
		r = LightRig.load_json(path)
	if r == null:
		export_panel.set_status("Rig non valido: " + path.get_file())
		return false
	rig = r
	_rig_path = path
	AppSettings.set_value("last_rig", ProjectSettings.globalize_path(path))
	_bind_rig()
	undo.reset(rig.to_dict())
	_select(0 if rig.lights.size() > 0 else -1)
	light_list.select(_selected)
	export_panel.set_status("Rig aperto: " + path.get_file())
	_update_status()
	return true


func _exit_tree() -> void:
	tex_rd.texture_rd_rid = RID()
	baker.free_resources()


# --- rig di default -----------------------------------------------------------------------------

func _default_rig() -> LightRig:
	var r := LightRig.new()
	r.background = LightRig.Background.GRADIENT
	r.bg_zenith = Color(0.06, 0.07, 0.09)
	r.bg_horizon = Color(0.02, 0.02, 0.025)
	r.bg_nadir = Color(0.0, 0.0, 0.0)
	var key := RigLight.new()
	key.name = "Key scrim"
	key.shape = RigLight.Shape.SCRIM
	key.azimuth = -50.0
	key.elevation = 40.0
	key.width = 70.0
	key.height = 50.0
	key.softness = 2.0
	key.corner_radius = 4.0
	key.intensity = 8.0
	key.kelvin = 5600.0
	key.scrim_depth = 0.5
	key.scrim_offset = Vector2(0.2, -0.1)
	r.add_light(key)
	var fill := RigLight.new()
	fill.name = "Fill"
	fill.shape = RigLight.Shape.GRADIENT
	fill.azimuth = 70.0
	fill.elevation = 10.0
	fill.width = 90.0
	fill.height = 70.0
	fill.intensity = 1.2
	fill.kelvin = 7000.0
	r.add_light(fill)
	var rim := RigLight.new()
	rim.name = "Rim strip"
	rim.shape = RigLight.Shape.RECT
	rim.azimuth = 160.0
	rim.elevation = 25.0
	rim.width = 8.0
	rim.height = 60.0
	rim.softness = 1.5
	rim.corner_radius = 2.0
	rim.intensity = 20.0
	rim.roll = 10.0
	r.add_light(rim)
	var top := RigLight.new()
	top.name = "Top ring"
	top.shape = RigLight.Shape.RING
	top.azimuth = 0.0
	top.elevation = 88.0
	top.width = 40.0
	top.ring_inner = 0.7
	top.softness = 2.0
	top.intensity = 3.0
	r.add_light(top)
	return r
