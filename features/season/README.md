# Season (Outgame) Feature

The campaign / out-of-match metagame, restructured around weekly progression.
Player picks a 5-pilot team from a 40-pilot pool, then plays through six
events from December → next year:

```
PRESEASON → PRESEASON_INTL → MIDSEASON → MIDSEASON_INTL → REGULAR → REGULAR_INTL
```

Win the final REGULAR_INTL = ending. Fail to make playoffs in any league
phase = game over. The campaign progresses **one week at a time** — the
calendar internally rolls 7 days per "다음 주" (Next week) press, but the player only
sees a phase / week counter.

## Bottom action bar (하단 액션 바) (every screen in this folder)
**The primary action is not a shape button floating in the middle of the screen but the whole
bottom section** — the single function `OutgameTheme.add_bottom_bar(parent, specs)` builds a
square-cornered bar running edge to edge, its bottom flush against the safe line. With N buttons the
section is split **by weight ratio**, and the convention is **primary 2 : secondary 1** with **the
primary action at the right end**.

| Screen | Bar |
|---|---|
| HubView | `리그 순위` (League standings) (1, ghost) / `이번 주 시작 →` (Start this week) (2, primary) |
| TrainingView | `판 비우기` (Clear board) (1, ghost) / `훈련 확정` (Confirm training) (2, primary) |
| TeamDraftView | PICK = `다음` (Next) full width · CONFIRM = `뒤로` (Back) (1) / `게임 시작` (Start game) (2) |
| LeagueView · BracketView · IntlBracketView | `확인` (OK) full width |
| WeekProgressView | `확인` / `주 마감 →` (End of week) / `경기 시작` (Start match) (dark) — always exactly one, full width |
| EndingView · GameOverView | `타이틀로` (To title) (1, ghost) / `다시 시작` (Restart) (2, primary) |

The four conventions (body height is derived back from `bottom_bar_top()` · the colour fill extends
below the safe line but the text stays above it · when a cell collapses, call `layout_bottom_bar`
again · use `style_bottom_button` to restyle a button) are in the "Bottom action bar" section of
`resources/README.md`. **The press conference (기자회견) answer choices are not this bar** — they are
choices standing inside the speech-bubble flow, so they are not pinned to the bottom.

## Entry point
`scenes/Season.tscn` — entered from `scenes/TitleScreen.tscn` once the
player picks a save slot. Root: `Control` with `SeasonHub.gd` attached.
SeasonHub branches on `gm.season_state["active"]`: false → run
`init_season()` and route to DRAFT (new campaign), true → skip init and
route directly to HUB (loaded campaign). See `features/save_load/` for the
save-system contract.

## Weekly flow
The week flows **one day at a time across all seven days, Mon–Sun** (`season_state["week_day"]` 0..6).

```
HUB (just before the week starts — roster · next match · "이번 주 시작 →")
  → PRESS      (press conference — messenger. A few lines, then answer choices)
  → TRAINING   (daily training — slot tiles into the board to plan training, then "훈련 확정")
  → WEEK       (week progress — left weekday rail + that day's card list)
       월 → 화 → 수 → 목 → 금   on each weekday apply_day_training(day) settles only
                                 that row, raises stats, and shows the result as cards
       토 (match day 0) ┬ player has a match → "경기 시작"
       일 (match day 1) │     → MatchFlow (PREP → BAN_PICK) → BattleSim
                        │     → re-enter Season → apply result + settle that match day's AI
                        │     → STANDINGS → "확인" → WEEK (same weekday)
                        └ none → a single "확인" settles only that day's AI matches, next day
       Sunday's "주 마감 →"
  → CalendarSystem.advance_week (rolls 7 days, bumps phase_week, possibly
    advances phase / bootstraps tournament for next phase)
  → TrainingBoard.reset_for_new_week (clear board + reset week-progress state)
  → HUB (autosave: post_week)
```

**Training is applied per weekday.** Previously "훈련 확정" settled the whole week at once with a
single `apply_week_training()` and one `TRAINING_RESULT` screen showed the result; once the
week-progress screen (시간 경과 화면) started asking "what happened that day" for each weekday,
settlement was split into `apply_day_training(day)` too.
`Screen.TRAINING_RESULT` and `TrainingResultView` **were deleted** at that point.

