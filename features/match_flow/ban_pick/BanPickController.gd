extends Node

# LoL international ban/pick: B-B-P-PP-PP-P-B-B-PP-PP
# Each side ends with 2 bans + 5 picks. Sides alternate per token.
# 상대(AI)는 그 상황에 고를 만한 후보를 점수로 늘어놓고(`_ai_rank`) 0~2대를
# 집어 보았다가 한 대를 확정한다(`_maybe_run_ai`).
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
# **화면은 아웃게임 흰 배경 계통이다**(`OutgameTheme`). 바탕은 옅은 회색(`BG`)이고
# 픽창만 그림자 진 흰 카드 한 장이라, 판 하나가 "여기가 고르는 곳"과 "여기는 양
# 팀 상황"을 가른다. 픽창 맨 위(역할군 필터 바로 위)에 열네 수의 **순서 줄**이
# 서고, 수가 넘어갈 때마다 화면 가운데로 **차례 배너**(`내 차례 밴` …)가 지나간다.
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
# **아군 메크 칸은 밴픽 중에도 끌어 다른 선수 자리로 옮길 수 있다** — 칸의 내용은
# 픽 순서가 아니라 자리표(`_seat_mechs`)이고 새 픽은 첫 빈 자리에 앉는다.
#
# 14수가 끝나면 **화면을 갈아타지 않는다** — 픽창이 사라지고 하단 구간에 "게임
# 시작" 바가 서며, 아래 아군 블록이 배정판으로 다시 선 뒤 두 팀 블록이 화면
# 가운데로 모이고 상대 메크가 포지션에 맞는 자리로 옮겨 앉는다
# (`_play_assign_intro`):
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

#
# ── 씬 (`UI_View_BanPickView.tscn`) ──────────────────────────────────────────────────
# **화면의 배치 · 스타일은 씬이 정본이다** — `BanPickView`(화면 한 장) 와 아이템 씬
# `BanPickMechCell`(격자 칸) · `BanPickMechSlot`(메크 칸) · `BanPickPortrait`(파일럿
# 초상화) · `BanPickBanChip`(밴 칩) · `BanPickSheetCard`(시트 카드 한 장), 순서 줄
# 위젯 `BanPickOrderRow`. 이 스크립트는 **규칙(순서 · 합법성 · AI · 배정)과 상태**를
# 들고, 씬 노드에 데이터를 채우고 상태가 바뀔 때 다시 칠한다. 진영색 · 역할색 ·
# 숙련 단계색 같은 데이터 색만 코드가 입힌다.

signal phase_finished(result: Dictionary)

const CARD_SCENE := preload("res://scenes/Card.tscn")


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

# 하단 시트 — 배치는 씬(`%Sheet`)이고, 카드 설명판만 코드가 띄운다.
const SHEET_CARD_SCALE: float = 0.9
## 설명판 윗끝의 하한(시트 안쪽 여백 = 씬의 `SheetName` 윗여백).
const SHEET_PAD: float        = 20.0
const SHEET_DESC_GAP: float   = 8.0
## 시트 패시브 아이콘 타일(36px)의 그림자 — 큰 타일의 14px 를 크기에 맞춰 줄인 값.
const SHEET_PASSIVE_SHADOW_PX: float = 6.0

## 배정 단계에서 메크 칸을 끌기 시작하는 문턱(px). 이보다 덜 움직인 것은 탭이지
## 드래그가 아니다 — 손가락은 언제나 조금씩 떨린다. 문턱을 못 넘긴 탭은
## 그 칸의 메크 상세를 연다.
const DRAG_THRESHOLD_PX: float = 8.0

## 배정 단계 진입 연출 — 두 팀 블록이 화면 가운데로 모이고(`GATHER_SEC`), 그
## 다음 상대 메크 칸들이 포지션에 맞는 선수 자리로 옮겨 앉는다(`ENEMY_SWAP_SEC`).
## 모인 두 블록 사이 간격이 `GATHER_GAP` 이다.
const GATHER_SEC: float = 0.42
const GATHER_GAP: float = 36.0
const ENEMY_SWAP_DELAY: float = 0.18
const ENEMY_SWAP_SEC: float = 0.48
## 옮겨 앉는 칸이 다른 칸을 가로지를 때 위로 살짝 떠오르는 높이.
const ENEMY_SWAP_LIFT_PX: float = 22.0

# ── 색 ── **아웃게임 흰 배경 계통**(`OutgameTheme`)이다. 바탕 · 카드 · 글자색은 씬의
# 테마(`OutgameTheme.tres`)가 입히고, 여기 남은 것은 상태 · 데이터에 따라 바뀌는 색이다.
const SLOT_EMPTY_COLOR := OutgameTheme.SURFACE_SUNK
## 진영색 — 흰 바탕에서 읽히도록 인게임 쪽보다 한 단계 짙다.
const BLUE_COLOR  := Color(0.20, 0.45, 0.92)
const RED_COLOR   := Color(0.88, 0.27, 0.27)
const BAN_TINT    := Color(0.42, 0.42, 0.46, 1.0)
const ACCENT      := OutgameTheme.ACCENT

# ── 상대의 만지작거리기 ── 상대는 곧장 고르지 않는다. 그 상황에 실제로 고를
# 만한 후보(`_ai_rank`) 중 0~2대를 차례로 **집어 보았다가** 마지막 한 대를
# 확정한다. 한 번 집어 보는 시간은 `AI_HOVER_MIN..MAX` 사이 무작위.
const AI_HOVER_MIN: float = 0.3
const AI_HOVER_MAX: float = 0.8
const AI_HOVER_MAX_COUNT: int = 2
## 집어 볼 후보를 고르는 상위 몇 대.
const AI_CONSIDER_TOP: int = 5

## Mastery tier a pilot needs to get a badge on a grid cell (2 = 능숙).
const ADEPT_TIER: int = 2
## Enemy badges per cell at most.
const ENEMY_DOTS_MAX: int = 2

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

# ── Mech mastery (M4) / analysis markers (M5 decision) ──────────────────────
# All empty / false when MatchFlow runs standalone (no active season), so the
# screen and the AI behave exactly as before.
var _mastery_on: bool = false
## Quirks (§14, T1) — on in a season run (`QuirkSystem.is_enabled`). My pilots only.
var _quirk_on: bool = false
## Analysis reveals the enemy's likely picks (`StaffSystem.analysis_tier >= 2`).
var _show_enemy_likely: bool = false
## mech_id(int) → {"pilot": String, "value": int} — each enemy pilot's top mech (sheet line).
var _enemy_likely: Dictionary = {}
## Grid cell pilot badges (mastery tier >= `ADEPT_TIER`, fixed for the whole draft):
## mech_id(int) → my pilot ids in seat order (≤ 5) / enemy pilot ids best first (≤ 2,
## only while `_show_enemy_likely`).
var _my_adept: Dictionary = {}
var _enemy_adept: Dictionary = {}
## The enemy's mech slots are re-seated by pilot (assign step) — only then does
## a seat's mastery label describe the right pilot.
var _enemy_seated: bool = false

## 배정 단계인가. true 면 격자가 사라지고 아군 블록이 드래그 가능한 배정판이 된다.
var _assign_mode: bool = false
## side → 자리(seat, 화면 순서 0..4) → mech_id (-1 = 빈 자리). **밴픽 중에도
## 이 표가 메크 칸의 내용이다** — 픽은 왼쪽부터 첫 빈 자리에 앉고, 아군은 그 칸을
## 끌어 다른 선수 자리로 옮길 수 있다(빈 자리로 옮기면 이동, 찬 자리면 맞바꿈).
## 상대는 밴픽 동안 픽 순서 그대로 앉아 있다가 배정 단계에서 포지션에 맞게 다시
## 앉는다(`_enemy_role_order`).
var _seat_mechs: Dictionary = {}
## 배정 진입 연출이 도는 동안 "게임 시작"을 잠근다 — 상대 재배치가 끝나기 전에
## 넘어가면 화면에서 본 배정과 실제 배정이 갈린다.
var _start_btn: Button = null

# ── UI ───────────────────────────────────────────────────────────────────────
## 화면 한 장(`UI_View_BanPickView.tscn`). null = 화면이 걷혔다 — AI 대기 / 연출 코루틴이
## 깨어났을 때 이것으로 손을 뗄지 판단한다.
var _view: BanPickView = null
## 미리보기 전용(`BanPickView._fill_preview`, F6 단독 실행) — 채워 두면 `_build_ui` 가 새
## 화면을 만들지 않고 이 화면을 채운다(MatchFlow 가 없으니 `_mf.canvas` 도 없다).
## 실제 흐름에서는 늘 null.
var preview_view: BanPickView = null
## 상대가 지금 집어 보고 있는 기체(-1 = 없음). 격자 칸 테두리와 상대 팀의 다음
## 칸(픽 슬롯 / 밴 칩)에 흐린 미리보기로 나타난다.
var _ai_hover_id: int = -1
# 시트의 카드 설명판 — 시트 카드를 누르면 그 카드 줄 위에 뜬다.
var _sheet_desc: Panel = null
var _sheet_desc_idx: int = -1
var _cells: Dictionary = {}        # mech_id(int) → BanPickMechCell
var _side_ui: Dictionary = {}      # side(int) → BanPickTeamBlock
var _filter_role: int = -1
var _thumbs: Dictionary = {}       # mech_id(int) → Texture2D (lazy)

