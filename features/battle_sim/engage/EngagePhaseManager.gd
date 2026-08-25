class_name EngagePhaseManager
extends Node

# 전투 개시(engage) 모듈 — engage:N / duel 카드 효과로 발동되는 **라운드 기반
# 턴제 사이드뷰 벨트 교전**을 구동한다. 해상도는 TurnEngageSim(헤드리스),
# 시각화는 EngageArena(Control) 가 담당하고 이 매니저는 둘을 잇는
# 오케스트레이터다.
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
#   4) **engage:N 의 N 은 라운드 수다**(초가 아니다). 한 라운드 안에서 참가자
#      전원이 정확히 한 번씩, **한 명씩 순서대로** 접근 → 공격 → 그 자리에
#      눌러앉기를 수행한다(원위치 복귀 없음). 매 라운드 시전자부터 시작한다.
#      플레이어 입력은 없다(관전 전용).
#   5) 종료 조건: 라운드 소진 OR 한 쪽 진영 전멸.
#      **교전 중 이탈은 없다** — 끝날 때까지 아무도 아레나를 뜨지 못한다.
#   6) 종료 후 딜량 대시보드(준 딜량 / 받은 딜량 / 처치 수) → "확인" 버튼 →
#      **아레나에 들어오기 직전의 페이즈**로 복귀(플레이어 카드면 CARD_PHASE,
#      상대 차례에 AI가 낸 카드면 BATTLE).
#
# 살아남은 파일럿은 원래 셀에 그대로 남는다. grid_pos 는 건드리지 않는다 —
# 저HP 파일럿은 작전 단계 종료 시 RecallSystem 의 HP 임계 복귀가 어차피
# 본진으로 데려간다.

# Emitted from _on_dashboard_confirmed once the engage modal has closed and the
# game phase is back at whatever opened it (_phase_before). AiCardPlayer awaits
# this so back-to-back AI plays don't stomp each other's modals.
signal engage_finished

@onready var _bs: BattleSim = get_parent() as BattleSim

## 시뮬레이션 고정 스텝. 프레임 레이트가 흔들려도 결과가 크게 달라지지 않도록
## delta 를 이 크기로 쪼개 굴린다.
const FIXED_DT: float = 1.0 / 60.0
## 한 프레임에 몰아서 굴릴 수 있는 스텝 상한(프레임 드랍 시 나선형 방지).
const MAX_STEPS_PER_FRAME: int = 8
## 종료 판정 → 결과 대시보드 사이의 유예(초). 마지막 처치나 시간 만료를 눈으로
## 확인할 틈을 준다. 이 동안 전투는 완전히 멈추고(시뮬레이터는 `step_afterglow`
## 로 잔여 연출만 굴린다) 아레나 상단에 종료 사유 배너가 뜬다.
const END_HOLD_SEC: float = 2.0

# ─── Engage state (cleared in start_engage / start_duel) ─────────────────────
var _active: bool = false
var _is_duel: bool = false
var _team_pilots: Array = [[], []]   # team_pilots[t] = Array[PilotData]
var _sim: TurnEngageSim = null
var _accum: float = 0.0
## 종료 유예 잔여 시간. 음수 = 유예 중이 아님(아직 전투 중).
var _hold_left: float = -1.0
## 아레나에 들어오기 직전의 game_phase. 플레이어 카드로 열린 교전이면
## CARD_PHASE, AI 차례(BATTLE 안에서 도는 상대 턴)로 열린 교전이면 BATTLE 이다.
## 끝나고 이 값으로 되돌린다 — 예전처럼 CARD_PHASE 로 못박으면 상대 턴이 끝난
## 뒤 전장이 작전 단계에 갇힌다.
var _phase_before: int = GameEnums.BattlePhase.CARD_PHASE

# Hand-off back to CardPhaseManager for UI refresh after engage closes.
var _on_done: Callable = Callable()

## 아레나 제목. 빈 문자열이면 "전투 개시" / "결투" 기본값을 쓴다. 오브젝트
## 교전이 "전령" / "용" 을 넣는다.
var _arena_title: String = ""

