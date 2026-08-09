# EsportsManager — Project Navigation Map

## Workflow Instructions
**Read this file first every session.** Then locate the relevant feature folder and read its `README.md` before touching any code.

---

## Project Overview
- **Engine**: Godot 4.5-stable, GDScript
- **Target**: 2D Mobile Portrait 1080×1920
- **Main scene**: `res://scenes/TitleScreen.tscn` (3 save slots — pick one to enter Season.tscn)
- **Campaign loop**: 6 events from December → next year:
  `PRESEASON → PRESEASON_INTL → MIDSEASON → MIDSEASON_INTL → REGULAR → REGULAR_INTL`.
  Win the final REGULAR_INTL = ending. Miss any phase's playoffs = game over.
- **Weekly progression**: campaign advances **one week at a time**. Each
  press of "다음 주" rolls the calendar 7 days forward, applies the week's
  training, and resolves any AI matches scheduled for the week.
- **Weekly flow**: HUB → TRAINING (set this week's schedule) → "주 진행"
  → TRAINING_RESULT (per-pilot before/after/delta dashboard) → "다음" →
  MatchFlow if player has a match (PREP → BAN_PICK → ASSIGN → JUNGLE_START
  → BattleSim → return) → STANDINGS (LeagueView / BracketView /
  IntlBracketView) → "다음 주" → HUB.
- **Save / load**: 3 slots persisted as JSON under `user://saves/slot{0,1,2}.save`.
  Auto-save fires at four points: (1) DRAFT → HUB, (2) MatchFlow pre-ban-pick
  (after PREP confirmation), (3) MatchFlow post-gambit (after jungle dir
  picked), (4) post-week-end (after CalendarSystem.advance_week on the
  "다음 주" press). No save during BattleSim — closing mid-battle resumes
  from #3. Title screen routes "이어하기" to MatchFlow.tscn when the slot
  was saved mid-match (`season_state.match_resume` non-null), else Season.tscn.

---

## Directory Structure

```
esports-manager/
├── CLAUDE.md                    ← YOU ARE HERE
│
├── features/
│   ├── season/                  ← Outgame campaign (PRIMARY entry — Season.tscn)
│   │   ├── README.md            ← Read before editing season code
│   │   ├── SeasonHub.gd         ← class_name SeasonHub — campaign orchestrator
│   │   ├── HubView.gd           ← class_name HubView — Phase 3 hub screen UI
│   │   ├── GameOverView.gd      ← class_name GameOverView — Phase 7/8 elimination screen
│   │   ├── EndingView.gd        ← class_name EndingView — Phase 8 world-champion screen
│   │   ├── calendar/            ← Weekly clock, phase transitions
│   │   ├── draft/               ← Initial 5-pilot team selection from 40-pool
│   │   ├── training/            ← 7-day × pilot training grid + TrainingResultView dashboard
│   │   ├── league/              ← LeagueManager + LeagueView (1-round-per-week schedule, AI sims, standings)
│   │   └── tournament/          ← TournamentManager + BracketView (4-team SE playoff, 2 weeks, Phase 7);
│   │                              InternationalTournament + IntlBracketView (8-team SE INTL, 3 weeks, Phase 8)
│   │
│   ├── match_flow/              ← Pre-battle pipeline (entered from Season on the player's match week)
│   │   ├── README.md            ← Read before editing match flow code
│   │   ├── MatchFlow.gd         ← class_name MatchFlow — orchestrator
│   │   ├── match_prep/          ← Pre-match dashboard (review rosters before BAN_PICK)
│   │   ├── ban_pick/            ← LoL-international ban/pick + random AI
│   │   ├── assign/              ← Mech↔player slot manual assignment
│   │   └── jungle_start/        ← Assassin jungle start direction (LEFT/RIGHT)
│   │
│   ├── save_load/               ← Title screen + 3-slot save/load (entry: TitleScreen.tscn)
│   │   ├── README.md            ← Read before editing save/load code
│   │   ├── SaveSystem.gd        ← class_name SaveSystem — static helpers (serialize/list/save/load/delete)
│   │   ├── TitleScreen.gd       ← Project entry — builds 3-slot UI, routes button presses
│   │   └── SlotCard.gd          ← class_name SlotCard — one slot card with new/continue/delete
│   │
│   └── battle_sim/              ← Battle simulation (PRIMARY FOCUS)
│       ├── README.md            ← Read before editing battle sim code
│       ├── BattleSim.gd         ← Thin orchestrator (class_name BattleSim)
│       ├── combat/
│       │   ├── README.md
│       │   ├── SimulationCore.gd   ← Main turn loop, targeting, win condition
│       │   ├── RecallSystem.gd     ← Instant HQ teleport at HP threshold
│       │   ├── HexGrid.gd          ← Hex math, neighbors, screen coords
│       │   └── Pathfinding.gd      ← BFS + greedy movement
│       ├── rendering/
│       │   ├── README.md
│       │   └── BattleRenderer.gd   ← All _draw() logic (extends Node2D)
│       ├── card_phase/
│       │   ├── README.md
│       │   ├── Card.gd                   ← class_name Card — card visual node
│       │   ├── CardPhaseManager.gd       ← Card draw/play overlay and effects
│       │   ├── CardSelectOverlay.gd      ← 버리기:N / 찾기:N modal pick UI
│       │   ├── CardTargetingOverlay.gd   ← 대상 지정 (PILOT/LOCATION/PREVIEW)
│       │   └── AiCardPlayer.gd           ← AI 카드 사용 시 중앙 애니메이션
│       ├── gambit/
│       │   ├── README.md
│       │   └── GambitPhaseManager.gd ← Pre-battle lane assignment UI
│       ├── buildings/
│       │   ├── Building.gd / Waypoint.gd  ← @tool placeable scene nodes
│       │   ├── BuildingLayer.gd / WaypointLayer.gd
│       │   └── BuildingRegistry.gd       ← Cell→Building lookup
│       ├── data/
│       │   ├── DataLoader.gd       ← game.db loader (game_cfg, pilots, lanes)
│       │   └── FieldLoader.gd      ← TileMap reader (HQs/turrets/waypoints/NZ)
│       └── ui/
│           ├── README.md
│           ├── HudBuilder.gd       ← HUD construction and label updates
│           └── CostDonut.gd        ← 전략 포인트 도넛 게이지 (player one = 턴 넘기기 버튼)
│
├── autoloads/
│   ├── README.md                ← Autoload documentation
│   └── GameManager.gd           ← State singleton — NO class_name
│
├── resources/
│   ├── README.md                ← Resource documentation
│   ├── CardData.gd              ← class_name CardData (card data container)
│   ├── GameEnums.gd             ← class_name GameEnums (all shared enums)
│   ├── PilotData.gd             ← class_name PilotData (pilot runtime state)
│   ├── TurretData.gd            ← class_name TurretData (turret state)
│   ├── PlayerData.gd            ← class_name PlayerData (out-game persona + assigned mech)
│   ├── MechData.gd              ← class_name MechData (mech stats — no role)
│   ├── BuildingData.gd / WaypointData.gd ← @tool inspector resources
│   └── UiHelpers.gd             ← class_name UiHelpers (mk_label etc.)
│
├── scenes/
│   ├── TitleScreen.tscn         ← MAIN scene — 3-slot save/load entry (uses features/save_load/)
│   ├── Season.tscn              ← Campaign hub (entered from TitleScreen; uses features/season/)
│   ├── MatchFlow.tscn           ← Pre-battle pipeline (entered from Season)
│   ├── BattleSim.tscn           ← Battle sim scene (entered from MatchFlow)
│   ├── BattleField.tscn         ← TileMapLayer + Building/Waypoint layers
│   └── Card.tscn                ← Card prefab (instantiated at runtime)
│
└── addons/godot_mcp/            ← MCP editor plugin (do not modify)
```

---

## Feature Map

| Feature | Scene | Script | Status |
|---|---|---|---|
| Save / Load | `scenes/TitleScreen.tscn` | `features/save_load/TitleScreen.gd` | **Main entry** — 3 slots under `user://saves/`. New game / continue / delete. Auto-saves at draft / pre-ban-pick / post-gambit / post-week-end. Mid-match resume re-enters MatchFlow at the saved phase. |
| Season | `scenes/Season.tscn` | `features/season/SeasonHub.gd` | Weekly campaign hub. HUB → TRAINING → TRAINING_RESULT → MatchFlow (if match) → STANDINGS → "다음 주" → HUB. Calendar advances 1 week per cycle. INTL phase = 3-week SE bracket; playoff = 2-week SE bracket. REGULAR_INTL win → ENDING; loss → GAME_OVER. |
| Match Flow | `scenes/MatchFlow.tscn` | `features/match_flow/MatchFlow.gd` | Pre-battle pipeline — entered from Season on the player's match week. PREP → BAN_PICK → ASSIGN → JUNGLE_START → BattleSim. |
| Battle Sim | `scenes/BattleSim.tscn` | `features/battle_sim/BattleSim.gd` | **Primary focus** — consumes match_ctx |

### TitleScreen → Season handoff
`TitleScreen.gd` lists three slots (`user://saves/slot{0,1,2}.save`) via
`SaveSystem.list_slots()`. Each slot card shows phase + date, team + trophy
count, current league standing, and last-save timestamp. **새 게임** on an
empty slot: `gm.reset_season_state()` + `gm.active_save_slot = idx` + scene
change to Season.tscn → SeasonHub sees `season_state.active == false` and
runs the DRAFT flow. **이어하기** on a filled slot: `SaveSystem.load_slot(idx)`
overwrites `gm.season_state` from disk + sets `active_save_slot` + scene
change → SeasonHub skips `init_season()` and routes to HUB. **삭제** is
double-tap-to-confirm (first tap arms the button, second tap deletes).
GameOverView and EndingView both expose a "타이틀로" button that resets
season state + clears `active_save_slot` + returns to TitleScreen.tscn.

### Auto-save
Four trigger points across SeasonHub and MatchFlow:
1. **Post-draft** — `SeasonHub.goto(Screen.HUB)` when previous screen was DRAFT.
2. **Pre-ban-pick** — `MatchFlow._on_prep_finished()` after the player
   confirms PREP. Writes `season_state.match_resume = {phase: BAN_PICK, player_side, ...}`.
3. **Post-gambit** — `MatchFlow._on_jungle_finished()` right before scene-change
   to BattleSim. Writes the full match snapshot (banned/picked/assigned mech
   IDs, jungle dir) into `match_resume` with `phase = LAUNCH`.
4. **Post-week-end** — `SeasonHub.on_proceed_to_next_week()` after
   `CalendarSystem.advance_week()` rolls the calendar. Covers both
   post-match weeks and no-match weeks.

No save fires inside BattleSim. Closing mid-battle leaves the disk save at
trigger #3, so resume drops back into BattleSim with the same locked-in
picks but the battle replays from scratch.

`SaveSystem.save_slot(gm.active_save_slot)` is a no-op when the slot is -1
(running Season.tscn / MatchFlow.tscn directly from the editor).

### Mid-match resume routing
TitleScreen "이어하기" branches on `season_state.match_resume`. Non-null →
`MatchFlow.tscn` (MatchFlow consumes the hint and skips PREP, jumping to
BAN_PICK or LAUNCH). Null → `Season.tscn`. SlotCard shows a "경기 진행
중" tag when `meta.match_in_progress == true`.

### Weekly progression contract
The campaign progresses one week at a time. `CalendarSystem.advance_week()`
rolls 7 days forward, bumps `phase_week`, and emits `week_advanced` (and
`phase_changed` on transitions). All three managers (LeagueManager,
TournamentManager, InternationalTournament) listen to `week_advanced` and
either bootstrap their bracket (`is_playoff_bootstrap_week()` for playoff,
`phase_week == 1 && is_intl_phase` for INTL) or no-op. Match resolution is
explicit: `SeasonHub` calls `resolve_current_week()` on each manager
during the post-match flow, never on signal.

### Season → MatchFlow → BattleSim handoff
On the player's match week, `SeasonHub.on_training_result_continue`
populates `season_state["pending_match"]` (`{source, schedule_idx,
enemy_team_id, winner_side}`) and `change_scene_to_file` to MatchFlow.tscn.
MatchFlow runs PREP (review rosters) → BAN_PICK → ASSIGN → JUNGLE_START
→ BattleSim. After BattleSim, the win panel's "다음 →" returns to
`Season.tscn`. `SeasonHub._consume_pending_match_result` applies the
result via `LeagueManager.record_result()` /
`TournamentManager.record_result(slot, winner)` /
`InternationalTournament.record_result(slot, winner)` based on
`pending_match.source`. Then `_resolve_remaining_ai_for_week()` sweeps up
remaining AI matches scheduled for the same week, and the hub routes to
the appropriate STANDINGS view.

### Season — Playoff bracket (Phase 7)
Each league phase reserves **2 trailing playoff weeks** (SF week + F
week). `CalendarSystem.PHASE_WEEKS` = LEAGUE_WEEKS + 2 for league phases.
`TournamentManager` bootstraps the bracket when entering the playoff
bootstrap week (week LEAGUE_WEEKS + 1):
`SF1: #1 vs #4` and `SF2: #2 vs #3` both stamped to that week,
`F: SF1.W vs SF2.W` stamped to week LEAGUE_WEEKS + 2. If
`LeagueManager.player_made_playoffs()` is false on bootstrap,
`playoff_failed_qualification` fires and `SeasonHub` routes to
`Screen.GAME_OVER`. Otherwise `playoff_started` fires; AI bracket matches
resolve via `TournamentManager.resolve_current_week()` during the post-
match sweep, player matches go through the MatchFlow → BattleSim handoff
with `pending_match.source = "playoff"`. The F result writes
`phase_results[phase] = {made_playoffs, champion}` and emits
`playoff_completed`.

### Season — INTL bracket (Phase 8)
Each *_INTL phase (`PRESEASON_INTL`, `MIDSEASON_INTL`, `REGULAR_INTL`) is
a **3-week 8-team single-elimination tournament**. Week 1 = QF (4
matches), Week 2 = SF (2 matches), Week 3 = F. `InternationalTournament`
bootstraps on entry to week 1 of an INTL phase using top-4 from
`LeagueManager.standings_ranked()` (the just-finished league phase's
standings) + 4 fixed external teams from `data/csv/intl_teams.csv` +
`intl_players.csv`. High-low pairing (L1×I4, L2×I3, L3×I2, L4×I1). Both
managers share `season_state["current_tournament"]` but discriminate by
`type` ("INTL" vs "PLAYOFF") — neither clears the other's bracket. AI
matches resolve via `InternationalTournament.resolve_current_week()`;
player matches use the MatchFlow → BattleSim handoff with
`pending_match.source = "intl"` → `InternationalTournament.record_result`.
`MatchFlow._team_roster()` reads from `season_state.intl_pilots` when
`team_id >= 100`. **REGULAR_INTL is the campaign-end gate**: win F →
`Screen.ENDING`; lose F or get eliminated mid-bracket → `Screen.GAME_OVER`
(via `intl_failed_campaign` for fail-fast). PRESEASON_INTL and
MIDSEASON_INTL just toast and continue. Phase results: INTL phases store
`{intl_played, intl_champion}` under `phase_results[phase]`; league
phases store `{made_playoffs, champion}`. HubView's third action button
toggles 3-way: INTL active → "국제대회", PLAYOFF active → "플레이오프",
else → "리그 순위".

### Match Flow → Battle Sim handoff
`MatchFlow` populates `GameManager.match_ctx` (player_roster, enemy_roster,
jungle_start_dir, banned_mech_ids, …) then `change_scene_to_file` to BattleSim.
`BattleSim.spawn_pilots_with_lanes()` injects each `PlayerData.assigned_mech`'s
hp/atk into `PilotData`. If `match_ctx.active` is false (running BattleSim
standalone), it falls back to `ROLE_STATS` defaults.

### Battle Sim — Module Architecture
`BattleSim.gd` is a **thin orchestrator** (`class_name BattleSim extends Node2D`).
Each child module has `@onready var _bs: BattleSim = get_parent() as BattleSim` and accesses state via `_bs.*`.

| Node | Script | Purpose |
|---|---|---|
| SimulationCore | `combat/SimulationCore.gd` | Main turn loop, targeting, movement, win condition |
| RecallSystem | `combat/RecallSystem.gd` | Instant HQ teleport at HP ≤ threshold |
| Pathfinding | `combat/Pathfinding.gd` | BFS + greedy movement |
| BattleRenderer | `rendering/BattleRenderer.gd` | All `_draw()` logic (extends Node2D) |
| CardPhaseManager | `card_phase/CardPhaseManager.gd` | Card turn flow, deck, hand, card effects |
| GambitPhaseManager | `gambit/GambitPhaseManager.gd` | Auto role→lane mapping + battle launch |
| HudBuilder | `ui/HudBuilder.gd` | HUD construction and update (incl. `ui/CostDonut.gd` 전략 포인트 도넛 ×2) |

### Battle Sim — Active Systems
| System | Description |
|---|---|
| Gambit Phase | **UI removed.** Lane is fixed by role (TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT/SNIPER→RIGHT). Pre-battle choices live in `features/match_flow/`. |
| Auto BATTLE | BATTLE auto-ticks every 0.5s (1 tick = "1분"). No Next-Turn or Auto-Play buttons. CARD_PHASE pauses the tick. |
| 작전 단계 (CARD_PHASE) | Triggered at `player_cost ≥ PHASE_THRESHOLD`. 작전 점수 read out on the 전략 포인트 donut gauges (player: top-right of the hand row; enemy: top-right of the screen). Tapping the player donut flips it into a circular 턴 넘기기 button — disabled until ≥ 1 작전 점수 is spent; tapping elsewhere flips it back. |
| 핸드 레이아웃 | Row is `BS_HAND_WIDTH` = (viewport − 2×`BS_HAND_AREA_MARGIN`) × `BS_HAND_WIDTH_SCALE` (1.10) = 902px wide; the Deck/Discard labels re-derive their gutter from the real hand edge. **The fan is one circle**: every card centre rides a circle of radius `BS_HAND_FAN_RADIUS` (3200px) pivoted *below* the row, so tilt and vertical offset always agree and **the middle card is the highest while both ends curve down** (12-card hand: ±6.7°, ends hanging 21.4px below the middle). Clicking the selected card again deselects it. Each player card casts a `DropShadow` child whose offset/blur grows with height — rest 10px → hover 24px → selected 32px. **The row spreads around one "focus" card — `_push_focus_card()` = the selected card, else the hovered one** — so selecting a card opens the hand exactly as hovering it does. Focus scales the card to `Card.HOVER_SCALE` (1.2×, cubic EASE_OUT in 0.04s) and slides its neighbours away by `_hover_push_amount` — solved from the coverage it must prevent (96px enlarged half-width + `BS_HAND_HOVER_MIN_STRIP` 32px clickable sliver − the row's own spacing), so **it grows with the hand size**: `BS_HAND_HOVER_PUSH` 28px floor up to 8 cards → 60.5px at the 12-card cap. **The hand's width is fixed**: the two end cards are anchors, and the push ramps to exactly 0 at them via `1 − (steps/steps_to_end)^BS_HAND_HOVER_FALLOFF_POW` (2.0, so near neighbours keep nearly the full push) — the row redistributes rather than growing. Selecting lifts the card by `Card.PRESS_LIFT` **along its own up-axis, keeping its fan rotation** (±4.6px sideways at the ends of a 12-card hand); `_select_card` reflows the whole row around it first, and since the focus card's own push is 0 there is no push-free slot variant — lift and drop are exact opposites. `_reorder_hand_nodes` raises the selected — else hovered — card above all others. A hover reflow lays out the **incoming focus card too** — only the *selected* card is skipped — otherwise it stays stranded at the push the previous focus gave it. **Hand cards don't pick the mouse**: `spawn_card_node` sets the whole card subtree to `MOUSE_FILTER_IGNORE` (PASS is not enough — a PASS container is still returned by picking) and one `HandHitLayer` Control over the row routes hover/clicks by cursor x, using bands cut at the midpoints between card centres, with the focus card holding the cursor while it's on its enlarged face. Rect picking let the focus card cover its right-hand neighbour down to 0–17px. Hover reflows are **deferred + coalesced** (`move_child` re-fires mouse_entered/exited synchronously — see card_phase/README.md), and `scale` is owned solely by `Card._refresh_float_state`. Card layout tweens `position`, never `global_position` (the latter is scale-coupled — see card_phase/README.md). |
| Combat | **Same-cell only** — no adjacent-cell engagement, no attack range. Lane pilots paired 1:1 by HP against enemy lane pilots; each rolls `hit/(hit+evasion)` for damage. **Push is team-level**: tally unilateral wins per team across all pairs in the cell; the side with strictly more unilateral wins sweeps — every pilot of that side in the cell (including unpaired pilots in e.g. 2v1) advances, every opposing pilot retreats. Tie/0-0 → no push. `_move_pilot` aborts further multi-step movement only when a *same-scope* enemy enters the cell (jungler-vs-jungler or lane-vs-lane); cross-scope contacts never freeze movement. |
| Engagement scopes | Junglers and lane pilots run on **separate engagement brackets**. A jungler never engages an enemy lane pilot, never deals turret damage, and is never paired against attackers as a turret defender. Lane pilots ignore enemy junglers in the same cell. |
| Turret Combat | **Only same-lane lane pilots interact with a turret** (e.g. a RIGHT-lane pilot cannot damage a CENTER turret). Same-lane attackers in an enemy turret cell deal 100% damage to the turret. Same-lane defenders roll on same-lane attackers; successful defender hit → that attacker takes damage. **Retreat is team-wide**: any defender hit forces every same-lane attacker in the cell (paired or not) to retreat together. Off-lane lane pilots in the cell ignore the turret; if both teams have off-lane pilots in the cell they may still pilot-vs-pilot fight each other. **Turrets do NOT attack pilots. Junglers do NOT attack/defend turrets.** Destroying a turret also frees its `Building` node so the sprite disappears. |
| Turret blocks pass-through | Lane pilots **cannot move past an alive enemy turret cell** — both natural movement and push-advance bail once the pilot stands on an alive enemy turret. The pilot must wait out turret destruction (same-lane) or be recalled / displaced out (off-lane). Push-retreat is unaffected. Junglers are exempt. |
| Recall | HP ≤ 20% → instant HQ teleport at full HP. Held during CARD_PHASE; re-checked at phase end (also recalls card-displaced pilots). |
| Jungle (initial) | Both jungles start fully captured; only `(-3,-1)` and `(1,-1)` are neutral. Junglers roam own-captured tiles + claim neutrals. **Lane pilots are forbidden from entering any jungle/neutral cell** — Pathfinding receives `_bs.neutral_zone_cells` as the forbidden set for non-junglers. |
| T1 → Jungle | T1 destroyed in lane L → priority branches off per-lane 취약지점 sets `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}` (side lanes 1 cell, mid 2 flanking cells). (1) **Restoration**: if any of capturer's own same-lane vuln cells are loser-owned, restore them, nothing else flips. (2) **Side-neutral override (L/R only)**: if `(-3,-1)`/`(1,-1)` is loser-owned, capturer takes that neutral instead of loser's vuln. (3) **Default**: loser's same-lane vuln cell(s) flip to capturer. Mid has no neutral override. |
| 3-Lane System | Waypoint paths from HQ → side waypoints → enemy HQ. The old minion / lane-strength concept is **removed**. |

---

## Critical Patterns

### Autoload Access (Godot 4.5)
Do NOT use `class_name` on autoload scripts. Access at runtime:
```gdscript
@onready var _gm: Node = get_node("/root/GameManager")
```

### Module Communication
All cross-module calls go through the BattleSim orchestrator:
```gdscript
_bs.sim_core.simulate_turn()
_bs.pathfinder.bfs_next_step(...)
_bs.renderer.queue_redraw()
```

### Enums
All shared enums live in `resources/GameEnums.gd` with `class_name GameEnums`.
- Battle sim: `BattlePhase`, `Role`, `LanePosition`, `Lane`, `TowerLevel`
- Match flow: `MatchPhase`, `JungleStartDir`, `DraftSide`
- Season: `SeasonPhase`, `TrainingType`, `MatchDayResult`, `TournamentStage`

### Scene → Script Relationship
Each `.tscn` file references its script by UID. When moving scripts, update both the `.uid` file and the `path=` in the `.tscn` file.

### Variable Naming Convention (lint-driven)
Godot 4.5's `UNUSED_PRIVATE_CLASS_VARIABLE` warning treats a leading underscore as **"declared private"**. The convention below keeps that warning a real signal instead of noise.

| Prefix | Meaning | Use when |
|---|---|---|
| `_foo` | private — used **only inside this script** | helper state, internal cache, locally-instantiated nodes |
| `foo`  | public  — read or called from **other scripts** | anything accessed via `_bs.foo`, `gm.foo`, signal payloads, etc. |

**Rules**
- If a variable is referenced as `_bs.x`, `gm.x`, `someNode.x` from another script → it MUST NOT have a leading underscore.
- If a variable is never touched outside its own script → it SHOULD have a leading underscore.
- `@export` / `@export_tool_button` variables exist for the editor; treat them as "public" (no underscore) so the unused-private warning doesn't fire.
- Local variables inside a function must not shadow `Node` / `CanvasItem` / `Control` properties (e.g. `visible`, `position`, `name`, `owner`). Suffix with intent: `visible_count`, `target_position`, `display_name`.

**When fixing a warning, fix the cause, not the symptom**
- `UNUSED_PRIVATE_CLASS_VARIABLE` on an externally-accessed var → drop the underscore (and update every caller).
- `SHADOWED_VARIABLE_BASE_CLASS` → rename the local. Never rename the engine property.
- Do **not** sprinkle `@warning_ignore(...)` to silence these — that hides the next real bug.

**Known exceptions**:
- `_bs` (the orchestrator handle inside each BattleSim child module) is conventionally underscored even though it's `get_parent()`-derived; the underscore marks it as "framework wiring, don't touch".
- `_on_*` signal handler methods keep the underscore even when their `Callable` is passed across scripts via `signal.connect(other._on_xxx)`. The underscore is the Godot-wide signal-handler convention; the cross-script reference is signal wiring, not a real call.

---

## Session Checklist
1. Read `CLAUDE.md` (this file)
2. Identify the target feature (`season`, `match_flow`, or `battle_sim`)
3. Read `features/<feature>/README.md`
4. For multi-module features (season, battle_sim, match_flow): also read the relevant submodule's README
5. Make focused changes only in that feature's folder
6. After adding tables/columns to CSV: run **Project → Tools → Rebuild game.db**

---

## Godot-SQLite Addon

**Addon**: `addons/godot-sqlite/` — GDNative SQLite3 wrapper for Godot 4.0+
**Platforms**: Windows, Linux, Mac, Android, iOS, HTML5

### Core API (class `SQLite`)
```gdscript
var db := SQLite.new()
db.path = "res://data/game.db"       # read-only (packaged)
db.path = "user://data/game.db"      # read-write (runtime)
db.open_db()
db.close_db()
db.query("SELECT * FROM pilots")
db.query_with_bindings("SELECT * FROM pilots WHERE role = ?", [role_id])
db.create_table("pilots", { "id": {"data_type":"int","primary_key":true}, ... })
db.insert_row("pilots", {"id":1, "role":"Tank", "hp":200, "atk":8})
db.select_rows("pilots", "hp > 100", ["role","hp"])  # returns Array of Dicts
db.update_rows("pilots", "id = 1", {"hp": 210})
db.delete_rows("pilots", "id = 1")
```

### Data Types
`int` → INTEGER, `real` → REAL, `text`/`char(n)` → TEXT, `blob` → BLOB (PackedByteArray)

### Important Constraints
- Column/table **names cannot be bound** — interpolate them directly into query strings
- **No encryption** support
- Read-only DBs: package inside `.pck` at `res://`; Read-write DBs: copy to `user://` at runtime
- Foreign keys must be enabled **before** `open_db()`

### Import / Export
```gdscript
db.export_to_json("user://backup.json")
db.import_from_json("res://data/seed.json")
db.backup_to("user://save.db")
db.restore_from("user://save.db")
```

### CSV → DB Workflow Pattern
CSV files live in `data/csv/`. The **EditorPlugin** at `addons/csv_to_db/plugin.gd`
reads each CSV at editor time (menu: **Project → Tools → Rebuild game.db**) and
writes `res://data/game.db` using `create_table` + `insert_row`. Adding a new
table = add a CSV under `data/csv/` and add an entry to both `SCHEMAS` and
`TABLE_DEFS` in the plugin.

### Tables (current)
| Table | CSV | Read at | Purpose |
|---|---|---|---|
| `pilots` | `pilots.csv` | BattleSim startup | Per-role baseline stats (used as fallback when match_ctx is inactive) |
| `cards` | `cards.csv` | GameManager startup | Card pool for the BattleSim card phase |
| `game_config` | `game_config.csv` | BattleSim startup | Tunable knobs (HP, turns, thresholds) |
| `lane_config` | `lane_config.csv` | BattleSim startup | LANE_NAMES, LANE_MAX, midpoints |
| `players` | `players.csv` | Season + MatchFlow startup | 40 pilots (8 teams × 5 roles), `PlayerData` fields. Player drafts 5 from this pool in Season. |
| `mechs` | `mechs.csv` | MatchFlow startup | 30 mech pool (no role); drives PilotData stats when picked |
| `teams` | `teams.csv` | Season `init_season()` | 8 teams (id/name/short_name) → `season_state["team_meta"]`. Falls back to synthesized `Team N` rows if the table is missing. |
| `intl_teams` | `intl_teams.csv` | Season `init_season()` | 4 INTL teams (ids 100..103) → `season_state["intl_team_meta"]`. Synthesized fallback `Intl Alpha/Bravo/Charlie/Delta` rows when the table is missing. |
| `intl_players` | `intl_players.csv` | Season `init_season()` | 20 INTL pilots (ids 100..119, 4 teams × 5 roles) → `season_state["intl_pilots"]`. Used by `MatchFlow._team_roster` and `InternationalTournament.simulate_ai_match` when `team_id >= 100`. |

At runtime, `GameManager` and BattleSim's `DataLoader` open the DB once, load
tables into Dictionaries / Arrays keyed by ID, then close the DB. All in-game
access goes through those structures — not live DB queries.
