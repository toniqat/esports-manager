class_name CardPileStack
extends Control

## 핸드 행 양옆 거터에 놓이는 **덱 / 버린 더미 뭉치**.
##
## 예전에는 이 자리에 `"Deck\n18"` 두 줄짜리 Label 하나가 있었다. 숫자는 읽혔지만
## 더미가 **물건으로 보이지 않았고**, 그래서 손패에 들어오는 카드가 어디서 오고
## 버린 카드가 어디로 가는지가 화면 어디에도 없었다. 지금은 같은 자리에
## **앞으로 누운 카드 뭉치**를 그린다 — 카드 뒷면이 위를 향한 채 겹쳐 쌓인 모양.
##
## ### 왜 사다리꼴인가
## "누워 있다"를 만드는 것은 두 가지다. (1) 세로를 `FORESHORTEN` 만큼 눌러
## 카드의 세로 비율(220/160)을 죽이고, (2) **윗변을 아랫변보다 좁게**
## (`TOP_EDGE_SCALE`) 그려 원근을 넣는다. 직사각형을 그대로 눌러 놓으면 누운 게
## 아니라 그냥 납작한 카드로 읽힌다.
##
## ### 왜 위로 쌓는가
## 층이 올라갈수록 **화면 위쪽**으로 `LAYER_DY` 씩 밀린다. 그래서 아래 카드들의
## 앞쪽 모서리가 뭉치 **아래**로 삐져나오고, 눈이 위에서 비스듬히 내려다보는
## 자세가 된다. 맨 마지막에 그리는 층이 곧 맨 위 카드이고, 숫자는 그 카드 뒷면
## 한가운데에 찍힌다.
##
## ### 두께는 장수에 비례한다
## 보이는 층 수 = `ceil(count / CARDS_PER_LAYER)`, 상한 `MAX_LAYERS`. 덱이 얇아지는
## 것이 숫자와 형태 양쪽으로 읽힌다. **바닥선(`base_y`)은 고정**이고 뭉치는 위로만
## 자란다 — 세로 중심을 고정하면 카드 한 장이 오갈 때마다 뭉치 전체가 아래위로
## 떨리기 때문이다. 자리는 `MAX_LAYERS` 기준으로 미리 잡아 둔다.
##
## 카운트는 `float` 를 받는다 — 리셔플 트윈(`CardPhaseManager._animate_reshuffle_counts`)
## 이 소수로 굴러들어오므로, 그동안 층 수도 같이 부드럽게 움직인다.
##
## ### 오가는 카드는 잔상으로 보인다
## 숫자만 바뀌면 카드가 **더미에서 나왔다 / 더미로 들어갔다**가 화면에 남지
## 않는다. 그래서 뭉치는 맨 위 카드와 같은 모양의 **잔상** 한 장을 더 그린다 —
## 덱은 위로 떠오르며 사라지고(`play_pop`, 드로우), 버린 더미는 위에서
## 내려앉으며 나타난다(`play_land`, 버리기). 잔상은 노드가 아니라 `_draw()` 안의
## 한 장이라 레이아웃 · 입력 · z-order 에 아무 영향이 없다.

# ── 뭉치 기하 ────────────────────────────────────────────────────────────────
## 누운 카드의 세로 압축률. 1.0 이면 똑바로 선 카드, 0 이면 완전히 눕는다.
## 0.42 로 시작했다가 0.55 로 올렸다 — 더 눕히면 맨 위 카드의 면이 숫자보다
## 얇아져 "카드 뒷면"이 아니라 그냥 띠로 읽힌다. 세로 자리는 핸드 행 높이
## (220px)만큼 있고 뭉치는 100px 도 안 쓰므로 아낄 이유가 없다.
const FORESHORTEN     := 0.55
## 윗변 / 아랫변 폭 비. 1.0 이면 원근이 없는 직사각형이 된다.
const TOP_EDGE_SCALE  := 0.78
## 층 간 세로 간격(px). 아래 카드가 이만큼씩 뭉치 밑으로 삐져나온다.
const LAYER_DY        := 5.5
## 보이는 층 수 상한. 자리 계산도 이 값 기준이라 뭉치는 여기서 더 자라지 않는다.
const MAX_LAYERS      := 8
## 한 층이 대변하는 카드 수.
const CARDS_PER_LAYER := 4.0
## 뭉치 바닥과 제목 라벨 사이 여백.
const TITLE_GAP       := 6.0

