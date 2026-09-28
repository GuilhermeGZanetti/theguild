shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// Index sprites: R = palette slot * 16, G = shade * 85 (outline: inner slot).

uniform sampler2D sheet : filter_nearest;
uniform sampler2D palette : filter_nearest, source_color;   // 16 x 5 (4 shades + outline row)
uniform vec2 frame = vec2(0.0);               // column, row
uniform vec2 grid = vec2(26.0, 4.0);          // columns, rows in the sheet
uniform bool flip = false;
uniform float flash = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform float alpha = 1.0;
uniform float grey = 0.0;
uniform float ghost = 0.0;
uniform float highlight = 0.0;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec2 uv = UV;
	if (flip) uv.x = 1.0 - uv.x;
	vec2 suv = (frame + uv) / grid;
	vec4 s = texture(sheet, suv);
	if (s.a < 0.5) discard;
	int slot = int(floor(s.r * 255.0 / 16.0 + 0.5));
	vec3 col;
	if (slot >= 15) {
		int inner = int(floor(s.g * 255.0 / 16.0 + 0.5));
		col = texelFetch(palette, ivec2(clamp(inner, 0, 14), 4), 0).rgb;
		if (highlight > 0.0) col = mix(col, vec3(1.0, 0.92, 0.55), highlight);
	} else {
		int shade = int(floor(s.g * 255.0 / 85.0 + 0.5));
		col = texelFetch(palette, ivec2(slot, clamp(shade, 0, 3)), 0).rgb;
	}
	col *= tint;
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g * 0.95, g * 0.96, g * 1.04), grey);
	col = mix(col, flash_color, flash);
	float a = alpha;
	if (ghost > 0.0) {
		ivec2 p = ivec2(FRAGCOORD.xy) % 2;
		if ((p.x + p.y) % 2 == 0 && ghost > 0.5) discard;
		a *= 1.0 - ghost * 0.3;
	}
	ALBEDO = col;
	ALPHA = a;
}
