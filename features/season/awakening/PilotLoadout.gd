class_name PilotLoadout
extends RefCounted

# ── Pilot card loadout (§15 C) ───────────────────────────────────────────────
# Run-only pilot card presets of my pilots: the base preset (the pilot's run pilot
# cards) + up to LOADOUT_EXTRA_MAX extra presets from awakenings. Card ids may be
# upgraded ("+") ids (`cards.upgrade_id`). The active preset is picked after ban/pick,
# right before the match. State: season_state.loadouts =
#   {"<pid>": {"presets": [[card_id ×3], …], "active": int}}.
#
# BASE STUB — signatures are the §15.2 contract; agent C implements the bodies.


static func init_run(_state: Dictionary) -> void:
	pass


static func presets(_state: Dictionary, _pid: int) -> Array:
	return []


static func active(_state: Dictionary, _pid: int) -> int:
	return 0


static func set_active(_state: Dictionary, _pid: int, _idx: int) -> void:
	pass


## `MatchFlow._finalize_rosters` hook: write the active preset into the roster copy's
## `pilot_cards` (my pilots only; anyone else is left untouched).
static func apply_to(_state: Dictionary, _pd: PlayerData) -> void:
	pass
