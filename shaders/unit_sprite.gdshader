shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, ambient_light_disabled, specular_disabled;
// Index sprites: R = palette slot * 16, G = shade * 85 (outline: inner slot).
// Lit by the scene. Palette colours are final under full sun at noon: the sun
// pass lays down the whole base light (sky + sun through its shadow map) and
// point lights (lanterns, fires, spells) add banded pools on top, under a
// soft knee so they never blow out. The map sets the unit_* globals
// (BattleMapView.update_unit_light).

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
uniform vec3 highlight_color : source_color = vec3(1.0, 0.92, 0.55);
uniform vec3 tint : source_color = vec3(1.0);

global uniform vec3 unit_amb_light;   // base light in shade, 1.0 = full sun at noon
global uniform vec3 unit_light_k;     // LIGHT_COLOR / PI -> the same scale
global uniform vec3 unit_expo;        // the hour's exposure (eyes adapt to dusk and night)

const float LIFT = 0.75;              // < 1 lifts the darks so the squad stays readable
const float KNEE = 0.95;
const float HEADROOM = 0.25;

void fragment() {
	vec2 uv = UV;
	if (flip) uv.x = 1.0 - uv.x;
	vec2 suv = (frame + uv) / grid;
	vec4 s = texture(sheet, suv);
	if (s.a < 0.5) discard;
	int slot = int(floor(s.r * 255.0 / 16.0 + 0.5));
	vec3 col;
	vec3 glow = vec3(0.0);
	if (slot >= 15) {
		int inner = int(floor(s.g * 255.0 / 16.0 + 0.5));
		col = texelFetch(palette, ivec2(clamp(inner, 0, 14), 4), 0).rgb;
		if (highlight > 0.0) {
			glow = highlight_color * highlight;
			col *= 1.0 - highlight;
		}
	} else {
		int shade = int(floor(s.g * 255.0 / 85.0 + 0.5));
		col = texelFetch(palette, ivec2(slot, clamp(shade, 0, 3)), 0).rgb;
	}
	col *= tint;
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g * 0.95, g * 0.96, g * 1.04), grey);
	// the selection rim and the hit flash ignore the light
	glow = mix(glow, flash_color, flash);
	col *= 1.0 - flash;
	float a = alpha;
	if (ghost > 0.0) {
		ivec2 p = ivec2(FRAGCOORD.xy) % 2;
		if ((p.x + p.y) % 2 == 0 && ghost > 0.5) discard;
		a *= 1.0 - ghost * 0.3;
	}
	ALBEDO = col;
	EMISSION = glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = a;
}

vec3 soft_knee(vec3 x) {
	vec3 over = max(x - KNEE, vec3(0.0));
	return min(x, vec3(KNEE)) + over / (1.0 + over / HEADROOM);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// the sun (moon at night) runs first and carries the base light; its
		// shadow map is banded so tree and roof shade cuts crisply
		float sh = ATTENUATION > 0.6 ? 1.0 : (ATTENUATION > 0.25 ? 0.5 : 0.0);
		float facing = 1.0 + 0.08 * clamp(dot(NORMAL, LIGHT), -1.0, 1.0);
		vec3 base = unit_amb_light + LIGHT_COLOR / PI * unit_light_k * sh * facing;
		DIFFUSE_LIGHT = soft_knee(DIFFUSE_LIGHT + pow(max(base, vec3(0.0)), vec3(LIFT)) * unit_expo);
	} else {
		// lanterns, fires and spells: banded pools like the terrain's toon light
		float l = ATTENUATION * (0.6 + 0.4 * max(dot(NORMAL, LIGHT), 0.0));
		float band = l > 0.45 ? 1.0 : (l > 0.18 ? 0.55 : (l > 0.04 ? 0.22 : 0.0));
		DIFFUSE_LIGHT = soft_knee(DIFFUSE_LIGHT + LIGHT_COLOR / PI * unit_light_k * band);
	}
}
