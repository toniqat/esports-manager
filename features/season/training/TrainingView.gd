class_name TrainingView
extends Control

# 일상 훈련 편성 화면. 위에서 아래로 네 덩이고, **판이 화면 한가운데에 온다** —
# 초상화 줄과 판이 한 덩어리(`Block`)로 가운데 정렬되므로 열 머리글과 열이 어긋날
# 수 없다. 세로로는 코스 목록이 하단 액션 바 위에 매달리고(`Inventory`), 남는
# 자리를 판 위아래에 고르게 나눈다(`BoardArea` = CenterContainer).
#
# **레이아웃의 정본은 `UI_View_TrainingView.tscn` 이다** — 제목, 스태프 줄, 초상화 다섯
# (`UI_Comp_TrainingThumb.tscn` 인스턴스), 판 자리(`%Grid`), "훈련 코스" 줄, 코스 스크롤, 하단
# 액션 바(`%Bar`). 반복 항목은 아이템 씬이다: 코스 카드 `UI_Comp_TrainingCourseCard.tscn`,
# 정보 팝오버 `UI_View_TrainingCoursePopover.tscn`. 스타일은 루트의 공용 테마
# (`resources/OutgameTheme.tres`) 변형이 정한다. **이 스크립트가 하는 일**: `%` 노드
# 바인딩, 데이터 채우기(초상화 · 역할 테두리 색 · EXP 칩 · 스태프 / 효과 줄 · 코스 카드),
# 기기별 안전 영역(화면째 위 인셋만큼 내리고 `%SafeArea` 아래끝 · `%Bar` 높이에 아래
# 인셋), 그리고 **판 그리기 · 드래그 앤 드롭 · 히트** — 판(`%Grid`)은 노드 스물다섯이
# 아니라 `_draw_grid` 한 장이다. 씬에서 지운 노드는 되살리지 않는다.
#
#   1. **파일럿 초상화 다섯** — 가로로 한 줄. 자리 순서는 전장 스트립과 같은
#      `GameEnums.ROLE_DISPLAY_ORDER`(탑 · 정글 · 미드 · 원딜 · 서폿)이고,
#      **그 자리가 곧 판의 열 번호**다. 인게임 스트립과 **같은 가로 초상화**
#      (`PilotImages.eye_for`, 480×200 밴드)를 쓰고 이름 · 역할 글자는 없다 —
#      이 줄이 답하는 질문은 "이 열이 누구의 훈련인가" 하나뿐이라 얼굴이
#      그 답이고 테두리 색이 역할이다. 누르면 그 선수의 상세 시트(`SeasonPilotDetail`).
#   2. **5×5 훈련판** — 열이 선수, 행이 하루. **칸도 요일 글자도 그리지
#      않는다**: 바탕은 선수마다 세로 줄 하나뿐이고, 그 위에 **모서리가 둥근**
#      코스 타일이 앉는다. 여러 칸 타일의 안쪽 경계는 이음매의 **가운데
#      토막**만 희미하게 남는다(2×2 = 작은 십자, 가로 2칸 = 작은 세로 일자).
#   3. **타일 인벤토리** — 세로로 선 **카드 한 줄의 가로 스크롤**이다. 카드에는
#      등급 띠 · 놓임/보유 · 모양 미니어처 · 이름만 있고 **설명문은 없다** —
#      카드를 누르면 그 위에 정보 팝오버가 뜬다(`_select_card`). 타일은 몇 번이든
#      다시 쓸 수 있고(보유 수량 없음) **등급별 배치 개수 상한**이 대신 판을 조인다.
#
#      **가로인 이유는 조작이다.** 판이 목록 바로 위에 있어 "카드를 판으로 끌어
#      올리기"는 세로 동작이고, 목록이 세로로 스크롤되면 같은 손짓이 두 뜻을
#      갖는다(예전에는 카드 위에서 시작한 드래그가 전부 타일 집기로 먹혀 목록이
#      아예 안 굴렀다). 지금은 **처음 움직임의 방향이 가른다** — 가로면 스크롤,
#      세로면 그 카드의 타일을 집는다(`DragScroll` 의 `cross_drag_started`).
#   4. **하단 액션 바** — 화면 끝에서 끝까지, 아래는 안전선에 밀착.
#      "판 비우기"(1) 와 "훈련 확정"(2) 이 그 구간을 1:2 로 나눠 갖는다
#      (`%Bar` 의 stretch ratio — 코치에게 맡긴 동안만 "코치 추천"(1) 이 가운데에 선다).
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

