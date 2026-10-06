# Run result (M2)

Run-end settlement and its screen. Contract: `docs/outgame_dev_plan.md` §10.3
(result shape), §10.4 (`run_stats` it reads), §4 (profile schema it writes).

## Files
| File | Class | Purpose |
|---|---|---|
| `RunResult.gd` | `class_name RunResult extends RefCounted` (static) | Settles the current run: score, rewards, achievements → profile, deletes the run file |
| `RunResultScreen.gd` | `extends Control` (scene `scenes/RunResult.tscn`) | Draws `GameManager.last_run_result` |

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
  `phase_reached_count` = that + 1 (phases entered, incl. the current one).
- `wins` / `losses` — `player_record(state)`: `run_stats.wins/losses` when either key exists,
  else `derive_record(state)`: played player matches in `match_schedule` (all phases accumulate),
  played player matches in the live `current_tournament.bracket`, and for **past** tournaments
  (brackets are cleared on phase change) only the won ones, counted as `PLAYOFF_ROUNDS` /
  `INTL_ROUNDS` wins (bracket shape, not tuning). Lost past tournaments are unknown → not counted (lower bound).
- `titles` — `phase_results` entries whose `champion` or `intl_champion` is the player team.
- `score` = `phase_reached_count·RUN_SCORE_PER_PHASE + wins·RUN_SCORE_PER_WIN +
  titles·RUN_SCORE_PER_TITLE + (clear ? RUN_SCORE_CLEAR_BONUS : 0) + bonus_points` (bonus 0 until M8).
  `breakdown` holds each term.
- `currency.outgame` = floor(score · `RUN_CURRENCY_PER_SCORE`), `manager_exp` =
  floor(score · `RUN_MGR_EXP_PER_SCORE`) (tiny epsilon guards float error).
- **My pilots only** (`run_setup.pilot_ids`, fallback: player team roster):
  `mvp` = per-pilot sum over `run_stats.mvp_count` phases; `pom` = `run_stats.pom_by_phase`
  entries whose pilot is mine; `achievements` = `{pid: {mvp, pom}}` for all 5.
- Extra display keys beyond §10.3: `id` (unique per settlement — the profile's idempotency key),
  `phase_reached_count`, `breakdown`, `team_name`, `scenario_name`, `pilots` (`[{id, name, role}]`
  in `GameEnums.role_seat` order) — the screen draws without `season_state`.

## RunResultScreen
White outgame theme, pattern B of `docs/mobile_safe_area.md` (`indent_to_safe_top` + `add_background`).
- Header: 런 클리어 (amber) / 런 실패 (red) / 런 포기 (grey), scenario · team, and a
  "테스트 런 — 프로필 미반영" chip when `test_run`.
- Scroll body (`OutgameTheme.add_vscroll`, ends at `bottom_bar_top()`): cards 진척 (phase reached,
  W-L, titles) · 점수 (breakdown + total) · 보상 (outgame currency, manager EXP) · 이번 런 업적
  (round portrait `PilotImages.circle_for`, name, role, MVP / POM chips — lit when > 0).
- Bottom bar, one full-width primary button: `로비로` → `Lobby.tscn`; when `outcome == "abandon"`
  `새 런` → `RunSetup.tscn`. Both call `reset_season_state()` first.
- `last_run_result` empty (scene opened directly) → empty-state card + `로비로`.
- SUCCESS haptic on open for a clear.