# ── 색 ───────────────────────────────────────────────────────────────────────
## 아래 층들 — 카드의 "옆면 / 종이 단면".
const EDGE_FILL   := Color(0.74, 0.72, 0.80, 1.0)
const EDGE_LINE   := Color(0.16, 0.14, 0.22, 1.0)
## 맨 위 카드 뒷면. `Card._apply_back_style` 와 같은 값이라 손패의 뒷면 카드와
## 같은 물건으로 읽힌다.
##
## **뒷면은 이 색 하나로 균일하게 칠한다.** 예전에는 면 안쪽으로 물러난 사다리꼴
## 하나를 accent 색(덱 보라 / 버린 더미 적갈, alpha 0.55)으로 덧그려 "뒤집힌
## 카드"라는 무늬를 넣었는데, 뭉치가 워낙 작아 그 액자가 무늬가 아니라 **면에
## 얹힌 계조**로 읽혔다. 두 더미는 아래 제목 라벨이 이미 갈라 준다.
const BACK_FILL   := Color(0.08, 0.05, 0.18, 1.0)
const BACK_LINE   := Color(0.40, 0.30, 0.60, 1.0)
## 빈 더미 — 테두리만 남는다.
const EMPTY_LINE  := Color(0.55, 0.55, 0.62, 0.40)
const TITLE_COL   := Color(0.85, 0.85, 0.85)
const COUNT_COL   := Color(1.0, 1.0, 1.0)
const COUNT_OUTLINE_COL := Color(0.0, 0.0, 0.0, 0.85)
## 목록을 열 수 없는 상태에서 뭉치 전체에 씌우는 알파.
const DIM_ALPHA   := 0.45

# ── 잔상 (오가는 카드) ───────────────────────────────────────────────────────
## 잔상 한 장이 떠오르거나 내려앉는 데 걸리는 시간(s).
const GHOST_SEC := 0.26
## 잔상이 맨 위 카드에서 떠오르는(내려앉기 시작하는) 높이(px).
const GHOST_RISE_PX := 74.0
## 드로우 인트로가 "왼쪽에서 카드 등장"을 시작하는 시점의 잔상 알파. 덱에서 뜬
## 카드가 아직 30% 쯤 보일 때 손패 쪽 연출이 이어받아야 두 동작이 한 장의
## 카드로 읽힌다 — 완전히 사라진 뒤에 시작하면 두 번 나온 것처럼 보인다.
const GHOST_HANDOFF_ALPHA := 0.30
## 같은 프레임에 여러 장이 오갈 때 잔상 사이에 주는 간격(s).
const GHOST_STAGGER_SEC := 0.08

# ── 상태 ─────────────────────────────────────────────────────────────────────
## 뭉치 아래 제목("Deck" / "Discard"). HudBuilder 가 setup 으로 넣는다.
var title: String = ""
## 표시 중인 장수. 리셔플 트윈 때문에 소수가 들어온다.
var count: float = 0.0

var _lbl_title: Label = null
var _count_font_size: int = 24
## 진행 중인 잔상들. 각 항목은 `{t: float, land: bool, delay: float}`.
## 트윈이 아니라 `_process` 로 굴린다 — 한 프레임에 여러 장이 겹칠 수 있고,
## 각자 자기 지연과 진행도를 들고 있어야 서로를 끊지 않는다.
var _ghosts: Array = []


func _ready() -> void:
	# 입력은 위에 얹히는 투명 Button(HudBuilder._make_pile_button)이 가져간다.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## `title_font_size` 는 거터 폭에서 유도된 값 — HudBuilder 가 계산해 넘긴다.
