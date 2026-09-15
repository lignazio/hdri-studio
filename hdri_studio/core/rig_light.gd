class_name RigLight
extends Resource
## Una luce parametrica sulla sfera. Tutti gli angoli in gradi, la radianza in unità lineari.

enum Shape { RECT, ELLIPSE, RING, GRADIENT, SCRIM, TEXTURE }
enum Falloff { LINEAR, SMOOTH, GAUSSIAN }
## ADD somma (fisico), MAX massimo, MULTIPLY maschera, NORMAL copre lo sfondo dove sta (le luci dopo
## nell'elenco coprono quelle prima).
enum Blend { ADD, MAX, MULTIPLY, NORMAL }

## Numero di vec4 per luce nel buffer del compute shader. Deve coincidere con STRIDE in bake.glsl.
const STRIDE := 5

@export var name := "Light"
@export var enabled := true
## Con almeno una luce in solo, il bake include solo quelle.
@export var solo := false
@export var shape := Shape.RECT
@export_range(-180.0, 180.0) var azimuth := 0.0
@export_range(-90.0, 90.0) var elevation := 0.0
@export_range(-180.0, 180.0) var roll := 0.0
@export_range(0.1, 360.0) var width := 30.0
@export_range(0.1, 180.0) var height := 20.0
@export_range(0.0, 90.0) var softness := 1.0
@export var falloff := Falloff.SMOOTH
@export var intensity := 1.0
@export_range(-10.0, 20.0) var ev := 0.0
## Fotometrico: invece della radianza si specifica l'illuminamento E prodotto al centro della sfera
## su una superficie rivolta verso la luce (unità arbitrarie ma coerenti fra luci: "lux"). La radianza
## è E / K, con K = ∫ w(d)·cosθ dω misurato dal baker sulla forma reale (immagine compresa).
@export var photometric := false
@export var illuminance := 100.0
## Ultimo K misurato dal baker (non serializzato).
var measured_k := 1.0
@export_range(1667.0, 25000.0) var kelvin := 6500.0
@export var tint := Color.WHITE
@export var blend := Blend.ADD
## Anello: raggio interno come frazione del raggio esterno (width / 2).
@export_range(0.0, 0.99) var ring_inner := 0.6
## Scrim: posizione della sorgente dietro il telo, in -1..1 rispetto a metà larghezza/altezza.
@export var scrim_offset := Vector2.ZERO
## Scrim: distanza della sorgente dal telo, in unità di metà larghezza del telo.
@export_range(0.05, 10.0) var scrim_depth := 0.6
## Scrim: raggio della sorgente nelle stesse unità (0 = puntiforme).
@export_range(0.0, 5.0) var scrim_source_size := 0.0
## Texture: immagine EXR/HDR lineare mappata sul rettangolo della luce (solo il percorso: il rig
## non contiene mai i pixel).
@export var texture_path := ""


func duplicate_light() -> RigLight:
	return RigLight.from_dict(to_dict())


func radiance() -> float:
	if photometric:
		return illuminance * pow(2.0, ev) / maxf(measured_k, 1e-9)
	return intensity * pow(2.0, ev)


## Chiave dei parametri da cui dipende K: se cambia, il baker rimisura.
func shape_key() -> String:
	return "%d|%.4f|%.4f|%.4f|%d|%.4f|%.4f|%.4f|%.4f|%.4f|%s" % [
		shape, width, height, softness, falloff, ring_inner,
		scrim_offset.x, scrim_offset.y, scrim_depth, scrim_source_size, texture_path]


## Colore lineare già moltiplicato per la radianza: è quello che entra nel bake.
func radiance_rgb() -> Color:
	var c := ColorTemp.kelvin_to_rgb(kelvin) * tint
	return c * radiance()


## Aggiunge STRIDE vec4 all'array che diventa il buffer del compute shader.
## tex_layer: strato del texture array per le luci Texture (-1 = nessuna immagine caricata).
func pack(out: PackedFloat32Array, tex_layer := -1) -> void:
	var rgb := radiance_rgb()
	out.append_array(PackedFloat32Array([
		float(shape), deg_to_rad(azimuth), deg_to_rad(elevation), deg_to_rad(roll),
		deg_to_rad(width), deg_to_rad(height), deg_to_rad(softness), float(falloff),
		rgb.r, rgb.g, rgb.b, float(blend),
		scrim_offset.x, scrim_offset.y, scrim_depth, scrim_source_size,
		ring_inner, 1.0 if enabled else 0.0, float(tex_layer), 0.0,
	]))


func to_dict() -> Dictionary:
	return {
		"name": name, "enabled": enabled, "solo": solo, "shape": Shape.keys()[shape],
		"azimuth": azimuth, "elevation": elevation, "roll": roll,
		"width": width, "height": height, "softness": softness,
		"falloff": Falloff.keys()[falloff],
		"intensity": intensity, "ev": ev, "kelvin": kelvin,
		"photometric": photometric, "illuminance": illuminance,
		"tint": [tint.r, tint.g, tint.b], "blend": Blend.keys()[blend],
		"ring_inner": ring_inner,
		"scrim_offset": [scrim_offset.x, scrim_offset.y],
		"scrim_depth": scrim_depth, "scrim_source_size": scrim_source_size,
		"texture_path": texture_path,
	}


static func from_dict(d: Dictionary) -> RigLight:
	var l := RigLight.new()
	l.name = d.get("name", l.name)
	l.enabled = d.get("enabled", l.enabled)
	l.solo = d.get("solo", l.solo)
	l.shape = Shape.get(d.get("shape", "RECT"), Shape.RECT)
	l.azimuth = d.get("azimuth", l.azimuth)
	l.elevation = d.get("elevation", l.elevation)
	l.roll = d.get("roll", l.roll)
	l.width = d.get("width", l.width)
	l.height = d.get("height", l.height)
	l.softness = d.get("softness", l.softness)
	l.falloff = Falloff.get(d.get("falloff", "SMOOTH"), Falloff.SMOOTH)
	l.intensity = d.get("intensity", l.intensity)
	l.photometric = d.get("photometric", false)
	l.illuminance = d.get("illuminance", l.illuminance)
	l.ev = d.get("ev", l.ev)
	l.kelvin = d.get("kelvin", l.kelvin)
	var t: Array = d.get("tint", [1, 1, 1])
	l.tint = Color(t[0], t[1], t[2])
	l.blend = Blend.get(d.get("blend", "ADD"), Blend.ADD)
	l.ring_inner = d.get("ring_inner", l.ring_inner)
	var so: Array = d.get("scrim_offset", [0, 0])
	l.scrim_offset = Vector2(so[0], so[1])
	l.scrim_depth = d.get("scrim_depth", l.scrim_depth)
	l.scrim_source_size = d.get("scrim_source_size", l.scrim_source_size)
	l.texture_path = d.get("texture_path", "")
	return l
