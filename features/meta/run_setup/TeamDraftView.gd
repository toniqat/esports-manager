class_name TeamDraftView
extends Control

# 런 준비의 **5인 편성** 화면 — 우마무스메식 인물 고르기.
#
#   맨 위: 단계 머리글(`RunSetupScreen` 이 그린다 — 이 화면은 그 아래부터)
#   상단: **샐러리 게이지** — 합계 / 캡, 넘치면 빨강. 그 아래 규칙 한 줄
#         (`RunRules.validate_lineup` 의 오류 문장 그대로)
#   상: 선택한 5인의 **상체 일러스트** (탑 · 정글 · 미드 · 원딜 · 서폿).
#       일러스트를 누르면 `DraftDetailPanel` 이 열린다. 칸 아래에 **레벨 스테퍼**
#       (− Lv +, 1 ~ 달성 최대)와 그 레벨의 샐러리 · 종합 스탯
#   중: 전체 / 탑 / 정글 / 미드 / 원딜 / 서폿 필터 버튼 한 줄
#   하: 보유 선수 썸네일 격자 (세로 스크롤, 3.5줄이 보인다, 칸마다 샐러리 꼬리표)
#   맨 아래: 하단 바 `뒤로` / `다음`
#
# 블록은 **아래에서 위로** 쌓는다 — 격자를 하단 바 위에 매달고, 필터와 선택
# 5인이 그 위에 차례로 앉는다. 게이지는 머리글 바로 아래에 붙는다.
#
# **화면은 두 모드를 오간다.** PICK 은 위와 같고, `다음`을 누르면 CONFIRM 으로
# 넘어가 **픽창(필터 + 격자)이 화면 아래로 빠지고 선택 5인이 화면 가운데로
# 내려온다**(`_apply_mode`). 거기서 **`게임 시작`**이 `TeamDraft.start_requested`
# 를 올리고, `RunSetupScreen` 이 암전 → 가짜 로딩 → 밝아짐 뒤에서 런을 연다.
# `뒤로`는 PICK 에서는 팀 단계로(`back_requested`), CONFIRM 에서는 PICK 으로.
#
# **규칙은 고를 때 보인다** — 샐러리캡을 넘기는 선택도 막지 않고 게이지를 빨갛게
# 칠한 뒤 `다음` / `게임 시작`을 잠근다. 시작 버튼에서 처음 거절당하는 조합은 없다.
#
# **다섯 칸은 역할 고정**이다(`TeamDraft.SLOT_ROLES`) — `validate_lineup` 이
# "포지션당 1명"을 강제하므로 자유 순서로 두면 화면에서만 가능한 조합이 생긴다.

const ROLE_COLORS: Array = OutgameTheme.ROLE_COLORS

# ─── 상단: 샐러리 게이지 ─────────────────────────────────────────────────────
const GAUGE_X: float = 24.0
const GAUGE_W: float = 1032.0
const GAUGE_H: float = 164.0
const GAUGE_PAD: float = 24.0
const GAUGE_BAR_H: float = 16.0
## 게이지 아랫변 ↔ 선택 5인(CONFIRM 모드에서 위로 붙을 수 있는 한계).
const GAUGE_ROW_GAP: float = 24.0

# ─── 상: 선택 5인 ────────────────────────────────────────────────────────────
# 다섯 칸은 `_slot_row` 한 Control 안의 **지역 좌표**로 산다 — CONFIRM 모드가
# 그 한 노드의 y 하나만 밀어 블록째 화면 가운데로 내리기 때문이다.
const SLOT_COUNT: int = 5
const SLOT_W: float = 204.0
const SLOT_GAP: float = 12.0
const SLOT_X0: float = 6.0          # (1080 − 5×204 − 4×12) / 2
## 칸 비율(204 : 412 = 0.495)은 `PilotImages.BUST_ASPECT`(0.496)와 같다 —
## 둘 중 하나만 바꾸면 얼굴이 찌그러진다.
const SLOT_ART_H: float = 412.0
const SLOT_BORDER: int = 3
const SLOT_RADIUS: int = 14
## 일러스트 아래 레벨 스테퍼 · 샐러리 · 종합 줄.
const STEP_GAP: float = 12.0
const STEP_H: float = 52.0
const STEP_BTN_W: float = 56.0
const INFO_LINE_H: float = 28.0
const SLOT_INFO_H: float = STEP_GAP + STEP_H + 6.0 + INFO_LINE_H * 2.0
## 블록 = 일러스트 + 레벨 / 샐러리 줄.
const SLOT_ROW_H: float = SLOT_ART_H + SLOT_INFO_H
## 블록 아랫변 ↔ 필터 줄.
const SLOT_FILTER_GAP: float = 32.0