func setup(title_text: String, title_font_size: int) -> void:
	title = title_text
	_count_font_size = clampi(int(size.x / 3.0), 14, 30)

	_lbl_title = Label.new()
	_lbl_title.text = title_text
	_lbl_title.add_theme_font_size_override("font_size", title_font_size)
	_lbl_title.add_theme_color_override("font_color", TITLE_COL)
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_title.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	_lbl_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lbl_title)
	_relayout_title(title_font_size)
	queue_redraw()


func set_count(v: float) -> void:
	if is_equal_approx(count, v):
		return
	count = v
	queue_redraw()


func set_dimmed(dim: bool) -> void:
	modulate = Color(1, 1, 1, DIM_ALPHA if dim else 1.0)


# ── 잔상 ─────────────────────────────────────────────────────────────────────
## 덱에서 카드가 **나갔다** — 맨 위 카드가 위로 떠오르며 사라진다.
func play_pop(delay: float = 0.0) -> void:
	_push_ghost(false, delay)


## 버린 더미가 카드를 **받았다** — 카드가 위에서 내려앉으며 나타난다.
func play_land(delay: float = 0.0) -> void:
	_push_ghost(true, delay)


## `n` 장을 `GHOST_STAGGER_SEC` 간격으로. 한 프레임에 여러 장이 오갈 때
## (개시 손패 · 드로우:N · 버리기:N) 정확히 겹쳐 한 장처럼 보이는 것을 막는다.
func play_burst(land: bool, n: int, delay: float = 0.0) -> void:
	for i in maxi(1, n):
		_push_ghost(land, delay + float(i) * GHOST_STAGGER_SEC)


## 잔상이 `GHOST_HANDOFF_ALPHA` 까지 옅어지는 데 걸리는 시간(s).
## `CardPhaseManager._play_draw_intro` 가 왼쪽 진입을 이만큼 늦춘다.
static func ghost_handoff_delay() -> float:
	return GHOST_SEC * (1.0 - GHOST_HANDOFF_ALPHA)


func _push_ghost(land: bool, delay: float) -> void:
	_ghosts.append({"t": 0.0, "land": land, "delay": maxf(0.0, delay)})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _ghosts.is_empty():
		set_process(false)
		return
	var step: float = delta / GHOST_SEC
	var alive: Array = []
	for raw in _ghosts:
		var g: Dictionary = raw
		var wait: float = float(g["delay"])
		if wait > 0.0:
			g["delay"] = wait - delta
			alive.append(g)
			continue
		g["t"] = float(g["t"]) + step
		if float(g["t"]) < 1.0:
			alive.append(g)
	_ghosts = alive
	queue_redraw()


# ── 자리 계산 ────────────────────────────────────────────────────────────────
## 누운 카드 한 장의 높이.
func _card_h() -> float:
	return size.x * (Card.CARD_H / Card.CARD_W) * FORESHORTEN


## `MAX_LAYERS` 를 다 채웠을 때의 뭉치 높이. 자리는 항상 이 기준으로 잡아
## 두께가 변해도 뭉치 바닥이 움직이지 않는다.
func _stack_h() -> float:
	return _card_h() + float(MAX_LAYERS - 1) * LAYER_DY


## 맨 아래 층의 **아랫변** y. 뭉치는 여기서 위로만 자란다.
func _base_y(title_h: float) -> float:
	var block_h: float = _stack_h() + TITLE_GAP + title_h
	return (size.y - block_h) * 0.5 + _stack_h()


func _relayout_title(title_font_size: int) -> void:
	var title_h: float = float(title_font_size) + 6.0
	_lbl_title.size     = Vector2(size.x, title_h)
	_lbl_title.position = Vector2(0.0, _base_y(title_h) + TITLE_GAP)


func _layer_count() -> int:
	if count <= 0.0:
		return 0
	return clampi(int(ceil(count / CARDS_PER_LAYER)), 1, MAX_LAYERS)


