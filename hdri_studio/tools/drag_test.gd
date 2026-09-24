extends SceneTree
## Test del drag & drop dal catalogo alla mappa attraverso il vero percorso del mouse.
## Muove il cursore di sistema (Godot individua il bersaglio del drop dalla posizione reale del
## cursore, non dagli eventi iniettati): non toccare il mouse durante l'esecuzione.
## Uso:  Godot --path hdri_studio -s res://tools/drag_test.gd -- --fresh

func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)

func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)

func _move(from: Vector2, to: Vector2) -> void:
	DisplayServer.warp_mouse(Vector2i(to))
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - from
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)

func _run(main: Node) -> void:
	await process_frame
	await process_frame
	main.catalog.set_folder(ProjectSettings.globalize_path("res://out"))
	main.tabs.current_tab = 1
	await create_timer(1.0).timeout
	var btn: Button = null
	for path in main.catalog._buttons:
		if path.ends_with("furnace.exr"):
			btn = main.catalog._buttons[path]
	(main.catalog._list.get_parent() as ScrollContainer).ensure_control_visible(btn)
	await process_frame
	await process_frame
	var start: Vector2 = btn.get_global_rect().get_center()
	var mrect: Rect2 = main.map_view._map_rect()
	var target: Vector2 = main.map_view.get_global_rect().position + mrect.position + mrect.size * Vector2(0.75, 0.25)
	var n0: int = main.rig.lights.size()
	print("[dd] premo su ", start, " (finestra ", main.get_viewport().get_visible_rect().size, ") → rilascio su ", target)
	DisplayServer.warp_mouse(Vector2i(start))
	await process_frame
	_mouse(start, true)
	await process_frame
	var p := start
	for i in 12:
		var q := start.lerp(target, float(i + 1) / 12.0)
		_move(p, q)
		p = q
		await process_frame
		if i == 2:
			print("[dd] dopo 3 movimenti, drag in corso: ", main.get_viewport().gui_is_dragging())
	print("[dd] prima del rilascio, drag in corso: ", main.get_viewport().gui_is_dragging())
	_mouse(target, false)
	await process_frame
	await process_frame
	var added: int = main.rig.lights.size() - n0
	if added == 1:
		var l: RigLight = main.rig.lights[main.rig.lights.size() - 1]
		print("[dd] ✓ luce creata via drag reale: az %.1f el %.1f" % [l.azimuth, l.elevation])
	else:
		print("[dd] ✗ nessuna luce creata (", added, ")")
	quit()
