extends SceneTree
## Smoke test del live link: avvia l'app, attiva il link, muove una luce e aspetta il client Python
## (plugins/c4d/hdri_studio_link/link_core.py lanciato in parallelo).

func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _run(main: Node) -> void:
	await process_frame
	await process_frame
	var ok := true
	main.rig.live_export_path = ProjectSettings.globalize_path("res://out/live.exr")
	main.link_panel.set_path(main.rig.live_export_path)
	main.link_panel._enabled.button_pressed = true
	ok = ok and _check(main.link.is_listening(), "server in ascolto su %d" % main.link.port)
	# primo export automatico (schedulato dall'attivazione)
	await create_timer(1.0).timeout
	ok = ok and _check(FileAccess.file_exists(main.rig.live_export_path), "live.exr scritto")
	# aspetta il client
	var waited := 0.0
	while main.link.client_count() == 0 and waited < 8.0:
		await create_timer(0.2).timeout
		waited += 0.2
	ok = ok and _check(main.link.client_count() == 1, "client collegato (%.1f s)" % waited)
	await create_timer(0.5).timeout
	# modifica → debounce → export → notify
	main.map_view.light_moved.emit(0, 30.0, 10.0, true)
	await create_timer(1.5).timeout
	ok = ok and _check(not main._live_dirty, "export live eseguito dopo la modifica")
	# il client risponde con un lightpaint → luce 0 verso -Z
	await create_timer(1.5).timeout
	var l0: RigLight = main.rig.lights[0]
	ok = ok and _check(absf(absf(l0.azimuth) - 180.0) < 0.5 and absf(l0.elevation) < 0.5, "lightpaint da C4D → az %.1f el %.1f" % [l0.azimuth, l0.elevation])
	print("[link-smoke] %s" % ("TUTTO OK" if ok else "FALLITO"))
	quit(0 if ok else 1)


func _check(cond: bool, label: String) -> bool:
	print("[link-smoke] %s %s" % ["✓" if cond else "✗", label])
	return cond
