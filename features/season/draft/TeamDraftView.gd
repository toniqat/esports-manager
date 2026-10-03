class_name TeamDraftView
extends Control

# 초기 팀 드래프트 화면 — **우마무스메식 인물 고르기**.
#
#   상: 선택한 5인의 **상체 일러스트**가 가로로 나란히 (탑 · 정글 · 미드 · 원딜 · 서폿)
#       일러스트 왼쪽 위에 역할군 배지. 일러스트를 누르면 `DraftDetailPanel` 이 열린다
#   중: 전체 / 탑 / 정글 / 미드 / 원딜 / 서폿 필터 버튼 한 줄
#   하: 캐릭터 썸네일 격자 (세로 스크롤, 3.5줄이 보인다)
#   맨 아래: 하단 바 "다음"
#
# 세 덩이는 **아래에서 위로** 쌓는다 — 격자를 하단 바 위에 매달고, 필터와 선택
# 5인이 그 위에 차례로 앉는다. 격자를 3.5줄로 줄인 만큼 선택 5인이 내려왔다.
#
# **화면은 두 모드를 오간다.** PICK 은 위와 같고, "다음"을 누르면 CONFIRM 으로
# 넘어가 **픽창(필터 + 격자)이 화면 아래로 빠지고 선택 5인이 화면 가운데로
# 내려온다**(연출, `_apply_mode`) — 확정 직전에 보아야 하는 것은 후보 스물다섯이
# 아니라 내가 고른 다섯이기 때문이다. 거기서 **"게임 시작"**이 팀을 확정하고
# 암전 → 가짜 로딩 → 밝아짐을 거쳐 시즌 허브로 넘어간다. 그 왼쪽의 "뒤로"가
# 픽창을 다시 올린다.
#
# **화면에서 걷어 낸 것들** — 제목("TEAM DRAFT")과 인원 수("내 팀 N/5")는
# 다섯 칸이 채워지는 것 자체가 이미 말해 주고, 일러스트 위의 포지션 글자와
# 아래의 이름은 각각 **역할군 배지**와 **상세 팝업**이 들고 있다.
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
## 칸 비율(204 : 412 = 0.495)은 `PilotImages.BUST_ASPECT`(0.496)와 같다 —
## 둘 중 하나만 바꾸면 얼굴이 찌그러진다.
const SLOT_ART_H: float = 412.0
## 블록은 **일러스트 한 줄뿐이다.** 예전에는 위에 포지션 글자(탑 · 정글 …)가,
## 아래에 이름이 붙어 502px 였는데 둘 다 걷었다 — 역할은 일러스트 왼쪽 위의
## 역할군 배지가(격자 썸네일과 같은 배지), 이름은 상세 팝업이 들고 있다.
const SLOT_ROW_H: float = SLOT_ART_H
## 일러스트 테두리(역할 색)의 두께와 굴림. 그림은 그 두께만큼 안으로 물려
## 앉아 테두리가 그림에 덮이지 않는다.
const SLOT_BORDER: int = 3
const SLOT_RADIUS: int = 14
## 블록 아랫변 ↔ 필터 줄.
const SLOT_FILTER_GAP: float = 32.0

const SLOT_FRAME_BG := OutgameTheme.SURFACE
const SLOT_FRAME_BG_EMPTY := OutgameTheme.SURFACE_SUNK
const SLOT_FRAME_BORDER_EMPTY := OutgameTheme.BORDER

# ─── 중: 필터 ────────────────────────────────────────────────────────────────
const FILTER_H: float = 64.0
## 필터 줄 아랫변 ↔ 격자 윗변.
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
## "아래로 더 있다"이다. 예전에는 필터 아래부터 하단 바 위까지를 통째로 격자에
## 주어 다섯 줄 남짓이 깔렸고, 그만큼 선택 5인이 화면 꼭대기로 밀려 있었다.
const GRID_VISIBLE_ROWS: float = 3.5

# ─── 연출 ────────────────────────────────────────────────────────────────────
## PICK ↔ CONFIRM 전환. 픽창이 아래로 빠지는 것과 5인이 가운데로 내려오는
## 것이 같은 박자로 돈다.
const MODE_ANIM_SEC: float = 0.38
## "게임 시작" 전환 — 암전 → 가짜 로딩 → 밝아짐.
const LAUNCH_FADE_OUT_SEC: float = 0.30
const LAUNCH_LOAD_SEC: float = 0.50
const LAUNCH_FADE_IN_SEC: float = 0.35
const LAUNCH_BAR_W: float = 420.0


