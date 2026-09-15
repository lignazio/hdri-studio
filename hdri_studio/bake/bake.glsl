#[compute]
#version 450

// HDRI Studio — bake delle luci parametriche su una tela equirettangolare.
// Ogni pixel contiene radianza lineare. Nessuna correzione ai poli: il renderer che campiona
// l'equirettangolare applica già il peso sin(theta).
//
// Convenzione interna (identica a PanoramaSkyMaterial di Godot, così il preview non ha offset):
//   centro immagine (u = 0.5) = +Z, alto (v = 0) = +Y, u = 0.25 = +X, u = 0.75 = -X.
//   Azimut positivo = verso destra sulla mappa, elevazione positiva = verso l'alto.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) restrict writeonly uniform image2D out_img;
layout(set = 0, binding = 1, std430) restrict readonly buffer Lights { vec4 data[]; } lights;
layout(set = 0, binding = 2) uniform sampler2D base_hdri;
layout(set = 0, binding = 3) uniform sampler2DArray light_textures;
layout(set = 0, binding = 4, std430) restrict readonly buffer Gradients { vec4 data[]; } grads;

layout(push_constant, std430) uniform Params {
	vec4 size;       // width, height, light_count, supersample
	vec4 bg_zenith;  // rgb, background mode (0 nero, 1 uniforme = horizon, 2 gradiente)
	vec4 bg_horizon; // rgb, calibration flag
	vec4 bg_nadir;   // rgb, mode: 1 = misura K della luce 0, 2 = proiezione planare della luce 0
	vec4 base;       // rotazione (rad), esposizione (mult), enabled, flip
} p;

const float PI = 3.14159265358979;

vec3 light_texture(int i, vec3 d);
vec3 gradient_rgb(int i, vec3 d);
const int STRIDE = 6; // vec4 per luce, deve coincidere con RigLight.STRIDE
const int GRAD_STOPS = 8; // tacche per gradiente (pos, r, g, b), come RigLight.GRAD_STOPS

// --- geometria della sfera ---------------------------------------------------------------

vec3 dir_from_uv(vec2 uv) {
	float phi = (uv.x - 0.5) * 2.0 * PI;
	float theta = (0.5 - uv.y) * PI;
	float c = cos(theta);
	return vec3(-c * sin(phi), sin(theta), c * cos(phi));
}

vec2 uv_from_dir(vec3 d) {
	float u = atan(-d.x, d.z) / (2.0 * PI) + 0.5;
	float v = 0.5 - asin(clamp(d.y, -1.0, 1.0)) / PI;
	return vec2(u, v);
}

// Frame ortonormale della luce: F guarda la luce dal centro, R va verso destra sulla mappa,
// U verso l'alto. Il roll ruota R e U attorno a F.
void light_frame(float az, float el, float roll, out vec3 F, out vec3 R, out vec3 U) {
	float c = cos(el);
	F = vec3(-c * sin(az), sin(el), c * cos(az));
	vec3 up = abs(F.y) > 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	R = normalize(cross(F, up));
	U = cross(R, F);
	float cr = cos(roll), sr = sin(roll);
	vec3 R2 = R * cr + U * sr;
	vec3 U2 = -R * sr + U * cr;
	R = R2;
	U = U2;
}

// --- profili -------------------------------------------------------------------------------

// Bordo sfumato verso l'interno: pieno a `softness` radianti dal bordo, zero sul bordo.
float soft_edge(float edge_dist, float softness) {
	if (softness <= 1e-6) return edge_dist >= 0.0 ? 1.0 : 0.0;
	return smoothstep(0.0, softness, edge_dist);
}

// Copertura di un rettangolo (hw × hh) con angoli arrotondati di raggio rr e bordo sfumato ss:
// distanza con segno dal rettangolo arrotondato, così la sfumatura gira attorno agli angoli invece
// di formare una punta. La parte piena resta un rettangolo netto.
float rect_cover(float ax, float ay, float hw, float hh, float rr, float ss) {
	rr = min(rr, min(hw, hh));
	vec2 q = abs(vec2(ax, ay)) - vec2(hw, hh) + vec2(rr);
	float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr;
	return soft_edge(-sd, ss);
}

float ellipse_cover(float ax, float ay, float hw, float hh, float ss) {
	float r = length(vec2(ax / hw, ay / hh));
	return soft_edge((1.0 - r) * min(hw, hh), ss);
}

