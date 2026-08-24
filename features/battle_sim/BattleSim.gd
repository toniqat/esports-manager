class_name BattleSim
extends Node2D

# ─── Preload ──────────────────────────────────────────────────────────────────
const CARD_SCENE := preload("res://scenes/Card.tscn")

# ─── Constants (UI/rendering — not DB scope) ──────────────────────────────────
# Seconds between auto-tick advances during BATTLE (each tick = 1 minute).
const AUTO_PLAY_INTERVAL := 0.5

# Card phase UI constants (not DB scope)
# Hand layout: fixed-width flat hand, centred on the viewport. The X anchor is
# computed in _ready so the layout follows the actual viewport width. Cards
# span ~y=1440..1660 at-rest (CARD_H=220).
#
# y 1440 은 전장 축소(`HexGrid.DISPLAY_SCALE` 1.5 → 1.35)를 따라온 값이다:
# 전장 하단이 1406 → 1351 로 55px 올라갔으므로 핸드도 60px 올려 카드 윗단과
# 전장 아랫단 사이의 ~90px 간격을 그대로 유지한다. 확인/취소 버튼 행, 전략
# 포인트 도넛, Deck / Discard 카운터는 전부 이 값에서 역산하므로 함께 따라온다.
var BS_HAND_CENTER: Vector2 = Vector2(540.0, 1440.0)
# Side margin (px) reserved for the Deck / Discard count indicators on the
# left and right of the hand row. Hand width = viewport_w − 2 × this.
const BS_HAND_AREA_MARGIN := 130.0
# Target gap (px) between adjacent cards when the hand fits inside its width.
# Once the natural span exceeds BS_HAND_WIDTH the spacing compresses below
# this — see CardPhaseManager.slot_position().
const BS_HAND_CARD_GAP    := 12.0
# Available inner width of the hand row (set in _ready from viewport size).
var BS_HAND_WIDTH: float  = 902.0
# The hand row is widened past the margin-derived width by this factor so the
# cards overlap each other less. It eats into the Deck / Discard gutters, so
# HudBuilder._build_hand_indicators re-derives its gutter from the real hand
# edge instead of BS_HAND_AREA_MARGIN.
const BS_HAND_WIDTH_SCALE := 1.10
# Minimum distance (px) the card *next to* the hovered card slides away from it.
# The real push is usually larger — it grows with the hand size so a tightly
# packed row still leaves its neighbours clickable — see
# CardPhaseManager._hover_push_amount().
const BS_HAND_HOVER_PUSH  := 28.0
# Sliver (px) of the neighbouring card that must stay uncovered by the
# 1.2x-enlarged hovered card. This is what the push size is solved for.
const BS_HAND_HOVER_MIN_STRIP := 32.0
# Shape of the falloff that carries the push from "full" next to the hovered
# card down to exactly 0 on the outermost card, which is what keeps the hand's
# overall width fixed while the row opens. ramp = 1 − (steps/steps_to_end)^POW,
# so a value > 1 holds the near neighbours near full push and concentrates the
# whole give-way in the outer cards. 1.0 would be a plain linear ramp.
const BS_HAND_HOVER_FALLOFF_POW := 2.0
# Radius (px) of the virtual circle the hand fans along. Every card centre rides
# that circle, whose pivot sits directly below the hand row, so the middle card
# is the highest point and the row curves down toward both ends. Smaller radius
# = deeper curve and stronger card tilt — see CardPhaseManager._fan_angle() /
# _fan_arc_drop(). At the 12-card cap the outermost cards tilt ~6.7° and hang
# ~22px below the middle one.
const BS_HAND_FAN_RADIUS := 3200.0

# ─── Pilot battlefield animation consts (fit within AUTO_PLAY_INTERVAL=0.5s) ─
## 마커 글라이드 — 초상화가 **직전에 그려지던 자리에서 새 자리까지** 미끄러지는
## 시간. 칸 이동(경로를 따라)과 같은 칸 안의 슬롯 이동이 같은 값을 쓴다.
## 타이머는 `BattleRenderer._glide` 가 쥐고 있고 여기는 그 노브다.
const ANIM_MOVE_DUR            := 0.30
## Damage shake: short horizontal jitter when a pilot takes damage.
const ANIM_SHAKE_DUR           := 0.18
## Recall fade-out at original cell (rise + alpha→0).
const ANIM_RECALL_FADE_OUT_DUR := 0.20
## Recall / respawn fade-in at HQ (descend + alpha→1).
const ANIM_RECALL_FADE_IN_DUR  := 0.25
## How far up the recalling/respawning pilot drifts (px) at peak alpha=0.
const ANIM_RECALL_RISE_PX      := 110.0
## Damage shake horizontal amplitude in px (decays linearly to 0 across the duration).
const ANIM_SHAKE_AMP_PX        := 6.0
## 공격 카드(`attack:N`) 명중 전용 흔들림 — 전장 자동 교전보다 **훨씬 격렬하다**
## (진폭 6 → 20px, 지속 0.18 → 0.26초 = 진동 수도 4 → 5.8회로 함께 늘어난다).
## 매 턴 자동으로 오가는 교전 피해와 달리 카드 명중은 플레이어가 방금 고른
## 한 방이라, 같은 세기로 흔들면 카드가 아무 일도 안 한 것처럼 읽힌다.
const ANIM_SHAKE_CARD_AMP_PX   := 20.0
const ANIM_SHAKE_CARD_DUR      := 0.26
## 사망 연출 1단계 — 쓰러진 자리에서 딤드된 채 버티는 시간.
const ANIM_DEATH_HOLD_DUR      := 1.0
## 사망 연출 2단계 — 투명해지며 위로 떠오르는 시간.
const ANIM_DEATH_FADE_DUR      := 0.45
## 사망 연출 2단계에서 떠오르는 높이(px).
const ANIM_DEATH_RISE_PX       := 90.0
## 사망 연출 1단계의 딤드 색 배율 (초상 / 링에 함께 곱해진다).
const ANIM_DEATH_TINT          := Color(0.34, 0.34, 0.40, 1.0)
## 포탑 피격 연출 — 흔들림 + 붉은 섬광이 감쇠하며 사라지기까지의 시간(s).
const ANIM_TURRET_HIT_DUR      := 0.26
## 포탑 피격 흔들림의 좌우 진폭(px). 파일럿보다 크게 흔들어 준다 —
## 포탑 스프라이트가 타일만 하기 때문에 6px 로는 눈에 띄지 않는다.
const ANIM_TURRET_HIT_AMP_PX   := 9.0
## 피격 순간 포탑 스프라이트에 곱하는 색. 연출이 끝나면 흰색으로 돌아온다.
const ANIM_TURRET_HIT_TINT     := Color(1.0, 0.42, 0.36, 1.0)

# ─── 공격 카드 명중 연출 ─────────────────────────────────────────────────────
# 공격 카드(`attack:N`)의 한 타격은 두 초상 위에서 동시에 벌어진다 —
# **시전자 초상에서 하얀 빛이 솟아오르고**, **피격자 초상에서 파티클이 사방으로
# 퍼지며 초상이 격하게 흔들린다**. 자세한 배선은 `anim_pilot_cast` /
# `BattleRenderer.spawn_pilot_burst` 참조.
#
# 예전에는 **돌진(몸통 박치기)**이었다 — 시전자 초상이 대상 초상까지 파고들었다
# (`ANIM_LUNGE_IN_DUR`) 붕 뜬 채 돌아오는(`ANIM_LUNGE_OUT_DUR`) 세 박자. 그
# 연출은 초상을 실제로 **옮겼기 때문에** 딸린 장치가 많았다: 마커 좌표를 다시
# 풀어 방향을 재고(같은 칸의 적이면 방향이 뒤집힌다), 파고든 얼굴이 대상 뒤로
# 숨지 않게 렌더러가 그리는 순서를 바꾸고(`_lunging_cells_last`), 사망 · 복귀 ·
# 부활마다 변위를 걷어 내야 했다(`anim_pilot_lunge_clear`). 지금은 두 초상이
# 제자리에 있고 그 위에 이펙트만 얹히므로 그 셋이 통째로 사라졌다.
# **되살리지 말 것** — 삭제된 API 목록은 `debug/removed` 대신 이 주석이 기록이다.

## **한 타격의 총 연출 시간은 `ANIM_CAST_DUR + ANIM_HIT_HOLD_SEC` = 0.32초다.**
## 돌진 시절(0.08 + 0.24)과 같은 길이로 맞춘 값이다 — 연속 공격(`repeat`, 최대
## 5타)이 이 두 박자를 타수만큼 반복하므로 한 장의 상한도 그대로 1.6초이고,
## `DMG_POPUP_DUR`(0.30) < 0.32 라는 기존 관계도 유지된다(팝업 좌표는 띄운
## 순간에 고정되므로 이 부등호가 깨지면 연속 타격의 숫자가 같은 자리에 쌓인다).
##
## 시전 빛이 솟아오르는 시간(s). 피해는 이 박자가 **끝난 뒤** 들어간다 —
## 빛이 올라가는 동안이 "쏘는 중"이고, 그 다음이 맞는 순간이다.
const ANIM_CAST_DUR      := 0.12
## 시전 빛이 시전자 초상 위로 솟아오르는 높이(px).
const ANIM_CAST_RISE_PX  := 54.0
## 명중 뒤 다음 타격까지 두는 여운(s). 파티클과 쉐이크가 이 구간에서 돈다.
const ANIM_HIT_HOLD_SEC  := 0.20

# ─── 피해 수치 팝업 (공격 카드 전용) ─────────────────────────────────────────
## 팝업이 화면에 머무는 시간(s). **한 타격의 연출 길이(0.32초)보다 길면 연속
## 공격의 숫자가 같은 자리에 겹쳐 쌓인다** — 팝업 좌표는 띄운 순간에 고정되므로
## 두 번째 타격의 `-N` 이 첫 번째 것 위에 그대로 얹힌다. 한 타격의 연출을 1.12 → 0.40
## → 0.32 초로 줄일 때마다 이 값도 함께 내려왔다(0.95 → 0.38 → 0.30). 마지막
## 숫자는 다음 타격이 시작되기 직전에 사라진다.
const DMG_POPUP_DUR      := 0.30
## 팝업이 떠오르는 총 높이(px).
const DMG_POPUP_RISE_PX  := 46.0
## 연속 공격처럼 한 번에 여러 번 터질 때 팝업 사이에 주는 시작 지연(s).
const DMG_POPUP_STAGGER  := 0.18

# ─── Animation timing & easing consts ─────────────────────────────────────────
## Duration (s) for normal hand relayout (draw, play).
const BS_HAND_SPRING_DURATION  := 0.18
## Duration (s) for the deck↔discard reshuffle count animation.
const BS_RESHUFFLE_TWEEN_DUR   := 0.55
## Ease type used in Card.tween_to for hand animations (int = Tween.EASE_OUT).
const BS_HAND_TWEEN_EASE  : int = 1   # Tween.EASE_OUT
## Trans type used in Card.tween_to for hand animations (int = Tween.TRANS_SPRING).
const BS_HAND_TWEEN_TRANS : int = 10  # Tween.TRANS_SPRING

