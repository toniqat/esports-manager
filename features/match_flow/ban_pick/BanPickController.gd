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
## 진행 순서 표시 줄(14칸)이 차지하는 띠의 높이. **화면 최상단이 아니라 픽창
## 안, 역할군 필터 바로 위**에 앉는다 — 지금 누구 차례인지를 보려고 시선이
## 화면 끝까지 올라갔다 내려오지 않게, 고르는 곳 바로 위에서 말한다.
## 띠가 칸보다 훨씬 높은 것은 **지금 칸**의 위아래로 삼각형이 오르내릴 자리다.
const PIPS_ROW_H: float   = 64.0
const PIP_W: float        = 58.0
const PIP_GAP: float      = 6.0
## 지난 / 다음 칸의 두께와 **지금 칸**의 두께. 지금 칸만 두꺼워져 그 안에 밴(X) /
## 픽(V) 아이콘이 들어간다.
const PIP_H: float        = 12.0
const PIP_ACTIVE_H: float = 26.0
const PIP_ICON: float     = 20.0
const PIP_GROW_SEC: float = 0.16
## 같은 팀의 같은 행동(밴 / 픽)이 연달아 이어지는 수들은 **캡슐 하나**로 붙는다
## (`_seq_run`). 칸 사이 틈이 사라지는 대신 이음매에 이 폭의 구분선이 서서
## 몇 수짜리인지가 읽힌다.
const PIP_DIVIDER_W: float = 2.0
## 지금 칸의 맥박 — 알파가 1 ↔ `1 − PIP_PULSE_DEPTH` 를 오간다. 캡슐로 붙은
## 수에서는 칸 두께가 함께 두꺼워져 있으므로 "그중 몇 번째인가"는 이 맥박과
## 아이콘이 말한다.
const PIP_PULSE_SEC: float   = 0.9
const PIP_PULSE_DEPTH: float = 0.38
## 지금 칸에 붙는 삼각형 — 내 차례면 칸 **아래**에서 아래(우리 팀 블록)를,
## 상대 차례면 칸 **위**에서 위(상대 팀 블록)를 가리키며 그쪽으로 천천히
## 오갔다 돌아온다.
const TURN_ARROW_W: float   = 22.0
const TURN_ARROW_H: float   = 13.0
const TURN_ARROW_GAP: float = 3.0
const TURN_ARROW_BOB_PX: float  = 5.0
const TURN_ARROW_BOB_SEC: float = 1.3
const ICON_BAN   := preload("res://resources/images/ui/banpick/ban_x.svg")
const ICON_PICK  := preload("res://resources/images/ui/banpick/pick_v.svg")
const ICON_ARROW := preload("res://resources/images/ui/banpick/turn_arrow.svg")
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
## eye 크롭의 가로:세로 비 (`eye/N_eye.png` 480×200). 임의 높이로
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
const SHEET_DESC_GAP: float   = 8.0

## 배정 단계에서 메크 칸을 끌기 시작하는 문턱(px). 이보다 덜 움직인 것은 탭이지
## 드래그가 아니다 — 손가락은 언제나 조금씩 떨린다. 문턱을 못 넘긴 탭은
## 그 칸의 메크 상세를 연다.
const DRAG_THRESHOLD_PX: float = 8.0

## 배정 단계 메크 줄 오른쪽 아래의 조작 안내 한 줄.
const ASSIGN_HINT_H: float = 24.0
const ASSIGN_HINT_FONT: int = 17
const ASSIGN_HINT_TEXT: String = "드래그 드롭으로 메크-파일럿 지정 변경"
## 배정 단계 진입 연출 — 두 팀 블록이 화면 가운데로 모이고(`GATHER_SEC`), 그
## 다음 상대 메크 칸들이 포지션에 맞는 선수 자리로 옮겨 앉는다(`ENEMY_SWAP_SEC`).
## 모인 두 블록 사이 간격이 `GATHER_GAP` 이다.
const GATHER_SEC: float = 0.42
const GATHER_GAP: float = 36.0
const ENEMY_SWAP_DELAY: float = 0.18
const ENEMY_SWAP_SEC: float = 0.48
## 옮겨 앉는 칸이 다른 칸을 가로지를 때 위로 살짝 떠오르는 높이.
const ENEMY_SWAP_LIFT_PX: float = 22.0

# ── 색 ── **아웃게임 흰 배경 계통**(`OutgameTheme`)이다. 밴픽은 경기 직전이지만
# 아직 전장이 아니라 시즌 화면들(허브 · 시간 경과 · 순위)과 같은 바탕을 쓴다 —
# 예전의 어두운 판은 이 화면 하나만 인게임처럼 보여 "경기가 이미 시작됐나"로
# 읽혔다. 픽창은 흰 카드 한 장(그림자)이 회색 바탕 위에 떠서 "여기가 고르는
# 곳"을 가른다.
const GRID_BG_COLOR := OutgameTheme.SURFACE
const PAGE_BG_COLOR := OutgameTheme.BG
const PANEL_COLOR := OutgameTheme.SURFACE
const SLOT_EMPTY_COLOR := OutgameTheme.SURFACE_SUNK
## 진영색 — 흰 바탕에서 읽히도록 인게임 쪽보다 한 단계 짙다.
const BLUE_COLOR  := Color(0.20, 0.45, 0.92)
const RED_COLOR   := Color(0.88, 0.27, 0.27)
const BAN_TINT    := Color(0.42, 0.42, 0.46, 1.0)
const TEXT_DIM    := OutgameTheme.TEXT_SUB
const ACCENT      := OutgameTheme.ACCENT
const SHEET_DIM_COLOR := Color(0.11, 0.11, 0.12, 0.38)

# ── 차례 배너 ── 수가 넘어갈 때마다 화면 가운데를 가로지르는 띠(인게임의
# "당신의 차례" 배너와 같은 모양). 지금이 **누구의 · 무엇** 차례인지를 한 번에
# 말한다(`내 차례 밴` / `상대 차례 픽` …). 입력을 막지 않는다.
const BANNER_H: float        = 104.0
const BANNER_IN_SEC: float   = 0.22
const BANNER_HOLD_SEC: float = 0.45
const BANNER_OUT_SEC: float  = 0.25
const BANNER_FONT: int       = 52

