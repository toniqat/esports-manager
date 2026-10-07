# Lobby

Project entry point — `scenes/Lobby.tscn` (`run/main_scene`). White outgame
theme (`OutgameTheme`), bottom action bar. Replaces the old 3-slot TitleScreen
(save structure is now profile 1 + run 1 — `features/save_load/README.md`).

## Files
| File | Class | Purpose |
|---|---|---|
| `LobbyScreen.gd` | `class_name LobbyScreen extends Control` (scene root) | **Tab host** (M8~M10): currency strip, tab bar, per-tab action bar, toast, confirm popup, manager type popup |
| `HomeTab.gd` | `class_name HomeTab extends Control` | 홈 tab — run card, continue / new run / abandon (the old lobby body) |
| `ConfirmPopup.tscn` + `.gd` | `class_name ConfirmPopup extends CanvasLayer` | Reusable modal confirm (dim + white card + cancel / confirm). **Layout lives in the `.tscn`** — first scene-authored outgame UI |
| `ManagerTypePopup.gd` | `class_name ManagerTypePopup extends CanvasLayer` | First-lobby manager type pick (운영형 / 실전형), not dismissible (M3); prestige re-pick mode, dismissible (M9) |

## Tab host (M8~M10) — `docs/outgame_dev_plan.md` §12.6
```
┌ currency strip (CURRENCY_H) — outgame · levelup · tickets · shards ┐
│ tab body (current tab's Control)                                   │
├ action bar (only when the tab's bar_specs() is non-empty)          ┤
└ tab bar (홈 · 컬렉션 · 감독 · 상점 · 패스), extends into the bottom inset ┘
```
- `TABS` is the one table; `_make_tab(id)` builds `HomeTab` / `CollectionTab` / `ManagerTab` /
  `ShopTab` / `PassTab` lazily on first open, then hides / shows.
- Tab duck-typed contract: `bar_specs() -> Array` (fixed has-bar / no-bar per tab), `setup(host)`,
  `on_bar_pressed(i)`, `on_shown()` (every activation — redraw from the profile).
- Host services: `show_toast(msg, is_error)`, `refresh_currency()`, `rebuild_bar()` / `relayout_bar()` /
  `bar_buttons()`, `switch_tab(id)`, `set_tab_badge(id, on)` / `refresh_badges()` (감독 = unseen
  unlocked traits), `open_confirm(title, body, cancel, confirm, danger, callback)`.
- **Bottom-bar exception**: only the lobby puts the tab bar at the very bottom; the action bar
  (`OutgameTheme.add_bottom_bar` specs, weights, primary on the right) is lifted on top of it
  (`action_bar_top()`), its bottom inset padding removed.
- Static layout helpers: `tab_bar_top()`, `action_bar_top()`, `content_rect(has_bar)`.

## HomeTab (was LobbyScreen body)
- The host's `_ready` sets **`GameManager.use_test_run = false`** first — runs entered through the
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
- A summary line under the title: manager level · owned pilots · owned traits.

## ConfirmPopup
`ConfirmPopup.create()` (instantiates `ConfirmPopup.tscn` — `ConfirmPopup.new()` is an empty layer),
`open(title, body, cancel_text, confirm_text, danger)`, `close()`, `is_open()`;
signals `confirmed` / `cancelled`. Opening / closing toggles the layer's `visible`; nodes are reused.
- **The `.tscn` is the source of truth for layout and style** (sizes, colours, gaps, fonts). The script
  only binds `%Title` · `%Body` · `%Cancel` · `%Confirm` · `%Dim` and never builds nodes — edit the look
  in the editor, not in code.
- Tree: CanvasLayer 20 → `Root` (full rect) → `%Dim` (flat Button, cancels on tap) · `DimRect`
  (`DIM_COLOR`) · `%SafeArea` (CenterContainer) → `Card` (PanelContainer, 920 wide, padding 48,
  STOP so taps don't close) → `VBox` → `%Title` · `Gap1` · `%Body` (autowrap, min 150 high — grows
  with longer text) · `Gap2` · `Buttons` (`%Cancel` ghost : `%Confirm` primary = stretch 1 : 2).
- Code-owned: `%SafeArea` offsets = `ScreenMetrics.top_y()` / `bottom_y()` on every `open()` (card stays
  above the gesture zone); `danger=true` overrides confirm normal / hover / pressed with
  `NEGATIVE` copies (scene styleboxes are shared between instances — never mutate them) and mutes
  its auto haptics (the caller plays ERROR).
- Styleboxes are copies of `OutgameTheme` ghost / primary / card values embedded in the scene;
  if the palette changes, update them here too.

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
- **Prestige mode (M9)** — `open(true, current_type)`, opened by the `감독` tab
  (`../manager/README.md`) after its prestige confirm. Title "프레스티지 — 감독 유형 재선택", the current
  type carries a `현재` chip, confirm reads "<이름> 감독으로 프레스티지". It **is dismissible**: a tap on
  the dim or the ghost `취소` (1 : 2 with confirm) calls `cancel()` → `cancelled` signal, nothing changes.
  First-lobby mode (`open()`) is unchanged.

## Safe area
Pattern B of `docs/mobile_safe_area.md`: `ScreenMetrics.indent_to_safe_top(self)` +
`OutgameTheme.add_background` (extends under the notch). Toast sits at
`OutgameTheme.bottom_bar_top() - 64`, above the bar and the gesture zone.