## 방금 끝난 교전의 성적표(`TurnEngageSim.stats` 의 사본). `_sim` 은 대시보드를
## 닫을 때 버려지는데, `engage:N` 절을 물고 있던 효과 체인은 그 **뒤에** 깨어나
## "이 교전에서 몇을 눕혔나"를 묻는다([우세한 전장] 의 `gen_hand|per_kill`).
## 그래서 사본을 여기 남긴다 — 교전 하나짜리 값이라 다음 교전이 덮어쓴다.
var _last_stats: Dictionary = {}

# Dedicated CanvasLayer for the engage modal so it sits above the hand row
# (hand cards live on _bs.canvas at layer 1) and any leftover targeting UI.
# Picked to be >= CardSelectOverlay (layer 10) and CardTargetingOverlay
# (layer 11) so engage always wins z-order.
const ENGAGE_OVERLAY_LAYER: int = 12
var _overlay_layer: CanvasLayer = null

# Arena instance (Control parented to _overlay_layer). Cleaned up in _close_overlay.
var _arena: EngageArena = null

# ─── 개시 확인 화면 (VS) ──────────────────────────────────────────────────────
# 카드가 **제출된 직후**, 아레나가 열리기 전에 참가자 명단을 보여 주는 모달.
# `prompt_engage` 가 만들고 await 하며, 그동안 `_active` 는 아직 false 다 —
# 교전은 시작되지 않았고 취소되면 아예 시작되지 않는다.
var _intro: EngageIntro = null


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
# `caster`       — the casting PilotData (시전자); defines the participant area
#                  and acts **first in every round** (선공권).
# `rounds_total` — the card's engage:N value, used verbatim as the round count
#                  (engage:3 → 3 라운드).
# `exclude_lane` — true for the 교전 card; filters out lane pilots that are on
#                  their lane (i.e., not displaced into a jungle cell).
# `on_done`      — optional Callable invoked once the modal closes and game
#                  phase returns to CARD_PHASE. Used to refresh hand UI.
func start_engage(caster: PilotData, rounds_total: int, exclude_lane: bool,
		on_done: Callable = Callable(),
		center: Vector2i = Vector2i(-999, -999), radius: int = 1) -> void:
	if _active:
		return
	if caster == null or rounds_total <= 0:
		return

	var participants := _gather_participants(caster, exclude_lane, center, radius)
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

	# 파일럿 스킬의 라운드 보정 — 전투 명령(이번 작전 단계, −1)과 공성전
	# (다음 한 장, +3)의 합. 후자는 여기서 **소모**된다: 한 장에만 붙는 것이라
	# 실제로 교전이 열리는 이 지점이 유일하게 옳은 소모 자리다.
	if _bs.skill != null:
		rounds_total = maxi(1, rounds_total
				+ _bs.skill.engage_round_delta(caster.team, true))

	_begin(caster, t0, t1, false, rounds_total, on_done)


## 시전자 기준 참가자를 **팀별로 갈라** 돌려준다: `[team0, team1]`.
## `start_engage` 가 쓰는 것과 같은 수집 규칙이라 개시 확인 화면(VS)에 뜬 명단과
## 실제로 무대에 오르는 명단이 어긋날 수 없다. 두 호출 사이에는 아무 일도
## 일어나지 않으므로 두 번 수집해도 결과가 같다.
func engage_sides(caster: PilotData, exclude_lane: bool,
		center: Vector2i = Vector2i(-999, -999), radius: int = 1) -> Array:
	var t0: Array = []
	var t1: Array = []
	if caster == null:
		return [t0, t1]
	for raw in _gather_participants(caster, exclude_lane, center, radius):
		var p := raw as PilotData
		if p.alive:
			(t0 if p.team == 0 else t1).append(p)
	return [t0, t1]


