extends SceneTree
## Verifica della GDExtension HsOpenEXR: scrive un'immagine di prova in ogni codec, la rilegge, confronta
## i pixel (lossless = identici, lossy = entro tolleranza) e controlla i metadati.
## Uso: Godot --headless --path hdri_studio -s res://tools/exr_smoke.gd

const W := 256
const H := 128


func _initialize() -> void:
	var ok := true
	if not ClassDB.class_exists("HsOpenEXR"):
		push_error("HsOpenEXR non caricata")
		quit(1)
		return
	print("[exr-smoke] OpenEXR ", ClassDB.class_call_static("HsOpenEXR", "version"))
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBAF)
	for y in H:
		for x in W:
			img.set_pixel(x, y, Color(x / float(W) * 8.0, y / float(H) * 2.0, sin(x * 0.1) * 0.5 + 0.5, 1.0))
	img.set_pixel(3, 3, Color(70000.0, 0.0, 0.0, 1.0)) # oltre l'half
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://exr_smoke"))
	var attrs := {"comments": "prova", "hdristudio_rig": "{\"a\": 1}", "chromaticities": PackedFloat32Array([0.64, 0.33, 0.3, 0.6, 0.15, 0.06, 0.3127, 0.329])}
	var codecs: PackedStringArray = ClassDB.class_call_static("HsOpenEXR", "codecs")
	for codec in codecs:
		for half in [true, false]:
			var path := "user://exr_smoke/%s_%s.exr" % [codec, "half" if half else "f32"]
			var t0 := Time.get_ticks_usec()
			var err: Error = ClassDB.class_call_static("HsOpenEXR", "save", img, path, codec, half, attrs, 45.0)
			var t_save := (Time.get_ticks_usec() - t0) / 1000.0
			if err != OK:
				push_error("%s: save %s" % [codec, error_string(err)])
				ok = false
				continue
			t0 = Time.get_ticks_usec()
			var back: Image = ClassDB.class_call_static("HsOpenEXR", "load", path)
			var t_load := (Time.get_ticks_usec() - t0) / 1000.0
			if back == null or back.get_width() != W or back.get_height() != H:
				push_error("%s: load fallito" % codec)
				ok = false
				continue
			var lossy := codec in ["PXR24", "B44", "B44A", "DWAA", "DWAB"]
			var max_err := 0.0
			for y in range(0, H, 3):
				for x in range(0, W, 3):
					if x < 8 and y < 8:
						continue # il blocco attorno al picco: nei codec lossy l'inf sporca i vicini
					var a := img.get_pixel(x, y)
					var b := back.get_pixel(x, y)
					max_err = max(max_err, abs(a.r - b.r) / max(a.r, 1.0), abs(a.g - b.g) / max(a.g, 1.0), abs(a.b - b.b) / max(a.b, 1.0))
			var tol := 0.05 if lossy else (0.001 if half else 0.0)
			# in half 70000 diventa inf; i codec lossy non lo conservano (l'app in quel caso scrive float32)
			var peak := back.get_pixel(3, 3).r
			var peak_ok: bool = peak > 60000.0 or is_inf(peak) or (half and lossy)
			var info: Dictionary = ClassDB.class_call_static("HsOpenEXR", "info", path)
			var meta_ok: bool = info.get("compression", "") == codec and info.get("half", false) == half \
				and info.get("attributes", {}).get("hdristudio_rig", "") == "{\"a\": 1}" \
				and HdriExport.read_string_attribute(path, "comments") == "prova"
			var size := FileAccess.get_file_as_bytes(path).size()
			# TinyEXR (Godot) deve rileggere i codec che conosce
			var tiny_ok := true
			if codec in ["NONE", "RLE", "ZIPS", "ZIP", "PIZ"]:
				var t := Image.new()
				tiny_ok = t.load_exr_from_buffer(FileAccess.get_file_as_bytes(path)) == OK and t.get_width() == W
			var line := "%-6s %-4s  save %6.1f ms  load %6.1f ms  %7d B  err max %.4f  picco %s  meta %s  tinyexr %s" % [
				codec, "half" if half else "f32", t_save, t_load, size, max_err, "ok" if peak_ok else "NO", "ok" if meta_ok else "NO", "ok" if tiny_ok else "NO"]
			print("[exr-smoke] " + line)
			if max_err > tol or not peak_ok or not meta_ok or not tiny_ok:
				push_error("%s %s: fuori tolleranza o metadati/tinyexr errati" % [codec, "half" if half else "f32"])
				ok = false
	# lettura di un EXR scritto da Godot (TinyEXR) e di un file inesistente
	var g := "user://exr_smoke/godot.exr"
	img.save_exr(g)
	var gb: Image = ClassDB.class_call_static("HsOpenEXR", "load", g)
	if gb == null or gb.get_pixel(10, 10).is_equal_approx(Color.BLACK):
		push_error("EXR di Godot non riletto")
		ok = false
	if ClassDB.class_call_static("HsOpenEXR", "load", "user://exr_smoke/nope.exr") != null:
		push_error("file inesistente non segnalato")
		ok = false
	print("[exr-smoke] ", "OK" if ok else "FALLITO")
	quit(0 if ok else 1)
