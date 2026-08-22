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
# 직전에 서 있던 셀. **정글러 초상화의 방향**이 여기서 나온다 — 정글에는 레인
# 경로가 없고 로밍 목적지는 수시로 바뀌므로, 지나온 자취가 "이 사람이 어디로
# 가는 중인가"의 유일한 안정적 신호다(BattleRenderer 는 온 방향의 **반대쪽**에
# 초상화를 앉힌다). `BattleSim.anim_pilot_move` 가 모든 실제 이동에서 갱신하고,
# 본진 복귀 / 부활은 자기 자신으로 되돌린다 — 순간이동에는 '온 방향'이 없다.
# 위의 `anim_prev_grid_pos` 와 다른 것이다: 저쪽은 이동 트윈 전용이라 복귀·부활
# 이후에도 죽기 전 값이 남아 있고, 연출이 끝나도 지워지지 않는다.
var prev_grid_pos: Vector2i = Vector2i.ZERO
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
# **성장은 시간이 아니라 성장치(`score`)가 만든다.** 예전에는 살아 있기만 하면
# 매 턴 `BattleSim.GROWTH_PER_TURN` 만큼 `atk` 와 `max_hp` 가 함께 늘었는데,
# 둘이 **같은 비율**로 자라면 "몇 대 맞아야 죽는가"가 수학적으로 영원히 그대로다
# — 50턴에 둘 다 ×1.5 여도 교전 타수는 1타도 줄지 않는다. 성장이 안 보인 게
# 아니라 구조상 보일 수 없었다.
#
# 지금은 둘이 갈라져 있다. `growth` 는 공격력, `growth_hp` 는 최대 체력이고
# 둘 다 `score` 에서 파생된다(`BattleSim.refresh_growth_stats`) — 공격력이
# 4배 빠르게 자라므로 성장치가 쌓일수록 TTK 가 실제로 줄어든다.
#
# `base_atk` / `base_max_hp` 는 `_init` 이 채운다. 스폰 시점의 메크 스탯 주입
# (`SimulationCore._stats_for`)이 생성자를 거치므로, 성장 이전의 원본은 언제나
# 여기 남는다. 성장은 파일럿에 붙어 있으므로 **사망·리스폰으로 초기화되지 않는다**.
var base_atk: int         = 0
var base_max_hp: int      = 0
## 공격력 성장 배율분. `atk = base_atk × (1 + growth) + atk_buff`.
var growth: float         = 0.0
## 최대 체력 성장 배율분. 공격력의 1/4 속도로 자란다.
var growth_hp: float      = 0.0
# 카드가 거는 **일시적** 공격력 가산(전투 준비 등). `atk` 를 직접 밀면 성장
# 재계산이 그 사이에 끼었을 때 가산분이 통째로 지워지거나 두 번 빠진다 —
# 성장은 이제 점수가 바뀔 때마다(= 턴 한가운데서도) 다시 계산되므로 별도
# 필드로 들고 있어야 한다.
var atk_buff: int         = 0
# 성장치 **획득** 배율. 안전한 파밍(+10% → 1.10) / 완벽한 마무리(+25% → 1.25).
# 예전에는 성장 배율이었지만 성장이 점수에서 파생되면서 적립 배율이 됐다 —
# 결과는 같고(더 번 만큼 더 큰다) 배선이 한 겹 준다.
# 두 카드는 같은 필드를 쓰므로 **나중에 건 쪽이 덮어쓴다**(합산 아님).
var growth_rate_mult: float = 1.0
# 턴 만료형 적립 배율의 만료 턴. -1 = 없음. (안전한 파밍)
var growth_rate_expire_turn: int = -1
# 작전 단계 만료형 적립 배율 표시. (완벽한 마무리) — 다음 작전 단계 진입 시 해제.
var growth_until_phase: bool = false

