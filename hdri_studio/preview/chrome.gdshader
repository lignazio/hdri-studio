// Sfera cromata "esatta": campiona direttamente la panoramica con il vettore riflesso,
// senza passare dalla radiance map del cielo (che è limitata a 256 px per lato in realtime).
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D panorama : filter_linear, repeat_enable, source_color;
uniform float exposure = 1.0;

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 r = reflect(-v, n);
	vec2 uv = vec2(atan(-r.x, r.z) / (2.0 * PI) + 0.5, 0.5 - asin(clamp(r.y, -1.0, 1.0)) / PI);
	ALBEDO = texture(panorama, uv).rgb * exposure;
}
