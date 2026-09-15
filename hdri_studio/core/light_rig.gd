class_name LightRig
extends Resource
## Il rig completo: luci + layer di base. È ciò che viene salvato nel file di progetto (JSON).

enum Background { BLACK, UNIFORM, GRADIENT }

@export var lights: Array[RigLight] = []
@export var background := Background.GRADIENT
@export var bg_zenith := Color(0.05, 0.05, 0.06)
@export var bg_horizon := Color(0.02, 0.02, 0.02)
@export var bg_nadir := Color(0.0, 0.0, 0.0)
## HDRI esistente usata come base sotto le luci (EXR o Radiance .hdr). Vuoto = nessuna.
@export_file("*.exr", "*.hdr") var base_hdri_path := ""
@export var base_enabled := false
@export_range(-180.0, 180.0) var base_rotation := 0.0
@export_range(-10.0, 10.0) var base_ev := 0.0
@export var base_flip := false
@export var resolution := Vector2i(4096, 2048)
## File scritto automaticamente dal live link a ogni modifica (vuoto = non impostato).
@export var live_export_path := ""


func add_light(light: RigLight) -> RigLight:
	lights.append(light)
	return light


## Luci che entrano nel bake: abilitate, e se c'è un solo attivo solo quelle. Le luci separate
## entrano solo nel preview (include_separate), mai nell'HDRI esportata.
func active_lights(include_separate := true) -> Array:
	var any_solo := false
	for l in lights:
		if l.solo and l.enabled:
			any_solo = true
			break
	return lights.filter(func(l: RigLight) -> bool:
		return l.enabled and (l.solo or not any_solo) and (include_separate or not l.separate))


## Luci separate attive (per l'export singolo e il live link).
func separate_lights() -> Array:
	return active_lights(true).filter(func(l: RigLight) -> bool: return l.separate)


func base_exposure() -> float:
	return pow(2.0, base_ev)


func to_dict() -> Dictionary:
	var ls: Array = []
	for l in lights:
		ls.append(l.to_dict())
	return {
		"version": 1,
		"lights": ls,
		"background": Background.keys()[background],
		"bg_zenith": [bg_zenith.r, bg_zenith.g, bg_zenith.b],
		"bg_horizon": [bg_horizon.r, bg_horizon.g, bg_horizon.b],
		"bg_nadir": [bg_nadir.r, bg_nadir.g, bg_nadir.b],
		"base_hdri_path": base_hdri_path, "base_enabled": base_enabled,
		"base_rotation": base_rotation, "base_ev": base_ev, "base_flip": base_flip,
		"resolution": [resolution.x, resolution.y],
		"live_export_path": live_export_path,
	}


static func from_dict(d: Dictionary) -> LightRig:
	var r := LightRig.new()
	for ld in d.get("lights", []):
		r.lights.append(RigLight.from_dict(ld))
	r.background = Background.get(d.get("background", "GRADIENT"), Background.GRADIENT)
	var z: Array = d.get("bg_zenith", [0.05, 0.05, 0.06])
	var h: Array = d.get("bg_horizon", [0.02, 0.02, 0.02])
	var n: Array = d.get("bg_nadir", [0, 0, 0])
	r.bg_zenith = Color(z[0], z[1], z[2])
	r.bg_horizon = Color(h[0], h[1], h[2])
	r.bg_nadir = Color(n[0], n[1], n[2])
	r.base_hdri_path = d.get("base_hdri_path", "")
	r.base_enabled = d.get("base_enabled", false)
	r.base_rotation = d.get("base_rotation", 0.0)
	r.base_ev = d.get("base_ev", 0.0)
	r.base_flip = d.get("base_flip", false)
	var res: Array = d.get("resolution", [4096, 2048])
	r.resolution = Vector2i(res[0], res[1])
	r.live_export_path = d.get("live_export_path", "")
	return r


func save_json(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


static func load_json(path: String) -> LightRig:
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty():
		return null
	var d = JSON.parse_string(txt)
	if d is Dictionary:
		return LightRig.from_dict(d)
	return null
