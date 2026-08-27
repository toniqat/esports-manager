class_name TurnEngageSim
extends RefCounted

# 교전 시뮬레이터 (headless) — **사이드뷰 벨트 무대 + 라운드 기반 턴제**.
#
# 노드를 하나도 만들지 않고 상태만 굴리기 때문에 EngageArena(렌더러)와 완전히
# 분리되며, 헤드리스로도 돌릴 수 있다. EngagePhaseManager 가 매 프레임
# step(delta) 를 호출하고, EngageArena 는 units / turrets / projectiles /
# popups / 라운드 상태를 읽어 그리기만 한다.
#
# 좌표계: 전장의 육각 셀 매핑은 **쓰지 않는다**. 무대는 팀0(아군)이 왼쪽,
# 팀1(적군)이 오른쪽에 마주 서는 평면 벨트다. x = 벨트를 따라가는 진행 방향,
# y = 벨트의 얕은 깊이(위쪽이 멀고 아래쪽이 가깝다). 파일럿이 전장 어느 셀에
# 있었는지는 배치에 반영하지 않는다 — 역할이 자리를 정한다(근접 앞줄 /
# 원거리 뒷줄).
#
# ─── 행동 모델: 라운드 · 한 명씩 ─────────────────────────────────────────────
# **한 라운드 안에서 모두가 정확히 한 번씩 행동한다.** 무대에는 언제나 단 한
# 명(`current_actor`)만 나와 있고, 그 한 차례(접근 → 공격 → 정착)가 끝나면
# 다음 순서로 넘어간다. 마지막 순서까지 돌면 라운드가 하나 오르고 **다시
# 시전자부터** 같은 순서를 돈다.
#
# `engage:N` 의 N 은 초가 아니라 **라운드 수**다. 예전의 ATB(메크 `speed` 스탯에
# 비례해 차오르는 게이지로 행동 빈도가 갈리던 실시간 모델)는 **삭제**됐고
# `speed` 스탯도 데이터에서 사라졌다 — 되살리지 말 것. 그 이전의 탑뷰 아레나도
# 마찬가지.
#
# 데미지는 PilotData 에 직접 적용된다 — 교전이 끝나면 전장 상태에 그대로
# 반영된다.

# ─── 라운드 / 종료 ───────────────────────────────────────────────────────────
## 결투(1:1)는 한 쪽이 처치될 때까지 — 다만 서로 못 잡고 버티는 조합(원거리
## 미러 등)이 있으므로 관전 페이싱용 라운드 상한을 둔다.
const DUEL_MAX_ROUNDS: int = 10

# ─── 벨트 지오메트리 (아레나 좌표, 렌더러가 카메라로 화면에 맞춘다) ──────────
## 벨트 전체 폭. 유닛은 항상 이 안에 갇힌다 — 교전 중 이탈은 없다.
## EngageArena.BAND_RECT(1032×500)에 통째로 들어가는 크기로 잡혀 있다 —
## 여기를 키우면 카메라 최소 배율이 떨어져 유닛이 잘게 보인다.
const BELT_W: float = 1240.0
## 벨트 깊이(y). 사이드뷰라 얕게 잡는다 — 깊이는 겹침 방지와 원근 표현용이지
## 전술적 의미는 없다.
const BELT_H: float = 400.0
## 유닛 슬롯이 들어가지 않는 위아래 여백.
const DEPTH_MARGIN: float = 60.0
## 양 팀 앞줄이 중앙선에서 각각 이만큼 떨어져 선다 (앞줄 간격 = 2배 = 300).
const FRONT_OFFSET: float = 150.0
## 앞줄(근접)과 뒷줄(원거리) 사이 간격.
const ROW_GAP: float = 155.0
## 슬롯 좌표에 주는 흐트러짐 — 완벽한 일렬은 기계적으로 보인다.
const SLOT_JITTER_X: float = 18.0
const SLOT_JITTER_Y: float = 14.0

# ─── 유닛 ────────────────────────────────────────────────────────────────────
const UNIT_RADIUS: float = 40.0
## 근접이 공격을 넣기 위해 좁혀야 하는 거리. UNIT_RADIUS 두 개(80)보다 살짝
## 커서 초상화가 겹치지 않고 붙는다.
const MELEE_REACH: float = 88.0
## 원거리 사거리. 실제 발사는 이 값의 RANGED_APPROACH_RATIO 안에서만 한다.
const RANGE_RANGED: float = 300.0
## "최대 사거리의 이 비율 안까지 들어간 다음 공격한다." 이미 그 안이면 더
## 접근하지 않고 제자리에서 쏜다.
const RANGED_APPROACH_RATIO: float = 0.9
## 돌진 이동 속도(px/s). 근접이 더 빠르게 파고든다.
##
## ATB 시절보다 **빠르게** 잡혀 있다. 그때는 10명이 동시에 움직여 한 사람의
## 접근이 느려도 무대가 비지 않았지만, 지금은 한 번에 한 명뿐이라 접근 시간이
## 곧 관전자가 기다리는 시간이다. 3라운드 5v5 가 약 17초에 끝나는 것이 여기서
## 나온다 — 느리게 잡으면 그대로 30초를 넘긴다.
const MOVE_SPEED_MELEE: float = 1400.0
const MOVE_SPEED_RANGED: float = 1100.0
## 넉백으로 밀려난 만큼 자기 자리(anchor_pos)로 되돌아오는 드리프트 속도 배율.
## **원위치 복귀가 아니다** — 앵커 자체가 마지막으로 공격한 자리로 갱신되므로
## 이 드리프트는 벨트 클램프 등으로 어긋난 잔차만 추스른다.
const SETTLE_SPEED_MULT: float = 0.85
## 접근 단계가 이 시간을 넘기면 이번 차례를 접는다(대상이 멀리 밀려나 있는 등의
## 교착 방지). 접는 자리가 곧 새 앵커다.
const ADVANCE_MAX_SEC: float = 0.55
## 공격 모션을 붙잡는 시간. 이 동안 유닛은 대상 앞에 멈춰 서 있다.
## 원거리는 투사체 비행(최대 270px / PROJECTILE_SPEED ≈ 0.19초)이 끝나기를
## 기다려야 하므로 근접보다 길다.
const STRIKE_HOLD_MELEE: float = 0.20
const STRIKE_HOLD_RANGED: float = 0.26
## 한 차례가 끝나고 다음 순서로 넘어가기까지의 짧은 숨.
const ACTOR_GAP_SEC: float = 0.06
## 라운드 사이의 숨. 렌더러가 이 동안 라운드 배너를 띄운다.
const ROUND_GAP_SEC: float = 0.45
## 포탑이 사격 모션을 붙잡는 시간(포탑 차례의 길이).
const TURRET_FIRE_HOLD: float = 0.30
## 앵커에 도착한 것으로 치는 거리.
const HOME_EPSILON: float = 6.0
## 사거리 판정 여유(px). **없으면 근접이 두 번째 공격부터 영영 못 나간다.**
## `_tick_advance` 의 정지점은 `target.pos - dir * strike_dist()` 이고
## `_step_toward` 가 거기에 스냅하므로, 접근을 끝낸 유닛은 사거리 **딱 그
## 거리**에 선다. 그 자리에서 다시 잰 거리는 부동소수 오차로 88.0 바로 위에
## 떨어지기 일쑤라 `dist <= strike_dist()` 가 거짓이 되고, 유닛은 이미 도착한
## 정지점을 향해 0px 씩 "이동"하다가 `ADVANCE_MAX_SEC` 교착으로만 차례를
## 접는다 — 공격은 한 번도 성립하지 않는다.
const STRIKE_DIST_EPSILON: float = 0.5

