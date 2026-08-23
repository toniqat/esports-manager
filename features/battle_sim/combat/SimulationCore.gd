class_name SimulationCore
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# ─── Hardcoded jungle layout ─────────────────────────────────────────────────
# The map starts with both jungles already captured by their respective teams.
# The two side cells between them (`NEUTRAL_LEFT` / `NEUTRAL_RIGHT`) are
# **permanently neutral** — see `is_objective_cell`.
# Coordinates use the BattleField TileMap's negative-coord system.
const JUNGLE_TEAM0_LEFT  := [Vector2i(-2,  0), Vector2i(-2, -1), Vector2i(-3,  0)]
const JUNGLE_TEAM0_RIGHT := [Vector2i( 0,  0), Vector2i( 0, -1), Vector2i( 1,  0)]
const JUNGLE_TEAM1_LEFT  := [Vector2i(-2, -3), Vector2i(-2, -2), Vector2i(-3, -2)]
const JUNGLE_TEAM1_RIGHT := [Vector2i( 0, -3), Vector2i( 0, -2), Vector2i( 1, -2)]
## 좌측 오브젝트(전령) 칸. 상시 중립이다 — 아래 `is_objective_cell` 참조.
const NEUTRAL_LEFT  := Vector2i(-3, -1)
## 우측 오브젝트(용) 칸. 상시 중립이다.
const NEUTRAL_RIGHT := Vector2i( 1, -1)


## **오브젝트 칸인가.** 좌우 중립 두 칸은 정글이 아니라 **오브젝트가 서는
## 자리**이고, 그래서 정글 규칙에서 통째로 빠진다:
##
##   • 캠프가 서지 않는다 (`init_jungle_camps`) — 밟아도 성장치가 안 나온다.
##   • 정글러가 점령할 수 없다 (`process_neutral_zone_captures`).
##   • T1 파괴 보상의 측면 중립 탈취 분기도 사라졌다 (`_on_t1_destroyed`) —
##     아무도 소유하지 않으므로 뺏을 것이 없다.
##   • 정글러의 순회 목표에서도 빠진다 (`_jungle_goal_for`).
##
## 예전에는 정글러가 밟아서 자기 팀 색으로 칠하는 **12번째 · 13번째 캠프**였다.
## 그 몫은 나머지 캠프 값(`BattleSim.SCORE_JUNGLE_CAMP` 0.98 → 1.15)으로
## 되돌려 놓았다 — 정글러의 수입 총량은 그대로 두고, 지도 한복판의 두 칸만
## "먹는 곳"에서 "싸우는 곳"으로 바뀐 것이다.
static func is_objective_cell(cell: Vector2i) -> bool:
	return cell == NEUTRAL_LEFT or cell == NEUTRAL_RIGHT

# 취약지점 (vulnerable points) per team per lane. Defined as the jungle cell(s)
# in a team's own territory that sit closest to enemy territory along that lane.
# When the team's same-lane T1 falls, these are what the enemy normally claims
# (subject to the side-neutral and restoration overrides in `_on_t1_destroyed`).
# Side lanes have a single cell; mid has the two flanking cells.
const VULN_TEAM0_LEFT   := [Vector2i(-3,  0)]
const VULN_TEAM0_CENTER := [Vector2i(-2, -1), Vector2i( 0, -1)]
const VULN_TEAM0_RIGHT  := [Vector2i( 1,  0)]
const VULN_TEAM1_LEFT   := [Vector2i(-3, -2)]
const VULN_TEAM1_CENTER := [Vector2i(-2, -2), Vector2i( 0, -2)]
const VULN_TEAM1_RIGHT  := [Vector2i( 1, -2)]

# ─── 성장치 귀속 (턴 안에서만 산다) ──────────────────────────────────────────
# 전장 피해는 두 단계로 처리된다: 판정 단계(`_resolve_*`)가 `damage_map` /
# `turret_dmg` 에 양만 쌓고, 적용 단계가 그걸 소진하며 HP 를 깎는다. 적용
# 단계에는 **누가 때렸는지가 남아 있지 않아** 처치 성장치를 귀속할 수 없다.
# 그래서 판정 단계에서 "마지막으로 이 대상을 때린 자"를 여기 적어 두고, 적용
# 단계가 `mark_pilot_dead(victim, killer)` / `score_turret_kill` 에 넘긴다.
# 매 턴 `simulate_turn` 첫머리에서 비운다 — 턴을 넘겨 살아남으면 안 되는 정보다.
var _last_hitter: Dictionary = {}         # PilotData victim  → PilotData attacker
var _last_turret_hitter: Dictionary = {}  # TurretData victim → PilotData attacker


# ─── Main turn (== 1 minute) loop ─────────────────────────────────────────────
func simulate_turn() -> void:
	if _bs.game_over or _bs.game_phase != GameEnums.BattlePhase.BATTLE:
		return
	_last_hitter.clear()
	_last_turret_hitter.clear()
	_bs.turn_count += 1
	_bs.blog.begin_turn()
	# 성장 / 지속 효과 만료가 턴의 맨 앞이다. 이 자리라야 이번 턴의 교전이
	# 갱신된 스탯으로 굴러가고, 뒤이어 붙는 pending_atk_buff 가 성장 재계산에
	# 지워지지 않는다(버프는 같은 simulate_turn 안에서 붙었다 떼어진다).
	tick_growth_and_expiries()
	_bs.blog.stage("1-respawn")
	process_respawns()

	# Apply pending ATK buffs from card plays this turn (kept from old design).
	# 가산은 `atk` 가 아니라 `atk_buff` 에 얹는다 — 성장 재계산이 이 턴 한가운데
	# (처치가 나면 그 자리에서) 돌기 때문에 `atk` 를 직접 밀면 가산분이 지워지고
	# 턴 끝의 되돌리기가 원본을 깎아 버린다.
	var buff_p  := _bs.pending_atk_buff_p
	var buff_ai := _bs.pending_atk_buff_ai
	var buffed_pilots: Array = []
	if buff_p > 0 or buff_ai > 0:
		for raw_p in _bs.pilots:
			var bp := raw_p as PilotData
			if not bp.alive: continue
			if bp.team == 0 and buff_p > 0:
				bp.atk_buff += buff_p; buffed_pilots.append(bp)
			elif bp.team == 1 and buff_ai > 0:
				bp.atk_buff += buff_ai; buffed_pilots.append(bp)
		for raw_p in buffed_pilots:
			_bs.refresh_growth_stats(raw_p as PilotData)

	var log_lines: Array = []
	# 1. Recall (instant teleport) for any pilot under HP threshold.
	_bs.blog.stage("2-recall")
	_bs.recall_sys.process_recalls(log_lines)

	# 2. Per-cell engagement resolution. Engaged pilots fight; the sets it fills
	#    feed the single movement pass in step 4.
	var damage_map: Dictionary = {}    # PilotData → int
	var turret_dmg: Dictionary = {}    # TurretData → int
	var advance_set: Dictionary = {}   # PilotData → true
	var retreat_set: Dictionary = {}   # PilotData → true
	var engaged: Dictionary = {}       # PilotData → true (cannot move this turn)

	_bs.blog.stage("3-engage")
	var by_cell: Dictionary = _group_pilots_by_cell()
	for pos in by_cell.keys():
		var bucket: Dictionary = by_cell[pos] as Dictionary
		var t0: Array = (bucket.get("t0", []) as Array).duplicate()
		var t1: Array = (bucket.get("t1", []) as Array).duplicate()
		_resolve_cell(pos as Vector2i, t0, t1,
				damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)
	# 인접 공성은 없다 — 전진하는 파일럿은 적 포탑 칸에 **실제로 올라선다**.
	# 포탑 피해는 그 칸에 서서 맞는 **다음 턴**의 `_resolve_cell` 이 넣는다.
	_bs.blog.log_event("SETS", "engaged=%s advance=%s retreat=%s" % [
			_labels(engaged.keys()), _labels(advance_set.keys()),
			_labels(retreat_set.keys())])

	# 3. Apply combat damage (pilots first, then turrets) — BEFORE any movement.
	# The damage/push sets were all computed from the pre-movement positions, so
	# resolving their consequences first means the single movement pass below
	# sees one consistent world: pilots killed this turn never move, and a
	# turret destroyed this turn is already gone for everyone's pathfinding.
	# 보호막 sits on top of HP — battlefield hits bleed it down before HP, same
	# rule the 공격 card uses. 본진 복귀 (RecallSystem) zeroes the shield.
	_bs.blog.stage("4-damage")
	for k in damage_map.keys():
		var p := k as PilotData
		var dmg: int = damage_map[k]
		var shield_before: int = p.shield
		if dmg > 0 and p.shield > 0:
			var absorbed: int = min(p.shield, dmg)
			p.shield -= absorbed
			dmg -= absorbed
		p.hp -= dmg
		_bs.blog.log_event("DMG", "%-4s -%d (shield %d→%d) hp→%d @%s" % [
				_bs.pilot_label(p), int(damage_map[k]), shield_before, p.shield,
				maxi(p.hp, 0), str(p.grid_pos)])
		if p.hp <= 0:
			_bs.mark_pilot_dead(p, _last_hitter.get(p, null) as PilotData)
			log_lines.append("%s died" % _bs.pilot_label(p))
			_bs.blog.log_event("DEATH", "%-4s died @%s (respawn in %d)" % [
					_bs.pilot_label(p), str(p.grid_pos), p.respawn_timer])
		elif damage_map[k] > 0:
			_bs.anim_pilot_shake(p)

	for k in turret_dmg.keys():
		var td := k as TurretData
		var was_alive := td.alive
		td.hp -= turret_dmg[k]
		_bs.blog.log_event("TURRET", "T%d[%s] team%d -%d hp→%d @%s" % [
				td.tier, _bs.LANE_NAMES[td.lane], td.team, int(turret_dmg[k]),
				maxi(td.hp, 0), str(td.grid_pos)])
		if td.hp > 0 and int(turret_dmg[k]) > 0:
			_bs.anim_turret_hit(td)
		if td.hp <= 0:
			td.hp = 0; td.alive = false
			log_lines.append("T%d %s turret destroyed!" % [td.tier, _bs.LANE_NAMES[td.lane]])
			_bs.blog.log_event("TURRET", "T%d[%s] team%d DESTROYED @%s" % [
					td.tier, _bs.LANE_NAMES[td.lane], td.team, str(td.grid_pos)])
			if was_alive:
				_bs.score_turret_kill(_last_turret_hitter.get(td, null) as PilotData, td)
				var b: Building = _bs.building_registry.get_at(td.grid_pos)
				if b != null:
					_bs.building_registry.unregister(b)
					b.queue_free()
			if was_alive and td.tier == 1:
				_on_t1_destroyed(td, log_lines)

	# 4. ONE movement pass for everybody — free movers and combat pushes alike.
	# See `resolve_movement` for why they cannot be two separate passes.
	_bs.blog.stage("5-move")
	resolve_movement(advance_set, retreat_set, engaged)

	# 5. HQ damage: any pilot sitting on enemy HQ once any T2 is down.
	_bs.blog.stage("6-hq")
	var hq_damage_p := 0
	var hq_damage_e := 0
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive: continue
		var defending_team := 1 if p.team == 0 else 0
		var ehq := _bs.ENEMY_HQ_POS if p.team == 0 else _bs.PLAYER_HQ_POS
		if p.grid_pos == ehq and any_t2_destroyed(defending_team):
			# 포탑과 같은 고정 피해다 — 성장한 공격력이 HQ 에 얹히면 후반
			# 한타 한 번에 경기가 닫혀 버린다.
			var hq_hit: int = _bs.PILOT_STRUCTURE_DMG
			if p.team == 0: hq_damage_e += hq_hit
			else:           hq_damage_p += hq_hit
			log_lines.append("%s→HQ:%d" % [_bs.pilot_label(p), hq_hit])
			_bs.blog.log_event("HQ", "%-4s hits team%d HQ for %d" % [
					_bs.pilot_label(p), defending_team, hq_hit])
	_bs.enemy_hq_hp  = max(0, _bs.enemy_hq_hp  - hq_damage_e)
	_bs.player_hq_hp = max(0, _bs.player_hq_hp - hq_damage_p)

	# Reset ATK buffs applied this turn
	for raw_p in buffed_pilots:
		var bp := raw_p as PilotData
		if bp.team == 0:    bp.atk_buff -= buff_p
		elif bp.team == 1:  bp.atk_buff -= buff_ai
		_bs.refresh_growth_stats(bp)
	_bs.pending_atk_buff_p  = 0
	_bs.pending_atk_buff_ai = 0

	_bs.blog.stage("7-zones")
	process_neutral_zone_captures()
	process_temp_zone_expiries()

	# 8. 성장치 적립 — 이동과 점령이 모두 끝난 **이번 턴의 최종 자리**로 판정한다.
	#    전선까지 걸어 들어간 턴에는 그 턴부터 벌고, 밀려난 턴에는 못 번다.
	_bs.blog.stage("8-income")
	award_frontline_income()
	process_jungle_camps()
	if not log_lines.is_empty(): _bs.last_log = log_lines[0]
	check_win_condition()
	_bs.blog.end_turn()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