# ── 상대의 만지작거리기 ── 상대는 곧장 고르지 않는다. 그 상황에 실제로 고를
# 만한 후보(`_ai_rank`) 중 0~2대를 차례로 **집어 보았다가** 마지막 한 대를
# 확정한다. 한 번 집어 보는 시간은 `AI_HOVER_MIN..MAX` 사이 무작위.
const AI_HOVER_MIN: float = 0.3
const AI_HOVER_MAX: float = 0.8
const AI_HOVER_MAX_COUNT: int = 2
## 집어 볼 후보를 고르는 상위 몇 대.
const AI_CONSIDER_TOP: int = 5

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
## Analysis is delegated → the analyst also marks recommended bans.
var _show_analyst_bans: bool = false
## mech_id(int) → {"pilot": String, "value": int} — each enemy pilot's top mech.
var _enemy_likely: Dictionary = {}
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
var _panel: Panel
var _seq_pips: Array = []          # Array[Panel]
## 캡슐 안 이음매의 구분선 — `{line: ColorRect, idx: int}` (idx 와 idx+1 사이).
var _seq_dividers: Array = []
var _pulse_t: float = 0.0
var _pips_root: Control = null
## 지금 칸 안의 밴 / 픽 아이콘과 그 위아래의 삼각형. 칸마다 두지 않고 한 벌을
## 지금 칸으로 옮겨 다닌다.
var _pip_icon: TextureRect = null
var _turn_arrow: TextureRect = null
var _arrow_base_y: float = 0.0
var _arrow_dir: float = 1.0        # +1 = 아래로 오간다(내 차례), -1 = 위로(상대 차례)
var _arrow_t: float = 0.0
var _pip_tween: Tween = null
## 차례 배너 — `_mf.canvas` 위, 판보다 앞에 선다. 새 배너가 뜨면 이전 것을 걷는다.
var _banner_root: Control = null
var _banner_gen: int = 0
var _banner_tween: Tween = null
## 상대가 지금 집어 보고 있는 기체(-1 = 없음). 격자 칸 테두리와 상대 팀의 다음
## 칸(픽 슬롯 / 밴 칩)에 흐린 미리보기로 나타난다.
var _ai_hover_id: int = -1
# 시트의 카드 설명판 — 시트 카드를 누르면 그 카드 줄 위에 뜬다.
var _sheet_desc: Panel = null
var _sheet_desc_idx: int = -1
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
	_show_enemy_likely = false
	_show_analyst_bans = false
	if not _mastery_on:
		return
	_show_enemy_likely = StaffSystem.analysis_tier(s) >= 2
	_show_analyst_bans = StaffSystem.is_delegated(s, "analysis")
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


## Analyst's recommended bans right now: the highest-mastery enemy likely picks
## that are still legal, while I still have bans left. Empty when not delegated.
func _analyst_bans() -> Array:
	if not _show_analyst_bans or _assign_mode:
		return []
	if (_side_bans.get(_player_side, []) as Array).size() >= 2:
		return []
	var rows: Array = []
	for k in _enemy_likely.keys():
		if _is_legal(int(k)):
			rows.append([int((_enemy_likely[k] as Dictionary)["value"]), int(k)])
	rows.sort_custom(func(a, b):
		if int(a[0]) != int(b[0]):
			return int(a[0]) > int(b[0])
		return int(a[1]) < int(b[1]))
	var out: Array = []
	for r in rows.slice(0, ConstTable.int_of("MASTERY_ANALYST_BANS")):
		out.append(int(r[1]))
	return out


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
		rows.append({"name": String(r["name"]), "grade": int(r["grade"]),
				"effect": QuirkSystem.effect_text(int(id), true),
				"active": QuirkSystem.cond_holds(s, pd, mech_id, String(r["cond"]))})
	return {"pilot": pd.name, "slots": QuirkSystem.slots_of(s, pd.id),
			"total": QuirkSystem.bonus_total(s, pd, mech_id), "rows": rows}


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

	var top_block_y: float = TOP_PAD
	var band_top: float = top_block_y + block_h + BLOCK_GAP
	var bot_block_y: float = h - BOT_PAD - block_h
	var band_h: float = maxf(200.0, (bot_block_y - BLOCK_GAP) - band_top)

	# 격자 칸 — 폭은 열 수가 정하고 **높이는 그 폭이 정한다**(정사각 + 이름 줄).
	var content_w: float = strip_w - GRID_PANEL_PAD * 2.0 - SCROLLBAR_W
	var gcell_w: float = (content_w - GRID_GAP * float(GRID_COLS - 1)) / float(GRID_COLS)
	var gcell_h: float = gcell_w + CELL_NAME_H
	var grid_h_want: float = GRID_VISIBLE_ROWS * (gcell_h + GRID_GAP) - GRID_GAP
	var grid_h_max: float = band_h - PIPS_ROW_H - TABS_H - BLOCK_GAP - GRID_PANEL_PAD * 2.0
	var grid_h: float = clampf(grid_h_want, 240.0, maxf(240.0, grid_h_max))

	# 픽창 한 덩이(패딩 + 순서 띠 + 탭 + 격자)를 가운데 띠에서 세로 가운데에
	# 놓는다 — 4.5줄이 남는 공간보다 짧으면 위아래로 같은 만큼씩 여백이 생겨야
	# 판이 어느 한쪽에 붙어 보이지 않는다.
	var group_h: float = GRID_PANEL_PAD * 2.0 + PIPS_ROW_H + TABS_H + BLOCK_GAP + grid_h
	var group_y: float = band_top + maxf(0.0, (band_h - group_h) * 0.5)
	var pips_mid_y: float = group_y + GRID_PANEL_PAD + PIPS_ROW_H * 0.5
	var tabs_y: float = group_y + GRID_PANEL_PAD + PIPS_ROW_H
	var grid_y: float = tabs_y + TABS_H + BLOCK_GAP

	var body_h: float = OutgameTheme.bottom_bar_top()
	var gather_h: float = block_h + GATHER_GAP + assign_block_h
	var gather_y: float = maxf(TOP_PAD, (body_h - gather_h) * 0.5)

	_lay = {
		"w": w, "h": h, "strip_w": strip_w,
		"cell_w": cell_w, "portrait_w": portrait_w, "portrait_h": portrait_h,
		"mech_h": mech_h, "block_h": block_h, "assign_block_h": assign_block_h,
		"assign_portrait_h": assign_portrait_h,
		"pips_mid_y": pips_mid_y,
		"top_block_y": top_block_y,
		"group_y": group_y, "group_h": group_h,
		"tabs_y": tabs_y,
		"grid_y": grid_y, "grid_h": grid_h, "grid_bottom": grid_y + grid_h,
		"content_w": content_w, "gcell_w": gcell_w, "gcell_h": gcell_h,
		"bot_block_y": bot_block_y,
		"assign_block_y": h - BOT_PAD - assign_block_h,
		# 배정 단계에서 두 블록이 모이는 자리 — 하단 바 위의 본문 세로 가운데.
		"gather_enemy_y": gather_y,
		"gather_player_y": gather_y + block_h + GATHER_GAP,
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

	_build_team_block(_other_side(_player_side), true)
	_build_grid_bg()
	_build_pips()
	_build_filter_tabs()
	_build_grid()
	_build_team_block(_player_side, false)

	# 배너는 판 **바깥**(같은 캔버스, 판보다 뒤에 붙인다)에 선다 — 판 안에 두면
	# 나중에 붙는 시트가 그 위를 덮는다.
	_banner_root = Control.new()
	_banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_root.position = Vector2.ZERO
	_banner_root.size = ScreenMetrics.viewport_size()
	_mf.canvas.add_child(_banner_root)


## 메크 정사각 초상화. `MechImages.portrait_for` 가 이미 256² 로 구워진 파일을
## 돌려주므로 예전처럼 1024² 전신 아트를 격자 크기로 다시 굽지 않는다 — 그
## 굽는 단계(`_bake_thumbs` / `THUMB_PX`)는 삭제됐다.
func _mech_thumb(mech_id: int) -> Texture2D:
	if not _thumbs.has(mech_id):
		_thumbs[mech_id] = MechImages.portrait_for(mech_id)
	return _thumbs[mech_id] as Texture2D


# ── 순서 표시 줄 ─────────────────────────────────────────────────────────────
## 열네 칸이 픽창 맨 위(역할군 필터 바로 위)에 한 줄로 선다. 칸 색은 그 수의
## 진영색이고 지난 수는 옅게, 남은 수는 더 옅게, **지금 수는 진하고 두껍게**
## 그 안에 밴(X) / 픽(V) 아이콘을 품는다. 지금 칸 위나 아래의 삼각형이 그 수를
## 두는 쪽을 가리킨다(`_refresh_pips`).
func _build_pips() -> void:
	var mid_y: float = _lay["pips_mid_y"]
	var w: float = _lay["w"]
	# 캡슐 안의 이음매에는 틈이 없다 — 틈은 캡슐과 캡슐 사이에만 선다.
	var n: int = SEQUENCE.size()
	var total: float = float(n) * PIP_W
	for i in range(n - 1):
		if not _same_run(i, i + 1):
			total += PIP_GAP
	var x: float = (w - total) * 0.5
	_pips_root = Control.new()
	_pips_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_pips_root)
	for i in range(n):
		var joined_left: bool = i > 0 and _same_run(i - 1, i)
		var joined_right: bool = i < n - 1 and _same_run(i, i + 1)
		var sty := OutgameTheme.flat_style(Color.WHITE, 6)
		# 캡슐의 바깥 모서리만 둥글다 — 안쪽까지 둥글면 붙은 두 칸 사이에 홈이
		# 패여 다시 두 개로 갈라져 보인다.
		if joined_left:
			sty.corner_radius_top_left = 0
			sty.corner_radius_bottom_left = 0
		if joined_right:
			sty.corner_radius_top_right = 0
			sty.corner_radius_bottom_right = 0
		var pip := Panel.new()
		pip.add_theme_stylebox_override("panel", sty)
		pip.position = Vector2(x, mid_y - PIP_H * 0.5)
		pip.size = Vector2(PIP_W, PIP_H)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pips_root.add_child(pip)
		_seq_pips.append(pip)
		x += PIP_W + (0.0 if joined_right else PIP_GAP)
	# 구분선은 칸들보다 **나중에** 붙인다 — 형제 순서가 곧 그리는 순서라 먼저
	# 붙이면 칸이 선을 덮는다.
	for i in range(n - 1):
		if not _same_run(i, i + 1):
			continue
		var line := ColorRect.new()
		line.color = OutgameTheme.SURFACE
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.position = Vector2((_seq_pips[i + 1] as Panel).position.x - PIP_DIVIDER_W * 0.5,
				mid_y - PIP_H * 0.5)
		line.size = Vector2(PIP_DIVIDER_W, PIP_H)
		_pips_root.add_child(line)
		_seq_dividers.append({"line": line, "idx": i})

	_pip_icon = TextureRect.new()
	_pip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pip_icon.size = Vector2(PIP_ICON, PIP_ICON)
	_pip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip_icon.visible = false
	_pips_root.add_child(_pip_icon)

	_turn_arrow = TextureRect.new()
	_turn_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_turn_arrow.stretch_mode = TextureRect.STRETCH_SCALE
	_turn_arrow.texture = ICON_ARROW
	_turn_arrow.size = Vector2(TURN_ARROW_W, TURN_ARROW_H)
	_turn_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_arrow.visible = false
	_pips_root.add_child(_turn_arrow)


