class_name TeamDraftView
extends Control

# 초기 팀 드래프트 화면 — **우마무스메식 인물 고르기**.
#
#   상: 선택한 5인의 **상체 일러스트**가 가로로 나란히 (탑 · 정글 · 미드 · 원딜 · 서폿)
#       일러스트를 누르면 `DraftDetailPanel` 이 열린다
#   중: 전체 / 탑 / 정글 / 미드 / 원딜 / 서폿 필터 버튼 한 줄
#   하: 캐릭터 썸네일 격자 (세로 스크롤)
#   맨 아래: 가운데 큰 "다음"
#
# **화면은 두 모드를 오간다.** PICK 은 위와 같고, "다음"을 누르면 CONFIRM 으로
# 넘어가 **픽창(필터 + 격자)이 통째로 사라지고 선택 5인이 화면 가운데로 내려온다** —
# 확정 직전에 보아야 하는 것은 후보 스물다섯이 아니라 내가 고른 다섯이기
# 때문이다. 거기서 "드래프트 확정"이 팀을 확정하고, 그 왼쪽의 작은 "뒤로"가
# 다시 픽창을 연다.
#
# **화면에서 걷어 낸 것들** — 제목("TEAM DRAFT")과 인원 수("내 팀 N/5")는
# 다섯 칸이 채워지는 것 자체가 이미 말해 주고, 일러스트 밑의 `역할 · 원소속`
# 한 줄과 하단의 파일럿 스킬 구성 패널은 **상세 팝업이 통째로 들고 있다**.
# 고르는 화면에 요약을 늘어놓으면 그 요약을 읽느라 정작 얼굴을 안 본다.
#
# **다섯 칸은 역할 고정**이다(`TeamDraft.SLOT_ROLES`). `TeamDraft.validate_draft`
# 가 "역할당 정확히 1명"을 강제하므로 자유 순서로 두면 화면에서만 가능한 조합이
# 생겨 확정 버튼에서 처음 거절당한다 — 규칙은 고를 때 보여야 한다.

## 역할 색은 팔레트가 소유한다 — 화면마다 자기 배열을 들면 같은 역할이
## 화면마다 다른 색으로 그려진다.
const ROLE_COLORS: Array = OutgameTheme.ROLE_COLORS

const BG_COLOR := OutgameTheme.BG

# ─── 상: 선택 5인 ────────────────────────────────────────────────────────────
# 다섯 칸은 `_slot_row` 한 Control 안의 **지역 좌표**로 산다 — CONFIRM 모드가
# 그 한 노드의 y 하나만 밀어 블록째 화면 가운데로 내리기 때문이다.
const SLOT_COUNT: int = 5
const SLOT_W: float = 204.0
const SLOT_GAP: float = 12.0
const SLOT_X0: float = 6.0          # (1080 − 5×204 − 4×12) / 2
const SLOT_TAG_H: float = 28.0
const SLOT_ART_Y: float = 32.0
## 칸 비율(204 : 412 = 0.495)은 `PilotImages.BUST_ASPECT`(0.496)와 같다 —
## 둘 중 하나만 바꾸면 얼굴이 찌그러진다.
const SLOT_ART_H: float = 412.0
const SLOT_NAME_Y: float = 448.0
const SLOT_NAME_H: float = 54.0
const SLOT_ROW_H: float = 502.0
## PICK 모드에서 선택 5인 블록이 앉는 y.
const SLOT_ROW_Y: float = 24.0

const SLOT_FRAME_BG := OutgameTheme.SURFACE
const SLOT_FRAME_BG_EMPTY := OutgameTheme.SURFACE_SUNK
const SLOT_FRAME_BORDER_EMPTY := OutgameTheme.BORDER

# ─── 중: 필터 ────────────────────────────────────────────────────────────────
const FILTER_Y: float = 546.0
const FILTER_H: float = 64.0
const FILTER_X0: float = 24.0
const FILTER_TOTAL_W: float = 1032.0
const FILTER_GAP: float = 8.0
const FILTER_LABELS: Array = ["전체", "탑", "정글", "미드", "원딜", "서폿"]
const FILTER_BG_ON  := OutgameTheme.ACCENT_DIM
const FILTER_BG_OFF := OutgameTheme.SURFACE
const FILTER_BORDER_ON  := OutgameTheme.ACCENT
const FILTER_BORDER_OFF := OutgameTheme.BORDER

