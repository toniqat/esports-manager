class_name ObjectiveTimer
extends Control

# 오브젝트(전령 / 용) 등장 시계 — **아이콘 하나 + 남은 턴 수** 한 쌍.
#
# 예전에는 이 숫자가 전장 타일 위에 찍혀 있었다(`BattleRenderer._draw_objectives`).
# 그 자리는 좌우 중립 칸이었고, 그 칸이 다시 평범한 정글 칸으로 돌아오면서
# — 캠프가 서고, 정글러가 밟아 점령하고, 아웃라인이 그려지는 칸 —
# 이름과 턴 수가 그 위에 겹쳐 세 가지가 한 칸을 다투게 됐다. 그래서 시계만
# 상단 패널로 옮겼다: **왼쪽 전령 / 오른쪽 용** 이라는 좌우 배치가 지도의
# 좌우와 같으므로, 어느 아이콘이 어느 오브젝트인지는 자리가 말해 준다.
#
# 자리는 적 파일럿 스트립의 양옆이다(`HudBuilder.OBJ_TIMER_*`). 스트립이 화면
# 폭의 62% 로 줄면서 생긴 좌우 여백이 그대로 이 두 칸이고, **세로는 적 초상화
# 띠와 정확히 같다**.

## 눌렸을 때. `HudBuilder` 가 받아 보상 카드 팝업을 연다 — 오브젝트가 무엇을
## 주는지는 **결판이 나기 전에** 알아야 값어치가 판단의 대상이 된다.
signal timer_pressed(kind: int)

## 남은 턴 수를 다시 읽어 오는 곳. `HudBuilder.update_hud` 가 매 갱신마다
## `queue_redraw()` 만 부르면 되도록 참조만 들고 있는다.
var _bs: BattleSim = null
var _kind: int = ObjectiveSystem.Kind.HERALD

## 아이콘이 앉는 정사각 칸의 한 변(px). 나머지 좌표는 전부 여기서 유도한다 —
## 글리프는 64×64 좌표계로 그린 뒤 이 크기에 맞춰 배율만 곱한다.
##
## **`HudBuilder.OBJ_TIMER_H`(= 적 초상화 높이)를 넘지 않는다.** 한때는 62 였고
## 시계 칸도 스트립 띠 전체(122px)를 썼는데, 그러면 시계가 적 초상화보다 위아래로
## 튀어나와 상단 패널에서 가장 큰 물체가 됐다 — 곁눈으로 읽히라고 키운 것이
## 정작 얼굴에서 시선을 뺏는다. 지금은 초상화와 같은 높이라 좌·중·우가 한 줄로
## 읽힌다.
const ICON_SIZE: float = 49.0
## 아이콘과 숫자 사이 간격. 적 스트립이 20% 커지며 이 칸이 168 → 101px 로 줄어
## 10 → **4** 가 됐다 — 두 물건이 붙어 있는 편이 한 덩어리로 읽히기도 한다.
const ICON_TEXT_GAP: float = 4.0
## 숫자도 아이콘과 함께 줄었다(40 → 32) — 49px 칸 안에서 두 자리 수가 위아래로
## 삐져나오지 않는 크기다.
##
## **"턴" 글자는 삭제됐다.** 아이콘 옆에 붙은 숫자가 남은 턴 수 말고 무엇일
## 수는 없고, 101px 칸에서는 그 두 글자가 숫자를 밀어내기만 했다.
const TURN_FONT_SIZE: int = 32
const TURN_COLOR: Color = Color(1.00, 0.98, 0.92)
## 오브젝트별 색. 전령은 보랏빛, 용은 주홍 — 위치(좌/우)와 색이 함께 말한다.
const HERALD_COLOR: Color = Color(0.74, 0.62, 0.99)
const DRAGON_COLOR: Color = Color(1.00, 0.55, 0.28)


func setup(bs: BattleSim, kind: int) -> void:
	_bs = bs
	_kind = kind
	# **누를 수 있다** — 보상 카드 팝업을 여는 손잡이다. 예전에는 IGNORE 였다.
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	timer_pressed.emit(_kind)


func _draw() -> void:
	if _bs == null or _bs.objective == null:
		return
	var left: int = _bs.objective.turns_until_cell(_cell())
	if left < 0:
		return
	var color: Color = HERALD_COLOR if _kind == ObjectiveSystem.Kind.HERALD \
			else DRAGON_COLOR
	var icon_y: float = (size.y - ICON_SIZE) * 0.5
	_draw_glyph(Vector2(0.0, icon_y), color)

	# 숫자는 아이콘 오른쪽. 남은 폭 한가운데에 놓는다(한 자리 ↔ 두 자리에서
	# 자리가 흔들리지 않게).
	var font := ThemeDB.fallback_font
	var num: String = str(left)
	var num_w: float = font.get_string_size(num,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TURN_FONT_SIZE).x
	var avail_x: float = ICON_SIZE + ICON_TEXT_GAP
	var x: float = avail_x + maxf(0.0, (size.x - avail_x - num_w) * 0.5)
	var baseline: float = size.y * 0.5 + float(TURN_FONT_SIZE) * 0.36
	_outlined(font, Vector2(x, baseline), num, TURN_FONT_SIZE, TURN_COLOR)


