class_name CardDragArrow
extends Node2D

# 손패에서 카드를 끌 때 **카드와 커서를 잇는 조준 화살표**.
#
# 예전에는 카드 자체가 커서를 따라 날아다녔다. 그러면 카드가 겨누려는 대상 —
# 커진 파일럿 초상 / 초록 유효 셀 — 을 자기 몸으로 덮어 버려서, 정작 놓는 순간에
# 무엇 위에 있는지가 안 보였다. 지금은 **카드가 손패에 선택된 자세 그대로 남고**
# 이 화살표만 커서를 쫓는다.
#
# 그리는 것은 **2차 베지어 곡선** 하나다:
#   • `p0` = 카드 위쪽 끝 — 다만 카드 안쪽으로 조금 파묻힌 지점(호출 측이
#     `ARROW_TUCK_PX` 만큼 밀어 넣어 준다). 이 노드는 `_bs.canvas` 의 맨 아래
#     자식이라 카드보다 **뒤에** 그려지므로, 리본의 시작부는 카드에 가려 보이지
#     않고 화살표가 카드 밑에서 뻗어 나온 것처럼 읽힌다.
#   • `p1` = 제어점 — `p0` 에서 **카드 자신의 위쪽 축**으로 뻗은 점. 부채꼴에서
#     기울어 있는 카드는 그 기울기 방향으로 화살을 쏘고, 커서가 카드보다 아래에
#     있으면(내적이 음수) `BOW_MIN` 으로 잘려 고리를 만들지 않는다.
#   • `p2` = 커서.
#
# 색은 두 가지다 — 평소에는 `COLOR_BASE`(금색, 드롭 존과 같은 계열), 커서가
# **지금 놓으면 나가는 지점** 위에 있으면 `COLOR_HOT`(시안, 대상 지정 링과 같은
# 계열). 유효/무효를 카드를 놓아 보기 전에 알려 주는 유일한 신호다.

# ─── 색 ──────────────────────────────────────────────────────────────────────
const COLOR_BASE    := Color(1.00, 0.85, 0.30, 0.92)
const COLOR_HOT     := Color(0.30, 0.95, 1.00, 0.98)
## 리본/촉 밑에 한 겹 더 그리는 어두운 테두리. 딤드된 전장 위에서도, 밝은 타일
## 위에서도 곡선이 끊겨 보이지 않게 한다.
const OUTLINE_COLOR := Color(0.04, 0.03, 0.09, 0.85)
const OUTLINE_PAD   := 3.0

# ─── 모양 ────────────────────────────────────────────────────────────────────
## 곡선을 나눠 그리는 조각 수. 조각마다 사다리꼴 하나를 칠하므로(오목 폴리곤
## 삼각분할을 피하려는 것) 값이 곧 부드러움이다.
const SEGMENTS := 26
## 리본 반폭 — 카드 쪽(시작)에서 촉 쪽(끝)으로 갈수록 굵어진다.
const WIDTH_START := 6.0
const WIDTH_END   := 14.0
const HEAD_LEN  := 44.0
const HEAD_HALF := 27.0
## 제어점을 카드 위쪽 축으로 얼마나 밀지 — 커서까지 거리의 이 비율, 상하한 사이.
const BOW_RATIO := 0.55
const BOW_MIN   := 40.0
const BOW_MAX   := 300.0
## 커서가 이보다 가까우면 아무것도 그리지 않는다 — 곡선이 촉 하나에 뭉개진다.
const MIN_LEN := 40.0

var _from: Vector2 = Vector2.ZERO
var _up:   Vector2 = Vector2.UP
var _to:   Vector2 = Vector2.ZERO
var _hot:  bool = false


## 화살표를 켜고 양 끝을 갱신한다. `up` 은 카드 자신의 위쪽 축(부채꼴 기울기가
## 반영된 것)이고, 곡선이 카드에서 뻗어 나가는 방향을 정한다.
func aim(from: Vector2, up: Vector2, to: Vector2, hot: bool) -> void:
	_from = from
	_up = up.normalized() if up.length_squared() > 0.0 else Vector2.UP
	_to = to
	_hot = hot
	visible = true
	queue_redraw()


func stop() -> void:
	if not visible:
		return
	visible = false
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	if _from.distance_to(_to) < MIN_LEN:
		return
	# 제어점은 언제나 카드 위쪽 축 위에 있다. 커서가 카드보다 아래면 내적이
	# 음수라 BOW_MIN 으로 잘리고, 곡선은 살짝 부풀 뿐 고리를 만들지 않는다.
	var ctrl: Vector2 = _from + _up * clampf((_to - _from).dot(_up) * BOW_RATIO,
			BOW_MIN, BOW_MAX)
	var to_tip: Vector2 = _to - ctrl
	if to_tip.length() < 1.0:
		return
	var head_dir: Vector2 = to_tip.normalized()
	var head_len: float = minf(HEAD_LEN, to_tip.length() * 0.5)
	# 촉의 밑변은 ctrl→_to 선분 **위**에 있으므로, 거기서 끝나는 베지어의 끝
	# 접선이 촉의 방향과 정확히 일치한다 — 리본과 촉의 이음매가 꺾이지 않는다.
	var neck: Vector2 = _to - head_dir * head_len
	var col: Color = COLOR_HOT if _hot else COLOR_BASE
	var head_half: float = HEAD_HALF * (head_len / HEAD_LEN)
	# 어두운 테두리를 한 겹 먼저 깔고 그 위에 본색을 얹는다 — 폴리라인 두 줄을
	# 따로 긋는 것보다 이음매가 깔끔하다.
	_draw_ribbon(_from, ctrl, neck, OUTLINE_PAD, OUTLINE_COLOR)
	_draw_head(neck, head_dir, head_half + OUTLINE_PAD, head_len + OUTLINE_PAD,
			OUTLINE_COLOR)
	_draw_ribbon(_from, ctrl, neck, 0.0, col)
	_draw_head(neck, head_dir, head_half, head_len, col)


## 조각마다 사다리꼴 하나를 칠한다. 곡선 전체를 한 폴리곤으로 만들면 급하게
## 굽은 구간에서 좌우 오프셋이 서로를 지나 자기교차하고, 그러면 삼각분할이
## 뒤집힌 조각을 만든다. 조각들은 서로 같은 두 꼭짓점을 공유하므로 이음매에
## 틈이 생기지 않는다.
func _draw_ribbon(p0: Vector2, p1: Vector2, p2: Vector2, pad: float,
		color: Color) -> void:
	var prev_l := Vector2.ZERO
	var prev_r := Vector2.ZERO
	for i in range(SEGMENTS + 1):
		var t: float = float(i) / float(SEGMENTS)
		var pt: Vector2 = _bezier(p0, p1, p2, t)
		var tangent: Vector2 = _bezier_tangent(p0, p1, p2, t)
		if tangent.length_squared() < 0.001:
			tangent = p2 - p0
		var normal := Vector2(-tangent.y, tangent.x).normalized()
		var half: float = lerpf(WIDTH_START, WIDTH_END, t) + pad
		var l: Vector2 = pt + normal * half
		var r: Vector2 = pt - normal * half
		if i > 0:
			draw_colored_polygon(PackedVector2Array([prev_l, l, r, prev_r]), color)
		prev_l = l
		prev_r = r


func _draw_head(neck: Vector2, dir: Vector2, half: float, length: float,
		color: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		neck + dir * length,
		neck + perp * half,
		neck - perp * half,
	]), color)


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)


func _bezier_tangent(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	return (p1 - p0) * (2.0 * (1.0 - t)) + (p2 - p1) * (2.0 * t)