# ── 그리기 ───────────────────────────────────────────────────────────────────
func _draw() -> void:
	if size.x <= 1.0:
		return
	var title_h: float = 0.0
	if _lbl_title != null:
		title_h = _lbl_title.size.y
	var base_y: float = _base_y(title_h)
	var card_h: float = _card_h()
	var cx: float     = size.x * 0.5
	var n: int        = _layer_count()

	if n == 0:
		_draw_lying_card(cx, base_y, card_h, Color(0, 0, 0, 0), EMPTY_LINE, 1.0)
		_draw_count(cx, base_y - card_h * 0.5, Color(1, 1, 1, 0.45))
		_draw_ghosts(cx, base_y, card_h)
		return

	# 아래 층부터 그린다 — 마지막에 그리는 층이 맨 위 카드다.
	for i in range(n - 1):
		var y: float = base_y - float(i) * LAYER_DY
		_draw_lying_card(cx, y, card_h, EDGE_FILL, EDGE_LINE, 1.0)

	# 맨 위 카드 뒷면 — 무늬 없는 단색이다(BACK_FILL 주석 참고).
	var top_y: float = base_y - float(n - 1) * LAYER_DY
	_draw_lying_card(cx, top_y, card_h, BACK_FILL, BACK_LINE, 2.0)
	_draw_count(cx, top_y - card_h * 0.5, COUNT_COL)
	# 잔상은 맨 마지막 = 뭉치보다 **위**다. 뭉치에서 떠오르는(또는 뭉치로 내려
	# 앉는) 카드이므로 뭉치에 가려지면 동작의 절반이 사라진다.
	_draw_ghosts(cx, top_y, card_h)


## 오가는 카드 한 장의 잔상. `top_y` 는 맨 위 카드의 아랫변 y — 잔상은 거기서
## 출발해 `GHOST_RISE_PX` 만큼 떠오르며 사라지거나(덱), 그 높이에서 내려앉으며
## 나타난다(버린 더미).
func _draw_ghosts(cx: float, top_y: float, card_h: float) -> void:
	for raw in _ghosts:
		var g: Dictionary = raw
		if float(g["delay"]) > 0.0:
			continue
		var t: float    = clampf(float(g["t"]), 0.0, 1.0)
		var land: bool  = bool(g["land"])
		# 내려앉는 쪽은 위치도 알파도 정확히 반대로 간다.
		var a: float    = t if land else 1.0 - t
		var lift: float = GHOST_RISE_PX * ((1.0 - t) if land else t)
		_draw_lying_card(cx, top_y - lift, card_h,
				Color(BACK_FILL.r, BACK_FILL.g, BACK_FILL.b, BACK_FILL.a * a),
				Color(BACK_LINE.r, BACK_LINE.g, BACK_LINE.b, BACK_LINE.a * a),
				2.0)


## 누운 카드 한 장. `(cx, bottom_y)` 는 아랫변의 가운데이고, 원근 때문에 윗변이
## `TOP_EDGE_SCALE` 만큼 좁다. `width_scale` 은 축소된 사본을 그릴 때.
func _draw_lying_card(cx: float, bottom_y: float, h: float,
		fill: Color, line: Color, line_w: float, width_scale: float = 1.0) -> void:
	var half_bottom: float = size.x * 0.5 * width_scale
	var half_top: float    = half_bottom * TOP_EDGE_SCALE
	var top_y: float       = bottom_y - h
	var quad := PackedVector2Array([
		Vector2(cx - half_top,    top_y),
		Vector2(cx + half_top,    top_y),
		Vector2(cx + half_bottom, bottom_y),
		Vector2(cx - half_bottom, bottom_y),
	])
	if fill.a > 0.0:
		draw_colored_polygon(quad, fill)
	var outline := quad.duplicate()
	outline.append(quad[0])
	draw_polyline(outline, line, line_w, true)


## 맨 위 카드 뒷면 한가운데의 장수. 뒷면이 어두워 흰 글자가 뜨지만, 아래 층의
## 밝은 단면과 겹치는 경우가 있어 외곽선을 함께 깐다.
func _draw_count(cx: float, center_y: float, col: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var fs: int = _count_font_size
	var baseline: float = center_y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var origin := Vector2(cx - size.x * 0.5, baseline)
	var text: String = "%d" % int(round(count))
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, fs, 4, COUNT_OUTLINE_COL)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x, fs, col)
