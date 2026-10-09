# Season (Outgame) Feature

The campaign / out-of-match metagame, restructured around weekly progression.
Player picks a 5-pilot team from a 40-pilot pool, then plays through six
events from December → next year:

```
PRESEASON → PRESEASON_INTL → MIDSEASON → MIDSEASON_INTL → REGULAR → REGULAR_INTL
```

Win the final REGULAR_INTL = ending. **All six tournaments must be won** —
missing a league phase's playoff cut, losing a playoff SF / F, or being
eliminated from any INTL ends the run right after that result (see
"Run end" below). The campaign progresses **one week at a time** — the
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
| LeagueView · BracketView · IntlBracketView | `확인` (OK) full width |
| WeekProgressView | `확인` / `주 마감 →` (End of week) / `경기 시작` (Start match) (dark) — always exactly one, full width |
| EndingView · GameOverView | `정산` (Settle) full width → `RunResult.SCENE_PATH` (the run is already settled on entry) |

The four conventions (body height is derived back from `bottom_bar_top()` · the colour fill extends
below the safe line but the text stays above it · when a cell collapses, call `layout_bottom_bar`
again · a slot that changes kind switches its `Bar*` variation and calls `fit_bar_button`) are in the "Bottom action bar" section of
`resources/README.md`. **The press conference (기자회견) answer choices are not this bar** — they are
choices standing inside the speech-bubble flow, so they are not pinned to the bottom.

## Entry point
`scenes/Season.tscn` — entered from the lobby (`scenes/Lobby.tscn`) via
`새 런` / `이어하기`. Root: `Control` with `SeasonHub.gd` attached.
**There is no DRAFT screen any more** — run setup (scenario → team → 5-pilot lineup)
lives outside the season in `features/meta/run_setup/` and ends with
`GameManager.start_run`, so the season **always opens at HUB**.
SeasonHub branches on `gm.season_state["active"]`: true → a run already exists
(fresh from run setup, or loaded) → HUB; false (editor direct-run of `Season.tscn`)
→ `init_season()` builds the default run (below) → HUB. See `features/save_load/`
for the save-system contract.

### Run start — `GameManager.start_run(run_setup) -> String`
The **only** way a run begins (contract: `docs/outgame_dev_plan.md` §10.2). The run
setup screen (`features/meta/run_setup/`) calls it and opens `Season.tscn` on `""`.
Steps:
1. **Validate** with `RunRules.validate_lineup` against the Lv1 pool from `game.db`
   and `ProfileManager.owned_max_levels()`; also rejects an unknown `team_id` /
   `scenario`. A rejection leaves `season_state` untouched. **Test runs**
   (`use_test_run`, editor direct-run) skip the ownership check — any named
   (non-mob) pilot up to `RunRules.max_level()`; cap and role rules still apply.
2. `_init_season_core(team_id, pool)` — reset, pilot pool, team meta, INTL pool,
   standings, empty training board, `active = true`.
3. `run_seed` — fresh random, never 0 (0 = "no run seed", old saves).
4. AI rosters — `RunRoster` (below); my 5 go to `team_id`.
5. `RunRules.apply_level` on my 5 — on the run copy in `season_state.all_pilots`
   only (stats already include the level; `salary` stays the Lv1 base).
