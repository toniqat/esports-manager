# facility/ — facilities · research (§16)

Contract: `docs/outgame_dev_plan.md` §16 (decisions 1–12, user-confirmed 2026-10-09). This README is the
**frozen API** of the base commit plus the ownership map for the feature agents. Tuning numbers live only in
`data/csv/const.csv` (keys below) and the data CSVs — this file names keys, never values.

| File | Role | Owner after base |
|---|---|---|
| `FacilitySystem.gd` | `class_name FacilitySystem` (static). Facility defs, levels + upgrade (front cap, expansion gate, paid via finance), occupants (manager slots, staff seats), `stat_value`, run init, save migration. | base (frozen) |
| `ResearchSystem.gd` | `class_name ResearchSystem` (static). Research rows, availability, HUB-only selection, per-research progress, weekly gauge, `tick_week`, boosts, kind-handler dispatch. | base (frozen) |
| `research/TrainingResearch.gd` | Kind handler `training` (`train_field` · `train_engage` · `train_growth`) — stub | agent C |
| `research/IntelResearch.gd` | Kind handler `intel` (+ `rank(state, team_id)` helper) — stub | agent E |
| `research/MechResearch.gd` | Kind handler `mech` (`mech_lab`) — stub | agent D |
| `research/FrontResearch.gd` | Kind handler `front` — stub | agent F |
| `research/PersonnelResearch.gd` | Kind handler `personnel` — stub | agent G |
| `FacilitySheet.gd` + `UI_View_FacilitySheet.tscn` | Facility sheet (`HubSheet` body) — see "UI" below | agent B |
| `UI_Comp_FacilityOccupantRow.tscn` · `UI_Comp_ResearchRow.tscn` · `UI_Comp_ResearchTargetChip.tscn` | Sheet list items (occupant · research row · target chip) | agent B |
| `ResearchBubble.gd` + `UI_Comp_ResearchBubble.tscn` | Map speech bubble per facility (hub: tappable, week screen: read-only) | agent B |
| `research_ring.gdshader` | Icon masked to a circle as a radial progress bar (bubble · row · sheet head) | agent B |

Agents: **do not edit `FacilitySystem.gd` / `ResearchSystem.gd`** — report needed changes. Kind handlers keep the
four static signatures below; anything else in their file is theirs.

## Facilities (`data/csv/facility_defs.csv`)
`id, kind, name_key, desc_key, stat, spot, icon, cost_pct` — order = `FacilitySystem.FACILITIES`:

| id | kind | stat | spot | auto seat (run start) |
|---|---|---|---|---|
| `train_field` | training | training | `Spot_Fac_TrainField` | `coach_training` |
| `train_engage` | training | training | `Spot_Fac_TrainEngage` | `coach_tactics` |
| `train_growth` | training | training | `Spot_Fac_TrainGrowth` | — |
| `intel` | intel | analysis | `Spot_Fac_Intel` | `analyst` |
| `mech_lab` | mech | knowledge | `Spot_Fac_MechLab` | `coach_knowledge` |
| `front` | front | finance | `Spot_Fac_Front` | `finance` |
| `personnel` | personnel | mental | `Spot_Fac_Personnel` | `assistant` |

`icon` = a quirk image name (`resources/images/quirks/quirk_<icon>.png`, `FacilitySystem.icon_texture(icon)`).
`kind` is an extra column beyond the contract list (the facility → handler map, used by `make_body`).

## State (`season_state`, string keys, JSON round trip → `int()` / `String()` on read)
```
facilities = {fid: {"level": int, "occupant": "" | "manager" | "<staff id>"}}
research   = {"active": {fid: {"rid": String, "target": String}},
              "points": {"<rid>|<target>": int},     # stored progress, kept while paused
              "done":   {"<rid>|<target>": int},     # completion count
              "boosts": [{"pct": int, "weeks_left": int}]}
intel_rank = {"<team_id>": 0..3}                     # all 0 at run start (absent = 0); own team = 3 (IntelResearch.rank)
scout      = {"candidates": [staff id], "week": String}   # filled by PersonnelResearch
```
Target "" = a row without a target, so the key of an untargeted row is `"<rid>|"`.
Run start (`GameManager.start_run`, after the staff snapshot and `FinanceSystem.init_run`): `FacilitySystem.init_run`
— every facility at the team package `facility_level`, team staff seated by `JOB_FACILITY` (a second of the same
job → next free facility in `FACILITIES` order), manager slots empty, research / intel_rank / scout reset.
Save: `features/save_load/` round-trips the four keys; `load_run` → `FacilitySystem.migrate` (old run:
`finance.facility_level` → every facility, key dropped, staff seated; new run: missing keys filled, floats → ints).

