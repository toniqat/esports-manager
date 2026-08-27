extends Node

# LoL international ban/pick: B-B-P-PP-PP-P-B-B-PP-PP
# Each side ends with 2 bans + 5 picks. Sides alternate per token.
# AI picks/bans are completely random among legal mechs.
#
# ── 화면 ─────────────────────────────────────────────────────────────────────
# 세로 한 장을 **위 / 가운데 / 아래** 세 덩이로 나눈다.
#
#   위     — 상대 팀 블록: 밴 칩 2개 → **메크 초상화 5칸** → 파일럿 초상화 5인
#   가운데 — **픽창**: 역할군 필터 탭 + 메크 격자(정사각 칸, 세로 4.5칸이 보이는
#            수직 스크롤). 반쯤 잘린 다섯째 줄이 곧 "아래로 더 있다"는 신호다.
#   아래   — 아군 팀 블록: 위 블록을 **거울로 뒤집은 순서**(파일럿 초상화 →
#            메크 초상화 → 밴 칩).
#
# **메크 칸은 파일럿 칸보다 세로로 두 배 길다**(`MECH_H_RATIO`) — 파일럿은 눈높이
# 밴드(2.4:1)라 납작하고 메크는 정사각 초상화라, 같은 폭에서 메크가 두 배 높이를
# 가져야 두 그림이 각자 제 비율로 앉는다. 배치가 거울인 것은 "안쪽이 전장"이라는
# 읽기 기준을 지키기 위해서다 — 적은 메크가 위, 아군은 메크가 아래에 붙는다.
#
# **픽창에만 짙은 배경판을 깐다**(`GRID_BG_COLOR`). 나머지 화면은 어두운 회색
# (`PAGE_BG_COLOR`)이라, 판 하나가 "여기가 고르는 곳"과 "여기는 양 팀 상황"을
# 색 한 단계로 가른다 — 예전에는 셋이 전부 같은 바탕이라 위아래 초상화 줄과
# 격자가 한 덩어리로 붙어 보였다.
#
# 파일럿 초상화는 전장 스트립과 **같은 eye 크롭**(`PilotImages.eye_for`)이고
# 이름표도 역할 태그도 붙지 않는다 — 다섯 칸의 순서 자체가 역할이기 때문이다
# (`GameEnums.ROLE_DISPLAY_ORDER`: 탑 · 정글 · 미드 · 원딜 · 서폿).
#
# ── 조작 (1탭 선택 → 2탭 확정) ───────────────────────────────────────────────
# 메크를 한 번 누르면 격자 위로 **하단 시트**가 올라와 그 기체의 스탯 · 패시브 ·
# 카드 셋을 보여 준다. 확정은 시트의 버튼이거나 **같은 메크를 한 번 더 누르는
# 것**이다. 한 번 누르면 곧장 나가던 예전 방식은 되돌릴 수 없는 선택에서 실수
# 한 번이 경기를 통째로 바꿔 버렸다. 격자 칸에서 스탯 · 패시브 줄이 사라진
# 지금은 시트가 그 정보를 들고 있는 **유일한** 자리다.
#
# 시트는 **내 차례가 아닐 때도 열린다** — 상대가 고민하는 동안 다음에 뭘 고를지
# 들여다보는 것이 밴픽 화면이 하는 일의 절반이다. 그때는 확정 버튼만 잠긴다.
#
# ── 배정 (ASSIGN) ────────────────────────────────────────────────────────────
# 14수가 끝나면 **화면을 갈아타지 않는다** — 픽창이 사라지고 그 자리에 "게임
# 시작" 버튼 하나가 서며, 아래 아군 블록이 배정판으로 다시 선다:
#
#   파일럿 상체 일러스트 5인  (드래프트 화면의 선택 칸과 **같은 크롭 · 같은 비율**)
#   메크 칸 5개              (끌어다 놓아 서로 맞바꾼다)
#   "드래그 드롭으로 메크-파일럿 지정 변경"  (메크 줄 오른쪽 아래, 작은 글씨)
#   밴 칩
#
# **파일럿이 위, 메크가 아래다.** 배정은 "이 사람이 무엇을 타는가"를 정하는
# 일이고, 그 문장의 주어가 위에 와야 한 칸을 세로로 훑는 것이 곧 한 문장이
# 된다. 초상화가 `PilotImages.bust_for` 상체 크롭으로 커진 것도 같은 이유다 —
# 눈높이 밴드는 다섯을 한 줄로 세워 놓고 훑는 데는 좋지만, 그 다섯 명 각각에게
# 기체를 붙이는 화면에서는 누가 누구인지가 먼저 읽혀야 한다.
#
# **양 팀 초상화와 메크 칸이 전부 눌린다** — 파일럿은 `DraftDetailPanel`,
# 메크는 `MechDetailPanel` 이다. 배정은 스탯을 보고 하는 일인데 그 스탯을
# 볼 자리가 없으면 픽 순서 그대로 두는 것 말고 할 수 있는 것이 없다.
# 인게임 상세 패널과 달리 **둘을 한 화면에 겹치지 않고 인게임 탭도 없다** —
# 아직 경기가 시작되지 않아 인게임 상태라는 것이 존재하지 않는다.
#
# 예전에는 이 단계가 `assign/AssignController.gd` 라는 **별도 화면**이었는데,
# 방금 고른 열 대가 화면에서 통째로 사라진 뒤 글자 목록으로 다시 나타나서
# "내가 뭘 골랐더라"를 두 번 읽게 했다. 그 파일은 삭제됐다.

signal phase_finished(result: Dictionary)

const CARD_SCENE := preload("res://scenes/Card.tscn")

const _AI_THINK_SEC := 0.45

# Per-action sequence (14 entries). Each = [side, kind].
# kind: 0 = BAN, 1 = PICK
const ACTION_BAN  := 0
const ACTION_PICK := 1

const SEQUENCE: Array = [
	[GameEnums.DraftSide.BLUE, ACTION_BAN],   # 0
	[GameEnums.DraftSide.RED,  ACTION_BAN],   # 1
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 2
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 3
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 4
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 5
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 6
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 7
	[GameEnums.DraftSide.BLUE, ACTION_BAN],   # 8
	[GameEnums.DraftSide.RED,  ACTION_BAN],   # 9
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 10
	[GameEnums.DraftSide.BLUE, ACTION_PICK],  # 11
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 12
	[GameEnums.DraftSide.RED,  ACTION_PICK],  # 13
]

## 한 팀의 슬롯 수 — 파일럿 초상화 · 메크 칸이 모두 이 수만큼 선다.
const SLOT_COUNT: int = 5
const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
## 역할 배지에 찍는 두 글자. 격자 칸이 정사각이 되면서 역할군 이름을 통째로 적을
## 자리가 없어졌고, 애초에 그 자리는 **읽는 곳이 아니라 알아보는 곳**이다 —
## 색이 먼저 눈에 들어오고 글자는 그 색을 확인해 준다.
const ROLE_INITIALS: Array = ["Tk", "Fi", "As", "Su", "Sn"]
## 역할군 색. 시즌 화면들(`HubView` / `TrainingView` / `MatchPrepController`)이
## 쓰는 팔레트와 같은 다섯 색이다 — 같은 역할이 화면마다 다른 색이면 색으로
## 알아본다는 전제가 무너진다.
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),  # TANK
	Color(1.00, 0.55, 0.20),  # FIGHTER
	Color(0.75, 0.40, 1.00),  # ASSASSIN
	Color(0.30, 0.85, 0.45),  # SUPPORT
	Color(1.00, 0.35, 0.35),  # SNIPER
]

# ── 레이아웃 ─────────────────────────────────────────────────────────────────
# 세로 좌표는 전부 아래 상수들에서 **계산해서** 나온다(`_layout()`). 안전 영역이
# 기기마다 다르므로 격자 칸 높이만은 칸 **폭**에서 나온다(정사각) — 그래야 어느
# 화면에서나 칸이 찌그러지지 않고, 대신 픽창 자체가 남는 공간에 맞춰 줄어든다.
const SIDE_MARGIN: float  = 25.0
const TOP_PAD: float      = 8.0
const BOT_PAD: float      = 10.0
const BLOCK_GAP: float    = 10.0
## 진행 순서 표시 줄(14칸)의 높이. 예전에는 그 밑에 "BLUE 픽 — 내 차례 (3 / 14)"
## 한 줄이 더 있었지만 **삭제됐다** — 지금 누구 차례인지는 칩이 밝아진 자리가
## 말해 주고, 무엇을 하는 차례인지는 시트의 확정 버튼이 말해 준다.
const PIPS_H: float       = 22.0
const TABS_H: float       = 58.0
const GRID_COLS: int      = 5
const GRID_GAP: float     = 10.0
## 격자에서 한 화면에 보이는 줄 수. 정수가 아닌 것이 요점이다 — 다섯째 줄이
## 반쯤 잘려 보이는 것이 "아래로 더 있다"는 유일한 신호다.
const GRID_VISIBLE_ROWS: float = 4.5
## 세로 스크롤바가 먹는 폭. 칸 폭을 여기서 뺀 나머지로 잡아야 마지막 열이
## 스크롤바 밑으로 들어가지 않는다.
const SCROLLBAR_W: float  = 16.0
## 픽창 배경판이 내용 바깥으로 더 먹는 여백.
const GRID_PANEL_PAD: float = 8.0
## 격자 칸 아래 이름 줄의 높이. 칸의 **정사각 부분은 초상화 몫**이고 이름은 그
## 아래에 따로 붙는다 — 이름을 초상화 위에 얹으면 어두운 기체에서 글자가 통째로
## 사라진다.
const CELL_NAME_H: float  = 28.0

