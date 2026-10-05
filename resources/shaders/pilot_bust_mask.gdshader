shader_type canvas_item;

// Pilot strip portrait (`features/battle_sim/ui/PilotStrip.gd`), Deadlock-style:
// a team-coloured disc sits at the bottom of the rect and a head-and-shoulders
// bust (`pilot/bust/N_bust.png`) is drawn over it with this mask —
//   • below the disc centre  → clipped to the disc (the bottom half is round),
//   • above the disc centre  → clipped to the disc's WIDTH only, so the head
//                              pops out past the top of the circle.
// The rect must have the bust aspect (w : h = 0.8); the disc diameter is the
// rect width, so its centre is (w/2, h − w/2).
//
// Drawn on a ColorRect (not a TextureRect) so the disc still shows when there is
// no portrait (standalone run / INTL pilots — `has_portrait = false`).
//
// The skill-readiness dim lives here too: everything right of `fill` (0..1 of
// the width) is darkened by `dim`. Doing it in the shader keeps the dim inside
// the mask — a ColorRect overlay would paint a box over the empty corners.

uniform sampler2D portrait : source_color, filter_linear_mipmap;
uniform bool has_portrait = false;
uniform vec4 disc_color : source_color = vec4(0.20, 0.36, 0.62, 1.0);
uniform vec4 rim_color : source_color = vec4(0.32, 0.62, 0.95, 1.0);
uniform float rim_width = 3.0;
uniform vec2 rect_size = vec2(180.0, 225.0);
uniform float fill = 1.0;
uniform float dim = 0.0;
// Whole-cell tint (a downed pilot greys out). Multiplies RGB.
uniform vec4 tint : source_color = vec4(1.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float r = rect_size.x * 0.5;
	vec2 c = vec2(r, rect_size.y - r);
	vec2 p = local_pos;
	float d_disc = length(p - c) - r;
	float aa = max(fwidth(d_disc), 1e-4);
	float in_disc = clamp(0.5 - d_disc / aa, 0.0, 1.0);

	// Disc + rim ring on its outer edge.
	float in_ring = clamp(0.5 - (abs(d_disc + rim_width * 0.5) - rim_width * 0.5) / aa, 0.0, 1.0);
	vec4 col = vec4(disc_color.rgb, in_disc);
	col.rgb = mix(col.rgb, rim_color.rgb, in_ring);

	if (has_portrait) {
		vec4 t = texture(portrait, UV);
		// Above the centre only the rect's own sides clip — the head pops out.
		float m = (p.y < c.y) ? 1.0 : in_disc;
		float a = t.a * m;
		// The rim stays on top of the bust in the lower half so the circle edge
		// reads as a frame; above the centre the bust covers it.
		float over_ring = (p.y < c.y) ? 0.0 : in_ring;
		vec3 rgb = mix(col.rgb, t.rgb, a * (1.0 - over_ring));
		col = vec4(rgb, max(col.a, a));
	}

	if (UV.x > fill) {
		col.rgb *= 1.0 - dim;
	}
	col.rgb *= tint.rgb;
	COLOR = col;
}
