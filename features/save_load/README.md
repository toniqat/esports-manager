# Save / Load

Two save files (outgame meta plan M0, `docs/outgame_dev_plan.md` §2.1):

| File | Owner | Lifetime | Content |
|---|---|---|---|
| `user://profile.save` | `ProfileManager` autoload (`autoloads/README.md`) | permanent | account progress — collection, manager, traits, currency, run history (schema: plan §4); `locale` — chosen language code, `""` = follow the device (l10n D11, read at boot in `ProfileManager._init`) |
| `user://run.save` | `SaveSystem` (this folder) | run start → run end | the in-progress run: `meta` + full `GameManager.season_state` |

There is **one run at a time**. The old 3-slot files (`user://saves/slot{0,1,2}.save`)
are ignored — no migration.

**Test run file** — `GameManager.use_test_run` defaults to `true`, so running
`Season.tscn` / `MatchFlow.tscn` directly from the editor still autosaves, but into
the hidden `user://run_test.save`. The lobby sets it to `false` in `_ready`, so a
normal boot (Lobby is `run/main_scene`) always uses `user://run.save`. The lobby
never shows the test run.

Auto-save fires at discrete points (no manual save UI):

1. **Post-run-start** — first HUB entry of a fresh run (`SeasonHub._is_run_start`).
2. **Pre-ban-pick** (Saturday) — MatchFlow `_on_prep_finished()`, right before BAN_PICK starts.
3. **Post-ban-pick** (Saturday) — MatchFlow `_store_picks_and_return()`: mech (메크) assignment is
   done, the picks go into `pending_match.picks`, `match_resume` is cleared, back to the season.
4. **Pre-match** (Sunday) — SeasonHub `on_week_day_match_start()`: `match_resume` = the stored picks
   (phase LAUNCH), then MatchFlow → BattleSim.
5. **Post-match** — SeasonHub `_ready()` after `_consume_pending_match_result`
   applies the result and clears `match_resume`.
6. **Weekly flow** — every step of the week (`SeasonHub.autosave(reason)`, public so the
   press / week screens call it): week start (training confirmed), each day-stage change
   (settlement → morning talk → afternoon → evening incident roll; the weekend's automatic afternoon /
   evening), a talk / interview / outing opened (record with `choice = -1`), every answer picked, the
   Sunday press answer, next day, end of week. See the table below.

No save fires while BattleSim is running — closing mid-battle resumes from
the Sunday pre-match snapshot and replays the battle (the jungle start screen shows again too).

**Run end** — `RunResult.settle_current_run(outcome)` (SeasonHub on ENDING / GAME_OVER
entry, the lobby on abandon) writes the profile (non-test runs), calls `SaveSystem.delete_run()`
and sets `season_state.run_over`, after which `SeasonHub._autosave` writes nothing.
→ `features/meta/run_result/README.md`
`EndingView` / `GameOverView` only offer `정산` → RunResult.tscn.

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
| `has_run()` | `bool` | file at `run_path()` exists, parses **and has `version == SAVE_VERSION`** |
| `read_run_meta()` | `Dictionary` | the `meta` block, `{}` when missing / corrupt / another version |
| `save_run()` | `String` | `""` on success; error when `season_state.active` is false |
| `load_run()` | `String` | overwrites `GameManager.season_state`; error for a missing / corrupt / other-version file |
| `delete_run()` | `String` | `""` also when there is no file |

## Run file schema (v2)

**Versioning (l10n D7).** `SAVE_VERSION` = **2**. v2 removed every display-string copy from
the run file — the save holds **ids and l10n keys only** and screens resolve text at draw
time (`Loc.t`, `docs/localization_design.md` §10.1). A file with any other `version` (v1 had
team / pilot names baked in) is **discarded, not migrated**: `_read_payload` returns `{}`, so
`has_run()` is false (the lobby shows no continue card — a new run is required) and
`load_run()` returns an error. The stale file stays on disk until the next run overwrites it.
`profile.save` is **not** affected (no version bump) — it never stored names (pilot ids,
trait ids, currency, `locale`).

