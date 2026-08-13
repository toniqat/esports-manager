class_name RealtimeEngageSim
extends RefCounted

# 실시간 교전 시뮬레이터 (headless) — **사이드뷰 벨트스크롤 + ATB**.
#
# 노드를 하나도 만들지 않고 상태만 굴리기 때문에 EngageArena(렌더러)와 완전히
# 분리되며, 헤드리스로도 돌릴 수 있다. EngagePhaseManager 가 매 프레임
# step(delta) 를 호출하고, EngageArena 는 units / turrets / projectiles /
# popups 를 읽어 그리기만 한다.
#
# 좌표계: 전장의 육각 셀 매핑은 **버렸다**. 아레나는 팀0(아군)이 왼쪽,
# 팀1(적군)이 오른쪽에 마주 서는 평면 벨트다. x = 벨트를 따라가는 진행 방향,
# y = 벨트의 얕은 깊이(위쪽이 멀고 아래쪽이 가깝다). 파일럿이 전장 어느 셀에
# 있었는지는 배치에 반영하지 않는다 — 역할이 자리를 정한다(근접 앞줄 /
# 원거리 뒷줄).
#
# 행동 모델: 각 유닛은 자기 자리(anchor_pos)에 서서 **보이지 않는 ATB
# 게이지**를 채운다. 게이지 충전 속도는 메크의 speed 스탯에 비례하므로 빠른
# 메크는 자기 차례가 자주 돌아오고, 느린 메크가 한 번 행동하는 동안 두 번
# 행동하기도 한다. 게이지가 차면 대상에게 접근 → 공격 → **그 자리에 눌러앉는다**.
# 원위치 복귀는 없다 — 공격을 끝낸 자리가 곧 새 anchor_pos 가 되므로 교전이
# 길어질수록 양 팀이 서로에게 파고들어 중앙에서 뭉친다.
#
# 데미지는 PilotData 에 직접 적용된다 — 교전이 끝나면 전장 상태에 그대로
# 반영된다(턴제 시절과 동일).

# ─── 시간 / 종료 ─────────────────────────────────────────────────────────────
## engage:N 의 N 을 초로 환산하는 계수. engage:3 → 9초.
const SEC_PER_ROUND: float = 3.0
## 결투(1:1)는 한 쪽이 처치될 때까지 — 다만 서로 못 잡고 버티는 조합(원거리
## 미러 등)이 있으므로 관전 페이싱용 상한을 둔다.
const DUEL_MAX_SEC: float = 15.0

# ─── 벨트 지오메트리 (아레나 좌표, 렌더러가 카메라로 화면에 맞춘다) ──────────
## 벨트 전체 폭. 유닛은 항상 이 안에 갇힌다 — 교전 중 이탈은 없다.
## EngageArena.BAND_RECT(1032×620)에 포탑까지 통째로 들어가는 크기로 잡혀 있다 —
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
const MOVE_SPEED_MELEE: float = 880.0
const MOVE_SPEED_RANGED: float = 620.0
## 넉백으로 밀려난 만큼 자기 자리(anchor_pos)로 되돌아오는 드리프트 속도 배율.
## **원위치 복귀가 아니다** — 앵커 자체가 마지막으로 공격한 자리로 갱신되므로
## 이 드리프트는 "맞고 밀린 걸 추스르는" 몫만 담당한다.
const SETTLE_SPEED_MULT: float = 0.85
## 접근 단계가 이 시간을 넘기면 이번 차례를 접는다(대상이 계속 밀려나며 도망가는
## 등의 교착 방지). 접는 자리가 곧 새 앵커다.
const ADVANCE_MAX_SEC: float = 1.8
## 공격 모션을 붙잡는 시간. 이 동안 유닛은 대상 앞에 멈춰 서 있다.
const STRIKE_HOLD_MELEE: float = 0.26
const STRIKE_HOLD_RANGED: float = 0.34
## 앵커에 도착한 것으로 치는 거리.
const HOME_EPSILON: float = 6.0
## 사거리 판정 여유(px). **없으면 근접이 두 번째 공격부터 영영 못 나간다.**
## `_tick_advance` 의 정지점은 `target.pos - dir * strike_dist()` 이고
## `_step_toward` 가 거기에 스냅하므로, 접근을 끝낸 유닛은 사거리 **딱 그
## 거리**에 선다. 그 자리에서 다시 잰 거리는 부동소수 오차로 88.0 바로 위에
## 떨어지기 일쑤라 `dist <= strike_dist()` 가 거짓이 되고, 유닛은 이미 도착한
## 정지점을 향해 0px 씩 "이동"하다가 `ADVANCE_MAX_SEC`(1.8초) 교착으로만
## 차례를 접는다 — 공격은 한 번도 성립하지 않는다. 실측(1:1 근접, 9초):
## 이 여유가 없으면 공격 1회, 있으면 9회.
const STRIKE_DIST_EPSILON: float = 0.5

