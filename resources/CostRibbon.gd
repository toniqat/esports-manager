class_name CostRibbon
extends RefCounted

# **비용**의 모양 — 위에서 아래로 늘어진 세로로 긴 직각사다리꼴 리본. 윗변 ·
# 왼변 · 오른변은 곧고, 아랫변만 비스듬하다: **왼쪽 아래가 더 내려가고** 오른쪽
# 아래가 `slant` 만큼 짧다.
#
#   TL ┌──┐ TR
#      │  │
#      │  ┘ BR   ← h - slant
#   BL └╱       ← h
#
# 비용이 찍히는 자리는 전부 이 도형이다: 카드 왼쪽 위 비용 리본(`Card.gd`, 큰
# 숫자), 설명판 머리줄의 작은 리본(`CardDescBox`), 설명문 안 "비용" 앞
# 아이콘(`StrategyIcon.fill_rich`). **테두리는 어디에도 없다** — 리본은 불투명한
# 흰 알맹이에 어두운 숫자(`INK`) + 아래로 떨어지는 그림자(시전자 초상 리본처럼),
# 설명문 아이콘은 전략 점수 색(`StrategyIcon.COLOR`) 알맹이뿐이다. 설명판 머리줄
# 리본은 구운 텍스처로 그리고 어두운 판에서는 그림자를 뺀다(`make_badge`) — 둘 다
# 작은 크기에서 회색 / 검은 테두리로 읽혔다.

const FILL := Color(1.0, 1.0, 1.0, 1.0)
## 리본 위 숫자 색 — 예전 어두운 리본 알맹이 색(불투명).
const INK := Color(0.08, 0.06, 0.14, 1.0)
## 드롭 섀도 — 리본을 아래로 `SHADOW_STEP` 씩 밀어 옅은 겹을 `SHADOW_LAYERS` 장
## 깐다(셰이더 없는 번짐). 알맹이가 불투명이라 아랫변 밑으로만 보인다.
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.22)
const SHADOW_LAYERS := 4
const SHADOW_STEP := 1.5
## 설명문 인라인 아이콘 색 — 전략 점수 색.
const ICON_COLOR := StrategyIcon.COLOR
## `number_texture` rim width as a fraction of its height.
const NUMBER_RIM_RATIO := 0.07
## 설명문 인라인 아이콘의 폭 / 높이.
const ICON_ASPECT := 0.62
## 아랫변의 기울기 — 높이에 대한 오른쪽 아래가 짧아지는 비율.
const SLANT_RATIO := 0.14
## 설명문 인라인 아이콘은 글자 높이라 같은 비율이면 사각형으로 읽힌다 — 더 기울인다.
const ICON_SLANT_RATIO := 0.30

static var _tex_cache: Dictionary = {}


## `rect` 안의 리본 꼭짓점 4개 — 시계 방향(TL → TR → BR → BL).
static func points(rect: Rect2, slant: float = -1.0) -> PackedVector2Array:
	if slant < 0.0:
		slant = rect.size.y * SLANT_RATIO
	var p := rect.position
	var s := rect.size
	return PackedVector2Array([
		p,
		p + Vector2(s.x, 0.0),
		p + Vector2(s.x, s.y - slant),
		p + Vector2(0.0, s.y),
	])


## 채운 리본 — 같은 색 얇은 선으로 가장자리만 안티앨리어싱한다
## (`draw_colored_polygon` 은 AA 가 없다). `shadow` 면 먼저 아래로 그림자를 깐다.
static func draw(ci: CanvasItem, rect: Rect2, fill: Color = FILL,
		slant: float = -1.0, shadow: bool = false) -> void:
	var pts: PackedVector2Array = points(rect, slant)
	if shadow:
		_draw_shadow(ci, pts)
	ci.draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, fill, 1.0, true)