# 하단 시트
var _sheet_open: bool = false
var _selected_mech_id: int = -1

# 배정 단계의 상세 팝업 — 파일럿은 드래프트 화면과 **같은 팝업**을 쓴다
# (`DraftDetailPanel` 은 `PlayerData` 한 장과 오토로드만 있으면 열린다).
# 둘 다 lazy-add: 배정 단계에 들어가기 전에는 열릴 일이 없다.
var _pilot_detail: DraftDetailPanel = null
var _mech_detail: MechDetailPanel = null

# 배정 단계의 드래그 상태 — 위치는 전부 **캔버스(전역) 좌표**다.
var _drag_seat: int = -1
var _drag_armed: bool = false      # 눌렀지만 아직 문턱을 못 넘었다
var _drag_from: Vector2 = Vector2.ZERO
var _dragging: bool = false        # 문턱을 넘어 `%DragGhost` 가 손에 들렸다


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
		player_side: (player_team_name if player_team_name != "" else Loc.t(L.TERM_SIDE_ALLY)),
		enemy_side:  (enemy_team_name  if enemy_team_name  != "" else Loc.t(L.MATCH_BAN_PICK_FALLBACK_ENEMY)),
	}
	_selected_mech_id = -1
	_filter_role = -1
	_assign_mode = false
	_seat_mechs = {player_side: _empty_seats(), enemy_side: _empty_seats()}
	_start_btn = null
	_ai_hover_id = -1
	_enemy_seated = false
	_setup_mastery()
	_build_ui()
	_refresh_ui()
	_play_turn_banner()
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


# ── Mastery helpers ──────────────────────────────────────────────────────────
## Reads the run state once per `enter`: is mastery on, what does analysis
## reveal, and which mechs are the enemy pilots' top-mastery mechs.
func _setup_mastery() -> void:
	var s: Dictionary = _gm.season_state
	_mastery_on = MechMastery.is_enabled(s)
	_quirk_on = QuirkSystem.is_enabled(s)
	_enemy_likely = {}
	_my_adept = {}
	_enemy_adept = {}
	_show_enemy_likely = false
	if not _mastery_on:
		return
	_show_enemy_likely = StaffSystem.analysis_tier(s) >= 2
	_setup_adept()
	for raw in _rosters.get(_other_side(_player_side), []):
		var pd := raw as PlayerData
		if pd == null:
			continue
		var top: Array = MechMastery.top_mechs(s, pd.id, 1)
		if top.is_empty():
			continue
		var mid: int = int((top[0] as Dictionary)["mech_id"])
		var v: int = int((top[0] as Dictionary)["value"])
		if not _enemy_likely.has(mid) or int((_enemy_likely[mid] as Dictionary)["value"]) < v:
			_enemy_likely[mid] = {"pilot": pd.name, "value": v}


## Mastery of `pd` with `mech_id` (0 when mastery is off).
func _mastery(pd: PlayerData, mech_id: int) -> int:
	if not _mastery_on or pd == null or mech_id < 0:
		return 0
	return MechMastery.value(_gm.season_state, pd.id, mech_id)


## The pilot of `side` whose role matches the mech's role class — the natural rider.
func _rider_for(side: int, m: MechData) -> PlayerData:
	var roster: Array = _rosters.get(side, [])
	if m == null or m.role < 0 or m.role >= roster.size():
		return null
	return roster[m.role] as PlayerData


## Grid badges: for every mech, my pilots (seat order) and — when analysis reveals
## mastery — the enemy's pilots (highest mastery first, ties by seat) at `ADEPT_TIER`+.
func _setup_adept() -> void:
	var enemy_side: int = _other_side(_player_side)
	var enemy_rows: Dictionary = {}   # mech_id → [[value, seat, pid]]
	for m_raw in _all_mechs:
		var mid: int = (m_raw as MechData).id
		var mine: Array = []
		var theirs: Array = []
		for st in range(SLOT_COUNT):
			var pd: PlayerData = _pilot_at(_player_side, st)
			if pd != null and MechMastery.tier_of(_mastery(pd, mid)) >= ADEPT_TIER:
				mine.append(pd.id)
			if not _show_enemy_likely:
				continue
			var ed: PlayerData = _pilot_at(enemy_side, st)
			if ed == null:
				continue
			var v: int = _mastery(ed, mid)
			if MechMastery.tier_of(v) >= ADEPT_TIER:
				theirs.append([v, st, ed.id])
		theirs.sort_custom(func(a, b):
			if int(a[0]) != int(b[0]):
				return int(a[0]) > int(b[0])
			return int(a[1]) < int(b[1]))
		var ids: Array = []
		for e in theirs.slice(0, ENEMY_DOTS_MAX):
			ids.append(int(e[2]))
		_my_adept[mid] = mine
		enemy_rows[mid] = ids
	_enemy_adept = enemy_rows


## Mastery rows for `MechDetailPanel`: every pilot of `side` (seat order) with
## this mech — `[{name, value, tier, bonus, current}]`. `current` marks the pilot
## sitting on `seat`. Empty when mastery is off, or for the enemy without analysis.
func _mastery_rows(side: int, mech_id: int, seat: int) -> Array:
	if not _mastery_on:
		return []
	if side != _player_side and not _show_enemy_likely:
		return []
	var out: Array = []
	for st in range(SLOT_COUNT):
		var pd: PlayerData = _pilot_at(side, st)
		if pd == null:
			continue
		var v: int = _mastery(pd, mech_id)
		var t: int = MechMastery.tier_of(v)
		out.append({"name": pd.name, "value": v, "tier": t,
				"bonus": MechMastery.bonus_text(t), "current": st == seat})
	return out


# ── Quirk helpers (§14, T1) — my pilots only ─────────────────────────────────
## Quirk stat total of `pd` riding `mech_id` (unconditional + conditions met).
## 0 when quirks are off or `pd` is not one of mine.
func _quirk_total(side: int, pd: PlayerData, mech_id: int) -> int:
	if not _quirk_on or side != _player_side or pd == null:
		return 0
	return QuirkSystem.bonus_total(_gm.season_state, pd, mech_id)


## Quirk rows for `MechDetailPanel` — the pilot on `seat` (my side only):
## `{pilot, slots, rows: [{name, grade, effect, active}]}`; `active` = the
## condition holds with this mech (or there is none). {} when nothing to show.
func _quirk_rows(side: int, mech_id: int, seat: int) -> Dictionary:
	if not _quirk_on or side != _player_side:
		return {}
	var pd: PlayerData = _pilot_at(side, seat)
	if pd == null:
		return {}
	var s: Dictionary = _gm.season_state
	var rows: Array = []
	for id in QuirkSystem.quirks_of(s, pd.id):
		var r: Dictionary = QuirkSystem.row(int(id))
		if r.is_empty():
			continue
		rows.append({"name": QuirkSystem.name_of(int(id)), "grade": int(r["grade"]),
				"effect": QuirkSystem.effect_text(int(id)),
				"active": QuirkSystem.cond_holds(s, pd, mech_id, String(r["cond"]))})
	return {"pilot": pd.name, "slots": QuirkSystem.slots_of(s, pd.id),
			"total": QuirkSystem.bonus_total(s, pd, mech_id), "rows": rows}


# ── UI build ─────────────────────────────────────────────────────────────────
## 화면 한 장을 세우고 데이터를 채운다. 배치는 전부 씬(`UI_View_BanPickView.tscn`) 몫이고
## 여기서 정하는 것은 기기에 따라 달라지는 값(안전 영역, 격자 높이)뿐이다.
func _build_ui() -> void:
	if preview_view != null:
		_view = preview_view
	else:
		_view = BanPickView.create()
		_mf.canvas.add_child(_view)
	# 화면 전체를 안전 영역 안에 앉힌다 — 노치 / 다이나믹 아일랜드 밑에 상대 블록이
	# 깔리지 않게. 바탕(`Background`)은 노치 자리까지 덮는다.
	_view.fit_safe_area()

	var enemy_side: int = _other_side(_player_side)
	_side_ui = {enemy_side: _view.enemy_block, _player_side: _view.player_block}
	_setup_team_block(enemy_side)
	_setup_team_block(_player_side)

	_view.order_row.build(SEQUENCE,
			{GameEnums.DraftSide.BLUE: BLUE_COLOR, GameEnums.DraftSide.RED: RED_COLOR})
	_setup_filter_tabs()
	_build_grid()

	_view.sheet_dim.gui_input.connect(_on_dim_input)
	_view.sheet_close.pressed.connect(_close_sheet)
	_view.sheet_confirm.pressed.connect(_on_confirm_pressed)
	_view.start_button.pressed.connect(_on_start_pressed)


