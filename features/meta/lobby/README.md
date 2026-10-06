# Lobby

Project entry point — `scenes/Lobby.tscn` (`run/main_scene`). White outgame
theme (`OutgameTheme`), bottom action bar. Replaces the old 3-slot TitleScreen
(save structure is now profile 1 + run 1 — `features/save_load/README.md`).

## Files
| File | Class | Purpose |
|---|---|---|
| `LobbyScreen.gd` | `extends Control` (scene only) | Builds the lobby, routes continue / new run |
| `ConfirmPopup.gd` | `class_name ConfirmPopup extends CanvasLayer` | Reusable modal confirm (dim + white card + cancel / confirm) |
| `ManagerTypePopup.gd` | `class_name ManagerTypePopup extends CanvasLayer` | First-lobby manager type pick (운영형 / 실전형), not dismissible (M3) |

## LobbyScreen
- `_ready` sets **`GameManager.use_test_run = false`** first — runs entered through the
  lobby save to `user://run.save`; direct editor runs of Season / MatchFlow keep `true`
  and save to the hidden `user://run_test.save`.
- Run exists (`SaveSystem.has_run()`) → run card from `SaveSystem.read_run_meta()`:
  phase name (`HubView.PHASE_NAMES`), "경기 진행 중" chip when `match_in_progress`,
  date + weekday (`OutgameTheme.DAY_LETTERS`), team, trophies, league rank W-L
  (or "리그 미시작"), last saved time. No run → empty-state card.
- Bottom bar: with a run `새 런`(ghost, 1) / `이어하기`(primary, 2); without, `새 런` full width.
- `이어하기` → `load_run()` → `MatchFlow.tscn` if `season_state.match_resume != null`,
  else `Season.tscn`. Error → red toast above the bar + ERROR haptic.
- `새 런` without a run → `reset_season_state()` → `RunSetup.tscn`.
- `새 런` with a run → WARNING haptic + `ConfirmPopup` ("진행 중인 런을 포기할까요?",
  danger style; body: settled as a failure, score / currency rewards still paid, irreversible;
  confirm "포기하고 정산"). Confirm (`_on_abandon_confirmed`) → `SaveSystem.load_run()` →
  `RunResult.settle_current_run("abandon")` (writes the profile, deletes `run.save`) →
  `RunResult.SCENE_PATH`, whose `새 런` goes on to `RunSetup.tscn` (`../run_result/README.md`).
  Load fails (corrupt run) → warning, `delete_run()` and straight to a new run without settlement.
- Later milestones add menu entries (컬렉션 / 감독 / 특성 / 상점) below the run card.

## ConfirmPopup
`open(title, body, cancel_text, confirm_text, danger)`, `close()`, `is_open()`;
signals `confirmed` / `cancelled`.
- CanvasLayer 20; full-viewport flat Button as the dim (`DIM_COLOR`, style from
  `meta/run_setup/DraftDetailPanel.gd`) — blocks input behind and cancels on tap.
- White card 920 wide, centred between `ScreenMetrics.top_y()` and `bottom_y()` so the
  buttons stay above the gesture zone; card is `MOUSE_FILTER_STOP` so taps on it don't close it.
- Buttons ghost cancel / primary confirm at 1:2; `danger=true` paints confirm `NEGATIVE` red.
- Body area is a fixed 150px (~4 lines) — a wrapped Label measures 0 before it enters the tree.

## ManagerTypePopup (M3)
Plan `docs/outgame_dev_plan.md` §11.0: the manager type is chosen **once, on the first lobby of a
profile**; changing it later is only via prestige (M9).
- `LobbyScreen._build` opens it when `ProfileManager.manager_type_chosen()` is false (on top of the
  normal lobby, after the bottom bar and `ConfirmPopup` are built).
- Options = `StaffSystem.manager_types()` (`manager_types.csv`): name, `desc`, and the six stats
  (`StaffSystem.STATS` order, labels `STAT_LABELS`, 1..20) as one row of six cells.
- **Cannot be dismissed without choosing**: the dim is a STOP `Control` that swallows taps (no
  close), there is no cancel button, and the full-width primary confirm starts disabled
  ("유형을 고르세요") until an option is tapped (then "<이름> 감독으로 시작"). A one-line accent
  note says later changes need prestige.
- Confirm emits `chosen(type_id)`; the lobby saves it with `ProfileManager.set_manager_type(id)`
  (`_on_manager_type_chosen`). A save error shows the red toast + ERROR haptic.
- `select(idx)` is public (tap path + headless checks). Selected option = `ACCENT_DIM` fill with an
  `ACCENT` border.
- Layout: CanvasLayer 20, pattern C (dim = viewport, card centred between `ScreenMetrics.top_y()`
  and `bottom_y()`), card 920 wide like `ConfirmPopup`. The run uses the type through
  `GameManager.start_run` → `StaffSystem.snapshot_for_run`.

## Safe area
Pattern B of `docs/mobile_safe_area.md`: `ScreenMetrics.indent_to_safe_top(self)` +
`OutgameTheme.add_background` (extends under the notch). Toast sits at
`OutgameTheme.bottom_bar_top() - 64`, above the bar and the gesture zone.