# ─── 성장 / 지속 효과 만료 ───────────────────────────────────────────────────
## 매 턴 한 번, 턴 만료형 버프를 걷고 전원의 스탯을 성장치에서 다시 계산한다.
##
## **시간이 성장을 만들지 않는다.** 예전에는 여기서 살아 있는 파일럿마다
## `GROWTH_PER_TURN` 을 누적했는데, 그러면 (1) 아무것도 안 해도 자라서 킬·포탑·
## 파밍이 성장에 아무 영향이 없었고 (2) `atk` 와 `max_hp` 가 **같은 비율**로
## 자라 교전 타수가 영원히 그대로였다. 지금 성장은 전부 성장치(`PilotData.score`)
## 에서 나오고, 그 환산은 `BattleSim.refresh_growth_stats` 한 곳에 있다.
##
## 여기 남은 재계산은 **보험**이다 — 점수가 움직이는 모든 자리(`add_score`)가
## 이미 스탯을 갱신하므로 값은 보통 그대로다. 배율 만료(안전한 파밍이 끝나는
## 턴)처럼 점수를 건드리지 않고 조건만 바뀌는 경우를 여기서 쓸어 담는다.
##
## 이 호출이 턴의 맨 앞이라야 이번 턴 교전이 갱신된 스탯으로 굴러간다.
func tick_growth_and_expiries() -> void:
	var turn: int = _bs.turn_count
	for raw in _bs.pilots:
		var p := raw as PilotData
		# 만료는 죽어 있어도 돈다 — 버프의 수명은 전장에 서 있는지와 무관하다.
		if p.growth_rate_expire_turn >= 0 and turn >= p.growth_rate_expire_turn:
			p.growth_rate_mult        = 1.0
			p.growth_rate_expire_turn = -1
		if p.lane_stat_expire_turn >= 0 and turn >= p.lane_stat_expire_turn:
			p.lane_stat_mod        = 0.0
			p.lane_stat_expire_turn = -1
		_bs.refresh_growth_stats(p)


# ─── 성장치 적립: 전선 체류 ──────────────────────────────────────────────────
## 레인 파일럿의 기본 수입. **살아서 자기 레인의 전선 안에 서 있는 턴**마다
## `SCORE_FRONTLINE_PER_TURN` 이 들어온다.
##
## 전선 = 그 레인에서 **양 팀의 살아 있는 최전방 포탑 사이**(포탑 칸 포함)다.
## 외곽(T1)이 부서지면 그 팀 쪽 경계가 T2 로, T2 마저 부서지면 HQ 로 물러나
## 전선이 넓어진다 — 밀어낸 만큼 벌 수 있는 자리가 늘어나는 셈이다.
##
## 죽어 있거나 저HP 복귀로 HQ 에 서 있는 동안에는 한 푼도 안 들어온다. 사망과
## 복귀의 진짜 비용이 여기 있다 — 전장을 비운 시간이 곧 성장을 놓친 시간이다.
##
## **정글러는 제외**다. 정글러의 전선은 정글이고, 수입은 캠프에서 나온다.
func award_frontline_income() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or p.is_guerrilla:
			continue
		if not front_line_cells(p.lane).has(p.grid_pos):
			continue
		_bs.add_score(p, _bs.SCORE_FRONTLINE_PER_TURN)


## `lane` 번 레인의 전선 셀 집합. 포탑이 부서질 때마다 넓어지므로 캐시하지 않고
## 매 턴 다시 만든다 — 레인이 셋뿐이고 통로가 수십 칸이라 비용이 없다.
func front_line_cells(lane: int) -> Dictionary:
	var order: Dictionary = lane_corridor_order(lane)
	var result: Dictionary = {}
	if order.is_empty():
		return result
	var lo: int = _front_boundary_index(0, lane, order)
	var hi: int = _front_boundary_index(1, lane, order)
	if lo > hi:
		var tmp: int = lo; lo = hi; hi = tmp
	for raw in order.keys():
		var idx: int = int(order[raw])
		if idx >= lo and idx <= hi:
			result[raw as Vector2i] = true
	return result


## `team` 의 이 레인 전선 경계가 통로의 몇 번째 칸인가. 살아 있는 **가장 바깥**
## 포탑(T1 → T2 순)이고, 둘 다 부서졌으면 그 팀의 HQ 쪽 끝이다.
func _front_boundary_index(team: int, lane: int, order: Dictionary) -> int:
	for tier in [1, 2]:
		for raw in _bs.turrets:
			var td := raw as TurretData
			if not td.alive or td.team != team or td.lane != lane or td.tier != tier:
				continue
			if order.has(td.grid_pos):
				return int(order[td.grid_pos])
	# 포탑이 다 무너진 레인 — 경계는 그 팀 쪽 통로 끝(팀0 = 0, 팀1 = 마지막).
	return 0 if team == 0 else order.size() - 1


# ─── 성장치 적립: 정글 캠프 ──────────────────────────────────────────────────
## 정글러의 기본 수입. 자기 팀 소유(또는 아직 중립인) 정글 칸에 **차 있는 캠프**
## 를 밟으면 `SCORE_JUNGLE_CAMP` 를 먹고, 그 칸은 `JUNGLE_CAMP_RESPAWN_TURNS`
## 뒤에나 다시 찬다. 그래서 정글러는 한자리에 머물 수 없고 계속 순회해야 한다.
##
## 적 소유 칸의 캠프는 못 먹는다 — 적 정글을 **점령**해야(T1 파괴 보상 / 약탈)
## 돌 수 있는 캠프가 늘고, 그만큼 라이너를 추월할 수 있다.
##
## `process_neutral_zone_captures` **뒤에** 부른다: 방금 점령한 중립 칸의 캠프를
## 그 턴에 바로 먹게 하기 위해서다.
func process_jungle_camps() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or not p.is_guerrilla:
			continue
		if not camp_harvestable(p.grid_pos, p.team):
			continue
		_bs.jungle_camps[p.grid_pos] = _bs.turn_count + _bs.JUNGLE_CAMP_RESPAWN_TURNS
		_bs.add_score(p, _bs.SCORE_JUNGLE_CAMP)
		_bs.blog.log_event("CAMP", "%-4s 캠프 획득 %s (+%.2fk → %.2fk, 재생성 %d턴)"
				% [_bs.pilot_label(p), str(p.grid_pos), _bs.SCORE_JUNGLE_CAMP,
					p.score, _bs.JUNGLE_CAMP_RESPAWN_TURNS])


## 이 칸의 캠프를 `team` 이 지금 먹을 수 있는가. 렌더러(캠프 표시)와 정글러의
## 목표 선택이 같은 함수를 읽는다 — 화면에 보이는 캠프와 실제로 먹히는 캠프가
## 어긋나면 안 된다.
func camp_harvestable(cell: Vector2i, team: int) -> bool:
	var owner_id: int = int(_bs.neutral_zone_cells.get(cell, -2))
	if owner_id == -2 or owner_id == 1 - team:
		return false
	return camp_charged(cell)


## 이 칸의 캠프가 지금 **차 있는가** — 소유권은 보지 않는다. 적 소유 칸의 캠프도
## 차 있고 비고를 반복하므로, 렌더러는 그것을 "있지만 지금 우리 것은 아닌" 속 빈
## 마름모로 그린다(`BattleRenderer._draw_jungle_camps`). 적 정글을 뺏을 값어치가
## 지금 있는지를 화면에서 읽을 수 있어야 점령이 판단의 대상이 된다.
func camp_charged(cell: Vector2i) -> bool:
	if not _bs.neutral_zone_cells.has(cell):
		return false
	return _bs.turn_count >= int(_bs.jungle_camps.get(cell, 0))


## 모든 정글 칸에 캠프를 세운다. 개시 시점에는 전부 차 있다.
##
## **오브젝트 칸(좌우 중립)에는 캠프가 서지 않는다** — `jungle_camps` 에 아예
## 들어가지 않으므로 `camp_charged` 도 렌더러의 마름모도 그 칸을 모른다.
func init_jungle_camps() -> void:
	_bs.jungle_camps.clear()
	for raw in _bs.neutral_zone_cells.keys():
		var cell := raw as Vector2i
		if is_objective_cell(cell):
			continue
		_bs.jungle_camps[cell] = 0


## 작전 단계 만료형 성장 배율(완벽한 마무리)을 `team` 전원에게서 걷는다.
## CardPhaseManager 가 그 팀의 **다음 작전 단계 진입 시** 부른다.
func clear_growth_until_phase(team: int) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.team != team or not p.growth_until_phase:
			continue
		p.growth_until_phase      = false
		p.growth_rate_mult        = 1.0
		p.growth_rate_expire_turn = -1


# Compact "T0 F1 A0" style list of pilot labels — used for the per-turn
# engaged / advance / retreat set dump.
func _labels(pilot_list: Array) -> String:
	if pilot_list.is_empty():
		return "-"
	var parts: Array = []
	for raw in pilot_list:
		parts.append(_bs.pilot_label(raw as PilotData))
	return ",".join(parts)


# ─── Engagement helpers ───────────────────────────────────────────────────────

func _group_pilots_by_cell() -> Dictionary:
	# Returns pos → {"t0": [...], "t1": [...]} for cells with at least one alive pilot.
	var by_cell: Dictionary = {}
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive: continue
		if not by_cell.has(p.grid_pos):
			by_cell[p.grid_pos] = {"t0": [], "t1": []}
		var key := "t0" if p.team == 0 else "t1"
		(by_cell[p.grid_pos][key] as Array).append(p)
	return by_cell


# Resolves combat at a single cell. Mutates the damage/push/engagement maps.
# Lane-scope combat (pilot vs pilot, pilot vs turret) only involves lane pilots
# (non-junglers). Junglers are split off and resolved in their own jungler-vs-
# jungler bracket — they neither attack/defend turrets nor engage lane pilots.
func _resolve_cell(pos: Vector2i, t0: Array, t1: Array,
		damage_map: Dictionary, turret_dmg: Dictionary,
		advance_set: Dictionary, retreat_set: Dictionary,
		engaged: Dictionary, log_lines: Array) -> void:
	var t0_lane: Array = []
	var t0_jung: Array = []
	for raw in t0:
		var p := raw as PilotData
		if p.is_guerrilla: t0_jung.append(p)
		else: t0_lane.append(p)
	var t1_lane: Array = []
	var t1_jung: Array = []
	for raw in t1:
		var p := raw as PilotData
		if p.is_guerrilla: t1_jung.append(p)
		else: t1_lane.append(p)

	var enemy_turret_for_t0: TurretData = _enemy_turret_at(pos, 0)
	var enemy_turret_for_t1: TurretData = _enemy_turret_at(pos, 1)
	if not (t0.is_empty() or t1.is_empty()):
		_bs.blog.log_event("CELL", "%s  t0[lane=%s jung=%s] vs t1[lane=%s jung=%s] turret=%s" % [
				str(pos), _labels(t0_lane), _labels(t0_jung),
				_labels(t1_lane), _labels(t1_jung),
				"none" if (enemy_turret_for_t0 == null and enemy_turret_for_t1 == null)
					else "yes"])

	# Case A: team-0 lane attackers on team-1 turret cell.
	if enemy_turret_for_t0 != null:
		_resolve_lane_at_turret(t0_lane, t1_lane, enemy_turret_for_t0,
				damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)
	# Case B: team-1 lane attackers on team-0 turret cell.
	elif enemy_turret_for_t1 != null:
		_resolve_lane_at_turret(t1_lane, t0_lane, enemy_turret_for_t1,
				damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)
	# Case C: pure lane pilot vs lane pilot combat.
	elif not t0_lane.is_empty() and not t1_lane.is_empty():
		_resolve_pilot_combat(t0_lane, t1_lane, damage_map,
				advance_set, retreat_set, engaged, log_lines)

	# Jungler vs jungler runs in parallel with lane-scope combat. Junglers do
	# not engage lane pilots — they only fight other junglers contesting the
	# same cell (typically a neutral camp).
	if not t0_jung.is_empty() and not t1_jung.is_empty():
		_resolve_pilot_combat(t0_jung, t1_jung, damage_map,
				advance_set, retreat_set, engaged, log_lines)


