class_name TrainingResearchCard
extends PanelContainer

# One research card of a training facility body (`TrainingResearchBody`, 3-column grid).
# Top: the course thumbnail in the training-board look (`TrainingCourseCard`, its cap =
# owned ×n / ∞ / 미보유); tap on it → `thumb_pressed` (the body shows the course's info
# popover). Under it a status line (research weeks · weeks left · paused · level needed)
# and the progress bar split into one segment per research week (`weeks` of the row;
# segment i is filled by `progress × weeks − i`). Tap elsewhere → `pressed` (select).
#
# **Layout lives in `UI_Comp_TrainingResearchCard.tscn`.** Code sets the data, the
# `SelectableCard` / `SelectableCardOn` variation (active row), the status label variation,
# the fade of a level-locked row and the segment count / fills.

signal pressed(rid: String)
signal thumb_pressed(card: TrainingResearchCard)

const SCENE_PATH: String = "res://features/season/facility/research/UI_Comp_TrainingResearchCard.tscn"
## Alpha of a row the facility level does not reach yet.
const LOCKED_ALPHA: float = 0.45

var rid: String = ""
var tile: TrainingTile = null
## Cap text of the thumbnail (owned ×n / ∞ / 미보유) — the info popover shows it too.
var cap_text: String = ""


static func create() -> TrainingResearchCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TrainingResearchCard


func _ready() -> void:
	(%Hit as Button).pressed.connect(func() -> void: pressed.emit(rid))
	(%ThumbHit as Button).pressed.connect(func() -> void: thumb_pressed.emit(self))
	if UiPreview.is_standalone(self):
		_fill_preview()


## Fills the card. `info` (from `TrainingResearchBody`):
## `{rid, tile: TrainingTile, cap, status, status_variation, weeks, progress, active, locked, selectable}`.
func fill(info: Dictionary) -> void:
	rid = String(info.get("rid", ""))
	tile = info.get("tile") as TrainingTile
	cap_text = String(info.get("cap", ""))
	var active: bool = bool(info.get("active", false))
	var locked: bool = bool(info.get("locked", false))
	theme_type_variation = &"SelectableCardOn" if active else &"SelectableCard"
	if tile != null:
		(%TrainingCourseCard_Thumb as TrainingCourseCard).fill(tile, cap_text, false)
	var status: Label = %Status
	status.text = String(info.get("status", ""))
	status.theme_type_variation = StringName(String(info.get("status_variation", "CaptionLabel")))
	(%Content as Control).modulate = Color(1, 1, 1, LOCKED_ALPHA) if locked else Color(1, 1, 1, 1)
	(%Hit as Button).disabled = locked or active or not bool(info.get("selectable", false))
	_fill_bar(maxi(1, int(info.get("weeks", 1))), float(info.get("progress", 0.0)))


# One segment per week; segment i holds `clamp(progress × weeks − i, 0, 1)`.
func _fill_bar(weeks: int, progress: float) -> void:
	var bar: HBoxContainer = %Bar
	var first: Control = bar.get_child(0)
	while bar.get_child_count() < weeks:
		bar.add_child(first.duplicate())
	for i in bar.get_child_count():
		var seg: Control = bar.get_child(i)
		seg.visible = i < weeks
		if not seg.visible:
			continue
		var fill_ratio: float = clampf(progress * float(weeks) - float(i), 0.0, 1.0)
		var f: Control = seg.get_child(0)
		f.anchor_right = fill_ratio
		f.offset_right = 0.0
		f.visible = fill_ratio > 0.0


## F6 preview — a hand-written active 3-week row, 40 % done.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var t := TrainingTile.from_def({"id": "T24", "name_key": "tx_ETXQNX2FF3", "grade": 2,
			"shape": "H", "exp": "field_hit:52", "effect": ""})
	fill({"rid": "tr_h2", "tile": t, "cap": "×1", "status": Loc.t(L.RESEARCH_TRAINING_CARD_WEEKS_LEFT, {"weeks": 2}),
		"status_variation": "AccentLabel", "weeks": 3, "progress": 0.4, "active": true,
		"locked": false, "selectable": true})
