class_name TrainingView
extends Control

# 주간 훈련 편성 화면. 위에서 아래로 네 덩이고, **가로 기준선은 하나뿐이다** —
# `_grid_x()` 가 판을 화면 한가운데에 놓고 썸네일 · 요일 글자 · 드롭 미리보기가
# 전부 그 한 값에서 나온다. 예전에는 판 왼쪽 끝이 상수(`GRID_X` 80)였고 요일
# 칸이 그 안쪽에 있어 판 오른쪽 끝이 화면 밖(1102 > 1080)으로 나가 있었다 —
# 화면에서는 초상화와 타일이 통째로 오른쪽으로 쏠린 것으로 보였다.
#
#   1. **파일럿 초상화 다섯** — 가로로 한 줄. 자리 순서는 전장 스트립과 같은
#      `GameEnums.ROLE_DISPLAY_ORDER`(탑 · 정글 · 미드 · 원딜 · 서폿)이고,
#      **그 자리가 곧 판의 열 번호**다. 인게임 스트립과 **같은 가로 초상화**
#      (`PilotImages.eye_for`, 480×200 밴드)를 쓰고 이름 · 역할 글자는 없다 —
#      이 줄이 답하는 질문은 "이 열이 누구의 한 주인가" 하나뿐이라 얼굴이
#      그 답이고 테두리 색이 역할이다. **누를 수 없다**(순수한 열 머리글).
#   2. **5×5 훈련판** — 열이 선수, 행이 월~금. 칸은 **정사각형**이다.
#   3. **타일 인벤토리** — 가로 4칸의 세로 스크롤. 카드에는 등급 · 놓임/상한 ·
#      모양 미니어처 · 이름만 있고 **설명문은 없다** — 카드를 누르면 그 옆에
#      정보 팝오버가 뜬다(`_select_card`). 타일은 몇 번이든 다시 쓸 수 있고
#      (보유 수량 없음) **등급별 배치 개수 상한**이 대신 판을 조인다.
#   4. **훈련 확정** — 화면 최하단 가운데.
#
# 예전에는 썸네일 아래에 **예상 변화 한 줄**(썸네일을 눌러 선수를 갈아타며
# 여섯 스탯 before→after 를 보던 줄)이 있었다. 썸네일이 순수한 머리글이 되며
# 고를 주체가 사라졌고, 그 정보는 "훈련 확정" 뒤의 **시간 경과 화면**
# (`features/season/week/WeekProgressView.gd`)이 요일마다 다섯 명 × 여섯 스탯으로
# 보여 준다. 예전에 그 자리를 맡았던 주간 결산 한 장(`TrainingResultView`)은
# 정산이 요일 단위로 쪼개지면서 삭제됐다.
#
# ── 드래그 앤 드롭 ────────────────────────────────────────────────────────────
# Godot 내장 드래그(`_get_drag_data` / `_can_drop_data` / `_drop_data`)를 쓴다.
# 두 출발점이 있다 — 인벤토리 카드에서 끌면 **새로 놓는 것**이고, 판 위의
# 타일에서 끌면 **옮기는 것**이다. 후자는 드래그가 시작되는 순간 판에서
# 걷어 내고(그래야 자기 자리와 겹친다고 거절당하지 않는다) 드롭이 실패하면
# `NOTIFICATION_DRAG_END` 에서 원래 자리에 되돌린다.
#
# **끌고 있는 타일은 커서를 한가운데에 두고 따라온다** — 그 중심이 어느 칸에
# 가장 가까운지가 곧 놓일 자리다(`_origin_for`). 손가락이 모양의 한복판에
# 있으므로 여러 칸 타일도 커서 주위로 통째로 보이고, 판 밖으로 삐져나가는
# 자리는 판 안으로 물려 잡힌다.
#
# 판 위의 타일은 **탭하면 걷힌다**. 내장 드래그는 커서가 움직여야 시작되므로
# 그냥 누르고 떼는 것은 `_gui_input` 이 따로 받는다. 인벤토리 카드의 탭이
# **고르기**인 것도 같은 이치다.

const COLS: int = TrainingBoard.COLS
const ROWS: int = TrainingBoard.ROWS

## 역할 색은 팔레트가 소유한다 — 화면마다 자기 배열을 들면 같은 역할이
## 화면마다 다른 색으로 그려진다.
const ROLE_COLORS: Array = OutgameTheme.ROLE_COLORS

# ── 레이아웃 (1080 폭 디자인 기준) ───────────────────────────────────────────
const MARGIN: float      = 40.0
## 판의 칸은 **정사각형**이다. 색 면이 곧 "한 선수의 하루"라 가로로 납작하면
## 여러 칸 타일의 모양(2×2 · 1×3 · 5×1)이 판 위에서 왜곡돼 읽힌다.
const CELL: float        = 176.0
const GRID_W: float      = CELL * float(COLS)   # 880
const GRID_H: float      = CELL * float(ROWS)   # 880
const DAY_GUTTER: float  = 56.0                 # 판 왼쪽 요일 글자 칸
## 칸 사이 여백. 타일 몸통은 **자기 타일과 맞닿은 변에서만** 이 여백을 버려
## 이어 붙는다(`_draw_tile_body`).
const CELL_PAD: float    = 2.0
const TILE_EDGE: float   = 3.0

