# staff/ — manager · staff stats (M3)

Contract: `docs/outgame_dev_plan.md` §11. Single entry point for every manager-stat read in a run.
Display text is l10n keys (`staff` domain; shared `term.person.*` · `term.week.*`). `STAT_LABELS` / `JOB_LABELS` /
`StaffPanel.DIRECT_TASKS` values are **keys** — show them with `StaffSystem.stat_label(stat)` / `job_label(job)`, never raw.
The staff section title in `UI_View_StaffPanel.tscn` is `term.person.staff`. `term.manager_stat.*` (the six manager stat
names) are also referenced as `{tx_…}` by finance specials, manager type descs and training / mastery lines.

| File | Role |
|---|---|
| `StaffSystem.gd` | `class_name StaffSystem` (static). Tables `manager_types` / `staff` / `teams.staff_ids`; run snapshot (`snapshot_for_run` → `run_setup.manager_type/manager_stats/staff`); cover rule `effective(state, stat) = max(manager + staff_mods, assistant, dedicated staff)`; `owner` / `owner_name` / `is_delegated` (auto buttons); `staff_name(e)` — staff rows (`staff_row`, `run_setup.staff[]`) hold the l10n key `name_key` (`name.staff.*`) only, never the text (D7); `effective_for_incident`; `analysis_tier` (`ANALYSIS_TIER_1..3`); temporary mods `add_mod` / `decay_mods` (week end). |
| `StaffPanel.gd` + `UI_View_StaffPanel.tscn` | Hub manage card + `HubSheet` body — see "Hub card + sheet" below. |
| `UI_Comp_StaffStatRow.tscn` · `UI_Comp_StaffTraitRow.tscn` · `UI_Comp_StaffMemberRow.tscn` | Item scenes of the sheet (no script): one 능력치 row · one 장착 특성 row · one 스태프 row. |

Rules
- Stats are 1..20 (`STAT_MIN` / `STAT_MAX`), six keys `StaffSystem.STATS`.
- One dedicated staff per field (`JOB_STAT`), one assistant per team (all stats). Ties go staff → assistant → manager (the delegated side wins).
- Interviews / outings read `manager_value(state, "mental")` only; incidents read `effective_for_incident`.
- The **finance** stat has a real effect besides "who allocates": `effective(state, "finance")` scales sponsor
  income and upkeep continuously (`FinanceSystem.finance_stat_income_mult` / `finance_stat_upkeep_mult`,
  `FINANCE_STAT_*`) — see `features/season/finance/README.md`.
- `staff_mods.source` is an id, never text (D7): `finance:<special id>` (the finance sheet's `coach_hire` specials,
  bought with balance — `FinanceSystem.buy_special`) or `mental:<event id>` (interview / outing / press / incident
  clauses). `StaffSystem.mod_source_text(source)` turns it into the special's name / the event kind's label.
- `manager_types()` rows hold l10n keys `name_key` / `desc_key` (`manager.type.{id}.name/desc`); screens `Loc.t` them.

## Hub card + sheet (`StaffPanel.gd`)
Contract §11.2 — static `hub_summary(state)` / `open(host)`; fills only, every value comes from `StaffSystem`.
`open` = `HubSheet.open_on` + `StaffPanel.create()` added to `sheet.body` (read-only, filled once).
**F6 preview** — run `UI_View_StaffPanel.tscn` alone and it fills dummy data (`resources/UiPreview.gd`): in-memory
run + two temporary `add_mod`s, bound without a sheet.

| Where | Shows |
|---|---|
| Card | `위임 n/6` (stats whose `owner` is not the manager), `약점 <stat> <value>` (lowest effective), owner badge = assistant name or `감독`, alert dot while any negative `staff_mods` entry is active |
| Sheet · 능력치 | Six rows: effective value + 1..20 bar, who covers it (`감독 (직접)` / job label + name), and every cover-rule candidate (`감독 v (±mod) · 어시 v · <job> v`). Green lead bar = delegated, amber = manager |
| Sheet · 일시 보정 | Active `staff_mods` (stat, delta, weeks left, source) |
| Sheet · 장착 특성 | Run's equipped manager traits (`TraitSystem.run_traits`, M8): +/− chip and lead bar (green / red), name, `desc_of`, rarity chip (`TraitUi.rarity_color` fill); header = `run_setup.bonus_points` and `n/TRAIT_SLOTS`. Empty → `장착한 특성 없음` |
| Sheet · 스태프 | Run staff list — name, job label, field value (assistant: top two stats), weekly salary; header shows `weekly_salary_total` |
| Sheet · 직접 해야 하는 일 | One line per non-delegated stat (`DIRECT_TASKS`), plus interviews / outings, which always read the manager's own mental |

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

The analysis reveal tiers (`analysis_tier`) are drawn by `features/match_flow/match_prep/` (`OpponentIntel` / `IntelView`) — see that README.
