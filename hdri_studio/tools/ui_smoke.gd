extends SceneTree
## Smoke test dell'app senza click: istanzia main.tscn e percorre le azioni principali.
## Uso:  Godot --path hdri_studio -s res://tools/ui_smoke.gd -- --fresh

func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _run(main: Node) -> void:
	await process_frame
	await process_frame
	var ok := true
	var rig: LightRig = main.rig
	print("[smoke] luci iniziali: %d" % rig.lights.size())
	var glsl := FileAccess.get_file_as_string("res://bake/bake.glsl").replace("#[compute]", "")
	_check(glsl == BakeGlslSource.SOURCE, "bake_glsl_source.gd aggiornato (altrimenti: python3 tools/embed_shader.py)")
	_check(main.baker.is_ready(), "baker pronto")

	# aggiungi / duplica / elimina
	main.light_list._on_add(RigLight.Shape.SCRIM)
	_check(rig.lights.size() == 5, "add → 5 luci")
	main.light_list._on_duplicate()
	_check(rig.lights.size() == 6, "duplicate → 6 luci")
	_check(main._selected == 5, "selezione sulla copia (%d)" % main._selected)
	main.light_list._on_delete()
	_check(rig.lights.size() == 5, "delete → 5 luci")
	await process_frame

	# proprietà: slider → valore → bake
	main.light_list.select(0)
	main._select(0)
	var row: ParamRow = main.props._rows["azimuth"]
	row.slider.value = 12.0
	_check(is_equal_approx(rig.lights[0].azimuth, 12.0), "slider azimut → 12")
	row.committed.emit()
	await process_frame

	# mappa: drag
	main.map_view.light_moved.emit(0, -33.0, 15.0, true)
	_check(is_equal_approx(rig.lights[0].azimuth, -33.0) and is_equal_approx(rig.lights[0].elevation, 15.0), "mappa → az -33 el 15")
	_check(is_equal_approx(main.props._rows["azimuth"].get_value(), -33.0), "pannello sincronizzato")

	# LightPaint: direzione +X interna → az -90
	main.preview.paint.emit(Vector3(1, 0, 0), true)
	_check(is_equal_approx(rig.lights[0].azimuth, -90.0), "paint +X → az -90 (%.1f)" % rig.lights[0].azimuth)
	main.preview.paint.emit(Vector3(0, 1, 0), true)
	_check(is_equal_approx(rig.lights[0].elevation, 90.0), "paint +Y → el 90")
	await process_frame

	# undo / redo
	var before := rig.lights[0].elevation
	main._restore(main.undo.undo())
	_check(not is_equal_approx(main.rig.lights[0].elevation, before), "undo cambia l'elevazione")
	main._restore(main.undo.redo())
	_check(is_equal_approx(main.rig.lights[0].elevation, before), "redo la ripristina")
	await process_frame

	# solo
	main.rig.lights[1].solo = true
	_check(main.rig.active_lights().size() == 1, "solo → 1 luce attiva")
	main.rig.lights[1].solo = false

	# sfondo: HDRI di base dal furnace dello spike
	var base := "res://out/furnace.exr"
	if FileAccess.file_exists(base):
		_check(main.baker.set_base_image_from_file(base), "carica HDRI di base")
		main.rig.base_hdri_path = base
		main.rig.base_enabled = true
		main.rig.base_ev = -2.0
		main._dirty = true
		await process_frame
		await process_frame
		var img: Image = main.baker.get_image()
		var c := img.get_pixel(img.get_width() / 2, int(img.get_height() * 0.9))
		_check(absf(c.r - 0.25) < 0.02, "base a -2 EV → nadir ≈ 0.25 (%.3f)" % c.r)
		main.rig.base_enabled = false
		main._dirty = true

	# salva / apri rig (luce 0 in una posizione asimmetrica per il test del flip)
	main.rig.lights[0].azimuth = -90.0
	main.rig.lights[0].elevation = 20.0
	var rig_path := "res://out/smoke_rig.json"
	_check(main.save_rig_to(rig_path) == OK, "salva rig")
	var n: int = main.rig.lights.size()
	_check(main.load_rig_from(rig_path), "apri rig")
	_check(main.rig.lights.size() == n, "rig riaperto con %d luci" % n)
	await process_frame

	# export con preset C4D (flip) a 2k
	main.export_panel._res.selected = 0
	main.export_panel._target.selected = HdriExport.TARGETS.keys().find("Cinema 4D nativo")
	var t0 := Time.get_ticks_msec()
	_check(main.export_to("res://out/smoke_export.exr") == OK, "export EXR C4D nativo 2k (%d ms)" % (Time.get_ticks_msec() - t0))
	await process_frame
	await process_frame
	_check(main.tex_rd.texture_rd_rid.is_valid(), "texture di preview riagganciata")
	# il flip: la luce 0 sta ad az -90 (u=0.25) → nel file C4D deve stare a u=0.75
	var exp := Image.new()
	exp.load_exr_from_buffer(FileAccess.get_file_as_bytes("res://out/smoke_export.exr"))
	var l0: RigLight = main.rig.lights[0]
	var uv := MapView.light_uv(l0)
	var pr := exp.get_pixel(int((1.0 - uv.x) * exp.get_width()), int(uv.y * exp.get_height()))
	var pl := exp.get_pixel(int(uv.x * exp.get_width()), int(uv.y * exp.get_height()))
	_check(pr.r > 1.0 and pl.r < 1.0, "flip C4D nativo: luce a u=%.2f nel file (%.2f vs %.2f)" % [1.0 - uv.x, pr.r, pl.r])

	# modello GLB nel preview + LightPaint con raycast fisico
	var glb := "res://out/torus.glb"
	if FileAccess.file_exists(glb):
		_check(main.preview.load_model(ProjectSettings.globalize_path(glb)), "carica torus.glb")
		main.preview.set_model_material(Preview3D.ModelMaterial.CHROME)
		for i in 4:
			await process_frame
		main._select(0)
		var before_az: float = main.rig.lights[0].azimuth
		main.rig.lights[0].elevation = 5.0
		var center: Vector2 = main.preview.size * 0.5
		var hit: bool = main.preview._try_paint(center, true)
		_check(hit, "LightPaint sul modello: colpito")
		# la camera guarda il toro dal davanti: il riflesso al centro deve puntare ~verso la camera
		var lm: RigLight = main.rig.lights[0]
		_check(lm.azimuth != before_az or absf(lm.elevation - 5.0) > 0.1, "LightPaint sul modello ha spostato la luce (az %.1f el %.1f)" % [lm.azimuth, lm.elevation])
		main.preview.clear_model()
		_check(not main.preview.has_model(), "modello rimosso")

	# luce Texture: furnace.exr (uniforme 1.0) come immagine → contributo = intensità
	var tex_path := ProjectSettings.globalize_path("res://out/furnace.exr")
	if FileAccess.file_exists(tex_path):
		main.rig.background = LightRig.Background.BLACK
		for l in main.rig.lights:
			l.enabled = false
		main._add_texture_light(tex_path, {"width": 40.0, "height": 30.0, "intensity": 2.0})
		var tl: RigLight = main.rig.lights[main.rig.lights.size() - 1]
		_check(tl.shape == RigLight.Shape.TEXTURE and tl.texture_path == tex_path, "luce Texture aggiunta dal file")
		tl.azimuth = 0.0
		tl.elevation = 0.0
		main._dirty = true
		await process_frame
		await process_frame
		var img: Image = main.baker.get_image()
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		_check(absf(c.r - 2.0) < 0.01, "pixel al centro della luce Texture = 2.0 (%.3f)" % c.r)
		var outside := img.get_pixel(int(img.get_width() * 0.75), img.get_height() / 2)
		_check(outside.r < 0.001, "fuori dalla luce Texture = 0 (%.4f)" % outside.r)

	# catalogo: la cartella out/ contiene gli EXR dello spike
	main.catalog.set_folder(ProjectSettings.globalize_path("res://out"))
	_check(main.catalog._items.size() >= 5, "catalogo: %d immagini trovate" % main.catalog._items.size())
	var waited := 0.0
	var with_icon := 0
	while waited < 20.0:
		await create_timer(0.5).timeout
		waited += 0.5
		with_icon = 0
		for path in main.catalog._buttons:
			if main.catalog._buttons[path].icon != null:
				with_icon += 1
		if with_icon == main.catalog._items.size():
			break
	_check(with_icon == main.catalog._items.size(), "miniature generate: %d/%d in %.1f s" % [with_icon, main.catalog._items.size(), waited])
	var n_before: int = main.rig.lights.size()
	main.catalog.light_requested.emit(tex_path, main.catalog._defaults({"path": tex_path, "name": "furnace", "sidecar": {}}))
	_check(main.rig.lights.size() == n_before + 1, "click sul catalogo aggiunge una luce")

	# catalogo per sottocartelle: out/softbox/ contiene una copia
	_check(main.catalog._sections.size() >= 2, "catalogo: %d sezioni (sottocartelle)" % main.catalog._sections.size())
	var idx := -1
	for i in main.catalog._subfolder.item_count:
		if main.catalog._subfolder.get_item_text(i) == "softbox":
			idx = i
	_check(idx > 0, "menu sottocartelle contiene 'softbox'")
	main.catalog._subfolder.selected = idx
	main.catalog._apply_filter()
	var vis := 0
	for path in main.catalog._buttons:
		if main.catalog._buttons[path].visible:
			vis += 1
	_check(vis == 1, "filtro per sottocartella: %d visibile" % vis)
	main.catalog._subfolder.selected = 0
	main.catalog._apply_filter()

	# fotometrico: rect 30x20 duro → K ≈ 0.1769 sr (dal test Blender di Fase 0), E = 1 → L = 1/K
	var pht := RigLight.new()
	pht.name = "photo"
	pht.shape = RigLight.Shape.RECT
	pht.width = 30.0
	pht.height = 20.0
	pht.softness = 0.0
	pht.photometric = true
	pht.illuminance = 1.0
	for l in main.rig.lights:
		l.enabled = false
	main.rig.background = LightRig.Background.BLACK
	main.light_list.add_and_select(pht)
	await process_frame
	await process_frame
	_check(absf(pht.measured_k - 0.1769) < 0.002, "K misurato = %.4f sr (atteso 0.1769)" % pht.measured_k)
	var pimg: Image = main.baker.get_image()
	var pc := pimg.get_pixel(pimg.get_width() / 2, pimg.get_height() / 2)
	_check(absf(pc.r - 1.0 / pht.measured_k) < 0.01, "radianza al centro = %.3f = 1/K" % pc.r)
	# K non dipende dalla posizione, sì dalla dimensione
	pht.azimuth = 60.0
	pht.elevation = -20.0
	main._dirty = true
	await process_frame
	_check(absf(pht.measured_k - 0.1769) < 0.002, "K invariante alla posizione")
	pht.width = 60.0
	main._dirty = true
	await process_frame
	_check(pht.measured_k > 0.3, "K cresce con la larghezza (%.4f)" % pht.measured_k)

	# fusione Normale: luce a 0.2 sopra sfondo 1.0 → 0.2 al centro
	pht.photometric = false
	pht.intensity = 0.2
	pht.azimuth = 0.0
	pht.elevation = 0.0
	pht.blend = RigLight.Blend.NORMAL
	main.rig.background = LightRig.Background.UNIFORM
	main.rig.bg_horizon = Color(1, 1, 1)
	main._dirty = true
	await process_frame
	var nimg: Image = main.baker.get_image()
	var nc := nimg.get_pixel(nimg.get_width() / 2, nimg.get_height() / 2)
	_check(absf(nc.r - 0.2) < 0.01, "fusione Normale copre lo sfondo: %.3f" % nc.r)

	# riordino
	var last: int = main.rig.lights.size() - 1
	main.light_list.select(last)
	main.light_list._move(-1)
	_check(main.rig.lights[last - 1] == pht and main._selected == last - 1, "sposta su")
	main.light_list._move(1)
	_check(main.rig.lights[last] == pht, "sposta giù")

	# LightPaint senza selezione crea una luce
	main._select(-1)
	var n0: int = main.rig.lights.size()
	main.preview.paint.emit(Vector3(0, 0, 1), true)
	_check(main.rig.lights.size() == n0 + 1 and main._selected == n0, "LightPaint senza selezione crea una luce")

	# drag & drop dal catalogo: sulla mappa (posizione) e sul preview (riflesso)
	var dd := {"type": "catalog_light", "path": tex_path, "defaults": {"width": 20.0, "height": 20.0}}
	var mrect: Rect2 = main.map_view._map_rect()
	var drop_pos: Vector2 = mrect.position + mrect.size * Vector2(0.75, 0.25)
	_check(main.map_view._can_drop_data(drop_pos, dd), "la mappa accetta il drop")
	var nd: int = main.rig.lights.size()
	main.map_view._drop_data(drop_pos, dd)
	var dl: RigLight = main.rig.lights[main.rig.lights.size() - 1]
	_check(main.rig.lights.size() == nd + 1 and absf(dl.azimuth - 90.0) < 0.5 and absf(dl.elevation - 45.0) < 0.5, "drop sulla mappa → az %.1f el %.1f" % [dl.azimuth, dl.elevation])
	_check(main.preview._can_drop_data(Vector2.ZERO, dd), "il preview accetta il drop")
	nd = main.rig.lights.size()
	main.preview._drop_data(main.preview.size * 0.5, dd)
	_check(main.rig.lights.size() == nd + 1, "drop sul preview crea la luce (sul riflesso se colpisce)")

	# luce separata: esclusa dall'HDRI, EXR planare accanto, messaggio per il plugin
	for l in main.rig.lights:
		l.enabled = false
	main.rig.background = LightRig.Background.BLACK
	var sep := RigLight.new()
	sep.name = "Key sep"
	sep.shape = RigLight.Shape.RECT
	sep.azimuth = 0.0
	sep.elevation = 0.0
	sep.width = 40.0
	sep.height = 20.0
	sep.softness = 0.0
	sep.intensity = 3.0
	sep.separate = true
	sep.distance = 150.0
	main.light_list.add_and_select(sep)
	await process_frame
	await process_frame
	var pimg2: Image = main.baker.get_image()
	_check(absf(pimg2.get_pixel(pimg2.get_width() / 2, pimg2.get_height() / 2).r - 3.0) < 0.01, "preview: la luce separata è visibile")
	var planar: Image = main.baker.bake_planar(sep, 512)
	_check(planar.get_width() == 512 and absi(planar.get_height() - int(round(512 * tan(deg_to_rad(10)) / tan(deg_to_rad(20))))) <= 1, "planare %dx%d (aspetto tan)" % [planar.get_width(), planar.get_height()])
	var pcen := planar.get_pixel(planar.get_width() / 2, planar.get_height() / 2)
	var pcorner := planar.get_pixel(2, 2)
	_check(absf(pcen.r - 3.0) < 0.01 and absf(pcorner.r - 3.0) < 0.01, "planare: radianza 3.0 al centro (%.2f) e all'angolo (%.2f)" % [pcen.r, pcorner.r])
	var sz := sep.physical_size()
	_check(absf(sz.x - 2.0 * 150.0 * tan(deg_to_rad(20.0))) < 0.01, "dimensione fisica %.1f × %.1f cm" % [sz.x, sz.y])
	main.export_panel._res.selected = 0
	_check(main.export_to("res://out/smoke_sep.exr") == OK, "export con luce separata")
	await process_frame
	await process_frame
	var sep_path := ProjectSettings.globalize_path("res://out/smoke_sep_key_sep.exr")
	_check(FileAccess.file_exists(sep_path), "EXR singolo scritto accanto all'HDRI")
	var hdri := Image.new()
	hdri.load_exr_from_buffer(FileAccess.get_file_as_bytes("res://out/smoke_sep.exr"))
	_check(hdri.get_pixel(hdri.get_width() / 2, hdri.get_height() / 2).r < 0.001, "HDRI esportata senza la luce separata")
	var msg: Dictionary = main.separate_message()
	_check(msg["lights"].size() == 1 and msg["lights"][0]["distance"] == 150.0 and msg["lights"][0]["path"] == sep_path, "messaggio separate_lights: 1 luce, distanza 150")
	var fwd: Array = msg["lights"][0]["forward"]
	_check(absf(fwd[2] - 1.0) < 1e-4, "forward verso +Z (az 0)")

	# preset: salva, ricarica, aggiungi
	main.presets.set_folder(ProjectSettings.globalize_path("res://out/presets"))
	var np: int = main.rig.lights.size()
	main._save_preset("Smoke preset")
	var pp: String = main.presets.preset_path("Smoke preset")
	_check(FileAccess.file_exists(pp) and FileAccess.file_exists(pp.get_basename() + ".png"), "preset salvato con miniatura")
	main._merge_preset(pp)
	_check(main.rig.lights.size() == np * 2, "aggiungi luci del preset → %d luci" % main.rig.lights.size())
	main._load_preset(pp)
	_check(main.rig.lights.size() == np, "carica preset → %d luci" % main.rig.lights.size())

	# catalogo: preferiti e tag
	main.catalog.set_favorite(tex_path, true)
	main.catalog.set_tags(tex_path, ["softbox", "test"])
	_check(main.catalog._buttons[tex_path].text.begins_with("★"), "preferito segnato nel nome")
	main.catalog._fav_only.button_pressed = true
	main.catalog._apply_filter()
	var vis2 := 0
	for path in main.catalog._buttons:
		if main.catalog._buttons[path].visible:
			vis2 += 1
	_check(vis2 == 1, "filtro preferiti: %d visibile" % vis2)
	main.catalog._fav_only.button_pressed = false
	main.catalog._filter.text = "softbox"
	main.catalog._apply_filter()
	vis2 = 0
	for path in main.catalog._buttons:
		if main.catalog._buttons[path].visible:
			vis2 += 1
	_check(vis2 == 1, "filtro per tag nel testo: %d visibile" % vis2)
	main.catalog._filter.text = ""
	main.catalog._apply_filter()
	_check(FileAccess.file_exists(CatalogPanel.META_PATH), "metadati del catalogo salvati")

	# codec EXR con la GDExtension HsOpenEXR: ZIP lossless → pixel identici al PIZ; DWAA (che TinyEXR
	# non legge) → riletto da OpenEXR con valori vicini
	_check(ExrCodec.available(), "HsOpenEXR caricata (OpenEXR %s)" % ExrCodec.version())
	if ExrCodec.available():
		var src := ProjectSettings.globalize_path("res://out/smoke_export_piz.exr")
		var dst := ProjectSettings.globalize_path("res://out/smoke_export_zip.exr")
		_check(main.export_to(src, {"codec": "PIZ", "quiet": true}) == OK, "export PIZ di riferimento")
		var t_zip := Time.get_ticks_msec()
		_check(main.export_to(dst, {"codec": "ZIP", "quiet": true}) == OK, "export ZIP (%d ms)" % (Time.get_ticks_msec() - t_zip))
		_check(ExrCodec.compression_of(dst) == 3, "header: compression = ZIP")
		var a := Image.new()
		a.load_exr_from_buffer(FileAccess.get_file_as_bytes(src))
		var b := Image.new()
		var lerr := b.load_exr_from_buffer(FileAccess.get_file_as_bytes(dst))
		var same := lerr == OK and a.get_size() == b.get_size()
		if same:
			for i in 20:
				var x := (i * 97) % a.get_width()
				var y := (i * 53) % a.get_height()
				if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
					same = false
		_check(same, "ZIP: pixel identici al PIZ, leggibile anche da TinyEXR")
		_check(HdriExport.read_string_attribute(dst, HdriExport.RIG_ATTR) != "", "ZIP: rig nei metadati")
		var dwaa := ProjectSettings.globalize_path("res://out/smoke_export_dwaa.exr")
		var t_dwa := Time.get_ticks_msec()
		_check(main.export_to(dwaa, {"codec": "DWAA", "quiet": true}) == OK, "export DWAA (%d ms)" % (Time.get_ticks_msec() - t_dwa))
		var direct := Image.new()
		var derr := direct.load_exr_from_buffer(FileAccess.get_file_as_bytes(dwaa))
		_check(derr != OK or direct.is_empty(), "DWAA non leggibile da TinyEXR (come previsto)")
		var via := HdriBaker.load_linear_image(dwaa)
		_check(via != null and via.get_size() == a.get_size(), "DWAA caricato da OpenEXR")
		if via != null:
			var pa := a.get_pixel(a.get_width() / 4, a.get_height() / 2)
			var pv := via.get_pixel(a.get_width() / 4, a.get_height() / 2)
			_check(absf(pa.r - pv.r) < 0.05 * maxf(pa.r, 0.1) + 0.01, "DWAA: valori vicini (%.3f vs %.3f)" % [pa.r, pv.r])
		var sizes := [FileAccess.get_file_as_bytes(src).size(), FileAccess.get_file_as_bytes(dst).size(), FileAccess.get_file_as_bytes(dwaa).size()]
		print("[smoke] dimensioni PIZ %d KB · ZIP %d KB · DWAA %d KB" % [sizes[0] / 1024, sizes[1] / 1024, sizes[2] / 1024])

	# geometria: contains / outline / pick per riflesso
	var gl := RigLight.new()
	gl.azimuth = 40.0
	gl.elevation = 10.0
	gl.width = 30.0
	gl.height = 20.0
	var center_dir := gl.dir_from_local(0.0, 0.0)
	_check(gl.contains(center_dir), "contains: centro della luce")
	_check(gl.contains(gl.dir_from_local(deg_to_rad(14.0), 0.0)) and not gl.contains(gl.dir_from_local(deg_to_rad(16.0), 0.0)), "contains: bordo a ±15°")
	_check(gl.outline().size() == 1 and gl.outline()[0].size() == 64, "outline: 64 punti")
	main.rig.lights.clear()
	main.rig.add_light(gl)
	main.light_list.refresh()
	main._select(-1)
	main._pick_light_by_reflection(center_dir)
	_check(main._selected == 0, "click sul riflesso seleziona la luce")
	# frecce: sposta la selezione
	main._nudge(10.0, -5.0, true)
	_check(is_equal_approx(gl.azimuth, 50.0) and is_equal_approx(gl.elevation, 5.0), "nudge → az 50 el 5")
	# multi-selezione: duplica ed elimina in blocco
	main.light_list._on_duplicate()
	main.light_list.select_many([0, 1])
	main._selection = [0, 1]
	main.light_list._on_delete()
	_check(main.rig.lights.is_empty(), "elimina in blocco → 0 luci")
	main.rig.add_light(gl)
	main.light_list.refresh()
	# lettura del valore sotto il cursore
	main._dirty = true
	await process_frame
	await process_frame
	var v: Color = main._map_value(gl.azimuth, gl.elevation)
	_check(v.r > 0.5, "valore sotto il cursore al centro della luce: %.2f" % v.r)

	# texture: specchio orizzontale sposta il contenuto; gradiente: valore della tacca oltre 1; base sfocata
	main.rig.lights.clear()
	main.rig.background = LightRig.Background.BLACK
	var rect_tex := ProjectSettings.globalize_path("res://out/rect.exr")
	var tl2 := RigLight.new()
	tl2.shape = RigLight.Shape.TEXTURE
	tl2.texture_path = rect_tex
	tl2.width = 40.0
	tl2.height = 20.0
	tl2.softness = 0.0
	tl2.intensity = 1.0
	main.rig.add_light(tl2)
	main.light_list.refresh()
	main._dirty = true
	await create_timer(0.4).timeout
	var right: Color = main._map_value(5.0, 3.3)
	var left: Color = main._map_value(-5.0, 3.3)
	_check(right.r > 5.0 and left.r < 0.5, "texture: contenuto a destra (%.1f / %.1f)" % [right.r, left.r])
	tl2.texture_flip_h = true
	main._dirty = true
	await create_timer(0.4).timeout
	right = main._map_value(5.0, 3.3)
	left = main._map_value(-5.0, 3.3)
	_check(left.r > 5.0 and right.r < 0.5, "texture specchiata: contenuto a sinistra (%.1f / %.1f)" % [left.r, right.r])
	var gv := RigLight.new()
	gv.shape = RigLight.Shape.GRADIENT
	gv.width = 40.0
	gv.height = 40.0
	gv.intensity = 1.0
	gv.gradient_stops = [[0.0, 1.0, 1.0, 1.0, 4.0], [1.0, 0.0, 0.0, 0.0, 1.0]]
	main.rig.lights.clear()
	main.rig.add_light(gv)
	main.light_list.refresh()
	main._dirty = true
	await create_timer(0.4).timeout
	_check(absf(main._map_value(0.0, 0.0).r - 4.0) < 0.05, "gradiente: tacca con valore 4 → %.2f al centro" % main._map_value(0.0, 0.0).r)
	main.rig.lights.clear()
	main.baker.set_base_image_from_file(rect_tex)
	main.rig.base_hdri_path = rect_tex
	main.rig.base_enabled = true
	main.rig.base_blur = 0.0
	main._dirty = true
	await create_timer(0.4).timeout
	var sharp: Color = main._map_value(45.0, 30.0)
	main.rig.base_blur = 1.0
	main._dirty = true
	await create_timer(0.4).timeout
	var blurred: Color = main._map_value(45.0, 30.0)
	var far: Color = main._map_value(-135.0, -30.0)
	_check(sharp.r > 2.0 and blurred.r < 1.0 and absf(blurred.r - far.r) < 0.05, "base sfocata: %.2f → %.3f (lontano %.3f)" % [sharp.r, blurred.r, far.r])
	main.rig.base_enabled = false
	main.rig.base_blur = 0.0

	# sidecar dalla luce, autosave, cartella di export ricordata
	main.rig.lights.clear()
	main._add_texture_light(ProjectSettings.globalize_path("res://out/softbox/rect_sub.exr"), {"width": 22.0, "height": 11.0, "intensity": 3.5})
	main._select(0)
	main._save_sidecar()
	var side := ProjectSettings.globalize_path("res://out/softbox/rect_sub.json")
	_check(FileAccess.file_exists(side) and JSON.parse_string(FileAccess.get_file_as_string(side)).get("intensity", 0) == 3.5, "sidecar scritto dalla luce")
	DirAccess.remove_absolute(side)
	main._autosave()
	var ad := DirAccess.open("user://autosave")
	var n_auto := 0
	if ad != null:
		ad.list_dir_begin()
		var e := ad.get_next()
		while e != "":
			if e.ends_with(".json"):
				n_auto += 1
			e = ad.get_next()
	_check(n_auto >= 1 and n_auto <= 10, "autosave: %d file" % n_auto)
	_check(String(AppSettings.get_value("export_dir", "")) != "", "cartella di export ricordata")

	# Fase 6: ruota tutto, specchia, esposimetro, camera dal link, materiali
	main.rig.lights.clear()
	var ra := RigLight.new()
	ra.azimuth = 30.0
	ra.roll = 15.0
	main.rig.add_light(ra)
	main.rig.rotate_all(90.0)
	_check(is_equal_approx(ra.azimuth, 120.0), "ruota tutto: az 30 → 120")
	var mir := ra.mirrored()
	_check(is_equal_approx(mir.azimuth, -120.0) and is_equal_approx(mir.roll, -15.0), "specchiata: az −120, roll −15")
	main.rig.lights.clear()
	main.rig.background = LightRig.Background.UNIFORM
	main.rig.bg_horizon = Color(1, 1, 1)
	main._dirty = true
	await create_timer(0.4).timeout
	main._map_cpu_dirty = true
	main._update_meter()
	var e_up: float = main.meter.illuminance(Vector3.UP)
	var e_side: float = main.meter.illuminance(Vector3(1, 0, 0))
	_check(absf(e_up - PI) < 0.03 and absf(e_side - PI) < 0.03, "esposimetro: ambiente 1.0 → E = π (%.3f / %.3f), EV100 %.2f" % [e_up, e_side, LightMeter.ev100(e_up)])
	main._link_camera.button_pressed = true
	main._on_link_message({"type": "camera", "host": "blender", "forward": [0, 0, 1], "up": [0, 1, 0], "fov": 60.0}, 0)
	_check(main.preview.camera.global_position.z < -1.0 and absf(main.preview.camera.global_position.x) < 0.01, "camera dal link: guarda +Z dal lato −Z (%s)" % main.preview.camera.global_position)
	main._link_camera.button_pressed = false
	main.preview.set_center_sphere_material(Preview3D.ModelMaterial.GOLD)
	var cm: Material = main.preview._spheres[1].material_override
	_check(cm is ShaderMaterial and (cm as ShaderMaterial).get_shader_parameter("tint") == Preview3D.METAL_F0[Preview3D.ModelMaterial.GOLD], "sfera centrale in oro (riflessi esatti tinti)")
	main.preview.set_center_sphere_material(Preview3D.ModelMaterial.ORIGINAL)
	_check(main.preview._spheres[1].material_override == main.preview._glossy, "Originale riporta la sfera centrale al glossy")
	main._clip_check.button_pressed = true
	_check(main.map_view._map_mat.get_shader_parameter("clip_threshold") > 0.0, "clipping attivo sulla mappa")
	main._clip_check.button_pressed = false

	# Radiance .hdr e metadati EXR
	main.rig.lights.clear()
	main.rig.background = LightRig.Background.BLACK
	var hl := RigLight.new()
	hl.name = "hdr test"
	hl.width = 30.0
	hl.height = 20.0
	hl.softness = 0.0
	hl.intensity = 7.5
	main.rig.add_light(hl)
	main.light_list.refresh()
	main.export_panel._res.selected = 0
	main.export_panel._codec.selected = 0
	_check(main.export_to("res://out/smoke_meta.hdr") == OK, "export .hdr")
	var hdr := Image.new()
	var herr := hdr.load(ProjectSettings.globalize_path("res://out/smoke_meta.hdr"))
	var hc := hdr.get_pixel(hdr.get_width() / 2, hdr.get_height() / 2) if herr == OK else Color.BLACK
	_check(herr == OK and hdr.get_width() == 2048 and absf(hc.r - 7.5) < 0.08, ".hdr riletto da Godot: %dx%d, centro %.3f (RGBE)" % [hdr.get_width(), hdr.get_height(), hc.r])
	# il rig nell'header del .hdr: prima la variabile grezza, poi il giro completo (la rilettura dei
	# pixel qui sopra è anche la prova che la riga in più non disturba chi legge l'immagine)
	var hjs := HdriExport.read_hdr_rig("res://out/smoke_meta.hdr")
	_check(hjs != "" and (JSON.parse_string(hjs) as Dictionary).get("lights", []).size() == 1, "rig letto dall'header .hdr")
	_check_hdr_header_lines("res://out/smoke_meta.hdr", "export dell'app")
	_check_hdr_big_rig()
	main.rig.lights.clear()
	_check(main.load_rig_from(ProjectSettings.globalize_path("res://out/smoke_meta.hdr")) and main.rig.lights.size() == 1 and main.rig.lights[0].name == "hdr test", "rig riaperto dall'.hdr")
	_check(main.export_to("res://out/smoke_meta.exr") == OK, "export EXR con metadati")
	await process_frame
	var js := HdriExport.read_string_attribute("res://out/smoke_meta.exr", HdriExport.RIG_ATTR)
	_check(js != "" and (JSON.parse_string(js) as Dictionary).get("lights", []).size() == 1, "attributo hdristudio_rig letto dall'EXR")
	var back := Image.new()
	var berr := back.load_exr_from_buffer(FileAccess.get_file_as_bytes("res://out/smoke_meta.exr"))
	_check(berr == OK and absf(back.get_pixel(back.get_width() / 2, back.get_height() / 2).r - 7.5) < 0.01, "EXR con metadati ancora leggibile (TinyEXR), centro %.2f" % (back.get_pixel(back.get_width() / 2, back.get_height() / 2).r if berr == OK else -1.0))
	main.rig.lights.clear()
	_check(main.load_rig_from(ProjectSettings.globalize_path("res://out/smoke_meta.exr")) and main.rig.lights.size() == 1 and main.rig.lights[0].name == "hdr test", "rig riaperto dall'EXR")
	# ACEScg: luce rossa pura (7.5, 0, 0) in Rec.709 → (7.5·0.6131, 7.5·0.0702, 7.5·0.0206) in AP1
	main.rig.lights[0].tint = Color(1, 0, 0)
	main.rig.lights[0].kelvin = 6500.0
	_check(main.export_to("res://out/smoke_aces.exr", {"acescg": true}) == OK, "export ACEScg")
	await process_frame
	var aces := Image.new()
	aces.load_exr_from_buffer(FileAccess.get_file_as_bytes("res://out/smoke_aces.exr"))
	var ac := aces.get_pixel(aces.get_width() / 2, aces.get_height() / 2)
	_check(absf(ac.r - 7.5 * 0.6130974) < 0.02 and absf(ac.g - 7.5 * 0.0701937) < 0.02 and absf(ac.b - 7.5 * 0.0206156) < 0.02, "ACEScg: rosso Rec.709 → (%.3f, %.3f, %.3f)" % [ac.r, ac.g, ac.b])
	_check(HdriExport.read_string_attribute("res://out/smoke_aces.exr", "comments").contains("ACEScg"), "metadati ACEScg (chromaticities AP1, commento)")
	main.rig.lights[0].tint = Color.WHITE

	# riordino con drag & drop nella lista
	main.rig.lights.clear()
	for nm in ["A", "B", "C", "D"]:
		var lx := RigLight.new()
		lx.name = nm
		main.rig.add_light(lx)
	main.light_list.refresh()
	await process_frame
	var r_a: Rect2 = main.light_list.item_rect(0)
	var r_d: Rect2 = main.light_list.item_rect(3)
	_check(main.light_list._can_drop(r_d.get_center(), {"type": "light_reorder", "indices": [0]}), "la lista accetta il drop di riordino")
	main.light_list._drop(Vector2(r_d.get_center().x, r_d.end.y - 1.0), {"type": "light_reorder", "indices": [0]})
	var order: Array = main.rig.lights.map(func(l: RigLight) -> String: return l.name)
	_check(order == ["B", "C", "D", "A"], "drag A in fondo → %s" % [order])
	await process_frame # la lista ricalcola i rettangoli delle voci al disegno
	r_a = main.light_list.item_rect(0)
	main.light_list._drop(Vector2(r_a.get_center().x, r_a.position.y + 1.0), {"type": "light_reorder", "indices": [1, 2]})
	order = main.rig.lights.map(func(l: RigLight) -> String: return l.name)
	_check(order == ["C", "D", "B", "A"], "drag del gruppo C,D in testa → %s" % [order])

	# lucchetto
	main._select(0)
	var lk: RigLight = main.rig.lights[0]
	lk.locked = true
	var az0 := lk.azimuth
	main._on_paint(Vector3(1, 0, 0), true)
	main._nudge(10.0, 0.0, true)
	_check(is_equal_approx(lk.azimuth, az0), "luce bloccata: LightPaint e frecce non la spostano")
	lk.locked = false

	ok = ok and _all_ok
	print("[smoke] %s" % ("TUTTO OK" if ok else "FALLITO"))
	quit(0 if ok else 1)