# ── 판의 기하 (그리기 · 히트가 같은 값을 읽는다) ─────────────────────────────
## 판의 칸은 **정사각형**이다. 색 면이 곧 "한 선수의 하루"라 가로로 납작하면
## 여러 칸 타일의 모양(2×2 · 1×3 · 5×1)이 판 위에서 왜곡돼 읽힌다.
## 씬의 `%Grid` 크기(880×880)와 초상화 폭(`TrainingThumb` 170 + 간격 6)이 이 값에 맞춰져 있다.
const CELL: float        = 176.0
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

## 마지막 코스 카드 뒤에 두는 여백 — 끝까지 굴렸을 때 마지막 카드가 화면 끝에
## 딱 붙으면 "여기가 끝"과 "더 있는데 안 보인다"가 같은 그림이 된다.
const INV_TAIL_PAD: float  = 24.0

## 정보 팝오버와 고른 카드 사이 간격, 화면 가장자리에서 물려 잡는 여백.
const POP_GAP: float = 10.0
const POP_EDGE: float = 12.0

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

const SCENE_PATH: String = "res://features/season/training/UI_View_TrainingView.tscn"

@onready var _hub: SeasonHub = get_parent() as SeasonHub

var _board: TrainingBoard = null

var _grid: Control = null                # 판 — 그리기 · 드롭 · 히트를 다 한다
var _inv_scroll: ScrollContainer = null
var _inv_row: HBoxContainer = null
var _inv_drag: DragScroll = null
## 지금 손가락이 눌린 코스 카드 — 세로 드래그로 판정나면 이 카드의 타일을 집는다.
var _inv_press_tile: TrainingTile = null

var _thumb_faces: Array = []             # 5 TextureRect
## Per-pilot EXP chip on each thumbnail (`_refresh_exp_chips`) — shown only when
## that pilot's multiplier differs from the team-wide one (rank-row `stat_growth` bonus).
var _thumb_exp_chips: Array = []         # 5 Panel (`%ExpChip` of each TrainingThumb)
var _thumb_exp_texts: Array = []         # 5 Label (`%ExpText`)
var _exp_chip_base: StyleBoxFlat = null  # 씬의 칩 옷 — 색만 바꿔 복사한다
## §15 B run training level chip on each thumbnail (`_refresh_level_chips`).
var _thumb_level_chips: Array = []       # 5 Panel (`%LevelChip`)
var _thumb_level_texts: Array = []       # 5 Label (`%LevelText`)

# 인벤토리에서 고른 코스와 그 정보 팝오버.
var _sel_tile: TrainingTile = null
var _sel_card: TrainingCourseCard = null
var _popover: TrainingCoursePopover = null

# 드래그 상태. `_drag_tile` 이 null 이 아니면 지금 무언가를 끌고 있다.
var _drag_tile: TrainingTile = null
var _drag_from_board: Dictionary = {}        # 판에서 걷어 온 배치(되돌리기용)
var _hover_cell: Vector2i = Vector2i(-1, -1)
var _hover_ok: bool = false

var _built: bool = false

# Staff (M3): who runs training, the EXP multiplier line, and the
# "코치 추천" (auto-arrange) slot of the bottom bar — hidden when the manager
# owns training (`StaffSystem.is_delegated`).
var _staff_lbl: Label = null
var _effect_lbl: Label = null
var _bar_buttons: Array = []             # [판 비우기, 코치 추천, 훈련 확정]


## 씬을 인스턴스한다. `TrainingView.new()` 는 빈 Control 이라 쓰지 않는다.
## 자기 씬을 preload 하면 스크립트 ↔ 씬 순환 참조가 되므로 load 한다.
static func create() -> TrainingView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TrainingView


