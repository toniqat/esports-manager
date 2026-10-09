class_name StressSystem
extends RefCounted

# ── Stress (Darkest Dungeon style) ───────────────────────────────────────────
# State: `season_state.stress = {"<pid>": int}` for my 5 pilots, [0, STRESS_MAX].
# Tuning lives in `data/csv/const.csv` (`STRESS_*`). Rules in `mental/README.md` "Stress".
#
#   • Rises on every training day a pilot has a tile (`on_training_day`) and on every
#     death in a match (BattleSim `stress/StressEvents.gd`, written back by `record_match`).
#   • Falls through interviews / outings (`relieve` + the `stress:` event clause).
#   • ≥ STRESS_THRESHOLD outside a match = **shaken** (위축): the 6 pilot stats drop by
#     `shaken_ratio(stress)` on the match roster copy (`apply_to`, MatchFlow).
#   • A pilot that enters a match below the threshold and crosses it there is **tested**
#     once: awaken (+) or panic (−) until the match ends. A shaken pilot is never tested.
#
# Static, takes `season_state` (no autoloads) so it runs headless like `MentalSystem`.

## In-match state of one pilot (`StressEvents` · display helpers).
enum Mood { NONE, SHAKEN, AWAKEN, PANIC }


## Run start (`GameManager.start_run`) — my 5 pilots at `STRESS_START`.
static func init_run(state: Dictionary) -> void:
	var d: Dictionary = {}
	for pid in MentalSystem.my_pilot_ids(state):
		d[str(pid)] = ConstTable.int_of("STRESS_START")
	state["stress"] = d


static func value(state: Dictionary, pilot_id: int) -> int:
	return int((state.get("stress", {}) as Dictionary).get(str(pilot_id), 0))


## Change stress, clamped to [0, STRESS_MAX]. Returns the delta actually applied.
## Only my pilots carry stress; anyone else is ignored (returns 0).
static func add(state: Dictionary, pilot_id: int, delta: int) -> int:
	if not MentalSystem.my_pilot_ids(state).has(pilot_id):
		return 0
	var before: int = value(state, pilot_id)
	var after: int = clampi(before + delta, 0, ConstTable.int_of("STRESS_MAX"))
	var d: Dictionary = state.get("stress", {})
	d[str(pilot_id)] = after
	state["stress"] = d
	return after - before


static func is_over(stress: int) -> bool:
	return stress >= ConstTable.int_of("STRESS_THRESHOLD")


## Shaken (위축) drop as a ratio: one `STRESS_SHAKEN_STAT_PER_STEP` per full
## `STRESS_SHAKEN_STEP` above the threshold. 0 below the threshold.
static func shaken_ratio(stress: int) -> float:
	var over: int = stress - ConstTable.int_of("STRESS_THRESHOLD")
	if over <= 0:
		return 0.0
	var steps: int = floori(float(over) / float(maxi(1, ConstTable.int_of("STRESS_SHAKEN_STEP"))))
	return float(steps) * ConstTable.num("STRESS_SHAKEN_STAT_PER_STEP")


## Stat multiplier of a mood (`stress` only matters for SHAKEN).
static func mood_mult(mood: int, stress: int) -> float:
	match mood:
		Mood.AWAKEN:
			return 1.0 + ConstTable.num("STRESS_AWAKEN_STAT")
		Mood.PANIC:
			return maxf(0.0, 1.0 - ConstTable.num("STRESS_PANIC_STAT"))
		Mood.SHAKEN:
			return maxf(0.0, 1.0 - shaken_ratio(stress))
	return 1.0


## Mood outside a match: SHAKEN at or over the threshold, else NONE.
static func mood_of(state: Dictionary, pilot_id: int) -> int:
	return Mood.SHAKEN if is_over(value(state, pilot_id)) else Mood.NONE


## Scale the 6 pilot stats of `pd` by `mult` (floor `PlayerData.STAT_MIN`).
## Only ever called on a **roster copy** (MatchFlow), like `PilotMods.apply_to`.
static func scale_stats(pd: PlayerData, mult: float) -> void:
	if pd == null or is_equal_approx(mult, 1.0):
		return
	for k in PlayerData.STAT_KEYS:
		var key: String = String(k)
		pd.set(key, maxi(PlayerData.STAT_MIN, roundi(float(int(pd.get(key))) * mult)))