# ─── ATB ─────────────────────────────────────────────────────────────────────
## 게이지 만충 값. 화면에는 표시되지 않는다 — 속도 차이는 "쟤가 더 자주 움직인다"
## 로만 드러난다.
const ATB_FULL: float = 100.0
## 이 속도의 메크가 ATB_REF_SEC 마다 한 번 행동한다는 기준점.
const ATB_REF_SPEED: float = 70.0
const ATB_REF_SEC: float = 1.9
## 게이지는 행동 중에도 계속 찬다. 그래서 빠른 메크는 복귀하자마자 다시
## 나갈 수 있다("가끔 두 번 행동"). 다만 무한정 쌓이지는 않도록 상한을 둔다.
const ATB_MAX: float = ATB_FULL * 2.0
## 교전을 연 시전자는 이만큼 채워진 채로 시작한다 — 선공권.
const ATB_CASTER_HEAD_START: float = 0.6
## 나머지 유닛의 시작 게이지 흐트러짐(만충 대비 비율).
const ATB_START_JITTER: float = 0.25

# ─── 넉백 (피격 피드백 + 재접근 거리) ───────────────────────────────────────
## 명중 시 대상에게 실리는 초기 속도(px/s). 감쇠까지 합치면 근접 ≈ 47px,
## 원거리 ≈ 17px 밀려나고, 밀려난 자리가 그대로 새 앵커가 된다
## (`_apply_knockback`). 이 거리가 근접의 다음 차례 돌진 거리이기도 하다 —
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
# 전장과 달리 아레나의 포탑은 **파일럿을 공격한다**. 다만 예전의 "사거리 원"
# 개념은 없다 — 포탑은 교전에 참가하면 아레나 전체를 사정권으로 본다.
# 참가 조건은 단 하나: **자기 팀 파일럿이 그 포탑 칸 위에 서 있을 때**.
# 즉 포탑 칸에 있는 적을 상대로 교전을 걸면 그 포탑이 방어에 가담한다.
#
# **포탑은 무대 참가자가 아니라 배경 지형 구조물이다.** 유닛 벨트가 아니라
# 지평선 너머(y < 0)의 먼 지형 위에 서고, 렌더러의 카메라 프레이밍에서도
# 빠진다(EngageArena._focus_positions) — 포탑을 프레임에 넣으면 벨트 양 끝까지
# 담느라 배율이 떨어져 정작 싸우는 유닛이 잘게 보였다.
## 포탑이 서는 x — 자기 팀 **뒷줄에서 이만큼 더 바깥**. 예전처럼 벨트 끝
## (x=130)까지 밀면, 카메라가 유닛만 프레이밍하게 된 지금은 배율이 높아
## 포탑이 화면에 거의 잡히지 않는다. 뒷줄 바로 뒤에 세워야 배경에 서 있는 게
## 실제로 보인다.
const TURRET_BACK_OFFSET: float = 90.0
## 포탑이 서는 y — 유닛 슬롯(DEPTH_MARGIN 60 부터)보다 살짝 위, 즉 **가장 먼
## 바닥선**. 지평선 너머(y<0)로 더 밀면 카메라가 유닛만 프레이밍하는 지금은
## 탑신이 밴드 위쪽으로 잘려 나간다 — 유닛 위로 남는 여백이 거의 없기 때문.
const TURRET_BG_Y: float = 48.0
## 같은 팀 포탑이 둘 이상이면 깊이(y) 대신 x 로 나눠 세운다 — 배경 지형은
## 지평선 한 줄이라 y 로 흩으면 그 줄을 벗어난다. 두 번째부터는 더 바깥에 선다.
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

