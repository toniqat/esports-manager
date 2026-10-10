# Lobby

Project entry point — `scenes/Lobby.tscn` (`run/main_scene`). White outgame
theme (`OutgameTheme`): floating top bar (manager level disc · wallet pills), tab body, optional
action bar, **floating capsule nav** at the bottom. Replaces the old 3-slot TitleScreen
(save structure is now profile 1 + run 1 — `features/save_load/README.md`).

표시 텍스트는 l10n key (`lobby` · `settings` 도메인 + 공유 `ui` · `term`). `TABS` `caption` values are keys
(`lobby.nav.*` — English upper-case in every locale: RECORD · PILOT · HOME · PASS · SHOP), `Loc.t` when drawn.
The level disc caption is `lobby.level.caption` ("Lv"). Scene nodes the scripts fill carry `auto_translate_mode = 2`
(preview text stays); fixed captions hold key literals. Old `lobby.tab.*` / `lobby.currency.{levelup,pilot_shard}`
are `deprecated`.

## Files
| File | Class | Purpose |
|---|---|---|
| `LobbyScreen.gd` | `class_name LobbyScreen extends Control` (root of `scenes/Lobby.tscn`) | **Tab host** (M8~M10): top bar (level disc → 감독 modal `ManagerPopup`, wallet pills → `CurrencyShopPopup`), capsule nav + sliding selector, per-tab action bar, toast, confirm popup, manager type popup. **Layout lives in `scenes/Lobby.tscn`** |
| `UI_Comp_LobbyCurrencyPill.tscn` | — (no script, `Button` `LobbyCurrencyPill`) | One wallet pill: `%Icon` · `%Value` (right-aligned, `Loc.grouped` commas) · `%Plus` (accent "+" disc) — item scene, one per `WALLET` row; the whole pill opens the currency shop |
| `UI_Comp_LobbyNavButton.tscn` | — (no script, flat `Button`) | One cell of the capsule nav: `%Icon` (52, white SVG tinted by `self_modulate`) · `%Caption` (17, shown only when selected) · red `%Badge` — item scene, one per `TABS` row |
| `UI_View_HomeTab.tscn` + `.gd` | `class_name HomeTab extends Control` | 홈 tab — run card, continue / new run / abandon (the old lobby body). **Layout lives in the `.tscn`** |
| `UI_View_ConfirmPopup.tscn` + `.gd` | `class_name ConfirmPopup extends CanvasLayer` | Reusable modal confirm (dim + white card + cancel / confirm). **Layout lives in the `.tscn`**, style in `OutgameTheme.tres` variations — first scene-authored outgame UI |
| `UI_View_ManagerTypePopup.tscn` + `.gd` | `class_name ManagerTypePopup extends CanvasLayer` | First-lobby manager type pick (운영형 / 실전형), not dismissible (M3); prestige re-pick mode, dismissible (M9). **Layout lives in the `.tscn`** |
| `UI_View_SettingsPopup.tscn` + `SettingsPopup.gd` | `class_name SettingsPopup extends CanvasLayer` | Settings modal (l10n D10) — language list, one button per `L.LOCALES`. Opened from the 홈 tab's `%SettingsButton`. **Layout lives in the `.tscn`** |
| `UI_Comp_SettingsLanguageButton.tscn` | — (no script, `Button`) | One language row of `SettingsPopup` (`SelectableCardButton` / `…On`, 112 high) — item scene, one per locale |
| `UI_Comp_ManagerTypeOption.tscn` + `.gd` | `class_name ManagerTypeOption extends PanelContainer` | One option card of `ManagerTypePopup` (name, `현재` chip, desc, six stat cells) — item scene instantiated per type. Name / desc = `Loc.t` of the row's `name_key` / `desc_key` (`manager.type.*`); F6 preview uses type 0's keys |

## F6 preview (standalone run)
Every scripted scene here except `LobbyScreen` (the `scenes/Lobby.tscn` root) shows dummy data when run on its own (editor "Run Current Scene") — `_ready` →
`UiPreview.is_standalone(self)` → `_fill_preview()` at the bottom of each script
(`resources/UiPreview.gd`). Nothing is saved: buttons that would save the profile are re-wired
to only print (`UiPreview.mute`).
- `HomeTab` — in-memory run (`ensure_run` + 3 league weeks), run card with rank / record / 경기 진행 중
  chip; the run file is neither read nor written. No action bar (host-owned).
- `ConfirmPopup` — the danger variant (런 포기). `ManagerTypePopup` — prestige mode, real
  `manager_types.csv`, "현재" chip on the last type, first option selected.
- `ManagerTypeOption` — hand-written 운영형 card, selected + "현재".
- `SettingsPopup` — opened with the real `L.LOCALES`; picking / closing only prints (no save, no reload).
  `HomeTab`'s settings button works in its preview too; a pick there only prints.

