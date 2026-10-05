shader_type canvas_item;

// Rounds the TOP two corners of a Control's rect with an anti-aliased edge.
// The coverage comes from a signed distance field, not a clip mask, so the
// curve fades over one screen pixel at any scale (`fwidth` follows the card's
// hover zoom). The bottom edge is left square and unfaded — the card art sits
// directly on the name plate and a faded seam would show a dark line there.
//
// Works on a TextureRect in any stretch mode: the mask is measured in the
// node's local pixels (VERTEX), not in UV, because KEEP_ASPECT_COVERED draws a
// texture sub-region and its UVs no longer span the rect.

uniform vec2 rect_size = vec2(160.0, 184.0);
uniform float radius = 10.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// Box extended `radius` past the bottom so the bottom edge never fades.
	vec2 half_size = vec2(rect_size.x, rect_size.y + radius) * 0.5;
	vec2 p = local_pos - half_size;
	float r = (p.y < 0.0) ? radius : 0.0;
	vec2 q = abs(p) - half_size + r;
	float d = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
	float aa = max(fwidth(d), 1e-4);
	COLOR.a *= clamp(0.5 - d / aa, 0.0, 1.0);
}
