class_name PilotLoadout
extends RefCounted

# ── Pilot card loadout (§15 C) ───────────────────────────────────────────────
# Run-only pilot card presets of my pilots: the base preset (the pilot's run pilot
# cards, `GameManager.pilot_card_ids_for`) + up to LOADOUT_EXTRA_MAX extra presets from
# awakenings. Card ids may be upgraded ("+") ids (`cards.upgrade_id`). The active preset
# is picked after ban/pick, right before the match (`BanPickLoadoutPicker`). State:
#   season_state.loadouts = {"<pid>": {"presets": [[card_id ×3], …], "active": int}}.
#
# Every read is lazy-safe: a run without the key (older save, editor test run) builds the
# base preset on first use. Only my pilots have a loadout; anyone else reads [] / 0 and
# `apply_to` leaves them untouched.

const STATE_KEY: String = "loadouts"
const CARDS_PER_PRESET: int = 3


static func init_run(state: Dictionary) -> void:
	var d: Dictionary = {}
	for pid in MentalSystem.my_pilot_ids(state):
		d[str(pid)] = {"presets": [base_ids(state, int(pid))], "active": 0}
	state[STATE_KEY] = d


static func presets(state: Dictionary, pid: int) -> Array:
	var e: Dictionary = _entry(state, pid)
	var out: Array = []
	for raw in (e.get("presets", []) as Array):
		var ids: Array = []
		for c in (raw as Array):
			ids.append(int(c))
		out.append(ids)
	return out


static func active(state: Dictionary, pid: int) -> int:
	var e: Dictionary = _entry(state, pid)
	var n: int = (e.get("presets", []) as Array).size()
	return clampi(int(e.get("active", 0)), 0, maxi(n - 1, 0))


static func set_active(state: Dictionary, pid: int, idx: int) -> void:
	var e: Dictionary = _entry(state, pid)
	if e.is_empty():
		return
	var n: int = (e.get("presets", []) as Array).size()
	if idx >= 0 and idx < n:
		e["active"] = idx


## The card ids of preset `idx` ([] when out of range).
static func preset(state: Dictionary, pid: int, idx: int) -> Array:
	var all: Array = presets(state, pid)
	return all[idx] if idx >= 0 and idx < all.size() else []


static func extra_count(state: Dictionary, pid: int) -> int:
	return maxi(presets(state, pid).size() - 1, 0)


## Whether an awakening may add a preset now: training level ≥ LOADOUT_PRESET_MIN_TLEVEL
## and fewer than LOADOUT_EXTRA_MAX extras.
static func can_add_preset(state: Dictionary, pid: int) -> bool:
	if _entry(state, pid).is_empty():
		return false
	return TrainingLevel.level(state, pid) >= ConstTable.int_of("LOADOUT_PRESET_MIN_TLEVEL") \
			and extra_count(state, pid) < ConstTable.int_of("LOADOUT_EXTRA_MAX")


## `MatchFlow._finalize_rosters` hook: write the active preset into the roster copy's
## `pilot_cards` (my pilots only; anyone else is left untouched). The deck reads it through
## `GameManager.pilot_card_ids_for` like any `players.pilot_cards` value.
static func apply_to(state: Dictionary, pd: PlayerData) -> void:
	if pd == null or not MentalSystem.my_pilot_ids(state).has(pd.id):
		return
	var ids: Array = preset(state, pd.id, active(state, pd.id))
	if ids.is_empty():
		return
	pd.pilot_cards = ids.duplicate()


# ── Edits (awakening outcomes) ───────────────────────────────────────────────

## Replace `card_id` in preset `idx` by its "+" row. False when the card is not in that
## preset or has no upgrade.
static func upgrade_card(state: Dictionary, pid: int, idx: int, card_id: int) -> bool:
	var up: int = upgrade_of(card_id)
	return up >= 0 and _replace(state, pid, idx, card_id, up)


## Swap `out_id` (in preset `idx`) for `in_id`. False when `out_id` is not there or the
## family of `in_id` is already held in that preset.
static func swap_card(state: Dictionary, pid: int, idx: int, out_id: int, in_id: int) -> bool:
	var held: Array = preset(state, pid, idx)
	for c in held:
		if int(c) != out_id and base_of(int(c)) == base_of(in_id):
			return false
	return _replace(state, pid, idx, out_id, in_id)


