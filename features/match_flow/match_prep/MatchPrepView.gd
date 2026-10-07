class_name MatchPrepView
extends Control

# PREP 화면 한 장 — 흰 아웃게임 종이, 가운데 제목, 세로 스크롤(상대 팀 위 · 내 팀 아래),
# 하단 바 `경기 시작`. `MatchPrepController` 가 만들고(`create()`) 채운다(`fill()`).
#
# **레이아웃의 정본은 `UI_View_MatchPrepView.tscn` 이다.** 이 스크립트가 하는 일:
#   • 안전 영역 — `%Safe` 를 노치만큼 내린다(`Paper` 는 화면 전체를 덮으므로 노치 띠를
#     따로 메울 필요가 없다). 아래쪽은 `OutgameTheme.fit_bottom_bar(%Start, %Safe)` 가 맡는다 —
#     `%Safe` 를 아래 인셋만큼 올리고, 하단 바(`BarPrimaryButton`, 모서리 0 은 변형 몫)는
#     인셋 자리까지 내려가 그 높이만큼 아래 여백을 갖는다(기기 값이라 변형이 아니라 코드).
#   • 두 팀 구역의 내용 — `%IntelView_EnemyIntel` / `%IntelView_OwnIntel` 은 `IntelView` 씬 인스턴스(리그 팀
#     상세와 공용, 컨테이너라 높이는 내용대로)이고, 여기서는 `show_intel` 로 채우기만 한다.

signal start_pressed

const SCENE_PATH: String = "res://features/match_flow/match_prep/UI_View_MatchPrepView.tscn"


static func create() -> MatchPrepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MatchPrepView


func _ready() -> void:
	var safe: Control = %Safe
	safe.offset_top = ScreenMetrics.top_y()
	var start: Button = %Start
	OutgameTheme.fit_bottom_bar(start, safe)
	start.pressed.connect(func() -> void: start_pressed.emit())
	DragScroll.attach(%Scroll)
	if UiPreview.is_standalone(self):
		_fill_preview()


func fill(state: Dictionary, player_roster: Array, enemy_roster: Array,
		player_team_name: String, enemy_team_name: String) -> void:
	%Matchup.text = "%s  vs  %s" % [player_team_name, enemy_team_name]
	%EnemyTitle.text = Loc.t(L.MATCH_PREP_ENEMY_TITLE, {"team": enemy_team_name})
	%OwnTitle.text = Loc.t(L.MATCH_PREP_OWN_TITLE, {"team": player_team_name})
	(%IntelView_EnemyIntel as IntelView).show_intel(OpponentIntel.build(state, enemy_roster, false))
	(%IntelView_OwnIntel as IntelView).show_intel(OpponentIntel.build(state, player_roster, true))


## F6 단독 실행 미리보기 — 메모리 런(`UiPreview.ensure_run`)의 다음 경기 상대(미리보기 전용
## 리그 일정 `UiPreview.ensure_league`)와 내 팀 로스터로 채운다. 분석 단계는 런 그대로다.
## `경기 시작` 은 출력만 한다(호스트가 없어 다음 단계로 넘어가지 않는다).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(start_pressed)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var lm: LeagueManager = UiPreview.ensure_league(self, 0)
	var pid: int = int(s["player_team_id"])
	var eid: int = (pid + 1) % 8
	var m: Variant = lm.next_unplayed_player_match()
	if m != null:
		eid = int(m["team_b"]) if int(m["team_a"]) == pid else int(m["team_a"])
	fill(s, OpponentIntel.team_roster(s, pid), OpponentIntel.team_roster(s, eid),
			lm.team_name(pid), lm.team_name(eid))
