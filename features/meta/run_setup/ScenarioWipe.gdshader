shader_type canvas_item;

// Black brush / wind wipe for `ScenarioSelectView` (driven by `ScenarioWipe.gd`). Threshold-mask
// ("luma") wipe: every pixel gets a value v in 0..1 — mostly its position along the travel axis,
// partly horizontally stretched fBm noise — and is black once the eased progress passes v. The noise
// makes the boundary coarse streaks stretched along the travel direction; `soft` gives the boundary a
// short black gradient tail; the noise flows with the travel (TIME) so the streaks stay alive.
//
// via_black = true (what the view uses): progress 0 → 0.5 covers the screen, 0.5 = fully black
// (c == 1 on every pixel), 0.5 → 1 removes the black in the SAME direction with the same mask
// (the black keeps travelling and its trailing edge leaves). via_black = false: 0 → 1 only covers.
// Each half is eased with a cubic ease-in-out. Output: black with alpha = coverage.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
/// 1 = travels left → right (starts at the left edge), -1 = right → left.
uniform float direction = 1.0;
uniform bool via_black = true;
/// Width of the boundary's gradient tail (in v units).
uniform float soft : hint_range(0.0, 1.0) = 0.2;
uniform float scale = 3.0;
/// Horizontal stretch of the noise — larger = longer streaks.
uniform float stretch = 8.0;
uniform float speed = 1.0;
/// Rect width / height (set by ScenarioWipe.gd on resize) so the noise is not squashed.
uniform float aspect = 0.5625;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

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

// 5-octave fBm, normalised to 0..1.
float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 5; i++) {
		sum += value_noise(p) * amp;
		norm += amp;
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum / norm;
}

float ease_in_out_cubic(float t) {
	return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5;
}

void fragment() {
	float dir = direction >= 0.0 ? 1.0 : -1.0;
	float x = dir > 0.0 ? UV.x : 1.0 - UV.x;
	float time = TIME * speed;
	vec2 p = vec2(UV.x * aspect, UV.y);
	vec2 q = vec2(p.x * scale / stretch - time * dir, p.y * scale * 2.0);
	float n = smoothstep(0.2, 0.8, fbm(q));
	float v = clamp(x * 0.65 + n * 0.35, 0.0, 1.0);

	float c;
	if (via_black) {
		if (progress <= 0.5) {
			float t = ease_in_out_cubic(clamp(progress * 2.0, 0.0, 1.0));
			c = smoothstep(v, v + soft, t * (1.0 + soft));
		} else {
			float t2 = ease_in_out_cubic(clamp((progress - 0.5) * 2.0, 0.0, 1.0));
			c = 1.0 - smoothstep(v, v + soft, t2 * (1.0 + soft));
		}
	} else {
		float t = ease_in_out_cubic(clamp(progress, 0.0, 1.0));
		c = smoothstep(v, v + soft, t * (1.0 + soft));
	}
	COLOR = vec4(tint.rgb, tint.a * c);
}