# ─── DB-driven vars (populated from DataLoader in _ready) ─────────────────────
var GRID_COLS:               int   = 0
var GRID_ROWS:               int   = 0
var HQ_MAX_HP:               int   = 0
var RESPAWN_TURNS:           int   = 0
var TURRET_HP:               int   = 0
var TURRET_ATK:              int   = 0
var RECALL_HP_THRESHOLD:     float = 0.0
## 전장 교전이 **파일럿에게** 넣는 피해에 곱하는 배율. 포탑 / HQ 피해와
## 공격 카드 · 교전 아레나는 이 배율을 타지 않는다.
var BATTLE_PILOT_DMG_MULT:   float = 1.0
var MAX_HAND_SIZE:           int   = 0
## 블루 진영이 개시 시점에 선점하는 전략 포인트. 밴픽에서 후밴/후픽을 하는
## 대가로 인게임 선을 잡게 하는 노브다 (see `blue_team`).
var BLUE_COST_HEAD_START:    int   = 0
var COST_RECOVERY:           int   = 0
var CARD_DRAW_INTERVAL:      int   = 1
var COST_RECOVERY_INTERVAL:  int   = 1
var PHASE_THRESHOLD:         int   = 0
## 카드 경제(전략 점수 회복 + 자동 드로우)가 처음 도는 턴. 그 전 턴들에는
## 회복도 드로우도 없고 **개시 손패도 없다** — 0턴에 들어가는 것은 블루 선점
## (`BLUE_COST_HEAD_START`) 하나뿐이고, 양 팀은 빈 손으로 이 턴까지 순수
## 라인전만 한다. 성장은 이 게이트를 타지 않는다(1턴부터 돈다).
var ECONOMY_START_TURN:      int   = 1
## 파일럿 한 명이 **포탑 / HQ 에 한 번에 넣는 고정 피해**. `atk` 와 무관하다.
##
## 예전에는 `atk` 전량이 들어갔는데, 성장이 공격력을 ×3 까지 밀어 올리는 지금
## 그대로 두면 후반 포탑이 한 턴에 녹아 경기 길이가 성장에 반비례해 무너진다.
## 구조물이 빨리 무너지는 이유는 **공격력이 커져서가 아니라 수비수가 저HP
## 복귀·사망으로 전장을 비웠기 때문**이어야 한다 — 그래서 피해는 고정이고,
## 대신 포탑 체력이 16 까지 내려와 무방비면 8턴에 철거된다.
var PILOT_STRUCTURE_DMG:     int   = 2

# ─── 오브젝트 (전령 / 용) ────────────────────────────────────────────────────
# 좌측 중립 칸에 전령, 우측 중립 칸에 용이 정해진 턴에 열린다. 자세한 규칙은
# `objective/README.md`. 여기 있는 것은 전부 `game_config` 노브다.
## 전령이 처음 열리는 턴. **용보다 10턴 늦다** — 두 오브젝트가 같은 구간에
## 겹쳐 열리면 정글러와 중앙이 양쪽에 끌려다니느라 어느 쪽도 결정이 되지 않는다.
## 순서를 용 먼저로 둔 이유는 보상의 성격이다: 용은 경기 내내 천천히 도는 성장
## 이득이라 일찍 먹을수록 값이 커지고, 전령의 포탑 8 피해는 늦게 먹어도 값이
## 그대로다.
var OBJ_HERALD_FIRST_TURN:   int   = 35
## 용이 처음 열리는 턴. **두 오브젝트 중 먼저 열린다.**
var OBJ_DRAGON_FIRST_TURN:   int   = 25
## **결판이 난 뒤** 같은 오브젝트가 다시 열리기까지의 턴 수. 한 팀이 가져갔든
## 교전 끝에 아무도 못 가져갔든 같은 값이다 — 자리는 소모되지 않는다.
var OBJ_RESPAWN_TURNS:       int   = 20
## **양 팀이 모두 미참여**해서 무산됐을 때의 재시도 간격. 결판 간격보다 짧다:
## 아무 일도 일어나지 않았으므로 자원을 그만큼 오래 재워 둘 이유가 없다.
var OBJ_RETRY_TURNS:         int   = 15
## 오브젝트 교전의 라운드 수. 카드 전투 개시(3) 보다 길다.
var OBJ_ENGAGE_ROUNDS:       int   = 4
## [전령 제압] 카드가 최외곽 적 포탑에 넣는 고정 피해.
var OBJ_HERALD_TURRET_DMG:   int   = 8
## 용을 가져간 팀의 덱에 섞여 들어가는 [용 보상] 카드 장수.
var OBJ_DRAGON_CARD_COUNT:   int   = 5
## [용 보상] 한 장이 지정한 파일럿에게 **영구로** 얹는 성장 적립 배율(%).
var OBJ_DRAGON_GROWTH_PCT:   int   = 10

# Derived after DB load
var PLAYER_HQ_POS: Vector2i = Vector2i.ZERO
var ENEMY_HQ_POS:  Vector2i = Vector2i.ZERO

var ROLE_STATS:    Dictionary = {}
var ROLE_NAMES:      Array = []
var ROLE_FULL_NAMES: Array = []
var LANE_NAMES:      Array = []
var LANE_MAX:        Array = []
var LANE_MIDPOINTS:  Array = []
var LANE_PATHS_TEAM0: Array = []
var LANE_PATHS_TEAM1: Array = []
var NEUTRAL_ZONES:    Array = []
var TURRET_POSITIONS: Dictionary = {}

# ─── State ────────────────────────────────────────────────────────────────────
var neutral_zone_cells: Dictionary = {}  # Vector2i → int (-1=gray, 0=team0, 1=team1)
## 정글 캠프의 재생성 시계. `Vector2i cell → int ready_turn` 이고, `turn_count`
## 가 그 값 이상이면 캠프가 차 있다. 정글러가 밟아 먹으면
## `turn_count + JUNGLE_CAMP_RESPAWN_TURNS` 로 밀린다.
##
## 칸은 `neutral_zone_cells` 와 같은 집합(정글 + 중립 전부)이고, 캠프를 먹을 수
## 있는 것은 **자기 팀 소유이거나 중립인 칸**뿐이다 — 그래서 적 정글을 점령하면
## 돌 수 있는 캠프가 늘어 수입이 그만큼 커진다.
var jungle_camps: Dictionary = {}        # Vector2i → int (ready_turn)
var pilots:  Array               = []
var turrets: Array               = []
var player_hq_hp: int            = 0
var enemy_hq_hp: int             = 0
var turn_count: int              = 0
var game_over: bool              = false
var auto_play_timer: float       = AUTO_PLAY_INTERVAL
var last_log: String             = ""
var game_phase: int              = GameEnums.BattlePhase.GAMBIT

# Card phase state
var player_hand:    Array = []
var ai_hand:        Array = []
var player_deck:    Array = []
var ai_deck:        Array = []
var player_discard: Array = []
var ai_discard:     Array = []
var player_cost:    int   = 0
var ai_cost:        int   = 0
var player_card_nodes: Array = []
var pending_atk_buff_p:  int   = 0
var pending_atk_buff_ai: int   = 0
var draw_counter:         int   = 0  # shared draw interval counter
var cost_counter:         int   = 0  # shared cost recovery interval counter

# 파일럿마다 개시에 배분받은 6장 — `PilotData → {"mech": Array, "pilot": Array}`.
# `CardPhaseManager._deal_team_deck` 이 덱을 돌 때 한 번 적고 경기 내내 바뀌지
# 않는다. 상세 패널(`ui/PilotDetailPanel.gd`)의 파일럿 / 메크 탭이 유일한
# 소비자이며, **손패 · 덱 · 버린 더미를 훑어 역산하지 않는 이유가 이것이다** —
# 소멸(`exhaust`)한 카드는 세 더미 어디에도 없어서 역산하면 목록에서 조용히
# 사라진다. "이 파일럿이 무엇을 들고 들어왔는가"는 경기 중에 변하지 않는 사실
# 이므로 배분 시점의 표를 그대로 들고 있는 편이 맞다.
var starter_cards: Dictionary = {}

# ─── 진영 (블루 / 레드) ───────────────────────────────────────────────────────
# 어느 팀이 블루인가. 0 = 플레이어 팀, 1 = AI 팀. `match_ctx.player_side`
# (GameEnums.DraftSide) 에서 유도되며, MatchFlow 를 거치지 않은 단독 실행에서는
# 플레이어가 블루다.
#
# 블루는 밴픽에서 **후밴 / 후픽**을 하는 대신 인게임에서 두 가지를 가져간다:
#   1. 개시 시점에 전략 포인트를 `BLUE_COST_HEAD_START` 만큼 선점한다.
#   2. 양 팀이 같은 점수로 문턱에 닿았을 때 **먼저 차례를 잡는다**
#      (CardPhaseManager.do_battle_turn 의 우선순위 규칙).
var blue_team: int = 0

# ─── Card cost-modifier state ────────────────────────────────────────────────
# Set by 비용 카드 효과들 (사전 준비 / 전투 준비 / 집중 …) and consumed at
# card-play / card-draw time. The phase-bound pair resets when
# CardPhaseManager.start_card_phase()/end_card_phase() flips back to BATTLE.
# engage_discount_*: one-shot discount applied to the next engage:N card the
#   side plays (전투 준비). Consumed on use.
# phase_cost_inc_*: add-on applied to every card play during the current
#   작전 단계 (cost_inc_phase). Reset on phase entry. **No card in the pool
#   carries that clause right now** — 정밀 이동 used to, but its +1 is now
#   self-only and lands on the card's own cost via return_left:1.
# phase_draw_discount_*: discount applied to every card drawn during the
#   current 작전 단계 (집중 cost_reduce_draw_phase). Mutates the drawn
#   CardData.cost directly so the cheaper cost survives even if the draw
#   re-enters the discard pile mid-phase.
var engage_discount_p:        int = 0
var engage_discount_ai:       int = 0
var phase_cost_inc_p:         int = 0
var phase_cost_inc_ai:        int = 0
var phase_draw_discount_p:    int = 0
var phase_draw_discount_ai:   int = 0

# ─── 카드 지연 효과 상태 ─────────────────────────────────────────────────────
# 계획 중시 (`preserve:N`) — 상한 초과 자동 버리기로부터 보호되는 손패 카드들.
# `CardPhaseManager._trim_hand_overflow` 만 이 목록을 본다: 카드 효과에 의한
# **강제** 버리기(재고 / 완벽한 마무리 / 과감한 정리 / 솔로 퍼포먼스)는 보존을
# 무시한다. 보존은 그 팀의 **다음 작전 단계 시작 시** 통째로 해제된다.
var preserved_cards_p:  Array = []   # Array[CardData]
var preserved_cards_ai: Array = []
# 아드레날린 (`strategy_next_phase:N`) — 다음 작전 단계 진입 시 전략 점수에
# 더해질 값(음수 가능). 적용 후 0으로 리셋되며 점수는 0 아래로 내려가지 않는다.
var next_phase_strategy_p:  int = 0
var next_phase_strategy_ai: int = 0
# 계획 살인 (`strategy_on_kill:N`) — **선불 예약형** 현상금. 카드를 낸 시점에
# 심어 두고, `mark_pilot_dead` 가 상대 팀 파일럿의 사망을 볼 때 한 번 지급하고
# 소모한다. 그 작전 단계가 끝나면 미사용분은 사라진다.
var kill_bounty_p:  int = 0
var kill_bounty_ai: int = 0

# Gambit state — gambit_lanes is filled by GambitPhaseManager.auto_assign_lanes()
var gambit_lanes: Array   = [-1, -1, -1, -1, -1]

# ─── HUD refs (set by HudBuilder) ────────────────────────────────────────────
var canvas: CanvasLayer
var panel_victory: Panel
var lbl_victory: Label
# 전략 포인트 도넛 게이지. `cost_donut` (player) doubles as the 턴 넘기기
# button once tapped; `cost_donut_enemy` is a readout only.
var cost_donut:       CostDonut = null
var cost_donut_enemy: CostDonut = null
# Deck / Discard 카드 뭉치 — 핸드 행 양옆 거터. 앞으로 누운 카드 뭉치이자
# 장수 카운터이자 목록 열람 버튼(위에 투명 Button 이 얹힌다).
var pile_deck:    CardPileStack = null
var pile_discard: CardPileStack = null

# 킬로그 — 화면 우측 상단(적 스트립 아래)에 처치 / 포탑 철거를 한 줄씩 쌓는다.
# `HudBuilder._build_kill_feed` 가 만들고, 적립은 `mark_pilot_dead` 와
# `score_turret_kill` 두 곳에서만 들어온다. 교전 중에 난 처치는 아레나가 닫힐
# 때까지 피드 안에 밀려 있다가 한 줄씩 풀린다 — `ui/KillFeed.gd` 참고.
var kill_feed: KillFeed = null

