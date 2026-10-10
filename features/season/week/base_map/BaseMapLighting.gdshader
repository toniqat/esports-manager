// Time-of-day lighting of a base map's art (BaseMapLighting.gd).
// normal_tex  — world normals of the map (z up), rgb = n * 0.5 + 0.5; ground = (0, 0, 1),
//               walls / roofs drawn from the BaseMapBuilding polygons
// shadow_tex  — red = 1 where a building's cast shadow lies on the ground (faces masked out)
// Both are rendered at map size × RES_SCALE and sampled by the map-local position.
// The art already carries its own baked shading: the lighting is relative — the ground
// keeps its brightness (the tint sets the time of day), a wall brightens / darkens
// against the ground as the sun turns, and cast shadows darken the ground.
shader_type canvas_item;

uniform sampler2D normal_tex : filter_linear, repeat_disable;
uniform sampler2D shadow_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(1200.0, 761.0);
uniform vec2 shadow_texel = vec2(0.0016, 0.0026);
uniform vec3 sun_dir = vec3(0.3, 0.4, 0.86);   // world, towards the sun, z up
uniform float sun_vis = 1.0;                    // 0 at night … 1 by day
uniform vec3 tint : source_color = vec3(1.0);
uniform float shadow_strength = 0.4;
uniform float normal_strength = 0.6;

varying vec2 map_uv;

void vertex() {
	map_uv = VERTEX / map_size;
}

void fragment() {
	vec4 albedo = COLOR;  // texture × modulate
	vec3 n = normalize(texture(normal_tex, map_uv).rgb * 2.0 - 1.0);
	float ground = 0.45 + 0.75 * max(sun_dir.z, 0.05);
	float lit = 0.45 + 0.75 * max(dot(n, sun_dir), 0.0);
	float rel = mix(1.0, clamp(lit / ground, 0.55, 1.35), normal_strength * sun_vis);
	// 5-tap soft edge
	float sh = texture(shadow_tex, map_uv).r * 0.4;
	sh += texture(shadow_tex, map_uv + vec2(shadow_texel.x, 0.0)).r * 0.15;
	sh += texture(shadow_tex, map_uv - vec2(shadow_texel.x, 0.0)).r * 0.15;
	sh += texture(shadow_tex, map_uv + vec2(0.0, shadow_texel.y)).r * 0.15;
	sh += texture(shadow_tex, map_uv - vec2(0.0, shadow_texel.y)).r * 0.15;
	float shade = rel * (1.0 - sh * shadow_strength * sun_vis);
	COLOR = vec4(albedo.rgb * shade * tint, albedo.a);
}
