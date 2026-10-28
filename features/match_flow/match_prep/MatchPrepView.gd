class_name MatchPrepView
extends Control

# PREP 화면 한 장 — 흰 아웃게임 종이, 가운데 제목, 세로 스크롤(분석 메모 → 상대 팀 카드 →
# 가운데 대진 블록 `내 팀 로고 · 약칭  VS  상대 약칭 · 로고` → 내 팀 카드), 하단 바 `경기 시작`.
# `MatchPrepController` 가 만들고(`create()`) 채운다(`fill()`).
#
# **레이아웃의 정본은 `UI_View_MatchPrepView.tscn` 이다.** 이 스크립트가 하는 일:
#   • 안전 영역 — `%Safe` 를 노치만큼 내린다(`Paper` 는 화면 전체를 덮으므로 노치 띠를
#     따로 메울 필요가 없다). 아래쪽은 `OutgameTheme.fit_bottom_bar(%FloatingBarButton_Start, %Safe)` 가 맡는다 —
#     lifts `%Safe` by the bottom inset and floats the start capsule (`BarPrimaryButton`)
#     32 px above the safe line, 40 px in from the sides.
#   • 상대 팀 분석 메모 — `%IntelView_EnemyIntel` 은 `IntelView` 씬 인스턴스(리그 팀 상세와 공용)를
#     `show_rows = false` · `show_header = false` 로 둔 것: 분석 메모(분석가 썸네일)만 보인다.
#   • 대진 블록 — 두 팀 로고(`TeamLogos`) · 약칭(`GameManager.team_short_name`).
#   • 카드 줄 배너 — `%OwnBanner` / `%EnemyBanner`(`TeamBanner`) 에 팀 배너 이미지(`TeamLogos.banner`),
#     없으면 팀 상징색(`TeamLogos.color`) 띠.
#   • 두 팀의 선수 — `%EnemyCards` / `%OwnCards` 의 `MatchPrepPilotCard` 다섯 장(자리 순서)을
#     `OpponentIntel.build()` 의 행으로 채운다(공개 단계는 그 행이 이미 지킨다). 카드를 누르면
#     상세 시트: 내 선수 = `SeasonPilotDetail`, 상대(또는 런 밖의 내 선수) = `MatchPrepPilotDetail`.
#   • 등장 연출 — `play_intro()`: 시즌에서 `SceneFade` 암전 뒤에 이 화면이 뜨고, 덮개가 걷히기
#     시작하면(`SceneFade.on_revealing`) 배너가 화면 밖에서 미끄러져 들어오고(내 팀 ← 왼쪽, 상대 ←
#     오른쪽), 로고 · 약칭이 같은 방향으로 서서히 나타나며 들어오고, 카드가 바깥에서 가운데 쪽으로
#     (상대 = 위에서 아래로, 내 팀 = 아래에서 위로) 한 장씩 나타난다.

signal start_pressed

const SCENE_PATH: String = "res://features/match_flow/match_prep/UI_View_MatchPrepView.tscn"

## Entrance (`play_intro`): every piece eases out (cubic) over `INTRO_SEC`; the start of each
## piece is its delay below. Slides are px from the resting spot.
const INTRO_SEC: float = 0.5
const INTRO_BANNER_DELAY: float = 0.0
const INTRO_LOGO_DELAY: float = 0.12
const INTRO_LOGO_SLIDE: float = 240.0
const INTRO_VS_DELAY: float = 0.3
const INTRO_CARD_DELAY: float = 0.2
const INTRO_CARD_STAGGER: float = 0.06   # between two cards of a row, seat order
const INTRO_CARD_SLIDE: float = 140.0

var _state: Dictionary = {}
## pilot_id → [intel (`OpponentIntel.build()`), row] of the card last filled — the detail sheet
## shows exactly what that card's reveal tier allows.
var _shown: Dictionary = {}


static func create() -> MatchPrepView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MatchPrepView


func _ready() -> void:
	var safe: Control = %Safe
	safe.offset_top = ScreenMetrics.top_y()
	var start: Button = %FloatingBarButton_Start
	OutgameTheme.fit_bottom_bar(start, safe)
	start.pressed.connect(func() -> void: start_pressed.emit())
	DragScroll.attach(%Scroll)
	for box in [%EnemyCards, %OwnCards]:
		for c in (box as Node).get_children():
			(c as MatchPrepPilotCard).pressed.connect(_on_card_pressed)
	if UiPreview.is_standalone(self):
		_fill_preview()


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


## Entrance animation. Hides the animated pieces now (nothing pops in before it starts) and plays
## when the scene-change cover starts to lift (`SceneFade.on_revealing`; no cover = next frame).
func play_intro() -> void:
	for c in _intro_nodes():
		(c as CanvasItem).modulate.a = 0.0
	SceneFade.on_revealing(get_tree(), _run_intro)


func _intro_nodes() -> Array:
	var out: Array = [%EnemyBanner, %OwnBanner, %OwnSide, %EnemySide, %VsText]
	out.append_array((%EnemyCards as Node).get_children())
	out.append_array((%OwnCards as Node).get_children())
	return out


func _run_intro() -> void:
	await get_tree().process_frame   # containers laid out → resting positions are final
	if not is_inside_tree():
		return
	var t := create_tween().set_parallel(true)
	for spec in [[%OwnBanner, -1.0], [%EnemyBanner, 1.0]]:
		var b: Control = spec[0]
		b.modulate.a = 1.0
		_slide_in(t, b, Vector2(float(spec[1]) * b.size.x, 0.0), INTRO_BANNER_DELAY, false)
	_slide_in(t, %OwnSide, Vector2(-INTRO_LOGO_SLIDE, 0.0), INTRO_LOGO_DELAY, true)
	_slide_in(t, %EnemySide, Vector2(INTRO_LOGO_SLIDE, 0.0), INTRO_LOGO_DELAY, true)
	_slide_in(t, %VsText, Vector2.ZERO, INTRO_VS_DELAY, true)
	for spec in [[%EnemyCards, -1.0], [%OwnCards, 1.0]]:
		var cards: Array = (spec[0] as Node).get_children()
		for i in cards.size():
			_slide_in(t, cards[i], Vector2(0.0, float(spec[1]) * INTRO_CARD_SLIDE),
					INTRO_CARD_DELAY + INTRO_CARD_STAGGER * i, true)


## Moves `c` to `offset` from its resting spot and tweens it back (cubic ease-out), fading in
## from 0 when `fade`.
func _slide_in(t: Tween, c: Control, offset: Vector2, delay: float, fade: bool) -> void:
	var home: Vector2 = c.position
	c.position = home + offset
	t.tween_property(c, "position", home, INTRO_SEC).set_delay(delay) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if fade:
		t.tween_property(c, "modulate:a", 1.0, INTRO_SEC).set_delay(delay)


## Card-row banner: the team's banner image (`TeamLogos.banner`, `teams.csv` banner_path) with its
## main colour as the fallback band; no team id → the scene's colour stays.
func _fill_banner(banner: TeamBanner, team_id: int) -> void:
	if team_id < 0:
		return
	banner.color = TeamLogos.color(team_id)
	banner.texture = TeamLogos.banner(team_id)


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
## `경기 시작` 은 출력만 한다(호스트가 없어 다음 단계로 넘어가지 않는다). 등장 연출도 돈다.
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
	play_intro()