## 순서 줄을 `_action_idx` 에 맞춘다. 지금 칸은 두께가 트윈으로 자라고(다른 칸은
## 즉시 얇아진다), 아이콘과 삼각형이 그 칸으로 옮겨 간다.
func _refresh_pips() -> void:
	if _pips_root == null:
		return
	var mid_y: float = _lay["pips_mid_y"]
	if _pip_tween != null and _pip_tween.is_valid():
		_pip_tween.kill()
	# 지금 수가 속한 캡슐은 **통째로** 두꺼워진다 — 한 칸만 두꺼우면 붙어 있던
	# 캡슐이 계단처럼 어긋난다. 그 안에서 지금 칸을 가르는 것은 색 · 맥박 · 아이콘.
	var run: Vector2i = _seq_run(_action_idx) if _action_idx < _seq_pips.size() \
			else Vector2i(-1, -2)
	_pip_tween = create_tween().set_parallel()
	# 빈 트윈은 시작하자마자 오류를 낸다 — 아이콘 페이드가 언제나 하나는 얹히지만
	# 마지막 수 뒤에는 그것도 없으므로 그 경로에서는 곧장 걷는다(아래).
	for i in range(_seq_pips.size()):
		var pip := _seq_pips[i] as Panel
		var sty := pip.get_theme_stylebox("panel") as StyleBoxFlat
		var in_run: bool = i >= run.x and i <= run.y
		var state: int = 1 if i < _action_idx else (2 if i == _action_idx else 0)
		if state == 0 and in_run:
			state = 3
		sty.bg_color = _seq_color(i, state)
		pip.modulate = Color.WHITE
		if not in_run:
			pip.size = Vector2(PIP_W, PIP_H)
			pip.position.y = mid_y - PIP_H * 0.5
		elif not is_equal_approx(pip.size.y, PIP_ACTIVE_H):
			_pip_tween.tween_property(pip, "size", Vector2(PIP_W, PIP_ACTIVE_H), PIP_GROW_SEC) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			_pip_tween.tween_property(pip, "position:y", mid_y - PIP_ACTIVE_H * 0.5, PIP_GROW_SEC) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	for raw in _seq_dividers:
		var d := raw as Dictionary
		var line := d["line"] as ColorRect
		var idx: int = int(d["idx"])
		var h: float = PIP_ACTIVE_H if idx >= run.x and idx < run.y else PIP_H
		if h == PIP_ACTIVE_H and not is_equal_approx(line.size.y, h):
			_pip_tween.tween_property(line, "size:y", h, PIP_GROW_SEC) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			_pip_tween.tween_property(line, "position:y", mid_y - h * 0.5, PIP_GROW_SEC) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif h == PIP_H:
			line.size.y = h
			line.position.y = mid_y - h * 0.5
	if _action_idx >= _seq_pips.size():
		_pip_tween.kill()
		_pip_icon.visible = false
		_turn_arrow.visible = false
		return

	var cur := _seq_pips[_action_idx] as Panel
	var cx: float = cur.position.x + PIP_W * 0.5
	_pulse_t = 0.0

	_pip_icon.texture = ICON_BAN if _current_kind() == ACTION_BAN else ICON_PICK
	_pip_icon.position = Vector2(cx - PIP_ICON * 0.5, mid_y - PIP_ICON * 0.5)
	_pip_icon.visible = true
	_pip_icon.modulate = Color(1, 1, 1, 0)
	_pip_tween.tween_property(_pip_icon, "modulate", Color.WHITE, PIP_GROW_SEC)

	# 내 차례 = 칸 아래에서 아래를(우리 팀 블록), 상대 차례 = 칸 위에서 위를.
	var mine: bool = _is_player_turn()
	_arrow_dir = 1.0 if mine else -1.0
	_turn_arrow.flip_v = not mine
	_turn_arrow.modulate = _seq_color(_action_idx, 2)
	_arrow_base_y = (mid_y + PIP_ACTIVE_H * 0.5 + TURN_ARROW_GAP) if mine \
			else (mid_y - PIP_ACTIVE_H * 0.5 - TURN_ARROW_GAP - TURN_ARROW_H)
	_turn_arrow.position = Vector2(cx - TURN_ARROW_W * 0.5, _arrow_base_y)
	_turn_arrow.visible = true
	_arrow_t = 0.0