## 끌고 있는 타일의 **영향 범위** 표시(`_draw_grid`). 칸을 채우는 것이 아니라
## 테두리로 가리키는 것이라 그 칸에 이미 놓인 타일의 색이 그대로 읽힌다 —
## 면을 진하게 깔면 증폭 타일이 무엇 위에 걸리는지가 그 표시에 지워진다.
## 노란색은 드롭 미리보기의 초록 / 빨강과도, 판의 여섯 스탯 색과도 겹치지
## 않는 자리다(노랑 `H` 는 칸 **면** 색이라 테두리와 다투지 않는다).
const AFFECT_FILL: Color = Color(1.00, 0.86, 0.25, 0.16)
const AFFECT_LINE: Color = Color(1.00, 0.86, 0.25, 0.92)

const TITLE_Y: float     = 8.0
const THUMB_Y: float     = 58.0
const THUMB_W: float     = CELL - 6.0
## 인게임 스트립과 같은 eye 밴드(480×200)라 높이는 그 비율에서 나온다 —
## 임의 높이로 늘리면 얼굴이 찌그러진다.
const THUMB_H: float     = THUMB_W / 2.4
const GRID_Y: float      = 146.0
const INV_TOP_PAD: float = 58.0                 # 판 ↔ 인벤토리 사이

const INV_COLS: int        = 4
const INV_GAP: float       = 12.0
## 카드에 남은 것은 등급 줄 · 모양 미니어처 · 이름 셋뿐이다. 설명문이 빠지며
## 244 → 146 으로 줄었고, 그 덕에 15장이 두 화면이 아니라 한 화면 남짓에 든다.
const INV_CARD_H: float    = 146.0
## 마지막 줄 뒤에 두는 여백. 스크롤 끝이 카드 밑단에 딱 맞아떨어지면 "여기가
## 끝"과 "더 있는데 안 보인다"가 같은 그림이 된다 — 반 칸을 비워 두면 아래로
## 더 있다는 것이 잘린 카드로 보인다.
const INV_TAIL_PAD: float = INV_CARD_H * 0.5

## 카드 안 모양 미니어처의 자리 · 크기(`_mini_geom` / `_add_shape_mini`).
const MINI_PAD: float = 10.0
const MINI_Y: float   = 34.0
const MINI_H: float   = 74.0
const MINI_MAX: float = 18.0

## 정보 팝오버. 고른 카드 **옆**에 뜨고 자리가 없으면 반대쪽으로 넘어간다.
const POP_W: float   = 380.0
const POP_PAD: float = 16.0
const POP_GAP: float = 10.0
## `Label` 이 줄 사이에 넣는 간격(기본 테마의 `line_spacing`). `_text_height`
## 가 이것을 되돌려 주지 않으면 여러 줄 글이 팝오버 아래로 넘친다.
const POP_LINE_SPACING: float = 3.0

const BTN_H: float       = 104.0
const BTN_W: float       = 460.0
const BTN_BOTTOM_PAD: float = 72.0

@onready var _hub: SeasonHub = get_parent() as SeasonHub

var _board: TrainingBoard = null

var _grid: Control = null                # 판 — 그리기 · 드롭 · 히트를 다 한다
var _inv_scroll: ScrollContainer = null
var _inv_rows: VBoxContainer = null

var _thumb_faces: Array = []             # 5 TextureRect

# 인벤토리에서 고른 코스와 그 정보 팝오버.
var _sel_tile: TrainingTile = null
var _sel_card: Control = null
var _popover: Control = null

# 드래그 상태. `_drag_tile` 이 null 이 아니면 지금 무언가를 끌고 있다.
var _drag_tile: TrainingTile = null
var _drag_from_board: Dictionary = {}        # 판에서 걷어 온 배치(되돌리기용)
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _hover_ok: bool = false

var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	ensure_view()


# Idempotent — SeasonHub calls this each time it routes to TRAINING.
func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	_resolve_board()
	refresh()


func _resolve_board() -> void:
	if _board != null:
		return
	if _hub == null:
		return
	_board = _hub.get_node_or_null("TrainingBoard") as TrainingBoard


## **판이 화면 한가운데에 온다.** 썸네일도 요일 글자도 이 한 값에서 나오므로
## 셋이 어긋날 수 없다. 가운데를 잡는 것은 요일 칸까지 합친 덩어리가 아니라
## **판 자체**다 — 요일 글자는 판 옆에 붙은 이름표이지 내용이 아니라서,
## 덩어리째 가운데에 두면 정작 눈이 따라가는 다섯 열이 요일 칸 폭의 절반만큼
## 오른쪽으로 밀린다.
static func _grid_x() -> float:
	return (1080.0 - GRID_W) * 0.5


## 요일 글자 칸의 왼쪽 끝. 판 바로 왼쪽에 붙는다.
static func _day_x() -> float:
	return _grid_x() - DAY_GUTTER


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)

	UiHelpers.mk_label(self, "주간 훈련 편성", 34, OutgameTheme.TEXT,
			Vector2(0, TITLE_Y), Vector2(ScreenMetrics.vp_w(), 44), HORIZONTAL_ALIGNMENT_CENTER)

	_build_thumbs()
	_build_grid()
	_build_inventory()
	_build_confirm_button()


## 열 머리글 다섯. **누를 수 없고 글자도 없다** — 얼굴이 누구인지를, 테두리
## 색이 역할을 말한다. 인게임 파일럿 스트립과 같은 가로 초상화라 전장에서
## 보던 얼굴과 여기 얼굴이 같은 컷이다.
func _build_thumbs() -> void:
	for seat in COLS:
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var role_col: Color = ROLE_COLORS[r]
		var panel := Panel.new()
		panel.position = Vector2(_grid_x() + float(seat) * CELL + 3.0, THUMB_Y)
		panel.size     = Vector2(THUMB_W, THUMB_H)
		panel.add_theme_stylebox_override("panel", _thumb_style(role_col))
		panel.clip_contents = true
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)

		var face := TextureRect.new()
		face.position     = Vector2(2, 2)
		face.size         = Vector2(THUMB_W - 4.0, THUMB_H - 4.0)
		face.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(face)
		_thumb_faces.append(face)


