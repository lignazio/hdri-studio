class_name RigLight
extends Resource
## Una luce parametrica sulla sfera. Tutti gli angoli in gradi, la radianza in unità lineari.

enum Shape { RECT, ELLIPSE, RING, GRADIENT, SCRIM, TEXTURE }
## Interpolazione fra le tacche del gradiente (GAUSSIAN resta solo per i rig vecchi → SMOOTH).
enum Falloff { LINEAR, SMOOTH, GAUSSIAN }
enum GradientType { RADIAL, LINEAR }
enum GradientShape { CIRCULAR, RECTANGULAR }
## ADD somma (fisico), MAX massimo, MULTIPLY maschera, NORMAL copre lo sfondo dove sta (le luci dopo
## nell'elenco coprono quelle prima).
enum Blend { ADD, MAX, MULTIPLY, NORMAL }

## Numero di vec4 per luce nel buffer del compute shader. Deve coincidere con STRIDE in bake.glsl.
const STRIDE := 7
## Tacche massime per gradiente (vec4 = pos, r, g, b), come GRAD_STOPS in bake.glsl.
const GRAD_STOPS := 8

@export var name := "Light"
@export var enabled := true
## Con almeno una luce in solo, il bake include solo quelle.
@export var solo := false
## Bloccata: LightPaint, trascinamento sulla mappa e frecce non la spostano.
@export var locked := false
@export var shape := Shape.RECT
@export_range(-180.0, 180.0) var azimuth := 0.0
@export_range(-90.0, 90.0) var elevation := 0.0
@export_range(-180.0, 180.0) var roll := 0.0
@export_range(0.1, 360.0) var width := 30.0
@export_range(0.1, 180.0) var height := 20.0
@export_range(0.0, 90.0) var softness := 1.0
## Raggio degli angoli (gradi) per le forme rettangolari: la sfumatura gira attorno agli angoli.
@export_range(0.0, 90.0) var corner_radius := 0.0
@export var falloff := Falloff.SMOOTH
## Gradiente: radiale o lineare, maschera circolare o rettangolare, angolo del lineare (gradi),
## tacche [pos 0..1, r, g, b] in ordine di posizione.
@export var gradient_type := GradientType.RADIAL
@export var gradient_shape := GradientShape.CIRCULAR
@export_range(-180.0, 180.0) var gradient_angle := 0.0
## Tacche: [pos, r, g, b, valore]; il valore moltiplica il colore (anche oltre 1).
var gradient_stops: Array = [[0.0, 1.0, 1.0, 1.0, 1.0], [1.0, 0.0, 0.0, 0.0, 1.0]]
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
@export var texture_flip_h := false
@export var texture_flip_v := false
## Rotazione dell'immagine in quarti di giro (0..3).
@export_range(0, 3) var texture_rotate := 0
## Luce separata: esclusa dall'HDRI esportata, scritta come EXR singolo (proiezione planare) e
## ricreata nel software 3D come area light nella stessa direzione, a `distance` dal centro.
@export var separate := false
@export_range(1.0, 10000.0) var distance := 200.0
## Luce separata visibile alla camera nel software 3D (altrimenti solo riflessi e illuminazione).
@export var separate_visible := true


func duplicate_light() -> RigLight:
	return RigLight.from_dict(to_dict())


## Copia specchiata sinistra ↔ destra rispetto al meridiano az = 0 (key ↔ fill).
func mirrored() -> RigLight:
	var m := duplicate_light()
	m.name = name + " specchio"
	m.azimuth = -azimuth
	m.roll = -roll
	m.gradient_angle = -gradient_angle
	m.scrim_offset.x = -scrim_offset.x
	m.texture_flip_h = not texture_flip_h
	return m


func radiance() -> float:
	if photometric:
		return illuminance * pow(2.0, ev) / maxf(measured_k, 1e-9)
	return intensity * pow(2.0, ev)


## Frame ortonormale della luce (come nello shader): F guarda la luce dal centro, R verso destra sulla
## mappa, U verso l'alto, con il roll applicato.
func frame() -> Array[Vector3]:
	var az := deg_to_rad(azimuth)
	var el := deg_to_rad(elevation)
	var c := cos(el)
	var F := Vector3(-c * sin(az), sin(el), c * cos(az))
	var up := Vector3(0, 0, 1) if absf(F.y) > 0.999 else Vector3(0, 1, 0)
	var R := F.cross(up).normalized()
	var U := R.cross(F)
	var cr := cos(deg_to_rad(roll))
	var sr := sin(deg_to_rad(roll))
	var R2 := R * cr + U * sr
	var U2 := -R * sr + U * cr
	return [F, R2, U2]