# 팀 블록 내부 (위 블록 기준 순서 — 아래 블록은 이 순서를 뒤집는다)
const BAN_ROW_H: float       = 44.0
const BAN_CHIP: float        = 38.0
## eye 크롭의 가로:세로 비 (`PilotStrip.EYE_ASPECT` 와 같은 값). 임의 높이로
## 늘리면 얼굴이 찌그러진다.
const EYE_ASPECT: float      = 2.4
## 메크 칸 높이 = 파일럿 초상화 높이 × 이 값.
const MECH_H_RATIO: float    = 2.0
const BLOCK_INNER_GAP: float = 5.0

# 하단 시트
const SHEET_PAD: float        = 20.0
## 왼쪽 아트 칸의 **폭**. 높이는 시트에서 남는 만큼을 통째로 쓰고 그 안에서
## 세로 가운데 정렬한다 — 아트를 위에 붙이면 그 밑에 아무것도 없는 구멍이
## 300px 넘게 남는다(정사각 아트라 폭을 늘리는 것 말고는 커지지 않는다).
const SHEET_ART_W: float      = 280.0
const SHEET_CARD_SCALE: float = 0.9
const SHEET_CARD_GAP: float   = 10.0
const SHEET_BTN_H: float      = 76.0

## 배정 단계에서 메크 칸을 끌기 시작하는 문턱(px). 이보다 덜 움직인 것은 탭이지
## 드래그가 아니다 — 손가락은 언제나 조금씩 떨린다. 문턱을 못 넘긴 탭은
## 그 칸의 메크 상세를 연다.
const DRAG_THRESHOLD_PX: float = 8.0

## 배정 단계 메크 줄 오른쪽 아래의 조작 안내 한 줄.
const ASSIGN_HINT_H: float = 24.0
const ASSIGN_HINT_FONT: int = 17
const ASSIGN_HINT_TEXT: String = "드래그 드롭으로 메크-파일럿 지정 변경"
## 픽창이 있던 자리에 서는 "게임 시작" 버튼.
const START_BTN_W: float = 460.0
const START_BTN_H: float = 108.0

## 픽창(격자) 배경 — 화면에서 **가장 어두운** 자리다.
const GRID_BG_COLOR := Color(0.04, 0.04, 0.10, 1.0)
## 그 밖의 화면 바탕 — 어두운 회색. 픽창보다 밝아서 판 하나가 파여 보인다.
const PAGE_BG_COLOR := Color(0.15, 0.15, 0.17, 1.0)
const PANEL_COLOR := Color(0.09, 0.10, 0.16, 1.0)
const SHEET_COLOR := Color(0.11, 0.12, 0.19, 1.0)
const BLUE_COLOR  := Color(0.36, 0.62, 0.98)
const RED_COLOR   := Color(0.98, 0.44, 0.40)
const BAN_TINT    := Color(0.30, 0.30, 0.34, 1.0)
const TEXT_DIM    := Color(0.62, 0.66, 0.78)
const ACCENT      := Color(1.0, 0.85, 0.30)

@onready var _mf: MatchFlow = get_parent() as MatchFlow
@onready var _gm: Node = get_node("/root/GameManager")

var _all_mechs: Array = []
## 격자에 늘어놓는 순서 — 역할군을 **화면 순서**(탑 · 정글 · 미드 · 원딜 · 서폿)로
## 묶는다. `_all_mechs` 는 CSV 순서(역할 열거값 순)를 그대로 지켜야 하므로
## 사본을 따로 든다.
var _grid_mechs: Array = []
var _player_side: int = GameEnums.DraftSide.BLUE
var _action_idx: int  = 0
var _banned: Array = []            # Array[int] — 양 팀 밴 전부 (합법성 판정의 유일한 표)
var _side_bans: Dictionary  = {}   # side(int) → Array[int]
var _side_picks: Dictionary = {}   # side(int) → Array[int]

var _rosters: Dictionary    = {}   # side(int) → Array[PlayerData] (역할 0..4 순)
var _team_names: Dictionary = {}   # side(int) → String

## 배정 단계인가. true 면 격자가 사라지고 아군 블록이 드래그 가능한 배정판이 된다.
var _assign_mode: bool = false
## 자리(seat, 화면 순서 0..4) → mech_id. 처음에는 픽 순서 그대로다.
var _assign_order: Array = []

# ── UI ───────────────────────────────────────────────────────────────────────
var _panel: Panel
var _seq_pips: Array = []          # Array[Panel]
var _cells: Dictionary = {}        # mech_id(int) → {btn, art, veil, tag, mech}
var _side_ui: Dictionary = {}      # side(int) → {holder, ban_chips, mech_slots}
var _filter_role: int = -1
var _filter_btns: Array = []       # Array[Button]
var _grid_bg: Panel
var _scroll: ScrollContainer
var _grid_content: Control
var _thumbs: Dictionary = {}       # mech_id(int) → Texture2D (lazy)

# 하단 시트
var _sheet_dim: ColorRect
var _sheet: Panel
var _sheet_confirm: Button
var _selected_mech_id: int = -1

# 배정 단계의 상세 팝업 — 파일럿은 드래프트 화면과 **같은 팝업**을 쓴다
# (`DraftDetailPanel` 은 `PlayerData` 한 장과 오토로드만 있으면 열린다).
# 둘 다 lazy-add: 배정 단계에 들어가기 전에는 열릴 일이 없다.
var _pilot_detail: DraftDetailPanel = null
var _mech_detail: MechDetailPanel = null

# 배정 단계의 드래그 상태
var _drag_seat: int = -1
var _drag_armed: bool = false      # 눌렀지만 아직 문턱을 못 넘었다
var _drag_from: Vector2 = Vector2.ZERO
var _drag_ghost: Control = null

## `_layout()` 이 채우는 계산된 좌표표. 화면 하나를 세우는 동안 열 군데가 같은
## 값을 물어보므로 한 번만 풀어 둔다.
var _lay: Dictionary = {}


func enter(all_mechs: Array, player_side: int,
		player_roster: Array = [], enemy_roster: Array = [],
		player_team_name: String = "", enemy_team_name: String = "") -> void:
	_all_mechs   = all_mechs
	_grid_mechs  = _sorted_for_grid(all_mechs)
	_player_side = player_side
	_action_idx  = 0
	_banned.clear()
	var enemy_side: int = _other_side(player_side)
	_side_bans  = {player_side: [], enemy_side: []}
	_side_picks = {player_side: [], enemy_side: []}
	_rosters    = {player_side: player_roster, enemy_side: enemy_roster}
	_team_names = {
		player_side: (player_team_name if player_team_name != "" else "아군"),
		enemy_side:  (enemy_team_name  if enemy_team_name  != "" else "상대"),
	}
	_selected_mech_id = -1
	_filter_role = -1
	_assign_mode = false
	_assign_order.clear()
	_build_ui()
	_refresh_ui()
	_maybe_run_ai()


## 격자용 정렬 — 역할군은 화면 순서로, 같은 역할군 안에서는 CSV 순서(= id)로.
func _sorted_for_grid(mechs: Array) -> Array:
	var out: Array = mechs.duplicate()
	out.sort_custom(func(a, b):
		var ra: int = GameEnums.role_seat((a as MechData).role)
		var rb: int = GameEnums.role_seat((b as MechData).role)
		if ra != rb:
			return ra < rb
		return (a as MechData).id < (b as MechData).id)
	return out