// Colore del gradiente della luce i nella direzione d: coordinate (ax/hw, ay/hh) in -1..1,
// t = raggio (radiale) o proiezione lungo l'angolo (lineare), tacche interpolate.
vec3 gradient_rgb(int i, vec3 d) {
	vec4 a = lights.data[i * STRIDE + 0];
	vec4 b = lights.data[i * STRIDE + 1];
	vec4 g = lights.data[i * STRIDE + 5]; // tipo, forma, angolo, n tacche
	int n = int(g.w + 0.5);
	if (n <= 0) return vec3(1.0);
	vec3 F, R, U;
	light_frame(a.y, a.z, a.w, F, R, U);
	float df = dot(d, F);
	vec2 p = vec2(atan(dot(d, R), df) / (b.x * 0.5), atan(dot(d, U), df) / (b.y * 0.5));
	float t;
	if (g.x < 0.5) {
		t = length(p);
	} else {
		float ca = cos(g.z), sa = sin(g.z);
		t = (p.x * ca - p.y * sa + 1.0) * 0.5;
	}
	t = clamp(t, 0.0, 1.0);
	bool smooth_interp = b.w > 0.5;
	vec4 s0 = grads.data[i * GRAD_STOPS];
	if (t <= s0.x) return s0.yzw;
	for (int k = 1; k < n; k++) {
		vec4 s1 = grads.data[i * GRAD_STOPS + k];
		if (t <= s1.x) {
			float u = (t - s0.x) / max(s1.x - s0.x, 1e-6);
			if (smooth_interp) u = smoothstep(0.0, 1.0, u);
			return mix(s0.yzw, s1.yzw, u);
		}
		s0 = s1;
	}
	return s0.yzw;
}

// (copertura, profilo) della luce i nella direzione d. La copertura è la forma con il suo bordo
// sfumato: è il peso con cui la luce si fonde con ciò che c'è sotto. Il profilo modula l'intensità
// dentro la forma (hotspot dello scrim). Per il gradiente non c'è un "fondo": copertura = profilo.
// Per le luci Texture il colore dell'immagine viene campionato a parte in light_texture().
vec2 light_mp(int i, vec3 d) {
	vec4 a = lights.data[i * STRIDE + 0]; // shape, az, el, roll
	vec4 b = lights.data[i * STRIDE + 1]; // w, h, softness, falloff
	vec4 s = lights.data[i * STRIDE + 3]; // scrim: offset xy, depth, source size
	vec4 e = lights.data[i * STRIDE + 4]; // ring_inner, enabled

	vec3 F, R, U;
	light_frame(a.y, a.z, a.w, F, R, U);
	float df = dot(d, F);
	// Coordinate angolari nel frame della luce. Dietro la luce (df < 0) valgono ~±pi e cadono fuori.
	float ax = atan(dot(d, R), df);
	float ay = atan(dot(d, U), df);
	float hw = b.x * 0.5;
	float hh = b.y * 0.5;
	float rr = e.w; // raggio degli angoli
	int shape = int(a.x + 0.5);

	if (shape == 0) { // rect
		return vec2(rect_cover(ax, ay, hw, hh, rr, b.z), 1.0);
	}
	if (shape == 1) { // ellipse
		return vec2(ellipse_cover(ax, ay, hw, hh, b.z), 1.0);
	}
	if (shape == 2) { // ring: raggio esterno hw, interno hw * ring_inner
		float r = length(vec2(ax, ay));
		float inner = hw * e.x;
		return vec2(soft_edge(min(r - inner, hw - r), b.z), 1.0);
	}
	if (shape == 3) { // gradient: la maschera è circolare o rettangolare, il colore viene dalle tacche
		vec4 g = lights.data[i * STRIDE + 5];
		float cov = g.y < 0.5 ? ellipse_cover(ax, ay, hw, hh, b.z) : rect_cover(ax, ay, hw, hh, rr, b.z);
		return vec2(cov, 1.0);
	}
	if (shape == 5) { // texture: copertura rettangolare, il contenuto arriva dall'immagine
		return vec2(rect_cover(ax, ay, hw, hh, rr, b.z), 1.0);
	}
	// scrim: telo rettangolare illuminato da dietro da una sorgente a distanza `depth`,
	// spostata di `offset`. Irradianza sul telo: E = depth / (|q|^2 + depth^2)^(3/2)
	// (coseno + inverso del quadrato), normalizzata a picco 1. Una sorgente estesa è
	// approssimata allargando la distanza efficace: deff^2 = depth^2 + size^2.
	float mask = rect_cover(ax, ay, hw, hh, rr, b.z);
	if (mask <= 0.0) return vec2(0.0);
	vec2 q = vec2(ax / hw, ay / hh) - s.xy;
	float depth = max(s.z, 1e-3);
	float deff2 = depth * depth + s.w * s.w;
	float deff = sqrt(deff2);
	float prof = deff * deff2 / pow(dot(q, q) + deff2, 1.5);
	return vec2(mask, prof);
}

