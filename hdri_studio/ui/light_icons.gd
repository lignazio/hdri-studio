class_name LightIcons
extends RefCounted
## Icone 16×16 disegnate al volo (bianche; il colore lo dà il Tree): occhio, pallino, lucchetto.

const SIZE := 16
static var _cache := {}


static func eye() -> Texture2D:
	return _icon("eye", func(x: float, y: float) -> float:
		# ellisse 12×7 come contorno + pupilla
		var ex := (x - 8.0) / 6.0
		var ey := (y - 8.0) / 3.6
		var r := sqrt(ex * ex + ey * ey)
		var outline := 1.0 - smoothstep(0.12, 0.3, absf(r - 1.0))
		var pupil := 1.0 - smoothstep(1.6, 2.4, Vector2(x - 8.0, y - 8.0).length())
		return maxf(outline, pupil))


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


static func _icon(key: String, f: Callable) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			# 4 campioni per pixel per bordi puliti
			var a := 0.0
			for sy in 2:
				for sx in 2:
					a += f.call(x + 0.25 + 0.5 * sx, y + 0.25 + 0.5 * sy)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a / 4.0, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
