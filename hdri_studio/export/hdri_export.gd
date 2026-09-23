class_name HdriExport
extends RefCounted
## Scrittura dell'HDRI su disco. I dati restano lineari: nessun tone mapping qui.

const HALF_MAX := 65504.0

## Preset di orientamento per software. flip = specchio orizzontale; shift = rotazione in gradi
## applicata prima della scrittura (positiva = la scena ruota verso destra sulla mappa).
## Misurati con out/calibration.exr (punto bianco ad az +25°, cioè a destra del centro nel preview):
##  - Blender: rotazione pura, nessun flip.
##  - Cinema 4D + Octane: punto bianco a destra → come il preview, nessun flip.
##  - Cinema 4D nativo (Standard/Physical): punto bianco a sinistra → specchio.
##  - Houdini: punto bianco a destra, centro immagine su −Z → come Blender (misurato il 23/09
##    con tools/houdini_calibrate.py, Karma).
## mirror_x: le basi delle luci separate vanno specchiate sull'asse X (Cinema 4D è left-handed; con il
## preset "nativo" è l'immagine a essere specchiata, non gli assi). Verso e specchio della texture delle
## luci separate sono opzioni del pannello Live link.
const TARGETS := {
	"Cinema 4D + Octane": {"flip": false, "shift": 0.0, "mirror_x": true},
	"Cinema 4D nativo": {"flip": true, "shift": 0.0, "mirror_x": false},
	"Godot / Blender": {"flip": false, "shift": 0.0, "mirror_x": false},
	"Houdini": {"flip": false, "shift": 0.0, "mirror_x": false},
}
const DEFAULT_TARGET := "Cinema 4D + Octane"


## Riga dell'header Radiance che porta il rig, come RIG_ATTR per l'EXR. L'header .hdr è testo (una
## riga per variabile, fino alla prima riga vuota) e il JSON ci sta su una riga sola, così anche un
## .hdr riapre il progetto. La scriviamo come commento (`#`): i lettori saltano i commenti in
## silenzio, mentre una variabile sconosciuta fa rumore (Godot stampa un warning con tutta la riga).
const RIG_HDR_KEY := "HDRISTUDIO_RIG"


## Radiance .hdr (RGBE, non compresso: lo leggono tutti). rgbe: 4 byte per pixel dal baker.
static func save_hdr(path: String, width: int, height: int, rgbe: PackedByteArray, rig_json := "") -> Error:
	if rgbe.size() != width * height * 4:
		return ERR_INVALID_DATA
	var dest := ProjectSettings.globalize_path(path)
	var tmp := dest + ".tmp.hdr"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var head := "#?RADIANCE\nFORMAT=32-bit_rle_rgbe\nSOFTWARE=HDRI Studio\n"
	if rig_json != "":
		# JSON.stringify non produce a capo veri, ma una stringa arrivata da altrove potrebbe: un a
		# capo qui chiuderebbe l'header a metà del rig.
		head += "#" + RIG_HDR_KEY + "=" + rig_json.replace("\n", " ").replace("\r", " ") + "\n"
	f.store_string(head + "\n-Y %d +X %d\n" % [height, width])
	f.store_buffer(rgbe)
	f.close()
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	return DirAccess.rename_absolute(tmp, dest)


# --- metadati EXR --------------------------------------------------------------------------------
# Godot scrive l'EXR senza attributi custom: li iniettiamo nell'header dopo la scrittura. L'header è
# una lista di attributi (nome\0 tipo\0 int32 size valore) chiusa da un byte 0, seguita dalla tabella
# degli offset assoluti dei blocchi di scanline: inserire byte nell'header impone di sommare lo
# spostamento a ogni offset.

const REC709 := [0.64, 0.33, 0.30, 0.60, 0.15, 0.06, 0.3127, 0.3290]
## ACEScg (AP1) con bianco D60.
const ACESCG := [0.713, 0.293, 0.165, 0.830, 0.128, 0.044, 0.32168, 0.33767]
const COLORSPACES := ["Rec.709 linear", "ACEScg"]
const RIG_ATTR := "hdristudio_rig"
const LINES_PER_CHUNK := {0: 1, 1: 1, 2: 1, 3: 16, 4: 32, 5: 16, 6: 32, 7: 32, 8: 32, 9: 256}


