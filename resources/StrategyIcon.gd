class_name StrategyIcon
extends RefCounted

# 전략 점수의 **모양** — 정팔각형. 두 가지 자세가 있다:
#   • 위아래가 뾰족한 자세(`flat = false`) — 양 팀 게이지(`CostDonut`) 전용.
#     꼭짓점 0 이 12시 방향이고 시계 방향으로 45° 씩 돌므로 면 0 은 **우측 상단
#     면**(12시 → 1시 반)이고, 게이지가 그 면부터 차오른다.
#   • 윗변 · 아랫변이 평평한 자세(`flat = true`) — **점수 인디케이터**. 작은 크기
#     에서 뾰족한 자세는 원처럼 읽혀서, 설명문 안의 "전략 점수" 아이콘이 이쪽을
#     쓴다. 검은 알맹이 + 두꺼운 파란 테두리.
#
# 설명문 안의 "비용" 앞 아이콘(세로로 긴 직각사다리꼴)은 `CostRibbon` 이 정의하고,
# 두 아이콘을 설명문에 끼워 넣는 일(`fill_rich`)은 여기서 한다.

const SIDES := 8
## 기본 배지 · 테두리 색. 플레이어 게이지(`HudBuilder.DONUT_FILL_PLAYER`)와 같다.
const COLOR := Color(0.25, 0.60, 1.00)
## 인디케이터 알맹이 색.
const INDICATOR_FILL := Color(0.02, 0.02, 0.04, 1.0)
## 인디케이터 테두리 두께 — 꼭짓점 반지름에 대한 비율(아이콘 크기에 따라 같이 큰다).
const INDICATOR_RIM_RATIO := 0.26
const KEYWORD := "전략 점수"
const COST_KEYWORD := "비용"
const NBSP := "\u00a0"

static var _tex_cache: Dictionary = {}


## 중심 `c`, 꼭짓점 반지름 `r` 의 팔각형 꼭짓점 8개 — 시계 방향. `flat` 이면
## 22.5° 돌려 윗변 · 아랫변이 평평하다.
static func points(c: Vector2, r: float, flat: bool = false) -> PackedVector2Array:
	var out := PackedVector2Array()
	var start: float = -PI * 0.5 + (PI / float(SIDES) if flat else 0.0)
	for i in SIDES:
		var a: float = start + TAU * float(i) / float(SIDES)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## 채운 팔각형. `rim_w > 0` 이면 테두리를 두르고, 아니면 같은 색 얇은 선으로
## 가장자리만 안티앨리어싱한다(`draw_colored_polygon` 은 AA 가 없다).
static func draw(ci: CanvasItem, c: Vector2, r: float, fill: Color,
		rim: Color = Color(0, 0, 0, 0), rim_w: float = 0.0, flat: bool = false) -> void:
	var pts: PackedVector2Array = points(c, r, flat)
	ci.draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	if rim_w > 0.0:
		ci.draw_polyline(loop, rim, rim_w, true)
	else:
		ci.draw_polyline(loop, fill, 1.0, true)


## 숫자를 얹은 팔각형 배지 — `parent` 안의 `center` 에 반지름 `r` 로 선다.
static func make_badge(parent: Node, center: Vector2, r: float, fill: Color,
		text: String, font_size: int, text_color: Color,
		rim: Color = Color(0, 0, 0, 0), rim_w: float = 0.0) -> Control:
	var badge := Control.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = center - Vector2(r, r)
	badge.size = Vector2(r, r) * 2.0
	badge.draw.connect(func() -> void:
		draw(badge, badge.size * 0.5, r, fill, rim, rim_w))
	parent.add_child(badge)
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", text_color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	badge.add_child(lbl)
	lbl.position = Vector2.ZERO
	lbl.size = badge.size
	return badge


## `px` 픽셀 정사각형 안에 꽉 찬 인디케이터 텍스처(평평한 윗변 · 검은 알맹이 ·
## 두꺼운 파란 테두리). 설명문 인라인 아이콘용.
static func texture(px: int) -> Texture2D:
	var key: String = "oct:%d" % px
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var r: float = float(px) * 0.5
	# 평평한 자세는 변까지 거리(내접원)가 r·cos(22.5°) 라 윗변이 텍스처 끝에
	# 닿지 않는다 — 꼭짓점 반지름을 키워 윗변 · 옆변이 정사각형을 꽉 채우게 한다.
	var vr: float = r / cos(PI / float(SIDES))
	var pts: PackedVector2Array = points(Vector2(r, r), vr, true)
	var tex := raster_convex(px, px, pts, INDICATOR_FILL, COLOR,
			float(px) * 0.5 * INDICATOR_RIM_RATIO)
	_tex_cache[key] = tex
	return tex