# ─── 세로 배치 — 아래에서 위로 ───────────────────────────────────────────────
## 하단 버튼 줄의 y. 격자가 여기에 매달린다.
##
## **하단 구간을 통째로 차지하는 바 한 줄**이다(`OutgameTheme.add_bottom_bar`).
## PICK 에서는 "다음"이 화면 폭 전체를, CONFIRM 에서는 "뒤로"(1) 와
## "게임 시작"(2) 이 2:1 로 나눠 갖는다.
static func bar_y() -> float:
	return OutgameTheme.bottom_bar_top()


## 격자 높이 — 썸네일 `GRID_VISIBLE_ROWS` 줄과 그 사이 간격.
static func grid_h() -> float:
	var gaps: float = floor(GRID_VISIBLE_ROWS)
	return PilotThumb.CELL_H * GRID_VISIBLE_ROWS + GRID_GAP * gaps


static func grid_y() -> float:
	return bar_y() - GRID_BAR_GAP - grid_h()


static func filter_y() -> float:
	return grid_y() - FILTER_GRID_GAP - FILTER_H


## PICK 모드에서 선택 5인 블록이 앉는 y — 필터 줄 바로 위.
static func pick_row_y() -> float:
	return maxf(0.0, filter_y() - SLOT_FILTER_GAP - SLOT_ROW_H)


## CONFIRM 모드에서 선택 5인 블록이 내려앉는 y — **화면의 세로 가운데**.
## 하단 버튼 줄과 겹치지 않게만 걸러 낸다(짧은 화면에서는 그 위로 밀린다).
static func confirm_row_y() -> float:
	return clampf((ScreenMetrics.safe_h() - SLOT_ROW_H) * 0.5,
			0.0, maxf(0.0, bar_y() - SLOT_ROW_H - 20.0))


@onready var _draft: TeamDraft = get_parent() as TeamDraft

var _picks: Array = [-1, -1, -1, -1, -1]   # 슬롯 인덱스 → pilot id (-1 = 빈 칸)
var _thumbs_by_id: Dictionary = {}         # pilot_id(int) → PilotThumb
var _entries: Array = []                   # Array[PlayerData], 화면 정렬 순서
var _filter_role: int = -1                 # -1 = 전체

## 확정 직전 화면인가. true 면 픽창이 빠지고 선택 5인이 가운데로 내려온다.
var _confirm_mode: bool = false
## 모드 전환 연출 / 게임 시작 전환이 도는 중 — 그 사이의 입력은 무시한다.
var _busy: bool = false
var _mode_tween: Tween

var _slot_row: Control
var _slot_art: Array = []                  # 5 × TextureRect
var _slot_frame: Array = []                # 5 × Button (누르면 상세 팝업)
## 픽창 — 필터 줄 + 격자 뒤판 + 스크롤. 한 Control 에 모여 있어야 CONFIRM 으로
## 넘어갈 때 덩어리째 아래로 빠진다.
var _pick_root: Control
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
	_apply_mode(false)


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

		# **일러스트 자체가 상세 팝업 버튼이다.** 슬롯을 비우는 조작은 격자에서
		# 같은 썸네일을 다시 누르는 것 하나뿐이라 이 칸에는 경쟁하는 탭이 없다 —
		# 인게임에서 파일럿 얼굴을 눌러 상세를 여는 것과 같은 몸짓이다.
		# **`flat` 로 두면 안 된다** — flat 버튼은 스타일박스를 통째로 무시해서
		# 빈 칸의 테두리와 바탕이 사라지고 "선택 없음" 글자만 허공에 뜬다.
		var frame := Button.new()
		frame.text = ""
		frame.focus_mode = Control.FOCUS_NONE
		frame.position = Vector2(_slot_x(i), 0.0)
		frame.size = Vector2(SLOT_W, SLOT_ART_H)
		frame.disabled = true
		frame.pressed.connect(_on_slot_pressed.bind(i))
		_slot_row.add_child(frame)
		_slot_frame.append(frame)

		# 그림은 테두리 두께만큼 안으로 물리고 **같은 곡선으로 깎는다** — 격자
		# 썸네일과 같은 마스크(`PilotThumb.add_rounded_art`).
		var art: TextureRect = PilotThumb.add_rounded_art(frame, Vector2(b, b),
				Vector2(SLOT_W - b * 2.0, SLOT_ART_H - b * 2.0),
				SLOT_RADIUS - SLOT_BORDER)
		_slot_art.append(art)

		var empty := UiHelpers.mk_label(frame, "선택 없음", 26,
				OutgameTheme.TEXT_FAINT, Vector2(0, SLOT_ART_H * 0.5 - 20.0),
				Vector2(SLOT_W, 40), HORIZONTAL_ALIGNMENT_CENTER)
		empty.name = "EmptyMark"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# 역할군 배지 — **빈 칸에도 선다.** 위에 있던 포지션 글자가 사라졌으므로
		# 빈 칸이 어느 역할의 자리인지는 이 배지가 말한다.
		PilotThumb.add_role_badge(frame, role, Vector2(b + 8.0, b + 8.0))


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
		# i == 0 이 "전체"(-1), 그 뒤는 `SLOT_ROLES` 와 같은 순서다 — 필터 버튼과
		# 위쪽 다섯 칸이 같은 표를 읽으므로 순서가 갈릴 수 없다.
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		btn.pressed.connect(_on_filter_pressed.bind(role))
		_pick_root.add_child(btn)
		_filter_btns.append(btn)
	_apply_filter_styles()


