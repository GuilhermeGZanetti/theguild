class_name UnitPalette
extends RefCounted
## Builds the 16x5 palette texture for an index sprite from slot colours.
## Mirrors tools/py/palette.py: shadows shift toward purple, lights toward yellow.

const SLOTS := ["skin", "skin2", "hair", "eyes", "cloth1", "cloth2", "leather", "metal",
		"trim", "wood", "glow", "feature", "cape", "white", "bandage"]
const DEFAULTS := {
	"skin": [238, 188, 150], "skin2": [196, 112, 104], "hair": [92, 58, 48], "eyes": [38, 28, 48],
	"cloth1": [64, 124, 170], "cloth2": [186, 70, 64], "leather": [126, 84, 54], "metal": [176, 184, 196],
	"trim": [226, 184, 74], "wood": [146, 98, 58], "glow": [130, 236, 255], "feature": [96, 176, 136],
	"cape": [84, 128, 72], "white": [236, 230, 218], "bandage": [242, 236, 224],
}

static var _cache := {}


static func shift_hue(h: float, target: float, amount: float) -> float:
	var d := fposmod(target - h + 0.5, 1.0) - 0.5
	return fposmod(h + d * amount, 1.0)


static func ramp(c: Color) -> Array:
	var out := []
	var h := c.h
	var s := c.s
	var v := c.v
	for level in 4:
		var hh := h
		var ss := s
		var vv := v
		match level:
			3:
				hh = shift_hue(h, 1.0 / 6.0, 0.12)
				ss = s * 0.82
				vv = minf(1.0, v * 1.16 + 0.05)
			1:
				hh = shift_hue(h, 0.70, 0.12)
				ss = minf(1.0, s * 1.08 + 0.05)
				vv = v * 0.72
			0:
				hh = shift_hue(h, 0.72, 0.22)
				ss = minf(1.0, s * 1.12 + 0.08)
				vv = v * 0.48
		out.append(Color.from_hsv(hh, ss, vv))
	return out


static func outline_of(c: Color) -> Color:
	var deep: Color = ramp(c)[0]
	var h := shift_hue(deep.h, 0.75, 0.3)
	return Color.from_hsv(h, minf(1.0, deep.s * 1.1 + 0.1), deep.v * 0.55 + 0.03)


static func to_color(v) -> Color:
	if v is Color:
		return v
	if v is Array and v.size() >= 3:
		return Color8(int(v[0]), int(v[1]), int(v[2]))
	return Color.MAGENTA


static func build(pal: Dictionary) -> ImageTexture:
	var key := JSON.stringify(pal)
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(16, 5, false, Image.FORMAT_RGBA8)
	for i in SLOTS.size():
		var c := to_color(pal.get(SLOTS[i], DEFAULTS[SLOTS[i]]))
		var r := ramp(c)
		for j in 4:
			img.set_pixel(i, j, r[j])
		img.set_pixel(i, 4, outline_of(c))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