## 개시 확인 화면(VS)을 띄우고 **확인(true) / 취소(false)** 를 기다린다.
##
## 아레나를 여는 것과는 별개의 단계다 — 여기서 취소하면 교전은 시작조차 하지
## 않고, 호출 측(`CardPhaseManager._effect_engage`)이 카드 제출 자체를 무른다.
## `allow_cancel` 이 false 면 확인만 놓는다: AI 가 낸 카드는 플레이어가 무를 수
## 있는 것이 아니므로 "누가 싸우는지 보고 넘긴다"만 남는다.
func prompt_engage(t0: Array, t1: Array, rounds: int, title: String,
		allow_cancel: bool, confirm_text: String = "확인",
		cancel_text: String = "취소", subtitle: String = "") -> bool:
	if _overlay_layer == null:
		return true
	# 카드를 든 손패 상태를 먼저 걷는다 — 이 모달이 그 위를 덮으면 리프트된
	# 카드가 딤 아래에 남는다. (`_begin` 도 같은 이유로 부른다.)
	if _bs.card_phase != null:
		_bs.card_phase.deselect_current_card()
	_intro = EngageIntro.new()
	_intro.name = "EngageIntro"
	_overlay_layer.add_child(_intro)
	_intro.setup(title, rounds, t0, t1, allow_cancel,
			confirm_text, cancel_text, subtitle)
	# 손패 딤과 턴 넘기기 잠금은 `is_intro_active()` 를 읽는데, 그 둘은 상태가
	# 바뀔 때만 다시 평가된다 — 열 때와 닫을 때 한 번씩 깨워 준다.
	_refresh_hand_gates()
	var confirmed: bool = await _intro.decided
	if is_instance_valid(_intro):
		_intro.queue_free()
	_intro = null
	_refresh_hand_gates()
	return confirmed


func _refresh_hand_gates() -> void:
	if _bs.card_phase != null:
		_bs.card_phase.highlight_affordable_cards()
	if _bs.hud != null:
		_bs.hud.update_hud()


## True while the VS 확인 화면 owns the screen. BattleSim's auto-tick is already
## held by CARD_PHASE (player) or `is_ai_turn_active()` (AI), so this exists for
## UI gates that need to know the hand is not the player's to touch.
func is_intro_active() -> bool:
	return _intro != null and is_instance_valid(_intro)


# 결투 — 1:1 턴제 교전. _gather_participants 를 우회해 시전자와 target 만
# 참여시키고, 카드가 정한 라운드 수 대신 DUEL_MAX_ROUNDS 상한만 둔다(실질적으로
# 한 쪽이 처치될 때까지). start_engage 와 같은 모달 생명주기를 타고
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
	_begin(caster, t0, t1, true, TurnEngageSim.DUEL_MAX_ROUNDS, on_done)


## 오브젝트 교전 — 전령 / 용을 두고 벌어지는 교전. 카드 교전과 다른 점은 셋뿐.
##
##   1. **시전자가 없다.** 카드가 아니라 타이머가 여는 교전이라 "먼저 행동하는
##      한 명"이 없다. 선공 팀은 `first_team`(블루)이 정한다.
##   2. **참가자를 시전자 주변에서 모으지 않는다.** 포지션으로 정해진 명단이
##      그대로 들어온다(`ObjectiveSystem.participants_for`).
##   3. **무대 제목이 오브젝트 이름**이다("전령" / "용").
##
## 종료 배너는 카드 교전과 같은 문구(전멸 / N라운드 완료)를 그대로 쓴다 — 승패와
## 보상은 배너가 아니라 무대가 닫힌 뒤 `last_log` 가 말한다. 배너는 종료 판정
## 직후 `END_HOLD_SEC` 동안 떠 있고 호출 측이 제어를 되찾는 것은 그 **뒤**라,
## 승패를 배너에 실을 수 있는 시점이 애초에 없다.
##
## 나머지 생명주기(라운드 진행 · 종료 유예 · 대시보드 · `engage_finished`)는
## 카드 교전과 완전히 같다 — 호출 측은 같은 방식으로 await 하면 된다.
func start_objective_engage(t0: Array, t1: Array, rounds: int, title: String,
		first_team: int, on_done: Callable = Callable()) -> void:
	if _active:
		return
	if t0.is_empty() or t1.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_begin(null, t0, t1, false, rounds, on_done, title, first_team)


# 공통 진입 — 시뮬레이터 구성 + 아레나 오픈 + _process 구동 시작.
func _begin(caster: PilotData, t0: Array, t1: Array, duel: bool,
		rounds: int, on_done: Callable, title: String = "",
		first_team: int = -1) -> void:
	_active = true
	_is_duel = duel
	_team_pilots[0] = t0
	_team_pilots[1] = t1
	_on_done = on_done
	_accum = 0.0
	_hold_left = -1.0
	_arena_title = title
	# 기회주의자(파일럿 스킬)의 처치 장부는 교전 하나에만 유효하다.
	if _bs.skill != null:
		_bs.skill.on_engage_started()
	# 메크 쪽 교전 개시 훅 — 반응 장갑 전개 · 불굴 · 약자 멸시가 여기서 켜진다.
	if _bs.mech_skill != null:
		_bs.mech_skill.on_engage_start(t0 + t1)

	_sim = TurnEngageSim.new()
	_sim.setup(_bs, caster, t0, t1, rounds, duel, first_team)

	# Drop any lifted-card / description-box selection so the modal sits cleanly
	# over the table. CardPhaseManager.deselect_current_card is idempotent.
	if _bs.card_phase != null:
		_bs.card_phase.deselect_current_card()

	_phase_before = _bs.game_phase
	_bs.game_phase = GameEnums.BattlePhase.ENGAGE
	_open_overlay()
	set_process(true)


