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
│       │   ├── CardTargetingOverlay.gd   ← 카드 선택 = 대상 지정 오버레이 (좌하단 확인/취소)
│       │   ├── CardPileViewer.gd         ← Deck / Discard 목록 열람 (읽기 전용, 이름순)
│       │   └── AiCardPlayer.gd           ← AI 카드 사용 시 중앙 애니메이션
│       ├── engage/
│       │   ├── README.md
│       │   ├── EngagePhaseManager.gd   ← 실시간 교전 오케스트레이터 (engage:N / duel)
│       │   ├── RealtimeEngageSim.gd    ← 헤드리스 사이드뷰 벨트 교전 시뮬레이터 (ATB)
│       │   └── EngageArena.gd          ← 사이드뷰 렌더러(시네마 밴드 + 카메라 + 하단 초상화 스트립) + 결과 대시보드
│       ├── gambit/
│       │   ├── README.md
│       │   └── GambitPhaseManager.gd ← Pre-battle lane assignment UI
│       ├── buildings/
│       │   ├── Building.gd / Waypoint.gd  ← @tool placeable scene nodes
│       │   ├── BuildingLayer.gd / WaypointLayer.gd
│       │   └── BuildingRegistry.gd       ← Cell→Building lookup
│       ├── debug/
│       │   ├── README.md
│       │   └── BattleLogger.gd     ← 전 행동 로그(콘솔 + user://battle_logs/) + 교차 감지
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
→ BattleSim. 진영(`player_side`)은 **현재 항상 BLUE 로 고정**이며
(예전의 매 경기 랜덤 추첨은 제거), 밴픽 순서와 BattleSim 의 전략 포인트
선점·선턴을 함께 결정한다 — 위 "진영 (블루 / 레드)" 항목 참조.
After BattleSim, the win panel's "다음 →" returns to
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
| EngagePhaseManager | `engage/EngagePhaseManager.gd` | 사이드뷰 벨트 교전 오케스트레이터 — `engage/RealtimeEngageSim.gd`(헤드리스 ATB 시뮬)와 `engage/EngageArena.gd`(렌더러)를 잇는다 |
| HudBuilder | `ui/HudBuilder.gd` | HUD construction and update (incl. `ui/CostDonut.gd` 전략 포인트 도넛 ×2) |
| BattleLogger | `debug/BattleLogger.gd` | 전 행동 로그 + 적 파일럿 교차(cross-over) 자동 감지 |

### Battle Sim — Active Systems
| System | Description |
|---|---|
| Gambit Phase | **UI removed.** Lane is fixed by role (TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT/SNIPER→RIGHT). Pre-battle choices live in `features/match_flow/`. |
| Auto BATTLE | BATTLE auto-ticks every 0.5s (1 tick = "1분"). No Next-Turn or Auto-Play buttons. CARD_PHASE pauses the tick, and so does 상대 차례 — that one runs *inside* BATTLE without changing `game_phase`, so `BattleSim._process` also gates on `card_phase.is_ai_turn_active()` (same flag freezes the MM:SS clock). |
| 진영 (블루 / 레드) | `BattleSim.blue_team` (0 = 플레이어 팀) 은 `match_ctx.player_side` 에서 유도된다. **레드 = 밴픽 선밴/선픽, 블루 = 후밴/후픽 + 인게임 선**. 블루의 인게임 이득은 둘이다 — (1) `BattleSim.seed_side_costs()` 가 개시 시점에 전략 포인트를 `BLUE_COST_HEAD_START`(game_config, 1) 로 심어 문턱에 먼저 닿게 하고(COST_RECOVERY 는 양 팀에 같은 틱에 같은 양이 들어가므로 격차가 유지된다), (2) 양 팀이 같은 틱에 문턱 위에 있을 때 **먼저 차례를 잡는다**. **현재 `MatchFlow` 는 플레이어를 항상 BLUE 로 고정한다** — 예전의 매 경기 랜덤 추첨은 제거됐고, 되살릴 때는 `MatchFlow._ready()` 의 fresh-entry 한 줄만 되돌리면 된다. |
| 개시 손패 | 양 팀은 `INITIAL_HAND_SIZE`(game_config, 5)장을 들고 시작한다 — `build_starter_decks` 가 덱을 섞은 직후 `_deal_initial_hands()` 로 돌린다. 예전엔 빈 손으로 시작해 첫 차례까지 자동 드로우만으로 손이 찼고, 그래서 첫 작전 단계를 상한에 한참 못 미치는 손으로 맞았다. 실측: 개시 5장 + 첫 차례(13틱)까지의 자동 드로우 7회 = **정확히 12장** = `MAX_HAND_SIZE`. |
| 상대 차례 (AI 턴) | **양 팀이 각자 자기 작전 점수로 턴을 갖는다.** 플레이어가 턴을 넘기는 것(`end_card_phase`)은 더 이상 AI 턴을 부르지 않는다 — 배너 없이 곧장 BATTLE 로 돌아간다. AI 턴은 BATTLE 틱에서 `ai_cost ≥ PHASE_THRESHOLD` **이고** 낼 수 있는 카드가 손에 있을 때 `CardPhaseManager._run_ai_turn()` 으로 발동하며, "상대 차례" 배너는 이때만 뜬다(예전엔 상대가 0점이라 아무것도 안 해도 매번 떴다). **양쪽이 동시에 준비되면 `_next_turn_side()` 가 중재한다 — 아직 아무도 안 잡았으면 블루, 그 뒤로는 직전에 잡지 않은 쪽이 잡는 교대다.** 예전엔 이 자리에서 **AI 를 무조건 먼저** 검사해 굶주림을 막았는데(0코스트 카드만 내고 턴을 넘긴 플레이어는 다음 틱에도 점수가 문턱 위라 자기 단계에 재진입해 AI 를 영원히 굶길 수 있다), 블루 우선으로 뒤집으면서 그 방어를 교대 규칙이 대신한다 — 방금 잡은 쪽은 상대가 한 번 잡기 전까지 다시 잡지 못한다. 반대쪽 굶주림(점수만 차고 낼 카드가 없어 배너만 매 틱 뜨는 것)은 `_ai_turn_ready()` 가 `AiCardPlayer` 와 **같은 지불 가능 필터**로 막는다. AI 턴 끝에도 플레이어 턴과 같은 복귀 스윕(`process_phase_end_recalls`)이 돈다. |
| 교전 (ENGAGE) | `engage:N` / `duel` 카드가 여는 **실시간 사이드뷰 벨트 교전** (관전 전용, 플레이어 입력 없음). **`engage:N` 의 N 은 라운드가 아니라 `N × RealtimeEngageSim.SEC_PER_ROUND` 초** (현재 3.0 → `engage:3` = 정확히 9초). **전장 육각 셀 매핑은 버렸다** — 무대는 팀0 왼쪽 / 팀1 오른쪽으로 마주 선 평면 벨트(1240×400)이고 자리는 역할이 정한다(근접 앞줄 / 원거리 뒷줄). **ATB**: 각 유닛이 메크 `speed`(mechs.csv, 40~100)에 비례해 차오르는 **보이지 않는 게이지**를 굴리고, 만충되면 `IDLE → ADVANCE(접근) → STRIKE(공격) → IDLE` 한 사이클을 돈다. **원위치 복귀는 없다** — 공격을 끝낸 자리가 곧 새 앵커(`anchor_pos`)이므로 양 팀이 서로에게 파고들며 무대 한쪽으로 뭉친다(예전의 `RETURN` 상태는 삭제). `IDLE` 의 앵커 복원 이동은 넉백으로 밀린 몫만 되돌린다. 게이지는 행동 중에도 차므로 빠른 메크는 느린 메크가 한 번 움직일 때 두 번 움직인다(기준: speed 70 = `ATB_REF_SEC` 1.9초마다 1회). 근접은 밀착(`MELEE_REACH` 88px)까지, 원거리는 **최대 사거리의 90%**(270px)까지 파고든 뒤 때린다. 사거리 판정에는 `STRIKE_DIST_EPSILON`(0.5px) 여유가 붙는다 — 접근을 끝낸 유닛은 사거리 **딱 그 거리**에 스냅하는데, 부동소수 오차로 그 거리가 사거리 바로 위에 떨어지면 여유 없는 판정이 영원히 실패해 유닛이 `ADVANCE_MAX_SEC` 교착으로만 차례를 접는다(실측: 근접 1:1 이 9초에 공격 1회). 명중하면 대상이 넉백되고 **밀려난 자리가 그대로 새 앵커가 된다** — 앵커를 두고 오면 IDLE 의 복원 드리프트(748px/s)가 넉백(420px/s)보다 빨라 맞은 프레임에 되돌려 버려 넉백이 아예 안 보이고, 근접이 사거리에 붙어 굳어 공격 모션도 사라진다. 피해·스탯에는 얹히지 않고 **위치와 재접근 거리**만 바꾼다. **암살자만 적 뒷줄(원거리)을 우선 노린다**(`DIVE_FOCUS`) — 이 분기가 없으면 앞줄이 더 가깝고 존재감도 두 배(4 vs 2)라 원거리 메크가 교전 내내 한 대도 맞지 않는다(실측 확인). **교전 중 이탈은 없다** — 아무도 무대를 뜰 수 없고, 종료는 시간 만료 또는 한 쪽 전멸뿐이며 빈사여도 후퇴하지 않는다. **종료 판정 후 `EngagePhaseManager.END_HOLD_SEC`(2.0초) 동안 전투만 멈춘 무대를 더 보여 주고(종료 사유 배너 표시) 그 다음 결과 대시보드가 뜬다** — 마지막 처치가 결과창에 먹히지 않게 하기 위함. 유예 동안 `elapsed` 는 멈추므로 표시되는 교전 시간은 실제 전투 시간 그대로다. **포탑은 사거리 존도 무대 참가자도 아니라 배경 지형이다**: 참가 파일럿이 **자기 팀 포탑 칸 위에 서 있을 때만** 그 포탑이 가담해 자기 ATB(`game_config.TURRET_SPEED` 55)로 적 파일럿을 때린다(**사거리 제한 없음**, 명중 판정은 굴린다, 무대에서 포탑 HP 는 안 깎인다). 예전의 포탑 사거리원 · 회피 · 다이브 판정은 전부 삭제됐다. 자리는 유닛 벨트가 아니라 **자기 팀 뒷줄 뒤의 가장 먼 바닥선**(x 225 / 1015, y 48)이고 유닛보다 먼저(= 뒤에) 축소해 그려진다. 피해 공식(atk 1회분, 보호막 우선)은 전장과 공유하지만 **명중률은 전장 확률을 80~100% 구간으로 리맵**한다(`ENGAGE_HIT_MIN` 0.80 / `ENGAGE_HIT_MAX` 1.00 → 스탯이 대등하면 90%). `grid_pos` 는 교전으로 바뀌지 않는다. **화면**: 가로로 납작한 시네마 밴드 `EngageArena.BAND_RECT`(24, 440, 1032×500) 한 창 안에서만 무대가 보이고(`clip_contents`) 그 밖은 검정 α 0.86 으로 딤드되며, **밴드 아래에 참가자 원형 초상화 + 체력 바 스트립**이 팀별 두 줄로 깔린다(행동 중인 유닛은 초상화 테두리가 금색으로 승격). 카메라는 **생존 유닛만** 프레이밍하고(포탑은 제외 — 담으면 배율이 떨어져 유닛이 잘게 보인다) `stage_rect()`(벨트 + 배경 지형) 밖은 절대 비추지 않는다. 자세한 내용과 튜닝 상수는 `engage/README.md`. |
| 작전 단계 (CARD_PHASE) | Triggered at `player_cost ≥ PHASE_THRESHOLD`. 작전 점수 read out on the 전략 포인트 donut gauges — **둘 다 화면 좌측 거터**(player: 핸드 행 좌측 상단 = Deck 카운터 위; enemy: 좌측 상단 = 상대 핸드 peek 아래). Tapping the player donut flips it into a circular 턴 넘기기 button — **카드를 한 장이라도 낸 뒤에야** 활성화된다(`cards_played_this_phase`). 예전 규칙은 "작전 점수를 1 이상 써야 한다"였는데, 28장 중 9장이 0코스트라 낼 수 있는 카드가 전부 무료면 점수가 줄지 않아 턴을 영영 넘기지 못했다(작전 단계 동안 BATTLE 이 멈추므로 손패도 안 바뀐다). 낼 수 있는 카드가 하나도 없는 손패는 그냥 통과시킨다. Tapping elsewhere flips it back. |
| 카드 선택 = 대상 지정 | **카드를 드는 순간이 곧 대상 지정 단계다.** 설명 상자의 "카드 내기" 버튼은 사라졌고, 카드를 고르면 즉시 사거리 밖 타일이 딤드되며 화면 **우하단**(Discard 카운터 위)에 확인 / 취소가 뜬다 — 전략 포인트 도넛과 좌우로 갈라져 있다. 대상 지정 카드는 사거리 안의 유효 대상 외 파일럿까지 딤드되고, 파일럿 마커를 눌러 대상을 찍으면 시안 링이 붙으면서 확인이 활성화된다. **확인을 누르기 전까지 비용도 빠지지 않고 카드도 핸드에 남으므로 취소는 그냥 선택 해제다** — 예전의 대상 지정 환불 경로는 사라졌다(버리기 / 찾기 스냅샷 환불은 그대로). PILOT / LOCATION 카드가 들려 있는 동안 전장 클릭은 빗나가도 오버레이가 삼키므로, 탈출은 취소 · 카드 재클릭 · 다른 카드 선택뿐이다. 모달이 아니라서 핸드 클릭과 턴 넘기기는 계속 살아 있다. |
| 공격 카드 명중 판정 | `attack:N` 카드도 전장과 **같은 명중 판정**을 굴린다 — `SimulationCore.roll_hit` (`hit/(hit+evasion)`). 빗나가면 데미지가 0이고 로그에 "빗나감"이 남는다. `pierce`(필중)는 판정을 건너뛰고, `repeat`(연속 공격)은 **명중할 때마다** 같은 공격을 다시 굴려 빗나가거나 대상이 쓰러질 때까지 이어진다 — 무한 루프 방지 상한은 `CardPhaseManager.MAX_ATTACK_REPEATS`(5타). |
| 한 셀에 여러 명일 때 대상 지정 | PILOT 히트 테스트는 `grid_pos` 가 아니라 **실제로 그려진 마커 위치**(`BattleRenderer.pilot_marker_positions()`, `_draw()` 와 같은 스택 solve)를 본다. 예전엔 타일 중심 / `pilot_marker_pos_solo` 로 재서 같은 셀의 파일럿이 전부 같은 좌표를 갖는 바람에 어느 얼굴을 눌러도 **맨 왼쪽 파일럿**이 잡혔다. 마커에 안 맞은 클릭은 자기 타일 안이면 여전히 잡히되 마커 거리 순으로 정렬된다. |
| 핸드 상한 12장 | `MAX_HAND_SIZE` = 12. **내 차례가 아닐 때**(작전 점수가 다시 차오르는 동안) 도는 자동 드로우는 핸드가 꽉 차 있어도 무조건 뽑고, 넘친 만큼 **가장 오래된** 카드부터 discard 로 보낸다(양 팀 동일) — 단 **계획 중시로 보존된 카드는 건너뛴다**. 예전처럼 드로우를 건너뛰면 덱이 돌지 않아 손이 그대로 굳어 있었다. 반면 **내 턴에 카드 효과로 뽑은 카드는 상한을 넘겨도 버리지 않는다** — 턴이 끝난 뒤 첫 자동 드로우가 정리한다. 덱이 비면 discard 전체를 되섞어 덱으로 되돌리는 건 기존과 동일(`draw_card`). |
| 카드 시전자 제약 (`scope`) | `cards.csv` 의 `scope` 가 카드를 가질 수 있는 파일럿을 정한다 — `lane`(전진 등)은 **레인 파일럿만**, `jungle`(약탈 · 정글 파밍 · 전투 준비 · 정밀 이동)은 **정글러만**, `any` 는 제약 없음. 판정은 **스타터 덱을 돌릴 때 한 번**만 한다(`CardPhaseManager._pool_for_pilot`): 시전자는 배분 후 바뀌지 않으므로, 사용 시점에 막으면 쓸 수 없는 카드가 손패에 영영 잠긴 채 남는다. 알 수 없는 `scope` 값은 제약 없음으로 읽어 CSV 오타가 카드를 통째로 지우지 않게 한다. **파급**: 전투 준비 / 정밀 이동이 정글 전용이 되면서 **레인 파일럿은 이동 카드를 전혀 갖지 못한다**(위치 조작은 전진뿐). `RecallSystem._is_out_of_position` 은 이제 발동할 수 없는 경로지만 향후 레인 이동 카드 자리로 남겨 둔다. |
| 카드 종류 / 덱 슬롯 (`card_type` · `card_cat`) | `scope` 가 **누가 가질 수 있는가**를 정한다면 이 둘은 **어느 슬롯을 채우는가**를 정한다. `card_type` = `mech` / `pilot`, `card_cat` = `-` / `lane` / `draw` / `jungle` / `common`. 파일럿마다 **메크 3장 + 파일럿 3장**을 받고, 파일럿 3장의 내역은 역할이 가른다 — **정글러** `jungle` 2 + `draw` 1, **서포터** `lane` 1 + `draw` 2, **나머지 3인** `lane` 2 + `draw` 1. 각 슬롯은 **중복 없이** 뽑는다(라인전 풀이 3종인데 2장을 요구하므로 중복 허용이면 같은 카드 두 장이 더 흔했다); 풀이 모자랄 때만 중복으로 폴백한다. `card_cat = common` 은 **라인전 슬롯과 정글 슬롯 양쪽 후보**이며 지금은 **복귀** 하나뿐이다 — 라인전 카드이면서 정글러의 유일한 HP 회복 수단이라 어느 한쪽에만 두면 한쪽이 굶는다. 덱 크기는 그대로 5명 × 6장 = 30장. |
| 4턴 경제 게이트 (`ECONOMY_START_TURN`) | 전략 점수 회복과 자동 드로우는 **4턴부터** 돈다(`CardPhaseManager.do_battle_turn`). 그 전에는 두 카운터를 아예 굴리지 않아 게이트가 열릴 때 밀린 회복이 몰려 터지지도 않는다. **개시 손패 5장과 블루 선점 1점은 그대로 0턴**에 들어가고, **성장도 게이트를 타지 않는다**(1턴부터). 실측: 첫 작전 단계가 13턴 → **16턴**(player 8 / ai 7)으로 밀린다. |
| 성장 (인게임 누적) | 살아 있는 파일럿의 `atk` / `max_hp` 가 매 턴 `GROWTH_PER_TURN`(game_config, 0.01 = +1%p) 만큼 원본 대비 늘어난다(`SimulationCore.tick_growth_and_expiries`, 턴 루프의 **맨 앞**). 스탯은 매 턴 곱해 나가는 대신 `PilotData.base_atk` / `base_max_hp` 에서 **다시 계산**한다 — 매 턴 반올림이 끼면 오차가 누적돼 실제 성장률을 갉아먹는다. 최대 체력 증가분만큼 현재 체력도 함께 오른다. **죽어 있는 동안은 성장이 멈추지만 누적치는 남는다** — 부활하면 죽기 전 성장을 들고 돌아온다. 획득 배율(`growth_rate_mult`)은 **안전한 파밍**(+10%, 턴 만료)과 **완벽한 마무리**(+25%, 다음 작전 단계까지, 팀 전원)가 건드리며 같은 필드라 나중에 건 쪽이 덮어쓴다. |
| 라인전 스탯 | **`hit` / `evasion` 전용** 배율(±10%)이며 `SimulationCore.roll_hit` **한 곳에서만** 곱해진다 — 공격자의 `hit` 과 방어자의 `evasion` 에 각자 자기 배율이 붙는다. `atk` / `max_hp` 는 성장이 담당하므로 여기서 건드리지 않는다. `roll_hit` 은 전장 자동 교전과 공격 카드가 공유하므로 둘 다 반영되고, **교전 무대는 자기 확률 구간(80~100%)을 쓰므로 반영되지 않는다**. 같은 파일럿에 두 번 걸면 **덮어쓴다**(합산 아님) — 3종 풀에서 2장 뽑는 구조상 합산을 허용하면 +20~30% 가 그냥 운으로 굴러 나온다. **공격적인 라인전**(+10%) / **안전한 파밍**(−10%, 대신 성장 +10%). |
| 지연 효과 3종 (작전 단계 진입 정산) | `CardPhaseManager._apply_phase_entry_carryovers(is_player)` 가 **자기 팀의 다음 작전 단계 진입 시점**에 한꺼번에 정산한다. (1) **계획 중시**의 보존 목록(`BattleSim.preserved_cards_p/ai`)을 비운다 — 보존은 BATTLE 구간 한 번만 버틴다. (2) **아드레날린**의 `next_phase_strategy_*`(−2)를 점수에 더한다(0 아래로는 안 내려간다). (3) **완벽한 마무리**의 팀 성장 배율을 1.0 으로 되돌린다. 한편 **계획 살인**의 예약(`kill_bounty_*`)은 그 단계가 끝날 때(`end_card_phase` / AI 턴 종료) 사라진다. |
| 계획 중시 (보존) | 보존은 **상한 초과 자동 버리기(`_trim_hand_overflow`)로부터만** 지켜 준다. 카드 효과에 의한 강제 버리기(재고 / 완벽한 마무리 / 과감한 정리 / 솔로 퍼포먼스)는 보존을 무시한다. 플레이어는 찾기와 같은 그리드로 **손패**를 펼쳐 고르고(`CardSelectOverlay.start_preserve`), 고른 카드는 손패에서 빠지지 않는다 — 오버레이는 픽만 돌려주고 등록은 `CardPhaseManager` 가 한다. 표시는 `Card` 의 시안 테두리(`PreserveMark`)이며 카드를 어둡게 하지 않는다(보존은 제약이 아니라 보증). |
| 계획 살인 (처치 현상금) | **선불 예약형**이다. 카드를 낸 시점에 `BattleSim.kill_bounty_p/ai` 를 심고, **모든 사망이 지나는 유일한 지점**인 `mark_pilot_dead` 가 쓰러진 파일럿의 **반대 팀**에 한 번 지급하고 0으로 소모한다. 전장에 제3세력이 없으므로 처치자 인자를 따로 넘기지 않는다. 같은 단계에 두 장을 내면 큰 쪽 하나만 남는다. |
| 완벽한 마무리 (`end_phase`) | 이 절은 **자리에서 단계를 닫지 않는다.** 효과 체인이 도는 동안 카드는 손패 밖에 떠 있어서, 지금 닫으면 소멸 / discard 라우팅 전에 문이 닫힌다. `_end_phase_requested` 플래그만 세우고 **플레이어는 `_finalize_pending_play` 말미**가, **AI 는 `AiCardPlayer` 의 플레이 루프**가(교전 아레나를 기다린 **뒤**에) `consume_end_phase_request()` 로 받아 간다. |
| AI 한 차례 플레이 상한 | `AiCardPlayer.MAX_PLAYS_PER_TURN`(12). 루프의 실제 종료 조건은 "낼 수 있는 카드가 없을 때"인데, **재고**(비용 0, 손패를 전부 버리고 같은 수를 다시 뽑는다)처럼 비용을 안 쓰고 손패를 회전시키는 카드가 그 조건을 덱+discard 가 마를 때까지 미룰 수 있다. 구조적 루프를 끊는 백스톱이지 밸런스 노브가 아니다. |
| 랜덤 풀 제외 (`pool = 0`) | `pool = 0` 인 카드는 `_build_pool_from_db` 가 걸러 내 랜덤 스타터 덱에 절대 들어가지 않는다. **결투(id 3)** 가 첫 사례 — 구현과 효과 처리는 전부 살아 있지만 아무에게도 지급되지 않으며, 특정 메크 고유 카드로 전환할 자리로 남겨 둔 것이다. |
| 손패 복귀 (`return_left:N`) | **정밀 이동**은 discard 로 가지 않고 **손패 맨 왼쪽**으로 돌아오며, 돌아올 때마다 **그 카드 자신의 비용만** N 오른다(0 → 1 → 2 …). 시전자별 사본(`make_card_copy`)에 찍히므로 다른 카드는 영향이 없다 — 단계 전체에 세금을 매기는 `cost_inc_phase` 와는 별개의 노브이고, 정밀 이동은 더 이상 그 절을 달고 있지 않다(`move;return_left:1`). 판정은 effect chain 이 아니라 `_dispose_used_card` 가 한다 — chain 이 도는 동안 카드는 손패 밖에 있기 때문. 비용이 감당 못 할 만큼 오르면 맨 왼쪽 = `_trim_hand_overflow` 가 가장 먼저 버리는 자리이므로 알아서 정리된다. **이 절을 다는 카드는 비용이 반드시 올라야 한다** — 0코스트가 0코스트로 돌아오면 `AiCardPlayer.run_ai_plays` 루프가 끝나지 않는다. |
| 카드 소멸 규칙 | **소멸은 `keyword = exhaust` 하나로만 결정된다.** 손패 복귀 카드를 뺀 나머지는 전부 discard 로 간다. 예전엔 `uses > 0` 인 카드가 사용 횟수를 다 쓰면 사라졌는데, `cards.csv` 는 exhaust 가 아닌 카드도 거의 전부 `uses = 1` 이라 **전투 개시를 포함한 대부분의 카드가 한 번 내면 그대로 소멸**했다 — 덱이 돌지 않고 매치 내내 줄어들기만 했고, discard 는 버리기 카드로만 찼다. `CardData.remaining_uses` 는 삭제됐고 `uses` 컬럼은 로드만 될 뿐 아무도 읽지 않는다(향후 "N회 사용 후 소멸" 용으로 남겨 둔 자리). |
| Deck / Discard 목록 열람 | 핸드 행 양옆의 **Deck / Discard 카운터를 누르면** 그 더미의 카드가 찾기 그리드와 같은 5열 목록으로 펼쳐진다(`card_phase/CardPileViewer.gd`, 읽기 전용). **정렬은 이름 오름차순** — 실제 덱 순서를 보여 주면 다음 드로우가 그대로 읽히기 때문이며, 찾기(`search:N`) 그리드도 같은 규칙으로 정렬한다. 열리는 시점은 **작전 단계뿐**(`CardPhaseManager.can_browse_piles()`); 못 여는 상태에서는 버튼이 비활성이고 라벨이 흐려진다. 열려 있는 동안 핸드 입력 · 턴 넘기기 · 도넛 플립이 모두 잠긴다 — 특히 `CostDonut` 은 `_input` 으로 듣기 때문에 딤만으로는 막히지 않아 `set_flip_allowed` 를 따로 끈다. 닫기는 닫기 버튼 또는 딤 클릭. |
| 사용 불가 카드 표시 | 마나 부족 / 시전자 부활 대기는 **카드 전체를 덮는 반투명 슬래브**(`Card.BlockOverlay`)로 표현한다 — 카드 배경만 회색으로 칠하면 그 위의 파일럿 일러스트가 밝게 남아 쓸 수 있는 카드처럼 읽혔다. 시전자가 쓰러져 있으면 그 위에 **부활까지 남은 턴 수**가 카드 한가운데 큰 폰트로 찍히고, 그 동안 확인 버튼은 비활성이다. |
| 핸드 레이아웃 | Row is `BS_HAND_WIDTH` = (viewport − 2×`BS_HAND_AREA_MARGIN`) × `BS_HAND_WIDTH_SCALE` (1.10) = 902px wide; the Deck/Discard labels re-derive their gutter from the real hand edge. **The fan is one circle**: every card centre rides a circle of radius `BS_HAND_FAN_RADIUS` (3200px) pivoted *below* the row, so tilt and vertical offset always agree and **the middle card is the highest while both ends curve down** (12-card hand: ±6.7°, ends hanging 21.4px below the middle). Clicking the selected card again deselects it. Each player card casts a `DropShadow` child whose offset/blur grows with height — rest 10px → hover 24px → selected 32px. **The row spreads around one "focus" card — `_push_focus_card()` = the selected card, else the hovered one** — so selecting a card opens the hand exactly as hovering it does. Focus scales the card to `Card.HOVER_SCALE` (1.2×, cubic EASE_OUT in 0.04s) and slides its neighbours away by `_hover_push_amount` — solved from the coverage it must prevent (96px enlarged half-width + `BS_HAND_HOVER_MIN_STRIP` 32px clickable sliver − the row's own spacing), so **it grows with the hand size**: `BS_HAND_HOVER_PUSH` 28px floor up to 8 cards → 60.5px at 12 cards. **The hand's width is fixed**: the two end cards are anchors, and the push ramps to exactly 0 at them via `1 − (steps/steps_to_end)^BS_HAND_HOVER_FALLOFF_POW` (2.0, so near neighbours keep nearly the full push) — the row redistributes rather than growing. Selecting lifts the card by `Card.PRESS_LIFT` **along its own up-axis, keeping its fan rotation** (±4.6px sideways at the ends of a 12-card hand); `_select_card` reflows the whole row around it first, and since the focus card's own push is 0 there is no push-free slot variant — lift and drop are exact opposites. `_reorder_hand_nodes` raises the selected — else hovered — card above all others. A hover reflow lays out the **incoming focus card too** — only the *selected* card is skipped — otherwise it stays stranded at the push the previous focus gave it. **Hand cards don't pick the mouse**: `spawn_card_node` sets the whole card subtree to `MOUSE_FILTER_IGNORE` (PASS is not enough — a PASS container is still returned by picking) and one `HandHitLayer` Control over the row routes hover/clicks by cursor x, using bands cut at the midpoints between card centres, with the focus card holding the cursor while it's on its enlarged face. Rect picking let the focus card cover its right-hand neighbour down to 0–17px. Hover reflows are **deferred + coalesced** (`move_child` re-fires mouse_entered/exited synchronously — see card_phase/README.md), and `scale` is owned solely by `Card._refresh_float_state`. Card layout tweens `position`, never `global_position` (the latter is scale-coupled — see card_phase/README.md). |
| 상대 핸드 레이아웃 | 상대 핸드도 겹쳐진 **부채꼴**이며, 플레이어 핸드를 **상하 반전**한 모양이다: 원의 중심이 카드보다 *위*에 있어 θ=0 지점이 호의 가장 낮은 점이 되고, 따라서 **가운데 카드가 패널 아래로 가장 많이 튀어나오고 양 끝이 위로 말려 올라간다**. 기울기는 `−θ`(플레이어 팬의 좌우 기울기를 거울대칭). `HudBuilder.AI_HAND_FAN_RADIUS` 620 / `AI_HAND_FAN_STEP_DEG` 3.2 / `AI_HAND_FAN_MAX_SPREAD_DEG` 28 로, 카드 간 중심 간격은 34.6px(72px 카드 대비 절반 넘게 겹침)에서 12장 기준 26.9px 까지 좁아진다. 자세한 식은 `ui/README.md`. |
| 전투 행동 로그 | `debug/BattleLogger.gd` (`_bs.blog`). 매 턴 전/후 위치 스냅샷 + 리스폰·리콜·교전·데미지·사망·자유이동(스텝 단위)·푸시·포탑·HQ·정글·카드까지 콘솔과 `user://battle_logs/battle_<timestamp>.log` 양쪽에 기록. 턴 종료 시 같은 스코프의 적끼리 자리를 맞바꾸면 `!!SWAP` / `!!CROSS` 로 표시하고 두 파일럿의 이동 이력을 되짚어 준다. 기본 ON — `blog.enabled` 로 끈다. |
| 이동 해석 (단일 패스) | 자유이동과 교전 푸시는 **하나의 패스**(`SimulationCore.resolve_movement`)에서 **락스텝**으로 해석된다 — 한 라운드 안의 모든 파일럿이 같은 스냅샷을 보고 목적지를 정한 뒤 동시에 커밋하므로, 같은 스코프의 적끼리 자리를 맞바꾸거나 서로를 통과하는 일이 구조적으로 불가능하다. 한 라운드에서 중재되는 충돌은 둘이다. (1) **버티는 적 지나치기** — 전진은 적 HQ 쪽, 후퇴는 자기 HQ 쪽이라 방향이 같으므로 **승자는 밀려난 패자를 따라 들어간다**(= 라인이 한 턴에 한 칸 밀린다). 예전엔 두 목적지가 겹치면 전진 쪽을 취소해 "패자만 쫓겨나고 승자는 그 칸을 지킨다" 였는데, 일직선 레인에서는 목적지가 **항상** 겹쳐서 교전에 이겨도 승자가 영영 한 칸도 나아가지 못했다. 지금은 적이 밀려날 곳이 없어 그 칸에 **남을 때만** 전진을 취소한다(`_veto_advance_over_stuck_enemy`) — 서 있는 적을 스쳐 지나가지 않기 위해서다. 적 포탑 칸은 막지 않는다 — 패자가 자기 포탑 칸으로 밀려나면 승자도 거기까지 따라 들어가고, 그 칸에서 공성이 시작된다. (2) **정면 충돌**(서로의 칸을 노림)은 **푸시 > 자유이동, 동률이면 팀0** 우선순위로 한쪽이 그 칸을 차지하고 다른 쪽이 멈춰 **같은 칸에서 만나** 다음 턴에 교전한다. 데미지 적용은 이동보다 **앞**에 온다(이번 턴에 죽은 파일럿은 움직이지 않는다). |
| Combat | **Same-cell only** — no adjacent-cell engagement, no attack range. Lane pilots paired 1:1 by HP against enemy lane pilots; each rolls `hit/(hit+evasion)` for damage — 이 판정에 **라인전 스탯**이 곱해진다(위 항목). **명중 1회 피해 = `atk × BATTLE_PILOT_DMG_MULT`**(game_config, 0.35 — 반올림, 최소 1). 이 배율은 **파일럿이 받는 전장 피해 전용**이다: 파일럿→포탑 / 파일럿→HQ 는 `atk` 원본 그대로이고, 공격 카드와 교전 무대도 각자 계산을 쓴다. 원본 `atk` 로는 한 대가 복귀 구간보다 컸다 — atk 28 상대 vs max_hp 75 스나이퍼는 1타가 최대 체력의 37% 라 20% 복귀선 위에서 곧장 0 으로 떨어졌고, 저HP 복귀가 발동할 구간 자체가 없었다. **Push is team-level**: tally unilateral wins per team across all pairs in the cell; the side with strictly more unilateral wins sweeps — every pilot of that side in the cell (including unpaired pilots in e.g. 2v1) advances, every opposing pilot retreats. Tie/0-0 → no push. Advance and retreat point the **same way** (enemy HQ vs own HQ), so the winners **follow the losers into the next cell** — 교전 칸 전체가 패자 HQ 쪽으로 한 칸 미끄러지고 다음 턴에 거기서 다시 붙는다. 이것이 라인 푸시다. 전진이 취소되는 경우는 **패자가 밀려날 곳이 없어 그 칸에 남을 때** 하나뿐이다 — 앞 칸이 적 포탑이어도 승자는 그 칸까지 따라 들어간다(포탑 공성은 그 다음 턴). `_move_pilot` aborts further multi-step movement only when a *same-scope* enemy enters the cell (jungler-vs-jungler or lane-vs-lane); cross-scope contacts never freeze movement. |
| Engagement scopes | Junglers and lane pilots run on **separate engagement brackets**. A jungler never engages an enemy lane pilot, never deals turret damage, and is never paired against attackers as a turret defender. Lane pilots ignore enemy junglers in the same cell. |
| Turret Combat (포탑 칸 점거) | **Only same-lane lane pilots interact with a turret** (e.g. a RIGHT-lane pilot cannot damage a CENTER turret). 전진하는 레인 파일럿은 같은 레인 적 포탑 칸에 **실제로 올라선다** — 그냥 걸어 올라가든, 교전에서 이겨 밀려나는 적을 따라 들어가든, 전진 카드로 들어가든 같다(예전의 "발만 들였다 빼는" 인접 공성 `resolve_turret_sieges` / `_bounce_off_enemy_turret` 은 삭제). **진입한 턴에는 피해가 없다.** 그 칸에 서서 맞는 **다음 턴**에 `_resolve_turret_combat` 이 돌아 **명중 판정 없이** `atk` 전량을 포탑에 넣는다. **적이 그 칸에서 농성 중이어도 포탑 피해는 반드시 들어간다** — 수비자는 포탑을 가려 주지 못한다. 포탑 피해를 넣은 **다음**, 같은 레인 공격자와 수비자가 **서로 명중 판정을 굴려**(HP 오름차순 1:1 페어링, 양쪽 다 `_pilot_hit_damage`) 피해를 주고받는다. 예전엔 "공격은 전부 포탑으로 간다"며 **공격자가 수비자에게 0 피해**였고, 그래서 포탑에 눌러앉은 수비자는 공격자를 일방적으로 두들길 수 있었다. 넉백은 그대로 **수비자가 있을 때만**이고, **명중 여부와 무관하게** 공격자는 직전 칸으로 밀려난다. 수비자가 없으면 밀어낼 주체가 없어 공격자는 그 자리에 눌러앉아 **매 턴** 포탑을 갈아 낸다. 예외는 **때릴 수 없는 포탑**(같은 레인 T1 이 살아 있는 T2)뿐 — 갈아 낼 게 없으니 무조건 물러난다(파일럿끼리의 판정은 그래도 굴린다). 결과적으로 포탑 피해는 무방비면 매 턴, 수비가 붙으면 2턴에 1회(진입 → 타격 후 밀려남 → 재진입). 오프레인 파일럿은 포탑을 무시하고, 양 팀 오프레인끼리는 여전히 파일럿 교전을 한다. **Turrets do NOT attack pilots. Junglers do NOT attack/defend turrets.** T2 는 같은 레인 T1 이 살아 있는 동안 무적. 포탑 파괴 시 `Building` 노드도 해제해 스프라이트가 사라진다. |
| 포탑 피격 연출 | 살아남은 포탑이 피해를 입으면 `BattleSim.anim_turret_hit(td)` 가 0.26초(`ANIM_TURRET_HIT_DUR`) 동안 **좌우로 흔들리며 붉게 번쩍이는** 연출을 건다(파괴 타격은 제외 — 스프라이트가 그 자리에서 사라진다). 포탑 그림은 렌더러가 그리는 게 아니라 `BattleField/BuildingLayer` 아래의 `Building` 노드라, `BattleSim._apply_turret_hit_visual` 이 그 노드의 `position` / `modulate` 를 직접 흔든다(기본 위치는 셀별로 `_turret_home_pos` 에 캐시, 마지막 프레임과 재시작 시 원복). `BattleRenderer` 는 `BattleSim.turret_hit_offset(td)` 를 읽어 **HP 바를 같은 오프셋으로** 흔들 뿐이다. |
| 전진 카드 (`advance:N`) | 카드 한 장이 **라인을 N 칸 밀어 올린다**. 미니틱 하나가 `SimulationCore._advance_tick` 이고, 전장 규칙을 그대로 쓰되 판정 하나만 강제한다 — **전진을 낸 쪽은 그 칸의 교전에서 무조건 이긴 것으로 친다**(피해 판정은 평소대로 굴리므로 맞을 건 맞는다. 밀리는 쪽만 고정). 그래서 **시전자와 같은 칸·같은 스코프의 아군이 함께 한 칸 전진하고, 같은 칸의 적은 함께 한 칸 밀려난다**. 예전엔 (1) 일방 명중 우세를 그대로 읽어 주사위가 나쁘면 시전자가 자기 HQ 쪽으로 물러났고(= 전진 카드가 후퇴 카드였다), (2) "카드는 한 명만 움직인다"며 진 적을 제자리에 두고 시전자만 옆을 스쳐 갔다. 다음 칸이 **같은 레인 적 포탑**이면 무리는 전장 규칙 그대로 **그 칸에 올라선다**(그 틱에는 포탑 피해 없음). 밀려날 곳이 없어 적이 칸에 남으면 무리도 전진하지 않는다. 시전 시점에 **이미 같은 레인 적 포탑 칸 위**라면 포탑 규칙이 이긴다 — 포탑에 무판정 피해를 넣고, 그 칸에 **수비자가 있으면** 한 칸 후퇴(**전진이 뒤로 가는 유일한 경우**), 없으면 물러나지 않고 제자리에서 계속 갈아 낸다. |
| Recall / Respawn | **복귀 = 본진 귀환.** 두 가지 사유가 `RecallSystem.return_to_hq` 한 경로로 들어온다 — (1) HP ≤ `RECALL_HP_THRESHOLD`(20%), (2) 이동 카드가 파일럿을 **정글이나 다른 레인의 통로**에 떨어뜨린 위치 이탈. **복귀는 전장을 비우지 않는다** — 그 턴에 곧장 자기 HQ 에 **만피로** 서고 `alive` 는 계속 true 다. 파일럿이 전장에서 사라지는 사유는 **사망뿐**. 대신 복귀한 턴에는 움직이지 않고(`PilotData.recall_hold` → `resolve_movement` 가 이동 패스 1회를 걸러 내며 플래그를 소비), **다음 턴부터** 웨이포인트 0 부터 자기 레인을 다시 걸어 나간다. 즉 복귀 비용은 회복 대기가 아니라 **HQ 에서 전선까지 다시 걸어가는 시간**이다. **자기 레인 위라면 아무리 깊어도 위치 이탈이 아니다** — 스플릿 푸시는 살려 둔 설계다. 복귀 카드(`recall_ally`)는 여기에 대기 없이 즉시 HQ + 만피. 전장을 비우는 것은 사망뿐이므로 `respawn_timer` 와 **`BattleSim.turns_until_return(p)`** 은 **사망 전용 시계**다 — "남은 턴 수"가 필요한 곳(카드 잠금 표시, 로그 `dead:N`)은 여전히 헬퍼를 거친다. **리스폰 턴 수는 경기 시간에 따라 늘어난다** — `BattleSim.respawn_turns_now()` = `RESPAWN_TURNS`(game_config, 5) + `turn_count / 10`. 사망은 **오직** `BattleSim.mark_pilot_dead(p)` 한 곳을 지난다(전장 교전 / 전진 / 공격 카드 / 교전 무대 공통). |
| 사망 연출 | 쓰러진 파일럿은 그 자리에서 **1초간 딤드된 채 남았다가**(`ANIM_DEATH_HOLD_DUR`) 0.45초 동안 투명해지며 위로 떠올라 전장을 뜬다. `alive` 는 이미 false 이므로 순수 UI다 — `BattleRenderer._is_renderable()` 이 `anim_death_phase != 0` 을 살아 있음과 함께 그리기 조건으로 삼는다. 시신도 셀 레이아웃 슬롯을 차지하므로 그 1.45초 동안 같은 칸의 산 파일럿이 밀린다(히트 테스트도 같은 solve 를 읽으므로 어긋나지 않는다). |
| 피해 수치 표시 | **공격 카드(`attack:N`) 전용.** 판정마다 대상 마커 위로 `-N` / `MISS` / `흡수`(보호막이 전부 먹은 경우)가 떠올랐다 사라진다(`BattleRenderer.spawn_pilot_popup`). 연속 공격은 타수마다 `DMG_POPUP_STAGGER` 만큼 늦게 뜬다. 좌표는 띄운 순간에 고정되므로 대상이 쓰러져도 숫자가 끝까지 재생된다. 전장 자동 교전은 기존대로 흔들림만. |
| Jungle (initial) | Both jungles start fully captured; only `(-3,-1)` and `(1,-1)` are neutral. Junglers roam own-captured tiles + claim neutrals. **Lane pilots are forbidden from entering any jungle/neutral cell** — Pathfinding receives `_bs.neutral_zone_cells` as the forbidden set for non-junglers. Once both neutrals are taken the roam target is **sticky** (`PilotData.jungle_roam_target`, held until reached): recomputing "farthest own-captured cell" every turn flipped as soon as the jungler stepped, so it ping-ponged between two *mid-lane* corridor cells in front of its own mid T1 forever. The jungler now finishes the tour and rests only on jungle cells. |
| T1 → Jungle | T1 destroyed in lane L → priority branches off per-lane 취약지점 sets `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}` (side lanes 1 cell, mid 2 flanking cells). (1) **Restoration**: if any of capturer's own same-lane vuln cells are loser-owned, restore them, nothing else flips. (2) **Side-neutral override (L/R only)**: if `(-3,-1)`/`(1,-1)` is loser-owned, capturer takes that neutral instead of loser's vuln. (3) **Default**: loser's same-lane vuln cell(s) flip to capturer. Mid has no neutral override. |
| 3-Lane System | Waypoint paths from HQ → side waypoints → enemy HQ. The old minion / lane-strength concept is **removed**. |
| 수비 개념 없음 | 레인 파일럿의 목표는 **언제나** `current_waypoint(p)` 하나다. 아군 포탑이 맞고 있다고 돌아오는 행동은 존재하지 않는다 — 파일럿은 자기 HQ 에서 출발해 레인 길을 따라가고, 그러다 상대 라이너와 마주치는 것이 설계다. (같은 레인 스나이퍼가 죽으면 서포터가 아군 최전방 포탑을 껴안던 `_supporter_should_fall_back` / `_own_forward_turret_cell` 은 삭제됐다.) |
| 레인 통로 (`lane_corridor`) | 레인별 실제 통과 셀 집합. 그 레인의 웨이포인트를 정글 금지로 BFS 연결해 **한 번만** 만들고 캐시한다(팀1 경로는 팀0 의 역순이라 셀 집합은 공유). 유일한 소비자는 `RecallSystem._is_out_of_position` — "이동 카드가 이 레인 파일럿을 **남의 레인**에 떨어뜨렸나". 판정은 반드시 **다른 레인에 속함**을 확인하지, 자기 레인에 없음만으로 판정하지 않는다: BFS 타이브레이크가 실제 걸어간 경로와 한 칸 어긋나도 멀쩡한 파일럿을 추방하면 안 되기 때문. `LANE_NAMES` 에는 GUERRILLA 칸도 있으니 순회는 `lane_corridor_count()` 로 한다. |

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
CSV files live in `data/csv/`. The conversion logic lives in
`addons/csv_to_db/csv_to_db.gd` (a plain `RefCounted`); `addons/csv_to_db/plugin.gd`
is a thin **EditorPlugin** that only registers the menu item
(**Project → Tools → Rebuild game.db**). It reads each CSV, validates required
columns + duplicate PKs, then writes `res://data/game.db` with
`create_table` + `insert_row`. Adding a new table = add a CSV under `data/csv/`
and add an entry to both `SCHEMAS` and `TABLE_DEFS` **in `csv_to_db.gd`**.

The logic sits outside the EditorPlugin because `EditorPlugin` cannot be
instantiated headlessly, so the DB can also be rebuilt from the CLI:
```gdscript
# a throwaway `extends SceneTree` script, run with --headless --script
func _initialize() -> void:
    var err: String = load("res://addons/csv_to_db/csv_to_db.gd").new().call("rebuild")
    if err != "": printerr(err)
    quit()
```

### Tables (current)
| Table | CSV | Read at | Purpose |
|---|---|---|---|
| `pilots` | `pilots.csv` | BattleSim startup | Per-role baseline stats (used as fallback when match_ctx is inactive) |
| `cards` | `cards.csv` | GameManager startup | Card pool for the BattleSim card phase (**28행**). `scope` (`any`/`lane`/`jungle`) restricts who may be a card's 시전자; `pool` (1/0) keeps a card out of the random starter deck; `card_type` (`mech`/`pilot`) 와 `card_cat` (`-`/`lane`/`draw`/`jungle`/`common`) 은 덱 슬롯을 정한다 — 위 "카드 종류 / 덱 슬롯" 항목 참조. 이름이 비슷한 **재빠른 사고**(id 15, `draw:2`)와 **과감한 정리**(id 29, `discard_right:3;draw:5`)는 다른 카드다. |
| `game_config` | `game_config.csv` | BattleSim startup | Tunable knobs (HP, turns, thresholds). `INITIAL_HAND_SIZE`(5) 는 개시 시 양 팀에 돌리는 손패 장수, `BLUE_COST_HEAD_START`(1) 은 블루 진영이 선점하는 전략 포인트다. `ECONOMY_START_TURN`(4)은 전략 점수 회복 / 자동 드로우가 처음 도는 턴이고, `GROWTH_PER_TURN`(0.01)은 턴당 누적 성장률이다 — 성장은 이 게이트를 타지 않고 1턴부터 돈다. `BATTLE_PILOT_DMG_MULT`(**0.35**) 는 **전장 교전이 파일럿에게 넣는 피해**에만 곱해진다 — 포탑/HQ 피해·공격 카드·교전 무대는 제외. `TURRET_HP` 는 **300**. `TURRET_SPEED`(55)는 **교전 무대 전용** — 가담한 포탑의 ATB 속도이며, 전장에서는 포탑이 파일럿을 공격하지 않으므로 아무 영향이 없다. 복귀는 이제 즉시 만피 + 1턴 대기라 회복/대기 관련 키가 없다 — `RECALL_HEAL_RATIO` 와 `RECALL_RETURN_TURNS` 둘 다 제거됐다. |
| `lane_config` | `lane_config.csv` | BattleSim startup | LANE_NAMES, LANE_MAX, midpoints |
| `players` | `players.csv` | Season + MatchFlow startup | 40 pilots (8 teams × 5 roles), `PlayerData` fields. Player drafts 5 from this pool in Season. **`name` 은 그 id 의 초상화에 묶여 있다** — pilot id `N` 이 쓰는 `resources/images/pilot/*/N+1_*.png` 가 어떤 젠레스 존 제로 에이전트인지가 곧 이름이다(40장 전부 공식 아이콘 아트와 대조). 행 순서·id 를 바꾸면 이름과 얼굴이 어긋난다 — 자세한 규칙과 대체 코스튬 4건은 `resources/README.md` 의 `PilotImages.gd` 절. |
| `mechs` | `mechs.csv` | MatchFlow startup | 30 mech pool (no role); drives PilotData stats when picked. `presence`(타겟 어그로)와 `speed`(40~100, ATB 충전 속도)는 **교전 무대 전용** — 전장은 읽지 않는다. speed 는 hp 와 역상관으로 채워져 있다(탱커 44~60 < 서포터 68~77 < 격투가 69~82 < 스나이퍼 82~91 < 암살자 91~100). |
| `teams` | `teams.csv` | Season `init_season()` | 8 teams (id/name/short_name) → `season_state["team_meta"]`. Falls back to synthesized `Team N` rows if the table is missing. 팀명은 젠레스 존 제로 **진영(faction)** 에서 땄다 — 다만 **로스터는 진영과 맞지 않는다**(초상화가 진영을 섞어 뽑혀 있어서), 팀명은 순수한 간판이다. |
| `intl_teams` | `intl_teams.csv` | Season `init_season()` | 4 INTL teams (ids 100..103) → `season_state["intl_team_meta"]`. Synthesized fallback `Intl Alpha/Bravo/Charlie/Delta` rows when the table is missing. 국내 8팀이 쓰지 않은 진영 4개를 쓴다. |
| `intl_players` | `intl_players.csv` | Season `init_season()` | 20 INTL pilots (ids 100..119, 4 teams × 5 roles) → `season_state["intl_pilots"]`. Used by `MatchFlow._team_roster` and `InternationalTournament.simulate_ai_match` when `team_id >= 100`. **초상화가 없으므로**(`PilotImages.has_image` 는 id ≥ 100 에 false) 이름은 `players.csv` 40명이 쓰고 남은 에이전트 중에서 자유롭게 붙였다. |

At runtime, `GameManager` and BattleSim's `DataLoader` open the DB once, load
tables into Dictionaries / Arrays keyed by ID, then close the DB. All in-game
access goes through those structures — not live DB queries.