# ─── 하: 썸네일 격자 ─────────────────────────────────────────────────────────
const GRID_Y: float = 626.0
const GRID_BAR_GAP: float = 12.0
const GRID_X0: float = 24.0
const GRID_W: float = 1032.0
const GRID_COLS: int = 5
const GRID_GAP: float = 8.0


## 격자 높이는 상수가 아니라 **남는 자리**다 — 필터 줄 아래부터 하단 버튼 위까지.
static func grid_h() -> float:
	return bar_y() - GRID_BAR_GAP - GRID_Y


# ─── 맨 아래: 다음 / 확정 ────────────────────────────────────────────────────
## **하단 구간을 통째로 차지하는 바 한 줄**이다(`OutgameTheme.add_bottom_bar`).
## PICK 에서는 "다음"이 화면 폭 전체를, CONFIRM 에서는 "뒤로"(1) 와
## "드래프트 확정"(2) 이 2:1 로 나눠 갖는다 — 그 화면이 묻는 것은 확정할
## 것인가 하나이므로 되돌아가는 길은 3분의 1로 족하다.


## 하단 버튼 줄의 y. 격자 높이가 여기서 역산된다.
static func bar_y() -> float:
	return OutgameTheme.bottom_bar_top()


## CONFIRM 모드에서 선택 5인 블록이 내려앉는 y — **화면의 세로 가운데**.
## 하단 버튼 줄과 겹치지 않게만 걸러 낸다(짧은 화면에서는 그 위로 밀린다).
static func confirm_row_y() -> float:
	return clampf((ScreenMetrics.safe_h() - SLOT_ROW_H) * 0.5,
			SLOT_ROW_Y, maxf(SLOT_ROW_Y, bar_y() - SLOT_ROW_H - 20.0))


@onready var _draft: TeamDraft = get_parent() as TeamDraft

var _picks: Array = [-1, -1, -1, -1, -1]   # 슬롯 인덱스 → pilot id (-1 = 빈 칸)
var _thumbs_by_id: Dictionary = {}         # pilot_id(int) → PilotThumb
var _entries: Array = []                   # Array[PlayerData], 화면 정렬 순서
var _filter_role: int = -1                 # -1 = 전체

## 확정 직전 화면인가. true 면 픽창이 사라지고 선택 5인이 가운데로 내려온다.
var _confirm_mode: bool = false

var _slot_row: Control
var _slot_art: Array = []                  # 5 × TextureRect
var _slot_frame: Array = []                # 5 × Button (누르면 상세 팝업)
var _slot_name_lbl: Array = []             # 5 × Label
var _filter_btns: Array = []               # 6 × Button
var _grid_back: Panel
var _grid_scroll: ScrollContainer
var _grid_body: Control
var _next_btn: Button
var _confirm_btn: Button
var _back_btn: Button
## 하단 바의 칸 셋과 그 무게. 모드가 바뀌어 보이는 칸이 달라지면
## `layout_bottom_bar` 가 이 둘을 다시 읽어 폭을 나눈다.
var _bar_btns: Array = []
var _bar_specs: Array = []
var _detail: DraftDetailPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_reflow_grid()
	_refresh_slots()
	_apply_mode()


