# Training Scheduler

Weekly 7-day training grid. Rows = pilots on the player's team (5 rows).
Columns = Mon..Sun. Each cell is a `GameEnums.TrainingType`. The whole
week is applied atomically when the player presses "주 진행".

## Files
| File | Role |
|---|---|
| `TrainingScheduler.gd` | Headless logic — default templates, `apply_week_training()` (returns per-pilot before/after/delta dict), `projected_week_stats()` for the preview UI, `refill_player_team_defaults()` after a week roll. |
| `TrainingView.gd` | Schedule editor — preview table + 5×7 grid + picker dialog. "주 진행" button calls `SeasonHub.on_training_save_and_advance()`. |
| `TrainingResultView.gd` | Post-week dashboard — 5 pilots × 5 stats with `before → after` and `+delta` per cell. "다음 →" calls `SeasonHub.on_training_result_continue()`. |

## Behavior
- Default schedule (`default_week_for_pilot`) auto-fills at the start of
  each week. `refill_player_team_defaults()` runs in
  `SeasonHub.on_proceed_to_next_week()` after `advance_week`.
- Player can override Mon–Thu cells freely. Fri/Sat/Sun cells lock to
  MATCH whenever the player has a real match this week (across league,
  playoff, or INTL). When unlocked, MATCH cells fall back to REST.
- `apply_week_training()` is the per-week tick: walks each player-team
  pilot's 7 cells, applies stat deltas (clamped 1..100), and returns a
  result dict the dashboard reads. MATCH cells fall back to REST when
  no real match is scheduled this week (so off-week-ends don't bleed
  mental). Idempotent within a week boundary because SeasonHub controls
  the call site.
- `projected_week_stats(p)` runs the same logic against a copy of `p`'s
  current stats to preview the post-week projection on the editor screen.

## Stats touched
Only the existing PlayerData stats: `laning, mechanics, gamesense, teamfight, mental`.
Clamped to `[1, 100]` per stat per day. `REST` boosts mental; `SCRIM` trades
mental for teamfight + gamesense; `MATCH` costs mental; topic-specific training
nudges the matching stat.

## Picker dialog
Tapping a non-locked cell opens a centered modal panel listing the six
player-editable types (`REST/LANING/MECHANICS/GAMESENSE/TEAMFIGHT/SCRIM`)
plus a Cancel button. `MATCH` is never offered — it's reserved for the
weekend lock. Tapping outside the panel (on the dim layer) also dismisses
the picker.
