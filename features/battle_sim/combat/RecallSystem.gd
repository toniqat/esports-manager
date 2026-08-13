class_name RecallSystem
extends Node

# **복귀 = 본진 귀환**. 두 가지 사유가 같은 한 경로로 들어온다.
#
#  • **저HP 복귀** (`RECALL_HP_THRESHOLD` 이하) — 파일럿이 자기 HQ 로 돌아간다.
#  • **위치 이탈 복귀** — 카드 이동이 파일럿을 **정글** 이나 **다른 레인의 통로**
#    에 떨어뜨린 경우.
#
# **복귀는 전장을 비우지 않는다.** 그 턴에 곧장 자기 HQ 에 **만피로** 서고,
# `alive` 는 계속 true 다 — 파일럿이 전장에서 사라지는 사유는 **사망뿐**이다.
# 대신 복귀한 턴에는 움직이지 않는다(`PilotData.recall_hold`): **다음 턴부터**
# 웨이포인트 0 부터 자기 레인을 다시 걸어 나간다. 복귀 비용은 회복 대기가
# 아니라 **HQ 에서 전선까지 다시 걸어가는 시간**이다.
#
# 예전에는 복귀가 `alive = false` + `is_recalling` 로 전장을 비우고 턴마다
# `RECALL_HEAL_RATIO` 만큼 회복해 만피가 된 다음 턴에 돌아왔다. 그 경로는
# 통째로 사라졌으니 `respawn_timer` / `BattleSim.turns_until_return` 은 이제
# **사망 전용**이다.

@onready var _bs: BattleSim = get_parent() as BattleSim


# Called by SimulationCore each BATTLE turn.
func process_recalls(log_lines: Array) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if float(p.hp) / float(p.max_hp) <= _bs.RECALL_HP_THRESHOLD:
			return_to_hq(p, log_lines, "저HP")


# Called by CardPhaseManager.end_card_phase() before returning to BATTLE, and at
# the end of the AI's turn. Recalls any pilot under the HP threshold, OR any
# pilot whose card-effect placement put them off their own lane.
func process_phase_end_recalls(log_lines: Array) -> void:
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if float(p.hp) / float(p.max_hp) <= _bs.RECALL_HP_THRESHOLD:
			return_to_hq(p, log_lines, "저HP")
			continue
		if _is_out_of_position(p):
			return_to_hq(p, log_lines, "위치 이탈")


# A pilot is "out of position" only when card effects clearly displaced them:
#  - jungler is sitting on an enemy-owned jungle cell, OR
#  - lane pilot is sitting on any jungle cell (own or enemy), OR
#  - lane pilot is standing on **another lane's** corridor.
#
# The lane check is deliberately one-sided: a cell that belongs to no corridor at
# all does *not* count. Corridors are rebuilt with BFS, and a BFS tie-break that
# differs by one cell from the route a pilot actually walked must never exile a
# correctly-positioned pilot. A cell on a *different* lane can't be reached that
# way, so requiring positive membership in another lane keeps the rule safe.
# Junglers legitimately cross lane cells between their jungle clusters, so they
# are exempt from the lane check entirely.
func _is_out_of_position(p: PilotData) -> bool:
	var zone_owner: int = _bs.neutral_zone_cells.get(p.grid_pos, -2)
	if zone_owner != -2:
		if p.is_guerrilla:
			return zone_owner == 1 - p.team
		return true   # 레인 파일럿이 정글/중립 칸에 떨어졌다
	if p.is_guerrilla:
		return false
	if _bs.sim_core.lane_corridor(p.lane).has(p.grid_pos):
		return false
	for lane in _bs.sim_core.lane_corridor_count():
		if lane == p.lane:
			continue
		if _bs.sim_core.lane_corridor(lane).has(p.grid_pos):
			return true
	return false


## 본진 귀환. 그 자리에서 자기 HQ 로 순간이동하고 **체력을 전부 회복한다**.
## 전장을 비우지 않으므로 `alive` 는 손대지 않는다 — 대신 `recall_hold` 를 켜서
## 이번 턴 이동만 건너뛰고, 다음 턴부터 웨이포인트 0 부터 다시 걸어 나간다.
func return_to_hq(p: PilotData, log_lines: Array, reason: String) -> void:
	var orig_pos := p.grid_pos
	var hp_before := p.hp
	p.grid_pos     = _bs.PLAYER_HQ_POS if p.team == 0 else _bs.ENEMY_HQ_POS
	p.hp           = p.max_hp
	p.shield       = 0   # 보호막 is consumed on 본진 복귀
	p.waypoint_idx = 0
	p.recall_hold  = true
	_bs.blog.log_move(p, orig_pos, p.grid_pos, "recall",
			"%s — 본진 복귀, hp %d→%d/%d, 다음 턴부터 레인 복귀"
					% [reason, hp_before, p.hp, p.max_hp])
	_bs.anim_pilot_recall(p, orig_pos)
	log_lines.append("%s 귀환 (체력 회복, 다음 턴 레인 복귀)" % _bs.pilot_label(p))