// Radianza rgb della luce i in d, copertura esclusa: colore × profilo × immagine o gradiente.
vec3 light_rgb(int i, vec3 d, float profile) {
	vec4 a = lights.data[i * STRIDE + 0];
	vec4 c = lights.data[i * STRIDE + 2];
	vec3 rgb = c.rgb * profile;
	int shape = int(a.x + 0.5);
	if (shape == 5) rgb *= light_texture(i, d);
	else if (shape == 3) rgb *= gradient_rgb(i, d);
	return rgb;
}

// Peso complessivo (copertura × profilo × luminanza di immagine/gradiente): radianza relativa della
// luce in quella direzione, usato dalla misura fotometrica.
float light_weight(int i, vec3 d) {
	vec2 mp = light_mp(i, d);
	if (mp.x <= 0.0) return 0.0;
	vec3 rgb = light_rgb(i, d, mp.y);
	vec4 c = lights.data[i * STRIDE + 2];
	// normalizza rispetto al colore della luce: il peso è la luminanza relativa
	float lum_c = max(dot(c.rgb, vec3(0.2126, 0.7152, 0.0722)), 1e-9);
	return mp.x * dot(rgb, vec3(0.2126, 0.7152, 0.0722)) / lum_c;
}

// Colore dell'immagine della luce Texture i nella direzione d (1 se la luce non ha immagine).
vec3 light_texture(int i, vec3 d) {
	vec4 a = lights.data[i * STRIDE + 0];
	vec4 b = lights.data[i * STRIDE + 1];
	vec4 e = lights.data[i * STRIDE + 4];
	if (e.z < 0.0) return vec3(1.0);
	vec3 F, R, U;
	light_frame(a.y, a.z, a.w, F, R, U);
	float df = dot(d, F);
	float ax = atan(dot(d, R), df);
	float ay = atan(dot(d, U), df);
	vec2 uv = vec2(0.5 + 0.5 * ax / (b.x * 0.5), 0.5 - 0.5 * ay / (b.y * 0.5));
	return texture(light_textures, vec3(clamp(uv, 0.0, 1.0), e.z)).rgb;
}

// --- layer di base ------------------------------------------------------------------------

vec3 background(vec3 d) {
	int mode = int(p.bg_zenith.w + 0.5);
	vec3 col = vec3(0.0);
	if (mode == 1) {
		col = p.bg_horizon.rgb;
	} else if (mode == 2) {
		float t = d.y;
		col = t >= 0.0 ? mix(p.bg_horizon.rgb, p.bg_zenith.rgb, t)
		               : mix(p.bg_horizon.rgb, p.bg_nadir.rgb, -t);
	}
	if (p.base.z > 0.5) {
		vec2 buv = uv_from_dir(d);
		buv.x = fract(buv.x + p.base.x / (2.0 * PI));
		if (p.base.w > 0.5) buv.x = 1.0 - buv.x;
		col += texture(base_hdri, buv).rgb * p.base.y;
	}
	return col;
}

// HDRI di taratura: dischi colorati sugli assi + un punto bianco "in alto a destra" del centro,
// per scoprire nel software 3D dove finisce ogni asse e se l'immagine viene specchiata.
vec3 calibration(vec3 d, vec3 col) {
	float c8 = cos(radians(8.0));
	if (dot(d, vec3(1.0, 0.0, 0.0)) > c8) return vec3(1.0, 0.0, 0.0);   // +X rosso
	if (dot(d, vec3(-1.0, 0.0, 0.0)) > c8) return vec3(0.25, 0.0, 0.0); // -X rosso scuro
	if (dot(d, vec3(0.0, 1.0, 0.0)) > c8) return vec3(0.0, 1.0, 0.0);   // +Y verde
	if (dot(d, vec3(0.0, -1.0, 0.0)) > c8) return vec3(0.0, 0.25, 0.0); // -Y verde scuro
	if (dot(d, vec3(0.0, 0.0, 1.0)) > c8) return vec3(0.0, 0.0, 1.0);   // +Z blu (centro immagine)
	if (dot(d, vec3(0.0, 0.0, -1.0)) > c8) return vec3(0.0, 0.0, 0.25); // -Z blu scuro (bordi)
	vec3 F, R, U;
	light_frame(radians(25.0), radians(12.0), 0.0, F, R, U);
	if (dot(d, F) > cos(radians(3.0))) return vec3(4.0);                  // punto bianco: az +25, el +12
	return col;
}

// --- main ---------------------------------------------------------------------------------

