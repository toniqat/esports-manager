class_name TrainingView
extends Control

# 일상 훈련 편성 화면. 위에서 아래로 네 덩이고, **가로 기준선은 하나뿐이다** —
# `_grid_x()` 가 판을 화면 한가운데에 놓고 썸네일과 드롭 미리보기가 전부 그 한
# 값에서 나온다. 세로 기준선도 하나다 — `_inv_y()` 가 코스 목록을 하단 액션
# 바 위에 매달고, `_block_y()` 가 남는 자리를 판 위아래에 고르게 나눈다.
#
#   1. **파일럿 초상화 다섯** — 가로로 한 줄. 자리 순서는 전장 스트립과 같은
#      `GameEnums.ROLE_DISPLAY_ORDER`(탑 · 정글 · 미드 · 원딜 · 서폿)이고,
#      **그 자리가 곧 판의 열 번호**다. 인게임 스트립과 **같은 가로 초상화**
#      (`PilotImages.eye_for`, 480×200 밴드)를 쓰고 이름 · 역할 글자는 없다 —
#      이 줄이 답하는 질문은 "이 열이 누구의 훈련인가" 하나뿐이라 얼굴이
#      그 답이고 테두리 색이 역할이다. **누를 수 없다**(순수한 열 머리글).
#   2. **5×5 훈련판** — 열이 선수, 행이 하루. **칸도 요일 글자도 그리지
#      않는다**: 바탕은 선수마다 세로 줄 하나뿐이고, 그 위에 **모서리가 둥근**
#      코스 타일이 앉는다. 여러 칸 타일의 안쪽 경계는 이음매의 **가운데
#      토막**만 희미하게 남는다(2×2 = 작은 십자, 가로 2칸 = 작은 세로 일자).
#   3. **타일 인벤토리** — 세로로 선 **카드 한 줄의 가로 스크롤**이다. 카드에는
#      등급 띠 · 놓임/상한 · 모양 미니어처 · 이름만 있고 **설명문은 없다** —
#      카드를 누르면 그 위에 정보 팝오버가 뜬다(`_select_card`). 타일은 몇 번이든
#      다시 쓸 수 있고(보유 수량 없음) **등급별 배치 개수 상한**이 대신 판을 조인다.
#
#      **가로인 이유는 조작이다.** 판이 목록 바로 위에 있어 "카드를 판으로 끌어
#      올리기"는 세로 동작이고, 목록이 세로로 스크롤되면 같은 손짓이 두 뜻을
#      갖는다(예전에는 카드 위에서 시작한 드래그가 전부 타일 집기로 먹혀 목록이
#      아예 안 굴렀다). 지금은 **처음 움직임의 방향이 가른다** — 가로면 스크롤,
#      세로면 그 카드의 타일을 집는다(`DragScroll` 의 `cross_drag_started`).
#   4. **하단 액션 바** — 화면 끝에서 끝까지, 아래는 안전선에 밀착.
#      "판 비우기"(1) 와 "훈련 확정"(2) 이 그 구간을 2:1 로 나눠 갖는다
#      (`OutgameTheme.add_bottom_bar`).
#
# **"주간"이라는 말은 화면에서 뺐다.** 판은 여전히 다섯 줄이고 정산도 하루씩
# 먹지만, 여기서 짜는 것은 한 주의 시간표가 아니라 선수 다섯의 일상이다 —
# 요일을 적어 두면 그 다섯 칸이 달력의 약속처럼 읽힌다.
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
#
# **인벤토리 쪽 드래그는 내장 경로가 아니다.** 카드에 `set_drag_forwarding` 을
# 걸면 엔진이 10px 만 움직여도 드래그를 시작해 가로 스크롤과 다툰다. 그래서
# 방향 판정을 `DragScroll` 이 먼저 하고, 세로로 판정나면 이 화면이
# `force_drag` 로 드래그를 연다(`_on_inv_cross_drag`). 드롭 쪽(판)은 그대로다.

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
const TITLE_H: float     = 44.0
const THUMB_W: float     = CELL - 6.0
## 인게임 스트립과 같은 eye 밴드(480×200)라 높이는 그 비율에서 나온다 —
## 임의 높이로 늘리면 얼굴이 찌그러진다.
const THUMB_H: float     = THUMB_W / 2.4
const THUMB_GAP: float   = 15.0                 # 초상화 ↔ 판
const INV_LABEL_GAP: float = 32.0               # "훈련 코스" 글자 ↔ 목록

