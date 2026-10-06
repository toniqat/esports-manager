# staff/ — manager · staff stats (M3)

Contract: `docs/outgame_dev_plan.md` §11. Single entry point for every manager-stat read in a run.

| File | Role |
|---|---|
| `StaffSystem.gd` | `class_name StaffSystem` (static). Tables `manager_types` / `staff` / `teams.staff_ids`; run snapshot (`snapshot_for_run` → `run_setup.manager_type/manager_stats/staff`); cover rule `effective(state, stat) = max(manager + staff_mods, assistant, dedicated staff)`; `owner` / `is_delegated` (auto buttons); `effective_for_incident`; `analysis_tier` (`ANALYSIS_TIER_1..3`); temporary mods `add_mod` / `decay_mods` (week end). |
| `StaffPanel.gd` | Hub manage card + `HubSheet` detail — see "Hub card + sheet" below. |

Rules
- Stats are 1..20 (`STAT_MIN` / `STAT_MAX`), six keys `StaffSystem.STATS`.
- One dedicated staff per field (`JOB_STAT`), one assistant per team (all stats). Ties go staff → assistant → manager (the delegated side wins).
- Interviews / outings read `manager_value(state, "mental")` only; incidents read `effective_for_incident`.
- The **finance** stat has a real effect besides "who allocates": `effective(state, "finance")` scales sponsor
  income and upkeep continuously (`FinanceSystem.finance_stat_income_mult` / `finance_stat_upkeep_mult`,
  `FINANCE_STAT_*`) — see `features/season/finance/README.md`.
- `staff_mods` sources include the finance sheet's `coach_hire` specials (`특별 지출 · <name>`), bought with
  balance (`FinanceSystem.buy_special`).

## Hub card + sheet (`StaffPanel.gd`)
Contract §11.2 — `hub_summary(state)` / `open(host)`; draws only, every value comes from `StaffSystem`.

| Where | Shows |
|---|---|
| Card | `위임 n/6` (stats whose `owner` is not the manager), `약점 <stat> <value>` (lowest effective), owner badge = assistant name or `감독`, alert dot while any negative `staff_mods` entry is active |
| Sheet · 능력치 | Six rows: effective value + 1..20 bar, who covers it (`감독 (직접)` / job label + name), and every cover-rule candidate (`감독 v (±mod) · 어시 v · <job> v`). Green lead bar = delegated, amber = manager |
| Sheet · 일시 보정 | Active `staff_mods` (stat, delta, weeks left, source) |
| Sheet · 장착 특성 | Run's equipped manager traits (`TraitSystem.run_traits`, M8): +/− chip and lead bar (green / red), name, `desc_of`, rarity chip; header = `run_setup.bonus_points` and `n/TRAIT_SLOTS`. Empty → `장착한 특성 없음` |
| Sheet · 스태프 | Run staff list — name, job label, field value (assistant: top two stats), weekly salary; header shows `weekly_salary_total` |
| Sheet · 직접 해야 하는 일 | One line per non-delegated stat (`DIRECT_TASKS`), plus interviews / outings, which always read the manager's own mental |

The analysis reveal tiers (`analysis_tier`) are drawn by `features/match_flow/match_prep/` (`OpponentIntel` / `IntelView`) — see that README.
