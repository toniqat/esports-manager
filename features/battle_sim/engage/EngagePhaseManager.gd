class_name EngagePhaseManager
extends Node

# 전투 개시(engage) 모듈 — engage:N / duel 카드 효과로 발동되는 **실시간 MOBA
# 교전**을 구동한다. 해상도는 RealtimeEngageSim(헤드리스), 시각화는
# EngageArena(Control) 가 담당하고 이 매니저는 둘을 잇는 오케스트레이터다.
#
# 흐름:
#   1) CardPhaseManager._apply_single_effect 가 engage clause 를 만나면
#      EngagePhaseManager.start_engage(caster, rounds, exclude_lane) 를 호출.
#   2) 시전자 셀 + 인접 1칸(반경 1 육각)의 모든 파일럿이 참여.
#      exclude_lane 플래그가 있으면 lane row 에서 정상적으로 자기 lane 을
#      밟고 있는 lane 파일럿은 제외; 정글러와 jungle 셀로 변위된 lane
#      파일럿은 포함한다.
#   3) _bs.game_phase = ENGAGE 로 전환 → 자동 BATTLE 틱은 BATTLE 가드에 의해
#      멈추고, 카드 클릭 / 턴 넘기기도 ENGAGE 에서는 차단된다.
#   4) 제한 시간(rounds × RealtimeEngageSim.SEC_PER_ROUND 초) 동안 각 파일럿이
#      자기 AI 로 접근 / 카이팅 / 공격 / 포탑 회피 / 다이브 / 후퇴를 실시간
#      수행한다. 플레이어 입력은 없다(관전 전용).
#   5) 종료 조건: 제한 시간 만료(전원 후퇴 연출 후) OR 한 쪽 진영의 활성
#      인원 0(처치 + 이탈 합산).
#   6) 종료 후 딜량 대시보드(준 딜량 / 받은 딜량 / 처치 수) → "확인" 버튼 →
#      CARD_PHASE 로 복귀.
#
# 이탈(FLED)한 파일럿은 살아서 원래 셀에 그대로 남는다. grid_pos 는 건드리지
# 않는다 — 저HP 파일럿은 작전 단계 종료 시 RecallSystem 의 HP 임계 복귀가
# 어차피 본진으로 데려간다.

# Emitted from _on_dashboard_confirmed once the engage modal has closed and
# game phase is back at CARD_PHASE. AiCardPlayer awaits this so back-to-back
# AI plays don't stomp each other's modals.
signal engage_finished

@onready var _bs: BattleSim = get_parent() as BattleSim

## 시뮬레이션 고정 스텝. 프레임 레이트가 흔들려도 결과가 크게 달라지지 않도록
## delta 를 이 크기로 쪼개 굴린다.
const FIXED_DT: float = 1.0 / 60.0
## 한 프레임에 몰아서 굴릴 수 있는 스텝 상한(프레임 드랍 시 나선형 방지).
const MAX_STEPS_PER_FRAME: int = 8

# ─── Engage state (cleared in start_engage / start_duel) ─────────────────────
var _active: bool = false
var _is_duel: bool = false
var _team_pilots: Array = [[], []]   # team_pilots[t] = Array[PilotData]
var _sim: RealtimeEngageSim = null
var _accum: float = 0.0

# Hand-off back to CardPhaseManager for UI refresh after engage closes.
var _on_done: Callable = Callable()

# Dedicated CanvasLayer for the engage modal so it sits above the hand row
# (hand cards live on _bs.canvas at layer 1) and any leftover targeting UI.
# Picked to be >= CardSelectOverlay (layer 10) and CardTargetingOverlay
# (layer 11) so engage always wins z-order.
const ENGAGE_OVERLAY_LAYER: int = 12
var _overlay_layer: CanvasLayer = null

# Arena instance (Control parented to _overlay_layer). Cleaned up in _close_overlay.
var _arena: EngageArena = null


func _ready() -> void:
	# Build the dedicated CanvasLayer up front so _open_overlay just has to
	# attach an EngageArena child. Lazy-construct in _ready (vs _init) so
	# add_child is legal — we're already inside the scene tree by this point.
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = ENGAGE_OVERLAY_LAYER
	_overlay_layer.name = "EngageOverlayLayer"
	add_child(_overlay_layer)
	set_process(false)