# ─── 넉백 (피격 피드백 + 재접근 거리) ───────────────────────────────────────
## 명중 시 대상에게 실리는 초기 속도(px/s). 감쇠까지 합치면 근접 ≈ 47px,
## 원거리 ≈ 17px 밀려나고, 밀려난 자리가 그대로 새 앵커가 된다
## (`_apply_knockback`). 이 거리가 때린 쪽의 다음 차례 돌진 거리이기도 하다 —
## 0 으로 두면 근접이 사거리에 붙어 선 채 굳어 공격 모션이 사라진다.
const KNOCK_IMPULSE_MELEE: float = 420.0
const KNOCK_IMPULSE_RANGED: float = 150.0
## 넉백 속도의 지수 감쇠 계수(1/s).
const KNOCK_DAMP: float = 9.0
## 벨트 느낌을 위해 넉백은 거의 수평으로 민다 — 세로 성분을 이만큼으로 죽인다.
const KNOCK_VERTICAL_SCALE: float = 0.35
## 넉백 연출 타이머(렌더러 전용) 길이.
const KNOCK_FLASH_SEC: float = 0.22

# ─── 포탑 ────────────────────────────────────────────────────────────────────
# 전장과 달리 아레나의 포탑은 **파일럿을 공격한다**. 다만 사거리 원 개념은 없다 —
# 참가한 포탑은 아레나 전체를 사정권으로 본다. 참가 조건은 단 하나:
# **자기 팀 파일럿이 그 포탑 칸 위에 서 있을 때**. 즉 포탑 칸에 있는 적을
# 상대로 교전을 걸면 그 포탑이 방어에 가담한다.
#
# 포탑도 **라운드마다 한 번** 행동한다 — 파일럿 전원이 돌고 난 뒤, 시전자 팀
# 포탑부터 차례가 온다. 예전의 자기 ATB(TURRET_SPEED)는 삭제됐다.
#
# **포탑은 무대 참가자가 아니라 배경 지형 구조물이다.** 유닛 벨트가 아니라
# 지평선 근처의 먼 지형 위에 서고, 렌더러의 카메라 프레이밍에서도 빠진다
# (EngageArena._focus_positions) — 포탑을 프레임에 넣으면 벨트 양 끝까지
# 담느라 배율이 떨어져 정작 싸우는 유닛이 잘게 보였다.
## 포탑이 서는 x — 자기 팀 **뒷줄에서 이만큼 더 바깥**.
const TURRET_BACK_OFFSET: float = 90.0
## 포탑이 서는 y — 유닛 슬롯(DEPTH_MARGIN 60 부터)보다 살짝 위, 즉 **가장 먼
## 바닥선**.
const TURRET_BG_Y: float = 48.0
## 같은 팀 포탑이 둘 이상이면 깊이(y) 대신 x 로 나눠 세운다 — 배경 지형은
## 지평선 한 줄이라 y 로 흩으면 그 줄을 벗어난다.
const TURRET_BG_STEP: float = 160.0
## 포탑 명중 굴림에 쓰는 고정 hit 스탯(포탑에는 hit 스탯이 없다).
const TURRET_HIT: int = 50

const PROJECTILE_SPEED: float = 1400.0

# ─── 명중 보정 ───────────────────────────────────────────────────────────────
## 교전 명중률은 전장(SimulationCore.roll_hit)과 **별개**로 계산한다. 전장 확률
## `hit/(hit+evasion)` 을 [ENGAGE_HIT_MIN, ENGAGE_HIT_MAX] 구간으로 리맵한다:
##     chance = ENGAGE_HIT_MIN + (ENGAGE_HIT_MAX - ENGAGE_HIT_MIN) * base
## 전장 대비 훨씬 가까이 붙어 싸운다는 전제라 **최소 80% / 평균(base 0.5) 90%
## / 최대 100%** 가 되도록 잡았다. 단조 증가라 스탯 우열 순서는 그대로
## 보존된다 — 명중이 높은 파일럿이 여전히 더 잘 맞힌다.
const ENGAGE_HIT_MIN: float = 0.80
const ENGAGE_HIT_MAX: float = 1.00

## 유닛 상태. 이탈 / 후퇴 / **원위치 복귀** 상태는 없다 — 라운드가 끝날 때까지
## 아무도 벨트를 뜨지 못하고, 공격을 끝낸 유닛은 그 자리에 눌러앉는다.
##   IDLE    — 자기 차례가 아니다. 넉백 잔차만 추스른다.
##   ADVANCE — 자기 차례. 대상에게 접근. 사거리에 들면 STRIKE.
##   STRIKE  — 공격 판정 완료, 모션 홀드. 끝나면 그 자리를 앵커로 삼고 IDLE.
enum State { IDLE, ADVANCE, STRIKE, DEAD }

## 라운드 진행 상태. 렌더러가 헤더/배너에 쓴다.
##   ROUND_START — 라운드 배너를 띄우는 짧은 정지
##   ACTING      — current_actor 가 자기 차례를 수행 중
##   ACTOR_GAP   — 한 차례가 끝나고 다음 순서로 넘어가는 숨
##   DONE        — 종료 판정이 났다 (finished == true)
enum Flow { ROUND_START, ACTING, ACTOR_GAP, DONE }

## 팀 안에서의 행동 우선순위. 앞이 먼저 나간다 — 파고드는 역할이 먼저 열고
## 뒤에서 받아 치는 역할이 나중에 정리하는 순서다. 시전자는 이 순서를 무시하고
## 자기 팀 맨 앞으로 당겨진다.
const ROLE_ACT_ORDER: Array[int] = [
	GameEnums.Role.ASSASSIN,
	GameEnums.Role.FIGHTER,
	GameEnums.Role.TANK,
	GameEnums.Role.SNIPER,
	GameEnums.Role.SUPPORT,
]