func _ready() -> void:
	ensure_view()
	if UiPreview.is_standalone(self):
		_fill_preview()


# Idempotent — SeasonHub calls this each time it routes to TRAINING.
func ensure_view() -> void:
	if not _built:
		_bind()
		_built = true
	_resolve_board()
	refresh()


func _resolve_board() -> void:
	if _board != null:
		return
	if _hub == null:
		return
	_board = _hub.get_node_or_null("TrainingBoard") as TrainingBoard


# ── Bind ─────────────────────────────────────────────────────────────────────
func _bind() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다. 바탕만 도로 늘린다.
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	# 아래 인셋만 코드 몫 — `%SafeArea` 아래끝이 안전선으로 오르고, 바(`Bar*` 변형)의 색면은
	# 화면 끝까지, 글자는 안전선 위(`resources/README.md` "Bottom action bar"). 코스 목록과
	# 판이 `%SafeArea` 아래끝에서 역산되므로 함께 따라 올라간다.
	OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)

	_staff_lbl = %StaffLine
	_effect_lbl = %EffectLine
	_bind_thumbs()
	_bind_grid()
	_bind_inventory()

	_bar_buttons = [%ClearButton, %AutoButton, %ConfirmButton]
	(%ClearButton as Button).pressed.connect(_on_clear_pressed)
	(%AutoButton as Button).pressed.connect(_on_auto_pressed)
	(%ConfirmButton as Button).pressed.connect(_on_confirm_pressed)


## 열 머리글 다섯. **글자가 없다** — 얼굴이 누구인지를, 테두리 색이 역할을 말한다.
## 누르면 그 선수의 상세 시트(`SeasonPilotDetail`). 인게임 파일럿 스트립과 같은 가로 초상화라 전장에서
## 보던 얼굴과 여기 얼굴이 같은 컷이다. 테두리 색만 코드가 넣는다(역할 = 데이터).
func _bind_thumbs() -> void:
	var row: Control = %Thumbs
	for seat in COLS:
		var thumb: Panel = row.get_child(seat) as Panel
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var role_col: Color = ROLE_COLORS[r]
		var sty := OutgameTheme.variation_box(&"TrainingThumbFrame")
		sty.border_color = Color(role_col.r, role_col.g, role_col.b, 0.85)
		thumb.add_theme_stylebox_override(&"panel", sty)
		_thumb_faces.append(thumb.get_node("%Face"))
		(thumb.get_node("%Hit") as Button).pressed.connect(_on_thumb_pressed.bind(seat))
		var chip: Panel = thumb.get_node("%ExpChip")
		if _exp_chip_base == null:
			_exp_chip_base = OutgameTheme.variation_box(&"TrainingThumbExpChip")
		chip.visible = false
		_thumb_exp_chips.append(chip)
		_thumb_exp_texts.append(thumb.get_node("%ExpText"))
		_thumb_level_chips.append(thumb.get_node("%LevelChip"))
		_thumb_level_texts.append(thumb.get_node("%LevelText"))


## **판 옆의 요일 글자는 없다.** 다섯 줄이 무슨 요일인가는 이 화면이 답해야
## 하는 질문이 아니다 — 여기서 짜는 것은 한 주의 시간표가 아니라 선수 다섯의
## 일상이고, 요일을 적어 두면 그 다섯 칸이 달력의 약속처럼 읽힌다. 줄의 순서
## 자체(위에서 아래로)가 이미 앞뒤를 말한다. 정산은 여전히 하루씩 먹는다.
##
## `TrainingBoard.DAY_NAMES` 는 이 화면이 유일한 소비자였으므로 함께 삭제됐다 —
## 요일 이름이 필요한 자리는 시간 경과 화면 하나이고, 그쪽은 예전부터
## `OutgameTheme.DAY_NAMES` 를 읽는다.
func _bind_grid() -> void:
	_grid = %Grid
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_on_grid_input)
	# 판 자신이 드롭 대상이자 드래그 출발점이다. `set_drag_forwarding` 을 쓰면
	# 세 콜백을 한 노드에 몰아넣을 수 있어 `_grid` 를 서브클래스로 만들 필요가
	# 없다 — 이 화면에서 판은 그리기 한 장이지 노드 스물다섯 개가 아니다.
	_grid.set_drag_forwarding(_grid_get_drag_data, _grid_can_drop, _grid_drop)