## 행동 사이클. 이탈 / 후퇴 / **원위치 복귀** 상태는 없다 — 교전이 끝날 때까지
## 아무도 벨트를 뜨지 못하고, 공격을 끝낸 유닛은 그 자리에 눌러앉는다.
##   IDLE    — 지금 자리에서 대기(넉백 복원 드리프트 포함). ATB 충전.
##   ADVANCE — 대상에게 접근. 사거리에 들면 STRIKE.
##   STRIKE  — 공격 판정 완료, 모션 홀드. 끝나면 그 자리를 앵커로 삼고 IDLE.
enum State { IDLE, ADVANCE, STRIKE, DEAD }


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
	var atk_range: float = 0.0
	var move_speed: float = 0.0
	## ATB 충전 속도(초당 게이지). speed 스탯에서 유도한다.
	var atb_rate: float = 0.0
	var atb: float = 0.0

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
	var atb: float = 0.0
	var atb_rate: float = 0.0
	## 사격 모션 잔여 시간(렌더러 전용).
	var fire_t: float = 0.0
	## 마지막 사격 대상 — 렌더러가 사격선을 그릴 때 쓴다.
	var last_target: EUnit = null


# ─── 상태 (EngageArena 가 읽는다) ────────────────────────────────────────────
var units: Array = []          # Array[EUnit]
var turrets: Array = []        # Array[ETurret]
var projectiles: Array = []    # Array[Dictionary] {from,to,t,dur,team,is_turret}
var popups: Array = []         # Array[Dictionary] {pos,text,color} — 렌더러가 소비 후 비운다
var stats: Dictionary = {}     # PilotData → {dealt,taken,kills}

var elapsed: float = 0.0
var duration: float = 0.0
var finished: bool = false
var initiator_team: int = 0
var is_duel: bool = false

var _bs: BattleSim = null
var _origin_cell: Vector2i = Vector2i.ZERO


# 유닛이 돌아다닐 수 있는 벨트 사각형. 렌더러의 최소 카메라 배율도 여기서 나온다.
static func belt_rect() -> Rect2:
	return Rect2(0.0, 0.0, BELT_W, BELT_H)


## 카메라가 비출 수 있는 최대 범위 — 벨트 + 배경 지형(포탑이 선 지평선 너머).
## 카메라 클램프를 belt_rect 로 두면 y < 0 에 선 포탑이 어떤 배율에서도 화면에
## 들어오지 못한다. 유닛 이동 한계는 여전히 belt_rect 다.
const STAGE_TOP_EXTRA: float = 150.0

static func stage_rect() -> Rect2:
	return Rect2(0.0, -STAGE_TOP_EXTRA, BELT_W, BELT_H + STAGE_TOP_EXTRA)


# 참가자 목록을 받아 벨트를 구성한다.
#   `caster`   — 시전자. 첫 ATB 를 미리 채운 채(선공) 시작한다.
#   `team0/1`  — 참가 PilotData 배열.
#   `secs`     — 제한 시간(초). 결투는 DUEL_MAX_SEC 로 넘긴다.
func setup(bs: BattleSim, caster: PilotData, team0: Array, team1: Array,
		secs: float, duel: bool) -> void:
	_bs = bs
	_origin_cell = caster.grid_pos
	initiator_team = caster.team
	is_duel = duel
	duration = secs

	_build_units(caster, team0, team1)
	_build_turrets()


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
			var u := _make_unit(p, p == caster)
			units.append(u)
			stats[p] = {"dealt": 0, "taken": 0, "kills": 0}
			(front if u.is_melee else back).append(u)
		_place_row(front, _row_x(t, true))
		_place_row(back, _row_x(t, false))


func _make_unit(p: PilotData, is_caster: bool) -> EUnit:
	var u := EUnit.new()
	u.pilot = p
	u.team = p.team
	u.is_melee = _is_melee_role(p.role)
	u.dives_backline = (p.role == GameEnums.Role.ASSASSIN)
	u.atk_range = MELEE_REACH if u.is_melee else RANGE_RANGED
	u.move_speed = MOVE_SPEED_MELEE if u.is_melee else MOVE_SPEED_RANGED
	u.atb_rate = atb_rate_for(p.speed)
	# 시전자는 선공권을 갖고, 나머지는 서로 조금씩 어긋난 채 시작한다.
	u.atb = ATB_FULL * (ATB_CASTER_HEAD_START if is_caster
			else randf() * ATB_START_JITTER)
	u.facing_x = 1.0 if u.team == 0 else -1.0
	return u


# speed 스탯 → 초당 게이지 충전량. speed == ATB_REF_SPEED 면 ATB_REF_SEC 마다
# 한 번 행동한다. speed 가 2배면 차례도 2배 자주 온다.
static func atb_rate_for(speed_stat: int) -> float:
	var s: float = float(max(1, speed_stat))
	return ATB_FULL * (s / ATB_REF_SPEED) / ATB_REF_SEC