6. `team_rosters` rebuilt (each team's ids in role order).
7. `season_state.run_setup` stored — `pilot_ids` sorted into `GameEnums.Role` order,
   `pilot_levels` string-keyed, `salary_cap` / `salary_total` **recomputed** here
   (the caller's values are ignored).

**Editor direct-run default.** `init_season(team_id := 0)` is now just
`start_run(default_run_setup(team_id))`, so SeasonHub's `active == false` path builds a
real run through the same code. `default_run_setup()` = the scenario with the
highest `salary_cap`, per role the starter (`players.starter = 1`) with the lowest id
(falls back to the lowest-id named pilot of that role), all Lv1. `start_run` never
calls `init_season` (no recursion) — both share `_init_season_core`.

### AI roster distribution — `features/meta/run_setup/RunRoster.gd`
`class_name RunRoster`, static and pure (no nodes, no global RNG).
- `assign(pilots, player_team_id, player_pilot_ids, run_seed, team_count)` →
  `{"error": "", "teams": {pilot_id: team_id}}`. For each role (in enum order) the
  pilots that are **not** mine — including the chosen team's original pilots — are
  sorted by id, shuffled (Fisher–Yates) with one `RandomNumberGenerator` seeded from
  `run_seed`, and dealt one each to the AI teams in ascending id order. Every team
  ends with exactly one pilot per role. Same seed → same result, regardless of input
  order. Mismatched counts (pool ≠ teams × roles, not one pick per role, unknown
  role) return `{"error": String}` instead of crashing.
- `apply(pilots, teams)` writes `PlayerData.team_id`.
- `build_rosters(pilots, team_count)` → `team_rosters` (`team_id → Array[int]`,
  role order).

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
| HubView                  | `HubView.gd` + `.tscn`                       | Simplified hub — phase/week counter + roster + "이번 주 시작" (Start this week) + 순위 (standings) buttons. The roster is **five small vertical `SeasonPilotCard`s side by side** (seat order): badge, portrait in a **trust ring** (trust / `TRUST_MAX`, band colour `HubView.trust_color`: grey < `TRUST_OUTING_MIN`, green from there, amber past halfway to `TRUST_MAX`) with the trust number at its bottom-right, stress line + mood. Tap = `SeasonPilotDetail` sheet. Stats live in that sheet, not on the card. Scene-built — see "HubView · EndingView · GameOverView" below. |
| *(item)* SeasonPilotCard | `SeasonPilotCard.gd` + `UI_Comp_SeasonPilotCard.tscn` · `TrustRing.gd` | Shared small pilot card (hub roster, week screen bottom row): see "Pilot card · detail sheet" below. |
| *(overlay)* SeasonPilotDetail | `SeasonPilotDetail.gd` + `UI_View_SeasonPilotDetail.tscn` | Pilot detail `HubSheet` body, opened by tapping a pilot portrait / card anywhere in a run (hub, week screen, training board headers). See below. |
| PressConferenceView      | `press/PressConferenceView.gd` + `.tscn`     | **Press conference** — the messenger screen right before the week starts (`.tscn` = one `MessengerView` instance; `create()`). `press/README.md` |
| TrainingBoard            | `training/TrainingBoard.gd`                  | **Daily training (일상 훈련) tile board (타일판)** — 5 columns (players) × 5 rows (one per day; weekdays are not written on screen). Placement checks + settlement (`cell_exp` / `compute_day_gains`) + **weekday application** (`apply_day_training(day)`) + leftover-EXP bank. `training/README.md` |
| TrainingView             | `training/TrainingView.gd` + `.tscn`         | Schedule editor; "훈련 확정" calls `SeasonHub.on_training_confirmed` — it does not settle the board but **opens the week** (puts the weekday cursor on Monday). |
| WeekProgressView         | `week/WeekProgressView.gd` + `.tscn`         | **Week progress** — top horizontal weekday rail + that day's training results / match cards + bottom "확인" ("경기 시작" on a match day). Layout in `.tscn`, cards are `week/Week*Card.tscn` item scenes; `create()`. `week/README.md` |
| LeagueManager            | `league/LeagueManager.gd`                    | Round-robin schedule keyed by `phase_week` (1 round per week), standings, `resolve_current_week()` for AI matches. |
| TournamentManager        | `tournament/TournamentManager.gd`            | 4-team SE playoff bracket distributed across 2 weeks (SF week + F week). |
| InternationalTournament  | `tournament/InternationalTournament.gd`      | 8-team SE INTL bracket distributed across 3 weeks (QF / SF / F). |
| LeagueView               | `league/LeagueView.gd` + `.tscn`             | Standings screen — 8 `UI_Comp_LeagueRow.tscn` rows + a single full-width "확인" (OK). Built with `LeagueView.create()`; `league/README.md`. |
| BracketView              | `tournament/BracketView.gd` + `.tscn`        | Phase-7 playoff bracket UI (3 `UI_Comp_BracketMatchBox.tscn` boxes: SF1/SF2/F). Built with `BracketView.create()`; see "Bracket screens" below. |
| IntlBracketView          | `tournament/IntlBracketView.gd` + `.tscn`    | Phase-8 INTL bracket UI (7 `UI_Comp_IntlMatchBox.tscn` boxes: 4 QF / 2 SF / F). Built with `IntlBracketView.create()`; see "Bracket screens" below. |
| GameOverView             | `GameOverView.gd` + `.tscn`                  | Game-over screen — playoff cut missed, playoff SF/F lost, or any INTL lost (reason line names the round) |
| EndingView               | `EndingView.gd` + `.tscn`                    | World-champion ending screen — REGULAR_INTL win                  |
| *(overlay)* HubSheet     | `HubSheet.gd` + `UI_View_HubSheet.tscn`              | Shared detail-sheet **frame** for the hub manage cards (`StaffPanel` · `MasteryPanel` · `FinancePanel`) and the standings team detail (`LeagueView.open_team_detail`). See "HubSheet" below. |

**F6 preview** — each of these scenes run alone fills dummy data (`resources/UiPreview.gd`, branch in
`_ready`, `_fill_preview()` at the bottom of the script). Screens use an in-memory run (nothing saved)
plus preview-only manager children, since `_hub` is null standalone:
`HubView` = 2 league weeks played (week / next-match lines filled from the preview league — they
normally come from the host) · `HubSheet` = own-team detail (a `LeagueTeamDetail` body) · `EndingView` = all six titles won ·
`GameOverView` = preseason playoff final lost · `BracketView` = SFs done, final pending ·
`IntlBracketView` = preseason INTL, QFs done, SFs pending. Item scenes use hand-written values:
`SeasonPilotCard` (Corin, trust past half, shaken) · `SeasonPilotDetail` (my first pilot of the in-memory run) · `HubManageCard` (finance, alert dot) · `BracketMatchBox`
/ `IntlMatchBox` (own team won). `정산` / `확인` / hub buttons only print (no settlement, no scene change).
`EndingView` / `GameOverView` keep their managers in `_league` / `_intl` / `_tournament` (re-read from
`_hub` every refresh; the preview sets them directly).

### HubSheet (`UI_View_HubSheet.tscn` + `HubSheet.gd`)
CanvasLayer 18, opened with `HubSheet.open_on(host, title)` (instantiates the scene via `create()`,
adds it under `host`, sets the title, fits the safe area). One-shot: `close()` (dim tap · `닫기`)
emits `closed` and frees it; `HubView` connects `closed` → `refresh()`.

```
HubSheet (CanvasLayer 18)
└ Root (full rect, theme = OutgameTheme.tres)
  ├ %Dim        flat Button — tap outside the card closes
  ├ DimRect     Panel · DimPanel
  └ %SafeArea   full rect; code sets top / bottom offsets to the safe-area insets
    └ %Card     Panel · PopupCard, centred 1008 wide, 60 below / 24 above the safe edges (STOP)
      └ %Pad    MarginContainer 40 / 34 / 40 / 40
        └ VBox (sep 0): %Title (TitleLabel, 40, ellipsis) · Gap 14 · Divider · Gap 15 ·
                        ScrollSlot (expand) ─ %Scroll ─ %Body · Gap 20 · %Close (GhostButton, 112)
```

- **Scene owns** the frame layout and styles (card size / margins, title, divider, button).
- **Code owns** the safe-area offsets, title text, close wiring, `DragScroll.attach(%Scroll)`.
- **Callers own the body** — children under `sheet.body`, width
  `sheet.body_w()` (= `%Card` width − `%Pad` side margins = 928), height via `set_body_height(h)`.
  Every body is one scene instance (top-wide, `resized` → `set_body_height`): `FinancePanel` ·
  `StaffPanel` · `MasteryPanel` · the standings team detail `league/LeagueTeamDetail` — see their
  folder READMEs. No caller places absolute-positioned children in the body any more.
  `card()` returns `%Card` for controls outside the scroll (card-local coords).
- `%Scroll` sits in a plain `ScrollSlot` Control and grows **right only** — when the body overflows,
  the scroll bar adds its width outside the 928 column instead of widening the VBox, so content x and
  `body_w()` never move.

### HubView · EndingView · GameOverView (`.tscn` scenes)
Created with `Xxx.create()` (`load(SCENE_PATH).instantiate()`; `.new()` is an empty Control).
Root = full-rect `Control`, theme `OutgameTheme.tres`, mouse PASS. Safe area (pattern B,
`docs/mobile_safe_area.md`) is **code offsets only**: `ScreenMetrics.indent_to_safe_top(self)`,
`ScreenMetrics.extend_background(%Background)`, `OutgameTheme.fit_bottom_bar(%BottomBar, %SafeBottom)`.

```
HubView (Control · HubView.gd)
├ %Background   ColorRect BG (code stretches it up over the notch)
├ %Phase (Caption 24) · Title "시즌 허브" (Heading) · %Week (Sub, right-anchored) · %NextMatch (Accent 24)
├ RosterCaption "내 팀 로스터" (Caption 24)           ← header labels: absolute offsets
├ Body VBox (x 30..−30, y 240, sep 12)
│ ├ %Roster HBox (sep 12) ─ SeasonPilotCard_Pilot0..4  SeasonPilotCard instances (expand), seat order (ROLE_DISPLAY_ORDER)
│ ├ GapManage (12)
│ └ %Manage HBox (sep 16, 176) ─ HubManageCard_Card0..2  HubManageCard instances, `_manage_panels()` order
└ %SafeBottom   full rect; code lifts its bottom by the bottom inset
  ├ %Toast      Accent label, 40 above the bar
  └ %BottomBar  HBox, 128 tall, sep 0 ─ %Standings (BarGhost 32, ratio 1, + Sep BarSeparator) · %Start (BarPrimary, ratio 2)

HubManageCard (Panel · Card · HubManageCard.gd)
├ VBox (20,14): %Title · %Value (34) · %Sub (20) · %Owner (Accent 18)
├ %Alert  red dot top-right
└ %Hit flat Button over the card → `pressed`

EndingView: %Background · Title "WORLD CHAMPION" (Accent 72) · Subtitle · RecapCaption ·
  %Recap VBox (800 centred, y 390) ─ 6 lines × 40 · RosterCaption · %Roster VBox (y 720) ─ 5 rows × 40 (HBox: `Badge` PositionBadge · `Text`) ·
  %SafeBottom/%BottomBar ─ %Settle (BarPrimary 32)
GameOverView: %Background · Title "GAME OVER" (NegativeLabel 80) · %Reason (Body 28) ·
  %Summary (Caption) · %SafeBottom/%BottomBar ─ %Settle (BarPrimary 32)
```

- **Scene owns** layout, texts' sizes / variations, bar ratio, the five rows / three cards / line slots.
- **Code owns** data, data colours (pilot cards: see below; recap line amber when won), safe-area offsets.
  The old `HubRosterRow` (horizontal row with face · name · TOTAL · trust gauge · six short stat columns) was deleted.
- **Bottom bar in a scene**: the buttons are `Bar*` variations (square corners) and the separator is a
  `BarSeparator` Panel inside every button but the last. `OutgameTheme.fit_bottom_bar(%BottomBar, %SafeBottom)`
  adds only the device inset: `%SafeBottom.offset_bottom = −inset`, `%BottomBar.offset_bottom = +inset` (colour
  fill reaches the viewport bottom) and each button's `content_margin_bottom += inset` (text stays above the
  safe line) — `resources/README.md` "Bottom action bar".
- Manage cards use the `Card` variation (radius 18; the old code card was 16).

### Pilot card · detail sheet (`SeasonPilotCard` · `SeasonPilotDetail`)
Every in-run screen that shows my five pilots as a group uses the same small vertical card, and **tapping a
pilot portrait opens the detail sheet** (hub roster, week screen bottom row, training board column headers).
Stat names are always written in full (`PlayerData.stat_label`: "전장 명중", never "전명").

```
SeasonPilotCard (Panel · Card, min h 256, width from the row · SeasonPilotCard.gd)
├ BadgeSlot CenterContainer (y 12..42) ─ %PositionBadge_Role (PositionBadge)
├ %Ring (TrustRing, 140², centred, y 50) ─ %Portrait slot 116² inside (code: add_round_portrait)
├ %TrustPill (ProgressFill 56×34, portrait bottom-right) ─ %TrustText (OnFill 22)
├ %Stress (Caption 20, y 196)        "스트레스 N", NegativeLabel when shaken
├ %StressNote (28, y 220)            emphasised line: hub = mood when shaken; week = the day's stress change
└ %Hit flat Button over the card → pressed(pilot_id)

SeasonPilotDetail (VBox, HubSheet body, title = pilot name · SeasonPilotDetail.gd)
├ Head HBox ─ %SeasonPilotCard_Head (same card, not tappable) · Info VBox: %Total · %Trust · %Outings · %Mood
├ StatsTitle · %Stats ─ Stat0..5 (Line: Name (Body 26) · Value (Title 30)) + Note (Caption 18, stat_note)
├ QuirksTitle · %QuirksEmpty · %Quirks ─ %QuirkLine template ("name · effect", grade colour)
└ ResearchTitle · %Research (research mech · tier (value / max), tier colour) · Tail
```

- API: `SeasonPilotCard.show_pilot(pid, role, trust, stress)` / `show_empty(role)` / `set_note(text, variation)` /
  `pulse_note()` / `set_tappable(on)`; `SeasonPilotDetail.open(host, pilot_id) -> HubSheet` (null for an unknown id).
- `TrustRing` (`@tool` `_draw` widget): `width` (scene), `ratio` · `color` (code). Track = `SURFACE_SUNK`, arc from 12 o'clock.

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
1. **Post-run-start** — `SeasonHub._show_hub` on the first HUB of a fresh run.
   Detected from state, no extra save key (`_is_run_start`): PRESEASON, week 1,
   `week_day == -1` and no PRESEASON entry in `match_schedule` yet — measured before
   `ensure_phase_scheduled` lays the schedule, so it is true exactly once per run.
2. **Pre-ban-pick** — `MatchFlow._on_prep_finished` after the player
   confirms PREP. Writes `season_state["match_resume"] = {phase: BAN_PICK,
   player_side, ...}`.
3. **Post-ban-pick** — `MatchFlow._on_ban_pick_finished` before
   `change_scene_to_file` to BattleSim. Writes the full match snapshot
   (banned/picked/assigned mech IDs) into `match_resume`.
4. **Post-week-end** — `SeasonHub._end_week` after `advance_week` (the
   Sunday close). Captures both post-match weeks and no-match weeks.

**No autosave after the run ends** — `SeasonHub.autosave` is a no-op while
`season_state.run_over` is true, so the post-match / post-week saves that
follow a game-over / ending result never resurrect the deleted `run.save`.

No save fires inside BattleSim. Closing mid-battle leaves the disk save at
trigger #3; resume re-enters BattleSim with the locked-in picks but the
battle replays from scratch.

## Resume routing
The lobby's "이어하기" (Continue) branches on `season_state["match_resume"]`:
- Non-null → `MatchFlow.tscn` (MatchFlow consumes the hint and skips
  PREP, jumping directly to BAN_PICK or LAUNCH depending on the saved
  phase).
- Null → `Season.tscn` → SeasonHub → HUB.

The lobby run card shows a "경기 진행 중" (Match in progress) chip when `meta.match_in_progress == true`
(set whenever `match_resume` is non-null at save time).

## SeasonHub screen routing
`SeasonHub._route()` toggles child controls based on `current_screen`.
Lazy view builders cache the instance after first creation.
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

### Bracket screens (`tournament/BracketView` · `IntlBracketView`)
Layout lives in the scenes; `create()` instantiates them (never `.new()`).
```
BracketView (Control, full rect, OutgameTheme)          IntlBracketView — same header / Empty / OkButton
├ %Background  ColorRect BG (code extends into notch)    └ %Bracket HBox (anchored top-centre, y 240)
├ Title · %Phase · %Stage · %NextMatch  (top-wide, centred)   ├ Quarters VBox (sep 50) ─ %IntlMatchBox_QF1..QF4 (280×130)
├ %Empty   FaintLabel, hidden (shown when no bracket)         ├ GapQS 70
├ %Bracket HBox (anchored top-centre, y 250, sep 70)          ├ Semis VBox ─ TopGap 145 · %IntlMatchBox_SF1 · MidGap 180 · %IntlMatchBox_SF2 (280×150)
│ ├ Semis VBox (sep 60) ─ %BracketMatchBox_SF1 · %BracketMatchBox_SF2   (420×200)             ├ GapSF 50
│ └ %BracketMatchBox_Final  (size_flags_vertical = centre)                    └ FinalColumn VBox ─ TopGap 300 · %IntlMatchBox_Final (320×170)
└ %OkButton  BarPrimaryButton, anchored bottom-wide
```
- Match boxes: `BracketMatchBox.gd` on two item scenes — `UI_Comp_BracketMatchBox.tscn` (playoff: 22/18/28 px
  fonts, radius 8) and `UI_Comp_IntlMatchBox.tscn` (INTL: 18/16/22 px, radius 6). Each instance sets
  `slot_title` (an l10n key `season.slot.*` — "4강 1경기" …) in the screen scene; the box size is the instance's minimum size.
  `show_match(m, pid, team_text)` fills team / week text and paints the data colours (team colour by
  player / winner / loser, border amber 3px for the player's match, green 2px decided, `BORDER` 2px
  otherwise — the `StyleBoxFlat` is built in code because the border is data).
- Script owns: text, `%Empty` / `%Bracket` visibility, safe-area offsets, bottom-bar styling.

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
`TrainingResultView` uses `safe_h() - 70 - h`; `HubView` · `EndingView` · `GameOverView` are
scene-built and hang the bar from `%SafeBottom` (above), `TrainingView` from `%SafeArea` (`training/README.md`)
(the lineup screen moved to `features/meta/run_setup/README.md`).

**Scene-based views** (`LeagueView` · `BracketView` · `IntlBracketView`): layout is anchors in the
`.tscn`, so the script only applies offsets — `indent_to_safe_top(self)` + `extend_background(%Background)`
in `_ready`, and the bottom-bar button (`%OkButton`, `BarPrimaryButton`, anchored bottom-wide in the scene)
gets `OutgameTheme.fit_bottom_bar(%OkButton)` (`offset_top = -(BOTTOM_BAR_H + bottom inset)`, text lifted
above the inset) — the same rect `add_bottom_bar` would give.

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
`playoff_completed`. **A player loss in SF or F** (only `record_result` can
eliminate the player) marks the bracket `player_eliminated` / `eliminated_slot`,
writes `phase_results[phase] = {made_playoffs: true, champion: -1}` if the
final hasn't been played, and emits `playoff_lost` once → `Screen.GAME_OVER`.

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
`team_id >= 100`. **Every INTL must be won**: player eliminated in any
round of any INTL → `intl_failed_campaign` (once — the bracket is marked
`player_eliminated`) → `Screen.GAME_OVER`. Winning F → `intl_completed`
(only ever carries the player's team; marked `completed` so later sweeps
don't re-emit): REGULAR_INTL → `Screen.ENDING`, PRESEASON_INTL /
MIDSEASON_INTL → HubView toast and the campaign continues. Phase results: INTL phases store
`{intl_played, intl_champion}` under `phase_results[phase]`; league
phases store `{made_playoffs, champion}`. HubView's third action button
toggles 3-way: INTL active → "국제대회" (International tournament), PLAYOFF active → "플레이오프"
(Playoffs), else → "리그 순위" (League standings).

### Season — Run end (M2)
Contract: `docs/outgame_dev_plan.md` §10.1 / §10.3.
- Six tournaments, any non-title = run over immediately: `playoff_failed_qualification`,
  `playoff_lost`, `intl_failed_campaign` → `SeasonHub._enter_run_end(GAME_OVER)`;
  REGULAR_INTL `intl_completed` → `_enter_run_end(ENDING)`.
- `_enter_run_end` fixes the first conclusion, **settles right away**
  (`_settle_run` → `RunResult.settle_current_run("fail" | "clear")`, guarded by
  `season_state.run_over` so it runs once per run) and routes **deferred** — the
  signals can fire mid-`_end_week` (calendar tick) or mid-`_show_hub`
  (`ensure_active()`), whose remaining code would otherwise redraw the hub over
  the end screen. `_show_game_over` / `_show_ending` also call `_settle_run`
  as a backstop.
- Settlement deletes `run.save`; with `run_over` set `autosave` does nothing, so a
  run file can never be left pointing at a GAME_OVER / ENDING state (continue
  always resumes from the last pre-end save, or there is no run).
- GameOverView / EndingView keep their presentation; their single bottom-bar
  button `정산` goes to `RunResult.SCENE_PATH`. They no longer delete the run or
  reset `season_state` — the RunResult screen owns what happens next.

### Season — Match MVP · phase POM (M2) → `run_stats/README.md`
- `_consume_pending_match_result` calls `RunStats.record_match(state, pending_match)` **before**
  applying the result to the schedule (the apply can cascade straight into run-end settlement,
  which closes the current phase's POM — the last match must already be counted).
- `_on_phase_changed_close_pom` (connected to `CalendarSystem.phase_changed` in `_ready`) closes
  the phase that just ended: `RunStats.finalize_phase(state, new_phase - 1)`. Settlement
  (`RunResult`) closes the current phase the same way; both are idempotent.

## Localization
Display text is l10n keys (`season` domain; shared `ui.*` / `term.*` where the word is generic).
EndingView and GameOverView share the settle button key `season.ending_view.settle`; win-loss records reference
`term.record.win_loss`.
Scene labels that the script fills carry `auto_translate_mode = 2` (placeholder text stays for WYSIWYG);
fixed captions hold a key literal. Bracket slot names are `season.slot.*` — `TournamentManager.SLOT_LABELS` /
`InternationalTournament.SLOT_LABELS` (`slot_label(i)` returns translated text) and the `BracketMatchBox.slot_title`
values in the bracket scenes are the same keys (translated by the box). Week-progress match rows carry a
logic field `result` (`"win"` / `"loss"` / `""`) — the colour never compares display text.
