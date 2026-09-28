shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// Props carry palette-slot data in their vertex colours (see tools/blender/props.py).

uniform sampler2D palette : filter_nearest, source_color;   // 16 x 4
uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform float desaturate = 0.0;
uniform float fade = 0.0;          // dithered fade for foliage covering units
uniform float glow_energy = 1.4;
uniform vec3 hush_tint = vec3(0.62, 0.62, 0.66);
uniform float highlight = 0.0;     // hovered hotspot in the guild hub
uniform vec4 glow_override = vec4(0.0);   // a > 0 replaces the glow slot colour
varying vec3 wpos;

#include "res://shaders/toon.gdshaderinc"

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int slot = clamp(int(floor(COLOR.r * 16.0)), 0, 15);
	float jit = COLOR.g;
	float ground = COLOR.b;
	// world-space pixel grain, aligned to the 24 px/unit texel grid
	vec3 q = floor(wpos * 24.0);
	float n = texture(noise_tex, (q.xz + q.y * 7.0) / 64.0).r;
	float v = (jit - 0.5) * 0.9 + (n - 0.5) * 0.9;
	int row = 2;
	if (v > 0.32) row = 3;
	else if (v < -0.38) row = 1;
	if (ground < 0.5) row = max(row - 1, 0);
	vec3 col = texelFetch(palette, ivec2(slot, row), 0).rgb;
	if (slot == 11) {
		if (glow_override.a > 0.0) col = glow_override.rgb * (0.8 + 0.25 * float(row));
		EMISSION = col * glow_energy;
	}
	col = mix(col, min(col * 1.28 + vec3(0.07, 0.06, 0.03), vec3(1.0)), highlight);
	EMISSION += vec3(0.05, 0.04, 0.02) * highlight;
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g) * hush_tint / 0.64, desaturate);
	ALBEDO = col;
	if (fade > 0.0) {
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if (bayer[p.y * 4 + p.x] / 16.0 < fade * 0.72) discard;
	}
}