# 팀 t 의 앞줄/뒷줄 x 좌표.
static func _row_x(team: int, is_front: bool) -> float:
	var centre: float = BELT_W * 0.5
	var depth_off: float = FRONT_OFFSET + (0.0 if is_front else ROW_GAP)
	return centre - depth_off if team == 0 else centre + depth_off


# 한 줄(같은 x)의 유닛들을 깊이 방향으로 균등 분배한다. 이 자리는 **개전
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


# 포탑 참가 규칙: **참가 파일럿이 자기 팀 포탑 칸 위에 서 있으면** 그 포탑이
# 교전에 가담한다. 즉 "포탑 칸에 있는 적에게 교전을 걸면 포탑이 같이 싸운다".
# 사거리 개념은 없다 — 참가한 포탑은 아레나 전체를 사정권으로 본다.
# 자리는 유닛 벨트가 아니라 **지평선 너머 배경 지형**(TURRET_BG_Y) 이다.
func _build_turrets() -> void:
	turrets.clear()
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
		if not (occupied[t.team] as Dictionary).has(t.grid_pos):
			continue
		var et := ETurret.new()
		et.data = t
		et.team = t.team
		et.atk = max(1, t.atk)
		et.atb_rate = atb_rate_for(_bs.TURRET_SPEED)
		et.atb = 0.0
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
func step(dt: float) -> void:
	if finished:
		return
	elapsed += dt

	for raw in turrets:
		_update_turret(raw as ETurret, dt)
	for raw in units:
		_update_unit(raw as EUnit, dt)
	_update_projectiles(dt)
	_check_end()


# 종료 판정이 난 뒤의 유예(EngagePhaseManager.END_HOLD_SEC) 동안 굴리는 스텝.
# 전투는 완전히 멈춘 상태에서 날아가던 투사체를 착탄시키고 피격 플래시 /
# 공격 모션 / 넉백만 마저 감쇠시킨다. `elapsed` 는 건드리지 않으므로 대시보드에
# 찍히는 교전 시간은 실제 전투 시간 그대로다.
func step_afterglow(dt: float) -> void:
	for raw in units:
		var u := raw as EUnit
		u.hit_flash = max(0.0, u.hit_flash - dt)
		u.swing_t = max(0.0, u.swing_t - dt)
		_apply_knockback(u, dt)
	for raw in turrets:
		var t := raw as ETurret
		t.fire_t = max(0.0, t.fire_t - dt)
	_update_projectiles(dt)


# 종료는 두 가지뿐이다 — 제한 시간 만료와 한 쪽 전멸. 둘 다 그 프레임에
# finished 가 서고, 대시보드는 매니저의 유예 시간만큼 늦게 뜬다.
# 교전 도중 이탈이 없으므로 engage:3 의 전투 시간은 정확히 9초다.
func _check_end() -> void:
	if elapsed >= duration:
		finished = true
		return
	if active_count(0) == 0 or active_count(1) == 0:
		finished = true


func active_count(team: int) -> int:
	var n := 0
	for raw in units:
		var u := raw as EUnit
		if u.team == team and u.is_active():
			n += 1
	return n


# ─── 유닛 업데이트 ───────────────────────────────────────────────────────────
func _update_unit(u: EUnit, dt: float) -> void:
	u.hit_flash = max(0.0, u.hit_flash - dt)
	u.swing_t = max(0.0, u.swing_t - dt)
	if u.state == State.DEAD:
		return
	if not u.pilot.alive:
		u.state = State.DEAD
		return

	# 넉백은 상태와 무관하게 항상 흐른다 — 돌진 중에 맞으면 그만큼 밀린다.
	_apply_knockback(u, dt)

	# 게이지는 행동 중에도 찬다. 그래서 빠른 메크는 복귀하자마자 다시 나간다.
	u.atb = minf(ATB_MAX, u.atb + u.atb_rate * dt)

	match u.state:
		State.IDLE:
			_tick_idle(u, dt)
		State.ADVANCE:
			_tick_advance(u, dt)
		State.STRIKE:
			_tick_strike(u, dt)