**Sat·Sun are the two match days (경기일).** The league runs two rounds a week to fill both, while
tournaments (playoffs · international tournaments (국제대회)) have one round a week and always stand
on Saturday only. Details in `calendar/README.md`.

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
| HubView                  | `HubView.gd`                                 | Simplified hub — phase/week counter + roster + "이번 주 시작" (Start this week) + 순위 (standings) buttons. |
| TeamDraft                | `draft/TeamDraft.gd`                         | Initial 5-player pick (pool of 25 named pilots (네임드)) — 5 role-fixed slots · role filter · scrolling thumbnail grid · detail popup. `draft/README.md` |
| PressConferenceView      | `press/PressConferenceView.gd`               | **Press conference** — the messenger screen right before the week starts. Currently a skeleton whose lines · choices are placeholder data. `press/README.md` |
| TrainingBoard            | `training/TrainingBoard.gd`                  | **Daily training (일상 훈련) tile board (타일판)** — 5 columns (players) × 5 rows (one per day; weekdays are not written on screen). Placement checks + settlement (`cell_exp` / `compute_day_gains`) + **weekday application** (`apply_day_training(day)`) + leftover-EXP bank. `training/README.md` |
| TrainingView             | `training/TrainingView.gd`                   | Schedule editor; "훈련 확정" calls `SeasonHub.on_training_confirmed` — it does not settle the board but **opens the week** (puts the weekday cursor on Monday). |
| WeekProgressView         | `week/WeekProgressView.gd`                   | **Week progress** — top horizontal weekday rail + that day's training results / match cards + bottom "확인" ("경기 시작" on a match day). `week/README.md` |
| LeagueManager            | `league/LeagueManager.gd`                    | Round-robin schedule keyed by `phase_week` (1 round per week), standings, `resolve_current_week()` for AI matches. |
| TournamentManager        | `tournament/TournamentManager.gd`            | 4-team SE playoff bracket distributed across 2 weeks (SF week + F week). |
| InternationalTournament  | `tournament/InternationalTournament.gd`      | 8-team SE INTL bracket distributed across 3 weeks (QF / SF / F). |
| LeagueView               | `league/LeagueView.gd`                       | Standings screen — "다음 주 →" advances week, "돌아가기" (Go back) returns to HUB. |
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

## Match-day handoff
- On Sat / Sun of the week-progress screen, if `SeasonHub.has_player_match_on_day(day)` is
  true, the bottom button becomes **"경기 시작"** (Start match). Pressing it,
  `on_week_day_match_start()` → `_launch_player_match_on_day(matchday)` fills
  `season_state["pending_match"]` (`{source, schedule_idx, enemy_team_id,
  winner_side}`) and does `change_scene_to_file` to MatchFlow.
  Priority is as before: INTL > playoff > league (`_find_player_match_source`).
- MatchFlow runs PREP → BAN_PICK (ban/pick (밴픽) + mech (메크) assignment) → BattleSim. The
  jungle start (정글 시작) direction is asked by BattleSim right before the opening (개시).
- When BattleSim ends, the win panel's "다음 →" (Next) returns to `Season.tscn`.
- `SeasonHub._ready` consumes `pending_match`, applies the result via
  `LeagueManager.record_result()` / `TournamentManager.record_result()` /
  `InternationalTournament.record_result()`, then calls
  `_resolve_ai_for_matchday(md)` — **only that match day's AI matches**. Running the whole week
  would put Sunday results that haven't been played yet into the standings shown after Saturday's
  match. It then routes to STANDINGS.
- **"확인"** (OK) on the standings / bracket is `on_standings_confirmed()` — if the week is running
  (`week_day >= 0`) it returns to that weekday, otherwise to the hub. The old
  "다음 주 →" button was deleted from all three screens (advancing the week moved to the Sunday
  close).

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

## White background theme
**Every colour on outgame screens goes through `resources/OutgameTheme.gd`** — background ·
cards · text · accents · role colours · button styles · weekday names all live in that one table.
The design principle is coloured cards on white paper. If each screen held its own `Color(...)`
literals, the same card would be drawn in a different grey on each screen, and touching up the
palette once would mean combing through a dozen-plus files.
**In-game (BattleSim) does not use this table** — the battlefield (전장) is a dark screen.

