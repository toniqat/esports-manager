# staff/ — manager · staff stats (M3)

Contract: `docs/outgame_dev_plan.md` §11. Single entry point for every manager-stat read in a run.
Display text is l10n keys (`staff` domain; shared `term.person.*` · `term.week.*`). `STAT_LABELS` / `JOB_LABELS` /
`StaffPanel.DIRECT_TASKS` values are **keys** — show them with `StaffSystem.stat_label(stat)` / `job_label(job)`, never raw.
The staff section title in `UI_View_StaffPanel.tscn` is `term.person.staff`. `term.manager_stat.*` (the six manager stat
names) are also referenced as `{tx_…}` by finance specials, manager type descs and training / mastery lines.

| File | Role |
|---|---|
| `StaffSystem.gd` | `class_name StaffSystem` (static). Tables `manager_types` / `staff` / `teams.staff_ids`; run snapshot (`snapshot_for_run` → `run_setup.manager_type/manager_stats/staff`); cover rule **§16: facility occupants** — `effective(state, stat)` = max over the stat's facilities (`FacilitySystem.facilities_for_stat`) of the occupant's value (manager + staff_mods / staff stat / `STAT_MIN` when empty; `tactics` = manager); `owner` (`manager` / `assistant` / `staff` / `none`) / `owner_name` / `is_delegated` (staff or assistant seated); `staff_for` = the staff whose seat supplies the stat; **hire / dismiss (§16)** — `free_agent_ids()` (staff on no team's `staff_ids` = the scouting pool), `is_hired`, `hire_block_reason` / `hire(state, id)` (appends a copy of `staff_row` to `run_setup.staff`, the `snapshot_for_run` shape, unseated), `dismiss_block_reason` / `dismiss(state, id)` (a seated staffer is `FacilitySystem.unassign`ed first, then removed); salary totals follow from `run_setup.staff`; `staff_name(e)` — staff rows (`staff_row`, `run_setup.staff[]`) hold the l10n key `name_key` (`name.staff.*`) only, never the text (D7); `effective_for_incident`; temporary mods `add_mod` / `decay_mods` (week end); coach points `coach_points_grant` / `grant_coach_points` / `coach_points` / `spend_coach_points` (§15 D). |
| `StaffPanel.gd` + `UI_View_StaffPanel.tscn` | Hub manage card + `HubSheet` body — see "Hub card + sheet" below. |
| `UI_Comp_StaffStatRow.tscn` · `UI_Comp_StaffTraitRow.tscn` · `UI_Comp_StaffMemberRow.tscn` | Item scenes of the sheet (no script): one 능력치 row · one 장착 특성 row · one 스태프 row. |
| `PersonnelBody.gd` + `UI_View_PersonnelBody.tscn` | §16 body of the 인력 개발실 (`personnel`) facility screen, built by `facility/research/PersonnelResearch.make_body` — see "Personnel body" below. |
| `StaffThumb.gd` + `UI_Comp_StaffThumb.tscn` | Shared person thumbnail card (Button): portrait (`resources/StaffImages`, temporary bust pictogram) · name · sub line (red = block reason) · value line; `show_person(who, name, sub, value, on, sub_bad)` / `set_on`, `who` = `"manager"` / staff id string. Used by `facility/OccupantPicker` and the personnel body. F6 = the manager card. |

Rules
- Stats are 1..20 (`STAT_MIN` / `STAT_MAX`), six keys `StaffSystem.STATS`.
- §16: a stat is read from whoever **sits in its facility** (`facility_defs.csv` `stat`: training ← `train_field` · `train_engage` · `train_growth`, analysis ← `intel`, knowledge ← `mech_lab`, finance ← `front`, mental ← `personnel`; `tactics` has none). `JOB_STAT` is only the specialty label; any staff may sit anywhere (`FacilitySystem.assign`). Ties go staff → assistant → manager (the delegated side wins); an empty seat gives `STAT_MIN` and owner `none` (not delegated).
- Interviews / outings read `manager_value(state, "mental")` only; incidents read `effective_for_incident`.
- The **finance** stat has a real effect besides "who allocates": `effective(state, "finance")` scales sponsor
  income and upkeep continuously (`FinanceSystem.finance_stat_income_mult` / `finance_stat_upkeep_mult`,
  `FINANCE_STAT_*`) — see `features/season/finance/README.md`.
- `staff_mods.source` is an id, never text (D7): `finance:<special id>` (the finance sheet's `coach_hire` specials,
  bought with balance — `FinanceSystem.buy_special`) or `mental:<event id>` (interview / outing / press / incident
  clauses). `StaffSystem.mod_source_text(source)` turns it into the special's name / the event kind's label.
- **Coach points** (§15 D, afternoon visit focus training): a weekly budget
  `COACH_POINTS_BASE + floor(COACH_POINTS_PER × effective(state, "training"))` (`coach_points_grant`), granted at week
  start (`grant_coach_points`, `SeasonHub.on_training_confirmed`) and never carried over. State
  `season_state.coach_points` (int) + `coach_week` (the `MentalSystem.week_key` it belongs to); `coach_points(state)`
  grants lazily when the week key changed (old saves), `spend_coach_points(state, n)` → false when short.
  Spent by `features/season/mental/FocusTraining.gd`; shown on the week screen's afternoon card and the visit popup.
- `manager_types()` rows hold l10n keys `name_key` / `desc_key` (`manager.type.{id}.name/desc`); screens `Loc.t` them.

## Staff pool (`data/csv/staff.csv`)
Ids 1–57 are the teams' initial staff (`teams.staff_ids`); ids 101+ are **free agents** (on no team) — the only
rows personnel scouting can draw (`free_agent_ids`). Names are data aliases `name.staff.{id}` in
`data/l10n/src/name.csv` (domain `name`, issued with `new_keys`). Jobs are specialty labels only (§16).

## Personnel body (`PersonnelBody.gd`)
Body of the `personnel` facility screen (`FacilityView` %BodySlot, full rect; `PersonnelResearch.make_body(state, fid)`
→ `PersonnelBody.create()` + `bind(state)`). The office researches on its own (`ResearchSystem.AUTO_KINDS`), so there
is no picker, no description, no "in progress" line (user, 2026-10-09). Text keys: `research_personnel.body.*`
(`data/l10n/src/research_personnel.csv`) + `staff.panel.salary`. Cards = `StaffThumb` (`who` = staff id string).

| Section | Shows / does |
|---|---|
| 스태프 목록 | Title line: title left, `n명 · 주급 합계 x` (`%StaffSub`) at the right end. Every `run_setup.staff` entry as a card (sub = `<job> · <facility>` / `<job> · 배치 없음`, value = weekly salary), 3-column grid; `%StaffScroll` is fixed at 2.5 card rows (881 px) and scrolls inside. Nobody hired → `%StaffEmpty` instead. Tap → `ConfirmPopup` (`<name> 해고`: job · salary, the six stats on two lines, a seated staffer adds "the seat empties"; danger button) → `StaffSystem.dismiss`. |
| 영입 후보 | Header line: title · scouting gauge (`ProgressTrack` / `%ScoutFill`, `anchor_right` = `ResearchSystem.progress(state, "personnel")`) · `스카우트 n%` (`ResearchBubble.percent_text`). `PersonnelResearch.candidates(state)` as cards (sub = job, value = salary), 3 columns; `%CandScroll` takes the rest of the body and scrolls inside. No empty-state text, no pass-all button. Tap → `ConfirmPopup` (`<name> 영입`, same info, "the other n go back" when others remain) → `PersonnelResearch.hire_candidate` (the list is consumed). |

Refusals (`hire_block_reason` / `dismiss_block_reason` / the action's result) go out as `message` (screen toast).
After a hire / dismiss the body refills and emits **`changed`** (the facility header and the occupant picker read
staff). Hire / dismiss are not week-locked. F6: `UI_View_PersonnelBody.tscn` alone fills the in-memory run, four
drawn candidates and the gauge at 40 %.

## Hub card + sheet (`StaffPanel.gd`)
Contract §11.2 — static `hub_summary(state)` / `open(host)`; fills only, every value comes from `StaffSystem`.
`open` = `HubSheet.open_on` + `StaffPanel.create()` added to `sheet.body` (read-only, filled once).
**F6 preview** — run `UI_View_StaffPanel.tscn` alone and it fills dummy data (`resources/UiPreview.gd`): in-memory
run + two temporary `add_mod`s, bound without a sheet.

| Where | Shows |
|---|---|
| Card | `감독 n/3` (manager seats used / `MANAGER_SLOTS`, `FacilitySystem.manager_slots_used`), `약점 <stat> <value>` (lowest effective), owner badge = assistant name or `감독`, alert dot while any negative `staff_mods` entry is active |
| Sheet · 능력치 | Six rows (§16, all reads via `FacilitySystem`): effective value + 1..20 bar; lead line = the best seat (`담당 <facility> · <occupant>`, `배치된 사람 없음 — 기본값 1`, or `담당 시설 없음 — 감독 값` for `tactics`); caption = every seat of the stat (`<facility> <occupant> <value>` / `<facility> 비어 있음`; the manager's value shows its mod `6 (+2)`). Lead bar green = staff, amber = manager, faint = nobody seated |
| Sheet · 일시 보정 | Active `staff_mods` (stat, delta, weeks left, source) |
| Sheet · 장착 특성 | Run's equipped manager traits (`TraitSystem.run_traits`, M8): +/− chip and lead bar (green / red), name, `desc_of`, rarity chip (`TraitUi.rarity_color` fill); header = `run_setup.bonus_points` and `n/TRAIT_SLOTS`. Empty → `장착한 특성 없음` |
| Sheet · 스태프 | Run staff list — name, job label, field value (assistant: top two stats), seat facility, weekly salary; header shows `weekly_salary_total` (hire / dismiss live in the personnel body) |
| Sheet · 직접 해야 하는 일 | One line per stat the manager supplies (`owner == manager`, `DIRECT_TASKS`), plus interviews / outings, which always read the manager's own mental |

**Sheet scene** (`UI_View_StaffPanel.tscn`, root `VBoxContainer` top-wide 16 short of the body width — scroll-bar room;
theme `OutgameTheme.tres`). The sheet's scroll height follows the root's height (`resized`); `Tail` is the bottom gap.
```
StaffPanel (VBox)
├ StatsSection (Title · Sub) · %StatRows (StaffStatRow ×6, sep 10) · StatTail
├ ModsSection · %ModsEmpty · %Mods (template line) · %ModsTail
├ TraitsSection (Title · %TraitsSub) · %TraitsEmpty · %Traits (StaffTraitRow, sep 8) · %TraitsTail
├ StaffSection (Title · %StaffSub) · %StaffEmpty · %Members (StaffMemberRow — Card, sep 8) · %MembersTail
├ DirectSection · %Direct (template line, autowrap, sep 6)
└ Tail
```
Code owns: texts, empty / list switching, and data styles — the lead-bar card of stat / trait rows
(`OutgameTheme.lead_bar_style`), bar fill colour + width (`ProgressTrack` / `ProgressFill`, `anchor_right` = value / 20),
owner / mod colours, +/− and rarity chip fills (`flat_style`, radius = half height). The scene's sample rows are
replaced at fill time.

The analysis reveal tiers are per opponent team since §16 (`IntelResearch.rank`, raised by intel research) and drawn by `features/match_flow/match_prep/` (`OpponentIntel` / `IntelView`) — see that README.
