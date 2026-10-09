class_name LimitBreak
extends RefCounted

# ── Limit break (한계돌파, §15 B) ─────────────────────────────────────────────
# A pilot whose training-level bar is full gets a forced visual-novel event at that
# day's evening: the manager offers 1 of 3 short-term goals; the goal stays until it is
# met on my matches (or focus training completes it). Met → level +1, all six stats
# + LIMIT_BREAK_STAT_GAIN. Goal pool and rules: `docs/outgame_dev_plan.md` §15.0 B.
#
# BASE STUB — signatures are the §15.2 contract; agent B implements the bodies.


## Pilot whose limit-break dialogue must open on the evening of `day`, -1 = none.
static func pending_event(_state: Dictionary, _day: int) -> int:
	return -1


## View dict for `VnDialogueView` (same shape as `MentalSystem.session_view`).
static func session(_state: Dictionary, _pid: int) -> Dictionary:
	return {}


## The manager picked goal `idx` of the offer → outcome view for `VnDialogueView.show_result`.
static func choose_goal(_state: Dictionary, _pid: int, _idx: int) -> Dictionary:
	return {}


static func goal_active(_state: Dictionary, _pid: int) -> bool:
	return false


## Translated one-line goal text with progress ("" when none).
static func goal_text(_state: Dictionary, _pid: int) -> String:
	return ""


## Finish the limit break now (goal met / focus training): level +1, stats up. Returns note dict.
static func complete(_state: Dictionary, _pid: int) -> Dictionary:
	return {}


## `SeasonHub._consume_pending_match_result` hook (after `RunStats.record_match`).
static func record_match(_state: Dictionary, _pending_match: Dictionary) -> void:
	pass
