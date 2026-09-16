// Mostra la mappa float nel 2D: esposizione, clamp, codifica sRGB. Solo visualizzazione.
shader_type canvas_item;

uniform float exposure = 1.0;
uniform float clip_threshold = -1.0; // < 0 = disattivo

void fragment() {
	vec3 raw = texture(TEXTURE, UV).rgb;
	vec3 c = clamp(raw * exposure, 0.0, 1.0);
	if (clip_threshold > 0.0 && max(raw.r, max(raw.g, raw.b)) > clip_threshold) {
		c = vec3(1.0, 0.0, 1.0);
	}
	c = mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
	COLOR = vec4(c, 1.0);
}