vec3 shade(vec3 d, int n) {
	vec3 col = background(d);
	if (p.bg_horizon.w > 0.5) return calibration(d, col);
	for (int i = 0; i < n; i++) {
		vec4 e = lights.data[i * STRIDE + 4];
		if (e.y < 0.5) continue;
		vec2 mp = light_mp(i, d);
		float cover = mp.x;
		if (cover <= 0.0) continue;
		vec4 c = lights.data[i * STRIDE + 2]; // radianza rgb, blend
		vec3 rgb = light_rgb(i, d, mp.y);
		int blend = int(c.w + 0.5);
		if (blend == 0) col += rgb * cover;
		else if (blend == 1) col = max(col, rgb * cover);
		else if (blend == 2) col *= mix(vec3(1.0), rgb, cover);
		else col = mix(col, rgb, cover); // normale: copre in ordine di elenco, con le sue parti scure
	}
	return col;
}

// Misura di K = ∫ w(d)·cosθ dω per la luce 0, integrando nel suo frame locale: il pixel copre
// (dax, day) in coordinate angolari, con d = normalize(tan ax·R + tan ay·U + F),
// dω = sec²ax·sec²ay / (1 + tan²ax + tan²ay)^(3/2) dax day e cosθ = 1 / sqrt(1 + tan²ax + tan²ay).
// Per le luci Texture pesa anche la luminanza dell'immagine. Scrive il contributo del pixel in .r.
void measure(ivec2 pix, ivec2 sz) {
	vec4 a = lights.data[0];
	vec4 b = lights.data[1];
	vec3 F, R, U;
	light_frame(a.y, a.z, a.w, F, R, U);
	float hw = b.x * 0.5, hh = b.y * 0.5;
	float dax = 2.0 * hw / float(sz.x);
	float day = 2.0 * hh / float(sz.y);
	float ax = -hw + (float(pix.x) + 0.5) * dax;
	float ay = -hh + (float(pix.y) + 0.5) * day;
	// oltre 89° la proiezione tangente diverge: clamp (le luci più larghe di 178° sono sfondi)
	ax = clamp(ax, -1.553, 1.553);
	ay = clamp(ay, -1.553, 1.553);
	float tx = tan(ax), ty = tan(ay);
	float q = 1.0 + tx * tx + ty * ty;
	vec3 d = normalize(tx * R + ty * U + F);
	float w = light_weight(0, d);
	float sec2 = (1.0 + tx * tx) * (1.0 + ty * ty);
	float domega = sec2 / (q * sqrt(q)) * dax * day;
	float cos_t = 1.0 / sqrt(q);
	imageStore(out_img, pix, vec4(w * cos_t * domega, 0.0, 0.0, 1.0));
}

// Proiezione planare della luce 0: la texture di un'area light rettangolare che, a distanza D,
// sottende (width × height). Il punto (x, y) del piano corrisponde a d = normalize((x/D)·R + (y/D)·U + F),
// quindi i pixel campionano uniformemente in tan-space. Scrive la radianza rgb (già con intensità).
void planar(ivec2 pix, ivec2 sz) {
	vec4 a = lights.data[0];
	vec4 b = lights.data[1];
	vec3 F, R, U;
	light_frame(a.y, a.z, a.w, F, R, U);
	float thw = tan(min(b.x * 0.5, 1.553));
	float thh = tan(min(b.y * 0.5, 1.553));
	int ss = max(int(p.size.w + 0.5), 1);
	vec3 acc = vec3(0.0);
	for (int sy = 0; sy < ss; sy++) {
		for (int sx = 0; sx < ss; sx++) {
			vec2 uv = (vec2(pix) + (vec2(sx, sy) + 0.5) / float(ss)) / vec2(sz);
			float tx = (uv.x * 2.0 - 1.0) * thw;
			float ty = (1.0 - uv.y * 2.0) * thh;
			vec3 d = normalize(tx * R + ty * U + F);
			vec2 mp = light_mp(0, d);
			if (mp.x <= 0.0) continue;
			acc += light_rgb(0, d, mp.y) * mp.x;
		}
	}
	imageStore(out_img, pix, vec4(acc / float(ss * ss), 1.0));
}

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	ivec2 sz = ivec2(p.size.xy);
	if (pix.x >= sz.x || pix.y >= sz.y) return;
	if (p.bg_nadir.w > 1.5) { planar(pix, sz); return; }
	if (p.bg_nadir.w > 0.5) { measure(pix, sz); return; }
	int n = int(p.size.z + 0.5);
	int ss = max(int(p.size.w + 0.5), 1);
	vec3 acc = vec3(0.0);
	for (int sy = 0; sy < ss; sy++) {
		for (int sx = 0; sx < ss; sx++) {
			vec2 uv = (vec2(pix) + (vec2(sx, sy) + 0.5) / float(ss)) / vec2(sz);
			acc += shade(dir_from_uv(uv), n);
		}
	}
	acc /= float(ss * ss);
	imageStore(out_img, pix, vec4(acc, 1.0));
}