const SLOT_FRAME_BG := OutgameTheme.SURFACE
const SLOT_FRAME_BG_EMPTY := OutgameTheme.SURFACE_SUNK
const SLOT_FRAME_BORDER_EMPTY := OutgameTheme.BORDER

# ─── 중: 필터 ────────────────────────────────────────────────────────────────
const FILTER_H: float = 64.0
const FILTER_GRID_GAP: float = 16.0
const FILTER_X0: float = 24.0
const FILTER_TOTAL_W: float = 1032.0
const FILTER_GAP: float = 8.0
const FILTER_LABELS: Array = ["전체", "탑", "정글", "미드", "원딜", "서폿"]
const FILTER_BG_ON  := OutgameTheme.ACCENT_DIM
const FILTER_BG_OFF := OutgameTheme.SURFACE
const FILTER_BORDER_ON  := OutgameTheme.ACCENT
const FILTER_BORDER_OFF := OutgameTheme.BORDER

# ─── 하: 썸네일 격자 ─────────────────────────────────────────────────────────
const GRID_BAR_GAP: float = 12.0
const GRID_X0: float = 24.0
const GRID_W: float = 1032.0
const GRID_COLS: int = 5
const GRID_GAP: float = 8.0
## **한 화면에 보이는 썸네일 줄 수.** 3.5 줄 — 반 줄이 잘려 보이는 것이 곧
## "아래로 더 있다"이다. 보유 선수가 적을 때는 뒤판이 빈 목록을 받쳐 준다.
const GRID_VISIBLE_ROWS: float = 3.5

# ─── 연출 ────────────────────────────────────────────────────────────────────
const MODE_ANIM_SEC: float = 0.38


# ─── 세로 배치 ───────────────────────────────────────────────────────────────
## 하단 버튼 줄의 y. 격자가 여기에 매달린다.
static func bar_y() -> float:
	return OutgameTheme.bottom_bar_top()


static func grid_h() -> float:
	var gaps: float = floor(GRID_VISIBLE_ROWS)
	return PilotThumb.CELL_H * GRID_VISIBLE_ROWS + GRID_GAP * gaps


static func grid_y() -> float:
	return bar_y() - GRID_BAR_GAP - grid_h()


static func filter_y() -> float:
	return grid_y() - FILTER_GRID_GAP - FILTER_H


## 게이지 윗변 — 단계 머리글 바로 아래.
static func gauge_y() -> float:
	return RunSetupScreen.content_top()


static func gauge_bottom() -> float:
	return gauge_y() + GAUGE_H


## PICK 모드에서 선택 5인 블록이 앉는 y — 필터 줄 바로 위(게이지와는 겹치지 않게).
static func pick_row_y() -> float:
	return maxf(gauge_bottom() + GAUGE_ROW_GAP,
			filter_y() - SLOT_FILTER_GAP - SLOT_ROW_H)


## CONFIRM 모드에서 선택 5인 블록이 내려앉는 y — **화면의 세로 가운데**.
## 게이지 아래 · 하단 바 위로만 걸러 낸다.
static func confirm_row_y() -> float:
	var lo: float = gauge_bottom() + GAUGE_ROW_GAP
	var hi: float = maxf(lo, bar_y() - SLOT_ROW_H - 20.0)
	return clampf((ScreenMetrics.safe_h() - SLOT_ROW_H) * 0.5, lo, hi)


@onready var _draft: TeamDraft = get_parent() as TeamDraft

