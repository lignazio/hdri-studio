extends SceneTree
## Verifica che la sfera diffusa (illuminata dalla mappa di radianza del cielo) segua i cambiamenti
## del rig: con luci → senza → di nuovo con luci. Uso: Godot --path hdri_studio -s res://tools/sky_smoke.gd -- --fresh

func _initialize() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run(main)


func _mean(main: Node) -> float:
	var img := root.get_texture().get_image()
	var r: Rect2 = main.preview.get_global_rect()
	# l'immagine è in pixel fisici, il rettangolo in pixel logici (senza --fresh su un Retina la scala è 2)
	var c := Vector2(r.position.x + r.size.x * 0.78, r.position.y + r.size.y * 0.45) * root.content_scale_factor
	var sum := 0.0
	var n := 0
	for dx in range(-12, 13, 4):
		for dy in range(-12, 13, 4):
			sum += img.get_pixel(int(c.x) + dx, int(c.y) + dy).get_luminance()
			n += 1
	return sum / n


func _run(main: Node) -> void:
	for i in 30:
		await process_frame
	var lit := _mean(main)
	for l in main.rig.lights:
		l.enabled = false
	main.rig.background = LightRig.Background.BLACK
	main._dirty = true
	for i in 40:
		await process_frame
	var dark := _mean(main)
	for l in main.rig.lights:
		l.enabled = true
	main.rig.background = LightRig.Background.GRADIENT
	main._dirty = true
	for i in 40:
		await process_frame
	var relit := _mean(main)
	var ok := dark < lit * 0.3 and relit > dark * 3.0
	print("[sky] diffusa: con luci %.3f · senza %.3f · di nuovo con luci %.3f → %s" % [lit, dark, relit, "TUTTO OK" if ok else "FALLITO"])
	quit(0 if ok else 1)
