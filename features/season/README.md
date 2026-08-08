# Season (Outgame) Feature

The campaign / out-of-match metagame, restructured around weekly progression.
Player picks a 5-pilot team from a 40-pilot pool, then plays through six
events from December → next year:

```
PRESEASON → PRESEASON_INTL → MIDSEASON → MIDSEASON_INTL → REGULAR → REGULAR_INTL
```

Win the final REGULAR_INTL = ending. Fail to make playoffs in any league
phase = game over. The campaign progresses **one week at a time** — the
calendar internally rolls 7 days per "다음 주" press, but the player only
sees a phase / week counter.

## Entry point
`scenes/Season.tscn` — entered from `scenes/TitleScreen.tscn` once the
player picks a save slot. Root: `Control` with `SeasonHub.gd` attached.
SeasonHub branches on `gm.season_state["active"]`: false → run
`init_season()` and route to DRAFT (new campaign), true → skip init and
route directly to HUB (loaded campaign). See `features/save_load/` for the
save-system contract.

## Weekly flow
```
HUB (이번 주 시작)
  → TRAINING (set this week's training schedule + 주 진행)
  → (apply_week_training mutates PlayerData stats)
  → TRAINING_RESULT (per-pilot before/after/delta dashboard + 다음)
  → has player match this week?
        ├─ Yes → MatchFlow (PREP → BAN_PICK → ASSIGN → JUNGLE_START → BattleSim)
        │           → return to Season → apply result
        │           → resolve remaining AI matches for the week
        │           → STANDINGS (LeagueView / BracketView / IntlBracketView)
        └─ No  → resolve all AI matches for the week
                  → STANDINGS
  STANDINGS (다음 주 →)
  → CalendarSystem.advance_week (rolls 7 days, bumps phase_week, possibly
    advances phase / bootstraps tournament for next phase)
  → refill training defaults
  → HUB (autosave: post_week)
```

## Architecture
`SeasonHub.gd` is a thin orchestrator (`class_name SeasonHub extends Control`).
Each child module reads/writes shared state via `GameManager.season_state`
and exposes intent methods on the hub. Pattern mirrors `BattleSim`:

```gdscript
@onready var _hub: SeasonHub = get_parent() as SeasonHub
```

| Node                     | Script                                       | Purpose                                                          |
|---|---|---|
| CalendarSystem           | `calendar/CalendarSystem.gd`                 | `advance_week()` — rolls 7 days, bumps `phase_week`, transitions phase. Emits `week_advanced`, `phase_changed`. |
| HubView                  | `HubView.gd`                                 | Simplified hub — phase/week counter + roster + "이번 주 시작" + 순위 buttons. |
| TeamDraft                | `draft/TeamDraft.gd`                         | Initial 5-pilot team selection from 40-pilot pool                |
| TrainingScheduler        | `training/TrainingScheduler.gd`              | 7-day × pilot grid; default fills + player edits + `apply_week_training()` (one-shot per week, returns before/after deltas) |
| TrainingView             | `training/TrainingView.gd`                   | Schedule editor; "주 진행" button calls `SeasonHub.on_training_save_and_advance`. |
| TrainingResultView       | `training/TrainingResultView.gd`             | Post-week dashboard — 5×5 stat deltas. "다음 →" calls `SeasonHub.on_training_result_continue`. |
| LeagueManager            | `league/LeagueManager.gd`                    | Round-robin schedule keyed by `phase_week` (1 round per week), standings, `resolve_current_week()` for AI matches. |
| TournamentManager        | `tournament/TournamentManager.gd`            | 4-team SE playoff bracket distributed across 2 weeks (SF week + F week). |
| InternationalTournament  | `tournament/InternationalTournament.gd`      | 8-team SE INTL bracket distributed across 3 weeks (QF / SF / F). |
| LeagueView               | `league/LeagueView.gd`                       | Standings screen — "다음 주 →" advances week, "돌아가기" returns to HUB. |
| BracketView              | `tournament/BracketView.gd`                  | Phase-7 playoff bracket UI (3 panels: SF1/SF2/F)                 |
| IntlBracketView          | `tournament/IntlBracketView.gd`              | Phase-8 INTL bracket UI (7 panels: 4 QF / 2 SF / F)              |
| GameOverView             | `GameOverView.gd`                            | Game-over screen — playoff miss (Phase 7) or REGULAR_INTL loss   |
| EndingView               | `EndingView.gd`                              | World-champion ending screen — REGULAR_INTL win                  |

## Phase week budget (CalendarSystem.PHASE_WEEKS)
| Phase           | League weeks | Playoff weeks | Total |
|---|---|---|---|
| PRESEASON       | 7  (single RR) | 2 (SF / F)    | 9     |
| PRESEASON_INTL  | —              | 3 (QF / SF / F) | 3   |
| MIDSEASON       | 14 (double RR) | 2             | 16    |
| MIDSEASON_INTL  | —              | 3             | 3     |
| REGULAR         | 14 (double RR) | 2             | 16    |
| REGULAR_INTL    | —              | 3             | 3     |

Total ≈ 50 weeks (~ 11.5 months).