static func _thumb_style(role_col: Color) -> StyleBoxFlat:
	var sty := StyleBoxFlat.new()
	sty.bg_color = OutgameTheme.SURFACE
	sty.border_color = Color(role_col.r, role_col.g, role_col.b, 0.85)
	sty.border_width_left = 2; sty.border_width_right = 2
	sty.border_width_top  = 2; sty.border_width_bottom = 2
	sty.corner_radius_top_left = 8;    sty.corner_radius_top_right = 8
	sty.corner_radius_bottom_left = 8; sty.corner_radius_bottom_right = 8
	return sty


func _build_grid() -> void:
	for day in ROWS:
		UiHelpers.mk_label(self, String(TrainingBoard.DAY_NAMES[day]), 24,
				OutgameTheme.TEXT_SUB,
				Vector2(_day_x(), GRID_Y + float(day) * CELL + (CELL - 30.0) * 0.5),
				Vector2(DAY_GUTTER, 30), HORIZONTAL_ALIGNMENT_CENTER)

	_grid = Control.new()
	_grid.position = Vector2(_grid_x(), GRID_Y)
	_grid.size     = Vector2(GRID_W, GRID_H)
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_on_grid_input)
	# 판 자신이 드롭 대상이자 드래그 출발점이다. `set_drag_forwarding` 을 쓰면
	# 세 콜백을 한 노드에 몰아넣을 수 있어 `_grid` 를 서브클래스로 만들 필요가
	# 없다 — 이 화면에서 판은 그리기 한 장이지 노드 스물다섯 개가 아니다.
	_grid.set_drag_forwarding(_grid_get_drag_data, _grid_can_drop, _grid_drop)
	add_child(_grid)


func _build_inventory() -> void:
	var top: float = GRID_Y + GRID_H + INV_TOP_PAD
	var btn_y: float = _confirm_button_y()
	var h: float = maxf(180.0, btn_y - 20.0 - top)

	UiHelpers.mk_label(self, "훈련 코스", 22, OutgameTheme.TEXT_SUB,
			Vector2(MARGIN, top - 32.0), Vector2(400, 28))

	_inv_scroll = ScrollContainer.new()
	_inv_scroll.position = Vector2(MARGIN, top)
	_inv_scroll.size     = Vector2(1080.0 - MARGIN * 2.0, h)
	_inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inv_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_inv_scroll)

	_inv_rows = VBoxContainer.new()
	_inv_rows.add_theme_constant_override("separation", int(INV_GAP))
	_inv_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_scroll.add_child(_inv_rows)

	# 팝오버는 스크롤 **밖**에 사는 별개의 판이라(안에 두면 스크롤 폭에 잘린다)
	# 스크롤이 움직이면 따라가야 한다.
	_inv_scroll.get_v_scroll_bar().value_changed.connect(_on_inv_scrolled)


## 확정 버튼의 y. 인벤토리 높이가 여기서 역산되므로 상수가 아니라 함수다 —
## 하단 안전선은 기기마다 다르고, 인벤토리가 버튼을 덮으면 훈련을 확정할 수 없다.
func _confirm_button_y() -> float:
	return ScreenMetrics.safe_h() - BTN_BOTTOM_PAD - BTN_H


func _build_confirm_button() -> void:
	var btn := Button.new()
	btn.text = "훈련 확정"
	btn.position = Vector2((1080.0 - BTN_W) * 0.5, _confirm_button_y())
	btn.size     = Vector2(BTN_W, BTN_H)
	OutgameTheme.style_primary_button(btn, 32)
	btn.pressed.connect(_on_confirm_pressed)
	add_child(btn)

	var clear := Button.new()
	clear.text = "판 비우기"
	clear.position = Vector2((1080.0 - BTN_W) * 0.5 - 210.0, _confirm_button_y() + 16.0)
	clear.size     = Vector2(190, BTN_H - 32.0)
	OutgameTheme.style_ghost_button(clear, 24)
	clear.pressed.connect(_on_clear_pressed)
	add_child(clear)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_rebuild_inventory()
	_refresh_thumbs()
	if _grid != null:
		_grid.queue_redraw()


func _refresh_thumbs() -> void:
	var pilots: Array = _pilots()
	for seat in COLS:
		var p: PlayerData = pilots[seat]
		(_thumb_faces[seat] as TextureRect).texture = \
				null if p == null else PilotImages.eye_for(p.id)


func _pilots() -> Array:
	if _board != null:
		return _board.player_pilots_by_seat()
	return [null, null, null, null, null]