## FacilitySystem API (frozen)
```
const FRONT = "front"; FACILITIES: Array; OCC_NONE = ""; OCC_MANAGER = "manager"; JOB_FACILITY: Dictionary
def(fid) -> Dictionary · is_facility(fid) -> bool · facility_name(fid) / facility_desc(fid) -> String
stat_of(fid) -> String · kind_of(fid) -> String · facilities_for_stat(stat) -> Array · icon_texture(icon) -> Texture2D
init_run(state, team_id) · migrate(state)
max_level() -> int                           # min(FACILITY_LEVEL_MAX, facilities.csv rows)
level(state, fid) -> int · set_level(state, fid, lvl)       # front down → others clamped to it
upgrade_cost(state, fid) -> int              # facilities.csv upgrade_cost(level) × cost_pct / 100
upgrade_block_reason(state, fid) -> String   # "" ok · unknown · max · front cap · front expansion · funds
can_upgrade(state, fid) -> bool · upgrade(state, fid) -> String     # pays FinanceSystem.pay_upgrade (fund, then balance)
front_expand_done(state, target_level) -> bool   # front row with p1 "expand", p2 = target level, done ≥ 1
occupant(state, fid) -> String · manager_slots() -> int · manager_slots_used(state) -> int
manager_facilities(state) -> Array · facility_of_staff(state, staff_id) -> String
assign_block_reason(state, fid, who) -> String · assign(state, fid, who) -> String · unassign(state, fid)
free_staff(state) -> Array · run_staff(state, staff_id) -> Dictionary
stat_value(state, fid) -> int                # occupant's value of the facility stat; nobody → STAT_MIN
is_delegated_fid(state, fid) -> bool · occupant_name(state, fid) -> String
```
- `who` = `"manager"` or a run staff id as a string. Seating replaces the current occupant; a staff member seated
  elsewhere moves (one seat per person); the manager is refused past `MANAGER_SLOTS` seats.
- **Front cap**: a non-front facility cannot upgrade to above the front's level; lowering the front (bankruptcy
  downgrade, `FinanceSystem.settle_week`) clamps the others. The front needs `front_expand_done(level + 1)`.
- Assignment is **not** week-locked in the base (only research selection is); the UI may still offer it at HUB only.

## ResearchSystem API (frozen)
```
KINDS = ["training", "intel", "mech", "front", "personnel"] · KEY_SEP = "|"
rows() / rows_for(fid) -> Array · row(rid) -> Dictionary   # {id, facility, kind, name_key, desc_key, weeks,
                                                           #  min_level, repeatable: bool, p1, p2, icon}
row_name(rid) / row_desc(rid) -> String · row_icon(rid) -> Texture2D
cost(row) -> int · base_points() -> int · key_of(rid, target) -> String
can_select(state) -> bool                    # HUB only: season_state.week_day == -1
block_reason(state, fid, row) -> String      # wrong facility · min_level · non-repeatable untargeted done · handler row_available
available(state, fid) -> Array               # rows with block_reason == ""
targets(state, row) -> Array · target_label(state, row, target) -> String
select_block_reason(state, fid, rid, target) -> String · select(state, fid, rid, target = "") -> String
clear(state, fid) -> String · active(state, fid) -> {rid, target} | {}
points(state, rid, target) -> int · done_count(state, rid, target) -> int
progress(state, fid, rid = "", target = "") -> float    # 0..1, rid "" = the active one
level_mult(lvl) · stat_mult(value) · boost_pct(state) · boost_mult(state)
add_boost(state, pct, weeks)                 # for FrontResearch
weekly_points(state, fid) -> int · weeks_left(state, fid, rid = "", target = "") -> int   # -1 never, 0 full
tick_week(state) -> Array[String]            # translated HUB toasts
make_body(state, fid) -> Control             # the facility kind's handler body (may be null)
```
**Selection is HUB-only**: the UI calls `can_select(state)` to enable pickers; `select` / `clear` refuse with
`facility.research.block.week_running` once the week opened. Switching keeps the old row's points (paused, resumable).
Targeted rows need a target from the handler's `targets`; untargeted rows need `target = ""`.