func _bind_inventory() -> void:
	_inv_scroll = %CourseScroll
	_inv_row = %CourseRow

	# **가로로 끌면 스크롤, 세로로 끌면 타일 집기.** 방향은 처음 문턱을 넘는
	# 순간 한 번만 정한다 — 그 뒤로는 손가락이 비스듬히 흘러도 뜻이 안 바뀐다.
	_inv_drag = DragScroll.attach(_inv_scroll, true, true)
	_inv_drag.cross_drag_started.connect(_on_inv_cross_drag)

	# 팝오버는 스크롤 **밖**에 사는 별개의 판이라(안에 두면 스크롤 폭에 잘린다)
	# 스크롤이 움직이면 따라가야 한다.
	_inv_scroll.get_h_scroll_bar().value_changed.connect(_on_inv_scrolled)


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
	if _board == null:
		return
	var state: Dictionary = _board.season_state()
	if _staff_lbl != null:
		# Tactics no longer gates course grades (courses are owned items), so
		# only the training owner is named here.
		_staff_lbl.text = _owner_text(state, "training")
	if _effect_lbl != null:
		_effect_lbl.text = _effect_text(_shared_parts(state))
	_refresh_exp_chips(state)
	if _bar_buttons.size() == 3:
		var auto_btn: Button = _bar_buttons[1]
		var show_auto: bool = StaffSystem.is_delegated(state, "training")
		# 숨긴 칸은 `%Bar`(HBox)가 빼고 남은 칸끼리 비율대로 다시 나눈다.
		auto_btn.visible = show_auto


## Team-wide EXP multiplier parts — the same calls `TrainingBoard.exp_mult_table`
## multiplies for every cell (training stat × finance × trait `train_exp_pct`).
## Part labels are l10n keys, translated in `_effect_text`.
## Per-pilot parts (rank-row growth bonus, outing fatigue) are not here; see `_refresh_exp_chips`.
func _shared_parts(state: Dictionary) -> Array:
	return [
		[L.TERM_PERSON_STAFF, TrainingTile.training_exp_mult(_board.training_stat())],
		[L.TRAINING_VIEW_PART_FINANCE, FinanceSystem.training_exp_mult(state)],
		[L.TRAINING_VIEW_PART_TRAIT, TraitSystem.run_pct_mult(state, "train_exp_pct")],
	]


static func _parts_product(parts: Array) -> float:
	var m: float = 1.0
	for part in parts:
		m *= float((part as Array)[1])
	return m


## "훈련 효과 ×1.21" — plus "(스태프 ×1.10 · 특성 ×1.10)" when anything besides the
## staff stat moves it. Parts at ×1.00 are left out of the breakdown.
static func _effect_text(parts: Array) -> String:
	var mult: String = "%.2f" % _parts_product(parts)
	var shown: Array = []
	var others_move: bool = false
	for i in parts.size():
		var part: Array = parts[i]
		var v: float = float(part[1])
		var moves: bool = absf(v - 1.0) >= 0.005
		if i > 0 and moves:
			others_move = true
		if moves or i == 0:
			shown.append("%s ×%.2f" % [Loc.t(String(part[0])), v])  # l10n-dynamic: training.view.part_*
	if others_move:
		return Loc.t(L.TRAINING_VIEW_EFFECT_BREAKDOWN, {"mult": mult, "parts": " · ".join(shown)})
	return Loc.t(L.TRAINING_VIEW_EFFECT, {"mult": mult})


