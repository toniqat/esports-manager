# EsportsManager — Project Navigation Map

**Read this file first every session.** It is a map, not a spec:
1. find the folder(s) for the task in **Feature folders** below;
2. read that folder's `README.md` — and every parent / sibling README the row points to —
   **before touching code**;
3. after changing a folder, update its `README.md`. Detail lives in READMEs; this file only
   gets a one-line pointer when the structure changes (new folder, moved responsibility).

---

## Architecture

Godot 4.5-stable, GDScript · 2D mobile portrait 1080×1920 · main scene `res://scenes/Lobby.tscn`.

```
Lobby ──new run──▶ RunSetup ──start_run──▶ Season (SeasonHub) ◀──────────┐
  │  (tabs: 홈 · 컬렉션 · 감독 · 상점 · 패스)     │ week: HUB → TRAINING → WEEK         │
  └──continue─────────────────────────────▶   │ 토 ban/pick · 일 match ▼ → PRESS   │
                                               MatchFlow (PREP → BAN_PICK) ──▶ BattleSim
                                               run over ▶ RunResult ▶ Lobby     (result back)
```

| Layer | What | Where |
|---|---|---|
| Scenes | One `.tscn` per screen, each driven by one orchestrator script | `scenes/` → script in `features/*` |
| State | **Profile** (meta, `user://profile.save`, `ProfileManager`) · **run** (`GameManager.season_state`, `user://run.save`) · **match** (`GameManager.match_ctx`, handoff MatchFlow → BattleSim, never saved) | `autoloads/`, `features/save_load/` |
| Rules | Static `class_name` systems per feature (`*System.gd`, `RunRules`, …) — screens draw, systems decide | each feature folder |
| Data | `data/csv/*.csv` → `data/game.db` (SQLite) → `GameDb` / `ConstTable`; tuning numbers only in `const.csv` | `data/`, `resources/` |
| UI kit | Outgame = white theme via `OutgameTheme` + bottom action bar; screen coords via `ScreenMetrics`. BattleSim = the same white paper via `BattleTheme` (only plate-less text over the field keeps outlines) | `resources/`, `docs/mobile_safe_area.md` |

Campaign = 6 phases (`PRESEASON` … `REGULAR_INTL`, 36 weeks), one week at a time, days 월~금 training /
토 stadium + ban/pick / 일 stadium match + press (one player match a week); rules in `features/season/README.md` + `calendar/README.md`.

---

## Feature folders

Read the README of every row your task touches. Indented rows are submodules — also read the parent.

