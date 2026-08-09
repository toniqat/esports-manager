class_name RealtimeEngageSim
extends RefCounted

# 실시간 MOBA 교전 시뮬레이터 (headless).
#
# 턴제 라운드 루프를 대체한다. 노드를 하나도 만들지 않고 순수하게 상태만
# 굴리기 때문에 EngageArena(렌더러)와 완전히 분리되며, 헤드리스로도 돌릴 수
# 있다. EngagePhaseManager 가 매 프레임 step(delta) 를 호출하고, EngageArena
# 는 units / turrets / projectiles / popups 를 읽어 그리기만 한다.
#
# 좌표계: 전장의 육각 셀을 "아레나 공간"(뷰포트 픽셀)으로 확대 매핑한다.
# 교전 참여 셀(시전자 셀 + 인접 6칸)의 중심이 ARENA_CENTER 기준 오프셋으로
# 펼쳐지고, 파일럿은 자기 셀 안 랜덤 위치에서 시작한다.
#
# 데미지는 PilotData 에 직접 적용된다 — 교전이 끝나면 전장 상태에 그대로
# 반영된다(턴제 시절과 동일).

# ─── 시간 / 종료 ─────────────────────────────────────────────────────────────
## engage:N 의 N 을 초로 환산하는 계수. engage:3 → 9초.
const SEC_PER_ROUND: float = 3.0
## 제한 시간이 끝난 뒤 전원 후퇴를 연출할 여유 시간.
const RETREAT_GRACE: float = 1.8
## 이 비율 아래로 HP 가 떨어지면 후퇴 AI 로 전환.
const FLEE_HP_RATIO: float = 0.30
## 결투(1:1)는 처치되거나 이탈할 때까지 — 다만 원거리 vs 원거리 미러는 서로
## 카이팅만 하며 한참 버티기 때문에 관전 페이싱용 상한을 둔다.
const DUEL_MAX_SEC: float = 15.0

# ─── 아레나 지오메트리 (뷰포트 픽셀) ─────────────────────────────────────────
const ARENA_CENTER: Vector2 = Vector2(540.0, 880.0)
## 아레나 반경(가로/세로). 이 밖으로 나가면 이탈 성공으로 친다.
const ARENA_HALF: Vector2 = Vector2(480.0, 560.0)
## 전장 육각 1행 피치를 아레나에서 몇 px 로 확대할지.
const CELL_PITCH: float = 380.0
## 셀 안에서 시작 위치를 흩뿌리는 반경.
const SPAWN_JITTER: float = 92.0
## 같은 셀에 겹친 아군끼리 시작 시 벌어지는 거리.
const ALLY_CLUMP: float = 48.0

# ─── 유닛 ────────────────────────────────────────────────────────────────────
const UNIT_RADIUS: float = 34.0
## 원거리 기본 이동 속도(px/s). 근접은 여기에 MELEE_SPEED_MULT 를 곱한다.
const SPEED_RANGED: float = 190.0
const MELEE_SPEED_MULT: float = 1.1
const RANGE_MELEE: float = 86.0
const RANGE_RANGED: float = 300.0
const ATK_INTERVAL_MELEE: float = 0.85
const ATK_INTERVAL_RANGED: float = 1.05
## 공격 시 제자리에 묶이는 시간. 원거리가 더 길어서 카이팅 리듬이 생긴다.
const ATTACK_LOCK_MELEE: float = 0.30
const ATTACK_LOCK_RANGED: float = 0.45
## 원거리가 이 비율(사거리 대비)보다 가까워지면 물러난다 = 카이팅.
const KITE_INNER_RATIO: float = 0.72
const RETARGET_SEC: float = 1.6
const SEPARATION_RADIUS: float = 72.0
const SEPARATION_PUSH: float = 130.0
## 후퇴 중에는 조금 더 빠르게 빠진다.
const RETREAT_SPEED_MULT: float = 1.15

# ─── 대쉬 (교전을 시작한 근접 파일럿 1회) ────────────────────────────────────
const DASH_SPEED: float = 900.0
const DASH_SEC: float = 0.32