## Thumbnail chips: each pilot's own multiplier relative to the team-wide one, read
## from `TrainingBoard.exp_mult_table` (what settlement multiplies). A pilot's best
## day is used, so a single outing-fatigue day does not hide the rank-row growth bonus.
func _refresh_exp_chips(state: Dictionary) -> void:
	if _thumb_exp_chips.size() != COLS:
		return
	var shared: float = _parts_product(_shared_parts(state))
	var table: Dictionary = _board.exp_mult_table()
	var pilots: Array = _pilots()
	for seat in COLS:
		var chip: Panel = _thumb_exp_chips[seat]
		var ratio: float = 1.0
		if pilots[seat] != null and shared > 0.0:
			var best: float = 0.0
			for day in TrainingBoard.ROWS:
				best = maxf(best, float(table.get(Vector2i(seat, day), 0.0)))
			ratio = best / shared
		chip.visible = absf(ratio - 1.0) >= 0.005
		if chip.visible:
			(_thumb_exp_texts[seat] as Label).text = "EXP ×%.2f" % ratio
			var sty := _exp_chip_base.duplicate() as StyleBoxFlat
			sty.bg_color = OutgameTheme.POSITIVE if ratio > 1.0 else OutgameTheme.NEGATIVE
			chip.add_theme_stylebox_override(&"panel", sty)


## "훈련: 강민호 코치 17" / "전술: 감독 6" — who covers this stat and its value.
static func _owner_text(state: Dictionary, stat: String) -> String:
	var params: Dictionary = {
		"stat": StaffSystem.stat_label(stat),
		"name": StaffSystem.owner_name(state, stat),
		"value": StaffSystem.effective(state, stat),
	}
	match StaffSystem.owner(state, stat):
		StaffSystem.OWNER_STAFF:
			return Loc.t(L.TRAINING_VIEW_OWNER_STAFF, params)
		StaffSystem.OWNER_ASSISTANT:
			return Loc.t(L.TRAINING_VIEW_OWNER_ASSISTANT, params)
	return "%s: %s %d" % [params["stat"], params["name"], params["value"]]


func _refresh_thumbs() -> void:
	var pilots: Array = _pilots()
	for seat in COLS:
		var p: PlayerData = pilots[seat]
		(_thumb_faces[seat] as TextureRect).texture = \
				null if p == null else PilotImages.eye_for(p.id)
	_refresh_level_chips(pilots)


## §15 B — "Lv2" chip per portrait; accent fill while that pilot's bar is full (a limit
## break is due or its goal is open), dark rail otherwise.
func _refresh_level_chips(pilots: Array) -> void:
	if _thumb_level_chips.size() != COLS or _board == null:
		return
	var state: Dictionary = _board.season_state()
	for seat in COLS:
		var chip: Panel = _thumb_level_chips[seat]
		var p: PlayerData = pilots[seat]
		chip.visible = p != null and TrainingLevel.has_level(state, p.id)
		if not chip.visible:
			continue
		(_thumb_level_texts[seat] as Label).text = TrainingLevel.chip_text(state, p.id)
		var sty := OutgameTheme.variation_box(&"PilotThumbTag")
		sty.bg_color = OutgameTheme.ACCENT if TrainingLevel.awaiting_break(state, p.id) \
				else OutgameTheme.RAIL
		chip.add_theme_stylebox_override(&"panel", sty)


