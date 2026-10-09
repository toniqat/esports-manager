class_name TrainingLevel
extends RefCounted

# ── Run-only training level (§15 B, `docs/outgame_dev_plan.md` §15) ─────────
# Each of my pilots has a training level 1..TLEVEL_MAX and training EXP. The EXP is
# the sum of stat EXP the pilot earned on the training board that day; when the bar
# is full the EXP stops and a limit break (`LimitBreak`) is needed for the next level.
# State: season_state.training_level = {"<pid>": {"level", "exp", "goal", "offer", "event_day"}}.
#
# BASE STUB — signatures are the §15.2 contract; agent B implements the bodies.


static func init_run(_state: Dictionary) -> void:
	pass


## Training level of my pilot `pid` (1 outside a run / unknown pilot).
static func level(_state: Dictionary, _pid: int) -> int:
	return 1


## Training EXP inside the current level.
static func exp_of(_state: Dictionary, _pid: int) -> int:
	return 0


## EXP that fills the current level's bar (0 at the cap).
static func exp_need(_state: Dictionary, _pid: int) -> int:
	return 0


## The bar is full (waiting for a limit break) or the level is the cap.
static func is_capped(_state: Dictionary, _pid: int) -> bool:
	return false


## Add training EXP; returns the applied amount (0 when capped).
static func add_exp(_state: Dictionary, _pid: int, _amount: int) -> int:
	return 0


## `TrainingBoard.apply_day_training` hook — `rows` are that day's result rows (`exp` = EXP earned).
static func on_training_day(_state: Dictionary, _rows: Array) -> void:
	pass