# Splits attackers/defenders by lane match against the turret. Same-lane pilots
# engage in turret combat (only same-lane attackers damage the turret, only
# same-lane defenders defend). Off-lane pilots in the same cell don't interact
# with the turret, but if both teams have off-lane pilots present they still
# fight each other as pilot-vs-pilot (e.g. card-displaced encounters).
func _resolve_lane_at_turret(attackers_lane: Array, defenders_lane: Array, td: TurretData,
		damage_map: Dictionary, turret_dmg: Dictionary,
		advance_set: Dictionary, retreat_set: Dictionary,
		engaged: Dictionary, log_lines: Array) -> void:
	var same_attackers: Array = []
	var off_attackers: Array = []
	for raw in attackers_lane:
		var p := raw as PilotData
		if p.lane == td.lane: same_attackers.append(p)
		else: off_attackers.append(p)
	var same_defenders: Array = []
	var off_defenders: Array = []
	for raw in defenders_lane:
		var p := raw as PilotData
		if p.lane == td.lane: same_defenders.append(p)
		else: off_defenders.append(p)
	if not same_attackers.is_empty():
		_resolve_turret_combat(same_attackers, same_defenders, td,
				damage_map, turret_dmg, retreat_set, engaged, log_lines)
	if not off_attackers.is_empty() and not off_defenders.is_empty():
		_resolve_pilot_combat(off_attackers, off_defenders, damage_map,
				advance_set, retreat_set, engaged, log_lines)


func _resolve_pilot_combat(t0: Array, t1: Array,
		damage_map: Dictionary, advance_set: Dictionary,
		retreat_set: Dictionary, engaged: Dictionary, log_lines: Array) -> void:
	# Sort by HP ascending; pair index-by-index for damage rolls. Leftover
	# pilots beyond the matched count don't take damage this turn.
	# Push, however, is decided at the *team level* across the whole bracket:
	# whichever side lands more unilateral hits sweeps — every pilot of that
	# side in the cell advances, every opponent retreats (including unpaired
	# pilots). Tie or 0-0 → no push.
	t0.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	t1.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	var pairs := mini(t0.size(), t1.size())
	var t0_uni_wins := 0
	var t1_uni_wins := 0
	for i in pairs:
		var a := t0[i] as PilotData
		var b := t1[i] as PilotData
		engaged[a] = true; engaged[b] = true
		var hit_a := roll_hit(a, b)
		var hit_b := roll_hit(b, a)
		if hit_a:
			var dmg_a := _pilot_hit_damage(a)
			_credit_pilot_damage(a, b, dmg_a, damage_map)
			log_lines.append("%s→%s:%d" % [_bs.pilot_label(a), _bs.pilot_label(b), dmg_a])
		if hit_b:
			var dmg_b := _pilot_hit_damage(b)
			_credit_pilot_damage(b, a, dmg_b, damage_map)
			log_lines.append("%s→%s:%d" % [_bs.pilot_label(b), _bs.pilot_label(a), dmg_b])
		if hit_a and not hit_b:
			t0_uni_wins += 1
		elif hit_b and not hit_a:
			t1_uni_wins += 1
	_bs.blog.log_event("FIGHT", "pairs=%d  uni-wins t0=%d t1=%d  →%s" % [
			pairs, t0_uni_wins, t1_uni_wins,
			"t0 sweeps" if t0_uni_wins > t1_uni_wins
				else ("t1 sweeps" if t1_uni_wins > t0_uni_wins else "no push")])
	if t0_uni_wins > t1_uni_wins:
		for raw in t0: advance_set[raw as PilotData] = true
		for raw in t1: retreat_set[raw as PilotData] = true
	elif t1_uni_wins > t0_uni_wins:
		for raw in t1: advance_set[raw as PilotData] = true
		for raw in t0: retreat_set[raw as PilotData] = true


## 적 포탑 칸 **위에 서 있는** 공격자들의 공성. 전진이 포탑 칸까지 들어가므로
## 모든 공성이 여기를 지난다 — 평범한 전진, 교전 승리 후 따라 들어간 무리,
## 카드 이동으로 떨어진 경우 전부.
##
## **넉백은 수비자가 있을 때만이다.** 포탑에 무판정 피해를 넣고 → 그 칸의 같은
## 레인 공격자와 수비자가 **서로** 명중 판정을 굴리고 → **명중 여부와 무관하게**
## 공격자는 직전 칸으로 밀려난다. 수비자가 없으면 밀어낼 주체가 없으므로
## 공격자는 그 자리에 남아 매 턴 포탑을 갈아 낸다 — 무방비 포탑은 그대로
## 무너진다.
##
## 예외 하나: **때릴 수 없는 포탑**(같은 레인 T1 이 살아 있는 T2)이면 갈아 낼
## 것이 없으므로 붙잡아 두지 않는다 — 무조건 물러난다. 걸어서는 닿을 수 없는
## 칸이지만 이동 카드가 떨어뜨릴 수 있고, 그때 영원히 얼어붙으면 안 된다.
func _resolve_turret_combat(attackers: Array, defenders: Array, td: TurretData,
		damage_map: Dictionary, turret_dmg: Dictionary,
		retreat_set: Dictionary, engaged: Dictionary, log_lines: Array) -> void:
	# Mark all attackers and defenders as engaged (no free movement this turn).
	for raw in attackers: engaged[raw as PilotData] = true
	for raw in defenders: engaged[raw as PilotData] = true
	var attackable: bool = _turret_attackable(td)
	var pushed_out: bool = not defenders.is_empty() or not attackable
	_bs.blog.log_event("SIEGE", "T%d[%s] team%d @%s ← %s  (수비 %s → %s)" % [
			td.tier, _bs.LANE_NAMES[td.lane], td.team, str(td.grid_pos),
			_labels(attackers), _labels(defenders),
			"공격자 후퇴" if pushed_out else "눌러앉음"])
	_apply_turret_siege(attackers, defenders, td, damage_map, turret_dmg, log_lines)
	if not pushed_out:
		return
	for raw in attackers:
		retreat_set[raw as PilotData] = true


## 공성 1회 판정 — 한 포탑 칸에 올라선 같은 레인 공격자 묶음에 대해 돌린다.
##  • 공격자는 포탑에 **명중 판정 없이** 100% 피해를 넣는다(같은 레인 T2 는
##    T1 이 살아 있는 동안 무적). 이게 먼저다 — 포탑 피해는 수비자가 농성하든
##    말든 **반드시** 들어간다.
##  • 그 다음, 포탑 칸에서 맞붙은 공격자와 수비자가 **서로** 명중 판정을 굴린다
##    (HP 오름차순 1:1 페어링, 피해는 `_pilot_hit_damage` = 전장 배율 적용).
##    예전에는 공격자의 공격이 전부 포탑으로만 가서 농성 중인 수비자는 공격자를
##    일방적으로 두들길 수 있었다 — 이제 포탑을 갈아 내는 것과 별개로 눈앞의
##    수비자에게도 명중 판정만큼 피해가 들어간다.
## 후퇴 처리는 호출자(`_resolve_turret_combat`)가 한다 — 수비자가 있을 때만.
func _apply_turret_siege(attackers: Array, defenders: Array, td: TurretData,
		damage_map: Dictionary, turret_dmg: Dictionary, log_lines: Array) -> void:
	if _turret_attackable(td):
		for raw in attackers:
			var a := raw as PilotData
			_credit_turret_damage(a, td, _bs.PILOT_STRUCTURE_DMG, turret_dmg)
			log_lines.append("%s→T%d[%s]:%d" % [_bs.pilot_label(a), td.tier,
					_bs.LANE_NAMES[td.lane], _bs.PILOT_STRUCTURE_DMG])

	if defenders.is_empty():
		return
	var atk_sorted := attackers.duplicate()
	atk_sorted.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	var def_sorted := defenders.duplicate()
	def_sorted.sort_custom(func(a: PilotData, b: PilotData) -> bool: return a.hp < b.hp)
	var pairs := mini(atk_sorted.size(), def_sorted.size())
	for i in pairs:
		var a := atk_sorted[i] as PilotData
		var d := def_sorted[i] as PilotData
		if roll_hit(a, d):
			var dmg_a := _pilot_hit_damage(a)
			_credit_pilot_damage(a, d, dmg_a, damage_map)
			log_lines.append("%s→%s:%d (attacker)" % [
					_bs.pilot_label(a), _bs.pilot_label(d), dmg_a])
		if roll_hit(d, a):
			var dmg_d := _pilot_hit_damage(d)
			_credit_pilot_damage(d, a, dmg_d, damage_map)
			log_lines.append("%s→%s:%d (defender)" % [
					_bs.pilot_label(d), _bs.pilot_label(a), dmg_d])


# Hit chance = attacker.hit / (attacker.hit + defender.evasion). Pure roll.
#
# 이건 **전장 전용** 명중률이다. 교전(TurnEngageSim)은 이 값을 기준값으로만
# 삼아 [ENGAGE_HIT_MIN, ENGAGE_HIT_MAX] = 80~100% 구간으로 리맵한 별도 확률을
# 쓴다 — 여기를 고쳐도 교전 구간은 그대로이고, 그 반대도 마찬가지다.
#
# 공개 함수 — 카드 공격(`CardPhaseManager._effect_attack`)도 같은 판정을 쓴다.
# 전장 교전과 공격 카드의 명중률이 갈라지지 않도록 여기 한 곳만 고치면 된다.
#
# **라인전 스탯**(`PilotData.lane_stat_mod`)이 붙는 유일한 지점이기도 하다.
# 공격자의 `hit` 과 방어자의 `evasion` 에 **각자 자기 배율**이 곱해지므로,
# 공격적인 라인전(+10%)을 건 파일럿은 때릴 때 더 잘 맞히고 맞을 때 더 잘 피한다.
# `atk` / `max_hp` 는 여기서 손대지 않는다 — 그쪽은 성장이 담당한다.
func roll_hit(attacker: PilotData, defender: PilotData) -> bool:
	var num := float(lane_adjusted(attacker.hit, attacker))
	var den := num + float(lane_adjusted(defender.evasion, defender))
	if den <= 0.0: return false
	return randf() < (num / den)


## 라인전 스탯 배율을 먹인 hit / evasion 값. 최소 1 을 보장해 −100% 같은 값이
## 판정을 0으로 무너뜨리지 않게 한다.
func lane_adjusted(stat_value: int, p: PilotData) -> int:
	if p == null or is_zero_approx(p.lane_stat_mod):
		return stat_value
	return maxi(1, roundi(float(stat_value) * (1.0 + p.lane_stat_mod)))


