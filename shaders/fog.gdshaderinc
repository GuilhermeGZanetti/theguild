// Fog of war over the board. Unexplored ground sinks into a grey haze the
// squad can barely see through, explored ground keeps a lighter veil and
// what the squad sees right now is clear. Needs mist.gdshaderinc (noise).

uniform sampler2D fog_tex : filter_linear, repeat_disable;   // r = explored, g = in sight, b = trail
uniform float fog_on = 0.0;
uniform vec4 fog_rect = vec4(0.0, 0.0, 16.0, 16.0);          // x0, z0, x1, z1
uniform vec3 fog_tint : source_color = vec3(0.12, 0.12, 0.17);

float fog_amount(vec3 wp, float t) {
	vec2 size = fog_rect.zw - fog_rect.xy;
	// wobble the lookup so the edges drift instead of following the tiles
	float n = texture(mist_noise, wp.xz / 6.0 + vec2(t * 0.012, -t * 0.008)).r;
	vec2 uv = (wp.xz - fog_rect.xy + vec2(n - 0.5) * 0.8) / size;
	vec3 f = texture(fog_tex, uv).rgb;
	float a = mix(0.86, 0.4, f.r) * (1.0 - f.g);
	// the trail glimmers through so the way north is never lost
	a *= 1.0 - 0.38 * f.b;
	// past the board the edge values carry on until the mist takes over
	return a * fog_on;
}

vec3 fog_apply(vec3 col, float a, vec3 wp, float t) {
	float n = texture(mist_noise, wp.xz / 3.0 - vec2(t * 0.02, t * 0.011)).r;
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	vec3 veiled = mix(vec3(g) * 0.6, fog_tint, 0.45 + (n - 0.5) * 0.2);
	return mix(col, veiled, a);
}