## Match-week handoff
On the player's match week, the path differs from the daily model:
- `SeasonHub.on_training_result_continue` checks
  `_has_player_match_this_week()`. If true, populates
  `season_state["pending_match"]` (`{source, schedule_idx, enemy_team_id,
  winner_side}`) and `change_scene_to_file` into MatchFlow.
- MatchFlow runs PREP → BAN_PICK → ASSIGN → JUNGLE_START → BattleSim.
- When BattleSim ends, the win panel's "다음 →" returns to `Season.tscn`.
- `SeasonHub._ready` consumes `pending_match`, applies the result via
  `LeagueManager.record_result()` / `TournamentManager.record_result()` /
  `InternationalTournament.record_result()`, then calls
  `_resolve_remaining_ai_for_week()` to sweep up any remaining AI matches
  scheduled for the same week, then routes to the appropriate STANDINGS
  view.

## Tournament lifecycle
- TournamentManager and InternationalTournament both listen to
  `CalendarSystem.week_advanced` and bootstrap their bracket on the right
  week (`is_playoff_bootstrap_week()` for playoff, week 1 of an INTL phase
  for INTL).
- They also expose `ensure_active()` so SeasonHub can re-bootstrap on HUB
  entry when loading a save mid-tournament.
- Both share `season_state["current_tournament"]` but discriminate by
  `type` (`"PLAYOFF"` vs `"INTL"`); each manager only clears its own type
  on phase change.
- `resolve_current_week()` runs AI-vs-AI sims for matches scheduled in the
  current `phase_week` of the active bracket. Player matches are left
  unplayed for SeasonHub to launch.

## Match schedule shape
`season_state["match_schedule"]` and bracket entries share most fields:

```gdscript
{
  "phase":      int,            # SeasonPhase
  "phase_week": int,            # 1-indexed week within the phase
  "round":      int,            # round-robin round index (league only)
  "slot":       int,            # bracket slot (tournaments only)
  "team_a":     int,
  "team_b":     int,
  "year":       int,            # Monday of the phase_week — for save metadata
  "month":      int,
  "day":        int,
  "weekday":    int,            # always 0 (Mon) under weekly progression
  "played":     bool,
  "winner":     int,            # team_id, or -1 when unplayed
}
```

`year/month/day` are derived from the phase_week's Monday so save slot
cards still show meaningful dates. The day-of-week distinction is
internal-only and never exposed in-game.

## Autosave triggers (4)
1. **Post-draft** — `SeasonHub.goto(HUB)` when previous screen was DRAFT.
2. **Pre-ban-pick** — `MatchFlow._on_prep_finished` after the player
   confirms PREP. Writes `season_state["match_resume"] = {phase: BAN_PICK,
   player_side, ...}`.
3. **Post-gambit** — `MatchFlow._on_jungle_finished` before
   `change_scene_to_file` to BattleSim. Writes the full match snapshot
   (banned/picked/assigned mech IDs, jungle dir) into `match_resume`.
4. **Post-week-end** — `SeasonHub.on_proceed_to_next_week` after
   `advance_week`. Captures both post-match weeks and no-match weeks.

No save fires inside BattleSim. Closing mid-battle leaves the disk save at
trigger #3; resume re-enters BattleSim with the locked-in picks but the
battle replays from scratch.

## Resume routing
TitleScreen "이어하기" branches on `season_state["match_resume"]`:
- Non-null → `MatchFlow.tscn` (MatchFlow consumes the hint and skips
  PREP, jumping directly to BAN_PICK or LAUNCH depending on the saved
  phase).
- Null → `Season.tscn` → SeasonHub → HUB.

SlotCard shows a "경기 진행 중" tag when `meta.match_in_progress == true`
(set whenever `match_resume` is non-null at save time).

## SeasonHub screen routing
`SeasonHub._route()` toggles child controls based on `current_screen`.
Lazy view builders cache the instance after first creation.
- `Screen.DRAFT` → `TeamDraft`.
- `Screen.HUB` → simplified HubView. Calls `LeagueManager.ensure_phase_scheduled()`
  + `TournamentManager.ensure_active()` + `InternationalTournament.ensure_active()`
  to handle save-loads landing on tournament weeks.
- `Screen.TRAINING` → `TrainingView`.
- `Screen.TRAINING_RESULT` → `TrainingResultView` (populated by
  `on_training_save_and_advance`).
- `Screen.LEAGUE` → `LeagueView` (standings).
- `Screen.PLAYOFF` → `BracketView`.
- `Screen.INTL_BRACKET` → `IntlBracketView`.
- `Screen.GAME_OVER` → `GameOverView`.
- `Screen.ENDING` → `EndingView`.

## Calendar contract
- `CalendarSystem.advance_week()` is the single tick. Rolls 7 days
  forward, bumps `phase_week`, transitions phase if `phase_week` exceeds
  `phase_max_weeks(current_phase)`. Emits `week_advanced` (always) and
  `phase_changed` (on phase transitions).
- `phase_week` weekday stays at 0 (Mon) — the player conceptually sits at
  the start of each week. F/S/S match days are fictional internal
  ordering.
- `is_league_match_week()` / `is_playoff_week()` / `is_playoff_bootstrap_week()`
  drive which subsystem owns the current week.
- `date_of_week_offset(n)` returns the Monday of the week n weeks ahead
  (used by schedulers to stamp matches).