### Gauge (weekly, `tick_week`)
```
points = RESEARCH_BASE_POINTS × level_mult(level) × stat_mult(stat_value) × (1 + Σ boosts.pct / 100)   (rounded)
level_mult(l) = 1 + (l − 1) × RESEARCH_LEVEL_STEP_PCT / 100
stat_mult(v)  = max(RESEARCH_STAT_MULT_MIN, 1 + (v − RESEARCH_STAT_PIVOT) × RESEARCH_STAT_STEP_PCT / 100)
cost(row)     = weeks × RESEARCH_BASE_POINTS
```
`tick_week` (from `SeasonHub._end_week` right after `FinanceSystem.settle_week`; toasts appended to `hub_toasts`):
1. Boosts running this week are summed, then each loses a week (dropped at 0) — a boost added by a completion in
   the same tick starts next week.
2. Per facility in `FACILITIES` order with an occupant and an active row: skipped (paused) while
   `block_reason != ""`; else points added. At `points ≥ cost`: points cleared (overflow is lost), `done += 1`,
   handler `on_complete` → note, toast `facility.toast.research_done` (+ ` · <note>`). The row stays active only
   if `repeatable`, still unblocked and (targeted) its target still offered; otherwise the facility goes idle.

## Kind handlers (`research/<Kind>Research.gd`, static)
```
targets(state, row) -> Array              # [{id: String, label: String, icon?: Texture2D}] — empty = no target
row_available(state, row) -> String       # "" ok, else block reason (current locale)
on_complete(state, row, target) -> Dictionary   # toast note {text_key, args}; text_key "" = none
make_body(state, fid) -> Control          # kind section of the facility sheet; null = none
```
Base stubs return `[]` / `""` / `{text_key: "", args: {}}` / `null` (so intel / mech rows run untargeted until
agents E / D add targets). Row columns per kind (`p1` / `p2` are strings):

| kind | p1 | p2 | completion (agent) |
|---|---|---|---|
| `training` | `training_tiles.id` | — | `TrainingCourses.grant(state, p1, 1)`; `min_level` gates higher grades (C) |
| `intel` | — | — | target team `intel_rank += 1` (max 3) (E) |
| `mech` | — | — | target mech: `MASTERY_GAIN_LAB` to every pilot of mine + research-quirk roll (D) |
| `front` | `budget_cut` / `boost` / `expand` | upkeep −% / research +% / unlocked front level | budget cut, `ResearchSystem.add_boost(pct, FRONT_BOOST_WEEKS)`, expansion needs nothing (F) |
| `personnel` | `scout` | — | `scout.candidates` = `SCOUT_BASE + level × SCOUT_PER_LEVEL` staff (G) |

`expand_<n>` rows = required to upgrade the front **to level n** (`p2 = n`, `min_level = n − 1`), n = 2..max.
The placeholder rows in `research.csv` are a starting set — each kind agent owns and rebalances its rows.

## const.csv keys
Base: `MANAGER_SLOTS`, `FACILITY_LEVEL_MAX`, `RESEARCH_BASE_POINTS`, `RESEARCH_LEVEL_STEP_PCT`, `RESEARCH_STAT_PIVOT`,
`RESEARCH_STAT_STEP_PCT`, `RESEARCH_STAT_MULT_MIN`. Pre-seeded for the agents (theirs to tune / read):
`FRONT_BOOST_WEEKS` (F), `SCOUT_BASE` · `SCOUT_PER_LEVEL` (G), `MASTERY_GAIN_LAB` (D). New keys: append at the end,
own prefix.

