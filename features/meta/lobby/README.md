# Lobby

Project entry point — `scenes/Lobby.tscn` (`run/main_scene`). White outgame
theme (`OutgameTheme`), bottom action bar. Replaces the old 3-slot TitleScreen
(save structure is now profile 1 + run 1 — `features/save_load/README.md`).

## Files
| File | Class | Purpose |
|---|---|---|
| `LobbyScreen.gd` | `class_name LobbyScreen extends Control` (root of `scenes/Lobby.tscn`) | **Tab host** (M8~M10): currency strip, tab bar, per-tab action bar, toast, confirm popup, manager type popup. **Layout lives in `scenes/Lobby.tscn`** |
| `LobbyCurrencyCell.tscn` | — (no script, `VBoxContainer`) | One cell of the currency strip (`%Caption` · `%Value`) — item scene, one per `CURRENCY_STRIP` row |
| `LobbyTabButton.tscn` | — (no script, flat `Button`) | One tab of the tab bar + its red `%Badge` dot — item scene, one per `TABS` row |
| `HomeTab.tscn` + `.gd` | `class_name HomeTab extends Control` | 홈 tab — run card, continue / new run / abandon (the old lobby body). **Layout lives in the `.tscn`** |
| `ConfirmPopup.tscn` + `.gd` | `class_name ConfirmPopup extends CanvasLayer` | Reusable modal confirm (dim + white card + cancel / confirm). **Layout lives in the `.tscn`**, style in `OutgameTheme.tres` variations — first scene-authored outgame UI |
| `ManagerTypePopup.tscn` + `.gd` | `class_name ManagerTypePopup extends CanvasLayer` | First-lobby manager type pick (운영형 / 실전형), not dismissible (M3); prestige re-pick mode, dismissible (M9). **Layout lives in the `.tscn`** |
| `ManagerTypeOption.tscn` + `.gd` | `class_name ManagerTypeOption extends PanelContainer` | One option card of `ManagerTypePopup` (name, `현재` chip, desc, six stat cells) — item scene instantiated per type |

## Tab host (M8~M10) — `docs/outgame_dev_plan.md` §12.6
```
┌ currency strip (%CurrencyStrip) — outgame · levelup · tickets · shards ┐
│ tab body (current tab's Control)                                   │
├ action bar (only when the tab's bar_specs() is non-empty)          ┤
└ tab bar (홈 · 컬렉션 · 감독 · 상점 · 패스), extends into the bottom inset ┘
```
- `TABS` is the one table; `_make_tab(id)` builds each tab with its `create()` (`HomeTab` / `CollectionTab` /
  `ManagerTab` / `ShopTab` / `PassTab` — all scene-based) lazily on first open, adds it under `%Tabs`, then hides / shows.
- **Tab rect** (`_place_tab`): anchors full rect, `offset_top` = `%CurrencyStrip`'s height, `offset_bottom` =
  top of `%ActionBar` (tab has a bar) or `%TabBar` (no bar) — read from the scene's offsets, so resizing a
  bar in the editor moves the tab bodies with it. Set before `setup(host)`, so tabs can read `size` there.
- Tab duck-typed contract: `bar_specs() -> Array` (fixed has-bar / no-bar per tab), `setup(host)`,
  `on_bar_pressed(i)`, `on_shown()` (every activation — redraw from the profile).
- Host services: `show_toast(msg, is_error)`, `refresh_currency()`, `rebuild_bar()` / `relayout_bar()` /
  `bar_buttons()`, `switch_tab(id)`, `set_tab_badge(id, on)` / `refresh_badges()` (감독 = unseen
  unlocked traits), `open_confirm(title, body, cancel, confirm, danger, callback)`.
- **Bottom-bar exception**: only the lobby puts the tab bar at the very bottom; the action bar
  (`OutgameTheme.add_bottom_bar` specs, weights, primary on the right — shared code, built per tab) is
  placed in the `%ActionBar` slot on top of it (`_lift_bar`: y 0 in the slot, slot height, bottom inset
  padding removed **before** the height is set — otherwise the inset margin's minimum height clamps the
  button taller and it overhangs the tab bar).
- (The old static helpers `tab_bar_top()` / `action_bar_top()` / `content_rect()` and `CURRENCY_H` /
  `TAB_BAR_H` are gone — the scene owns those sizes.)

