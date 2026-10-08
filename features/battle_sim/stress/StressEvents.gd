class_name StressEvents
extends Node

# 경기 중 스트레스 — 내 파일럿이 쓰러질 때마다 스트레스가 오르고, 경기에 기준치
# 아래로 들어온 파일럿이 경기 안에서 기준치를 넘으면 **한 번** 시험받는다
# (각성 / 패닉, 경기 끝까지). 규칙 · 수치는 `StressSystem`(season/mental) 과 const.csv
# `STRESS_*` — 이 모듈은 경기 안의 값과 연출 차례만 들고 있다. 자세한 것은 `stress/README.md`.
#
#   • 시작값 = `match_ctx.stress`(MatchFlow 가 넣는 `{"<pid>": int}`). 경기에 기준치 이상으로
#     들어온 파일럿은 위축(로스터 사본에 이미 반영됨)이고 시험받지 않는다.
#   • 사망은 `BattleSim.mark_pilot_dead` 가 `on_death` 로 알린다(전장 · 카드 · 교전 무대 모두).
#   • 시험이 생기면 **그 자리에서 멈춘다**: 큐가 빌 때까지 `is_busy()` — 자동 틱
#     (`BattleSim._battle_tick_held`) · 교전 무대 스텝(`EngagePhaseManager._process`) ·
#     상대 차례(`AiCardPlayer.run_ai_plays` 가 `wait_idle`) 가 이 답을 읽는다.
#   • 끝값은 `BattleSim.end_match` 가 `final_values()` 로 `pending_match.stress` 에 적는다.

## 큐가 비고 연출이 끝났다(`wait_idle` 이 기다린다).
signal idle

## 시험 연출 창 — 전투 HUD(50) 위, MVP 뷰(60) 아래. 씬의 `layer` 와 같은 값.
const OVERLAY_LAYER: int = 55

@onready var _bs: BattleSim = get_parent() as BattleSim

var _stress: Dictionary = {}   # PilotData → int (내 팀, 페르소나가 있는 파일럿만)
var _mood: Dictionary = {}     # PilotData → StressSystem.Mood
var _queue: Array = []         # [PilotData] 시험 차례
var _view: StressEventView = null
var _rng := RandomNumberGenerator.new()


## 파일럿 스폰 뒤 한 번(`BattleSim._ready`). 시즌 경기가 아니면(단독 실행) 아무도 없다.
func init_for_match() -> void:
	_rng.randomize()
	var gm: Node = _bs.gm
	if gm == null or not bool(gm.match_ctx.get("active", false)):
		return
	var snap: Dictionary = gm.match_ctx.get("stress", {})
	for p_raw in _bs.pilots:
		var p := p_raw as PilotData
		if p == null or p.team != 0:
			continue
		var pd: PlayerData = _bs.player_data_for(p)
		if pd == null or not snap.has(str(pd.id)):
			continue
		var s: int = int(snap[str(pd.id)])
		_stress[p] = s
		_mood[p] = StressSystem.Mood.SHAKEN if StressSystem.is_over(s) else StressSystem.Mood.NONE


## 상태 한 낱말의 글자 변형(스트립 칸 · 상세 패널 머리) — `BattleTheme._add_stress_variations`.
static func mood_variation(mood: int) -> StringName:
	match mood:
		StressSystem.Mood.AWAKEN:
			return &"StressMoodAwakenLabel"
		StressSystem.Mood.PANIC:
			return &"StressMoodPanicLabel"
	return &"StressMoodShakenLabel"


func has_stress(p: PilotData) -> bool:
	return _stress.has(p)


func stress_of(p: PilotData) -> int:
	return int(_stress.get(p, 0))


func mood_of(p: PilotData) -> int:
	return int(_mood.get(p, StressSystem.Mood.NONE))


## 연출이 떠 있거나 차례를 기다리는 시험이 있다 — 시뮬레이션을 붙잡는다.
func is_busy() -> bool:
	return _view != null or not _queue.is_empty()