# ─── 포탑 ────────────────────────────────────────────────────────────────────
## CELL_PITCH(380) 보다 작게 잡는다 — 포탑이 자기 셀과 그 언저리만 위협해야
## 아레나 대부분이 금지구역이 되지 않는다. 여기를 CELL_PITCH 위로 올리면
## 포탑이 여러 개 걸린 교전에서 AI 가 싸우지 않고 회피만 하게 된다.
const TURRET_RANGE: float = 340.0
const TURRET_INTERVAL: float = 1.1
## 사거리 밖으로 이 정도 여유를 두고 회피한다.
const TURRET_SAFE_MARGIN: float = 45.0
const TURRET_AVOID_WEIGHT: float = 1.7
## 다이브 가능 여부를 재평가하는 주기.
const DIVE_EVAL_SEC: float = 0.5
## 다이브 후 빠져나오는 데 걸린다고 가정하는 시간.
const DIVE_ESCAPE_SEC: float = 1.2
## 다이브를 감행하려면 최대 HP 대비 이만큼은 남는다는 계산이 서야 한다.
const DIVE_SAFETY_RATIO: float = 0.18
## 교전 영역 중심에서 이 거리 안의 포탑만 아레나에 등장한다(육각 거리).
const TURRET_GATHER_DIST: int = 2

const PROJECTILE_SPEED: float = 1400.0

enum State { COMBAT, DASH, RETREAT, FLED, DEAD }


# ─── 유닛 ────────────────────────────────────────────────────────────────────
class EUnit extends RefCounted:
	var pilot: PilotData
	var team: int = 0
	var pos: Vector2 = Vector2.ZERO
	var is_melee: bool = true
	var atk_range: float = 0.0
	var speed: float = 0.0
	var atk_interval: float = 1.0
	var atk_lock: float = 0.0

	var state: int = State.COMBAT
	var target: EUnit = null
	var cooldown: float = 0.0
	var lock_t: float = 0.0
	var retarget_t: float = 0.0
	var dash_t: float = 0.0
	var dash_dir: Vector2 = Vector2.ZERO
	var has_dash: bool = false
	var dive_ok: bool = false
	var dive_eval_t: float = 0.0
	## 제한 시간 만료로 다 같이 물러난 것이 아니라, 스스로 저HP 이탈을 택했는가.
	## 결과 대시보드의 "이탈" 표기는 이 쪽만 센다 — 종료 후퇴는 이탈이 아니다.
	var fled_low_hp: bool = false
	## 마지막으로 바라본 방향 — 렌더러가 공격 연출 방향으로 쓴다.
	var facing: Vector2 = Vector2.DOWN
	## 피격 플래시 잔여 시간(렌더러 전용).
	var hit_flash: float = 0.0
	## 공격 모션 잔여 시간(렌더러 전용).
	var swing_t: float = 0.0

	func is_active() -> bool:
		return state != State.DEAD and state != State.FLED

	func hp_ratio() -> float:
		if pilot == null or pilot.max_hp <= 0:
			return 0.0
		return clampf(float(pilot.hp) / float(pilot.max_hp), 0.0, 1.0)

	func dps() -> float:
		return float(max(1, pilot.atk)) / max(0.1, atk_interval)


# ─── 아레나에 등장하는 포탑 ──────────────────────────────────────────────────
class ETurret extends RefCounted:
	var data: TurretData
	var team: int = 0
	var pos: Vector2 = Vector2.ZERO
	var cooldown: float = 0.0
	var atk: int = 0
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
## 아레나 그리드 표시용 — 교전에 포함된 셀들의 아레나 좌표.
var area_cell_positions: Array = []   # Array[Vector2]
## 아레나에서의 셀 외접원 반지름 (육각 외곽선 그리기용).
var cell_radius: float = CELL_PITCH / sqrt(3.0)

var _bs: BattleSim = null
var _origin_cell: Vector2i = Vector2i.ZERO
var _retreat_all: bool = false
var _retreat_started_at: float = 0.0


# 참가자 목록을 받아 아레나를 구성한다.
#   `caster`   — 시전자. 아레나 중심이 되는 셀의 주인이며, 근접이면 대쉬를 얻는다.
#   `team0/1`  — 참가 PilotData 배열.
#   `secs`     — 제한 시간(초). 결투는 DUEL_MAX_SEC 로 넘긴다.
func setup(bs: BattleSim, caster: PilotData, team0: Array, team1: Array,
		secs: float, duel: bool) -> void:
	_bs = bs
	_origin_cell = caster.grid_pos
	initiator_team = caster.team
	is_duel = duel
	duration = secs
	cell_radius = CELL_PITCH / sqrt(3.0)

	_build_area_cells()
	_build_units(caster, team0, team1)
	_build_turrets()


