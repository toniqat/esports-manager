# staff/ — manager · staff stats (M3)

Contract: `docs/outgame_dev_plan.md` §11. Single entry point for every manager-stat read in a run.

| File | Role |
|---|---|
| `StaffSystem.gd` | `class_name StaffSystem` (static). Tables `manager_types` / `staff` / `teams.staff_ids`; run snapshot (`snapshot_for_run` → `run_setup.manager_type/manager_stats/staff`); cover rule `effective(state, stat) = max(manager + staff_mods, assistant, dedicated staff)`; `owner` / `is_delegated` (auto buttons); `effective_for_incident`; `analysis_tier` (`ANALYSIS_TIER_1..3`); temporary mods `add_mod` / `decay_mods` (week end). |
| `StaffPanel.gd` | Hub manage card + `HubSheet` detail (M5 work fills it). |

Rules
- Stats are 1..20 (`STAT_MIN` / `STAT_MAX`), six keys `StaffSystem.STATS`.
- One dedicated staff per field (`JOB_STAT`), one assistant per team (all stats). Ties go staff → assistant → manager (the delegated side wins).
- Interviews / outings read `manager_value(state, "mental")` only; incidents read `effective_for_incident`.