What v2 changed vs v1:
| Where | v1 | v2 |
|---|---|---|
| `all_pilots[]` / `intl_pilots[]` | `name` (text) | `name_key` (`name.player.*` / `name.intl_player.*`) — `PlayerData.name` is a read-only getter |
| `team_meta[]` / `intl_team_meta[]` | `{id, name, short_name}` | `{id, name_key, short_name_key}` — show via `GameManager.team_name` / `team_short_name` |
| `run_setup.staff[]` | `name` | `name_key` (`name.staff.*`) — `StaffSystem.staff_name(e)` |
| `week_day_log[day][]` | `name` | dropped — `GameManager.pilot_name(pilot_id)` |
| `meta` | `team_name`, `scenario_name` | `team_id` (scenario stays the id `scenario`) |

```json
{
  "version": 2,
  "meta": {
    "phase": 0, "year": 1, "month": 12, "day": 1, "weekday": 0,
    "team_id": 0,
    "trophies": 0,
    "rank": 3, "wins": 5, "losses": 2,
    "saved_at": "2026-05-05 23:14",
    "match_in_progress": false,
    "scenario": 1
  },
  "season_state": { ...full GameManager.season_state, JSON-encoded... }
}
```

The `meta` block is denormalized info for the lobby's run card, computed
once at save time, so the lobby can render it without loading the full
season_state (and without instantiating LeagueManager).
`match_in_progress` is true when the run was saved with a `match_resume` (mid Saturday ban/pick, or
the Sunday launch / battle) — the lobby shows a "경기 진행 중" (Match in progress) chip and
routes "이어하기" (Continue) to MatchFlow.tscn instead of Season.tscn. Between the Saturday ban/pick
and the Sunday match it is false (the picks wait in `pending_match.picks`).
`team_id` is the player team (the lobby shows `GameManager.team_name(team_id)` — before a run
is loaded that falls back to the `teams.csv` package table). `scenario` comes from
`season_state.run_setup` (-1 for a run without one); a screen showing it resolves the name
from `RunRules.scenario(id).name_key`.

## Serialization notes
`season_state` is a Dictionary of mostly-primitive values plus a few
Resource-typed entries:
- `all_pilots` / `intl_pilots` are `Array[PlayerData]`. Persisted as plain
  Dicts via `_pilots_to_array` / `_array_to_pilots` — the name is saved as **`name_key`** only
  (v2). **`pilot_cards` (ids of the 3
  fixed pilot (파일럿) cards) is saved too.** Old saves without that key restore it as an empty
  array, and `GameManager.pilot_card_ids_for` fills it from the same player's DB row. `assigned_mech` is
  runtime-only (set in match flow) and is rebuilt on resume from
  `match_resume.{player,enemy}_assigned_mech_ids`, so it isn't persisted on
  the PlayerData rows themselves.
- `team_rosters`, `league_standings`, `phase_results` are all
  `Dictionary[int, X]`. JSON.stringify converts int keys to strings;
  `_int_keyed_dict_in` rebuilds the int keys on load. `team_rosters` goes through
  `_rosters_in`, which also casts the pilot ids back to int — a float id is not
  found by `roster.has(pilot_id)`.
- **Run keys (M1, written by `GameManager.start_run`)**:
  - `run_seed` — int, never 0 for a started run (0 = old save / no run). The AI
    roster distribution (`RunRoster`) is reproducible from it.
  - `run_setup` — `{scenario, team_id, pilot_ids: Array[int] (role order),
    pilot_levels: {"<pilot_id>": int}, salary_cap, salary_total}` (plan §10.2).
    `_run_setup_in` casts the ints back after JSON (ids, level values, scalars);
    `pilot_levels` keys stay strings. `{}` (old save) stays `{}`.
  - Each pilot row also carries `salary` (Lv1 base), `rarity` and `level`; the
    six stats are saved **with the level already applied**, so load does not
    re-apply it.
  - `run_stats` (string keys only) and `run_over` round-trip as-is.
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
  - `week_day_log` — `day(int) → Array[줄]` (`줄` = line), per-weekday training result log
    (`pilot_id` only — no name copy since v2).
    **Int keys**, so it goes through `_int_keyed_dict_in` — otherwise `log[3]` forever
    returns an empty array and the same weekday's training is applied twice.
  - `training_exp_carry` — `seat(int) → {stat: 남은 EXP}` (remaining EXP) remainder ledger.
    Both the outer keys and inner values become strings / floats after JSON, so
    `_exp_carry_in` casts both back to int — otherwise `total / EXP_PER_POINT` stops being
    integer division and the remainder silently disappears.
