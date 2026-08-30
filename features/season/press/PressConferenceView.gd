class_name PressConferenceView
extends Control

# ── 기자회견 (주 시작 직전) ──────────────────────────────────────────────────
#
# **메신저 화면이다.** 기자가 왼쪽에서 말을 걸고 플레이어가 오른쪽에서 답한다.
#
#   [원형 초상] ◀ 말풍선 ─ 기자 대사 1
#               ◀ 말풍선 ─ 기자 대사 2
#                                    답변 선택지 ▶ (오른쪽 아래)
#
# 기자 대사는 **한 줄씩** 나온다 — 화면 아무 데나 누르면 다음 줄이 붙고, 다 나온
# 뒤에 답변 선택지 셋이 오른쪽 아래에 뜬다. 하나를 고르면 그 답이 플레이어
# 말풍선으로 붙고 잠깐 뒤 `SeasonHub.on_press_finished()` 로 훈련 계획 화면에
# 넘어간다.
#
# ── 지금은 틀만이다 ─────────────────────────────────────────────────────────
# 대사와 선택지는 `_SCRIPT_POOL` 에 박아 둔 **임시 데이터**이고, 답변은 아무런
# 효과도 없다(`_on_answer_picked` 이 고른 인덱스를 로그로만 남긴다). 나중에
# 붙일 자리는 셋이다 —
#   (1) 대사 풀을 CSV(`data/csv/press_lines.csv` 같은 표)로 빼고 페이즈 · 순위 ·
#       직전 경기 결과로 고르기,
#   (2) 답변마다 팀 사기 / 선수 컨디션 / 평판 같은 상태를 움직이기,
#   (3) 기자 초상화를 실제 인물 아트로 바꾸기(지금은 `_draw_reporter_glyph` 가
#       그리는 마이크 도형이다 — 기자 에셋이 없다).
#
# 배치 규약은 다른 시즌 화면과 같다: 화면째 `indent_to_safe_top` 으로 내리고,
# 배경만 `extend_background` 로 노치 자리까지 도로 늘린다. 색은 전부
# `OutgameTheme` 를 지난다.

const PHASE_NAMES: Dictionary = {
	GameEnums.SeasonPhase.PRESEASON:      "프리시즌",
	GameEnums.SeasonPhase.PRESEASON_INTL: "프리시즌 국제대회",
	GameEnums.SeasonPhase.MIDSEASON:      "미드시즌",
	GameEnums.SeasonPhase.MIDSEASON_INTL: "미드시즌 국제대회",
	GameEnums.SeasonPhase.REGULAR:        "정규시즌",
	GameEnums.SeasonPhase.REGULAR_INTL:   "정규시즌 국제대회",
}

## 임시 대본. `{lines: [기자 대사…], answers: [답변…]}` 하나가 회견 한 번이다.
## 고르는 규칙도 임시로 `phase_week` 나머지 하나뿐이다.
const _SCRIPT_POOL: Array = [
	{
		"reporter": "리그 위클리",
		"lines": [
			"이번 주도 시간 내주셔서 감사합니다, 감독님.",
			"지난주 훈련 성과가 눈에 띄더군요. 이번 주 계획도 비슷하게 가시나요?",
		],
		"answers": [
			"계획대로 갑니다. 흔들릴 이유가 없죠.",
			"조금 바꿀 생각입니다. 아직 말씀드리긴 이르고요.",
			"그건 경기장에서 확인하시죠.",
		],
	},
	{
		"reporter": "e스포츠 데일리",
		"lines": [
			"주말 경기 상대가 만만치 않다는 평이 많습니다.",
			"솔직히, 이길 자신 있으십니까?",
		],
		"answers": [
			"저희 선수들을 믿습니다.",
			"쉽지 않겠지만 준비한 게 있습니다.",
			"질문이 좀 무례하시네요.",
		],
	},
]

# ── 배치 상수 ────────────────────────────────────────────────────────────────
const MARGIN_X: float      = 40.0
const PORTRAIT_D: float    = 96.0            # 기자 원형 초상 지름
const BUBBLE_MAX_W: float  = 700.0
const BUBBLE_PAD_X: float  = 26.0
const BUBBLE_PAD_Y: float  = 20.0
const BUBBLE_GAP: float    = 18.0            # 말풍선 사이 세로 간격
const WEDGE_W: float       = 18.0            # 초상화를 가리키는 쐐기
const WEDGE_H: float       = 22.0
const LINE_FONT: int       = 27
const ANSWER_FONT: int     = 26
const ANSWER_H: float      = 96.0
const ANSWER_GAP: float    = 14.0
const BODY_TOP: float      = 190.0

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _script: Dictionary = {}
var _shown: int = 0                 # 지금까지 붙은 기자 대사 수
var _finished: bool = false         # 답변까지 고른 뒤
var _built: bool = false