## 메크 정사각 초상화. `MechImages.portrait_for` 가 이미 256² 로 구워진 파일을
## 돌려주므로 예전처럼 1024² 전신 아트를 격자 크기로 다시 굽지 않는다 — 그
## 굽는 단계(`_bake_thumbs` / `THUMB_PX`)는 삭제됐다.
func _mech_thumb(mech_id: int) -> Texture2D:
	if not _thumbs.has(mech_id):
		_thumbs[mech_id] = MechImages.portrait_for(mech_id)
	return _thumbs[mech_id] as Texture2D


func _side_color(side: int) -> Color:
	return BLUE_COLOR if side == GameEnums.DraftSide.BLUE else RED_COLOR


## 순서 줄을 `_action_idx` 에 맞춘다(`BanPickOrderRow`).
func _refresh_pips() -> void:
	if _view == null:
		return
	_view.order_row.refresh(_action_idx, _is_player_turn(), _current_kind() == ACTION_BAN)


# ── 팀 블록 (밴 칩 / 메크 칸 / 파일럿 초상화) ────────────────────────────────
## 씬에 선 팀 블록 하나에 그 팀을 채운다 — 진영색 · 팀 이름 · 초상화 · 탭 배선.
## 위 블록은 밴 → 메크 → 파일럿, 아래 블록은 그 거울(씬의 자식 순서)이라 **안쪽
## (전장 쪽)에 언제나 파일럿 얼굴이 오고 바깥쪽에 메크가 온다**.
func _setup_team_block(side: int) -> void:
	var blk: BanPickTeamBlock = _side_ui[side]
	var side_col: Color = _side_color(side)
	blk.side_label.text = "%s  ·  %s" % [
			("BLUE" if side == GameEnums.DraftSide.BLUE else "RED"),
			String(_team_names.get(side, ""))]
	blk.side_label.add_theme_color_override("font_color", side_col)

	# ── 메크 칸 ── 내용은 자리표(`_seat_mechs`)다 — 새 픽은 첫 빈 자리에 앉는다.
	for i in range(blk.mech_slots.size()):
		var slot: BanPickMechSlot = blk.mech_slots[i]
		slot.setup(side_col, i)
		slot.hit.pressed.connect(_on_mech_slot_tapped.bind(side, i))
		# 아군 메크 칸은 **밴픽 중에도** 끌어 다른 선수 자리로 옮길 수 있다 —
		# 누구에게 태울지를 다 고른 뒤에야 정하라고 하면, 고르는 동안 머릿속에만
		# 있던 배치를 마지막에 다시 세워야 한다.
		if side == _player_side:
			_bind_slot_drag(slot)

	# ── 파일럿 초상화 ── (이름표도 역할 태그도 없다 — 자리가 곧 역할이다)
	for i in range(blk.portraits.size()):
		var por: BanPickPortrait = blk.portraits[i]
		por.setup(side_col)
		por.hit.pressed.connect(_on_pilot_portrait_pressed.bind(side, i))
		var p: PlayerData = _pilot_at(side, i)
		# 눈높이 밴드(밴픽) — 배정 단계에서 상체 크롭으로 바뀐다(`_enter_assign_layout`).
		por.face.texture = PilotImages.eye_for(p.id) if p != null else null
		_refresh_portrait_quirk(side, por, p)


## Quirk badge on my pilot's portrait (bottom-right): `기벽 n` filled with the
## colour of that pilot's highest quirk grade (§14, T1). Nothing when the pilot
## has no quirk, for the enemy, or outside a run.
func _refresh_portrait_quirk(side: int, por: BanPickPortrait, p: PlayerData) -> void:
	if por.quirk_badge == null:
		return
	por.quirk_badge.visible = false
	if not _quirk_on or side != _player_side or p == null:
		return
	var ids: Array = QuirkSystem.quirks_of(_gm.season_state, p.id)
	if ids.is_empty():
		return
	var top: int = 0
	for id in ids:
		top = maxi(top, int(QuirkSystem.row(int(id)).get("grade", 0)))
	por.quirk_badge.visible = true
	# 알약 모양 — 반지름은 높이의 반(`OutgameTheme.add_chip` 과 같다).
	por.quirk_badge.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
			QuirkSystem.grade_color(top), int(por.quirk_badge.size.y * 0.5)))
	if por.quirk_label != null:
		por.quirk_label.text = Loc.t(L.MATCH_BAN_PICK_QUIRK_COUNT, {"n": ids.size()})


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


# ── 역할군 필터 탭 ───────────────────────────────────────────────────────────
## 탭 순서도 화면 순서(탑 · 정글 · 미드 · 원딜 · 서폿)다 — 격자가 그 순서로
## 늘어서 있는데 탭만 열거값 순서면 두 줄이 서로를 가리키지 않는다.
func _filter_tabs() -> Array:
	var out: Array = [[-1, Loc.t(L.UI_WORD_ALL)]]
	for role_raw in GameEnums.ROLE_DISPLAY_ORDER:
		var role: int = int(role_raw)
		out.append([role, MechDetailPanel.role_tag(role)])
	return out


func _setup_filter_tabs() -> void:
	var tabs: Array = _filter_tabs()
	var btns: Array = _view.tab_buttons
	for i in range(btns.size()):
		var btn := btns[i] as Button
		if i >= tabs.size():
			btn.visible = false
			continue
		var role: int = int(tabs[i][0])
		btn.text = String(tabs[i][1])
		btn.set_meta("role", role)
		btn.pressed.connect(_on_filter_pressed.bind(role))


func _on_filter_pressed(role: int) -> void:
	if _filter_role == role:
		return
	_filter_role = role
	_apply_filter()
	_refresh_filter_tabs()


## 켜진 탭 = `SelectableTileOn`(앰버 바탕 · 앰버 테두리 · 앰버 글자), 꺼진 탭 = 씬의
## `SelectableTile`. 모양은 공용 테마 몫이고 여기서는 변형 이름만 바꾼다.
func _refresh_filter_tabs() -> void:
	if _view == null:
		return
	for btn_raw in _view.tab_buttons:
		var btn := btn_raw as Button
		if not btn.visible:
			continue
		var on: bool = int(btn.get_meta("role", -99)) == _filter_role
		btn.theme_type_variation = &"SelectableTileOn" if on else &"SelectableTile"


# ── 메크 격자 ────────────────────────────────────────────────────────────────
## 칸 하나 = `UI_Comp_BanPickMechCell.tscn` — **정사각 초상화 + 아래 파일럿 배지 줄**(능숙 이상인
## 내 선수, 이름은 없다 — 시트 / `MechDetailPanel` 이 들고 있다).
## 숫자와 패시브 설명은 한 번 눌러 여는 시트가 통째로 들고 있다. 칸 높이가 정해지면
## 격자가 보여 줄 4.5 줄이 정해지므로 픽창 높이도 여기서 맞춘다(`fit_pane`).
func _build_grid() -> void:
	var cell_h: float = 0.0
	for m_raw in _grid_mechs:
		var m := m_raw as MechData
		var cell := BanPickMechCell.create()
		_view.grid.add_child(cell)
		var has_role: bool = m.role >= 0 and m.role < ROLE_INITIALS.size()
		cell.setup(_mech_thumb(m.id),
				String(ROLE_INITIALS[m.role]) if has_role else "",
				(ROLE_COLORS[m.role] as Color) if has_role else Color.WHITE)
		cell.pressed.connect(_on_mech_pressed.bind(m.id))
		_cells[m.id] = cell
		cell_h = cell.custom_minimum_size.y
	_view.fit_pane(cell_h)
	_apply_filter()


## 필터를 적용한다. 걸러진 칸은 숨기고 **자리도 비운다** — 빈 칸을 남기면 그
## 역할군에 몇 대가 있는지가 안 읽힌다. 자리를 다시 흘려 놓는 것은 격자
## 컨테이너(`%Grid`)가 숨은 칸을 건너뛰며 한다.
func _apply_filter() -> void:
	for m_raw in _grid_mechs:
		var m := m_raw as MechData
		var cell := _cells.get(m.id, null) as BanPickMechCell
		if cell != null:
			cell.visible = _filter_role < 0 or m.role == _filter_role
	_view.scroll.scroll_vertical = 0


# ── 하단 시트 (선택한 메크의 스탯 · 패시브 · 카드) ───────────────────────────
## 딤은 **픽창만** 덮는다 — 위아래 팀 블록은 지금까지의 밴픽 상황이라 시트를
## 보는 동안에도 보여야 한다(무엇이 이미 나갔는지 모르면 이 기체를 고를지
## 판단할 수 없다). 시트와 딤은 씬에 서 있고 열 때마다 내용만 다시 채운다.
func _open_sheet(mech_id: int) -> void:
	_close_sheet()
	var m := _find_mech(mech_id)
	if m == null:
		return
	_selected_mech_id = mech_id
	_sheet_open = true
	_view.sheet_dim.visible = true
	_view.sheet.visible = true
	_fill_sheet(m)


