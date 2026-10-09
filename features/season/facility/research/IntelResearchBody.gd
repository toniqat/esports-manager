class_name IntelResearchBody
extends VBoxContainer

# Intel facility sheet section (`IntelResearch.make_body`): every team of the competition I play
# in now (`IntelResearch.field`, next opponent first) with its analysis rank and the reveal it buys
# (`OpponentIntel.TIER_LABELS`); the next opponent's row carries the `다음 상대` chip.
#
# **Layout lives in `UI_Comp_IntelResearchBody.tscn`**: caption · `%Rows` with one sample `Row`
# (Card panel: team name · next chip · tier label · rank). The sample is taken out on first use
# and duplicated per team; the script only fills texts and shows the chip.

const SCENE_PATH: String = "res://features/season/facility/research/UI_Comp_IntelResearchBody.tscn"

var _sample: Control = null   # scene sample row, duplicated per team


static func create() -> IntelResearchBody:
	return (load(SCENE_PATH) as PackedScene).instantiate() as IntelResearchBody


func _ready() -> void:
	_take_sample()
	if UiPreview.is_standalone(self):
		_fill_preview()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_sample):
		_sample.free()


## Fills the list from the run state. Can be called before `_ready` and again later.
func fill(state: Dictionary) -> void:
	_take_sample()
	%Caption.text = Loc.t(L.RESEARCH_INTEL_BODY_CAPTION)
	var rows: Node = %Rows
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var next_id: int = IntelResearch.next_opponent(state)
	for raw in IntelResearch.field(state):
		var tid: int = int(raw)
		var r: int = IntelResearch.rank(state, tid)
		var row := _sample.duplicate() as Control
		rows.add_child(row)
		(row.get_node("Pad/Line/Team") as Label).text = "%s  (%s)" % [
				IntelResearch.team_full(tid), IntelResearch.team_short(tid)]
		(row.get_node("Pad/Line/NextChip") as Control).visible = tid == next_id
		(row.get_node("Pad/Line/NextChip/NextText") as Label).text = Loc.t(L.RESEARCH_INTEL_BODY_NEXT)
		(row.get_node("Pad/Line/Tier") as Label).text = \
				Loc.t(String(OpponentIntel.TIER_LABELS[OpponentIntel.tier_for(state, tid)]))  # l10n-dynamic: match.intel.tier.*
		var rank_label := row.get_node("Pad/Line/Rank") as Label
		rank_label.text = Loc.t(L.RESEARCH_INTEL_BODY_RANK, {"rank": r, "max": IntelResearch.MAX_RANK})
		rank_label.theme_type_variation = &"AccentLabel" if r >= IntelResearch.MAX_RANK else &"BodyLabel"


func _take_sample() -> void:
	if _sample != null:
		return
	var rows: Node = %Rows
	_sample = rows.get_child(0) as Control
	rows.remove_child(_sample)


## F6 단독 실행 미리보기 — 메모리 런 + 미리보기 리그 일정(다음 상대 표시), 몇 팀에 분석 단계를 줘 본다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	UiPreview.ensure_league(self, 0)
	var s: Dictionary = gm.season_state
	var pid: int = int(s["player_team_id"])
	var ranks: Dictionary = {}
	for i in 3:
		ranks[str((pid + 2 + i) % 8)] = i + 1
	s["intel_rank"] = ranks
	fill(s)