## 코스 카드 — **세로로 선 카드 한 장**이고 목록은 그 한 줄의 가로 스크롤이다.
## 폭은 화면에 5장 반이 걸리게 잡았다 — 반 장이 잘려 보이는 것이 곧 "옆으로
## 더 있다"이고, 딱 떨어지면 목록이 거기서 끝난 것처럼 보인다.
const INV_CARD_W: float    = 168.0
const INV_CARD_H: float    = 236.0
const INV_GAP: float       = 14.0
const INV_CARD_RADIUS: int = 12
## 카드 맨 위 등급 띠(등급 색 면 + 등급 글자 + 놓임/상한).
const INV_BAND_H: float    = 36.0
## 마지막 카드 뒤에 두는 여백 — 끝까지 굴렸을 때 마지막 카드가 화면 끝에
## 딱 붙으면 "여기가 끝"과 "더 있는데 안 보인다"가 같은 그림이 된다.
const INV_TAIL_PAD: float  = 24.0

## 카드 안 모양 미니어처의 자리 · 크기(`_mini_geom` / `_add_shape_mini`).
## 등급 띠 아래의 오목한 상자 안에 가운데 정렬로 앉는다.
const MINI_PAD: float = 10.0
const MINI_Y: float   = INV_BAND_H + 10.0
const MINI_H: float   = 124.0
const MINI_MAX: float = 26.0
## 이름 — 미니어처 상자 아래, 두 줄까지.
const INV_NAME_Y: float = MINI_Y + MINI_H + 6.0

## 정보 팝오버. 고른 카드 **옆**에 뜨고 자리가 없으면 반대쪽으로 넘어간다.
const POP_W: float   = 380.0
const POP_PAD: float = 16.0
const POP_GAP: float = 10.0
## `Label` 이 줄 사이에 넣는 간격(기본 테마의 `line_spacing`). `_text_height`
## 가 이것을 되돌려 주지 않으면 여러 줄 글이 팝오버 아래로 넘친다.
const POP_LINE_SPACING: float = 3.0

## ── 판의 바탕과 타일 ────────────────────────────────────────────────────────
## **빈 칸은 그리지 않는다.** 선수 한 명당 세로 줄 하나가 그 열이 어디까지인지를
## 말하고, 그 밖에는 흰 종이다 — 칸을 스물다섯 개 그려 두면 아직 아무것도 안
## 놓은 판이 이미 무언가로 꽉 찬 것처럼 보이고, 놓인 타일이 그 격자에 묻힌다.
const COLUMN_LINE_W: float     = 2.0
const COLUMN_LINE_COLOR: Color = OutgameTheme.BORDER

## 타일 몸통의 모서리 굴림. **바깥으로 난 두 변이 만나는 구석에서만** 둥글어
## 지므로(`_tile_cell_box`) 여러 칸 타일은 한 덩어리의 둥근 사각형이 된다.
const TILE_RADIUS: int = 20

## 타일 **안쪽** 칸 경계. 이음매를 통째로 긋지 않고 **가운데 토막만** 희미하게
## 남긴다 — 2×2 는 한가운데 작은 십자, 가로 2칸은 한가운데 작은 세로 일자가
## 된다. 선을 끝까지 그으면 그것이 곧 "여기서 타일이 끊긴다"로 읽혀 한 장이
## 두 장으로 보인다.
const SEAM_LEN: float = 32.0
const SEAM_W: float   = 2.0
const SEAM_ALPHA: float = 0.45

@onready var _hub: SeasonHub = get_parent() as SeasonHub

var _board: TrainingBoard = null

var _grid: Control = null                # 판 — 그리기 · 드롭 · 히트를 다 한다
var _inv_scroll: ScrollContainer = null
var _inv_row: HBoxContainer = null
var _inv_drag: DragScroll = null
## 지금 손가락이 눌린 코스 카드 — 세로 드래그로 판정나면 이 카드의 타일을 집는다.
var _inv_press_tile: TrainingTile = null

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

# Staff (M3): who runs training / tactics, the EXP multiplier line, and the
# "코치 추천" (auto-arrange) slot of the bottom bar — hidden when the manager
# owns training (`StaffSystem.is_delegated`).
const STAFF_Y: float = TITLE_Y + TITLE_H + 2.0
const STAFF_H: float = 30.0
var _staff_lbl: Label = null
var _effect_lbl: Label = null
var _bar_buttons: Array = []
var _bar_specs: Array = []


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


## 코스 목록의 높이 — 카드 한 장 높이. 가로 스크롤바는 숨긴다(잘린 카드가 이미
## "옆으로 더 있다"를 말한다).
static func _inv_h() -> float:
	return INV_CARD_H


## 코스 목록의 y. 하단 액션 바 바로 위에 매단다.
static func _inv_y() -> float:
	return OutgameTheme.bottom_bar_top() - 24.0 - _inv_h()


## **초상화 줄 + 판** 덩어리의 y. 목록 위로 남는 자리를 판 위와
## 아래에 고르게 나눈다 — 통째로 위에 붙여 두면 화면 아래쪽 300px 이 이유
## 없이 비고, 아래에 붙이면 제목과 판 사이가 벌어진다.
static func _block_y() -> float:
	var block_h: float = THUMB_H + THUMB_GAP + GRID_H
	var top: float = STAFF_Y + STAFF_H + 12.0
	var bottom: float = _inv_y() - INV_LABEL_GAP - 16.0
	return top + maxf(0.0, bottom - top - block_h) * 0.5