# ─── Module refs ─────────────────────────────────────────────────────────────
@onready var gm: Node                       = get_node("/root/GameManager")
@onready var _data_loader: Node              = $DataLoader
@onready var _field_loader: Node             = $FieldLoader
@onready var hex_grid:   HexGrid           = $HexGrid
@onready var sim_core:   SimulationCore    = $SimulationCore
@onready var recall_sys: RecallSystem      = $RecallSystem
@onready var pathfinder: Pathfinding       = $Pathfinding
@onready var renderer:   BattleRenderer    = $BattleRenderer
@onready var card_phase: CardPhaseManager  = $CardPhaseManager
@onready var _gambit:     GambitPhaseManager = $GambitPhaseManager
@onready var hud:               HudBuilder        = $HudBuilder
@onready var building_registry: BuildingRegistry  = $BuildingRegistry
# Modal pick overlay for 버리기:N / 찾기:N card effects. Built lazily in
# _ready() once the HUD canvas exists, since the overlay parents its dim
# rect into _bs.canvas.
var card_select_overlay: CardSelectOverlay = null
# 카드 대상 지정(targeting) 오버레이. 플레이어가 대상 지정 카드를 내면
# CardPhaseManager가 이 오버레이를 띄워 PILOT/LOCATION/PREVIEW 모드에서
# 클릭으로 대상을 고르거나 취소할 수 있게 한다. lazy-add in _ready().
var targeting_overlay: CardTargetingOverlay = null
# Deck / Discard 목록 열람 오버레이 (읽기 전용). 핸드 행 양옆의 카운터를 누르면
# 해당 더미의 카드를 이름순 그리드로 펼쳐 보여 준다. 작전 단계에서만 열린다.
# lazy-add in _ready().
var card_pile_viewer: CardPileViewer = null
# 파일럿 상세 패널 — 하단 아군 스트립의 얼굴을 누르면 열리는 모달. 좌측에 전신
# 아트, 우측에 아웃게임 / 인게임 / 메크 스탯. **자기 작전 단계에서만** 열리며
# 단계를 벗어나면 HudBuilder 가 닫는다. lazy-add in _ready().
var pilot_detail: PilotDetailPanel = null
# 오브젝트 보상 미리보기 — 상단 패널의 오브젝트 시계를 누르면 열리는 정보
# 팝업. 그 오브젝트가 주는 카드를 실물로 보여 준다. **전장을 붙잡지 않는다**
# (`_battle_tick_held` 가 읽지 않는다) — 순수 정보이므로 읽는 동안에도 턴은
# 평소대로 흐르고, 아무 데나 누르면 닫힌다. lazy-add in _ready().
var objective_reward: ObjectiveRewardPopup = null
# 오브젝트 보상 **획득** 연출 — 전령 / 용의 보상 카드를 화면 한가운데에 펼쳤다가
# 들어갈 자리(덱 뭉치 / 손패 왼쪽 끝 / 상대 손패)로 날려 보낸다. 위의
# `objective_reward` 는 **결판 전에** 무엇을 주는지 미리 보는 정보 팝업이고,
# 이쪽은 **결판 뒤에** 실제로 받은 카드를 보여 주는 연출이다 — 이름이 비슷할 뿐
# 여는 사람도(시계 / `ObjectiveSystem`) 수명도 다르다. lazy-add in _ready().
var objective_fx: ObjectiveRewardFx = null
# 전투 개시(engage) — 카드의 engage:N 효과가 발동되면 잠시 ENGAGE 페이즈로
# 전환되어 실시간 교전 아레나를 띄운다. 전투가 끝나면 아레나를 연 페이즈로
# 복귀한다(플레이어 카드면 CARD_PHASE, 상대 차례의 AI 카드면 BATTLE).
# 모듈은 _ready()에서 lazy-add.
var engage_phase: EngagePhaseManager = null
# AI가 카드를 사용할 때 화면 중앙에 띄우는 카드 애니메이션 오버레이.
# 상대 차례(CardPhaseManager._run_ai_turn) 안에서 await로 한 장씩 차례대로
# 보여 준다. lazy-add.
var ai_card_player: AiCardPlayer = null
# 오브젝트(전령 / 용) — 좌우 중립 칸에서 정해진 턴마다 열리는 교전 사건.
# 시계 · 참여 결정 · 정산을 전부 들고 있다. 턴 진입점은
# `CardPhaseManager.do_battle_turn` 하나뿐이다. `objective/README.md` 참고.
# lazy-add in _ready().
var objective: ObjectiveSystem = null
# 전투 행동 로거 — 모든 좌표 변화 / 교전 / 카드 사용을 콘솔 + user:// 파일에
# 남기고, 턴 경계에서 적 파일럿 간 교차(cross-over)를 자동 감지한다.
# `debug/BattleLogger.gd` 참고. lazy-add in _ready() after pilots spawn.
var blog: BattleLogger = null

## 파일럿 스킬 — 선수마다 붙는 고유 능력(쿨타임 / 충전식 / 패시브).
## `features/battle_sim/skill/PilotSkillSystem.gd` 참조. 스폰과 덱 배분이 **끝난
## 뒤** 세운다 — 짝을 로스터에서 찾고, 백본 패시브가 이미 돌아간 덱을 만진다.
var skill: PilotSkillSystem = null
## 메크 스킬 — 배정된 **기체**에 붙는 패시브와 그 기체가 들고 온 카드들의
## 런타임 상태(충전 · 지속 효과 · 사건 훅). 파일럿 스킬(`skill`)과 같은 자리에
## 서는 형제 모듈이고, 같은 이유로 스폰과 덱 배분이 모두 끝난 뒤에 세워진다.
## `features/battle_sim/mech/MechSkillSystem.gd` 참조.
var mech_skill: MechSkillSystem = null
## 매혹의 성장치 복사가 지금 한 겹 돌고 있는가. 고리를 한 겹에서 끊는 빗장이다.
var _score_link_depth: int = 0
## 교전이 도는 동안 밀어 둔 성장치 팝업. `PilotData → float`(그 교전에서 번 합).
## 무대가 치워질 때 `flush_score_popups` 가 한 사람당 한 장으로 풀어놓는다.
var _score_popup_hold: Dictionary = {}

# ─── TileMapLayer refs (set after BattleField.tscn is added as child) ────────
@onready var tiles_layer:    TileMapLayer = $BattleField/Tiles
@onready var _wp_layer:       Node2D       = $BattleField/WaypointLayer
@onready var _building_layer: Node2D       = $BattleField/BuildingLayer

# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_data_loader.data_load_failed.connect(_on_data_load_failed)
	if not _data_loader.load_data():
		return  # error panel shown by signal handler

	# 파일럿 portrait 텍스처를 SceneTree에 사전 등록해 GPU 업로드를 트리거.
	# 이 단계가 없으면 draw_texture_rect가 흰 사각형으로 그려진다.
	PilotImages.prime_into(self)

	# Centre the hand row on the actual viewport width (handles any screen size).
	# Subtract half card width so the pivot point (card centre) lands on screen centre,
	# not the top-left corner which Godot uses for Control global_position.
	var vp_w  := get_viewport().get_visible_rect().size.x
	var vp_cx := vp_w * 0.5
	BS_HAND_CENTER.x = vp_cx - Card.CARD_W * 0.5
	# Inner hand width = total width minus the two side margins reserved for
	# the Deck / Discard count labels, widened by BS_HAND_WIDTH_SCALE.
	BS_HAND_WIDTH = max(Card.CARD_W,
			(vp_w - 2.0 * BS_HAND_AREA_MARGIN) * BS_HAND_WIDTH_SCALE)

	_field_loader.load_field(tiles_layer, _building_layer, _wp_layer)
	var _vp_size := get_viewport().get_visible_rect().size
	var _bf_pos := hex_grid.init_from_tilemap(tiles_layer, _vp_size)
	_bf_pos.y -= 100.0
	$BattleField.position = _bf_pos
	hex_grid.grid_top   -= 100.0  # keep hex_to_screen() aligned with the shifted TileMap
	_populate_from_data_loader()
	player_hq_hp = HQ_MAX_HP
	enemy_hq_hp  = HQ_MAX_HP
	hud.build_ui()
	# Pick overlay must exist before any 버리기 / 찾기 card resolves; it parents
	# its UI into the HUD canvas, so build it after hud.build_ui() and before
	# the card phase can fire.
	card_select_overlay = CardSelectOverlay.new()
	card_select_overlay.name = "CardSelectOverlay"
	add_child(card_select_overlay)
	card_select_overlay.bind(self)
	# Targeting overlay owns the modal pilot/cell pick UI for cards that
	# require a target. Built before engage_phase so engage's preview can
	# hand control off to it.
	targeting_overlay = CardTargetingOverlay.new()
	targeting_overlay.name = "CardTargetingOverlay"
	add_child(targeting_overlay)
	targeting_overlay.bind(self)
	# Deck / Discard 열람 오버레이 — HUD 의 카운터 버튼이 열고 닫는다. 자기
	# CanvasLayer(12) 위에 그리므로 다른 오버레이보다 뒤에 만들어도 상관없다.
	card_pile_viewer = CardPileViewer.new()
	card_pile_viewer.name = "CardPileViewer"
	add_child(card_pile_viewer)
	card_pile_viewer.bind(self)
	# 파일럿 상세 패널 — 하단 아군 스트립을 누르면 열린다(작전 단계 한정).
	pilot_detail = PilotDetailPanel.new()
	pilot_detail.name = "PilotDetailPanel"
	add_child(pilot_detail)
	pilot_detail.bind(self)
	# 오브젝트 보상 미리보기 — 상단 패널의 시계가 연다.
	objective_reward = ObjectiveRewardPopup.new()
	objective_reward.name = "ObjectiveRewardPopup"
	add_child(objective_reward)
	objective_reward.bind(self)
	# 오브젝트 보상 획득 연출 — `ObjectiveSystem._grant_reward` 가 지급 직전에 연다.
	objective_fx = ObjectiveRewardFx.new()
	objective_fx.name = "ObjectiveRewardFx"
	add_child(objective_fx)
	objective_fx.bind(self)
	# Engage manager owns the turn-based 전투 modal lifecycle.
	engage_phase = EngagePhaseManager.new()
	engage_phase.name = "EngagePhaseManager"
	add_child(engage_phase)
	# AI 카드 사용 애니메이션 오버레이 — end_card_phase 동안 활성.
	ai_card_player = AiCardPlayer.new()
	ai_card_player.name = "AiCardPlayer"
	add_child(ai_card_player)
	ai_card_player.bind(self)
	# 오브젝트 시계 — 첫 등장 턴이 game_config 에서 오므로
	# `_populate_from_data_loader()` 뒤라야 한다.
	objective = ObjectiveSystem.new()
	objective.name = "ObjectiveSystem"
	add_child(objective)
	objective.init_objectives()
	# Lane assignment is fixed by role; jungle direction comes from MatchFlow
	# (or default LEFT when running BattleSim standalone).
	_gambit.auto_assign_lanes()
	_gambit.launch_battle()
	# Action logger — bound AFTER pilots spawn so its header can dump the roster.
	blog = BattleLogger.new()
	blog.name = "BattleLogger"
	add_child(blog)
	blog.bind(self)
	# Build the per-team deck AFTER pilots spawn — each pilot owns 6 random cards
	# from the pool (시전자 rule) and all 5 stacks shuffle into the team deck.
	card_phase.build_starter_decks()
	# 파일럿 스킬 — 로스터(`player_data_for`)와 덱이 모두 선 뒤라야 한다.
	skill = PilotSkillSystem.new()
	skill.name = "PilotSkillSystem"
	add_child(skill)
	# 충전 / 쿨타임이 움직이면 스트립의 딤과 숫자가 그 자리에서 따라간다.
	# `update_hud` 는 매 턴과 카드 사용 뒤에도 돌지만, 전장 틱과 무관하게
	# 상태가 바뀌는 경로(오브젝트 등장 · 처치 관여 · 포탑 파괴)가 있어서
	# 그쪽까지 덮으려면 신호가 필요하다.
	skill.skill_state_changed.connect(hud.update_hud)
	skill.init_for_match()
	# 메크 스킬 — 파일럿 스킬과 같은 전제(로스터 + 덱)를 요구하므로 바로 옆에
	# 세운다. 덱보다 먼저 세우면 `mech_cards` 배분 표를 못 읽는다.
	mech_skill = MechSkillSystem.new()
	mech_skill.name = "MechSkillSystem"
	add_child(mech_skill)
	mech_skill.init_for_match()


func _on_data_load_failed(reason: String) -> void:
	push_error("BattleSim: data load failed — " + reason)
	# Build a minimal error overlay directly on the scene root
	var err_canvas := CanvasLayer.new()
	err_canvas.layer = 100
	add_child(err_canvas)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.modulate = Color(0.1, 0.05, 0.05, 0.95)
	err_canvas.add_child(panel)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size  = Vector2(900.0, 0.0)
	lbl.text = "Data Load Error\n\n" + reason + \
		"\n\nRun Project → Tools → CSV to DB to regenerate game.db."
	panel.add_child(lbl)
	lbl.set_anchors_preset(Control.PRESET_CENTER)