var _title_lbl: Label
var _sub_lbl: Label
var _hint_lbl: Label
var _body: Control                  # 말풍선이 쌓이는 자리 (스크롤 내용)
var _scroll: ScrollContainer
var _body_y: float = 0.0
var _answer_holder: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 탭은 **이 화면 자신이** 받는다 — 스크롤 안쪽에서 올라온 클릭이 여기서 멎는다.
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_tap_input)
	ensure_view()


## SeasonHub 가 이 화면으로 라우팅할 때마다 부른다 — **회견은 매번 새로 연다**
## (대본을 다시 고르고 말풍선을 전부 걷는다). 주마다 같은 회견이 이어져 보이면
## 안 되기 때문이고, 그래서 `_built` 는 뼈대만 지키고 내용은 `_restart()` 가 쥔다.
func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	_restart()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)

	_sub_lbl = UiHelpers.mk_label(self, "", 24, OutgameTheme.TEXT_SUB,
			Vector2(MARGIN_X, 36), Vector2(700, 30), HORIZONTAL_ALIGNMENT_LEFT)
	_title_lbl = UiHelpers.mk_label(self, "기자회견", 52, OutgameTheme.TEXT,
			Vector2(MARGIN_X, 72), Vector2(700, 62), HORIZONTAL_ALIGNMENT_LEFT)
	OutgameTheme.add_divider(self, Vector2(MARGIN_X, 160.0),
			ScreenMetrics.vp_w() - MARGIN_X * 2.0)

	var bottom: float = ScreenMetrics.safe_h()
	var scroll_h: float = bottom - BODY_TOP - 40.0
	var pack: Dictionary = OutgameTheme.add_vscroll(self,
			Vector2(0, BODY_TOP),
			Vector2(ScreenMetrics.vp_w(), scroll_h))
	_scroll = pack["scroll"]
	_body = pack["body"]
	# **스크롤과 그 안의 판은 클릭을 삼키지 않는다.** 둘 다 기본값이 STOP 이라
	# 그대로 두면 화면의 190px 아래쪽 — 곧 말풍선이 있는 자리 전부 — 이 탭을
	# 먹어 버려 "화면 아무 데나 눌러 다음 줄"이 동작하지 않는다. PASS 로 두면
	# 처리되지 않은 클릭이 **부모 사슬**을 타고 이 화면까지 올라온다(형제로
	# 깔아 둔 판은 소용이 없다 — 전파는 위로만 가지 옆으로는 안 간다).
	# 휠 · 터치 드래그는 ScrollContainer 가 자기 자리에서 먹으므로 스크롤은
	# 그대로 살아 있고, 답변 Button 은 STOP 이라 거기서 멎는다.
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.mouse_filter = Control.MOUSE_FILTER_PASS

	_hint_lbl = UiHelpers.mk_label(self, "", 22, OutgameTheme.TEXT_FAINT,
			Vector2(0, bottom - 46.0), Vector2(ScreenMetrics.vp_w(), 28),
			HORIZONTAL_ALIGNMENT_CENTER)


# ── 회견 한 번 ───────────────────────────────────────────────────────────────
func _restart() -> void:
	_script = _pick_script()
	_shown = 0
	_finished = false
	for c in _body.get_children():
		c.queue_free()
	_body_y = 0.0
	_answer_holder = null

	var s: Dictionary = _gm.season_state
	_sub_lbl.text = "%s · %d주차 · %s 기자" % [
		PHASE_NAMES.get(int(s["current_phase"]), "—"),
		int(s["phase_week"]),
		String(_script.get("reporter", "")),
	]
	_reveal_next_line()


func _pick_script() -> Dictionary:
	if _SCRIPT_POOL.is_empty():
		return {"reporter": "", "lines": [], "answers": []}
	var w: int = int(_gm.season_state.get("phase_week", 1))
	return _SCRIPT_POOL[w % _SCRIPT_POOL.size()]


# ── 대사 한 줄 ───────────────────────────────────────────────────────────────
func _reveal_next_line() -> void:
	var lines: Array = _script.get("lines", [])
	if _shown >= lines.size():
		_show_answers()
		return
	_add_reporter_bubble(String(lines[_shown]), _shown == 0)
	_shown += 1
	_refresh_hint()
	_scroll_to_bottom()


