class_name FrontResearch
extends RefCounted

# ── Research kind handler: `front` (§16) ──
# Front research for `front`: row `p1` = `budget_cut` (p2 = upkeep −%), `boost` (p2 = research +%,
# `ResearchSystem.add_boost` for `FRONT_BOOST_WEEKS`), `expand` (p2 = the front level it unlocks —
# read by `FacilitySystem.front_expand_done`; completion itself needs no effect).
# **Stub from the base commit** — owner after the base: agent F (front-finance). Keep the four
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