## Reads `match_ctx.player_side` into `blue_team` and seeds both sides' 전략
## 포인트 from it: 블루가 `BLUE_COST_HEAD_START` 만큼 앞선 채로 시작한다.
##
## 선점은 순전히 **선을 잡기 위한** 장치다 — COST_RECOVERY 는 양 팀에 같은
## 틱에 같은 양이 들어가므로, 개시 시점의 차이가 그대로 유지되어 블루가 항상
## 문턱에 먼저 닿는다. 같은 점수로 동시에 닿는 경우(카드로 점수를 쓴 뒤 등)의
## 타이브레이크는 CardPhaseManager 의 차례 우선순위가 따로 책임진다.
##
## MatchFlow 를 거치지 않은 단독 실행에서는 match_ctx 가 비어 있어 플레이어가
## 블루가 된다.
func seed_side_costs() -> void:
	var side: int = GameEnums.DraftSide.BLUE
	if gm != null and bool(gm.match_ctx.get("active", false)):
		side = int(gm.match_ctx.get("player_side", GameEnums.DraftSide.BLUE))
	# player_side 는 "플레이어 팀의 진영"이므로, 플레이어가 BLUE 면 블루 팀은 0.
	blue_team = 0 if side == GameEnums.DraftSide.BLUE else 1
	player_cost = BLUE_COST_HEAD_START if blue_team == 0 else 0
	ai_cost     = BLUE_COST_HEAD_START if blue_team == 1 else 0


func _populate_from_data_loader() -> void:
	var cfg: Dictionary = _data_loader.game_cfg

	GRID_COLS               = int(cfg.get("GRID_COLS", "9"))
	GRID_ROWS               = int(cfg.get("GRID_ROWS", "11"))
	HQ_MAX_HP               = int(cfg.get("HQ_MAX_HP", "500"))
	RESPAWN_TURNS           = int(cfg.get("RESPAWN_TURNS", "5"))
	TURRET_HP               = int(cfg.get("TURRET_HP", "150"))
	TURRET_ATK              = int(cfg.get("TURRET_ATK", "8"))
	RECALL_HP_THRESHOLD     = float(cfg.get("RECALL_HP_THRESHOLD", "0.2"))
	BATTLE_PILOT_DMG_MULT   = float(cfg.get("BATTLE_PILOT_DMG_MULT", "0.5"))
	MAX_HAND_SIZE           = int(cfg.get("MAX_HAND_SIZE", "10"))
	BLUE_COST_HEAD_START    = int(cfg.get("BLUE_COST_HEAD_START", "1"))
	COST_RECOVERY           = int(cfg.get("COST_RECOVERY", "1"))
	CARD_DRAW_INTERVAL      = max(1, int(cfg.get("CARD_DRAW_INTERVAL", "1")))
	COST_RECOVERY_INTERVAL  = max(1, int(cfg.get("COST_RECOVERY_INTERVAL", "1")))
	PHASE_THRESHOLD         = int(cfg.get("PHASE_THRESHOLD", "8"))
	ECONOMY_START_TURN      = max(1, int(cfg.get("ECONOMY_START_TURN", "1")))
	PILOT_STRUCTURE_DMG     = max(1, int(cfg.get("PILOT_STRUCTURE_DMG", "2")))
	OBJ_HERALD_FIRST_TURN   = max(1, int(cfg.get("OBJ_HERALD_FIRST_TURN", "35")))
	OBJ_DRAGON_FIRST_TURN   = max(1, int(cfg.get("OBJ_DRAGON_FIRST_TURN", "25")))
	OBJ_RESPAWN_TURNS       = max(1, int(cfg.get("OBJ_RESPAWN_TURNS", "20")))
	OBJ_RETRY_TURNS         = max(1, int(cfg.get("OBJ_RETRY_TURNS", "15")))
	OBJ_ENGAGE_ROUNDS       = max(1, int(cfg.get("OBJ_ENGAGE_ROUNDS", "4")))
	OBJ_HERALD_TURRET_DMG   = max(1, int(cfg.get("OBJ_HERALD_TURRET_DMG", "8")))
	OBJ_DRAGON_CARD_COUNT   = max(1, int(cfg.get("OBJ_DRAGON_CARD_COUNT", "5")))
	OBJ_DRAGON_GROWTH_PCT   = max(0, int(cfg.get("OBJ_DRAGON_GROWTH_PCT", "10")))
	# Init counters so first event fires on turn 1
	draw_counter = CARD_DRAW_INTERVAL - 1
	cost_counter = COST_RECOVERY_INTERVAL - 1
	seed_side_costs()

	# Pilot stats
	ROLE_STATS      = _data_loader.pilot_stats.duplicate(true)
	ROLE_NAMES      = []
	ROLE_FULL_NAMES = []
	for i in range(_data_loader.pilot_stats.size()):
		var s: Dictionary = _data_loader.pilot_stats[i]
		ROLE_NAMES.append(s.get("abbrev", "?"))
		ROLE_FULL_NAMES.append(s.get("name", "?"))

	# Lane config
	LANE_NAMES     = []
	LANE_MAX       = []
	LANE_MIDPOINTS = []
	for lc in _data_loader.lane_cfg:
		LANE_NAMES.append(lc["name"])
		LANE_MAX.append(lc["max_pilots"])
		LANE_MIDPOINTS.append(Vector2i(lc["mid_col"], lc["mid_row"]))

	# Waypoints (from FieldLoader — TileMapLayer source of truth)
	LANE_PATHS_TEAM0 = _field_loader.waypoints[0].duplicate(true)
	LANE_PATHS_TEAM1 = _field_loader.waypoints[1].duplicate(true)

	# HQ positions (from FieldLoader)
	for hq in _field_loader.hqs:
		if hq["team"] == 0:
			PLAYER_HQ_POS = Vector2i(hq["col"], hq["row"])
		else:
			ENEMY_HQ_POS = Vector2i(hq["col"], hq["row"])

	# Neutral zones (from FieldLoader)
	NEUTRAL_ZONES = _field_loader.neutral_zone_cells.duplicate(true)

	# Turret positions (from FieldLoader)
	TURRET_POSITIONS = _field_loader.turret_pos.duplicate(true)

	# Apply disabled cells and actual cell bounds from FieldLoader to hex grid
	hex_grid.set_disabled_cells(_field_loader.disabled_cells)
	hex_grid.set_grid_bounds(_field_loader.min_cell, _field_loader.max_cell)


func _process(delta: float) -> void:
	# BATTLE auto-ticks every AUTO_PLAY_INTERVAL seconds. CARD_PHASE pauses the
	# tick until the player presses "단계 넘기기"; the AI's own turn runs *inside*
	# BATTLE (CardPhaseManager._run_ai_turn) and holds the tick the same way.
	if not game_over and game_phase == GameEnums.BattlePhase.BATTLE \
			and not _battle_tick_held():
		auto_play_timer -= delta
		if auto_play_timer <= 0.0:
			auto_play_timer = AUTO_PLAY_INTERVAL
			card_phase.do_battle_turn()
	# Tick the on-screen MM:SS clock smoothly every frame (paused when not in BATTLE).
	if hud != null:
		hud.update_time_label()
	# Drive pilot UI animations (move tween, damage shake, recall fade) every
	# frame regardless of phase so animations finish during CARD_PHASE too.
	var pilot_anim: bool = _advance_pilot_animations(delta)
	var turret_anim: bool = _advance_turret_animations(delta)
	if pilot_anim or turret_anim:
		renderer.queue_redraw()


# True while the opponent is taking its 작전 단계. That turn runs inside the
# BATTLE phase (game_phase never changes), so every "is the sim running?" check
# has to consult it on top of game_phase.
func _ai_turn_active() -> bool:
	return card_phase != null and card_phase.is_ai_turn_active()


## **BATTLE 안에서 시뮬레이션을 붙잡고 있는 것이 있는가.** `game_phase` 를 바꾸지
## 않은 채 턴을 멈추는 사유가 둘이다.
##
##   • 상대 차례 — `CardPhaseManager._run_ai_turn` 이 BATTLE 안에서 돈다.
##   • 오브젝트 — 참여 / 미참여 결정 창이 떠 있는 동안은 아직 BATTLE 이다
##     (뒤이어 열리는 교전 무대는 `game_phase = ENGAGE` 로도 막히지만, 그 앞의
##     결정 구간은 이 가드만이 막는다).
##
## 자동 틱과 MM:SS 시계가 같은 답을 읽어야 화면의 시간과 실제 턴이 어긋나지
## 않는다.
func _battle_tick_held() -> bool:
	if _ai_turn_active():
		return true
	return objective != null and objective.is_busy()


# Smooth in-game seconds, derived from completed turns + fractional progress
# through the current 0.5s real-time tick. 1 turn = 1 in-game minute = 60 sec.
# Frozen during CARD_PHASE / 상대 차례 / game_over so the clock matches the
# paused sim.
func get_elapsed_ingame_seconds() -> int:
	var base: int = turn_count * 60
	if game_over or game_phase != GameEnums.BattlePhase.BATTLE or _battle_tick_held():
		return base
	var frac: float = clamp(1.0 - auto_play_timer / AUTO_PLAY_INTERVAL, 0.0, 1.0)
	return base + int(frac * 60.0)


# ─── Respawn timing ──────────────────────────────────────────────────────────
## 이번 사망에 걸리는 리스폰 턴 수. 초반 사망은 싸게, 후반 사망은 비싸게 —
## `RESPAWN_TURNS`(기본 5) 에 경과 턴의 1/10 을 더한다. 예전에는 DB 값 하나가
## 전 구간에 그대로 쓰여서(16턴) 개전 직후 한 번 죽으면 초반 라인전이 통째로
## 날아갔다.
##
## **모든 사망 판정은 이 함수를 통과해야 한다** — 전장 교전, 공격 카드, 교전
## 아레나가 각자 `RESPAWN_TURNS` 를 직접 읽으면 스케일링이 한쪽에만 붙는다.
const RESPAWN_TURN_SCALE_DIV: int = 10

func respawn_turns_now() -> int:
	@warning_ignore("integer_division")
	var scaled: int = turn_count / RESPAWN_TURN_SCALE_DIV
	return max(1, RESPAWN_TURNS + scaled)


## 전장 밖 파일럿이 나오기까지 남은 턴 수. 살아 있으면 0.
##
## 파일럿이 전장을 비우는 사유는 **사망뿐**이므로 이 값은 곧 `respawn_timer` 다
## (복귀는 HQ 에 선 채로 처리되어 `alive` 를 건드리지 않는다). UI(카드 잠금
## 표시)와 로그는 타이머를 직접 읽지 말고 이 함수를 거친다 — 돌아오기 직전
## 틱에도 최소 1 을 돌려줘서 카드가 깜빡이며 풀리지 않게 한다.
func turns_until_return(p: PilotData) -> int:
	if p == null or p.alive:
		return 0
	return maxi(1, p.respawn_timer)


## The one place a pilot dies. Zeroes HP, takes them off the field, stamps the
## scaled respawn timer and starts the 전사 연출. Every damage source funnels
## through here so the respawn scaling and the death animation can never be
## wired into one path and forgotten in another.
##
## `killer` 는 **성장치 정산 전용**이다. 계획 살인 현상금은 예나 지금이나
## "쓰러진 파일럿의 반대 팀"으로 충분하지만(전장에 제3세력이 없다), 성장치는
## 개인 지표라 실제로 마지막 타격을 넣은 파일럿을 알아야 한다. 모르면 null 을
## 넘긴다 — 포탑 처치가 그런 경우이고, 그때도 어시스트는 지급된다.
##
## **사망 자체에는 점수 벌점이 없다.** 벌점은 죽어 있는 동안 전선 수입과 캠프가
## 통째로 멈추는 것 — 그것이 리스폰 턴 수(경기 후반일수록 길어진다)에 비례하는
## 진짜 비용이다. 예전의 −0.10k 는 25k 스케일에서 아무 의미가 없는 데다 같은
## 손해를 두 번 매기는 것이었다.
func mark_pilot_dead(p: PilotData, killer: PilotData = null) -> void:
	p.hp            = 0
	p.alive         = false
	p.recall_hold   = false   # 복귀 대기 중 죽으면 대기도 함께 사라진다
	p.shield        = 0
	p.respawn_timer = respawn_turns_now()
	p.atk_buff      = 0   # 카드가 걸어 둔 일시 공격력은 죽으면 사라진다
	p.deaths += 1
	if killer != null and killer.team != p.team:
		killer.kills += 1
	anim_pilot_death(p)
	# **`_payout_kill_bounty` 보다 먼저** — 어시스트 명단이 `damage_credit`
	# 에서 나오는데 그 정산이 장부를 비운다. 파일럿 스킬의 처치 관여 훅도
	# 같은 장부를 읽으므로 같은 이유로 이 앞에 선다.
	_push_kill_feed(p, killer)
	if skill != null:
		skill.on_kill(p, killer)
	if mech_skill != null:
		mech_skill.on_kill(p, killer)
	_award_kill_bounty(p.team)
	_payout_kill_bounty(p, killer)


