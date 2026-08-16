class_name PilotData
extends RefCounted

# Source pilot id from the players.csv pool (0..39), or 100..119 for INTL
# pilots. -1 when the battle was launched standalone (no match_ctx) — in that
# case the renderer falls back to a placeholder circle. Currently consumed by
# BattleRenderer to look up the pilot's circle portrait.
var pilot_id: int = -1
var role: int
var hp: int
var max_hp: int
var atk: int
var team: int
var grid_pos: Vector2i
var alive: bool           = true
# Turns until the pilot walks back out of their HQ. **사망 전용** — counts down
# in SimulationCore.process_respawns. 복귀(본진 귀환)는 전장을 비우지 않으므로
# 이 타이머를 쓰지 않는다: 죽지 않는 한 파일럿은 항상 전장 위에 있다.
var respawn_timer: int    = 0
# 본진 복귀한 그 턴에는 HQ 에 서 있기만 하고 움직이지 않는다는 표시.
# RecallSystem.return_to_hq 가 켜고, 다음 이동 패스(SimulationCore.resolve_movement)
# 가 한 턴을 걸러 내면서 스스로 끈다 — 그래서 "복귀 → 다음 턴부터 레인으로".
var recall_hold: bool     = false
var lane: int             = GameEnums.LanePosition.GUERRILLA
var is_guerrilla: bool    = false
var waypoint_idx: int     = 0
var move_range: int       = 1                # cells advanced per minute
var jungle_start_pref: int = -1              # GameEnums.JungleStartDir or -1 (none)
# Sticky roam destination for junglers, (-1,-1) = none yet. Held across turns by
# SimulationCore._jungle_goal_for so the roam target cannot flip mid-route.
var jungle_roam_target: Vector2i = Vector2i(-1, -1)
# Hit/evasion drive paired combat rolls (PlayerData.mechanics → hit, gamesense → evasion).
var hit: int              = 50
var evasion: int          = 50
# 존재감 — 전투 개시(engage)에서만 참조. 근접 메크 4, 원거리 메크 2.
# 피격 가중치(높을수록 자주 표적이 됨).
#
# **속도(speed)는 삭제됐다** — 교전이 라운드 기반 턴제가 되면서 라운드마다
# 전원이 한 번씩 행동하므로 행동 빈도를 가르는 스탯이 없다. 되살리지 말 것.
var presence: int         = 4
# 보호막. Granted by the 보호 card; removed on 본진 복귀 (RecallSystem clears it).
# Damage absorption isn't wired into SimulationCore yet — this field is the
# data hook for future integration so card effects can build up the value now.
var shield: int           = 0

# ─── 성장 (인게임 누적) ───────────────────────────────────────────────────────
# 파일럿은 매 턴 `BattleSim.GROWTH_PER_TURN` 만큼 `atk` 와 `max_hp` 가 늘어난다.
# 누적치는 배율 하나(`growth`)로 들고 있고, 실제 스탯은 매 턴 **원본에서 다시
# 계산**한다 — 매 턴 곱해 나가면 반올림 오차가 누적되기 때문.
#
# `base_atk` / `base_max_hp` 는 `_init` 이 채운다. 스폰 시점의 메크 스탯 주입
# (`SimulationCore._stats_for`)이 생성자를 거치므로, 성장 이전의 원본은 언제나
# 여기 남는다. 성장은 파일럿에 붙어 있으므로 **사망·리스폰으로 초기화되지 않는다**.
var base_atk: int         = 0
var base_max_hp: int      = 0
var growth: float         = 0.0
# 성장 획득 배율. 안전한 파밍(+10% → 1.10) / 완벽한 마무리(+25% → 1.25) 가 건다.
# 두 카드는 같은 필드를 쓰므로 **나중에 건 쪽이 덮어쓴다**(합산 아님).
var growth_rate_mult: float = 1.0
# 턴 만료형 성장 배율의 만료 턴. -1 = 없음. (안전한 파밍)
var growth_rate_expire_turn: int = -1
# 작전 단계 만료형 성장 배율 표시. (완벽한 마무리) — 다음 작전 단계 진입 시 해제.
var growth_until_phase: bool = false