## Tab host (M8~M10) — `docs/outgame_dev_plan.md` §12.6
```
┌ top bar (%TopBar, no plate) — (Lv disc)                 [coin 1,234][gem 56 (+)] ┐
│ tab body (current tab's Control)                                                │
├ action bar (only when the tab's bar_specs() is non-empty)                       ┤
└   ( RECORD · PILOT · HOME · PASS · SHOP )  floating capsule nav, icons only      ┘
```
- `TABS` is the one table (left → right: `record` (locked) · `collection` · `home` · `pass` · `shop`, each with
  `caption` key + `icon` file in `resources/images/ui/lobby/`). `_make_tab(id)` builds each tab with its `create()`
  (`HomeTab` / `CollectionTab` / `ShopTab` / `PassTab` — all scene-based) lazily on first open, adds it under `%Tabs`,
  then hides / shows. The lobby opens on `home` (the centre cell).
- **Locked cell** (`locked: true` — 기록): icon at `NAV_ICON_LOCKED`, button disabled + `MOUSE_FILTER_IGNORE` — no
  reaction at all (no haptic, selector stays). `switch_tab` also refuses it.
- **Selector** (`%NavSelector`, white pill under the cells): `_move_selector(animate)` puts it on the current cell's
  rect (`%NavButtons.position + button.position`, button size) — tweened `SELECTOR_SEC` (cubic ease-out) on a tab
  switch, snapped on every `%NavButtons.sort_children` (first layout, resize). `_paint_nav` tweens each icon's
  `self_modulate` (selected = `NAV_ICON_ON` dark on the white pill, else `NAV_ICON_OFF`) and shows only the selected
  cell's `%Caption`.
- **감독 = modal, not a tab**: `%LevelButton` (top-left disc) → `open_manager()` → `ManagerPopup` (lazy, child of the
  lobby, `../manager/README.md`). `%LevelBadge` = unseen unlocked traits (`refresh_badges`, `set_tab_badge("manager")`).
- **Level disc** (`refresh_level`, called by `refresh_currency`): `%LevelValue` = manager level, `%LevelRing`
  (`TextureProgressBar`, radial clockwise, 0..1) = EXP inside the level (`ManagerProgress.level_progress`; full at max).
- **Wallet** (`WALLET` = `outgame`, `premium` + `plus`): pills show `Loc.grouped(amount)`; icons from
  `CurrencyShopPopup.currency_icon(key)`. Any pill → `open_wallet()` → `CurrencyShopPopup` (`../shop/README.md`).
  Other currencies are no longer in the lobby header (shop / collection screens show them).
- Modal close (`closed`) → `_on_modal_closed`: `refresh_currency` · `refresh_badges` · current tab `on_shown`.
- **Tab rect** (`_place_tab`): anchors full rect, `offset_top` = `%TopBar`'s bottom, `offset_bottom` = top of
  `%ActionBar` (tab has a bar) or `%NavBar` (no bar) — read from the scene's offsets.
- Tab duck-typed contract: `bar_specs() -> Array` (fixed has-bar / no-bar per tab), `setup(host)`,
  `on_bar_pressed(i)`, `on_shown()` (every activation — redraw from the profile).
- Host services: `show_toast(msg, is_error)`, `refresh_currency()` (wallet + level disc), `rebuild_bar()` /
  `relayout_bar()` / `bar_buttons()`, `switch_tab(id)`, `set_tab_badge(id, on)` / `refresh_badges()`,
  `open_confirm(title, body, cancel, confirm, danger, callback)`, `open_manager()`, `open_wallet()`.
- **Bottom-bar exception**: only the lobby puts the nav at the very bottom; the action bar
  (`OutgameTheme.add_bottom_bar` specs, weights, primary on the right — shared code, built per tab) is
  placed in the `%ActionBar` slot right above the capsule (`_lift_bar`: y 0 in the slot, slot height, bottom inset
  padding removed **before** the height is set — otherwise the inset margin's minimum height clamps the
  button taller and it overhangs the nav).