## 킬로그 한 줄. 막타(`killer`)를 앞에 세우고, 같은 대상에게 피해를 넣은 나머지를
## **피해가 큰 순**으로 어시스트에 붙인다 — 성장치 어시스트 배분과 같은 표를
## 읽으므로 화면에 뜬 얼굴과 점수를 받은 얼굴이 어긋나지 않는다.
##
## `killer` 가 null 로 들어오는 경로가 있다(라스트힛을 적어 두는
## `SimulationCore._last_hitter` 는 매 턴 비워진다). 그때는 가장 많이 때린
## 사람을 막타 자리에 세운다 — 빈 칸을 두는 것보다 낫다.
func _push_kill_feed(victim: PilotData, killer: PilotData) -> void:
	if kill_feed == null:
		return
	var credit: Dictionary = live_damage_credit(victim)
	var contributors: Array = credit.keys()
	contributors.sort_custom(func(a: PilotData, b: PilotData) -> bool:
		return float(credit[a]) > float(credit[b]))
	var last_hit: PilotData = killer
	if last_hit == null and not contributors.is_empty():
		last_hit = contributors[0] as PilotData
	var assists: Array = []
	for raw in contributors:
		var a := raw as PilotData
		if a != last_hit:
			assists.append(a)
	kill_feed.push_kill(last_hit, victim, assists)


## 계획 살인의 지급 지점. 전장에는 제3세력이 없으므로 "누가 죽였는가"를 따로
## 넘겨받을 필요가 없다 — 쓰러진 파일럿의 **반대 팀**이 처치자다. 예약해 둔
## 현상금이 있으면 한 번 지급하고 곧바로 소모한다(카드 한 장 = 처치 한 번).
func _award_kill_bounty(dead_team: int) -> void:
	if dead_team == 1:
		if kill_bounty_p > 0:
			player_cost += kill_bounty_p
			kill_bounty_p = 0
	elif kill_bounty_ai > 0:
		ai_cost += kill_bounty_ai
		kill_bounty_ai = 0


# ─── 성장치 (파일럿 점수) ────────────────────────────────────────────────────
# 파일럿의 **성장 통화**. MOBA 의 골드에 해당하고, 개시 1.00k 에서 시작해 50턴
# 평균 25.00k / 잘 큰 캐리 40.00k 을 넘긴다. 파일럿 스트립의 체력 바 아래에
# 찍히고, 상단 중앙의 팀 점수는 그 팀 다섯 명의 **합산**이다(개시 5.00k).
# 상한이 없으므로 게이지가 아니라 숫자로만 보여 준다.
#
# **성장(`PilotData.growth`)은 이 값에서 파생된다** — `refresh_growth_stats`.
# 예전에는 둘이 완전히 무관해서(성장은 시간 경과, 성장치는 표시용 기록) 킬을
# 따도 포탑을 밀어도 스탯이 1도 변하지 않았고, 게다가 `atk` 와 `max_hp` 가 같은
# 비율로 자라 교전 타수가 영원히 그대로였다.
#
# 적립처는 셋뿐이다.
#   • **전선 체류** — 살아서 자기 레인의 전선(양 팀 최전방 포탑 사이) 안에
#     서 있는 턴마다 `SCORE_FRONTLINE_PER_TURN`. 수입의 60%가 여기서 나온다.
#   • **정글 캠프** — 정글러가 자기 팀 소유(또는 중립) 정글 칸의 살아 있는
#     캠프를 밟으면 `SCORE_JUNGLE_CAMP`. 캠프는 `JUNGLE_CAMP_RESPAWN_TURNS`
#     마다 되살아나므로 정글러는 쉬지 않고 순회해야 라이너만큼 번다.
#   • **처치 현상금** — 라스트힛이 전액, 그 대상에게 피해를 넣은 아군이
#     피해 비례로 최대 50%를 더 받는다(어시스트). 아래 `mark_pilot_dead`.
#
# 포탑/HQ **피해**는 더 이상 점수를 주지 않는다 — 피해가 고정 2 로 바뀌면서
# 한 경기에 굴러 봐야 0.01k 수준이라 노이즈였다. 대신 **철거**에 한 번 지급한다.
## 개시값.
const SCORE_START: float = 1.0
## 아무리 죽어도 여기 아래로는 내려가지 않는다.
const SCORE_MIN: float = 0.10
## 전선 안에 살아서 서 있는 1턴당 적립. **이 값 하나가 성장 속도의 주 노브다.**
##
## 0.50 은 헤드리스 실측에서 역산한 값이다. 목표는 "50턴에 평균 25k(= atk ×3)"
## 이고, 파일럿이 실제로 전선에서 버는 턴은 50턴 중 약 46턴(HQ 에서 걸어 나오는
## 초반 몇 턴과 복귀·사망 구간이 빠진다) → 24k / 46 ≈ 0.52.
##
## 처음에는 "전선 15k + 킬 8k = 25k" 를 겨냥해 0.35 로 잡았는데, 실측이 두 가정을
## 모두 비껴갔다 — 전선 체류율이 예상보다 높아 전선만으로 17.8k 를 벌었고(예상
## 15k), 반대로 **킬이 거의 안 났다**(전장 자동 교전은 `BATTLE_PILOT_DMG_MULT`
## 0.35 때문에 한 대에 2~9 밖에 안 들어가 라인전만으로는 사람이 죽지 않는다.
## 처치는 사실상 교전·공격 카드에서만 나오므로 플레이어가 얼마나 싸우느냐에
## 통째로 달려 있다). 그래서 **아무도 싸우지 않은 하한선**이 목표에 닿도록
## 전선 수입을 올리고, 킬은 그 위에 얹히는 가속으로 둔다.
const SCORE_FRONTLINE_PER_TURN: float = 0.50
## 정글 캠프 1개. **라이너의 턴당 수입(0.50)보다 훨씬 크다** — 캠프를 먹으려면
## 그 칸까지 걸어가야 하고 재생성을 기다려야 하므로, 캠프당 값이 같으면
## 정글러의 턴당 수입은 구조적으로 라이너보다 낮다.
##
## 0.65 는 헤드리스 실측에서 역산한 값이었다. 기준선은 **"50턴 · 포탑이 하나도
## 안 부서지고 적 정글도 안 뺏은"** 판이다(포탑을 불사로 만들어 T1 파괴 보상과
## 전선 확장을 둘 다 없앤 4회 평균): 캠프값 0.50 · 재생성 4턴에서 정글러 18.4k /
## 라이너 평균 23.5k = **0.78배**였고, 필요한 배수 22.45 / 17.375 = 1.29 를
## 곱해 0.65 가 나왔다(적용 후 0.98배).
##
## **재생성이 4턴 → 6턴으로 늦춰지면서 0.98 로 다시 올렸다.** 캠프 획득 빈도가
## 그대로 재생성 주기에 반비례하므로(정글러 수입은 전부 캠프다) 주기를 1.5배로
## 늘리면 값도 1.5배여야 같은 수입이 나온다: 0.65 × 1.5 ≈ 0.98. 늦춘 것은
## **순회 리듬**이지 정글러의 몫이 아니다 — 한 칸이 되살아나기를 더 오래 기다리는
## 대신 한 번 먹을 때 더 크게 먹는다.
##
## 적 정글까지 점령하면 돌 캠프가 늘어 라이너를 추월한다 — 그것이 정글 점령의
## 값이고, 이 상수는 **점령이 없는 하한선**을 라이너와 나란히 놓을 뿐이다.
##
## 한때 1.15 였다 — 좌우 중립 두 칸이 오브젝트 전용 자리가 되어 캠프가 서는 칸이
## 14 → 12 로 줄었을 때 그 몫(× 14/12)을 얹은 값이다. 두 칸이 다시 평범한 정글
## 칸으로 돌아오면서(캠프도, 점령도 그대로다) 그 보정은 근거를 잃어 0.98 로
## 되돌렸다. 전령 / 용은 **같은 자리를 무대로 빌려 쓸 뿐** 캠프를 밀어내지 않는다.
const SCORE_JUNGLE_CAMP: float = 0.98
## 캠프가 다시 차오르기까지의 턴 수. 4턴은 한쪽 정글(4칸)에서 **매 턴 정확히
## 한 칸**이 되살아나 정글러가 발밑을 뜰 이유가 없었다 — 6턴이면 그 칸이
## 비어 있는 구간이 생겨 반대쪽으로 넘어가는 순회가 강제된다.
const JUNGLE_CAMP_RESPAWN_TURNS: int = 6
## **방치 할인** — 차 있는 채로 놀고 있는 캠프가 거리 한 칸을 되사는 데 걸리는
## 턴 수. 정글러의 목표 선택(`SimulationCore._best_ready_camp`)은 거리에서
## `방치 턴 / 이 값` 을 뺀 값이 가장 작은 캠프를 고르므로, 멀리 있어 계속
## 미뤄지던 캠프도 언젠가는 가장 싼 목표가 된다.
##
## 이것이 없으면 정글러는 **자기 발밑 4칸에 갇힌다**: 한쪽 정글이 4칸이라
## 재생성 주기가 그 칸 수에 가까우면 매 턴 한 칸이 되살아나고, 거리만 보는 그리디는
## 언제나 거리 1짜리 캠프를 찾아내고 반대쪽 정글은 개시부터 끝까지 캠프가 꽉
## 찬 채로 남는다(실측: 팀0 정글러가 30턴 동안 (0,0)/(0,-1)/(1,0) 을 한 번도
## 밟지 않았다). 할인이 붙으면 방치된 쪽이 주기적으로 가장 싸져 정글러가
## 좌우를 오가는 **순회**가 된다.
const JUNGLE_CAMP_STALE_PER_STEP: int = 3
## 처치 기본 현상금 — 누구를 잡아도 이만큼은 나온다.
const SCORE_KILL_BASE: float = 1.5
## 앞서가는 적 현상금. 피해자가 처치자 팀 평균보다 앞선 만큼의 이 비율이
## 기본값 위에 얹힌다. 10k 앞선 에이스를 잡으면 1.5 + 2.0 = 3.5k.
const SCORE_KILL_BOUNTY_RATE: float = 0.20
## 어시스트 전원이 나눠 갖는 현상금의 상한 비율. 각자의 몫은
## `현상금 × 0.5 × (내 피해 / 그 대상이 이번 생에 받은 총 피해)` 라, 라스트힛만
## 넣고 딜을 안 넣은 파일럿과 끝까지 두들긴 파일럿이 구분된다.
const SCORE_ASSIST_MAX_SHARE: float = 0.50
## 포탑 한 기를 처음부터 끝까지 갈아 냈을 때 그 레인이 벌어 가는 성장치 총액.
##
## 예전에는 이 값이 **철거하는 순간** 마지막 한 대를 넣은 파일럿에게 통째로
## 갔다(`SCORE_TURRET_KILL`). 그러면 8턴 동안 밀어붙인 파일럿과 마지막 2 를
## 넣은 파일럿의 몫이 같았고, 포탑을 반쯤 갈아 놓고 죽은 사람은 한 푼도 못
## 받았다 — 공성은 한 번의 사건이 아니라 여러 턴에 걸친 노동이다. 지금은
## **깎아 낸 체력 1점당**으로 쪼개 실제로 민 만큼 나눠 갖는다
## (`score_turret_damage`). 총액은 그대로라 포탑 하나의 값어치는 안 달라졌다.
const SCORE_TURRET_FULL: float = 1.0
## 처치 관여(어시스트)가 살아 있는 기간(턴). 이보다 오래된 피해는 현상금
## 배분에서도 킬로그 명단에서도 빠진다 — 20턴 전에 한 대 긁어 놓은 것이
## 지금의 처치에 지분을 갖는 것은 "관여"가 아니다. 판정은
## `live_damage_credit` 한 곳뿐이고 만료된 기록은 그 자리에서 지워진다.
const SCORE_ASSIST_WINDOW_TURNS: int = 15

