# League Manager

Owns the regular-league round-robin schedule, AI-vs-AI auto resolution,
standings table, and the playoff cut-line check (top 4 of 8 = playoffs).
The campaign now progresses 1 week at a time, so each league week =
exactly 1 round of the round-robin.

## Schedule shape
- **PRESEASON** — single round-robin (7 rounds, 28 matches, each team
  plays every other once). 7 league weeks.
- **MIDSEASON / REGULAR** — double round-robin (14 rounds, 56 matches,
  home-and-away). 14 league weeks.
- **\*\_INTL** phases — no league schedule. INTL bracket lives in
  `features/season/tournament/` (3-week 8-team SE).
- 1 round = 1 week. Round `r_idx` → `phase_week r_idx + 1`. Each match is
  stamped with the Monday of its phase_week so save metadata stays
  coherent.
- Schedule is generated lazily and idempotently:
  - `SeasonHub._show_hub()` calls `LeagueManager.ensure_phase_scheduled()`
    on every hub entry — covers the initial PRESEASON post-draft.
  - `LeagueManager._on_phase_changed()` does the same on every league
    phase transition (MIDSEASON, REGULAR). INTL transitions are no-ops.

## Match-week flow
- Player flow goes through `SeasonHub.on_training_result_continue` →
  MatchFlow → BattleSim. SeasonHub's `_resolve_remaining_ai_for_week()`
  calls `LeagueManager.resolve_current_week()` after the player match
  returns to sweep up the same week's AI matches.
- `resolve_current_week()` resolves every match where `phase ==
  current_phase && phase_week == current_phase_week` that does NOT
  involve the player team via `simulate_ai_match()` and records results.
  No-op outside league weeks (`is_league_match_week()`).

## Standings
- `season_state["league_standings"]` — `team_id (int) → {wins, losses}`.
  Reset to all-zeros at the start of every league phase
  (`generate_phase_schedule` clears it).
- `standings_ranked()` returns rows `{team_id, wins, losses}` sorted by
  wins desc, losses asc, team_id asc.
- `player_made_playoffs()` checks whether the player team is in the top
  `GameManager.PLAYOFF_TEAMS` (default 4). Used by Phase 7 at phase end.

## Public API
| Method | Caller |
|---|---|
| `ensure_phase_scheduled()` | SeasonHub on hub entry, self on phase_changed |
| `generate_phase_schedule(phase)` | Internal (called by ensure) |
| `resolve_current_week()` | SeasonHub during the post-match sweep |
| `record_result(a, b, winner)` | SeasonHub after BattleSim returns |
| `simulate_ai_match(a, b)` | resolve_current_week (and tournaments reuse it) |
| `standings_ranked()` | LeagueView, tournament managers |
| `player_made_playoffs()` | Phase 7 cut |
| `next_unplayed_player_match()` | LeagueView next-match header, HubView |
| `player_match_this_week()` | TrainingScheduler, TrainingView (cell lock) |
| `matches_this_week()` | LeagueView "this week's matches" |
| `team_name(id)` / `team_short_name(id)` | LeagueView, draft, future UIs |

## Match-schedule entry shape
Each entry in `season_state["match_schedule"]` is a Dictionary:
```
{
  "phase":      GameEnums.SeasonPhase,
  "phase_week": int,                  # 1-indexed week within the phase
  "round":      int,                  # round-robin round index
  "year":       int, "month": int, "day": int, "weekday": int,
  "team_a":     int, "team_b": int,
  "played":     bool,
  "winner":     int,                  # team_id or -1 if not played
}
```

`year/month/day` are stamped to the Monday of the phase_week — used only
for save metadata and SlotCard display, never for match-day filtering.

## Files
- `LeagueManager.gd` — orchestrator (this README's contract).
- `LeagueView.gd` — standings screen. 8 ranked rows + next-match header
  + "다음 주 →" / "돌아가기" buttons. Routed via `SeasonHub.Screen.LEAGUE`.
