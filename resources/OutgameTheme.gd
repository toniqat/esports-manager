class_name OutgameTheme
extends RefCounted

# ── 아웃게임 흰 배경 팔레트 ────────────────────────────────────────────────
#
# **아웃게임 화면의 모든 색이 여기를 지난다.** 시즌 허브 · 기자회견 · 훈련판 ·
# 시간 경과 · 순위 · 브래킷 · 드래프트가 같은 표를 읽는다 — 화면마다 자기
# `Color(...)` 리터럴을 들고 있으면 같은 카드가 화면마다 다른 회색으로 그려지고,
# 팔레트를 한 번 손보는 일이 파일 열몇 개를 훑는 일이 된다.
#
# 참고 디자인은 `docs/ref_image.jpg` — **하얀 종이 위에 색이 있는 카드**다.
# 규칙 셋으로 요약된다:
#   1. 바탕은 흰색(`BG`), 내용은 그보다 **더 흰** 카드(`SURFACE`) 위에 얹는다.
#      경계는 선이 아니라 **그림자와 밝기 차이**가 만든다(`BORDER` 는 아주 옅다).
#   2. 강조는 색면 하나(`ACCENT`)로만 한다 — 지금 어느 요일인가, 지금 누를
#      버튼은 무엇인가.
#   3. 분류는 **카드 왼쪽의 색 띠 또는 카드 자체의 색면**(`CARD_TINTS`)이 한다.
#      역할 색 다섯(`ROLE_COLORS`)도 그 자리에서만 쓴다.
#
# 인게임(BattleSim)은 이 표를 쓰지 않는다 — 전장은 어두운 화면이고 거기서
# 흰 카드는 눈부신 판이 된다.

# ── 바탕과 면 ────────────────────────────────────────────────────────────────
const BG:            Color = Color(0.960, 0.960, 0.968, 1.0)   # 화면 바탕
const SURFACE:       Color = Color(1.000, 1.000, 1.000, 1.0)   # 카드 · 패널
const SURFACE_SUNK:  Color = Color(0.929, 0.933, 0.945, 1.0)   # 눌린 자리 · 빈 칸
const RAIL:          Color = Color(0.110, 0.110, 0.122, 1.0)   # 좌측 요일 레일
const RAIL_TEXT:     Color = Color(0.620, 0.620, 0.650, 1.0)

# ── 글자 ─────────────────────────────────────────────────────────────────────
const TEXT:          Color = Color(0.110, 0.110, 0.122, 1.0)   # 본문 · 제목
const TEXT_SUB:      Color = Color(0.541, 0.541, 0.569, 1.0)   # 부제 · 라벨
const TEXT_FAINT:    Color = Color(0.722, 0.722, 0.749, 1.0)   # 비활성 · 자리표시
const TEXT_ON_FILL:  Color = Color(1.000, 1.000, 1.000, 1.0)   # 색면 위 글자

# ── 강조 ─────────────────────────────────────────────────────────────────────
const ACCENT:        Color = Color(0.961, 0.651, 0.137, 1.0)   # 앰버
const ACCENT_DIM:    Color = Color(0.996, 0.929, 0.808, 1.0)   # 앰버 배경 틴트
## 흰 바탕 위의 앰버 **글자**. `ACCENT` 를 글자에 그대로 쓰면 흰 종이에서
## 대비가 모자라 안 읽힌다. `ACCENT.darkened(0.2)` 와 같은 값을 리터럴로
## 둔 것은 `darkened()` 가 상수식이 아니라 `const` 자리에서 못 쓰이기 때문이다.
const ACCENT_TEXT:   Color = Color(0.769, 0.521, 0.110, 1.0)
const LINK:          Color = Color(0.180, 0.400, 0.918, 1.0)

# ── 의미색 ───────────────────────────────────────────────────────────────────
const POSITIVE:      Color = Color(0.130, 0.680, 0.380, 1.0)   # 상승 · 승리
const NEGATIVE:      Color = Color(0.878, 0.271, 0.271, 1.0)   # 하락 · 패배
const NEUTRAL:       Color = Color(0.620, 0.620, 0.650, 1.0)   # 변화 없음

# ── 선 ───────────────────────────────────────────────────────────────────────
const BORDER:        Color = Color(0.886, 0.890, 0.906, 1.0)
const BORDER_STRONG: Color = Color(0.780, 0.784, 0.808, 1.0)
const SHADOW:        Color = Color(0.110, 0.110, 0.180, 0.10)