var _picks: Array = [-1, -1, -1, -1, -1]   # 슬롯 인덱스 → pilot id (-1 = 빈 칸)
var _thumbs_by_id: Dictionary = {}         # pilot_id(int) → PilotThumb
var _entries: Array = []                   # Array[PlayerData], 화면 정렬 순서
var _filter_role: int = -1                 # -1 = 전체

var _confirm_mode: bool = false
## 모드 전환 연출 / 게임 시작 전환이 도는 중 — 그 사이의 입력은 무시한다.
var _busy: bool = false
var _mode_tween: Tween

# 게이지
var _gauge_title: Label
var _gauge_value: Label
var _gauge_fill: ColorRect
var _gauge_msg: Label
## 시작이 실패했을 때(`show_start_error`)의 문장. 다음 조작에서 지운다.
var _start_error: String = ""

var _slot_row: Control
var _slot_art: Array = []                  # 5 × TextureRect
var _slot_frame: Array = []                # 5 × Button (누르면 상세 팝업)
var _slot_minus: Array = []                # 5 × Button
var _slot_plus: Array = []                 # 5 × Button
var _slot_level: Array = []                # 5 × Label
var _slot_salary: Array = []               # 5 × Label
var _slot_total: Array = []                # 5 × Label
var _pick_root: Control
var _filter_btns: Array = []
var _grid_back: Panel
var _grid_scroll: ScrollContainer
var _grid_body: Control
var _next_btn: Button
var _confirm_btn: Button
var _back_btn: Button
var _bar_btns: Array = []
var _bar_specs: Array = []
var _detail: DraftDetailPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_reflow_grid()
	_refresh_slots()
	_apply_mode(false)


# ── Build ────────────────────────────────────────────────────────────────────
# 안전 영역 들여쓰기와 배경은 `RunSetupScreen` 이 화면째 한다 — 여기서 또 하면
# 두 번 내려간다.
func _build_ui() -> void:
	_build_gauge()
	_build_slot_row()
	# 픽창은 하단 바보다 **먼저** 붙는다 — 그래야 CONFIRM 으로 넘어갈 때 아래로
	# 빠지는 격자가 바 뒤로 숨는다.
	_pick_root = Control.new()
	_pick_root.position = Vector2.ZERO
	_pick_root.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.safe_h())
	_pick_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pick_root)
	_build_filter_row()
	_build_grid()
	_build_bottom_bar()

	_detail = DraftDetailPanel.new()
	add_child(_detail)


func _build_gauge() -> void:
	var card: Panel = OutgameTheme.add_card(self, Vector2(GAUGE_X, gauge_y()),
			Vector2(GAUGE_W, GAUGE_H), 18)
	var inner_w: float = GAUGE_W - GAUGE_PAD * 2.0
	_gauge_title = UiHelpers.mk_label(card, "", 26, OutgameTheme.TEXT_SUB,
			Vector2(GAUGE_PAD, GAUGE_PAD - 4.0), Vector2(inner_w * 0.6, 36))
	_gauge_title.clip_text = true
	_gauge_value = UiHelpers.mk_label(card, "", 34, OutgameTheme.TEXT,
			Vector2(GAUGE_PAD + inner_w * 0.4, GAUGE_PAD - 8.0),
			Vector2(inner_w * 0.6, 44), HORIZONTAL_ALIGNMENT_RIGHT)

	var track := ColorRect.new()
	track.color = OutgameTheme.SURFACE_SUNK
	track.position = Vector2(GAUGE_PAD, GAUGE_PAD + 48.0)
	track.size = Vector2(inner_w, GAUGE_BAR_H)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(track)
	_gauge_fill = ColorRect.new()
	_gauge_fill.color = OutgameTheme.ACCENT
	_gauge_fill.position = Vector2.ZERO
	_gauge_fill.size = Vector2(0, GAUGE_BAR_H)
	_gauge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_gauge_fill)

	_gauge_msg = UiHelpers.mk_label(card, "", 24, OutgameTheme.TEXT_SUB,
			Vector2(GAUGE_PAD, GAUGE_PAD + 80.0), Vector2(inner_w, 36))
	_gauge_msg.clip_text = true


