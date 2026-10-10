@tool
class_name BaseMapLighting
extends Control

# ── Time-of-day lighting of a base map (해 · 그림자 · 색조) ───────────────────────
#   BaseMap_<Name>
#   ├ Art        the map picture
#   ├ Lighting   (this, full rect, mouse Ignore) — code adds, never saved:
#   │  ├ Lit         TextureRect = Art's picture again, drawn with BaseMapLighting.gdshader
#   │  ├ NormalView  SubViewport: ground (0,0,1) + every building's walls / roof as world normals
#   │  └ ShadowView  SubViewport: every building's cast shadow (white), faces masked black
#   └ Buildings  Node2D (hidden at runtime) ─ BaseMapBuilding × N (roof polygon + height)
# `hour` (0 … 24) drives the sun: it rises at `SUNRISE`, crosses the sky to `SUNSET`
# (azimuth sweeps 180° around `noon_azimuth_deg`), and the map takes the colour of
# `TINT_KEYS` at that hour. A map without `Buildings` still gets the tint.
# The ground plane is projected with a camera at `cam_azimuth_deg` / `cam_elevation_deg`
# (the art's isometric view): it turns a wall's screen edge into a ground direction
# (its light normal) and the sun's ground direction into the shadow's screen direction.
# Works in the editor too (@tool): scrub `hour` to preview, shapes refresh as you edit.

const SHADER: Shader = preload("res://features/season/week/base_map/BaseMapLighting.gdshader")
## Render scale of the normal / shadow views against the map size.
const RES_SCALE: float = 0.5
const SUNRISE: float = 6.0
const SUNSET: float = 19.0
const MAX_SUN_ELEVATION_DEG: float = 62.0
## Lowest sun height used for shadow length (a sun at the horizon would cast them to infinity).
const MIN_SHADOW_SUN_Z: float = 0.22
## Shadow length cap, × the building height.
const MAX_SHADOW_RATIO: float = 1.8
## Map tint by hour `[hour, Color]`, interpolated, wraps at 24.
const TINT_KEYS: Array = [
	[0.0, Color(0.38, 0.42, 0.66)],
	[5.0, Color(0.40, 0.44, 0.68)],
	[6.5, Color(0.92, 0.72, 0.66)],
	[8.5, Color(1.0, 0.95, 0.88)],
	[12.0, Color(1.0, 1.0, 1.0)],
	[16.0, Color(1.0, 0.95, 0.86)],
	[18.0, Color(1.0, 0.76, 0.58)],
	[19.3, Color(0.70, 0.56, 0.72)],
	[21.0, Color(0.40, 0.43, 0.67)],
	[24.0, Color(0.38, 0.42, 0.66)],
]
const _EDITOR_REFRESH: float = 0.4

@export_range(0.0, 24.0, 0.1) var hour: float = 12.0:
	set(v):
		hour = v
		if is_node_ready():
			_apply_hour()
@export_group("Projection")
## The art's camera: azimuth around the vertical axis and elevation above the ground.
@export_range(0.0, 90.0, 0.5) var cam_azimuth_deg: float = 45.0:
	set(v):
		cam_azimuth_deg = v
		_dirty = true
@export_range(5.0, 89.0, 0.5) var cam_elevation_deg: float = 25.0:
	set(v):
		cam_elevation_deg = v
		_dirty = true
@export_group("Sun")
## Ground azimuth of the sun at noon (world, 0 = the art's upper-right ground axis).
@export_range(-180.0, 180.0, 1.0) var noon_azimuth_deg: float = 56.0:
	set(v):
		noon_azimuth_deg = v
		if is_node_ready():
			_apply_hour()
@export_range(0.0, 1.0, 0.01) var shadow_strength: float = 0.42:
	set(v):
		shadow_strength = v
		if is_node_ready():
			_apply_hour()
@export_range(0.0, 1.0, 0.01) var normal_strength: float = 0.7:
	set(v):
		normal_strength = v
		if is_node_ready():
			_apply_hour()

var _mat: ShaderMaterial = null
var _normal_vp: SubViewport = null
var _shadow_vp: SubViewport = null
var _normal_root: Node2D = null
var _shadow_root: Node2D = null
var _shadow_polys: Array = []   # Polygon2D per building, in `_buildings_in_order()` order
var _buildings: Array = []      # BaseMapBuilding, scene order (later = drawn over earlier)
var _dirty: bool = true
var _editor_wait: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_nodes()
	_rebuild()
	_apply_hour()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	# Editor: pick up polygon / height edits.
	_editor_wait -= delta
	if _editor_wait <= 0.0:
		_editor_wait = _EDITOR_REFRESH
		_rebuild()
		_apply_hour()


