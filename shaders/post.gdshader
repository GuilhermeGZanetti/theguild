shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix;
// Full-screen pass on the low-res buffer: depth outlines, normal-edge
// highlights, fog of war, mist around the map, Hush desaturation with a dithered grey
// vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform float outline_strength = 0.55;
uniform float highlight_strength = 0.18;
uniform float hush = 0.0;
uniform float vignette = 0.0;
uniform vec3 fog_color : source_color = vec3(0.62, 0.62, 0.66);

#include "res://shaders/mist.gdshaderinc"
#include "res://shaders/fog.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;
	float d = lin_depth(uv, INV_PROJECTION_MATRIX);
	vec3 n = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	float edge = 0.0;
	float ridge = 0.0;
	vec2 offs[4] = vec2[](vec2(px.x, 0.0), vec2(-px.x, 0.0), vec2(0.0, px.y), vec2(0.0, -px.y));
	for (int i = 0; i < 4; i++) {
		float dn = lin_depth(uv + offs[i], INV_PROJECTION_MATRIX);
		if (dn < d - 0.35) edge = 1.0;
		vec3 nn = texture(normal_tex, uv + offs[i]).xyz * 2.0 - 1.0;
		if (dn >= d - 0.05 && dot(n, nn) < 0.8 && dot(nn - n, vec3(0.0, 1.0, 0.0)) < 0.0) ridge = 1.0;
	}
	if (d > 400.0) { edge = 0.0; ridge = 0.0; }
	if (edge > 0.0) {
		col = col * (1.0 - outline_strength) + vec3(0.12, 0.08, 0.2) * outline_strength * 0.5;
	} else if (ridge > 0.0) {
		col = mix(col, col * 1.35 + vec3(0.04, 0.03, 0.0), highlight_strength);
	}
	if (mist > 0.0 || fog_on > 0.0) {
		float dr = texture(depth_tex, uv).r;
		vec4 vp = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, dr, 1.0);
		vec3 wp = (INV_VIEW_MATRIX * vec4(vp.xyz / vp.w, 1.0)).xyz;
		if (fog_on > 0.0 && d <= 250.0) {
			col = fog_apply(col, mist_dither(fog_amount(wp, TIME), wp, INV_VIEW_MATRIX), wp, TIME);
		}
		if (mist > 0.0) {
			float f = d > 250.0 ? 1.0 : mist_dither(mist_amount(wp, TIME), wp, INV_VIEW_MATRIX);
			col = mix(col, mist_tint(wp, TIME), f);
		}
	}
	// Hush: desaturate and dither into grey at the edges of the screen
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g) * fog_color / 0.64, hush);
	if (vignette > 0.0) {
		vec2 c = uv - 0.5;
		float r = length(c * vec2(1.3, 1.0));
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		float th = bayer[p.y * 4 + p.x] / 16.0;
		if (smoothstep(0.42, 0.72, r) * vignette > th) col = fog_color;
	}
	ALBEDO = col;
}