func _slot_x(i: int) -> float:
	return SLOT_X0 + float(i) * (SLOT_W + SLOT_GAP)


func _build_slot_row() -> void:
	_slot_row = Control.new()
	_slot_row.position = Vector2(0.0, pick_row_y())
	_slot_row.size = Vector2(ScreenMetrics.vp_w(), SLOT_ROW_H)
	_slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_row)

	var b: float = float(SLOT_BORDER)
	for i in SLOT_COUNT:
		var role: int = int(TeamDraft.SLOT_ROLES[i])
		var x: float = _slot_x(i)

		# **일러스트 자체가 상세 팝업 버튼이다.** 슬롯을 비우는 조작은 격자에서
		# 같은 썸네일을 다시 누르는 것 하나뿐이라 이 칸에는 경쟁하는 탭이 없다.
		# **`flat` 로 두면 안 된다** — flat 버튼은 스타일박스를 통째로 무시한다.
		var frame := Button.new()
		frame.text = ""
		frame.focus_mode = Control.FOCUS_NONE
		frame.position = Vector2(x, 0.0)
		frame.size = Vector2(SLOT_W, SLOT_ART_H)
		frame.disabled = true
		frame.pressed.connect(_on_slot_pressed.bind(i))
		_slot_row.add_child(frame)
		_slot_frame.append(frame)

		var art: TextureRect = PilotThumb.add_rounded_art(frame, Vector2(b, b),
				Vector2(SLOT_W - b * 2.0, SLOT_ART_H - b * 2.0),
				SLOT_RADIUS - SLOT_BORDER)
		_slot_art.append(art)

		var empty := UiHelpers.mk_label(frame, "선택 없음", 26,
				OutgameTheme.TEXT_FAINT, Vector2(0, SLOT_ART_H * 0.5 - 20.0),
				Vector2(SLOT_W, 40), HORIZONTAL_ALIGNMENT_CENTER)
		empty.name = "EmptyMark"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# 역할군 배지 — **빈 칸에도 선다.** 빈 칸이 어느 역할의 자리인지를 말한다.
		PilotThumb.add_role_badge(frame, role, Vector2(b + 8.0, b + 8.0))

		# ── 레벨 스테퍼: [−] Lv N [+] ──────────────────────────────────────
		# 달성 최대 레벨이 1 이면 두 버튼이 다 잠긴다 — 그래도 자리는 선다
		# (레벨업 수단이 붙는 M10 에서 화면이 바뀌지 않도록).
		var step_y: float = SLOT_ART_H + STEP_GAP
		var minus := Button.new()
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(minus, 30)
		minus.position = Vector2(x, step_y)
		minus.size = Vector2(STEP_BTN_W, STEP_H)
		minus.pressed.connect(_on_level_step.bind(i, -1))
		_slot_row.add_child(minus)
		_slot_minus.append(minus)

		var plus := Button.new()
		plus.text = "+"
		plus.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(plus, 30)
		plus.position = Vector2(x + SLOT_W - STEP_BTN_W, step_y)
		plus.size = Vector2(STEP_BTN_W, STEP_H)
		plus.pressed.connect(_on_level_step.bind(i, 1))
		_slot_row.add_child(plus)
		_slot_plus.append(plus)

		var lv := UiHelpers.mk_label(_slot_row, "", 26, OutgameTheme.TEXT,
				Vector2(x + STEP_BTN_W, step_y),
				Vector2(SLOT_W - STEP_BTN_W * 2.0, STEP_H), HORIZONTAL_ALIGNMENT_CENTER)
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot_level.append(lv)

		var info_y: float = step_y + STEP_H + 6.0
		var sal := UiHelpers.mk_label(_slot_row, "", 22, OutgameTheme.ACCENT_TEXT,
				Vector2(x, info_y), Vector2(SLOT_W, INFO_LINE_H),
				HORIZONTAL_ALIGNMENT_CENTER)
		sal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot_salary.append(sal)
		var tot := UiHelpers.mk_label(_slot_row, "", 20, OutgameTheme.TEXT_SUB,
				Vector2(x, info_y + INFO_LINE_H), Vector2(SLOT_W, INFO_LINE_H),
				HORIZONTAL_ALIGNMENT_CENTER)
		tot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_slot_total.append(tot)


