# Lobby

Project entry point — `scenes/Lobby.tscn` (`run/main_scene`). White outgame
theme (`OutgameTheme`): floating top bar (manager level disc · wallet pills · settings disc), tab body, optional
action bar, **floating capsule nav** at the bottom. The home tab's `게임 시작` opens **scenario mode** in place
(`ScenarioSelectView` from `../run_setup/`, see *Scenario mode* below). Replaces the old 3-slot TitleScreen
(save structure is now profile 1 + run 1 — `features/save_load/README.md`).

표시 텍스트는 l10n key (`lobby` · `settings` 도메인 + 공유 `ui` · `term`). `TABS` `caption` values are keys
(`lobby.nav.*` — English upper-case in every locale: RECORD · PILOT · HOME · PASS · SHOP), `Loc.t` when drawn.
The level disc caption is `lobby.level.caption` ("Lv"). Scene nodes the scripts fill carry `auto_translate_mode = 2`
(preview text stays); fixed captions hold key literals. Old `lobby.tab.*` / `lobby.currency.{levelup,pilot_shard}`
are `deprecated`.

## Files
| File | Class | Purpose |
|---|---|---|
| `LobbyScreen.gd` | `class_name LobbyScreen extends Control` (root of `scenes/Lobby.tscn`) | **Tab host** (M8~M10): top bar (level disc → 감독 modal `ManagerPopup`, wallet pills → `CurrencyShopPopup`, settings disc → `SettingsPopup`), capsule nav + sliding selector, per-tab action bar, toast, confirm popup, manager type popup, scenario mode (`open_scenario_select`). **Layout lives in `scenes/Lobby.tscn`** |
| `UI_Comp_LobbyCurrencyPill.tscn` | — (no script, `Button` `LobbyCurrencyPill`) | One wallet pill: `%Icon` · `%Value` (right-aligned, `Loc.grouped` commas) · `%Plus` (accent "+" disc) — item scene, one per `WALLET` row; the whole pill opens the currency shop |
| `UI_Comp_LobbyNavButton.tscn` | — (no script, flat `Button`) | One cell of the capsule nav: `%Icon` (52, white SVG tinted by `self_modulate`) · `%Caption` (17, shown only when selected) · red `%Badge` — item scene, one per `TABS` row |
| `UI_View_HomeTab.tscn` + `.gd` | `class_name HomeTab extends Control` | 홈 tab — run card, 게임 시작 (→ scenario mode) / continue / abandon (the old lobby body). **Layout lives in the `.tscn`** |
| `UI_View_AbandonRunPopup.tscn` + `AbandonRunPopup.gd` | `class_name AbandonRunPopup extends CanvasLayer` | Run-abandon modal opened by the home tab's round X: dim + white card — title, the run summary (`SunkPanel` box: phase · date / team / trophies / record / saved at, lines from `HomeTab.run_texts`), warning body, `취소` / `포기하고 정산` (`DangerButton`, auto haptics muted — the caller plays ERROR). `create()`, `open(meta)`, `close()`, `is_open()`, signals `confirmed` / `cancelled`; fixed texts are key literals in the scene. F6 = hand-written meta. Host: `LobbyScreen.open_abandon_run(meta, cb)` |
| `UI_View_ConfirmPopup.tscn` + `.gd` | `class_name ConfirmPopup extends CanvasLayer` | Reusable modal confirm (dim + white card + cancel / confirm). **Layout lives in the `.tscn`**, style in `OutgameTheme.tres` variations — first scene-authored outgame UI |
| `UI_View_ManagerTypePopup.tscn` + `.gd` | `class_name ManagerTypePopup extends CanvasLayer` | First-lobby manager type pick (운영형 / 실전형), not dismissible (M3); prestige re-pick mode, dismissible (M9). **Layout lives in the `.tscn`** |
| `UI_View_SettingsPopup.tscn` + `SettingsPopup.gd` | `class_name SettingsPopup extends CanvasLayer` | Settings modal (l10n D10) — language list, one button per `L.LOCALES`. Opened from the lobby top bar's `%SettingsButton` (gear disc). **Layout lives in the `.tscn`** |
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

