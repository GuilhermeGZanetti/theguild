shader_type canvas_item;
// Recolours an index portrait through a unit palette (see unit_sprite.gdshader).

uniform sampler2D palette : filter_nearest, source_color;
uniform float grey = 0.0;
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	if (s.a < 0.5) discard;
	int slot = int(floor(s.r * 255.0 / 16.0 + 0.5));
	vec3 col;
	if (slot >= 15) {
		int inner = int(floor(s.g * 255.0 / 16.0 + 0.5));
		col = texelFetch(palette, ivec2(clamp(inner, 0, 14), 4), 0).rgb;
	} else {
		int shade = int(floor(s.g * 255.0 / 85.0 + 0.5));
		col = texelFetch(palette, ivec2(slot, clamp(shade, 0, 3)), 0).rgb;
	}
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g), grey);
	COLOR = vec4(col, 1.0) * modulate;
}
