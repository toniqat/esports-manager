# Save / Load

Title-screen save-slot system. Three slots persisted as JSON under
`user://saves/slot{0,1,2}.save`. Auto-save fires at four discrete points
across the campaign / match-day lifecycle (no manual save UI):

1. **Post-draft** — first DRAFT → HUB transition (SeasonHub).
2. **Pre-ban-pick** — MatchFlow `_ready()`, right before BAN_PICK starts.
3. **Post-ban-pick** — `_on_ban_pick_finished` in MatchFlow, right after
   mech (메크) assignment finishes and just before BattleSim launches. It used to sit
   where the following JUNGLE_START finished (`_on_jungle_finished`), but it moved one
   step earlier when the jungle start (정글 시작) choice moved inside BattleSim.
4. **Post-match** — SeasonHub `_ready()` after `_consume_pending_match_result`
   applies the result and clears `match_resume`.

No save fires while BattleSim is running — closing mid-battle resumes from
the post-ban-pick snapshot and replays the battle (the jungle start screen shows again too).

## Entry point
`scenes/TitleScreen.tscn` — set as `run/main_scene` in `project.godot`.
The player picks a slot, then the scene changes to `Season.tscn`.

## Files
| File | Class | Purpose |
|---|---|---|
| `SaveSystem.gd`   | `class_name SaveSystem extends RefCounted` | Static helpers for serialize / deserialize / list / save / load / delete |
| `TitleScreen.gd`  | `extends Control` (no class_name — only used via scene) | Project entry. Builds the 3-slot UI. Routes button presses to GameManager + scene change. |
| `SlotCard.gd`     | `class_name SlotCard extends Control` | One slot card. Builds its own UI; parent feeds meta + callbacks. |

## Slot file schema (v1)
```json
{
  "version": 1,
  "meta": {
    "phase": 0, "year": 1, "month": 12, "day": 1, "weekday": 0,
    "team_name": "Team 0",
    "trophies": 0,
    "rank": 3, "wins": 5, "losses": 2,
    "saved_at": "2026-05-05 23:14",
    "match_in_progress": false
  },
  "season_state": { ...full GameManager.season_state, JSON-encoded... }
}
```

The `meta` block is denormalized info for the title-screen card, computed
once at save time. It lets the title screen render slot cards without
loading the full season_state (and without instantiating LeagueManager).
`match_in_progress` is true when the slot was saved between BAN_PICK start
and BattleSim launch — SlotCard surfaces a "경기 진행 중" (Match in progress) tag, and TitleScreen
routes "이어하기" (Continue) to MatchFlow.tscn instead of Season.tscn.

## Serialization notes
`season_state` is a Dictionary of mostly-primitive values plus a few
Resource-typed entries:
- `all_pilots` / `intl_pilots` are `Array[PlayerData]`. Persisted as plain
  Dicts via `_pilots_to_array` / `_array_to_pilots` — **`pilot_cards` (ids of the 3
  fixed pilot (파일럿) cards) is saved too.** Old saves without that key restore it as an empty
  array, and `GameManager.pilot_card_ids_for` fills it from the same player's DB row. `assigned_mech` is
  runtime-only (set in match flow) and is rebuilt on resume from
  `match_resume.{player,enemy}_assigned_mech_ids`, so it isn't persisted on
  the PlayerData rows themselves.
- `team_rosters`, `league_standings`, `phase_results` are all
  `Dictionary[int, X]`. JSON.stringify converts int keys to strings;
  `_int_keyed_dict_in` rebuilds the int keys on load.
- `training_board` is an `Array` of `{tile: String, x: int, y: int}` (weekly training board).
  JSON returns every number as a float, so `_board_in` casts `x`/`y` back to
  int on load — otherwise it becomes `{x: 0.0}`, every later spot that wraps it in
  `Vector2i(...)` needs one more cast, and missing even one spot breaks cell comparisons.
  (The old `training_schedule` `Dictionary[int, Array[7]]` was deleted.)