func _build_grid() -> void:
	# 격자 뒤판 — 필터를 좁히면 칸이 다섯 개만 남아 아래가 통째로 비는데,
	# 받침이 없으면 그 여백이 "화면이 끝났다"로 읽힌다. 스크롤 영역의 경계를
	# 색으로 못 박아 두면 빈 목록도 빈 목록으로 보인다.
	_grid_back = Panel.new()
	_grid_back.position = Vector2(GRID_X0 - 8.0, grid_y() - 8.0)
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
	_pick_root.add_child(_grid_back)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.position = Vector2(GRID_X0, grid_y())
	_grid_scroll.size = Vector2(GRID_W, grid_h())
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pick_root.add_child(_grid_scroll)
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`). 썸네일을 누른 채 끌기
	# 시작하면 그 눌림은 취소되므로 스크롤하려던 손이 파일럿을 고르지 않는다.
	DragScroll.attach(_grid_scroll)

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
## "다음"과 "게임 시작"은 서로 배타라 언제나 하나만 서고, 보이는 칸만
## 무게대로 폭을 나눠 가지므로 PICK 에서는 "다음"이 화면 폭을 통째로 쓴다.
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
	_back_btn.visible = false
	_confirm_btn.visible = false
	_next_btn.disabled = true
	_back_btn.pressed.connect(_on_back_pressed)
	_next_btn.pressed.connect(_on_next_pressed)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	OutgameTheme.layout_bottom_bar(_bar_btns, _bar_specs)


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

	_refresh_slots()
	_refresh_next_btn()


func _on_slot_pressed(slot: int) -> void:
	if _busy:
		return
	var p: PlayerData = _pilot_in_slot(slot)
	if p == null:
		return
	_detail.open(p)


func _on_next_pressed() -> void:
	if _busy or not _all_filled():
		return
	_confirm_mode = true
	_apply_mode(true)


func _on_back_pressed() -> void:
	if _busy:
		return
	_confirm_mode = false
	_apply_mode(true)


## PICK ↔ CONFIRM. 바꾸는 것은 셋뿐이다 — 픽창(필터 + 격자)의 자리,
## 선택 5인 블록의 y, 그리고 하단 버튼 셋 중 무엇이 서는가.
##
## `animate` 면 **픽창이 화면 아래로 빠지고 5인이 가운데로 내려오는** 두
## 움직임이 한 박자로 돈다(되돌아갈 때는 그 반대). 버튼은 연출 전에 곧장
## 바뀐다 — 하단 바가 픽창보다 위에 그려지므로 빠져나가는 격자가 바 뒤로 숨는다.
func _apply_mode(animate: bool) -> void:
	var picking: bool = not _confirm_mode
	_next_btn.visible = picking
	_confirm_btn.visible = not picking
	_back_btn.visible = not picking
	# 보이는 칸이 바뀌었으니 하단 구간을 다시 나눠 준다 — 안 하면 PICK 의
	# "다음"이 CONFIRM 에서 쓰던 3분의 2 폭을 그대로 들고 서 있는다.
	OutgameTheme.layout_bottom_bar(_bar_btns, _bar_specs)
	_refresh_next_btn()

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
		sty.corner_radius_top_left     = SLOT_RADIUS
		sty.corner_radius_top_right    = SLOT_RADIUS
		sty.corner_radius_bottom_left  = SLOT_RADIUS
		sty.corner_radius_bottom_right = SLOT_RADIUS
		sty.border_width_left   = SLOT_BORDER
		sty.border_width_right  = SLOT_BORDER
		sty.border_width_top    = SLOT_BORDER
		sty.border_width_bottom = SLOT_BORDER

		if p == null:
			art.texture = null
			empty_mark.visible = true
			sty.bg_color = SLOT_FRAME_BG_EMPTY
			sty.border_color = SLOT_FRAME_BORDER_EMPTY
			frame.disabled = true
		else:
			art.texture = PilotImages.bust_for(p.id)
			empty_mark.visible = false
			sty.bg_color = SLOT_FRAME_BG
			sty.border_color = ROLE_COLORS[role]
			frame.disabled = false
		# 채워진 칸은 눌러서 상세를 여는 버튼이므로 다섯 상태 전부 같은 스타일을
		# 준다 — 안 그러면 hover / pressed 는 기본 테마가 덧칠한다.
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


## **"게임 시작"** — 팀을 확정하고 시즌(인게임)으로 넘어간다. 팀 결성은 아웃게임의
## 마지막 화면이고 그 다음부터가 캠페인이라, 화면을 그냥 갈아 끼우지 않고
## **암전 → 가짜 로딩 → 밝아짐**으로 넘긴다(`_play_launch_transition`).
func _on_confirm_pressed() -> void:
	if _busy or not _all_filled():
		return
	# 확정은 **역할 순서(GameEnums.Role)** 로 넘긴다 — `validate_draft` 는 순서를
	# 보지 않지만, 화면의 슬롯 순서(탑 · 정글 · 미드 · 원딜 · 서폿)를 그대로
	# 흘려보내면 이 목록이 무엇의 순서인지가 호출부마다 달라진다.
	var ids: Array = []
	for role in 5:
		var slot: int = TeamDraft.slot_of_role(role)
		ids.append(int(_picks[slot]))
	# 규칙 검사는 **암전 전에** — 거절될 확정이면 화면을 가리지 않는다.
	var err: String = _draft.validate_draft(ids)
	if err != "":
		push_error("TeamDraftView: confirm failed — " + err)
		return
	_busy = true
	_play_launch_transition(ids)


## 암전 → 가짜 로딩(`LAUNCH_LOAD_SEC`) → 밝아짐.
##
## 덮개는 **허브에 붙인 `CanvasLayer`** 라 이 화면이 숨겨진 뒤에도 남는다
## (CanvasLayer 는 부모 Control 의 `visible` 을 따르지 않는다). 팀 확정과 허브
## 전환(= 드래프트 직후 자동 저장)은 **화면이 다 가려진 뒤에** 한다 — 바뀌는
## 순간이 보이지 않아야 한 장면이 넘어간 것으로 읽힌다. 로딩 막대는 실제
## 작업과 무관한 연출이다(전환 자체는 한 프레임이다).
func _play_launch_transition(ids: Array) -> void:
	var hub: SeasonHub = _draft.get_parent() as SeasonHub
	var layer := CanvasLayer.new()
	layer.layer = 100
	(hub as Node if hub != null else self as Node).add_child(layer)

	var vp: Vector2 = ScreenMetrics.viewport_size()
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 1)
	cover.position = Vector2.ZERO
	cover.size = vp
	cover.mouse_filter = Control.MOUSE_FILTER_STOP   # 전환 중의 탭을 삼킨다
	cover.modulate.a = 0.0
	layer.add_child(cover)

	var load_lbl := UiHelpers.mk_label(cover, "LOADING", 28,
			Color(1, 1, 1, 0.80), Vector2(0, vp.y * 0.5 - 56.0),
			Vector2(vp.x, 36), HORIZONTAL_ALIGNMENT_CENTER)
	load_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.18)
	track.position = Vector2((vp.x - LAUNCH_BAR_W) * 0.5, vp.y * 0.5)
	track.size = Vector2(LAUNCH_BAR_W, 6)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(track)
	var fill := ColorRect.new()
	fill.color = OutgameTheme.ACCENT
	fill.size = Vector2(0, 6)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	var tw := layer.create_tween()
	tw.tween_property(cover, "modulate:a", 1.0, LAUNCH_FADE_OUT_SEC)
	tw.tween_callback(_commit_draft.bind(ids, hub))
	tw.tween_property(fill, "size:x", LAUNCH_BAR_W, LAUNCH_LOAD_SEC) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cover, "modulate:a", 0.0, LAUNCH_FADE_IN_SEC)
	tw.tween_callback(layer.queue_free)


## 화면이 다 가려진 순간에 도는 확정 — 팀 재배치 + 허브 전환.
func _commit_draft(ids: Array, hub: SeasonHub) -> void:
	var err: String = _draft.apply_draft(ids)
	if err != "":
		push_error("TeamDraftView: confirm failed — " + err)
	# 팝업은 CanvasLayer 라 부모 Control 의 `visible` 을 따르지 않는다 — 열어 둔
	# 채 허브로 넘어가면 딤이 화면에 그대로 남는다.
	_detail.close()
	_busy = false
	if hub != null:
		hub.goto(SeasonHub.Screen.HUB)