## Direzione dal punto (ax, ay) in coordinate angolari nel frame della luce (come nello shader).
func dir_from_local(ax: float, ay: float) -> Vector3:
	var fr := frame()
	return (tan(ax) * fr[1] + tan(ay) * fr[2] + fr[0]).normalized()


## Coordinate angolari locali (ax, ay) di una direzione; z = d·F (negativo = dietro la luce).
func local_of(d: Vector3) -> Vector3:
	var fr := frame()
	var df := d.dot(fr[0])
	return Vector3(atan2(d.dot(fr[1]), df), atan2(d.dot(fr[2]), df), df)


## La direzione cade dentro la forma (copertura > 0, sfumatura esclusa)?
func contains(d: Vector3) -> bool:
	var l := local_of(d)
	if l.z <= 0.0:
		return false
	var hw := deg_to_rad(width) * 0.5
	var hh := deg_to_rad(height) * 0.5
	var ax := l.x
	var ay := l.y
	match shape:
		Shape.ELLIPSE:
			return (ax / hw) * (ax / hw) + (ay / hh) * (ay / hh) < 1.0
		Shape.RING:
			var r := sqrt(ax * ax + ay * ay)
			return r < hw and r > hw * ring_inner
		Shape.GRADIENT:
			if gradient_shape == GradientShape.CIRCULAR:
				return (ax / hw) * (ax / hw) + (ay / hh) * (ay / hh) < 1.0
			return absf(ax) < hw and absf(ay) < hh
		_:
			return absf(ax) < hw and absf(ay) < hh


## Contorno della forma come lista di direzioni (per disegnarla sulla mappa). Più liste per l'anello.
func outline() -> Array:
	var hw := deg_to_rad(minf(width, 178.0)) * 0.5
	var hh := deg_to_rad(minf(height, 178.0)) * 0.5
	var loops: Array = []
	var circular := shape == Shape.ELLIPSE or shape == Shape.RING \
		or (shape == Shape.GRADIENT and gradient_shape == GradientShape.CIRCULAR)
	if circular:
		var radii: Array = [Vector2(hw, hh)]
		if shape == Shape.RING:
			radii = [Vector2(hw, hw), Vector2(hw * ring_inner, hw * ring_inner)]
		for rr in radii:
			var pts: Array = []
			for i in 64:
				var t := TAU * i / 64.0
				pts.append(dir_from_local(rr.x * cos(t), rr.y * sin(t)))
			loops.append(pts)
	else:
		var pts: Array = []
		var corners := [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]
		for k in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			for i in 16:
				var p := a.lerp(b, i / 16.0)
				pts.append(dir_from_local(p.x, p.y))
		loops.append(pts)
	return loops


## Dimensione fisica del rettangolo che sottende (width × height) a distanza `distance`.
func physical_size() -> Vector2:
	return Vector2(2.0 * distance * tan(deg_to_rad(width) * 0.5), 2.0 * distance * tan(deg_to_rad(height) * 0.5))


## Chiave dei parametri da cui dipende K: se cambia, il baker rimisura.
func shape_key() -> String:
	return "%d|%.4f|%.4f|%.4f|%.4f|%d|%.4f|%.4f|%.4f|%.4f|%.4f|%s|%d|%d|%.4f|%s" % [
		shape, width, height, softness, corner_radius, falloff, ring_inner,
		scrim_offset.x, scrim_offset.y, scrim_depth, scrim_source_size,
		texture_path + str(texture_flip_h) + str(texture_flip_v) + str(texture_rotate),
		gradient_type, gradient_shape, gradient_angle, JSON.stringify(gradient_stops)]


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
		ring_inner, 1.0 if enabled else 0.0, float(tex_layer), deg_to_rad(corner_radius),
		float(gradient_type), float(gradient_shape), deg_to_rad(gradient_angle), float(mini(gradient_stops.size(), GRAD_STOPS)),
		float((1 if texture_flip_h else 0) + (2 if texture_flip_v else 0) + 4 * texture_rotate), 0.0, 0.0, 0.0,
	]))


static func stop_value(s: Array) -> float:
	return float(s[4]) if s.size() > 4 else 1.0


