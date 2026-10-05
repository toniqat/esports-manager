class_name SkillBadge
extends Control

# 파일럿 스킬 원형 배지 — 아군 스트립 초상 원의 **오른쪽 아래**에 걸친다
# (`PilotStrip._build_cell`). 한 장이 스킬 상태를 전부 말한다:
#
#   • 아이콘 — `SkillImages.icon_for`(흰 글리프). 쓸 수 없으면 **아이콘만** 딤드,
#     원 바탕은 그대로다.
#   • 쿨타임 — 위쪽에서 시계방향으로 **밝은 부채꼴이 차오른다**(나머지는 딤드).
#     가운데에 남은 턴. 준비되면 숫자 없이 아이콘 전체가 밝다.
#   • 스택(충전식 · 토큰 패시브) — 테두리를 최대 스택 수만큼 칸으로 갈라 채운
#     만큼 칠한다. 최대가 `STACK_SEGMENT_MAX` 를 넘으면 칸 없이 연속 호로 채우고
#     가운데에 스택 수를 찍는다(100칸은 칸이 읽히지 않는다).
#   • 그 밖(쿨타임 · 토큰 없는 패시브) — 팀색 얇은 테두리만.
#
# 그리기는 전부 `_draw` 이고 숫자만 자식 `Label` 이다(자식은 `_draw` 위에 그려진다).
# 부채꼴은 셰이더가 아니라 **아이콘 사각형과 교차시킨 다각형에 텍스처 UV** 를
# 붙여 그린다 — 밝은 쪽 / 어두운 쪽 두 장이 겹치지 않아 경계에 알파가 쌓이지 않는다.

const BG_COLOR := Color(0.03, 0.04, 0.08, 0.92)
const ICON_LIT := Color(1.0, 0.96, 0.86)
const ICON_DIM := Color(0.36, 0.37, 0.42)
const STACK_ON := Color(1.0, 0.84, 0.32)
const STACK_OFF := Color(1.0, 1.0, 1.0, 0.18)
const NUMBER_COLOR := Color(1.0, 1.0, 1.0)
const NUMBER_OUTLINE := Color(0, 0, 0, 0.95)
## 이 수까지는 테두리를 칸으로 가르고, 넘으면 연속 호 + 가운데 숫자.
const STACK_SEGMENT_MAX: int = 10
## 테두리 두께 = 반지름 × 이 값.
const RING_W_RATIO: float = 0.16
## 아이콘 사각형 한 변 = 테두리 안쪽 반지름 × 이 값.
const ICON_SIDE_RATIO: float = 1.45
const ARC_POINTS: int = 48

var _icon: Texture2D = null
## 밝은 부채꼴의 비율 0..1(위쪽에서 시계방향). 1 = 전부 밝음, 0 = 전부 딤드.
var _lit: float = 1.0
var _stack_max: int = 0
var _stack: int = 0
var _rim: Color = Color.WHITE
var _num: Label = null


func setup(diameter: float, rim_color: Color) -> void:
	size = Vector2(diameter, diameter)
	_rim = rim_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_num = Label.new()
	_num.add_theme_font_size_override("font_size", maxi(10, int(round(diameter * 0.46))))
	_num.add_theme_color_override("font_color", NUMBER_COLOR)
	_num.add_theme_color_override("font_outline_color", NUMBER_OUTLINE)
	_num.add_theme_constant_override("outline_size", 6)
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_num.position = Vector2.ZERO
	_num.size = size
	_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_num)


## `number` 가 비면 가운데 숫자를 숨긴다.
func set_state(icon: Texture2D, lit: float, stack_max: int, stack: int,
		number: String) -> void:
	_icon = icon
	_lit = clampf(lit, 0.0, 1.0)
	_stack_max = maxi(0, stack_max)
	_stack = clampi(stack, 0, _stack_max)
	_num.text = number
	_num.visible = not number.is_empty()
	queue_redraw()


func _draw() -> void:
	var r: float = size.x * 0.5
	var c := Vector2(r, r)
	var ring_w: float = maxf(3.0, r * RING_W_RATIO)
	draw_circle(c, r, BG_COLOR, true, -1.0, true)

	if _icon != null:
		var side: float = (r - ring_w) * ICON_SIDE_RATIO
		var rect := Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side))
		if _lit >= 1.0:
			draw_texture_rect(_icon, rect, false, ICON_LIT)
		elif _lit <= 0.0:
			draw_texture_rect(_icon, rect, false, ICON_DIM)
		else:
			var split: float = -PI * 0.5 + TAU * _lit
			_draw_icon_sector(rect, -PI * 0.5, split, ICON_LIT)
			_draw_icon_sector(rect, split, PI * 1.5, ICON_DIM)

	var ring_r: float = r - ring_w * 0.5
	if _stack_max <= 0:
		draw_arc(c, r - 1.0, 0.0, TAU, ARC_POINTS, _rim, 2.0, true)
	elif _stack_max > STACK_SEGMENT_MAX:
		draw_arc(c, ring_r, 0.0, TAU, ARC_POINTS, STACK_OFF, ring_w, true)
		var frac: float = float(_stack) / float(_stack_max)
		if frac > 0.0:
			draw_arc(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * frac,
					maxi(4, int(ARC_POINTS * frac)), STACK_ON, ring_w, true)
	else:
		var step: float = TAU / float(_stack_max)
		var gap: float = 0.0 if _stack_max == 1 else minf(0.22, step * 0.25)
		var pts: int = maxi(4, ARC_POINTS / _stack_max)
		for i in _stack_max:
			var a0: float = -PI * 0.5 + step * float(i) + gap * 0.5
			draw_arc(c, ring_r, a0, a0 + step - gap, pts,
					STACK_ON if i < _stack else STACK_OFF, ring_w, true)


## 아이콘 사각형 중 각도 `a0`..`a1`(시계방향) 부채꼴만 `tint` 로 그린다.
func _draw_icon_sector(rect: Rect2, a0: float, a1: float, tint: Color) -> void:
	if a1 <= a0:
		return
	var c: Vector2 = rect.get_center()
	# 사각형 모서리까지 덮는 반지름 — 교차가 사각형 밖을 잘라 낸다.
	var reach: float = rect.size.x
	var fan := PackedVector2Array([c])
	var steps: int = maxi(2, int(ceil((a1 - a0) / TAU * float(ARC_POINTS))))
	for i in steps + 1:
		var a: float = lerpf(a0, a1, float(i) / float(steps))
		fan.append(c + Vector2(cos(a), sin(a)) * reach)
	var square := PackedVector2Array([rect.position,
			Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
	for poly in Geometry2D.intersect_polygons(fan, square):
		var pts := poly as PackedVector2Array
		if pts.size() < 3:
			continue
		var uvs := PackedVector2Array()
		for pt in pts:
			uvs.append((pt - rect.position) / rect.size)
		draw_colored_polygon(pts, tint, uvs, _icon)
