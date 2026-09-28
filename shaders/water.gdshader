shader_type spatial;
render_mode cull_back, unshaded, blend_mix, depth_draw_opaque;
// Animated pixel water with foam along the shore.

uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform sampler2D shore : filter_linear;    // distance-to-land mask (1 = touching land)
uniform vec2 map_size = vec2(16.0, 16.0);
uniform vec2 map_origin = vec2(0.0);
uniform vec3 water_color : source_color = vec3(0.25, 0.62, 0.68);
uniform float desaturate = 0.0;
uniform float opacity = 0.86;
varying vec3 wpos;

#include "res://shaders/mist.gdshaderinc"

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 pxf = floor(wpos.xz * 24.0);
	float t = floor(TIME * 6.0) / 6.0;
	float n = texture(noise_tex, pxf / 80.0 + vec2(t * 0.02, t * 0.013)).r;
	float n2 = texture(noise_tex, pxf / 40.0 - vec2(t * 0.017, -t * 0.01)).r;
	vec3 deep = water_color * 0.72;
	vec3 mid = water_color;
	vec3 light = mix(water_color, vec3(0.9, 0.97, 1.0), 0.45);
	vec3 col = n < 0.42 ? deep : (n < 0.62 ? mid : mid * 1.06);
	if (n2 > 0.72) col = light;
	float s = texture(shore, (pxf / 24.0 - map_origin) / map_size).r;
	float wave = sin(TIME * 1.6 - s * 9.0) * 0.5 + 0.5;
	float foam_n = texture(noise_tex, pxf / 32.0 + vec2(t * 0.05, 0.0)).r;
	if (s > 0.9 - wave * 0.08 + foam_n * 0.06) col = vec3(0.94, 0.97, 0.98);
	else if (s > 0.74 - wave * 0.06 + foam_n * 0.06) col = mix(col, vec3(0.85, 0.94, 0.96), 0.5);
	float gray = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(gray * 0.96, gray * 0.96, gray * 1.02), desaturate);
	float a = opacity;
	if (mist > 0.0) {
		float f = mist_dither(mist_amount(wpos, TIME), wpos, INV_VIEW_MATRIX);
		col = mix(col, mist_tint(wpos, TIME), f);
		a = mix(a, 1.0, f);
	}
	ALBEDO = col;
	ALPHA = a;
}