| Folder | Covers | README |
|---|---|---|
| `autoloads/` | `GameManager` (run / match state, `start_run`), `ProfileManager`, `Haptics` · `HapticUi`, `L10nKeyMode` (dev: Ctrl+Alt+K shows l10n aliases in game), game.db copy | `autoloads/README.md` |
| `resources/` | Shared data classes, `GameEnums`, `OutgameTheme` · `BattleTheme` (dark battle UI), `PositionBadge` (pilot position on every screen), `ScreenMetrics`, `DragScroll`, `UiHelpers`, `ConstTable`, `GameDb`, image lookups, shaders | `resources/README.md` |
| `data/` | CSV tables, SQLite API, **Rebuild game.db**, const table rules | `data/README.md` |
| ↳ `l10n/` | Localization source CSVs (`src/`), `config.json`, generated `strings_*.csv` · `L.gd` · `refs.json` — text is l10n keys, shown via `Loc.t()` | `data/l10n/README.md` |
| `features/save_load/` | Profile / run save, autosave points, mid-match resume, test run file | `features/save_load/README.md` |
| `features/meta/` | Outgame outside a run | `features/meta/README.md` |
| ↳ `lobby/` | Entry scene = tab host, confirm popup, manager type popup | `features/meta/lobby/README.md` |
| ↳ `run_setup/` | Scenario → team → manager preset → 5-pilot lineup (levels, salary cap), `DraftDetailPanel` | `features/meta/run_setup/README.md` |
| ↳ `run_result/` | Run settlement (`RunResult`), result screen, run balance sim | `features/meta/run_result/README.md` |
| ↳ `traits/` | Manager traits, bonus points, unlocks (`TraitSystem`) | `features/meta/traits/README.md` |
| ↳ `manager/` | Manager levels, specialisation, presets, prestige, 감독 tab | `features/meta/manager/README.md` |
| ↳ `collection/` | 컬렉션 tab: owned pilots, level · rank (★ stars, breakthrough = max rank), rank-up | `features/meta/collection/README.md` |
| ↳ `shop/` | 상점 / 패스 tabs: gacha, shards, crafting, `PassSystem` | `features/meta/shop/README.md` |
| `features/season/` | In-run campaign: `SeasonHub` orchestrator, `HubView`, pilot card · detail sheet (`SeasonPilotCard` · `SeasonPilotDetail`), handoffs, playoff / INTL brackets (`tournament/`) | `features/season/README.md` |
| ↳ `calendar/` | Week clock, weekdays / match days, phase transitions | `features/season/calendar/README.md` |
| ↳ `press/` | Press conference messenger screen | `features/season/press/README.md` |
| ↳ `training/` | Daily training tile board, owned courses (`TrainingCourses`: counts, I~IV upgrade lines), coach auto-arrange | `features/season/training/README.md` |
| ↳ `week/` | 시간 경과 screen (day rail, morning → talk → afternoon visit (`VisitMenu`) → evening, day cards; opens §15 awakening / limit-break events) | `features/season/week/README.md` |
| ↳ `week/base_map/` | Team base map widget (`BaseMap`) + one scene per map (art, spot markers), `teams.csv` `map_id` | `features/season/week/base_map/README.md` |
| ↳ `league/` | `LeagueManager`, standings view | `features/season/league/README.md` |
| ↳ `run_stats/` | Match MVP metric, phase POM | `features/season/run_stats/README.md` |
| ↳ `staff/` | Manager · staff stats, cover rule, hub manage cards (`HubSheet`) | `features/season/staff/README.md` |
| ↳ `mastery/` | Mech mastery, 메크 연구 card | `features/season/mastery/README.md` |
| ↳ `quirk/` | 기벽 — run-only pilot passives | `features/season/quirk/README.md` |
| ↳ `finance/` | Weekly budget, facilities, allocation, special spending | `features/season/finance/README.md` |
| ↳ `mental/` | Trust, stress (`StressSystem`), morning talk (훈련 소감 · 합동 훈련 pair), afternoon visit (방문: `FocusTraining` 집중 훈련 · 이야기 · 외출), evening incidents, choice preview, `PilotMods` — event data authored in `narrative/` (Draft) | `features/season/mental/README.md` |
| ↳ `awakening/` | 깨달음 gauge + event view (`AwakeningView`), run-only card presets (`PilotLoadout`, "+" upgraded cards), detail-sheet block; pre-match preset picker in `ban_pick/` | `features/season/awakening/README.md` |
| ↳ `facility/` | §16 seven facilities per team (levels, front cap, occupants = manager · staff seats → stat cover rule), research (`ResearchSystem` weekly gauge, HUB-only selection, kind handlers `research/*Research.gd`), facility screen `FacilityView` (hub map tap → `Screen.FACILITY`, occupant picker, kind bodies) | `features/season/facility/README.md` |
| `features/match_flow/` | PREP → BAN_PICK → BattleSim handoff (`match_ctx`), cheat menu | `features/match_flow/README.md` |
| ↳ `match_prep/` | Opponent intel / analysis tiers | `features/match_flow/match_prep/README.md` |
| ↳ `ban_pick/` | Ban / pick, mech assignment, `MechDetailPanel` | `features/match_flow/ban_pick/README.md` |
| `features/battle_sim/` | Battle simulation orchestrator, module table, sides, growth, economy gate, field size | `features/battle_sim/README.md` |
| ↳ `combat/` | Sim core, hex grid, pathfinding, lanes, turrets, recall, jungle, match stats | `features/battle_sim/combat/README.md` |
| ↳ `card_phase/` | Cards, hand layout / hit layer, drag & drop, targeting, deck rules, AI turn | `features/battle_sim/card_phase/README.md` |
| ↳ `engage/` | Round-based engage stage, VS intro, result screen | `features/battle_sim/engage/README.md` |
| ↳ `rendering/` | `BattleRenderer`, marker layout / glide, death / popup FX | `features/battle_sim/rendering/README.md` |
| ↳ `ui/` | HUD, pilot strips, detail panel, kill feed, timers, card piles | `features/battle_sim/ui/README.md` |
| ↳ `objective/` | Herald / Dragon objectives | `features/battle_sim/objective/README.md` |
| ↳ `skill/` · `mech/` | Pilot skills · mech passives | `features/battle_sim/skill/README.md`, `mech/README.md` |
| ↳ `trait/` | Manager in-game trait hooks | `features/battle_sim/trait/README.md` |
| ↳ `stress/` | In-match stress, awaken / panic test (rules in `season/mental/`) | `features/battle_sim/stress/README.md` |
| ↳ `gambit/` · `debug/` | Pre-battle setup, jungle start · `BattleLogger` | `gambit/README.md`, `debug/README.md` |
| ↳ `buildings/` · `data/` | `@tool` Building / Waypoint nodes · `DataLoader`, `FieldLoader` | *(no README — see `features/battle_sim/README.md`)* |
| `ios/plugins/` · `build/` | iOS native plugins · downloaded `.ipa` | `ios/plugins/README.md`, `build/README.md` |
| `narrative/` | **Draft project** (open in Draft, `D:/Projects/Draft`): source of every mental event text / rule — convention, kinds, speakers | `narrative/README.md` |
| `addons/draft_import/` | Draft runtime JSON (`data/draft/`) → `mental_events.csv` · `mental_texts.csv` · l10n `mental.<event>.<id>`; Project → Tools → **Draft: Import mental events** / headless `cli.gd` | `addons/draft_import/README.md` |
| `addons/l10n_tool/` | L10n tool: Project → Tools → L10n (build · validate · scan), **L10n editor = main screen `L10n` tab** (key sheet · glossary · orphan texts · scene preview · log), headless CLI · tests | `addons/l10n_tool/README.md` |
| `addons/ui_scene_tree/` | Editor dock "UI 트리": `scenes/*` · `UI_View` → `UI_Comp` tree (instanced + code-created), TODO · node counts per scene; headless `assign_uids_cli.gd` (uid for text-written `.tscn`) | `addons/ui_scene_tree/README.md` |
| `addons/godot_mcp/` | MCP editor plugin — **do not modify** | — |