# ── 카드 색면 (ref_image 의 카드 네 장) ──────────────────────────────────────
## 분류가 필요한 카드가 순서대로 집어 쓴다. 채도가 비슷해야 한 화면에서
## 어느 하나가 먼저 튀지 않는다.
const CARD_TINTS: Array = [
	Color(0.290, 0.760, 0.780, 1.0),   # 청록
	Color(0.960, 0.475, 0.231, 1.0),   # 주황
	Color(0.608, 0.349, 0.816, 1.0),   # 보라
	Color(0.259, 0.522, 0.957, 1.0),   # 파랑
	Color(0.180, 0.702, 0.443, 1.0),   # 초록
]

## 역할 다섯의 색. 순서는 `GameEnums.Role`(TANK · FIGHTER · ASSASSIN ·
## SUPPORT · SNIPER)이고 **자리 순서가 아니다** — 화면은 `ROLE_DISPLAY_ORDER`
## 로 자리를 잡고 색은 그 자리에 앉은 역할 번호로 집는다.
const ROLE_COLORS: Array = [
	Color(0.180, 0.451, 0.898, 1.0),   # TANK     파랑
	Color(0.937, 0.478, 0.145, 1.0),   # FIGHTER  주황
	Color(0.573, 0.322, 0.847, 1.0),   # ASSASSIN 보라
	Color(0.145, 0.671, 0.400, 1.0),   # SUPPORT  초록
	Color(0.867, 0.235, 0.294, 1.0),   # SNIPER   빨강
]
## 역할 이름도 같은 순서. 예전 화면들이 각자 들고 있던 `ROLE_NAMES` 자리.
const ROLE_NAMES: Array = ["탱커", "격투", "암살", "서폿", "원딜"]

# ── 요일 ─────────────────────────────────────────────────────────────────────
const DAY_LETTERS: Array = ["월", "화", "수", "목", "금", "토", "일"]
const DAY_NAMES:   Array = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"]


# ── StyleBox 공장 ────────────────────────────────────────────────────────────

