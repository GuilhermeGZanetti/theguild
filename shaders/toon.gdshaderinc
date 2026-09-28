// Stepped toon lighting shared by terrain and props.
// Shadows are handled by the ambient colour (blue/purple), lights are warm.

uniform float toon_sun_mid = 0.62;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float l = clamp(ndl, 0.0, 1.0) * ATTENUATION;
	float band;
	if (LIGHT_IS_DIRECTIONAL) {
		band = l > 0.38 ? 1.0 : (l > 0.06 ? toon_sun_mid : 0.0);
	} else {
		band = l > 0.45 ? 1.0 : (l > 0.18 ? 0.55 : (l > 0.04 ? 0.22 : 0.0));
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * band / PI;
}
