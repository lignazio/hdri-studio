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
var status: Label

var _dirty := true
var _preview_ev := 0.0
var _selected := -1
var _rig_path := ""
var _screenshot_frames := -1
var _file_dialog: FileDialog
var _live_dirty := false
var _live_deadline := 0
var _link_hosts := {}
var _model_label: Label


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

	if "--screenshot" in OS.get_cmdline_user_args():
		_screenshot_frames = 12


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
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tabs)
	var lights_tab := VBoxContainer.new()
	lights_tab.name = "Luci"
	lights_tab.add_theme_constant_override("separation", 6)
	tabs.add_child(lights_tab)
	light_list = LightListPanel.new()
	light_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	light_list.custom_minimum_size.y = 220
	lights_tab.add_child(light_list)
	lights_tab.add_child(HSeparator.new())
	props = LightProperties.new()
	lights_tab.add_child(props)
	catalog = CatalogPanel.new()
	catalog.name = "Catalogo"
	tabs.add_child(catalog)
	catalog.set_folder(AppSettings.get_value("catalog_folder", ""))

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
	map_view.size_flags_vertical = Control.SIZE_SHRINK_END
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
	right.add_child(HSeparator.new())
	export_panel = ExportPanel.new()
	right.add_child(export_panel)
	right.add_child(HSeparator.new())
	link_panel = LiveLinkPanel.new()
	right.add_child(link_panel)
	right.add_child(HSeparator.new())
	_build_model_panel(right)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	add_child(_file_dialog)

	# segnali
	light_list.selection_changed.connect(_select)
	light_list.structure_changed.connect(func() -> void: _on_light_changed(true))
	light_list.texture_light_requested.connect(func() -> void: _pick_texture_file(true))
	props.texture_pick_requested.connect(func() -> void: _pick_texture_file(false))
	catalog.light_requested.connect(_add_texture_light)
	catalog.folder_pick_requested.connect(_pick_catalog_folder)
	props.changed.connect(_on_light_changed)
	props.light_renamed.connect(func() -> void: light_list.refresh(); map_view.refresh())
	map_view.light_selected.connect(func(i: int) -> void: light_list.select(i); _select(i))
	map_view.light_moved.connect(_on_map_move)
	preview.paint.connect(_on_paint)
	bg_panel.changed.connect(_on_light_changed)
	bg_panel.base_hdri_requested.connect(_pick_base_hdri)
	export_panel.export_requested.connect(_export_exr)
	export_panel.save_rig_requested.connect(_save_rig)
	export_panel.load_rig_requested.connect(_load_rig)
	export_panel.resolution_changed.connect(func(r: Vector2i) -> void: rig.resolution = r)
	link_panel.toggled_link.connect(_set_link_enabled)
	link_panel.pick_path_requested.connect(_pick_live_path)
	link_panel.push_now_requested.connect(func() -> void: _live_export())
	_update_status()
	_update_link_status()


func _build_model_panel(parent: Container) -> void:
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
	for it in ["Originale", "Cromato", "Glossy", "Diffuso"]:
		mat.add_item(it)
	mat.item_selected.connect(func(i: int) -> void: preview.set_model_material(i as Preview3D.ModelMaterial))
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


