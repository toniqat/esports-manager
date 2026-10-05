class_name CardDragArrow
extends Node2D

# 손패에서 카드를 끌 때 **카드와 커서를 잇는 조준 화살표**.
#
# 예전에는 카드 자체가 커서를 따라 날아다녔다. 그러면 카드가 겨누려는 대상 —
# 커진 파일럿 초상 / 초록 유효 셀 — 을 자기 몸으로 덮어 버려서, 정작 놓는 순간에
# 무엇 위에 있는지가 안 보였다. 지금은 **카드가 손패에 선택된 자세 그대로 남고**
# 이 화살표만 커서를 쫓는다.
#
# 화살표는 **같은 굵기의 chevron(›) 여러 개를 사슬처럼** 2차 베지어 곡선 위에
# 늘어놓은 것이다. 맨 끝 chevron 의 꼭짓점이 커서에 정확히 닿고, 거기서 곡선을
# 따라 `CHEVRON_SPACING` 마다 하나씩 카드 쪽으로 거슬러 놓는다. 각 chevron 은
# 그 자리의 곡선 접선을 향한다. 커서 쪽 맨 끝 chevron 만 원래 크기이고 그
# 뒤를 따르는 나머지는 `TRAIL_SCALE` 배로 작다 — 촉이 어디인지가 크기로 읽힌다.
# 예전에는 밝은 띠가 사슬을 타고 흐르는 애니메이션이 있었다(삭제됨). 그보다
# 전에는 카드 쪽이 가늘고 촉 쪽이 굵은 이어진 리본 + 큰 삼각 촉이었다.
#
# 곡선의 세 점:
#   • `p0` = 카드 위쪽 끝 — 다만 카드 안쪽으로 조금 파묻힌 지점(호출 측이
#     `ARROW_TUCK_PX` 만큼 밀어 넣어 준다). 이 노드는 `_bs.canvas` 의 맨 아래
#     자식이라 카드보다 **뒤에** 그려지므로, 사슬의 시작부는 카드에 가려 보이지
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
## 평소(금색, 드롭 존과 같은 계열) / 놓으면 나가는 지점 위(시안, 대상 지정 링과
## 같은 계열).
const COLOR_BASE := Color(1.00, 0.85, 0.30, 0.95)
const COLOR_HOT  := Color(0.55, 1.00, 1.00, 1.00)
## chevron 밑에 한 겹 더 그리는 어두운 테두리. 딤드된 전장 위에서도, 밝은 타일
## 위에서도 사슬이 끊겨 보이지 않게 한다.
const OUTLINE_COLOR := Color(0.04, 0.03, 0.09, 0.85)
const OUTLINE_PAD   := 3.0

# ─── 모양 ────────────────────────────────────────────────────────────────────
## chevron 한 개 — 꼭짓점에서 뒤로 `CHEVRON_LEN`, 좌우로 `CHEVRON_HALF` 벌어진
## 두 팔. 커서 쪽 맨 끝 chevron 의 크기다.
const CHEVRON_LEN     := 16.0
const CHEVRON_HALF    := 17.0
const CHEVRON_WIDTH   := 7.0
## 이웃 chevron 꼭짓점 사이의 곡선 길이.
const CHEVRON_SPACING := 30.0
## 곡선 길이를 재려고 나누는 조각 수.
const SAMPLES := 48
## 맨 끝을 뒤따르는 chevron 의 크기 배율 (팔 길이 · 반폭 · 선 굵기 모두).
const TRAIL_SCALE := 0.75
## 제어점을 카드 위쪽 축으로 얼마나 밀지 — 커서까지 거리의 이 비율, 상하한 사이.
const BOW_RATIO := 0.55
const BOW_MIN   := 40.0
const BOW_MAX   := 300.0
## 커서가 이보다 가까우면 아무것도 그리지 않는다.
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
	# 곡선을 잘게 나눠 누적 길이표를 만든다 — chevron 을 길이 기준으로 고르게 놓는다.
	var pts := PackedVector2Array()
	var lens := PackedFloat32Array()
	var total: float = 0.0
	for i in range(SAMPLES + 1):
		var pt: Vector2 = _bezier(_from, ctrl, _to, float(i) / float(SAMPLES))
		if i > 0:
			total += pt.distance_to(pts[i - 1])
		pts.append(pt)
		lens.append(total)
	if total < MIN_LEN:
		return
	var color: Color = COLOR_HOT if _hot else COLOR_BASE
	# 커서(끝)에서 카드 쪽으로 거슬러 놓는다 — 맨 끝 꼭짓점이 커서에 닿는다.
	# 테두리를 전부 먼저 깔고 본색을 얹어야 이웃 chevron 의 테두리가 본색을 덮지 않는다.
	var chevs: Array = []
	var d: float = total
	while d >= CHEVRON_LEN:
		chevs.append(d)
		d -= CHEVRON_SPACING
	# chevs[0] 이 커서 쪽 맨 끝 — 그것만 원래 크기, 나머지는 TRAIL_SCALE.
	for k in chevs.size():
		var sc: float = 1.0 if k == 0 else TRAIL_SCALE
		_draw_chevron(pts, lens, chevs[k], sc,
				(CHEVRON_WIDTH + OUTLINE_PAD * 2.0) * sc, OUTLINE_COLOR)
	for k in chevs.size():
		var sc: float = 1.0 if k == 0 else TRAIL_SCALE
		_draw_chevron(pts, lens, chevs[k], sc, CHEVRON_WIDTH * sc, color)


## 곡선 길이 `d` 지점에 꼭짓점을 둔 chevron 하나 — 그 자리 접선을 향한다.
## `sc` 는 팔 길이 · 반폭 배율이다.
func _draw_chevron(pts: PackedVector2Array, lens: PackedFloat32Array, d: float,
		sc: float, width: float, color: Color) -> void:
	var i: int = 1
	while i < lens.size() - 1 and lens[i] < d:
		i += 1
	var seg: float = maxf(0.001, lens[i] - lens[i - 1])
	var tip: Vector2 = pts[i - 1].lerp(pts[i], clampf((d - lens[i - 1]) / seg, 0.0, 1.0))
	var dir: Vector2 = pts[i] - pts[i - 1]
	if dir.length_squared() < 0.0001:
		dir = _to - _from
	dir = dir.normalized()
	var n := Vector2(-dir.y, dir.x)
	var back: Vector2 = tip - dir * CHEVRON_LEN * sc
	draw_polyline(PackedVector2Array([back + n * CHEVRON_HALF * sc, tip,
			back - n * CHEVRON_HALF * sc]), color, width, true)


func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t)