# Public entry point. Called from CardPhaseManager when an engage:N clause fires.
# `caster`       — the casting PilotData (시전자); the area centre, and the pilot
#                  that gets the one-shot 대쉬 when it's a melee mech.
# `rounds_total` — the card's engage:N value. Converted to seconds via
#                  RealtimeEngageSim.SEC_PER_ROUND (engage:3 → 9초).
# `exclude_lane` — true for the 교전 card; filters out lane pilots that are on
#                  their lane (i.e., not displaced into a jungle cell).
# `on_done`      — optional Callable invoked once the modal closes and game
#                  phase returns to CARD_PHASE. Used to refresh hand UI.
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

	_begin(caster, t0, t1, false,
			float(rounds_total) * RealtimeEngageSim.SEC_PER_ROUND, on_done)


# 결투 — 1:1 실시간 교전. _gather_participants 를 우회해 시전자와 target 만
# 참여시키고, 제한 시간 대신 DUEL_MAX_SEC 상한만 둔다(실질적으로 한 쪽이
# 처치되거나 이탈할 때까지). start_engage 와 같은 모달 생명주기를 타고
# engage_finished 로 끝나므로 AiCardPlayer 는 동일하게 await 하면 된다.
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
	_begin(caster, t0, t1, true, RealtimeEngageSim.DUEL_MAX_SEC, on_done)


# 공통 진입 — 시뮬레이터 구성 + 아레나 오픈 + _process 구동 시작.
func _begin(caster: PilotData, t0: Array, t1: Array, duel: bool,
		secs: float, on_done: Callable) -> void:
	_active = true
	_is_duel = duel
	_team_pilots[0] = t0
	_team_pilots[1] = t1
	_on_done = on_done
	_accum = 0.0

	_sim = RealtimeEngageSim.new()
	_sim.setup(_bs, caster, t0, t1, secs, duel)

	# Drop any lifted-card / description-box selection so the modal sits cleanly
	# over the table. CardPhaseManager.deselect_current_card is idempotent.
	if _bs.card_phase != null:
		_bs.card_phase.deselect_current_card()

	_bs.game_phase = GameEnums.BattlePhase.ENGAGE
	_open_overlay()
	set_process(true)


# ─── 실시간 구동 ─────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _active or _sim == null:
		return
	# 고정 스텝 누적. 프레임이 크게 튀어도 MAX_STEPS_PER_FRAME 로 잘라서
	# 한 프레임에 교전이 통째로 끝나 버리는 일을 막는다.
	_accum += min(delta, FIXED_DT * float(MAX_STEPS_PER_FRAME))
	var steps := 0
	while _accum >= FIXED_DT and steps < MAX_STEPS_PER_FRAME and not _sim.finished:
		_sim.step(FIXED_DT)
		_accum -= FIXED_DT
		steps += 1
	if _sim.finished:
		set_process(false)
		_finish_engage()


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


# ─── End / dashboard / teardown ──────────────────────────────────────────────
func _finish_engage() -> void:
	_bs.last_log = _result_log()
	if _arena != null:
		_arena.mark_fled(_fled_pilots())
		_arena.show_dashboard(_team_pilots[0], _team_pilots[1], _sim.stats,
				Callable(self, "_on_dashboard_confirmed"))
	else:
		_on_dashboard_confirmed()


# 저HP 로 스스로 빠져 이탈에 성공한 파일럿 목록. 제한 시간 만료로 양 팀이
# 함께 물러난 경우는 이탈이 아니므로 세지 않는다 — 안 그러면 시작 위치가
# 자기 진영 쪽에 가까웠던 팀만 전원 "이탈"로 표기되는 착시가 생긴다.
func _fled_pilots() -> Array:
	var out: Array = []
	for raw in _sim.units:
		var u := raw as RealtimeEngageSim.EUnit
		if u.state == RealtimeEngageSim.State.FLED and u.fled_low_hp:
			out.append(u.pilot)
	return out


func _result_log() -> String:
	var kills: Array = [0, 0]
	for p in _sim.stats:
		var s: Dictionary = _sim.stats[p]
		kills[(p as PilotData).team] += int(s["kills"])
	return "[교전] %.1f초 · 아군 처치 %d / 적군 처치 %d" % [
		_sim.elapsed, kills[0], kills[1]]


func _on_dashboard_confirmed() -> void:
	_close_overlay()
	_active = false
	_sim = null
	# Return to CARD_PHASE — player can keep playing cards or press 턴 넘기기.
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
	_arena = EngageArena.new()
	_arena.name = "EngageArena"
	_overlay_layer.add_child(_arena)
	_arena.setup(_bs, _sim, "결투" if _is_duel else "전투 개시", _is_duel)


func _close_overlay() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