func _column(parent: Container, width: float, scroll := false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width * 0.8
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
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
	props.set_light(rig.lights[_selected] if _selected >= 0 else null)
	map_view.set_selected(_selected)


func _on_light_changed(commit: bool) -> void:
	_dirty = true
	_schedule_live()
	map_view.refresh()
	light_list.refresh()
	if commit:
		_commit()


func _on_map_move(i: int, az: float, el: float, commit: bool) -> void:
	var l: RigLight = rig.lights[i]
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
		_dirty = false
		if _selected >= 0 and rig.lights[_selected].photometric:
			props.sync_values()
	if _live_dirty and Time.get_ticks_msec() >= _live_deadline:
		_live_dirty = false
		_live_export()
	if _screenshot_frames >= 0:
		_screenshot_frames -= 1
		if _screenshot_frames == 0:
			var img := get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
			img.save_png(ProjectSettings.globalize_path("res://out/app.png"))
			print("Screenshot salvato: out/app.png")
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed() and event.keycode == KEY_Z:
			_restore(undo.redo() if event.shift_pressed else undo.undo())
			accept_event()
		elif event.keycode == KEY_Q or event.keycode == KEY_E:
			_preview_ev += PREVIEW_EV_STEP if event.keycode == KEY_E else -PREVIEW_EV_STEP
			var k := pow(2.0, _preview_ev)
			preview.set_exposure(k)
			map_view.set_exposure(k)
			_update_status()
			accept_event()


func _update_status() -> void:
	var name := _rig_path.get_file() if _rig_path != "" else "rig senza nome"
	status.text = "  %s · %d luci · preview %dx%d · export %dx%d · esposizione preview %+.1f EV   |   trascina: orbita · rotella: zoom · Shift+trascina su una sfera: LightPaint · Q/E: esposizione · ⌘Z / ⇧⌘Z: undo/redo" % [
		name, rig.lights.size(), PREVIEW_RES.x, PREVIEW_RES.y, rig.resolution.x, rig.resolution.y, _preview_ev]


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
func _add_texture_light(path: String, defaults: Dictionary) -> void:
	var l := RigLight.new()
	l.shape = RigLight.Shape.TEXTURE
	l.texture_path = path
	l.name = defaults.get("name", path.get_file().get_basename())
	l.width = float(defaults.get("width", 30.0))
	l.height = float(defaults.get("height", 30.0))
	l.intensity = float(defaults.get("intensity", 1.0))
	l.ev = float(defaults.get("ev", 0.0))
	l.kelvin = float(defaults.get("kelvin", 6500.0))
	l.softness = float(defaults.get("softness", 0.5))
	l.roll = float(defaults.get("roll", 0.0))
	l.elevation = 30.0
	if baker.texture_layer(path) < 0:
		export_panel.set_status("Immagine non leggibile: " + path.get_file())
		return
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
	_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.exr ; OpenEXR"], "Esporta HDRI", export_to)


## Bake a piena risoluzione con supersampling, preset di orientamento, scrittura EXR.
## opts: "resolution" (Vector2i), "half" (bool), "target" (String), "shift" (float), "quiet" (bool).
func export_to(path: String, opts := {}) -> Error:
	if path.get_extension().to_lower() != "exr":
		path += ".exr"
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
	baker.bake(rig)
	var img := baker.get_image()
	img = HdriExport.apply_orientation(img, target, shift)
	var err := HdriExport.save_exr(img, path, half)
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
		export_panel.set_status("Esportato %s (%dx%d, %s, %s) in %.1f s" % [
			path.get_file(), res.x, res.y, "half" if half else "float32",
			target, (Time.get_ticks_msec() - t0) / 1000.0])
	else:
		export_panel.set_status("Errore export: " + error_string(err))
	_update_status()
	return err


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
		_live_deadline = Time.get_ticks_msec() + LIVE_DEBOUNCE_MS


## Export alla risoluzione live sul file del link e notifica ai client collegati.
func _live_export() -> void:
	if rig.live_export_path == "":
		link_panel.set_status("Scegli prima il file di export.")
		return
	var t0 := Time.get_ticks_msec()
	var err := export_to(rig.live_export_path, {
		"resolution": link_panel.live_resolution(), "half": true,
		"target": export_panel.target(), "shift": export_panel.extra_shift(), "quiet": true})
	if err != OK:
		link_panel.set_status("Errore export live: " + error_string(err))
		return
	link.notify_hdri(rig.live_export_path, export_panel.target())
	_update_link_status("ultimo invio %s in %d ms" % [Time.get_time_string_from_system(), Time.get_ticks_msec() - t0])


func _on_link_message(msg: Dictionary, client_id: int) -> void:
	match msg.get("type", ""):
		"hello":
			_link_hosts[client_id] = "%s %s" % [msg.get("host", "?"), msg.get("version", "")]
			_update_link_status()
			# il plugin appena collegato riceve subito l'HDRI corrente
			if rig.live_export_path != "" and FileAccess.file_exists(rig.live_export_path):
				link.notify_hdri(rig.live_export_path, export_panel.target())
		"lightpaint":
			_lightpaint_from_host(msg)


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
		export_panel.set_status("Rig salvato: " + path.get_file())
	else:
		export_panel.set_status("Errore salvataggio: " + error_string(err))
	_update_status()
	return err


func _load_rig() -> void:
	_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.json ; Rig HDRI Studio"], "Apri rig", load_rig_from)


func load_rig_from(path: String) -> bool:
	var r := LightRig.load_json(path)
	if r == null:
		export_panel.set_status("Rig non valido: " + path.get_file())
		return false
	rig = r
	_rig_path = path
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