### Scene (`scenes/Lobby.tscn`) — layout / style source of truth
```
Lobby (Control, full rect, theme = OutgameTheme.tres, LobbyScreen.gd)
├ %Background      Panel ScreenBackground, full rect
├ %Tabs            Control, full rect — tab bodies are added here (below everything else)
├ %TopBar          Control, top-wide, 136 high, no plate
│ ├ %LevelButton   flat Button 112×112 at (24, 12)
│ │ ├ Disc         Panel `LobbyLevelDisc` (RAIL circle)
│ │ ├ %LevelRing   TextureProgressBar, fill_mode clockwise, under / progress = `ring_track.svg`
│ │ │              (tint_under white 16 %, tint_progress ACCENT)
│ │ ├ LevelCaption `RailLabel` 18 "Lv" (y 22..44) · %LevelValue `OnFillLabel` 40 (y 40..90)
│ │ └ %LevelBadge  ColorRect 16×16, top-right, hidden
│ └ %Wallet        HBox sep 12, right-anchored (24 px margin), y 36..100, grows left
│                  → LobbyCurrencyPill_Outgame · _Premium (300×64; preview: gem + plus)
└ %SafeBottom      Control, full rect (bottom offset = device inset, code)
  ├ %ActionBar     Control slot, bottom-anchored, y −304..−176 (16 px above the capsule)
  ├ %NavBar        Control, bottom-anchored, 40 px side margins, y −160..−32 (128 high)
  │ ├ NavBack      Panel `LobbyNavCapsule` (RAIL pill + shadow)
  │ ├ %NavSelector Panel `LobbyNavSelector` (white pill) — preview on the HOME cell
  │ └ %NavButtons  HBox (10 px inset, sep 0) → 5 LobbyNavButton instances (Record · Pilot · Home · Pass · Shop)
  └ %Toast         Panel `LobbyToast`, z 5, 20 px above the action bar slot (also over the modals)
    └ %ToastText   OnFillLabel 26, centred, clipped
```
- **Code-owned**: `indent_to_safe_top(self)` + `_fit_safe_area` (`%Background` extended under the notch,
  `%SafeBottom.offset_bottom = -inset`); item counts / texts / icons from `TABS` · `WALLET` (`_sync_items` reuses the
  scene's preview instances, instantiates or frees the rest); selector position; nav icon / caption colours; badge
  visibility; level disc values; the action bar buttons; the error toast colour (the scene's toast style duplicated
  and recoloured `NEGATIVE`).
- Lobby-only looks are screen variations (`resources/README.md` → Screen variations): `LobbyNavCapsule`,
  `LobbyNavSelector`, `LobbyLevelDisc`, `LobbyCurrencyPill` (Button, black 50 % / pressed 62 % pill),
  `LobbyCurrencyPlus` (ACCENT disc), `LobbyToast`; badges / ring tints are node colours.
- Icons: `resources/images/ui/lobby/*.svg` — white single-colour nav icons (`nav_*`), `currency_coin` /
  `currency_gem` (coloured), `icon_plus`, `icon_close`, `ring_track` (112 px ring for the level disc).

## HomeTab (was LobbyScreen body)
- **Layout lives in `UI_View_HomeTab.tscn`**; created with `HomeTab.create()` (`.new()` is an empty Control).
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
- **`%SettingsButton`** (`GhostButton`, 150×60, font 24, key `settings.title`, the popup's own title) — anchored top-right of the
  tab, 32 px from the right edge, y 12..72 (inside the top gap, beside the centred title). The tab already starts
  below the top bar, which the host indents under the notch, so no extra safe-area code. Pressed →
  `_open_settings` (creates one `SettingsPopup` lazily as a child) → `locale_chosen(code)` →
  `_on_locale_chosen`: `ProfileManager.set_locale(code)` (saves) → `get_tree().reload_current_scene()` —
  the only way texts refresh after a language switch (§10.4: no `NOTIFICATION_TRANSLATION_CHANGED` handling).
  Save error → red toast `settings.save_failed`.

## SettingsPopup (l10n M5 — `docs/localization_design.md` D10 · §10.4)
`SettingsPopup.create()` → `open()` / `close()` / `is_open()`; signals `locale_chosen(code)` (a locale other
than the current one was tapped — the popup hides itself, the opener saves + reloads) and `closed`
(dim / `닫기` / re-tapping the current language).
- **The `.tscn` is the source of truth for layout and style.** Tree: CanvasLayer 20 → `Root` (full rect,
  **`theme = OutgameTheme.tres`**) → `%Dim` (flat Button, closes) · `DimRect` (`DimPanel`) · `%SafeArea`
  (CenterContainer) → `Card` (`PopupCard`, 920 wide) → `VBox` → `Title` (`TitleLabel`) · Gap · `LanguageHeader`
  (`CaptionLabel` 24) · Gap · `%Languages` (VBox sep 16; two preview `SettingsLanguageButton_Lang0/1`
  instances) · Gap · `Note` (`FaintLabel`, autowrap) · Gap · `%Close` (`GhostButton`, 112 high).
- Static texts are **key literals in the scene** (`tx_…` — Control auto-translate, inherited/on); keys live in
  `data/l10n/src/settings.csv` (`settings.*`); `%Close` uses the shared `ui.button.close`.
- Code-owned: the language buttons (`_sync_languages` reuses the scene's previews / instantiates
  `UI_Comp_SettingsLanguageButton.tscn` / frees to match `L.LOCALES`); each button's text =
  `Loc.t(LOCALE_NAMES[code])` — **language names are endonyms** (`settings.locale.ko` = "한국어",
  `settings.locale.en` = "English" in every locale; adding a locale = one `settings.locale.<code>` key +
  one `LOCALE_NAMES` row); the current locale (`TranslationServer.get_locale()`) gets `SelectableCardButtonOn`,
  others `SelectableCardButton`; `%SafeArea` offsets = `ScreenMetrics.top_y()` / `bottom_y()` on every `open()`
  (pattern C of `docs/mobile_safe_area.md`, same frame as `ConfirmPopup`).

## ConfirmPopup
`ConfirmPopup.create()` (instantiates `UI_View_ConfirmPopup.tscn` — `ConfirmPopup.new()` is an empty layer),
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
- Creation: `ManagerTypePopup.create()` (instantiates `UI_View_ManagerTypePopup.tscn` — `.new()` is an empty layer),
  then `open(prestige_mode, current_type)` / `close()` / `is_open()` / `cancel()`; signals `chosen(type_id)` /
  `cancelled`. Open / close toggles the layer's `visible`; nodes are reused (the 감독 tab keeps one instance).
- **The `.tscn` is the source of truth for layout and style.** Tree: CanvasLayer 20 → `Root` (full rect,
  **`theme = OutgameTheme.tres`**) → `%Dim` (flat Button) · `DimRect` (`DimPanel`) · `%SafeArea`
  (plain Control, full rect) → `%Center` (CenterContainer, full rect, offsets 40 / −40 = the margin the card
  keeps from the safe edges) → `%Card` (`PopupCard`, 920 wide, STOP) → `VBox` → `%Title` (`TitleLabel`) · `Gap1` ·
  `%Sub` (`CaptionLabel`, autowrap, min 66) · `%Note` (`AccentLabel`) · `Gap2` · `%Scroll` (ScrollContainer,
  horizontal off, + `DragScroll`) → `%Body` (VBox) → `%Options` (VBox, sep 20; two preview
  `ManagerTypeOption` instances) · `Gap3` · `Buttons` (`%Cancel` `GhostButton` : `%Confirm`
  `PrimaryButton` + font size 30 override = stretch 1 : 2).
- **Tall content scrolls, the frame doesn't** (`_fit_body`): the card is centred in `%Center` while it fits;
  `%Scroll`'s min height = the option list's height, capped at `%Center`'s height (from its anchors / offsets)
  minus everything else on the card. Past the cap only the option list scrolls — title, texts and buttons stay
  fixed, the confirm button stays above the gesture zone. Re-fit on every `open()` and whenever `%Card`'s minimum
  size changes (wrapped labels settle after the first layout pass) — one deferred refit per frame. When the
  scroll bar shows, the card widens by its width (the options' min width already fills the card). A release that
  ended a scroll drag is not a pick (`_on_option_tapped` checks `DragScroll.moved`). Normal data never reaches
  the cap — pixel-identical to the old `CenterContainer` frame.
- `UI_Comp_ManagerTypeOption.tscn` (item scene, min 824 × 268, root variation `SelectableCard`): `Margin` (28 / 20 / 28) → `VBox` → `Header`
  (`%Name` `BodyLabel` 32 + `%Chip` 90 × 36, centred) · `Gap1` · `%Desc` (`CaptionLabel` 21, autowrap, min 60) ·
  `Gap2` · `StatsMargin` (4 / 4) → `%Stats` (HBox sep 8, min 104) → `Stat0..5` (`SunkPanel`, key
  `CaptionLabel` 20 + value `TitleLabel`). API: `fill(row, is_current)`, `set_selected(on)`, signal `tapped`
  (left release anywhere on the card — all children are mouse-ignore).
- Code-owned: texts; the option instances (`_sync_options` reuses the scene's previews, instantiates or frees
  to match `manager_types()`); the **selection** (`set_selected` switches the root variation
  `SelectableCard` ↔ `SelectableCardOn` — both padding 0, the scene's `Margin` pads, so the border width never
  shifts content); the `현재` chip pill (`SURFACE_SUNK`, no variation — `OutgameTheme.flat_style`); `%Cancel.visible` = prestige mode; `%Confirm` disabled / text;
  `%SafeArea` offsets = `ScreenMetrics.top_y()` / `bottom_y()` on every `open()`; `%Scroll` min height
  (`_fit_body`); `%Dim` haptics muted in
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
whole screen below the notch; `%Background` gets `extend_background` (covers the notch band); everything at the
bottom hangs from `%SafeBottom` (bottom offset = inset) so the action bar, the floating nav and the toast stay
above the gesture zone (the capsule floats — nothing extends down to the screen edge). The toast sits 20 px above
the action bar slot. The modals (`ManagerPopup`, `CurrencyShopPopup`) extend their dim under the notch and lift
their bottom buttons / card by the inset themselves.
