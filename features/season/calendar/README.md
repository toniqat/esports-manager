# Calendar System

Drives the **week-by-week** clock that frames the entire campaign.

- 1 tick = 1 week. `SeasonHub` advances the clock when the player closes
  **Sunday** on the week-progress screen (시간 경과 화면) (`on_week_day_confirmed` → `_end_week`).
  The standings/bracket views no longer carry a "다음 주" (Next week) button.
- `CalendarSystem.advance_week()` rolls the date 7 days forward, bumps
  `season_state["phase_week"]`, and triggers a phase transition when
  `phase_week > phase_max_weeks(current_phase)`.
- `season_state["weekday"]` stays at 0 (Mon) — it is the *week's* date, and
  every match entry is stamped with that Monday for save metadata.
  **The day the player actually sits on is `season_state["week_day"]`**
  (0 = 월 (Mon) … 6 = 일 (Sun)), owned by the week-progress screen
  (`features/season/week/`). -1 means the week has not been opened yet.
- Month/year roll-over and SeasonPhase transitions are owned here:
  PRESEASON → PRESEASON_INTL → MIDSEASON → ... → REGULAR_INTL.

## Signals
- `week_advanced(new_date)` — fires every `advance_week()` call. Listened
  to by TournamentManager + InternationalTournament for bracket bootstrap,
  and by HubView for refresh.
- `phase_changed(new_phase)` — fires when `_advance_phase()` triggers.
  LeagueManager schedules the new phase here; tournament managers clear
  their own bracket type.

## Weekdays and match days
A week is **seven days, 월~일 (Mon–Sun)** (`DAYS_PER_WEEK`).

| Weekday (요일) index | | What happens |
|---|---|---|
| 0..4 | 월~금 (Mon–Fri) | **Training days** (`TRAINING_DAYS` = 5, the five rows of the training board) |
| 5 | 토 (Sat) | **Match day (경기일) 0** (`MATCH_DAYS`) |
| 6 | 일 (Sun) | **Match day 1** |

**The league runs two rounds per week** (`ROUNDS_PER_WEEK` = 2) — one round on Saturday,
one on Sunday. The schedule entry's `matchday` column tells them apart.
**Tournaments (playoffs · international tournaments (국제대회)) are still 1 match per week**
and always land on Saturday (`matchday = 0`) — QF · SF · final need a week's rest
between rounds for the bracket to read well; packing them into two days like the league
would shrink a 3-week international tournament to two and a half days.

Two static helpers read that table — `is_training_day(day)` / `matchday_of(day)`
(they do not answer whether a match is actually **scheduled**; the schedule answers that).

## Phase boundaries (CalendarSystem.PHASE_WEEKS)
The round count is unchanged; **since two rounds go into each week, league weeks were halved**
(= `ceil(rounds / 2)`). The number of matches a team plays did not change.

| Phase           | Rounds | League weeks | Playoff weeks | Total |
|---|---|---|---|---|
| PRESEASON       | 7  (single RR) | 4  | 2 (SF / F)      | 6 |
| PRESEASON_INTL  | —              | —  | 3 (QF / SF / F) | 3 |
| MIDSEASON       | 14 (double RR) | 7  | 2               | 9 |
| MIDSEASON_INTL  | —              | —  | 3               | 3 |
| REGULAR         | 14 (double RR) | 7  | 2               | 9 |
| REGULAR_INTL    | —              | —  | 3               | 3 |

Total ≈ 33 weeks. Preseason has an odd round count (7), so **the last week ends with a single
Saturday round and Sunday is empty** — on that day the match card shows "예정된 경기 없음"
(No scheduled match) and simply moves on.

## Helpers
- `is_league_match_week()` — true iff inside the league portion of a
  league phase (`phase_week <= LEAGUE_WEEKS[phase]`).
- `is_playoff_week()` — true iff inside the trailing playoff weeks.
- `is_playoff_bootstrap_week()` — true iff `phase_week == LEAGUE_WEEKS + 1`
  (the SF week). Used by TournamentManager to bootstrap the bracket.
- `date_of_week_offset(n)` — returns `{year, month, day, weekday}` of the
  Monday `n` weeks ahead. Schedulers stamp matches with this so save
  metadata stays coherent.


## Detail moved from root CLAUDE.md

### Weekly progression contract
`CalendarSystem.advance_week()` rolls 7 days forward, bumps `phase_week`,
and emits `week_advanced` (and `phase_changed` on transitions). **The only
caller is `SeasonHub._end_week()`** — when Sunday is closed on the week-progress screen.
All three managers (LeagueManager, TournamentManager,
InternationalTournament) listen to `week_advanced` and either bootstrap
their bracket (`is_playoff_bootstrap_week()` for playoff,
`phase_week == 1 && is_intl_phase` for INTL) or no-op. Match resolution is
explicit: `SeasonHub` calls `_resolve_ai_for_matchday(md)` **per match day**
(not for the whole week — the standings shown after Saturday's match must not include
Sunday results that have not been played yet), never on signal.

### Week-end order (`SeasonHub._end_week`)
Runs when Sunday is closed, **before** `advance_week()` — every step still sees the
week that just ended (`current_phase` / `phase_week`). Order is fixed (plan §11.1):
1. `_resolve_remaining_ai_for_week()` — leftover AI matches.
2. `FinanceSystem.settle_week(state)` — income − expense, surplus allocation or the
   bankruptcy rule, history (`features/season/finance/README.md`). Its `toast` is queued in
   `SeasonHub.hub_toasts` and shown on the next HUB.
3. `MechMastery.settle_week(state)` — weekly research mech.
4. `MentalSystem.end_week(state)` — weekly mental reset.
5. `StaffSystem.decay_mods(state)` → `PilotMods.decay_week(state)` — temporary mods tick down.
6. `CalendarSystem.advance_week()` → `week_advanced` (+ `phase_changed`).
7. `TrainingBoard.reset_for_new_week()` — the next week's board starts empty.

Finance runs first so that this week's match bonus (accrued by `FinanceSystem.record_match`
when each result was consumed) is paid in the same week, and so that the allocation effects
it sets (`training_exp_mult` / `incident_mult`) are in place for the coming Mon–Fri.

### Weekdays and match days (inside a week)
A week is seven days, Mon–Sun, and the current weekday is held in `season_state["week_day"]`
(0..6; **-1 means the week has not been opened yet**). The five days Mon–Fri are the five rows
of the training board, and the two days **Sat (match day 0) · Sun (match day 1)** are match days
(`CalendarSystem.MATCH_DAYS`).

**The league runs two rounds per week** (`ROUNDS_PER_WEEK` = 2) — schedule entries gained a
`matchday` column that tells them apart. The round count did not change; with two per week
**league weeks were halved** (preseason 7→4 weeks, mid / regular 14→7 weeks;
whole campaign ≈ 50 weeks → **33 weeks**). Preseason has an odd round count, so its last week
ends with a single Saturday round and Sunday is empty. **Tournaments (playoffs · international
tournaments) are still 1 match per week** and always land on Saturday (`matchday = 0`) —
QF · SF · final need a week's rest between rounds for the bracket to read well.

Three pieces of week-progress state live in `season_state` and are saved — `week_day`,
`week_day_log` (per-weekday training result log; **integer keys**, so they are converted back on load),
`training_exp_carry` (the leftover-EXP bank). All three are cleared by
`TrainingBoard.reset_week_progress()`, which runs in two places: training confirm and week end.