# ─── 성장치 팝업 (전장 초상화 위) ────────────────────────────────────────────
# 성장치가 오르는 자리 중 **한 번에 크게 들어오는 것**만 초상화 위에 숫자로
# 띄운다 — 처치 현상금(막타 · 어시스트), 포탑 피해, 그리고 교전에서 번 총액.
# 전선 체류(턴당 0.50k)와 정글 캠프는 뺐다: 매 턴 열 명의 얼굴 위에서 숫자가
# 튀면 그게 곧 배경이 되어 정작 큰 한 건이 묻힌다.
#
# 진입점은 `award_score` 하나이고, 조용히 적립만 하는 `add_score` 와 그 한 겹이
# 갈라져 있다 — 어느 적립처가 화면에 뜨는지가 호출부에서 읽혀야 한다.
## 팝업 글자색 — 성장치 숫자(스트립)와 같은 계열의 금색.
const SCORE_POPUP_COLOR := Color(1.00, 0.86, 0.36)
## 화면에 머무는 시간(s). 피해 숫자(0.30초)보다 한참 길다 — 피해는 연속 타격의
## 리듬에 맞춰 스쳐 가면 되지만 성장치는 **읽으라고 띄우는 값**이다.
const SCORE_POPUP_DUR := 1.10
## 떠오르는 높이(px). 피해 숫자(46)보다 높이 떠서 같은 얼굴 위에 둘이 동시에
## 떠도 서로를 덮지 않는다.
const SCORE_POPUP_RISE_PX := 72.0

# ─── 성장 환산 (성장치 → 스탯) ───────────────────────────────────────────────
# **공격력이 체력의 4배 속도로 자란다.** 이 비대칭이 성장 체감의 전부다 —
# 둘이 같은 비율이면 `atk/max_hp` 가 불변이라 "몇 대 맞아야 죽는가"가 50턴이
# 지나도 1타도 안 줄어든다(예전 설계의 구조적 결함).
#
# 기준점: 성장치 25k(= 개시분을 뺀 24k) 에서 **공격력 ×3.0 / 최대 체력 ×1.5**.
# 격투가 atk 16 → 48, 탱커 hp 220 → 330 이라 교전 타수가 14타 → 7타로 준다.
# 스나이퍼(hp 75 → 113)는 3타에 무너지고, 40k 캐리는 ×4.25 로 2타에 끝낸다.
const GROWTH_ATK_PER_SCORE: float = 2.0 / 24.0   # +8.33%p / 1k
const GROWTH_HP_PER_SCORE:  float = 0.5 / 24.0   # +2.08%p / 1k


## 모든 성장치 변동이 지나는 한 지점. 하한만 지키고(상한 없음), **적립 배율**
## (안전한 파밍 / 완벽한 마무리)은 늘어나는 쪽에만 곱한다.
##
## 곧바로 스탯을 다시 계산하는 것이 요점이다 — 성장이 턴 경계가 아니라 점수가
## 움직인 그 순간에 붙어야 "킬을 땄더니 세졌다"가 한 박자로 읽힌다.
##
## **실제로 오른 만큼**을 돌려준다(하한과 적립 배율이 먹은 뒤의 값). 화면에
## 띄우는 쪽(`award_score`)이 요청한 값이 아니라 들어간 값을 보여야 하기
## 때문이고, 그 밖의 호출부는 그냥 무시하면 된다.
func add_score(p: PilotData, delta: float) -> float:
	if p == null or is_zero_approx(delta):
		return 0.0
	if delta > 0.0:
		# 만료형 슬롯(`growth_rate_mult`) + 영구 가산분(`growth_rate_bonus`, 용
		# 보상) + 파일럿 스킬 가산분(축적 / 사냥의 보상 / 위치 고정 / 경쟁 심리).
		# 셋을 합쳐 한 번에 곱하므로 라인전 카드가 오브젝트 보상이나 스킬을
		# 덮어쓰지 않는다 — PilotData.growth_rate_bonus 주석 참조.
		var skill_add: float = skill.growth_rate_add(p) if skill != null else 0.0
		delta *= p.growth_rate_mult + p.growth_rate_bonus + skill_add
	# 매혹([매혹] 카드) — 이 파일럿이 버는 만큼을 걸어 둔 쪽이 **그대로 한 벌
	# 더** 번다. 복사이지 이전이 아니라서 원래 주인의 몫은 줄지 않는다. 복사본에
	# 다시 링크가 걸려 있어도 한 겹에서 끊는다(`_score_link_depth`) — A→B→A 같은
	# 고리가 생기면 무한 재귀가 되기 때문이다.
	if p.growth_link_to != null and _score_link_depth == 0:
		_score_link_depth = 1
		add_score(p.growth_link_to, delta)
		_score_link_depth = 0
	var before: float = p.score
	p.score = maxf(SCORE_MIN, p.score + delta)
	refresh_growth_stats(p)
	return p.score - before


## `add_score` 에 **전장 초상화 팝업**을 붙인 판. 성장치가 크게 움직이는 자리
## (처치 현상금 · 어시스트 · 포탑 피해)는 전부 이쪽을 지난다.
##
## 죽어 있는 파일럿에게는 띄우지 않는다 — 시신은 1.45초 뒤 전장을 뜨고, 그
## 뒤에 뜬 숫자는 아무 얼굴 위에도 서 있지 않다. 어시스트는 자기가 죽은
## 뒤에도 들어오므로 실제로 걸리는 경로다.
func award_score(p: PilotData, delta: float) -> float:
	var applied: float = add_score(p, delta)
	if applied > 0.0:
		_show_score_gain(p, applied)
	return applied


## 팝업 한 장. **교전이 도는 동안은 띄우지 않고 쌓아 둔다** — 아레나가 화면을
## 통째로 덮고 있어 지금 띄워 봐야 아무도 못 보고, 팝업 좌표는 띄운 순간의
## 마커 자리에 고정되므로 무대가 치워질 때쯤엔 엉뚱한 곳에 떠 있다. 킬로그가
## 같은 이유로 같은 짓을 한다(`KillFeed._pending`).
func _show_score_gain(p: PilotData, amount: float) -> void:
	if p == null or amount <= 0.0:
		return
	if engage_phase != null and engage_phase.is_active():
		_score_popup_hold[p] = float(_score_popup_hold.get(p, 0.0)) + amount
		return
	if not p.alive or renderer == null:
		return
	renderer.spawn_score_popup(p, amount)


## 교전이 닫히는 순간 `EngagePhaseManager._on_dashboard_confirmed` 가 부른다.
## 그 교전 동안 번 것을 **파일럿마다 한 장으로 합쳐** 띄운다 — 라운드마다
## 처치가 났다고 숫자가 세 번 뜨면 "이 교전에서 얼마를 벌었나"를 도리어 더하게
## 된다. 쓰러진 파일럿은 건너뛴다.
func flush_score_popups() -> void:
	for raw in _score_popup_hold.keys():
		var p := raw as PilotData
		if p != null and p.alive and renderer != null:
			renderer.spawn_score_popup(p, float(_score_popup_hold[p]))
	_score_popup_hold.clear()


## 성장치에서 `atk` / `max_hp` 를 **원본에서 다시 계산**한다. 매 턴 곱해 나가는
## 대신 이렇게 하는 이유는 그때나 지금이나 같다 — 반올림이 반복되면 누적 오차가
## 실제 성장률을 갉아먹는다.
##
## 최대 체력이 오른 만큼 현재 체력도 같이 올려 준다(성장이 만피 파일럿을
## 상대적으로 다치게 하지 않는다). 카드가 건 일시 공격력은 `atk_buff` 로 따로
## 들고 있다가 마지막에 더한다 — `atk` 를 직접 밀면 이 재계산에 지워진다.
func refresh_growth_stats(p: PilotData) -> void:
	if p == null:
		return
	var gained: float = maxf(0.0, p.score - SCORE_START)
	p.growth    = gained * GROWTH_ATK_PER_SCORE
	p.growth_hp = gained * GROWTH_HP_PER_SCORE
	# 파일럿 스킬의 스탯 배율은 **여기**에 얹는다 — `atk` 를 직접 밀면 다음
	# 재계산에 통째로 지워지고, 충전이 오르내릴 때마다 원본이 깎여 나간다.
	var s_atk: float = skill.atk_mult(p) if skill != null else 1.0
	var s_hp:  float = skill.hp_mult(p)  if skill != null else 1.0
	# 메크가 쌓는 **영구** 보정도 같은 자리에 얹는다 — 고정분은 성장 배율 밖에서
	# 더하고(공격력 +1 은 성장률에 따라 커지는 값이 아니다), 배율분만 성장과 함께
	# 곱해진다. 탱커 E(과적재)는 최대 체력에서 공격력을 파생시키므로 **체력을 먼저
	# 확정한 뒤** 공격력을 다시 계산한다.
	var m_atk: float = mech_skill.atk_mult(p) if mech_skill != null else 1.0
	var new_max: int = maxi(1, roundi(
			float(p.base_max_hp) * (1.0 + p.growth_hp) * s_hp)) + p.bonus_max_hp
	p.atk = maxi(1, roundi(float(p.base_atk) * (1.0 + p.growth)
			* s_atk * m_atk * (1.0 + p.bonus_atk_mult))) 			+ p.bonus_atk_flat + p.atk_buff
	if mech_skill != null:
		p.atk += mech_skill.bulk_power_atk(p, new_max)
	if new_max != p.max_hp:
		# 죽어 있는 파일럿의 현재 체력은 0 으로 둔다 — 쓰러진 뒤에도 점수가
		# 들어올 수 있고(자기가 때려 둔 적이 나중에 죽으면 어시스트가 붙는다)
		# 그때 최대 체력이 오르면서 hp 가 1 이상으로 되살아나면 스트립과 카드
		# 잠금 표시가 살아 있는 것처럼 읽힌다. 부활은 `process_respawns` 가
		# 만피로 세워 준다.
		if p.alive:
			p.hp = maxi(1, p.hp + (new_max - p.max_hp))
		p.max_hp = new_max


## 팀 평균 성장치. 처치 현상금이 "얼마나 앞선 적인가"를 재는 기준선이다.
func team_avg_score(team: int) -> float:
	var total: float = 0.0
	var n: int = 0
	for raw in pilots:
		var p := raw as PilotData
		if p.team == team:
			total += p.score
			n += 1
	return total / float(n) if n > 0 else SCORE_START


## 피해 한 건을 **피해자의 장부**에 적는다. 점수는 여기서 나가지 않는다 —
## 어시스트는 그 대상이 실제로 쓰러졌을 때만 정산되기 때문이다(MOBA 와 같다).
## 전장 자동 교전 · 교전 무대 · 공격 카드가 전부 이 한 지점을 지난다.
##
## 적는 값은 **굴린 피해 전체**다 — 보호막에 먹힌 몫도 기여이고, 오버킬 몇 점이
## 비율을 흔들지도 않는다.
## 적는 값에는 **턴 도장**이 함께 찍힌다 — 같은 턴의 피해는 한 항목으로 합치고,
## `SCORE_ASSIST_WINDOW_TURNS` 이 지난 항목은 `live_damage_credit` 이 지운다.
func record_pilot_damage(attacker: PilotData, victim: PilotData, amount: int) -> void:
	if attacker == null or victim == null or amount <= 0:
		return
	if attacker.team == victim.team:
		return
	var entries: Array = victim.damage_credit.get(attacker, [])
	if not entries.is_empty() and (entries[-1] as Vector2i).x == turn_count:
		entries[-1] = (entries[-1] as Vector2i) + Vector2i(0, amount)
	else:
		entries.append(Vector2i(turn_count, amount))
	victim.damage_credit[attacker] = entries