# ── 판 그리기 ────────────────────────────────────────────────────────────────
func _draw_grid() -> void:
	if _grid == null:
		return
	# 빈 칸
	for x in COLS:
		for y in ROWS:
			var r := Rect2(float(x) * CELL + CELL_PAD, float(y) * CELL + CELL_PAD,
					CELL - CELL_PAD * 2.0, CELL - CELL_PAD * 2.0)
			_grid.draw_rect(r, OutgameTheme.SURFACE_SUNK, true)
			_grid.draw_rect(r, OutgameTheme.BORDER, false, 2.0)

	if _board == null:
		return

	# 놓인 타일 — 칸 색을 칠하고 **바깥 윤곽만** 두른다.
	var b: Array = _board.board()
	for e_raw in b:
		var e: Dictionary = e_raw
		var t: TrainingTile = _board.tile(String(e.get("tile", "")))
		if t == null:
			continue
		var ox: int = int(e.get("x", 0))
		var oy: int = int(e.get("y", 0))
		_draw_tile_body(t, ox, oy)
		_draw_tile_caption(t, ox, oy)

	if _drag_tile == null or _hover_cell.x < 0:
		return

	# 영향 범위 — **끌고 있는 타일이 남의 칸에 무슨 일을 하는가.** 절을 가진
	# 타일만 그리고, 드롭 미리보기(초록 / 빨강)보다 **먼저** 깔아 자기 칸에서는
	# 미리보기가 위를 덮는다. 놓을 수 없는 자리에서도 그린다 — 못 놓는 것과
	# 무엇에 닿는지 안 보이는 것은 다른 일이고, 이 표시를 보고 자리를 옮기는
	# 것이 이 화면에서 증폭 타일의 자리를 고르는 방식이다. 드롭하는 순간
	# `_drag_tile` 이 비므로 표시도 그 자리에서 사라진다.
	var own: Dictionary = {}
	for c_own in _drag_tile.cells:
		own[Vector2i(_hover_cell.x + (c_own as Vector2i).x,
				_hover_cell.y + (c_own as Vector2i).y)] = true
	for c_aff in _board.affected_cells(_drag_tile, _hover_cell):
		var a: Vector2i = c_aff
		if own.has(a):
			continue
		var r_aff := Rect2(float(a.x) * CELL + CELL_PAD, float(a.y) * CELL + CELL_PAD,
				CELL - CELL_PAD * 2.0, CELL - CELL_PAD * 2.0)
		_grid.draw_rect(r_aff, AFFECT_FILL, true)
		_grid.draw_rect(r_aff, AFFECT_LINE, false, TILE_EDGE)

	# 드롭 미리보기 — 놓을 수 있으면 초록, 없으면 빨강.
	var tint: Color = Color(OutgameTheme.POSITIVE, 0.45) if _hover_ok \
			else Color(OutgameTheme.NEGATIVE, 0.38)
	for c2 in _drag_tile.cells:
		var at := Vector2i(_hover_cell.x + (c2 as Vector2i).x,
				_hover_cell.y + (c2 as Vector2i).y)
		if at.x < 0 or at.x >= COLS or at.y < 0 or at.y >= ROWS:
			continue
		var pad: float = CELL_PAD + 1.0
		var r3 := Rect2(float(at.x) * CELL + pad, float(at.y) * CELL + pad,
				CELL - pad * 2.0, CELL - pad * 2.0)
		_grid.draw_rect(r3, tint, true)


## 타일 하나의 몸통. **같은 타일의 이웃 칸과 맞닿은 변에서는 여백도 테두리도
## 버린다** — 그래서 여러 칸 타일은 칸 사이에 구분선 없이 한 덩어리로 이어져
## 보이고 바깥 윤곽만 남는다(전장의 캠프 아웃라인이 쓰는 규칙과 같다: 그 변
## 너머의 이웃이 같은 타일이 아닐 때만 그린다). 색은 **그 변이 속한 칸의 색**
## 이라, 위가 빨강 아래가 보라인 [합숙 스크림]은 윤곽만 봐도 위아래가 다른 것이
## 읽힌다. 안쪽 이음매에 어두운 선을 넣던 예전 방식은 삭제했다 — 그 선이 곧
## "여기서 타일이 끊긴다"로 읽혔다.
func _draw_tile_body(t: TrainingTile, ox: int, oy: int) -> void:
	var own: Dictionary = {}
	for c in t.cells:
		own[c] = true
	for i in t.cells.size():
		var c2: Vector2i = t.cells[i]
		var col: Color = TrainingTile.color_of(String(t.cell_colors[i]))
		var up: bool = own.has(c2 + Vector2i(0, -1))
		var dn: bool = own.has(c2 + Vector2i(0, 1))
		var lf: bool = own.has(c2 + Vector2i(-1, 0))
		var rt: bool = own.has(c2 + Vector2i(1, 0))
		var x0: float = float(ox + c2.x) * CELL + (0.0 if lf else CELL_PAD)
		var x1: float = float(ox + c2.x + 1) * CELL - (0.0 if rt else CELL_PAD)
		var y0: float = float(oy + c2.y) * CELL + (0.0 if up else CELL_PAD)
		var y1: float = float(oy + c2.y + 1) * CELL - (0.0 if dn else CELL_PAD)
		var w: float = x1 - x0
		var h: float = y1 - y0
		_grid.draw_rect(Rect2(x0, y0, w, h),
				col.darkened(0.42), true)
		if not up:
			_grid.draw_rect(Rect2(x0, y0, w, TILE_EDGE), col, true)
		if not dn:
			_grid.draw_rect(Rect2(x0, y1 - TILE_EDGE, w, TILE_EDGE), col, true)
		if not lf:
			_grid.draw_rect(Rect2(x0, y0, TILE_EDGE, h), col, true)
		if not rt:
			_grid.draw_rect(Rect2(x1 - TILE_EDGE, y0, TILE_EDGE, h), col, true)