static func _thumb_y() -> float:
	return _block_y()


static func _grid_y() -> float:
	return _block_y() + THUMB_H + THUMB_GAP


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)

	UiHelpers.mk_label(self, "일상 훈련 편성", 34, OutgameTheme.TEXT,
			Vector2(0, TITLE_Y), Vector2(ScreenMetrics.vp_w(), TITLE_H),
			HORIZONTAL_ALIGNMENT_CENTER)
	_staff_lbl = UiHelpers.mk_label(self, "", 22, OutgameTheme.TEXT_SUB,
			Vector2(MARGIN, STAFF_Y), Vector2(1080.0 - MARGIN * 2.0, STAFF_H),
			HORIZONTAL_ALIGNMENT_CENTER)

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
		panel.position = Vector2(_grid_x() + float(seat) * CELL + 3.0, _thumb_y())
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


## **판 옆의 요일 글자는 없다.** 다섯 줄이 무슨 요일인가는 이 화면이 답해야
## 하는 질문이 아니다 — 여기서 짜는 것은 한 주의 시간표가 아니라 선수 다섯의
## 일상이고, 요일을 적어 두면 그 다섯 칸이 달력의 약속처럼 읽힌다. 줄의 순서
## 자체(위에서 아래로)가 이미 앞뒤를 말한다. 정산은 여전히 하루씩 먹는다.
##
## `TrainingBoard.DAY_NAMES` 는 이 화면이 유일한 소비자였으므로 함께 삭제됐다 —
## 요일 이름이 필요한 자리는 시간 경과 화면 하나이고, 그쪽은 예전부터
## `OutgameTheme.DAY_NAMES` 를 읽는다.
func _build_grid() -> void:
	_grid = Control.new()
	_grid.position = Vector2(_grid_x(), _grid_y())
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
	var top: float = _inv_y()
	var h: float = _inv_h()

	UiHelpers.mk_label(self, "훈련 코스", 22, OutgameTheme.TEXT_SUB,
			Vector2(MARGIN, top - INV_LABEL_GAP), Vector2(400, 28))
	# Right side of the same row: what the staff stats do to the courses.
	_effect_lbl = UiHelpers.mk_label(self, "", 20, OutgameTheme.ACCENT_TEXT,
			Vector2(1080.0 - MARGIN - 600.0, top - INV_LABEL_GAP), Vector2(600, 28),
			HORIZONTAL_ALIGNMENT_RIGHT)

	_inv_scroll = ScrollContainer.new()
	_inv_scroll.position = Vector2(MARGIN, top)
	_inv_scroll.size     = Vector2(1080.0 - MARGIN * 2.0, h)
	_inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_inv_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_inv_scroll)

	_inv_row = HBoxContainer.new()
	_inv_row.add_theme_constant_override("separation", int(INV_GAP))
	_inv_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_inv_scroll.add_child(_inv_row)

	# **가로로 끌면 스크롤, 세로로 끌면 타일 집기.** 방향은 처음 문턱을 넘는
	# 순간 한 번만 정한다 — 그 뒤로는 손가락이 비스듬히 흘러도 뜻이 안 바뀐다.
	_inv_drag = DragScroll.attach(_inv_scroll, true, true)
	_inv_drag.cross_drag_started.connect(_on_inv_cross_drag)

	# 팝오버는 스크롤 **밖**에 사는 별개의 판이라(안에 두면 스크롤 폭에 잘린다)
	# 스크롤이 움직이면 따라가야 한다.
	_inv_scroll.get_h_scroll_bar().value_changed.connect(_on_inv_scrolled)


## **하단 구간을 둘이 2:1 로 나눠 갖는다** — 주 행동인 "훈련 확정"이 오른쪽
## 3분의 2, 되돌리는 "판 비우기"가 왼쪽 3분의 1이다(`OutgameTheme.add_bottom_bar`).
## 코스 목록의 높이가 이 바의 윗변에서 역산되므로(`_inv_y`) 바를 손보면 목록이
## 저절로 따라 올라간다.
##
## M3: a third slot "코치 추천" sits between them (ghost, weight 1) and is shown
## only while training is delegated to staff — when hidden, the bar is laid out
## again so the other two keep the 1:2 split (`OutgameTheme.layout_bottom_bar`).
func _build_confirm_button() -> void:
	_bar_specs = [
		{"text": "판 비우기", "style": "ghost",   "font": 28, "weight": 1.0},
		{"text": "코치 추천", "style": "ghost",   "font": 28, "weight": 1.0},
		{"text": "훈련 확정", "style": "primary", "font": 34, "weight": 2.0},
	]
	_bar_buttons = OutgameTheme.add_bottom_bar(self, _bar_specs)
	(_bar_buttons[0] as Button).pressed.connect(_on_clear_pressed)
	(_bar_buttons[1] as Button).pressed.connect(_on_auto_pressed)
	(_bar_buttons[2] as Button).pressed.connect(_on_confirm_pressed)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_rebuild_inventory()
	_refresh_thumbs()
	_refresh_staff()
	if _grid != null:
		_grid.queue_redraw()