# 명중 1회가 **파일럿에게** 넣는 전장 피해. `BattleSim.BATTLE_PILOT_DMG_MULT`
# (기본 0.5)를 곱하고 반올림하되 최소 1 은 보장한다 — 배율 때문에 명중이
# 무의미해지는 일은 없어야 한다.
#
# 이 배율은 **파일럿이 받는 피해 전용**이다. 파일럿 → 포탑 / HQ 피해는 원래
# `atk` 그대로이고(공성 속도 = 경기 길이라 건드리지 않는다), 공격 카드와 교전
# 아레나도 각자 자기 계산을 쓴다. 전장 교전만 절반이다.
#
# 원래는 `damage_map` 에 `atk` 를 그대로 더했다. atk 28 짜리 상대와 max_hp 75
# 인 스나이퍼가 붙으면 한 대가 최대 체력의 37% 라, 복귀선(20%) 위에서 곧장
# 0 으로 떨어져 **복귀할 구간 자체가 존재하지 않았다**.
func _pilot_hit_damage(attacker: PilotData) -> int:
	return maxi(1, roundi(float(attacker.atk) * _bs.BATTLE_PILOT_DMG_MULT))


## 판정 단계에서 나온 파일럿 피해 한 건을 `damage_map` 에 쌓고, 같은 자리에서
## 성장치 적립 + 처치 귀속용 마지막 타격자 기록까지 끝낸다. 전장의 모든 파일럿
## 피해가 여기 한 곳을 지나야 한 경로만 점수를 놓치는 일이 없다.
func _credit_pilot_damage(attacker: PilotData, victim: PilotData, dmg: int,
		damage_map: Dictionary) -> void:
	damage_map[victim] = damage_map.get(victim, 0) + dmg
	_last_hitter[victim] = attacker
	_bs.record_pilot_damage(attacker, victim, dmg)


## 포탑 피해 한 건. 파괴 귀속(`SCORE_TURRET_KILL`)은 적용 단계가
## `_last_turret_hitter` 를 보고 준다.
func _credit_turret_damage(attacker: PilotData, td: TurretData, dmg: int,
		turret_dmg: Dictionary) -> void:
	turret_dmg[td] = turret_dmg.get(td, 0) + dmg
	_last_turret_hitter[td] = attacker


## 지금 이 포탑을 때릴 수 있는가. T2 는 같은 레인 T1 이 살아 있는 동안 무적이다.
func _turret_attackable(td: TurretData) -> bool:
	return not (td.tier == 2 and t1_alive_in_lane(td.team, td.lane))


## 포탑 칸에 서 있는 **같은 레인** 수비 파일럿들. 정글러는 포탑을 지키지 않는다.
## 넉백 여부를 가르는 유일한 기준이므로 `_resolve_lane_at_turret` 의 분류와 같은
## 조건(팀 = 포탑 팀, 레인 = 포탑 레인, 위치 = 포탑 칸)을 쓴다.
func _same_lane_defenders_at(td: TurretData) -> Array:
	var out: Array = []
	for raw in _bs.pilots:
		var d := raw as PilotData
		if not d.alive or d.is_guerrilla:
			continue
		if d.team == td.team and d.lane == td.lane and d.grid_pos == td.grid_pos:
			out.append(d)
	return out


func _enemy_turret_at(pos: Vector2i, friendly_team: int) -> TurretData:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.alive and td.team != friendly_team and td.grid_pos == pos:
			return td
	return null


# ─── Movement — one simultaneous pass for free moves AND combat pushes ───────
#
# Free movement and push movement used to be two separate passes with the damage
# application wedged between them, and neither looked at where it was sending a
# pilot. That let two same-lane enemies trade cells inside one turn: a pilot that
# was not engaged walked into an enemy's cell, and that enemy — queued to advance
# from a fight it had just won — pushed out into the cell just vacated. Both
# moves were individually legal, so nothing caught it, and the pair passed
# through each other without ever engaging.
#
# The fix is structural: there is exactly one movement pass, and inside it every
# pilot's intent is visible at once.
#
#  • Every alive pilot gets one intent — `push-adv` / `push-ret` if combat
#    decided one, nothing at all if it is locked in melee, otherwise `free`.
#  • The pass runs in **lockstep rounds**: in each round every still-moving
#    pilot names its next cell against the *same* snapshot, conflicts are
#    resolved, and the survivors commit together. A pilot with `move_range` > 1
#    simply takes part in more rounds; a push takes part in exactly one.
#  • Because every step inside a round is decided before any of them lands, no
#    pilot can ever walk into space another pilot is about to leave.
#
# Two conflicts have to be arbitrated inside a round:
#
#  • **Advance over a stuck enemy** — the winner of a fight advances toward the
#    enemy HQ and the loser retreats toward its own, which is the same
#    direction, so the winner follows the loser into the next cell and the whole
#    fight slides one tile up the lane. That is the lane push, and it is only
#    called off when the loser has nowhere to retreat to: nobody walks past a
#    pilot still standing in the contested cell. See
#    `_veto_advance_over_stuck_enemy`.
#  • **Head-on exchange** — A aiming at B's cell while B aims at A's. Vetoing
#    both would leave them adjacent and deadlocked forever, so the
#    higher-priority mover takes the step and the other holds — they finish in
#    the same cell and fight next turn, which is the outcome the engagement
#    rules want. Priority is push over free (a combat result outranks a stroll),
#    then team 0 over team 1 as a deterministic tie-break.

const MOVE_KIND_FREE    := "free"
const MOVE_KIND_ADVANCE := "push-adv"
const MOVE_KIND_RETREAT := "push-ret"
## Safety cap on lockstep rounds; `move_range` is 1–2 in practice.
const MAX_MOVE_ROUNDS   := 8


## Resolves this turn's movement for every alive pilot in one pass.
## `advance_set` / `retreat_set` / `engaged` come from `_resolve_cell`.
func resolve_movement(advance_set: Dictionary, retreat_set: Dictionary,
		engaged: Dictionary) -> void:
	var movers: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		# 이번 턴에 본진으로 복귀한 파일럿은 HQ 에 서 있기만 한다. 플래그는 여기서
		# 소비되므로 다음 턴에는 평소처럼 자기 레인을 걸어 나간다.
		if p.recall_hold:
			p.recall_hold = false
			_bs.blog.log_block(p, "본진 복귀 — 이번 턴 대기")
			continue
		var kind: String = MOVE_KIND_FREE
		if advance_set.has(p):
			kind = MOVE_KIND_ADVANCE
		elif retreat_set.has(p):
			kind = MOVE_KIND_RETREAT
		elif engaged.has(p):
			continue   # locked in melee with no push result — stays put
		movers.append({
			"pilot":      p,
			"kind":       kind,
			"orig":       p.grid_pos,
			# 실제로 밟은 칸들. 락스텝 라운드마다 커밋된 칸이 하나씩 붙고, 패스가
			# 끝나면 통째로 연출에 넘어간다 — `move_range` 2 짜리 정글러가 중간
			# 칸을 스쳐 지나가지 않고 꺾어서 걷게 하기 위한 것이다.
			"path":       [p.grid_pos] as Array,
			"steps_left": maxi(1, p.move_range) if kind == MOVE_KIND_FREE else 1,
			"active":     true,
			"moved":      false,
		})
	for _round in MAX_MOVE_ROUNDS:
		if not _run_movement_round(movers):
			break
	for raw_m in movers:
		var m: Dictionary = raw_m
		if bool(m["moved"]):
			_bs.anim_pilot_move_path(m["pilot"] as PilotData, m["path"] as Array)


# One lockstep round: collect intents, arbitrate head-on exchanges, commit.
# Returns false once nothing is left to do so the caller can stop early.
func _run_movement_round(movers: Array) -> bool:
	# 1. Every still-active mover names its next cell, all against the same
	#    board state — nothing has moved yet this round.
	var wants: Array = []
	for raw_m in movers:
		var m: Dictionary = raw_m
		if not bool(m["active"]) or int(m["steps_left"]) <= 0:
			continue
		var p := m["pilot"] as PilotData
		var dest: Vector2i = p.grid_pos
		match m["kind"]:
			MOVE_KIND_ADVANCE: dest = _desired_push_advance_cell(p)
			MOVE_KIND_RETREAT: dest = _desired_push_retreat_cell(p)
			_:                 dest = _desired_free_cell(p)
		if dest == p.grid_pos:
			m["active"] = false
			continue
		wants.append({"m": m, "dest": dest, "ok": true})
	if wants.is_empty():
		return false

	_veto_head_on_exchanges(wants)
	# 버티고 선 적을 지나치는 전진만 걸러 낸다. 순서 주의 — 정면 충돌 중재가
	# 누군가의 이동을 취소하면 그 파일럿은 "칸을 비우지 않는" 쪽이 되므로,
	# 반드시 그 뒤에 본다.
	_veto_advance_over_stuck_enemy(wants)

	# 2. Commit the survivors together.
	var committed: Array = []
	for raw_w in wants:
		var w: Dictionary = raw_w
		if not bool(w["ok"]):
			continue
		var m2: Dictionary = w["m"]
		var p2 := m2["pilot"] as PilotData
		committed.append({"p": p2, "prev": p2.grid_pos, "kind": m2["kind"]})
		p2.grid_pos = w["dest"] as Vector2i
		(m2["path"] as Array).append(p2.grid_pos)
		m2["steps_left"] = int(m2["steps_left"]) - 1
		m2["moved"] = true
		if m2["kind"] == MOVE_KIND_RETREAT:
			_rollback_waypoint(p2)
	# Logged only after every commit lands, so "enemies on dest" reflects the
	# settled board rather than a half-applied round.
	for raw_c in committed:
		var c: Dictionary = raw_c
		var cp := c["p"] as PilotData
		_bs.blog.log_move(cp, c["prev"] as Vector2i, cp.grid_pos,
				c["kind"] as String,
				"enemies on dest: %s" % _enemies_on_cell_str(cp))

	# 3. Contact ends a pilot's turn: sharing a cell with a same-scope enemy
	#    means combat, which resolves next turn, so no further steps.
	for raw_m2 in movers:
		var m3: Dictionary = raw_m2
		if not bool(m3["active"]):
			continue
		var p3 := m3["pilot"] as PilotData
		if _has_engaging_enemy_at(p3.grid_pos, p3):
			m3["active"] = false
	return not committed.is_empty()


# 전진은 밀어낸 자리를 **따라 들어간다** — 버티고 선 적을 지나치지만 않는다.
#
# 예전에는 정반대였다. 전진 목적지가 같은 칸에서 나온 적의 후퇴 목적지와
# 겹치면 **전진 쪽을 취소**해, 패자만 쫓겨나고 승자는 그 칸을 지켰다. 그런데
# `_desired_push_advance_cell` 은 적 HQ 쪽, `_desired_push_retreat_cell` 은
# 후퇴자의 자기 HQ 쪽이고 레인은 일직선이라 **두 목적지는 언제나 같은 칸**이다.
# 결과적으로 교전에 이겨도 승자는 한 칸도 나아가지 못했다 — 라인이 밀리지 않고
# 패자만 뒤로 흘러갔다.
#
# 지금 규칙: 같은 칸의 적이 이번 라운드에 그 칸을 **비우면** 승자는 따라 들어가
# 다음 턴에 다시 붙는다. 이게 한 턴에 한 칸씩 밀리는 라인 푸시다. 적이 밀려날
# 곳이 없어 그 자리에 남으면 전진을 취소한다 — 서 있는 적을 옆으로 스쳐
# 지나가는 일은 만들지 않는다. 적 포탑 칸은 **막지 않는다**: 밀려난 패자가 자기
# 포탑 칸으로 들어가면 승자도 그 칸까지 따라 들어가고, 포탑 공성은 다음 턴
# `_resolve_turret_combat` 이 이어받는다.
func _veto_advance_over_stuck_enemy(wants: Array) -> void:
	for raw_wa in wants:
		var wa: Dictionary = raw_wa
		if not bool(wa["ok"]):
			continue
		var ma: Dictionary = wa["m"]
		if ma["kind"] != MOVE_KIND_ADVANCE:
			continue
		var a := ma["pilot"] as PilotData
		var blocker: PilotData = _stuck_enemy_on_cell(a, wants)
		if blocker == null:
			continue
		wa["ok"] = false
		ma["active"] = false
		_bs.blog.log_block(a, "push-advance held — %s 가 %s 에서 밀려나지 못했다"
				% [_bs.pilot_label(blocker), str(a.grid_pos)])


