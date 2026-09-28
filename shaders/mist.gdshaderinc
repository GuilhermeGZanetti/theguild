// Soft mist around the playable map: drifting, dithered in world-anchored
// pixels so it never swims when the camera pans.

uniform vec4 map_rect = vec4(0.0, 0.0, 16.0, 16.0);   // x0, z0, x1, z1
uniform vec3 mist_color : source_color = vec3(0.3, 0.3, 0.4);
uniform float mist = 0.0;
uniform float mist_reach = 5.5;
uniform sampler2D mist_noise : filter_linear, repeat_enable;

float mist_amount(vec3 wp, float t) {
	vec2 lo = map_rect.xy - wp.xz;
	vec2 hi = wp.xz - map_rect.zw;
	vec2 o = max(lo, hi);
	// signed distance to the map rectangle (negative inside)
	float sd = length(max(o, vec2(0.0))) + min(max(o.x, o.y), 0.0);
	float n = texture(mist_noise, wp.xz / 11.0 + vec2(t * 0.011, t * 0.006)).r;
	float n2 = texture(mist_noise, wp.xz / 4.0 - vec2(t * 0.02, -t * 0.013)).r;
	float f = smoothstep(0.0, mist_reach, sd + (n - 0.5) * 2.0 + (n2 - 0.5) * 0.7);
	return f * mist;
}

// Quantize into a few bands with an ordered dither between them.
float mist_dither(float f, vec3 wp, mat4 inv_view) {
	vec2 sp = vec2(dot(wp, inv_view[0].xyz), -dot(wp, inv_view[1].xyz)) * 24.0;
	ivec2 p = ivec2(floor(sp)) & ivec2(3);
	float bayer[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	float th = (bayer[p.y * 4 + p.x] + 0.5) / 16.0;
	return clamp(floor(f * 6.0 + th) / 6.0, 0.0, 1.0);
}

vec3 mist_tint(vec3 wp, float t) {
	float n = texture(mist_noise, wp.xz / 7.0 + vec2(-t * 0.008, t * 0.01)).r;
	return mist_color * (0.93 + n * 0.14);
}