## Staff line under the title + effect line above the course list + whether the
## "코치 추천" slot is shown. Reads only `TrainingBoard` / `StaffSystem`.
func _refresh_staff() -> void:
	if _board == null or _hub == null:
		return
	var state: Dictionary = _board.season_state()
	if _staff_lbl != null:
		_staff_lbl.text = "%s · %s" % [
			_owner_text(state, "training"), _owner_text(state, "tactics")]
	if _effect_lbl != null:
		var top: int = TrainingTile.max_unlocked_grade(_board.tactics_stat())
		_effect_lbl.text = "훈련 효과 ×%.2f · 사용 가능 %s 등급까지" % [
			TrainingTile.training_exp_mult(_board.training_stat()),
			String(TrainingTile.GRADE_NAMES[top])]
	if _bar_buttons.size() == 3:
		var auto_btn: Button = _bar_buttons[1]
		var show_auto: bool = StaffSystem.is_delegated(state, "training")
		if auto_btn.visible != show_auto:
			auto_btn.visible = show_auto
			OutgameTheme.layout_bottom_bar(_bar_buttons, _bar_specs)


## "훈련: 강민호 코치 17" / "전술: 감독 6" — who covers this stat and its value.
static func _owner_text(state: Dictionary, stat: String) -> String:
	var who: String = StaffSystem.owner_name(state, stat)
	match StaffSystem.owner(state, stat):
		StaffSystem.OWNER_STAFF:
			who += " 코치"
		StaffSystem.OWNER_ASSISTANT:
			who += " 어시스턴트"
	return "%s: %s %d" % [String(StaffSystem.STAT_LABELS.get(stat, stat)), who,
			StaffSystem.effective(state, stat)]


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
	# **바탕은 선수마다 세로 줄 하나뿐이다.** 칸을 스물다섯 개 깔면 빈 판이
	# 이미 무언가로 꽉 찬 것처럼 보이고, 놓인 타일이 그 격자에 묻힌다.
	# 줄은 열 한가운데를 지나므로 그 위에 앉는 타일이 줄을 덮는다 — 놓인
	# 자리와 빈 자리가 "줄이 보이는가"로 갈린다.
	for x in COLS:
		var cx: float = (float(x) + 0.5) * CELL
		_grid.draw_rect(Rect2(cx - COLUMN_LINE_W * 0.5, 0.0,
				COLUMN_LINE_W, GRID_H), COLUMN_LINE_COLOR, true)

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
		_draw_tile_seams(t, ox, oy)
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

	# 드롭 미리보기 — 놓을 수 있으면 초록, 없으면 빨강. **놓인 타일과 같은
	# 둥근 몸통**이라 미리보기의 모양이 곧 결과의 모양이다.
	var tint: Color = Color(OutgameTheme.POSITIVE, 0.45) if _hover_ok \
			else Color(OutgameTheme.NEGATIVE, 0.38)
	var own2: Dictionary = {}
	for c3 in _drag_tile.cells:
		own2[c3] = true
	for c2 in _drag_tile.cells:
		var cc: Vector2i = c2
		var at := Vector2i(_hover_cell.x + cc.x, _hover_cell.y + cc.y)
		if at.x < 0 or at.x >= COLS or at.y < 0 or at.y >= ROWS:
			continue
		var box: Dictionary = _tile_cell_box(own2, cc, _hover_cell.x, _hover_cell.y,
				tint, null, TILE_RADIUS)
		_grid.draw_style_box(box["sb"], box["rect"])


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
		var box: Dictionary = _tile_cell_box(own, c2, ox, oy,
				col, col.darkened(0.30), TILE_RADIUS)
		_grid.draw_style_box(box["sb"], box["rect"])


