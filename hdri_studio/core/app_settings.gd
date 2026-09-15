class_name AppSettings
extends RefCounted
## Preferenze dell'app (non del rig): cartella del catalogo, ecc. In user://settings.json.

const PATH := "user://settings.json"


static func load_all() -> Dictionary:
	var txt := FileAccess.get_file_as_string(PATH)
	if txt.is_empty():
		return {}
	var d = JSON.parse_string(txt)
	return d if d is Dictionary else {}


static func get_value(key: String, default: Variant = null) -> Variant:
	return load_all().get(key, default)


static func set_value(key: String, value: Variant) -> void:
	var d := load_all()
	d[key] = value
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "\t"))
