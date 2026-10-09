class_name FrontResearch
extends RefCounted

# ── Research kind handler: `front` (§16) ──
# Front research for `front` (rows in `data/csv/research.csv`, facility `front`), by `p1`:
#   `budget_cut` — permanent facility upkeep −p2 %, stacking (`FinanceSystem.add_upkeep_cut`,
#                  stored as `season_state.finance.upkeep_cut_pct`, capped at
#                  `FINANCE_UPKEEP_CUT_MAX_PCT`). One non-repeatable row per rung, gated by `min_level`.
#   `boost`      — every facility's research gauge +p2 % for `FRONT_BOOST_WEEKS` week ends
#                  (`ResearchSystem.add_boost`; starts the week after the completion). Repeatable.
#   `expand`     — p2 = the front level it unlocks; `FacilitySystem.front_expand_done` reads the done
#                  count, so completion only leaves a toast note. Blocked once the front is at that level.
# The kind body (`make_body`) is `UI_View_FrontResearchBody.tscn` (`FrontResearchBody`).
# Contract: `features/season/facility/README.md` "Kind handlers" + "FrontResearch".

const P_BUDGET_CUT: String = "budget_cut"
const P_BOOST: String = "boost"
const P_EXPAND: String = "expand"


## Front rows have no target.
static func targets(_state: Dictionary, _row: Dictionary) -> Array:
	return []


## "" when `row` may be researched now, else the block reason (current locale):
## `expand` for a level the front already has · `budget_cut` once the cut cap is reached.
static func row_available(state: Dictionary, row: Dictionary) -> String:
	match String(row.get("p1", "")):
		P_EXPAND:
			var lvl: int = FacilitySystem.level(state, FacilitySystem.FRONT)
			if String(row.get("p2", "")).to_int() <= lvl:
				return Loc.t(L.RESEARCH_FRONT_BLOCK_EXPAND_REACHED, {"level": lvl})
		P_BUDGET_CUT:
			if FinanceSystem.upkeep_cut_pct(state) >= FinanceSystem.upkeep_cut_max():
				return Loc.t(L.RESEARCH_FRONT_BLOCK_CUT_MAX, {"pct": FinanceSystem.upkeep_cut_max()})
	return ""


## Applies a completed front research. Returns the toast note `{text_key, args}`.
static func on_complete(state: Dictionary, row: Dictionary, _target: String) -> Dictionary:
	var p2: int = String(row.get("p2", "0")).to_int()
	match String(row.get("p1", "")):
		P_BUDGET_CUT:
			var before: int = FinanceSystem.upkeep_cut_pct(state)
			var total: int = FinanceSystem.add_upkeep_cut(state, p2)
			return {"text_key": L.RESEARCH_FRONT_NOTE_BUDGET_CUT, "args": {"pct": total - before, "total": total}}
		P_BOOST:
			var weeks: int = boost_weeks()
			ResearchSystem.add_boost(state, p2, weeks)
			return {"text_key": L.RESEARCH_FRONT_NOTE_BOOST, "args": {"pct": p2, "weeks": weeks}}
		P_EXPAND:
			return {"text_key": L.RESEARCH_FRONT_NOTE_EXPAND, "args": {"level": p2}}
	return {"text_key": "", "args": {}}


## Kind section of the front's facility sheet: budget cut total, running boosts, the
## expansion ladder, the "no facility above the front" rule with every facility's level.
static func make_body(state: Dictionary, _fid: String) -> Control:
	return FrontResearchBody.create(state)


## `FRONT_BOOST_WEEKS`, at least 1.
static func boost_weeks() -> int:
	return maxi(1, ConstTable.int_of("FRONT_BOOST_WEEKS"))


## The `expand` row that unlocks front level `target_level` ({} when none).
static func expand_row(target_level: int) -> Dictionary:
	for raw in ResearchSystem.rows_for(FacilitySystem.FRONT):
		var row: Dictionary = raw
		if String(row.get("p1", "")) == P_EXPAND and String(row.get("p2", "")).to_int() == target_level:
			return row
	return {}


## Progress 0..1 of the expansion research for `target_level` (1 once done; 0 when no row).
static func expand_progress(state: Dictionary, target_level: int) -> float:
	var row: Dictionary = expand_row(target_level)
	if row.is_empty():
		return 0.0
	if FacilitySystem.front_expand_done(state, target_level):
		return 1.0
	return ResearchSystem.progress(state, FacilitySystem.FRONT, String(row["id"]), "")


## Weeks left of that expansion research at the front's current pace (-1 = never: nobody
## seated / not researching; 0 = done).
static func expand_weeks_left(state: Dictionary, target_level: int) -> int:
	var row: Dictionary = expand_row(target_level)
	if row.is_empty():
		return -1
	return ResearchSystem.weeks_left(state, FacilitySystem.FRONT, String(row["id"]), "")