## 삼각형이 가리키는 쪽으로 천천히 나갔다 돌아온다 — (1 − cos) / 2 라 양 끝에서
## 느려지고, 출발점이 곧 기본 자리라 칸이 바뀐 순간 튀지 않는다.
func _process(delta: float) -> void:
	if _turn_arrow == null or not is_instance_valid(_turn_arrow) or not _turn_arrow.visible:
		return
	# 지금 칸의 맥박 — 캡슐로 붙은 수에서 "그중 몇 번째인가"를 말한다.
	if _action_idx < _seq_pips.size():
		_pulse_t = fmod(_pulse_t + delta, PIP_PULSE_SEC)
		var p: float = (1.0 - cos(TAU * _pulse_t / PIP_PULSE_SEC)) * 0.5
		(_seq_pips[_action_idx] as Panel).modulate = Color(1, 1, 1, 1.0 - PIP_PULSE_DEPTH * p)
	_arrow_t = fmod(_arrow_t + delta, TURN_ARROW_BOB_SEC)
	var k: float = (1.0 - cos(TAU * _arrow_t / TURN_ARROW_BOB_SEC)) * 0.5
	_turn_arrow.position.y = _arrow_base_y + _arrow_dir * TURN_ARROW_BOB_PX * k


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
		var slot: Dictionary = _build_mech_slot(holder,
				Vector2(cx - pw * 0.5, mech_y), Vector2(pw, mh), side_col, side, i)
		# 아군 메크 칸은 **밴픽 중에도** 끌어 다른 선수 자리로 옮길 수 있다 —
		# 누구에게 태울지를 다 고른 뒤에야 정하라고 하면, 고르는 동안 머릿속에만
		# 있던 배치를 마지막에 다시 세워야 한다.
		if side == _player_side:
			_bind_slot_drag(slot)
		slots.append(slot)

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
	back.color = SLOT_EMPTY_COLOR
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
	_build_portrait_quirk_badge(holder, side, p, pos, sz)

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


## Quirk badge on my pilot's portrait (bottom-right): `기벽 n` filled with the
## colour of that pilot's highest quirk grade (§14, T1). Nothing when the pilot
## has no quirk, for the enemy, or outside a run.
func _build_portrait_quirk_badge(holder: Control, side: int, p: PlayerData,
		pos: Vector2, sz: Vector2) -> void:
	if not _quirk_on or side != _player_side or p == null:
		return
	var ids: Array = QuirkSystem.quirks_of(_gm.season_state, p.id)
	if ids.is_empty():
		return
	var top: int = 0
	for id in ids:
		top = maxi(top, int(QuirkSystem.row(int(id)).get("grade", 0)))
	var bw: float = minf(sz.x - 8.0, 86.0)
	OutgameTheme.add_chip(holder, "기벽 %d" % ids.size(),
			pos + Vector2(sz.x - bw - 4.0, sz.y - 30.0), Vector2(bw, 26.0),
			QuirkSystem.grade_color(top), OutgameTheme.TEXT_ON_FILL, 16)


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
	sb.bg_color = SLOT_EMPTY_COLOR
	sb.border_color = OutgameTheme.BORDER
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
	sb.bg_color = SLOT_EMPTY_COLOR
	sb.border_color = side_col.lerp(OutgameTheme.SURFACE, 0.55)
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

	# Mastery tag (top-left) — "<tier> <bonus>" of the pilot sitting on this seat
	# with this mech. Filled by `_refresh_side_block`; hidden without mastery.
	var mtag := Panel.new()
	mtag.position = Vector2(4.0, 4.0)
	mtag.size = Vector2(minf(sz.x - 8.0, 104.0), 28.0)
	mtag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mtag.visible = false
	frame.add_child(mtag)
	var mtag_lbl := UiHelpers.mk_label(mtag, "", 17, OutgameTheme.TEXT_ON_FILL,
			Vector2.ZERO, mtag.size, HORIZONTAL_ALIGNMENT_CENTER)
	mtag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mtag_lbl.clip_text = true

	# Quirk tag (under the mastery tag) — "기벽 +N", my seats only (§14, T1).
	var qtag := Panel.new()
	qtag.position = Vector2(4.0, 36.0)
	qtag.size = Vector2(minf(sz.x - 8.0, 104.0), 28.0)
	qtag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qtag.visible = false
	qtag.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(QuirkSystem.grade_color(2), 8))
	frame.add_child(qtag)
	var qtag_lbl := UiHelpers.mk_label(qtag, "", 17, OutgameTheme.TEXT_ON_FILL,
			Vector2.ZERO, qtag.size, HORIZONTAL_ALIGNMENT_CENTER)
	qtag_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qtag_lbl.clip_text = true

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
			"style": sb, "side_col": side_col, "seat": seat, "pos": pos,
			"mtag": mtag, "mtag_lbl": mtag_lbl, "qtag": qtag, "qtag_lbl": qtag_lbl}


# ── 픽창 배경판 ──────────────────────────────────────────────────────────────
## 필터 탭과 격자를 함께 덮는 짙은 판. 이 판 하나가 "여기가 고르는 곳"과
## "여기는 양 팀 상황"을 가른다.
func _build_grid_bg() -> void:
	_grid_bg = Panel.new()
	_grid_bg.position = Vector2(SIDE_MARGIN, _lay["group_y"])
	_grid_bg.size = Vector2(_lay["strip_w"], _lay["group_h"])
	_grid_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_bg.add_theme_stylebox_override("panel", OutgameTheme.card_style(16))
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
		btn.add_theme_color_override("font_color", OutgameTheme.ACCENT_TEXT if on else TEXT_DIM)
		btn.add_theme_color_override("font_hover_color", OutgameTheme.ACCENT_TEXT if on else OutgameTheme.TEXT)
		btn.add_theme_color_override("font_pressed_color", OutgameTheme.ACCENT_TEXT)
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, _tab_style(on))