# ─── 유닛 ────────────────────────────────────────────────────────────────────
class EUnit extends RefCounted:
	var pilot: PilotData
	var team: int = 0
	var pos: Vector2 = Vector2.ZERO
	## 지금 이 유닛이 서 있기로 한 자리. 개전 시엔 진형 슬롯이고, 그 뒤로는
	## **마지막으로 공격을 끝낸 자리**(_settle) 또는 **넉백으로 밀려난 자리**
	## (_apply_knockback)로 갱신된다 — 원위치 복귀가 없으므로.
	## 타겟 거리 계산의 기준점.
	var anchor_pos: Vector2 = Vector2.ZERO
	var is_melee: bool = true
	## 적 뒷줄(원거리)을 우선으로 노리는가. 암살자만 true.
	var dives_backline: bool = false
	## 파일럿 스킬이 강제하는 **첫 공격**의 표적 역할(GameEnums.Role). -1 = 없음.
	## 원딜 사냥꾼 하나가 쓴다 — 그 한 번이 지나면 `skill_focus_used` 가 켜져
	## 평소 표적 규칙으로 돌아간다.
	var skill_focus_role: int = -1
	var skill_focus_used: bool = false
	## 이번 차례의 표적을 **약자 멸시**가 정했는가. 스택은 그때만 소모된다 —
	## 다른 규칙이 고른 표적에까지 값을 물리면 스택이 겨눔과 무관하게 마른다.
	var atk_range: float = 0.0
	var move_speed: float = 0.0

	var state: int = State.IDLE
	var target: EUnit = null
	## 현재 행동(ADVANCE/STRIKE) 경과 시간.
	var act_t: float = 0.0
	## 넉백 잔여 속도.
	var knock_vel: Vector2 = Vector2.ZERO
	## 바라보는 방향의 x 부호(+1 = 오른쪽). 사이드뷰라 좌우만 의미가 있다.
	var facing_x: float = 1.0
	## 피격 플래시 잔여 시간(렌더러 전용).
	var hit_flash: float = 0.0
	## 공격 모션 잔여 시간(렌더러 전용).
	var swing_t: float = 0.0

	func is_active() -> bool:
		return state != State.DEAD

	func hp_ratio() -> float:
		if pilot == null or pilot.max_hp <= 0:
			return 0.0
		return clampf(float(pilot.hp) / float(pilot.max_hp), 0.0, 1.0)

	## 이번 행동에서 공격이 성립하는 거리.
	func strike_dist() -> float:
		return MELEE_REACH if is_melee else atk_range * RANGED_APPROACH_RATIO

	## 행동 중(= 지금 나와서 때리는 중)인가. 렌더러가 강조 표시에 쓴다.
	func is_acting() -> bool:
		return state == State.ADVANCE or state == State.STRIKE


# ─── 아레나에 등장하는 포탑 ──────────────────────────────────────────────────
class ETurret extends RefCounted:
	var data: TurretData
	var team: int = 0
	var pos: Vector2 = Vector2.ZERO
	var atk: int = 0
	## 사격 모션 잔여 시간(렌더러 전용).
	var fire_t: float = 0.0
	## 마지막 사격 대상 — 렌더러가 사격선을 그릴 때 쓴다.
	var last_target: EUnit = null

	func is_active() -> bool:
		return data != null and data.alive


# ─── 상태 (EngageArena 가 읽는다) ────────────────────────────────────────────
var units: Array = []          # Array[EUnit]
var turrets: Array = []        # Array[ETurret]
var projectiles: Array = []    # Array[Dictionary] {from,to,t,dur,team,is_turret}
var popups: Array = []         # Array[Dictionary] {pos,text,color} — 렌더러가 소비 후 비운다
var stats: Dictionary = {}     # PilotData → {dealt,taken,kills}

## 1-based 진행 라운드. 개시 직후부터 1 이다.
var round_index: int = 1
## 카드가 정한 라운드 수. 결투는 DUEL_MAX_ROUNDS.
var total_rounds: int = 1
## 지금 무대에 나와 있는 행동자 (EUnit 또는 ETurret 또는 null).
var current_actor = null
var flow: int = Flow.ROUND_START
var finished: bool = false
var initiator_team: int = 0
var is_duel: bool = false
## 순수 관전 경과 시간(초). 페이싱 계측용 — 종료 판정에는 쓰지 않는다.
var elapsed: float = 0.0

## 라운드마다 반복되는 행동 순서. 개시 시 한 번 정하고 그 뒤로 바뀌지 않는다 —
## "매번 시전자의 순서로 시작"이 성립하는 근거. 죽은 행동자는 건너뛴다.
var _order: Array = []
var _order_idx: int = -1
## ROUND_START / ACTOR_GAP 의 잔여 시간.
var _gap_left: float = 0.0

var _bs: BattleSim = null
var _origin_cell: Vector2i = Vector2i.ZERO
## 시전자가 있는 교전인가(= 카드가 연 교전인가). 오브젝트 교전은 false 이고,
## 그때는 포탑이 한 기도 가담하지 않는다 — `_build_turrets` 참조.
var _has_caster: bool = false


# 유닛이 돌아다닐 수 있는 벨트 사각형. 렌더러의 최소 카메라 배율도 여기서 나온다.
static func belt_rect() -> Rect2:
	return Rect2(0.0, 0.0, BELT_W, BELT_H)


## 카메라가 비출 수 있는 최대 범위 — 벨트 + 배경 지형(포탑이 선 지평선 근처).
## 카메라 클램프를 belt_rect 로 두면 지평선 위에 선 포탑이 어떤 배율에서도
## 화면에 들어오지 못한다. 유닛 이동 한계는 여전히 belt_rect 다.
const STAGE_TOP_EXTRA: float = 150.0

static func stage_rect() -> Rect2:
	return Rect2(0.0, -STAGE_TOP_EXTRA, BELT_W, BELT_H + STAGE_TOP_EXTRA)


# 참가자 목록을 받아 벨트를 구성한다.
#   `caster` — 시전자. 매 라운드 **첫 번째로** 행동한다. **null 이어도 된다** —
#              오브젝트 교전(전령 / 용)은 카드가 아니라 타이머가 여는 것이라
#              시전자가 없다. 그때는 순서가 역할 우선순위만으로 정해지고
#              선공 팀은 `first_team` 이 정한다.
#   `team0/1` — 참가 PilotData 배열.
#   `rounds` — 라운드 수. 결투는 DUEL_MAX_ROUNDS 를 넘긴다.
#   `first_team` — 선공 팀. -1 이면 시전자의 팀(시전자도 없으면 팀0).
func setup(bs: BattleSim, caster: PilotData, team0: Array, team1: Array,
		rounds: int, duel: bool, first_team: int = -1) -> void:
	_bs = bs
	_origin_cell = caster.grid_pos if caster != null else Vector2i.ZERO
	_has_caster = caster != null
	if first_team >= 0:
		initiator_team = first_team
	else:
		initiator_team = caster.team if caster != null else 0
	is_duel = duel
	total_rounds = max(1, rounds)

	_build_units(caster, team0, team1)
	_build_turrets()
	_build_order(caster)
	_contempt_opening()

	round_index = 1
	_order_idx = -1
	flow = Flow.ROUND_START
	_gap_left = ROUND_GAP_SEC


## 약자 멸시(암살 R) — **1라운드가 돌기 전에** 터지는 선제 타격. 손패에 든
## [약자 멸시]의 충전을 통째로 태우고, 태운 수만큼 **체력이 가장 적은 적**을
## 공격력 `CONTEMPT_DMG_MULT` 로 때린다.
##
## 순서가 중요하다: `_build_units` 뒤라야 무대에 선 유닛과 그 자리가 정해져 있고
## (팝업 좌표가 거기서 나온다), 라운드 루프 앞이라야 "교전을 시작하면"이 된다.
## 오버클럭은 태우지 않는다(`allow_extra = false`) — 개시 타격이 다시 추가 공격을
## 굴리면 카드 한 장이 교전을 혼자 끝낼 수 있다.
func _contempt_opening() -> void:
	var mech: MechSkillSystem = _bs.mech_skill
	if mech == null:
		return
	for raw in units:
		var u := raw as EUnit
		var n: int = mech.take_contempt_charges(u.pilot)
		if n <= 0:
			continue
		popups.append({"pos": u.pos, "text": "약자 멸시 x%d" % n,
				"color": Color(1.0, 0.72, 0.35)})
		for _i in n:
			var weak: EUnit = _weakest_enemy(u)
			if weak == null:
				break
			_strike_one(u, weak, false, CONTEMPT_DMG_MULT)