## Tab host (M8~M10) — `docs/outgame_dev_plan.md` §12.6
```
┌ top bar (%TopBar, no plate) — (Lv disc)             [coin 1,234][gem 56 (+)] (⚙) ┐
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
  lobby, `../manager/README.md`). Both modals (감독 · 재화) drop from the top edge and close with the shared floating
  close capsule bottom-right (`resources/UI_Comp_FloatingCloseButton.tscn`) — it sits where the nav capsule is, so
  `_fade_nav(false)` fades `%NavBar` out (hidden once faded) on open and `_on_modal_closed` fades it back. `%LevelBadge` = unseen unlocked traits (`refresh_badges`, `set_tab_badge("manager")`).
- **Level disc** (`refresh_level`, called by `refresh_currency`): `%LevelValue` = manager level, `%LevelRing`
  (`TextureProgressBar`, radial clockwise, 0..1) = EXP inside the level (`ManagerProgress.level_progress`; full at max).
- **Wallet** (`WALLET` = `outgame`, `premium` + `plus`): pills show `Loc.grouped(amount)`; icons from
  `CurrencyShopPopup.currency_icon(key)`. Any pill → `open_wallet()` → `CurrencyShopPopup` (`../shop/README.md`).
  Other currencies are no longer in the lobby header (shop / collection screens show them).
- Modal close (`closed`) → `_on_modal_closed`: nav fades back · `refresh_currency` · `refresh_badges` · current tab `on_shown`.
- **Tab rect** (`_place_tab`): anchors full rect, `offset_top` = `%TopBar`'s bottom, `offset_bottom` = top of
  `%ActionBar` (tab has a bar) or `%NavBar` (no bar) — read from the scene's offsets.
- Tab duck-typed contract: `bar_specs() -> Array` (fixed has-bar / no-bar per tab), `setup(host)`,
  `on_bar_pressed(i)`, `on_shown()` (every activation — redraw from the profile).
- Optional tab hook `bar_scale() -> Vector2` (only `HomeTab`: `(0.5, 1.1)`): `_lift_bar` sizes the capsules to
  x × the full row width (screen − side insets), **centred** (capsules keep `BOTTOM_BAR_GAP` and their weight ratio,
  never under their own minimum width), and makes each capsule y × the slot height, growing **upwards** from the slot
  bottom (the 16 px gap to the nav stays). `round` icon slots (`bar_round` meta) are circles (width = height) that
  **hang outside** the centred row — before the first capsule to its left, after the last to its right — so they
  never push the main capsule off centre. The shared
  `OutgameTheme.add_bottom_bar` / `layout_bottom_bar` are untouched.
- Host services: `show_toast(msg, is_error)`, `refresh_currency()` (wallet + level disc), `rebuild_bar()` /
  `relayout_bar()` / `bar_buttons()`, `switch_tab(id)`, `set_tab_badge(id, on)` / `refresh_badges()`,
  `open_confirm(title, body, cancel, confirm, danger, callback)`, `open_manager()`, `open_wallet()`,
  `open_settings()`, `open_scenario_select(animate)` / `close_scenario_select(animate)` / `is_scenario_open()`.
- **Settings disc** (`%SettingsButton`, top bar, right of the wallet): → `open_settings()` (one `SettingsPopup`,
  lazy child) → `locale_chosen(code)` → `_on_locale_chosen`: `ProfileManager.set_locale(code)` (saves) →
  `get_tree().reload_current_scene()` — the only way texts refresh after a language switch (§10.4: no
  `NOTIFICATION_TRANSLATION_CHANGED` handling). Save error → red toast `settings.save_failed`.
- **Bottom-bar exception**: only the lobby puts the nav at the very bottom; the action bar
  (`OutgameTheme.add_bottom_bar` specs, weights, primary on the right — shared code, built per tab) is
  placed in the `%ActionBar` slot right above the capsule (`_lift_bar`: y 0 in the slot, slot height). The slots
  are the shared floating capsules (40 px side insets, 16 px gaps, orange primary / dark secondary).

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
│ ├ %Wallet        HBox sep 12, right-anchored (108 px = disc 72 + gap 12 + margin 24), y 36..100, grows left
│ │                → LobbyCurrencyPill_Outgame (300×64, Row right margin 22) · _Premium (252×64; preview: gem + plus)
│ └ %SettingsButton Button `LobbyCurrencyPill` (same black pill look → a circle at 72×72), right-anchored
│                  (24 px margin), y 32..104 (centred on the pills) → `Icon` TextureRect 44×44 `icon_settings.svg`
└ %SafeBottom      Control, full rect (bottom offset = device inset, code)
  ├ %ActionBar     Control slot, bottom-anchored, y −272..−176 (96 tall = one bottom capsule, 16 px above the nav capsule)
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
  `currency_gem` (coloured), `icon_plus`, `icon_close`, `icon_settings` (white stroked gear, 64 px, stroke 5),
  `ring_track` (112 px ring for the level disc).

## Scenario mode (`open_scenario_select`)
The new-run entry: the home tab's `게임 시작` **without a run** (and the corrupt-run abandon path) calls
`open_scenario_select(true)`; `LobbyScreen.open_scenario_on_enter = true` before loading the lobby (RunSetup's first
step 뒤로, RunResult 새 런) makes `_ready` switch to 홈 and open it with `animate = false` (the chrome snaps; the view
may still animate its own panel).
- **Chrome slide** (`_slide_chrome` → `_apply_chrome(t)`, `CHROME_SLIDE_SEC` 0.38 s, cubic in-out): `%Wallet` moves up
  until its bottom is `CHROME_SLIDE_MARGIN` above the notch; `%NavBar` and `%ActionBar` move down until their top is
  that margin under the screen bottom. Driven by offsets from `_chrome_base` (the scene's offsets, captured in
  `_build`; `_place_tab` / `_lift_bar` read the base, never the slid value). Hidden at `t = 1` (no taps). The level
  disc and the settings disc stay — both work in scenario mode.
- **View**: `ScenarioSelectView.create()` once, child of the lobby moved to just **below `%TopBar`** (above `%Tabs`;
  `%SafeBottom` / toast / modals stay above it), full rect, `open(selected, animate)` — `selected` = the view's
  last `selected_id`, first time `RunSetupScreen.entry_scenario` (if ≥ 0) else 0. The view owns its bottom bar
  (뒤로 / 시나리오 선택) and its enter / exit animation.
- `back_requested` → `close_scenario_select()` → `view.close(true)`; the chrome slides back only on the view's
  `closed` (`_on_scenario_closed`, after its close wipe has fully finished — never in parallel; skipped if the mode
  was re-opened meanwhile). `close_scenario_select(false)` → the view closes at once and the chrome snaps back.
- The view's black wipe is its own last child, so it stays **under `%TopBar`**: the level / settings discs remain
  visible over the black.
- `scenario_chosen(id)` → `GameManager.reset_season_state()`, `RunSetupScreen.entry_scenario = id`,
  `RunSetup.tscn`.
- **Modals in scenario mode**: `open_manager` doesn't fade the nav and `_on_modal_closed` doesn't fade it back while
  `_scenario_open` — the nav stays slid away until 뒤로.

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
- Bottom bar (`bar_specs`, font 35, `bar_scale()` = half width · 1.1× height, centred): one 500 px capsule in the
  centre — `이어하기` (with a run) or `게임 시작` (key `lobby.home.start`, without). With a run a dark **round X**
  slot (= new game, `icon_close.svg`, `round: true`) hangs left of it. `lobby.home.new_run` (새 런) stays for `RunResult`.
- `이어하기` → `load_run()` → `MatchFlow.tscn` if `season_state.match_resume != null`,
  else `Season.tscn`. Error → red toast above the bar + ERROR haptic.
- `게임 시작` without a run → host `open_scenario_select(true)` (scenario mode; the pick resets the season → `RunSetup.tscn`).
- Round X (with a run) → WARNING haptic + `AbandonRunPopup` (host `open_abandon_run(_meta, …)`: "진행 중인 런을
  포기할까요?", the run summary, body: settled as a failure, score / currency rewards still paid, irreversible;
  danger confirm "포기하고 정산"). The run-card lines come from `HomeTab.run_texts(meta, gm)` (static, shared with the popup). Confirm (`_on_abandon_confirmed`) → `SaveSystem.load_run()` →
  `RunResult.settle_current_run("abandon")` (writes the profile, deletes `run.save`) →
  `RunResult.SCENE_PATH`, whose `새 런` goes on to `RunSetup.tscn` (`../run_result/README.md`).
  Load fails (corrupt run) → warning, `delete_run()`, the tab redraws as run-less and scenario mode opens (no settlement).
- A summary line under the title: manager level · owned pilots · owned traits.

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
the action bar slot. The modals (`ManagerPopup`, `CurrencyShopPopup`) extend their dim and their top sheet under the notch (content
indented by the notch height) and lift the floating close capsule by the inset themselves.
