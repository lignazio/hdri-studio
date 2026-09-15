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

layout(push_constant, std430) uniform Params {
	vec4 size;       // width, height, light_count, supersample
	vec4 bg_zenith;  // rgb, background mode (0 nero, 1 uniforme = horizon, 2 gradiente)
	vec4 bg_horizon; // rgb, calibration flag
	vec4 bg_nadir;   // rgb, -
	vec4 base;       // rotazione (rad), esposizione (mult), enabled, flip
} p;

const float PI = 3.14159265358979;
const int STRIDE = 5; // vec4 per luce, deve coincidere con RigLight.STRIDE

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

// t = 1 al centro, 0 al bordo.
float falloff_curve(float t, float type) {
	t = clamp(t, 0.0, 1.0);
	if (type < 0.5) return t;
	if (type < 1.5) return smoothstep(0.0, 1.0, t);
	float r = 1.0 - t;
	const float k = exp(-4.0);
	return (exp(-4.0 * r * r) - k) / (1.0 - k);
}

// Peso in [0, 1] della luce i nella direzione d. Per le luci Texture il peso è la maschera del
// rettangolo; il colore dell'immagine viene campionato a parte in light_texture().
float light_weight(int i, vec3 d) {
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
	int shape = int(a.x + 0.5);

	if (shape == 0) { // rect
		float ed = min(hw - abs(ax), hh - abs(ay));
		return soft_edge(ed, b.z);
	}
	if (shape == 1) { // ellipse
		float r = length(vec2(ax / hw, ay / hh));
		return soft_edge((1.0 - r) * min(hw, hh), b.z);
	}
	if (shape == 2) { // ring: raggio esterno hw, interno hw * ring_inner
		float r = length(vec2(ax, ay));
		float inner = hw * e.x;
		return soft_edge(min(r - inner, hw - r), b.z);
	}
	if (shape == 3) { // gradient
		float r = length(vec2(ax / hw, ay / hh));
		return falloff_curve(1.0 - r, b.w);
	}
	if (shape == 5) { // texture: maschera rettangolare, il contenuto arriva dall'immagine
		float ed = min(hw - abs(ax), hh - abs(ay));
		return soft_edge(ed, b.z);
	}
	// scrim: telo rettangolare illuminato da dietro da una sorgente a distanza `depth`,
	// spostata di `offset`. Irradianza sul telo: E = depth / (|q|^2 + depth^2)^(3/2)
	// (coseno + inverso del quadrato), normalizzata a picco 1. Una sorgente estesa è
	// approssimata allargando la distanza efficace: deff^2 = depth^2 + size^2.
	float ed = min(hw - abs(ax), hh - abs(ay));
	float mask = soft_edge(ed, b.z);
	if (mask <= 0.0) return 0.0;
	vec2 q = vec2(ax / hw, ay / hh) - s.xy;
	float depth = max(s.z, 1e-3);
	float deff2 = depth * depth + s.w * s.w;
	float deff = sqrt(deff2);
	float prof = deff * deff2 / pow(dot(q, q) + deff2, 1.5);
	return mask * prof;
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
		float w = light_weight(i, d);
		if (w <= 0.0) continue;
		vec4 c = lights.data[i * STRIDE + 2]; // radianza rgb, blend
		vec3 rgb = c.rgb;
		if (int(lights.data[i * STRIDE + 0].x + 0.5) == 5) rgb *= light_texture(i, d);
		int blend = int(c.w + 0.5);
		if (blend == 0) col += rgb * w;
		else if (blend == 1) col = max(col, rgb * w);
		else col *= mix(vec3(1.0), rgb, w);
	}
	return col;
}

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	ivec2 sz = ivec2(p.size.xy);
	if (pix.x >= sz.x || pix.y >= sz.y) return;
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
