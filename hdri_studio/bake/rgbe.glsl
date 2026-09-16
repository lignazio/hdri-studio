#[compute]
#version 450

// Codifica Radiance RGBE (per i file .hdr): mantissa a 8 bit con esponente condiviso.
// src: immagine lineare RGBA32F; dst: RGBA8 uint = (r, g, b, e + 128).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) restrict readonly uniform image2D src;
layout(set = 0, binding = 1, rgba8ui) restrict writeonly uniform uimage2D dst;

void main() {
	ivec2 pix = ivec2(gl_GlobalInvocationID.xy);
	ivec2 sz = imageSize(src);
	if (pix.x >= sz.x || pix.y >= sz.y) return;
	vec3 c = max(imageLoad(src, pix).rgb, vec3(0.0));
	float m = max(c.r, max(c.g, c.b));
	uvec4 o = uvec4(0u);
	if (m >= 1e-32) {
		int ex = int(floor(log2(m))) + 1;     // m = f · 2^ex con f in [0.5, 1)
		float scale = exp2(float(-ex)) * 256.0;
		uvec3 q = uvec3(clamp(floor(c * scale), 0.0, 255.0));
		o = uvec4(q, uint(clamp(ex + 128, 0, 255)));
	}
	imageStore(dst, pix, o);
}