## Localization — one domain file per owner
| Domain file (`data/l10n/src/`) | Holds | Owner |
|---|---|---|
| `facility.csv` | `facility.def.{id}.name/desc` (data) + base code keys `facility.block.*`, `facility.research.block.*`, `facility.toast.*` | base |
| `facility_ui.csv` (empty) | facility sheet / bubble / map captions | B |
| `research_training.csv` | `research_training.{id}.name/desc` (training rows) + C's code keys | C |
| `research_mech.csv` | mech rows + D's code keys | D |
| `research_intel.csv` | intel rows + E's code keys | E |
| `research_front.csv` | front rows + F's code keys | F |
| `research_personnel.csv` | personnel rows + G's code keys | G |

`research.csv` alias rule (config `data_columns`): `research_{kind}.{id}.name` / `.desc` — issue new row keys with
`new_keys` in the kind's domain (never `extract data`). A code key in a `research_*` domain must not have the shape
`research_<x>.<y>.name|desc` (that is a data alias and gets no `L` constant) — use e.g. `research_mech.note.done`.
Other agents' existing domains (`training`, `mastery`, `finance`, `staff`, `match` …) stay with their owners.

## UI (agent B)
**Map bubbles** — every team map (`week/base_map/`) has seven `Spot_Fac_*` markers (`facility_defs.csv` `spot`) and
a `%Facilities` layer under the pilot tokens. `ResearchBubble.populate(map, state, interactive)` puts one bubble per
marker (reused on refill; the stadium has no layer → none) with its tail tip (`%TailTip`) on the spot. The bubble
shows the facility name, the active research icon (`ResearchSystem.row_icon`, else the facility icon) through
`research_ring.gdshader` — circle mask + clockwise ring up to `ResearchSystem.progress`, the icon in colour only
inside the filled sector — and the percent below. Idle states replace the percent and grey the icon, in this order:
`공석` (nobody seated, red) · `대기` (no active research) · `정지` (active row blocked). Hub
(`features/season/HubView.gd`): interactive, `pressed(fid)` → `FacilitySheet.open(hub, fid)`; `%Hit` also covers the
spot under the tail (the building). Week screen (`week/WeekProgressView._add_map_section`, team map only):
read-only, mouse ignored.

**Facility sheet** — `FacilitySheet.open(host, fid) -> HubSheet` (title = facility name). Sections: head (ring icon,
desc, `<stat> 스탯 <value>` = `FacilitySystem.stat_value`, weekly points / red "nobody" line) · level (`Lv n / max`,
front-cap or expansion note, cost from `FacilitySystem.upgrade_cost` + `FinanceSystem.upgrade_funds`, two-step
upgrade like the finance sheet, else a disabled button with `upgrade_block_reason`) · occupants (`담당 … · 감독 자리
n/3`, then the manager and every run staff member with their value of this facility's stat; `배치` =
`FacilitySystem.assign` — disabled with `assign_block_reason` in red, `해제` on the seated one) · research
(active line + %, `연구 중지` = `ResearchSystem.clear`, one `ResearchRow` per `rows_for(fid)`: ring icon, name,
desc, weeks · weeks left · done count, progress bar, `진행 중` / `대상 선택`, blocked rows disabled with
`block_reason`) · target picker (a row whose handler offers `targets`: tapping the row opens chips `label NN%`,
a chip = `select(fid, rid, target)`; untargeted row tap = `select(fid, rid, "")`) · kind body. Seating and
selection are enabled only while `ResearchSystem.can_select(state)` (HUB); otherwise a red note. Every change
refills in place (rows reused).

**Kind body slot** (`%KindSlot`, hidden when `ResearchSystem.make_body` returns null): after every refill the
sheet calls the body's `refresh()` if it has one, else frees it and builds a new one; a `changed` signal on the
body (any payload) refills the whole sheet, deferred. Bodies are top-wide with their natural height.

F6 previews: `UI_View_FacilitySheet` (in-memory run, manager seated in `train_field`, first row selected, one
week ticked) · `UI_Comp_ResearchBubble` (40 % running) · items show their scene sample values. Display text:
`data/l10n/src/facility_ui.csv` (`facility_ui.*`).