# 대기 — 자기 앵커에 붙어 선 채로 게이지가 차기를 기다린다. 앵커는 마지막으로
# 공격을 끝낸 자리(넉백으로 밀렸다면 밀려난 자리)이므로 이 드리프트는 진형으로
# 돌아가는 이동이 아니고, **넉백을 되돌리는 이동도 아니다** —
# `_apply_knockback` 이 앵커를 함께 밀기 때문에 밀리는 동안 드리프트는 할 일이
# 없다. 남는 역할은 벨트 클램프 등으로 어긋난 잔차를 추스르는 것뿐이다.
func _tick_idle(u: EUnit, dt: float) -> void:
	_step_toward(u, u.anchor_pos, u.move_speed * SETTLE_SPEED_MULT, dt)
	if u.atb < ATB_FULL:
		return
	var t := _pick_target(u)
	if t == null:
		return                      # 때릴 상대가 없으면 게이지를 물고 기다린다.
	u.atb -= ATB_FULL
	u.target = t
	u.state = State.ADVANCE
	u.act_t = 0.0


# 접근 — 사거리에 들 때까지 붙는다. 근접은 MELEE_REACH, 원거리는 최대 사거리의
# RANGED_APPROACH_RATIO(90%). 이미 그 안이면 곧장 공격한다.
func _tick_advance(u: EUnit, dt: float) -> void:
	u.act_t += dt
	if u.target == null or not u.target.is_active():
		u.target = _pick_target(u)
		if u.target == null:
			_settle(u)
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
		_settle(u)                # 교착 — 이번 차례는 접고 여기 눌러앉는다.
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
		_settle(u)


# 한 차례를 끝내고 **지금 서 있는 자리에 눌러앉는다**. 이 자리가 새 앵커이므로
# 다음 타겟 거리도, 넉백 복원 목표도 여기서 다시 잰다. 예전의 RETURN(진형
# 슬롯으로 복귀) 상태를 대체한다 — 되살리지 말 것.
func _settle(u: EUnit) -> void:
	u.state = State.IDLE
	u.target = null
	u.act_t = 0.0
	u.anchor_pos = u.pos


# `to` 로 dt 만큼 이동. 도착했으면 true.
func _step_toward(u: EUnit, to: Vector2, speed: float, dt: float) -> bool:
	var off: Vector2 = to - u.pos
	var d: float = off.length()
	if d <= HOME_EPSILON:
		u.pos = _clamp_to_belt(to)
		return true
	var step: float = speed * dt
	if step >= d:
		u.pos = _clamp_to_belt(to)
		return true
	u.pos = _clamp_to_belt(u.pos + off / d * step)
	return false


func _face_toward(u: EUnit, dx: float) -> void:
	if absf(dx) > 1.0:
		u.facing_x = 1.0 if dx > 0.0 else -1.0


# 넉백 속도를 적용하고 지수 감쇠시킨다. 상태와 무관하게 매 프레임 돈다.
#
# **밀려난 만큼 앵커도 같이 민다.** 앵커를 제자리에 두면 IDLE 의 복원 드리프트
# (`_tick_idle` → `move_speed × SETTLE_SPEED_MULT`, 근접 748px/s)가 넉백 초기
# 속도(근접 420px/s)보다 빨라서 맞은 유닛이 **맞은 그 프레임 안에** 앵커로
# 되돌아간다 — 화면상 넉백이 전혀 보이지 않았다(`_step_toward` 는 6px 안이면
# 목표로 스냅하므로 남는 잔차조차 없다). 앵커를 함께 옮기면 밀린 자리가 그대로
# 새 자리가 되고, 그래서
#   ① 넉백이 실제로 보이고,
#   ② 때린 쪽은 다음 차례에 그 거리를 다시 좁혀야 한다.
# ②가 없으면 근접은 첫 접근 이후 영원히 `MELEE_REACH` 에 붙어 선 채라
# `_tick_advance` 가 매번 같은 프레임에 STRIKE 로 넘어가 **공격 모션이 통째로
# 사라진다** — 1:1 근접에서는 무대에서 아무것도 움직이지 않는 것처럼 보인다.
# "밀려난 자리가 새 자리"는 `_settle()` 의 "공격을 끝낸 자리가 새 자리"와 같은
# 규칙이다 — 이 모듈에는 원위치 복귀가 없다.
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
const FOCUS_BONUS: float = 0.78     # 아군 1명이 이미 물고 있을 때마다 곱해지는 계수
const FOCUS_BONUS_FLOOR: float = 0.45
const LOW_HP_FOCUS: float = 0.6     # 빈사(35% 미만) 적 마무리 가중
## 암살자가 적 뒷줄(원거리)에 주는 가중. 낮을수록 더 집요하게 파고든다.
const DIVE_FOCUS: float = 0.40

