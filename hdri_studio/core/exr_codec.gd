class_name ExrCodec
extends RefCounted
## OpenEXR dentro l'app: la GDExtension HsOpenEXR (addons/hs_openexr, sorgenti in gdextension/) scrive e
## legge tutti i codec. Senza l'estensione (piattaforma senza binario) resta TinyEXR di Godot, che
## scrive solo PIZ e non legge DWAA/DWAB, B44/B44A, PXR24.
## Lossless: PIZ, ZIP, ZIPS, RLE, NONE. Lossy: PXR24 (float → 24 bit), B44/B44A, DWAA/DWAB.

const CODECS := ["PIZ", "ZIP", "ZIPS", "RLE", "PXR24", "B44", "B44A", "DWAA", "DWAB", "NONE"]
const LOSSY := ["PXR24", "B44", "B44A", "DWAA", "DWAB"]
## Codec (valore dell'attributo "compression") che TinyEXR sa decodificare: NONE, RLE, ZIPS, ZIP, PIZ.
const TINYEXR_READABLE := [0, 1, 2, 3, 4]


static func available() -> bool:
	return ClassDB.class_exists("HsOpenEXR")


static func version() -> String:
	return ClassDB.class_call_static("HsOpenEXR", "version") if available() else ""


## Scrive img (RGB, half o float) con il codec scelto e gli attributi (String → string, PackedFloat32Array
## di 8 → chromaticities). Atomica: temporaneo + rinomina.
static func save(img: Image, path: String, codec: String, half: bool, attributes: Dictionary) -> Error:
	return ClassDB.class_call_static("HsOpenEXR", "save", img, path, codec, half, attributes, 45.0)


## Legge un EXR con qualunque codec in RGBAF; null se non leggibile.
static func load(path: String) -> Image:
	return ClassDB.class_call_static("HsOpenEXR", "load", path)


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