### Docs (`docs/`)
| File | Read when |
|---|---|
| `outgame_dev_plan.md` | Outgame milestones and **parallel-work contracts** (§10 M1·M2, §11 M3~M7, §12 M8~M10, §13 task list, §14 §13 contract, §15 pilot growth rework, §16 facilities · research) |
| `mobile_safe_area.md` | Placing / moving any UI |
| `ios_testbuild.md` | iOS CI build, `.ipa` download |
| `run_balance.md` | Score / currency / EXP formula derivation (run sim) |
| `localization_design.md` | Any display text (new strings = keys first), l10n tool / data columns — **§0.5 decisions override body** |
| `ui_scene_migration.md` | Moving code-built UI to `.tscn` (WYSIWYG editing, `editor_description` TODO marks) — status, procedure, task list |

---

## Critical patterns (cross-cutting)

- **Autoloads have no `class_name`** — `get_node("/root/GameManager")` at runtime. `--check-only --script`
  doesn't know autoload identifiers (`Haptics`, `HapticUi`) — verify by running a scene.
- **BattleSim modules talk through the orchestrator** — `_bs.sim_core…`, `_bs.renderer…`, never sideways.
- **Enums** live in `resources/GameEnums.gd`; `GameEnums.ROLE_DISPLAY_ORDER` / `role_seat(role)`
  (탑 · 정글 · 미드 · 원딜 · 서폿) is the single pilot order on every screen.
