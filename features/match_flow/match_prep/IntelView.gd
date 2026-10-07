class_name IntelView
extends VBoxContainer

# Shows one team's `OpponentIntel.build()` result on white outgame paper. Shared by the
# MatchFlow PREP screen (`MatchPrepView` places two instances in its scroll) and the league
# team detail sheet (`features/season/league/LeagueTeamDetail`, a `HubSheet` body), so both
# read the same reveal rule the same way.
#
# **Layout lives in `UI_Comp_IntelView.tscn`** (+ one `UI_Comp_IntelPilotRow.tscn` per pilot): a VBox as wide as
# its parent and as tall as its content — tier header (opponents only) · analyst note
# (delegated) or the "no analyst" line · five rows. This script only fills `%` nodes, shows /
# hides the blocks, instances the rows, and paints the tier chip (full = `AccentChip`, below
# full = a `SURFACE_SUNK` copy of that box — a state colour, `OutgameTheme.variation_box`).

const SCENE_PATH: String = "res://features/match_flow/match_prep/UI_Comp_IntelView.tscn"
const ROW_SCENE: PackedScene = preload("res://features/match_flow/match_prep/UI_Comp_IntelPilotRow.tscn")

var _note_line: Label = null   # scene sample analyst line, duplicated per line


static func create() -> IntelView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as IntelView


func _ready() -> void:
	_clear(%Rows)   # scene sample = preview only
	var lines: Node = %Lines
	_note_line = lines.get_child(0) as Label
	lines.remove_child(_note_line)
	if UiPreview.is_standalone(self):
		_fill_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_note_line):
		_note_line.free()


## Fills the view with `intel` (`OpponentIntel.build()`). Can be called again.
func show_intel(intel: Dictionary) -> void:
	var own: bool = bool(intel.get("own", false))
	var delegated: bool = bool(intel.get("delegated", false))
	%Header.visible = not own
	%NoAnalyst.visible = not own and not delegated
	%Note.visible = not own and delegated
	if not own:
		_fill_header(intel)
	if not own and delegated:
		_fill_note(intel)
	var rows: Node = %Rows
	_clear(rows)
	for raw in (intel.get("rows", []) as Array):
		var row := ROW_SCENE.instantiate() as IntelPilotRow
		rows.add_child(row)
		row.fill(raw)


func _fill_header(intel: Dictionary) -> void:
	var tier: int = int(intel["tier"])
	var full: bool = tier >= OpponentIntel.FULL
	%TierText.text = "분석 %d단계 · %s" % [tier, intel["tier_label"]]
	%TierText.theme_type_variation = &"AccentLabel" if full else &"BodyLabel"
	var chip: PanelContainer = %TierChip
	if full:
		chip.remove_theme_stylebox_override(&"panel")
	else:
		var sb := OutgameTheme.variation_box(&"AccentChip")
		sb.bg_color = OutgameTheme.SURFACE_SUNK
		chip.add_theme_stylebox_override(&"panel", sb)
	%Need.visible = not full
	%Need.text = "내 분석 %d · 다음 단계 %d 필요" % [int(intel.get("analysis", 0)),
			int(intel.get("next_need", 0))]


func _fill_note(intel: Dictionary) -> void:
	%Analyst.text = "분석 · %s" % intel["analyst"]
	var lines: Node = %Lines
	_clear(lines)
	for raw in (intel.get("notes", []) as Array):
		var l := _note_line.duplicate() as Label
		l.text = UiHelpers.keep_words(String(raw))
		lines.add_child(l)


static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## F6 단독 실행 미리보기 — 메모리 런(`UiPreview.ensure_run`)의 다른 팀 하나를 런의 실제
## 분석 단계로 보여 준다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var eid: int = (int(s["player_team_id"]) + 1) % 8
	show_intel(OpponentIntel.build(s, OpponentIntel.team_roster(s, eid), false))