## `a` 와 같은 칸·같은 교전 스코프에 있으면서 이번 라운드에 그 칸을 떠나지
## **않는** 적. 없으면 null.
func _stuck_enemy_on_cell(a: PilotData, wants: Array) -> PilotData:
	for raw in _bs.pilots:
		var o := raw as PilotData
		if not o.alive or o.team == a.team:
			continue
		if o.grid_pos != a.grid_pos or o.is_guerrilla != a.is_guerrilla:
			continue
		if not _is_leaving_cell(o, wants):
			return o
	return null


## `p` 가 이번 라운드에 살아남은 이동 의사를 갖고 있는가. `wants` 에는 제자리
## 목적지가 애초에 들어오지 않으므로, 취소되지 않은 항목이 곧 "칸을 비운다"다.
func _is_leaving_cell(p: PilotData, wants: Array) -> bool:
	for raw_w in wants:
		var w: Dictionary = raw_w
		if not bool(w["ok"]):
			continue
		if ((w["m"] as Dictionary)["pilot"] as PilotData) != p:
			continue
		# 캐스트는 반드시 괄호로 — `x as Vector2i != y` 는 두 번째 피연산자를
		# 캐스트 안으로 끌고 들어가 런타임에 터진다.
		return (w["dest"] as Vector2i) != p.grid_pos
	return false


# Head-on exchange arbitration — see the block comment above `resolve_movement`.
# Mutates `wants` in place: the losing entry's "ok" flag is cleared and its
# mover is deactivated so it holds for the rest of the turn.
func _veto_head_on_exchanges(wants: Array) -> void:
	for i in range(wants.size()):
		var wa: Dictionary = wants[i]
		if not bool(wa["ok"]):
			continue
		var a := (wa["m"] as Dictionary)["pilot"] as PilotData
		for j in range(i + 1, wants.size()):
			var wb: Dictionary = wants[j]
			if not bool(wb["ok"]):
				continue
			var b := (wb["m"] as Dictionary)["pilot"] as PilotData
			if a.team == b.team:
				continue
			# Junglers and lane pilots never engage, so they are allowed to
			# slide past each other — that is not a pass-through bug.
			if a.is_guerrilla != b.is_guerrilla:
				continue
			if wa["dest"] as Vector2i != b.grid_pos:
				continue
			if wb["dest"] as Vector2i != a.grid_pos:
				continue
			var loser_idx: int = j
			if _move_priority(wa) < _move_priority(wb):
				loser_idx = i
			var winner_idx: int = i if loser_idx == j else j
			var wl: Dictionary = wants[loser_idx]
			var ml: Dictionary = wl["m"]
			wl["ok"] = false
			ml["active"] = false
			var lp := ml["pilot"] as PilotData
			var wp := ((wants[winner_idx] as Dictionary)["m"]
					as Dictionary)["pilot"] as PilotData
			_bs.blog.log_block(lp, "head-on exchange with %s — %s takes %s, %s holds"
					% [_bs.pilot_label(wp), _bs.pilot_label(wp),
						str((wants[winner_idx] as Dictionary)["dest"]),
						_bs.pilot_label(lp)])
			if loser_idx == i:
				break   # `a` is out of the running; stop pairing it


# Higher wins a head-on exchange. A combat push (+10) outranks a free move so
# the side that just won a fight keeps its advance; team 0 (+1) breaks the
# remaining tie, matching the old sequential order where team-0 pilots moved
# first.
func _move_priority(w: Dictionary) -> int:
	var m: Dictionary = w["m"]
	var pri: int = 0
	if m["kind"] != MOVE_KIND_FREE:
		pri += 10
	if (m["pilot"] as PilotData).team == 0:
		pri += 1
	return pri


# ─── Desired-destination helpers (pure: never mutate grid_pos) ───────────────
# Each returns the pilot's own cell when it must hold, so callers can treat
# "no move" and "blocked" identically.

func _desired_free_cell(p: PilotData) -> Vector2i:
	# Already sharing a cell with a same-scope enemy → hold and fight next turn.
	# Junglers and lane pilots ignore each other, so a jungler crossing a lane
	# cell does not freeze on a lane enemy.
	if _has_engaging_enemy_at(p.grid_pos, p):
		_bs.blog.log_block(p, "engaging enemy on current cell")
		return p.grid_pos
	return _next_step_for(p)


## 전진은 적 포탑 칸에서 **멈추지 않는다** — 다음 걸음이 같은 레인 적 포탑이면
## 그 칸에 올라선다. 포탑 피해와 넉백은 다음 턴의 `_resolve_turret_combat` 몫.
## (다른 레인의 살아 있는 적 포탑 칸은 `_movement_forbidden_for` 가 BFS 단계에서
## 이미 막으므로 여기까지 후보로 올라오지 않는다.)
func _desired_push_advance_cell(p: PilotData) -> Vector2i:
	var fbd: Dictionary = _movement_forbidden_for(p)
	if p.is_guerrilla:
		var jg_goal := _jungle_goal_for(p)
		if jg_goal == Vector2i(-1, -1):
			return p.grid_pos
		return _bs.pathfinder.bfs_next_step(p.grid_pos, jg_goal, fbd)
	return _bs.pathfinder.bfs_next_step(p.grid_pos, current_waypoint(p), fbd)


func _desired_push_retreat_cell(p: PilotData) -> Vector2i:
	var fbd: Dictionary = _movement_forbidden_for(p)
	if p.is_guerrilla:
		# Retreat toward nearest own-captured jungle cell.
		var dest := Vector2i(-1, -1)
		var best_d := 999999
		for c in _own_captured_jungle_cells(p.team):
			if c == p.grid_pos: continue
			var d: int = _bs.hex_grid.hex_distance(p.grid_pos, c as Vector2i)
			if d < best_d:
				best_d = d; dest = c
		if dest == Vector2i(-1, -1):
			dest = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
		return _bs.pathfinder.bfs_next_step(p.grid_pos, dest, fbd)
	# Lane pilots retreat one step along their lane toward own HQ.
	var home := _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	return _bs.pathfinder.bfs_next_step(p.grid_pos, home, fbd)


# After a retreat step, walk `waypoint_idx` back if the pilot fell behind an
# earlier waypoint on its lane path.
func _rollback_waypoint(p: PilotData) -> void:
	if p.is_guerrilla:
		return
	var path: Array = _bs.LANE_PATHS_TEAM0[p.lane] if p.team == 0 \
			else _bs.LANE_PATHS_TEAM1[p.lane]
	while p.waypoint_idx > 0:
		var wp := path[p.waypoint_idx] as Vector2i
		if _bs.hex_grid.hex_distance(p.grid_pos, wp) > _bs.hex_grid.hex_distance(
				p.grid_pos, path[p.waypoint_idx - 1] as Vector2i):
			p.waypoint_idx -= 1
		else:
			break


# Debug helper: which enemies are standing on `p`'s current cell right now, and
# whether they share `p`'s engagement scope. "-" when the cell is clear.
func _enemies_on_cell_str(p: PilotData) -> String:
	var parts: Array = []
	for raw in _bs.pilots:
		var o := raw as PilotData
		if not o.alive or o.team == p.team or o.grid_pos != p.grid_pos:
			continue
		parts.append("%s%s" % [_bs.pilot_label(o),
				"" if o.is_guerrilla == p.is_guerrilla else "(x-scope)"])
	return "-" if parts.is_empty() else ",".join(parts)


# True only if the cell contains an enemy that would actually engage `p`.
# Junglers and lane pilots ignore each other (matches `_resolve_cell` rules).
func _has_engaging_enemy_at(cell: Vector2i, p: PilotData) -> bool:
	for raw in _bs.pilots:
		var o := raw as PilotData
		if not o.alive: continue
		if o.team == p.team: continue
		if o.grid_pos != cell: continue
		if o.is_guerrilla != p.is_guerrilla: continue
		return true
	return false


# Raw lane/jungle pathfinding step, ignoring occupancy. `_desired_free_cell`
# wraps it with the contact / turret hold rules.
func _next_step_for(p: PilotData) -> Vector2i:
	var goal: Vector2i
	if p.is_guerrilla:
		goal = _jungle_goal_for(p)
		if goal == Vector2i(-1, -1):
			return p.grid_pos
	else:
		# 레인 파일럿의 목표는 **언제나** 다음 웨이포인트 하나뿐이다. 아군 포탑이
		# 맞고 있다고 수비하러 돌아오는 개념은 없다 — 파일럿은 자기 HQ 에서
		# 출발해 레인 길을 따라가고, 그러다 상대 라이너와 마주치는 것이 설계다.
		goal = current_waypoint(p)
	var fbd: Dictionary = _movement_forbidden_for(p)
	return _bs.pathfinder.bfs_next_step(p.grid_pos, goal, fbd)


# Goal selection for jungler: nearest uncaptured neutral, else a **sticky** roam
# target held on the pilot until it is actually reached.
#
# The roam target used to be recomputed every turn as "the own-captured cell
# farthest from where I am standing right now". That is a coin that flips the
# instant the jungler takes a step: moving one cell toward the far side makes
# the side it just left the farthest one, so it turned around and walked back.
# In a logged battle A0 rode (-1,0) ↔ (-1,-1) from turn 31 to the end of the
# match — and those are *mid-lane* cells on the corridor between the two
# jungles, so it read as the jungler loitering in front of its own mid T1 while
# the enemy sieged it. Holding the target makes the jungler finish its tour and
# come to rest only on a jungle cell; lane cells are crossed, never idled on.
#
# **"아직 안 잡힌 중립부터 간다"는 1순위는 삭제됐다.** 좌우 중립 두 칸이
# 오브젝트 자리(상시 중립)가 되면서 그 판정은 영원히 참이 됐다 — 정글러가
# 개시부터 끝까지 전령 / 용 칸 위에 서서 점령되지도 않는 칸을 기다리고, 캠프는
# 한 번도 돌지 않는다. 지금 정글러의 1순위는 **차 있는 캠프**다.
func _jungle_goal_for(p: PilotData) -> Vector2i:
	# **차 있는 캠프가 가장 먼저다.** 정글러의 수입이 전부 캠프에서 나오므로
	# "가장 먼 아군 칸"으로 순회하는 것보다 "지금 먹을 수 있는 캠프"가 곧 목표다.
	# 먹고 나면 그 칸의 캠프가 4턴 동안 비므로 다음 캠프가 자연히 새 목표가 되고,
	# 그 반복이 순회가 된다 — 예전의 sticky 왕복이 필요 없다.
	var camp := _best_ready_camp(p)
	if camp != Vector2i(-1, -1):
		p.jungle_roam_target = Vector2i(-1, -1)
		return camp
	var captured := _own_captured_jungle_cells(p.team)
	if captured.is_empty():
		p.jungle_roam_target = Vector2i(-1, -1)
		return _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	# Keep the standing target unless it was reached, was never set, or stopped
	# belonging to us (a lost T1 can flip a jungle cell to the other team).
	var target: Vector2i = p.jungle_roam_target
	if target != Vector2i(-1, -1) and target != p.grid_pos \
			and int(_bs.neutral_zone_cells.get(target, -2)) == p.team:
		return target
	p.jungle_roam_target = _farthest_captured_cell(p.grid_pos, captured)
	return p.jungle_roam_target