static func _attr(name: String, type: String, value: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(name.to_ascii_buffer())
	out.append(0)
	out.append_array(type.to_ascii_buffer())
	out.append(0)
	var size := PackedByteArray()
	size.resize(4)
	size.encode_s32(0, value.size())
	out.append_array(size)
	out.append_array(value)
	return out


## Senza HsOpenEXR: inietta chromaticities, commento e rig (JSON) nell'header di un EXR scritto da
## TinyEXR, rimuovendo eventuali copie precedenti degli stessi attributi. Restituisce OK o l'errore.
static func inject_metadata(path: String, rig_json: String, acescg := false) -> Error:
	var abs := ProjectSettings.globalize_path(path)
	var data := FileAccess.get_file_as_bytes(abs)
	if data.size() < 8 or data[0] != 0x76 or data[1] != 0x2f or data[2] != 0x31 or data[3] != 0x01:
		return ERR_FILE_UNRECOGNIZED
	var version := data.decode_u32(4)
	if version & 0x200 or version & 0x1000 or version & 0x800:
		return ERR_UNAVAILABLE # tiled, multipart o deep: non gestiti
	# scorre gli attributi, ricostruendo l'header senza i nostri e leggendo compressione e dataWindow
	var i := 8
	var header := PackedByteArray()
	var compression := 3
	var height := 0
	var ours := ["chromaticities", "comments", RIG_ATTR]
	while i < data.size():
		if data[i] == 0:
			i += 1
			break
		var name_end := data.find(0, i)
		var type_end := data.find(0, name_end + 1)
		var size := data.decode_s32(type_end + 1)
		var value_at := type_end + 5
		var name := data.slice(i, name_end).get_string_from_ascii()
		var next := value_at + size
		if name == "compression":
			compression = data[value_at]
		elif name == "dataWindow":
			height = data.decode_s32(value_at + 12) - data.decode_s32(value_at + 4) + 1
		if not (name in ours):
			header.append_array(data.slice(i, next))
		i = next
	var old_header_end := i # inizio della tabella degli offset nel file originale
	var attrs := metadata(rig_json, acescg)
	var chroma := PackedByteArray()
	chroma.resize(32)
	for k in 8:
		chroma.encode_float(k * 4, attrs["chromaticities"][k])
	header.append_array(_attr("chromaticities", "chromaticities", chroma))
	header.append_array(_attr("comments", "string", attrs["comments"].to_utf8_buffer()))
	if attrs.has(RIG_ATTR):
		header.append_array(_attr(RIG_ATTR, "string", attrs[RIG_ATTR].to_utf8_buffer()))
	header.append(0)
	var new_header_end := 8 + header.size()
	var delta := new_header_end - old_header_end
	var lines: int = LINES_PER_CHUNK.get(compression, 1)
	@warning_ignore("integer_division")
	var chunks := (height + lines - 1) / lines
	var table := data.slice(old_header_end, old_header_end + chunks * 8)
	for c in chunks:
		table.encode_u64(c * 8, table.decode_u64(c * 8) + delta)
	var out := PackedByteArray()
	out.append_array(data.slice(0, 8))
	out.append_array(header)
	out.append_array(table)
	out.append_array(data.slice(old_header_end + chunks * 8))
	var tmp := abs + ".tmp.exr"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(out)
	f.close()
	DirAccess.remove_absolute(abs)
	return DirAccess.rename_absolute(tmp, abs)


## Legge un attributo stringa dall'header di un EXR ("" se assente).
static func read_string_attribute(path: String, attr: String) -> String:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return ""
	var head := f.get_buffer(mini(f.get_length(), 4 << 20))
	if head.size() < 8 or head[0] != 0x76:
		return ""
	var i := 8
	while i < head.size():
		if head[i] == 0:
			return ""
		var name_end := head.find(0, i)
		var type_end := head.find(0, name_end + 1)
		if name_end < 0 or type_end < 0:
			return ""
		var size := head.decode_s32(type_end + 1)
		var value_at := type_end + 5
		if head.slice(i, name_end).get_string_from_ascii() == attr:
			return head.slice(value_at, value_at + size).get_string_from_utf8()
		i = value_at + size
	return ""


## Legge una variabile dall'header di un Radiance .hdr ("" se assente). L'header finisce alla prima
## riga vuota, prima della riga di risoluzione.
static func read_hdr_variable(path: String, key: String) -> String:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return ""
	if not f.get_line().begins_with("#?"):
		return ""
	var prefix := key + "="
	while not f.eof_reached():
		var line := f.get_line()
		if line == "":
			break # riga vuota: l'header finisce qui
		line = line.trim_prefix("#")
		if line.begins_with(prefix):
			return line.substr(prefix.length())
	return ""


## Rig salvato dentro l'immagine, qualunque sia il formato ("" se il file non ne ha).
static func read_rig_json(path: String) -> String:
	if path.get_extension().to_lower() == "hdr":
		return read_hdr_variable(path, RIG_HDR_KEY)
	return read_string_attribute(path, RIG_ATTR)


## Percorso dell'EXR singolo di una luce separata, accanto all'HDRI principale: <base>_<nome>.exr
static func separate_path(base_path: String, light_name: String) -> String:
	var slug := ""
	for ch in light_name.to_lower():
		slug += ch if ch.is_valid_identifier() or ch.is_valid_int() else "_"
	slug = slug.strip_edges().trim_prefix("_").trim_suffix("_")
	if slug == "":
		slug = "light"
	var ext := base_path.get_extension().to_lower()
	return base_path.get_basename() + "_" + slug + "." + (ext if ext in ["exr", "hdr"] else "exr")


## Applica il preset (specchio + rotazione) e restituisce una nuova immagine.
static func apply_orientation(img: Image, target: String, extra_shift_deg := 0.0) -> Image:
	var t: Dictionary = TARGETS.get(target, TARGETS["Godot / Blender"])
	var out := img.duplicate() as Image
	if t["flip"]:
		out.flip_x()
	var shift_deg: float = t["shift"] + extra_shift_deg
	var px := int(round(fposmod(shift_deg, 360.0) / 360.0 * out.get_width())) % out.get_width()
	if px != 0:
		out = _roll_x(out, px)
	return out


## Scorre l'immagine orizzontalmente di px pixel (con wrap).
static func _roll_x(img: Image, px: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create_empty(w, h, false, img.get_format())
	out.blit_rect(img, Rect2i(0, 0, w - px, h), Vector2i(px, 0))
	out.blit_rect(img, Rect2i(w - px, 0, px, h), Vector2i(0, 0))
	return out


## Salva in EXR con codec e metadati (chromaticities, commento, rig JSON se non vuoto). half = true scrive
## 16 bit; se il bake contiene valori oltre il massimo dell'half (una luce "sole") passa automaticamente
## a float32 e lo segnala. Con la GDExtension HsOpenEXR tutto avviene in una scrittura; senza, TinyEXR
## scrive PIZ (gli altri codec sono ignorati con un avviso) e i metadati vengono iniettati dopo.
static func save_exr(img: Image, path: String, half := true, codec := "PIZ", rig_json := "", acescg := false) -> Error:
	if half and _peak(img) > HALF_MAX:
		push_warning("Peak above the half maximum: %s written as float32" % path.get_file())
		half = false
	if ExrCodec.available():
		return ExrCodec.save(img, path, codec, half, metadata(rig_json, acescg))
	if codec != "PIZ":
		push_warning("HsOpenEXR not loaded: %s written as PIZ instead of %s" % [path.get_file(), codec])
	var out := img
	if half:
		out = img.duplicate() as Image
		out.convert(Image.FORMAT_RGBAH)
	# Scrittura atomica: file temporaneo accanto alla destinazione, poi rinomina. Così un plugin che
	# guarda il file non lo legge mai a metà.
	var dest := ProjectSettings.globalize_path(path)
	var tmp := dest + ".tmp.exr"
	var err := out.save_exr(tmp)
	if err != OK:
		return err
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	err = DirAccess.rename_absolute(tmp, dest)
	if err != OK:
		# fallback: scrittura diretta
		DirAccess.remove_absolute(tmp)
		err = out.save_exr(dest)
	if err == OK:
		var merr := inject_metadata(path, rig_json, acescg)
		if merr != OK:
			push_warning("EXR metadata not written in %s (%s)" % [path.get_file(), error_string(merr)])
	return err


## Attributi da scrivere nell'header: chromaticities, commento e (se c'è) il rig.
static func metadata(rig_json: String, acescg := false) -> Dictionary:
	var space := "ACEScg (AP1, D60)" if acescg else "Rec.709 (D65)"
	var attrs := {
		"chromaticities": PackedFloat32Array(ACESCG if acescg else REC709),
		"comments": "HDRI Studio — linear radiance, primaries " + space,
	}
	if rig_json != "":
		attrs[RIG_ATTR] = rig_json
	return attrs


## PNG di controllo: esposizione moltiplicativa, clamp, sRGB. Solo per guardare, mai per illuminare.
static func save_preview_png(img: Image, path: String, exposure := 1.0) -> Error:
	var prev := img.duplicate() as Image
	if exposure != 1.0:
		prev = _scaled(prev, exposure)
	prev.convert(Image.FORMAT_RGB8)
	prev.linear_to_srgb()
	return prev.save_png(ProjectSettings.globalize_path(path))


static func _peak(img: Image) -> float:
	# Lettura diretta del buffer float: molto più veloce di get_pixel su 8 M pixel.
	var f := img.get_data().to_float32_array()
	var m := 0.0
	var i := 0
	var n := f.size()
	while i < n:
		var v := f[i]
		if v > m:
			m = v
		i += 1
		if i % 4 == 3: # salta l'alpha
			i += 1
	return m


static func _scaled(img: Image, k: float) -> Image:
	var f := img.get_data().to_float32_array()
	for i in f.size():
		f[i] *= k
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBAF, f.to_byte_array())