## 지금 이 순간 유효한 기여만 남긴 `공격자 → 누적 피해` 표. 현상금 배분 ·
## 킬로그 명단 · 파일럿 스킬의 처치 관여 훅이 **전부 이 함수 하나**를 읽는다 —
## 만료 규칙이 세 군데에 흩어지면 화면에 뜬 얼굴과 점수를 받은 얼굴이 갈린다.
##
## 만료된 항목은 읽는 김에 실제로 지운다(항목이 하나도 안 남은 공격자는 키째
## 지운다). 기록은 턴 순서대로 쌓이므로 앞에서부터 걷어 내면 된다.
func live_damage_credit(victim: PilotData) -> Dictionary:
	var out: Dictionary = {}
	if victim == null:
		return out
	# 턴 T 의 피해는 T + WINDOW 턴이 되는 순간 사라진다.
	var cutoff: int = turn_count - SCORE_ASSIST_WINDOW_TURNS
	for raw in victim.damage_credit.keys():
		var entries: Array = victim.damage_credit[raw]
		while not entries.is_empty() and (entries[0] as Vector2i).x <= cutoff:
			entries.pop_front()
		if entries.is_empty():
			victim.damage_credit.erase(raw)
			continue
		var total: int = 0
		for e in entries:
			total += (e as Vector2i).y
		out[raw] = total
	return out


## 처치 현상금 정산. 라스트힛(`killer`)이 전액을 받고, 그 대상에게 피해를 넣은
## 다른 아군이 **피해 비례로 최대 `SCORE_ASSIST_MAX_SHARE`** 를 더 받는다.
## 분모는 피해자가 이번 생에 받은 총 피해라, 라스트힛이 딜의 대부분을 넣었다면
## 어시스트 총합은 50% 에 한참 못 미친다.
##
## `killer` 가 null 이어도(포탑 처치) 어시스트는 지급된다 — 끝까지 두들긴
## 사람에게 아무것도 안 주는 쪽이 더 이상하다.
func _payout_kill_bounty(victim: PilotData, killer: PilotData) -> void:
	var killer_team: int = killer.team if killer != null else 1 - victim.team
	var lead: float = maxf(0.0, victim.score - team_avg_score(killer_team))
	var bounty: float = SCORE_KILL_BASE + lead * SCORE_KILL_BOUNTY_RATE
	# **만료를 지난 피해는 분모에도 안 들어간다** — 15턴 전에 긁어 놓은 딜이
	# 분모를 부풀리면 정작 지금 잡은 사람들의 몫이 조용히 깎인다.
	var credit: Dictionary = live_damage_credit(victim)
	var total_dmg: float = 0.0
	for raw in credit.keys():
		total_dmg += float(credit[raw])
	if killer != null:
		award_score(killer, bounty)
	if total_dmg > 0.0:
		for raw in credit.keys():
			var a := raw as PilotData
			if a == killer:
				continue
			var share: float = float(credit[a]) / total_dmg
			award_score(a, bounty * SCORE_ASSIST_MAX_SHARE * share)
	victim.damage_credit.clear()


## 포탑 피해 한 건의 성장치 적립. `hp_removed` 는 **실제로 깎인 체력**이다 —
## 오버킬까지 값으로 치면 마지막 한 대에 인원이 몰릴수록 포탑 총액이 불어난다.
##
## 한 점당 값은 `SCORE_TURRET_FULL / TURRET_HP` 라, 한 기를 통째로 갈아 내면
## 예전의 철거 일시불과 정확히 같은 총액이 나온다(지금 설정 = 체력 16 · 고정
## 피해 2 이므로 한 대에 0.13k, 여덟 대에 1.0k).
func score_turret_damage(attacker: PilotData, hp_removed: int) -> void:
	if attacker == null or hp_removed <= 0:
		return
	award_score(attacker, SCORE_TURRET_FULL * float(hp_removed)
			/ float(maxi(1, TURRET_HP)))


## 포탑 철거. `td` 는 킬로그가 어느 포탑인지를 그리는 데만 쓴다.
##
## **여기서는 성장치가 나가지 않는다** — 포탑의 몫은 갈아 내는 동안 이미
## `score_turret_damage` 로 다 나갔다. 남은 일은 킬로그 한 줄과 사건 훅이다.
func score_turret_kill(attacker: PilotData, td: TurretData = null) -> void:
	if kill_feed != null:
		kill_feed.push_turret(attacker, td)
	if skill != null:
		skill.on_turret_destroyed(attacker)
	if mech_skill != null:
		mech_skill.on_turret_destroyed(attacker, td)



## 팀 합산 성장치. 상단 중앙 점수표가 읽는다 — 죽어 있는 파일럿도 포함한다
## (점수는 전장에 서 있는지와 무관한 누적 기록이다).
func team_score(team: int) -> float:
	var total: float = 0.0
	for raw in pilots:
		var p := raw as PilotData
		if p.team == team:
			total += p.score
	return total


## 성장치 표기. 1.0 → "1.00k". 소수 둘째 자리까지 — 피해 100 이 0.01k 라
## 한 자리로 자르면 한참을 싸워도 숫자가 안 움직이는 것처럼 보인다.
static func fmt_score(v: float) -> String:
	# 소수 둘째 자리는 개시 구간(1.00k 대)에서 숫자가 움직이는 것을 보여 주기
	# 위한 것이다. 후반에는 자릿수가 늘어 `24.90k` / 팀 합산은 `124.50k` 까지
	# 가는데, 스트립 칸이 좁아 한 자리로 줄인다 — 그 구간에서는 0.05k 의 변화가
	# 어차피 안 읽히고, 자릿수가 밀려 옆 칸을 침범하는 쪽이 훨씬 나쁘다.
	if absf(v) >= 100.0:
		return "%.0fk" % v
	if absf(v) >= 10.0:
		return "%.1fk" % v
	return "%.2fk" % v


# ─── Pilot animation driver ──────────────────────────────────────────────────
# Returns true if at least one pilot is currently animating.
func _advance_pilot_animations(delta: float) -> bool:
	var any_active := false
	for raw in pilots:
		var p := raw as PilotData
		if p.anim_death_phase != 0:
			p.anim_death_t += delta
			if p.anim_death_t >= p.anim_death_dur:
				if p.anim_death_phase == 1:
					# 딤드 대기 끝 → 투명해지며 상승.
					p.anim_death_phase = 2
					p.anim_death_t     = 0.0
					p.anim_death_dur   = ANIM_DEATH_FADE_DUR
				else:
					p.anim_death_phase = 0
					p.anim_death_t     = 0.0
					p.anim_death_dur   = 0.0
			any_active = true
		# 이동 연출에는 여기 타이머가 없다 — 마커 좌표의 보간은 렌더러가
		# 통째로 쥐고 있고(BattleRenderer._glide), 재draw 도 거기서 걷어찬다.
		if p.anim_shake_dur > 0.0:
			p.anim_shake_t += delta
			if p.anim_shake_t >= p.anim_shake_dur:
				p.anim_shake_dur = 0.0
				p.anim_shake_t   = 0.0
			any_active = true
		if p.anim_recall_phase != 0:
			p.anim_recall_t += delta
			if p.anim_recall_t >= p.anim_recall_dur:
				if p.anim_recall_phase == 1:
					# Phase 1 done → start fade-in at HQ.
					p.anim_recall_phase = 2
					p.anim_recall_t     = 0.0
					p.anim_recall_dur   = ANIM_RECALL_FADE_IN_DUR
				else:
					p.anim_recall_phase = 0
					p.anim_recall_t     = 0.0
					p.anim_recall_dur   = 0.0
			any_active = true
		if p.anim_cast_dur > 0.0:
			p.anim_cast_t += delta
			if p.anim_cast_t >= p.anim_cast_dur:
				p.anim_cast_dur = 0.0
				p.anim_cast_t   = 0.0
			any_active = true
	return any_active


# Triggered by SimulationCore when a pilot moves cell. `from_cell` is the cell
# the pilot was on before the move.
#
# **한 걸음씩 들어온다.** 같은 프레임에 여러 번 불리면(전진 카드의 N틱) 경로를
# 이어 붙여 렌더러가 실제로 밟은 칸을 따라 미끄러지게 한다 — 마지막 걸음만 남기면
# 3칸 전진이 2칸을 순간이동한 뒤 1칸만 걷는 그림이 된다. 렌더러는 경로를 읽는
# 즉시 비우므로, 턴을 넘긴 다음 이동은 빈 배열에서 새로 시작한다.
func anim_pilot_move(p: PilotData, from_cell: Vector2i) -> void:
	if from_cell == p.grid_pos:
		return
	# Skip the glide if the pilot is mid-recall (recall takes priority).
	if p.anim_recall_phase != 0:
		return
	if not p.anim_move_path.is_empty() \
			and p.anim_move_path[p.anim_move_path.size() - 1] == from_cell:
		p.anim_move_path.append(p.grid_pos)
	else:
		p.anim_move_path.assign([from_cell, p.grid_pos])


## 한 턴치 이동을 **경로 통째로** 넘기는 진입점. `SimulationCore.resolve_movement`
## 이 락스텝 라운드마다 밟은 칸을 모아 한 번에 부른다 — 걸음마다
## `anim_pilot_move` 를 부르는 것과 결과는 같지만, 그쪽 패스는 커밋을 모아
## 처리하므로 경로도 모아서 넘기는 편이 배선이 짧다.
func anim_pilot_move_path(p: PilotData, cells: Array) -> void:
	if cells.size() < 2:
		return
	if p.anim_recall_phase != 0:
		return
	p.anim_move_path.assign(cells)


## 피격 흔들림. 인자를 비우면 **전장 자동 교전의 기본 세기**이고, 공격 카드는
## `ANIM_SHAKE_CARD_DUR` / `ANIM_SHAKE_CARD_AMP_PX` 를 넘겨 훨씬 격렬하게 흔든다 —
## 카드 한 장의 명중은 매 턴 자동으로 오가는 교전 피해와 무게가 다르다.
##
## 흔들림의 **주파수는 고정**이다(`BattleRenderer` 가 지속시간에 비례해 진동 수를
## 늘린다). 길게 흔들라는 지시가 "느리게 흔들라"로 읽히면 격렬함이 사라진다.
func anim_pilot_shake(p: PilotData, dur: float = ANIM_SHAKE_DUR,
		amp: float = ANIM_SHAKE_AMP_PX) -> void:
	p.anim_shake_t   = 0.0
	p.anim_shake_dur = dur
	p.anim_shake_amp = amp


# Recall sequence: fade out + rise at orig_cell, then fade in + descend at HQ.
#
# 복귀는 전장을 비우지 않으므로 두 반쪽이 늘 이어 붙는다 — 저HP / 위치 이탈
# 복귀와 복귀 card 가 같은 연출을 쓴다. (파일럿이 전장에서 사라지는 사유는
# 사망뿐이고, 그건 anim_pilot_death 가 맡는다.)
func anim_pilot_recall(p: PilotData, orig_cell: Vector2i) -> void:
	p.anim_move_path.clear()
	anim_pilot_cast_clear(p)
	p.anim_recall_orig    = orig_cell
	p.anim_recall_phase   = 1
	p.anim_recall_t       = 0.0
	p.anim_recall_dur     = ANIM_RECALL_FADE_OUT_DUR


# Respawn: skip phase 1; just fade in + descend at the pilot's HQ cell.
func anim_pilot_respawn(p: PilotData) -> void:
	p.anim_move_path.clear()
	anim_pilot_cast_clear(p)
	p.anim_recall_phase   = 2
	p.anim_recall_t       = 0.0
	p.anim_recall_dur     = ANIM_RECALL_FADE_IN_DUR
	# 쓰러진 자리에 남아 있던 시신 연출은 부활과 함께 걷는다.
	anim_pilot_death_clear(p)


# 전사 연출 — 쓰러진 셀에서 ANIM_DEATH_HOLD_DUR 동안 딤드된 채 남아 있다가
# 투명해지며 위로 떠올라 전장에서 사라진다. 로직상 파일럿은 이미 alive == false
# 이므로 이 연출은 순수 UI다: 렌더러가 anim_death_phase 를 보고 계속 그려 준다.
#
# 사망 판정을 내리는 모든 경로(전장 교전 / 전진 카드 / 공격 카드 / 교전 아레나)
# 에서 불러야 한다 — 안 부르면 예전처럼 파일럿이 그 프레임에 툭 사라진다.
func anim_pilot_death(p: PilotData) -> void:
	p.anim_move_path.clear()
	p.anim_recall_phase   = 0
	# 시전 도중에 쓰러질 수 있다(반격 · 계시 연쇄). 시신 위에 빛이 남아
	# 있으면 아직 무언가를 쏘는 중으로 읽히므로 걷어 낸다.
	anim_pilot_cast_clear(p)
	p.anim_death_cell     = p.grid_pos
	p.anim_death_phase    = 1
	p.anim_death_t        = 0.0
	p.anim_death_dur      = ANIM_DEATH_HOLD_DUR


