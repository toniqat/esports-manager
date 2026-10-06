# EsportsManager — Project Navigation Map

## Workflow Instructions
**Read this file first every session.** It is a map only: find the feature
folder for the task, then read that folder's `README.md` (and the submodule's
README for battle_sim / season / match_flow) before touching any code.
Detail lives in the READMEs — **do not grow this file with system specs**;
add them to the owning folder's README and at most a one-line pointer here.

---

## Project Overview
- **Engine**: Godot 4.5-stable, GDScript · **Target**: 2D mobile portrait 1080×1920
- **Main scene**: `res://scenes/Lobby.tscn` (lobby: continue → `Season.tscn`; new run → `RunSetup.tscn` → `Season.tscn`)
- **Campaign**: `PRESEASON → PRESEASON_INTL → MIDSEASON → MIDSEASON_INTL → REGULAR → REGULAR_INTL`.
  Win final REGULAR_INTL = ending; miss any phase's playoffs = game over.
- **Week**: advances one week at a time, run day by day 월~일 (Mon–Sun)
  (`season_state["week_day"]`). 월~금 (Mon–Fri) = training days, 토·일 (Sat·Sun) = match days.
  `CalendarSystem.advance_week()` is called only from `SeasonHub._end_week()`.
- **Weekly flow**: HUB → PRESS (press conference) → TRAINING (tile board) → WEEK (weekday rail) →
  on match day MatchFlow (PREP → BAN_PICK (ban/pick + mech assignment) → BattleSim) →
  STANDINGS → back to WEEK → Sunday "주 마감" (End week) → HUB.
- **Outgame = white theme**: every colour goes through `resources/OutgameTheme.gd`
  (white paper, coloured cards); primary actions use the full-width bottom bar
  (`OutgameTheme.add_bottom_bar`, rules in `resources/README.md` "Bottom action bar").
  **BattleSim uses neither** — the battlefield is a dark screen.
- **Save / load**: profile 1 (`user://profile.save`, `ProfileManager`) + run 1
  (`user://run.save`), 4 autosave points, no save inside BattleSim → `features/save_load/README.md`.
- **Screen coordinates** all pass through `ScreenMetrics` (safe area) →
  `docs/mobile_safe_area.md`.
- **Dev setup per PC**: `.mcp.json` registers `godot-mcp` pinned to the addon's
  version (`addons/godot_mcp/plugin.cfg`, currently 2.17.0 — bump both together);
  `.vscode/` is gitignored — copy `.vscode/settings.example.json` → `settings.json`
  and set the local Godot path.

---

## Directory Map

