class_name HomeTab
extends Control

# 로비의 홈 탭 — 진행 중인 런 카드와 `새 런`(1) / `이어하기`(2) 행동 바.
# 런이 없으면 빈 상태 카드와 전폭 `새 런`. 탭 계약은 `LobbyScreen.gd` 머리말.
#
# **레이아웃 · 스타일의 정본은 `UI_View_HomeTab.tscn`** — 이 스크립트는 `%노드` 에 글을 넣고
# 런 카드 / 빈 카드 중 하나를 보일 뿐이다. 생성은 `HomeTab.create()`.
#
# `새 런` 을 누를 때 런이 이미 있으면 **포기 확인 모달**을 띄운다 — 확인하면 그 런을
# **포기로 정산**(`RunResult.settle_current_run("abandon")`, 실패 정산이지만 보상은
# 준다)하고 정산 화면으로 간다. 그 화면의 `새 런` 이 런 준비로 잇는다.

const PHASE_NAMES: Dictionary = HubView.PHASE_NAMES
const WEEKDAY_NAMES: Array = OutgameTheme.DAY_LETTERS
const RUN_SETUP_SCENE: String = "res://scenes/RunSetup.tscn"
const SCENE_PATH: String = "res://features/meta/lobby/UI_View_HomeTab.tscn"

var _host: LobbyScreen
var _gm: Node
var _pm: Node
var _has_run: bool = false
var _meta: Dictionary = {}


## 씬을 인스턴스한다. `HomeTab.new()` 는 빈 Control 이라 쓰지 않는다.
static func create() -> HomeTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HomeTab


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


func bar_specs() -> Array:
	# 런이 있으면 1:2 — 이어하기가 주 행동이라 오른쪽 3분의 2. 없으면 새 런이 전폭.
	if SaveSystem.has_run():
		return [
			{"text": "새 런",    "style": "ghost",   "font": 32, "weight": 1.0},
			{"text": "이어하기", "style": "primary", "font": 32, "weight": 2.0},
		]
	return [{"text": "새 런", "style": "primary", "font": 32, "weight": 1.0}]


func setup(host: LobbyScreen) -> void:
	_host = host
	_gm = get_node("/root/GameManager")
	_pm = get_node("/root/ProfileManager")
	_has_run = SaveSystem.has_run()
	_meta = SaveSystem.read_run_meta() if _has_run else {}
	_fill()


func on_shown() -> void:
	pass


func on_bar_pressed(i: int) -> void:
	if _has_run and i == 1:
		_on_continue_pressed()
	else:
		_on_new_run_pressed()


# ── Fill (레이아웃 · 스타일은 UI_View_HomeTab.tscn) ─────────────────────────────────────
func _fill() -> void:
	var mgr_lv: int = ManagerProgress.level_of(_pm.profile)
	%Summary.text = "감독 Lv%d · 보유 선수 %d명 · 특성 %d개" % [
			mgr_lv, (_pm.owned_pilot_ids() as Array).size(),
			(_pm.owned_trait_ids() as Array).size()]
	if _has_run and not _meta.is_empty():
		_show_run(_meta)
	else:
		%RunCard.visible = false
		%EmptyCard.visible = true


## 런 카드를 `meta`(`SaveSystem.read_run_meta()`)로 채우고 빈 카드를 숨긴다.
func _show_run(meta: Dictionary) -> void:
	%EmptyCard.visible = false
	%RunCard.visible = true
	%Phase.text = String(PHASE_NAMES.get(int(meta.get("phase", 0)), "—"))
	%LiveChip.visible = bool(meta.get("match_in_progress", false))
	%Date.text = "%d년 %d월 %d일 (%s)" % [
			int(meta.get("year", 1)), int(meta.get("month", 12)),
			int(meta.get("day", 1)), _weekday_name(int(meta.get("weekday", 0)))]
	%Team.text = String(meta.get("team_name", "—"))
	%Trophies.text = "우승 트로피 %d개" % int(meta.get("trophies", 0))
	var rank: int = int(meta.get("rank", 0))
	var record: String = "리그 미시작"
	if rank > 0:
		record = "현재 리그 %d위 (%d승 %d패)" % [
			rank, int(meta.get("wins", 0)), int(meta.get("losses", 0))]
	%Record.text = record
	%SavedAt.text = "마지막 저장 " + String(meta.get("saved_at", ""))


