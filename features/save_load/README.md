# Save / Load

Two save files (outgame meta plan M0, `docs/outgame_dev_plan.md` §2.1):

| File | Owner | Lifetime | Content |
|---|---|---|---|
| `user://profile.save` | `ProfileManager` autoload (`autoloads/README.md`) | permanent | account progress — collection, manager, traits, currency, run history (schema: plan §4) |
| `user://run.save` | `SaveSystem` (this folder) | run start → run end | the in-progress run: `meta` + full `GameManager.season_state` |

There is **one run at a time**. The old 3-slot files (`user://saves/slot{0,1,2}.save`)
are ignored — no migration.

**Test run file** — `GameManager.use_test_run` defaults to `true`, so running
`Season.tscn` / `MatchFlow.tscn` directly from the editor still autosaves, but into
the hidden `user://run_test.save`. The lobby sets it to `false` in `_ready`, so a
normal boot (Lobby is `run/main_scene`) always uses `user://run.save`. The lobby
never shows the test run.

Auto-save fires at four discrete points (no manual save UI):

1. **Post-run-start** — first DRAFT → HUB transition (SeasonHub).
2. **Pre-ban-pick** — MatchFlow `_ready()`, right before BAN_PICK starts.
3. **Post-ban-pick** — `_on_ban_pick_finished` in MatchFlow, right after
   mech (메크) assignment finishes and just before BattleSim launches.
4. **Post-match** — SeasonHub `_ready()` after `_consume_pending_match_result`
   applies the result and clears `match_resume`.

No save fires while BattleSim is running — closing mid-battle resumes from
the post-ban-pick snapshot and replays the battle (the jungle start screen shows again too).

**Run end** — `EndingView` / `GameOverView` call `SaveSystem.delete_run()` from both
buttons (`다시 시작` → Season.tscn, `로비로` → Lobby.tscn). M2 inserts the run-result
settlement (write to profile) right before that delete.

## Entry point
`scenes/Lobby.tscn` (`features/meta/lobby/`) — `run/main_scene` in `project.godot`.
The lobby reads `SaveSystem.has_run()` / `read_run_meta()` and routes to
`Season.tscn` / `MatchFlow.tscn` — see `features/meta/README.md`.

## Files
| File | Class | Purpose |
|---|---|---|
| `SaveSystem.gd` | `class_name SaveSystem extends RefCounted` | Static run-file helpers: path / exists / meta / save / load / delete + season_state serialization |

`ProfileManager` lives in `autoloads/` (it is an autoload, not a feature script).

### SaveSystem API
| Function | Returns | Notes |
|---|---|---|
| `run_path()` | `String` | `TEST_RUN_PATH` when `GameManager.use_test_run`, else `RUN_PATH` |
| `has_run()` | `bool` | file at `run_path()` exists |
| `read_run_meta()` | `Dictionary` | the `meta` block, `{}` when missing / corrupt |
| `save_run()` | `String` | `""` on success; error when `season_state.active` is false |
| `load_run()` | `String` | overwrites `GameManager.season_state` |
| `delete_run()` | `String` | `""` also when there is no file |

## Run file schema (v1)
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

The `meta` block is denormalized info for the lobby's run card, computed
once at save time, so the lobby can render it without loading the full
season_state (and without instantiating LeagueManager).
`match_in_progress` is true when the run was saved between BAN_PICK start
and BattleSim launch — the lobby shows a "경기 진행 중" (Match in progress) chip and
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

| # | When | Where | match_resume |
|---|---|---|---|
| 1 | DRAFT → HUB | `SeasonHub.goto()` | null (cleared) |
| 2 | Pre-ban-pick (MatchFlow entry, before BAN_PICK starts) | `MatchFlow._ready()` | `{phase: BAN_PICK, ...}` |
| 3 | Post-ban-pick (after mech assignment is done, before BattleSim) | `MatchFlow._on_ban_pick_finished()` | `{phase: LAUNCH, ...}` |
| 4 | Post-match (return from BattleSim, result applied) | `SeasonHub._ready()` | null (cleared by `_consume_pending_match_result`) |

Both `_autosave` helpers call `SaveSystem.save_run()` unconditionally — which file
it lands in is decided by `use_test_run` (above).

## Mid-match resume
Closing the game between save #2 (pre-ban-pick) and save #4 (post-match)
leaves `match_resume` non-null on disk. On `이어하기` (Continue) in the lobby:

- The lobby branches on `season_state.match_resume`. Non-null →
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

## New-run vs continue flow (lobby)
- **새 런, no run**: `reset_season_state()` → Season.tscn. SeasonHub sees
  `season_state.active == false`, runs `init_season()` and DRAFT. First save fires at DRAFT → HUB.
- **새 런, run exists**: modal warning popup (`진행 중인 런을 포기할까요?`). Confirm →
  `SaveSystem.delete_run()` → `reset_season_state()` → Season.tscn. Cancel / tapping the
  dim closes it. (Abandon = delete only until M2 adds the fail settlement.)
- **이어하기**: `SaveSystem.load_run()` overwrites `season_state` (active=true) →
  MatchFlow.tscn if `match_resume != null`, else Season.tscn (skips `init_season()`).

---

## Screen fit (safe area)
The lobby's safe-area handling (shift to safe top, background extended to the edge,
bottom action bar above the gesture zone) is described in `features/meta/lobby/README.md`.
Details: **`docs/mobile_safe_area.md`**