# ─── 구성 ────────────────────────────────────────────────────────────────────
# 진형: 팀0 은 왼쪽에서 오른쪽을 보고, 팀1 은 오른쪽에서 왼쪽을 본다. 각 팀은
# 근접(앞줄)과 원거리(뒷줄)로 나뉘고, 줄 안에서는 깊이(y)를 균등 분배한다.
func _build_units(caster: PilotData, team0: Array, team1: Array) -> void:
	units.clear()
	stats.clear()

	for t in range(2):
		var front: Array = []   # Array[EUnit]
		var back: Array = []    # Array[EUnit]
		for raw in (team0 if t == 0 else team1):
			var p := raw as PilotData
			if p == null or not p.alive:
				continue
			var u := _make_unit(p)
			units.append(u)
			# `score0` 는 교전 **개시 시점**의 성장치 — 결과 대시보드가 이 값과
			# 지금 값의 차를 "성장" 행으로 보여 준다.
			stats[p] = {"dealt": 0, "taken": 0, "kills": 0, "score0": p.score}
			(front if u.is_melee else back).append(u)
		_place_row(front, _row_x(t, true))
		_place_row(back, _row_x(t, false))
	# caster 는 배치에 영향을 주지 않는다 — 순서에서만 앞으로 당겨진다.
	if caster == null:
		return


func _make_unit(p: PilotData) -> EUnit:
	var u := EUnit.new()
	u.pilot = p
	u.team = p.team
	u.is_melee = _is_melee_role(p.role)
	u.dives_backline = (p.role == GameEnums.Role.ASSASSIN)
	# 원딜 사냥꾼(파일럿 스킬)이 강제하는 첫 표적. 스킬이 없으면 -1 이라
	# `_pick_target` 이 평소 규칙으로 흐른다.
	u.skill_focus_role = _bs.skill.engage_focus_role(p) if _bs.skill != null else -1
	u.atk_range = MELEE_REACH if u.is_melee else RANGE_RANGED
	u.move_speed = MOVE_SPEED_MELEE if u.is_melee else MOVE_SPEED_RANGED
	u.facing_x = 1.0 if u.team == 0 else -1.0
	return u


## 라운드마다 반복되는 행동 순서를 만든다.
##
## **상황 기반 — 팀 교대 + 팀 내 역할 고정.** 시전자 팀부터 한 명, 상대 팀에서
## 한 명씩 번갈아 나간다. 팀 안의 순서는 `ROLE_ACT_ORDER` 로 고정하되 **시전자는
## 자기 팀 맨 앞으로 당겨진다** — 교전을 연 쪽이 선공한다는 것이 전투 개시
## 카드의 값이다.
##
## 포탑은 파일럿 전원이 돈 **뒤** 시전자 팀 포탑부터 차례를 갖는다. 유닛 벨트에
## 섞어 넣지 않는 이유는 포탑이 무대 참가자가 아니라 배경 지형이라서다 —
## 카메라도 포탑을 프레이밍하지 않으므로 파일럿 사이에 끼우면 화면 밖에서
## 포격만 날아오는 침묵 구간이 생긴다.
##
## 순서는 개시 시 한 번만 정한다. 죽은 행동자는 `_advance_order` 가 건너뛰므로
## 라운드가 흘러도 살아 있는 사람의 상대 순서는 바뀌지 않는다.
func _build_order(caster: PilotData) -> void:
	_order.clear()
	var first: int = initiator_team
	var second: int = 1 - first
	var by_team: Array = [_role_sorted(first, caster), _role_sorted(second, caster)]
	var n: int = max((by_team[0] as Array).size(), (by_team[1] as Array).size())
	for i in n:
		if i < (by_team[0] as Array).size():
			_order.append((by_team[0] as Array)[i])
		if i < (by_team[1] as Array).size():
			_order.append((by_team[1] as Array)[i])
	for t in [first, second]:
		for raw in turrets:
			var et := raw as ETurret
			if et.team == t:
				_order.append(et)


## 한 팀의 유닛을 역할 우선순위로 정렬한다. `caster` 가 이 팀이면 맨 앞으로.
func _role_sorted(team: int, caster: PilotData) -> Array:
	var out: Array = []
	for raw in units:
		var u := raw as EUnit
		if u.team == team:
			out.append(u)
	out.sort_custom(func(a, b) -> bool:
		return _role_rank((a as EUnit).pilot.role) < _role_rank((b as EUnit).pilot.role))
	for i in out.size():
		if (out[i] as EUnit).pilot == caster:
			var u: EUnit = out.pop_at(i)
			out.insert(0, u)
			break
	return out


static func _role_rank(role: int) -> int:
	var idx: int = ROLE_ACT_ORDER.find(role)
	return ROLE_ACT_ORDER.size() if idx < 0 else idx


# 팀 t 의 앞줄/뒷줄 x 좌표.
static func _row_x(team: int, is_front: bool) -> float:
	var centre: float = BELT_W * 0.5
	var depth_off: float = FRONT_OFFSET + (0.0 if is_front else ROW_GAP)
	return centre - depth_off if team == 0 else centre + depth_off


# 한 줄(같은 x)의 유닛들을 깊이 방향으로 균등 분배한다. 이 자리는 **개시
# 시점의 앵커**일 뿐이다 — 첫 공격을 끝내는 순간부터 앵커는 그때그때 서 있는
# 자리로 갱신된다.
func _place_row(row: Array, x: float) -> void:
	var n: int = row.size()
	if n == 0:
		return
	var top: float = DEPTH_MARGIN
	var span: float = BELT_H - DEPTH_MARGIN * 2.0
	for i in n:
		var u := row[i] as EUnit
		var frac: float = 0.5 if n == 1 else float(i) / float(n - 1)
		var slot := Vector2(
			x + randf_range(-SLOT_JITTER_X, SLOT_JITTER_X),
			top + span * frac + randf_range(-SLOT_JITTER_Y, SLOT_JITTER_Y))
		u.anchor_pos = _clamp_to_belt(slot)
		u.pos = u.anchor_pos


