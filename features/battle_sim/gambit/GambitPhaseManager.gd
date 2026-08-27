class_name GambitPhaseManager
extends Node

# 개시 전 단계(`BattlePhase.GAMBIT`)의 주인.
#
# 레인 배정은 **역할이 고정한다**(`ROLE_TO_LANE`) — 예전의 인게임 배정 오버레이는
# 삭제됐고 그 자리는 밴픽 화면이 가져갔다. 이 모듈에 남은 선택은 하나,
# **정글 시작 방향**이다.
#
#   Role → Lane
#     TANK     → LEFT
#     FIGHTER  → CENTER
#     ASSASSIN → GUERRILLA
#     SUPPORT  → RIGHT
#     SNIPER   → RIGHT
#
# ── 개시 흐름 ────────────────────────────────────────────────────────────────
# `prepare_field()` 가 전장을 통째로 세운다(파일럿 · 포탑 · 정글 소유 · 캠프).
# 그 뒤 갈림길이 하나다.
#
#   • `match_ctx.active` — MatchFlow 를 거쳐 들어온 경기다. GAMBIT 에 머물면서
#     `JungleStartOverlay` 를 열어 정글러를 어느 쪽 정글에 놓을지 묻고,
#     "전투 시작"을 누르면 그때 BATTLE 로 넘어간다.
#   • 단독 실행(BattleSim.tscn 을 에디터에서 직접 돌리는 경우) — 물을 상대가
#     없으므로 기본값(LEFT)으로 곧장 BATTLE 이다. 헤드리스 검증이 이 경로를
#     타므로 **여기에 사람을 기다리는 단계를 두면 안 된다**.
#
# 정글 방향을 묻는 자리가 여기인 것은 그 선택이 **전장을 보고 하는 선택**이기
# 때문이다. 예전에는 `features/match_flow/jungle_start/` 의 별도 화면이 전장을
# 보여 주지 않은 채 "← LEFT / RIGHT →" 두 버튼만 세웠다.

@onready var _bs: BattleSim = get_parent() as BattleSim


# Indexed by role (0..4). Returns LanePosition.
const ROLE_TO_LANE: Array = [
	GameEnums.LanePosition.LEFT,        # 0 TANK
	GameEnums.LanePosition.CENTER,      # 1 FIGHTER
	GameEnums.LanePosition.GUERRILLA,   # 2 ASSASSIN
	GameEnums.LanePosition.RIGHT,       # 3 SUPPORT
	GameEnums.LanePosition.RIGHT,       # 4 SNIPER
]


func auto_assign_lanes() -> void:
	# Fills _bs.gambit_lanes for the player team in role order (0..4).
	for i in range(5):
		_bs.gambit_lanes[i] = ROLE_TO_LANE[i]


## 전장을 세운다 — 파일럿 · 포탑 · 정글 소유 · 캠프. **개시(BATTLE)는 하지
## 않는다**: `field_ready` 만 세워 렌더러가 그리기 시작하게 하고, 그 다음
## 무엇을 할지는 `launch_battle()` 이 정한다.
func prepare_field() -> void:
	_bs.sim_core.spawn_pilots_with_lanes()
	_bs.sim_core.spawn_turrets()
	_bs.sim_core.init_neutral_zones()
	_bs.sim_core.init_jungle_camps()
	_bs.field_ready = true
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()


## 전장을 세우고, 정글 시작 방향을 물을 수 있으면 묻고, 아니면 곧장 개시한다.
func launch_battle() -> void:
	prepare_field()
	if _open_jungle_start():
		return
	begin_battle()


## 정글 시작 오버레이를 연다. 열렸으면 true — 그때 개시는 "전투 시작" 버튼이
## 돌아온 뒤로 미뤄진다.
func _open_jungle_start() -> bool:
	if not bool(_bs.gm.match_ctx.get("active", false)):
		return false
	if _bs.jungle_pick == null:
		_bs.jungle_pick = JungleStartOverlay.new()
		_bs.jungle_pick.name = "JungleStartOverlay"
		_bs.add_child(_bs.jungle_pick)
		_bs.jungle_pick.bind(_bs)
		_bs.jungle_pick.start_pressed.connect(_on_jungle_start_pressed)
	return _bs.jungle_pick.open()


func _on_jungle_start_pressed() -> void:
	var dir: int = _bs.jungle_pick.commit()
	# `match_ctx` 에도 적어 둔다 — 이 값을 읽는 자리가 스폰(이미 지났다) 말고도
	# 있고, 무엇보다 "이번 경기에 무엇을 골랐나"의 답이 한 군데에만 있어야 한다.
	_bs.gm.match_ctx["jungle_start_dir"] = dir
	begin_battle()


## 실제 개시. 여기서만 `game_phase` 가 BATTLE 이 된다.
func begin_battle() -> void:
	_bs.game_phase = GameEnums.BattlePhase.BATTLE
	_bs.renderer.queue_redraw()
	_bs.hud.update_hud()
