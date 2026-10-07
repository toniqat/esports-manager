class_name HubSheet
extends CanvasLayer

# The **shared detail sheet** opened by the hub manage cards (staff · mech research · finance)
# and the standings team detail. Dims the whole screen and shows one white card inside the
# safe area (title · vertically scrolling body · bottom `닫기`). Same pattern as
# `meta/lobby/ConfirmPopup.gd`.
#
# **The frame's layout lives in `UI_View_HubSheet.tscn`** (card size / margins, title, divider,
# scroll, close button — edit them in the editor). Styles come from the shared theme on
# `Root` (`resources/OutgameTheme.tres`: `PopupCard` · `TitleLabel` · `Divider` ·
# `GhostButton` · `DimPanel`). This script only binds `%` nodes, puts the title in, wires
# close, and offsets `%SafeArea` by the device's safe-area insets.
#
# **The body is filled by the caller.** Every body is a scene — the hub panels (`FinancePanel` ·
# `StaffPanel` · `MasteryPanel`) and the standings team detail (`league/LeagueTeamDetail`):
# the caller adds one instance under `body` (top-wide) and it reports its own height
# (`set_body_height(size.y)` on `resized`).
#
# Usage (a panel scene's `open(host)`):
#   var sheet := HubSheet.open_on(host, "스태프")
#   var panel := create()                   # the panel's own scene
#   sheet.body.add_child(panel)             # the panel calls sheet.set_body_height(size.y)
#   sheet.closed.connect(...)               # on close
#
# `HubView` already connects `closed` to its `refresh()`, so panels that change state
# inside the sheet don't need to call the hub themselves. A sheet is one-shot: `close()`
# frees it, the next `open_on` instantiates a fresh one.

signal closed

const SCENE_PATH: String = "res://features/season/UI_View_HubSheet.tscn"

## Scroll content root — callers add one top-wide body scene here.
var body: Control = null


## Instantiates the scene. `HubSheet.new()` is an empty CanvasLayer — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> HubSheet:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HubSheet


## Opens a sheet under `host` and returns it.
static func open_on(host: Node, title: String) -> HubSheet:
	var sheet := create()
	host.add_child(sheet)
	sheet._open(title)
	return sheet


func _ready() -> void:
	body = %Body
	%Dim.pressed.connect(close)
	%Close.pressed.connect(close)
	# Drag / fling scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(%Scroll)
	# A press on the card must not fall through to the dim — `%Card` is STOP in the scene.
	if UiPreview.is_standalone(self):
		_fill_preview()


## Body width (inside the scroll) = card width minus the `%Pad` side margins. Valid right
## after `open_on` — the card is anchor-sized, not container-sized, so no layout pass is needed.
func body_w() -> float:
	var pad: MarginContainer = %Pad
	return (%Card as Control).size.x - float(pad.get_theme_constant(&"margin_left")) \
			- float(pad.get_theme_constant(&"margin_right"))


## Tells the scroll how tall the body is.
func set_body_height(h: float) -> void:
	if body != null:
		body.custom_minimum_size.y = h


## The card itself, for callers that need fixed controls outside the scroll
## (card-local coordinates). Callers create those controls.
func card() -> Panel:
	return %Card


func close() -> void:
	if is_queued_for_deletion():
		return
	visible = false
	closed.emit()
	queue_free()


func _open(title: String) -> void:
	%Title.text = title
	_fit_safe_area()


## `%SafeArea` is the full screen shrunk to the safe area; the card's own top / bottom
## gaps inside it are scene offsets.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## F6 단독 실행 미리보기 — 메모리 런의 내 팀 상세(순위표 팀 상세와 같은 본문
## `LeagueTeamDetail`)를 띄운다 (`resources/UiPreview.gd`). "닫기" · 바깥 누름은 시트를 지운다(빈 화면이 남는다).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(closed)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	var tid: int = int(state["player_team_id"])
	_open("%s  (%s)" % [String(gm.team_name(tid)), String(gm.team_short_name(tid))])
	var table: Dictionary = state.get("league_standings", {})
	var rec: Dictionary = table.get(tid, table.get(str(tid), {}))
	var detail := LeagueTeamDetail.create()
	body.add_child(detail)
	detail.bind(self, Loc.t(L.SEASON_LEAGUE_RECORD_MINE,
			{"win": int(rec.get("wins", 0)), "loss": int(rec.get("losses", 0))}),
			OpponentIntel.build(state, OpponentIntel.team_roster(state, tid), true))