func _pick_target(u: EUnit) -> EUnit:
	var focus: Dictionary = {}   # EUnit → 이미 이 적을 노리는 아군 수
	for raw in units:
		var a := raw as EUnit
		if a == u or a.team != u.team or not a.is_active():
			continue
		if a.target != null and a.target.is_active():
			focus[a.target] = int(focus.get(a.target, 0)) + 1

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
			# 없으면 앞줄이 더 가깝고 존재감(4 vs 2)까지 두 배라 원거리 메크가
			# 교전 내내 단 한 대도 맞지 않는다 — 실측으로 확인된 구멍이다.
			score = d * (DIVE_FOCUS if not e.is_melee else 1.0)
		else:
			score = d / float(max(1, e.pilot.presence))
		if e.hp_ratio() < 0.35:
			score *= LOW_HP_FOCUS
		var n: int = int(focus.get(e, 0))
		if n > 0:
			score *= maxf(FOCUS_BONUS_FLOOR, pow(FOCUS_BONUS, float(n)))
		if score < best_score:
			best_score = score
			best = e
	return best


# ─── 전투 해상도 ─────────────────────────────────────────────────────────────
# 데미지는 전장과 동일(명중 시 dmg = atk, 보호막부터 흡수)하지만 **명중률만은
# 전장과 별개**다 — `_hit_chance` 가 80~100% 구간으로 리맵한 확률을 준다.
func _resolve_attack(u: EUnit, target: EUnit) -> void:
	u.swing_t = 0.22
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

	var dealt := _apply_damage(d, max(1, a.atk))
	target.hit_flash = KNOCK_FLASH_SEC
	_apply_knock(u.pos, target,
			KNOCK_IMPULSE_MELEE if u.is_melee else KNOCK_IMPULSE_RANGED)
	(stats[a] as Dictionary)["dealt"] = int(stats[a]["dealt"]) + dealt
	(stats[d] as Dictionary)["taken"] = int(stats[d]["taken"]) + dealt
	if d.hp <= 0:
		_kill(target)
		(stats[a] as Dictionary)["kills"] = int(stats[a]["kills"]) + 1
		popups.append({"pos": target.pos, "text": "-%d  KO!" % dealt,
				"color": Color(1.0, 0.85, 0.30)})
	else:
		popups.append({"pos": target.pos, "text": "-%d" % dealt,
				"color": Color(1.0, 0.45, 0.45)})


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
	return absorbed + hp_dmg


func _kill(target: EUnit) -> void:
	# 전장과 같은 사망 경로를 탄다 — 리스폰 턴 스케일링(`respawn_turns_now`)이
	# 아레나 처치에도 그대로 걸린다.
	_bs.mark_pilot_dead(target.pilot)
	target.state = State.DEAD
	target.target = null
	target.knock_vel = Vector2.ZERO


# ─── 포탑 ────────────────────────────────────────────────────────────────────
# 전장에서는 포탑이 파일럿을 때리지 않지만, 교전에 가담한 포탑은 때린다.
# 포탑도 자기 ATB(TURRET_SPEED)를 굴리고 게이지가 차면 사격한다. 사거리 제한은
# 없으므로 아레나에 적이 하나라도 살아 있으면 반드시 대상을 찾는다.
func _update_turret(t: ETurret, dt: float) -> void:
	t.fire_t = max(0.0, t.fire_t - dt)
	t.atb = minf(ATB_MAX, t.atb + t.atb_rate * dt)
	if t.atb < ATB_FULL:
		return
	var victim: EUnit = _turret_target(t)
	if victim == null:
		t.last_target = null
		return
	t.atb -= ATB_FULL
	t.last_target = victim
	t.fire_t = 0.25
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
		_kill(victim)
		popups.append({"pos": victim.pos, "text": "-%d  포탑 처치" % dealt,
				"color": Color(1.0, 0.6, 0.25)})
	else:
		popups.append({"pos": victim.pos, "text": "-%d" % dealt,
				"color": Color(1.0, 0.72, 0.30)})


# 포탑에서 가장 가까운 적 — 자기 진영 깊숙이 파고든 유닛이 먼저 맞는다.
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


# 남은 시간(초). 0 이 되는 순간이 곧 종료다.
func time_left() -> float:
	return max(0.0, duration - elapsed)


func units_of(team: int) -> Array:
	var out: Array = []
	for raw in units:
		if (raw as EUnit).team == team:
			out.append(raw)
	return out
