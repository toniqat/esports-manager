shader_type canvas_item;

// Soft drop shadow of a logo texture (`ScenarioSelectView` %LogoShadow): the texture's alpha,
// blurred, painted in `shadow_color`. The node rect is the logo rect grown by `pad` (fraction of the
// node size, per side) so the blur has room to spread; the logo itself is sampled inset by `pad`.
// Offset (the "drop") is the node's position, not the shader's.

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.55);
/// Inset of the logo inside the node rect, per side, as a fraction of the node size.
uniform float pad : hint_range(0.0, 0.45) = 0.1;
/// Blur radius as a fraction of the logo (inner) size.
uniform float blur : hint_range(0.0, 0.2) = 0.05;

// Node (and parent) modulate — the fragment COLOR is overwritten, so carry it from the vertex
// stage; the shadow then fades with its parent like everything else.
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

const int RINGS = 3;
const int TAPS = 12;
const float FULL_TURN = 6.283185307;

float _alpha_at(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec2 inner = max(vec2(0.0001), vec2(1.0) - vec2(pad * 2.0));
	vec2 uv = (UV - vec2(pad)) / inner;
	float sum = _alpha_at(TEXTURE, uv);
	float weight = 1.0;
	for (int r = 1; r <= RINGS; r++) {
		float rad = blur * float(r) / float(RINGS);
		float w = 1.0 - float(r) / float(RINGS + 1);
		for (int i = 0; i < TAPS; i++) {
			float ang = FULL_TURN * (float(i) + 0.5 * float(r)) / float(TAPS);
			sum += _alpha_at(TEXTURE, uv + vec2(cos(ang), sin(ang)) * rad) * w;
			weight += w;
		}
	}
	COLOR = vec4(shadow_color.rgb, shadow_color.a * sum / weight) * v_modulate;
}
