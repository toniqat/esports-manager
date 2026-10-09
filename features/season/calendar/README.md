# Calendar System

Drives the **week-by-week** clock that frames the entire campaign.

- 1 tick = 1 week. `SeasonHub` advances the clock when the player closes
  **Sunday evening** on the week-progress screen (시간 경과 화면) (`on_week_day_confirmed` → `_end_week`).
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

## Phase start title card (`PhaseIntro.gd` + `UI_View_PhaseIntro.tscn`)
The first HUB of every phase (run start included) opens with a dark full-screen card over the hub:
`캠페인 n / 6` · the phase name (`GameEnums.phase_label`) · amber line · `리그 n주 · 플레이오프 n주`
(`LEAGUE_WEEKS` / `PHASE_WEEKS`) or `국제대회 토너먼트 n주`, hint `화면을 눌러 계속`. Fade in → hold `HOLD` s →
fade out → frees itself, revealing the hub; a tap skips to the fade out. `SeasonHub._maybe_phase_intro` (end of
`_show_hub`) plays it when `season_state.phase_intro_seen != current_phase` and stores the phase (saved; -1 =
none yet, an old save shows the current phase's card once). Backdrop = screen variation `PhaseIntroBackdrop`.
Text: `season.phase_intro.*`. F6 = the 미드시즌 card, static.

## Signals
- `week_advanced(new_date)` — fires every `advance_week()` call. Listened
  to by TournamentManager + InternationalTournament for bracket bootstrap,
  and by HubView for refresh.
- `phase_changed(new_phase)` — fires when `_advance_phase()` triggers.
  LeagueManager schedules the new phase here; tournament managers clear
  their own bracket type.

## Weekdays — one player match per week, on Sunday
A week is **seven days, 월~일 (Mon–Sun)** (`DAYS_PER_WEEK`).

| Weekday (요일) index | | What happens |
|---|---|---|
| 0..4 | 월~금 (Mon–Fri) | **Training days** (`TRAINING_DAYS` = 5, the five rows of the training board) |
| 5 | 토 (Sat) | **Prep day** (`PREP_DAY`): morning = stadium → MatchFlow PREP + BAN_PICK for Sunday's match (picks stored in the run); afternoon / evening = a normal day **without training** |
| 6 | 일 (Sun) | **Match day** (`MATCH_DAY`, match-day number 0 — `MATCH_DAYS = {6: 0}`): morning = stadium → BattleSim with the Saturday picks; afternoon = press conference (result-reactive); evening = normal → week end |

**One round per week** (`ROUNDS_PER_WEEK` = 1). Every player match — league, playoff, INTL — and
the AI matches of that round stand on **Sunday**; schedule and bracket entries all carry
`matchday = 0`. A week without a player match (should not happen with the current tables) has plain
Sat / Sun (afternoon + evening only, no stadium / press).

Static helpers: `is_training_day(day)` (Mon–Fri) · `matchday_of(day)` (Sunday → 0, else -1) ·
`is_week_day(day)` (0..6 — every day has an afternoon / evening). They do not answer whether a match
is actually **scheduled** — the schedule answers that (`SeasonHub.has_player_match_on_day`).

## Phase boundaries (CalendarSystem.PHASE_WEEKS)
Every league phase is a **single round robin** (8 teams → 7 rounds) at one round per week.

| Phase           | Rounds | League weeks | Playoff weeks | Total |
|---|---|---|---|---|
| PRESEASON       | 7 (single RR) | 7 | 2 (SF / F)      | 9 |
| PRESEASON_INTL  | —             | — | 3 (QF / SF / F) | 3 |
| MIDSEASON       | 7 (single RR) | 7 | 2               | 9 |
| MIDSEASON_INTL  | —             | — | 3               | 3 |
| REGULAR         | 7 (single RR) | 7 | 2               | 9 |
| REGULAR_INTL    | —             | — | 3               | 3 |

**Total = 36 weeks, 36 player matches** on a full clear (7 league + 2 playoff per league phase,
3 per INTL). History: 50 weeks (1 round/week, double RR in MID / REGULAR) → 33 weeks (2 rounds/week
on Sat · Sun) → 36 weeks (this table).

## Helpers
- `is_league_match_week()` — true iff inside the league portion of a
  league phase (`phase_week <= LEAGUE_WEEKS[phase]`).
- `is_playoff_week()` — true iff inside the trailing playoff weeks.
- `is_playoff_bootstrap_week()` — true iff `phase_week == LEAGUE_WEEKS + 1`
  (the SF week). Used by TournamentManager to bootstrap the bracket.
- `date_of_week_offset(n)` — returns `{year, month, day, weekday}` of the
  Monday `n` weeks ahead. Schedulers stamp matches with this so save
  metadata stays coherent.

## Old saves (`migrate_weekly_format`)
`season_state.schedule_format` (`SCHEDULE_FORMAT` = 2) marks the one-match-per-week calendar; it is
written by `LeagueManager.generate_phase_schedule` and saved. `SaveSystem.load_run` calls the static
`CalendarSystem.migrate_weekly_format(state)` on every load; a run without the key (format 1: two
rounds on Sat · Sun, 4 preseason league weeks, double RR in MID / REGULAR) is normalised once:
- **League week**: the current phase's unplayed rounds are re-stamped one per week from the current
  `phase_week` (`matchday` 0 = Sunday). Rounds that no longer fit before the playoffs are voided
  (`played` true, `winner` -1, `phase_week` 0, `void` true) — entries stay in the array so a
  `pending_match.schedule_idx` keeps pointing at the right match. Standings are untouched.
- **Playoff week**: `phase_week` and the playoff bracket's `phase_week`s move by the added league
  weeks (preseason +3).
- INTL phases are unchanged (3 weeks before and after); tournament `matchday` 0 simply means Sunday now.
- A mid-week old save keeps its day; the week screen then runs the new weekend (an old Saturday
  becomes the prep day). An old Sunday whose picks were never made falls back to the full
  PREP → BAN_PICK → BattleSim flow.

## Detail moved from root CLAUDE.md

### Weekly progression contract
`CalendarSystem.advance_week()` rolls 7 days forward, bumps `phase_week`,
and emits `week_advanced` (and `phase_changed` on transitions). **The only
caller is `SeasonHub._end_week()`** — when Sunday is closed on the week-progress screen.
All three managers (LeagueManager, TournamentManager,
InternationalTournament) listen to `week_advanced` and either bootstrap
their bracket (`is_playoff_bootstrap_week()` for playoff,
`phase_week == 1 && is_intl_phase` for INTL) or no-op. Match resolution is
explicit: `SeasonHub` calls `_resolve_ai_for_matchday(0)` on Sunday (after the player's match, or
on Sunday's "확인" when there is none), never on signal.

### Week-end order (`SeasonHub._end_week`)
Runs when Sunday is closed, **before** `advance_week()` — every step still sees the
week that just ended (`current_phase` / `phase_week`). Order is fixed (plan §11.1):
1. `_resolve_remaining_ai_for_week()` — leftover AI matches.
2. `FinanceSystem.settle_week(state)` — income − expense, surplus allocation or the
   bankruptcy rule, history (`features/season/finance/README.md`). Its `toast` is queued in
   `SeasonHub.hub_toasts` and shown on the next HUB.
3. `ResearchSystem.tick_week(state)` — §16 research gauges (mech mastery comes from the mech lab's
   completions, `features/season/facility/README.md`); toasts queued in `hub_toasts`.
4. `MentalSystem.end_week(state)` — weekly mental reset; a `pending_match` that never got a result
   (stale Saturday picks) is dropped.
5. `StaffSystem.decay_mods(state)` → `PilotMods.decay_week(state)` — temporary mods tick down.
6. `CalendarSystem.advance_week()` → `week_advanced` (+ `phase_changed`).
7. `TrainingBoard.reset_for_new_week()` — the next week's board starts empty.

Finance runs first so that this week's match bonus (accrued by `FinanceSystem.record_match`
when each result was consumed) is paid in the same week, and so that the allocation effects
it sets (`training_exp_mult` / `incident_mult`) are in place for the coming Mon–Fri.

### Week-progress state
The current weekday is held in `season_state["week_day"]` (0..6; **-1 means the week has not been
opened yet**). Three pieces of week-progress state live in `season_state` and are saved — `week_day`,
`week_day_log` (per-weekday training result log; **integer keys**, so they are converted back on load),
`training_exp_carry` (the leftover-EXP bank). All three are cleared by
`TrainingBoard.reset_week_progress()`, which runs in two places: training confirm and week end.
The Saturday picks live in `season_state.pending_match.picks` (`features/save_load/README.md`).
