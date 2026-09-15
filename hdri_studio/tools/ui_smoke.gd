extends SceneTree
## Smoke test dell'app senza click: istanzia main.tscn e percorre le azioni principali.
## Uso:  Godot --path hdri_studio -s res://tools/ui_smoke.gd

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

	# aggiungi / duplica / elimina
	main.light_list._on_add(RigLight.Shape.SCRIM)
	ok = ok and _check(rig.lights.size() == 5, "add → 5 luci")
	main.light_list._on_duplicate()
	ok = ok and _check(rig.lights.size() == 6, "duplicate → 6 luci")
	ok = ok and _check(main._selected == 5, "selezione sulla copia (%d)" % main._selected)
	main.light_list._on_delete()
	ok = ok and _check(rig.lights.size() == 5, "delete → 5 luci")
	await process_frame

	# proprietà: slider → valore → bake
	main.light_list.select(0)
	main._select(0)
	var row: ParamRow = main.props._rows["azimuth"]
	row.slider.value = 12.0
	ok = ok and _check(is_equal_approx(rig.lights[0].azimuth, 12.0), "slider azimut → 12")
	row.committed.emit()
	await process_frame

	# mappa: drag
	main.map_view.light_moved.emit(0, -33.0, 15.0, true)
	ok = ok and _check(is_equal_approx(rig.lights[0].azimuth, -33.0) and is_equal_approx(rig.lights[0].elevation, 15.0), "mappa → az -33 el 15")
	ok = ok and _check(is_equal_approx(main.props._rows["azimuth"].get_value(), -33.0), "pannello sincronizzato")

	# LightPaint: direzione +X interna → az -90
	main.preview.paint.emit(Vector3(1, 0, 0), true)
	ok = ok and _check(is_equal_approx(rig.lights[0].azimuth, -90.0), "paint +X → az -90 (%.1f)" % rig.lights[0].azimuth)
	main.preview.paint.emit(Vector3(0, 1, 0), true)
	ok = ok and _check(is_equal_approx(rig.lights[0].elevation, 90.0), "paint +Y → el 90")
	await process_frame

	# undo / redo
	var before := rig.lights[0].elevation
	main._restore(main.undo.undo())
	ok = ok and _check(not is_equal_approx(main.rig.lights[0].elevation, before), "undo cambia l'elevazione")
	main._restore(main.undo.redo())
	ok = ok and _check(is_equal_approx(main.rig.lights[0].elevation, before), "redo la ripristina")
	await process_frame

	# solo
	main.rig.lights[1].solo = true
	ok = ok and _check(main.rig.active_lights().size() == 1, "solo → 1 luce attiva")
	main.rig.lights[1].solo = false

	# sfondo: HDRI di base dal furnace dello spike
	var base := "res://out/furnace.exr"
	if FileAccess.file_exists(base):
		ok = ok and _check(main.baker.set_base_image_from_file(base), "carica HDRI di base")
		main.rig.base_hdri_path = base
		main.rig.base_enabled = true
		main.rig.base_ev = -2.0
		main._dirty = true
		await process_frame
		await process_frame
		var img: Image = main.baker.get_image()
		var c := img.get_pixel(img.get_width() / 2, int(img.get_height() * 0.9))
		ok = ok and _check(absf(c.r - 0.25) < 0.02, "base a -2 EV → nadir ≈ 0.25 (%.3f)" % c.r)
		main.rig.base_enabled = false
		main._dirty = true

	# salva / apri rig (luce 0 in una posizione asimmetrica per il test del flip)
	main.rig.lights[0].azimuth = -90.0
	main.rig.lights[0].elevation = 20.0
	var rig_path := "res://out/smoke_rig.json"
	ok = ok and _check(main.save_rig_to(rig_path) == OK, "salva rig")
	var n: int = main.rig.lights.size()
	ok = ok and _check(main.load_rig_from(rig_path), "apri rig")
	ok = ok and _check(main.rig.lights.size() == n, "rig riaperto con %d luci" % n)
	await process_frame

	# export con preset C4D (flip) a 2k
	main.export_panel._res.selected = 0
	main.export_panel._target.selected = HdriExport.TARGETS.keys().find("Cinema 4D nativo")
	var t0 := Time.get_ticks_msec()
	ok = ok and _check(main.export_to("res://out/smoke_export.exr") == OK, "export EXR C4D nativo 2k (%d ms)" % (Time.get_ticks_msec() - t0))
	await process_frame
	await process_frame
	ok = ok and _check(main.tex_rd.texture_rd_rid.is_valid(), "texture di preview riagganciata")
	# il flip: la luce 0 sta ad az -90 (u=0.25) → nel file C4D deve stare a u=0.75
	var exp := Image.new()
	exp.load_exr_from_buffer(FileAccess.get_file_as_bytes("res://out/smoke_export.exr"))
	var l0: RigLight = main.rig.lights[0]
	var uv := MapView.light_uv(l0)
	var pr := exp.get_pixel(int((1.0 - uv.x) * exp.get_width()), int(uv.y * exp.get_height()))
	var pl := exp.get_pixel(int(uv.x * exp.get_width()), int(uv.y * exp.get_height()))
	ok = ok and _check(pr.r > 1.0 and pl.r < 1.0, "flip C4D nativo: luce a u=%.2f nel file (%.2f vs %.2f)" % [1.0 - uv.x, pr.r, pl.r])

	# modello GLB nel preview + LightPaint con raycast fisico
	var glb := "res://out/torus.glb"
	if FileAccess.file_exists(glb):
		ok = ok and _check(main.preview.load_model(ProjectSettings.globalize_path(glb)), "carica torus.glb")
		main.preview.set_model_material(Preview3D.ModelMaterial.CHROME)
		for i in 4:
			await process_frame
		main._select(0)
		var before_az: float = main.rig.lights[0].azimuth
		main.rig.lights[0].elevation = 5.0
		var center: Vector2 = main.preview.size * 0.5
		var hit: bool = main.preview._try_paint(center, true)
		ok = ok and _check(hit, "LightPaint sul modello: colpito")
		# la camera guarda il toro dal davanti: il riflesso al centro deve puntare ~verso la camera
		var lm: RigLight = main.rig.lights[0]
		ok = ok and _check(lm.azimuth != before_az or absf(lm.elevation - 5.0) > 0.1, "LightPaint sul modello ha spostato la luce (az %.1f el %.1f)" % [lm.azimuth, lm.elevation])
		main.preview.clear_model()
		ok = ok and _check(not main.preview.has_model(), "modello rimosso")

	# luce Texture: furnace.exr (uniforme 1.0) come immagine → contributo = intensità
	var tex_path := ProjectSettings.globalize_path("res://out/furnace.exr")
	if FileAccess.file_exists(tex_path):
		main.rig.background = LightRig.Background.BLACK
		for l in main.rig.lights:
			l.enabled = false
		main._add_texture_light(tex_path, {"width": 40.0, "height": 30.0, "intensity": 2.0})
		var tl: RigLight = main.rig.lights[main.rig.lights.size() - 1]
		ok = ok and _check(tl.shape == RigLight.Shape.TEXTURE and tl.texture_path == tex_path, "luce Texture aggiunta dal file")
		tl.azimuth = 0.0
		tl.elevation = 0.0
		main._dirty = true
		await process_frame
		await process_frame
		var img: Image = main.baker.get_image()
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		ok = ok and _check(absf(c.r - 2.0) < 0.01, "pixel al centro della luce Texture = 2.0 (%.3f)" % c.r)
		var outside := img.get_pixel(int(img.get_width() * 0.75), img.get_height() / 2)
		ok = ok and _check(outside.r < 0.001, "fuori dalla luce Texture = 0 (%.4f)" % outside.r)

	# catalogo: la cartella out/ contiene gli EXR dello spike
	main.catalog.set_folder(ProjectSettings.globalize_path("res://out"))
	ok = ok and _check(main.catalog._items.size() >= 5, "catalogo: %d immagini trovate" % main.catalog._items.size())
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
	ok = ok and _check(with_icon == main.catalog._items.size(), "miniature generate: %d/%d in %.1f s" % [with_icon, main.catalog._items.size(), waited])
	var n_before: int = main.rig.lights.size()
	main.catalog.light_requested.emit(tex_path, main.catalog._defaults({"path": tex_path, "name": "furnace", "sidecar": {}}))
	ok = ok and _check(main.rig.lights.size() == n_before + 1, "click sul catalogo aggiunge una luce")

	# catalogo per sottocartelle: out/softbox/ contiene una copia
	ok = ok and _check(main.catalog._sections.size() >= 2, "catalogo: %d sezioni (sottocartelle)" % main.catalog._sections.size())
	var idx := -1
	for i in main.catalog._subfolder.item_count:
		if main.catalog._subfolder.get_item_text(i) == "softbox":
			idx = i
	ok = ok and _check(idx > 0, "menu sottocartelle contiene 'softbox'")
	main.catalog._subfolder.selected = idx
	main.catalog._apply_filter()
	var vis := 0
	for path in main.catalog._buttons:
		if main.catalog._buttons[path].visible:
			vis += 1
	ok = ok and _check(vis == 1, "filtro per sottocartella: %d visibile" % vis)
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
	ok = ok and _check(absf(pht.measured_k - 0.1769) < 0.002, "K misurato = %.4f sr (atteso 0.1769)" % pht.measured_k)
	var pimg: Image = main.baker.get_image()
	var pc := pimg.get_pixel(pimg.get_width() / 2, pimg.get_height() / 2)
	ok = ok and _check(absf(pc.r - 1.0 / pht.measured_k) < 0.01, "radianza al centro = %.3f = 1/K" % pc.r)
	# K non dipende dalla posizione, sì dalla dimensione
	pht.azimuth = 60.0
	pht.elevation = -20.0
	main._dirty = true
	await process_frame
	ok = ok and _check(absf(pht.measured_k - 0.1769) < 0.002, "K invariante alla posizione")
	pht.width = 60.0
	main._dirty = true
	await process_frame
	ok = ok and _check(pht.measured_k > 0.3, "K cresce con la larghezza (%.4f)" % pht.measured_k)

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
	ok = ok and _check(absf(nc.r - 0.2) < 0.01, "fusione Normale copre lo sfondo: %.3f" % nc.r)

	# riordino
	var last: int = main.rig.lights.size() - 1
	main.light_list.select(last)
	main.light_list._move(-1)
	ok = ok and _check(main.rig.lights[last - 1] == pht and main._selected == last - 1, "sposta su")
	main.light_list._move(1)
	ok = ok and _check(main.rig.lights[last] == pht, "sposta giù")

	# LightPaint senza selezione crea una luce
	main._select(-1)
	var n0: int = main.rig.lights.size()
	main.preview.paint.emit(Vector3(0, 0, 1), true)
	ok = ok and _check(main.rig.lights.size() == n0 + 1 and main._selected == n0, "LightPaint senza selezione crea una luce")

	print("[smoke] %s" % ("TUTTO OK" if ok else "FALLITO"))
	quit(0 if ok else 1)


func _check(cond: bool, label: String) -> bool:
	print("[smoke] %s %s" % ["✓" if cond else "✗", label])
	return cond