# ── Build ────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 일러스트가 깔리지 않게.
	ScreenMetrics.indent_to_safe_top(self)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 배경만은 안전 영역 밖(노치 자리)까지 덮는다 — 안 그러면 그 띠가
	# 엔진 기본 배경색으로 남는다.
	ScreenMetrics.extend_background(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_slot_row()
	_build_filter_row()
	_build_grid()
	_build_bottom_bar()

	_detail = DraftDetailPanel.new()
	add_child(_detail)


func _slot_x(i: int) -> float:
	return SLOT_X0 + float(i) * (SLOT_W + SLOT_GAP)


func _build_slot_row() -> void:
	_slot_row = Control.new()
	_slot_row.position = Vector2(0.0, SLOT_ROW_Y)
	_slot_row.size = Vector2(ScreenMetrics.vp_w(), SLOT_ROW_H)
	_slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_row)

	for i in SLOT_COUNT:
		var role: int = int(TeamDraft.SLOT_ROLES[i])
		var col: Color = ROLE_COLORS[role]
		var x: float = _slot_x(i)

		UiHelpers.mk_label(_slot_row, String(TeamDraft.SLOT_NAMES[i]), 24, col,
				Vector2(x, 0.0), Vector2(SLOT_W, SLOT_TAG_H),
				HORIZONTAL_ALIGNMENT_CENTER)

		# **일러스트 자체가 상세 팝업 버튼이다.** 예전에는 아래 이름 칸이 그
		# 역할을 했는데(일러스트를 누르면 슬롯을 비우려는 탭과 헷갈린다는
		# 이유였다), 슬롯을 비우는 조작은 격자에서 같은 썸네일을 다시 누르는
		# 것 하나뿐이라 위 칸에는 애초에 경쟁하는 탭이 없다 — 인게임에서
		# 파일럿 얼굴을 눌러 상세를 여는 것과 같은 몸짓이 된다.
		# **`flat` 로 두면 안 된다** — flat 버튼은 스타일박스를 통째로 무시해서
		# 빈 칸의 테두리와 바탕이 사라지고 "선택 없음" 글자만 허공에 뜬다.
		var frame := Button.new()
		frame.text = ""
		frame.focus_mode = Control.FOCUS_NONE
		frame.position = Vector2(x, SLOT_ART_Y)
		frame.size = Vector2(SLOT_W, SLOT_ART_H)
		frame.clip_contents = true
		frame.disabled = true
		frame.pressed.connect(_on_slot_pressed.bind(i))
		_slot_row.add_child(frame)
		_slot_frame.append(frame)

		var art := TextureRect.new()
		art.position = Vector2.ZERO
		art.size = Vector2(SLOT_W, SLOT_ART_H)
		art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(art)
		_slot_art.append(art)

		var empty := UiHelpers.mk_label(frame, "선택 없음", 26,
				OutgameTheme.TEXT_FAINT, Vector2(0, SLOT_ART_H * 0.5 - 20.0),
				Vector2(SLOT_W, 40), HORIZONTAL_ALIGNMENT_CENTER)
		empty.name = "EmptyMark"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var nm := UiHelpers.mk_label(_slot_row, "—", 26, OutgameTheme.TEXT,
				Vector2(x, SLOT_NAME_Y), Vector2(SLOT_W, SLOT_NAME_H),
				HORIZONTAL_ALIGNMENT_CENTER)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.clip_text = true
		_slot_name_lbl.append(nm)


func _build_filter_row() -> void:
	var n: int = FILTER_LABELS.size()
	var w: float = (FILTER_TOTAL_W - FILTER_GAP * float(n - 1)) / float(n)
	for i in n:
		var btn := Button.new()
		btn.text = String(FILTER_LABELS[i])
		btn.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(btn, 26)
		btn.position = Vector2(FILTER_X0 + float(i) * (w + FILTER_GAP), FILTER_Y)
		btn.size = Vector2(w, FILTER_H)
		# i == 0 이 "전체"(-1), 그 뒤는 `SLOT_ROLES` 와 같은 순서다 — 필터 버튼과
		# 위쪽 다섯 칸이 같은 표를 읽으므로 순서가 갈릴 수 없다.
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		btn.pressed.connect(_on_filter_pressed.bind(role))
		add_child(btn)
		_filter_btns.append(btn)
	_apply_filter_styles()


func _build_grid() -> void:
	# 격자 뒤판 — 필터를 좁히면 칸이 다섯 개만 남아 아래가 통째로 비는데,
	# 받침이 없으면 그 여백이 "화면이 끝났다"로 읽힌다. 스크롤 영역의 경계를
	# 색으로 못 박아 두면 빈 목록도 빈 목록으로 보인다.
	_grid_back = Panel.new()
	_grid_back.position = Vector2(GRID_X0 - 8.0, GRID_Y - 8.0)
	_grid_back.size = Vector2(GRID_W + 16.0, grid_h() + 16.0)
	_grid_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back_sty := StyleBoxFlat.new()
	back_sty.bg_color = OutgameTheme.SURFACE
	back_sty.border_color = OutgameTheme.BORDER
	back_sty.border_width_left = 2
	back_sty.border_width_right = 2
	back_sty.border_width_top = 2
	back_sty.border_width_bottom = 2
	back_sty.corner_radius_top_left     = 12
	back_sty.corner_radius_top_right    = 12
	back_sty.corner_radius_bottom_left  = 12
	back_sty.corner_radius_bottom_right = 12
	_grid_back.add_theme_stylebox_override("panel", back_sty)
	add_child(_grid_back)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.position = Vector2(GRID_X0, GRID_Y)
	_grid_scroll.size = Vector2(GRID_W, grid_h())
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_grid_scroll)

	# 스크롤 범위는 이 Control 의 `custom_minimum_size` 가 정한다 — 칸을
	# 좌표로 놓으므로 컨테이너가 아니라 빈 Control 이 몸통이다.
	_grid_body = Control.new()
	_grid_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid_scroll.add_child(_grid_body)

	# 격자 순서는 **슬롯 순서(탑 → 정글 → 미드 → 원딜 → 서폿) 안에서 종합
	# 스탯 내림차순**이다. `TeamDraft.get_pool_grid()` 는 역할 열거값 순서로
	# 돌려주므로 여기서 슬롯 순서로 다시 묶는다 — 필터 버튼의 순서와 격자의
	# 순서가 어긋나면 "정글 다음이 미드"라는 읽기 기준이 깨진다.
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