func _tab_style(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = OutgameTheme.ACCENT_DIM if on else PANEL_COLOR
	sb.border_color = ACCENT if on else OutgameTheme.BORDER
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
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`). 메크 칸을 누른 채 끌기 시작하면
	# 그 눌림은 취소되므로 스크롤하려던 손이 메크를 고르지 않는다.
	DragScroll.attach(_scroll)

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

	var nm := UiHelpers.mk_label(btn, m.name, 20, OutgameTheme.TEXT,
			Vector2(pad, pad + art_sz + 1.0), Vector2(cw - pad * 2.0, CELL_NAME_H - 2.0),
			HORIZONTAL_ALIGNMENT_CENTER)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Mastery / analysis markers (filled by `_refresh_grid_cells`, hidden by
	# default): top-right = enemy likely pick / analyst ban, bottom-left = my
	# rider's tier when it is 능숙 or better.
	var mark_w: float = minf(84.0, art_sz * 0.48)
	var intel := _mk_cell_tag(btn, Vector2(pad + art_sz - 4.0 - mark_w, pad + 4.0),
			Vector2(mark_w, 28.0))
	var mine := _mk_cell_tag(btn, Vector2(pad + 4.0, pad + art_sz - 32.0),
			Vector2(mark_w, 28.0))

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

	return {"btn": btn, "art": art, "veil": veil, "tag": tag, "mech": m,
			"intel": intel, "mine": mine}


## A small filled tag on a grid cell (`{panel, label}`), hidden until set.
func _mk_cell_tag(parent: Control, pos: Vector2, sz: Vector2) -> Dictionary:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	parent.add_child(p)
	var l := UiHelpers.mk_label(p, "", 17, OutgameTheme.TEXT_ON_FILL,
			Vector2.ZERO, sz, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return {"panel": p, "label": l}


func _set_cell_tag(tag: Dictionary, text: String, bg: Color) -> void:
	var p := tag["panel"] as Panel
	p.visible = text != ""
	if text == "":
		return
	p.add_theme_stylebox_override("panel", OutgameTheme.flat_style(bg, 8))
	(tag["label"] as Label).text = text


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
	sb.border_color = ACCENT if selected else OutgameTheme.BORDER
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
	_sheet_dim.color = SHEET_DIM_COLOR
	_sheet_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheet_dim.gui_input.connect(_on_dim_input)
	_panel.add_child(_sheet_dim)

	var sh: float = _lay["sheet_h"]
	var sw: float = _lay["strip_w"]
	_sheet = Panel.new()
	_sheet.position = Vector2(SIDE_MARGIN, _lay["grid_bottom"] - sh)
	_sheet.size = Vector2(sw, sh)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := OutgameTheme.card_style(18)
	sb.border_color = ACCENT
	sb.set_border_width_all(3)
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
		ph.color = SLOT_EMPTY_COLOR
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
	var nm := UiHelpers.mk_label(_sheet, m.name, 38, OutgameTheme.TEXT,
			Vector2(rx, y), Vector2(rw, 48.0))
	nm.clip_text = true
	y += 52.0

	var role_txt: String = String(ROLE_NAMES[m.role]) if m.role >= 0 and m.role < ROLE_NAMES.size() else "—"
	var st := UiHelpers.mk_label(_sheet,
			"%s   ·   HP %d   ·   ATK %d   ·   존재감 %d" % [role_txt, m.hp, m.atk, m.presence],
			24, OutgameTheme.TEXT_SUB, Vector2(rx, y), Vector2(rw, 34.0))
	st.clip_text = true
	y += 42.0

	var pas: Dictionary = _gm.mech_passive_def(m.id)
	if pas.is_empty():
		UiHelpers.mk_label(_sheet, "패시브 없음", 24, OutgameTheme.TEXT_FAINT,
				Vector2(rx, y), Vector2(rw, 32.0))
	else:
		var kw: String = String(pas.get("keyword", ""))
		var head: String = "◆ %s" % String(pas["name"])
		if kw != "":
			head += "   [%s]" % kw
		var hl := UiHelpers.mk_label(_sheet, head, 26, OutgameTheme.ACCENT_TEXT,
				Vector2(rx, y), Vector2(rw, 34.0))
		hl.clip_text = true
		y += 38.0
		var desc := Label.new()
		desc.text = String(pas.get("description", ""))
		desc.add_theme_font_size_override("font_size", 20)
		desc.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(rx, y)
		desc.size = Vector2(rw, 128.0)
		desc.clip_text = true
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sheet.add_child(desc)

	# ── 카드 셋 ── (오른쪽 칸에서 이어진다 — 왼쪽은 아트 한 장이 통째로 쓴다)
	var cy: float = SHEET_PAD + 250.0
	var defs: Array = _gm.mech_cards_for(m.id)
	UiHelpers.mk_label(_sheet, "메크 카드  %d종   ·   카드를 누르면 설명" % defs.size(), 22,
			OutgameTheme.TEXT_SUB, Vector2(rx, cy), Vector2(rw, 28.0))
	cy += 32.0
	_build_card_row(defs, cy, rx, rw)

	# ── 버튼 ──
	var by: float = sh - SHEET_PAD - SHEET_BTN_H
	var close_btn := Button.new()
	close_btn.text = "닫기"
	OutgameTheme.style_ghost_button(close_btn, 26)
	close_btn.position = Vector2(sw - SHEET_PAD - 340.0 - 12.0 - 190.0, by)
	close_btn.size = Vector2(190.0, SHEET_BTN_H)
	close_btn.pressed.connect(_close_sheet)
	_sheet.add_child(close_btn)

	_sheet_confirm = Button.new()
	OutgameTheme.style_primary_button(_sheet_confirm, 28)
	_sheet_confirm.position = Vector2(sw - SHEET_PAD - 340.0, by)
	_sheet_confirm.size = Vector2(340.0, SHEET_BTN_H)
	_sheet_confirm.pressed.connect(_on_confirm_pressed)
	_sheet.add_child(_sheet_confirm)
	_refresh_sheet_confirm()
	_build_sheet_mastery(m, Vector2(SHEET_PAD, by),
			Vector2(close_btn.position.x - 12.0 - SHEET_PAD, SHEET_BTN_H))


## Left of the sheet buttons (under the art): my natural rider's mastery with
## this mech, and what analysis knows about the enemy wanting it.
func _build_sheet_mastery(m: MechData, pos: Vector2, sz: Vector2) -> void:
	if not _mastery_on:
		return
	var rider: PlayerData = _rider_for(_player_side, m)
	if rider != null:
		var v: int = _mastery(rider, m.id)
		var t: int = MechMastery.tier_of(v)
		var qt: int = _quirk_total(_player_side, rider, m.id)
		var l1 := UiHelpers.mk_label(_sheet, "%s  %s %d  (스탯 %s%s)" % [
				rider.name, MechMastery.tier_name(t), v, MechMastery.bonus_text(t),
				(" · 기벽 +%d" % qt) if qt > 0 else ""],
				21, MechMastery.tier_color(t), pos, Vector2(sz.x, sz.y * 0.5))
		l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l1.clip_text = true
	var intel: String = ""
	if m.id in _analyst_bans():
		intel = "분석가 추천 밴 — %s 의 주력" % String((_enemy_likely[m.id] as Dictionary)["pilot"])
	elif _show_enemy_likely and _enemy_likely.has(m.id):
		intel = "상대 예상 픽 — %s" % String((_enemy_likely[m.id] as Dictionary)["pilot"])
	if intel != "":
		var l2 := UiHelpers.mk_label(_sheet, intel, 19,
				OutgameTheme.ACCENT_TEXT if m.id in _analyst_bans() else RED_COLOR,
				pos + Vector2(0.0, sz.y * 0.5), Vector2(sz.x, sz.y * 0.5))
		l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l2.clip_text = true


## 메크 카드들을 손패와 **같은 노드**(`Card.tscn`)로 늘어놓는다 — 따로 그린
## 그림이면 실제로 덱에 들어갈 카드와 같은 것인지 확인할 길이 없다.
## `rx` / `rw` 는 오른쪽 칸의 왼쪽 끝과 폭이다 — 시트 전체 폭으로 가운데를
## 잡으면 카드 줄이 왼쪽 아트 위로 밀려 들어간다.
func _build_card_row(defs: Array, y: float, rx: float, rw: float) -> void:
	if defs.is_empty():
		UiHelpers.mk_label(_sheet, "이 기체에는 고유 카드가 없다", 20,
				OutgameTheme.TEXT_FAINT, Vector2(rx, y), Vector2(rw, 30.0))
		return
	var cw: float = Card.CARD_W * SHEET_CARD_SCALE
	var chh: float = Card.CARD_H * SHEET_CARD_SCALE
	var row_w: float = float(defs.size()) * cw + float(defs.size() - 1) * SHEET_CARD_GAP
	var x0: float = rx + maxf(0.0, (rw - row_w) * 0.5)
	for i in range(defs.size()):
		var def: Dictionary = defs[i]
		var node := CARD_SCENE.instantiate() as Card
		# add_child 를 setup 보다 **먼저** — Card.gd 의 @onready 참조는 트리에
		# 들어간 뒤에야 풀린다(CardPileViewer / PilotDetailPanel 과 같은 순서).
		_sheet.add_child(node)
		node.setup(CardData.from_def(def), false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = Vector2.ZERO
		node.scale = Vector2(SHEET_CARD_SCALE, SHEET_CARD_SCALE)
		node.position = Vector2(x0 + float(i) * (cw + SHEET_CARD_GAP), y)
		# 카드 앞면에는 설명문이 없다 — 누르면 카드 줄 **위쪽**에 설명판이 뜬다
		# (같은 카드를 다시 누르면 닫힌다).
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.modulate = Color(1, 1, 1, 0)
		hit.position = node.position
		hit.size = Vector2(cw, chh)
		hit.pressed.connect(_toggle_sheet_desc.bind(i, node, y, rx, rw))
		_sheet.add_child(hit)

		# 장수 배지 — `count = 0` 인 카드는 덱에 처음부터 들어가지 않고 패시브나
		# 다른 카드가 만들어 줄 때만 세상에 나온다. 그 사정을 적어 두지 않으면
		# "왜 이 카드가 손에 안 들어오나"가 화면 어디에도 없다.
		var cnt: int = int(def.get("count", 0))
		var badge := UiHelpers.mk_label(_sheet,
				("×%d" % cnt) if cnt > 0 else "생성 전용",
				18, OutgameTheme.TEXT if cnt > 0 else OutgameTheme.LINK,
				Vector2(x0 + float(i) * (cw + SHEET_CARD_GAP), y + chh + 2.0),
				Vector2(cw, 24.0), HORIZONTAL_ALIGNMENT_CENTER)
		badge.clip_text = true


## 시트 카드의 설명판. 폭은 오른쪽 칸 폭 그대로, 아랫변이 카드 줄 윗단에서
## `SHEET_DESC_GAP` 위다 — 패시브 설명을 잠시 덮지만, 카드를 누른 손이 보려는
## 것은 지금 그 카드다. 시트가 닫히면 시트의 자식이라 함께 사라진다.
func _toggle_sheet_desc(idx: int, node: Card, row_y: float, rx: float, rw: float) -> void:
	var same: bool = idx == _sheet_desc_idx
	if _sheet_desc != null and is_instance_valid(_sheet_desc):
		_sheet_desc.queue_free()
	_sheet_desc = null
	_sheet_desc_idx = -1
	if same or _sheet == null or node == null or not is_instance_valid(node):
		return
	_sheet_desc = CardDescBox.build(node.data, rw, true)
	_sheet.add_child(_sheet_desc)
	_sheet_desc.position = Vector2(rx,
			maxf(SHEET_PAD, row_y - SHEET_DESC_GAP - _sheet_desc.size.y))
	_sheet_desc_idx = idx


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
	_sheet_desc = null       # 시트의 자식이라 시트와 함께 해제된다
	_sheet_desc_idx = -1
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
	var rec_bans: Array = _analyst_bans()
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
		_refresh_cell_marks(cell, mid, rec_bans)


## Mastery / analysis tags of one grid cell. Taken (banned / picked) cells show
## none — the slab already says everything.
func _refresh_cell_marks(cell: Dictionary, mid: int, rec_bans: Array) -> void:
	if not cell.has("intel"):
		return
	var available: bool = _is_legal(mid)
	var intel_txt: String = ""
	var intel_col: Color = OutgameTheme.ACCENT
	if available and mid in rec_bans:
		intel_txt = "추천 밴"
	elif available and _show_enemy_likely and _enemy_likely.has(mid):
		intel_txt = "예상 픽"
		intel_col = RED_COLOR
	_set_cell_tag(cell["intel"], intel_txt, intel_col)
	var mine_txt: String = ""
	var t: int = 0
	if available and _mastery_on:
		t = MechMastery.tier_of(_mastery(_rider_for(_player_side, cell["mech"] as MechData), mid))
		if t >= 2:
			mine_txt = MechMastery.tier_name(t)
	_set_cell_tag(cell["mine"], mine_txt, MechMastery.tier_color(t))


## 칸 테두리 — 내가 시트로 열어 본 칸은 앰버, **상대가 집어 보고 있는 칸**은
## 상대 진영색으로 두껍게. 둘이 같은 칸이면 상대 쪽이 이긴다(지금 움직이는 손은
## 그쪽이다).
func _refresh_cell_selection() -> void:
	var ai_col: Color = BLUE_COLOR if _other_side(_player_side) == GameEnums.DraftSide.BLUE \
			else RED_COLOR
	for id in _cells.keys():
		var btn := (_cells[id] as Dictionary)["btn"] as Button
		var sty: StyleBoxFlat
		if int(id) == _ai_hover_id:
			sty = _cell_style(true)
			sty.border_color = ai_col
			sty.set_border_width_all(5)
		else:
			sty = _cell_style(int(id) == _selected_mech_id)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(st, sty)


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
		art.modulate = BAN_TINT
		if i < bans.size():
			art.texture = _mech_thumb(int(bans[i]))
			x_lbl.text = "✕"
		else:
			art.texture = null
			x_lbl.text = ""
	# 상대가 밴을 집어 보는 중이면 다음 칩에 흐린 미리보기.
	var hover_slot: int = _ai_hover_slot(side, ACTION_BAN)
	if hover_slot >= 0 and hover_slot < chips.size():
		var hchip: Dictionary = chips[hover_slot]
		(hchip["art"] as TextureRect).texture = _mech_thumb(_ai_hover_id)
		(hchip["art"] as TextureRect).modulate = Color(1, 1, 1, 0.45)

	# 칸의 내용은 언제나 자리표다 — 아군 칸은 밴픽 중에도 옮겨지므로 픽 순서를
	# 그대로 읽으면 옮긴 자리가 다음 갱신에 되돌아간다.
	var ids: Array = _seat_mechs.get(side, [])
	var slots: Array = ui["mech_slots"]
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var sty := slot["style"] as StyleBoxFlat
		var side_col: Color = slot["side_col"]
		var nm := slot["name"] as Label
		var band := slot["band"] as ColorRect
		var art := slot["art"] as TextureRect
		art.modulate = Color.WHITE
		if i < ids.size() and int(ids[i]) >= 0:
			var mid: int = int(ids[i])
			var m := _find_mech(mid)
			art.texture = _mech_thumb(mid)
			nm.text = m.name if m != null else "?"
			band.visible = true
			sty.bg_color = side_col.lerp(OutgameTheme.SURFACE, 0.75)
			sty.border_color = side_col
		elif i == _ai_hover_slot(side, ACTION_PICK):
			# 상대가 집어 보는 기체 — 다음 칸에 흐리게, 테두리는 진영색.
			var hm := _find_mech(_ai_hover_id)
			art.texture = _mech_thumb(_ai_hover_id)
			art.modulate = Color(1, 1, 1, 0.45)
			nm.text = hm.name if hm != null else ""
			band.visible = true
			sty.bg_color = SLOT_EMPTY_COLOR
			sty.border_color = side_col
		else:
			art.texture = null
			nm.text = ""
			band.visible = false
			sty.bg_color = SLOT_EMPTY_COLOR
			sty.border_color = side_col.lerp(OutgameTheme.SURFACE, 0.55)
		_refresh_slot_mastery(side, slot, int(ids[i]) if i < ids.size() else -1)
		_refresh_slot_quirk(side, slot, int(ids[i]) if i < ids.size() else -1)


## The seat's mastery tag: my seats always (the slot row is "the mech of the
## pilot above it" from the first pick), enemy seats only once analysis reveals
## mastery and the enemy mechs are re-seated by pilot in the assign step.
func _refresh_slot_mastery(side: int, slot: Dictionary, mech_id: int) -> void:
	var tag := slot.get("mtag", null) as Panel
	if tag == null:
		return
	var wanted: bool = _mastery_on and mech_id >= 0 \
			and (side == _player_side or (_show_enemy_likely and _enemy_seated))
	var pd: PlayerData = _pilot_at(side, int(slot["seat"])) if wanted else null
	if pd == null:
		tag.visible = false
		return
	var t: int = MechMastery.tier_of(_mastery(pd, mech_id))
	tag.visible = true
	tag.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(MechMastery.tier_color(t), 8))
	(slot["mtag_lbl"] as Label).text = "%s %s" % [MechMastery.tier_name(t), MechMastery.bonus_text(t)]


## The seat's quirk tag `기벽 +N` — total quirk stat bonus of my pilot on that
## seat riding that mech (conditional quirks follow the mech, so dragging a slot
## updates it). Hidden for enemy seats, empty seats and a 0 total.
func _refresh_slot_quirk(side: int, slot: Dictionary, mech_id: int) -> void:
	var tag := slot.get("qtag", null) as Panel
	if tag == null:
		return
	var total: int = 0
	if mech_id >= 0:
		total = _quirk_total(side, _pilot_at(side, int(slot["seat"])), mech_id)
	tag.visible = total > 0
	if total > 0:
		(slot["qtag_lbl"] as Label).text = "기벽 +%d" % total


## 상대가 지금 집어 보는 기체가 `side` 블록의 몇 번째 칸(밴 칩 / 픽 슬롯)에
## 미리보기로 앉는가. 지금 수가 그 쪽의 그 종류가 아니면 -1.
func _ai_hover_slot(side: int, kind: int) -> int:
	if _ai_hover_id < 0 or _assign_mode or _action_idx >= SEQUENCE.size():
		return -1
	if int(SEQUENCE[_action_idx][0]) != side or _current_kind() != kind:
		return -1
	return (_side_bans.get(side, []) as Array).size() if kind == ACTION_BAN \
			else _first_empty_seat(side)


func _seq_color(idx: int, state: int) -> Color:
	# state: 0=upcoming, 1=done, 2=current, 3=지금 캡슐 안의 다음 수
	var side: int = SEQUENCE[idx][0]
	var base: Color = BLUE_COLOR if side == GameEnums.DraftSide.BLUE else RED_COLOR
	# 흰 바탕이라 **진할수록 지금**이다 — 지난 수는 반쯤, 남은 수는 거의 바탕색.
	# 지금 캡슐의 다음 수는 그 사이 — 곧 이어질 수라 남은 수보다는 진하다.
	if state == 1: return base.lerp(OutgameTheme.SURFACE, 0.45)
	if state == 2: return base
	if state == 3: return base.lerp(OutgameTheme.SURFACE, 0.60)
	return base.lerp(OutgameTheme.SURFACE, 0.80)


## 두 수가 같은 팀의 같은 행동인가 — 순서 줄의 캡슐과 차례 배너가 함께 읽는다.
func _same_run(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= SEQUENCE.size() or b >= SEQUENCE.size():
		return false
	return int(SEQUENCE[a][0]) == int(SEQUENCE[b][0]) \
			and int(SEQUENCE[a][1]) == int(SEQUENCE[b][1])


## `idx` 가 속한 캡슐의 첫 수 · 끝 수(x..y). 홀로 선 수면 x == y == idx.
func _seq_run(idx: int) -> Vector2i:
	var a: int = idx
	while _same_run(a - 1, a):
		a -= 1
	var b: int = idx
	while _same_run(b, b + 1):
		b += 1
	return Vector2i(a, b)


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
	await get_tree().create_timer(BANNER_IN_SEC + BANNER_HOLD_SEC).timeout
	if _action_idx != my_idx or _panel == null:
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
		if _action_idx != my_idx or _panel == null:
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
## (인게임 `HudBuilder.play_turn_announce` 와 같은 모양). 입력은 막지 않고,
## 다음 수가 먼저 오면 이전 배너를 걷고 새로 뜬다(`_banner_gen`).
func _play_turn_banner() -> void:
	if _banner_root == null or _action_idx >= SEQUENCE.size():
		return
	# 같은 팀이 같은 행동을 이어서 하는 수에는 띠를 다시 띄우지 않는다 — 말할
	# 것(누구의 · 무엇)이 바로 앞 수와 같다. 그 이어짐은 순서 줄의 캡슐이 말한다.
	if _same_run(_action_idx - 1, _action_idx):
		return
	_clear_banner()
	_banner_gen += 1
	var gen: int = _banner_gen
	var mine: bool = _is_player_turn()
	var msg: String = "%s %s" % ["내 차례" if mine else "상대 차례",
			"밴" if _current_kind() == ACTION_BAN else "픽"]
	var side_col: Color = _seq_color(_action_idx, 2)
	var vp: Vector2 = ScreenMetrics.viewport_size()
	var y: float = vp.y * 0.5 - BANNER_H * 0.5

	var bar := ColorRect.new()
	bar.color = Color(side_col.r, side_col.g, side_col.b, 0.92)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(vp.x * 0.5, y)
	bar.size = Vector2(0.0, BANNER_H)
	_banner_root.add_child(bar)

	var lbl := UiHelpers.mk_label(_banner_root, msg, BANNER_FONT, OutgameTheme.TEXT_ON_FILL,
			Vector2(0.0, y), Vector2(vp.x, BANNER_H), HORIZONTAL_ALIGNMENT_CENTER)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.modulate = Color(1, 1, 1, 0)

	var tw := create_tween().set_parallel()
	_banner_tween = tw
	tw.tween_property(bar, "size:x", vp.x, BANNER_IN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(bar, "position:x", 0.0, BANNER_IN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(lbl, "modulate", Color.WHITE, BANNER_IN_SEC)
	tw.chain().tween_interval(BANNER_HOLD_SEC)
	tw.chain().tween_property(bar, "modulate", Color(1, 1, 1, 0), BANNER_OUT_SEC)
	tw.parallel().tween_property(lbl, "modulate", Color(1, 1, 1, 0), BANNER_OUT_SEC)
	tw.chain().tween_callback(func() -> void:
		if gen == _banner_gen:
			_clear_banner(false))


func _clear_banner(kill_tween: bool = true) -> void:
	if kill_tween and _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = null
	if _banner_root == null or not is_instance_valid(_banner_root):
		return
	for c in _banner_root.get_children():
		c.queue_free()


# ── 배정 단계 ────────────────────────────────────────────────────────────────
## 픽창을 걷어 내고 아군 블록을 **배정판**으로 다시 세운다. 화면이 바뀌지 않는
## 것이 요점이다 — 방금 고른 열 대가 그 자리에 그대로 있어야 "누가 뭘 탈지"를
## 그 그림 위에서 정할 수 있다.
func _enter_assign_mode() -> void:
	_assign_mode = true
	_close_sheet()
	# 끌던 칸이 있으면 놓게 한다 — 아군 블록을 새로 세우므로 손에 든 칸의
	# 원래 자리가 사라진다.
	_cancel_drag()
	var enemy_side: int = _other_side(_player_side)

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
	# 순서 줄도 픽창과 함께 걷는다 — 열네 수가 다 끝났으니 가리킬 차례가 없다.
	if _pip_tween != null and _pip_tween.is_valid():
		_pip_tween.kill()
	if _pips_root != null:
		_pips_root.queue_free()
		_pips_root = null
	_seq_pips.clear()
	_seq_dividers.clear()
	_pip_icon = null
	_turn_arrow = null

	# 상대 블록은 다시 세우지 않고 **탭만 열어 준다** — 밴픽 내내 서 있던
	# 그림이 그대로 남아야 "저쪽이 무엇을 골랐나"를 두 번 읽지 않는다.
	_set_block_tappable(enemy_side, true)

	_rebuild_player_block_for_assign()
	_build_assign_prompt()
	_refresh_ui()
	_play_assign_intro(enemy_side)


## 배정 진입 연출. 두 팀 블록이 비워진 픽창 자리로 **가운데에 모이고**, 그 다음
## 상대 메크 칸이 포지션에 맞는 선수 자리로 옮겨 앉는다. 끝나야 "게임 시작"이
## 풀린다.
func _play_assign_intro(enemy_side: int) -> void:
	var e_holder := (_side_ui.get(enemy_side, {}) as Dictionary).get("holder", null) as Control
	var p_holder := (_side_ui.get(_player_side, {}) as Dictionary).get("holder", null) as Control
	var tw := create_tween().set_parallel()
	if e_holder != null:
		tw.tween_property(e_holder, "position:y", float(_lay["gather_enemy_y"]), GATHER_SEC) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	if p_holder != null:
		tw.tween_property(p_holder, "position:y", float(_lay["gather_player_y"]), GATHER_SEC) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	await get_tree().create_timer(GATHER_SEC + ENEMY_SWAP_DELAY).timeout
	if _panel == null:
		return
	await _play_enemy_reassign(enemy_side, _enemy_role_order(enemy_side))
	if _panel == null:
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


## 상대 메크 칸이 지금 자리에서 새 자리로 미끄러져 옮겨 앉는다. 칸 노드 자체를
## 옮겼다가, 다 옮기면 제자리로 되돌리고 내용(자리표)을 바꿔 끼운다 — 끝 화면은
## 같고, 칸 노드가 언제나 자기 자리에 있다는 전제(탭 버튼 · 갱신)가 유지된다.
func _play_enemy_reassign(side: int, new_order: Array) -> void:
	var slots: Array = (_side_ui.get(side, {}) as Dictionary).get("mech_slots", [])
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
		var frame := (slots[i] as Dictionary)["frame"] as Panel
		var from: Vector2 = (slots[i] as Dictionary)["pos"]
		var to: Vector2 = (slots[j] as Dictionary)["pos"]
		frame.z_index = 1
		tw.tween_property(frame, "position:x", to.x, ENEMY_SWAP_SEC) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		# 오른쪽으로 가는 칸은 위로, 왼쪽으로 가는 칸은 아래로 비켜 지나간다 —
		# 가로지르는 두 칸이 서로를 통과하지 않고 엇갈려 지나가는 것으로 읽힌다.
		var lift: float = ENEMY_SWAP_LIFT_PX if j > i else -ENEMY_SWAP_LIFT_PX
		tw.tween_property(frame, "position:y", from.y - lift, ENEMY_SWAP_SEC * 0.5) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(frame, "position:y", from.y, ENEMY_SWAP_SEC * 0.5) \
				.set_delay(ENEMY_SWAP_SEC * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	if not moved:
		tw.kill()
	else:
		# 박자는 트윈의 `finished` 가 아니라 타이머로 기다린다 — 노드가 도중에
		# free 되면 그 신호는 영영 오지 않는다.
		await get_tree().create_timer(ENEMY_SWAP_SEC).timeout
		if _panel == null:
			return
		for slot_raw in slots:
			var slot: Dictionary = slot_raw
			var frame := slot["frame"] as Panel
			if is_instance_valid(frame):
				frame.position = slot["pos"]
				frame.z_index = 0
	_seat_mechs[side] = new_order
	_enemy_seated = true
	_refresh_side_block(side)


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


## "게임 시작"은 **하단 구간을 통째로 차지하는 바**다(`OutgameTheme.add_bottom_bar`)
## — 아웃게임 화면의 주된 행동이 서는 자리. 배정 진입 연출(`_play_assign_intro`)
## 이 끝날 때까지 잠겨 있다. 안내 문구는 아군 메크 줄 오른쪽 아래에 있고 제목
## ("메크 배정")은 없다 — 화면에 남은 것이 양 팀 초상화와 그 밑의 기체뿐이면
## 무엇을 하는 단계인지는 그림이 말한다.
func _build_assign_prompt() -> void:
	var bar: Array = OutgameTheme.add_bottom_bar(_panel, [
		{"text": "게임 시작", "style": "primary"},
	])
	_start_btn = bar[0] as Button
	_start_btn.disabled = true
	_start_btn.pressed.connect(_finish)


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
		_mech_detail = MechDetailPanel.new()
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
			# 칸이 손에 들렸다. 아직 바꾼 것은 없다.
			Haptics.play(Haptics.Kind.SELECT)
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
	sb.bg_color = SLOT_EMPTY_COLOR
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
				(side_col if filled else side_col.lerp(OutgameTheme.SURFACE, 0.55))
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
			# 두 칸이 실제로 맞바뀌었다.
			Haptics.play(Haptics.Kind.MEDIUM)
	_drag_armed = false
	_drag_seat = -1
	if dragging:
		var slot: Dictionary = _slot_at(from_seat)
		if not slot.is_empty():
			(slot["frame"] as Panel).modulate = Color(1, 1, 1, 1)
	_refresh_side_block(_player_side)
	_reset_slot_borders()


## 끌던 칸을 그 자리에 내려놓는다(아무것도 바꾸지 않는다).
func _cancel_drag() -> void:
	if _drag_ghost != null and is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_ghost = null
	var slot: Dictionary = _slot_at(_drag_seat)
	if not slot.is_empty():
		(slot["frame"] as Panel).modulate = Color(1, 1, 1, 1)
	_drag_armed = false
	_drag_seat = -1
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
	var seats: Array = _seat_mechs.get(_player_side, [])
	if a < 0 or b < 0 or a >= seats.size() or b >= seats.size():
		return
	var tmp = seats[a]
	seats[a] = seats[b]
	seats[b] = tmp


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
	# 팝업은 CanvasLayer 라 `_panel` 을 지워도 따라 사라지지 않는다 — 열어 둔
	# 채 넘어가면 딤이 BattleSim 위에 그대로 남는다.
	_close_detail_panels()
	_panel.queue_free()
	_panel = null
	if _banner_root != null and is_instance_valid(_banner_root):
		_banner_root.queue_free()
	_banner_root = null
	_cells.clear()
	_side_ui.clear()
	_seq_pips.clear()
	_seq_dividers.clear()
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
