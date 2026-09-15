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
##  - Houdini: da misurare, per ora come Blender.
const TARGETS := {
	"Cinema 4D + Octane": {"flip": false, "shift": 0.0},
	"Cinema 4D nativo": {"flip": true, "shift": 0.0},
	"Godot / Blender": {"flip": false, "shift": 0.0},
	"Houdini": {"flip": false, "shift": 0.0},
}
const DEFAULT_TARGET := "Cinema 4D + Octane"


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


## Salva in EXR. half = true scrive 16 bit; se il bake contiene valori oltre il massimo
## dell'half (una luce "sole") passa automaticamente a float32 e lo segnala.
static func save_exr(img: Image, path: String, half := true) -> Error:
	var out := img
	if half:
		var peak := _peak(img)
		if peak > HALF_MAX:
			push_warning("Picco %.0f oltre il massimo dell'half: %s scritto in float32" % [peak, path.get_file()])
		else:
			out = img.duplicate() as Image
			out.convert(Image.FORMAT_RGBAH)
	return out.save_exr(ProjectSettings.globalize_path(path))


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
