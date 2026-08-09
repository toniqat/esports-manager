class_name EngagePhaseManager
extends Node

# 전투 개시(engage) 모듈 — engage:N 카드 효과로 발동되는 N 라운드 턴제 전투를
# 해상도(resolution)와 시각화(EngageOverlay) 양쪽 모두 담당한다.
#
# 흐름:
#   1) CardPhaseManager._apply_single_effect 가 engage clause를 만나면
#      EngagePhaseManager.start_engage(caster, rounds, exclude_lane) 를 호출.
#   2) 시전자 셀 + 인접 1칸(반경 1 육각)의 모든 파일럿이 참여.
#      exclude_lane 플래그가 있으면 lane row에서 정상적으로 자기 lane을
#      밟고 있는 lane 파일럿(= jungle/neutral 셀이 아닌 cell에 서있는 lane
#      pilot)은 제외; 정글러와 lane에서 벗어난(jungle 셀에 displaced된) lane
#      pilot은 포함한다.
#   3) _bs.game_phase = ENGAGE 로 전환 → 자동 BATTLE 틱은 BATTLE 가드에 의해
#      자연스럽게 멈추고, 카드 클릭/단계 넘기기도 ENGAGE 에서는 차단된다.
#   4) 라운드 N 동안: 시전자 진영부터 → 상대 진영. 진영 내 공격 순서는
#      존재감 DESC, 동률은 무작위 셔플. 각 파일럿은 라운드당 1회 공격.
#      대상은 상대 진영 생존자 중에서 존재감 가중치 무작위로 선정.
#      명중 굴림은 hit/(hit+evasion). 명중 시 dmg = 시전 파일럿의 atk,
#      보호막부터 흡수, HP 차감. 0 이하면 사망 + respawn_timer = RESPAWN_TURNS
#      (전장에서의 처치와 동일).
#   5) 종료 조건: rounds_total 만큼 라운드 진행 OR 한 쪽 진영의 생존자 0.
#   6) 라운드 종료 후 딜량 대시보드(준 딜량 / 받은 딜량 / 처치 수) →
#      "확인" 버튼 → CARD_PHASE 로 복귀.

# Emitted from _on_dashboard_confirmed once the engage modal has closed and
# game phase is back at CARD_PHASE. AiCardPlayer awaits this so back-to-back
# AI plays don't stomp each other's modals.
signal engage_finished

@onready var _bs: BattleSim = get_parent() as BattleSim

# Per-attack pacing inside the modal. Short enough that a 3-round engage with
# ~10 pilots resolves in under 5 seconds, long enough that the player can read
# each hit. Tunable.
const STEP_DELAY_SEC := 0.45
# Pause between rounds for a round-banner pop.
const ROUND_DELAY_SEC := 0.7

# ─── Engage state (cleared in start_engage) ──────────────────────────────────
var _active: bool = false
var _caster: PilotData = null
var _rounds_total: int = 0
var _round_idx: int = 0
var _initiator_team: int = 0
# True when running a 결투 — round banner / count is hidden, fight runs
# until the first KO regardless of _rounds_total.
var _is_duel: bool = false
var _team_pilots: Array = [[], []]   # team_pilots[t] = Array[PilotData], full participant list
var _team_order: Array = [[], []]    # team_order[t]  = Array[PilotData], current-round attack queue
# Per-pilot stat tracking — keyed by PilotData instance. Values:
#   {dealt: int, taken: int, kills: int}
var _stats: Dictionary = {}

# Hand-off back to CardPhaseManager for UI refresh after engage closes.
var _on_done: Callable = Callable()

# Dedicated CanvasLayer for the engage modal so it sits above the hand row
# (hand cards live on _bs.canvas at layer 1) and any leftover targeting UI.
# Picked to be >= CardSelectOverlay (layer 10) and CardTargetingOverlay
# (layer 11) so engage always wins z-order.
const ENGAGE_OVERLAY_LAYER: int = 12
var _overlay_layer: CanvasLayer = null

# Overlay instance (Control parented to _overlay_layer). Cleaned up in _close_overlay.
var _overlay: Control = null


func _ready() -> void:
	# Build the dedicated CanvasLayer up front so _open_overlay just has to
	# attach an EngageOverlay child. Lazy-construct in _ready (vs _init) so
	# add_child is legal — we're already inside the scene tree by this point.
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = ENGAGE_OVERLAY_LAYER
	_overlay_layer.name = "EngageOverlayLayer"
	add_child(_overlay_layer)


