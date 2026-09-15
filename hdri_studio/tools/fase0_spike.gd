extends SceneTree
## Fase 0 — spike: bake → EXR (float e half) → PNG di controllo, senza UI.
## Uso:  Godot --path hdri_studio -s res://tools/fase0_spike.gd
## Scrive in hdri_studio/out/.

const OUT := "res://out/"

var Baker := preload("res://bake/baker.gd")
var Rig := preload("res://core/light_rig.gd")
var Light := preload("res://core/rig_light.gd")
var Exp := preload("res://export/hdri_export.gd")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var t0 := Time.get_ticks_msec()
	var baker = Baker.new(false)
	baker.set_resolution(4096, 2048)
	print("Baker pronto in %d ms (RD: %s)" % [Time.get_ticks_msec() - t0, baker.rd.get_device_name()])

	_run(baker, "calibration", _rig_empty(), true)
	_run(baker, "furnace", _rig_furnace())
	_run(baker, "rect", _rig_rect())
	_run(baker, "shapes", _rig_shapes())
	_run(baker, "scrim", _rig_scrim())
	_run(baker, "studio", _rig_studio())

	baker.free_resources()
	print("Fatto.")
	quit()


func _run(baker, name: String, rig, calibration := false) -> void:
	var t0 := Time.get_ticks_msec()
	baker.bake(rig, calibration)
	var img: Image = baker.get_image()
	var t1 := Time.get_ticks_msec()
	var err := Exp.save_exr(img, OUT + name + ".exr", true)
	var err2 := Exp.save_exr(img, OUT + name + "_f32.exr", false)
	var t2 := Time.get_ticks_msec()
	# PNG di controllo a bassa risoluzione per non aspettare la conversione in GDScript
	var small := img.duplicate() as Image
	small.resize(1024, 512, Image.INTERPOLATE_BILINEAR)
	Exp.save_preview_png(small, OUT + name + ".png", 1.0)
	print("%-12s bake+readback %4d ms | exr %4d ms | half %s | f32 %s | pixel centro %s" % [
		name, t1 - t0, t2 - t1, error_string(err), error_string(err2),
		img.get_pixel(img.get_width() / 2, img.get_height() / 2)])
	rig.save_json(OUT + name + ".json")


func _rig_empty():
	var r = Rig.new()
	r.background = Rig.Background.UNIFORM
	r.bg_horizon = Color(0.18, 0.18, 0.18)
	return r


func _rig_furnace():
	var r = Rig.new()
	r.background = Rig.Background.UNIFORM
	r.bg_horizon = Color(1, 1, 1)
	return r


func _rig_rect():
	var r = Rig.new()
	r.background = Rig.Background.BLACK
	var l = Light.new()
	l.name = "key"
	l.shape = Light.Shape.RECT
	l.azimuth = 45.0
	l.elevation = 30.0
	l.width = 30.0
	l.height = 20.0
	l.softness = 0.0
	l.intensity = 10.0
	r.add_light(l)
	return r


func _rig_shapes():
	var r = Rig.new()
	r.background = Rig.Background.GRADIENT
	r.bg_zenith = Color(0.10, 0.11, 0.13)
	r.bg_horizon = Color(0.03, 0.03, 0.03)
	r.bg_nadir = Color(0, 0, 0)
	var specs := [
		["rect", Light.Shape.RECT, -120.0, 20.0, 40.0, 25.0, 3.0],
		["ellipse", Light.Shape.ELLIPSE, -40.0, 35.0, 30.0, 30.0, 4.0],
		["ring", Light.Shape.RING, 40.0, 10.0, 35.0, 35.0, 1.0],
		["gradient", Light.Shape.GRADIENT, 120.0, -10.0, 60.0, 40.0, 0.0],
	]
	var kelvins := [3200.0, 5600.0, 6500.0, 9000.0]
	for i in specs.size():
		var s: Array = specs[i]
		var l = Light.new()
		l.name = s[0]
		l.shape = s[1]
		l.azimuth = s[2]
		l.elevation = s[3]
		l.width = s[4]
		l.height = s[5]
		l.softness = s[6]
		l.intensity = 4.0
		l.kelvin = kelvins[i]
		l.roll = 15.0 if l.shape == Light.Shape.RECT else 0.0
		r.add_light(l)
	return r


func _rig_scrim():
	var r = Rig.new()
	r.background = Rig.Background.BLACK
	var depths := [0.2, 0.6, 1.5]
	for i in depths.size():
		var l = Light.new()
		l.name = "scrim_%0.1f" % depths[i]
		l.shape = Light.Shape.SCRIM
		l.azimuth = -90.0 + 90.0 * i
		l.elevation = 20.0
		l.width = 60.0
		l.height = 40.0
		l.softness = 1.0
		l.intensity = 5.0
		l.scrim_depth = depths[i]
		l.scrim_offset = Vector2(0.3, 0.2) if i == 1 else Vector2.ZERO
		r.add_light(l)
	return r


## Un set da still life: key scrim, fill morbido, rim, sfondo a gradiente.
func _rig_studio():
	var r = Rig.new()
	r.background = Rig.Background.GRADIENT
	r.bg_zenith = Color(0.06, 0.07, 0.09)
	r.bg_horizon = Color(0.02, 0.02, 0.025)
	r.bg_nadir = Color(0, 0, 0)
	var key = Light.new()
	key.name = "key scrim"
	key.shape = Light.Shape.SCRIM
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
	var fill = Light.new()
	fill.name = "fill"
	fill.shape = Light.Shape.GRADIENT
	fill.azimuth = 70.0
	fill.elevation = 10.0
	fill.width = 90.0
	fill.height = 70.0
	fill.intensity = 1.2
	fill.kelvin = 7000.0
	r.add_light(fill)
	var rim = Light.new()
	rim.name = "rim strip"
	rim.shape = Light.Shape.RECT
	rim.azimuth = 160.0
	rim.elevation = 25.0
	rim.width = 8.0
	rim.height = 60.0
	rim.softness = 1.5
	rim.intensity = 20.0
	rim.kelvin = 6500.0
	rim.roll = 10.0
	r.add_light(rim)
	var top = Light.new()
	top.name = "top ring"
	top.shape = Light.Shape.RING
	top.azimuth = 0.0
	top.elevation = 88.0
	top.width = 40.0
	top.ring_inner = 0.7
	top.softness = 2.0
	top.intensity = 3.0
	r.add_light(top)
	return r
