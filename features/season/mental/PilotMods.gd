class_name PilotMods
extends RefCounted

# ── Temporary per-pilot stat mods (M7 incidents · outings, …) ──────────────────
# `season_state.pilot_mods` = `[{pilot_id, stat, delta, weeks_left, source}]`.
# - `stat` is one of `PlayerData.STAT_KEYS` or `"all"` (all six stats).
# - `weeks_left` > 0 = minus one per week end, gone at 0. **-1 = until the next own
#   match** (`consume_match` drops it when that match's result is consumed).
#
# Mods are **never written to the original pilot** — only to the match roster
# **copy** (`MatchFlow` calls `apply_to` when it builds the copy). Writing them to the
# original would mix them with training growth so they could never be undone.


static func add(state: Dictionary, pilot_id: int, stat: String, delta: int,
		weeks: int, source: String = "") -> void:
	if delta == 0 or weeks == 0 or (stat != "all" and not PlayerData.STAT_KEYS.has(stat)):
		return
	var mods: Array = state.get("pilot_mods", [])
	mods.append({"pilot_id": pilot_id, "stat": stat, "delta": delta,
			"weeks_left": weeks, "source": source})
	state["pilot_mods"] = mods


## Current mod totals on this pilot `{stat: delta}` (`all` is expanded to the six).
static func of(state: Dictionary, pilot_id: int) -> Dictionary:
	var out: Dictionary = {}
	for raw in (state.get("pilot_mods", []) as Array):
		var m: Dictionary = raw
		if int(m.get("pilot_id", -1)) != pilot_id:
			continue
		var d: int = int(m.get("delta", 0))
		var stat: String = String(m.get("stat", ""))
		var keys: Array = PlayerData.STAT_KEYS if stat == "all" else [stat]
		for k in keys:
			out[k] = int(out.get(k, 0)) + d
	return out


## Add the mods onto `pd` — **only ever call this on a copy**. Floor is `PlayerData.STAT_MIN`.
static func apply_to(state: Dictionary, pd: PlayerData) -> void:
	var mods: Dictionary = of(state, pd.id)
	for k in mods.keys():
		pd.set(k, maxi(PlayerData.STAT_MIN, int(pd.get(k)) + int(mods[k])))


## Once per week end (`SeasonHub._end_week`).
static func decay_week(state: Dictionary) -> void:
	var kept: Array = []
	for raw in (state.get("pilot_mods", []) as Array):
		var m: Dictionary = (raw as Dictionary).duplicate()
		var w: int = int(m.get("weeks_left", 0))
		if w < 0:
			kept.append(m)
			continue
		m["weeks_left"] = w - 1
		if w - 1 > 0:
			kept.append(m)
	state["pilot_mods"] = kept


## Once right after an own match result is consumed — drops the "until next match" (-1) mods.
static func consume_match(state: Dictionary) -> void:
	var kept: Array = []
	for raw in (state.get("pilot_mods", []) as Array):
		if int((raw as Dictionary).get("weeks_left", 0)) != -1:
			kept.append(raw)
	state["pilot_mods"] = kept