func _fill_sheet(m: MechData) -> void:
	var v: BanPickView = _view
	# ── 왼쪽: 전신 아트 (원본 — 한 번에 한 대뿐이라 여기서만 1024² 를 쓴다) ──
	var full := MechImages.full_for(m.id)
	v.sheet_art.texture = full
	v.sheet_art.visible = full != null
	v.sheet_art_placeholder.visible = full == null

	# ── 오른쪽: 이름 · 스탯 · 패시브 ──
	v.sheet_name.text = m.name
	var role_txt: String = MechDetailPanel.role_tag(m.role)
	if role_txt == "":
		role_txt = "—"
	v.sheet_stats.text = Loc.t(L.MATCH_BAN_PICK_SHEET_STATS,
			{"role": role_txt, "hp": m.hp, "atk": m.atk, "presence": m.presence})
	var pas: Dictionary = _gm.mech_passive_def(m.id)
	v.sheet_no_passive.visible = pas.is_empty()
	v.sheet_passive_icon.visible = not pas.is_empty()
	v.sheet_passive_head.visible = not pas.is_empty()
	v.sheet_passive_desc.visible = not pas.is_empty()
	for c in v.sheet_passive_icon.get_children():
		v.sheet_passive_icon.remove_child(c)
		c.queue_free()
	if not pas.is_empty():
		# 패시브 아이콘 타일 — `MechDetailPanel` 의 패시브 타일과 같은 색(크기 = 씬 칸).
		v.sheet_passive_icon.add_child(SkillImages.make_mech_icon_tile(
				String(pas.get("key", "")), v.sheet_passive_icon.size.x,
				MechDetailPanel.PASSIVE_TILE_BG, MechDetailPanel.PASSIVE_TILE_ICON,
				MechDetailPanel.PASSIVE_TILE_SHADOW, SHEET_PASSIVE_SHADOW_PX))
		var kw: String = GameEnums.tags_text(String(pas.get("keyword", "")))
		var head: String = Loc.t(String(pas["name_key"]))  # l10n-dynamic: mech_passive.*.name
		if kw != "":
			head += "   [%s]" % kw
		v.sheet_passive_head.text = head
		v.sheet_passive_desc.text = MechSkillSystem.passive_description(pas)

	# ── 카드 셋 ── (오른쪽 칸에서 이어진다 — 왼쪽은 아트 한 장이 통째로 쓴다)
	var defs: Array = _gm.mech_cards_for(m.id)
	v.sheet_cards_header.text = Loc.t(L.MATCH_BAN_PICK_SHEET_CARDS_HEADER, {"n": defs.size()})
	_build_card_row(defs)

	_refresh_sheet_confirm()
	_fill_sheet_mastery(m)


## Left of the sheet buttons (under the art): my natural rider's mastery with
## this mech, and what analysis knows about the enemy wanting it.
func _fill_sheet_mastery(m: MechData) -> void:
	var rider_lbl: Label = _view.sheet_rider
	var intel_lbl: Label = _view.sheet_intel
	rider_lbl.text = ""
	intel_lbl.text = ""
	if not _mastery_on:
		return
	var rider: PlayerData = _rider_for(_player_side, m)
	if rider != null:
		var v: int = _mastery(rider, m.id)
		var t: int = MechMastery.tier_of(v)
		var qt: int = _quirk_total(_player_side, rider, m.id)
		var rider_args: Dictionary = {"name": rider.name, "tier": MechMastery.tier_name(t),
				"value": v, "bonus": MechMastery.bonus_text(t), "quirk": qt}
		rider_lbl.text = Loc.t(L.MATCH_BAN_PICK_RIDER_QUIRK if qt > 0 else L.MATCH_BAN_PICK_RIDER,
				rider_args)
		rider_lbl.add_theme_color_override("font_color", MechMastery.tier_color(t))
	if _show_enemy_likely and _enemy_likely.has(m.id):
		intel_lbl.text = Loc.t(L.MATCH_BAN_PICK_INTEL_ENEMY_PICK,
				{"pilot": String((_enemy_likely[m.id] as Dictionary)["pilot"])})
		intel_lbl.add_theme_color_override("font_color", RED_COLOR)