```
esports-manager/
├── CLAUDE.md                 ← YOU ARE HERE (map only)
├── .mcp.json                 ← godot-mcp server (Claude Code), version pinned to addon
├── export_presets.cfg        ← iOS export preset (read by CI)
├── .github/workflows/ios-testbuild.yml ← unsigned .ipa build → docs/ios_testbuild.md
├── ios/plugins/              ← iOS native plugins (Haptics built by CI) → README.md
├── build/                    ← where the phone build (.ipa) is downloaded → README.md
├── data/                     ← CSV tables, game.db, SQLite addon usage, table list → README.md
├── autoloads/                ← GameManager, ProfileManager, Haptics, HapticUi (+ haptics table, db_path) → README.md
├── resources/                ← shared data classes, enums, image lookups, OutgameTheme,
│                               ScreenMetrics, DragScroll, UiHelpers, ConstTable, GameDb, shaders → README.md
├── scenes/                   ← Lobby / Season / MatchFlow / BattleSim / BattleField / Card .tscn
├── docs/                     ← ios_testbuild.md, mobile_safe_area.md,
│                               outgame_dev_plan.md (outgame meta development plan, 아웃게임 메타 개발 계획)
├── addons/godot_mcp/         ← MCP editor plugin (do not modify)
└── features/
    ├── meta/                 ← outgame outside a run (lobby, run setup; later result / collection) → README.md
    │   ├── lobby/            ← project entry: continue / new run, abandon confirm popup
    │   └── run_setup/        ← run setup: scenario → team → 5-pilot lineup (levels, salary cap) → start_run
    ├── save_load/            ← run save (SaveSystem), autosave, mid-match resume
    ├── season/               ← outgame campaign (SeasonHub orchestrator, handoffs, brackets)
    │   ├── calendar/         ← week clock, weekdays / match days, phase transitions
    │   ├── press/            ← press conference (기자회견) messenger screen
    │   ├── week/             ← 시간 경과 (Time passing) screen (day rail + day cards)
    │   ├── training/         ← daily training (일상 훈련) tile board
    │   ├── league/           ← LeagueManager + LeagueView (2 rounds / week)
    │   ├── run_stats/        ← RunStats: match MVP metric, phase POM (season_state.run_stats)
│   ├── staff/            ← StaffSystem: manager · staff stats, cover rule (effective), StaffPanel
│   ├── mastery/          ← MechMastery: mech mastery (run-only), 메크 연구 hub card
│   ├── finance/          ← FinanceSystem: weekly budget, facilities, allocation
│   ├── mental/           ← MentalSystem (trust · interview · outing · incident), PilotMods
    │   └── tournament/       ← playoff + INTL brackets (no README — see season/README.md)
    ├── match_flow/           ← PREP → BAN_PICK → BattleSim handoff
    │   ├── match_prep/
    │   └── ban_pick/         ← ban/pick + mech assignment, MechDetailPanel
    └── battle_sim/           ← battle simulation (PRIMARY FOCUS) — module table in README.md
        ├── combat/           ← SimulationCore, recall, hex grid, pathfinding, lanes, jungle, growth income
        ├── rendering/        ← BattleRenderer (all _draw), marker layout / glide / popups
        ├── card_phase/       ← cards, hand, drag & drop, targeting, deck rules, AI card play
        ├── engage/           ← round-based turn engage stage, VS intro, result screen
        ├── objective/        ← Herald (전령) / Dragon (용) objectives + reward FX
        ├── skill/            ← pilot skills (25)
        ├── mech/             ← mech passives (15) + mech card hooks
        ├── gambit/           ← pre-battle setup + jungle start overlay
        ├── buildings/        ← @tool Building / Waypoint nodes
        ├── debug/            ← BattleLogger
        ├── data/             ← DataLoader, FieldLoader
        └── ui/               ← HUD, pilot strips, detail panel, kill feed, timers, card piles
```

---

## Feature Map

| Feature | Scene | Script | Read |
|---|---|---|---|
| Lobby (main entry) | `scenes/Lobby.tscn` | `features/meta/lobby/LobbyScreen.gd` | `features/meta/lobby/README.md` |
| Run setup | `scenes/RunSetup.tscn` | `features/meta/run_setup/RunSetupScreen.gd` | `features/meta/run_setup/README.md` |
| Season | `scenes/Season.tscn` | `features/season/SeasonHub.gd` | `features/season/README.md` + submodule |
| Match Flow | `scenes/MatchFlow.tscn` | `features/match_flow/MatchFlow.gd` | `features/match_flow/README.md` |
| Battle Sim | `scenes/BattleSim.tscn` | `features/battle_sim/BattleSim.gd` | `features/battle_sim/README.md` + submodule |