## Sets the hour now (stops a running `play`).
func set_hour(h: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	hour = fposmod(h, 24.0)


## Runs the clock from `from_h` to `to_h` (may pass 24 — the night of a day change) over
## `time` seconds.
func play(from_h: float, to_h: float, time: float) -> void:
	set_hour(from_h)
	_tween = create_tween()
	_tween.tween_method(_set_hour_wrapped, from_h, to_h, maxf(0.01, time)) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func is_playing() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Jumps a running `play` to its end.
func finish() -> void:
	if is_playing():
		_tween.custom_step(1000.0)


func _set_hour_wrapped(h: float) -> void:
	hour = fposmod(h, 24.0)


# ── Projection ───────────────────────────────────────────────────────────────
## Screen vectors of one ground unit along the world x / y axes.
func ground_axes() -> Array:
	var a: float = deg_to_rad(cam_azimuth_deg)
	var se: float = sin(deg_to_rad(cam_elevation_deg))
	return [Vector2(cos(a), -sin(a) * se), Vector2(sin(a), cos(a) * se)]


## World normal (z = 0) of a wall hanging from a roof edge with screen direction `edge`
## and outward screen normal `out`.
func wall_normal(edge: Vector2, out: Vector2) -> Vector3:
	var axes: Array = ground_axes()
	var u: Vector2 = axes[0]
	var v: Vector2 = axes[1]
	var det: float = u.x * v.y - v.x * u.y
	if absf(det) < 0.0001:
		return Vector3(0, 0, 1)
	# Screen → ground: solve a·u + b·v = edge.
	var w := Vector2((edge.x * v.y - v.x * edge.y) / det, (u.x * edge.y - edge.x * u.y) / det)
	var n := Vector2(w.y, -w.x).normalized()
	if (u * n.x + v * n.y).dot(out) < 0.0:
		n = -n
	return Vector3(n.x, n.y, 0.0)


## World vector towards the sun at hour `h` (z up); z < 0 below the horizon.
func sun_vector(h: float) -> Vector3:
	var t: float = (fposmod(h, 24.0) - SUNRISE) / (SUNSET - SUNRISE)
	var elev: float = sin(clampf(t, 0.0, 1.0) * PI) * deg_to_rad(MAX_SUN_ELEVATION_DEG)
	if t <= 0.0 or t >= 1.0:
		elev = -0.2
	var az: float = deg_to_rad(noon_azimuth_deg) + (clampf(t, 0.0, 1.0) - 0.5) * PI
	return Vector3(cos(az) * cos(elev), sin(az) * cos(elev), sin(elev))


## Screen offset of a shadow per screen pixel of building height (zero at night).
func shadow_per_px(sun: Vector3) -> Vector2:
	if sun.z <= 0.0:
		return Vector2.ZERO
	var axes: Array = ground_axes()
	var hw: float = 1.0 / cos(deg_to_rad(cam_elevation_deg))  # world height per screen px
	var k: float = hw / maxf(sun.z, MIN_SHADOW_SUN_Z)
	var d := Vector2(-sun.x, -sun.y) * k
	var off: Vector2 = (axes[0] as Vector2) * d.x + (axes[1] as Vector2) * d.y
	return off.limit_length(MAX_SHADOW_RATIO)


static func tint_at(h: float) -> Color:
	var hh: float = fposmod(h, 24.0)
	for i in range(1, TINT_KEYS.size()):
		var b: Array = TINT_KEYS[i]
		if hh <= float(b[0]):
			var a: Array = TINT_KEYS[i - 1]
			var f: float = inverse_lerp(float(a[0]), float(b[0]), hh)
			return (a[1] as Color).lerp(b[1] as Color, f)
	return TINT_KEYS[0][1]


# ── Build ────────────────────────────────────────────────────────────────────
## The map picture (`Art`), or null when it is missing or not a TextureRect.
func _art() -> TextureRect:
	return get_parent().get_node_or_null("Art") as TextureRect if get_parent() != null else null


func _map_size() -> Vector2:
	var p: Control = get_parent() as Control
	return p.size if p != null and p.size != Vector2.ZERO else BaseMap.DESIGN_SIZE


## Lit copy of the art + the two views. Not owned → never saved with the scene.
func _build_nodes() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	var art: TextureRect = _art()
	if art != null:
		var lit := TextureRect.new()
		lit.name = "Lit"
		lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lit.set_anchors_preset(Control.PRESET_FULL_RECT)
		lit.texture = art.texture
		lit.expand_mode = art.expand_mode
		lit.stretch_mode = art.stretch_mode
		lit.material = _mat
		add_child(lit)
	elif not Engine.is_editor_hint() and get_parent() != null:
		# Placeholder art that is not a picture (the stadium's ColorRect): light it in place.
		var plain: CanvasItem = get_parent().get_node_or_null("Art") as CanvasItem
		if plain != null:
			plain.material = _mat
			for c in plain.get_children():
				if c is CanvasItem:
					(c as CanvasItem).use_parent_material = true
	var vp_size := Vector2i((_map_size() * RES_SCALE).ceil())
	_normal_vp = _make_view("NormalView", vp_size)
	_normal_root = _normal_vp.get_child(0) as Node2D
	_shadow_vp = _make_view("ShadowView", vp_size)
	_shadow_root = _shadow_vp.get_child(0) as Node2D
	_mat.set_shader_parameter("normal_tex", _normal_vp.get_texture())
	_mat.set_shader_parameter("shadow_tex", _shadow_vp.get_texture())


func _make_view(view_name: String, vp_size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = view_name
	vp.size = vp_size
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var root := Node2D.new()
	root.scale = Vector2.ONE * RES_SCALE
	vp.add_child(root)
	add_child(vp)
	return vp


## The buildings in **scene hierarchy order** — the draw order of the normal view: a later
## sibling's walls and roof cover an earlier one's, so a wall hidden behind a roof in
## front gets that roof's lighting, not its own. Reorder the nodes to fix an overlap.
func _buildings_in_order() -> Array:
	var out: Array = []
	var holder: Node = get_parent().get_node_or_null("Buildings") if get_parent() != null else null
	if holder == null:
		return out
	for c in holder.get_children():
		if c is BaseMapBuilding and (c as BaseMapBuilding).polygon.size() >= 3:
			out.append(c)
	return out


## Redraws both views' polygons from the buildings (normals are static; shadows are
## re-shaped by `_apply_hour`).
func _rebuild() -> void:
	if _normal_root == null:
		return
	_dirty = false
	_buildings = _buildings_in_order()
	for root in [_normal_root, _shadow_root]:
		for c in (root as Node).get_children():
			(root as Node).remove_child(c)
			c.queue_free()
	var full := PackedVector2Array([Vector2.ZERO, Vector2(_map_size().x, 0.0), _map_size(),
			Vector2(0.0, _map_size().y)])
	_add_poly(_normal_root, full, _encode(Vector3(0, 0, 1)))
	_add_poly(_shadow_root, full, Color.BLACK)
	_shadow_polys.clear()
	for raw in _buildings:
		var b: BaseMapBuilding = raw
		_shadow_polys.append(_add_poly(_shadow_root, PackedVector2Array(), Color.WHITE))
		for w in b.walls():
			_add_poly(_normal_root, w["poly"], _encode(wall_normal(w["edge"], w["out"])))
		_add_poly(_normal_root, b.roof(), _encode(Vector3(0, 0, 1)))
	# Faces mask the shadows: a shadow only lies on the ground.
	for raw in _buildings:
		var b2: BaseMapBuilding = raw
		for w in b2.walls():
			_add_poly(_shadow_root, w["poly"], Color.BLACK)
		_add_poly(_shadow_root, b2.roof(), Color.BLACK)
	_normal_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _add_poly(root: Node2D, pts: PackedVector2Array, col: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = col
	p.antialiased = false
	root.add_child(p)
	return p


static func _encode(n: Vector3) -> Color:
	var v: Vector3 = n.normalized() * 0.5 + Vector3(0.5, 0.5, 0.5)
	return Color(v.x, v.y, v.z, 1.0)


func _apply_hour() -> void:
	if _mat == null:
		return
	if _dirty:
		_rebuild()
	var sun: Vector3 = sun_vector(hour)
	var per_px: Vector2 = shadow_per_px(sun)
	for i in _shadow_polys.size():
		(_shadow_polys[i] as Polygon2D).polygon = (_buildings[i] as BaseMapBuilding).shadow(per_px)
	_shadow_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var tint: Color = tint_at(hour)
	_mat.set_shader_parameter("map_size", _map_size())
	_mat.set_shader_parameter("shadow_texel", Vector2.ONE / (_map_size() * RES_SCALE))
	_mat.set_shader_parameter("sun_dir", sun.normalized())
	_mat.set_shader_parameter("sun_vis", smoothstep(0.0, 0.12, sun.z))
	_mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_mat.set_shader_parameter("shadow_strength", shadow_strength)
	_mat.set_shader_parameter("normal_strength", normal_strength)
