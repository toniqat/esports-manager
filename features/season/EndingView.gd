class_name EndingView
extends Control

# Phase 8 — campaign-ending screen. Reached when the player wins
# REGULAR_INTL. Shows a "WORLD CHAMPION" banner, a 6-event recap of every
# phase result (league playoff + INTL champion), and the final 5-pilot
# roster. "다시 시작" wipes season_state and reloads Season.tscn.

const PHASE_ORDER: Array = [
	GameEnums.SeasonPhase.PRESEASON,
	GameEnums.SeasonPhase.PRESEASON_INTL,
	GameEnums.SeasonPhase.MIDSEASON,
	GameEnums.SeasonPhase.MIDSEASON_INTL,
	GameEnums.SeasonPhase.REGULAR,
	GameEnums.SeasonPhase.REGULAR_INTL,
]
const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _phase_lines: Array = []   # 6 Labels
var _roster_lines: Array = []  # 5 Labels
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not _built:
		_build()
		_built = true
	refresh()


func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	refresh()
	# 우승. 캠페인 전체가 여기로 오려고 굴러왔다.
	Haptics.play(Haptics.Kind.SUCCESS)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(self)
	var bg := ColorRect.new()
	bg.color = OutgameTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 배경만은 안전 영역 밖(노치 자리)까지 덮는다 — 안 그러면 그 띠가
	# 엔진 기본 배경색으로 남는다.
	ScreenMetrics.extend_background(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "WORLD CHAMPION", 72, OutgameTheme.ACCENT_TEXT,
			Vector2(0, 140), Vector2(1080, 96), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(self, "캠페인 완주 — 정규시즌 국제대회 우승!", 26, OutgameTheme.TEXT,
			Vector2(0, 244), Vector2(1080, 36), HORIZONTAL_ALIGNMENT_CENTER)

	# Section: campaign recap (6 events).
	UiHelpers.mk_label(self, "── 캠페인 기록 ──", 24, OutgameTheme.TEXT_SUB,
			Vector2(0, 340), Vector2(1080, 32), HORIZONTAL_ALIGNMENT_CENTER)
	for i in PHASE_ORDER.size():
		var lbl := UiHelpers.mk_label(self, "", 22, OutgameTheme.TEXT_SUB,
				Vector2(140, 390 + i * 40), Vector2(800, 32),
				HORIZONTAL_ALIGNMENT_LEFT)
		_phase_lines.append(lbl)

	# Section: final roster.
	UiHelpers.mk_label(self, "── 최종 로스터 ──", 24, OutgameTheme.TEXT_SUB,
			Vector2(0, 670), Vector2(1080, 32), HORIZONTAL_ALIGNMENT_CENTER)
	for i in 5:
		var lbl := UiHelpers.mk_label(self, "", 22, OutgameTheme.TEXT,
				Vector2(140, 720 + i * 40), Vector2(800, 32),
				HORIZONTAL_ALIGNMENT_LEFT)
		_roster_lines.append(lbl)

	# **하단 구간을 둘이 2:1 로 나눠 갖는다** — 다시 시작이 주 행동이라 오른쪽
	# 3분의 2, 타이틀로 나가는 길이 왼쪽 3분의 1이다(`OutgameTheme.add_bottom_bar`).
	var bar: Array = OutgameTheme.add_bottom_bar(self, [
		{"text": "타이틀로",  "style": "ghost",   "font": 32, "weight": 1.0},
		{"text": "다시 시작", "style": "primary", "font": 32, "weight": 2.0},
	])
	(bar[0] as Button).pressed.connect(_on_title_pressed)
	(bar[1] as Button).pressed.connect(_on_restart_pressed)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	_refresh_recap()
	_refresh_roster()


func _refresh_recap() -> void:
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var pr: Dictionary = s.get("phase_results", {})
	var league: LeagueManager = null
	var intl: InternationalTournament = null
	if _hub != null:
		league = _hub.get_node_or_null("LeagueManager") as LeagueManager
		intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament
	for i in PHASE_ORDER.size():
		var phase: int = int(PHASE_ORDER[i])
		var phase_name: String = HubView.PHASE_NAMES.get(phase, "—")
		var entry: Dictionary = pr.get(phase, {})
		var line: String = phase_name
		if _is_intl_phase(phase):
			# INTL phases are stored under their own enum key with intl_champion.
			var champ: int = int(entry.get("intl_champion", -1))
			line += "  —  " + _format_winner(champ, pid, league, intl)
		else:
			var champ_p: int = int(entry.get("champion", -1))
			line += "  —  " + _format_winner(champ_p, pid, league, intl)
		_phase_lines[i].text = line
		var color: Color = OutgameTheme.TEXT
		if _phase_won_by_player(phase, entry, pid):
			color = OutgameTheme.ACCENT_TEXT
		_phase_lines[i].add_theme_color_override("font_color", color)


func _is_intl_phase(phase: int) -> bool:
	return phase == GameEnums.SeasonPhase.PRESEASON_INTL \
		or phase == GameEnums.SeasonPhase.MIDSEASON_INTL \
		or phase == GameEnums.SeasonPhase.REGULAR_INTL


func _phase_won_by_player(phase: int, entry: Dictionary, pid: int) -> bool:
	if _is_intl_phase(phase):
		return int(entry.get("intl_champion", -1)) == pid
	return int(entry.get("champion", -1)) == pid


func _format_winner(team_id: int, pid: int, league: LeagueManager, intl: InternationalTournament) -> String:
	if team_id < 0:
		return "기록 없음"
	var team_label: String = "Team %d" % team_id
	if team_id >= 100 and intl != null:
		team_label = intl.team_name(team_id)
	elif league != null:
		team_label = league.team_name(team_id)
	if team_id == pid:
		return "우승 — %s ★" % team_label
	return "우승 — %s" % team_label


func _refresh_roster() -> void:
	var s: Dictionary = _gm.season_state
	var pool: Array = s.get("all_pilots", [])
	var pid: int = int(s["player_team_id"])
	var by_role: Dictionary = {}
	for raw in pool:
		var p := raw as PlayerData
		if p.team_id == pid:
			by_role[int(p.role)] = p
	# 줄 순서는 화면 순서(탑 · 정글 · 미드 · 원딜 · 서폿) — `_roster_lines` 도
	# 그 순서로 세워져 있다.
	for seat in 5:
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		if by_role.has(r):
			var p: PlayerData = by_role[r]
			var total: int = p.stat_total()
			_roster_lines[seat].text = "%-9s  %-14s  TOTAL %d" % [
				ROLE_NAMES[r], p.name, total,
			]
		else:
			_roster_lines[seat].text = "%s  —" % ROLE_NAMES[r]


func _on_restart_pressed() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_title_pressed() -> void:
	_gm.reset_season_state()
	_gm.active_save_slot = -1
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