# ── 레이아웃 계산 ────────────────────────────────────────────────────────────
func _layout() -> void:
	var w: float = ScreenMetrics.vp_w()
	var h: float = ScreenMetrics.safe_h()
	var strip_w: float = w - SIDE_MARGIN * 2.0
	var cell_w: float = strip_w / float(SLOT_COUNT)
	var portrait_w: float = cell_w - 14.0
	var portrait_h: float = portrait_w / EYE_ASPECT
	var mech_h: float = portrait_h * MECH_H_RATIO
	var block_h: float = BAN_ROW_H + BLOCK_INNER_GAP + mech_h + 2.0 + portrait_h
	# 배정 단계에서는 파일럿 초상화가 **상체 일러스트**로 커진다 — 드래프트
	# 화면의 선택 칸과 같은 크롭이라 비율도 같은 곳(`PilotImages.BUST_ASPECT`)
	# 에서 온다. 폭은 그대로이므로 높이만 그 비율이 정한다.
	var assign_portrait_h: float = portrait_w / PilotImages.BUST_ASPECT
	var assign_block_h: float = assign_portrait_h + 2.0 + mech_h + 2.0 \
			+ ASSIGN_HINT_H + BLOCK_INNER_GAP + BAN_ROW_H

	var top_block_y: float = TOP_PAD + PIPS_H + BLOCK_GAP
	var band_top: float = top_block_y + block_h + BLOCK_GAP
	var bot_block_y: float = h - BOT_PAD - block_h
	var band_h: float = maxf(200.0, (bot_block_y - BLOCK_GAP) - band_top)

	# 격자 칸 — 폭은 열 수가 정하고 **높이는 그 폭이 정한다**(정사각 + 이름 줄).
	var content_w: float = strip_w - GRID_PANEL_PAD * 2.0 - SCROLLBAR_W
	var gcell_w: float = (content_w - GRID_GAP * float(GRID_COLS - 1)) / float(GRID_COLS)
	var gcell_h: float = gcell_w + CELL_NAME_H
	var grid_h_want: float = GRID_VISIBLE_ROWS * (gcell_h + GRID_GAP) - GRID_GAP
	var grid_h_max: float = band_h - TABS_H - BLOCK_GAP - GRID_PANEL_PAD * 2.0
	var grid_h: float = clampf(grid_h_want, 240.0, maxf(240.0, grid_h_max))

	# 픽창 한 덩이(패딩 + 탭 + 격자)를 가운데 띠에서 세로 가운데에 놓는다 —
	# 4.5줄이 남는 공간보다 짧으면 위아래로 같은 만큼씩 여백이 생겨야 판이
	# 어느 한쪽에 붙어 보이지 않는다.
	var group_h: float = GRID_PANEL_PAD * 2.0 + TABS_H + BLOCK_GAP + grid_h
	var group_y: float = band_top + maxf(0.0, (band_h - group_h) * 0.5)
	var tabs_y: float = group_y + GRID_PANEL_PAD
	var grid_y: float = tabs_y + TABS_H + BLOCK_GAP

	_lay = {
		"w": w, "h": h, "strip_w": strip_w,
		"cell_w": cell_w, "portrait_w": portrait_w, "portrait_h": portrait_h,
		"mech_h": mech_h, "block_h": block_h, "assign_block_h": assign_block_h,
		"assign_portrait_h": assign_portrait_h,
		"pips_y": TOP_PAD,
		"top_block_y": top_block_y,
		"group_y": group_y, "group_h": group_h,
		"tabs_y": tabs_y,
		"grid_y": grid_y, "grid_h": grid_h, "grid_bottom": grid_y + grid_h,
		"content_w": content_w, "gcell_w": gcell_w, "gcell_h": gcell_h,
		"bot_block_y": bot_block_y,
		"assign_block_y": h - BOT_PAD - assign_block_h,
		"sheet_h": clampf(grid_h - 40.0, 560.0, 700.0),
	}


# ── UI build ─────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_layout()
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = PAGE_BG_COLOR
	_panel.add_theme_stylebox_override("panel", bg)
	_mf.canvas.add_child(_panel)
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 순서 줄이 깔리지 않게. 한 줄만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(_panel)
	# 판을 내리면 위쪽 띠가 비므로 같은 색으로 메운다 — 노치 자리는 비워 둘
	# 곳이 아니라 쓰지 않을 곳이다.
	ScreenMetrics.backfill_top(_panel, PAGE_BG_COLOR)

	_build_pips()
	_build_team_block(_other_side(_player_side), true)
	_build_grid_bg()
	_build_filter_tabs()
	_build_grid()
	_build_team_block(_player_side, false)


## 메크 정사각 초상화. `MechImages.portrait_for` 가 이미 256² 로 구워진 파일을
## 돌려주므로 예전처럼 1024² 전신 아트를 격자 크기로 다시 굽지 않는다 — 그
## 굽는 단계(`_bake_thumbs` / `THUMB_PX`)는 삭제됐다.
func _mech_thumb(mech_id: int) -> Texture2D:
	if not _thumbs.has(mech_id):
		_thumbs[mech_id] = MechImages.portrait_for(mech_id)
	return _thumbs[mech_id] as Texture2D


# ── 순서 표시 줄 ─────────────────────────────────────────────────────────────
func _build_pips() -> void:
	var y: float = _lay["pips_y"]
	var w: float = _lay["w"]
	var pip_w: float = 58.0
	var pip_gap: float = 6.0
	var total: float = float(SEQUENCE.size()) * pip_w + float(SEQUENCE.size() - 1) * pip_gap
	var x0: float = (w - total) * 0.5
	for i in range(SEQUENCE.size()):
		var pip := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.corner_radius_top_left = 3
		sty.corner_radius_top_right = 3
		sty.corner_radius_bottom_left = 3
		sty.corner_radius_bottom_right = 3
		pip.add_theme_stylebox_override("panel", sty)
		pip.position = Vector2(x0 + float(i) * (pip_w + pip_gap), y)
		pip.size = Vector2(pip_w, 12.0)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(pip)
		_seq_pips.append(pip)


# ── 팀 블록 (밴 칩 / 메크 칸 / 파일럿 초상화) ────────────────────────────────
## `is_top` 이면 위에서부터 밴 → 메크 → 파일럿, 아니면 그 반대. 거울 배치라
## **안쪽(전장 쪽)에 언제나 파일럿 얼굴이 오고 바깥쪽에 메크가 온다**.
func _build_team_block(side: int, is_top: bool) -> void:
	var block_y: float = _lay["top_block_y"] if is_top else _lay["bot_block_y"]
	var strip_w: float = _lay["strip_w"]
	var cell_w: float = _lay["cell_w"]
	var pw: float = _lay["portrait_w"]
	var ph: float = _lay["portrait_h"]
	var mh: float = _lay["mech_h"]
	var side_col: Color = BLUE_COLOR if side == GameEnums.DraftSide.BLUE else RED_COLOR

	var holder := Control.new()
	holder.position = Vector2(SIDE_MARGIN, block_y)
	holder.size = Vector2(strip_w, _lay["block_h"])
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(holder)

	var ban_y: float
	var mech_y: float
	var por_y: float
	if is_top:
		ban_y  = 0.0
		mech_y = BAN_ROW_H + BLOCK_INNER_GAP
		por_y  = mech_y + mh + 2.0
	else:
		por_y  = 0.0
		mech_y = ph + 2.0
		ban_y  = mech_y + mh + BLOCK_INNER_GAP

	var chips: Array = _build_ban_row(holder, side, side_col, ban_y, strip_w)

	# ── 메크 칸 ── (파일럿과 짝이 아니라 **픽 순서**다 — 배정은 아래 단계에서)
	var slots: Array = []
	for i in range(SLOT_COUNT):
		var cx: float = cell_w * (float(i) + 0.5)
		slots.append(_build_mech_slot(holder,
				Vector2(cx - pw * 0.5, mech_y), Vector2(pw, mh), side_col, side, i))

	# ── 파일럿 초상화 ── (이름표도 역할 태그도 없다 — 자리가 곧 역할이다)
	var hits: Array = []
	for i in range(SLOT_COUNT):
		var cx2: float = cell_w * (float(i) + 0.5)
		hits.append(_build_pilot_portrait(holder, side, i,
				Vector2(cx2 - pw * 0.5, por_y), Vector2(pw, ph), side_col))

	_side_ui[side] = {"holder": holder, "ban_chips": chips, "mech_slots": slots,
			"pilot_hits": hits}


## 밴 줄 — 팀 이름 + 밴 칩 2개. 블록 바깥쪽 끝에 붙는다.
func _build_ban_row(holder: Control, side: int, side_col: Color,
		ban_y: float, strip_w: float) -> Array:
	var side_label: String = "%s  ·  %s" % [
			("BLUE" if side == GameEnums.DraftSide.BLUE else "RED"),
			String(_team_names.get(side, ""))]
	var side_lbl := UiHelpers.mk_label(holder, side_label, 22, side_col,
			Vector2(0.0, ban_y + 8.0), Vector2(strip_w * 0.5, 28.0))
	side_lbl.clip_text = true
	var ban_lbl := UiHelpers.mk_label(holder, "BAN", 18, TEXT_DIM,
			Vector2(strip_w - 2.0 * (BAN_CHIP + 8.0) - 62.0, ban_y + 12.0),
			Vector2(48.0, 24.0), HORIZONTAL_ALIGNMENT_RIGHT)
	ban_lbl.clip_text = true
	var chips: Array = []
	for i in range(2):
		chips.append(_build_chip(holder,
				Vector2(strip_w - float(2 - i) * (BAN_CHIP + 8.0) + 8.0, ban_y + 3.0),
				BAN_CHIP))
	return chips


