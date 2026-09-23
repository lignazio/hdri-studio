class_name LightIcons
extends RefCounted
## Icone 16×16 disegnate al volo (bianche; il colore lo dà il Tree): occhio, pallino, lucchetto, e le
## caselle di spunta del tema (UiStyle).
##
## Sono rese a OVERSAMPLE volte la risoluzione e dichiarate 16×16 (size override): con la scala dello
## schermo applicata da main (Retina = 2) restano nitide invece di essere ingrandite.

const SIZE := 16
const OVERSAMPLE := 2
static var _cache := {}


static func eye() -> Texture2D:
	return _icon("eye", func(x: float, y: float) -> float:
		return _eye(x, y))


## Occhio barrato: lo stato "spento" non si affida solo all'opacità.
static func eye_off() -> Texture2D:
	return _icon("eye_off", func(x: float, y: float) -> float:
		# barra diagonale da (3, 13) a (13, 3), con un filo di vuoto attorno per staccarla dall'occhio
		var d := absf((x - 8.0) + (y - 8.0)) / sqrt(2.0)
		var inside := absf((x - 8.0) - (y - 8.0)) / sqrt(2.0) < 7.0
		var bar := (1.0 - smoothstep(0.7, 1.2, d)) if inside else 0.0
		var gap := (1.0 - smoothstep(1.4, 2.0, d)) if inside else 0.0
		return maxf(_eye(x, y) * (1.0 - gap), bar))


static func dot() -> Texture2D:
	return _icon("dot", func(x: float, y: float) -> float:
		return 1.0 - smoothstep(3.6, 4.6, Vector2(x - 8.0, y - 8.0).length()))


static func lock() -> Texture2D:
	return _icon("lock", func(x: float, y: float) -> float:
		# corpo: rettangolo 10×7 in basso; archetto: mezzo anello sopra
		var body := 1.0 if (x >= 3.0 and x <= 13.0 and y >= 7.5 and y <= 14.5) else 0.0
		var d := Vector2(x - 8.0, y - 7.5).length()
		var arc := 1.0 - smoothstep(0.7, 1.4, absf(d - 3.4))
		if y > 7.5:
			arc = 0.0
		return maxf(body, arc))


## Casella vuota: bordo di 1,5 px a 0,6, contrasto > 3:1 sul fondo del pannello.
static func check_off() -> Texture2D:
	return _icon("check_off", func(x: float, y: float) -> float:
		return _box_outline(x, y) * 0.6)


## Casella piena (grigio chiaro, non l'accento: quello è della selezione) con la spunta in negativo.
static func check_on() -> Texture2D:
	var f := func(x: float, y: float) -> float:
		var box := _box_fill(x, y)
		# segno: due segmenti (4.5, 8.2) → (7, 10.8) → (11.6, 5.4)
		var p := Vector2(x, y)
		var tick := minf(_seg_dist(p, Vector2(4.5, 8.2), Vector2(7.0, 10.8)), _seg_dist(p, Vector2(7.0, 10.8), Vector2(11.6, 5.4)))
		var mark := 1.0 - smoothstep(0.8, 1.3, tick)
		return box * (1.0 - mark)
	return _icon("check_on", f, Color(0.88, 0.88, 0.9))


static func _eye(x: float, y: float) -> float:
	# ellisse 12×7 come contorno + pupilla
	var ex := (x - 8.0) / 6.0
	var ey := (y - 8.0) / 3.6
	var r := sqrt(ex * ex + ey * ey)
	var outline := 1.0 - smoothstep(0.12, 0.3, absf(r - 1.0))
	var pupil := 1.0 - smoothstep(1.6, 2.4, Vector2(x - 8.0, y - 8.0).length())
	return maxf(outline, pupil)


## Quadrato 12×12 centrato con angoli arrotondati: distanza con segno dal bordo.
static func _box_sdf(x: float, y: float) -> float:
	var q := Vector2(absf(x - 8.0), absf(y - 8.0)) - Vector2(4.0, 4.0)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 2.0


static func _box_outline(x: float, y: float) -> float:
	return 1.0 - smoothstep(0.5, 1.0, absf(_box_sdf(x, y) + 0.75))


static func _box_fill(x: float, y: float) -> float:
	return 1.0 - smoothstep(-0.5, 0.0, _box_sdf(x, y))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _icon(key: String, f: Callable, tint := Color(1, 1, 1)) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var n := SIZE * OVERSAMPLE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var step := 1.0 / OVERSAMPLE
	for y in n:
		for x in n:
			# 4 campioni per pixel per bordi puliti (coordinate della griglia 16×16)
			var a := 0.0
			for sy in 2:
				for sx in 2:
					a += f.call((x + 0.25 + 0.5 * sx) * step, (y + 0.25 + 0.5 * sy) * step)
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, clampf(a / 4.0, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(SIZE, SIZE))
	_cache[key] = tex
	return tex
