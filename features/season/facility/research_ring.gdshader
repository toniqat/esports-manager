shader_type canvas_item;

// Research icon as a radial progress bar (ResearchBubble · ResearchRow · FacilitySheet).
// The node's texture (a quirk image) is masked to a circle inside an outer ring. The ring
// fills clockwise from 12 o'clock up to `progress` (`fill_color` over `track_color`); the
// icon is full colour inside the filled sector and greyed / dimmed outside it, so the
// icon itself reads as the gauge. `all_grey` greys the whole icon (idle / vacant / paused).
// Everything outside the outer circle is transparent. The node's modulate is kept
// (captured from the vertex colour, since COLOR is overwritten here).

uniform float progress : hint_range(0.0, 1.0) = 0.0;
// Ring thickness and the white gap between ring and icon, in UV units (size = 1).
uniform float ring_width : hint_range(0.0, 0.5) = 0.09;
uniform float gap : hint_range(0.0, 0.2) = 0.02;
uniform vec4 fill_color : source_color = vec4(0.961, 0.651, 0.137, 1.0);
uniform vec4 track_color : source_color = vec4(0.886, 0.890, 0.906, 1.0);
uniform vec4 gap_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Brightness of the icon outside the filled sector (and of the whole icon when all_grey).
uniform float rest_dim : hint_range(0.0, 1.0) = 0.6;
uniform bool all_grey = false;

varying vec4 vmod;

void vertex() {
	vmod = COLOR;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	float aa = max(fwidth(r), 0.0005);
	// Angle from 12 o'clock, clockwise, 0..1.
	float a = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
	float filled = progress > 0.0 ? step(a, progress) : 0.0;

	float inner = 0.5 - ring_width;
	float icon_r = inner - gap;
	// Icon: the inscribed circle of the texture scaled into icon_r.
	vec2 iuv = vec2(0.5) + p * (0.5 / max(icon_r, 0.001));
	vec4 tex = texture(TEXTURE, clamp(iuv, vec2(0.0), vec2(1.0)));
	float grey = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	bool dim = all_grey || filled < 0.5;
	vec3 icon_rgb = dim ? vec3(grey) * rest_dim + vec3(1.0 - rest_dim) * 0.35 : tex.rgb;
	vec4 icon = vec4(icon_rgb, tex.a);
	// Transparent icon pixels show the gap colour (a white disc behind the icon).
	icon = mix(gap_color, icon, tex.a);

	vec4 ring = filled > 0.5 ? fill_color : track_color;
	vec4 col = gap_color;
	col = mix(col, icon, 1.0 - smoothstep(icon_r - aa, icon_r, r));
	col = mix(col, ring, smoothstep(inner - aa, inner, r));
	float outer = 1.0 - smoothstep(0.5 - aa, 0.5, r);
	COLOR = vec4(col.rgb, col.a * outer) * vmod;
}