## 파일럿 초상화 한 칸. **칸 비율이 크롭을 정한다** — 가로로 납작하면 눈높이
## 밴드(밴픽 단계), 세로로 길면 상체 일러스트(배정 단계)다. 눈높이 밴드를
## 세로로 긴 칸에 넣으면 얼굴만 늘어나고, 상체 크롭을 납작한 칸에 넣으면
## 이목구비가 통째로 잘려 나간다.
##
## 반환값은 그 칸을 덮는 **투명 탭 버튼**이다. 처음에는 숨어 있고 배정 단계에
## 들어갈 때만 켜진다 — 밴픽 중에는 초상화가 "누구를 위해 고르는가"를 말하는
## 그림일 뿐이라 누를 것이 없다.
func _build_pilot_portrait(holder: Control, side: int, seat: int,
		pos: Vector2, sz: Vector2, side_col: Color) -> Button:
	# 초상화 뒤판 — 이미지가 없을 때(INTL 팀 / 단독 실행) 그대로 보이는 폴백.
	var back := ColorRect.new()
	back.position = pos
	back.size = sz
	back.color = Color(0.12, 0.13, 0.19)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(back)

	var p: PlayerData = _pilot_at(side, seat)
	if p != null:
		# **`expand_mode` 를 `texture` 보다 먼저 준다.** 기본 `EXPAND_KEEP_SIZE`
		# 에서는 텍스처 크기가 그대로 최소 크기가 되어, 그 뒤에 준 `size` 가
		# 위로 잡아당겨진다 — 480×200 짜리 eye 크롭이 192×80 칸을 뚫고 나와
		# 아래 줄을 통째로 덮었다(실측).
		var face := TextureRect.new()
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var wide: bool = sz.x > sz.y
		face.texture = PilotImages.eye_for(p.id) if wide else PilotImages.bust_for(p.id)
		face.position = pos
		face.size = sz
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(face)

	var rim := Panel.new()
	rim.position = pos
	rim.size = sz
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim_sb := StyleBoxFlat.new()
	rim_sb.bg_color = Color(0, 0, 0, 0)
	rim_sb.border_color = side_col
	rim_sb.border_width_top = 2
	rim_sb.border_width_bottom = 2
	rim_sb.border_width_left = 2
	rim_sb.border_width_right = 2
	rim.add_theme_stylebox_override("panel", rim_sb)
	holder.add_child(rim)

	var hit := Button.new()
	hit.flat = true
	hit.text = ""
	hit.focus_mode = Control.FOCUS_NONE
	hit.modulate = Color(1, 1, 1, 0)
	hit.position = pos
	hit.size = sz
	hit.visible = false
	hit.pressed.connect(_on_pilot_portrait_pressed.bind(side, seat))
	holder.add_child(hit)
	return hit


## 자리(화면 순서) → 그 팀의 파일럿. 로스터는 역할 0..4 순으로 들어오므로
## `ROLE_DISPLAY_ORDER` 한 겹을 지나 자리를 역할로 바꾼다.
func _pilot_at(side: int, seat: int) -> PlayerData:
	var roster: Array = _rosters.get(side, [])
	if seat < 0 or seat >= GameEnums.ROLE_DISPLAY_ORDER.size():
		return null
	var role: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
	if role < 0 or role >= roster.size():
		return null
	return roster[role] as PlayerData


## 밴 칩 한 칸 — 작은 정사각 초상화 + 붉은 ✕. 비어 있으면 테두리만 남는다.
func _build_chip(parent: Control, pos: Vector2, sz: float) -> Dictionary:
	var frame := Panel.new()
	frame.position = pos
	frame.size = Vector2(sz, sz)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.14, 0.19)
	sb.border_color = Color(0.35, 0.30, 0.32)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	frame.add_theme_stylebox_override("panel", sb)
	parent.add_child(frame)

	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(1.0, 1.0)
	art.size = Vector2(sz - 2.0, sz - 2.0)
	art.modulate = BAN_TINT
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)

	var x_lbl := UiHelpers.mk_label(frame, "", 26, Color(1.0, 0.35, 0.35),
			Vector2(0.0, 0.0), Vector2(sz, sz), HORIZONTAL_ALIGNMENT_CENTER)
	x_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	x_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	x_lbl.add_theme_constant_override("outline_size", 5)
	return {"art": art, "x": x_lbl}