- `stress` (`{"<pid>": int}`, `features/season/mental/README.md` "Stress") round-trips as-is next to
  `trust` / `outings` / `mental` (string keys; readers wrap values in `int()`). It was missing from the
  save list at first, so a reload reset every pilot's stress to 0.
- `coach_points` (int) + `coach_week` (week key) — §15 D coach points of the running week
  (`features/season/staff/README.md`). Missing (old saves) → 0 / "" and `StaffSystem.coach_points` grants the
  week's points on the first read. The visit records (`visit` / `focus` / `story`) and `mental.last_match` live
  inside `mental` and round-trip with it.
- `awakening` · `awakening_pending` · `awakening_count` · `loadouts` (§15 C, `features/season/awakening/README.md`)
  round-trip as-is (string keys; numbers read back with `int()`). A run saved before them gets them lazily
  (base preset / empty queue) on first read.
- `training_level` (§15 B, `features/season/training/README.md` "Training level · limit break") round-trips
  as-is (string keys; `TrainingLevel` / `LimitBreak` read every number through `int()`). A run saved before
  §15 has none — `TrainingLevel.ensure` creates Lv1 entries on first read.
- `facilities` · `research` · `intel_rank` · `scout` (§16, `features/season/facility/README.md`) round-trip as-is
  (string keys). `load_run` then calls `FacilitySystem.migrate`: for a §16 save it only fills missing keys and
  turns the JSON floats back into ints (levels, points, done counts, boosts, ranks); for a run saved **before**
  §16 (no `facilities`) it builds the seven facilities at the old `finance.facility_level` (key dropped) and seats
  the run staff by job, as at run start (manager slots empty). Every `FacilitySystem` read also migrates lazily.
- `pending_match` round-trips as-is. Non-null from the Saturday "경기 준비" (`split: true`) through
  `_consume_pending_match_result` on Sunday. After the Saturday ban/pick it carries **`picks`** — the
  LAUNCH snapshot (shape of `match_resume` below) — with `match_resume` null; Sunday copies `picks`
  into `match_resume`. Numbers come back as floats after JSON (`_resume_at_launch` wraps them in
  `int()`). A `pending_match` without a result is dropped at week end.
- `schedule_format` — int, `CalendarSystem.SCHEDULE_FORMAT` (2 = one Sunday match per week). Missing
  in older files → read as 1 and `load_run` runs `CalendarSystem.migrate_weekly_format`
  (`features/season/calendar/README.md` "Old saves"); the next save writes 2.
