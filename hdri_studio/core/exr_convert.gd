class_name ExrConvert
extends RefCounted
## Riconversione degli EXR con un altro codec tramite Blender in batch (Godot scrive solo PIZ).
## Lossless: PIZ, ZIP, ZIPS, RLE, NONE. Lossy: PXR24 (float → 24 bit), B44/B44A, DWAA/DWAB.

const CODECS := ["PIZ", "ZIP", "ZIPS", "RLE", "PXR24", "B44", "B44A", "DWAA", "DWAB", "NONE"]

## Script eseguito da Blender: coppie sorgente/destinazione dopo "--", scrive in un temporaneo e
## rinomina, così il file non è mai a metà.
const PY := """
import bpy, os, sys
args = sys.argv[sys.argv.index('--') + 1:]
codec, depth = args[0], args[1]
pairs = list(zip(args[2::2], args[3::2]))
s = bpy.context.scene.render.image_settings
s.file_format = 'OPEN_EXR'; s.exr_codec = codec; s.color_depth = depth; s.color_mode = 'RGB'
s.color_management = 'OVERRIDE'; bpy.context.scene.view_settings.view_transform = 'Standard'
for src, dst in pairs:
    img = bpy.data.images.load(src, check_existing=False)
    tmp = dst + '.tmp.exr'
    img.save_render(tmp, scene=bpy.context.scene)
    os.replace(tmp, dst)
    bpy.data.images.remove(img)
print('[exr-convert] %d file in %s' % (len(pairs), codec))
"""


static func find_blender() -> String:
	var custom: String = AppSettings.get_value("blender_path", "")
	if custom != "" and FileAccess.file_exists(custom):
		return custom
	var candidates: Array[String] = []
	match OS.get_name():
		"macOS":
			candidates.append("/Applications/Blender.app/Contents/MacOS/Blender")
		"Windows":
			for base in ["C:/Program Files/Blender Foundation", "C:/Program Files (x86)/Blender Foundation"]:
				var dir := DirAccess.open(base)
				if dir == null:
					continue
				var subs: Array[String] = []
				dir.list_dir_begin()
				var e := dir.get_next()
				while e != "":
					if dir.current_is_dir() and e.begins_with("Blender"):
						subs.append(e)
					e = dir.get_next()
				dir.list_dir_end()
				subs.sort()
				subs.reverse()
				for s in subs:
					candidates.append(base.path_join(s).path_join("blender.exe"))
		_:
			candidates.append_array(["/usr/bin/blender", "/usr/local/bin/blender", "/snap/bin/blender"])
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


const CACHE_DIR := "user://exr_piz_cache"
## Codec (valore dell'attributo "compression") che TinyEXR sa decodificare: NONE, RLE, ZIPS, ZIP, PIZ.
const TINYEXR_READABLE := [0, 1, 2, 3, 4]


## Legge l'attributo "compression" dall'header EXR senza decodificare l'immagine (-1 se non EXR).
static func compression_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var head := f.get_buffer(mini(f.get_length(), 65536))
	if head.size() < 8 or head[0] != 0x76 or head[1] != 0x2f or head[2] != 0x31 or head[3] != 0x01:
		return -1
	var i := 8
	while i < head.size():
		if head[i] == 0: # fine degli attributi
			return -1
		var name_end := head.find(0, i)
		if name_end < 0:
			return -1
		var name := head.slice(i, name_end).get_string_from_ascii()
		var type_end := head.find(0, name_end + 1)
		if type_end < 0:
			return -1
		var size := head.decode_s32(type_end + 1)
		var value_at := type_end + 5
		if name == "compression":
			return head[value_at] if value_at < head.size() else -1
		i = value_at + size
	return -1


static func tinyexr_can_read(path: String) -> bool:
	return compression_of(path) in TINYEXR_READABLE


## EXR che TinyEXR non decodifica (DWAA/DWAB, B44, PXR24): lo converte in PIZ con Blender, in modo
## sincrono, in una cache per percorso + data di modifica. Restituisce il file convertito o "".
## Sicuro da chiamare da un thread (nessun accesso alla scena).
static func to_piz_cached(path: String) -> String:
	var blender := find_blender()
	if blender == "":
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var key := (path + ":" + str(FileAccess.get_modified_time(path))).md5_text()
	var dst := ProjectSettings.globalize_path(CACHE_DIR + "/" + key + ".exr")
	if FileAccess.file_exists(dst):
		return dst
	var args: Array[String] = ["-b", "--python-expr", PY, "--", "PIZ", "16", path, dst]
	var code := OS.execute(blender, args, [], false)
	return dst if code == 0 and FileAccess.file_exists(dst) else ""


## Avvia Blender in background sulle coppie [src, dst, ...]. Restituisce il pid, o -1.
static func start(pairs: Array, codec: String, half: bool) -> int:
	var blender := find_blender()
	if blender == "" or pairs.is_empty():
		return -1
	var args: Array[String] = ["-b", "--python-expr", PY, "--", codec, "16" if half else "32"]
	for p in pairs:
		args.append(ProjectSettings.globalize_path(p))
	return OS.create_process(blender, args, false)