## 메크 칸 한 칸 — 정사각 초상화가 칸을 채우고 아래에 이름 띠 한 줄.
## 배정 단계에서는 이 칸이 **끌 수 있는 물건**이 된다(`_bind_slot_drag`).
func _build_mech_slot(parent: Control, pos: Vector2, sz: Vector2,
		side_col: Color, side: int, seat: int) -> Dictionary:
	var frame := Panel.new()
	frame.position = pos
	frame.size = sz
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.21)
	sb.border_color = side_col.darkened(0.55)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	frame.add_theme_stylebox_override("panel", sb)
	parent.add_child(frame)

	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(2.0, 2.0)
	art.size = Vector2(sz.x - 4.0, sz.y - 4.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(art)

	var band_h: float = 26.0
	var band := ColorRect.new()
	band.position = Vector2(2.0, sz.y - 2.0 - band_h)
	band.size = Vector2(sz.x - 4.0, band_h)
	band.color = Color(0, 0, 0, 0.62)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(band)

	var nm := UiHelpers.mk_label(frame, "", 17, Color(0.92, 0.94, 1.0),
			Vector2(4.0, sz.y - 2.0 - band_h + 2.0), Vector2(sz.x - 8.0, band_h - 2.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	nm.clip_text = true

	# 상대 팀 칸의 탭 버튼. 아군 칸은 드래그 배선(`_bind_slot_drag`)이 탭까지
	# 함께 받으므로 이 버튼을 켜지 않는다 — 켜면 그 버튼이 press 를 가져가
	# 드래그가 시작되지 않는다.
	var hit := Button.new()
	hit.flat = true
	hit.text = ""
	hit.focus_mode = Control.FOCUS_NONE
	hit.modulate = Color(1, 1, 1, 0)
	hit.position = pos
	hit.size = sz
	hit.visible = false
	hit.pressed.connect(_on_mech_slot_tapped.bind(side, seat))
	parent.add_child(hit)

	return {"frame": frame, "art": art, "band": band, "name": nm, "hit": hit,
			"style": sb, "side_col": side_col, "seat": seat}


# ── 픽창 배경판 ──────────────────────────────────────────────────────────────
## 필터 탭과 격자를 함께 덮는 짙은 판. 이 판 하나가 "여기가 고르는 곳"과
## "여기는 양 팀 상황"을 가른다.
func _build_grid_bg() -> void:
	_grid_bg = Panel.new()
	_grid_bg.position = Vector2(SIDE_MARGIN, _lay["group_y"])
	_grid_bg.size = Vector2(_lay["strip_w"], _lay["group_h"])
	_grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = GRID_BG_COLOR
	sb.border_color = Color(0.24, 0.26, 0.34)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	_grid_bg.add_theme_stylebox_override("panel", sb)
	_panel.add_child(_grid_bg)


# ── 역할군 필터 탭 ───────────────────────────────────────────────────────────
## 탭 순서도 화면 순서(탑 · 정글 · 미드 · 원딜 · 서폿)다 — 격자가 그 순서로
## 늘어서 있는데 탭만 열거값 순서면 두 줄이 서로를 가리키지 않는다.
func _filter_tabs() -> Array:
	var out: Array = [[-1, "전체"]]
	for role_raw in GameEnums.ROLE_DISPLAY_ORDER:
		var role: int = int(role_raw)
		out.append([role, String(ROLE_NAMES[role])])
	return out


func _build_filter_tabs() -> void:
	var y: float = _lay["tabs_y"]
	var strip_w: float = _lay["strip_w"] - GRID_PANEL_PAD * 2.0
	var x0: float = SIDE_MARGIN + GRID_PANEL_PAD
	var gap: float = 6.0
	var tabs: Array = _filter_tabs()
	var n: int = tabs.size()
	var bw: float = (strip_w - gap * float(n - 1)) / float(n)
	for i in range(n):
		var role: int = int(tabs[i][0])
		var btn := Button.new()
		btn.text = String(tabs[i][1])
		btn.add_theme_font_size_override("font_size", 20)
		btn.clip_text = true
		btn.position = Vector2(x0 + float(i) * (bw + gap), y)
		btn.size = Vector2(bw, TABS_H)
		btn.set_meta("role", role)
		btn.pressed.connect(_on_filter_pressed.bind(role))
		_panel.add_child(btn)
		_filter_btns.append(btn)


func _on_filter_pressed(role: int) -> void:
	if _filter_role == role:
		return
	_filter_role = role
	_apply_filter()
	_refresh_filter_tabs()


func _refresh_filter_tabs() -> void:
	for btn_raw in _filter_btns:
		var btn := btn_raw as Button
		var on: bool = int(btn.get_meta("role", -99)) == _filter_role
		btn.add_theme_color_override("font_color", ACCENT if on else TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", ACCENT if on else Color(0.86, 0.89, 0.96))
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, _tab_style(on))


func _tab_style(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.19, 0.11) if on else PANEL_COLOR
	sb.border_color = ACCENT if on else Color(0.24, 0.26, 0.34)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	return sb


# ── 메크 격자 ────────────────────────────────────────────────────────────────
func _build_grid() -> void:
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(SIDE_MARGIN + GRID_PANEL_PAD, _lay["grid_y"])
	_scroll.size = Vector2(_lay["strip_w"] - GRID_PANEL_PAD * 2.0, _lay["grid_h"])
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	_panel.add_child(_scroll)

	# 칸을 절대 좌표로 놓으므로 컨테이너가 아니라 맨 Control 이다 — 필터가
	# 바뀔 때 자리를 다시 흘려 놓는 곳이 `_apply_filter()` 한 군데뿐이어야 한다.
	_grid_content = Control.new()
	_grid_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_grid_content)

	for m_raw in _grid_mechs:
		var m := m_raw as MechData
		_cells[m.id] = _build_mech_cell(m)
	_apply_filter()


## 격자 칸 하나 — **정사각 초상화 + 아래 이름 한 줄**이 전부다. 예전에는 그
## 밑에 `HP · ATK · 존재감` 과 패시브 이름이 두 줄 더 붙었는데, 스물한 대를
## 훑는 화면에서 칸마다 다섯 줄을 읽게 하면 정작 **그림으로 알아보는** 일이
## 안 된다. 숫자와 패시브 설명은 한 번 눌러 여는 시트가 통째로 들고 있다.
func _build_mech_cell(m: MechData) -> Dictionary:
	var cw: float = _lay["gcell_w"]
	var ch: float = _lay["gcell_h"]

	var btn := Button.new()
	btn.size = Vector2(cw, ch)
	btn.custom_minimum_size = Vector2(cw, ch)
	btn.clip_contents = true
	# 스크롤 안의 탭 대상은 **PASS** 여야 한다 — 모바일 드래그 스크롤은 터치에서
	# 에뮬레이트된 마우스 press 가 ScrollContainer 까지 올라가야 시작되는데
	# STOP 이 그걸 끊는다. 칸이 격자를 빈틈없이 덮으므로 STOP 이면 손가락을
	# 어디에 대도 격자가 안 움직인다(실측). 탭은 PASS 로도 그대로 동작한다.
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.pressed.connect(_on_mech_pressed.bind(m.id))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, _cell_style(false))
	_grid_content.add_child(btn)

	# 초상화는 칸의 **정사각 부분을 통째로 채운다**(COVERED). 정사각 소스를
	# 정사각 칸에 넣는 것이라 잘려 나가는 것도 늘어나는 것도 없다.
	var pad: float = 4.0
	var art_sz: float = cw - pad * 2.0
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _mech_thumb(m.id)
	art.position = Vector2(pad, pad)
	art.size = Vector2(art_sz, art_sz)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(art)

	_build_role_badge(btn, m.role, Vector2(pad + 4.0, pad + 4.0))

	var nm := UiHelpers.mk_label(btn, m.name, 20, Color(0.95, 0.96, 1.0),
			Vector2(pad, pad + art_sz + 1.0), Vector2(cw - pad * 2.0, CELL_NAME_H - 2.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 상태 슬래브 (밴 / 픽) — 칸 전체를 덮고 그 위에 태그 한 줄.
	var veil := ColorRect.new()
	veil.position = Vector2.ZERO
	veil.size = Vector2(cw, ch)
	veil.color = Color(0, 0, 0, 0)
	veil.visible = false
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(veil)

	var tag := UiHelpers.mk_label(btn, "", 28, Color(1, 1, 1),
			Vector2(0.0, ch * 0.5 - 22.0), Vector2(cw, 44.0), HORIZONTAL_ALIGNMENT_CENTER)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	tag.add_theme_constant_override("outline_size", 6)
	tag.visible = false
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return {"btn": btn, "art": art, "veil": veil, "tag": tag, "mech": m}


## 역할군 배지 — 역할 색으로 채운 둥근 사각형 안에 하얀 두 글자. 글자가 아니라
## **색**이 먼저 읽히는 표시이므로 이름을 통째로 적지 않는다.
func _build_role_badge(parent: Control, role: int, pos: Vector2) -> void:
	if role < 0 or role >= ROLE_INITIALS.size():
		return
	var w: float = 44.0
	var h: float = 30.0
	var badge := Panel.new()
	badge.position = pos
	badge.size = Vector2(w, h)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = (ROLE_COLORS[role] as Color).darkened(0.15)
	sb.border_color = Color(0, 0, 0, 0.55)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	badge.add_theme_stylebox_override("panel", sb)
	parent.add_child(badge)

	var lbl := UiHelpers.mk_label(badge, String(ROLE_INITIALS[role]), 19, Color(1, 1, 1),
			Vector2(0.0, 0.0), Vector2(w, h), HORIZONTAL_ALIGNMENT_CENTER)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _cell_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = ACCENT if selected else Color(0.22, 0.24, 0.32)
	var bw: int = 4 if selected else 2
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.border_width_left = bw
	sb.border_width_right = bw
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb


## 필터를 적용해 격자를 다시 흘려 놓는다. 걸러진 칸은 숨기고 **자리도 비운다** —
## 빈 칸을 남기면 그 역할군에 몇 대가 있는지가 안 읽힌다.
func _apply_filter() -> void:
	var cw: float = _lay["gcell_w"]
	var ch: float = _lay["gcell_h"]
	var idx: int = 0
	for m_raw in _grid_mechs:
		var m := m_raw as MechData
		var btn := (_cells[m.id] as Dictionary)["btn"] as Button
		if _filter_role >= 0 and m.role != _filter_role:
			btn.visible = false
			continue
		btn.visible = true
		var col: int = idx % GRID_COLS
		@warning_ignore("integer_division")
		var row: int = idx / GRID_COLS
		btn.position = Vector2(float(col) * (cw + GRID_GAP), float(row) * (ch + GRID_GAP))
		idx += 1
	var rows: int = int(ceil(float(idx) / float(GRID_COLS)))
	_grid_content.custom_minimum_size = Vector2(_lay["content_w"],
			maxf(0.0, float(rows) * (ch + GRID_GAP) - GRID_GAP))
	_scroll.scroll_vertical = 0


# ── 하단 시트 (선택한 메크의 스탯 · 패시브 · 카드) ───────────────────────────
func _open_sheet(mech_id: int) -> void:
	_close_sheet()
	var m := _find_mech(mech_id)
	if m == null:
		return
	_selected_mech_id = mech_id

	# 딤은 **픽창만** 덮는다 — 위아래 팀 블록은 지금까지의 밴픽 상황이라 시트를
	# 보는 동안에도 보여야 한다(무엇이 이미 나갔는지 모르면 이 기체를 고를지
	# 판단할 수 없다).
	_sheet_dim = ColorRect.new()
	_sheet_dim.position = Vector2(0.0, _lay["group_y"])
	_sheet_dim.size = Vector2(_lay["w"], _lay["group_h"])
	_sheet_dim.color = Color(0.0, 0.0, 0.02, 0.72)
	_sheet_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_dim.gui_input.connect(_on_dim_input)
	_panel.add_child(_sheet_dim)

	var sh: float = _lay["sheet_h"]
	var sw: float = _lay["strip_w"]
	_sheet = Panel.new()
	_sheet.position = Vector2(SIDE_MARGIN, _lay["grid_bottom"] - sh)
	_sheet.size = Vector2(sw, sh)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHEET_COLOR
	sb.border_color = ACCENT.darkened(0.25)
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	_sheet.add_theme_stylebox_override("panel", sb)
	_panel.add_child(_sheet)

	_build_sheet_body(m, sw, sh)


func _build_sheet_body(m: MechData, sw: float, sh: float) -> void:
	# ── 왼쪽: 전신 아트 (원본 — 한 번에 한 대뿐이라 여기서만 1024² 를 쓴다) ──
	var art_h: float = maxf(120.0, sh - SHEET_PAD * 2.0 - SHEET_BTN_H - 16.0)
	var full := MechImages.full_for(m.id)
	if full == null:
		var ph := ColorRect.new()
		ph.position = Vector2(SHEET_PAD, SHEET_PAD)
		ph.size = Vector2(SHEET_ART_W, art_h)
		ph.color = Color(1, 1, 1, 0.06)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sheet.add_child(ph)
	else:
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = full
		art.position = Vector2(SHEET_PAD, SHEET_PAD)
		art.size = Vector2(SHEET_ART_W, art_h)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sheet.add_child(art)

	# ── 오른쪽: 이름 · 스탯 · 패시브 · 카드 ──
	var rx: float = SHEET_PAD + SHEET_ART_W + 24.0
	var rw: float = sw - rx - SHEET_PAD
	var y: float = SHEET_PAD
	var nm := UiHelpers.mk_label(_sheet, m.name, 38, Color(1, 1, 1),
			Vector2(rx, y), Vector2(rw, 48.0))
	nm.clip_text = true
	y += 52.0

	var role_txt: String = String(ROLE_NAMES[m.role]) if m.role >= 0 and m.role < ROLE_NAMES.size() else "—"
	var st := UiHelpers.mk_label(_sheet,
			"%s   ·   HP %d   ·   ATK %d   ·   존재감 %d" % [role_txt, m.hp, m.atk, m.presence],
			24, Color(0.80, 0.85, 0.96), Vector2(rx, y), Vector2(rw, 34.0))
	st.clip_text = true
	y += 42.0

	var pas: Dictionary = _gm.mech_passive_def(m.id)
	if pas.is_empty():
		UiHelpers.mk_label(_sheet, "패시브 없음", 24, Color(0.48, 0.51, 0.62),
				Vector2(rx, y), Vector2(rw, 32.0))
	else:
		var kw: String = String(pas.get("keyword", ""))
		var head: String = "◆ %s" % String(pas["name"])
		if kw != "":
			head += "   [%s]" % kw
		var hl := UiHelpers.mk_label(_sheet, head, 26, ACCENT,
				Vector2(rx, y), Vector2(rw, 34.0))
		hl.clip_text = true
		y += 38.0
		var desc := Label.new()
		desc.text = String(pas.get("description", ""))
		desc.add_theme_font_size_override("font_size", 20)
		desc.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(rx, y)
		desc.size = Vector2(rw, 128.0)
		desc.clip_text = true
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sheet.add_child(desc)

	# ── 카드 셋 ── (오른쪽 칸에서 이어진다 — 왼쪽은 아트 한 장이 통째로 쓴다)
	var cy: float = SHEET_PAD + 250.0
	var defs: Array = _gm.mech_cards_for(m.id)
	UiHelpers.mk_label(_sheet, "메크 카드  %d종" % defs.size(), 22,
			Color(0.78, 0.82, 0.92), Vector2(rx, cy), Vector2(rw, 28.0))
	cy += 32.0
	_build_card_row(defs, cy, rx, rw)

	# ── 버튼 ──
	var by: float = sh - SHEET_PAD - SHEET_BTN_H
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.position = Vector2(sw - SHEET_PAD - 340.0 - 12.0 - 190.0, by)
	close_btn.size = Vector2(190.0, SHEET_BTN_H)
	close_btn.pressed.connect(_close_sheet)
	_sheet.add_child(close_btn)

	_sheet_confirm = Button.new()
	_sheet_confirm.add_theme_font_size_override("font_size", 28)
	_sheet_confirm.position = Vector2(sw - SHEET_PAD - 340.0, by)
	_sheet_confirm.size = Vector2(340.0, SHEET_BTN_H)
	_sheet_confirm.pressed.connect(_on_confirm_pressed)
	_sheet.add_child(_sheet_confirm)
	_refresh_sheet_confirm()


## 메크 카드들을 손패와 **같은 노드**(`Card.tscn`)로 늘어놓는다 — 따로 그린
## 그림이면 실제로 덱에 들어갈 카드와 같은 것인지 확인할 길이 없다.
## `rx` / `rw` 는 오른쪽 칸의 왼쪽 끝과 폭이다 — 시트 전체 폭으로 가운데를
## 잡으면 카드 줄이 왼쪽 아트 위로 밀려 들어간다.
func _build_card_row(defs: Array, y: float, rx: float, rw: float) -> void:
	if defs.is_empty():
		UiHelpers.mk_label(_sheet, "이 기체에는 고유 카드가 없다", 20,
				Color(0.48, 0.51, 0.62), Vector2(rx, y), Vector2(rw, 30.0))
		return
	var cw: float = Card.CARD_W * SHEET_CARD_SCALE
	var chh: float = Card.CARD_H * SHEET_CARD_SCALE
	var row_w: float = float(defs.size()) * cw + float(defs.size() - 1) * SHEET_CARD_GAP
	var x0: float = rx + maxf(0.0, (rw - row_w) * 0.5)
	for i in range(defs.size()):
		var def: Dictionary = defs[i]
		var node := CARD_SCENE.instantiate() as Card
		# add_child 를 setup 보다 **먼저** — Card.gd 의 @onready 참조는 트리에
		# 들어간 뒤에야 풀린다(DraftDetailPanel / CardPileViewer 와 같은 순서).
		_sheet.add_child(node)
		node.setup(CardData.from_def(def), false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = Vector2.ZERO
		node.scale = Vector2(SHEET_CARD_SCALE, SHEET_CARD_SCALE)
		node.position = Vector2(x0 + float(i) * (cw + SHEET_CARD_GAP), y)

		# 장수 배지 — `count = 0` 인 카드는 덱에 처음부터 들어가지 않고 패시브나
		# 다른 카드가 만들어 줄 때만 세상에 나온다. 그 사정을 적어 두지 않으면
		# "왜 이 카드가 손에 안 들어오나"가 화면 어디에도 없다.
		var cnt: int = int(def.get("count", 0))
		var badge := UiHelpers.mk_label(_sheet,
				("×%d" % cnt) if cnt > 0 else "생성 전용",
				18, Color(0.92, 0.94, 1.0) if cnt > 0 else Color(0.62, 0.70, 0.92),
				Vector2(x0 + float(i) * (cw + SHEET_CARD_GAP), y + chh + 2.0),
				Vector2(cw, 24.0), HORIZONTAL_ALIGNMENT_CENTER)
		badge.clip_text = true


## 확정 버튼이 곧 상태 표시다 — 예전의 "BLUE 픽 — 내 차례 (3 / 14)" 한 줄이
## 사라진 지금, 지금이 밴 차례인지 픽 차례인지를 글자로 말하는 자리는 여기뿐이다.
func _refresh_sheet_confirm() -> void:
	if _sheet_confirm == null:
		return
	var ok: bool = _is_player_turn() and _is_legal(_selected_mech_id)
	_sheet_confirm.disabled = not ok
	if ok:
		_sheet_confirm.text = "밴 확정" if _current_kind() == ACTION_BAN else "픽 확정"
	elif not _is_player_turn():
		_sheet_confirm.text = "상대 차례"
	else:
		_sheet_confirm.text = "선택 불가"


func _on_dim_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_sheet()


func _close_sheet() -> void:
	_selected_mech_id = -1
	_sheet_confirm = null
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null
	if _sheet_dim != null:
		_sheet_dim.queue_free()
		_sheet_dim = null
	_refresh_cell_selection()


func _on_confirm_pressed() -> void:
	var id: int = _selected_mech_id
	if id < 0 or not _is_player_turn() or not _is_legal(id):
		return
	_close_sheet()
	_commit_action(id)


# ── State refresh ────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	for i in range(_seq_pips.size()):
		var pip := _seq_pips[i] as Panel
		var sty := pip.get_theme_stylebox("panel") as StyleBoxFlat
		sty.bg_color = _seq_color(i, 1 if i < _action_idx else (2 if i == _action_idx else 0))

	if not _assign_mode:
		_refresh_grid_cells()
		_refresh_cell_selection()
		_refresh_filter_tabs()
	_refresh_side_block(GameEnums.DraftSide.BLUE)
	_refresh_side_block(GameEnums.DraftSide.RED)
	_refresh_sheet_confirm()


func _refresh_grid_cells() -> void:
	var blue_picks: Array = _picks_of(GameEnums.DraftSide.BLUE)
	var red_picks: Array  = _picks_of(GameEnums.DraftSide.RED)
	for id in _cells.keys():
		var cell: Dictionary = _cells[id]
		var veil := cell["veil"] as ColorRect
		var tag := cell["tag"] as Label
		var art := cell["art"] as TextureRect
		var mid: int = int(id)
		if mid in _banned:
			veil.visible = true
			veil.color = Color(0.0, 0.0, 0.0, 0.62)
			tag.visible = true
			tag.text = "BAN"
			tag.add_theme_color_override("font_color", Color(1.0, 0.45, 0.42))
			art.modulate = BAN_TINT
		elif mid in blue_picks:
			veil.visible = true
			veil.color = Color(0.10, 0.24, 0.52, 0.62)
			tag.visible = true
			tag.text = "BLUE"
			tag.add_theme_color_override("font_color", BLUE_COLOR)
			art.modulate = Color(0.74, 0.80, 0.94)
		elif mid in red_picks:
			veil.visible = true
			veil.color = Color(0.46, 0.12, 0.12, 0.62)
			tag.visible = true
			tag.text = "RED"
			tag.add_theme_color_override("font_color", RED_COLOR)
			art.modulate = Color(0.94, 0.78, 0.76)
		else:
			veil.visible = false
			tag.visible = false
			art.modulate = Color(1, 1, 1)


func _refresh_cell_selection() -> void:
	for id in _cells.keys():
		var btn := (_cells[id] as Dictionary)["btn"] as Button
		var on: bool = int(id) == _selected_mech_id
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(st, _cell_style(on))


func _refresh_side_block(side: int) -> void:
	var ui: Dictionary = _side_ui.get(side, {})
	if ui.is_empty():
		return
	var bans: Array = _side_bans.get(side, [])
	var chips: Array = ui["ban_chips"]
	for i in range(chips.size()):
		var chip: Dictionary = chips[i]
		var art := chip["art"] as TextureRect
		var x_lbl := chip["x"] as Label
		if i < bans.size():
			art.texture = _mech_thumb(int(bans[i]))
			x_lbl.text = "✕"
		else:
			art.texture = null
			x_lbl.text = ""

	# 배정 단계의 아군 블록만 `_assign_order` 를 읽는다 — 그때부터 칸의 뜻이
	# "픽 순서"에서 "이 파일럿의 기체"로 바뀌기 때문이다.
	var ids: Array = _side_picks.get(side, [])
	if _assign_mode and side == _player_side:
		ids = _assign_order
	var slots: Array = ui["mech_slots"]
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var sty := slot["style"] as StyleBoxFlat
		var side_col: Color = slot["side_col"]
		var nm := slot["name"] as Label
		var band := slot["band"] as ColorRect
		if i < ids.size() and int(ids[i]) >= 0:
			var mid: int = int(ids[i])
			var m := _find_mech(mid)
			(slot["art"] as TextureRect).texture = _mech_thumb(mid)
			nm.text = m.name if m != null else "?"
			band.visible = true
			sty.bg_color = side_col.darkened(0.72)
			sty.border_color = side_col
		else:
			(slot["art"] as TextureRect).texture = null
			nm.text = ""
			band.visible = false
			sty.bg_color = Color(0.13, 0.14, 0.21)
			sty.border_color = side_col.darkened(0.55)


func _seq_color(idx: int, state: int) -> Color:
	# state: 0=upcoming, 1=done, 2=current
	var side: int = SEQUENCE[idx][0]
	var base: Color = BLUE_COLOR if side == GameEnums.DraftSide.BLUE else RED_COLOR
	if state == 1: return base.darkened(0.45)
	if state == 2: return base.lightened(0.20)
	return base.darkened(0.75)


# ── Click handling ───────────────────────────────────────────────────────────
## 1탭 = 선택(시트 열기), **같은 메크 2탭 = 확정**. 시트는 상대 차례에도 열린다 —
## 다음 수를 들여다보는 것이 밴픽 화면이 하는 일의 절반이다.
func _on_mech_pressed(mech_id: int) -> void:
	if _selected_mech_id == mech_id:
		if _is_player_turn() and _is_legal(mech_id):
			_close_sheet()
			_commit_action(mech_id)
		return
	_open_sheet(mech_id)
	_refresh_cell_selection()


func _is_player_turn() -> bool:
	if _action_idx >= SEQUENCE.size(): return false
	return SEQUENCE[_action_idx][0] == _player_side


func _current_kind() -> int:
	if _action_idx >= SEQUENCE.size(): return ACTION_PICK
	return int(SEQUENCE[_action_idx][1])


func _is_legal(mech_id: int) -> bool:
	if mech_id < 0:
		return false
	return not (mech_id in _banned) \
		and not (mech_id in _picks_of(GameEnums.DraftSide.BLUE)) \
		and not (mech_id in _picks_of(GameEnums.DraftSide.RED))


func _picks_of(side: int) -> Array:
	return _side_picks.get(side, [])


func _other_side(side: int) -> int:
	return GameEnums.DraftSide.RED if side == GameEnums.DraftSide.BLUE else GameEnums.DraftSide.BLUE


func _commit_action(mech_id: int) -> void:
	var cur: Array = SEQUENCE[_action_idx]
	var side: int = int(cur[0])
	if cur[1] == ACTION_BAN:
		_banned.append(int(mech_id))
		(_side_bans[side] as Array).append(int(mech_id))
	else:
		(_side_picks[side] as Array).append(int(mech_id))
	_action_idx += 1
	_refresh_ui()
	if _action_idx >= SEQUENCE.size():
		_enter_assign_mode()
	else:
		_maybe_run_ai()


func _maybe_run_ai() -> void:
	if _action_idx >= SEQUENCE.size():
		return
	if _is_player_turn():
		return
	# AI turn — pick a random legal mech after a short delay
	await get_tree().create_timer(_AI_THINK_SEC).timeout
	if _action_idx >= SEQUENCE.size() or _panel == null:
		return
	var legal: Array = []
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if _is_legal(m.id): legal.append(m)
	if legal.is_empty():
		push_error("BanPickController: no legal mechs left for AI")
		return
	var pick := legal[randi() % legal.size()] as MechData
	_commit_action(pick.id)


# ── 배정 단계 ────────────────────────────────────────────────────────────────
## 픽창을 걷어 내고 아군 블록을 **배정판**으로 다시 세운다. 화면이 바뀌지 않는
## 것이 요점이다 — 방금 고른 열 대가 그 자리에 그대로 있어야 "누가 뭘 탈지"를
## 그 그림 위에서 정할 수 있다.
func _enter_assign_mode() -> void:
	_assign_mode = true
	_close_sheet()
	_assign_order = (_picks_of(_player_side) as Array).duplicate()

	# 상대 팀은 자동 배정(섞기) — 플레이어가 관리하지 않는 팀이다.
	var enemy_side: int = _other_side(_player_side)
	var e_roster: Array = _rosters.get(enemy_side, [])
	var shuffled: Array = (_picks_of(enemy_side) as Array).duplicate()
	shuffled.shuffle()
	for i in range(min(SLOT_COUNT, e_roster.size(), shuffled.size())):
		(e_roster[i] as PlayerData).assigned_mech = _find_mech(int(shuffled[i]))

	# 픽창 해체
	if _scroll != null:
		_scroll.queue_free()
		_scroll = null
	_grid_content = null
	if _grid_bg != null:
		_grid_bg.queue_free()
		_grid_bg = null
	for btn_raw in _filter_btns:
		(btn_raw as Button).queue_free()
	_filter_btns.clear()
	_cells.clear()

	# 상대 블록은 다시 세우지 않고 **탭만 열어 준다** — 밴픽 내내 서 있던
	# 그림이 그대로 남아야 "저쪽이 무엇을 골랐나"를 두 번 읽지 않는다.
	_set_block_tappable(enemy_side, true)

	_rebuild_player_block_for_assign()
	_build_assign_prompt()
	_refresh_ui()


## 한 팀 블록의 초상화 · 메크 칸 탭을 켜고 끈다. 아군 메크 칸만은 예외로
## 남는다 — 그쪽 탭은 드래그 배선(`_on_slot_input`)이 함께 받으므로 투명
## 버튼을 켜면 그 버튼이 press 를 가져가 드래그가 영영 시작되지 않는다.
func _set_block_tappable(side: int, on: bool) -> void:
	var ui: Dictionary = _side_ui.get(side, {})
	if ui.is_empty():
		return
	for raw in ui.get("pilot_hits", []):
		var b := raw as Button
		if b != null:
			b.visible = on
	if side == _player_side:
		return
	for slot_raw in ui.get("mech_slots", []):
		var hit := (slot_raw as Dictionary).get("hit", null) as Button
		if hit != null:
			hit.visible = on


## 아군 블록을 다시 세운다 — **파일럿 상체 일러스트가 위, 메크 칸이 그 아래**,
## 메크 줄 오른쪽 아래에 조작 안내 한 줄, 맨 밑에 밴 칩. 메크 칸은 끌 수 있는
## 물건이 된다.
##
## 예전에는 메크가 위였다 — 끄는 손가락이 그 밑의 "어느 파일럿 자리인가"를
## 가리지 않게 하려는 배치였는데, 그러면 세로로 훑을 때 목적어가 주어보다
## 먼저 와서 다섯 칸이 무엇을 정하는 화면인지가 뒤집혀 읽혔다. 초상화가
## 상체 일러스트로 커진 지금은 손가락이 덮을 수 있는 넓이보다 칸이 훨씬 커서
## 그 걱정 자체가 없다.
func _rebuild_player_block_for_assign() -> void:
	var old: Dictionary = _side_ui.get(_player_side, {})
	if not old.is_empty() and old["holder"] != null:
		(old["holder"] as Control).queue_free()

	var strip_w: float = _lay["strip_w"]
	var cell_w: float = _lay["cell_w"]
	var pw: float = _lay["portrait_w"]
	var ph: float = _lay["assign_portrait_h"]
	var mh: float = _lay["mech_h"]
	var side_col: Color = BLUE_COLOR if _player_side == GameEnums.DraftSide.BLUE else RED_COLOR

	var holder := Control.new()
	holder.position = Vector2(SIDE_MARGIN, _lay["assign_block_y"])
	holder.size = Vector2(strip_w, _lay["assign_block_h"])
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(holder)

	var por_y: float = 0.0
	var mech_y: float = ph + 2.0
	var hint_y: float = mech_y + mh + 2.0
	var ban_y: float = hint_y + ASSIGN_HINT_H + BLOCK_INNER_GAP

	var chips: Array = _build_ban_row(holder, _player_side, side_col, ban_y, strip_w)

	var hits: Array = []
	for i in range(SLOT_COUNT):
		var cx2: float = cell_w * (float(i) + 0.5)
		hits.append(_build_pilot_portrait(holder, _player_side, i,
				Vector2(cx2 - pw * 0.5, por_y), Vector2(pw, ph), side_col))

	var slots: Array = []
	for i in range(SLOT_COUNT):
		var cx: float = cell_w * (float(i) + 0.5)
		var slot: Dictionary = _build_mech_slot(holder,
				Vector2(cx - pw * 0.5, mech_y), Vector2(pw, mh), side_col,
				_player_side, i)
		_bind_slot_drag(slot)
		slots.append(slot)

	# 조작 안내는 **메크 줄 오른쪽 아래에 작게** 붙는다 — 한 번 읽고 나면
	# 다시 볼 일이 없는 문장이라 화면 가운데를 차지하면 안 된다.
	var hint := UiHelpers.mk_label(holder, ASSIGN_HINT_TEXT, ASSIGN_HINT_FONT,
			TEXT_DIM, Vector2(0.0, hint_y), Vector2(strip_w, ASSIGN_HINT_H),
			HORIZONTAL_ALIGNMENT_RIGHT)
	hint.clip_text = true

	_side_ui[_player_side] = {"holder": holder, "ban_chips": chips,
			"mech_slots": slots, "pilot_hits": hits}
	_set_block_tappable(_player_side, true)


## 픽창이 있던 자리에 "게임 시작" 버튼 하나를 세운다. 안내 문구는 아군 메크 줄
## 오른쪽 아래로 내려갔고 제목("메크 배정")은 삭제됐다 — 화면에 남은 것이
## 양 팀 초상화와 그 밑의 기체뿐이면 무엇을 하는 단계인지는 그림이 말한다.
func _build_assign_prompt() -> void:
	var w: float = _lay["w"]
	var btn := Button.new()
	btn.text = "게임 시작"
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 34)
	btn.size = Vector2(START_BTN_W, START_BTN_H)
	# 가운데 띠의 **아래쪽**에 매단다 — 배정판(아군 블록) 바로 위라, 칸을
	# 다 옮긴 손이 그대로 내려가 닿는 자리다.
	btn.position = Vector2((w - START_BTN_W) * 0.5,
			float(_lay["assign_block_y"]) - BLOCK_GAP - START_BTN_H)
	btn.pressed.connect(_finish)
	_panel.add_child(btn)


# ── 배정 단계의 상세 팝업 ────────────────────────────────────────────────────
func _on_pilot_portrait_pressed(side: int, seat: int) -> void:
	if not _assign_mode:
		return
	var p: PlayerData = _pilot_at(side, seat)
	if p == null:
		return
	if _pilot_detail == null:
		_pilot_detail = DraftDetailPanel.new()
		add_child(_pilot_detail)
	_close_detail_panels()
	_pilot_detail.open(p)


func _on_mech_slot_tapped(side: int, seat: int) -> void:
	if not _assign_mode:
		return
	var ids: Array = _assign_order if side == _player_side else _picks_of(side)
	if seat < 0 or seat >= ids.size():
		return
	_open_mech_detail(int(ids[seat]))


func _open_mech_detail(mech_id: int) -> void:
	var m := _find_mech(mech_id)
	if m == null:
		return
	if _mech_detail == null:
		_mech_detail = MechDetailPanel.new()
		add_child(_mech_detail)
	_close_detail_panels()
	_mech_detail.open(m)


## 두 팝업은 **동시에 뜨지 않는다** — 파일럿과 메크를 한 화면에 겹치지 않는
## 것이 이 단계의 규칙이고, 딤이 두 겹 쌓이면 뒤엣것이 앞엣것을 어둡게 덮는다.
func _close_detail_panels() -> void:
	if _pilot_detail != null:
		_pilot_detail.close()
	if _mech_detail != null:
		_mech_detail.close()


## 메크 칸 하나를 끌 수 있게 만든다. 누른 컨트롤이 마우스 포커스를 유지하므로
## 커서가 칸 밖으로 나가도 motion / release 가 계속 이 칸으로 들어온다 —
## 그래서 드래그 레이어를 따로 두지 않는다.
func _bind_slot_drag(slot: Dictionary) -> void:
	var frame := slot["frame"] as Panel
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(_on_slot_input.bind(int(slot["seat"])))


func _on_slot_input(ev: InputEvent, seat: int) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if _mech_at_seat(seat) < 0:
				return
			_drag_armed = true
			_drag_seat = seat
			_drag_from = _panel.get_local_mouse_position()
		else:
			_end_drag()
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _drag_armed:
		var here: Vector2 = _panel.get_local_mouse_position()
		if _drag_ghost == null:
			# 문턱을 넘기 전까지는 탭이지 드래그가 아니다 — 손가락은 언제나
			# 조금씩 떨리므로, 문턱이 없으면 누르기만 해도 칸이 떠오른다.
			if here.distance_to(_drag_from) < DRAG_THRESHOLD_PX:
				return
			_begin_drag_ghost()
		_drag_ghost.position = here - _drag_ghost.size * 0.5
		_highlight_drop_target(here)


func _begin_drag_ghost() -> void:
	var mid: int = _mech_at_seat(_drag_seat)
	if mid < 0:
		return
	var pw: float = _lay["portrait_w"]
	var mh: float = _lay["mech_h"]
	var ghost := Panel.new()
	ghost.size = Vector2(pw, mh)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.21)
	sb.border_color = ACCENT
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.corner_radius_top_left = 5
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	ghost.add_theme_stylebox_override("panel", sb)
	ghost.modulate = Color(1, 1, 1, 0.9)
	_panel.add_child(ghost)

	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = _mech_thumb(mid)
	art.position = Vector2(3.0, 3.0)
	art.size = Vector2(pw - 6.0, mh - 6.0)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.add_child(art)

	_drag_ghost = ghost
	# 끌려 나온 칸은 그 자리에 **자국으로 남는다** — 비워 버리면 어디서 끌어
	# 왔는지가 사라져, 엉뚱한 곳에 놓고도 무엇과 바뀌었는지를 못 읽는다.
	var slot: Dictionary = _slot_at(_drag_seat)
	if not slot.is_empty():
		(slot["frame"] as Panel).modulate = Color(1, 1, 1, 0.35)


## 지금 커서가 놓인 칸의 테두리를 밝힌다. 놓을 수 있는 자리가 어디인지는
## 끌고 있는 동안에만 물어보는 질문이라 상태로 남기지 않는다.
func _highlight_drop_target(here: Vector2) -> void:
	var target: int = _seat_under(here)
	for slot_raw in _player_slots():
		var slot: Dictionary = slot_raw
		var seat: int = int(slot["seat"])
		if seat == _drag_seat:
			continue
		var sty := slot["style"] as StyleBoxFlat
		var side_col: Color = slot["side_col"]
		var filled: bool = _mech_at_seat(seat) >= 0
		sty.border_color = ACCENT if seat == target else \
				(side_col if filled else side_col.darkened(0.55))
		sty.border_width_top = 4 if seat == target else 2
		sty.border_width_bottom = sty.border_width_top
		sty.border_width_left = sty.border_width_top
		sty.border_width_right = sty.border_width_top


func _end_drag() -> void:
	var from_seat: int = _drag_seat
	var dragging: bool = _drag_ghost != null
	# 문턱을 못 넘긴 것은 드래그가 아니라 **탭**이고, 탭은 그 칸의 메크 상세를
	# 연다 — 아군 메크 칸에는 투명 탭 버튼을 얹을 수 없어서(드래그의 press 를
	# 가로챈다) 그 몫이 여기로 온다.
	if not dragging and _drag_armed and from_seat >= 0:
		_drag_armed = false
		_drag_seat = -1
		_on_mech_slot_tapped(_player_side, from_seat)
		return
	if _drag_ghost != null:
		var here: Vector2 = _panel.get_local_mouse_position()
		var to_seat: int = _seat_under(here)
		_drag_ghost.queue_free()
		_drag_ghost = null
		if to_seat >= 0 and to_seat != from_seat:
			_swap_assign(from_seat, to_seat)
	_drag_armed = false
	_drag_seat = -1
	if dragging:
		var slot: Dictionary = _slot_at(from_seat)
		if not slot.is_empty():
			(slot["frame"] as Panel).modulate = Color(1, 1, 1, 1)
	_refresh_side_block(_player_side)
	_reset_slot_borders()


func _reset_slot_borders() -> void:
	for slot_raw in _player_slots():
		var slot: Dictionary = slot_raw
		var sty := slot["style"] as StyleBoxFlat
		sty.border_width_top = 2
		sty.border_width_bottom = 2
		sty.border_width_left = 2
		sty.border_width_right = 2


func _swap_assign(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= _assign_order.size() or b >= _assign_order.size():
		return
	var tmp = _assign_order[a]
	_assign_order[a] = _assign_order[b]
	_assign_order[b] = tmp


## `_panel` 좌표 하나가 어느 메크 칸 위인가. 칸은 아군 블록(holder) 안의 자식
## 이므로 홀더 위치를 더해 절대 사각형으로 판정한다.
func _seat_under(here: Vector2) -> int:
	var ui: Dictionary = _side_ui.get(_player_side, {})
	if ui.is_empty():
		return -1
	var holder := ui["holder"] as Control
	for slot_raw in _player_slots():
		var slot: Dictionary = slot_raw
		var frame := slot["frame"] as Panel
		var rect := Rect2(holder.position + frame.position, frame.size)
		if rect.has_point(here):
			return int(slot["seat"])
	return -1


func _player_slots() -> Array:
	var ui: Dictionary = _side_ui.get(_player_side, {})
	return ui.get("mech_slots", []) if not ui.is_empty() else []


func _slot_at(seat: int) -> Dictionary:
	for slot_raw in _player_slots():
		var slot: Dictionary = slot_raw
		if int(slot["seat"]) == seat:
			return slot
	return {}


func _mech_at_seat(seat: int) -> int:
	if seat < 0 or seat >= _assign_order.size():
		return -1
	return int(_assign_order[seat])


# ── 종료 ─────────────────────────────────────────────────────────────────────
## 배정을 로스터에 새기고 화면을 걷는다. `PlayerData.assigned_mech` 를 직접
## 채우는 것은 예전 `AssignController` 가 하던 일이고, 그 파일이 사라진 지금
## 그 책임이 여기로 왔다. 자리(seat) → 역할 변환은 `ROLE_DISPLAY_ORDER` 한 겹
## 뿐이고, **로스터 자체는 역할 0..4 순서를 그대로 지킨다** — MatchFlow 의
## 재개 스냅샷(`_roster_mech_ids`)이 그 순서를 전제한다.
func _finish() -> void:
	var p_roster: Array = _rosters.get(_player_side, [])
	for seat in range(min(SLOT_COUNT, _assign_order.size())):
		var role: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		if role < 0 or role >= p_roster.size():
			continue
		(p_roster[role] as PlayerData).assigned_mech = _find_mech(int(_assign_order[seat]))

	var player_picks: Array = (_picks_of(_player_side) as Array).duplicate()
	var enemy_picks: Array  = (_picks_of(_other_side(_player_side)) as Array).duplicate()
	_close_sheet()
	# 팝업은 CanvasLayer 라 `_panel` 을 지워도 따라 사라지지 않는다 — 열어 둔
	# 채 넘어가면 딤이 BattleSim 위에 그대로 남는다.
	_close_detail_panels()
	_panel.queue_free()
	_panel = null
	_cells.clear()
	_side_ui.clear()
	_seq_pips.clear()
	_filter_btns.clear()
	_thumbs.clear()
	_scroll = null
	_grid_content = null
	_grid_bg = null
	phase_finished.emit({
		"banned": _banned.duplicate(),
		"player_picks": player_picks,
		"enemy_picks": enemy_picks,
		"player_roster": p_roster,
		"enemy_roster": _rosters.get(_other_side(_player_side), []),
	})


# ── Helpers ──────────────────────────────────────────────────────────────────
func _find_mech(id: int) -> MechData:
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if m.id == id: return m
	return null
