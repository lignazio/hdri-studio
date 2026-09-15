extends SceneTree
## Esporta la coppia per la verifica fisica delle luci separate (tools/blender_separate_verify.py):
## la stessa luce rect 30°×20° L=10 ad az 0 / el 0, prima nell'HDRI, poi separata (HDRI nera + EXR planare).

func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _run(main: Node) -> void:
	await process_frame
	await process_frame
	main.rig.lights.clear()
	main.rig.background = LightRig.Background.BLACK
	var l := RigLight.new()
	l.name = "key"
	l.width = 30.0
	l.height = 20.0
	l.softness = 0.0
	l.intensity = 10.0
	l.distance = 150.0
	main.rig.add_light(l)
	main.export_panel._res.selected = 1
	main.export_panel._target.selected = HdriExport.TARGETS.keys().find("Godot / Blender")
	main.link_panel._sep_flip_tex.button_pressed = false
	main.export_to("res://out/sepv_hdri.exr")
	l.separate = true
	main.export_to("res://out/sepv_black.exr")
	var msg: Dictionary = main.separate_message()
	var f := FileAccess.open("res://out/sepv_message.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(msg))
	print("[sepv] scritti sepv_hdri.exr, sepv_black.exr, sepv_black_key.exr, sepv_message.json")
	quit()
