class_name TrainingResearchBody
extends VBoxContainer

# Training facility sheet section (`TrainingResearch.make_body`, §16): the occupant's
# training stat → the EXP multiplier of this facility's courses (the same value
# `TrainingBoard.exp_mult_table` uses for their cells), then one
# `UI_Comp_TrainingResearchLine` per course line the facility researches — its name,
# what the run owns of it, and its ladder (`<grade> Lv<facility level>` per row).
# Layout is the scene; this script binds `%` nodes and fills data.

const SCENE_PATH: String = "res://features/season/facility/research/UI_Comp_TrainingResearchBody.tscn"
const LINE_SCENE: PackedScene = preload("res://features/season/facility/research/UI_Comp_TrainingResearchLine.tscn")

var _state: Dictionary = {}
var _fid: String = ""


static func create() -> TrainingResearchBody:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TrainingResearchBody


func _ready() -> void:
	if not _fid.is_empty():
		_apply()
	if UiPreview.is_standalone(self):
		_fill_preview()


## Shows `fid` (a training facility) for the run `state`. Callable before the node
## enters the tree (the sheet builds the body first) — applied on `_ready` then.
func fill(state: Dictionary, fid: String) -> void:
	_state = state
	_fid = fid
	if is_node_ready():
		_apply()


func _apply() -> void:
	(%StatLine as Label).text = Loc.t(L.RESEARCH_TRAINING_BODY_STAT, {
		"name": FacilitySystem.occupant_name(_state, _fid),
		"value": FacilitySystem.stat_value(_state, _fid),
		"mult": "%.2f" % TrainingResearch.exp_mult(_state, _fid),
	})
	var lines: VBoxContainer = %Lines
	for c in lines.get_children():
		lines.remove_child(c)
		c.queue_free()
	var lvl: int = FacilitySystem.level(_state, _fid)
	for raw in TrainingResearch.ladder(_fid):
		_add_line(lines, raw as Dictionary, lvl)


func _add_line(parent: VBoxContainer, entry: Dictionary, lvl: int) -> void:
	var row: Control = LINE_SCENE.instantiate()
	parent.add_child(row)
	var steps: Array = entry["steps"]
	var inv: Dictionary = TrainingCourses.inventory(_state)
	var owned: Dictionary = inv.get(String(entry["line"]), {})
	var owned_id: String = String(owned.get("tile", ""))
	var owned_grade: int = -1
	var name_id: String = String((steps[0] as Dictionary)["tile"])
	var owned_lbl: Label = row.get_node("%Owned")
	if owned_id.is_empty():
		owned_lbl.text = Loc.t(L.RESEARCH_TRAINING_BODY_NOT_OWNED)
		owned_lbl.add_theme_color_override(&"font_color", OutgameTheme.TEXT_FAINT)
	else:
		name_id = owned_id
		owned_grade = int(_gm().training_tile_def(owned_id).get("grade", -1))
		var count: int = int(owned.get("count", 0))
		if count == TrainingCourses.UNLIMITED:
			owned_lbl.text = Loc.t(L.RESEARCH_TRAINING_BODY_OWNED_ALL, {"tile": _tile_name(owned_id)})
		else:
			owned_lbl.text = Loc.t(L.RESEARCH_TRAINING_BODY_OWNED, {"tile": _tile_name(owned_id), "count": count})
		owned_lbl.add_theme_color_override(&"font_color", OutgameTheme.POSITIVE)
	(row.get_node("%Name") as Label).text = _tile_name(name_id)
	var parts: PackedStringArray = []
	for s_raw in steps:
		var s: Dictionary = s_raw
		var grade: int = int(s["grade"])
		var txt: String = Loc.t(L.RESEARCH_TRAINING_BODY_STEP, {
			"grade": TrainingTile.GRADE_NAMES[clampi(grade, 0, TrainingTile.GRADE_NAMES.size() - 1)],
			"level": int(s["min_level"])})
		var col: Color = OutgameTheme.TEXT_SUB
		if lvl < int(s["min_level"]):
			col = OutgameTheme.TEXT_FAINT
		elif grade == owned_grade:
			col = OutgameTheme.ACCENT_TEXT
			txt = "[b]%s[/b]" % txt
		parts.append("[color=#%s]%s[/color]" % [col.to_html(false), txt])
	(row.get_node("%Steps") as RichTextLabel).text = " · ".join(parts)


static func _tile_name(tile_id: String) -> String:
	var key: String = String(_gm().training_tile_def(tile_id).get("name_key", ""))
	return tile_id if key.is_empty() else Loc.t(key)  # l10n-dynamic: training.tile.*.name


static func _gm() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameManager")


# ── F6 preview ───────────────────────────────────────────────────────────────
## In-memory run: a few courses owned (one line upgraded), the field facility at Lv2.
func _fill_preview() -> void:
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	TrainingCourses.grant(state, "T03", 1)
	TrainingCourses.grant(state, "T24", 1)
	TrainingCourses.grant(state, "T04", 1)
	FacilitySystem.set_level(state, FacilitySystem.FRONT, 2)
	FacilitySystem.set_level(state, "train_field", 2)
	fill(state, "train_field")