### Scene (`scenes/Lobby.tscn`) — layout / style source of truth
```
Lobby (Control, full rect, theme = OutgameTheme.tres, LobbyScreen.gd)
├ %Background      ColorRect BG, full rect
├ %Tabs            Control, full rect — tab bodies are added here (below everything else)
├ %CurrencyStrip   Control, top-wide, 96 high
│ ├ %StripBack     Panel (local SURFACE style)
│ ├ %CurrencyCells HBox (16 px side margins, sep 0) → 5 preview LobbyCurrencyCell instances
│ │                (Gap 12 · %Caption CaptionLabel 18 · Gap 2 · %Value BodyLabel 30)
│ └ StripDivider   HSeparator `Divider`, bottom 1 px
└ %SafeBottom      Control, full rect (bottom offset = device inset, code)
  ├ %ActionBar     Control slot, bottom-anchored, 128 high, right above the tab bar
  ├ %TabBar        Control, bottom-anchored, 128 high
  │ ├ %TabBarBack  Panel (local SURFACE style) — extends down into the inset (code)
  │ ├ TopLine      ColorRect BORDER_STRONG, 1 px
  │ └ %TabButtons  HBox sep 0 → 5 preview LobbyTabButton instances (flat, font 28, %Badge 14×14 hidden)
  └ %Toast         Panel (local RAIL pill, radius 34), z 5, 20 px above the action bar slot
    └ %ToastText   OnFillLabel 26, centred, clipped
```
- **Code-owned**: `indent_to_safe_top(self)` + `_fit_safe_area` (`%Background` / `%StripBack` extended under the
  notch, `%SafeBottom.offset_bottom = -inset`, `%TabBarBack.offset_bottom = +inset`); item counts / texts from
  `TABS` · `CURRENCY_STRIP` (`_sync_items` reuses the scene's preview instances, instantiates or frees the
  rest); selected-tab font colours; badge visibility; the action bar buttons; the error toast colour (the
  scene's toast style duplicated and recoloured `NEGATIVE`).
- Lobby-only looks are screen variations (`resources/README.md` → Screen variations): `LobbySurfaceBar`
  (flat `SURFACE`, square — strip and tab bar), `LobbyToast` (flat `RAIL` pill, radius 34); `TopLine` /
  badge / background are `ColorRect` colours.

## HomeTab (was LobbyScreen body)
- **Layout lives in `HomeTab.tscn`**; created with `HomeTab.create()` (`.new()` is an empty Control).
  Tree: `HomeTab` (full rect, theme) → `VBox` (top-wide, sep 0): Gap 64 · `Title` (`HeadingLabel` 64) · Gap ·
  `Rule` (80×6 `ACCENT` ColorRect) · Gap · `%Summary` (`CaptionLabel`) · Gap · `Section` "진행 중인 런" (920 wide) ·
  Gap · `%RunCard` / `%EmptyCard` (920 wide `Panel` with the `PopupCard` variation — radius 24; Panel so the
  variation's padding is ignored and a `MarginContainer` 44/40/44/42 sets it).
  `%RunCard` → `Header` (`%Phase` `TitleLabel` + `%LiveChip` "경기 진행 중" — margin box → `Chip` `AccentChip` PanelContainer 170×40, centred `AccentLabel` 20) · `%Date` ·
  `Divider` · `%Team` · `%Trophies` (`AccentLabel`) · `%Record` · spacer · `%SavedAt` (right). Gaps are spacer
  Controls sized so every line sits on its old pixel row.
- Code-owned: texts, which card is visible, `%LiveChip.visible` (`_fill` / `_show_run(meta)`).
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
- Tree: CanvasLayer 20 → `Root` (full rect, **`theme = OutgameTheme.tres`**) → `%Dim` (flat Button,
  cancels on tap) · `DimRect` (Panel, `DimPanel`) · `%SafeArea` (CenterContainer) → `Card`
  (PanelContainer, `PopupCard`, 920 wide, STOP so taps don't close) → `VBox` → `%Title` (`TitleLabel`) ·
  `Gap1` · `%Body` (`SubLabel`, autowrap, min 150 high — grows with longer text) · `Gap2` · `Buttons`
  (`%Cancel` `GhostButton` : `%Confirm` `PrimaryButton` with a font size override = stretch 1 : 2).
- Code-owned: `%SafeArea` offsets = `ScreenMetrics.top_y()` / `bottom_y()` on every `open()` (card stays
  above the gesture zone); `danger=true` swaps `%Confirm`'s `theme_type_variation` to `DangerButton`
  (back to `PrimaryButton` otherwise — theme styleboxes are shared, never mutate them) and mutes
  its auto haptics (the caller plays ERROR).
- **No embedded styles**: every colour / stylebox comes from the theme variations
  (`resources/README.md` → *OutgameTheme.tres*). Palette changes go to `OutgameTheme.gd` + regenerate.

## ManagerTypePopup (M3)
Plan `docs/outgame_dev_plan.md` §11.0: the manager type is chosen **once, on the first lobby of a
profile**; changing it later is only via prestige (M9).
- `LobbyScreen._build` opens it when `ProfileManager.manager_type_chosen()` is false (on top of the
  normal lobby, after the bottom bar and `ConfirmPopup` are built).
- Options = `StaffSystem.manager_types()` (`manager_types.csv`): name, `desc`, and the six stats
  (`StaffSystem.STATS` order, labels `STAT_LABELS`, 1..20) as one row of six cells.
- **Cannot be dismissed without choosing**: the dim swallows taps (no close), there is no cancel button, and the full-width primary confirm starts disabled
  ("유형을 고르세요") until an option is tapped (then "<이름> 감독으로 시작"). A one-line accent
  note says later changes need prestige.
- Confirm emits `chosen(type_id)`; the lobby saves it with `ProfileManager.set_manager_type(id)`
  (`_on_manager_type_chosen`). A save error shows the red toast + ERROR haptic.
- `select(idx)` is public (tap path + headless checks). Selected option = variation `SelectableCardOn`
  (`ACCENT_DIM` fill, 4px `ACCENT` border), others `SelectableCard` (white, 2px `BORDER`), radius 18.
- Creation: `ManagerTypePopup.create()` (instantiates `ManagerTypePopup.tscn` — `.new()` is an empty layer),
  then `open(prestige_mode, current_type)` / `close()` / `is_open()` / `cancel()`; signals `chosen(type_id)` /
  `cancelled`. Open / close toggles the layer's `visible`; nodes are reused (the 감독 tab keeps one instance).
- **The `.tscn` is the source of truth for layout and style.** Tree: CanvasLayer 20 → `Root` (full rect,
  **`theme = OutgameTheme.tres`**) → `%Dim` (flat Button) · `DimRect` (`DimPanel`) · `%SafeArea`
  (CenterContainer) → `Card` (`PopupCard`, 920 wide, STOP) → `VBox` → `%Title` (`TitleLabel`) · `Gap1` ·
  `%Sub` (`CaptionLabel`, autowrap, min 66) · `%Note` (`AccentLabel`) · `Gap2` · `%Options` (VBox, sep 20;
  two preview `ManagerTypeOption` instances) · `Gap3` · `Buttons` (`%Cancel` `GhostButton` : `%Confirm`
  `PrimaryButton` + font size 30 override = stretch 1 : 2).
- `ManagerTypeOption.tscn` (item scene, min 824 × 268, root variation `SelectableCard`): `Margin` (28 / 20 / 28) → `VBox` → `Header`
  (`%Name` `BodyLabel` 32 + `%Chip` 90 × 36, centred) · `Gap1` · `%Desc` (`CaptionLabel` 21, autowrap, min 60) ·
  `Gap2` · `StatsMargin` (4 / 4) → `%Stats` (HBox sep 8, min 104) → `Stat0..5` (`SunkPanel`, key
  `CaptionLabel` 20 + value `TitleLabel`). API: `fill(row, is_current)`, `set_selected(on)`, signal `tapped`
  (left release anywhere on the card — all children are mouse-ignore).
- Code-owned: texts; the option instances (`_sync_options` reuses the scene's previews, instantiates or frees
  to match `manager_types()`); the **selection** (`set_selected` switches the root variation
  `SelectableCard` ↔ `SelectableCardOn` — both padding 0, the scene's `Margin` pads, so the border width never
  shifts content); the `현재` chip pill (`SURFACE_SUNK`, no variation — `OutgameTheme.flat_style`); `%Cancel.visible` = prestige mode; `%Confirm` disabled / text;
  `%SafeArea` offsets = `ScreenMetrics.top_y()` / `bottom_y()` on every `open()`; `%Dim` haptics muted in
  first-lobby mode (the tap does nothing there) and restored in prestige mode.
- Not dismissible in first-lobby mode: `%Dim` swallows taps (its `pressed` → `cancel()`, a no-op outside
  prestige mode), `%Cancel` is hidden.
- The card is centred in the safe area; with many more types than today's two it would overflow both ends
  (the old code pinned it to the top) — wrap `%Options` in a scroll if the table ever grows.
- Pattern C of `docs/mobile_safe_area.md` (dim = viewport, card centred in the safe area), same frame as
  `ConfirmPopup`. The run uses the type through `GameManager.start_run` → `StaffSystem.snapshot_for_run`.
- **Prestige mode (M9)** — `open(true, current_type)`, opened by the `감독` tab
  (`../manager/README.md`) after its prestige confirm. Title "프레스티지 — 감독 유형 재선택", the current
  type carries a `현재` chip, confirm reads "<이름> 감독으로 프레스티지". It **is dismissible**: a tap on
  the dim or the ghost `취소` (1 : 2 with confirm) calls `cancel()` → `cancelled` signal, nothing changes.
  First-lobby mode (`open()`) is unchanged.

## Safe area
Pattern B of `docs/mobile_safe_area.md`, scene version: `ScreenMetrics.indent_to_safe_top(self)` moves the
whole screen below the notch; `%Background` and `%StripBack` get `extend_background` (cover the notch band);
everything at the bottom hangs from `%SafeBottom` (bottom offset = inset) so the action bar, tab bar and
toast stay above the gesture zone, while `%TabBarBack` extends back down to the screen edge. The toast
sits 20 px above the action bar slot.