## 칸 하나의 사각형과 그 옷. **같은 타일과 맞닿은 변에서는 여백도 테두리도
## 모서리 굴림도 버린다** — 그래서 여러 칸 타일은 안쪽에 이음매 없이 이어
## 붙고 바깥 윤곽만 남으며, 굴림은 **바깥으로 난 두 변이 만나는 구석**에만
## 걸려 덩어리 전체가 하나의 둥근 사각형이 된다(전장의 캠프 아웃라인이 쓰는
## 규칙과 같다: 그 변 너머의 이웃이 같은 타일이 아닐 때만 그린다).
##
## 그리는 쪽이 셋(판 · 드롭 미리보기 · 커서를 따라오는 미리보기)이라 기하가
## 한 함수에 있어야 한다 — 손가락 밑의 모양과 놓인 결과가 다르면 그것은
## 미리보기가 아니다.
static func _tile_cell_box(own: Dictionary, c: Vector2i, ox: int, oy: int,
		fill: Color, border: Variant, radius: int) -> Dictionary:
	var up: bool = own.has(c + Vector2i(0, -1))
	var dn: bool = own.has(c + Vector2i(0, 1))
	var lf: bool = own.has(c + Vector2i(-1, 0))
	var rt: bool = own.has(c + Vector2i(1, 0))
	var x0: float = float(ox + c.x) * CELL + (0.0 if lf else CELL_PAD)
	var x1: float = float(ox + c.x + 1) * CELL - (0.0 if rt else CELL_PAD)
	var y0: float = float(oy + c.y) * CELL + (0.0 if up else CELL_PAD)
	var y1: float = float(oy + c.y + 1) * CELL - (0.0 if dn else CELL_PAD)

	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	if border is Color:
		sb.border_color = border
		sb.border_width_left   = 0 if lf else int(TILE_EDGE)
		sb.border_width_right  = 0 if rt else int(TILE_EDGE)
		sb.border_width_top    = 0 if up else int(TILE_EDGE)
		sb.border_width_bottom = 0 if dn else int(TILE_EDGE)
	sb.corner_radius_top_left     = 0 if (up or lf) else radius
	sb.corner_radius_top_right    = 0 if (up or rt) else radius
	sb.corner_radius_bottom_left  = 0 if (dn or lf) else radius
	sb.corner_radius_bottom_right = 0 if (dn or rt) else radius
	return {"rect": Rect2(x0, y0, x1 - x0, y1 - y0), "sb": sb}


## 타일 **안쪽** 칸 경계. 이음매를 통째로 긋는 대신 **연속한 이음매 하나마다
## 그 가운데 토막만** 희미하게 남긴다 — 2×2 는 세로 이음매와 가로 이음매가
## 둘 다 타일 한가운데에서 잘려 작은 십자가 되고, 가로 2칸은 한가운데 작은
## 세로 일자가 되며, 가로 5칸([전지 훈련])은 이음매 넷이 각자 제 자리에서
## 짧은 세로 토막으로 남는다. 끝까지 그으면 그 선이 곧 "여기서 타일이
## 끊긴다"로 읽혀 한 장이 여러 장으로 보인다.
func _draw_tile_seams(t: TrainingTile, ox: int, oy: int) -> void:
	var own: Dictionary = {}
	for c in t.cells:
		own[c] = true
	var ext: Vector2i = t.extent()
	var col: Color = TrainingTile.color_of(String(t.cell_colors[0])).darkened(0.30)
	col.a = SEAM_ALPHA

	# 세로 이음매 — 열 경계(gx)마다 위아래로 이어진 구간을 찾는다.
	for gx in range(1, ext.x):
		var run: int = -1
		for gy in range(ext.y + 1):
			var joined: bool = gy < ext.y \
					and own.has(Vector2i(gx - 1, gy)) and own.has(Vector2i(gx, gy))
			if joined and run < 0:
				run = gy
			elif not joined and run >= 0:
				_draw_seam(Vector2(float(ox + gx) * CELL,
						(float(oy) + float(run + gy) * 0.5) * CELL), true, col)
				run = -1

	# 가로 이음매 — 행 경계(gy)마다 좌우로 이어진 구간.
	for gy2 in range(1, ext.y):
		var run2: int = -1
		for gx2 in range(ext.x + 1):
			var joined2: bool = gx2 < ext.x \
					and own.has(Vector2i(gx2, gy2 - 1)) and own.has(Vector2i(gx2, gy2))
			if joined2 and run2 < 0:
				run2 = gx2
			elif not joined2 and run2 >= 0:
				_draw_seam(Vector2((float(ox) + float(run2 + gx2) * 0.5) * CELL,
						float(oy + gy2) * CELL), false, col)
				run2 = -1


func _draw_seam(at: Vector2, vertical: bool, col: Color) -> void:
	if vertical:
		_grid.draw_rect(Rect2(at.x - SEAM_W * 0.5, at.y - SEAM_LEN * 0.5,
				SEAM_W, SEAM_LEN), col, true)
	else:
		_grid.draw_rect(Rect2(at.x - SEAM_LEN * 0.5, at.y - SEAM_W * 0.5,
				SEAM_LEN, SEAM_W), col, true)


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
		# 판에서 타일이 실제로 빠졌다. 놓기(SOFT)의 반대 동작이라 그보다 가볍게 —
		# 걷어내기는 되돌리는 손이지 확정하는 손이 아니다.
		Haptics.play(Haptics.Kind.LIGHT)
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
	set_drag_preview(_make_drag_preview(t))
	return {"tile": t.id, "from": "board"}


