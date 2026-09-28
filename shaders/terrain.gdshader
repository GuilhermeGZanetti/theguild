shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// Tile terrain: ground types come from a splat map with noisy borders,
// sides use the cliff strata with a hanging lip of the tile's ground.

uniform sampler2D atlas : filter_nearest, source_color;   // strip of 48px textures
uniform sampler2D splat : filter_nearest;                  // R8: ground index per tile
uniform sampler2D noise_tex : filter_nearest, repeat_enable;
uniform int tex_count = 15;
uniform int cliff_index = 13;
uniform vec2 map_size = vec2(16.0, 16.0);
uniform vec2 map_origin = vec2(0.0);                       // world xz of splat texel 0
uniform float grid_alpha = 0.0;
uniform vec4 play_rect = vec4(0.0, 0.0, 1e5, 1e5);         // grid lines only on the playable map
uniform float desaturate = 0.0;
uniform vec3 hush_tint = vec3(0.62, 0.62, 0.66);
varying vec3 wpos;
varying vec3 wnorm;
varying float top_y;

#include "res://shaders/toon.gdshaderinc"

const float PX = 24.0;
const int TS = 48;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = NORMAL;
	top_y = UV2.x;
}

int ground_at(vec2 xz) {
	ivec2 t = ivec2(floor(xz - map_origin));
	t = clamp(t, ivec2(0), ivec2(map_size) - 1);
	return int(texelFetch(splat, t, 0).r * 255.0 + 0.5);
}

vec3 tex(int idx, ivec2 px) {
	ivec2 p = ivec2(((px.x % TS) + TS) % TS + idx * TS, ((px.y % TS) + TS) % TS);
	return texelFetch(atlas, p, 0).rgb;
}

void fragment() {
	vec3 col;
	if (wnorm.y > 0.5) {
		vec2 pxf = floor(wpos.xz * PX);
		ivec2 px = ivec2(pxf);
		float n1 = texture(noise_tex, pxf / 96.0).r;
		float n2 = texture(noise_tex, pxf / 96.0 + vec2(0.37, 0.61)).r;
		vec2 jitter = (vec2(n1, n2) - 0.5) * 0.85;
		vec2 cell = (pxf + 0.5) / PX;
		int g = ground_at(cell + jitter);
		int own = ground_at(cell);
		// water beds and planks keep crisp edges
		if (own == 10 || g == 10 || own == 12 || g == 12) g = own;
		col = tex(g, px);
		if (grid_alpha > 0.0 && all(greaterThanEqual(cell, play_rect.xy)) && all(lessThan(cell, play_rect.zw))) {
			vec2 f = fract(cell);
			if (f.x < 1.0 / PX || f.y < 1.0 / PX) col *= 1.0 - grid_alpha;
		}
	} else {
		// side face: along-edge coordinate and height
		float along = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
		ivec2 px = ivec2(int(floor(along * PX)), int(floor(-wpos.y * PX)));
		vec2 inward = wpos.xz - wnorm.xz * 0.25;
		int own = ground_at(inward);
		float depth = (top_y - wpos.y) * PX;
		float lip = 2.0 + floor(texture(noise_tex, vec2(float(px.x) / 64.0, 0.3)).r * 4.0);
		if (depth < lip && own != 12 && own != 10) {
			col = tex(own, px) * (depth < 1.0 ? 1.0 : 0.86);
		} else {
			col = tex(cliff_index, px);
			if (depth < lip + 1.0) col *= 0.7;
		}
	}
	// the land beyond the board sinks gently into shadow so its edge reads
	vec2 o = max(play_rect.xy - wpos.xz, wpos.xz - play_rect.zw);
	float outside = length(max(o, vec2(0.0)));
	col *= 1.0 - 0.16 * smoothstep(0.0, 2.5, outside);
	float gray = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(gray) * hush_tint / 0.64, desaturate);
	ALBEDO = col;
}
