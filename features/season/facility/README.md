# facility/ — facilities · research (§16)

Contract: `docs/outgame_dev_plan.md` §16 (decisions 1–12, user-confirmed 2026-10-09). **UI rework 2026-10-09**
(user): the facility sheet popup became a **screen** (`FacilityView`), the front lost its research (no expansion
gate, no budget cut, no boosts), the personnel office researches on its own, intel / mech have one row each.
Tuning numbers live only in `data/csv/const.csv` (keys below) and the data CSVs — this file names keys, never values.

| File | Role |
|---|---|
| `FacilitySystem.gd` | `class_name FacilitySystem` (static). Facility defs, levels + upgrade (front cap, paid via finance), occupants (manager slots, staff seats), `stat_value`, icons, run init, save migration. |
| `ResearchSystem.gd` | `class_name ResearchSystem` (static). Research rows, availability, HUB-only selection, auto facilities, per-research progress, weekly gauge, `tick_week`, kind-handler dispatch, `make_body`. |
| `FacilityView.gd` + `UI_View_FacilityView.tscn` | **Facility screen** (`SeasonHub.Screen.FACILITY`) — "UI" below |
| `OccupantPicker.gd` + `UI_View_OccupantPicker.tscn` | Modal occupant picker: manager + run staff as `staff/StaffThumb` cards (3 columns) with the facility stat |
| `FrontBody.gd` + `UI_View_FrontBody.tscn` | Front body (no research): cap rule + every other facility's level |
| `ResearchBubble.gd` + `UI_Comp_ResearchBubble.tscn` | Map speech bubble per facility (hub: tappable, week screen: read-only) |
| `research_ring.gdshader` | Icon masked to a circle as a radial progress bar (bubble) |
| `research/TrainingResearch*` · `research/UI_*_TrainingResearch*` | Kind `training` handler + body (research cards) + owned courses modal |
| `research/IntelResearch*` · `research/UI_Comp_IntelResearchBody.tscn` | Kind `intel` handler + body (+ `rank(state, team_id)`) |
| `research/MechResearch.gd` | Kind `mech` handler; body = `mastery/MechLabBody` |
| `research/PersonnelResearch.gd` | Kind `personnel` handler (auto); body = `staff/PersonnelBody` |

**Icons** — temporary pictograms (`resources/images/`, svg): facilities `facilities/fac_<fid>.svg`
(`FacilitySystem.icon_of(fid)`), staff / manager bust `staff/*.svg` (`resources/StaffImages.portrait(who)`), team logos
`team_logos/team_<id>.svg` (`resources/TeamLogos.texture(team_id)`, INTL teams borrow `id % 8`).

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

`icon` = pictogram name (`fac_<icon>.svg`, today the facility id). `research.csv` `icon` is empty on every row —
`ResearchSystem.row_icon` falls back to the facility icon. `kind` = the facility → handler / body map. The front's
`desc_key` is still in the data but no screen shows facility descriptions any more.

## State (`season_state`, string keys, JSON round trip → `int()` / `String()` on read)
```
facilities = {fid: {"level": int, "occupant": "" | "manager" | "<staff id>"}}
research   = {"active": {fid: {"rid": String, "target": String}},
              "points": {"<rid>|<target>": int},     # stored progress, kept while paused
              "done":   {"<rid>|<target>": int}}     # completion count   (an old save's "boosts" is dropped)
intel_rank = {"<team_id>": 0..3}                     # all 0 at run start (absent = 0); own team = 3 (IntelResearch.rank)
scout      = {"candidates": [staff id], "week": String}   # filled by PersonnelResearch
```
Target "" = a row without a target, so the key of an untargeted row is `"<rid>|"`.
Run start (`GameManager.start_run`, after the staff snapshot and `FinanceSystem.init_run`): `FacilitySystem.init_run`
— every facility at the team package `facility_level`, team staff seated by `JOB_FACILITY` (a second of the same
job → next free facility in `FACILITIES` order), manager slots fill the seats still empty, in `MANAGER_AUTO_ORDER`
(growth → front → …; user decision 2026-10-09), research / intel_rank / scout reset, then `ResearchSystem.ensure_auto`.
Save: `features/save_load/` round-trips the four keys; `load_run` → `FacilitySystem.migrate` (old run:
`finance.facility_level` → every facility, key dropped, staff seated; new run: missing keys filled, floats → ints;
both end with `ensure_auto`).