# Public entry point. Called from CardPhaseManager when an engage:N clause fires.
# `caster`         — the casting PilotData (시전자); also defines the area centre.
# `rounds_total`   — number of full rounds to play (engage:3 → 3).
# `exclude_lane`   — true for the 교전 card; filters out lane pilots that are on
#                    their lane (i.e., not displaced into a jungle cell).
# `on_done`        — optional Callable invoked once the modal closes and game
#                    phase returns to CARD_PHASE. Used to refresh hand UI.
func start_engage(caster: PilotData, rounds_total: int, exclude_lane: bool,
		on_done: Callable = Callable()) -> void:
	if _active:
		return
	if caster == null or rounds_total <= 0:
		return

	var participants := _gather_participants(caster, exclude_lane)
	# Need at least one pilot per side; otherwise the card just no-ops.
	var t0: Array = []
	var t1: Array = []
	for raw in participants:
		var p := raw as PilotData
		if p.alive:
			(t0 if p.team == 0 else t1).append(p)
	if t0.is_empty() or t1.is_empty():
		_bs.last_log = "[전투 개시] 대상 부족"
		if on_done.is_valid():
			on_done.call()
		return

	_active = true
	_is_duel = false
	_caster = caster
	_rounds_total = rounds_total
	_round_idx = 0
	_initiator_team = caster.team
	_team_pilots[0] = t0
	_team_pilots[1] = t1
	_stats.clear()
	for raw in t0 + t1:
		_stats[raw] = {"dealt": 0, "taken": 0, "kills": 0}
	_on_done = on_done

	# Drop any lifted-card / description-box selection so the modal sits cleanly
	# over the table. CardPhaseManager.deselect_current_card is idempotent.
	if _bs.card_phase != null:
		_bs.card_phase.deselect_current_card()

	_bs.game_phase = GameEnums.BattlePhase.ENGAGE
	_open_overlay()
	# Resolve sequentially so the overlay can animate one attack at a time.
	_run_engage()


# 결투 — 1:1 engage to KO. Bypasses _gather_participants so only the caster
# and `target` participate. rounds_total is set very high; the round loop
# naturally terminates as soon as either side has 0 alive participants
# (i.e., on the first KO). Same modal lifecycle as start_engage; routes
# through engage_finished so AiCardPlayer awaits it like any engage card.
func start_duel(caster: PilotData, target: PilotData,
		on_done: Callable = Callable()) -> void:
	if _active:
		return
	if caster == null or target == null:
		return
	if not caster.alive or not target.alive:
		return
	if caster.team == target.team:
		return
	var t0: Array
	var t1: Array
	if caster.team == 0:
		t0 = [caster]; t1 = [target]
	else:
		t0 = [target]; t1 = [caster]

	_active = true
	_is_duel = true
	_caster = caster
	# Effectively unbounded; loop exits on first KO.
	_rounds_total = 99
	_round_idx = 0
	_initiator_team = caster.team
	_team_pilots[0] = t0
	_team_pilots[1] = t1
	_stats.clear()
	for raw in t0 + t1:
		_stats[raw] = {"dealt": 0, "taken": 0, "kills": 0}
	_on_done = on_done

	if _bs.card_phase != null:
		_bs.card_phase.deselect_current_card()

	_bs.game_phase = GameEnums.BattlePhase.ENGAGE
	_open_overlay()
	_run_engage()


# AI 측 engage 즉시 일괄 해상도 — 모달/애니메이션 없이 결과만 적용한다.
# end_card_phase 가 동기 while-loop 안에서 AI 카드를 한 번에 처리하기 때문에
# 모달을 띄우면 페이즈 전이가 꼬인다. 디자인 정리가 끝나면 이 경로도 모달을
# 보여주도록 통합 가능.
func resolve_silent(caster: PilotData, rounds_total: int,
		exclude_lane: bool) -> void:
	if caster == null or rounds_total <= 0:
		return
	var participants := _gather_participants(caster, exclude_lane)
	var t0: Array = []
	var t1: Array = []
	for raw in participants:
		var p := raw as PilotData
		if p.alive:
			(t0 if p.team == 0 else t1).append(p)
	if t0.is_empty() or t1.is_empty():
		return
	var pilots: Array = [t0, t1]
	var initiator: int = caster.team
	for r in rounds_total:
		if pilots[0].filter(func(p): return (p as PilotData).alive).is_empty():
			break
		if pilots[1].filter(func(p): return (p as PilotData).alive).is_empty():
			break
		var sides := [initiator, 1 - initiator]
		for side in sides:
			var order := _build_attack_order(pilots[side])
			for raw in order:
				var attacker := raw as PilotData
				if not attacker.alive:
					continue
				if pilots[1 - attacker.team].filter(
						func(p): return (p as PilotData).alive).is_empty():
					return
				_silent_attack(attacker, pilots[1 - attacker.team])