# ─── 구성 ────────────────────────────────────────────────────────────────────
func _build_area_cells() -> void:
	area_cell_positions.clear()
	area_cell_positions.append(arena_pos_for_cell(_origin_cell))
	for n in _bs.hex_grid.get_neighbors(_origin_cell.x, _origin_cell.y):
		area_cell_positions.append(arena_pos_for_cell(n))


# 전장 셀 중심 → 아레나 좌표. 전장의 육각 배치를 그대로 확대한 것이라
# "왼쪽 위 셀에 있던 파일럿은 아레나에서도 왼쪽 위"가 보장된다.
func arena_pos_for_cell(cell: Vector2i) -> Vector2:
	var here := _bs.hex_grid.hex_to_screen(cell.x, cell.y)
	var origin := _bs.hex_grid.hex_to_screen(_origin_cell.x, _origin_cell.y)
	var pitch: float = max(1.0, _bs.hex_grid.hex_height)
	return ARENA_CENTER + (here - origin) / pitch * CELL_PITCH


func _build_units(caster: PilotData, team0: Array, team1: Array) -> void:
	units.clear()
	stats.clear()
	# 같은 팀이 같은 셀에 겹쳐 있으면 서로 가까이 배치하기 위한 그룹 앵커.
	var clump_anchor: Dictionary = {}   # "team:cell" → Vector2
	var clump_count: Dictionary = {}    # "team:cell" → int

	for t in range(2):
		for raw in (team0 if t == 0 else team1):
			var p := raw as PilotData
			if p == null or not p.alive:
				continue
			var u := EUnit.new()
			u.pilot = p
			u.team = p.team
			u.is_melee = _is_melee_role(p.role)
			u.atk_range = RANGE_MELEE if u.is_melee else RANGE_RANGED
			u.speed = SPEED_RANGED * (MELEE_SPEED_MULT if u.is_melee else 1.0)
			u.atk_interval = ATK_INTERVAL_MELEE if u.is_melee else ATK_INTERVAL_RANGED
			u.atk_lock = ATTACK_LOCK_MELEE if u.is_melee else ATTACK_LOCK_RANGED
			# 첫 공격이 동시에 터지지 않도록 쿨다운을 살짝 흩뜨린다.
			u.cooldown = randf() * 0.4
			u.pos = _spawn_pos(p, clump_anchor, clump_count)
			# "교전을 시작한 파일럿" = 시전자. 근접일 때만 대쉬를 갖는다.
			u.has_dash = (p == caster and u.is_melee)
			u.facing = Vector2.UP if u.team == 0 else Vector2.DOWN
			units.append(u)
			stats[p] = {"dealt": 0, "taken": 0, "kills": 0}


func _spawn_pos(p: PilotData, anchors: Dictionary, counts: Dictionary) -> Vector2:
	var key := "%d:%d,%d" % [p.team, p.grid_pos.x, p.grid_pos.y]
	var base := arena_pos_for_cell(p.grid_pos)
	if anchors.has(key):
		# 같은 셀의 아군 — 앵커 주변에 붙여서 시작한다.
		var idx: int = int(counts[key])
		counts[key] = idx + 1
		var ang: float = TAU * float(idx) / 5.0 + randf() * 0.6
		var out: Vector2 = (anchors[key] as Vector2) \
				+ Vector2(cos(ang), sin(ang)) * (ALLY_CLUMP + float(idx) * 6.0)
		return _clamp_to_arena(out)
	# 셀 안 랜덤 배치. 팀 진영 쪽(아군은 아래, 적군은 위)으로 살짝 치우친다.
	var ang0: float = randf() * TAU
	var r: float = sqrt(randf()) * SPAWN_JITTER
	var side_bias: float = 34.0 * (1.0 if p.team == 0 else -1.0)
	var pos := base + Vector2(cos(ang0), sin(ang0)) * r + Vector2(0.0, side_bias)
	pos = _clamp_to_arena(pos)
	anchors[key] = pos
	counts[key] = 1
	return pos


func _build_turrets() -> void:
	turrets.clear()
	for raw in _bs.turrets:
		var t := raw as TurretData
		if t == null or not t.alive:
			continue
		if _bs.hex_grid.hex_distance(t.grid_pos, _origin_cell) > TURRET_GATHER_DIST:
			continue
		var et := ETurret.new()
		et.data = t
		et.team = t.team
		et.pos = arena_pos_for_cell(t.grid_pos)
		et.atk = max(1, t.atk)
		et.cooldown = randf() * TURRET_INTERVAL
		turrets.append(et)