# 포탑 참가 규칙: **적이 걸어온 교전에서만**, 그리고 **참가 파일럿이 자기 팀
# 포탑 칸 위에 서 있을 때만** 그 포탑이 가담한다. 즉 포탑은 "허깅하고 있는 우리
# 편에게 적이 교전을 강제했을 때" 방어에 나서는 것이지, 우리가 그 자리에서 먼저
# 교전을 열 때 따라 나오는 화력이 아니다. 포탑 칸에 눌러앉아 카드로 교전을
# 여는 쪽이 포탑까지 끼고 싸우면 그 칸이 일방적인 안전지대가 된다.
#
# 그래서 걸러 내는 자리가 둘이다.
#   1. **오브젝트 교전(전령 / 용)에는 어느 팀 포탑도 안 낀다** — 시전자가 없는
#      교전이라 "누가 걸었는가"가 없고, 무대도 중립 칸에서 열린다.
#   2. **시전자 팀의 포탑은 빠진다** — 교전을 연 쪽이 곧 강제한 쪽이다.
#
# 가담한 포탑에 사거리 개념은 없다 — 아레나 전체를 사정권으로 본다.
# 자리는 유닛 벨트가 아니라 **지평선 근처의 배경 지형**(TURRET_BG_Y) 이다.
func _build_turrets() -> void:
	turrets.clear()
	if not _has_caster:
		return                       # 오브젝트 교전 — 포탑은 가담하지 않는다.
	# 참가자가 밟고 있는 셀 집합을 팀별로 모은다.
	var occupied: Array = [{}, {}]   # occupied[team][Vector2i] = true
	for raw in units:
		var u := raw as EUnit
		(occupied[u.team] as Dictionary)[u.pilot.grid_pos] = true

	var joined: Array = [[], []]     # joined[team] = Array[ETurret]
	for raw in _bs.turrets:
		var t := raw as TurretData
		if t == null or not t.alive:
			continue
		if t.team == initiator_team:
			continue                 # 교전을 건 쪽의 포탑은 가담하지 않는다.
		if not (occupied[t.team] as Dictionary).has(t.grid_pos):
			continue
		var et := ETurret.new()
		et.data = t
		et.team = t.team
		et.atk = max(1, t.atk)
		turrets.append(et)
		(joined[t.team] as Array).append(et)

	# 자기 팀 진영 뒤쪽 **배경 지형** 위에 세운다. 같은 팀 포탑이 둘 이상이면
	# 지평선 한 줄을 따라 안쪽으로 나란히 선다.
	for team in range(2):
		var row: Array = joined[team]
		var back_x: float = _row_x(team, false)
		for i in row.size():
			var et := row[i] as ETurret
			var out_off: float = TURRET_BACK_OFFSET + TURRET_BG_STEP * float(i)
			et.pos = Vector2(
					back_x - out_off if team == 0 else back_x + out_off,
					TURRET_BG_Y)


static func _is_melee_role(role: int) -> bool:
	return role == GameEnums.Role.TANK \
			or role == GameEnums.Role.FIGHTER \
			or role == GameEnums.Role.ASSASSIN


# ─── 메인 스텝 ───────────────────────────────────────────────────────────────
# 무대에는 언제나 한 명만 나와 있다. 나머지는 넉백 잔차만 추스르고, 연출
# 타이머(피격 플래시 / 공격 모션)만 흐른다.
func step(dt: float) -> void:
	if finished:
		return
	elapsed += dt
	_tick_passive(dt)
	_update_projectiles(dt)

	match flow:
		Flow.ROUND_START, Flow.ACTOR_GAP:
			_gap_left -= dt
			if _gap_left <= 0.0:
				_advance_order()
		Flow.ACTING:
			_tick_actor(dt)


# 종료 판정이 난 뒤의 유예(EngagePhaseManager.END_HOLD_SEC) 동안 굴리는 스텝.
# 전투는 완전히 멈춘 상태에서 날아가던 투사체를 착탄시키고 피격 플래시 /
# 공격 모션 / 넉백만 마저 감쇠시킨다. `round_index` 는 건드리지 않으므로
# 대시보드에 찍히는 라운드 수는 실제로 싸운 라운드 수 그대로다.
func step_afterglow(dt: float) -> void:
	_tick_passive(dt)
	for raw in turrets:
		var t := raw as ETurret
		t.fire_t = max(0.0, t.fire_t - dt)
	_update_projectiles(dt)


## 차례와 무관하게 매 프레임 흐르는 것들 — 연출 타이머, 넉백, 앵커 잔차 복원.
func _tick_passive(dt: float) -> void:
	for raw in units:
		var u := raw as EUnit
		u.hit_flash = max(0.0, u.hit_flash - dt)
		u.swing_t = max(0.0, u.swing_t - dt)
		if u.state == State.DEAD:
			continue
		if not u.pilot.alive:
			u.state = State.DEAD
			continue
		_apply_knockback(u, dt)
		if u.state == State.IDLE:
			_step_toward(u, u.anchor_pos, u.move_speed * SETTLE_SPEED_MULT, dt)
	for raw in turrets:
		var t := raw as ETurret
		t.fire_t = max(0.0, t.fire_t - dt)


## 다음 행동자에게 차례를 넘긴다. 죽은 행동자는 건너뛰고, 순서 끝에 닿으면
## 라운드를 하나 올려 **다시 시전자부터** 시작한다.
func _advance_order() -> void:
	if _check_end():
		return
	while true:
		_order_idx += 1
		if _order_idx >= _order.size():
			# 한 라운드 종료.
			if round_index >= total_rounds:
				# 기회주의자(파일럿 스킬) — 이 교전에서 처치를 낸 파일럿이
				# 그 스킬을 갖고 있으면 라운드가 한 번 늘어난다. 한 교전에
				# 한 번뿐이라 `_opportunist_used` 로 잠근다.
				var extra: int = 0
				if not _opportunist_used and _bs.skill != null:
					extra = _bs.skill.engage_bonus_rounds_from_kills()
				if extra > 0:
					_opportunist_used = true
					total_rounds += extra
				else:
					_finish()
					return
			round_index += 1
			_order_idx = -1
			current_actor = null
			flow = Flow.ROUND_START
			_gap_left = ROUND_GAP_SEC
			return
		var actor = _order[_order_idx]
		if not actor.is_active():
			continue
		if actor is ETurret:
			_begin_turret_turn(actor as ETurret)
			return
		var u := actor as EUnit
		# 기절([강타]) — 이번 차례를 통째로 건너뛰고 남은 라운드가 하나 준다.
		# 순서 배열에서 빼지는 않으므로 살아 있는 사람들의 상대 순서는 그대로다.
		if _bs.mech_skill != null and _bs.mech_skill.consume_stun_turn(u.pilot):
			popups.append({"pos": u.pos, "text": "기절",
					"color": Color(0.70, 0.85, 1.0)})
			continue
		var t := _pick_target(u)
		if t == null:
			continue                # 때릴 상대가 없다 — 이번 차례는 그냥 넘긴다.
		current_actor = u
		u.target = t
		u.state = State.ADVANCE
		u.act_t = 0.0
		flow = Flow.ACTING
		return


## 지금 나와 있는 행동자의 한 차례를 굴린다.
func _tick_actor(dt: float) -> void:
	if current_actor == null:
		_end_actor_turn()
		return
	if current_actor is ETurret:
		var t := current_actor as ETurret
		if t.fire_t <= 0.0:
			_end_actor_turn()
		return
	var u := current_actor as EUnit
	if u.state == State.DEAD:
		_end_actor_turn()
		return
	match u.state:
		State.ADVANCE:
			_tick_advance(u, dt)
		State.STRIKE:
			_tick_strike(u, dt)
		_:
			_end_actor_turn()


func _end_actor_turn() -> void:
	if current_actor is EUnit:
		_settle(current_actor as EUnit)
	current_actor = null
	if _check_end():
		return
	flow = Flow.ACTOR_GAP
	_gap_left = ACTOR_GAP_SEC