## 지금 먹을 수 있는 캠프 중 `p` 가 가야 할 칸. 없으면 (-1,-1).
##
## **거리만으로 고르면 정글러가 자기 발밑에 갇힌다.** 한쪽 정글이 4칸이고 캠프
## 재생성이 4턴이라 매 턴 정확히 한 칸이 되살아나므로, 최단 거리 그리디는 영원히
## 거리 1짜리 캠프를 찾아내 그 4칸을 뱅뱅 돈다 — 반대쪽 정글은 개시부터 끝까지
## 캠프가 꽉 찬 채로 남는다(실측: 팀0 정글러가 30턴 동안 오른쪽 정글 세 칸을 한
## 번도 밟지 않았다). 화면에는 "먹을 게 남아 있는 칸을 두고 빈 칸만 도는" 것으로
## 보인다.
##
## 그래서 비용은 거리가 아니라 **거리 − 방치 할인**이다:
##     cost = 거리 × JUNGLE_CAMP_STALE_PER_STEP − 차 있는 채로 방치된 턴 수
## 차 있는 채 놀고 있는 캠프는 턴마다 조금씩 싸지므로, 멀어서 계속 밀리던 캠프도
## 언젠가는 가장 싼 목표가 되어 정글러가 좌우를 오가는 **순회**가 된다.
##
## **목표를 향해 한 걸음 옮기면 그 목표의 비용은 반드시 더 내려간다**(거리 −1 =
## −2, 방치 +1 = −1, 합 −3). 다른 캠프는 같은 턴에 −1 밖에 안 싸지므로 가는
## 도중에 목표가 뒤집혀 왕복하는 일이 없다.
##
## 제자리(이미 서 있는 칸)가 차 있으면 **무조건 그 칸이다** — 이동은
## `process_jungle_camps` 보다 앞에 오므로, 발밑의 캠프는 가만히 있기만 하면
## 이번 턴에 먹는다. 방치 할인에 끌려 떠나면 그 한 턴을 통째로 버린다.
func _best_ready_camp(p: PilotData) -> Vector2i:
	if camp_harvestable(p.grid_pos, p.team):
		return p.grid_pos
	var best := Vector2i(-1, -1)
	var best_cost: int = 2147483647
	var best_d: int = 999999
	for raw in _bs.jungle_camps.keys():
		var cell := raw as Vector2i
		if not camp_harvestable(cell, p.team):
			continue
		var d: int = _bs.hex_grid.hex_distance(p.grid_pos, cell)
		var idle: int = maxi(0, _bs.turn_count - int(_bs.jungle_camps.get(cell, 0)))
		var cost: int = d * _bs.JUNGLE_CAMP_STALE_PER_STEP - idle
		# 동률은 가까운 쪽 — 방치 할인은 어디로 갈지를 정하는 항이지 헛걸음을
		# 늘리는 항이 아니다.
		if cost < best_cost or (cost == best_cost and d < best_d):
			best_cost = cost; best_d = d; best = cell
	return best


# Farthest cell of `captured` from `from`, excluding `from` itself. Returns
# `from` when there is nowhere else to go, which makes the caller hold.
func _farthest_captured_cell(from: Vector2i, captured: Array) -> Vector2i:
	var best := from
	var best_d := -1
	for raw in captured:
		var c := raw as Vector2i
		if c == from:
			continue
		var d: int = _bs.hex_grid.hex_distance(from, c)
		if d > best_d:
			best_d = d; best = c
	return best


# ─── Card-driven lane push (전진) ─────────────────────────────────────────────
# 전진 (advance:N) 카드. `steps` 번의 미니틱을 돌리며, 한 틱이 라인을 한 칸
# 밀어 올린다. 규칙은 턴 전투와 같은 헬퍼를 쓰되 판정 하나를 강제한다.
#
#  • **판정 강제** — 전진을 낸 쪽은 그 칸의 교전에서 **이긴 것으로 확정**된다.
#    피해 교환은 평소 그대로(`_resolve_cell` 의 명중 판정)라 맞을 건 맞지만,
#    밀려나는 쪽은 언제나 상대다. 예전에는 일방 명중 우세를 그대로 읽어서,
#    주사위가 나쁘면 전진 카드가 시전자를 자기 HQ 쪽으로 되돌려 보냈다 —
#    전진 카드가 후퇴 카드로 동작했다.
#  • **무리 단위** — 시전자와 **같은 칸·같은 팀·같은 교전 스코프**의 아군이
#    함께 전진하고, 같은 칸의 적은 함께 밀려난다. 예전에는 "카드는 한 명만
#    움직인다"며 시전자만 옮겨서, 진 적이 제자리에 남고 시전자 혼자 그 옆을
#    스쳐 지나갔다(= 밀어내기가 눈에 보이지 않았다).
#  • **포탑** — 다음 걸음이 같은 레인 적 포탑 칸이면 무리는 전장 규칙 그대로
#    **그 칸에 올라선다**. 그 틱에는 포탑 피해가 없다 — 포탑은 칸 위에 서서
#    맞는 다음 틱/턴에 맞는다.
#  • 시전자가 **이미** 적 포탑 칸 위라면(전 틱에 올라섰거나 이동 카드로 올라간
#    경우) 포탑 규칙이 이긴다: 포탑에 무판정 피해를 넣고, 그 칸에 같은 레인
#    **수비자가 서 있으면** 그 명중 판정을 맞은 뒤 한 칸 후퇴한다. 전진 카드가
#    뒤로 가는 경우는 이것뿐이다. 수비자가 없으면 물러나지 않고 눌러앉아 계속
#    갈아 낸다.
func advance_pilot(caster: PilotData, steps: int, log_lines: Array) -> void:
	if caster == null or steps <= 0:
		return
	# 전진은 작전 단계에서 도는 별도 경로다 — 지난 턴의 마지막 타격자가 남아
	# 있으면 여기서 나온 처치가 엉뚱한 사람에게 귀속된다.
	_last_hitter.clear()
	_last_turret_hitter.clear()
	_bs.blog.stage("card-adv")
	_bs.blog.log_event("CARD", "전진 — %s runs %d mini-ticks from %s"
			% [_bs.pilot_label(caster), steps, str(caster.grid_pos)])
	for _i in steps:
		if not caster.alive:
			break
		_advance_tick(caster, log_lines)
	check_win_condition()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


## 전진 미니틱 한 번 — 판정 → 공성 → 피해 → 이동. 블록 주석의 규칙을 그대로
## 옮긴 것이므로 순서를 바꾸지 말 것: 피해는 이동보다 **앞**이라야 이번 틱에
## 쓰러진 파일럿이 움직이지 않고, 공성은 피해 적용보다 앞이라야 포탑 피해와
## 수비자 반격이 같은 묶음으로 들어간다(`simulate_turn` 과 같은 순서).
func _advance_tick(caster: PilotData, log_lines: Array) -> void:
	var cell: Vector2i = caster.grid_pos
	var cell_turret: TurretData = _enemy_turret_at(cell, caster.team)
	# 포탑 규칙은 **같은 레인 레인 파일럿**에게만 걸린다 — 정글러나 카드로 남의
	# 레인 포탑 칸에 떨어진 파일럿은 포탑을 무시하고 평소대로 전진한다.
	var on_enemy_turret: bool = cell_turret != null \
			and not caster.is_guerrilla and cell_turret.lane == caster.lane
	# 포탑 칸 위에서 물러나는 것은 **수비자가 있을 때만**이다. 무방비 포탑 위라면
	# 무리는 그 자리에 눌러앉아 계속 갈아 낸다(전진도 후퇴도 하지 않는다).
	var turret_defended: bool = on_enemy_turret \
			and not _same_lane_defenders_at(cell_turret).is_empty()
	var squad: Array = [caster]
	squad.append_array(_same_scope_allies_at(cell, caster))
	var foes: Array = _same_scope_enemies_at(cell, caster)

	var damage_map: Dictionary = {}
	var turret_dmg: Dictionary = {}
	var advance_set: Dictionary = {}
	var retreat_set: Dictionary = {}
	var engaged: Dictionary = {}
	var by_cell: Dictionary = _group_pilots_by_cell()
	var bucket: Dictionary = by_cell.get(cell, {"t0": [], "t1": []})
	var t0: Array = (bucket.get("t0", []) as Array).duplicate()
	var t1: Array = (bucket.get("t1", []) as Array).duplicate()
	_resolve_cell(cell, t0, t1,
			damage_map, turret_dmg, advance_set, retreat_set, engaged, log_lines)

	# 판정 강제 — 주사위가 어떻게 나왔든 무리가 이 칸을 가져간다. 이미 적 포탑
	# 칸 위에 서 있을 때만 포탑 규칙이 우선한다: 수비자가 있으면 때리고 한 칸
	# 후퇴, 없으면 때리며 제자리.
	for raw_m in squad:
		var m := raw_m as PilotData
		advance_set.erase(m)
		retreat_set.erase(m)
		if turret_defended:
			retreat_set[m] = true
		elif not on_enemy_turret:
			advance_set[m] = true
	if not on_enemy_turret:
		for raw_f in foes:
			var f := raw_f as PilotData
			advance_set.erase(f)
			retreat_set[f] = true
	var verdict := "전진 확정"
	if turret_defended:      verdict = "포탑 칸 수비자 → 후퇴"
	elif on_enemy_turret:    verdict = "무방비 포탑 칸 → 제자리"
	_bs.blog.log_event("CARD", "전진 판정 — %s %s / 밀려남 %s" % [
			_labels(squad), verdict, _labels(foes)])

	_apply_card_damage(damage_map, turret_dmg, log_lines)
	if not caster.alive:
		return

	# 밀려나는 적 먼저 — 무리가 들어갈 칸을 비운다. `retreat_set` 을 거치는 것이
	# 중요하다: 시전자가 적 포탑 칸 위에 서서 튕겨 나가는 틱에는 그 칸의
	# 수비자를 밀어낼 자격이 없다(무리가 물러나는 쪽이다).
	for raw_f2 in foes:
		var f2 := raw_f2 as PilotData
		if not f2.alive or not retreat_set.has(f2):
			continue
		_step_pilot(f2, _desired_push_retreat_cell(f2), MOVE_KIND_RETREAT)
	# 밀려날 곳이 없어 적이 칸에 남았다면 무리도 전진하지 않는다 — 적을 두고
	# 옆으로 스쳐 지나가는 일은 만들지 않는다.
	var still_contested: bool = false
	for raw_f3 in foes:
		var f3 := raw_f3 as PilotData
		if f3.alive and f3.grid_pos == cell:
			still_contested = true
			break
	for raw_m2 in squad:
		var m2 := raw_m2 as PilotData
		if not m2.alive:
			continue
		if retreat_set.has(m2):
			_step_pilot(m2, _desired_push_retreat_cell(m2), MOVE_KIND_RETREAT)
		elif not advance_set.has(m2):
			# 무방비 적 포탑 칸 위 — 때리며 눌러앉는다.
			_bs.blog.log_block(m2, "전진 — 적 포탑 칸을 점거 중이라 제자리")
		elif still_contested:
			_bs.blog.log_block(m2, "전진 — 밀려나지 못한 적이 칸에 남아 제자리")
		else:
			_step_pilot(m2, _desired_push_advance_cell(m2), MOVE_KIND_ADVANCE)


## 카드 한 틱의 피해 적용 — 파일럿(보호막 먼저) → 포탑(T1 파괴 시 정글 획득).
## `simulate_turn` 의 4단계와 같은 규칙을 카드용으로 뽑아 둔 것이다.
func _apply_card_damage(damage_map: Dictionary, turret_dmg: Dictionary,
		log_lines: Array) -> void:
	for k in damage_map.keys():
		var dp := k as PilotData
		var dmg: int = damage_map[k]
		if dmg > 0 and dp.shield > 0:
			var absorbed: int = min(dp.shield, dmg)
			dp.shield -= absorbed
			dmg -= absorbed
		dp.hp -= dmg
		_bs.blog.log_event("DMG", "%-4s -%d hp→%d @%s" % [
				_bs.pilot_label(dp), int(damage_map[k]), maxi(dp.hp, 0),
				str(dp.grid_pos)])
		if dp.hp <= 0:
			_bs.mark_pilot_dead(dp, _last_hitter.get(dp, null) as PilotData)
			log_lines.append("%s died" % _bs.pilot_label(dp))
			_bs.blog.log_event("DEATH", "%-4s died @%s"
					% [_bs.pilot_label(dp), str(dp.grid_pos)])
		elif damage_map[k] > 0:
			_bs.anim_pilot_shake(dp)
	for k in turret_dmg.keys():
		var td := k as TurretData
		var was_alive := td.alive
		td.hp -= turret_dmg[k]
		_bs.blog.log_event("TURRET", "T%d[%s] team%d -%d hp→%d @%s" % [
				td.tier, _bs.LANE_NAMES[td.lane], td.team, int(turret_dmg[k]),
				maxi(td.hp, 0), str(td.grid_pos)])
		if td.hp > 0 and int(turret_dmg[k]) > 0:
			_bs.anim_turret_hit(td)
		if td.hp <= 0:
			td.hp = 0; td.alive = false
			log_lines.append("T%d %s turret destroyed!" % [td.tier, _bs.LANE_NAMES[td.lane]])
			if was_alive:
				_bs.score_turret_kill(_last_turret_hitter.get(td, null) as PilotData, td)
				var b: Building = _bs.building_registry.get_at(td.grid_pos)
				if b != null:
					_bs.building_registry.unregister(b)
					b.queue_free()
			if was_alive and td.tier == 1:
				_on_t1_destroyed(td, log_lines)