static func _is_melee_role(role: int) -> bool:
	return role == GameEnums.Role.TANK \
			or role == GameEnums.Role.FIGHTER \
			or role == GameEnums.Role.ASSASSIN


# ─── 메인 스텝 ───────────────────────────────────────────────────────────────
func step(dt: float) -> void:
	if finished:
		return
	elapsed += dt

	if not _retreat_all and elapsed >= duration:
		_begin_global_retreat()

	for raw in turrets:
		_update_turret(raw as ETurret, dt)
	for raw in units:
		_update_unit(raw as EUnit, dt)
	_apply_separation(dt)
	_update_projectiles(dt)
	_check_end()


func _check_end() -> void:
	var a0 := active_count(0)
	var a1 := active_count(1)
	if not _retreat_all and (a0 == 0 or a1 == 0):
		_begin_global_retreat()
	if _retreat_all:
		if a0 + a1 == 0 or elapsed - _retreat_started_at >= RETREAT_GRACE:
			finished = true


func _begin_global_retreat() -> void:
	if _retreat_all:
		return
	_retreat_all = true
	_retreat_started_at = elapsed
	for raw in units:
		var u := raw as EUnit
		if u.is_active():
			u.state = State.RETREAT
			u.target = null


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
	if u.state == State.DEAD or u.state == State.FLED:
		return
	if not u.pilot.alive:
		u.state = State.DEAD
		return

	u.cooldown = max(0.0, u.cooldown - dt)
	u.lock_t = max(0.0, u.lock_t - dt)
	u.retarget_t = max(0.0, u.retarget_t - dt)
	u.dive_eval_t = max(0.0, u.dive_eval_t - dt)

	# 저HP 이탈 판정 — 전역 후퇴가 아니어도 스스로 빠진다.
	if u.state != State.RETREAT and u.hp_ratio() < FLEE_HP_RATIO:
		u.state = State.RETREAT
		u.target = null
		u.fled_low_hp = true

	if u.state == State.RETREAT:
		_update_retreat(u, dt)
		return

	# 대쉬는 상태 갱신보다 먼저 — 교전 시작 직후 1회만 발동한다.
	if u.has_dash and u.state == State.COMBAT:
		var first := _pick_target(u)
		if first != null:
			u.has_dash = false
			u.state = State.DASH
			u.target = first
			u.dash_t = DASH_SEC
			u.dash_dir = (first.pos - u.pos).normalized()

	if u.state == State.DASH:
		u.dash_t -= dt
		u.pos = _clamp_to_arena(u.pos + u.dash_dir * DASH_SPEED * dt)
		u.facing = u.dash_dir
		if u.dash_t <= 0.0:
			u.state = State.COMBAT
		return

	# 타겟 유지/재선정.
	if u.target == null or not u.target.is_active() or u.retarget_t <= 0.0:
		var t := _pick_target(u)
		if t != null:
			u.target = t
		u.retarget_t = RETARGET_SEC
	if u.target == null:
		return

	var to_target: Vector2 = u.target.pos - u.pos
	var dist: float = to_target.length()
	if dist > 0.001:
		u.facing = to_target / dist

	if u.dive_eval_t <= 0.0:
		u.dive_eval_t = DIVE_EVAL_SEC
		u.dive_ok = _should_dive(u)

	# 공격 — 사거리 안이고 쿨다운/경직이 풀렸을 때.
	if dist <= u.atk_range and u.cooldown <= 0.0 and u.lock_t <= 0.0:
		_resolve_attack(u, u.target)
		return

	# 공격 경직 중에는 못 움직인다.
	if u.lock_t > 0.0:
		return

	var desired := _desired_move_dir(u, dist)
	if desired.length_squared() > 0.0001:
		u.pos = _clamp_to_arena(u.pos + desired.normalized() * u.speed * dt)


# 전투 의도(접근/카이팅) + 포탑 회피를 합성한 이동 방향.
func _desired_move_dir(u: EUnit, dist: float) -> Vector2:
	var to_target: Vector2 = u.target.pos - u.pos
	var dir := Vector2.ZERO
	if dist > 0.001:
		var n: Vector2 = to_target / dist
		if u.is_melee:
			# 근접 — 사거리에 들어갈 때까지 붙는다.
			if dist > u.atk_range * 0.9:
				dir = n
		else:
			# 원거리 — 사거리 끝자락을 유지하며 거리를 벌린다(카이팅).
			if dist < u.atk_range * KITE_INNER_RATIO:
				dir = -n
			elif dist > u.atk_range * 0.95:
				dir = n
	# 적 포탑 회피. 다이브 판정이 서면 무시한다.
	if not u.dive_ok:
		for raw in turrets:
			var t := raw as ETurret
			if t.team == u.team:
				continue
			var away: Vector2 = u.pos - t.pos
			var d: float = away.length()
			var danger: float = TURRET_RANGE + TURRET_SAFE_MARGIN
			if d < danger and d > 0.001:
				# 사거리 안쪽일수록 강하게 밀어낸다.
				var w: float = TURRET_AVOID_WEIGHT * (1.0 - d / danger)
				dir += (away / d) * w
	return dir