# 접근 — 사거리에 들 때까지 붙는다. 근접은 MELEE_REACH, 원거리는 최대 사거리의
# RANGED_APPROACH_RATIO(90%). 이미 그 안이면 곧장 공격한다.
func _tick_advance(u: EUnit, dt: float) -> void:
	u.act_t += dt
	if u.target == null or not u.target.is_active():
		u.target = _pick_target(u)
		if u.target == null:
			_end_actor_turn()
			return
	var to_target: Vector2 = u.target.pos - u.pos
	var dist: float = to_target.length()
	_face_toward(u, to_target.x)

	if dist <= u.strike_dist() + STRIKE_DIST_EPSILON:
		_resolve_attack(u, u.target)
		u.state = State.STRIKE
		u.act_t = 0.0
		return
	if u.act_t >= ADVANCE_MAX_SEC:
		_end_actor_turn()         # 교착 — 이번 차례는 접고 여기 눌러앉는다.
		return

	# 대상 바로 앞(사거리 끝)까지만 파고든다.
	var stop: Vector2 = u.target.pos - (to_target / max(0.001, dist)) * u.strike_dist()
	_step_toward(u, stop, u.move_speed, dt)


# 타격 모션 홀드 — 이 동안은 대상 앞에 멈춰 서 있는다. 홀드가 끝나도 원위치로
# 돌아가지 않는다.
func _tick_strike(u: EUnit, dt: float) -> void:
	u.act_t += dt
	var hold: float = STRIKE_HOLD_MELEE if u.is_melee else STRIKE_HOLD_RANGED
	if u.act_t >= hold:
		_end_actor_turn()


# 한 차례를 끝내고 **지금 서 있는 자리에 눌러앉는다**. 이 자리가 새 앵커이므로
# 다음 타겟 거리도, 넉백 복원 목표도 여기서 다시 잰다.
func _settle(u: EUnit) -> void:
	if u.state != State.DEAD:
		u.state = State.IDLE
	u.target = null
	u.act_t = 0.0
	u.anchor_pos = u.pos


# 종료는 두 가지뿐이다 — 라운드 소진과 한 쪽 전멸. 둘 다 그 프레임에 finished 가
# 서고, 대시보드는 매니저의 유예 시간만큼 늦게 뜬다.
func _check_end() -> bool:
	if finished:
		return true
	if active_count(0) == 0 or active_count(1) == 0:
		_finish()
		return true
	return false


func _finish() -> void:
	finished = true
	flow = Flow.DONE
	current_actor = null


func active_count(team: int) -> int:
	var n := 0
	for raw in units:
		var u := raw as EUnit
		if u.team == team and u.is_active():
			n += 1
	return n


func _step_toward(u: EUnit, to: Vector2, speed: float, dt: float) -> bool:
	var off: Vector2 = to - u.pos
	var d: float = off.length()
	if d <= HOME_EPSILON:
		u.pos = _clamp_to_belt(to)
		return true
	var step_len: float = speed * dt
	if step_len >= d:
		u.pos = _clamp_to_belt(to)
		return true
	u.pos = _clamp_to_belt(u.pos + off / d * step_len)
	return false


func _face_toward(u: EUnit, dx: float) -> void:
	if absf(dx) > 1.0:
		u.facing_x = 1.0 if dx > 0.0 else -1.0


# 넉백 속도를 적용하고 지수 감쇠시킨다. 상태와 무관하게 매 프레임 돈다.
#
# **밀려난 만큼 앵커도 같이 민다.** 앵커를 제자리에 두면 IDLE 의 복원 드리프트
# (`move_speed × SETTLE_SPEED_MULT`)가 넉백 초기 속도보다 빨라서 맞은 유닛이
# **맞은 그 프레임 안에** 앵커로 되돌아간다 — `_step_toward` 는 6px 안이면
# 목표로 스냅하므로 잔차조차 남지 않는다. 즉 넉백이 화면에 **전혀 보이지
# 않았다**. 앵커를 함께 옮기면 밀린 자리가 그대로 새 자리가 되고, 그래서
#   ① 넉백이 실제로 보이고,
#   ② 때린 쪽은 다음 차례에 그 거리를 다시 좁혀야 한다.
# ②가 없으면 근접은 첫 접근 이후 영원히 `MELEE_REACH` 에 붙어 선 채라
# `_tick_advance` 가 매번 같은 프레임에 STRIKE 로 넘어가 **공격 모션이 통째로
# 사라진다**. "밀려난 자리가 새 자리"는 `_settle()` 의 "공격을 끝낸 자리가 새
# 자리"와 같은 규칙이다 — 이 모듈에는 원위치 복귀가 없다.
func _apply_knockback(u: EUnit, dt: float) -> void:
	if u.knock_vel.length_squared() < 1.0:
		u.knock_vel = Vector2.ZERO
		return
	var before: Vector2 = u.pos
	u.pos = _clamp_to_belt(u.pos + u.knock_vel * dt)
	u.anchor_pos = _clamp_to_belt(u.anchor_pos + (u.pos - before))
	u.knock_vel = u.knock_vel.lerp(Vector2.ZERO, 1.0 - exp(-KNOCK_DAMP * dt))


# 타겟 선정 — 거리 기반이되 존재감이 높은 쪽을 선호하고(어그로 가중),
# 아군이 이미 때리고 있는 적과 빈사인 적에 가산점을 준다. 집중 사격 항목이
# 없으면 모두가 각자 제일 가까운 적만 때려서 딜이 흩어지고 처치가 나오지
# 않는다 — 실제 MOBA 교전의 포커스를 흉내 내는 부분.
#
# 턴제에서는 무대에 한 명만 나와 있으므로 "아군이 이미 물고 있는 적"은 이번
# 라운드에서 **아군이 마지막으로 노린 적**을 뜻한다(`_last_focus`). 그래서
# 라운드 안에서 딜이 한 명에게 모인다.
const FOCUS_BONUS: float = 0.78     # 같은 팀이 이미 노린 적에게 곱해지는 계수
const FOCUS_BONUS_FLOOR: float = 0.45
const LOW_HP_FOCUS: float = 0.6     # 빈사(35% 미만) 적 마무리 가중
## 암살자가 적 뒷줄(원거리)에 주는 가중. 낮을수록 더 집요하게 파고든다.
const DIVE_FOCUS: float = 0.40
## 약자 멸시의 개시 타격에 곱해지는 공격력 배율 (카드 문안의 "공격력 50%").
const CONTEMPT_DMG_MULT: float = 0.5

## 팀별 이번 라운드의 집중 대상 → 몇 명이 노렸는가. 라운드가 넘어가도 그대로
## 두는 이유는 집중 사격이 라운드 경계에서 끊기면 처치가 거의 나오지 않기
## 때문이다(실시간 시절에는 동시 행동이 이 역할을 했다).
var _focus_count: Dictionary = {}   # EUnit → int

## 기회주의자의 라운드 연장을 이 교전에서 이미 썼는가.
var _opportunist_used: bool = false