func _weekday_name(wd: int) -> String:
	if wd >= 0 and wd < WEEKDAY_NAMES.size():
		return String(WEEKDAY_NAMES[wd])
	return "?"


# ── Actions ──────────────────────────────────────────────────────────────────
func _on_continue_pressed() -> void:
	var err: String = SaveSystem.load_run()
	if err != "":
		_host.show_toast("불러오기 실패: " + err, true)
		return
	# Mid-match save: jump straight back into MatchFlow (which reads
	# season_state.match_resume on _ready and skips ahead to the saved phase).
	if _gm.season_state.get("match_resume", null) != null:
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_new_run_pressed() -> void:
	if not _has_run:
		_start_new_run()
		return
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm("진행 중인 런을 포기할까요?",
			"지금까지의 진척으로 실패 정산하고 런을 끝냅니다.\n점수 · 재화 보상은 받지만 런은 되돌릴 수 없습니다.",
			"취소", "포기하고 정산", true, _on_abandon_confirmed)


func _on_abandon_confirmed() -> void:
	# 포기 = 그 시점 진척으로 실패 정산(계획서 §10.3) — 셀 수 있게 런을 먼저 싣는다.
	var lerr: String = SaveSystem.load_run()
	if lerr == "":
		Haptics.play(Haptics.Kind.ERROR)
		RunResult.settle_current_run(RunResult.OUTCOME_ABANDON)
		get_tree().change_scene_to_file(RunResult.SCENE_PATH)
		return
	# 깨진 런 — 정산할 것이 없다. 지우고 새 런으로.
	push_warning("Lobby: abandon could not load run (%s) — deleting without settlement" % lerr)
	var err: String = SaveSystem.delete_run()
	if err != "":
		_host.show_toast("런 삭제 실패: " + err, true)
		return
	Haptics.play(Haptics.Kind.ERROR)
	_start_new_run()


func _start_new_run() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(RUN_SETUP_SCENE)


## F6 단독 실행 미리보기 — 메모리 런(몇 주 치른 리그)의 런 카드 (`resources/UiPreview.gd`).
## 런 파일은 읽지도 쓰지도 않는다: 메타는 `SaveSystem` 의 런 메타와 같은 칸을 메모리 런에서
## 채운다. 행동 바는 호스트(`LobbyScreen`) 몫이라 없다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	_pm = get_node("/root/ProfileManager")
	_gm = UiPreview.ensure_run()
	if _gm == null:
		_fill()
		return
	var lm: LeagueManager = UiPreview.ensure_league(self, 3)
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var rank: int = 0
	var wins: int = 0
	var losses: int = 0
	var ranked: Array = lm.standings_ranked()
	for i in ranked.size():
		if int(ranked[i]["team_id"]) == pid:
			rank = i + 1
			wins = int(ranked[i]["wins"])
			losses = int(ranked[i]["losses"])
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	_has_run = true
	_meta = {
		"phase": int(s.get("current_phase", 0)), "year": int(s.get("year", 1)),
		"month": int(s.get("month", 12)), "day": int(s.get("day", 1)),
		"weekday": int(s.get("weekday", 0)), "team_name": lm.team_name(pid),
		"trophies": 1, "rank": rank, "wins": wins, "losses": losses,
		"saved_at": "%04d-%02d-%02d %02d:%02d" % [dt["year"], dt["month"], dt["day"],
				dt["hour"], dt["minute"]],
		"match_in_progress": true,
	}
	_fill()