## MatchFlow `_finalize_rosters`: a shaken pilot of mine enters the match weaker.
static func apply_to(state: Dictionary, pd: PlayerData) -> void:
	if pd == null or not MentalSystem.my_pilot_ids(state).has(int(pd.id)):
		return
	var s: int = value(state, int(pd.id))
	if is_over(s):
		scale_stats(pd, mood_mult(Mood.SHAKEN, s))


## Snapshot for `match_ctx.stress` — `{"<pid>": int}` of my pilots.
static func snapshot(state: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for pid in MentalSystem.my_pilot_ids(state):
		out[str(pid)] = value(state, int(pid))
	return out


## Match result (`SeasonHub._consume_pending_match_result`): `pending_match.stress`
## = `{"<pid>": int}` written by BattleSim at match end replaces my pilots' values.
## Awaken / panic are not stored, they end with the match.
static func record_match(state: Dictionary, pm: Dictionary) -> void:
	var after: Variant = pm.get("stress", null)
	if not (after is Dictionary):
		return
	for k in (after as Dictionary).keys():
		var pid: int = int(k)
		add(state, pid, int((after as Dictionary)[k]) - value(state, pid))


## Training day `day` settled for `pilot_id` (`TrainingBoard.apply_day_training`):
## a pilot with a tile that day gains STRESS_TRAIN_MIN..MAX. Seeded per run · week ·
## day · pilot, so a resettle (preview, sim) draws the same number. Returns the delta.
static func on_training_day(state: Dictionary, pilot_id: int, day: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(state.get("run_seed", 0)), MentalSystem.week_key(state), day,
			"stress_train", pilot_id])
	return add(state, pilot_id, rng.randi_range(ConstTable.int_of("STRESS_TRAIN_MIN"),
			ConstTable.int_of("STRESS_TRAIN_MAX")))


## Base relief of a finished interview / outing (`MentalSystem.finish_evening`).
## Returns the delta applied (≤ 0).
static func relieve(state: Dictionary, pilot_id: int, action: String) -> int:
	return add(state, pilot_id, -relief_amount(action))


## Base stress relief of a finished action or event kind (≥ 0): outing / interview / morning
## talk (`STRESS_*_RELIEF`); incidents and press conferences relieve nothing.
static func relief_amount(action: String) -> int:
	match action:
		MentalSystem.ACTION_OUTING, MentalEvents.KIND_OUTING:
			# §15 D — the visit's outing relieves more than the old one.
			return ConstTable.int_of("STRESS_OUTING_RELIEF") + ConstTable.int_of("VISIT_OUTING_RELIEF_BONUS")
		MentalSystem.ACTION_INTERVIEW, MentalEvents.KIND_INTERVIEW, MentalSystem.ACTION_STORY:
			return ConstTable.int_of("STRESS_INTERVIEW_RELIEF")
		MentalSystem.ACTION_TALK, MentalEvents.KIND_TALK_PAIR:
			return ConstTable.int_of("STRESS_TALK_RELIEF")
	return 0


# ── Display ──────────────────────────────────────────────────────────────────
## Mood name ("위축" …), "" for NONE.
static func mood_label(mood: int) -> String:
	match mood:
		Mood.SHAKEN:
			return Loc.t(L.MENTAL_UI_STRESS_MOOD_SHAKEN)
		Mood.AWAKEN:
			return Loc.t(L.MENTAL_UI_STRESS_MOOD_AWAKEN)
		Mood.PANIC:
			return Loc.t(L.MENTAL_UI_STRESS_MOOD_PANIC)
	return ""


## "스트레스 120" or "스트레스 120 · 위축".
static func line(stress: int, mood: int) -> String:
	var base: String = Loc.t(L.MENTAL_UI_STRESS_VALUE, {"n": stress})
	if mood == Mood.NONE:
		return base
	return "%s · %s" % [base, mood_label(mood)]