- **Three week-progress fields** — added when a week started flowing one day at a time,
  월~일 (Mon–Sun) (`features/season/week/README.md`).
  - `week_day` — the weekday (요일) currently being viewed, 0..6. **-1 means the week hasn't
    opened yet**, and that value decides whether the standings' "확인" (OK) returns to the
    week or to the hub.
  - `week_day_log` — `day(int) → Array[줄]` (`줄` = line), per-weekday training result log.
    **Int keys**, so it goes through `_int_keyed_dict_in` — otherwise `log[3]` forever
    returns an empty array and the same weekday's training is applied twice.
  - `training_exp_carry` — `seat(int) → {stat: 남은 EXP}` (remaining EXP) remainder ledger.
    Both the outer keys and inner values become strings / floats after JSON, so
    `_exp_carry_in` casts both back to int — otherwise `total / EXP_PER_POINT` stops being
    integer division and the remainder silently disappears.
- `pending_match` round-trips as-is. Non-null between match-day dispatch
  and `_consume_pending_match_result` (always paired with `match_resume`
  except briefly during post-match save where both are null).
- `current_tournament` rounds-trips as a plain dict.
- `match_resume` is the mid-match snapshot. Non-null between the pre-ban-pick
  save and the post-match save. Shape:
  ```
  { phase: int (MatchPhase.BAN_PICK or LAUNCH),
    player_side: int,
    banned_mech_ids, player_picked_mech_ids, enemy_picked_mech_ids: Array[int],
    player_assigned_mech_ids, enemy_assigned_mech_ids: Array[int] (5, role-sorted),
    jungle_start_dir: int }
  ```
  At BAN_PICK only `phase` + `player_side` are meaningful; the assignment
  fields are filled in at the post-ban-pick save. `jungle_start_dir` now
  **only ever holds the default (LEFT)** — that choice is asked by BattleSim right before
  the opening (개시), and resume replays the battle from the start anyway.

## Auto-save trigger points
Four trigger points across two scripts:

| # | When | Where | match_resume |
|---|---|---|---|
| 1 | DRAFT → HUB | `SeasonHub.goto()` | null (cleared) |
| 2 | Pre-ban-pick (MatchFlow entry, before BAN_PICK starts) | `MatchFlow._ready()` | `{phase: BAN_PICK, ...}` |
| 3 | Post-ban-pick (after mech assignment is done, before BattleSim) | `MatchFlow._on_ban_pick_finished()` | `{phase: LAUNCH, ...}` |
| 4 | Post-match (return from BattleSim, result applied) | `SeasonHub._ready()` | null (cleared by `_consume_pending_match_result`) |

`active_save_slot` is set on GameManager by TitleScreen. If a session enters
Season.tscn / MatchFlow.tscn directly (no slot chosen, e.g. running the
scene from the editor) `active_save_slot == -1` and `SaveSystem.save_slot(-1)`
is a no-op.

## Mid-match resume
Closing the game between save #2 (pre-ban-pick) and save #4 (post-match)
leaves `match_resume` non-null on disk. On `이어하기` (Continue):

- TitleScreen branches on `season_state.match_resume`. Non-null →
  `MatchFlow.tscn`. Null → `Season.tscn`.
- `MatchFlow._ready()` reads `season_state.match_resume`, clears it
  in-memory, and skips ahead:
  - `phase == BAN_PICK`: restore `player_side`, fall into the normal
    entry path. The pre-ban-pick save then re-fires (idempotent).
  - `phase == LAUNCH`: rebuild `match_ctx` (rosters, assigned mechs,
    bans, jungle dir) from the resume payload, scene-change directly to
    BattleSim. No phase UI runs.
- The on-disk `match_resume` is only overwritten by save #3 (post-ban-pick)
  or save #4 (post-match). Closing mid-battle leaves the disk save at #3,
  so the next resume drops back into BattleSim with the same locked-in
  picks.

## New-game vs continue flow
- **New game on empty slot**: `TitleScreen` calls `gm.reset_season_state()`,
  sets `active_save_slot = idx`, scene-changes to Season.tscn. SeasonHub
  sees `season_state["active"] == false`, calls `init_season()`, shows DRAFT.
  First save fires at DRAFT → HUB transition.
