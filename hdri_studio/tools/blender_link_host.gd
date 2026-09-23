extends SceneTree
## Lato app dei test del live link (Blender e Houdini): avvia l'app con il link attivo, una luce
## separata (az 0, el 0, 150 cm) e stampa dove finisce la luce selezionata a ogni lightpaint ricevuto.
## Uso:  Godot --path hdri_studio -s res://tools/blender_link_host.gd [-- --target <preset>]
##       (poi il test Blender o Houdini; il preset di default è "Godot / Blender")

func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _run(main: Node) -> void:
	await process_frame
	await process_frame
	main.rig.live_export_path = ProjectSettings.globalize_path("res://out/live.exr")
	main.link_panel.set_path(main.rig.live_export_path)
	var args := OS.get_cmdline_user_args()
	var ti := args.find("--target")
	var target := args[ti + 1] if ti >= 0 and ti + 1 < args.size() else "Godot / Blender"
	main.export_panel._target.selected = maxi(HdriExport.TARGETS.keys().find(target), 0)
	var l0: RigLight = main.rig.lights[0]
	l0.separate = true
	l0.distance = 150.0
	l0.azimuth = 0.0
	l0.elevation = 0.0
	l0.width = 40.0
	l0.height = 20.0
	main._select(1)
	main.link_panel._enabled.button_pressed = true
	print("[host] in ascolto, luce 0 separata; luce selezionata: 1")
	var last := Vector2(INF, INF)
	var t := 0.0
	while t < 25.0:
		await create_timer(0.25).timeout
		t += 0.25
		var l: RigLight = main.rig.lights[main._selected]
		var cur := Vector2(l.azimuth, l.elevation)
		if cur != last:
			print("[host] luce selezionata: az %.1f el %.1f" % [cur.x, cur.y])
			last = cur
	print("[host] fine")
	quit()