## 타일 위에 남는 글씨는 **이름 하나뿐**이고, 타일이 덮은 범위 한가운데에
## 앉는다. EXP 요약은 여기서 빠졌다 — 판이 답해야 하는 질문은 "무엇이 어디에
## 놓였나"이고 숫자는 인벤토리의 정보 팝오버가 들고 있다.
func _draw_tile_caption(t: TrainingTile, ox: int, oy: int) -> void:
	var font: Font = ThemeDB.fallback_font
	var ext: Vector2i = t.extent()
	var w: float = float(ext.x) * CELL - 16.0
	var at := Vector2(float(ox) * CELL + 8.0,
			(float(oy) + float(ext.y) * 0.5) * CELL + 7.0)
	_grid.draw_string_outline(font, at, t.tile_name, HORIZONTAL_ALIGNMENT_CENTER,
			w, 20, 4, Color(1, 1, 1, 0.85))
	_grid.draw_string(font, at, t.tile_name, HORIZONTAL_ALIGNMENT_CENTER,
			w, 20, OutgameTheme.TEXT)


func _cell_at(local: Vector2) -> Vector2i:
	var x: int = int(floor(local.x / CELL))
	var y: int = int(floor(local.y / CELL))
	if x < 0 or x >= COLS or y < 0 or y >= ROWS:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


## 커서가 `local` 에 있을 때 끌고 있는 타일이 놓일 **원점 칸**. 타일의 한가운데를
## 커서에 맞춘 뒤 가장 가까운 칸으로 반올림한다 — 화면 위를 떠다니는 미리보기가
## 쓰는 것과 **같은 중앙 정렬**이라 손가락 밑의 모양과 판 위의 초록 칸이 갈릴 수
## 없다. 그 다음 판 안으로 **물려 잡는다**(clamp): 5칸짜리 [전지 훈련]은 x 가
## 0 일 수밖에 없고, 2칸짜리를 맨 왼쪽 열 한가운데에서 놓으려 하면 중심이 판
## 밖을 가리키므로 물려 주지 않으면 영영 놓을 수 없는 자리가 생긴다.
func _origin_for(t: TrainingTile, local: Vector2) -> Vector2i:
	var ext: Vector2i = t.extent()
	var top_left: Vector2 = local - Vector2(float(ext.x), float(ext.y)) * CELL * 0.5
	return Vector2i(
			clampi(int(round(top_left.x / CELL)), 0, COLS - ext.x),
			clampi(int(round(top_left.y / CELL)), 0, ROWS - ext.y))


# ── 판 입력 ──────────────────────────────────────────────────────────────────
## 탭(움직이지 않은 누름)은 그 칸의 타일을 걷어 낸다. 내장 드래그는 커서가
## 움직여야 시작되므로 이 경로와 겹치지 않는다.
func _on_grid_input(event: InputEvent) -> void:
	if _board == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _drag_tile != null:
		return
	# 판을 건드리면 정보 팝오버는 닫는다 — 지금 보는 것은 판이다.
	_close_popover()
	var cell: Vector2i = _cell_at(mb.position)
	if cell.x < 0:
		return
	if not _board.remove_at(cell).is_empty():
		refresh()


# ── 드래그 소스 / 드롭 대상 ──────────────────────────────────────────────────
## 판 위의 타일을 집어 든다. **집는 순간 판에서 걷어 낸다** — 그래야 한 칸 옆으로
## 미는 이동이 "자기 자신과 겹친다"로 거절되지 않는다. 드롭이 실패하면
## `NOTIFICATION_DRAG_END` 가 원래 자리에 되돌린다.
func _grid_get_drag_data(at_position: Vector2) -> Variant:
	if _board == null:
		return null
	var cell: Vector2i = _cell_at(at_position)
	if cell.x < 0:
		return null
	var occ: Dictionary = _board.occupancy()
	if not occ.has(cell):
		return null
	var idx: int = int(occ[cell])
	var entry: Dictionary = _board.board()[idx].duplicate()
	var t: TrainingTile = _board.tile(String(entry.get("tile", "")))
	if t == null:
		return null
	_board.remove_entry(idx)
	_begin_drag(t, entry)
	return {"tile": t.id, "from": "board"}


func _grid_can_drop(at_position: Vector2, _data: Variant) -> bool:
	if _board == null or _drag_tile == null:
		return false
	var origin: Vector2i = _origin_for(_drag_tile, at_position)
	var ok: bool = _board.can_place(_drag_tile, origin)
	if origin != _hover_cell or ok != _hover_ok:
		# 미리보기가 **놓을 수 있는 자리로 막 들어선** 순간에만 한 톡 —
		# 손가락 밑에서 타일이 칸에 물린 느낌이 이 화면의 조작 감각이다.
		# 칸이 바뀌었을 뿐인데도 울리면 판 위를 훑는 내내 진동이 된다.
		if ok and not _hover_ok:
			Haptics.play(Haptics.Kind.SELECT)
		_hover_cell = origin
		_hover_ok = ok
		_grid.queue_redraw()
	return ok


func _grid_drop(at_position: Vector2, _data: Variant) -> void:
	if _board == null or _drag_tile == null:
		return
	if _board.place(_drag_tile.id, _origin_for(_drag_tile, at_position)) >= 0:
		Haptics.play(Haptics.Kind.MEDIUM)
		# 놓였으므로 되돌릴 것이 없다 — 여기서 지우지 않으면 DRAG_END 가
		# 판에서 걷어 온 사본을 한 장 더 얹어 타일이 둘로 늘어난다.
		_drag_from_board = {}
	refresh()


func _begin_drag(t: TrainingTile, from_board: Dictionary) -> void:
	_close_popover()
	_drag_tile = t
	_drag_from_board = from_board
	_hover_cell = Vector2i(-1, -1)
	_hover_ok = false
	Haptics.play(Haptics.Kind.SELECT)
	set_drag_preview(_make_drag_preview(t))
	if _grid != null:
		_grid.queue_redraw()


