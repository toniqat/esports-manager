class_name MatchPrepView
extends Control

# PREP 화면 한 장 — 흰 아웃게임 종이, 가운데 제목, 세로 스크롤(분석 메모 → 상대 팀 카드 →
# 가운데 대진 블록 `내 팀 로고 · 약칭  VS  상대 약칭 · 로고` → 내 팀 카드), 하단 바 `경기 시작`.
# `MatchPrepController` 가 만들고(`create()`) 채운다(`fill()`).
#
# **레이아웃의 정본은 `UI_View_MatchPrepView.tscn` 이다.** 이 스크립트가 하는 일:
#   • 안전 영역 — `%Safe` 를 노치만큼 내린다(`Paper` 는 화면 전체를 덮으므로 노치 띠를
#     따로 메울 필요가 없다). 아래쪽은 `OutgameTheme.fit_bottom_bar(%Start, %Safe)` 가 맡는다 —
#     `%Safe` 를 아래 인셋만큼 올리고, 하단 바(`BarPrimaryButton`, 모서리 0 은 변형 몫)는
#     인셋 자리까지 내려가 그 높이만큼 아래 여백을 갖는다(기기 값이라 변형이 아니라 코드).
#   • 상대 팀 분석 메모 — `%IntelView_EnemyIntel` 은 `IntelView` 씬 인스턴스(리그 팀 상세와 공용)를
#     `show_rows = false` · `show_header = false` 로 둔 것: 분석 메모(분석가 썸네일)만 보인다.
#   • 대진 블록 — 두 팀 로고(`TeamLogos`) · 약칭(`GameManager.team_short_name`).
#   • 카드 줄 배너 — `%OwnBanner` / `%EnemyBanner`(`TeamBanner`) 를 팀 상징색(`TeamLogos.color`)으로.
#   • 두 팀의 선수 — `%EnemyCards` / `%OwnCards` 의 `MatchPrepPilotCard` 다섯 장(자리 순서)을
#     `OpponentIntel.build()` 의 행으로 채운다(공개 단계는 그 행이 이미 지킨다). 카드를 누르면
#     상세 시트: 내 선수 = `SeasonPilotDetail`, 상대(또는 런 밖의 내 선수) = `MatchPrepPilotDetail`.

signal start_pressed

const SCENE_PATH: String = "res://features/match_flow/match_prep/UI_View_MatchPrepView.tscn"

var _state: Dictionary = {}
## pilot_id → [intel (`OpponentIntel.build()`), row] of the card last filled — the detail sheet
## shows exactly what that card's reveal tier allows.
var _shown: Dictionary = {}


static func create() -> MatchPrepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MatchPrepView


func _ready() -> void:
	var safe: Control = %Safe
	safe.offset_top = ScreenMetrics.top_y()
	var start: Button = %Start
	OutgameTheme.fit_bottom_bar(start, safe)
	start.pressed.connect(func() -> void: start_pressed.emit())
	DragScroll.attach(%Scroll)
	for box in [%EnemyCards, %OwnCards]:
		for c in (box as Node).get_children():
			(c as MatchPrepPilotCard).pressed.connect(_on_card_pressed)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Relabels the bottom bar (Saturday prep: "밴픽 시작" instead of the scene's "경기 시작").
func set_start_text(text: String) -> void:
	var start: Button = %Start
	start.text = text


## `enemy_team_id` = the opponent (its analysis rank sets the reveal tier); -1 = read it from
## `enemy_roster`.
func fill(state: Dictionary, player_roster: Array, enemy_roster: Array,
		player_team_name: String, enemy_team_name: String, enemy_team_id: int = -1) -> void:
	_state = state
	_shown.clear()
	var enemy: Dictionary = OpponentIntel.build(state, enemy_roster, false, enemy_team_id)
	var own: Dictionary = OpponentIntel.build(state, player_roster, true)
	(%IntelView_EnemyIntel as IntelView).show_intel(enemy)
	_fill_cards(%EnemyCards, enemy)
	_fill_cards(%OwnCards, own)
	_fill_versus(%OwnLogo, %OwnAbbr, int(own["team_id"]), player_team_name)
	_fill_versus(%EnemyLogo, %EnemyAbbr, int(enemy["team_id"]), enemy_team_name)
	_fill_banner(%OwnBanner, int(own["team_id"]))
	_fill_banner(%EnemyBanner, int(enemy["team_id"]))


## Card-row banner in the team's signature colour; no team id → the scene's colour stays.
func _fill_banner(banner: TeamBanner, team_id: int) -> void:
	if team_id >= 0:
		banner.color = TeamLogos.color(team_id)


## One side of the versus block: the team logo and short name (`teams.csv` short_name_key);
## no team id (-1, MatchFlow without a season) → no logo and `fallback_name`.
func _fill_versus(logo: TextureRect, abbr: Label, team_id: int, fallback_name: String) -> void:
	logo.texture = TeamLogos.texture(team_id) if team_id >= 0 else null
	var gm: Node = get_node_or_null("/root/GameManager")
	abbr.text = String(gm.team_short_name(team_id)) if gm != null and team_id >= 0 else fallback_name


## Five cards of one team in seat order (the intel rows already are); missing pilots hide
## their card.
func _fill_cards(box: Node, intel: Dictionary) -> void:
	var rows: Array = intel["rows"]
	var own: bool = bool(intel["own"])
	var threat: int = int(intel.get("threat_pilot_id", -1))
	var cards: Array = box.get_children()
	for i in cards.size():
		var card := cards[i] as MatchPrepPilotCard
		card.visible = i < rows.size()
		if not card.visible:
			continue
		var row: Dictionary = rows[i]
		var pid: int = int(row["pilot_id"])
		card.fill(row, own, MentalSystem.trust(_state, pid) if own else 0, pid == threat)
		_shown[pid] = [intel, row]


func _on_card_pressed(pid: int) -> void:
	var entry: Array = _shown.get(pid, [])
	if entry.is_empty():
		return
	var intel: Dictionary = entry[0]
	if bool(intel["own"]) and MentalEvents.pilot_of(_state, pid) != null:
		SeasonPilotDetail.open(self, pid)
	else:
		MatchPrepPilotDetail.open(self, intel, entry[1])


## F6 단독 실행 미리보기 — 메모리 런(`UiPreview.ensure_run`)의 다음 경기 상대(미리보기 전용
## 리그 일정 `UiPreview.ensure_league`)와 내 팀 로스터로 채운다. 분석 단계는 그 상대의 런 속
## 분석 단계(`IntelResearch.rank`) 그대로다.
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
			lm.team_name(pid), lm.team_name(eid), eid)
