class_name LightMeter
extends RefCounted
## Esposimetro: illuminamento E = ∫ L(d) · max(d·n, 0) dω su tutta la mappa (luci e sfondo),
## per una superficie al centro con normale n. Lavora su una copia CPU ridotta del bake.
## EV100 = log2(E / 2.5) (taratura degli esposimetri a luce incidente, C = 250 lux, ISO 100).

const RES := Vector2i(256, 128)

var _lum := PackedFloat32Array()
var _dirs := PackedVector3Array()
var _domega := PackedFloat32Array()


func _init() -> void:
	# direzioni e angoli solidi dei pixel della griglia ridotta (convenzione interna)
	for y in RES.y:
		var v := (y + 0.5) / RES.y
		var theta := (0.5 - v) * PI
		var c := cos(theta)
		var dw := (TAU / RES.x) * (PI / RES.y) * c
		for x in RES.x:
			var phi := ((x + 0.5) / RES.x - 0.5) * TAU
			_dirs.append(Vector3(-c * sin(phi), sin(theta), c * cos(phi)))
			_domega.append(dw)


## Aggiorna la copia ridotta dal bake (Image RGBAF di qualsiasi dimensione).
func update(img: Image) -> void:
	var small := img.duplicate() as Image
	small.resize(RES.x, RES.y, Image.INTERPOLATE_BILINEAR)
	var f := small.get_data().to_float32_array()
	_lum.resize(RES.x * RES.y)
	var i := 0
	var k := 0
	while i < f.size():
		_lum[k] = 0.2126 * f[i] + 0.7152 * f[i + 1] + 0.0722 * f[i + 2]
		i += 4
		k += 1


## Illuminamento per una superficie con normale n (unità della radianza dell'HDRI × sr).
func illuminance(n: Vector3) -> float:
	if _lum.is_empty():
		return 0.0
	n = n.normalized()
	var e := 0.0
	for k in _lum.size():
		var c := _dirs[k].dot(n)
		if c > 0.0:
			e += _lum[k] * c * _domega[k]
	return e


static func ev100(e: float) -> float:
	return log(maxf(e, 1e-9) / 2.5) / log(2.0)


## Direzione interna da azimut/elevazione in gradi.
static func dir(az_deg: float, el_deg: float) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(-cos(el) * sin(az), sin(el), cos(el) * cos(az))