### Where to look for a topic
| Topic | README |
|---|---|
| Haptics table & rules, `game.db` res→user copy | `autoloads/README.md` |
| Profile / run save, autosave, mid-match resume, test run file | `features/save_load/README.md` |
| Lobby → Season handoff, abandon-run confirm | `features/meta/lobby/README.md` |
| Run setup steps, lineup (levels · salary cap), pilot detail popup (`DraftDetailPanel`) | `features/meta/run_setup/README.md` |
| ProfileManager (profile.save) | `autoloads/README.md` |
| Weekly progression contract, Weekdays and match days | `features/season/calendar/README.md` |
| Season→MatchFlow→BattleSim handoff, playoff / INTL brackets | `features/season/README.md` |
| MatchFlow→BattleSim handoff (`match_ctx`) | `features/match_flow/README.md`, `features/battle_sim/README.md` |
| Match stats (K/D/A · damage · care), MVP metric, MVP view, phase POM | `features/battle_sim/combat/README.md`, `features/season/run_stats/README.md` |
| BattleSim module architecture, side (blue/red), growth & growth points (성장치), economy gate, field size | `features/battle_sim/README.md` |
| Lane combat, turrets, recall, jungle / camps, front line, stats & hit chance | `features/battle_sim/combat/README.md` |
| Card phase, drag & drop, hand layout, keywords, AI turn, **fixed pilot cards (3 per player) · card scope / categories** | `features/battle_sim/card_phase/README.md` |
| Hand-card press/drag preview (caster neon, draw/discard chevrons, path, hit %), buff banners, reservation chips | `features/battle_sim/card_phase/README.md` (손패 미리보기) |
| Engage stage, VS intro, start positions, result screen | `features/battle_sim/engage/README.md` |
| Marker layout / glide, camp outline, death / popup FX | `features/battle_sim/rendering/README.md` |
| Pilot strips, top chrome, kill feed, detail panel, card piles, safe-area offsets | `features/battle_sim/ui/README.md` |
| Objectives (Herald / Dragon) | `features/battle_sim/objective/README.md` |
| Pilot skills / mech passives | `features/battle_sim/skill/README.md`, `features/battle_sim/mech/README.md` |
| Mob pilots (silhouettes), silhouette shader, image lookups | `resources/README.md` |
| CSV tables, SQLite API, Rebuild game.db | `data/README.md` |
| Tuning constants (const.csv / ConstTable), no values in docs | `data/README.md` |
| M3~M7 contract (state keys, week-end order, file ownership) | `docs/outgame_dev_plan.md` §11 |
| Manager · staff stats, cover rule, hub manage cards (`HubSheet`) | `features/season/staff/README.md` |
| iOS test build, downloading the .ipa | `docs/ios_testbuild.md`, `build/README.md` |

---

## Critical Patterns

### Autoload Access (Godot 4.5)
Do NOT use `class_name` on autoload scripts. Access at runtime:
```gdscript
@onready var _gm: Node = get_node("/root/GameManager")
```
`--check-only --script` doesn't know autoload identifiers (`Haptics`, `HapticUi`)
— verify by running a scene instead.

### Module Communication
All cross-module calls go through the BattleSim orchestrator:
```gdscript
_bs.sim_core.simulate_turn()
_bs.pathfinder.bfs_next_step(...)
_bs.renderer.queue_redraw()
```

### Enums & role order
All shared enums live in `resources/GameEnums.gd` (`class_name GameEnums`).
`GameEnums.ROLE_DISPLAY_ORDER` / `role_seat(role)` (탑 · 정글 · 미드 · 원딜 · 서폿 = top · jungle · mid · ADC · support)
is the **single** order every screen (in-game and outgame) uses to line up five pilots.

### Scene → Script Relationship
Each `.tscn` references its script by UID. When moving scripts, update both the
`.uid` file and the `path=` in the `.tscn`.

### Variable Naming Convention (lint-driven)
Godot 4.5's `UNUSED_PRIVATE_CLASS_VARIABLE` treats a leading underscore as "private".

| Prefix | Meaning | Use when |
|---|---|---|
| `_foo` | private — used **only inside this script** | helper state, internal cache, local nodes |
| `foo`  | public — read or called from **other scripts** | `_bs.foo`, `gm.foo`, signal payloads, etc. |

- Referenced from another script → MUST NOT have a leading underscore; never touched outside → SHOULD.
- `@export` / `@export_tool_button` vars count as public.
- Locals must not shadow `Node` / `CanvasItem` / `Control` properties (`visible`, `position`, `name`, `owner`) — suffix them (`visible_count`).
- Fix the cause, not the symptom: drop the underscore / rename the local. No `@warning_ignore(...)`.
- Exceptions: `_bs` (orchestrator handle) and `_on_*` signal handlers keep the underscore.

---

## Session Checklist
1. Read `CLAUDE.md` (this file)
2. Identify the target feature (`season`, `match_flow`, `battle_sim`, …)
3. Read `features/<feature>/README.md`
4. For multi-module features also read the relevant submodule's README
5. Make focused changes only in that feature's folder; update its README afterwards
6. After adding tables/columns to CSV: run **Project → Tools → Rebuild game.db** (`data/README.md`)
7. After an iOS CI build: download the `.ipa` into `build/` (short SHA in the name),
   delete stale artifacts — `build/README.md`
8. After placing / moving UI: check against **`docs/mobile_safe_area.md`** —
   the bottom gesture zone eats touches
