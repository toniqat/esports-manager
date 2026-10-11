shader_type canvas_item;

// Week screen top banner (`%TeamBanner`, a `TeamBanner` draw widget): the image is drawn as
// is up to `fade_from` of the rect width, then dissolves into transparency to the right edge
// through coarse horizontal streaks (the `ScenarioWipe` look, still — no TIME). Every pixel
// gets v = its position inside the fade band; it stays while v is under a horizontally
// stretched fBm value, so the boundary breaks into streaks along the rows. Works for any
// draw call of the node: the position comes from the vertex (node-local), not from UV.

/// Node size in px (set by `WeekProgressView` on resize).
uniform vec2 rect_size = vec2(540.0, 120.0);
/// Where the fade starts, fraction of the width (0.7 = the right 30 % dissolves).
uniform float fade_from : hint_range(0.0, 1.0) = 0.7;
/// Noise frequency across the rows and its horizontal stretch (larger = longer streaks).
uniform float scale = 9.0;
uniform float stretch = 12.0;
/// Softness of each streak's tail (in v units).
uniform float soft : hint_range(0.0, 0.5) = 0.12;

varying vec2 local_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		norm += amp;
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum / norm;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 p = local_pos / max(rect_size, vec2(1.0));
	float v = clamp((p.x - fade_from) / max(1.0 - fade_from, 0.001), 0.0, 1.0);
	float aspect = rect_size.x / max(rect_size.y, 1.0);
	float n = fbm(vec2(p.x * aspect * scale / stretch, p.y * scale));
	// Threshold per row: 0.15 … 0.85, so v = 0 always shows and v = 1 never does.
	float edge = mix(0.15, 0.85, smoothstep(0.2, 0.8, n));
	float keep = 1.0 - smoothstep(edge - soft, edge + soft, v * (1.0 + soft) - soft * 0.5);
	COLOR = vec4(c.rgb, c.a * keep);
}