## 세 칸을 한 번에 세우고 **모드가 그중 무엇을 보이게 할지만 정한다** —
## "다음"과 "드래프트 확정"은 서로 배타라 언제나 하나만 서고, 보이는 칸만
## 무게대로 폭을 나눠 가지므로 PICK 에서는 "다음"이 화면 폭을 통째로 쓴다.
func _build_bottom_bar() -> void:
	_bar_specs = [
		{"text": "뒤로",          "style": "ghost",   "font": 30, "weight": 1.0},
		{"text": "다음",          "style": "primary", "font": 38, "weight": 2.0},
		{"text": "드래프트 확정", "style": "primary", "font": 38, "weight": 2.0},
	]
	_bar_btns = OutgameTheme.add_bottom_bar(self, _bar_specs)
	_back_btn    = _bar_btns[0]
	_next_btn    = _bar_btns[1]
	_confirm_btn = _bar_btns[2]
	_back_btn.visible = false
	_confirm_btn.visible = false
	_next_btn.disabled = true
	_back_btn.pressed.connect(_on_back_pressed)
	_next_btn.pressed.connect(_on_next_pressed)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	OutgameTheme.layout_bottom_bar(_bar_btns, _bar_specs)


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_filter_pressed(role: int) -> void:
	if _filter_role == role:
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
		@warning_ignore("integer_division")
		var row: int = shown / GRID_COLS
		thumb.position = Vector2(float(col) * (cell_w + GRID_GAP),
				float(row) * (cell_h + GRID_GAP))
		shown += 1
	var rows: int = int(ceil(float(shown) / float(GRID_COLS)))
	var body_h: float = float(rows) * cell_h + float(maxi(0, rows - 1)) * GRID_GAP
	_grid_body.custom_minimum_size = Vector2(GRID_W, body_h)
	_grid_body.size = Vector2(GRID_W, body_h)


func _on_thumb_tapped(pilot_id: int) -> void:
	if not _thumbs_by_id.has(pilot_id):
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

	_refresh_slots()
	_refresh_next_btn()


func _on_slot_pressed(slot: int) -> void:
	var p: PlayerData = _pilot_in_slot(slot)
	if p == null:
		return
	_detail.open(p)


func _on_next_pressed() -> void:
	if not _all_filled():
		return
	_confirm_mode = true
	_apply_mode()


func _on_back_pressed() -> void:
	_confirm_mode = false
	_apply_mode()


## PICK ↔ CONFIRM. 바꾸는 것은 셋뿐이다 — 픽창(필터 + 격자)의 표시 여부,
## 선택 5인 블록의 y, 그리고 하단 버튼 셋 중 무엇이 서는가.
func _apply_mode() -> void:
	var picking: bool = not _confirm_mode
	for btn_raw in _filter_btns:
		(btn_raw as Button).visible = picking
	_grid_back.visible = picking
	_grid_scroll.visible = picking
	_next_btn.visible = picking
	_confirm_btn.visible = not picking
	_back_btn.visible = not picking
	# 보이는 칸이 바뀌었으니 하단 구간을 다시 나눠 준다 — 안 하면 PICK 의
	# "다음"이 CONFIRM 에서 쓰던 3분의 2 폭을 그대로 들고 서 있는다.
	OutgameTheme.layout_bottom_bar(_bar_btns, _bar_specs)
	_slot_row.position.y = SLOT_ROW_Y if picking else confirm_row_y()
	_refresh_next_btn()