# Lightweight per-attack resolver for the silent path. Mirrors _perform_attack
# but writes nothing to the overlay or the per-pilot stats dict.
func _silent_attack(attacker: PilotData, enemies: Array) -> void:
	var weights: Array = []
	var alive: Array = []
	var total: int = 0
	for raw in enemies:
		var p := raw as PilotData
		if not p.alive:
			continue
		var w: int = max(1, p.presence)
		alive.append(p)
		weights.append(w)
		total += w
	if alive.is_empty():
		return
	var roll_w: int = randi() % total
	var target: PilotData = alive[-1]
	for i in alive.size():
		roll_w -= int(weights[i])
		if roll_w < 0:
			target = alive[i]
			break
	var hit_total: float = float(max(1, attacker.hit + target.evasion))
	if randf() >= float(attacker.hit) / hit_total:
		return
	var dmg: int = max(1, attacker.atk)
	if target.shield > 0:
		var absorbed: int = min(target.shield, dmg)
		target.shield -= absorbed
		dmg -= absorbed
	if dmg > 0:
		target.hp = max(0, target.hp - dmg)
	if target.hp <= 0:
		target.alive = false
		target.respawn_timer = _bs.RESPAWN_TURNS


# ─── Participant gathering ───────────────────────────────────────────────────
# Caster cell + 6 neighbor cells (radius-1 hex). Includes the caster.
func _gather_participants(caster: PilotData, exclude_lane: bool) -> Array:
	var area: Dictionary = {caster.grid_pos: true}
	for n in _bs.hex_grid.get_neighbors(caster.grid_pos.x, caster.grid_pos.y):
		area[n] = true
	var out: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if not area.has(p.grid_pos):
			continue
		if exclude_lane and not _is_engage_eligible_under_exclude_lane(p):
			continue
		out.append(p)
	return out


# exclude_lane 의미: 자기 lane 위에서 정상적으로 push 중인 lane 파일럿은 제외.
# 정글러는 항상 포함, lane 파일럿이지만 카드 효과로 jungle/neutral 셀에
# 변위된 경우는 포함(2:1 일방적 교전을 노린 디자인 의도).
func _is_engage_eligible_under_exclude_lane(p: PilotData) -> bool:
	if p.is_guerrilla:
		return true
	# neutral_zone_cells 는 모든 jungle/neutral 셀을 포함하는 사전.
	# lane 파일럿이 그 안에 있다 = displaced 상태.
	return _bs.neutral_zone_cells.has(p.grid_pos)


# ─── Round / attack loop ─────────────────────────────────────────────────────
func _run_engage() -> void:
	while _active and _round_idx < _rounds_total and _both_sides_alive():
		_round_idx += 1
		# 결투 hides the per-round banner — the modal title already says 결투.
		if _overlay != null and not _is_duel:
			_overlay.show_round_banner(_round_idx, _rounds_total)
		if not _is_duel:
			await _bs.get_tree().create_timer(ROUND_DELAY_SEC).timeout
			if not _active:
				return

		# Initiator side first, then the other side. Each side rebuilds its
		# attack queue at the start of the round (presence DESC, ties random).
		var sides: Array = [_initiator_team, 1 - _initiator_team]
		for side in sides:
			_team_order[side] = _build_attack_order(_team_pilots[side])
			while not (_team_order[side] as Array).is_empty():
				var attacker := (_team_order[side] as Array).pop_front() as PilotData
				if not attacker.alive:
					continue
				if not _both_sides_alive():
					break
				_perform_attack(attacker)
				await _bs.get_tree().create_timer(STEP_DELAY_SEC).timeout
				if not _active:
					return
			if not _both_sides_alive():
				break

	if _active:
		_finish_engage()


# Sort participants by presence DESC; randomize ties via a small random offset.
func _build_attack_order(pilots: Array) -> Array:
	var copy: Array = pilots.duplicate()
	# Stable-ish randomized sort: pair each pilot with a random tiebreaker, then
	# sort by (-presence, tiebreaker).
	var pairs: Array = []
	for raw in copy:
		var p := raw as PilotData
		if not p.alive:
			continue
		pairs.append({"p": p, "pres": p.presence, "tie": randf()})
	pairs.sort_custom(func(a, b):
		if a["pres"] != b["pres"]:
			return a["pres"] > b["pres"]
		return a["tie"] < b["tie"])
	var out: Array = []
	for entry in pairs:
		out.append(entry["p"])
	return out


func _both_sides_alive() -> bool:
	return _alive_count(0) > 0 and _alive_count(1) > 0