## 기자 말풍선 한 장. `with_portrait` 이면 왼쪽에 원형 초상화와 쐐기가 함께 선다
## (연속된 대사는 초상화를 반복하지 않는다 — 같은 사람이 이어 말하는 것이다).
func _add_reporter_bubble(text: String, with_portrait: bool) -> void:
	var bubble_x: float = MARGIN_X + PORTRAIT_D + 26.0
	var body_w: float = BUBBLE_MAX_W
	var h: float = _text_block_height(text, body_w - BUBBLE_PAD_X * 2.0, LINE_FONT) \
			+ BUBBLE_PAD_Y * 2.0

	if with_portrait:
		var holder: Control = OutgameTheme.add_round_portrait(_body, null,
				Vector2(MARGIN_X, _body_y), PORTRAIT_D, OutgameTheme.BORDER)
		# 기자 아트가 없으므로 마이크 도형을 그려 둔다. 초상화 텍스처가 생기면
		# `add_round_portrait` 의 두 번째 인자에 넘기고 이 자식만 지우면 된다.
		var glyph := Control.new()
		glyph.size = Vector2(PORTRAIT_D, PORTRAIT_D)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.draw.connect(_draw_reporter_glyph.bind(glyph))
		holder.add_child(glyph)

	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.SURFACE, 22, OutgameTheme.BORDER))
	panel.position = Vector2(bubble_x, _body_y)
	panel.size = Vector2(body_w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(panel)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", LINE_FONT)
	lbl.add_theme_color_override("font_color", OutgameTheme.TEXT)
	lbl.position = Vector2(BUBBLE_PAD_X, BUBBLE_PAD_Y)
	lbl.size = Vector2(body_w - BUBBLE_PAD_X * 2.0, h - BUBBLE_PAD_Y * 2.0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	if with_portrait:
		_add_wedge(Vector2(bubble_x - WEDGE_W + 1.0, _body_y + 26.0), true)

	_body_y += h + BUBBLE_GAP
	_body.custom_minimum_size = Vector2(ScreenMetrics.vp_w(), _body_y)


## 플레이어 말풍선 — 오른쪽 정렬 + 앰버 색면 + 흰 글자.
func _add_player_bubble(text: String) -> void:
	var body_w: float = BUBBLE_MAX_W - 60.0
	var h: float = _text_block_height(text, body_w - BUBBLE_PAD_X * 2.0, LINE_FONT) \
			+ BUBBLE_PAD_Y * 2.0
	var x: float = ScreenMetrics.vp_w() - MARGIN_X - body_w

	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.ACCENT, 22))
	panel.position = Vector2(x, _body_y)
	panel.size = Vector2(body_w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(panel)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", LINE_FONT)
	lbl.add_theme_color_override("font_color", OutgameTheme.TEXT_ON_FILL)
	lbl.position = Vector2(BUBBLE_PAD_X, BUBBLE_PAD_Y)
	lbl.size = Vector2(body_w - BUBBLE_PAD_X * 2.0, h - BUBBLE_PAD_Y * 2.0)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	_add_wedge(Vector2(x + body_w - 1.0, _body_y + 24.0), false)

	_body_y += h + BUBBLE_GAP
	_body.custom_minimum_size = Vector2(ScreenMetrics.vp_w(), _body_y)


## 말풍선의 꼬리. `_draw` 는 자식보다 **먼저** 나가므로 자식이 없는 전용
## Control 로 둔다 — 말풍선 Panel 안에 넣으면 글자 밑에 깔린다.
func _add_wedge(pos: Vector2, point_left: bool) -> void:
	var w := Control.new()
	w.position = pos
	w.size = Vector2(WEDGE_W, WEDGE_H)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.draw.connect(_draw_wedge.bind(w, point_left))
	_body.add_child(w)


func _draw_wedge(node: Control, point_left: bool) -> void:
	var col: Color = OutgameTheme.SURFACE if point_left else OutgameTheme.ACCENT
	var pts: PackedVector2Array
	if point_left:
		pts = PackedVector2Array([
			Vector2(WEDGE_W, 0.0), Vector2(0.0, WEDGE_H * 0.45),
			Vector2(WEDGE_W, WEDGE_H)])
	else:
		pts = PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(WEDGE_W, WEDGE_H * 0.45),
			Vector2(0.0, WEDGE_H)])
	node.draw_colored_polygon(pts, col)


