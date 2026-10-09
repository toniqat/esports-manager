class_name Awakening
extends RefCounted

# ── Awakening (깨달음, §15 C) ────────────────────────────────────────────────
# Per-pilot gauge in percent points (may exceed 100). Training, stories, incidents,
# focus training … add to it; at ≥ 100 an awakening fires right there on the week
# screen (dim + pause + FX) and the gauge drops by 100. The pilot then picks 1 of 3:
# card upgrade / card swap / add preset (`PilotLoadout`). Rules: §15.0 C.
# State: season_state.awakening = {"<pid>": int}, season_state.awakening_pending = [pid…].
#
# BASE STUB — signatures are the §15.2 contract; agent C implements the bodies.


static func init_run(_state: Dictionary) -> void:
	pass


static func gauge(_state: Dictionary, _pid: int) -> int:
	return 0


## Add to the gauge (`source` = short id for logs / notes). Crossing 100 queues an event.
static func add_gauge(_state: Dictionary, _pid: int, _amount: int, _source: String = "") -> void:
	pass


## Pilot with a queued awakening, -1 = none. The week screen polls this after each state change.
static func next_pending(_state: Dictionary) -> int:
	return -1


## `TrainingBoard.apply_day_training` hook.
static func on_training_day(_state: Dictionary, _rows: Array) -> void:
	pass


## `SeasonHub._consume_pending_match_result` hook.
static func on_match(_state: Dictionary, _pending_match: Dictionary) -> void:
	pass