# ─── 성장치 (파일럿 점수) ─────────────────────────────────────────────────────
# 개시 1.00k 에서 시작해 처치 / 사망 / 준 피해 / 포탑 · HQ 피해로 누적되는 종합
# 지표. 파일럿 스트립에 숫자로 찍히고 팀 점수는 팀원 합산이다. 상한이 없다.
#
# **바로 위의 `growth` 와는 다른 것이다.** `growth` 는 스탯을 밀어 올리는 배율,
# `score` 는 스탯에 아무 영향이 없는 기여 지표다. 적립 규칙과 상수는 전부
# `BattleSim` 의 `SCORE_*` 절에 있고, 변동은 `BattleSim.add_score` 한 곳만 지난다.
var score: float          = 1.0   # = BattleSim.SCORE_START

# ─── 라인전 스탯 ──────────────────────────────────────────────────────────────
# **전장 명중 판정 전용** 배율 (+0.10 / −0.10). `SimulationCore.roll_hit` 이
# 공격자의 `hit` 과 방어자의 `evasion` 에 각각 곱한다. `atk` / `max_hp` 는 건드리지
# 않는다 — 그쪽은 성장이 담당한다. 교전 무대(TurnEngageSim)는 자기 명중률
# 구간을 따로 쓰므로 이 값을 읽지 않는다.
var lane_stat_mod: float  = 0.0
var lane_stat_expire_turn: int = -1   # -1 = 없음

# ─── Animation state (UI-only; SimulationCore does NOT read these) ────────────
# Move tween: cell-to-cell pixel interpolation from anim_prev_grid_pos to grid_pos.
var anim_prev_grid_pos: Vector2i = Vector2i.ZERO
var anim_move_t: float    = 0.0
var anim_move_dur: float  = 0.0
# Damage shake: short horizontal jitter.
var anim_shake_t: float   = 0.0
var anim_shake_dur: float = 0.0
# Recall sequence: 0 = none, 1 = fade-out + rise at anim_recall_orig,
# 2 = fade-in + descend at grid_pos (HQ). Respawn skips straight to phase 2.
var anim_recall_phase: int   = 0
var anim_recall_t: float     = 0.0
var anim_recall_dur: float   = 0.0
var anim_recall_orig: Vector2i = Vector2i.ZERO

# 사망 연출: 0 = 없음, 1 = 제자리에서 딤드된 채 대기, 2 = 투명해지며 위로 상승.
# 로직상 파일럿은 이미 alive == false 지만, 이 타이머가 도는 동안에는 렌더러가
# anim_death_cell 에 계속 그려 준다.
var anim_death_phase: int    = 0
var anim_death_t: float      = 0.0
var anim_death_dur: float    = 0.0
var anim_death_cell: Vector2i = Vector2i.ZERO

# 공격 카드 돌진 연출: 0 = 없음, 1 = 대상에게 파고드는 중(가속),
# 2 = 붕 뜬 채 천천히 원래 자리로. `anim_lunge_vec` 는 1단계가 끝났을 때의
# 최종 변위(픽셀)이고 1·2단계 모두 이 벡터를 보간해 쓴다 — 대상이 그 사이
# 쓰러져 사라져도 복귀 경로가 어긋나지 않는다.
# 1단계는 시간이 다 차도 스스로 꺼지지 않고 **대상 앞에서 멈춘 채 대기**한다:
# 그 정지 구간에서 피해·쉐이크가 재생되고, 2단계는 호출 측이 건다.
var anim_lunge_phase: int   = 0
var anim_lunge_t: float     = 0.0
var anim_lunge_dur: float   = 0.0
var anim_lunge_vec: Vector2 = Vector2.ZERO

func _init(p_role: int, p_team: int, p_pos: Vector2i, stats: Dictionary) -> void:
	role     = p_role
	team     = p_team
	grid_pos = p_pos
	hp       = stats["hp"]
	max_hp   = stats["hp"]
	atk      = stats["atk"]
	if stats.has("move_range"):
		move_range = max(1, int(stats["move_range"]))
	if stats.has("hit"):
		hit = int(stats["hit"])
	if stats.has("evasion"):
		evasion = int(stats["evasion"])
	if stats.has("presence"):
		presence = int(stats["presence"])
	# 성장 계산의 원본. 생성자에서 잡아 두는 것이 요점이다 — 메크 스탯 주입은
	# 이 생성자를 통해 들어오므로 어떤 스폰 경로를 타도 원본이 비지 않는다.
	base_atk    = atk
	base_max_hp = max_hp
