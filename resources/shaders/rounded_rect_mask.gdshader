shader_type canvas_item;

// Rounds ALL four corners of a Control's rect with an anti-aliased edge — the
// all-corners sibling of `rounded_top_mask.gdshader`. Used for card-art
// thumbnails (pilot detail panel's persistent-effect thumbs).
//
// Measured in local pixels (VERTEX), not UV, so it stays correct on a
// TextureRect in KEEP_ASPECT_COVERED mode.

uniform vec2 rect_size = vec2(68.0, 68.0);
uniform float radius = 10.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 p = local_pos - half_size;
	vec2 q = abs(p) - half_size + radius;
	float d = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
	float aa = max(fwidth(d), 1e-4);
	COLOR.a *= clamp(0.5 - d / aa, 0.0, 1.0);
}
