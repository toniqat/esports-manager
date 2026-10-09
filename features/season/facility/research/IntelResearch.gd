class_name IntelResearch
extends RefCounted

# ── Research kind handler: `intel` (§16) ──
# Opponent research for `intel`. Target = a team of my current league; completion raises
# `season_state.intel_rank["<team_id>"]` by one (0..3, own team always 3).
# **Stub from the base commit** — owner after the base: agent E (intel-research). Keep the four
# static signatures (`ResearchSystem` dispatches to them); everything else is free.
# Contract: `features/season/facility/README.md` "Kind handlers".


## Targets offered for `row`: `[{id: String, label: String, icon?: Texture2D}]`. Empty = no target.
static func targets(_state: Dictionary, _row: Dictionary) -> Array:
	return []


## "" when `row` may be researched now, else the block reason (current locale).
static func row_available(_state: Dictionary, _row: Dictionary) -> String:
	return ""


## Applies a completed research. Returns the toast note `{text_key, args}` (`text_key` "" = none).
static func on_complete(_state: Dictionary, _row: Dictionary, _target: String) -> Dictionary:
	return {"text_key": "", "args": {}}


## Kind-specific section of the facility sheet (added under the research list); null = none.
static func make_body(_state: Dictionary, _fid: String) -> Control:
	return null


## Analysis rank 0..3 of `team_id` (own team = 3). Replaces `StaffSystem.analysis_tier`.
static func rank(state: Dictionary, team_id: int) -> int:
	if team_id == int(state.get("player_team_id", -1)):
		return 3
	return clampi(int((state.get("intel_rank", {}) as Dictionary).get(str(team_id), 0)), 0, 3)
