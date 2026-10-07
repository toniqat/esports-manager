class_name EndingView
extends Control

# Phase 8 — campaign-ending screen. Reached when the player wins
# REGULAR_INTL. Shows a "WORLD CHAMPION" banner, a 6-event recap of every
# phase result (league playoff + INTL champion), and the final 5-pilot
# roster. SeasonHub settles the run (RunResult, outcome "clear") before this
# screen shows, so run.save is already gone. Only action: `정산` → RunResult.tscn.
#
# **Layout lives in `UI_View_EndingView.tscn`** (banner, recap / roster line lists, bottom bar). This
# script binds `%` nodes, fills the lines (recap line colour = won by the player, data), and
# applies the safe-area offsets (pattern B). Create with `EndingView.create()`.

const SCENE_PATH: String = "res://features/season/UI_View_EndingView.tscn"

const PHASE_ORDER: Array = [
	GameEnums.SeasonPhase.PRESEASON,
	GameEnums.SeasonPhase.PRESEASON_INTL,
	GameEnums.SeasonPhase.MIDSEASON,
	GameEnums.SeasonPhase.MIDSEASON_INTL,
	GameEnums.SeasonPhase.REGULAR,
	GameEnums.SeasonPhase.REGULAR_INTL,
]

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

var _phase_lines: Array = []   # 6 Labels (scene `%Recap`, PHASE_ORDER order)
var _roster_lines: Array = []  # 5 rows (scene `%Roster`, seat order) — `Badge` (PositionBadge) + `Text`
var _built: bool = false
# 팀 이름을 읽는 매니저 — 실제 게임은 `_hub` 의 것을 매번 다시 읽는다(`_resolve_refs`).
# 호스트가 없는 F6 미리보기만 직접 넣는다.
var _league: LeagueManager = null
var _intl: InternationalTournament = null


## Instantiates the scene. `EndingView.new()` is an empty Control — don't use it.
static func create() -> EndingView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as EndingView


func _ready() -> void:
	_bind()
	if UiPreview.is_standalone(self):
		_fill_preview()
	refresh()


func ensure_view() -> void:
	_bind()
	refresh()
	# 우승. 캠페인 전체가 여기로 오려고 굴러왔다.
	Haptics.play(Haptics.Kind.SUCCESS)


# ── Bind ─────────────────────────────────────────────────────────────────────
func _bind() -> void:
	if _built:
		return
	_built = true
	# 화면 전체를 안전 영역 위끝까지 내리고, 배경만 노치 자리까지 다시 덮는다.
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	OutgameTheme.fit_bottom_bar(%BottomBar, %SafeBottom)
	_phase_lines = %Recap.get_children()
	_roster_lines = %Roster.get_children()
	# 갈 길은 하나 — 정산 화면.
	%Settle.pressed.connect(_on_settle_pressed)


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
	_resolve_refs()
	var league: LeagueManager = _league
	var intl: InternationalTournament = _intl
	for i in mini(PHASE_ORDER.size(), _phase_lines.size()):
		var phase: int = int(PHASE_ORDER[i])
		var phase_name: String = GameEnums.phase_label(phase)
		var entry: Dictionary = pr.get(phase, {})
		var line: String = phase_name
		if _is_intl_phase(phase):
			# INTL phases are stored under their own enum key with intl_champion.
			var champ: int = int(entry.get("intl_champion", -1))
			line = "%s  —  %s" % [phase_name, _format_winner(champ, pid, league, intl)]
		else:
			var champ_p: int = int(entry.get("champion", -1))
			line = "%s  —  %s" % [phase_name, _format_winner(champ_p, pid, league, intl)]
		_phase_lines[i].text = line
		var color: Color = OutgameTheme.TEXT
		if _phase_won_by_player(phase, entry, pid):
			color = OutgameTheme.ACCENT_TEXT
		_phase_lines[i].add_theme_color_override("font_color", color)


func _resolve_refs() -> void:
	if _hub == null:
		return
	_league = _hub.get_node_or_null("LeagueManager") as LeagueManager
	_intl = _hub.get_node_or_null("InternationalTournament") as InternationalTournament


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
		return Loc.t(L.UI_WORD_NO_RECORD)
	var team_label: String = "Team %d" % team_id
	if team_id >= 100 and intl != null:
		team_label = intl.team_name(team_id)
	elif league != null:
		team_label = league.team_name(team_id)
	if team_id == pid:
		return Loc.t(L.SEASON_ENDING_CHAMPION_MINE, {"team": team_label})
	return Loc.t(L.SEASON_ENDING_CHAMPION, {"team": team_label})


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
	for seat in mini(5, _roster_lines.size()):
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var line: Node = _roster_lines[seat]
		(line.get_node("PositionBadge_Badge") as PositionBadge).set_role(r)
		if by_role.has(r):
			var p: PlayerData = by_role[r]
			var total: int = p.stat_total()
			(line.get_node("Text") as Label).text = "%-14s  TOTAL %d" % [p.name, total]
		else:
			(line.get_node("Text") as Label).text = "—"


# 정산(프로필 반영 · run.save 삭제)은 SeasonHub 가 이 화면에 들어서며 이미 했다.
# 여기서는 결과 화면으로 넘어가기만 한다.
func _on_settle_pressed() -> void:
	get_tree().change_scene_to_file(RunResult.SCENE_PATH)


## F6 단독 실행 미리보기 — 메모리 런으로 여섯 대회를 전부 우리 팀이 우승한 기록을 깐다
## (`resources/UiPreview.gd`). 정산(`RunResult.settle_current_run`)은 부르지 않는다 — 실제로도
## SeasonHub 가 이 화면 **전에** 하는 일이다. "정산" 버튼은 장면을 넘기지 않고 출력만 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	if UiPreview.ensure_run() == null:
		return
	_league = UiPreview.ensure_league(self, 0)
	_intl = InternationalTournament.new()
	_intl.name = "PreviewIntl"
	add_child(_intl)
	var s: Dictionary = _gm.season_state
	var pid: int = int(s["player_team_id"])
	var pr: Dictionary = {}
	for phase in PHASE_ORDER:
		if _is_intl_phase(int(phase)):
			pr[int(phase)] = {"intl_played": true, "intl_champion": pid}
		else:
			pr[int(phase)] = {"made_playoffs": true, "champion": pid}
	s["phase_results"] = pr
	s["current_phase"] = GameEnums.SeasonPhase.REGULAR_INTL
	%Settle.pressed.disconnect(_on_settle_pressed)
	UiPreview.trace(%Settle.pressed, "정산")  # l10n-ignore