func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	# 판에서 집어 든 타일이 아무 데도 안 놓였으면 원래 자리로 되돌린다.
	if not _drag_from_board.is_empty() and not is_drag_successful():
		_board.board().append(_drag_from_board)
	_drag_tile = null
	_drag_from_board = {}
	_hover_cell = Vector2i(-1, -1)
	_hover_ok = false
	if _built:
		refresh()


## 커서를 따라다니는 미리보기. 판의 칸 크기 그대로 그려야 "이만큼 자리를
## 차지한다"가 손가락 밑에서 읽힌다. 맞닿은 변에서 여백과 테두리를 버리는
## 규칙도 판과 같다 — 미리보기와 놓인 결과가 다른 모양이면 미리보기가 아니다.
##
## **껍데기가 두 겹인 것은 엔진 때문이다.** `set_drag_preview` 로 넘긴 노드는
## 뷰포트가 매 프레임 `set_position(마우스 좌표)` 로 **덮어쓰므로**, 그 노드에
## 오프셋을 적어 두면 조용히 사라지고 왼쪽 위 모서리가 커서에 붙는다. 그래서
## 바깥 `root` 는 엔진에 자리를 내주고, 실제 그림은 그 **자식**(`body`)이
## `-ext × CELL / 2` 만큼 밀린 채 들고 있다 — 그래야 타일 한가운데가 커서에 온다.
func _make_drag_preview(t: TrainingTile) -> Control:
	var ext: Vector2i = t.extent()
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate = Color(1, 1, 1, 0.90)

	var body := Control.new()
	body.size = Vector2(float(ext.x), float(ext.y)) * CELL
	body.position = -body.size * 0.5
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)

	var own: Dictionary = {}
	for c in t.cells:
		own[c] = true
	for i in t.cells.size():
		var c2: Vector2i = t.cells[i]
		var col: Color = TrainingTile.color_of(String(t.cell_colors[i]))
		var lf: bool = own.has(c2 + Vector2i(-1, 0))
		var rt: bool = own.has(c2 + Vector2i(1, 0))
		var up: bool = own.has(c2 + Vector2i(0, -1))
		var dn: bool = own.has(c2 + Vector2i(0, 1))
		var box := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = col.lightened(0.55)
		sty.border_color = col
		sty.border_width_left   = 0 if lf else int(TILE_EDGE)
		sty.border_width_right  = 0 if rt else int(TILE_EDGE)
		sty.border_width_top    = 0 if up else int(TILE_EDGE)
		sty.border_width_bottom = 0 if dn else int(TILE_EDGE)
		box.add_theme_stylebox_override("panel", sty)
		var px0: float = 0.0 if lf else CELL_PAD
		var py0: float = 0.0 if up else CELL_PAD
		box.position = Vector2(float(c2.x) * CELL + px0, float(c2.y) * CELL + py0)
		box.size = Vector2(CELL - px0 - (0.0 if rt else CELL_PAD),
				CELL - py0 - (0.0 if dn else CELL_PAD))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(box)
	var name_lbl := UiHelpers.mk_label(body, t.tile_name, 20, OutgameTheme.TEXT,
			Vector2(8, body.size.y * 0.5 - 14.0),
			Vector2(body.size.x - 16.0, 28), HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return root


# ── 인벤토리 ─────────────────────────────────────────────────────────────────
func _rebuild_inventory() -> void:
	if _inv_rows == null or _board == null:
		return
	# 카드 노드가 통째로 새로 서므로 팝오버가 가리키던 카드도 사라진다.
	_close_popover()
	for child in _inv_rows.get_children():
		child.queue_free()

	var card_w: float = (_inv_scroll.size.x - INV_GAP * float(INV_COLS - 1) - 16.0) \
			/ float(INV_COLS)
	var tiles: Array = _board.all_tiles()
	var row: HBoxContainer = null
	for i in tiles.size():
		if i % INV_COLS == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", int(INV_GAP))
			_inv_rows.add_child(row)
		row.add_child(_make_inventory_card(tiles[i], card_w))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, INV_TAIL_PAD)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_rows.add_child(pad)


