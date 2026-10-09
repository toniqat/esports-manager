class_name MechResearch
extends RefCounted

# ── Research kind handler: `mech` (§16) ──
# Mech research for `mech_lab`. Target = a mech id (string); completion gives every one
# of my five pilots `MASTERY_GAIN_LAB` × (row `p1` % , empty = 100) raw mastery on it
# through `MechMastery.gain` (knowledge = the lab occupant via `StaffSystem.effective`,
# `FinanceSystem.mastery_mult`, trait `mastery_pct`), then rolls the research quirk
# (`QUIRK_RESEARCH_CHANCE`% per pilot, seeded per run · week · pilot).
# This replaces the old per-pilot weekly research mech (`mastery_research`, removed).
# Contract: `features/season/facility/README.md` "Kind handlers" + `mastery/README.md`.

const FID: String = "mech_lab"


## Every mech whose mastery can still grow for at least one of my pilots, the ones my
## pilots' roles use first (count desc), then mech id. `{id: "<mech id>", label, icon}`.
static func targets(state: Dictionary, _row: Dictionary) -> Array:
	if not MechMastery.is_enabled(state):
		return []
	var pilots: Array = MechMastery.my_pilots(state)
	var cap: int = MechMastery.max_value()
	var scored: Array = []
	for raw in MechMastery.all_mechs():
		var mid: int = int((raw as Dictionary)["id"])
		var users: int = 0
		var room: bool = false
		for p in pilots:
			var pd := p as PlayerData
			if pd.role == int((raw as Dictionary)["role"]):
				users += 1
			if MechMastery.value(state, pd.id, mid) < cap:
				room = true
		if room:
			scored.append({"mech": mid, "users": users})
	scored.sort_custom(func(a, b):
		if int(a["users"]) != int(b["users"]):
			return int(a["users"]) > int(b["users"])
		return int(a["mech"]) < int(b["mech"]))
	var out: Array = []
	for e in scored:
		var mid: int = int(e["mech"])
		out.append({"id": str(mid), "label": MechMastery.mech_name(mid),
				"icon": MechImages.portrait_for(mid)})
	return out


## Blocked outside a run (no mastery table).
static func row_available(state: Dictionary, _row: Dictionary) -> String:
	if not MechMastery.is_enabled(state):
		return Loc.t(L.RESEARCH_MECH_BLOCK_NO_RUN)
	return ""


## Raw mastery a completion of `row` hands each pilot: `MASTERY_GAIN_LAB` × `p1` % (empty = 100).
static func raw_gain(row: Dictionary) -> int:
	var pct: String = String(row.get("p1", "")).strip_edges()
	var mult: float = float(pct) / 100.0 if pct.is_valid_float() else 1.0
	return maxi(0, roundi(float(ConstTable.int_of("MASTERY_GAIN_LAB")) * mult))


## The mech the lab is researching now (-1 = idle / no mech target).
static func lab_mech(state: Dictionary) -> int:
	var a: Dictionary = ResearchSystem.active(state, FID)
	if a.is_empty() or not String(a["target"]).is_valid_int():
		return -1
	return int(String(a["target"]))


## Gives the mech's mastery to my pilots + the quirk roll. Note = `research_mech.note.done`
## (`{mech} +n`, then level-ups and quirks found as extra segments).
static func on_complete(state: Dictionary, row: Dictionary, target: String) -> Dictionary:
	if not target.is_valid_int() or not MechMastery.is_enabled(state):
		return {"text_key": "", "args": {}}
	var mech: int = int(target)
	var raw: int = raw_gain(row)
	var ups: Array = []
	var found: Array = []
	var shown: int = 0
	for p in MechMastery.my_pilots(state):
		var pd := p as PlayerData
		var before: int = MechMastery.value(state, pd.id, mech)
		MechMastery.gain(state, pd.id, mech, raw)
		var after: int = MechMastery.value(state, pd.id, mech)
		shown = maxi(shown, after - before)
		var lv: int = MechMastery.level_for_value(after)
		if lv > MechMastery.level_for_value(before):
			ups.append("%s %s" % [pd.name, MechMastery.level_name(lv)])
		var q: int = quirk_roll(state, pd.id)
		if q >= 0:
			found.append("%s %s" % [pd.name, QuirkSystem.name_of(q)])
	var extra: String = ""
	if not ups.is_empty():
		extra += " · " + Loc.t(L.RESEARCH_MECH_NOTE_LEVEL_UPS, {"list": ", ".join(ups)})
	if not found.is_empty():
		extra += " · " + Loc.t(L.RESEARCH_MECH_NOTE_QUIRKS, {"list": ", ".join(found)})
	return {"text_key": L.RESEARCH_MECH_NOTE_DONE,
			"args": {"mech": MechMastery.mech_name(mech), "n": shown, "extra": extra}}


## Research also turns up quirks (§14 T1, moved here from the old weekly research):
## `QUIRK_RESEARCH_CHANCE`% per pilot → `QuirkSystem.gain_random`. Seeded per run · week ·
## pilot, so reloading the week close never rerolls. Returns the quirk id gained, -1 = none.
static func quirk_roll(state: Dictionary, pilot_id: int) -> int:
	if not QuirkSystem.is_enabled(state):
		return -1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(state.get("run_seed", 0)), int(state.get("current_phase", 0)),
			int(state.get("phase_week", 1)), pilot_id, "quirk_research"])
	if rng.randi_range(1, 100) > ConstTable.int_of("QUIRK_RESEARCH_CHANCE"):
		return -1
	var res: Dictionary = QuirkSystem.gain_random(state, pilot_id)
	return int(res.get("id", -1)) if String(res.get("result", "")) == "gain" else -1


## Role (`GameEnums.Role`) a mech is built for (`mechs.role`); -1 for an unknown id.
static func mech_role(mech_id: int) -> int:
	for raw in MechMastery.all_mechs():
		if int((raw as Dictionary)["id"]) == mech_id:
			return int((raw as Dictionary)["role"])
	return -1


## Up to `n` of my pilots suited to `mech_id` (the lab body's per-mech strip): first every pilot
## with Lv1+ mastery on it, highest points first (ties: own-role pilot first, then seat order),
## then the remaining pilots whose role is the mech's role, highest points first. A pilot with
## Lv0 on a mech of another role is never suggested, so fewer than `n` can come back.
static func fit_pilots(state: Dictionary, mech_id: int, n: int = 3) -> Array:
	var role: int = mech_role(mech_id)
	var lv1: int = MechMastery.threshold(1)
	var skilled: Array = []
	var fits: Array = []
	for p in MechMastery.my_pilots(state):
		var pd := p as PlayerData
		var v: int = MechMastery.value(state, pd.id, mech_id)
		if v >= lv1:
			skilled.append(pd)
		elif pd.role == role:
			fits.append(pd)
	var by_points := func(a: PlayerData, b: PlayerData) -> bool:
		var va: int = MechMastery.value(state, a.id, mech_id)
		var vb: int = MechMastery.value(state, b.id, mech_id)
		if va != vb:
			return va > vb
		if (a.role == role) != (b.role == role):
			return a.role == role
		return GameEnums.role_seat(a.role) < GameEnums.role_seat(b.role)
	skilled.sort_custom(by_points)
	fits.sort_custom(by_points)
	return (skilled + fits).slice(0, maxi(0, n))


## The mech-lab facility body: the grid of research targets (`MechLabBody`).
static func make_body(state: Dictionary, _fid: String) -> Control:
	return MechLabBody.create(state)