## Autosave triggers (5)
0. **Post-match** — `SeasonHub._ready` right after the BattleSim result is
   applied (so closing on the standings screen preserves the outcome).
1. **Post-draft** — `SeasonHub.goto(HUB)` when previous screen was DRAFT.
2. **Pre-ban-pick** — `MatchFlow._on_prep_finished` after the player
   confirms PREP. Writes `season_state["match_resume"] = {phase: BAN_PICK,
   player_side, ...}`.
3. **Post-ban-pick** — `MatchFlow._on_ban_pick_finished` before
   `change_scene_to_file` to BattleSim. Writes the full match snapshot
   (banned/picked/assigned mech IDs) into `match_resume`.
4. **Post-week-end** — `SeasonHub._end_week` after `advance_week` (the
   Sunday close). Captures both post-match weeks and no-match weeks.

No save fires inside BattleSim. Closing mid-battle leaves the disk save at
trigger #3; resume re-enters BattleSim with the locked-in picks but the
battle replays from scratch.

## Resume routing
TitleScreen "이어하기" (Continue) branches on `season_state["match_resume"]`:
- Non-null → `MatchFlow.tscn` (MatchFlow consumes the hint and skips
  PREP, jumping directly to BAN_PICK or LAUNCH depending on the saved
  phase).
- Null → `Season.tscn` → SeasonHub → HUB.

SlotCard shows a "경기 진행 중" (Match in progress) tag when `meta.match_in_progress == true`
(set whenever `match_resume` is non-null at save time).

## SeasonHub screen routing
`SeasonHub._route()` toggles child controls based on `current_screen`.
Lazy view builders cache the instance after first creation.
- `Screen.DRAFT` → `TeamDraft`.
- `Screen.HUB` → simplified HubView. Calls `LeagueManager.ensure_phase_scheduled()`
  + `TournamentManager.ensure_active()` + `InternationalTournament.ensure_active()`
  to handle save-loads landing on tournament weeks.
- `Screen.PRESS` → `PressConferenceView` (opens a fresh conference every time).
- `Screen.TRAINING` → `TrainingView`.
- `Screen.WEEK` → `WeekProgressView` (the weekday cursor is `season_state["week_day"]`).
- `Screen.LEAGUE` → `LeagueView` (standings).
- `Screen.PLAYOFF` → `BracketView`.
- `Screen.INTL_BRACKET` → `IntlBracketView`.
- `Screen.GAME_OVER` → `GameOverView`.
- `Screen.ENDING` → `EndingView`.

## Calendar contract
- `CalendarSystem.advance_week()` is the single tick, and **only
  `SeasonHub._end_week()` calls it** — the Sunday close. Rolls 7 days
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

---

## Screen fit (safe area)

All season views draw in absolute coordinates on a full-screen `Control`. The convention is two lines.

```gdscript
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)   # push the whole screen down below the notch
	...
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ScreenMetrics.extend_background(bg)      # stretch only the background back up into the notch area
```

**Don't push down only the title** — the body stays in place and the two overlap (on the title
screen the title actually slid under the slot cards).

When hanging the bottom action bar inside a pushed-down screen, use **`safe_h()`**, not
`ScreenMetrics.bottom_y()` (the latter is in viewport coordinates, so the push-down gets added twice).
`LeagueView` / `BracketView` / `IntlBracketView` / `TrainingView` use
`safe_h() - 80 - h`, `TrainingResultView` uses `- 70`, `HubView` uses `- 110`,
and `TeamDraftView`'s `bar_y()` is `safe_h() - 20 - BAR_H`.

`TeamDraftView.grid_h()` is computed from **the remaining space** (`bar_y() - 12 - GRID_Y`) —
the taller the screen, the more thumbnail rows show (950 at 1920, 1280 at 2340).

Details: **`docs/mobile_safe_area.md`**


## Detail moved from root CLAUDE.md