- **Scene ↔ script by UID** — moving a script means updating its `.uid` and the `.tscn` `path=`.
- **Run state is JSON-round-tripped** — string keys only, wrap numeric reads in `int()` / `float()`.
- **Naming (lint-driven)**: `_foo` = used only inside its script; anything read from another script,
  `@export` vars, signal payloads = no underscore. Exceptions: `_bs`, `_on_*` handlers. Locals must not
  shadow `Node` / `Control` properties (`visible`, `position`, `name`, `owner`). Fix the cause — no `@warning_ignore`.
- **UI lives in `.tscn`** — outgame and the BattleSim HUD (rules — `docs/ui_scene_migration.md` §3):
  layout / style are owned by the scene; the script only binds `%UniqueName` nodes, fills data,
  connects signals; scenes are built with `Xxx.create()`, not `.new()`. **No local StyleBoxes in scenes** —
  a one-scene look is a `<Scene><Role>` theme variation derived from a shared one
  (`OutgameTheme._add_screen_variations`, `resources/README.md`). **A node missing from a scene
  was deleted on purpose — never re-create it in code** (drop its binding too). Empty nodes with
  `editor_description = "TODO: …"` mark work to implement at that spot / size
  (`grep -rn 'editor_description = "TODO' --include=*.tscn`). `_draw` widgets stay code, placed as nodes.
  Every scripted UI scene fills **dummy data when run alone (F6)** — `_ready` ends with
  `if UiPreview.is_standalone(self): _fill_preview()`; keep it working, add it to new scenes (`resources/README.md` → UiPreview).
  **Scene naming** (`docs/ui_scene_migration.md` §3 rules 9 ~ 11): UI scene files are `UI_View_<Name>.tscn` (screen / tab /
  popup / sheet / panel / HUD) or `UI_Comp_<Name>.tscn` (row / cell / chip / card placed inside others); the `.gd` keeps
  the bare name. A node instancing another scene is named `<SourceScene>_<Role>` (`BanPickPortrait_Pilot0`). Nodes whose
  `editor_description` starts with `[필수]` are bound without a null guard — removing / renaming them breaks the script.
- **Display text = l10n key** — code `Loc.t(L.X)`, scenes hold `tx_…` literals, data rows `Loc.t(row.xxx_key)`;
  `strict.orphans = error`, so a new Korean literal / scene text fails `build dev`. Shared words and helpers
  (`ui.*` · `term.*`, `GameEnums.phase_label` …) — `docs/localization_design.md` §0.7. Scene text the script
  overwrites → `auto_translate_mode = 2` on that node.
- **Dev setup per PC**: `.mcp.json` pins `godot-mcp` to `addons/godot_mcp/plugin.cfg`'s version (bump both);
  copy `.vscode/settings.example.json` → `settings.json` and set the local Godot path.

---

## Session checklist
1. Read this file → pick the folder rows → read those READMEs (parent + submodule).
2. Change code only inside the owning folder(s); update their README afterwards.
3. CSV tables / columns changed → **Project → Tools → Rebuild game.db** (`data/README.md`).
   New `.tscn` written as text → `godot --headless --path . -s res://addons/ui_scene_tree/assign_uids_cli.gd`
   (adds the header uid without opening the editor, `addons/ui_scene_tree/README.md`), then `--import`.
4. UI placed / moved → check `docs/mobile_safe_area.md` (the bottom gesture zone eats touches).
5. iOS CI build run → download the `.ipa` into `build/` (short SHA in the name), delete stale ones.