## 카드 한 장. `tint` 를 주면 그 색으로 꽉 찬 색면 카드가, 안 주면 흰 카드가 된다.
static func card_style(radius: int = 18, tint: Variant = null,
		with_shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if tint is Color:
		sb.bg_color = tint
	else:
		sb.bg_color = SURFACE
		sb.border_color = BORDER
		sb.set_border_width_all(1)
	set_corner_radius(sb, radius)
	if with_shadow:
		sb.shadow_color = SHADOW
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
	return sb


## 테두리만 있는 판 (그림자 없음) — 표 · 격자처럼 여러 장이 붙어 서는 자리.
static func flat_style(bg: Color, radius: int = 12,
		border: Variant = null, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border is Color:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	set_corner_radius(sb, radius)
	return sb


## 카드 왼쪽에 색 띠 하나를 세운 카드 — 분류는 있지만 색면까지 칠하면
## 글자가 안 읽히는 자리(순위표 한 줄, 훈련 결과 한 줄).
static func lead_bar_style(bar: Color, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.border_color = bar
	sb.border_width_left = 6
	set_corner_radius(sb, radius)
	sb.shadow_color = SHADOW
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func set_corner_radius(sb: StyleBoxFlat, r: int) -> void:
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r


# ── 버튼 ─────────────────────────────────────────────────────────────────────

## 화면의 주된 행동 한 개 — 앰버 색면 + 흰 글자. 한 화면에 하나만 둔다.
##
## **감촉은 여기서 정하지 않는다.** 한때는 버튼의 색을 고르는 자리가 곧 그
## 감촉의 세기를 고르는 자리여서 이 네 함수가 `HapticUi.kind` 를 적었지만(primary
## · dark = MEDIUM / ghost = LIGHT / text = SELECT), 그 표는 폐기됐다 — 지금은
## 모든 버튼이 종류와 무관하게 같은 두 박자(누름 LIGHT → 뗌 SOFT)를 낸다.
## 무게는 화면이 말하고, 손에 오는 것은 눌렸다는 사실 하나다. `autoloads/HapticUi.gd`.
static func style_primary_button(b: Button, font_size: int = 34) -> Button:
	return _style_button(b, font_size, ACCENT, TEXT_ON_FILL,
			ACCENT.lightened(0.10), ACCENT.darkened(0.12), null)


## 그 밖의 행동 — 흰 바탕 + 옅은 테두리.
static func style_ghost_button(b: Button, font_size: int = 30) -> Button:
	return _style_button(b, font_size, SURFACE, TEXT,
			SURFACE_SUNK, BORDER_STRONG, BORDER)


## 되돌아가는 행동 — 바탕 없이 글자만.
static func style_text_button(b: Button, font_size: int = 26) -> Button:
	return _style_button(b, font_size, Color(1, 1, 1, 0), TEXT_SUB,
			Color(0, 0, 0, 0.04), Color(0, 0, 0, 0.08), null)


## 어두운 색면 — 경기 시작처럼 "지금 이 화면을 떠난다"는 행동.
static func style_dark_button(b: Button, font_size: int = 34) -> Button:
	return _style_button(b, font_size, RAIL, TEXT_ON_FILL,
			RAIL.lightened(0.12), RAIL.lightened(0.22), null)


static func _style_button(b: Button, font_size: int, bg: Color, fg: Color,
		hover: Color, pressed: Color, border: Variant) -> Button:
	if b == null:
		return b
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	b.add_theme_stylebox_override("normal",   _btn_box(bg, border))
	b.add_theme_stylebox_override("hover",    _btn_box(hover, border))
	b.add_theme_stylebox_override("pressed",  _btn_box(pressed, border))
	b.add_theme_stylebox_override("focus",    _btn_box(Color(0, 0, 0, 0), null))
	b.add_theme_stylebox_override("disabled", _btn_box(SURFACE_SUNK, BORDER))
	return b


static func _btn_box(bg: Color, border: Variant) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border is Color:
		sb.border_color = border
		sb.set_border_width_all(1)
	set_corner_radius(sb, 16)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


# ── 하단 액션 바 ─────────────────────────────────────────────────────────────
#
# **아웃게임 화면의 주된 행동은 화면 한가운데 떠 있는 도형이 아니라 하단
# 구간 전체다.** 좌우 여백 없이 화면 끝에서 끝까지, 아래는 안전선에 밀착하고
# 모서리는 각지게 — 그래서 바가 화면의 한 구획이 되고 "여기 아래는 전부 이
# 행동"이 자리만으로 읽힌다. 버튼이 여럿이면 그 구간을 **무게 비율대로**
# 나눠 갖는다(주 행동 2 : 보조 1) — 무엇이 주 행동인지가 색뿐 아니라 폭으로도
# 읽혀야 하기 때문이다.
#
# **색면은 안전선 아래까지 내려간다.** 홈 인디케이터 / 제스처 바 자리를 비워
# 두면 바 밑에 배경색 띠가 한 줄 남아 바가 화면에서 떠 보인다. 그래서 버튼
# 사각형은 뷰포트 바닥까지 늘리되 **글자는 안전선 위에 남긴다** —
# `content_margin_bottom` 에 인셋을 얹으면 Button 이 글자를 그 안쪽 사각형
# 한가운데에 놓으므로, 눌리는 자리와 읽히는 자리가 둘 다 안전 영역 안이다.
#
# 화면은 `bottom_bar_top()` 하나만 알면 된다 — 본문 높이를 그 값에서 역산하면
# 바가 기기마다 오르내려도 내용이 그 밑에 깔리지 않는다.

## 바의 높이(안전 영역 안쪽 기준). 아래 인셋은 여기에 포함되지 않는다 —
## 그것은 글자가 아니라 색면만 내려가는 몫이다.
const BOTTOM_BAR_H: float = 128.0

## 구간 사이의 실선. ghost 버튼은 자기 테두리가 이미 경계를 만들지만
## primary · dark 끼리 붙으면 그 자리가 통짜 색면이 된다.
const BOTTOM_BAR_SEP: Color = Color(0.110, 0.110, 0.122, 0.14)


## **본문이 끝나야 하는 y.** 화면째 `indent_to_safe_top` 으로 내려놓은
## 좌표계 기준이라 `bottom_y()` 가 아니라 `safe_h()` 에서 뺀다.
static func bottom_bar_top() -> float:
	return ScreenMetrics.safe_h() - BOTTOM_BAR_H


## 하단 바 한 줄을 세운다. `specs` 는 왼쪽부터의 구간 목록이고 한 칸은
## `{text, style, weight, font}` — `style` 은 `"primary"`(기본) / `"ghost"` /
## `"dark"` / `"text"`, `weight` 는 구간 폭의 비(기본 1), `font` 는 글자 크기.
## 주 행동은 **오른쪽 끝**에 둔다(엄지가 닿는 자리이고, 훑는 눈이 마지막에
## 멎는 자리다).
##
## 돌려주는 것은 만든 `Button` 배열이다. 상태에 따라 구간이 접히는 화면
## (드래프트의 "뒤로")은 `visible` 을 끄고 `layout_bottom_bar` 를 다시 부른다.
static func add_bottom_bar(parent: Control, specs: Array) -> Array:
	var out: Array = []
	for s_raw in specs:
		var s: Dictionary = s_raw
		var b := Button.new()
		b.text = String(s.get("text", ""))
		b.focus_mode = Control.FOCUS_NONE
		style_bottom_button(b, String(s.get("style", "primary")),
				int(s.get("font", 34)))
		parent.add_child(b)
		out.append(b)
		if out.size() < specs.size():
			var sep := ColorRect.new()
			sep.color = BOTTOM_BAR_SEP
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(sep)
	layout_bottom_bar(out, specs)
	return out


## 보이는 구간만 무게 비율대로 다시 늘어놓는다. 마지막 구간의 오른쪽 끝은
## 반올림 잔차 없이 화면 끝에 정확히 닿는다 — 1px 이라도 남으면 그 틈으로
## 배경이 비쳐 바가 두 조각으로 보인다.
static func layout_bottom_bar(buttons: Array, specs: Array) -> void:
	var vp_w: float = ScreenMetrics.vp_w()
	var top: float = bottom_bar_top()
	var below: float = maxf(0.0, ScreenMetrics.insets().w)
	var total: float = 0.0
	for i in buttons.size():
		if (buttons[i] as Button).visible:
			total += _bar_weight(specs, i)
	if total <= 0.0:
		return

	var x: float = 0.0
	var used: float = 0.0
	var last: int = -1
	for i in buttons.size():
		if (buttons[i] as Button).visible:
			last = i
	for i in buttons.size():
		var b: Button = buttons[i]
		if not b.visible:
			continue
		var w: float = vp_w - used if i == last \
				else floorf(vp_w * _bar_weight(specs, i) / total)
		b.position = Vector2(x, top)
		b.size     = Vector2(w, BOTTOM_BAR_H + below)
		for c in b.get_children():
			var sep := c as ColorRect
			if sep != null:
				# 구분선은 그 구간의 **오른쪽** 끝에 선다. 마지막 구간은
				# 화면 끝이라 선을 세우면 바깥 테두리가 된다.
				sep.visible = i != last
				sep.position = Vector2(w - 2.0, 0.0)
				sep.size     = Vector2(2.0, BOTTOM_BAR_H + below)
		x   += w
		used += w


static func _bar_weight(specs: Array, i: int) -> float:
	if i < 0 or i >= specs.size():
		return 1.0
	return maxf(0.01, float((specs[i] as Dictionary).get("weight", 1.0)))


## 바 한 칸의 옷을 입힌다 — 색을 고르고, 모서리를 각지게 펴고, 안전선 아래로
## 내려간 몫만큼 글자를 위로 물린다. 스타일박스는 `_btn_box` 가 호출마다 새로
## 만든 것이라 여기서 고쳐도 다른 버튼에 번지지 않는다.
##
## **바뀌는 버튼은 이 함수를 다시 부른다** — `style_primary_button` 을 직접
## 부르면 둥근 모서리가 되살아나 그 칸만 화면에서 도로 떠오른다(시간 경과
## 화면의 "경기 시작"이 그렇게 바뀐다).
static func style_bottom_button(b: Button, style: String = "primary",
		font_size: int = 34) -> Button:
	if b == null:
		return b
	match style:
		"ghost": style_ghost_button(b, font_size)
		"dark":  style_dark_button(b, font_size)
		"text":  style_text_button(b, font_size)
		_:       style_primary_button(b, font_size)
	var below: float = maxf(0.0, ScreenMetrics.insets().w)
	for n in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := b.get_theme_stylebox(n) as StyleBoxFlat
		if sb == null:
			continue
		set_corner_radius(sb, 0)
		sb.content_margin_bottom = 8.0 + below
	return b


# ── 자주 쓰는 조각 ───────────────────────────────────────────────────────────

## 화면 바탕 한 장. `_build()` 첫 줄에서 부른다 —
## `ScreenMetrics.extend_background` 까지 여기서 해 주므로 노치 자리에
## 엔진 기본 회색이 남는 사고를 화면마다 다시 막을 필요가 없다.
static func add_background(parent: Control, color: Color = BG) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ScreenMetrics.extend_background(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg


## 카드 판 한 장을 붙인다. 반환값은 그 `Panel` 이라 자식은 로컬 좌표로 얹는다.
static func add_card(parent: Control, pos: Vector2, sz: Vector2,
		radius: int = 18, tint: Variant = null) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", card_style(radius, tint))
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


## 가로 구분선.
static func add_divider(parent: Control, pos: Vector2, w: float,
		color: Color = BORDER) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = Vector2(w, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## 원형으로 잘린 초상화.
##
## **`clip_contents` 로는 못 만든다** — 그것은 Control 의 사각 rect 로 자르지
## StyleBox 의 모서리 반지름으로 자르지 않는다. `Panel`(radius = 지름/2) 안에
## `TextureRect` 를 넣어 봐야 텍스처가 둥근 모서리를 그대로 덮어 **모서리만 살짝
## 둥근 사각형**이 나온다(실측). 그래서 텍스처를 입힌 **원형 폴리곤**을 직접
## 그린다 — `draw_colored_polygon(points, WHITE, uvs, tex)`.
##
## UV 는 `KEEP_ASPECT_COVERED` 와 같게 잡는다: 짧은 쪽을 꽉 채우고 긴 쪽은
## 가운데를 잘라 낸다. 그래야 정사각이 아닌 컷을 넘겨도 얼굴이 안 늘어난다.
##
## 반환값은 자식을 얹어도 되는 `Control` 이다 — Control 의 `_draw` 는 자식보다
## **먼저** 나가므로 원이 배경, 자식이 그 위다.
static func add_round_portrait(parent: Control, tex: Texture2D,
		pos: Vector2, diameter: float,
		ring: Variant = null) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = Vector2(diameter, diameter)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	holder.draw.connect(_draw_round_portrait.bind(holder, tex, diameter, ring))
	return holder


static func _draw_round_portrait(node: Control, tex: Texture2D,
		diameter: float, ring: Variant) -> void:
	const SEGMENTS: int = 48
	var r: float = diameter * 0.5
	var centre := Vector2(r, r)
	node.draw_circle(centre, r, SURFACE_SUNK)
	if tex != null:
		var ts: Vector2 = tex.get_size()
		# cover: 짧은 축을 1.0 으로, 긴 축은 그 비율만큼 가운데를 쓴다.
		var scale_uv := Vector2(1.0, 1.0)
		if ts.x > 0.0 and ts.y > 0.0:
			if ts.x > ts.y:
				scale_uv.x = ts.y / ts.x
			else:
				scale_uv.y = ts.x / ts.y
		var origin := (Vector2.ONE - scale_uv) * 0.5
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in SEGMENTS:
			var a: float = TAU * float(i) / float(SEGMENTS)
			var off := Vector2(cos(a), sin(a)) * r
			pts.append(centre + off)
			uvs.append(origin + (centre + off) / diameter * scale_uv)
		node.draw_colored_polygon(pts, Color(1, 1, 1), uvs, tex)
	if ring is Color:
		node.draw_arc(centre, r - 1.5, 0.0, TAU, SEGMENTS, ring, 3.0, true)


## 작은 알약형 칩 (`3승 1패`, `T01`, `+2` 같은 것).
static func add_chip(parent: Control, text: String, pos: Vector2,
		sz: Vector2, bg: Color, fg: Color, font_size: int = 20) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", flat_style(bg, int(sz.y * 0.5)))
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var l := UiHelpers.mk_label(p, text, font_size, fg,
			Vector2(0, 0), sz, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return p


## 스크롤 컨테이너 한 장 — 세로만 스크롤. 반환값은
## `{scroll: ScrollContainer, body: Control}` 이고 내용은 `body` 에 절대
## 좌표로 얹은 뒤 `body.custom_minimum_size.y` 로 높이를 알려 준다.
static func add_vscroll(parent: Control, pos: Vector2, sz: Vector2) -> Dictionary:
	var sc := ScrollContainer.new()
	sc.position = pos
	sc.size = sz
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(sc)
	var body := Control.new()
	body.custom_minimum_size = Vector2(sz.x, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	return {"scroll": sc, "body": body}
