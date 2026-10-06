class_name QuirkSystem
extends RefCounted

# ── Quirks (기벽) — run-only pilot passives (§14, T1) ─────────────────────────
# Contract: `docs/outgame_dev_plan.md` §14. Run-scoped state, string keys only:
#   season_state.quirks = {"<pilot_id>": {"slots": int, "ids": [quirk_id]}}  (MY 5 pilots only)
# Positive stat bonuses only. MatchFlow adds them to roster copies (`apply_to`),
# like mech mastery — BattleSim never reads quirks.
#
# BASE STUB: signatures are fixed; the T1 agent fills the bodies.

## Once at run start (`GameManager.start_run`) — every pilot of mine: 0 quirks,
## `QUIRK_SLOTS_START` slots.
static func init_run(_state: Dictionary) -> void:
	pass


## False outside a run / before `init_run` → no bonus, UI hidden.
static func is_enabled(state: Dictionary) -> bool:
	return bool(state.get("active", false)) \
			and not (state.get("quirks", {}) as Dictionary).is_empty()


## Equipped quirk ids of a pilot (empty for opponents).
static func quirks_of(_state: Dictionary, _pilot_id: int) -> Array:
	return []


## Current slot count (QUIRK_SLOTS_START..QUIRK_SLOTS_MAX).
static func slots_of(_state: Dictionary, _pilot_id: int) -> int:
	return 0


## Rolls a random quirk (grade weighted by effective knowledge) into an empty slot.
## Returns `{result: "gain"|"full"|"none", id}`; "full" = no empty slot (nothing changes).
static func gain_random(_state: Dictionary, _pilot_id: int) -> Dictionary:
	return {"result": "none", "id": -1}


## Rerolls every equipped quirk of the pilot. Returns `{result: "reroll"|"none", from: [id], to: [id]}`.
static func reroll(_state: Dictionary, _pilot_id: int) -> Dictionary:
	return {"result": "none", "from": [], "to": []}


## +1 slot up to QUIRK_SLOTS_MAX. Returns `{result: "slot"|"max", slots}`.
static func add_slot(_state: Dictionary, _pilot_id: int) -> Dictionary:
	return {"result": "max", "slots": 0}


## Total per-stat bonus `{stat_key: int}` for the pilot riding `pd.assigned_mech`
## (unconditional `stats` + `cond_stats` whose `cond` holds).
static func stat_bonus(_state: Dictionary, _pd: PlayerData) -> Dictionary:
	return {}


## Adds `stat_bonus` to `pd`. **Call on a copy only** (`MatchFlow._finalize_rosters`).
static func apply_to(_state: Dictionary, _pd: PlayerData) -> void:
	pass


## Table row `{id, name, grade, stats, cond, cond_stats, weight, desc}` ({} if unknown).
static func row(_id: int) -> Dictionary:
	return {}