- `current_tournament` rounds-trips as a plain dict.
- `match_resume` is the mid-match snapshot. Non-null from the Saturday pre-ban-pick save until the
  ban/pick ends, and from the Sunday pre-match save until the post-match save. Shape:
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
| 1 | First HUB entry after `start_run` | `SeasonHub._show_hub()` (`_is_run_start`) | null (cleared) |
| 2 | Pre-ban-pick (Saturday, before BAN_PICK starts) | `MatchFlow._on_prep_finished()` | `{phase: BAN_PICK, ...}` |
| 3 | Post-ban-pick (Saturday, mech assignment done) | `MatchFlow._store_picks_and_return()` | null — picks in `pending_match.picks` |
| 3b | Pre-match (`pre_match`, Sunday "경기 시작") | `SeasonHub.on_week_day_match_start()` | `{phase: LAUNCH, ...}` (= the picks) |
| 4 | Post-match (return from BattleSim, result applied) | `SeasonHub._ready()` | null (cleared by `_consume_pending_match_result`) |
| 5 | Press answer (`press_answer`, Sunday afternoon) | `PressConferenceView._on_answer_picked` | null |
| 6 | Week start (`week_start`, `week_day = 0`) | `SeasonHub.on_training_confirmed` | null |
| 7 | Training settled (`training_settled`) · talk opens (`morning_talk`) · afternoon (`afternoon`) · incident rolled (`incident`) | `WeekProgressView._settle_day` · `_finish_result_fx` · `_begin_afternoon` · `_begin_evening` · `_advance_weekend` | null (or the Saturday picks in `pending_match`) |
| 8 | Dialog opened (`talk_open` / `afternoon_open`) · answer picked (`choice`) | `WeekProgressView._on_talk_pressed` · `_on_afternoon_action` · `_on_overlay_choice` | null |
| 9 | Next day (`next_day`) · end of week (`post_week`) | `SeasonHub.on_week_day_confirmed` · `_end_week` | null |

Both `_autosave` helpers call `SaveSystem.save_run()` unconditionally — which file
it lands in is decided by `use_test_run` (above).

## Mid-match resume
Closing the game during the Saturday ban/pick (after save #2) or between the Sunday save #3b and
save #4 leaves `match_resume` non-null on disk. On `이어하기` (Continue) in the lobby:

- The lobby branches on `season_state.match_resume`. Non-null →
  `MatchFlow.tscn`. Null → `Season.tscn`.
- `MatchFlow._ready()` reads `season_state.match_resume`, clears it
  in-memory, and skips ahead:
  - `phase == BAN_PICK`: restore `player_side`, fall into the normal
    entry path (`pending_match.split` is still set, so the ban/pick ends by storing the picks and
    returning to the season).
  - `phase == LAUNCH`: rebuild `match_ctx` (rosters, assigned mechs,
    bans, jungle dir) from the resume payload, scene-change directly to
    BattleSim. No phase UI runs.
- Closing mid-battle leaves the disk save at #3b, so the next resume drops back into BattleSim with
  the same locked-in picks. Closing between the Saturday ban/pick and the Sunday match resumes in the
  season (Saturday afternoon / Sunday morning) with the picks intact in `pending_match.picks`.

## New-run vs continue flow (lobby)
- **새 런, no run**: `reset_season_state()` → RunSetup.tscn (`features/meta/run_setup/`) →
  `GameManager.start_run(run_setup)` → Season.tscn at HUB. First save fires on that first HUB entry.
- **새 런, run exists**: modal warning popup (`진행 중인 런을 포기할까요?`). Confirm →
  `SaveSystem.load_run()` → `RunResult.settle_current_run("abandon")` (fail settlement,
  deletes the run file) → RunResult.tscn → `새 런` → RunSetup.tscn. Unreadable run →
  `delete_run()` and a new run without settlement. Cancel / tapping the dim closes it.
- **이어하기**: `SaveSystem.load_run()` overwrites `season_state` (active=true) →
  MatchFlow.tscn if `match_resume != null`, else Season.tscn (skips `init_season()`).
  Season.tscn then picks the screen from the state (`SeasonHub._resume_screen`): **WEEK** when a week
  is running (`week_day >= 0` — the week screen reads its day stage, the Saturday picks, the Sunday
  press and any open dialog back from the records), else HUB (the week-start press conference is gone,
  so there is no TRAINING resume any more). A non-HUB entry runs the schedule / tournament
  bootstrap (`_ensure_schedule`) that `_show_hub` normally does. Old-format runs are migrated on load
  (`schedule_format`).

---

## Screen fit (safe area)
The lobby's safe-area handling (shift to safe top, background extended to the edge,
bottom action bar above the gesture zone) is described in `features/meta/lobby/README.md`.
Details: **`docs/mobile_safe_area.md`**
