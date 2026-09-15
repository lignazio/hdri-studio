class_name ColorTemp
extends RefCounted
## Temperatura di colore → RGB lineare Rec.709.
## Locus planckiano approssimato (Kim et al. 2002), CIE xy → XYZ (Y=1) → Rec.709 lineare.
## Il risultato è bilanciato in modo che 6500 K sia esattamente bianco (1,1,1):
## i cursori "kelvin" devono dare un bianco neutro al default, non il planckiano puro.

const WHITE_K := 6500.0

## Gelatine di correzione (CTO/CTB come spostamento in mired applicato a 6500 K) e di colore.
## Valori approssimati: servono come punto di partenza, non come dati di catalogo.
const GELS := {
	"Nessuna (bianco)": Color.WHITE,
	"CTO ⅛ (+20 mired)": null, "CTO ¼ (+42)": null, "CTO ½ (+81)": null, "CTO Full (+159)": null,
	"CTB ¼ (−30)": null, "CTB ½ (−68)": null, "CTB Full (−131)": null,
	"Plus Green": Color(0.86, 1.0, 0.78),
	"Minus Green": Color(1.0, 0.86, 1.0),
	"Straw": Color(1.0, 0.92, 0.72),
	"Ambra": Color(1.0, 0.7, 0.35),
	"Rosso": Color(1.0, 0.25, 0.15),
	"Blu profondo": Color(0.25, 0.4, 1.0),
	"Magenta": Color(1.0, 0.45, 0.85),
}
const GEL_MIRED := {"CTO ⅛ (+20 mired)": 20.0, "CTO ¼ (+42)": 42.0, "CTO ½ (+81)": 81.0, "CTO Full (+159)": 159.0,
	"CTB ¼ (−30)": -30.0, "CTB ½ (−68)": -68.0, "CTB Full (−131)": -131.0}


static func gel_color(name: String) -> Color:
	if GEL_MIRED.has(name):
		var mired: float = 1.0e6 / WHITE_K + GEL_MIRED[name]
		return kelvin_to_rgb(1.0e6 / maxf(mired, 40.0))
	var c = GELS.get(name, Color.WHITE)
	return c if c != null else Color.WHITE


static func kelvin_to_rgb(kelvin: float) -> Color:
	var raw := _planck_rgb(kelvin)
	var ref := _planck_rgb(WHITE_K)
	return Color(raw.r / ref.r, raw.g / ref.g, raw.b / ref.b, 1.0)

static func _planck_rgb(kelvin: float) -> Color:
	var t: float = clamp(kelvin, 1667.0, 25000.0)
	var x: float
	if t <= 4000.0:
		x = -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
	else:
		x = -3.0258469e9 / (t * t * t) + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390
	var y: float
	if t <= 2222.0:
		y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
	elif t <= 4000.0:
		y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
	else:
		y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
	# xyY con Y = 1
	var X := x / y
	var Y := 1.0
	var Z := (1.0 - x - y) / y
	# XYZ (D65) → Rec.709 lineare
	var r := 3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z
	var g := -0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z
	var b := 0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z
	return Color(max(r, 0.0), max(g, 0.0), max(b, 0.0), 1.0)