### Season → MatchFlow → BattleSim handoff
Pressing "경기 시작" on Sat / Sun of the week-progress screen,
`SeasonHub.on_week_day_match_start()` → `_launch_player_match_on_day(matchday)`
fills `season_state["pending_match"]` (`{source, schedule_idx, enemy_team_id,
winner_side}`) and does `change_scene_to_file` to MatchFlow.tscn.
MatchFlow runs PREP (review rosters) → BAN_PICK (ban/pick + mech assignment) →
BattleSim (the jungle start direction is asked inside it). **BAN_PICK also receives both teams'
rosters and team names** — it stands 5 eye portraits (초상화) per team at the top and bottom of the
screen, the same as the battlefield strip (스트립), attaches mech slots outside them, and once the 14
moves are done **writes the assignments directly into those rosters** and returns them
(`MatchFlow._enter_phase` passes `_team_roster()` / `_team_name()` along, and
`_on_ban_pick_finished` puts the result's `player_roster` / `enemy_roster` straight into
`match_ctx`).
The side (`player_side`) is **currently always fixed to BLUE**
(the old per-match random draw was removed), and together it decides the ban/pick order and
BattleSim's strategy-point priority · first turn — see the "Side (blue / red)" (진영 (블루 / 레드))
entry above.
After BattleSim, the win panel's "다음 →" returns to
`Season.tscn`. `SeasonHub._consume_pending_match_result` applies the
result via `LeagueManager.record_result()` /
`TournamentManager.record_result(slot, winner)` /
`InternationalTournament.record_result(slot, winner)` based on
`pending_match.source`. Then `_resolve_remaining_ai_for_week()` sweeps up
remaining AI matches scheduled for the same week, and the hub routes to
the appropriate STANDINGS view.

### Season — Playoff bracket (Phase 7)
Each league phase reserves **2 trailing playoff weeks** (SF week + F
week). `CalendarSystem.PHASE_WEEKS` = LEAGUE_WEEKS + 2 for league phases.
`TournamentManager` bootstraps the bracket when entering the playoff
bootstrap week (week LEAGUE_WEEKS + 1):
`SF1: #1 vs #4` and `SF2: #2 vs #3` both stamped to that week,
`F: SF1.W vs SF2.W` stamped to week LEAGUE_WEEKS + 2. If
`LeagueManager.player_made_playoffs()` is false on bootstrap,
`playoff_failed_qualification` fires and `SeasonHub` routes to
`Screen.GAME_OVER`. Otherwise `playoff_started` fires; AI bracket matches
resolve via `TournamentManager.resolve_current_week()` during the post-
match sweep, player matches go through the MatchFlow → BattleSim handoff
with `pending_match.source = "playoff"`. The F result writes
`phase_results[phase] = {made_playoffs, champion}` and emits
`playoff_completed`.

### Season — INTL bracket (Phase 8)
Each *_INTL phase (`PRESEASON_INTL`, `MIDSEASON_INTL`, `REGULAR_INTL`) is
a **3-week 8-team single-elimination tournament**. Week 1 = QF (4
matches), Week 2 = SF (2 matches), Week 3 = F. `InternationalTournament`
bootstraps on entry to week 1 of an INTL phase using top-4 from
`LeagueManager.standings_ranked()` (the just-finished league phase's
standings) + 4 fixed external teams from `data/csv/intl_teams.csv` +
`intl_players.csv`. High-low pairing (L1×I4, L2×I3, L3×I2, L4×I1). Both
managers share `season_state["current_tournament"]` but discriminate by
`type` ("INTL" vs "PLAYOFF") — neither clears the other's bracket. AI
matches resolve via `InternationalTournament.resolve_current_week()`;
player matches use the MatchFlow → BattleSim handoff with
`pending_match.source = "intl"` → `InternationalTournament.record_result`.
`MatchFlow._team_roster()` reads from `season_state.intl_pilots` when
`team_id >= 100`. **REGULAR_INTL is the campaign-end gate**: win F →
`Screen.ENDING`; lose F or get eliminated mid-bracket → `Screen.GAME_OVER`
(via `intl_failed_campaign` for fail-fast). PRESEASON_INTL and
MIDSEASON_INTL just toast and continue. Phase results: INTL phases store
`{intl_played, intl_champion}` under `phase_results[phase]`; league
phases store `{made_playoffs, champion}`. HubView's third action button
toggles 3-way: INTL active → "국제대회" (International tournament), PLAYOFF active → "플레이오프"
(Playoffs), else → "리그 순위" (League standings).
