class_name MatchPrepView
extends Control

# PREP 화면 한 장 — 흰 아웃게임 종이, 가운데 제목, 세로 스크롤(상대 팀 위 · 내 팀 아래),
# 하단 바 `경기 시작`. `MatchPrepController` 가 만들고(`create()`) 채운다(`fill()`).
#
# **레이아웃의 정본은 `MatchPrepView.tscn` 이다.** 이 스크립트가 하는 일:
#   • 안전 영역 — `%Safe` 를 노치만큼 내린다(`Paper` 는 화면 전체를 덮으므로 노치 띠를
#     따로 메울 필요가 없다). 아래쪽은 `OutgameTheme.fit_bottom_bar(%Start, %Safe)` 가 맡는다 —
#     `%Safe` 를 아래 인셋만큼 올리고, 하단 바(`BarPrimaryButton`, 모서리 0 은 변형 몫)는
#     인셋 자리까지 내려가 그 높이만큼 아래 여백을 갖는다(기기 값이라 변형이 아니라 코드).
#   • 두 팀 구역의 내용 — `IntelView`(리그 팀 상세와 공용, 절대 좌표 그리기)가
#     `%EnemyIntel` / `%OwnIntel` 자리에 그리고, 쓴 높이를 그 자리의 최소 높이로 준다.

signal start_pressed

const SCENE_PATH: String = "res://features/match_flow/match_prep/MatchPrepView.tscn"
## 행이 스크롤 막대 자리를 비워 두는 폭.
const SCROLLBAR_ROOM: float = 16.0


static func create() -> MatchPrepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MatchPrepView


func _ready() -> void:
	var safe: Control = %Safe
	safe.offset_top = ScreenMetrics.top_y()
	var start: Button = %Start
	OutgameTheme.fit_bottom_bar(start, safe)
	start.pressed.connect(func() -> void: start_pressed.emit())
	DragScroll.attach(%Scroll)


## 트리에 들어간 **뒤에** 부른다(행 폭이 화면 폭에서 나온다).
func fill(state: Dictionary, player_roster: Array, enemy_roster: Array,
		player_team_name: String, enemy_team_name: String) -> void:
	%Matchup.text = "%s  vs  %s" % [player_team_name, enemy_team_name]
	%EnemyTitle.text = "상대 팀 · %s" % enemy_team_name
	%OwnTitle.text = "내 팀 · %s" % player_team_name
	var scroll: Control = %Scroll
	var w: float = ScreenMetrics.vp_w() - scroll.offset_left + scroll.offset_right \
			- SCROLLBAR_ROOM
	_draw_intel(%EnemyIntel, w, OpponentIntel.build(state, enemy_roster, false))
	_draw_intel(%OwnIntel, w, OpponentIntel.build(state, player_roster, true))


func _draw_intel(holder: Control, w: float, intel: Dictionary) -> void:
	var y: float = 0.0
	y += IntelView.add_tier_header(holder, Vector2(0, y), w, intel)
	y += IntelView.add_analyst_note(holder, Vector2(0, y), w, intel)
	y += IntelView.add_rows(holder, Vector2(0, y), w, intel)
	holder.custom_minimum_size.y = y