# "버티고 잡고 빠져나올 수 있는가" 계산. 적 포탑 사거리 안으로 들어가야만
# 대상을 때릴 수 있을 때에만 의미가 있다.
func _should_dive(u: EUnit) -> bool:
	if u.target == null:
		return false
	var threat: float = _turret_dps_against(u.team, u.target.pos)
	if threat <= 0.0:
		return false   # 포탑이 안 걸리면 다이브라는 개념 자체가 없다.
	var my_dps: float = u.dps()
	if my_dps <= 0.0:
		return false
	var target_hp: float = float(u.target.pilot.hp + u.target.pilot.shield)
	var ttk: float = target_hp / my_dps
	var incoming: float = threat * (ttk + DIVE_ESCAPE_SEC)
	var survive_hp: float = float(u.pilot.hp + u.pilot.shield) - incoming
	return survive_hp > float(u.pilot.max_hp) * DIVE_SAFETY_RATIO


# `at` 지점에 서 있을 때 `team` 이 맞게 되는 적 포탑 DPS 총합.
func _turret_dps_against(team: int, at: Vector2) -> float:
	var total := 0.0
	for raw in turrets:
		var t := raw as ETurret
		if t.team == team:
			continue
		if at.distance_to(t.pos) <= TURRET_RANGE:
			total += float(t.atk) / TURRET_INTERVAL
	return total


func _update_retreat(u: EUnit, dt: float) -> void:
	# 자기 진영 방향(팀0 = 아래, 팀1 = 위)으로 빠지되, 가장 가까운 적에게서도
	# 멀어지는 쪽으로 합성한다.
	var home := Vector2(0.0, 1.0 if u.team == 0 else -1.0)
	var dir := home
	var nearest := _nearest_enemy(u)
	if nearest != null:
		var away: Vector2 = u.pos - nearest.pos
		if away.length() > 0.001:
			dir += away.normalized() * 0.8
	for raw in turrets:
		var t := raw as ETurret
		if t.team == u.team:
			continue
		var off: Vector2 = u.pos - t.pos
		var d: float = off.length()
		if d < TURRET_RANGE + TURRET_SAFE_MARGIN and d > 0.001:
			dir += (off / d) * TURRET_AVOID_WEIGHT
	if dir.length_squared() > 0.0001:
		u.pos += dir.normalized() * u.speed * RETREAT_SPEED_MULT * dt
		u.facing = dir.normalized()

	# 아레나 밖으로 완전히 빠져나오면 이탈 성공 — 살아서 전장으로 돌아간다.
	var off_c: Vector2 = u.pos - ARENA_CENTER
	if absf(off_c.y) > ARENA_HALF.y or absf(off_c.x) > ARENA_HALF.x:
		u.state = State.FLED


func _nearest_enemy(u: EUnit) -> EUnit:
	var best: EUnit = null
	var best_d: float = INF
	for raw in units:
		var e := raw as EUnit
		if e.team == u.team or not e.is_active():
			continue
		var d: float = u.pos.distance_squared_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