## 카드 이동 한 걸음. 목적지가 제자리면 아무것도 하지 않는다(호출자는 "막힘"과
## "안 움직임"을 구분할 필요가 없다).
func _step_pilot(p: PilotData, dest: Vector2i, kind: String) -> void:
	if dest == p.grid_pos:
		return
	var orig := p.grid_pos
	p.grid_pos = dest
	if kind == MOVE_KIND_RETREAT:
		_rollback_waypoint(p)
	_bs.blog.log_move(p, orig, p.grid_pos, kind,
			"enemies on dest: %s" % _enemies_on_cell_str(p))
	_bs.anim_pilot_move(p, orig)


## `cell` 위에서 `p` 와 같은 교전 스코프(레인끼리 / 정글러끼리)인 아군.
## `p` 자신은 빠진다.
func _same_scope_allies_at(cell: Vector2i, p: PilotData) -> Array:
	var out: Array = []
	for raw in _bs.pilots:
		var o := raw as PilotData
		if o == p or not o.alive:
			continue
		if o.team != p.team or o.grid_pos != cell:
			continue
		if o.is_guerrilla != p.is_guerrilla:
			continue
		out.append(o)
	return out


## `cell` 위에서 `p` 와 실제로 교전하는 적(같은 스코프). 정글러와 레인 파일럿은
## 서로를 무시하므로 여기서도 섞이지 않는다.
func _same_scope_enemies_at(cell: Vector2i, p: PilotData) -> Array:
	var out: Array = []
	for raw in _bs.pilots:
		var o := raw as PilotData
		if not o.alive or o.team == p.team:
			continue
		if o.grid_pos != cell:
			continue
		if o.is_guerrilla != p.is_guerrilla:
			continue
		out.append(o)
	return out


# ─── Targeting / waypoint helpers (used by movement) ─────────────────────────

func current_waypoint(pilot: PilotData) -> Vector2i:
	var path: Array = _bs.LANE_PATHS_TEAM0[pilot.lane] if pilot.team == 0 \
			else _bs.LANE_PATHS_TEAM1[pilot.lane]
	while pilot.waypoint_idx < path.size() - 1:
		var wp: Vector2i = path[pilot.waypoint_idx] as Vector2i
		if pilot.grid_pos == wp:
			pilot.waypoint_idx += 1
		else:
			break
	return path[min(pilot.waypoint_idx, path.size() - 1)] as Vector2i


func t1_alive_in_lane(team: int, lane: int) -> bool:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.team == team and td.lane == lane and td.tier == 1 and td.alive:
			return true
	return false


## **레인별로 살아 있는 가장 바깥 적 포탑** 목록. [전령 제압] 카드의 유효 대상이
## 이것 하나다 — 안쪽 포탑(같은 레인 T1 이 아직 서 있는 T2)은 저격할 수 없다.
##
## 레인마다 T1 → T2 순으로 훑어 **처음 만난 살아 있는 포탑**을 담는다. 그래서
## T1 이 무너진 레인은 T2 가 그 자리를 물려받아 대상이 되고, 후반에 먹은 전령
## 보상도 쓸 곳이 남는다. 세 레인이 전부 정리된 팀에는 대상이 없다(빈 배열).
##
## `_turret_attackable` 과 같은 규칙을 다른 각도에서 읽는다: 저쪽은 "이 포탑을
## 지금 때릴 수 있나"이고 이쪽은 "때릴 수 있는 포탑이 어느 것들인가"다.
func outermost_enemy_turrets(attacker_team: int) -> Array:
	var out: Array = []
	var foe: int = 1 - attacker_team
	for lane_idx in range(3):
		for tier in [1, 2]:
			var found: TurretData = null
			for raw in _bs.turrets:
				var td := raw as TurretData
				if td.alive and td.team == foe and td.lane == lane_idx and td.tier == tier:
					found = td
					break
			if found != null:
				out.append(found)
				break
	return out


## `cell` 위에 서 있는 **살아 있는 포탑**. 없으면 null. [전령 제압] 이 LOCATION
## 모드로 찍은 칸을 포탑으로 되돌릴 때 쓴다.
func turret_at_cell(cell: Vector2i) -> TurretData:
	for raw in _bs.turrets:
		var td := raw as TurretData
		if td.alive and td.grid_pos == cell:
			return td
	return null


## 카드가 포탑 한 기에 넣는 즉발 피해. 명중 판정은 없다.
##
## 턴 전투의 피해 적용 경로(`_apply_card_damage`)를 그대로 재사용한다 — 흔들림
## 연출 · 킬로그 · `Building` 노드 해제 · T1 파괴 시 정글 획득까지 한 군데서만
## 일어나야 하기 때문이다. `attacker` 는 성장치 귀속용이고 **null 이어도 된다**
## (오브젝트 보상 카드는 시전자가 없다 — `add_score` 가 null 을 걸러 낸다).
func apply_card_turret_damage(td: TurretData, dmg: int,
		attacker: PilotData, log_lines: Array) -> void:
	if td == null or not td.alive or dmg <= 0:
		return
	_last_turret_hitter.clear()
	if attacker != null:
		_last_turret_hitter[td] = attacker
	_apply_card_damage({}, {td: dmg}, log_lines)


func any_t2_destroyed(defending_team: int) -> bool:
	for t in _bs.turrets:
		var td := t as TurretData
		if td.team == defending_team and td.tier == 2 and not td.alive:
			return true
	return false


func has_enemy_turret_at(pos: Vector2i, pilot_team: int) -> bool:
	return _enemy_turret_at(pos, pilot_team) != null


# ─── Respawn ─────────────────────────────────────────────────────────────────

# 전장 밖에 있는 파일럿을 매 턴 한 번씩 훑는다. **사망만이 파일럿을 전장에서
# 치우므로** 여기는 `respawn_timer` 카운트다운 하나뿐이다 — 복귀(본진 귀환)는
# 전장에 선 채로 처리된다(`RecallSystem.return_to_hq`).
func process_respawns() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if p.alive:
			continue
		p.respawn_timer -= 1
		if p.respawn_timer <= 0:
			_return_to_field(p)


func _return_to_field(p: PilotData) -> void:
	var orig := p.grid_pos
	p.grid_pos      = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	p.hp            = p.max_hp
	p.shield        = 0   # 본진 복귀 = 보호막 제거
	p.alive         = true
	p.respawn_timer = 0
	p.waypoint_idx  = 0
	p.recall_hold   = false   # 부활은 나오는 턴에 바로 걸어 나간다
	_bs.blog.log_move(p, orig, p.grid_pos, "respawn")
	_bs.anim_pilot_respawn(p)


# ─── Neutral zones / jungle ──────────────────────────────────────────────────

# Builds neutral_zone_cells with the user-defined initial state:
#  - Both teams' jungles already captured for their team.
#  - Two side neutral cells uncaptured.
func init_neutral_zones() -> void:
	_bs.neutral_zone_cells.clear()
	for c in JUNGLE_TEAM0_LEFT:  _set_zone_cell(c as Vector2i, 0)
	for c in JUNGLE_TEAM0_RIGHT: _set_zone_cell(c as Vector2i, 0)
	for c in JUNGLE_TEAM1_LEFT:  _set_zone_cell(c as Vector2i, 1)
	for c in JUNGLE_TEAM1_RIGHT: _set_zone_cell(c as Vector2i, 1)
	_set_zone_cell(NEUTRAL_LEFT,  -1)
	_set_zone_cell(NEUTRAL_RIGHT, -1)


func _set_zone_cell(cell: Vector2i, owner_id: int) -> void:
	_bs.neutral_zone_cells[cell] = owner_id
	# atlas (3,0) = neutral-gray, (1,0) = team-0 colour, (2,0) = team-1 colour
	var atlas: Vector2i
	if owner_id == 0:    atlas = Vector2i(1, 0)
	elif owner_id == 1:  atlas = Vector2i(2, 0)
	else:                atlas = Vector2i(3, 0)
	_bs.tiles_layer.set_cell(cell, 0, atlas, 0)


# Public wrapper for outside callers (e.g. CardPhaseManager._effect_capture_jungle).
func set_zone_cell(cell: Vector2i, owner_id: int) -> void:
	_set_zone_cell(cell, owner_id)


# Restore expired 약탈 captures. Called from simulate_turn after the
# capture-by-jungler step so naturally-captured cells aren't immediately
# overwritten by an expiring temp.
func process_temp_zone_expiries() -> void:
	if _bs.temp_zone_overrides.is_empty():
		return
	var keep: Array = []
	for raw in _bs.temp_zone_overrides:
		var entry: Dictionary = raw as Dictionary
		if _bs.turn_count >= int(entry["expires_turn"]):
			_set_zone_cell(entry["cell"] as Vector2i, int(entry["prev_owner"]))
		else:
			keep.append(entry)
	_bs.temp_zone_overrides = keep


func process_neutral_zone_captures() -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive or not p.is_guerrilla:
			continue
		# 오브젝트 칸은 상시 중립이다 — 밟아도 점령되지 않는다. 이 가드가
		# 없으면 개시 직후 정글러가 걸어 들어가 전령 / 용 자리를 자기 색으로
		# 칠해 버리고, 그 칸은 다시는 중립으로 돌아오지 않는다.
		if is_objective_cell(p.grid_pos):
			continue
		# Only capture neutral cells (uncaptured) — jungle owned by an enemy
		# team can be retaken only via T1 destruction, not by stepping on it.
		var zone_owner: int = _bs.neutral_zone_cells.get(p.grid_pos, -2)
		if zone_owner != -1:
			continue
		# Block capture if any enemy is on the same cell.
		var enemy_present := false
		for other_raw in _bs.pilots:
			var o := other_raw as PilotData
			if o.alive and o.team != p.team and o.grid_pos == p.grid_pos:
				enemy_present = true; break
		if enemy_present: continue
		_set_zone_cell(p.grid_pos, p.team)
		_bs.blog.log_event("ZONE", "%-4s captured neutral %s"
				% [_bs.pilot_label(p), str(p.grid_pos)])


# Used by RecallSystem to decide if a card-displaced jungler is in enemy territory.
func _own_captured_jungle_cells(team: int) -> Array:
	var result: Array = []
	for k in _bs.neutral_zone_cells.keys():
		if int(_bs.neutral_zone_cells[k]) == team:
			result.append(k)
	return result


# Pathfinding "forbidden" set per pilot:
#  - Junglers move freely (no forbidden cells).
#  - Lane pilots are blocked from entering jungle/neutral cells AND alive enemy
#    turret cells in lanes other than their own. The same-lane enemy turret cell
#    is intentionally NOT forbidden — a lane pilot **steps onto it** and besieges
#    from there (`_resolve_turret_combat`), held in place by `engaged` until the
#    turret falls or a defender pushes it back out. Off-lane enemy turrets
#    used to stop lane pilots dead (e.g. right-lane pilots routing toward enemy
#    HQ would freeze on the still-alive center T2 cell), so we route around them.
# A fresh dictionary is built — never mutate `_bs.neutral_zone_cells`.
func _movement_forbidden_for(p: PilotData) -> Dictionary:
	if p.is_guerrilla:
		return {}
	var fbd: Dictionary = _bs.neutral_zone_cells.duplicate()
	for t in _bs.turrets:
		var td := t as TurretData
		if not td.alive: continue
		if td.team == p.team: continue
		if td.lane == p.lane: continue
		fbd[td.grid_pos] = true
	return fbd