## 메크 카드들을 손패와 **같은 노드**(`Card.tscn`)로 늘어놓는다 — 따로 그린
## 그림이면 실제로 덱에 들어갈 카드와 같은 것인지 확인할 길이 없다. 카드 한 장 =
## `UI_Comp_BanPickSheetCard.tscn`(카드 자리 + 탭 버튼 + 장수 배지), 줄은 씬의 `%SheetCardRow`.
func _build_card_row(defs: Array) -> void:
	_clear_card_row()
	_view.sheet_no_cards.visible = defs.is_empty()
	for i in range(defs.size()):
		var def: Dictionary = defs[i]
		var item := BanPickSheetCard.create()
		_view.sheet_card_row.add_child(item)
		var node := CARD_SCENE.instantiate() as Card
		# add_child 를 setup 보다 **먼저** — Card.gd 의 @onready 참조는 트리에
		# 들어간 뒤에야 풀린다(CardPileViewer / PilotDetailPanel 과 같은 순서).
		item.hold_card(node)
		node.setup(CardData.from_mech_def(def), false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = Vector2.ZERO
		node.scale = Vector2(SHEET_CARD_SCALE, SHEET_CARD_SCALE)
		node.position = Vector2.ZERO
		# 카드 앞면에는 설명문이 없다 — 누르면 카드 줄 **위쪽**에 설명판이 뜬다
		# (같은 카드를 다시 누르면 닫힌다).
		item.hit.pressed.connect(_toggle_sheet_desc.bind(i, node))
		# 장수 배지 — `count = 0` 인 카드는 덱에 처음부터 들어가지 않고 패시브나
		# 다른 카드가 만들어 줄 때만 세상에 나온다. 그 사정을 적어 두지 않으면
		# "왜 이 카드가 손에 안 들어오나"가 화면 어디에도 없다.
		var cnt: int = int(def.get("count", 0))
		item.count.text = ("×%d" % cnt) if cnt > 0 else Loc.t(L.MATCH_BAN_PICK_GENERATED_ONLY)
		if cnt <= 0:
			item.count.add_theme_color_override("font_color", OutgameTheme.LINK)


func _clear_card_row() -> void:
	if _view == null:
		return
	for c in _view.sheet_card_row.get_children():
		_view.sheet_card_row.remove_child(c)
		c.queue_free()


## 시트 카드의 설명판. 폭은 카드 줄(오른쪽 칸) 폭 그대로, 아랫변이 카드 줄 윗단에서
## `SHEET_DESC_GAP` 위다 — 패시브 설명을 잠시 덮지만, 카드를 누른 손이 보려는
## 것은 지금 그 카드다. 시트가 닫히면 함께 걷힌다(`_close_sheet`).
func _toggle_sheet_desc(idx: int, node: Card) -> void:
	var same: bool = idx == _sheet_desc_idx
	_free_sheet_desc()
	if same or not _sheet_open or node == null or not is_instance_valid(node):
		return
	var row: Control = _view.sheet_card_row
	# 줄의 자리 · 폭은 씬의 오프셋에서 읽는다 — 시트 폭에서 양쪽 오프셋을 뺀 것.
	var rx: float = row.offset_left
	var rw: float = _view.sheet.size.x - row.offset_left + row.offset_right
	_sheet_desc = CardDescBox.build(node.data, rw, true)
	_view.sheet.add_child(_sheet_desc)
	_sheet_desc.position = Vector2(rx,
			maxf(SHEET_PAD, row.offset_top - SHEET_DESC_GAP - _sheet_desc.size.y))
	_sheet_desc_idx = idx


func _free_sheet_desc() -> void:
	if _sheet_desc != null and is_instance_valid(_sheet_desc):
		_sheet_desc.queue_free()
	_sheet_desc = null
	_sheet_desc_idx = -1


## 확정 버튼이 곧 상태 표시다 — 예전의 "BLUE 픽 — 내 차례 (3 / 14)" 한 줄이
## 사라진 지금, 지금이 밴 차례인지 픽 차례인지를 글자로 말하는 자리는 여기뿐이다.
func _refresh_sheet_confirm() -> void:
	if not _sheet_open or _view == null:
		return
	var btn: Button = _view.sheet_confirm
	var ok: bool = _is_player_turn() and _is_legal(_selected_mech_id)
	btn.disabled = not ok
	if ok:
		btn.text = Loc.t(L.MATCH_BAN_PICK_CONFIRM_BAN if _current_kind() == ACTION_BAN
				else L.MATCH_BAN_PICK_CONFIRM_PICK)
	elif not _is_player_turn():
		btn.text = Loc.t(L.MATCH_BAN_PICK_OPPONENT_TURN)
	else:
		btn.text = Loc.t(L.MATCH_BAN_PICK_UNAVAILABLE)


func _on_dim_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_close_sheet()


func _close_sheet() -> void:
	_selected_mech_id = -1
	_sheet_open = false
	_free_sheet_desc()
	if _view != null:
		_clear_card_row()
		_view.sheet.visible = false
		_view.sheet_dim.visible = false
	_refresh_cell_selection()


func _on_confirm_pressed() -> void:
	var id: int = _selected_mech_id
	if id < 0 or not _is_player_turn() or not _is_legal(id):
		return
	_close_sheet()
	_commit_action(id)


# ── State refresh ────────────────────────────────────────────────────────────
func _refresh_ui() -> void:
	if not _assign_mode:
		_refresh_pips()
		_refresh_grid_cells()
		_refresh_cell_selection()
		_refresh_filter_tabs()
	_refresh_side_block(GameEnums.DraftSide.BLUE)
	_refresh_side_block(GameEnums.DraftSide.RED)
	_refresh_sheet_confirm()


func _refresh_grid_cells() -> void:
	var blue_picks: Array = _picks_of(GameEnums.DraftSide.BLUE)
	var red_picks: Array  = _picks_of(GameEnums.DraftSide.RED)
	var my_turn: bool = _is_player_turn()
	var focus_mine: bool = my_turn and _current_kind() == ACTION_PICK
	var focus_enemy: bool = my_turn and _current_kind() == ACTION_BAN
	for id in _cells.keys():
		var cell: BanPickMechCell = _cells[id]
		var veil: ColorRect = cell.veil
		var tag: Label = cell.tag
		var art: TextureRect = cell.art
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
		_refresh_cell_marks(cell, mid, focus_mine, focus_enemy)


## Pilot badges of one grid cell — my 능숙+ pilots under the art, the enemy's (analysis
## tier >= 2) over its top-right; the row of whoever my current move works against is
## highlighted (my pick → mine, my ban → theirs). Taken (banned / picked) cells show none —
## the slab already says everything.
func _refresh_cell_marks(cell: BanPickMechCell, mid: int, focus_mine: bool,
		focus_enemy: bool) -> void:
	var available: bool = _is_legal(mid)
	cell.set_pilot_dots(_my_adept.get(mid, []) if available else [],
			_enemy_adept.get(mid, []) if available else [],
			_side_color(_player_side), _side_color(_other_side(_player_side)),
			focus_mine, focus_enemy)


## 칸 테두리 — 내가 시트로 열어 본 칸은 앰버, **상대가 집어 보고 있는 칸**은
## 상대 진영색으로 두껍게. 둘이 같은 칸이면 상대 쪽이 이긴다(지금 움직이는 손은
## 그쪽이다).
func _refresh_cell_selection() -> void:
	var ai_col: Color = _side_color(_other_side(_player_side))
	for id in _cells.keys():
		var cell: BanPickMechCell = _cells[id]
		if int(id) == _ai_hover_id:
			cell.set_highlight(ai_col, 5)
		elif int(id) == _selected_mech_id:
			cell.set_highlight(ACCENT, 4)
		else:
			cell.set_highlight(ACCENT, 0)


func _refresh_side_block(side: int) -> void:
	var blk := _side_ui.get(side, null) as BanPickTeamBlock
	if blk == null:
		return
	var bans: Array = _side_bans.get(side, [])
	var chips: Array = blk.ban_chips
	for i in range(chips.size()):
		var chip: BanPickBanChip = chips[i]
		chip.art.modulate = BAN_TINT
		if i < bans.size():
			chip.art.texture = _mech_thumb(int(bans[i]))
			chip.x_label.text = "✕"
		else:
			chip.art.texture = null
			chip.x_label.text = ""
	# 상대가 밴을 집어 보는 중이면 다음 칩에 흐린 미리보기.
	var hover_slot: int = _ai_hover_slot(side, ACTION_BAN)
	if hover_slot >= 0 and hover_slot < chips.size():
		var hchip: BanPickBanChip = chips[hover_slot]
		hchip.art.texture = _mech_thumb(_ai_hover_id)
		hchip.art.modulate = Color(1, 1, 1, 0.45)

	# 칸의 내용은 언제나 자리표다 — 아군 칸은 밴픽 중에도 옮겨지므로 픽 순서를
	# 그대로 읽으면 옮긴 자리가 다음 갱신에 되돌아간다.
	var ids: Array = _seat_mechs.get(side, [])
	var slots: Array = blk.mech_slots
	for i in range(slots.size()):
		var slot: BanPickMechSlot = slots[i]
		var sty: StyleBoxFlat = slot.style
		var side_col: Color = slot.side_col
		slot.art.modulate = Color.WHITE
		if i < ids.size() and int(ids[i]) >= 0:
			var mid: int = int(ids[i])
			var m := _find_mech(mid)
			slot.art.texture = _mech_thumb(mid)
			slot.name_label.text = m.name if m != null else "?"
			slot.band.visible = true
			sty.bg_color = side_col.lerp(OutgameTheme.SURFACE, 0.75)
			sty.border_color = side_col
		elif i == _ai_hover_slot(side, ACTION_PICK):
			# 상대가 집어 보는 기체 — 다음 칸에 흐리게, 테두리는 진영색.
			var hm := _find_mech(_ai_hover_id)
			slot.art.texture = _mech_thumb(_ai_hover_id)
			slot.art.modulate = Color(1, 1, 1, 0.45)
			slot.name_label.text = hm.name if hm != null else ""
			slot.band.visible = true
			sty.bg_color = SLOT_EMPTY_COLOR
			sty.border_color = side_col
		else:
			slot.art.texture = null
			slot.name_label.text = ""
			slot.band.visible = false
			sty.bg_color = SLOT_EMPTY_COLOR
			sty.border_color = side_col.lerp(OutgameTheme.SURFACE, 0.55)
		_refresh_slot_mastery(side, slot, int(ids[i]) if i < ids.size() else -1)
		_refresh_slot_quirk(side, slot, int(ids[i]) if i < ids.size() else -1)


## The seat's mastery tag: my seats always (the slot row is "the mech of the
## pilot above it" from the first pick), enemy seats only once analysis reveals
## mastery and the enemy mechs are re-seated by pilot in the assign step.
func _refresh_slot_mastery(side: int, slot: BanPickMechSlot, mech_id: int) -> void:
	var tag: Panel = slot.mtag
	if tag == null:
		return
	var wanted: bool = _mastery_on and mech_id >= 0 \
			and (side == _player_side or (_show_enemy_likely and _enemy_seated))
	var pd: PlayerData = _pilot_at(side, slot.seat) if wanted else null
	if pd == null:
		tag.visible = false
		return
	var t: int = MechMastery.tier_of(_mastery(pd, mech_id))
	tag.visible = true
	tag.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(MechMastery.tier_color(t), 8))
	if slot.mtag_label != null:
		slot.mtag_label.text = "%s %s" % [MechMastery.tier_name(t), MechMastery.bonus_text(t)]


## The seat's quirk tag `기벽 +N` — total quirk stat bonus of my pilot on that
## seat riding that mech (conditional quirks follow the mech, so dragging a slot
## updates it). Hidden for enemy seats, empty seats and a 0 total.
func _refresh_slot_quirk(side: int, slot: BanPickMechSlot, mech_id: int) -> void:
	var tag: Panel = slot.qtag
	if tag == null:
		return
	var total: int = 0
	if mech_id >= 0:
		total = _quirk_total(side, _pilot_at(side, slot.seat), mech_id)
	tag.visible = total > 0
	if total > 0 and slot.qtag_label != null:
		slot.qtag_label.text = Loc.t(L.MATCH_BAN_PICK_QUIRK_BONUS, {"n": total})


## 상대가 지금 집어 보는 기체가 `side` 블록의 몇 번째 칸(밴 칩 / 픽 슬롯)에
## 미리보기로 앉는가. 지금 수가 그 쪽의 그 종류가 아니면 -1.
func _ai_hover_slot(side: int, kind: int) -> int:
	if _ai_hover_id < 0 or _assign_mode or _action_idx >= SEQUENCE.size():
		return -1
	if int(SEQUENCE[_action_idx][0]) != side or _current_kind() != kind:
		return -1
	return (_side_bans.get(side, []) as Array).size() if kind == ACTION_BAN \
			else _first_empty_seat(side)


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
		var seat: int = _first_empty_seat(side)
		if seat >= 0:
			(_seat_mechs[side] as Array)[seat] = int(mech_id)
	_action_idx += 1
	_ai_hover_id = -1
	_refresh_ui()
	if _action_idx >= SEQUENCE.size():
		_clear_banner()
		_enter_assign_mode()
	else:
		_play_turn_banner()
		_maybe_run_ai()


## 상대의 한 수. 곧장 두지 않는다 — 차례 배너가 지나간 뒤, 그 상황에 실제로
## 고를 만한 후보(`_ai_rank`) 가운데 0~2대를 차례로 **집어 보았다가**(격자 칸
## 테두리 + 상대 팀 다음 칸의 흐린 미리보기) 마지막 한 대를 집어 확정한다.
## 집는 한 번은 `AI_HOVER_MIN..MAX` 초. 기다리는 사이 화면이 걷혔거나 수가
## 넘어갔으면(`my_idx`) 조용히 손을 뗀다.
func _maybe_run_ai() -> void:
	if _action_idx >= SEQUENCE.size():
		return
	if _is_player_turn():
		return
	var my_idx: int = _action_idx
	await get_tree().create_timer(BanPickView.BANNER_IN_SEC + BanPickView.BANNER_HOLD_SEC).timeout
	if _action_idx != my_idx or _view == null:
		return
	var ranked: Array = _ai_rank(int(SEQUENCE[my_idx][0]), _current_kind())
	if ranked.is_empty():
		push_error("BanPickController: no legal mechs left for AI")
		return
	var final_pick := ranked[0] as MechData
	var others: Array = ranked.slice(1, AI_CONSIDER_TOP)
	others.shuffle()
	var looks: int = mini(randi_range(0, AI_HOVER_MAX_COUNT), others.size())
	var seq: Array = others.slice(0, looks)
	seq.append(final_pick)
	for m_raw in seq:
		_set_ai_hover((m_raw as MechData).id)
		await get_tree().create_timer(randf_range(AI_HOVER_MIN, AI_HOVER_MAX)).timeout
		if _action_idx != my_idx or _view == null:
			return
	_commit_action(final_pick.id)