func _alive_count(team: int) -> int:
	var n := 0
	for raw in _team_pilots[team]:
		if (raw as PilotData).alive:
			n += 1
	return n


# ─── Per-attack resolution ───────────────────────────────────────────────────
func _perform_attack(attacker: PilotData) -> void:
	var target := _pick_target(attacker)
	if target == null:
		return

	# 전장 룰과 동일: hit/(hit+evasion) 굴림. 명중 시 dmg = atk, 보호막부터 흡수.
	var hit_total: float = float(max(1, attacker.hit + target.evasion))
	var hit_chance: float = float(attacker.hit) / hit_total
	var roll := randf()
	var did_hit := roll < hit_chance
	var dmg_applied := 0
	var killed := false
	if did_hit:
		var dmg: int = max(1, attacker.atk)
		var shield_absorbed: int = 0
		if target.shield > 0:
			shield_absorbed = min(target.shield, dmg)
			target.shield -= shield_absorbed
			dmg -= shield_absorbed
		var hp_dmg: int = 0
		if dmg > 0:
			hp_dmg = min(dmg, target.hp)
			target.hp = max(0, target.hp - dmg)
		dmg_applied = shield_absorbed + hp_dmg
		if target.hp <= 0:
			target.alive = false
			target.respawn_timer = _bs.RESPAWN_TURNS
			killed = true
		else:
			_bs.anim_pilot_shake(target)

	# Stats — record dealt/taken on the actual atk value (shield + HP).
	if did_hit:
		(_stats[attacker] as Dictionary)["dealt"] = int(_stats[attacker]["dealt"]) + dmg_applied
		(_stats[target] as Dictionary)["taken"]   = int(_stats[target]["taken"])   + dmg_applied
		if killed:
			(_stats[attacker] as Dictionary)["kills"] = int(_stats[attacker]["kills"]) + 1

	if _overlay != null:
		_overlay.show_attack(attacker, target, did_hit, dmg_applied, killed)

	_bs.last_log = "[전투] %s → %s %s" % [
		_bs.pilot_label(attacker),
		_bs.pilot_label(target),
		("-%d HP" % dmg_applied) if did_hit else "(빗나감)",
	]


# Weighted-random target selection: weight = presence on alive enemy participants.
func _pick_target(attacker: PilotData) -> PilotData:
	var enemies: Array = _team_pilots[1 - attacker.team]
	var alive_enemies: Array = []
	var weights: Array = []
	var total: int = 0
	for raw in enemies:
		var p := raw as PilotData
		if not p.alive:
			continue
		var w: int = max(1, p.presence)
		alive_enemies.append(p)
		weights.append(w)
		total += w
	if alive_enemies.is_empty():
		return null
	var roll: int = randi() % total
	for i in alive_enemies.size():
		roll -= int(weights[i])
		if roll < 0:
			return alive_enemies[i]
	return alive_enemies[-1]


# ─── End / dashboard / teardown ──────────────────────────────────────────────
func _finish_engage() -> void:
	_bs.blog.log_event("ENGAGE", "전투 개시 종료 — t0=%s t1=%s"
			% [_engage_side_str(0), _engage_side_str(1)])
	if _overlay != null:
		_overlay.show_dashboard(_team_pilots[0], _team_pilots[1], _stats,
				Callable(self, "_on_dashboard_confirmed"))
	else:
		_on_dashboard_confirmed()


func _on_dashboard_confirmed() -> void:
	_close_overlay()
	_active = false
	# Return to CARD_PHASE — player can keep playing cards or press 단계 넘기기.
	_bs.game_phase = GameEnums.BattlePhase.CARD_PHASE
	if _on_done.is_valid():
		_on_done.call()
		_on_done = Callable()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()
	engage_finished.emit()


# Public read used by AiCardPlayer to know when to await engage_finished.
func is_active() -> bool:
	return _active


func _open_overlay() -> void:
	if _overlay_layer == null:
		return
	_overlay = EngageOverlay.new()
	_overlay.name = "EngageOverlay"
	_overlay_layer.add_child(_overlay)
	var title: String = "결투" if _is_duel else "전투 개시"
	(_overlay as EngageOverlay).setup(_bs, _team_pilots[0], _team_pilots[1],
			_initiator_team, _rounds_total, title, _is_duel)


# Debug-log helper: "TANK0(hp120) SNPR0(dead)" for one side of the engage.
func _engage_side_str(team: int) -> String:
	var parts: Array = []
	for raw in (_team_pilots[team] as Array):
		var p := raw as PilotData
		parts.append("%s(%s)" % [_bs.pilot_label(p),
				("hp%d" % p.hp) if p.alive else "dead"])
	return "-" if parts.is_empty() else ",".join(parts)


func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