- **Continue on filled slot**: `SaveSystem.load_slot(idx)` overwrites
  `gm.season_state` from disk (active=true), `active_save_slot = idx`,
  scene-changes to Season.tscn. SeasonHub sees active=true, skips
  `init_season()`, routes straight to HUB.
- **Delete**: requires double-tap on the SlotCard (first tap arms, second
  tap deletes). No undo.
- **New game on filled slot**: not allowed directly — player must delete
  first. Keeps the destructive path explicit.

---

## Screen fit (safe area)

`TitleScreen._build()` shifts the whole screen down to the top of the safe area (안전 영역)
with `ScreenMetrics.indent_to_safe_top(self)`, and stretches only the background `ColorRect`
back to the screen edge with `extend_background(bg)` (the notch area is a place not to use,
not a place to leave empty).

The bottom hint label hangs at `ScreenMetrics.safe_h() - 100`.

**A bug that actually happened here**: only the title label was moved down by `top_y()`, so
the body (slot cards) stayed put and the title slid under the cards. Margins are applied per
screen, not per element.

Details: **`docs/mobile_safe_area.md`**


## Detail moved from root CLAUDE.md

### TitleScreen → Season handoff
`TitleScreen.gd` lists three slots (`user://saves/slot{0,1,2}.save`) via
`SaveSystem.list_slots()`. Each slot card shows phase + date, team + trophy
count, current league standing, and last-save timestamp. **새 게임** (New game) on an
empty slot: `gm.reset_season_state()` + `gm.active_save_slot = idx` + scene
change to Season.tscn → SeasonHub sees `season_state.active == false` and
runs the DRAFT flow. **이어하기** (Continue) on a filled slot: `SaveSystem.load_slot(idx)`
overwrites `gm.season_state` from disk + sets `active_save_slot` + scene
change → SeasonHub skips `init_season()` and routes to HUB. **삭제** (Delete) is
double-tap-to-confirm (first tap arms the button, second tap deletes).
GameOverView and EndingView both expose a "타이틀로" (To title) button that resets
season state + clears `active_save_slot` + returns to TitleScreen.tscn.

### Auto-save
Four trigger points across SeasonHub and MatchFlow:
1. **Post-draft** — `SeasonHub.goto(Screen.HUB)` when previous screen was DRAFT.
2. **Pre-ban-pick** — `MatchFlow._on_prep_finished()` after the player
   confirms PREP. Writes `season_state.match_resume = {phase: BAN_PICK, player_side, ...}`.
3. **Post-ban-pick** — `MatchFlow._on_ban_pick_finished()` right before
   scene-change to BattleSim. Writes the full match snapshot (banned/picked/
   assigned mech IDs) into `match_resume` with `phase = LAUNCH`. The jungle
   direction used to be included here too, so the save sat one step later
   (`_on_jungle_finished`); when that choice moved into BattleSim, the timing moved earlier —
   resume replays the battle from the start anyway, so the jungle direction is asked again then.
4. **Post-week-end** — `SeasonHub.on_proceed_to_next_week()` after
   `CalendarSystem.advance_week()` rolls the calendar. Covers both
   post-match weeks and no-match weeks.

No save fires inside BattleSim. Closing mid-battle leaves the disk save at
trigger #3, so resume drops back into BattleSim with the same locked-in
picks but the battle replays from scratch (the jungle start screen shows again too).

`SaveSystem.save_slot(gm.active_save_slot)` is a no-op when the slot is -1
(running Season.tscn / MatchFlow.tscn directly from the editor).

### Mid-match resume routing
TitleScreen "이어하기" branches on `season_state.match_resume`. Non-null →
`MatchFlow.tscn` (MatchFlow consumes the hint and skips PREP, jumping to
BAN_PICK or LAUNCH). Null → `Season.tscn`. SlotCard shows a "경기 진행 중"
(Match in progress) tag when `meta.match_in_progress == true`.