## 상대가 이 수에서 고를 만한 순서대로 늘어놓은 합법 기체. 점수는 셋이 정한다 —
## **픽**은 아직 자기 팀에 없는 역할군을, **밴**은 상대(= 이쪽에서 보면 플레이어)
## 팀에 아직 없는 역할군을 노리고(채울 자리를 뺏는 밴), 패시브가 있는 기체에
## 조금 더 얹는다. 흔들림(`randf`)이 있어 같은 판에서도 매번 같은 순서가 아니다.
## Mastery (season only): a pick adds `MASTERY_AI_PICK_W × mastery/MAX` of our
## rider of that role class; a ban adds `MASTERY_AI_BAN_W × mastery/MAX` of the
## opponent's rider — so the AI picks its mains and bans the player's.
func _ai_rank(side: int, kind: int) -> Array:
	var own_roles: Array = []
	for id in _picks_of(side):
		var m := _find_mech(int(id))
		if m != null: own_roles.append(m.role)
	var opp_roles: Array = []
	for id in _picks_of(_other_side(side)):
		var m := _find_mech(int(id))
		if m != null: opp_roles.append(m.role)
	var pick_w: float = ConstTable.num("MASTERY_AI_PICK_W") if _mastery_on else 0.0
	var ban_w: float = ConstTable.num("MASTERY_AI_BAN_W") if _mastery_on else 0.0
	var mmax: float = maxf(1.0, float(MechMastery.max_value())) if _mastery_on else 1.0
	var scored: Array = []
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if not _is_legal(m.id):
			continue
		var s: float = randf() * 1.5
		if not (_gm.mech_passive_def(m.id) as Dictionary).is_empty():
			s += 1.0
		if kind == ACTION_PICK:
			s += 3.0 if not (m.role in own_roles) else -2.0
			# Mastery: prefer what our natural rider of that role rides well.
			s += pick_w * float(_mastery(_rider_for(side, m), m.id)) / mmax
		else:
			if not (m.role in opp_roles):
				s += 2.5
			# Mastery: ban what the opponent's rider of that role rides well.
			s += ban_w * float(_mastery(_rider_for(_other_side(side), m), m.id)) / mmax
		scored.append([s, m])
	scored.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array = []
	for row in scored:
		out.append(row[1])
	return out


func _set_ai_hover(mech_id: int) -> void:
	_ai_hover_id = mech_id
	_refresh_cell_selection()
	_refresh_side_block(_other_side(_player_side))


# ── 차례 배너 ────────────────────────────────────────────────────────────────
## 화면 가운데를 가로지르는 띠 — `내 차례 밴` / `상대 차례 픽` 처럼 **누구의 ·
## 무엇** 차례인지. 가운데에서 양옆으로 펼쳐졌다가 잠깐 머물고 옅어진다
## (인게임 `HudBuilder.play_turn_announce` 와 같은 모양, `BanPickView.play_banner`).
## 입력은 막지 않고, 다음 수가 먼저 오면 이전 배너를 걷고 새로 뜬다.
func _play_turn_banner() -> void:
	if _view == null or _action_idx >= SEQUENCE.size():
		return
	# 같은 팀이 같은 행동을 이어서 하는 수에는 띠를 다시 띄우지 않는다 — 말할
	# 것(누구의 · 무엇)이 바로 앞 수와 같다. 그 이어짐은 순서 줄의 캡슐이 말한다.
	if BanPickOrderRow.same_run(SEQUENCE, _action_idx - 1, _action_idx):
		return
	var mine: bool = _is_player_turn()
	var ban: bool = _current_kind() == ACTION_BAN
	var msg_key: String
	if mine:
		msg_key = L.MATCH_BAN_PICK_BANNER_MY_BAN if ban else L.MATCH_BAN_PICK_BANNER_MY_PICK
	else:
		msg_key = L.MATCH_BAN_PICK_BANNER_OPPONENT_BAN if ban else L.MATCH_BAN_PICK_BANNER_OPPONENT_PICK
	var msg: String = Loc.t(msg_key)  # l10n-dynamic: match.ban_pick.banner.*
	_view.play_banner(msg, _side_color(int(SEQUENCE[_action_idx][0])))


func _clear_banner() -> void:
	if _view != null:
		_view.clear_banner()


# ── 배정 단계 ────────────────────────────────────────────────────────────────
## 픽창을 걷어 내고 아군 블록을 **배정판**으로 바꾼다. 화면이 바뀌지 않는
## 것이 요점이다 — 방금 고른 열 대가 그 자리에 그대로 있어야 "누가 뭘 탈지"를
## 그 그림 위에서 정할 수 있다.
func _enter_assign_mode() -> void:
	_assign_mode = true
	_close_sheet()
	# 끌던 칸이 있으면 놓게 한다 — 아군 블록이 배정판으로 바뀌므로 손에 든 칸의
	# 원래 자리가 움직인다.
	_cancel_drag()
	var enemy_side: int = _other_side(_player_side)

	# 픽창 해체 — 순서 줄도 함께 걷는다(열네 수가 다 끝났으니 가리킬 차례가 없다).
	_view.order_row.stop()
	_view.band.visible = false
	for cell in _cells.values():
		(cell as Node).queue_free()
	_cells.clear()

	# 상대 블록은 그대로 두고 **탭만 열어 준다** — 밴픽 내내 서 있던 그림이 그대로
	# 남아야 "저쪽이 무엇을 골랐나"를 두 번 읽지 않는다.
	_set_block_tappable(enemy_side, true)

	_enter_assign_layout()
	_build_assign_prompt()
	_refresh_ui()
	_play_assign_intro(enemy_side)


## 배정 진입 연출. 두 팀 블록이 비워진 픽창 자리로 **가운데에 모이고**, 그 다음
## 상대 메크 칸이 포지션에 맞는 선수 자리로 옮겨 앉는다. 끝나야 "게임 시작"이
## 풀린다. 모이는 자리 = 하단 바 위 본문의 세로 가운데(블록 높이는 씬에서 읽는다).
func _play_assign_intro(enemy_side: int) -> void:
	var e_holder := _side_ui.get(enemy_side, null) as Control
	var p_holder := _side_ui.get(_player_side, null) as Control
	var tw := create_tween().set_parallel()
	if e_holder != null and p_holder != null:
		var top_pad: float = e_holder.position.y
		var e_h: float = e_holder.get_combined_minimum_size().y
		var p_h: float = p_holder.get_combined_minimum_size().y
		var body_h: float = OutgameTheme.bottom_bar_top()
		var gather_y: float = maxf(top_pad, (body_h - (e_h + GATHER_GAP + p_h)) * 0.5)
		tw.tween_property(e_holder, "position:y", gather_y, GATHER_SEC) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(p_holder, "position:y", gather_y + e_h + GATHER_GAP, GATHER_SEC) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		tw.kill()
	await get_tree().create_timer(GATHER_SEC + ENEMY_SWAP_DELAY).timeout
	if _view == null:
		return
	await _play_enemy_reassign(enemy_side, _enemy_role_order(enemy_side))
	if _view == null:
		return
	if _start_btn != null and is_instance_valid(_start_btn):
		_start_btn.disabled = false


## 상대의 배정 — 각 자리에 **그 선수의 역할과 같은 역할군의 기체**를 앉히고,
## 맞는 기체가 없는 자리는 남은 기체로 픽 순서대로 채운다. 상대가 다섯 대를
## 역할군대로 골랐다면 자리마다 제 역할의 기체가 앉는다.
##
## With mastery on, the pairing is greedy over (role match first, then the
## seat pilot's mastery with the mech) — so among two mechs of the same role
## class the pilot gets the one they ride best, and an off-role leftover goes to
## whoever handles it best. Without mastery the score is the role match alone
## and the order falls back to pick order, as before.
func _enemy_role_order(side: int) -> Array:
	var picks: Array = (_picks_of(side) as Array).duplicate()
	var pairs: Array = []   # [score, pick_index, seat, mech_id]
	for seat in range(SLOT_COUNT):
		var role: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var pd: PlayerData = _pilot_at(side, seat)
		for pi in picks.size():
			var mid: int = int(picks[pi])
			var m := _find_mech(mid)
			var score: int = (1000 if m != null and m.role == role else 0) + _mastery(pd, mid)
			pairs.append([score, pi, seat, mid])
	pairs.sort_custom(func(a, b):
		if int(a[0]) != int(b[0]):
			return int(a[0]) > int(b[0])
		if int(a[1]) != int(b[1]):
			return int(a[1]) < int(b[1])
		return int(a[2]) < int(b[2]))
	var out: Array = _empty_seats()
	var used: Dictionary = {}
	for p in pairs:
		var seat: int = int(p[2])
		var mid: int = int(p[3])
		if int(out[seat]) >= 0 or used.has(mid):
			continue
		out[seat] = mid
		used[mid] = true
	return out