## 코스 카드 한 장 — **등급 · 놓임/상한 · 모양 · 이름**이 전부다. 설명문과 EXP
## 요약은 여기서 빠져 정보 팝오버로 갔다: 카드 열다섯 장이 각자 네 줄짜리 설명을
## 들고 있으면 목록이 두 화면이 되고, 정작 훑어 고를 때 견주는 것은 이름과
## 모양이다.
func _make_inventory_card(t: TrainingTile, w: float) -> Control:
	var placed: int = _board.placed_count_of_grade(t.grade)
	var limit: int = t.place_limit()
	var locked: bool = limit >= 0 and placed >= limit

	var card := Panel.new()
	card.custom_minimum_size = Vector2(w, INV_CARD_H)
	card.add_theme_stylebox_override("panel", _card_style(t, locked, false))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.modulate = Color(1, 1, 1, 0.42) if locked else Color(1, 1, 1, 1)
	# 탭 = 고르기(정보 팝오버). **잠긴 카드도 고를 수 있다** — 못 놓는 것과
	# 무엇인지 못 보는 것은 다른 일이다.
	card.gui_input.connect(_on_card_input.bind(t, card))
	if not locked:
		card.set_drag_forwarding(
				func(_at: Vector2) -> Variant: return _inv_get_drag_data(t),
				func(_at: Vector2, _d: Variant) -> bool: return false,
				func(_at: Vector2, _d: Variant) -> void: pass)

	# 등급 배지 + 배치 수
	UiHelpers.mk_label(card, t.grade_name(), 18, t.grade_color(),
			Vector2(MINI_PAD, 6), Vector2(40, 22)).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap: String = "∞" if limit < 0 else "%d/%d" % [placed, limit]
	UiHelpers.mk_label(card, cap, 16, OutgameTheme.TEXT_SUB,
			Vector2(w - 74.0, 8), Vector2(64, 20),
			HORIZONTAL_ALIGNMENT_RIGHT).mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 모양 미니어처 — 판에서 몇 칸을 먹는지가 카드에서 먼저 읽혀야 한다.
	_add_shape_mini(card, t, w)

	var name_lbl := UiHelpers.mk_label(card, t.tile_name, 20, OutgameTheme.TEXT,
			Vector2(MINI_PAD, MINI_Y + MINI_H + 6.0),
			Vector2(w - MINI_PAD * 2.0, 26), HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return card


static func _card_style(t: TrainingTile, locked: bool, selected: bool) -> StyleBoxFlat:
	var g: Color = t.grade_color()
	var sty := StyleBoxFlat.new()
	sty.bg_color = OutgameTheme.ACCENT_DIM if selected else OutgameTheme.SURFACE
	sty.border_color = Color(g.r, g.g, g.b, 0.35 if locked else 1.0)
	var bw: int = 4 if selected else 2
	sty.border_width_left = bw; sty.border_width_right = bw
	sty.border_width_top  = bw; sty.border_width_bottom = bw
	sty.corner_radius_top_left = 8;    sty.corner_radius_top_right = 8
	sty.corner_radius_bottom_left = 8; sty.corner_radius_bottom_right = 8
	return sty


## 카드 안 모양 미니어처의 기하 — 칸 크기와 그 상자 안에서의 원점.
static func _mini_geom(t: TrainingTile, card_w: float) -> Dictionary:
	var ext: Vector2i = t.extent()
	var box_w: float = card_w - MINI_PAD * 2.0
	var s: float = minf(MINI_MAX, minf(box_w / float(ext.x), MINI_H / float(ext.y)))
	return {
		"s": s,
		"ox": MINI_PAD + (box_w - s * float(ext.x)) * 0.5,
		"oy": MINI_Y + (MINI_H - s * float(ext.y)) * 0.5,
	}


## 칸 하나를 최대 18px 로 잡되 모양이 커지면 줄여 언제나 같은 상자 안에 들어오게
## 한다 — 6칸 타일과 1칸 타일이 같은 크기로 그려지면 "몇 칸짜리인가"가 카드에서
## 안 읽힌다.
func _add_shape_mini(card: Control, t: TrainingTile, card_w: float) -> void:
	var g: Dictionary = _mini_geom(t, card_w)
	var s: float = float(g["s"])
	for i in t.cells.size():
		var c: Vector2i = t.cells[i]
		var box := ColorRect.new()
		box.color = TrainingTile.color_of(String(t.cell_colors[i]))
		box.position = Vector2(float(g["ox"]) + float(c.x) * s + 1.0,
				float(g["oy"]) + float(c.y) * s + 1.0)
		box.size     = Vector2(s - 2.0, s - 2.0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(box)


## 인벤토리 카드에서 끌어내기. 카드 어디를 잡았는지는 보지 않는다 — 끌려 나온
## 타일은 언제나 커서를 한가운데에 두므로 카드 안의 잡은 지점이 놓일 자리를
## 바꾸지 않는다(예전에는 미니어처의 잡은 칸을 판 좌표로 역산했다).
func _inv_get_drag_data(t: TrainingTile) -> Variant:
	_begin_drag(t, {})
	return {"tile": t.id, "from": "inventory"}


# ── 정보 팝오버 ──────────────────────────────────────────────────────────────
## 카드 탭. 같은 카드를 다시 누르면 닫히고, 다른 카드를 누르면 그쪽으로 갈아탄다.
func _on_card_input(event: InputEvent, t: TrainingTile, card: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _drag_tile != null:
		return
	if _sel_tile != null and _sel_tile.id == t.id:
		_close_popover()
		return
	_select_card(t, card)


func _select_card(t: TrainingTile, card: Control) -> void:
	_close_popover()
	_sel_tile = t
	_sel_card = card
	var placed: int = _board.placed_count_of_grade(t.grade)
	var limit: int = t.place_limit()
	card.add_theme_stylebox_override("panel",
			_card_style(t, limit >= 0 and placed >= limit, true))
	_popover = _build_popover(t, placed, limit)
	add_child(_popover)
	_place_popover()


func _close_popover() -> void:
	if _sel_tile != null and _sel_card != null and is_instance_valid(_sel_card):
		var placed: int = 0 if _board == null else _board.placed_count_of_grade(_sel_tile.grade)
		var limit: int = _sel_tile.place_limit()
		_sel_card.add_theme_stylebox_override("panel",
				_card_style(_sel_tile, limit >= 0 and placed >= limit, false))
	if _popover != null and is_instance_valid(_popover):
		_popover.queue_free()
	_popover = null
	_sel_tile = null
	_sel_card = null


## 줄바꿈된 글자가 실제로 차지하는 높이. **`Font.get_multiline_string_size` 를
## 그대로 믿으면 안 된다** — 그 함수는 글꼴 줄 높이만 더할 뿐 `Label` 이 줄
## 사이에 넣는 `line_spacing`(기본 3)을 세지 않아서, 두 줄짜리 글은 실측 49px
## 인데 46 이 돌아온다. 그 3px 이 팝오버 아래끝을 넘어 판 위로 삐져나오던 것이
## **설명이 패널을 넘어가던** 원인이다. 줄 수를 세어 그 몫을 되돌려 준다
## (실측: 1줄 23 · 2줄 49 · 3줄 75 로 `Label.get_minimum_size().y` 와 정확히 일치).
static func _text_height(text: String, width: float, font_size: int) -> float:
	if text.is_empty():
		return 0.0
	var font: Font = ThemeDB.fallback_font
	var one: float = maxf(1.0,
			font.get_string_size("가", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).y)
	var total: float = font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
	var lines: int = maxi(1, int(round(total / one)))
	return total + float(lines - 1) * POP_LINE_SPACING


## 팝오버는 **높이를 글자에서 역산해** 세운다 — 절대 좌표로 짓는 이 화면에서
## 컨테이너 자동 크기를 섞으면 자리를 잡는 프레임과 그리는 프레임이 어긋난다.
##
## **설명문 줄은 없다.** 예전에는 `training_tiles.csv` 의 `description` 을 그대로
## 찍었는데, 그 문장은 절을 사람이 손으로 옮겨 적은 것이라 절의 숫자를 고치면
## 설명만 조용히 거짓말이 됐다. 지금 이 팝오버가 답하는 것은 등급 · 이름 ·
## 놓임/상한 · **EXP** · **효과** 다섯이고, 뒤의 둘은 둘 다 타일 데이터에서
## 만들어진다(`exp_summary` / `effect_summary`).
func _build_popover(t: TrainingTile, placed: int, limit: int) -> Control:
	var text_w: float = POP_W - POP_PAD * 2.0
	var exp_h: float = _text_height(t.exp_summary(), text_w, 17)
	var eff: String = t.effect_summary()
	var eff_h: float = _text_height(eff, text_w, 16)

	var pop := Panel.new()
	var body_h: float = exp_h + (0.0 if eff.is_empty() else 10.0 + eff_h)
	pop.size = Vector2(POP_W, POP_PAD * 2.0 + 30.0 + 10.0 + body_h)
	var sty := StyleBoxFlat.new()
	sty.bg_color = OutgameTheme.SURFACE
	sty.border_color = t.grade_color()
	sty.border_width_left = 2; sty.border_width_right = 2
	sty.border_width_top  = 2; sty.border_width_bottom = 2
	sty.corner_radius_top_left = 10;    sty.corner_radius_top_right = 10
	sty.corner_radius_bottom_left = 10; sty.corner_radius_bottom_right = 10
	sty.shadow_color = Color(0.11, 0.11, 0.18, 0.28)
	sty.shadow_size = 10
	pop.add_theme_stylebox_override("panel", sty)
	# 팝오버 자신이 클릭을 삼키고 **그 클릭으로 닫힌다**. 삼키지 않으면 밑에
	# 깔린 카드가 대신 눌려 방금 연 것이 그 자리에서 닫히거나 옆 코스로
	# 갈아타 버린다 — 팝오버는 카드 두어 장을 덮으므로 반드시 일어나는 일이다.
	pop.mouse_filter = Control.MOUSE_FILTER_STOP
	pop.gui_input.connect(_on_popover_input)

	var y: float = POP_PAD
	UiHelpers.mk_label(pop, "[%s] %s" % [t.grade_name(), t.tile_name], 24,
			OutgameTheme.TEXT, Vector2(POP_PAD, y), Vector2(text_w - 84.0, 30))
	var cap: String = "∞" if limit < 0 else "%d/%d" % [placed, limit]
	UiHelpers.mk_label(pop, cap, 18, t.grade_color(),
			Vector2(POP_W - POP_PAD - 80.0, y + 5.0), Vector2(80, 24),
			HORIZONTAL_ALIGNMENT_RIGHT)
	y += 30.0 + 10.0

	var exp_lbl := UiHelpers.mk_label(pop, t.exp_summary(), 17,
			OutgameTheme.TEXT_SUB, Vector2(POP_PAD, y), Vector2(text_w, exp_h))
	exp_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	y += exp_h + 10.0

	if not eff.is_empty():
		var eff_lbl := UiHelpers.mk_label(pop, eff, 16,
				OutgameTheme.ACCENT_TEXT, Vector2(POP_PAD, y), Vector2(text_w, eff_h))
		eff_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for child in pop.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pop


## 고른 카드 **오른쪽**에 붙이되 자리가 없으면 왼쪽으로 넘긴다. 세로로는 카드
## 윗변에 맞추고 화면 밖으로 나가면 끌어올린다.
func _place_popover() -> void:
	if _popover == null or _sel_card == null or not is_instance_valid(_sel_card):
		return
	var at: Vector2 = _sel_card.get_global_rect().position - get_global_rect().position
	var x: float = at.x + _sel_card.size.x + POP_GAP
	if x + POP_W > 1080.0 - 12.0:
		x = at.x - POP_W - POP_GAP
	x = clampf(x, 12.0, 1080.0 - POP_W - 12.0)
	var y: float = clampf(at.y, GRID_Y, ScreenMetrics.safe_h() - _popover.size.y - 12.0)
	_popover.position = Vector2(x, y)
	# 가리키던 카드가 스크롤 밖으로 밀려나면 함께 숨는다 — 가리킬 것이 없는
	# 팝오버는 그 자리에 남아 화면을 덮기만 한다.
	_popover.visible = Rect2(_inv_scroll.position, _inv_scroll.size) \
			.intersects(Rect2(at, _sel_card.size))


func _on_popover_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_popover()


func _on_inv_scrolled(_v: float) -> void:
	_place_popover()


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_clear_pressed() -> void:
	if _board != null:
		_board.clear_board()
	refresh()


func _on_confirm_pressed() -> void:
	if _hub != null and _hub.has_method("on_training_confirmed"):
		_hub.on_training_confirmed()