# ─── 실시간 구동 ─────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _active or _sim == null:
		return
	# 종료 유예 중 — 전투는 멈춘 채 잔여 연출만 흐른다.
	if _hold_left >= 0.0:
		_sim.step_afterglow(delta)
		_hold_left -= delta
		if _hold_left <= 0.0:
			_hold_left = -1.0
			set_process(false)
			_finish_engage()
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
		_begin_end_hold()


# 종료 판정 직후 — 대시보드를 바로 띄우지 않고 END_HOLD_SEC 만큼 아레나를
# 그대로 보여 준다. 마지막 처치가 대시보드에 먹혀 "언제 죽었지?" 가 되는 걸
# 막는 게 목적이라, 배너로 종료 사유(전멸 / 시간 종료)도 같이 알려 준다.
func _begin_end_hold() -> void:
	_hold_left = END_HOLD_SEC
	if _arena != null:
		_arena.mark_engage_over(_end_banner_text())


func _end_banner_text() -> String:
	if _sim == null:
		return "교전 종료"
	var t0_out: bool = _sim.active_count(0) == 0
	var t1_out: bool = _sim.active_count(1) == 0
	if t0_out and t1_out:
		return "교전 종료 — 양측 전멸"
	if t1_out:
		return "교전 종료 — 적군 전멸"
	if t0_out:
		return "교전 종료 — 아군 전멸"
	return "교전 종료 — %d라운드 완료" % _sim.total_rounds


# ─── Participant gathering ───────────────────────────────────────────────────
# Caster cell + 6 neighbor cells (radius-1 hex). Includes the caster.
## 교전 무대에 설 사람들. 기본 무대는 **시전자 칸 + 인접 6칸**이지만, 메크
## 카드가 그 둘을 바꿔 부른다 — `center` 로 무대를 시전자가 아닌 **지정한 적
## 주변**으로 옮기고([돌격] · [강습] · [간보기]), `radius` 로 넓힌다([우세한
## 전장] 3, [개시] · [제압 전투] 2). 기본값은 예전 그대로다.
func _gather_participants(caster: PilotData, exclude_lane: bool,
		center: Vector2i = Vector2i(-999, -999), radius: int = 1) -> Array:
	var origin: Vector2i = center if center != Vector2i(-999, -999) else caster.grid_pos
	var out: Array = []
	for raw in _bs.pilots:
		var p := raw as PilotData
		if not p.alive:
			continue
		if _bs.hex_grid.hex_distance(origin, p.grid_pos) > radius:
			continue
		if exclude_lane and not _is_engage_eligible_under_exclude_lane(p):
			continue
		# 탈진([탈진] 카드) — 이번 작전 단계 동안 전투에 못 들어간다. 무대에
		# 세우지 않는 것이 곧 그 효과다.
		if p.engage_locked:
			continue
		out.append(p)
	# 결속 / 추적 — **무대 밖에서 끌려 들어오는** 두 경로. 참가가 확정된 뒤에
	# 붙이므로 사거리를 보지 않는다: 그 원격성이 두 카드의 값이다.
	var pulled: Array = []
	for raw in out:
		var p := raw as PilotData
		if p.engage_link != null and p.engage_link.alive 				and not out.has(p.engage_link) and not pulled.has(p.engage_link):
			pulled.append(p.engage_link)
		for entry_raw in p.tracked_by:
			var tracker: PilotData = (entry_raw as Dictionary).get("pilot", null)
			if tracker != null and tracker.alive 					and not out.has(tracker) and not pulled.has(tracker):
				pulled.append(tracker)
	out.append_array(pulled)
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
	# 성적표는 `_sim` 이 버려지기 전에 떠 둔다 — 아래 `_on_dashboard_confirmed`
	# 가 `_sim = null` 로 무대를 치우고, 그 뒤에야 효과 체인이 깨어난다.
	_last_stats = _sim.stats.duplicate()
	# 메크 쪽 교전 종료 훅 — 강타 장전 · 약자 멸시 스택 · 불굴 장부처럼 **그
	# 교전 한 번**짜리 상태가 여기서 걷힌다(`on_engage_start` 의 짝이다).
	if _bs.mech_skill != null:
		_bs.mech_skill.on_engage_end(_team_pilots[0] + _team_pilots[1])
	_bs.last_log = _result_log()
	_bs.blog.log_event("ENGAGE", "전투 개시 종료 — t0=%s t1=%s"
			% [_engage_side_str(0), _engage_side_str(1)])
	if _arena != null:
		_arena.show_dashboard(_team_pilots[0], _team_pilots[1], _sim.stats,
				Callable(self, "_on_dashboard_confirmed"))
	else:
		_on_dashboard_confirmed()