## 어느 칸의 시계인가. `ObjectiveSystem` 이 그 좌표로 상태를 찾는다.
func _cell() -> Vector2i:
	return SimulationCore.NEUTRAL_LEFT if _kind == ObjectiveSystem.Kind.HERALD \
			else SimulationCore.NEUTRAL_RIGHT


## 상단 패널 배경이 짙은 남색이라 얇은 글자는 그냥 묻힌다. 타일 위에 찍던
## 시절과 같은 규칙 — 검은 외곽선을 먼저 깔고 그 위에 본 색.
func _outlined(font: Font, at: Vector2, text: String, fsize: int,
		color: Color) -> void:
	for ox in [-1.5, 1.5]:
		for oy in [-1.5, 1.5]:
			draw_string(font, at + Vector2(ox, oy), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.85))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


# ─── 글리프 ──────────────────────────────────────────────────────────────────
# 이미지 에셋이 없으므로 도형으로 그린다(킬로그 아이콘과 같은 방식). 좌표는
# 전부 **64×64 기준**으로 적고 `ICON_SIZE / 64` 배율을 곱해 옮긴다 — 크기를
# 바꿀 때 숫자를 다시 짜지 않아도 된다.
const GLYPH_UNIT: float = 64.0

func _draw_glyph(origin: Vector2, color: Color) -> void:
	if _kind == ObjectiveSystem.Kind.HERALD:
		_draw_herald(origin, color)
	else:
		_draw_dragon(origin, color)


## 전령 = **깃발**. 세로 장대에 삼각 페넌트 하나. "누군가가 소식을 들고 온다"는
## 뜻을 도형 셋으로 낼 수 있는 가장 짧은 그림이다.
func _draw_herald(o: Vector2, color: Color) -> void:
	var pole := _poly(o, [
		Vector2(17, 6), Vector2(22, 6), Vector2(22, 58), Vector2(17, 58)])
	draw_colored_polygon(pole, color)
	var flag := _poly(o, [
		Vector2(22, 9), Vector2(55, 20), Vector2(22, 31)])
	draw_colored_polygon(flag, color)
	# 장대 꼭대기 구슬 — 깃발이 매달린 쪽이 위라는 것을 못 박는다.
	draw_circle(o + Vector2(19.5, 6.0) * (ICON_SIZE / GLYPH_UNIT),
			4.5 * (ICON_SIZE / GLYPH_UNIT), color)


## 용 = **머리 + 몸통 + 펼친 두 날개**. 좌우 대칭이라 왼쪽 날개만 적고 x 를
## 뒤집는다.
##
## 날개는 **꼭짓점 넷짜리 매끈한 삼각**이다. 처음에는 박쥐 날개처럼 아래쪽에
## 톱니를 넣었는데(꼭짓점 여덟), 62px 로 줄이면 톱니가 뭉개져 **나뭇잎 한 장**
## 으로 보였다 — 이 크기에서 실루엣을 만드는 것은 디테일이 아니라 큰 삼각형
## 둘의 각도다. 위쪽 머리 원과 아래로 뻗은 꼬리가 "위아래가 있는 생물"이라는
## 것을 마저 말해 준다.
func _draw_dragon(o: Vector2, color: Color) -> void:
	var wing: Array = [
		Vector2(31, 22), Vector2(3, 12), Vector2(9, 33), Vector2(29, 38)]
	draw_colored_polygon(_poly(o, wing), color)
	var mirrored: Array = []
	for raw in wing:
		var v := raw as Vector2
		mirrored.append(Vector2(GLYPH_UNIT - v.x, v.y))
	draw_colored_polygon(_poly(o, mirrored), color)
	# 몸통 — 위가 굵고 아래로 갈수록 가늘어지는 꼬리.
	var body := _poly(o, [
		Vector2(32, 14), Vector2(39, 30), Vector2(34, 56), Vector2(30, 56),
		Vector2(25, 30)])
	draw_colored_polygon(body, color)
	# 머리 — 몸통 맨 위의 원 하나.
	var k: float = ICON_SIZE / GLYPH_UNIT
	draw_circle(o + Vector2(32.0, 13.0) * k, 8.0 * k, color)


## 64×64 좌표 목록을 실제 화면 좌표로 옮긴다.
func _poly(o: Vector2, pts: Array) -> PackedVector2Array:
	var k: float = ICON_SIZE / GLYPH_UNIT
	var out := PackedVector2Array()
	for raw in pts:
		out.append(o + (raw as Vector2) * k)
	return out