## Append a preset (3 card ids); returns its index, -1 when the cap is reached.
static func add_preset(state: Dictionary, pid: int, ids: Array) -> int:
	var e: Dictionary = _entry(state, pid)
	if e.is_empty() or extra_count(state, pid) >= ConstTable.int_of("LOADOUT_EXTRA_MAX"):
		return -1
	var list: Array = e.get("presets", [])
	var clean: Array = []
	for c in ids:
		clean.append(int(c))
	list.append(clean)
	e["presets"] = list
	return list.size() - 1


static func _replace(state: Dictionary, pid: int, idx: int, from_id: int, to_id: int) -> bool:
	var e: Dictionary = _entry(state, pid)
	var list: Array = e.get("presets", [])
	if idx < 0 or idx >= list.size():
		return false
	var ids: Array = list[idx]
	for i in ids.size():
		if int(ids[i]) == from_id:
			ids[i] = to_id
			return true
	return false


# ── Card table helpers ───────────────────────────────────────────────────────

## The "+" row of `card_id` (`cards.upgrade_id`), -1 = none / already upgraded.
static func upgrade_of(card_id: int) -> int:
	var gm: Node = _gm()
	if gm == null:
		return -1
	return int((gm.card_def(card_id) as Dictionary).get("upgrade_id", -1))


## The base card of `card_id` (itself for a base card) — a base card and its "+" row are
## one family: a preset never holds both, swap / preset candidates skip held families.
static func base_of(card_id: int) -> int:
	var gm: Node = _gm()
	if gm == null:
		return card_id
	var b: int = int(gm.card_upgrade_base(card_id))
	return b if b >= 0 else card_id


static func is_upgraded(card_id: int) -> bool:
	return base_of(card_id) != card_id


## Base preset of my pilot `pid`: its run pilot cards (`GameManager.pilot_card_ids_for`).
static func base_ids(state: Dictionary, pid: int) -> Array:
	var gm: Node = _gm()
	var pd: PlayerData = MentalEvents.pilot_of(state, pid)
	if gm == null or pd == null:
		return []
	var out: Array = []
	for c in gm.pilot_card_ids_for(pd):
		out.append(int(c))
	return out


## Pool cards (`pool = 1`) that pilot `pid`'s position may hold (`scope`), minus every
## family in `held` and any `excl_group` a held card claims. Ascending id order.
static func candidate_pool(state: Dictionary, pid: int, held: Array) -> Array:
	var gm: Node = _gm()
	var pd: PlayerData = MentalEvents.pilot_of(state, pid)
	if gm == null or pd == null:
		return []
	var pos: String = GameEnums.position_key(pd.role)
	var families: Dictionary = {}
	var claimed: Dictionary = {}
	for c in held:
		families[base_of(int(c))] = true
		var g: String = String((gm.card_def(int(c)) as Dictionary).get("excl_group", ""))
		if g != "":
			claimed[g] = true
	var out: Array = []
	for raw in gm.card_pool_bs:
		var def: Dictionary = raw as Dictionary
		if int(def.get("pool", 1)) != 1:
			continue
		var id: int = int(def.get("id", -1))
		if families.has(id):
			continue
		if not CardData.positions_of(String(def.get("scope", "any"))).has(pos):
			continue
		var grp: String = String(def.get("excl_group", ""))
		if grp != "" and claimed.has(grp):
			continue
		out.append(id)
	out.sort()
	return out


## Loadout entry of my pilot `pid` — created (base preset) when a run predates the key.
## {} for a pilot that is not mine.
static func _entry(state: Dictionary, pid: int) -> Dictionary:
	if not MentalSystem.my_pilot_ids(state).has(pid):
		return {}
	if not (state.get(STATE_KEY, null) is Dictionary):
		state[STATE_KEY] = {}
	var d: Dictionary = state[STATE_KEY]
	var key: String = str(pid)
	var cur: Variant = d.get(key, null)
	if not (cur is Dictionary) or ((cur as Dictionary).get("presets", []) as Array).is_empty():
		var base: Array = base_ids(state, pid)
		if base.is_empty():
			return {}
		d[key] = {"presets": [base], "active": 0}
	return d[key]


static func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameManager") if tree != null else null