func _pick_target(u: EUnit) -> EUnit:
	# 원딜 사냥꾼(파일럿 스킬) — 아직 안 쓴 첫 공격은 적 원딜이 살아 있는 한
	# 반드시 그쪽으로 간다. 거리도 존재감도 보지 않는다.
	if u.skill_focus_role >= 0 and not u.skill_focus_used:
		for raw in units:
			var e := raw as EUnit
			if e.team != u.team and e.is_active() 					and e.pilot.role == u.skill_focus_role:
				_focus_count[e] = int(_focus_count.get(e, 0)) + 1
				return e
	var best: EUnit = null
	var best_score: float = INF
	for raw in units:
		var e := raw as EUnit
		if e.team == u.team or not e.is_active():
			continue
		var d: float = u.anchor_pos.distance_to(e.pos)
		var score: float
		if u.dives_backline:
			# 암살자는 존재감 어그로를 무시하고 **뒷줄을 노린다**. 이 분기가
			# 없으면 앞줄이 더 가깝고 존재감까지 두 배(4 vs 2)라 원거리 메크가
			# 교전 내내 단 한 대도 맞지 않는다 — 실측으로 확인된 구멍이다.
			score = d * (DIVE_FOCUS if not e.is_melee else 1.0)
		else:
			score = d / float(max(1, e.pilot.presence))
		if e.hp_ratio() < 0.35:
			score *= LOW_HP_FOCUS
		var n: int = int(_focus_count.get(e, 0))
		if n > 0:
			score *= maxf(FOCUS_BONUS_FLOOR, pow(FOCUS_BONUS, float(n)))
		if score < best_score:
			best_score = score
			best = e
	if best != null:
		_focus_count[best] = int(_focus_count.get(best, 0)) + 1
	return best


## 아직 살아 있는 적 유닛 전부. 전탄 발사가 한 차례에 훑는 명단이다.
func _living_enemies(u: EUnit) -> Array:
	var out: Array = []
	for raw in units:
		var e := raw as EUnit
		if e.team != u.team and e.is_active():
			out.append(e)
	return out


## 남은 체력이 가장 적은 적. 비율이 아니라 **절대값**이다 — 약자 멸시는
## "체력이 가장 적은 적"이라 적혀 있고, 비율로 읽으면 최대 체력이 큰 탱커가
## 반피만 되어도 표적이 되어 "약자"라는 말과 어긋난다.
func _weakest_enemy(u: EUnit) -> EUnit:
	var best: EUnit = null
	for raw in _living_enemies(u):
		var e := raw as EUnit
		if best == null or e.pilot.hp < best.pilot.hp:
			best = e
	return best


## 이 PilotData 를 들고 무대에 서 있는 유닛. 피해 계산이 팝업을 띄울 자리를
## 되찾을 때만 쓴다(`_apply_damage` 는 PilotData 만 들고 있다).
func _unit_for(p: PilotData) -> EUnit:
	for raw in units:
		var u := raw as EUnit
		if u.pilot == p:
			return u
	return null


# ─── 전투 해상도 ─────────────────────────────────────────────────────────────
# 데미지는 전장과 동일(명중 시 dmg = atk, 보호막부터 흡수)하지만 **명중률만은
# 전장과 별개**다 — `_hit_chance` 가 80~100% 구간으로 리맵한 확률을 준다.
func _resolve_attack(u: EUnit, target: EUnit) -> void:
	u.swing_t = 0.22
	var mech: MechSkillSystem = _bs.mech_skill
	# 전탄 발사(원딜 I) — 이 한 차례의 공격이 **적 전원**에게 간다. 대가는
	# 기체 공격력 절반이고 그건 데이터(mechs.csv atk 12)에 이미 들어가 있다.
	var victims: Array = [target]
	if mech != null and mech.engage_targets_all(u.pilot):
		var all_foes: Array = _living_enemies(u)
		if not all_foes.is_empty():
			victims = all_foes
	for raw in victims:
		_strike_one(u, raw as EUnit)


## 한 대상에게 들어가는 타격 한 번. `_resolve_attack` 이 대상 집합을 정하고
## 이 함수가 그 하나하나를 굴린다 — 전탄 발사는 같은 차례에 이 함수를 여러 번
## 부르는 것이고, 오버클럭은 같은 대상에게 한 번 더 부르는 것이다.
##
## `allow_extra` 가 false 면 오버클럭이 걸리지 않는다. 추가 공격이 다시 추가
## 공격을 굴리면 확률에 따라 한 차례가 무한히 늘어난다.
func _strike_one(u: EUnit, target: EUnit, allow_extra: bool = true,
		dmg_mult: float = 1.0) -> void:
	if target == null or not target.is_active():
		return
	if not u.is_melee:
		projectiles.append({
			"from": u.pos, "to": target.pos, "t": 0.0,
			"dur": max(0.05, u.pos.distance_to(target.pos) / PROJECTILE_SPEED),
			"team": u.team, "is_turret": false,
		})

	var a: PilotData = u.pilot
	var d: PilotData = target.pilot
	if randf() >= _hit_chance(a.hit, d.evasion):
		popups.append({"pos": target.pos, "text": "MISS",
				"color": Color(0.85, 0.85, 0.85)})
		return

	# 파일럿 스킬의 피해 배율 — 불안정한 대포(양방향)와 원딜 사냥꾼의 첫 공격
	# 보너스. 전장과 같은 질의 함수를 쓰므로 두 무대의 규칙이 갈라지지 않는다.
	var raw_dmg: float = float(max(1, a.atk)) * dmg_mult
	if _bs.skill != null:
		raw_dmg *= _bs.skill.damage_out_mult(a) * _bs.skill.damage_in_mult(d)
	if u.skill_focus_role >= 0 and not u.skill_focus_used:
		if d.role == u.skill_focus_role and _bs.skill != null:
			raw_dmg *= _bs.skill.engage_focus_atk_mult(a)
		u.skill_focus_used = true
	var dealt := _apply_damage(d, maxi(1, roundi(raw_dmg)))
	target.hit_flash = KNOCK_FLASH_SEC
	_apply_knock(u.pos, target,
			KNOCK_IMPULSE_MELEE if u.is_melee else KNOCK_IMPULSE_RANGED)
	(stats[a] as Dictionary)["dealt"] = int(stats[a]["dealt"]) + dealt
	(stats[d] as Dictionary)["taken"] = int(stats[d]["taken"]) + dealt
	# 성장치(점수) — 준 피해와 처치는 전장과 같은 지점을 지난다. 피해는 곧장
	# 점수가 되는 대신 피해자의 장부에 쌓였다가 처치 시 어시스트로 정산된다.
	_bs.record_pilot_damage(a, d, dealt)
	# 메크 쪽 교전 피해 훅 — 영혼 수확(전사 L)과 고통과 쾌감(탱커 N)이 무대
	# 위에서도 걸린다. 전장·카드와 같은 함수를 지나므로 규칙이 갈라지지 않는다.
	var mech: MechSkillSystem = _bs.mech_skill
	if mech != null:
		mech.on_engage_damage(a, d, dealt)
		# 강타([강타] 카드) — 때린 쪽이 장전돼 있으면 맞은 적이 다음 차례를
		# 통째로 잃는다. 같은 적에게 두 번은 걸리지 않는다.
		if mech.try_stun(a, d):
			popups.append({"pos": target.pos, "text": "기절!",
					"color": Color(0.70, 0.85, 1.0)})
	if d.hp <= 0:
		_kill(target, a)
		(stats[a] as Dictionary)["kills"] = int(stats[a]["kills"]) + 1
		popups.append({"pos": target.pos, "text": "-%d  KO!" % dealt,
				"color": Color(1.0, 0.85, 0.30)})
	else:
		popups.append({"pos": target.pos, "text": "-%d" % dealt,
				"color": Color(1.0, 0.45, 0.45)})
	# 오버클럭(암살 P) — 교전 피해 직후 굴린다. 성공하면 **같은 대상에게**
	# 한 번 더 때리고 충전 절반이 날아간다(소모는 질의 함수가 한다).
	if allow_extra and mech != null and target.is_active() \
			and mech.overclock_extra_attack(a):
		popups.append({"pos": u.pos, "text": "오버클럭",
				"color": Color(0.65, 0.95, 1.0)})
		_strike_one(u, target, false)