func _on_thumb_pressed(seat: int) -> void:
	var p: PlayerData = _pilots()[seat]
	if p != null:
		SeasonPilotDetail.open(self, p.id)


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

	for t_raw in _board.owned_tiles():
		var t: TrainingTile = t_raw
		var card := TrainingCourseCard.create()
		_inv_row.add_child(card)
		card.fill(t, _cap_of(t), _card_locked(t))
		# 탭 = 고르기(정보 팝오버), 세로 드래그 = 집기. **잠긴 카드도 고를 수 있다** —
		# 못 놓는 것과 무엇인지 못 보는 것은 다른 일이다.
		card.gui_input.connect(_on_card_input.bind(t, card))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(INV_TAIL_PAD, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	_inv_row.add_child(pad)


## Locked = every owned copy is already on the board.
## Locked cards can still be selected (popover), never picked up.
func _card_locked(t: TrainingTile) -> bool:
	if _board == null:
		return true
	return not _board.can_take_more(t)


## `placed/owned` of one course ("∞" for the unlimited basic course).
func _cap_of(t: TrainingTile) -> String:
	var owned: int = _board.owned_count(t)
	return "∞" if owned == TrainingCourses.UNLIMITED else "%d/%d" % [_board.placed_count(t), owned]


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
func _on_card_input(event: InputEvent, t: TrainingTile, card: TrainingCourseCard) -> void:
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


## 팝오버(`TrainingCoursePopover`)는 등급 · 이름 · 놓임/보유 · **EXP** · **효과** 를
## 든다 — 설명문 줄은 없다(`README.md` "Course inventory + info popover").
func _select_card(t: TrainingTile, card: TrainingCourseCard) -> void:
	_close_popover()
	_sel_tile = t
	_sel_card = card
	card.set_selected(true, _card_locked(t))
	_popover = TrainingCoursePopover.create()
	# 팝오버 자신이 클릭을 삼키고(씬에서 STOP) **그 클릭으로 닫힌다**. 삼키지 않으면
	# 밑에 깔린 카드가 대신 눌려 방금 연 것이 그 자리에서 닫히거나 옆 코스로
	# 갈아타 버린다 — 팝오버는 카드 두어 장을 덮으므로 반드시 일어나는 일이다.
	_popover.gui_input.connect(_on_popover_input)
	add_child(_popover)
	_popover.fill(t, _cap_of(t))
	_place_popover()


func _close_popover() -> void:
	if _sel_tile != null and _sel_card != null and is_instance_valid(_sel_card):
		_sel_card.set_selected(false, _card_locked(_sel_tile))
	if _popover != null and is_instance_valid(_popover):
		_popover.queue_free()
	_popover = null
	_sel_tile = null
	_sel_card = null


## 고른 카드 **위**에 띄운다 — 카드가 화면 아래 한 줄로 늘어서 있어 옆자리는
## 다른 카드가 차지하고 있다. 가로로는 카드 가운데에 맞추고 화면 밖으로 나가면
## 끌어들인다.
func _place_popover() -> void:
	if _popover == null or _sel_card == null or not is_instance_valid(_sel_card):
		return
	var origin: Vector2 = get_global_rect().position
	var at: Vector2 = _sel_card.get_global_rect().position - origin
	var pop_w: float = _popover.size.x
	var x: float = at.x + (_sel_card.size.x - pop_w) * 0.5
	x = clampf(x, POP_EDGE, size.x - pop_w - POP_EDGE)
	var y: float = maxf(POP_EDGE, at.y - _popover.size.y - POP_GAP)
	_popover.position = Vector2(x, y)
	# 가리키던 카드가 스크롤 밖으로 밀려나면 함께 숨는다 — 가리킬 것이 없는
	# 팝오버는 그 자리에 남아 화면을 덮기만 한다.
	var view := Rect2(_inv_scroll.get_global_rect().position - origin, _inv_scroll.size)
	_popover.visible = view.intersects(Rect2(at, _sel_card.size))


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


## F6 단독 실행 미리보기 — 메모리 런 + 미리보기 전용 `TrainingBoard` 에 코치 추천으로 판을
## 채우고, 코스 카드 하나를 골라 정보 팝오버까지 띄운 상태(`resources/UiPreview.gd`).
## "훈련 확정"은 호스트(`SeasonHub`)가 없어 아무 일도 안 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	if UiPreview.ensure_run() == null:
		return
	_board = TrainingBoard.new()
	_board.name = "PreviewBoard"
	add_child(_board)
	# A new run owns Basic Training I only — the preview owns two of every course.
	TrainingCourses.grant_all(_board.season_state(), 2)
	_board.auto_arrange()
	refresh()
	_preview_pick_card.call_deferred()


## 판을 다시 세운 다음 프레임에 세 번째 코스 카드를 고른다 — 카드 자리가 잡혀야
## 팝오버가 그 위에 선다.
func _preview_pick_card() -> void:
	await get_tree().process_frame
	var cards: Array = _inv_row.get_children().filter(
			func(c: Node) -> bool: return c is TrainingCourseCard)
	if cards.size() > 2:
		var card: TrainingCourseCard = cards[2]
		_select_card(card.tile, card)
