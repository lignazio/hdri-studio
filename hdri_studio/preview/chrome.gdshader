// Sfera cromata "esatta": campiona direttamente la panoramica con il vettore riflesso,
// senza passare dalla radiance map del cielo (che è limitata a 256 px per lato in realtime).
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D panorama : filter_linear, repeat_enable, source_color;
uniform float exposure = 1.0;
uniform float clip_threshold = -1.0; // < 0 = disattivo
// Riflettanza del metallo (F0): bianco = cromo/argento ideale, oro = (1.0, 0.71, 0.29)
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec2 uv = vec2(atan(-r.x, r.z) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(r.y, -1.0, 1.0)) / PI);
	vec3 raw = texture(panorama, uv).rgb * tint;
	ALBEDO = raw * exposure;
	if (clip_threshold > 0.0 && max(raw.r, max(raw.g, raw.b)) > clip_threshold) {
		ALBEDO = vec3(1.0, 0.0, 1.0) * exposure * 4.0;
	}
}
