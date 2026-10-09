class_name LimitBreakDemo
extends Control

# F6 harness for the limit-break dialogue (§15 B) — the exact call sequence the week
# screen (`WeekProgressView`, agent D) runs at an evening:
#
#   var pid := LimitBreak.pending_event(state, day)          # -1 = nothing due
#   var v := LimitBreak.session(state, pid)
#   vn.open(v.sub, v.title, pid, v.lines, v.choices, "", v.previews)
#   vn.choice_picked → vn.show_result(LimitBreak.choose_goal(state, pid, idx))
#   vn.closed → ask pending_event again (next due pilot), then the incident
#
# Run alone (F6): an in-memory run (`UiPreview.ensure_run`, nothing saved), the first
# pilot's Lv1 bar filled on Monday (→ Lv2, bar locked), then the dialogue above in a
# `VnDialogueView`.
# In the game this scene is never instanced.

const SCENE_PATH: String = "res://features/season/training/UI_View_LimitBreakDemo.tscn"

## The dialogue view opened by `play` (null before).
var view: VnDialogueView = null


static func create() -> LimitBreakDemo:
	return (load(SCENE_PATH) as PackedScene).instantiate() as LimitBreakDemo


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## Opens the limit-break dialogue of the pilot due on the evening of `day`. Returns that
## pilot id (-1 = nobody due, nothing opened).
func play(state: Dictionary, day: int) -> int:
	var pid: int = LimitBreak.pending_event(state, day)
	if pid < 0:
		return -1
	var v: Dictionary = LimitBreak.session(state, pid)
	if v.is_empty():
		return -1
	if view == null:
		view = VnDialogueView.create()
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.choice_picked.connect(func(idx: int) -> void:
		view.show_result(LimitBreak.choose_goal(state, pid, idx)), CONNECT_ONE_SHOT)
	view.open(String(v["sub"]), String(v["title"]), pid, v["lines"], v["choices"], "",
			v["previews"])
	return pid


func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var ids: Array = MentalSystem.my_pilot_ids(s)
	if ids.is_empty():
		return
	var pid: int = int(ids[0])
	s["week_day"] = 0
	TrainingLevel.add_exp(s, pid, TrainingLevel.exp_need(s, pid))
	play(s, 0)
	if view != null:
		UiPreview.trace(view.choice_picked)
		UiPreview.trace(view.closed)