## 볼록 다각형 `pts`(시계 방향, 픽셀 좌표)를 `w`×`h` 텍스처로 굽는다 — 알맹이
## `fill`, 안쪽으로 `rim_w` 두께의 테두리 `rim`. 가장자리는 1px 로 안티앨리어싱.
## 변마다 바깥 법선과의 내적 최댓값이 볼록 다각형의 부호 거리다.
static func raster_convex(w: int, h: int, pts: PackedVector2Array, fill: Color,
		rim: Color, rim_w: float) -> Texture2D:
	var n: int = pts.size()
	var normals: Array[Vector2] = []
	var offsets: Array[float] = []
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		# 시계 방향(y 아래) 다각형의 바깥 법선은 변 방향을 반시계로 90° 돌린 것.
		var nrm: Vector2 = Vector2(b.y - a.y, a.x - b.x).normalized()
		normals.append(nrm)
		offsets.append(nrm.dot(a))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = -INF
			for i in n:
				d = maxf(d, normals[i].dot(p) - offsets[i])
			var cov: float = clampf(0.5 - d, 0.0, 1.0)
			if cov <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rim_t: float = clampf(d + rim_w + 0.5, 0.0, 1.0)
			var col: Color = fill.lerp(rim, rim_t)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * cov))
	return ImageTexture.create_from_image(img)


## 카드 설명문을 `RichTextLabel` 로 — "전략 점수" 앞마다 팔각형 인디케이터,
## "비용" 앞마다 비용 리본(`CostRibbon`)을 끼운다. BBCode 를 쓰지 않고
## `add_text` / `add_image` 로 쌓으므로 설명문의 `[캐시]` 같은 대괄호가 태그로
## 먹히지 않는다.
static func fill_rich(rtl: RichTextLabel, text: String, font_size: int) -> void:
	rtl.clear()
	var icon_px: int = int(round(float(font_size) * 1.1))
	var rib_h: int = int(round(float(font_size) * 1.2))
	var rib_w: int = int(round(float(rib_h) * CostRibbon.ICON_ASPECT))
	var rest: String = text
	while true:
		var i_s: int = rest.find(KEYWORD)
		var i_c: int = rest.find(COST_KEYWORD)
		if i_s < 0 and i_c < 0:
			break
		var is_cost: bool = i_s < 0 or (i_c >= 0 and i_c < i_s)
		var at: int = i_c if is_cost else i_s
		var kw: String = COST_KEYWORD if is_cost else KEYWORD
		rtl.add_text(UiHelpers.keep_words(rest.substr(0, at)))
		if is_cost:
			rtl.add_image(CostRibbon.icon_texture(rib_w * 2, rib_h * 2), rib_w, rib_h,
					Color.WHITE, INLINE_ALIGNMENT_CENTER)
		else:
			rtl.add_image(texture(icon_px * 2), icon_px, icon_px, Color.WHITE,
					INLINE_ALIGNMENT_CENTER)
		# 줄 안 끊김 공백 — 아이콘과 그 낱말이 다른 줄로 갈리지 않는다.
		rtl.add_text(NBSP + UiHelpers.keep_words(kw))
		rest = rest.substr(at + kw.length())
	rtl.add_text(UiHelpers.keep_words(rest))


## `fill_rich` 로 채운 설명 라벨 하나. 크기는 부르는 쪽이 정한다.
static func make_rich_label(text: String, font_size: int, color: Color) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.scroll_active = false
	# 인라인 이미지가 낀 줄은 RichTextLabel 의 줄바꿈 폭 계산이 몇 px 어긋나
	# 마지막 글자가 rect 경계에서 잘린다 — 판의 여백 안이므로 잘라내지 않는다.
	rtl.clip_contents = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", font_size)
	rtl.add_theme_color_override("default_color", color)
	rtl.add_theme_constant_override("line_separation", 0)
	fill_rich(rtl, text, font_size)
	return rtl


## 높이 측정용 대역 문자열 — 아이콘 한 개가 차지하는 폭을 글자로 친다(팔각형 두
## 개, 리본 한 개). `get_multiline_string_size` 는 이미지를 모르므로, 아이콘이
## 들어간 줄이 접히는 자리를 맞추려면 그만큼의 폭을 미리 넣어 재야 한다. 줄바꿈
## 규칙(`keep_words` · 줄 안 끊김 공백)도 `fill_rich` 와 같아야 한다.
static func measure_text(text: String) -> String:
	var t: String = (text.replace(KEYWORD, "\u0001" + NBSP + KEYWORD)
			.replace(COST_KEYWORD, "\u0002" + NBSP + COST_KEYWORD))
	return UiHelpers.keep_words(t).replace("\u0001", "00").replace("\u0002", "0")
