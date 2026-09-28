shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Small ground decoration billboards (tufts, flowers, shells...).
// White/grey pixels take the biome grass colour, red pixels the accent.

uniform sampler2D sheet : filter_nearest, source_color;
uniform float cell = 0.0;
uniform float cells = 12.0;
uniform float yaw = 0.785398;
uniform vec3 grass : source_color = vec3(0.4, 0.6, 0.3);
uniform vec3 accent : source_color = vec3(0.9, 0.4, 0.4);
uniform float desaturate = 0.0;

void vertex() {
	float c = cos(yaw);
	float s = sin(yaw);
	vec3 v = VERTEX;
	VERTEX = vec3(v.x * c, v.y, -v.x * s);
	// nudge toward the camera so the base never clips the ground
	VERTEX += vec3(s, 0.0, c) * 0.12;
}

void fragment() {
	vec2 uv = vec2((cell + UV.x) / cells, UV.y);
	vec4 t = texture(sheet, uv);
	if (t.a < 0.5) discard;
	vec3 col = t.rgb;
	if (abs(t.r - t.g) < 0.02 && abs(t.g - t.b) < 0.02 && t.r > 0.7) {
		col = t.r > 0.9 ? grass * 1.18 : grass * 0.86;
	} else if (t.r > 0.9 && t.g < 0.1 && t.b < 0.1) {
		col = accent;
	} else if (t.r > 0.7 && t.g < 0.1) {
		col = accent * 0.8;
	} else if (t.r > 0.9 && t.g > 0.9 && t.b < 0.1) {
		col = vec3(1.0, 0.9, 0.4);
	}
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g), desaturate);
	ALBEDO = col * 0.95;
}