# 넉백 — 공격자로부터 멀어지는 방향으로 민다. 벨트 느낌을 위해 세로 성분은
# KNOCK_VERTICAL_SCALE 만큼 눌러 거의 수평으로 밀려나게 한다.
func _apply_knock(from: Vector2, target: EUnit, impulse: float) -> void:
	var dir: Vector2 = target.pos - from
	if dir.length_squared() < 0.001:
		dir = Vector2(1.0 if target.team == 1 else -1.0, 0.0)
	dir = Vector2(dir.x, dir.y * KNOCK_VERTICAL_SCALE).normalized()
	target.knock_vel += dir * impulse


# 교전 전용 명중 확률. 전장의 `hit/(hit+evasion)` 을 기준값으로 삼아
# [ENGAGE_HIT_MIN, ENGAGE_HIT_MAX] 구간에 선형으로 얹는다 — 최소 80%,
# 스탯이 대등하면(base 0.5) 90%. 전장 굴림은 `SimulationCore.roll_hit` 에
# 그대로 남아 있고 여기와 서로 영향을 주지 않는다.
static func _hit_chance(hit: int, evasion: int) -> float:
	var total: float = float(max(1, hit + evasion))
	var base: float = clampf(float(hit) / total, 0.0, 1.0)
	return ENGAGE_HIT_MIN + (ENGAGE_HIT_MAX - ENGAGE_HIT_MIN) * base


func _apply_damage(d: PilotData, amount: int) -> int:
	var dmg := amount
	var absorbed := 0
	if d.shield > 0:
		absorbed = min(d.shield, dmg)
		d.shield -= absorbed
		dmg -= absorbed
	var hp_dmg := 0
	if dmg > 0:
		hp_dmg = min(dmg, d.hp)
		d.hp = max(0, d.hp - dmg)
	# 불굴(지원 V) — 이 교전에서 **팀 전원이 한 번씩**, 체력 1 아래로 내려가지
	# 않는다. 판정을 여기 두는 이유는 포탑 사격도 같은 함수를 지나기 때문이다 —
	# 파일럿 공격에만 걸면 포탑 한 방에 죽는 구멍이 남는다.
	if d.hp <= 0 and _bs.mech_skill != null \
			and _bs.mech_skill.last_stand_available(d):
		_bs.mech_skill.consume_last_stand(d)
		d.hp = 1
		hp_dmg = maxi(0, hp_dmg - 1)   # 실제로 깎인 만큼만 센다
		var u: EUnit = _unit_for(d)
		if u != null:
			popups.append({"pos": u.pos, "text": "불굴!",
					"color": Color(1.0, 0.92, 0.55)})
	return absorbed + hp_dmg


func _kill(target: EUnit, killer: PilotData) -> void:
	# 전장과 같은 사망 경로를 탄다 — 리스폰 턴 스케일링(`respawn_turns_now`)과
	# 성장치 정산이 아레나 처치에도 그대로 걸린다.
	_bs.mark_pilot_dead(target.pilot, killer)
	target.state = State.DEAD
	target.target = null
	target.knock_vel = Vector2.ZERO


# ─── 포탑 차례 ───────────────────────────────────────────────────────────────
# 전장에서는 포탑이 파일럿을 때리지 않지만, 교전에 가담한 포탑은 때린다.
# 사거리 제한은 없으므로 아레나에 적이 하나라도 살아 있으면 반드시 대상을 찾는다.
# 대상은 **포탑에서 가장 가까운 적** — 자기 진영 깊숙이 파고든 유닛이 먼저 맞는다.
func _begin_turret_turn(t: ETurret) -> void:
	var victim: EUnit = _turret_target(t)
	if victim == null:
		t.last_target = null
		_advance_order()          # 때릴 상대가 없으면 차례를 넘긴다.
		return
	current_actor = t
	flow = Flow.ACTING
	t.last_target = victim
	t.fire_t = TURRET_FIRE_HOLD
	projectiles.append({
		"from": t.pos, "to": victim.pos, "t": 0.0,
		"dur": max(0.05, t.pos.distance_to(victim.pos) / PROJECTILE_SPEED),
		"team": t.team, "is_turret": true,
	})
	# 포탑도 명중 판정을 굴린다 — hit 스탯이 없으므로 TURRET_HIT 를 쓴다.
	if randf() >= _hit_chance(TURRET_HIT, victim.pilot.evasion):
		popups.append({"pos": victim.pos, "text": "MISS",
				"color": Color(0.85, 0.85, 0.85)})
		return
	var dealt := _apply_damage(victim.pilot, t.atk)
	victim.hit_flash = KNOCK_FLASH_SEC
	_apply_knock(t.pos, victim, KNOCK_IMPULSE_RANGED)
	if stats.has(victim.pilot):
		(stats[victim.pilot] as Dictionary)["taken"] = \
				int(stats[victim.pilot]["taken"]) + dealt
	if victim.pilot.hp <= 0:
		# 포탑 처치는 어느 파일럿에게도 성장치가 귀속되지 않는다.
		_kill(victim, null)
		popups.append({"pos": victim.pos, "text": "-%d  포탑 처치" % dealt,
				"color": Color(1.0, 0.6, 0.25)})
	else:
		popups.append({"pos": victim.pos, "text": "-%d" % dealt,
				"color": Color(1.0, 0.72, 0.30)})


func _turret_target(t: ETurret) -> EUnit:
	var best: EUnit = null
	var best_d: float = INF
	for raw in units:
		var u := raw as EUnit
		if u.team == t.team or not u.is_active():
			continue
		var d: float = u.pos.distance_to(t.pos)
		if d < best_d:
			best_d = d
			best = u
	return best


# ─── 보조 ────────────────────────────────────────────────────────────────────
func _update_projectiles(dt: float) -> void:
	var keep: Array = []
	for raw in projectiles:
		var p: Dictionary = raw
		p["t"] = float(p["t"]) + dt
		if float(p["t"]) < float(p["dur"]):
			keep.append(p)
	projectiles = keep


# 교전이 끝날 때까지 아무도 벨트 밖으로 나갈 수 없다.
func _clamp_to_belt(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, UNIT_RADIUS, BELT_W - UNIT_RADIUS),
		clampf(p.y, UNIT_RADIUS, BELT_H - UNIT_RADIUS))


## 지금 무대에 나와 있는 행동자의 표시 이름. 렌더러가 헤더에 쓴다.
func actor_label() -> String:
	if current_actor == null:
		return ""
	if current_actor is ETurret:
		var t := current_actor as ETurret
		return "포탑 T%d [%s]" % [t.data.tier, _bs.LANE_NAMES[t.data.lane]]
	return _bs.pilot_label((current_actor as EUnit).pilot)


func units_of(team: int) -> Array:
	var out: Array = []
	for raw in units:
		if (raw as EUnit).team == team:
			out.append(raw)
	return out