## FacilitySystem API
```
const FRONT = "front"; FACILITIES: Array; OCC_NONE = ""; OCC_MANAGER = "manager"; JOB_FACILITY: Dictionary
def(fid) -> Dictionary · is_facility(fid) -> bool · facility_name(fid) / facility_desc(fid) -> String
stat_of(fid) -> String · kind_of(fid) -> String · facilities_for_stat(stat) -> Array
icon_texture(icon) -> Texture2D · icon_of(fid) -> Texture2D
init_run(state, team_id) · migrate(state)
max_level() -> int                           # min(FACILITY_LEVEL_MAX, facilities.csv rows)
level(state, fid) -> int · set_level(state, fid, lvl)       # front down → others clamped to it
upgrade_cost(state, fid) -> int              # facilities.csv upgrade_cost(level) × cost_pct / 100
upgrade_block_reason(state, fid) -> String   # "" ok · unknown · max · front cap · funds
can_upgrade(state, fid) -> bool · upgrade(state, fid) -> String     # pays FinanceSystem.pay_upgrade (fund, then balance)
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
  downgrade, `FinanceSystem.settle_week`) clamps the others. The front itself only needs the money.
- Assignment is not week-locked in the system (only research selection is); the UI offers it at HUB only.

## ResearchSystem API
```
KINDS = ["training", "intel", "mech", "personnel"] · AUTO_KINDS = ["personnel"] · KEY_SEP = "|"
rows() / rows_for(fid) -> Array · row(rid) -> Dictionary   # {id, facility, kind, name_key, desc_key, weeks,
                                                           #  min_level, repeatable: bool, p1, p2, icon}
