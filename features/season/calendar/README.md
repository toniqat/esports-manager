# Calendar System

Drives the **week-by-week** clock that frames the entire campaign.

- 1 tick = 1 week. Player advances explicitly via "다음 주" on the
  standings/bracket views (which routes through
  `SeasonHub.on_proceed_to_next_week`).
- `CalendarSystem.advance_week()` rolls the date 7 days forward, bumps
  `season_state["phase_week"]`, and triggers a phase transition when
  `phase_week > phase_max_weeks(current_phase)`.
- Internal weekday stays at 0 (Mon) — the player conceptually sits at the
  start of every week. Match days (Fri/Sat/Sun) are fictional internal
  ordering and never exposed in-game.
- Month/year roll-over and SeasonPhase transitions are owned here:
  PRESEASON → PRESEASON_INTL → MIDSEASON → ... → REGULAR_INTL.

## Signals
- `week_advanced(new_date)` — fires every `advance_week()` call. Listened
  to by TournamentManager + InternationalTournament for bracket bootstrap,
  and by HubView for refresh.
- `phase_changed(new_phase)` — fires when `_advance_phase()` triggers.
  LeagueManager schedules the new phase here; tournament managers clear
  their own bracket type.

## Phase boundaries (CalendarSystem.PHASE_WEEKS)
| Phase           | Months          | League weeks | Playoff weeks | Total |
|---|---|---|---|---|
| PRESEASON       | Dec             | 7  (single RR) | 2 (SF / F)    | 9     |
| PRESEASON_INTL  | mid-Feb         | —              | 3 (QF / SF / F) | 3   |
| MIDSEASON       | Mar–Jun         | 14 (double RR) | 2             | 16    |
| MIDSEASON_INTL  | late Jun        | —              | 3             | 3     |
| REGULAR         | Jul–Oct         | 14 (double RR) | 2             | 16    |
| REGULAR_INTL    | early Nov       | —              | 3             | 3     |

Total ≈ 50 weeks (~ 11.5 months Dec → Nov).

## Helpers
- `is_league_match_week()` — true iff inside the league portion of a
  league phase (`phase_week <= LEAGUE_WEEKS[phase]`).
- `is_playoff_week()` — true iff inside the trailing playoff weeks.
- `is_playoff_bootstrap_week()` — true iff `phase_week == LEAGUE_WEEKS + 1`
  (the SF week). Used by TournamentManager to bootstrap the bracket.
- `date_of_week_offset(n)` — returns `{year, month, day, weekday}` of the
  Monday `n` weeks ahead. Schedulers stamp matches with this so save
  metadata stays coherent.