var _all_ok := true

## Ogni controllo viene sempre eseguito (niente cortocircuito): un fallimento non nasconde i successivi.

## Nessuna riga dell'header .hdr oltre HDR_HEADER_LINE_MAX byte: Three.js si ferma a 1024, rgbe.c
## legge a pezzi di 128 (il 28/09 due .hdr con il rig su una riga sola non si aprivano sul web).
func _check_hdr_header_lines(path: String, what: String) -> void:
	var data := FileAccess.get_file_as_bytes(path)
	var longest := 0
	var start := 0
	var closed := false
	while start < data.size():
		var nl := data.find(10, start)
		if nl < 0:
			break
		longest = maxi(longest, nl - start + 1)
		if nl == start:
			closed = true # riga vuota: da qui in poi risoluzione e pixel
			break
		start = nl + 1
	_check(closed and longest <= HdriExport.HDR_HEADER_LINE_MAX, "header .hdr a righe corte (%s): la più lunga %d byte" % [what, longest])


## Rig grande e con caratteri non ASCII: torna identico, le righe restano corte, i pixel si leggono. Più
## la compatibilità con i .hdr scritti prima del 28/09 (JSON su una riga sola).
func _check_hdr_big_rig() -> void:
	var lights := []
	for i in 300:
		lights.append({"name": "luce è ñ ✓ %d" % i, "intensity": i * 0.5})
	var big := JSON.stringify({"lights": lights})
	var path := "res://out/smoke_bigrig.hdr"
	var px := PackedByteArray()
	px.resize(8 * 4 * 4)
	px.fill(128)
	_check(HdriExport.save_hdr(path, 8, 4, px, big) == OK, "export .hdr con rig di %d caratteri" % big.length())
	_check(HdriExport.read_rig_json(path) == big, "rig grande riletto identico dall'.hdr")
	_check_hdr_header_lines(path, "rig grande")
	var img := Image.new()
	_check(img.load(ProjectSettings.globalize_path(path)) == OK and img.get_width() == 8, ".hdr con rig grande riletto da Godot")
	var legacy := "res://out/smoke_legacy.hdr"
	var f := FileAccess.open(legacy, FileAccess.WRITE)
	f.store_string("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n#%s=%s\n\n-Y 4 +X 8\n" % [HdriExport.RIG_HDR_KEY, big])
	f.store_buffer(px)
	f.close()
	_check(HdriExport.read_rig_json(legacy) == big, "rig riletto da un .hdr del vecchio formato (riga unica)")

func _check(cond: bool, label: String) -> bool:
	print("[smoke] %s %s" % ["✓" if cond else "✗", label])
	if not cond:
		_all_ok = false
	return cond