func anim_pilot_death_clear(p: PilotData) -> void:
	p.anim_death_phase = 0
	p.anim_death_t     = 0.0
	p.anim_death_dur   = 0.0


# ─── 공격 카드 명중 연출 ─────────────────────────────────────────────────────
# 한 번의 타격이 두 박자다: **시전(빛이 솟는다) → 명중(파티클 + 쉐이크)**.
# 가운데의 피해 계산은 여기 없다 — 호출 측(`CardPhaseManager._effect_attack`)이
# 두 박자 사이에서 판정을 굴리고 피해를 넣고 팝업을 띄운다. 그래서 두 함수로
# 갈라져 있고, 둘 다 자기 박자가 끝날 때까지 await 할 수 있는 코루틴이다.
#
# 연속 공격(`repeat`)은 이 두 박자를 타수만큼 반복한다. 다음 카드는 마지막
# 여운이 끝나야 낼 수 있다(`CardPhaseManager._attack_anim_active`).

## 1단계 — 시전자 초상에서 하얀 빛이 솟아오른다. 초상 자체는 움직이지 않는다.
## 빛이 다 오를 때까지 기다렸다가 반환하므로 호출 측은 이 await 뒤에 피해를 넣는다.
func anim_pilot_cast(caster: PilotData) -> void:
	if caster == null or not caster.alive:
		return
	caster.anim_cast_t   = 0.0
	caster.anim_cast_dur = ANIM_CAST_DUR
	if renderer != null:
		renderer.queue_redraw()
	await get_tree().create_timer(ANIM_CAST_DUR).timeout


## 2단계 — 피격자 초상에서 파티클이 사방으로 퍼진다. 쉐이크는 피해를 실제로
## 넣는 `CardPhaseManager._apply_attack_damage` 가 따로 건다(전장 자동 교전과
## 같은 진입점을 쓰기 위해서다 — 여기서 같이 걸면 스킬이 거는 한 방까지
## 흔들린다). 파티클을 뿌린 뒤 여운만큼 기다리고 반환한다.
func anim_pilot_impact(target: PilotData) -> void:
	if renderer != null and target != null:
		renderer.spawn_pilot_burst(target)
	await get_tree().create_timer(ANIM_HIT_HOLD_SEC).timeout


## 시전 빛이 걸려 있지 않은 상태로 되돌린다. 사망 / 복귀 / 부활이 부른다 —
## 빛은 변위가 아니라서 남아 있어도 자리를 어긋나게 하지는 않지만, 시신이나
## HQ 로 순간이동한 초상 위에 빛이 계속 떠 있으면 무슨 일이 일어난 것처럼 읽힌다.
func anim_pilot_cast_clear(p: PilotData) -> void:
	p.anim_cast_t   = 0.0
	p.anim_cast_dur = 0.0


## 지금 프레임의 시전 빛 진행도(0..1). 걸려 있지 않으면 -1.
## `BattleRenderer._draw_pilot_cast_fx` 하나가 읽는다.
func pilot_cast_progress(p: PilotData) -> float:
	if p == null or p.anim_cast_dur <= 0.0:
		return -1.0
	return clampf(p.anim_cast_t / p.anim_cast_dur, 0.0, 1.0)


# ─── Turret animation driver ─────────────────────────────────────────────────
# 포탑 스프라이트는 렌더러가 그리는 게 아니라 BattleField/BuildingLayer 아래의
# `Building` 노드다. 그래서 피격 연출은 여기서 직접 그 노드의 position/modulate
# 를 흔든다 — 렌더러는 같은 `TurretData.anim_hit_*` 를 읽어 HP 바만 함께 흔든다.
# 파괴는 예전대로 `Building.queue_free()` 라 살아 있는 피격에만 연출이 붙는다.

## Building 노드의 기본 위치(셀 좌표 → 흔들리기 전 position). 연출 도중 다시
## 맞으면 진행 중인 오프셋을 기준으로 삼지 않도록 **처음 한 번만** 채운다.
var _turret_home_pos: Dictionary = {}


## 포탑이 피해를 입었을 때 호출한다 (파괴된 타격은 제외 — 스프라이트가 사라진다).
func anim_turret_hit(td: TurretData) -> void:
	if td == null:
		return
	td.anim_hit_t   = 0.0
	td.anim_hit_dur = ANIM_TURRET_HIT_DUR


# Returns true while at least one turret is still playing its hit reaction.
func _advance_turret_animations(delta: float) -> bool:
	var any_active := false
	for raw in turrets:
		var td := raw as TurretData
		if td == null or td.anim_hit_dur <= 0.0:
			continue
		td.anim_hit_t += delta
		var finished: bool = td.anim_hit_t >= td.anim_hit_dur
		if finished:
			td.anim_hit_t   = 0.0
			td.anim_hit_dur = 0.0
		_apply_turret_hit_visual(td, finished)
		any_active = true
	return any_active


# Pushes the current frame of the hit reaction onto the Building node: a
# decaying horizontal jitter plus a red flash that fades back to white.
func _apply_turret_hit_visual(td: TurretData, finished: bool) -> void:
	if building_registry == null:
		return
	var b: Building = building_registry.get_at(td.grid_pos)
	if b == null:
		return
	if not _turret_home_pos.has(td.grid_pos):
		_turret_home_pos[td.grid_pos] = b.position
	var home: Vector2 = _turret_home_pos[td.grid_pos] as Vector2
	if finished:
		b.position = home
		b.modulate = Color.WHITE
		return
	var t: float = clampf(td.anim_hit_t / td.anim_hit_dur, 0.0, 1.0)
	var decay: float = 1.0 - t
	b.position = home + Vector2(sin(t * TAU * 3.0) * ANIM_TURRET_HIT_AMP_PX * decay, 0.0)
	b.modulate = Color.WHITE.lerp(ANIM_TURRET_HIT_TINT, decay)


## 재시작 — 연출 도중이었던 포탑 스프라이트를 기본 위치 / 흰색으로 되돌린다.
## `turrets` 는 곧바로 비워지므로 남은 연출을 소모해 줄 주체가 사라진다.
func _clear_turret_hit_visuals() -> void:
	for raw in turrets:
		var td := raw as TurretData
		if td == null:
			continue
		td.anim_hit_t   = 0.0
		td.anim_hit_dur = 0.0
		_apply_turret_hit_visual(td, true)


## 포탑 피격 오프셋 — 렌더러가 HP 바를 스프라이트와 같이 흔들 때 읽는다.
func turret_hit_offset(td: TurretData) -> Vector2:
	if td == null or td.anim_hit_dur <= 0.0:
		return Vector2.ZERO
	var t: float = clampf(td.anim_hit_t / td.anim_hit_dur, 0.0, 1.0)
	return Vector2(sin(t * TAU * 3.0) * ANIM_TURRET_HIT_AMP_PX * (1.0 - t), 0.0)

# ─── Public helpers (used by modules) ────────────────────────────────────────
func cell_center(pos: Vector2i) -> Vector2:
	return hex_grid.hex_to_screen(pos.x, pos.y)


func pilot_label(p: PilotData) -> String:
	return "%s%d" % [ROLE_NAMES[p.role], p.team]


## 이 파일럿의 아웃게임 페르소나(`PlayerData`). 없으면 null — 단독 실행이나
## 초상화 없는 INTL 파일럿이 그렇다.
##
## `pilots` 는 스폰 순서가 곧 역할 순서다(0..4 = 팀0, 5..9 = 팀1). match_ctx 의
## 두 로스터도 같은 역할 순서라 인덱스가 그대로 대응한다 — 스폰 이후 배열이
## 재정렬되지 않는다는 것이 이 대응의 전제이므로, `pilots` 를 정렬하고 싶으면
## 사본을 정렬할 것(HudBuilder 가 그렇게 한다).
func player_data_for(p: PilotData) -> PlayerData:
	if p == null or gm == null or not bool(gm.match_ctx.get("active", false)):
		return null
	var idx: int = pilots.find(p)
	if idx < 0:
		return null
	var roster: Array = gm.match_ctx.get(
			"player_roster" if idx < 5 else "enemy_roster", [])
	var slot: int = idx if idx < 5 else idx - 5
	if slot >= roster.size():
		return null
	return roster[slot] as PlayerData


func role_stats_str(role: int) -> String:
	var s: Dictionary = ROLE_STATS[role]
	return "HP:%d ATK:%d" % [s["hp"], s["atk"]]


# Effective cost of a card for the given side, after applying:
#  • phase_cost_inc_* (cost_inc_phase) — additive, can push cost up.
#  • engage_discount_* (전투 준비) — applied only if the card carries an
#    engage clause (engage:N). Does NOT consume the discount; consumption
#    happens in CardPhaseManager._play_card_direct after the cost is paid.
# Clamped to 0 from below.
func effective_cost_for(cd: CardData, is_player: bool) -> int:
	if cd == null:
		return 0
	var inc: int = phase_cost_inc_p if is_player else phase_cost_inc_ai
	var c: int = cd.cost + inc
	var disc: int = engage_discount_p if is_player else engage_discount_ai
	if disc > 0 and card_phase != null and card_phase.card_has_engage(cd):
		c = max(0, c - disc)
	return max(0, c)


# Drawn-position of a pilot marker assuming it sits solo on its tile — the
# **fallback** for callers that can't wait for BattleRenderer's per-frame slot
# solve (CardTargetingOverlay's PILOT hit test). 답은
# 렌더러가 소유한다: 초상화가 앉는 방향은 그 파일럿의 이동 방향에서 나오므로
# 여기서 다시 계산하면 두 답이 갈라진다(예전에는 여기에 "적 위 / 아군 아래"가
# 한 벌 더 적혀 있었다).
func pilot_marker_pos_solo(p: PilotData) -> Vector2:
	if renderer != null:
		return renderer.pilot_marker_pos_fallback(p)
	return cell_center(p.grid_pos)

# ─── Button callbacks ─────────────────────────────────────────────────────────
# Season-mode return: the win panel "다음 →" button hands control back to the
# campaign hub. SeasonHub._ready() picks up season_state.pending_match.winner_side
# and applies the result to standings.
func _on_return_to_season_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_restart_pressed() -> void:
	_populate_from_data_loader()
	player_hq_hp = HQ_MAX_HP; enemy_hq_hp = HQ_MAX_HP
	turn_count = 0; game_over = false
	last_log = ""; auto_play_timer = AUTO_PLAY_INTERVAL
	game_phase    = GameEnums.BattlePhase.GAMBIT
	gambit_lanes = [-1, -1, -1, -1, -1]
	panel_victory.visible = false
	pilots.clear()
	turrets.clear()
	player_hand.clear();    ai_hand.clear()
	player_discard.clear(); ai_discard.clear()
	# 진영 선점 포인트를 다시 심는다 — _populate_from_data_loader 가 이미
	# seed_side_costs() 를 돌렸지만, 여기서 0 으로 밀어 버리면 재시작한 판에서만
	# 블루의 선이 사라진다.
	seed_side_costs()
	pending_atk_buff_p = 0; pending_atk_buff_ai = 0
	engage_discount_p = 0; engage_discount_ai = 0
	phase_cost_inc_p = 0; phase_cost_inc_ai = 0
	phase_draw_discount_p = 0; phase_draw_discount_ai = 0
	preserved_cards_p.clear(); preserved_cards_ai.clear()
	next_phase_strategy_p = 0; next_phase_strategy_ai = 0
	kill_bounty_p = 0; kill_bounty_ai = 0
	_clear_turret_hit_visuals()
	_score_popup_hold.clear()
	if renderer != null:
		renderer.clear_popups()
	for node in player_card_nodes:
		if is_instance_valid(node):
			node.queue_free()
	player_card_nodes.clear()
	# Clear AI hand visuals; HudBuilder reflows from the now-empty ai_hand.
	if hud != null:
		hud.update_ai_hand_visuals()
	_gambit.auto_assign_lanes()
	_gambit.launch_battle()
	card_phase.build_starter_decks()