row_name(rid) / row_desc(rid) -> String · row_icon(rid) -> Texture2D   # icon "" → facility icon
cost(row) -> int · base_points() -> int · key_of(rid, target) -> String
can_select(state) -> bool                    # HUB only: season_state.week_day == -1
block_reason(state, fid, row) -> String      # wrong facility · min_level · non-repeatable untargeted done · handler row_available
available(state, fid) -> Array               # rows with block_reason == ""
targets(state, row) -> Array · target_label(state, row, target) -> String
select_block_reason(state, fid, rid, target) -> String · select(state, fid, rid, target = "") -> String
clear(state, fid) -> String · active(state, fid) -> {rid, target} | {}      # no UI calls clear any more
is_auto(fid) -> bool · ensure_auto(state)    # auto facility idle → its first available row (first target)
unset_facilities(state) -> Array             # non-auto facilities with rows, nothing active, something available
points(state, rid, target) -> int · done_count(state, rid, target) -> int
progress(state, fid, rid = "", target = "") -> float    # 0..1, rid "" = the active one
level_mult(lvl) · stat_mult(value)
weekly_points(state, fid) -> int · weeks_left(state, fid, rid = "", target = "") -> int   # -1 never, 0 full
tick_week(state) -> Array[String]            # translated HUB toasts
make_body(state, fid) -> Control             # the facility screen body (by facility kind, front = FrontBody)
```
**Selection is HUB-only**: bodies call `can_select(state)` to enable pickers; `select` / `clear` refuse with
`facility.research.block.week_running` once the week opened. Switching keeps the old row's points (paused, resumable).
Targeted rows need a target from the handler's `targets`; untargeted rows need `target = ""`. There is no "stop"
button anywhere (user decision 2026-10-09) — picking another row / target is the only switch.
**Start-week warning**: HubView "이번 주 시작" asks first (`ConfirmPopup`) when `unset_facilities` is not empty.

### Gauge (weekly, `tick_week`)
```
points = RESEARCH_BASE_POINTS × level_mult(level) × stat_mult(stat_value)   (rounded)
level_mult(l) = 1 + (l − 1) × RESEARCH_LEVEL_STEP_PCT / 100
stat_mult(v)  = max(RESEARCH_STAT_MULT_MIN, 1 + (v − RESEARCH_STAT_PIVOT) × RESEARCH_STAT_STEP_PCT / 100)
cost(row)     = weeks × RESEARCH_BASE_POINTS
```
`tick_week` (from `SeasonHub._end_week` right after `FinanceSystem.settle_week`; toasts appended to `hub_toasts`):
`ensure_auto`, then per facility in `FACILITIES` order with an occupant and an active row: skipped (paused) while
`block_reason != ""`; else points added. At `points ≥ cost`: points cleared (overflow is lost), `done += 1`,
handler `on_complete` → note, toast `facility.toast.research_done` (+ ` · <note>`). The row stays active only
if `repeatable`, still unblocked and (targeted) its target still offered; otherwise the facility goes idle.
`ensure_auto` again at the end (an auto facility never idles while a row is available).

## Kind handlers (`research/<Kind>Research.gd`, static)
```
targets(state, row) -> Array              # [{id: String, label: String, icon?: Texture2D}] — empty = no target
row_available(state, row) -> String       # "" ok, else block reason (current locale)
on_complete(state, row, target) -> Dictionary   # toast note {text_key, args}; text_key "" = none
make_body(state, fid) -> Control          # the facility screen body (Body contract below); null = empty screen
```
| kind | rows | p1 | p2 | completion |
|---|---|---|---|---|
| `training` | one per course tile (below) | `training_tiles.id` | — | `TrainingCourses.grant(state, p1, 1)` |
| `intel` | `in_scout` | — | — | target team `intel_rank += 1` (max 3) |
| `mech` | `mech_study` | gain % ("" = 100) | — | target mech: `MASTERY_GAIN_LAB` to every pilot of mine + research-quirk roll |
| `personnel` | `scout` (auto) | `scout` | extra candidates | `scout.candidates` = `SCOUT_BASE + level × SCOUT_PER_LEVEL` staff |

## UI
**Map bubbles** — every team map (`week/base_map/`) has seven `Spot_Fac_*` markers (`facility_defs.csv` `spot`) and
a `%Facilities` layer under the pilot tokens. `ResearchBubble.populate(map, state, interactive)` puts one bubble per
marker (reused on refill; the stadium has no layer → none) with its tail tip (`%TailTip`) on the spot. The bubble
shows the facility name, the facility icon through `research_ring.gdshader` — circle mask + clockwise ring up to
`ResearchSystem.progress` — and the percent below. Idle states replace the percent and grey the icon, in this order:
`공석` (nobody seated, red) · `대기` (no active research) · `정지` (active row blocked). Hub
(`features/season/HubView.gd`): interactive, `pressed(fid)` → `SeasonHub.open_facility(fid)`; `%Hit` also covers the
spot under the tail (the building). Week screen (`week/WeekProgressView._add_map_section`, team map only):
read-only, mouse ignored.

**Facility screen** — `SeasonHub.open_facility(fid)` → `FacilityView.show_facility(state, fid)` + `Screen.FACILITY`;
`허브로 돌아가기` (bottom bar, right) → HUB. The screen never scrolls as a whole.
- Header: facility icon · name · status (`주간 연구량 n`, red `담당자가 없어…` when vacant, the HUB-only note once the
  week runs; nothing for the front). No facility description, no stat line.
- **Occupant button** (left of the upgrade): occupant portrait + name, the facility stat value at the button's
  bottom (red when vacant). Tap → `OccupantPicker` (dimmed modal): manager + every run staff member as `StaffThumb`
  cards, 3 columns, `<stat> <value>` under each; tap = `FacilitySystem.assign` and close, `자리 비우기` =
  `unassign`; disabled outside HUB or with `assign_block_reason` (red sub line).
- **Level + upgrade** (top right): `Lv n / max`; the upgrade button is lit (`PrimaryButton`) only when
  `FacilitySystem.can_upgrade`, else `GhostButton` whose tap toasts `upgrade_block_reason`; lit tap →
  `ConfirmPopup` (Lv n → n+1, cost, available funds) → `FacilitySystem.upgrade`.
- `%BodySlot` (1000 wide, header bottom → just above the bar) holds `ResearchSystem.make_body(state, fid)`.
- Bottom bar: the body's action (left, hidden when none) · `허브로 돌아가기` (right, primary). Toast above the bar.

### Body contract (`ResearchSystem.make_body` → `FacilityView`)
The body is added under `%BodySlot` with **full-rect anchors** and must fit it: lists / grids scroll **inside** the
body (`ScrollContainer` + `DragScroll.attach`), the rest of the body stays put. Duck-typed optional members:
```
refresh()                        # called after the header changed (seat, upgrade) — refill in place
signal changed                   # the body changed state (selection, hire …) → the header refreshes (deferred)
signal message(text: String)     # shown as the screen's toast (refusals, results)
bottom_action_text() -> String   # label of the bar's left slot ("" = slot hidden); re-read after every refresh
on_bottom_action()               # that slot was pressed (e.g. open a modal)
```
Selection is HUB-only (`ResearchSystem.can_select`); a body disables its pickers otherwise. Every body keeps an F6
preview (in-memory run). Bodies: training → `research/TrainingResearchBody`, intel → `research/IntelResearchBody`,
mech → `mastery/MechLabBody`, front → `FrontBody`, personnel → `staff/PersonnelBody`.

F6 previews: `UI_View_FacilityView` (in-memory run, the intel screen) · `UI_View_OccupantPicker` (intel) ·
`UI_View_FrontBody` · `UI_Comp_ResearchBubble` (40 % running). Display text: `data/l10n/src/facility_ui.csv`
(`facility_ui.*`).

## const.csv keys
`MANAGER_SLOTS`, `FACILITY_LEVEL_MAX`, `RESEARCH_BASE_POINTS`, `RESEARCH_LEVEL_STEP_PCT`, `RESEARCH_STAT_PIVOT`,
`RESEARCH_STAT_STEP_PCT`, `RESEARCH_STAT_MULT_MIN`; `SCOUT_BASE` · `SCOUT_PER_LEVEL` (personnel), `MASTERY_GAIN_LAB`
(mech). New keys: append at the end, own prefix. (`FRONT_BOOST_WEEKS` · `FINANCE_UPKEEP_CUT_MAX_PCT` were removed
with the front research.)

## Localization — one domain file per owner
| Domain file (`data/l10n/src/`) | Holds |
|---|---|
| `facility.csv` | `facility.def.{id}.name/desc` (data) + code keys `facility.block.*`, `facility.research.block.*`, `facility.toast.*` |
| `facility_ui.csv` | facility screen / picker / front body / bubble / hub warning (`facility_ui.*`) |
| `research_training.csv` · `research_intel.csv` · `research_mech.csv` · `research_personnel.csv` | `research_{kind}.{id}.name/desc` (rows) + the kind's code keys |

`research.csv` alias rule (config `data_columns`): `research_{kind}.{id}.name` / `.desc` — issue new row keys with
`new_keys` in the kind's domain (never `extract data`). A code key in a `research_*` domain must not have the shape
`research_<x>.<y>.name|desc` (that is a data alias and gets no `L` constant) — use e.g. `research_mech.note.done`.

## PersonnelResearch (`research/PersonnelResearch.gd`) — auto, no selection
Row (`research.csv`, facility `personnel`, repeatable): `scout` (Lv1+); `p1 = scout`, `p2` = extra candidates.
The facility is in `ResearchSystem.AUTO_KINDS` — `ensure_auto` keeps `scout` active, the gauge just runs.
- `targets` → none. `row_available` → `research_personnel.block.no_pool` while the scouting pool is empty.
- `on_complete` → `scout.candidates` = `draw(state, candidate_count(state, row), seed)` — a new list replaces an
  unanswered one; `scout.week = MentalSystem.week_key`. Note `research_personnel.note.candidates` {n}
  (or `.note.none`). `candidate_count = SCOUT_BASE + level(personnel) × SCOUT_PER_LEVEL + p2`; pool =
  `StaffSystem.free_agent_ids()` (staff.csv rows on no team) minus the run team; seed =
  `hash("run_seed|week_key|rid|done_count")` (the drawn list itself is saved).
- Helpers: `candidate_count` · `pool` · `draw(state, n, seed)` · `candidates(state)` (ints, hired ones skipped) ·
  `hire_candidate(state, id)` (`StaffSystem.hire`, then the list is consumed) · `pass_all(state)`.
- `make_body` → `staff/PersonnelBody` — `features/season/staff/README.md` "Personnel body".

## IntelResearch (`research/IntelResearch.gd` · `research/IntelResearchBody.gd` · `research/UI_Comp_IntelResearchBody.tscn`)
- **Field** (`field(state)`): the teams of the competition I play in now, without my team — the INTL bracket
  teams while I am in that bracket (`current_tournament.type == "INTL"`), else every league team
  (`GameManager.TEAM_COUNT`; playoffs use the league too). My next opponent (`next_opponent`: first unplayed
  match with me in `current_tournament.bracket`, then `match_schedule`) is moved to the front.
- `targets`: the field's teams below `MAX_RANK` (3), id = team id string, label `research_intel.target`
  (`<short> · 분석 r/3`) or `research_intel.target_next` (`… · 다음 상대`). `row_available` blocks
  (`research_intel.block.no_target`) once every field team is at 3. Rank-3 teams are not offered, so the
  repeatable row goes idle when its target reaches 3.
- `on_complete`: `intel_rank["<team>"] = min(3, rank + 1)`, note `research_intel.note.rank_up` (`<short> 분석 n단계`).
- `rank(state, team_id)`: 0..3 from `intel_rank`, own team 3. Read by `OpponentIntel.tier_for` (PREP · ban/pick ·
  league team detail; + the `analysis_tier` traits) — `features/match_flow/match_prep/README.md` "Reveal tiers".
- Row (`research.csv`, facility `intel`): `in_scout` only (2 weeks, Lv1+, repeatable) — `in_deep` was removed.
- `make_body` → `IntelResearchBody` — *being reworked (2026-10-09 UI rework).*

## MechResearch (`research/MechResearch.gd`, `mech_lab`)
- **Row** (`research.csv`, l10n `research_mech`): `mech_study` (2 weeks, Lv1, repeatable) — `mech_deep` was
  removed. `p1` = gain percent of `MASTERY_GAIN_LAB` (empty = 100).
- **`targets`**: every mech that at least one of my pilots can still grow on (below `MASTERY_MAX`), mechs my
  pilots' roles use first (count of my pilots with that role, desc), then mech id. `{id: "<mech id>",
  label: mech name, icon: MechImages.portrait_for}`. The repeatable row goes idle once its mech is maxed for
  all five (target no longer offered). **`row_available`**: blocked outside a run.
- **`on_complete`**: each of my five pilots `MechMastery.gain(state, pid, mech, raw_gain(row))` (knowledge =
  the lab occupant through `StaffSystem.effective`, `FinanceSystem.mastery_mult`, trait `mastery_pct`), then
  `quirk_roll` (`QUIRK_RESEARCH_CHANCE`% per pilot, seeded per run · phase · week · pilot · `"quirk_research"`).
  Note `research_mech.note.done` = `{mech} 숙련도 +{n}{extra}` — `extra` = ` · 레벨 업 <name LvN, …>` and/or
  ` · 기벽 획득 <name quirk, …>`.
- Helpers: `FID`, `lab_mech(state)` (the lab's active target mech, -1 idle — read by `SeasonPilotDetail` and
  `FocusTraining.story_mech`), `raw_gain(row)`, `quirk_roll(state, pid) -> quirk id | -1`.
- **`make_body`** → `MechLabBody.create(state)` (`features/season/mastery/`) — *being reworked (2026-10-09).*

## TrainingResearch (`research/TrainingResearch.gd`, kind `training`)
Files: `research/TrainingResearch.gd` (handler + course→facility map), `research/TrainingResearchBody.gd` +
`UI_View_TrainingResearchBody.tscn` (body), `research/TrainingResearchCard.gd` + `UI_Comp_TrainingResearchCard.tscn`
(one research card), `research/TrainingResearchOwned.gd` + `UI_View_TrainingResearchOwned.tscn` (owned courses modal).

- **Rows** (`research.csv`, `facility` = `train_*`): one row per training tile except Basic Training I (`T01`,
  owned from the start) — every other tile in `training_tiles.csv` is granted by exactly one row. `p1` = tile id.
  Ladder: grade C / B / A / S → `min_level` 1 / 2 / 3 / 4 and more `weeks` (stat lines 2 / 3 / 4); basic II / III /
  IV = `min_level` 1 / 3 / 5, `weeks` 3 / 5 / 7 (they raise every empty cell). Basic rows `repeatable = 0`, the rest 1.

  | Facility | Rows |
  |---|---|
  | `train_field` | `tr_h1..3` 사격 I~III (H) · `tr_e1..3` 회피 기동 I~III (E) |
  | `train_engage` | `tr_c1..3` 근접 교전 (C) · `tr_d1..3` 반응 (D) · `tr_scrim` 합숙 스크림 (CC/DD, Lv4) |
  | `train_growth` | `tr_a1..3` 화력 증강 (A) · `tr_p1..3` 내구 단련 (P) · `tr_b2..4` 기초 훈련 II~IV · `tr_q1..4` quirk tiles · `tr_joint` · `tr_focus` · `tr_meeting` · `tr_mentor` · `tr_camp` (amplifier / misc) |
- **`row_available`**: blocked (`research_training.block.owned_higher`) when the tile's line is owned at a **higher**
  grade — a lower row would only add a copy the owned-level row also adds; for the basic line (unlimited copies)
  at this grade **or higher**. Same grade = one more copy (repeatable rows stay selected and keep adding copies).
- **`on_complete`**: `TrainingCourses.grant(state, p1, 1)`; note `research_training.note.basic` (basic upgraded) ·
  `.upgrade` (`{from} → {tile}`, board copies retargeted) · `.gain` (`{tile} +1 (보유 n)`).
- **Per-facility training stat** (decision 3): `TrainingResearch.facility_of_tile(tile_id)` / `facility_of_line`
  = the training facility whose rows grant that line (map built once from `research.csv`); no row (Basic Training
  I) → `DEFAULT_FACILITY` = `train_growth`. `exp_mult(state, fid)` =
  `TrainingTile.training_exp_mult(FacilitySystem.stat_value(state, fid))`. `TrainingBoard.exp_mult_table` uses it
  per cell — details in `features/season/training/README.md` "Training stat — per facility". Other helpers:
  `FACILITIES`, `ladder(fid)`.
- **Body** (`TrainingResearchBody`, UI rework 2026-10-09 by the user): no "진행 중" line, no row description, no
  ladder section. The facility's rows (CSV order) as `TrainingResearchCard`s in a **3-column grid scrolling inside
  the body** (card height from the scene: ≈ 4.5 rows in the 1540 px slot of a 1080×1920 screen, more rows on long
  phones). A row is **hidden** when it gives nothing any more (`row_available` blocked = line owned higher, or a
  finished non-repeatable basic row) unless it is the active one; below `min_level` it is faded with `Lv n 필요`.
  Card: the course thumbnail in the training-board look (`training/UI_Comp_TrainingCourseCard`, cap = owned copies
  of exactly that tile `×n` / `∞` / `미보유`), a status line (`n주 연구` · active `n주 남음` (`weeks_left`;
  `연구 중` when no rate) · active-but-blocked `정지됨`), and the progress bar **split into `weeks` segments**
  (segment i = `clamp(progress × weeks − i, 0, 1)`, `progress` = `ResearchSystem.progress`). Active card =
  `SelectableCardOn`. Tap a card = `ResearchSystem.select(state, fid, rid, "")` (HUB only — `Hit` disabled
  otherwise, refusals → `message`) → `changed` + refill. Tap a thumbnail = the course info popover
  (`training/UI_View_TrainingCoursePopover`, instanced in the body outside the scroll, below the thumbnail or
  above it; `%InfoCatcher` closes it on any tap). Bottom bar action `보유 중인 훈련 코스` → `TrainingResearchOwned`
  (CanvasLayer modal, dim: every owned course (`TrainingCourses.owned_tile_ids`) as a `TrainingCourseCard`,
  5 columns, scroll capped to the safe area, tap = the same popover, close button / dim tap closes).
  `TrainingResearchBody.cap_of(state, tile)` · `place_popover(pop, at, bounds)` are shared with the modal.
  F6 previews: body (`train_field` Lv2, two courses owned, 사격 훈련 II active at 45 %), card, owned modal.
- l10n: rows `research_training.<rid>.name/desc` (the `desc` cells are no longer shown); code keys
  `research_training.block.*` · `.note.*` · `.card.*` · `.owned.title`; scene `.training_research_owned.sub`.