## 숫자를 얹은 작은 리본 — 설명판 머리줄용. 숫자는 리본 위쪽에 앉는다.
##
## `draw()` 와 달리 같은 색 1px AA 선을 덧그리지 않고 **커버리지 AA 로 구운
## 텍스처**(`fill_texture`)를 붙인다 — 작은 리본에서는 그 선의 페더가 어두운
## 판 위에 회색 테두리로 읽혔다. 그림자(`shadow`)도 어두운 판에서는 아랫변 밑
## 검은 테두리로만 보이므로 밝은 판(아웃게임)에서만 깐다.
static func make_badge(parent: Node, rect: Rect2, text: String, font_size: int,
		text_color: Color = INK, fill: Color = FILL, shadow: bool = true) -> Control:
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = rect.position
	badge.size = rect.size
	badge.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, badge.size)
		if shadow:
			_draw_shadow(badge, points(r))
		# 2배로 구워 줄여 그린다 — 스트레치 배율이 1 을 넘는 기기에서도 가장자리가 무르지 않다.
		badge.draw_texture_rect(fill_texture(int(ceil(r.size.x * 2.0)),
				int(ceil(r.size.y * 2.0)), fill, r.size.y * 2.0 * SLANT_RATIO), r, false))
	parent.add_child(badge)
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", text_color)
	badge.add_child(lbl)
	lbl.position = Vector2.ZERO
	# 비스듬한 아랫변 위쪽 — 숫자가 짧은 오른쪽 아래에 걸치지 않게.
	lbl.size = Vector2(rect.size.x, rect.size.y * (1.0 - SLANT_RATIO))
	return badge


## 리본을 아래로 `SHADOW_STEP` 씩 민 옅은 겹 `SHADOW_LAYERS` 장.
static func _draw_shadow(ci: CanvasItem, pts: PackedVector2Array) -> void:
	for i in SHADOW_LAYERS:
		var off := Vector2(0.0, SHADOW_STEP * float(i + 1))
		var sh := PackedVector2Array()
		for v in pts:
			sh.append(v + off)
		ci.draw_colored_polygon(sh, SHADOW_COLOR)


## `w`×`h` 픽셀 리본 텍스처 — 전략 점수 색 알맹이, 테두리 없음. 설명문 인라인 아이콘용.
static func icon_texture(w: int, h: int) -> Texture2D:
	return fill_texture(w, h, ICON_COLOR, float(h) * ICON_SLANT_RATIO)


static var _num_cache: Dictionary = {}


## A `w`×`h` px ribbon with `text` (the cost) on it, as a texture — the card face's
## cost ribbon in miniature (white `FILL`, `INK` number and a thin `INK` rim so
## it still reads on the white outgame panels; no shadow).
## `RichTextLabel.add_image` only takes textures, so the label is rendered once by
## a cached `SubViewport` (`UPDATE_ONCE`) parked under the SceneTree root. The
## texture fills in on the first frame after the call. Callers pass 2x pixel
## sizes and draw at 1x, like the other inline icons.
static func number_texture(text: String, w: int, h: int) -> Texture2D:
	w = maxi(1, w)
	h = maxi(1, h)
	var key: String = "%s:%dx%d" % [text, w, h]
	if _num_cache.has(key):
		var cached: SubViewport = _num_cache[key] as SubViewport
		if is_instance_valid(cached):
			return cached.get_texture()
		_num_cache.erase(key)
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := TextureRect.new()
	var pts: PackedVector2Array = points(Rect2(0.0, 0.0, float(w), float(h)),
			float(h) * SLANT_RATIO)
	bg.texture = StrategyIcon.raster_convex(w, h, pts, FILL, INK,
			maxf(1.5, float(h) * NUMBER_RIM_RATIO))
	bg.position = Vector2.ZERO
	bg.size = Vector2(w, h)
	vp.add_child(bg)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", maxi(1, int(round(float(h) * 0.62))))
	lbl.add_theme_color_override("font_color", INK)
	vp.add_child(lbl)
	lbl.position = Vector2.ZERO
	# Above the slanted bottom edge — same as `make_badge`.
	lbl.size = Vector2(float(w), float(h) * (1.0 - SLANT_RATIO))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		# Deferred: the root may be busy setting up children when this is called.
		tree.root.call_deferred("add_child", vp)
	_num_cache[key] = vp
	return vp.get_texture()


## `w`×`h` 픽셀 단색 리본 텍스처 — 테두리 없이 가장자리 커버리지만 1px AA.
static func fill_texture(w: int, h: int, fill: Color, slant: float) -> Texture2D:
	w = maxi(1, w)
	h = maxi(1, h)
	var key: String = "%dx%d:%s:%.2f" % [w, h, fill.to_html(), slant]
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var pts: PackedVector2Array = points(Rect2(0.0, 0.0, float(w), float(h)), slant)
	var tex := StrategyIcon.raster_convex(w, h, pts, fill, fill, 0.0)
	_tex_cache[key] = tex
	return tex