func _result_log() -> String:
	var kills: Array = [0, 0]
	for p in _sim.stats:
		var s: Dictionary = _sim.stats[p]
		kills[(p as PilotData).team] += int(s["kills"])
	return "[교전] %d라운드 · 아군 처치 %d / 적군 처치 %d" % [
		_sim.round_index, kills[0], kills[1]]


func _on_dashboard_confirmed() -> void:
	_close_overlay()
	_active = false
	_sim = null
	_hold_left = -1.0
	# Return to whichever phase opened the arena: CARD_PHASE for a player card
	# (player can keep playing cards or press 턴 넘기기), BATTLE for an AI card
	# played during 상대 차례 (the tick stays held by is_ai_turn_active()).
	_bs.game_phase = _phase_before
	if _on_done.is_valid():
		_on_done.call()
		_on_done = Callable()
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()
	# 교전 중에 난 처치는 아레나가 화면을 덮고 있어 킬로그가 보류해 두었다.
	# 무대가 치워진 지금 한 줄씩 이어서 풀어놓는다.
	if _bs.kill_feed != null:
		_bs.kill_feed.flush_pending()
	# 같은 이유로 밀려 있던 성장치 팝업 — 이쪽은 파일럿마다 **한 장으로 합쳐**
	# 전장 초상화 위에 뜬다("이 교전에서 얼마를 벌었나"). 쓰러진 참가자는
	# 건너뛴다.
	_bs.flush_score_popups()
	engage_finished.emit()


# Public read used by AiCardPlayer to know when to await engage_finished.
func is_active() -> bool:
	return _active


## 방금 끝난 교전에서 이 파일럿이 눕힌 적 수. 무대가 치워진 뒤에도 답한다.
## [우세한 전장] 의 `gen_hand:19|per_kill` 이 유일한 소비자다.
func last_engage_kills(p: PilotData) -> int:
	if p == null or not _last_stats.has(p):
		return 0
	return int((_last_stats[p] as Dictionary).get("kills", 0))


## 방금 끝난 교전에 서 있었고 **살아서 나왔는가**. "교전에서 생존할 시" 라는
## 조건이 붙은 카드가 읽는다 — 명단에 없으면(참가하지 않았으면) false 다.
func survived_last_engage(p: PilotData) -> bool:
	return p != null and _last_stats.has(p) and p.alive


func _open_overlay() -> void:
	if _overlay_layer == null:
		return
	_arena = EngageArena.new()
	_arena.name = "EngageArena"
	_overlay_layer.add_child(_arena)
	var title: String = _arena_title
	if title.is_empty():
		title = "결투" if _is_duel else "전투 개시"
	_arena.setup(_bs, _sim, title, _is_duel)


# Debug-log helper: "TANK0(hp120) SNPR0(dead)" for one side of the engage.
func _engage_side_str(team: int) -> String:
	var parts: Array = []
	for raw in (_team_pilots[team] as Array):
		var p := raw as PilotData
		parts.append("%s(%s)" % [_bs.pilot_label(p),
				("hp%d" % p.hp) if p.alive else "dead"])
	return "-" if parts.is_empty() else ",".join(parts)


func _close_overlay() -> void:
	if _arena != null and is_instance_valid(_arena):
		_arena.queue_free()
	_arena = null