## 바쁘면 큐가 빌 때까지 기다린다(상대 차례 코루틴용).
func wait_idle() -> void:
	if is_busy():
		await idle


## 내 파일럿이 쓰러졌다 — 스트레스를 올리고, 처음 기준치를 넘었으면 시험을 큐에 넣는다.
## 결과(각성 / 패닉)는 지금 정하고, 능력치는 연출이 결과를 보여 줄 때 바뀐다.
func on_death(p: PilotData) -> void:
	if not _stress.has(p) or _bs.game_over:
		return
	var s: int = clampi(stress_of(p) + _rng.randi_range(ConstTable.int_of("STRESS_DEATH_MIN"),
			ConstTable.int_of("STRESS_DEATH_MAX")), 0, ConstTable.int_of("STRESS_MAX"))
	_stress[p] = s
	if mood_of(p) != StressSystem.Mood.NONE or not StressSystem.is_over(s):
		return
	var awaken: bool = _rng.randf() < ConstTable.num("STRESS_AWAKEN_CHANCE")
	_mood[p] = StressSystem.Mood.AWAKEN if awaken else StressSystem.Mood.PANIC
	_queue.append(p)
	# 지금 도는 스텝(사망 처리 · 정산)을 끝까지 마친 뒤 연다.
	_pump.call_deferred()


## 경기 끝 — `{"<pid>": int}`. 각성 / 패닉은 적지 않는다(경기와 함께 끝난다).
func final_values() -> Dictionary:
	var out: Dictionary = {}
	for p in _stress.keys():
		var pd: PlayerData = _bs.player_data_for(p as PilotData)
		if pd != null:
			out[str(pd.id)] = int(_stress[p])
	return out


## 경기가 끝났다 — 남은 연출은 버린다(결과는 이미 정해져 능력치는 의미가 없다).
func abort() -> void:
	_queue.clear()
	if _view != null:
		_view.queue_free()
		_view = null
	idle.emit()


func _pump() -> void:
	if _view != null:
		return
	if _queue.is_empty() or _bs.game_over:
		_queue.clear()
		idle.emit()
		return
	var p := _queue.pop_front() as PilotData
	_view = StressEventView.create()
	_view.name = "StressEventView"
	add_child(_view)
	_view.revealed.connect(_apply_mood.bind(p))
	_view.closed.connect(_on_view_closed)
	_view.open(MvpView.display_name(_bs, p), MvpView.portrait_id(p), mood_of(p))


func _on_view_closed() -> void:
	if _view != null:
		_view.queue_free()
		_view = null
	_bs.hud.update_hud()
	_pump()


## 각성 / 패닉을 전장 파일럿에 얹는다 — 명중 · 회피(전장 · 교전)는 값에 직접 곱하고,
## 성장 계수 둘은 선수 스탯을 곱한 값으로 배율을 다시 뽑아 `refresh_growth_stats` 로 반영.
func _apply_mood(p: PilotData) -> void:
	var m: float = StressSystem.mood_mult(mood_of(p), stress_of(p))
	p.hit = maxi(PlayerData.STAT_MIN, roundi(float(p.hit) * m))
	p.evasion = maxi(PlayerData.STAT_MIN, roundi(float(p.evasion) * m))
	p.engage_hit = maxi(PlayerData.STAT_MIN, roundi(float(p.engage_hit) * m))
	p.engage_eva = maxi(PlayerData.STAT_MIN, roundi(float(p.engage_eva) * m))
	var pd: PlayerData = _bs.player_data_for(p)
	if pd != null:
		p.atk_growth_mult = PlayerData.growth_mult(maxi(PlayerData.STAT_MIN, roundi(float(pd.atk_growth) * m)))
		p.hp_growth_mult = PlayerData.growth_mult(maxi(PlayerData.STAT_MIN, roundi(float(pd.hp_growth) * m)))
	_bs.refresh_growth_stats(p)
	_bs.hud.update_hud()