## Aggiunge GRAD_STOPS vec4 (pos, r, g, b) all'array del buffer dei gradienti.
func pack_gradient(out: PackedFloat32Array) -> void:
	var stops := gradient_stops.duplicate()
	stops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in GRAD_STOPS:
		if k < stops.size():
			var s: Array = stops[k]
			var v := stop_value(s)
			out.append_array(PackedFloat32Array([s[0], s[1] * v, s[2] * v, s[3] * v]))
		else:
			out.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))


## Colore del gradiente in t (0..1), come nello shader (per l'editor e le anteprime).
func gradient_color(t: float) -> Color:
	var stops := gradient_stops.duplicate()
	stops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if stops.is_empty():
		return Color.WHITE
	var s0: Array = stops[0]
	if t <= s0[0]:
		return Color(s0[1], s0[2], s0[3]) * stop_value(s0)
	for k in range(1, stops.size()):
		var s1: Array = stops[k]
		if t <= s1[0]:
			var u: float = (t - s0[0]) / maxf(s1[0] - s0[0], 1e-6)
			if falloff != Falloff.LINEAR:
				u = smoothstep(0.0, 1.0, u)
			return (Color(s0[1], s0[2], s0[3]) * stop_value(s0)).lerp(Color(s1[1], s1[2], s1[3]) * stop_value(s1), u)
		s0 = s1
	return Color(s0[1], s0[2], s0[3]) * stop_value(s0)


func to_dict() -> Dictionary:
	return {
		"name": name, "enabled": enabled, "solo": solo, "locked": locked, "shape": Shape.keys()[shape],
		"azimuth": azimuth, "elevation": elevation, "roll": roll,
		"width": width, "height": height, "softness": softness, "corner_radius": corner_radius,
		"falloff": Falloff.keys()[falloff],
		"gradient_type": GradientType.keys()[gradient_type], "gradient_shape": GradientShape.keys()[gradient_shape],
		"gradient_angle": gradient_angle, "gradient_stops": gradient_stops.duplicate(true),
		"intensity": intensity, "ev": ev, "kelvin": kelvin,
		"photometric": photometric, "illuminance": illuminance,
		"tint": [tint.r, tint.g, tint.b], "blend": Blend.keys()[blend],
		"ring_inner": ring_inner,
		"scrim_offset": [scrim_offset.x, scrim_offset.y],
		"scrim_depth": scrim_depth, "scrim_source_size": scrim_source_size,
		"texture_path": texture_path, "texture_flip_h": texture_flip_h, "texture_flip_v": texture_flip_v,
		"texture_rotate": texture_rotate,
		"separate": separate, "distance": distance, "separate_visible": separate_visible,
	}


static func from_dict(d: Dictionary) -> RigLight:
	var l := RigLight.new()
	l.name = d.get("name", l.name)
	l.enabled = d.get("enabled", l.enabled)
	l.solo = d.get("solo", l.solo)
	l.locked = d.get("locked", false)
	l.shape = Shape.get(d.get("shape", "RECT"), Shape.RECT)
	l.azimuth = d.get("azimuth", l.azimuth)
	l.elevation = d.get("elevation", l.elevation)
	l.roll = d.get("roll", l.roll)
	l.width = d.get("width", l.width)
	l.height = d.get("height", l.height)
	l.softness = d.get("softness", l.softness)
	l.corner_radius = d.get("corner_radius", 0.0)
	l.falloff = Falloff.get(d.get("falloff", "SMOOTH"), Falloff.SMOOTH)
	if l.falloff == Falloff.GAUSSIAN:
		l.falloff = Falloff.SMOOTH
	l.gradient_type = GradientType.get(d.get("gradient_type", "RADIAL"), GradientType.RADIAL)
	l.gradient_shape = GradientShape.get(d.get("gradient_shape", "CIRCULAR"), GradientShape.CIRCULAR)
	l.gradient_angle = d.get("gradient_angle", 0.0)
	var st: Array = d.get("gradient_stops", [])
	if st.size() >= 1:
		l.gradient_stops = []
		for s in st:
			l.gradient_stops.append([float(s[0]), float(s[1]), float(s[2]), float(s[3]), float(s[4]) if s.size() > 4 else 1.0])
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
	l.texture_flip_h = d.get("texture_flip_h", false)
	l.texture_flip_v = d.get("texture_flip_v", false)
	l.texture_rotate = int(d.get("texture_rotate", 0))
	l.separate = d.get("separate", false)
	l.distance = d.get("distance", l.distance)
	l.separate_visible = d.get("separate_visible", true)
	return l