# ── Refresh ──────────────────────────────────────────────────────────────────
func _pilot_in_slot(slot: int) -> PlayerData:
	var pid: int = int(_picks[slot])
	if pid == -1 or not _thumbs_by_id.has(pid):
		return null
	return (_thumbs_by_id[pid] as PilotThumb).pilot


func _refresh_slots() -> void:
	for i in SLOT_COUNT:
		var p: PlayerData = _pilot_in_slot(i)
		var role: int = int(TeamDraft.SLOT_ROLES[i])
		var frame: Button = _slot_frame[i]
		var art: TextureRect = _slot_art[i]
		var empty_mark: Label = frame.get_node("EmptyMark") as Label
		var sty := StyleBoxFlat.new()
		sty.corner_radius_top_left     = 10
		sty.corner_radius_top_right    = 10
		sty.corner_radius_bottom_left  = 10
		sty.corner_radius_bottom_right = 10
		sty.border_width_left = 3
		sty.border_width_right = 3
		sty.border_width_top = 3
		sty.border_width_bottom = 3

		if p == null:
			art.texture = null
			empty_mark.visible = true
			sty.bg_color = SLOT_FRAME_BG_EMPTY
			sty.border_color = SLOT_FRAME_BORDER_EMPTY
			_slot_name_lbl[i].text = "—"
			_slot_name_lbl[i].add_theme_color_override("font_color",
					OutgameTheme.TEXT_FAINT)
			frame.disabled = true
		else:
			art.texture = PilotImages.bust_for(p.id)
			empty_mark.visible = false
			sty.bg_color = SLOT_FRAME_BG
			sty.border_color = ROLE_COLORS[role]
			_slot_name_lbl[i].text = p.name
			_slot_name_lbl[i].add_theme_color_override("font_color",
					OutgameTheme.TEXT)
			frame.disabled = false
		# 채워진 칸은 눌러서 상세를 여는 버튼이므로 다섯 상태 전부 같은 스타일을
		# 준다 — flat 버튼이라도 hover / pressed 는 기본 테마가 덧칠한다.
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			frame.add_theme_stylebox_override(st, sty)


func _all_filled() -> bool:
	for i in SLOT_COUNT:
		if int(_picks[i]) == -1:
			return false
	return true


func _refresh_next_btn() -> void:
	_next_btn.disabled = not _all_filled()


func _apply_filter_styles() -> void:
	for i in _filter_btns.size():
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		var on: bool = role == _filter_role
		var sty := StyleBoxFlat.new()
		sty.bg_color     = FILTER_BG_ON if on else FILTER_BG_OFF
		sty.border_color = FILTER_BORDER_ON if on else FILTER_BORDER_OFF
		var w: int = 3 if on else 2
		sty.border_width_left = w
		sty.border_width_right = w
		sty.border_width_top = w
		sty.border_width_bottom = w
		sty.corner_radius_top_left     = 8
		sty.corner_radius_top_right    = 8
		sty.corner_radius_bottom_left  = 8
		sty.corner_radius_bottom_right = 8
		var btn: Button = _filter_btns[i]
		btn.add_theme_stylebox_override("normal",  sty)
		btn.add_theme_stylebox_override("hover",   sty)
		btn.add_theme_stylebox_override("pressed", sty)
		btn.add_theme_stylebox_override("focus",   sty)


func _on_confirm_pressed() -> void:
	if not _all_filled():
		return
	# 확정은 **역할 순서(GameEnums.Role)** 로 넘긴다 — `validate_draft` 는 순서를
	# 보지 않지만, 화면의 슬롯 순서(탑 · 정글 · 미드 · 원딜 · 서폿)를 그대로
	# 흘려보내면 이 목록이 무엇의 순서인지가 호출부마다 달라진다.
	var ids: Array = []
	for role in 5:
		var slot: int = TeamDraft.slot_of_role(role)
		ids.append(int(_picks[slot]))
	var err: String = _draft.apply_draft(ids)
	if err != "":
		push_error("TeamDraftView: confirm failed — " + err)
		return
	# 팝업은 CanvasLayer 라 부모 Control 의 `visible` 을 따르지 않는다 — 열어 둔
	# 채 허브로 넘어가면 딤이 화면에 그대로 남는다.
	_detail.close()
	var hub: SeasonHub = _draft.get_parent() as SeasonHub
	if hub:
		hub.goto(SeasonHub.Screen.HUB)