## 상대 메크 칸이 지금 자리에서 새 자리로 미끄러져 옮겨 앉는다. 칸의 판(`frame`)
## 자체를 옮겼다가, 다 옮기면 제자리로 되돌리고 내용(자리표)을 바꿔 끼운다 — 끝
## 화면은 같고, 판이 언제나 자기 칸에 있다는 전제(탭 버튼 · 갱신)가 유지된다.
func _play_enemy_reassign(side: int, new_order: Array) -> void:
	var blk := _side_ui.get(side, null) as BanPickTeamBlock
	var slots: Array = blk.mech_slots if blk != null else []
	var old: Array = _seat_mechs.get(side, [])
	var moved: bool = false
	var tw := create_tween().set_parallel()
	for i in range(mini(slots.size(), old.size())):
		var mid: int = int(old[i])
		if mid < 0:
			continue
		var j: int = new_order.find(mid)
		if j < 0 or j == i or j >= slots.size():
			continue
		moved = true
		var frame: Panel = (slots[i] as BanPickMechSlot).frame
		# 판은 제 칸 안의 (0, 0) 에 앉아 있다 — 목표는 두 칸 사이의 거리다.
		var dx: float = (slots[j] as Control).position.x - (slots[i] as Control).position.x
		frame.z_index = 1
		tw.tween_property(frame, "position:x", dx, ENEMY_SWAP_SEC) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		# 오른쪽으로 가는 칸은 위로, 왼쪽으로 가는 칸은 아래로 비켜 지나간다 —
		# 가로지르는 두 칸이 서로를 통과하지 않고 엇갈려 지나가는 것으로 읽힌다.
		var lift: float = ENEMY_SWAP_LIFT_PX if j > i else -ENEMY_SWAP_LIFT_PX
		tw.tween_property(frame, "position:y", -lift, ENEMY_SWAP_SEC * 0.5) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(frame, "position:y", 0.0, ENEMY_SWAP_SEC * 0.5) \
				.set_delay(ENEMY_SWAP_SEC * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	if not moved:
		tw.kill()
	else:
		# 박자는 트윈의 `finished` 가 아니라 타이머로 기다린다 — 노드가 도중에
		# free 되면 그 신호는 영영 오지 않는다.
		await get_tree().create_timer(ENEMY_SWAP_SEC).timeout
		if _view == null:
			return
		for slot_raw in slots:
			var slot := slot_raw as BanPickMechSlot
			if is_instance_valid(slot):
				slot.frame.position = Vector2.ZERO
				slot.frame.z_index = 0
	_seat_mechs[side] = new_order
	_enemy_seated = true
	_refresh_side_block(side)


## 한 팀 블록의 초상화 · 메크 칸 탭을 켜고 끈다. 아군 메크 칸만은 예외로
## 남는다 — 그쪽 탭은 드래그 배선(`_on_slot_input`)이 함께 받으므로 투명
## 버튼을 켜면 그 버튼이 press 를 가져가 드래그가 영영 시작되지 않는다.
func _set_block_tappable(side: int, on: bool) -> void:
	var blk := _side_ui.get(side, null) as BanPickTeamBlock
	if blk == null:
		return
	for por in blk.portraits:
		(por as BanPickPortrait).hit.visible = on
	if side == _player_side:
		return
	for slot in blk.mech_slots:
		(slot as BanPickMechSlot).hit.visible = on


## 아군 블록을 배정판으로 — **파일럿 상체 일러스트가 위, 메크 칸이 그 아래**,
## 메크 줄 오른쪽 아래에 조작 안내 한 줄, 맨 밑에 밴 칩(씬의 `%PlayerBlock` 순서).
## 초상화 줄은 드래프트 화면의 선택 칸과 **같은 크롭 · 같은 비율**
## (`PilotImages.BUST_ASPECT`)로 길어지고, 블록은 아래끝을 지킨 채 위로 자란다.
##
## 예전에는 메크가 위였다 — 끄는 손가락이 그 밑의 "어느 파일럿 자리인가"를
## 가리지 않게 하려는 배치였는데, 그러면 세로로 훑을 때 목적어가 주어보다
## 먼저 와서 다섯 칸이 무엇을 정하는 화면인지가 뒤집혀 읽혔다. 초상화가
## 상체 일러스트로 커진 지금은 손가락이 덮을 수 있는 넓이보다 칸이 훨씬 커서
## 그 걱정 자체가 없다.
func _enter_assign_layout() -> void:
	var blk := _side_ui.get(_player_side, null) as BanPickTeamBlock
	if blk == null:
		return
	var pw: float = (blk.portraits[0] as Control).custom_minimum_size.x if not blk.portraits.is_empty() \
			else 0.0
	blk.set_assign_layout(pw / PilotImages.BUST_ASPECT)
	for i in range(blk.portraits.size()):
		var p: PlayerData = _pilot_at(_player_side, i)
		(blk.portraits[i] as BanPickPortrait).face.texture = \
				PilotImages.bust_for(p.id) if p != null else null
	_set_block_tappable(_player_side, true)


## "게임 시작"은 **하단 구간을 통째로 차지하는 바**다(씬의 `%StartButton` = `BarPrimaryButton`,
## 아래 인셋은 `BanPickView.fit_safe_area` 의 `OutgameTheme.fit_bottom_bar`) — 아웃게임 화면의 주된 행동이 서는
## 자리. 배정 진입 연출(`_play_assign_intro`)이 끝날 때까지 잠겨 있다. 제목("메크
## 배정")은 없다 — 화면에 남은 것이 양 팀 초상화와 그 밑의 기체뿐이면 무엇을 하는
## 단계인지는 그림이 말한다.
func _build_assign_prompt() -> void:
	_start_btn = _view.start_button
	_start_btn.visible = true
	_start_btn.disabled = true
	# Saturday prep (split): the picks are stored and the match waits for Sunday.
	if _mf != null and _mf.is_prep_only():
		_start_btn.text = Loc.t(L.MATCH_FLOW_PICKS_DONE)


# ── 배정 단계의 상세 팝업 ────────────────────────────────────────────────────
func _on_pilot_portrait_pressed(side: int, seat: int) -> void:
	if not _assign_mode:
		return
	var p: PlayerData = _pilot_at(side, seat)
	if p == null:
		return
	if _pilot_detail == null:
		_pilot_detail = DraftDetailPanel.create()
		add_child(_pilot_detail)
	_close_detail_panels()
	_pilot_detail.open(p)


func _on_mech_slot_tapped(side: int, seat: int) -> void:
	var ids: Array = _seat_mechs.get(side, [])
	if seat < 0 or seat >= ids.size() or int(ids[seat]) < 0:
		return
	if not _assign_mode:
		# 밴픽 중에 아군 칸을 누르면 격자 칸을 누른 것과 같은 시트가 뜬다 —
		# 이미 가져간 기체라 확정 버튼은 잠겨 있다.
		if side == _player_side:
			_open_sheet(int(ids[seat]))
			_refresh_cell_selection()
		return
	_open_mech_detail(int(ids[seat]), side, seat)


## `side` / `seat` say whose slot was tapped — the panel lists that team's
## mastery with the mech and highlights the pilot on that seat.
func _open_mech_detail(mech_id: int, side: int, seat: int) -> void:
	var m := _find_mech(mech_id)
	if m == null:
		return
	if _mech_detail == null:
		_mech_detail = MechDetailPanel.create()
		add_child(_mech_detail)
	_close_detail_panels()
	_mech_detail.open(m, _mastery_rows(side, mech_id, seat), _quirk_rows(side, mech_id, seat))


## 두 팝업은 **동시에 뜨지 않는다** — 파일럿과 메크를 한 화면에 겹치지 않는
## 것이 이 단계의 규칙이고, 딤이 두 겹 쌓이면 뒤엣것이 앞엣것을 어둡게 덮는다.
func _close_detail_panels() -> void:
	if _pilot_detail != null:
		_pilot_detail.close()
	if _mech_detail != null:
		_mech_detail.close()


# ── 메크 칸 드래그 ───────────────────────────────────────────────────────────
## 메크 칸 하나를 끌 수 있게 만든다. 누른 컨트롤이 마우스 포커스를 유지하므로
## 커서가 칸 밖으로 나가도 motion / release 가 계속 이 칸으로 들어온다 —
## 그래서 드래그 레이어를 따로 두지 않는다.
func _bind_slot_drag(slot: BanPickMechSlot) -> void:
	slot.frame.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.frame.gui_input.connect(_on_slot_input.bind(slot.seat))


## 이벤트 자리 → 캔버스(전역) 좌표. `gui_input` 의 위치는 그 칸의 로컬 좌표다.
func _event_pos(ev: InputEventMouse, seat: int) -> Vector2:
	var slot := _slot_at(seat)
	if slot == null:
		return ev.position
	return slot.frame.get_global_transform() * ev.position


func _on_slot_input(ev: InputEvent, seat: int) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if _mech_at_seat(seat) < 0:
				return
			_drag_armed = true
			_drag_seat = seat
			_drag_from = _event_pos(mb, seat)
		else:
			_end_drag(_event_pos(mb, seat))
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _drag_armed:
		var here: Vector2 = _event_pos(mm, seat)
		if not _dragging:
			# 문턱을 넘기 전까지는 탭이지 드래그가 아니다 — 손가락은 언제나
			# 조금씩 떨리므로, 문턱이 없으면 누르기만 해도 칸이 떠오른다.
			if here.distance_to(_drag_from) < DRAG_THRESHOLD_PX:
				return
			_begin_drag_ghost()
			if not _dragging:
				return
			# 칸이 손에 들렸다. 아직 바꾼 것은 없다.
			Haptics.play(Haptics.Kind.SELECT)
		var ghost: Panel = _view.drag_ghost
		ghost.global_position = here - ghost.size * 0.5
		_highlight_drop_target(here)


## 손에 든 칸 = 씬의 `%DragGhost` (앰버 테두리 판 + 그 메크 초상화). 크기는 끌려
## 나온 칸의 판 크기를 그대로 받는다.
func _begin_drag_ghost() -> void:
	var mid: int = _mech_at_seat(_drag_seat)
	var slot := _slot_at(_drag_seat)
	if mid < 0 or slot == null:
		return
	var ghost: Panel = _view.drag_ghost
	ghost.size = slot.frame.size
	_view.drag_ghost_art.texture = _mech_thumb(mid)
	ghost.visible = true
	_dragging = true
	# 끌려 나온 칸은 그 자리에 **자국으로 남는다** — 비워 버리면 어디서 끌어
	# 왔는지가 사라져, 엉뚱한 곳에 놓고도 무엇과 바뀌었는지를 못 읽는다.
	slot.frame.modulate = Color(1, 1, 1, 0.35)


## 지금 커서가 놓인 칸의 테두리를 밝힌다. 놓을 수 있는 자리가 어디인지는
## 끌고 있는 동안에만 물어보는 질문이라 상태로 남기지 않는다.
func _highlight_drop_target(here: Vector2) -> void:
	var target: int = _seat_under(here)
	for slot_raw in _player_slots():
		var slot: BanPickMechSlot = slot_raw
		if slot.seat == _drag_seat:
			continue
		var sty: StyleBoxFlat = slot.style
		var filled: bool = _mech_at_seat(slot.seat) >= 0
		sty.border_color = ACCENT if slot.seat == target else \
				(slot.side_col if filled else slot.side_col.lerp(OutgameTheme.SURFACE, 0.55))
		sty.set_border_width_all(4 if slot.seat == target else 2)


func _end_drag(here: Vector2) -> void:
	var from_seat: int = _drag_seat
	var dragging: bool = _dragging
	# 문턱을 못 넘긴 것은 드래그가 아니라 **탭**이고, 탭은 그 칸의 메크 상세를
	# 연다 — 아군 메크 칸에는 투명 탭 버튼을 얹을 수 없어서(드래그의 press 를
	# 가로챈다) 그 몫이 여기로 온다.
	if not dragging and _drag_armed and from_seat >= 0:
		_drag_armed = false
		_drag_seat = -1
		_on_mech_slot_tapped(_player_side, from_seat)
		return
	if dragging:
		var to_seat: int = _seat_under(here)
		_hide_drag_ghost()
		if to_seat >= 0 and to_seat != from_seat:
			_swap_assign(from_seat, to_seat)
			# 두 칸이 실제로 맞바뀌었다.
			Haptics.play(Haptics.Kind.MEDIUM)
	_drag_armed = false
	_drag_seat = -1
	if dragging:
		var slot := _slot_at(from_seat)
		if slot != null:
			slot.frame.modulate = Color(1, 1, 1, 1)
	_refresh_side_block(_player_side)
	_reset_slot_borders()


func _hide_drag_ghost() -> void:
	_dragging = false
	if _view != null:
		_view.drag_ghost.visible = false


## 끌던 칸을 그 자리에 내려놓는다(아무것도 바꾸지 않는다).
func _cancel_drag() -> void:
	_hide_drag_ghost()
	var slot := _slot_at(_drag_seat)
	if slot != null:
		slot.frame.modulate = Color(1, 1, 1, 1)
	_drag_armed = false
	_drag_seat = -1
	_reset_slot_borders()


func _reset_slot_borders() -> void:
	for slot_raw in _player_slots():
		((slot_raw as BanPickMechSlot).style as StyleBoxFlat).set_border_width_all(2)


func _swap_assign(a: int, b: int) -> void:
	var seats: Array = _seat_mechs.get(_player_side, [])
	if a < 0 or b < 0 or a >= seats.size() or b >= seats.size():
		return
	var tmp = seats[a]
	seats[a] = seats[b]
	seats[b] = tmp


## 캔버스(전역) 좌표 하나가 어느 아군 메크 칸 위인가.
func _seat_under(here: Vector2) -> int:
	for slot_raw in _player_slots():
		var slot: BanPickMechSlot = slot_raw
		if slot.frame.get_global_rect().has_point(here):
			return slot.seat
	return -1


func _player_slots() -> Array:
	var blk := _side_ui.get(_player_side, null) as BanPickTeamBlock
	return blk.mech_slots if blk != null else []


func _slot_at(seat: int) -> BanPickMechSlot:
	for slot_raw in _player_slots():
		var slot: BanPickMechSlot = slot_raw
		if slot.seat == seat:
			return slot
	return null


func _mech_at_seat(seat: int) -> int:
	var seats: Array = _seat_mechs.get(_player_side, [])
	if seat < 0 or seat >= seats.size():
		return -1
	return int(seats[seat])


func _empty_seats() -> Array:
	var out: Array = []
	out.resize(SLOT_COUNT)
	out.fill(-1)
	return out


## 그 팀의 왼쪽부터 첫 빈 자리(-1 = 다 찼다). 새 픽은 여기에 앉는다.
func _first_empty_seat(side: int) -> int:
	return (_seat_mechs.get(side, []) as Array).find(-1)


# ── 종료 ─────────────────────────────────────────────────────────────────────
## §15 C — pilots with 2+ card presets pick the active one first
## (`BanPickLoadoutPicker`, cancel = back to the assignment); otherwise straight on.
func _on_start_pressed() -> void:
	if not BanPickLoadoutPicker.open_if_needed(self, _rosters.get(_player_side, []), _finish):
		_finish()


## 배정을 로스터에 새기고 화면을 걷는다. `PlayerData.assigned_mech` 를 직접
## 채우는 것은 예전 `AssignController` 가 하던 일이고, 그 파일이 사라진 지금
## 그 책임이 여기로 왔다. 자리(seat) → 역할 변환은 `ROLE_DISPLAY_ORDER` 한 겹
## 뿐이고, **로스터 자체는 역할 0..4 순서를 그대로 지킨다** — MatchFlow 의
## 재개 스냅샷(`_roster_mech_ids`)이 그 순서를 전제한다.
func _finish() -> void:
	var p_roster: Array = _rosters.get(_player_side, [])
	_write_assignment(_player_side)
	_write_assignment(_other_side(_player_side))

	var player_picks: Array = (_picks_of(_player_side) as Array).duplicate()
	var enemy_picks: Array  = (_picks_of(_other_side(_player_side)) as Array).duplicate()
	_close_sheet()
	# 팝업은 CanvasLayer 라 화면을 지워도 따라 사라지지 않는다 — 열어 둔
	# 채 넘어가면 딤이 BattleSim 위에 그대로 남는다.
	_close_detail_panels()
	_view.queue_free()
	_view = null
	_cells.clear()
	_side_ui.clear()
	_thumbs.clear()
	phase_finished.emit({
		"banned": _banned.duplicate(),
		"player_picks": player_picks,
		"enemy_picks": enemy_picks,
		"player_roster": p_roster,
		"enemy_roster": _rosters.get(_other_side(_player_side), []),
	})


## 자리표를 그 팀 로스터의 `assigned_mech` 에 새긴다.
func _write_assignment(side: int) -> void:
	var roster: Array = _rosters.get(side, [])
	var seats: Array = _seat_mechs.get(side, [])
	for seat in range(mini(SLOT_COUNT, seats.size())):
		var role: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		if role < 0 or role >= roster.size() or int(seats[seat]) < 0:
			continue
		(roster[role] as PlayerData).assigned_mech = _find_mech(int(seats[seat]))


# ── Helpers ──────────────────────────────────────────────────────────────────
func _find_mech(id: int) -> MechData:
	for m_raw in _all_mechs:
		var m := m_raw as MechData
		if m.id == id: return m
	return null
