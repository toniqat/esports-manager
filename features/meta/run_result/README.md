# Run result (M2)

Run-end settlement and its screen. Contract: `docs/outgame_dev_plan.md` §10.3
(result shape), §10.4 (`run_stats` it reads), §4 (profile schema it writes).

## Files
| File | Class | Purpose |
|---|---|---|
| `RunResult.gd` | `class_name RunResult extends RefCounted` (static) | Settles the current run: score, rewards, achievements → profile, deletes the run file |
| `RunResultScreen.gd` | `extends Control` (scene `scenes/RunResult.tscn`) | Draws `GameManager.last_run_result` |
| `sim/RunSim.gd` + `sim/RunSim.tscn` | `extends Node` (dev tool, headless) | Run simulator for balancing the score / currency / EXP constants — see "Run simulator" below |

## RunResult.settle_current_run(outcome) -> Dictionary
`outcome` = `"clear"` | `"fail"` | `"abandon"` (`OUTCOME_*` consts). Callers: SeasonHub on
ENDING / GAME_OVER entry, the lobby on abandon. `SCENE_PATH` is the screen to open afterwards.

Order:
1. Guard — `season_state.run_over == true` → returns `last_run_result` unchanged (one settlement per run).
2. `run_over = true` first (so `SeasonHub._autosave` can't revive `run.save`), then
   `RunStats.finalize_phase(state, current_phase)`.
3. `build_result(state, outcome, use_test_run)` — pure, touches nothing.
4. Not a test run → `ProfileManager.apply_run_result(result)`. Always → `SaveSystem.delete_run()`
   (`run_path()` points at `run_test.save` for test runs, so only that file goes).
5. `GameManager.last_run_result = result`.

Autoloads are fetched via `Engine.get_main_loop().root` (static class, no `@onready`).

### Fields
- `phase_reached` = index of `current_phase` in `CAMPAIGN_ORDER` (0-based);
  `phases_cleared` = phases **finished** — `phase_reached` for fail / abandon (the current
  phase is the one the run ended in, so it doesn't count), `phase_reached + 1` for clear.
- `wins` / `losses` — `player_record(state)`: `run_stats.wins/losses` when either key exists,
  else `derive_record(state)`: played player matches in `match_schedule` (all phases accumulate),
  played player matches in the live `current_tournament.bracket`, and for **past** tournaments
  (brackets are cleared on phase change) only the won ones, counted as `PLAYOFF_ROUNDS` /
  `INTL_ROUNDS` wins (bracket shape, not tuning). Lost past tournaments are unknown → not counted (lower bound).
- `titles` — `phase_results` entries whose `champion` or `intl_champion` is the player team.
- `score` = `phases_cleared·RUN_SCORE_PER_PHASE + wins·RUN_SCORE_PER_WIN +
  titles·RUN_SCORE_PER_TITLE + (clear ? RUN_SCORE_CLEAR_BONUS : 0) + bonus_points·phases_cleared·RUN_SCORE_PER_BONUS` (M8 trait bonus points, per cleared phase).
  `breakdown` holds each term.
- `currency.outgame` = floor(score · `RUN_CURRENCY_PER_SCORE`), `manager_exp` =
  floor(score · `RUN_MGR_EXP_PER_SCORE`) (tiny epsilon guards float error).
- **My pilots only** (`run_setup.pilot_ids`, fallback: player team roster):
  `mvp` = per-pilot sum over `run_stats.mvp_count` phases; `pom` = `run_stats.pom_by_phase`
  entries whose pilot is mine; `achievements` = `{pid: {mvp, pom}}` for all 5.
- Extra display keys beyond §10.3: `id` (unique per settlement — the profile's idempotency key),
  `phases_cleared`, `breakdown`, `team_name`, `scenario_name`, `pilots` (`[{id, name, role}]`
  in `GameEnums.role_seat` order) — the screen draws without `season_state`.
- `true_endings` (M7) — **only on a clear**: `MentalSystem.true_ending_pilots(state)` (my pilots
  with outings ≥ `TRUE_ENDING_OUTINGS`). Absent on fail / abandon. `ProfileManager.apply_run_result`
  sets `achievements[pid].true_ending = true` for each.

## RunResultScreen
White outgame theme, pattern B of `docs/mobile_safe_area.md` (`indent_to_safe_top` + `add_background`).
- Header: 런 클리어 (amber) / 런 실패 (red) / 런 포기 (grey), scenario · team, and a
  "테스트 런 — 프로필 미반영" chip when `test_run`.
- Scroll body (`OutgameTheme.add_vscroll`, ends at `bottom_bar_top()`): when `true_endings` is
  non-empty a **진엔딩** card leads (amber-tinted; per pilot a large amber-ringed portrait, name,
  a closing line and an `외출 N회 · 약속을 지켰다` chip — N from `TRUE_ENDING_OUTINGS`), then cards 진척 (phase reached,
  W-L, titles) · 점수 (breakdown + total) · 보상 · 선수 성장 · 이번 런 업적
  (round portrait `PilotImages.circle_for`, name, role, MVP / POM chips — lit when > 0).
- M8~M10 rewards (contract §12.5) — level changes come only from `result.profile_delta`
  (`ProfileManager.apply_run_result`); a test run has none, so it shows computed values only:
  - **새 특성 해금** card (amber, right after 진엔딩): ids from `profile_delta.traits`, or for a
    test run `unlocked_traits` (with a "not granted" note). Per trait: +/− chip, name,
    `TraitSystem.desc_of`, rarity chip coloured per rarity (`TraitUi.add_rarity_chip` — the card
    stays amber, the chip no longer is).
  - 점수: `특성 보너스 × <bonus_points>` row = `breakdown.bonus`.
  - 보상: `currency.outgame` · `currency.levelup` · `pass_exp` (+ `Lv a → b` from `profile_delta.pass`,
    plus a row for `overflow_outgame` when > 0) · `manager_exp` (+ `Lv a → b` from
    `profile_delta.manager`, then a `새 제거 포인트` row = level gain × `MANAGER_REMOVE_PER_LEVEL`).
    Level-ups are amber text.
  - **선수 성장**: per pilot `pilot_exp` and an amber `최대 Lv a → b` chip from `profile_delta.pilots`.
- Bottom bar, one full-width primary button: `로비로` → `Lobby.tscn`; when `outcome == "abandon"`
  `새 런` → `RunSetup.tscn`. Both call `reset_season_state()` first.
- `last_run_result` empty (scene opened directly) → empty-state card + `로비로`.
- SUCCESS haptic on open for a clear.

## Run simulator (`sim/`, T2 — balancing tool, not shipped gameplay)
Plays N whole runs headlessly through the real season code and prints the
distributions of phase reached, wins, titles, score and every reward; the
reverse-solved constants, measured tables and targets live in
**`docs/run_balance.md`** (numbers stay there and in `const.csv`, not here).

Run (PowerShell 5.1, from the repo root):
```
& "D:\Projects\Godot Project\godot.exe" --headless --path . res://features/meta/run_result/sim/RunSim.tscn -- --runs=200 --edge=1.5 "--out=$env:TEMP\t2_runs.csv"
```
Args (after `--`): `--runs`, `--edge` (player win-odds multiplier), `--seed`,
`--level` (my five's level), `--team` / `--scenario` (fixed, else random per run),
`--no-coach`, `--out` (per-run CSV of raw counts). Filter the console with
`Select-String "=== RunSim" -Context 0,40` — the hub views log image-load noise headlessly.

How a run is driven:
- Setup = random team / scenario, one random starter (`players.starter`) per role at
  `--level`, test run (`use_test_run`, no traits). `GameManager.start_run` as usual.
- `season_state.run_over` is set **right after** `start_run`: every `SeasonHub._autosave`
  is skipped and `RunResult.settle_current_run` (profile write, run-file delete) never runs —
  the sim calls `RunStats.finalize_phase` + `RunResult.build_result(state, outcome, true)`
  itself. **user:// is never written** (profile, `run.save`, `run_test.save` untouched).
- A live `Season.tscn` is added under the sim node; each week: coach board
  (`TrainingBoard.auto_arrange`, skip with `--no-coach`), `apply_day_training` Mon–Fri,
  on Sat / Sun the player match (if any) then `_resolve_ai_for_matchday`, then
  `SeasonHub._end_week` (finance / mastery / mental week close, calendar tick, playoff /
  INTL bootstrap). The run ends when the hub's run-end handlers fire (`_run_end_screen`).
- **Player match outcome** = the AI quick-sim coin (`InternationalTournament.team_avg_stat`
  ratio) with the player's side × `--edge`; the result goes through
  `SeasonHub._consume_pending_match_result` (RunStats, finance, bracket signals) with
  zeroed stat rows like `MatchFlow._cheat_finish`, MVP = random pilot of the winning side.
- Not simulated: press answers, mental incidents / evening sessions, finance / staff
  choices, manager traits / bonus points, match mastery (no mech assignment).
