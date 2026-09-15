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

	print("[smoke] %s" % ("TUTTO OK" if ok else "FALLITO"))
	quit(0 if ok else 1)


func _check(cond: bool, label: String) -> bool:
	print("[smoke] %s %s" % ["✓" if cond else "✗", label])
	return cond