func _build_filter_row() -> void:
	var n: int = FILTER_LABELS.size()
	var w: float = (FILTER_TOTAL_W - FILTER_GAP * float(n - 1)) / float(n)
	for i in n:
		var btn := Button.new()
		btn.text = String(FILTER_LABELS[i])
		btn.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(btn, 26)
		btn.position = Vector2(FILTER_X0 + float(i) * (w + FILTER_GAP), filter_y())
		btn.size = Vector2(w, FILTER_H)
		# i == 0 이 "전체"(-1), 그 뒤는 `SLOT_ROLES` 와 같은 순서다.
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		btn.pressed.connect(_on_filter_pressed.bind(role))
		_pick_root.add_child(btn)
		_filter_btns.append(btn)
	_apply_filter_styles()


func _build_grid() -> void:
	# 격자 뒤판 — 필터를 좁히거나 보유 선수가 적으면 아래가 통째로 비는데,
	# 받침이 없으면 그 여백이 "화면이 끝났다"로 읽힌다.
	_grid_back = Panel.new()
	_grid_back.position = Vector2(GRID_X0 - 8.0, grid_y() - 8.0)
	_grid_back.size = Vector2(GRID_W + 16.0, grid_h() + 16.0)
	_grid_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_back.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.SURFACE, 12, OutgameTheme.BORDER, 2))
	_pick_root.add_child(_grid_back)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.position = Vector2(GRID_X0, grid_y())
	_grid_scroll.size = Vector2(GRID_W, grid_h())
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pick_root.add_child(_grid_scroll)
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`). 썸네일을 누른 채 끌기
	# 시작하면 그 눌림은 취소되므로 스크롤하려던 손이 파일럿을 고르지 않는다.
	DragScroll.attach(_grid_scroll)

	_grid_body = Control.new()
	_grid_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid_scroll.add_child(_grid_body)

	# 격자 순서는 **슬롯 순서 안에서 종합 스탯 내림차순**이다.
	# `TeamDraft.get_pool_grid()` 는 역할 열거값 순서로 돌려주므로 여기서
	# 슬롯 순서로 다시 묶는다.
	var by_role: Dictionary = {}
	for entry_raw in _draft.get_pool_grid():
		var entry: Dictionary = entry_raw
		var r: int = int(entry["role"])
		if not by_role.has(r):
			by_role[r] = []
		(by_role[r] as Array).append(entry["pilot"])
	for role_raw in TeamDraft.SLOT_ROLES:
		var role: int = int(role_raw)
		for p_raw in by_role.get(role, []):
			var p := p_raw as PlayerData
			_entries.append(p)
			var thumb := PilotThumb.new()
			_grid_body.add_child(thumb)
			thumb.setup(p, false)
			thumb.thumb_tapped.connect(_on_thumb_tapped)
			_thumbs_by_id[p.id] = thumb
			_refresh_thumb_tag(p.id)


## 하단 바 — `뒤로`(1) 는 언제나 서고, `다음` / `게임 시작`(2) 은 모드에 따라
## 하나만 선다. 보이는 칸만 무게대로 폭을 나눈다.
func _build_bottom_bar() -> void:
	_bar_specs = [
		{"text": "뒤로",      "style": "ghost",   "font": 30, "weight": 1.0},
		{"text": "다음",      "style": "primary", "font": 38, "weight": 2.0},
		{"text": "게임 시작", "style": "primary", "font": 38, "weight": 2.0},
	]
	_bar_btns = OutgameTheme.add_bottom_bar(self, _bar_specs)
	_back_btn    = _bar_btns[0]
	_next_btn    = _bar_btns[1]
	_confirm_btn = _bar_btns[2]
	_confirm_btn.visible = false
	_next_btn.disabled = true
	_back_btn.pressed.connect(_on_back_pressed)
	_next_btn.pressed.connect(_on_next_pressed)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	OutgameTheme.layout_bottom_bar(_bar_btns, _bar_specs)


# ── 바깥에서 부르는 것 (RunSetupScreen) ─────────────────────────────────────
## 시나리오가 바뀌었을 때 — 캡과 그 판정만 다시 그린다.
func refresh_rules() -> void:
	_start_error = ""
	_refresh_rules()


## `GameManager.start_run` 이 거절했을 때. 입력을 다시 받고 문장을 띄운다.
func show_start_error(msg: String) -> void:
	_busy = false
	_start_error = msg
	_refresh_rules()


## 런 준비를 떠날 때 — 팝업은 CanvasLayer 라 부모의 `visible` 을 따르지 않는다.
func close_detail() -> void:
	if _detail != null:
		_detail.close()


## 역할 순(`GameEnums.Role`)으로 늘어놓은 고른 id — 빈 칸은 빠진다.
## `run_setup.pilot_ids` 가 이 순서다(계약 §10.2).
func picked_ids_role_order() -> Array:
	var ids: Array = []
	for role in SLOT_COUNT:
		var slot: int = TeamDraft.slot_of_role(role)
		if slot >= 0 and int(_picks[slot]) != -1:
			ids.append(int(_picks[slot]))
	return ids


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_filter_pressed(role: int) -> void:
	if _busy or _filter_role == role:
		return
	_filter_role = role
	_apply_filter_styles()
	_reflow_grid()


## 필터가 바뀌면 **보이는 칸만** 좌표를 다시 받는다. 숨긴 칸을 격자에 그대로
## 두고 `visible` 만 끄면 빈 구멍이 남아 5열 배치가 무너진다.
func _reflow_grid() -> void:
	var shown: int = 0
	var cell_w: float = PilotThumb.CELL_W
	var cell_h: float = PilotThumb.CELL_H
	for p_raw in _entries:
		var p := p_raw as PlayerData
		var thumb: PilotThumb = _thumbs_by_id[p.id]
		if _filter_role != -1 and int(p.role) != _filter_role:
			thumb.visible = false
			continue
		thumb.visible = true
		var col: int = shown % GRID_COLS
		var row: int = floori(float(shown) / float(GRID_COLS))
		thumb.position = Vector2(float(col) * (cell_w + GRID_GAP),
				float(row) * (cell_h + GRID_GAP))
		shown += 1
	var rows: int = ceili(float(shown) / float(GRID_COLS))
	var body_h: float = float(rows) * cell_h + float(maxi(0, rows - 1)) * GRID_GAP
	_grid_body.custom_minimum_size = Vector2(GRID_W, body_h)
	_grid_body.size = Vector2(GRID_W, body_h)


func _on_thumb_tapped(pilot_id: int) -> void:
	if _busy or not _thumbs_by_id.has(pilot_id):
		return
	var thumb: PilotThumb = _thumbs_by_id[pilot_id]
	var slot: int = TeamDraft.slot_of_role(int(thumb.pilot.role))
	if slot < 0:
		return

	if int(_picks[slot]) == pilot_id:
		_picks[slot] = -1
		thumb.set_selected(false)
	else:
		var prev_id: int = int(_picks[slot])
		if prev_id != -1 and _thumbs_by_id.has(prev_id):
			(_thumbs_by_id[prev_id] as PilotThumb).set_selected(false)
		_picks[slot] = pilot_id
		thumb.set_selected(true)
	_start_error = ""
	_refresh_slots()


func _on_slot_pressed(slot: int) -> void:
	if _busy:
		return
	var pid: int = int(_picks[slot])
	if pid == -1:
		return
	# 상세는 **고른 레벨이 반영된 사본**으로 연다 — 칸 아래의 종합과 팝업의
	# 스탯 칩이 같은 숫자여야 한다.
	var p: PlayerData = _draft.leveled(pid)
	if p != null:
		_detail.open(p)


func _on_level_step(slot: int, delta: int) -> void:
	if _busy:
		return
	var pid: int = int(_picks[slot])
	if pid == -1:
		return
	if _draft.set_level(pid, _draft.level_of(pid) + delta):
		_start_error = ""
		_refresh_thumb_tag(pid)
		_refresh_slots()


func _on_next_pressed() -> void:
	if _busy or _validation_error() != "":
		return
	_confirm_mode = true
	_apply_mode(true)


func _on_back_pressed() -> void:
	if _busy:
		return
	if not _confirm_mode:
		_detail.close()
		_draft.back_requested.emit()
		return
	_confirm_mode = false
	_apply_mode(true)


## PICK ↔ CONFIRM. 바꾸는 것은 셋뿐이다 — 픽창(필터 + 격자)의 자리,
## 선택 5인 블록의 y, 그리고 `다음` / `게임 시작` 중 무엇이 서는가.
func _apply_mode(animate: bool) -> void:
	var picking: bool = not _confirm_mode
	_next_btn.visible = picking
	_confirm_btn.visible = not picking
	OutgameTheme.layout_bottom_bar(_bar_btns, _bar_specs)
	_refresh_action_btns()

	var row_y: float = pick_row_y() if picking else confirm_row_y()
	# 픽창이 빠지는 거리 — 필터 줄 윗변이 화면 아래끝을 넘을 만큼.
	var pick_y: float = 0.0 if picking \
			else ScreenMetrics.safe_h() - filter_y() + 40.0
	if _mode_tween != null and _mode_tween.is_valid():
		_mode_tween.kill()
	if not animate:
		_slot_row.position.y = row_y
		_pick_root.position.y = pick_y
		_pick_root.visible = picking
		_busy = false
		return

	_busy = true
	_pick_root.visible = true
	_mode_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_mode_tween.tween_property(_pick_root, "position:y", pick_y, MODE_ANIM_SEC)
	_mode_tween.tween_property(_slot_row, "position:y", row_y, MODE_ANIM_SEC)
	_mode_tween.chain().tween_callback(_on_mode_anim_done.bind(picking))


func _on_mode_anim_done(picking: bool) -> void:
	# 다 빠진 픽창은 숨긴다 — 화면 밖이라도 남아 있으면 스크롤 · 버튼이 계속
	# 입력 경로에 걸린다.
	_pick_root.visible = picking
	_busy = false


## **`게임 시작`** — 규칙 검사는 **암전 전에** 한다(거절될 시작이면 화면을
## 가리지 않는다). 런을 여는 일은 `RunSetupScreen` 이 한다.
func _on_confirm_pressed() -> void:
	if _busy:
		return
	var err: String = _validation_error()
	if err != "":
		_refresh_rules()
		return
	_busy = true
	_draft.start_requested.emit(picked_ids_role_order())


# ── Refresh ──────────────────────────────────────────────────────────────────
func _validation_error() -> String:
	return _draft.validate(picked_ids_role_order())


func _refresh_slots() -> void:
	for i in SLOT_COUNT:
		var pid: int = int(_picks[i])
		var p: PlayerData = _draft.leveled(pid) if pid != -1 else null
		var role: int = int(TeamDraft.SLOT_ROLES[i])
		var frame: Button = _slot_frame[i]
		var art: TextureRect = _slot_art[i]
		var empty_mark: Label = frame.get_node("EmptyMark") as Label
		var sty := StyleBoxFlat.new()
		OutgameTheme.set_corner_radius(sty, SLOT_RADIUS)
		sty.set_border_width_all(SLOT_BORDER)

		var minus: Button = _slot_minus[i]
		var plus: Button = _slot_plus[i]
		var lv_lbl: Label = _slot_level[i]
		var sal_lbl: Label = _slot_salary[i]
		var tot_lbl: Label = _slot_total[i]
		if p == null:
			art.texture = null
			empty_mark.visible = true
			sty.bg_color = SLOT_FRAME_BG_EMPTY
			sty.border_color = SLOT_FRAME_BORDER_EMPTY
			frame.disabled = true
			minus.visible = false
			plus.visible = false
			lv_lbl.text = ""
			sal_lbl.text = ""
			tot_lbl.text = ""
		else:
			art.texture = PilotImages.bust_for(p.id)
			empty_mark.visible = false
			sty.bg_color = SLOT_FRAME_BG
			sty.border_color = ROLE_COLORS[role]
			frame.disabled = false
			var lv: int = _draft.level_of(pid)
			var top: int = _draft.max_level_of(pid)
			minus.visible = true
			plus.visible = true
			minus.disabled = lv <= 1
			plus.disabled = lv >= top
			lv_lbl.text = "Lv %d" % lv
			sal_lbl.text = "샐러리 %d" % _draft.salary_of(pid)
			tot_lbl.text = "종합 %d" % p.stat_total()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			frame.add_theme_stylebox_override(st, sty)
	_refresh_rules()


## 게이지 · 규칙 줄 · 하단 버튼 잠금. 고를 때마다 다시 그린다.
func _refresh_rules() -> void:
	var ids: Array = picked_ids_role_order()
	var cap: int = _draft.salary_cap()
	var total: int = _draft.lineup_salary(ids)
	var over: bool = cap > 0 and total > cap
	var scen: Dictionary = RunRules.scenario(_draft.scenario_id)
	_gauge_title.text = "%s · 샐러리캡" % String(scen.get("name", "?"))
	# M8 — trait `salary_cap` adjustment, when the manager preset carries one.
	var trait_adj: int = _draft.cap_bonus()
	if trait_adj != 0:
		_gauge_title.text += " (특성 %s)" % ManagerUi.signed(trait_adj)
	_gauge_value.text = "%d / %d" % [total, cap]
	_gauge_value.add_theme_color_override("font_color",
			OutgameTheme.NEGATIVE if over else OutgameTheme.TEXT)
	var ratio: float = clampf(float(total) / float(cap), 0.0, 1.0) if cap > 0 else 0.0
	_gauge_fill.size = Vector2((GAUGE_W - GAUGE_PAD * 2.0) * ratio, GAUGE_BAR_H)
	_gauge_fill.color = OutgameTheme.NEGATIVE if over else OutgameTheme.ACCENT

	var err: String = _draft.validate(ids)
	var msg: String = err
	var col: Color = OutgameTheme.TEXT_SUB
	if _start_error != "":
		msg = "시작 실패: " + _start_error
		col = OutgameTheme.NEGATIVE
	elif over:
		# 다섯을 다 고르기 전이라도 캡을 넘겼으면 그것부터 말한다 — 빈 칸을
		# 채우면 더 넘칠 뿐이다.
		msg = "샐러리캡 초과 (%d / %d) — 레벨을 내리거나 다른 선수를 고르세요" % [total, cap]
		col = OutgameTheme.NEGATIVE
	elif ids.size() < SLOT_COUNT:
		msg = "포지션마다 1명씩 — %d / %d명" % [ids.size(), SLOT_COUNT]
	elif err != "":
		col = OutgameTheme.NEGATIVE
	else:
		msg = "편성 완료 — 남은 샐러리 %d" % (cap - total) if cap > 0 else "편성 완료"
		col = OutgameTheme.POSITIVE
	_gauge_msg.text = msg
	_gauge_msg.add_theme_color_override("font_color", col)
	_refresh_action_btns()


func _refresh_action_btns() -> void:
	var ok: bool = _validation_error() == ""
	_next_btn.disabled = not ok
	_confirm_btn.disabled = not ok


func _refresh_thumb_tag(pilot_id: int) -> void:
	var thumb: PilotThumb = _thumbs_by_id.get(pilot_id, null) as PilotThumb
	if thumb != null:
		thumb.set_tag(str(_draft.salary_of(pilot_id)))


func _apply_filter_styles() -> void:
	for i in _filter_btns.size():
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		var on: bool = role == _filter_role
		var sty := OutgameTheme.flat_style(
				FILTER_BG_ON if on else FILTER_BG_OFF, 8,
				FILTER_BORDER_ON if on else FILTER_BORDER_OFF, 3 if on else 2)
		var btn: Button = _filter_btns[i]
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, sty)
