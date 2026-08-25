class_name GameOverView
extends Control

# Phase 7 — game-over screen. Shown when the player team failed to make the
# top-PLAYOFF_TEAMS cut on the final regular-season standings (and later in
# Phase 8, when an INTL run ends in elimination). Only action: restart the
# campaign (resets season_state and reloads Season.tscn).

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _reason_lbl: Label
var _summary_lbl: Label
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not _built:
		_build()
		_built = true
	refresh()


# Idempotent — SeasonHub calls this each time it routes to GAME_OVER.
func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	refresh()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 배경만은 안전 영역 밖(노치 자리)까지 덮는다 — 안 그러면 그 띠가
	# 엔진 기본 배경색으로 남는다.
	ScreenMetrics.extend_background(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "GAME OVER", 80, Color(1.0, 0.40, 0.40),
			Vector2(0, 600), Vector2(1080, 100), HORIZONTAL_ALIGNMENT_CENTER)

	_reason_lbl = UiHelpers.mk_label(self, "", 28, Color(0.95, 0.85, 0.85),
			Vector2(0, 740), Vector2(1080, 40), HORIZONTAL_ALIGNMENT_CENTER)
	_summary_lbl = UiHelpers.mk_label(self, "", 22, Color(0.75, 0.78, 0.85),
			Vector2(0, 800), Vector2(1080, 30), HORIZONTAL_ALIGNMENT_CENTER)

	var btn := Button.new()
	btn.text = "다시 시작"
	btn.position = Vector2((1080.0 - 760.0) / 2.0, 1500.0)
	btn.size     = Vector2(360, 110)
	btn.add_theme_font_size_override("font_size", 32)
	btn.pressed.connect(_on_restart_pressed)
	add_child(btn)

	var title_btn := Button.new()
	title_btn.text = "타이틀로"
	title_btn.position = Vector2((1080.0 - 760.0) / 2.0 + 400.0, 1500.0)
	title_btn.size     = Vector2(360, 110)
	title_btn.add_theme_font_size_override("font_size", 32)
	title_btn.pressed.connect(_on_title_pressed)
	add_child(title_btn)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	var s: Dictionary = _gm.season_state
	var phase: int = int(s["current_phase"])
	var phase_name: String = HubView.PHASE_NAMES.get(phase, "—")

	# Phase 8 REGULAR_INTL elimination has a different copy than Phase 7
	# playoff-miss. Detect by phase + whether an INTL bracket was active.
	var is_intl: bool = (phase == GameEnums.SeasonPhase.PRESEASON_INTL
			or phase == GameEnums.SeasonPhase.MIDSEASON_INTL
			or phase == GameEnums.SeasonPhase.REGULAR_INTL)
	if is_intl:
		_reason_lbl.text = "최종 국제대회에서 우승하지 못했습니다."
		_summary_lbl.text = _intl_summary_text()
	else:
		_reason_lbl.text = "%s 플레이오프 진출에 실패했습니다." % phase_name
		_summary_lbl.text = _league_rank_text()


func _league_rank_text() -> String:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var league: LeagueManager = null
	if _hub != null:
		league = _hub.get_node_or_null("LeagueManager") as LeagueManager
	if league == null:
		return ""
	var ranked: Array = league.standings_ranked()
	for i in ranked.size():
		if int(ranked[i]["team_id"]) == pid:
			var row: Dictionary = ranked[i]
			return "최종 순위 %d위 — %d승 %d패" % [
				i + 1, int(row["wins"]), int(row["losses"]),
			]
	return ""


func _intl_summary_text() -> String:
	var pr: Dictionary = _gm.season_state.get("phase_results", {})
	var wins: int = 0
	for k in pr.keys():
		var r: Dictionary = pr[k]
		if int(r.get("champion", -1)) == int(_gm.season_state["player_team_id"]):
			wins += 1
		if int(r.get("intl_champion", -1)) == int(_gm.season_state["player_team_id"]):
			wins += 1
	return "캠페인 우승 %d회 — 캠페인 종료" % wins


# ── Button handlers ─────────────────────────────────────────────────────────
func _on_restart_pressed() -> void:
	# In-place restart on the same save slot. The next DRAFT → HUB transition
	# auto-saves, overwriting the lost campaign in this slot.
	_gm.reset_season_state()
	get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_title_pressed() -> void:
	# Back to the title screen — lets the player switch slots or delete the
	# lost-campaign save before starting over.
	_gm.reset_season_state()
	_gm.active_save_slot = -1
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