func _grid_can_drop(at_position: Vector2, _data: Variant) -> bool:
	if _board == null or _drag_tile == null:
		return false
	var origin: Vector2i = _origin_for(_drag_tile, at_position)
	var ok: bool = _board.can_place(_drag_tile, origin)
	if origin != _hover_cell or ok != _hover_ok:
		# **놓을 수 있는 칸에 스냅할 때마다** 한 톡 — 판 위를 끌고 다니는 동안
		# 칸을 하나 넘을 때마다 따다닥 걸리는 것이 이 화면의 조작 감각이다.
		# 놓을 수 없는 자리는 조용하다(그 침묵이 곧 "여기엔 안 들어간다"이고,
		# 미리보기의 빨간 칸이 이미 그것을 말한다).
		if ok:
			Haptics.play(Haptics.Kind.LIGHT)
		_hover_cell = origin
		_hover_ok = ok
		_grid.queue_redraw()
	return ok


func _grid_drop(at_position: Vector2, _data: Variant) -> void:
	if _board == null or _drag_tile == null:
		return
	if _board.place(_drag_tile.id, _origin_for(_drag_tile, at_position)) >= 0:
		# 타일이 판에 물렸다 — 뭉툭한 한 겹이 그 조작을 닫는다.
		# 집기(SELECT) · 칸 넘김(LIGHT)보다 무거워야 한 동작의 끝으로 읽힌다.
		Haptics.play(Haptics.Kind.SOFT)
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
	# 타일이 손에 딸려 올라왔다. 한 동작의 첫 박자다 —
	# 칸을 넘을 때마다(LIGHT) 따다닥 이어지고 놓을 때(SOFT) 닫힌다.
	# 미리보기는 부르는 쪽이 붙인다 — 판은 내장 드래그 안이라 `set_drag_preview`,
	# 인벤토리는 드래그를 직접 여는 것이라 `force_drag` 에 넘긴다.
	Haptics.play(Haptics.Kind.SELECT)
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

	# 판과 **같은 기하 · 같은 색**이다(`_tile_cell_box`) — 둥근 모서리도,
	# 안쪽 이음매의 가운데 토막도 그대로 따라온다. 손가락 밑의 모양이 놓인
	# 결과와 다르면 그것은 미리보기가 아니다.
	var own: Dictionary = {}
	for c in t.cells:
		own[c] = true
	for i in t.cells.size():
		var c2: Vector2i = t.cells[i]
		var col: Color = TrainingTile.color_of(String(t.cell_colors[i]))
		var geom: Dictionary = _tile_cell_box(own, c2, 0, 0,
				col, col.darkened(0.30), TILE_RADIUS)
		var r: Rect2 = geom["rect"]
		var box := Panel.new()
		box.add_theme_stylebox_override("panel", geom["sb"])
		box.position = r.position
		box.size     = r.size
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(box)
	_add_preview_seams(body, t)
	var name_lbl := UiHelpers.mk_label(body, t.tile_name, 20, OutgameTheme.TEXT,
			Vector2(8, body.size.y * 0.5 - 14.0),
			Vector2(body.size.x - 16.0, 28), HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return root


## 커서를 따라오는 미리보기의 이음매. 판 쪽(`_draw_tile_seams`)은 `_grid` 의
## `_draw` 에 그리고 이쪽은 노드를 쌓는 자리라 그리는 수단만 다르다 — 자리를
## 정하는 규칙(연속한 이음매의 가운데 토막)은 같은 뜻을 따른다.
func _add_preview_seams(body: Control, t: TrainingTile) -> void:
	var own: Dictionary = {}
	for c in t.cells:
		own[c] = true
	var ext: Vector2i = t.extent()
	var col: Color = TrainingTile.color_of(String(t.cell_colors[0])).darkened(0.30)
	col.a = SEAM_ALPHA
	for gx in range(1, ext.x):
		var run: int = -1
		for gy in range(ext.y + 1):
			var joined: bool = gy < ext.y and own.has(Vector2i(gx - 1, gy)) \
					and own.has(Vector2i(gx, gy))
			if joined and run < 0:
				run = gy
			elif not joined and run >= 0:
				_add_seam_rect(body, Vector2(float(gx) * CELL,
						float(run + gy) * 0.5 * CELL), true, col)
				run = -1
	for gy2 in range(1, ext.y):
		var run2: int = -1
		for gx2 in range(ext.x + 1):
			var joined2: bool = gx2 < ext.x and own.has(Vector2i(gx2, gy2 - 1)) \
					and own.has(Vector2i(gx2, gy2))
			if joined2 and run2 < 0:
				run2 = gx2
			elif not joined2 and run2 >= 0:
				_add_seam_rect(body, Vector2(float(run2 + gx2) * 0.5 * CELL,
						float(gy2) * CELL), false, col)
				run2 = -1


func _add_seam_rect(body: Control, at: Vector2, vertical: bool, col: Color) -> void:
	var r := ColorRect.new()
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		r.position = Vector2(at.x - SEAM_W * 0.5, at.y - SEAM_LEN * 0.5)
		r.size     = Vector2(SEAM_W, SEAM_LEN)
	else:
		r.position = Vector2(at.x - SEAM_LEN * 0.5, at.y - SEAM_W * 0.5)
		r.size     = Vector2(SEAM_LEN, SEAM_W)
	body.add_child(r)


# ── 인벤토리 ─────────────────────────────────────────────────────────────────
func _rebuild_inventory() -> void:
	if _inv_row == null or _board == null:
		return
	# 카드 노드가 통째로 새로 서므로 팝오버가 가리키던 카드도 사라진다.
	_close_popover()
	for child in _inv_row.get_children():
		child.queue_free()

	for t_raw in _board.all_tiles():
		_inv_row.add_child(_make_inventory_card(t_raw as TrainingTile))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(INV_TAIL_PAD, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_inv_row.add_child(pad)


## 코스 카드 한 장 — **세로로 선 카드**. 위에서부터 등급 띠(등급 글자 ·
## 놓임/상한) → 오목한 상자 안의 모양 미니어처 → 이름. 설명문과 EXP 요약은
## 정보 팝오버가 들고 있다: 훑어 고를 때 견주는 것은 이름과 모양이다.
func _make_inventory_card(t: TrainingTile) -> Control:
	var w: float = INV_CARD_W
	var placed: int = _board.placed_count_of_grade(t.grade)
	var limit: int = _board.limit_of(t)
	var grade_locked: bool = not _board.is_unlocked(t)
	var locked: bool = _card_locked(t)

	var card := Panel.new()
	card.custom_minimum_size = Vector2(w, INV_CARD_H)
	card.add_theme_stylebox_override("panel", _card_style(t, locked, false))
	# **PASS** — 눌림이 스크롤까지 올라가야 `DragScroll` 이 방향을 판정한다.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	# 탭 = 고르기(정보 팝오버), 세로 드래그 = 집기. **잠긴 카드도 고를 수 있다** —
	# 못 놓는 것과 무엇인지 못 보는 것은 다른 일이다.
	card.gui_input.connect(_on_card_input.bind(t, card))

	# Everything but the lock-reason chip lives in `body`, so a locked card fades
	# its contents while the reason stays fully readable on top.
	var body := Control.new()
	body.position = Vector2.ZERO
	body.size = Vector2(w, INV_CARD_H)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.modulate = Color(1, 1, 1, 0.42) if locked else Color(1, 1, 1, 1)
	card.add_child(body)

	# 등급 띠 — 카드 윗변의 둥근 모서리를 그대로 이어받는다.
	var g: Color = t.grade_color()
	var band := Panel.new()
	band.position = Vector2.ZERO
	band.size = Vector2(w, INV_BAND_H)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsty := StyleBoxFlat.new()
	bsty.bg_color = Color(g.r, g.g, g.b, 0.22)
	bsty.corner_radius_top_left  = INV_CARD_RADIUS
	bsty.corner_radius_top_right = INV_CARD_RADIUS
	band.add_theme_stylebox_override("panel", bsty)
	body.add_child(band)
	var grade_lbl := UiHelpers.mk_label(band, t.grade_name(), 22, g,
			Vector2(MINI_PAD + 2.0, 0), Vector2(40, INV_BAND_H))
	grade_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grade_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap: String = "" if grade_locked else _cap_text(placed, limit)
	var cap_lbl := UiHelpers.mk_label(band, cap, 17, OutgameTheme.TEXT_SUB,
			Vector2(w - 84.0, 0), Vector2(72, INV_BAND_H),
			HORIZONTAL_ALIGNMENT_RIGHT)
	cap_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 모양 미니어처를 담는 오목한 상자 — 판에서 몇 칸을 먹는지가 카드의 그림이다.
	var well := Panel.new()
	well.position = Vector2(MINI_PAD, MINI_Y)
	well.size = Vector2(w - MINI_PAD * 2.0, MINI_H)
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 8))
	body.add_child(well)
	_add_shape_mini(body, t, w)

	var name_lbl := UiHelpers.mk_label(body, t.tile_name, 19, OutgameTheme.TEXT,
			Vector2(8, INV_NAME_Y),
			Vector2(w - 16.0, INV_CARD_H - INV_NAME_Y - 8.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Grade not unlocked by tactics: say why, on the shape well.
	if grade_locked:
		var chip_h: float = 36.0
		OutgameTheme.add_chip(card, _lock_reason(t),
				Vector2(MINI_PAD + 6.0, MINI_Y + (MINI_H - chip_h) * 0.5),
				Vector2(w - (MINI_PAD + 6.0) * 2.0, chip_h),
				OutgameTheme.TEXT, OutgameTheme.TEXT_ON_FILL, 18)

	return card


## Locked = grade not unlocked by tactics, or its placement limit is reached.
## Locked cards can still be selected (popover), never picked up.
func _card_locked(t: TrainingTile) -> bool:
	if _board == null:
		return true
	return not _board.can_take_more(t)


## "전술 11 필요" — the tactics a locked grade needs.
static func _lock_reason(t: TrainingTile) -> String:
	return "전술 %d 필요" % TrainingTile.required_tactics(t.grade)


static func _cap_text(placed: int, limit: int) -> String:
	return "∞" if limit < 0 else "%d/%d" % [placed, limit]


static func _card_style(t: TrainingTile, locked: bool, selected: bool) -> StyleBoxFlat:
	var g: Color = t.grade_color()
	var sty := StyleBoxFlat.new()
	sty.bg_color = OutgameTheme.ACCENT_DIM if selected else OutgameTheme.SURFACE
	sty.border_color = Color(g.r, g.g, g.b, 0.35 if locked else 1.0)
	var bw: int = 4 if selected else 2
	sty.border_width_left = bw; sty.border_width_right = bw
	sty.border_width_top  = bw; sty.border_width_bottom = bw
	sty.corner_radius_top_left = INV_CARD_RADIUS
	sty.corner_radius_top_right = INV_CARD_RADIUS
	sty.corner_radius_bottom_left = INV_CARD_RADIUS
	sty.corner_radius_bottom_right = INV_CARD_RADIUS
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


## 인벤토리 카드에서 끌어내기 — `DragScroll` 이 **세로** 드래그로 판정했을 때만
## 온다. 내장 드래그 경로가 아니므로 `force_drag` 로 직접 연다. 카드 어디를
## 잡았는지는 보지 않는다 — 끌려 나온 타일은 언제나 커서를 한가운데에 둔다.
func _on_inv_cross_drag(_press_pos: Vector2) -> void:
	var t: TrainingTile = _inv_press_tile
	_inv_press_tile = null
	if t == null or _board == null or _drag_tile != null:
		return
	if _card_locked(t):
		return   # 잠긴 카드 — 고를 수는 있어도 집을 수는 없다
	_begin_drag(t, {})
	force_drag({"tile": t.id, "from": "inventory"}, _make_drag_preview(t))


# ── 정보 팝오버 ──────────────────────────────────────────────────────────────
## 카드 탭. 같은 카드를 다시 누르면 닫히고, 다른 카드를 누르면 그쪽으로 갈아탄다.
func _on_card_input(event: InputEvent, t: TrainingTile, card: Control) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_inv_press_tile = t
		return
	# 스크롤했거나 타일을 집은 손가락의 떼기는 탭이 아니다.
	if _drag_tile != null or (_inv_drag != null and _inv_drag.moved):
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
	var limit: int = _board.limit_of(t)
	card.add_theme_stylebox_override("panel", _card_style(t, _card_locked(t), true))
	_popover = _build_popover(t, placed, limit)
	add_child(_popover)
	_place_popover()


func _close_popover() -> void:
	if _sel_tile != null and _sel_card != null and is_instance_valid(_sel_card):
		_sel_card.add_theme_stylebox_override("panel",
				_card_style(_sel_tile, _card_locked(_sel_tile), false))
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
	# Locked grade (tactics): one extra line saying what it needs vs. now.
	var lock: String = ""
	if _board != null and not _board.is_unlocked(t):
		lock = "%s (지금 전술 %d)" % [_lock_reason(t), _board.tactics_stat()]
	var lock_h: float = _text_height(lock, text_w, 16)

	var pop := Panel.new()
	var body_h: float = exp_h + (0.0 if eff.is_empty() else 10.0 + eff_h) \
			+ (0.0 if lock.is_empty() else 10.0 + lock_h)
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
	var cap: String = "" if not lock.is_empty() else _cap_text(placed, limit)
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
		y += eff_h + 10.0

	if not lock.is_empty():
		var lock_lbl := UiHelpers.mk_label(pop, lock, 16,
				OutgameTheme.NEGATIVE, Vector2(POP_PAD, y), Vector2(text_w, lock_h))
		lock_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for child in pop.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pop


## 고른 카드 **위**에 띄운다 — 카드가 화면 아래 한 줄로 늘어서 있어 옆자리는
## 다른 카드가 차지하고 있다. 가로로는 카드 가운데에 맞추고 화면 밖으로 나가면
## 끌어들인다.
func _place_popover() -> void:
	if _popover == null or _sel_card == null or not is_instance_valid(_sel_card):
		return
	var at: Vector2 = _sel_card.get_global_rect().position - get_global_rect().position
	var x: float = at.x + (_sel_card.size.x - POP_W) * 0.5
	x = clampf(x, 12.0, 1080.0 - POP_W - 12.0)
	var y: float = maxf(12.0, at.y - _popover.size.y - POP_GAP)
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


## "코치 추천" — the delegated coach fills the board (`TrainingBoard.auto_arrange`);
## the player can still edit it afterwards.
func _on_auto_pressed() -> void:
	if _board == null:
		return
	_board.auto_arrange()
	refresh()


func _on_confirm_pressed() -> void:
	if _hub != null and _hub.has_method("on_training_confirmed"):
		_hub.on_training_confirmed()