# ─── Lane corridors ──────────────────────────────────────────────────────────
# lane → {cell: true}. 한 레인의 웨이포인트를 BFS 로 이어 붙인 통로 셀 집합.
# 소비자는 둘이다 — 카드 이동이 파일럿을 **다른 레인**에 떨어뜨렸는지 판정하는
# `RecallSystem._is_out_of_position`, 그리고 **전선** 계산(`front_line_cells`).
# 팀1 의 경로는 팀0 경로의 역순이라 통로 셀 집합은 양 팀이 같으므로 레인당
# 하나만 만든다. `_lane_corridor_orders` 는 같은 통로에 팀0 HQ 쪽부터 순번을
# 매긴 표로, 전선이 "두 포탑 **사이**"를 물어야 해서 앞뒤 관계가 필요하다.
var _lane_corridors: Array = []
var _lane_corridor_orders: Array = []


## 통로가 만들어진 레인 수. `LANE_NAMES` 는 GUERRILLA 슬롯까지 세므로 레인을
## 훑는 쪽은 반드시 이 값을 쓴다.
func lane_corridor_count() -> int:
	if _lane_corridors.is_empty():
		_build_lane_corridors()
	return _lane_corridors.size()


## `lane` 번 레인의 통로 셀 집합. 최초 호출 때 한 번만 만들어 캐시한다.
func lane_corridor(lane: int) -> Dictionary:
	if _lane_corridors.is_empty():
		_build_lane_corridors()
	if lane < 0 or lane >= _lane_corridors.size():
		return {}
	return _lane_corridors[lane] as Dictionary


## `lane` 번 레인의 통로를 **팀0 HQ 쪽부터 순서대로** 번호 매긴 표.
## `Vector2i cell → int index`. 전선 계산이 "이 칸이 두 포탑 사이인가"를 묻는데,
## 집합만으로는 앞뒤를 알 수 없어서 통로를 만드는 그 자리에서 순번도 적어 둔다.
func lane_corridor_order(lane: int) -> Dictionary:
	if _lane_corridors.is_empty():
		_build_lane_corridors()
	if lane < 0 or lane >= _lane_corridor_orders.size():
		return {}
	return _lane_corridor_orders[lane] as Dictionary


func _build_lane_corridors() -> void:
	# 재진입 방지 — 아래 루프가 `lane_corridor*` 를 다시 부르지는 않지만, 빈
	# 배열이 "아직 안 만들었다" 의 신호라서 자리부터 채워 둔다.
	_lane_corridors = []
	_lane_corridor_orders = []
	# 레인 파일럿은 정글에 못 들어가므로 통로도 정글을 우회해야 한다.
	var jungle_fbd: Dictionary = _bs.neutral_zone_cells.duplicate()
	for lane in _bs.LANE_PATHS_TEAM0.size():
		var cells: Dictionary = {}
		var order: Dictionary = {}
		var path: Array = _bs.LANE_PATHS_TEAM0[lane] as Array
		if path.is_empty():
			_lane_corridors.append(cells)
			_lane_corridor_orders.append(order)
			continue
		var cur: Vector2i = path[0] as Vector2i
		cells[cur] = true
		order[cur] = 0
		for i in range(1, path.size()):
			var wp: Vector2i = path[i] as Vector2i
			var guard: int = 0
			while cur != wp and guard < 64:
				var nxt: Vector2i = _bs.pathfinder.bfs_next_step(cur, wp, jungle_fbd)
				if nxt == cur:
					break
				cur = nxt
				cells[cur] = true
				# 순번은 **처음 밟았을 때만** 적는다 — 웨이포인트 사이를 되짚는
				# 구간이 있어도 앞뒤 관계가 뒤집히지 않는다.
				if not order.has(cur):
					order[cur] = order.size()
				guard += 1
		_lane_corridors.append(cells)
		_lane_corridor_orders.append(order)


# ─── T1 destruction → jungle capture ─────────────────────────────────────────

func _on_t1_destroyed(td: TurretData, log_lines: Array) -> void:
	# `td.team` = the destroyed turret's owner (the loser). `capturer` = the team
	# that took it down. Three branches in priority order:
	#   1. Restoration: if any of the capturer's own same-lane vuln cells are
	#      currently owned by the loser, restore those cells to the capturer
	#      INSTEAD of capturing the loser's vuln. (Applies to all lanes.)
	#   2. Default capture: the loser's same-lane vuln cell(s) flip to the
	#      capturer. Side lanes flip 1 cell, mid flips both flanking cells.
	#
	# **측면 중립 탈취 분기는 삭제됐다.** 예전에는 사이드 레인 T1 을 깨면 같은
	# 쪽 중립 칸이 패자 소유일 때 그 칸을 대신 가져갔는데, 좌우 중립은 이제
	# 상시 중립(오브젝트 자리)이라 누구의 소유도 되지 않는다 — 그 조건은
	# 영원히 거짓이므로 분기 자체가 죽은 코드였다.
	var capturer := 1 - td.team
	var own_vulns: Array  = _vuln_cells_for(capturer, td.lane)
	var loser_vulns: Array = _vuln_cells_for(td.team, td.lane)

	var to_restore: Array = []
	for c in own_vulns:
		if int(_bs.neutral_zone_cells.get(c as Vector2i, -2)) == td.team:
			to_restore.append(c)
	if not to_restore.is_empty():
		for c in to_restore:
			_set_zone_cell(c as Vector2i, capturer)
		log_lines.append("%s vuln restored by team %d" % [_bs.LANE_NAMES[td.lane], capturer])
		return

	for c in loser_vulns:
		_set_zone_cell(c as Vector2i, capturer)
	log_lines.append("%s vuln captured by team %d" % [_bs.LANE_NAMES[td.lane], capturer])


func _vuln_cells_for(team: int, lane: int) -> Array:
	if team == 0:
		match lane:
			GameEnums.Lane.LEFT:   return VULN_TEAM0_LEFT
			GameEnums.Lane.CENTER: return VULN_TEAM0_CENTER
			GameEnums.Lane.RIGHT:  return VULN_TEAM0_RIGHT
	else:
		match lane:
			GameEnums.Lane.LEFT:   return VULN_TEAM1_LEFT
			GameEnums.Lane.CENTER: return VULN_TEAM1_CENTER
			GameEnums.Lane.RIGHT:  return VULN_TEAM1_RIGHT
	return []


# ─── Spawning ────────────────────────────────────────────────────────────────

func spawn_pilots_with_lanes() -> void:
	_bs.pilots.clear()
	var roles: Array[int] = [
		GameEnums.Role.TANK, GameEnums.Role.FIGHTER, GameEnums.Role.ASSASSIN,
		GameEnums.Role.SUPPORT, GameEnums.Role.SNIPER,
	]
	var ctx: Dictionary = _bs.gm.match_ctx
	var ctx_active: bool   = bool(ctx.get("active", false))
	var p_roster: Array    = ctx.get("player_roster", [])
	var e_roster: Array    = ctx.get("enemy_roster", [])
	var jungle_dir: int    = int(ctx.get("jungle_start_dir", GameEnums.JungleStartDir.LEFT))

	for i in range(5):
		var lid: int = _bs.gambit_lanes[i]
		var stats: Dictionary = _stats_for(ctx_active, p_roster, i, roles[i])
		var pilot := PilotData.new(roles[i], 0, _bs.PLAYER_HQ_POS, stats)
		pilot.pilot_id     = _pilot_id_from_roster(ctx_active, p_roster, i, i)
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.LanePosition.GUERRILLA)
		pilot.waypoint_idx = 0
		if pilot.is_guerrilla:
			pilot.jungle_start_pref = jungle_dir
		_bs.pilots.append(pilot)

	var e_lanes: Array = GambitPhaseManager.ROLE_TO_LANE
	for i in range(5):
		var lid: int = e_lanes[i]
		var stats: Dictionary = _stats_for(ctx_active, e_roster, i, roles[i])
		var pilot := PilotData.new(roles[i], 1, _bs.ENEMY_HQ_POS, stats)
		pilot.pilot_id     = _pilot_id_from_roster(ctx_active, e_roster, i, 5 + i)
		pilot.lane         = lid
		pilot.is_guerrilla = (lid == GameEnums.LanePosition.GUERRILLA)
		pilot.waypoint_idx = 0
		if pilot.is_guerrilla:
			pilot.jungle_start_pref = randi() % 2
		_bs.pilots.append(pilot)


# Returns the id used for portrait lookup. When the roster carries a regular
# PlayerData (id 0..39) we use it directly. Otherwise (standalone runs with
# no roster, or INTL pilots whose ids are 100+ and have no image assets),
# we fall back to a deterministic per-slot id so PilotImages can still
# resolve a sprite — keeping pilot art visible across every entry path.
func _pilot_id_from_roster(ctx_active: bool, roster: Array, idx: int,
		fallback_id: int) -> int:
	if ctx_active and idx < roster.size():
		var pd := roster[idx] as PlayerData
		if pd != null and pd.id >= 0 and pd.id < PilotImages.POOL_SIZE:
			return pd.id
	return fallback_id


# Returns a stats dict {hp, atk, hit, evasion, presence}.
# hp/atk/presence come from the assigned mech (or ROLE_STATS fallback).
# hit/evasion come from PlayerData (mechanics → hit, gamesense → evasion).
# presence drives 전투 개시(engage) target weighting and is not read by the
# battlefield. Fallback presence: melee roles (TANK/FIGHTER/ASSASSIN) → 4,
# ranged (SUPPORT/SNIPER) → 2, matching the mech CSV convention.
# (예전의 `speed` 는 삭제됐다 — 교전이 라운드 기반 턴제가 되면서 행동 빈도
#  개념이 사라졌다.)
func _stats_for(ctx_active: bool, roster: Array, idx: int, role_id: int) -> Dictionary:
	if ctx_active and idx < roster.size():
		var pd := roster[idx] as PlayerData
		var m: MechData = pd.assigned_mech
		if m != null:
			return {
				"hp": m.hp, "atk": m.atk,
				"hit": pd.mechanics, "evasion": pd.gamesense,
				"presence": m.presence,
			}
	var base: Dictionary = _bs.ROLE_STATS[role_id]
	var melee: bool = role_id <= GameEnums.Role.ASSASSIN
	return {
		"hp": base["hp"], "atk": base["atk"],
		"hit": 50, "evasion": 50,
		"presence": 4 if melee else 2,
	}


func spawn_turrets() -> void:
	_bs.turrets.clear()
	var tp: Dictionary = _bs.TURRET_POSITIONS
	for lane_idx in range(3):
		for team in range(2):
			for tier in [1, 2]:
				var pos: Vector2i
				if not tp.is_empty() and tp.has(lane_idx) and \
						tp[lane_idx].has(team) and tp[lane_idx][team].has(tier):
					pos = tp[lane_idx][team][tier] as Vector2i
				else:
					var cols := [1, 4, 7]
					var _rows_t1: Array = [6, 4]
					var row_t1: int = _rows_t1[team]
					var _rows_t2: Array = [8, 2]
					var row_t2: int = _rows_t2[team]
					pos = Vector2i(cols[lane_idx], row_t1 if tier == 1 else row_t2)
				_bs.turrets.append(TurretData.new(team, pos, tier, lane_idx, _bs.TURRET_HP, _bs.TURRET_ATK))


# ─── Win Condition ────────────────────────────────────────────────────────────

func check_win_condition() -> void:
	if _bs.enemy_hq_hp <= 0:
		_bs.game_over = true
		_bs.lbl_victory.text       = "Player Team Wins!"
		_bs.panel_victory.visible = true
		_record_season_winner(0)
	elif _bs.player_hq_hp <= 0:
		_bs.game_over = true
		_bs.lbl_victory.text       = "Opponent Team Wins!"
		_bs.panel_victory.visible = true
		_record_season_winner(1)


# When BattleSim was launched from a Season campaign, write the winning side
# back into season_state.pending_match so SeasonHub can pick it up after the
# scene change. Standalone runs (no pending_match) are a no-op.
func _record_season_winner(winner_side: int) -> void:
	var pm = _bs.gm.season_state.get("pending_match", null)
	if pm == null:
		return
	pm["winner_side"] = winner_side