# 타겟 선정 — 거리 기반이되 존재감이 높은 쪽을 선호하고(어그로 가중),
# 아군이 이미 때리고 있는 적과 빈사인 적에 가산점을 준다. 집중 사격 항목이
# 없으면 모두가 각자 제일 가까운 적만 때려서 딜이 흩어지고 처치가 나오지
# 않는다 — 실제 MOBA 교전의 포커스를 흉내 내는 부분.
const FOCUS_BONUS: float = 0.78     # 아군 1명이 이미 물고 있을 때마다 곱해지는 계수
const FOCUS_BONUS_FLOOR: float = 0.45
const LOW_HP_FOCUS: float = 0.6     # 빈사(35% 미만) 적 마무리 가중

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
		var d: float = u.pos.distance_to(e.pos)
		var score: float = d / float(max(1, e.pilot.presence))
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
# 전장 룰과 동일: hit/(hit+evasion) 굴림, 명중 시 dmg = atk, 보호막부터 흡수.
func _resolve_attack(u: EUnit, target: EUnit) -> void:
	u.cooldown = u.atk_interval
	u.lock_t = u.atk_lock
	u.swing_t = 0.18
	if not u.is_melee:
		projectiles.append({
			"from": u.pos, "to": target.pos, "t": 0.0,
			"dur": max(0.05, u.pos.distance_to(target.pos) / PROJECTILE_SPEED),
			"team": u.team, "is_turret": false,
		})

	var a: PilotData = u.pilot
	var d: PilotData = target.pilot
	var hit_total: float = float(max(1, a.hit + d.evasion))
	if randf() >= float(a.hit) / hit_total:
		popups.append({"pos": target.pos, "text": "MISS",
				"color": Color(0.85, 0.85, 0.85)})
		return

	var dealt := _apply_damage(d, max(1, a.atk))
	target.hit_flash = 0.22
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
	target.pilot.alive = false
	target.pilot.respawn_timer = _bs.RESPAWN_TURNS
	target.state = State.DEAD
	target.target = null


# ─── 포탑 ────────────────────────────────────────────────────────────────────
# 전장에서는 포탑이 파일럿을 때리지 않지만, 아레나에서는 때린다 —
# "포탑 사거리에 닿으면 위험하다"가 이 시뮬레이터의 핵심 압박이기 때문.
func _update_turret(t: ETurret, dt: float) -> void:
	t.cooldown = max(0.0, t.cooldown - dt)
	if t.cooldown > 0.0:
		return
	var victim: EUnit = null
	var best_d: float = INF
	for raw in units:
		var u := raw as EUnit
		if u.team == t.team or not u.is_active():
			continue
		var d: float = u.pos.distance_to(t.pos)
		if d <= TURRET_RANGE and d < best_d:
			best_d = d
			victim = u
	if victim == null:
		t.last_target = null
		return
	t.cooldown = TURRET_INTERVAL
	t.last_target = victim
	projectiles.append({
		"from": t.pos, "to": victim.pos, "t": 0.0,
		"dur": max(0.05, best_d / PROJECTILE_SPEED),
		"team": t.team, "is_turret": true,
	})
	# 포탑 사격은 빗나가지 않는다.
	var dealt := _apply_damage(victim.pilot, t.atk)
	victim.hit_flash = 0.22
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


# ─── 보조 ────────────────────────────────────────────────────────────────────
# 유닛끼리 완전히 겹쳐 보이지 않도록 하는 약한 분리력.
func _apply_separation(dt: float) -> void:
	for i in units.size():
		var a := units[i] as EUnit
		if not a.is_active():
			continue
		for j in range(i + 1, units.size()):
			var b := units[j] as EUnit
			if not b.is_active():
				continue
			var off: Vector2 = b.pos - a.pos
			var d: float = off.length()
			if d >= SEPARATION_RADIUS:
				continue
			var push: Vector2
			if d < 0.001:
				push = Vector2(randf() - 0.5, randf() - 0.5).normalized()
			else:
				push = off / d
			var strength: float = (1.0 - d / SEPARATION_RADIUS) * SEPARATION_PUSH * dt
			a.pos -= push * strength
			b.pos += push * strength
	for raw in units:
		var u := raw as EUnit
		# 후퇴/이탈 중에는 아레나 밖으로 나가야 하므로 가두지 않는다.
		if u.is_active() and u.state != State.RETREAT:
			u.pos = _clamp_to_arena(u.pos)


func _update_projectiles(dt: float) -> void:
	var keep: Array = []
	for raw in projectiles:
		var p: Dictionary = raw
		p["t"] = float(p["t"]) + dt
		if float(p["t"]) < float(p["dur"]):
			keep.append(p)
	projectiles = keep


func _clamp_to_arena(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, ARENA_CENTER.x - ARENA_HALF.x + UNIT_RADIUS,
				ARENA_CENTER.x + ARENA_HALF.x - UNIT_RADIUS),
		clampf(p.y, ARENA_CENTER.y - ARENA_HALF.y + UNIT_RADIUS,
				ARENA_CENTER.y + ARENA_HALF.y - UNIT_RADIUS))


# 남은 시간(초). 후퇴 구간에서는 0 에 고정된다.
func time_left() -> float:
	return max(0.0, duration - elapsed)


func units_of(team: int) -> Array:
	var out: Array = []
	for raw in units:
		if (raw as EUnit).team == team:
			out.append(raw)
	return out