# ─── 성장치 (파일럿 점수) ─────────────────────────────────────────────────────
# 개시 1.00k 에서 시작해 경기 내내 누적되는 파일럿의 성장 통화 — MOBA 의 골드에
# 해당한다. 50턴 평균 25.00k, 잘 큰 캐리는 40.00k 을 넘긴다. 파일럿 스트립에
# 숫자로 찍히고 팀 점수는 팀원 합산이며 상한이 없다.
#
# **`growth` 는 여기서 파생된다** — 위의 성장 절 참조. 예전에는 둘이 완전히
# 무관해서(성장은 시간, 성장치는 기록) 킬을 따도 타워를 밀어도 스탯이 1도
# 변하지 않았다.
#
# 적립처는 셋이다: **전선 체류**(턴당), **정글 캠프**(정글러), **처치 현상금**
# (라스트힛 + 피해 비례 어시스트). 규칙과 상수는 전부 `BattleSim` 의 `SCORE_*`
# 절에 있고, 변동은 `BattleSim.add_score` 한 곳만 지난다.
var score: float          = 1.0   # = BattleSim.SCORE_START

# 이번 생에 **나를 때린 사람들**의 누적 피해량. `PilotData attacker → int`.
# 내가 쓰러질 때 `BattleSim.mark_pilot_dead` 가 이걸 읽어 현상금을 라스트힛과
# 어시스트에게 나눠 주고 비운다. 피해가 굴려지는 그 지점에서 쌓으므로
# (`BattleSim.record_pilot_damage`) 전장·교전 무대·공격 카드가 같은 표를 쓴다.
var damage_credit: Dictionary = {}

# ─── 라인전 스탯 ──────────────────────────────────────────────────────────────
# **전장 명중 판정 전용** 배율 (+0.10 / −0.10). `SimulationCore.roll_hit` 이
# 공격자의 `hit` 과 방어자의 `evasion` 에 각각 곱한다. `atk` / `max_hp` 는 건드리지
# 않는다 — 그쪽은 성장이 담당한다. 교전 무대(TurnEngageSim)는 자기 명중률
# 구간을 따로 쓰므로 이 값을 읽지 않는다.
var lane_stat_mod: float  = 0.0
var lane_stat_expire_turn: int = -1   # -1 = 없음

# ─── Animation state (UI-only; SimulationCore does NOT read these) ────────────
# 이동 연출의 **경로**. `[출발 칸, …, 도착 칸]` 이고, 두 칸 이상 움직인 턴에는
# 실제로 밟은 칸이 순서대로 들어 있다(정글러 move_range 2, 전진 카드 advance:N).
# 렌더러가 이 경로를 따라 초상화를 미끄러뜨리므로 2칸 이동이 중간 칸을 스쳐
# 지나가지 않고 **꺾여서** 간다.
#
# **렌더러가 소비하며 비운다** — `BattleRenderer._sync_glide` 가 경로를 읽어
# 글라이드를 시작한 뒤 `clear()` 한다. 그래서 같은 프레임에 여러 걸음이 들어오면
# (전진 카드의 N틱) `BattleSim.anim_pilot_move` 가 이어 붙일 수 있고, 턴을 넘긴
# 다음 이동은 빈 배열에서 새로 시작한다.
#
# 연출 **시간**은 여기 없다 — 타이머는 렌더러(`BattleRenderer._glide`)가 쥐고
# 있다. 예전의 `anim_prev_grid_pos` / `anim_move_t` / `anim_move_dur` 는 삭제됐다:
# 칸 이동만 트윈하고 슬롯 변화는 순간이동이라 "칸은 미끄러지는데 초상화는 튀는"
# 그림이 남았고, 지금은 **마커 좌표 자체**를 렌더러가 한 곳에서 보간한다.
var anim_move_path: Array[Vector2i] = []
# Damage shake: short horizontal jitter.
# 진폭은 **흔들림마다 다르다** — 전장 자동 교전은 `BattleSim.ANIM_SHAKE_AMP_PX`,
# 공격 카드 명중은 `ANIM_SHAKE_CARD_AMP_PX`(훨씬 크다)로 들어온다. 상수를 하나로
# 두고 렌더러가 읽던 시절에는 둘 중 하나만 맞출 수 있었다.
var anim_shake_t: float   = 0.0
var anim_shake_dur: float = 0.0
var anim_shake_amp: float = 0.0
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
	prev_grid_pos = p_pos
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