## 기자 초상 자리표시 — 마이크 하나. 실제 아트가 들어오면 통째로 지운다.
func _draw_reporter_glyph(node: Control) -> void:
	var c: Vector2 = Vector2(PORTRAIT_D, PORTRAIT_D) * 0.5
	var col: Color = OutgameTheme.TEXT_SUB
	node.draw_circle(c, PORTRAIT_D * 0.5 - 2.0, OutgameTheme.SURFACE_SUNK)
	# 헤드
	node.draw_rect(Rect2(c.x - 11.0, c.y - 26.0, 22.0, 30.0), col)
	node.draw_circle(Vector2(c.x, c.y - 26.0), 11.0, col)
	node.draw_circle(Vector2(c.x, c.y + 4.0), 11.0, col)
	# 스탠드
	node.draw_rect(Rect2(c.x - 3.0, c.y + 4.0, 6.0, 22.0), col)
	node.draw_rect(Rect2(c.x - 16.0, c.y + 24.0, 32.0, 6.0), col)


# ── 답변 선택지 ──────────────────────────────────────────────────────────────
func _show_answers() -> void:
	if _answer_holder != null or _finished:
		return
	var answers: Array = _script.get("answers", [])
	if answers.is_empty():
		_finish()
		return
	_answer_holder = Control.new()
	_answer_holder.position = Vector2(0, _body_y + 10.0)
	_answer_holder.size = Vector2(ScreenMetrics.vp_w(),
			answers.size() * (ANSWER_H + ANSWER_GAP))
	_answer_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_answer_holder)

	var w: float = BUBBLE_MAX_W - 60.0
	var x: float = ScreenMetrics.vp_w() - MARGIN_X - w
	for i in answers.size():
		var b := Button.new()
		b.text = String(answers[i])
		b.position = Vector2(x, i * (ANSWER_H + ANSWER_GAP))
		b.size = Vector2(w, ANSWER_H)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		OutgameTheme.style_ghost_button(b, ANSWER_FONT)
		b.pressed.connect(_on_answer_picked.bind(i, String(answers[i])))
		# 답은 한 번 고르면 무를 수 없다 — 확정의 무게로 낸다.
		HapticUi.kind(b, Haptics.Kind.MEDIUM)
		_answer_holder.add_child(b)

	_body_y += _answer_holder.size.y + 10.0
	_body.custom_minimum_size = Vector2(ScreenMetrics.vp_w(), _body_y)
	_refresh_hint()
	_scroll_to_bottom()


func _on_answer_picked(idx: int, text: String) -> void:
	if _finished:
		return
	_finished = true
	# TODO: 고른 답이 팀 사기 / 평판 같은 상태를 움직일 자리. 지금은 기록만.
	print("PressConference: answer %d picked — %s" % [idx, text])
	if _answer_holder != null:
		var freed_h: float = _answer_holder.size.y + 10.0
		_answer_holder.queue_free()
		_answer_holder = null
		_body_y -= freed_h
	_add_player_bubble(text)
	_refresh_hint()
	_scroll_to_bottom()
	# 답이 붙은 것을 한 박자 보여 준 뒤 넘어간다. 곧장 화면을 갈면 방금 고른
	# 답이 화면에 뜨지 않은 채로 사라진다.
	var t := create_tween()
	t.tween_interval(0.7)
	t.tween_callback(_finish)


func _finish() -> void:
	if _hub != null and _hub.has_method("on_press_finished"):
		_hub.on_press_finished()


# ── 입력 · 보조 ──────────────────────────────────────────────────────────────
func _on_tap_input(event: InputEvent) -> void:
	if _finished:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	_reveal_next_line()


func _refresh_hint() -> void:
	if _hint_lbl == null:
		return
	if _finished:
		_hint_lbl.text = ""
	elif _answer_holder != null:
		_hint_lbl.text = "답변을 고르세요"
	else:
		_hint_lbl.text = "화면을 눌러 계속"


## 스크롤을 맨 아래로. 새 말풍선의 크기가 이번 프레임의 레이아웃에 아직 반영되지
## 않았으므로 한 프레임 기다린 뒤에 민다.
func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(maxf(0.0, _body_y))


## 자동 줄바꿈된 글이 차지하는 높이. `Label` 하나를 실제로 세워 재는 대신
## 폰트에게 직접 묻는다 — 재려고 세운 라벨은 그 프레임에 크기가 0 이라
## 물어봐야 0 이 나온다.
static func _text_block_height(text: String, w: float, font_size: int) -> float:
	var font: Font = ThemeDB.fallback_font
	var line_h: float = float(font_size) * 1.35
	var total: float = 0.0
	for para in text.split("\n"):
		var wrapped: int = maxi(1, int(ceil(
				font.get_string_size(para, HORIZONTAL_ALIGNMENT_LEFT, -1,
						font_size).x / maxf(1.0, w))))
		total += line_h * float(wrapped)
	return maxf(line_h, total)
