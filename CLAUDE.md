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
│       │   ├── CardTargetingOverlay.gd   ← 카드 드래그 = 대상 지정 오버레이 (딤·강조 + 드롭 확정)
│       │   ├── CardDragArrow.gd          ← 카드 ↔ 커서 조준 화살표 (2차 베지어, 카드 뒤에 그려짐)
│       │   ├── CardPileViewer.gd         ← Deck / Discard 목록 열람 (읽기 전용, 이름순)
│       │   └── AiCardPlayer.gd           ← AI 카드 사용 시 중앙 애니메이션
│       ├── engage/
│       │   ├── README.md
│       │   ├── EngagePhaseManager.gd   ← 턴제 교전 오케스트레이터 (engage:N / duel)
│       │   ├── EngageIntro.gd         ← 카드 제출 직후의 VS 개시 확인 화면 (참가자 명단 + 확인/취소)
│       │   ├── TurnEngageSim.gd        ← 헤드리스 사이드뷰 벨트 교전 시뮬레이터 (라운드 턴제)
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
│           ├── PilotStrip.gd       ← 파일럿 5인 스트립 (눈높이 초상화 + 체력 + 성장치) ×2
│           ├── PilotDetailPanel.gd ← 파일럿 상세 모달 (좌 전신 아트 / 우 스탯 3절)
│           ├── CardPileStack.gd   ← 덱 / 버린 더미 — 앞으로 누운 카드 뭉치 + 장수 + 오가는 카드 잔상
│           └── CostDonut.gd        ← 전략 포인트 도넛 게이지 (player one = 턴 넘기기 버튼)
│
├── autoloads/
│   ├── README.md                ← Autoload documentation
│   └── GameManager.gd           ← State singleton — NO class_name
│
├── resources/
│   ├── README.md                ← Resource documentation
│   ├── CardData.gd              ← class_name CardData (card data container)
│   ├── MechImages.gd            ← class_name MechImages (메크 전신 아트 조회 — 30칸 전부 채워져 있음)
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
| EngagePhaseManager | `engage/EngagePhaseManager.gd` | 사이드뷰 벨트 교전 오케스트레이터 — `engage/EngageIntro.gd`(제출 직후 VS 확인 화면) → `engage/TurnEngageSim.gd`(헤드리스 라운드 턴제 시뮬) → `engage/EngageArena.gd`(렌더러) 를 잇는다 |
| HudBuilder | `ui/HudBuilder.gd` | HUD construction and update (incl. `ui/CostDonut.gd` 전략 포인트 도넛 ×2, `ui/PilotStrip.gd` 파일럿 스트립 ×2, `ui/CardPileStack.gd` 덱 / 버린 더미 뭉치 ×2) |
| PilotDetailPanel | `ui/PilotDetailPanel.gd` | 파일럿 상세 모달 — 하단 스트립의 얼굴을 누르면 열린다 (작전 단계 한정) |
| BattleLogger | `debug/BattleLogger.gd` | 전 행동 로그 + 적 파일럿 교차(cross-over) 자동 감지 |

### Battle Sim — Active Systems
| System | Description |
|---|---|
| Gambit Phase | **UI removed.** Lane is fixed by role (TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT/SNIPER→RIGHT). Pre-battle choices live in `features/match_flow/`. |
| Auto BATTLE | BATTLE auto-ticks every 0.5s (1 tick = "1분"). No Next-Turn or Auto-Play buttons. CARD_PHASE pauses the tick, and so does 상대 차례 — that one runs *inside* BATTLE without changing `game_phase`, so `BattleSim._process` also gates on `card_phase.is_ai_turn_active()` (same flag freezes the MM:SS clock). |
| 진영 (블루 / 레드) | `BattleSim.blue_team` (0 = 플레이어 팀) 은 `match_ctx.player_side` 에서 유도된다. **레드 = 밴픽 선밴/선픽, 블루 = 후밴/후픽 + 인게임 선**. 블루의 인게임 이득은 둘이다 — (1) `BattleSim.seed_side_costs()` 가 개시 시점에 전략 포인트를 `BLUE_COST_HEAD_START`(game_config, 1) 로 심어 문턱에 먼저 닿게 하고(COST_RECOVERY 는 양 팀에 같은 틱에 같은 양이 들어가므로 격차가 유지된다), (2) 양 팀이 같은 틱에 문턱 위에 있을 때 **먼저 차례를 잡는다**. **현재 `MatchFlow` 는 플레이어를 항상 BLUE 로 고정한다** — 예전의 매 경기 랜덤 추첨은 제거됐고, 되살릴 때는 `MatchFlow._ready()` 의 fresh-entry 한 줄만 되돌리면 된다. |
| 개시 손패 (없음) | **양 팀은 빈 손으로 시작한다.** `build_starter_decks` 는 덱을 섞고 `_clear_hands()` 로 손패를 비우는 데서 끝나고, 손패는 오직 `ECONOMY_START_TURN`(10)부터 도는 BATTLE 자동 드로우로만 찬다 — 1~9턴은 카드가 아예 없는 순수 라인전이다. 예전에는 `INITIAL_HAND_SIZE`(game_config, 5)장을 `_deal_initial_hands()` 로 미리 돌려 첫 차례를 상한에 꽉 찬 손으로 맞게 했는데, 그 키와 함수는 **삭제됐다**. 실측: 첫 작전 단계가 **22턴 · 손패 7장**(player 8 / ai 7). |
| 상대 차례 (AI 턴) | **양 팀이 각자 자기 작전 점수로 턴을 갖는다.** 플레이어가 턴을 넘긴 순간 **상대가 이미 문턱 위(＋낼 카드 보유)면 그 자리에서 상대 차례가 시작된다** — 다음 BATTLE 틱을 기다리지 않고, 내 점수와도 무관하다(`end_card_phase` 말미의 `_ai_turn_ready()` → `await _run_ai_turn()`). 상대가 문턱 아래면 예전처럼 배너 없이 곧장 BATTLE 로 돌아간다. AI 턴은 그 밖에도 BATTLE 틱에서 `ai_cost ≥ PHASE_THRESHOLD` **이고** 낼 수 있는 카드가 손에 있을 때 `CardPhaseManager._run_ai_turn()` 으로 발동하며, "상대 차례" 배너는 이때만 뜬다(예전엔 상대가 0점이라 아무것도 안 해도 매번 떴다). **양쪽이 동시에 준비되면 `_next_turn_side()` 가 중재한다 — 아직 아무도 안 잡았으면 블루, 그 뒤로는 직전에 잡지 않은 쪽이 잡는 교대다.** 예전엔 이 자리에서 **AI 를 무조건 먼저** 검사해 굶주림을 막았는데(0코스트 카드만 내고 턴을 넘긴 플레이어는 다음 틱에도 점수가 문턱 위라 자기 단계에 재진입해 AI 를 영원히 굶길 수 있다), 블루 우선으로 뒤집으면서 그 방어를 교대 규칙이 대신한다 — 방금 잡은 쪽은 상대가 한 번 잡기 전까지 다시 잡지 못한다. 반대쪽 굶주림(점수만 차고 낼 카드가 없어 배너만 매 틱 뜨는 것)은 `_ai_turn_ready()` 가 `AiCardPlayer` 와 **같은 지불 가능 필터**로 막는다. AI 턴 끝에도 플레이어 턴과 같은 복귀 스윕(`process_phase_end_recalls`)이 돈다. |
| 교전 (ENGAGE) | `engage:N` / `duel` 카드가 여는 **라운드 기반 턴제 사이드뷰 벨트 교전** (관전 전용, 플레이어 입력 없음). **`engage:N` 의 N 은 라운드 수다** — `engage:3` = 3라운드이고, 예전의 "N × 3초" 환산은 삭제됐다. **한 라운드 = 참가자 전원이 정확히 한 번씩 행동**하며, 무대에는 언제나 **한 명만**(`current_actor`) 나와 있다 — 그 한 차례(`ADVANCE` 접근 → `STRIKE` 공격 → 정착)가 끝나면 다음 순서로 넘어가고, 순서 끝에 닿으면 라운드가 오르며 **다시 시전자부터** 같은 순서를 돈다. **행동 순서는 개시 시 한 번 정해져 매 라운드 반복된다(상황 기반)**: 시전자 팀부터 한 명씩 **팀 교대**, 팀 안에서는 **역할 고정**(암살자 → 격투가 → 탱커 → 스나이퍼 → 서포터), 단 **시전자는 자기 팀 맨 앞으로 당겨진다**(교전을 연 쪽이 선공한다는 것이 카드의 값이다). 포탑은 파일럿 전원이 돈 **뒤** 시전자 팀 포탑부터 한 번씩 — 유닛 사이에 끼우지 않는 이유는 카메라가 포탑을 프레이밍하지 않아 화면 밖에서 포격만 날아오는 침묵 구간이 생기기 때문이다. 죽은 행동자는 건너뛰되 순서 배열은 그대로라 살아 있는 사람들의 상대 순서는 바뀌지 않는다. **메크 `speed` 스탯과 `game_config.TURRET_SPEED` 는 삭제됐다** — 라운드마다 전원이 한 번씩 행동하므로 행동 빈도를 가르는 스탯이 없다(예전 ATB 실시간 모델의 유산이며 되살리지 말 것). **전장 육각 셀 매핑은 쓰지 않는다** — 무대는 팀0 왼쪽 / 팀1 오른쪽으로 마주 선 평면 벨트(1240×400)이고 자리는 역할이 정한다(근접 앞줄 / 원거리 뒷줄). 근접은 밀착(`MELEE_REACH` 88px)까지, 원거리는 **최대 사거리의 90%**(270px)까지 파고든 뒤 때린다. 이동 속도는 근접 1400 / 원거리 1100px/s 로 ATB 시절(880 / 620)보다 빠르다 — 한 번에 한 명뿐이라 **접근 시간이 곧 관전자가 기다리는 시간**이기 때문. 사거리 판정에는 `STRIKE_DIST_EPSILON`(0.5px) 여유가 붙는다 — 접근을 끝낸 유닛은 사거리 **딱 그 거리**에 스냅하는데, 부동소수 오차로 그 거리가 사거리 바로 위에 떨어지면 여유 없는 판정이 영원히 실패해 유닛이 `ADVANCE_MAX_SEC` 교착으로만 차례를 접는다. **원위치 복귀는 없다** — 공격을 끝낸 자리가 곧 새 앵커(`anchor_pos`)이므로 양 팀이 서로에게 파고들며 무대 한쪽으로 뭉친다. 명중하면 대상이 넉백되고 **밀려난 자리가 그대로 새 앵커가 된다** — 앵커를 두고 오면 복원 드리프트가 넉백보다 빨라 맞은 프레임에 되돌려 버려 넉백이 아예 안 보이고, 근접이 사거리에 붙어 굳어 공격 모션도 사라진다. 피해·스탯에는 얹히지 않고 **위치와 재접근 거리**만 바꾼다. **암살자만 적 뒷줄(원거리)을 우선 노린다**(`DIVE_FOCUS`) — 이 분기가 없으면 앞줄이 더 가깝고 존재감도 두 배(4 vs 2)라 원거리 메크가 교전 내내 한 대도 맞지 않는다(실측 확인). 집중 사격 가중(`_focus_count`)은 **라운드 경계에서 비우지 않는다** — 끊으면 딜이 흩어져 처치가 거의 안 나온다(실시간 시절에는 동시 행동이 이 역할을 했다). **교전 중 이탈은 없다** — 아무도 무대를 뜰 수 없고, 종료는 **라운드 소진** 또는 한 쪽 전멸뿐이며 빈사여도 후퇴하지 않는다. **종료 판정 후 `EngagePhaseManager.END_HOLD_SEC`(2.0초) 동안 전투만 멈춘 무대를 더 보여 주고(종료 사유 배너 표시) 그 다음 결과 대시보드가 뜬다** — 마지막 처치가 결과창에 먹히지 않게 하기 위함. 유예 동안 `round_index` 는 멈추므로 대시보드의 라운드 수는 실제로 싸운 라운드 수 그대로다. **포탑은 사거리 존도 무대 참가자도 아니라 배경 지형이다**: 참가 파일럿이 **자기 팀 포탑 칸 위에 서 있을 때만** 그 포탑이 가담해 **라운드마다 한 번** 적 파일럿을 때린다(**사거리 제한 없음**, 명중 판정은 굴린다, 무대에서 포탑 HP 는 안 깎인다). 자리는 유닛 벨트가 아니라 **자기 팀 뒷줄 뒤의 가장 먼 바닥선**(x 225 / 1015, y 48)이고 유닛보다 먼저(= 뒤에) 축소해 그려진다. 피해 공식(atk 1회분, 보호막 우선)은 전장과 공유하지만 **명중률은 전장 확률을 80~100% 구간으로 리맵**한다(`ENGAGE_HIT_MIN` 0.80 / `ENGAGE_HIT_MAX` 1.00 → 스탯이 대등하면 90%). 처치는 `mark_pilot_dead(victim, killer)` 를 지나므로 리스폰 스케일링과 **성장치 정산**이 그대로 걸리고, 준 피해도 `score_pilot_damage` 로 적립된다. `grid_pos` 는 교전으로 바뀌지 않는다. **화면**: 가로로 납작한 시네마 밴드 `EngageArena.BAND_RECT`(24, 440, 1032×500) 한 창 안에서만 무대가 보이고(`clip_contents`) 그 밖은 검정 α 0.86 으로 딤드되며, **밴드 아래에 참가자 원형 초상화 + 체력 바 스트립**이 팀별 두 줄로 깔린다(지금 차례를 가진 **정확히 한 명**의 초상화 테두리가 금색으로 승격). 상단 헤더는 **라운드 카운터(`라운드 2 / 3`) + 라운드 칸 + "누구의 차례"** 두 줄이다 — 실시간 시절의 남은 시간 바(MM:SS.s)는 삭제됐다. 카메라는 **생존 유닛만** 프레이밍하고(포탑은 제외 — 담으면 배율이 떨어져 유닛이 잘게 보인다) `stage_rect()`(벨트 + 배경 지형) 밖은 절대 비추지 않는다. 실측(헤드리스 5v5 ×8, engage:3): **13.3초 · 처치 1.0건** — ATB 시절(9초에 처치 2.75건)보다 훨씬 온건하다. 자세한 내용과 튜닝 상수는 `engage/README.md`. |
| 전투 개시 확인 화면 (VS) | **참가자 명단은 카드를 제출한 순간에 뜬다**(`engage/EngageIntro.gd`). 딤드된 전체 화면 위에 **상단 = 적군 / 중앙 = VS + N라운드 / 하단 = 아군** 으로 eye 초상화가 가로로 깔리고, 초상화 아래마다 체력 바 + `hp / max` 숫자가 붙는다(전장 스트립 `ui/PilotStrip.gd` 와 같은 eye 크롭 · 같은 보호막 색 규칙). 아군 줄 아래에 **취소 / 확인**. **취소는 카드 제출 자체를 무른다** — `CardPhaseManager._effect_engage` 가 `_on_overlay_cancel()` 로 `_play_card_direct` 의 스냅샷(손패 / 덱 / 비용 / engage 할인 / 보존 목록)을 통째로 복원하므로 버리기·찾기 취소와 완전히 같은 경로다(실측: 손패 5→4→**5**, 점수 99→93→**99**, `cards_played_this_phase` 0 유지). **AI 가 낸 카드에는 확인만 뜬다** — 플레이어가 무를 수 있는 것이 아니다. 이 화면이 떠 있는 동안 `game_phase` 는 아직 CARD_PHASE(AI 턴이면 BATTLE)라 아레나는 열리지 않았고, 그래서 손패 딤 · 턴 넘기기 · 더미 열람 · 도넛 플립이 페이즈가 아니라 `EngagePhaseManager.is_intro_active()` 를 따로 읽는다. **예전에는 이 명단이 카드를 고르는 순간 화면 좌/우에 뜨는 세로 팀 패널 두 개였다** — 아직 낼지도 정하지 않은 카드에 화면 절반이 덮였고, 나란히 선 목록 둘은 어느 쪽이 내 팀인지를 위치로 말해 주지 못했다. `CardTargetingOverlay` 의 PREVIEW 모드 자체는 남아 있다(끄는 동안 시전자 셀 + 인접 6칸이 밝아지고 참가자가 강조된다). |
| 작전 단계 (CARD_PHASE) | Triggered at `player_cost ≥ PHASE_THRESHOLD`. 작전 점수 read out on the 전략 포인트 donut gauges — **둘 다 화면 좌측 거터**(player: 핸드 행 좌측 상단 = Deck 카운터 위; enemy: 좌측 상단 = 상대 핸드 peek 아래). Tapping the player donut flips it into a circular 턴 넘기기 button — **카드를 한 장도 내지 않아도 언제든 넘길 수 있다**(잠기는 것은 배너 / 모달 / 돌진 연출처럼 지금 닫으면 무언가가 끊기는 상태뿐). 규칙은 두 번 바뀌었다: "작전 점수를 1 이상 써야 한다" → 28장 중 9장이 0코스트라 무료 카드만 있는 손은 점수가 줄지 않아 턴을 영영 못 넘겼고, 그래서 "카드를 한 장 이상 낼 것"(`cards_played_this_phase`)이 됐다가, 지금은 그 마저도 없앴다 — 점수는 문턱 위인데 손에 낼 게 없는 상황이 흔하고, 강제하면 아무 카드나 버리듯 내게 되기 때문이다. `cards_played_this_phase` 와 `_has_any_playable_card()` 는 함께 **삭제됐다**. Tapping elsewhere flips it back. |
| 턴 넘기기의 대가 (초과분 소멸 · 패스 잠금) | 카드를 안 내고도 넘길 수 있는 대신 세 규칙이 붙는다(양 팀 동일). (1) **문턱 초과 소멸** — 차례를 놓는 순간 점수는 정확히 `PHASE_THRESHOLD`(8)로 깎인다(`end_card_phase` / `_run_ai_turn` 말미, 소멸량은 로그에 남는다). (2) **문턱 위에서는 회복 정지** — `COST_RECOVERY` 는 자기 점수가 문턱 **미만인 쪽에만** 들어간다(`do_battle_turn`). 둘이 합쳐 전략 점수의 실질 상한이 문턱이 되고, 카드 효과(아드레날린)로 그 위에 올라간 점수도 차례를 넘기면 깎인다. (3) **패스 잠금**(`CardPhaseManager._player_pass_lock`) — 넘긴 직후에도 점수는 문턱에 걸려 있으므로 그대로 두면 **다음 틱(0.5초)에 내 차례가 다시 열린다**. 그래서 넘긴 쪽은 **자동 드로우로 손패가 바뀌거나 상대가 한 번 차례를 가질 때까지** `_next_turn_side()` 에서 준비되지 않은 것으로 친다. 그 사이 BATTLE 은 평소대로 흐른다. |
| 카드 드래그 = 대상 지정 | **카드를 끌어내는 순간이 곧 대상 지정 단계다** — 클릭만으로는 아무 일도 일어나지 않는다(아래 '카드 드래그 앤 드롭' 항목). 설명 상자의 "카드 내기" 버튼도, 화면 우하단의 확인 / 취소 버튼도 없다 — **카드를 내는 조작은 끌어다 놓기 하나뿐**이고, 카드가 손을 떠나는 즉시 **놓을 수 없는 곳이 전부 딤드**된다. 딤 규칙은 모드가 가른다: **PILOT 은 타일을 전부 딤드하고**(타일은 대상이 아니다) 유효 대상 파일럿만 **1.5배로 커진 채**(`BattleRenderer.TARGET_EMPHASIS_SCALE`, 예전 2.0 에서 낮췄다 — 2배는 무리를 화면 밖까지 밀어내고 얼굴이 옆 레인을 침범했다) 밝게 남기며 나머지 파일럿은 딤드한다. **커지는 것은 초상만이 아니라 배치도다** — 한 칸에 두세 명이 서 있으면 커진 얼굴이 서로를 덮어 겨눌 수 없으므로, `_build_pilot_render_layout` 이 그 칸 육각 링의 **반지름**을 같은 배율로 벌린다 — 링 정의(`지름 + 여백`)가 곧 비겹침 조건이라 배율을 곱해도 조건이 유지되고, 타일에서 물러난 만큼 화살표가 길어진다. **슬롯 배정 자체는 강조를 보지 않는다**(겹침 판정은 강조 이전 좌표로 돌린다) — 강조까지 반영하면 카드를 집을 때마다 전장의 슬롯이 새로 풀려 배치가 통째로 다시 섞인 것처럼 보인다. 벌어진 무리가 화면 밖으로 나가면 `_clamp_group_on_screen` 이 칸째 평행 이동해 화면 안에 넣는다. 히트 반경도 `BattleRenderer.pilot_marker_radius(p)` 에서 받아 커진 얼굴 테두리까지 잡힌다. **확대·축소는 즉시 튀지 않고 `BattleRenderer.EMPHASIS_TWEEN_SEC`(**0.05초**) 동안 보간된다** — 한 프레임 만에 얼굴 서넛이 부풀고 무리가 벌어지면 무엇이 대상인지보다 화면이 흔들렸다는 인상이 먼저 온다. 예전 0.15초는 그 인상은 지웠지만 카드를 든 손이 이미 대상 위에 가 있는데 얼굴이 아직 자라는 중인 구간을 남겼다 — 강조는 겨누기 **전에** 끝나 있어야 하는 신호다. 목표값(`_pilot_emphasis_target`)과 지금 값(`_pilot_emphasis_scale`)이 갈라져 있고, 그리기·배치·히트 반경이 전부 후자 한 곳을 읽으므로 보간 중에도 셋이 어긋나지 않는다. 도달하면 미동도 없다 — 예전의 펄스와는 다른 것이다. **LOCATION 은 유효 셀만 초록으로 남기고** 나머지 셀과 **파일럿 전원**을 딤드한다(사거리 노란 채움과 `range_unlimited` 특례는 삭제 — 사거리가 무제한이어도 갈 수 있는 칸만 밝다). **단 시전자는 어느 모드에서도 딤드되지 않는다**(`CardTargetingOverlay.card_caster`) — 카드를 쏘는 당사자에게 "여기엔 놓을 수 없다"는 말은 성립하지 않는다. 대신 강조 대상도 아니어서, 시전자가 자기 카드의 유효 대상일 때(보호 / 복귀 같은 `target=ally`)만 커진다. **확정 전까지 비용도 빠지지 않고 카드도 핸드에 남으므로 되돌릴 것이 없다** — **드래그를 빗나가게 놓으면 카드가 제자리로 돌아가고 오버레이가 꺼진다.** 대상 지정 상태는 드래그와 정확히 같은 수명을 가지므로 '탈출' 이라는 개념 자체가 없다(손을 떼면 끝난다). 모달이 아니라서 턴 넘기기는 계속 살아 있다. **오버레이는 이제 노드를 하나도 소유하지 않는다** — PREVIEW 의 좌/우 팀 패널이 제출 후 VS 화면으로 옮겨 가면서 그 CanvasLayer 도 사라졌다. |
| 카드 드래그 앤 드롭 | **카드를 끌어다 놓는 것이 카드를 집는 유일한 조작이다.** **카드 선택 상태는 삭제됐다** — 클릭해도 아무 일도 일어나지 않고, 누른 채 `DRAG_THRESHOLD_PX`(10px) 넘게 움직여야 비로소 카드가 손을 떠난다. 예전에는 클릭하면 카드가 리프트된 채 대상 지정이 켜져 남아, 다시 끌거나 다른 곳을 눌러 해제해야 했다 — 조작이 둘로 갈려 있었고(클릭→끌기 / 클릭→클릭 해제) 카드를 낼 수 있는 경로는 어차피 드롭 하나뿐이라 중간 상태가 하는 일이 없었다. `_selected_card` / `_select_card` / `Card.is_selected` / `Card.card_clicked` / 바깥 클릭 해제가 전부 그때 사라졌고, `deselect_current_card()` 는 이름만 남아 '진행 중인 드래그와 대상 지정을 강제로 걷는다' 를 뜻한다. **끌린 카드의 자세는 대상 유무가 가른다.** (1) **대상 지정 카드(PILOT / LOCATION)는 손패에 남는다** — 리프트 자세(`Card.PRESS_LIFT`) 그대로 부채꼴 기울기를 유지하고, 카드 **위쪽 끝에서 커서까지 2차 베지어 조준 화살표**(`card_phase/CardDragArrow.gd`)가 이어진다. 카드가 커서에 붙어 날아다니면 겨누려는 대상(커진 초상 / 초록 유효 셀)을 카드가 자기 몸으로 덮어 정작 놓는 순간에 무엇 위인지가 안 보인다. 화살표 노드는 `_bs.canvas` 의 **자식 인덱스 0**(카드보다 뒤)이고 시작점을 `ARROW_TUCK_PX`(42px)만큼 카드 안으로 파묻어 두므로 화살이 카드 **밑에서** 뻗어 나온 것처럼 읽힌다. 제어점은 **카드 자신의 위쪽 축** 위라 기울어 있는 카드는 그 기울기대로 쏘고, 커서가 카드보다 아래면 `BOW_MIN` 으로 잘려 고리를 만들지 않는다. 색은 지금 놓으면 나가는지를 말한다 — 평소 금색, 유효 대상/셀 위에서 시안. (2) **대상이 없는 카드는 커서를 따라다닌다**(`Card.follow_cursor`) — 겨눌 대상이 없으니 가릴 것도 없고, `Card.begin_free_drag()` 이 부채꼴 기울기를 `FREE_DRAG_STRAIGHTEN_SEC`(0.10초) 동안 0 으로 펴서 '손에서 뽑아 든' 자세를 만든다. 이 카드에는 화살표 대신 드롭 존이 신호다. **원래 자리는 어느 쪽이든 빈 채로 유지된다** — `relayout_hand` 이 `is_dragging` 카드를 건너뛰므로 남은 카드는 자리를 지키고, 빗나간 드롭은 그 자리로 오차 0.00px 로 돌아온다. 놓는 곳이 곧 무엇을 하는가다: **대상 지정 카드는 대상 위에**(커진 파일럿 초상 / 초록 유효 셀), **대상이 없는 카드는 화면 중앙 드롭 존**(`CardPhaseManager.drop_zone_rect` — 세로 중앙 기준 화면 높이의 40%, 가로 전체), **버리기:N 픽 중에는 중앙 버리기 구역**(같은 함수가 `CardSelectOverlay.TO_DISCARD_CENTER_Y` 700 을 중심으로 `DISCARD_ZONE_H` 440px 띠를 돌려준다 — 그때는 구역 노드를 캔버스 자식 인덱스 **1** 로 올린다. 0 은 버리기 딤이 차지하고 있어 그대로 두면 구역이 딤 아래로 눌린다). **빗나가면 카드가 제자리로 돌아갈 뿐 비용도 카드도 그대로다.** 확정은 `CardTargetingOverlay.confirm_with` → `_on_selection_confirm` 한 경로뿐이라 비용 차감 / 카드 소비 / effect chain 이 두 벌 생기지 않는다(`_end_drag` 은 그 콜백이 동기적으로 되돌아올 때까지 `_drag_card` 를 살려 둔다). 입력은 전부 `HandHitLayer` 하나가 받는다 — 버튼을 쥔 컨트롤이 마우스 포커스를 유지하므로 커서가 전장으로 나가도 motion/release 가 계속 들어오고, 전장 쪽에는 드래그 배선이 없다. |
| 드로우 연출 (카드가 손패에 들어오는 길) | 뽑힌 카드는 자기 슬롯에 그냥 나타나지 않는다 — **먼저 덱 뭉치에서 카드 한 장이 떠오르며 사라지고**(`CardPileStack.play_pop`, 위 "뭉치를 오가는 카드" 항목 — 알파가 30% 남은 0.182초 시점에 아래 박자가 이어받는다), **뒷면인 채로 화면 왼쪽 바깥에서 나타나**(`_draw_entry_position`) **손패 오른쪽 끝(새 카드가 앉을 자리) 위로 날아가고**(`DRAW_FLY_SEC` 0.28초, `EASE_IN_OUT`/`SINE` — 앞이 무거운 감속 곡선은 1200px 를 0.1초에 77% 지나가 "왼쪽에서 왔다"가 안 읽혔다), **그 자리에서 뒤집혀**(`Card.play_flip_reveal`, `FLIP_HALF_SEC` 0.09초 ×2, `scale.x` 를 0 까지 접었다 펴며 폭이 0 인 프레임에 앞/뒷면 교체) **슬롯에 안착한다**(`relayout_hand`). 뒤집는 지점은 슬롯보다 `DRAW_FLIP_LIFT_PX`(78px) 위다 — 행 안에서 뒤집으면 이웃 카드가 절반을 가리고 안착이 눈에 보이는 동작으로 남지 않는다. 연출이 도는 동안 `Card.intro_active` 가 그 카드를 손패의 일원에서 빼므로 **레이아웃 · 호버 · 잡기가 전부 비켜 간다**(나머지 손패는 이미 새 카드 몫까지 자리를 좁힌 채 기다린다). 비행은 `Card.tween_to`(= `_active_tween`)를 쓴다 — 카드 자신이 쥔 트윈이라야 버리기 연출이 걷어 낼 수 있고, 상한 초과 정리는 **가장 오래된 카드**(= 아직 날아오는 중일 수 있는 카드)를 버린다. 같은 프레임에 여러 장이면 `DRAW_STAGGER_SEC`(0.07초)씩 밀려 출발한다. 각 박자는 트윈의 `finished` 가 아니라 타이머로 기다린다 — 카드가 도중에 free 되면 그 신호는 영영 오지 않는다. **인트로를 끄는 두 자리**: 정밀 이동의 손패 왼쪽 복귀(`at_left`, 방향이 어긋난다)와 `_restore_from_snapshot`(취소 롤백이 새 손패처럼 보인다). |
| 버리기 연출 | 손패를 떠나 버려지는 카드는 **부채꼴 기울기와 무관하게 화면 Y축으로만** 곧장 내려가며 투명해지고 (`Card.DISCARD_DROP_PX` **150px** / `DISCARD_FADE_SEC` 0.30초 — 화면 아래로 멀리 빠져나가기보다 손패 바로 밑에서 사라지는 쪽이 "버렸다"로 읽힌다. **낙하 곡선은 `EASE_OUT`** — 손을 떠나는 순간 확 튕겨 내려간 뒤 아래에서 서서히 멎는다. 예전 `EASE_IN` 은 떨어져 나가는 순간이 가장 흐릿하고 다 사라질 때 제일 빨라 무게가 끝에 실렸다) 다 내려가면 스스로 `queue_free` 한다. **그 낙하가 끝난 뒤에야 버린 더미가 카드를 받는다** — `CardPileStack.play_land` 가 `PILE_LAND_DELAY_SEC`(= `Card.DISCARD_FADE_SEC` 0.30초) 뒤에 시작해 두 연출이 겹치지 않고 이어 붙고(예전 0.16초는 카드가 아직 떨어지는 중에 더미가 먼저 받아 같은 카드가 두 군데에 있었다), **장수와 뭉치 두께는 그 착지 잔상이 다 내려앉은 뒤에 오른다**(`CardPhaseManager._discard_pending` / `_commit_discard_gain` — 표시값은 언제나 `배열 크기 − pending`). 델타 0 인 단순 갱신은 정산을 건드리지 않는다 — 거기서 pending 을 밀면 갱신 한 번에 지연이 통째로 날아간다 — 리프트(`PRESS_LIFT`)가 카드 자신의 up 축을 타는 것과 반대다(버려지는 카드는 뽑히는 게 아니라 떨어지는 것이라, 기울기를 타면 기울어진 카드만 옆으로 새 나간다). 진입점은 `CardPhaseManager.play_discard_fx(node)` 하나이고 **노드는 부르기 전에 이미 `player_card_nodes` 에서 빠져 있어야 한다** — 0.3초 동안 레이아웃 · 호버 · 히트 밴드가 그 카드를 손패로 세면 남은 카드들이 빈자리를 메우지 못한다. 진행 중이던 레이아웃 / 호버 / 그림자 / 뒤집기 트윈은 전부 kill 하고 시작한다. **버리기:N 으로 화면 중앙에 늘어세운 카드들도 확정 시 같은 연출로 내려간다**(`CardSelectOverlay._commit_discard` 가 `to_discard_nodes` 를 목록에서 먼저 떼어 낸 뒤 넘긴다 — 안 그러면 `_teardown` 이 그 자리에서 free 한다). **취소는 예외** — 버려지지 않은 카드가 떨어질 이유가 없으므로 즉시 free 하고 스냅샷이 손패를 다시 세운다. |
| 카드 설명 상자 | **화면 상단 고정**(`DESC_BOX_TOP` 142, 640×150, 가로 가운데) — 상단 패널(아래끝 130)과 전장(위끝 369) 사이의 빈 띠다. 예전에는 든 카드 좌/우 옆에 붙었는데, 드래그가 들어오면서 상자가 커서 앞을 가로막았다. **가리키기만 해도 뜬다** — 보여 줄 카드는 손패 포커스와 같은 질문이라 `_push_focus_card()`(끌고 있는 카드 > 호버) 하나가 답한다. **버튼은 하나도 없다** — 카드를 내는 것도 드롭이고 버리기:N 픽도 드롭이라, 예전의 "카드 내기" 버튼과 "버리기" 버튼이 둘 다 사라졌다. 상자는 `MOUSE_FILTER_IGNORE` 라 그 위를 지나는 드래그를 막지 않는다. |
| 공격 카드 명중 판정 | `attack:N` 카드도 전장과 **같은 명중 판정**을 굴린다 — `SimulationCore.roll_hit` (`hit/(hit+evasion)`). 빗나가면 데미지가 0이고 로그에 "빗나감"이 남는다. `pierce`(필중)는 판정을 건너뛰고, `repeat`(연속 공격)은 **명중할 때마다** 같은 공격을 다시 굴려 빗나가거나 대상이 쓰러질 때까지 이어진다 — 무한 루프 방지 상한은 `CardPhaseManager.MAX_ATTACK_REPEATS`(5타). **타격마다 돌진 연출이 붙고 `_effect_attack` 이 그것을 `await` 한다** — 아래 "공격 돌진 연출" 항목. |
| 전장 초상화 배치 (육각 6슬롯) | 초상화는 타일을 **둘러싼 육각 링**에 앉는다 — 6방향(N/NE/SE/S/SW/NW) × 3겹(반지름 91 / 182 / 273px)이고, 이웃 슬롯이 60° 간격이라 반지름 d 인 링에서 이웃 사이 거리가 정확히 d 여서 `지름 + 여백`을 그대로 반지름으로 쓰면 한 링 안에서 얼굴이 절대 닿지 않는다. **기본 방향은 이동 방향의 정반대**(가려는 쪽을 비우고 지나온 쪽에 선다): 오른쪽 레인을 NE 로 올라가는 팀0 은 왼쪽 아래(SW), 같은 구간을 내려오는 팀1 은 오른쪽 위(NE), 미드는 예전 그대로 팀0 아래 / 팀1 위, 왼쪽 레인은 오른쪽 레인의 좌우 반전이 저절로 나온다. 방향의 출처는 **레인 파일럿 = 레인 경로**(다음 웨이포인트 방향을 6방향으로 스냅 — 교전으로 멈추거나 밀려나도 표시가 뒤집히지 않는다), **정글러 = `PilotData.prev_grid_pos`**(직전 칸에서 온 방향; 왼쪽 위로 왔으면 오른쪽 아래에 선다). 자리는 기본 방향에서 **시계방향으로** 돌며 (a) 같은 칸에서 안 쓴 자리이고 (b) **이미 놓인 어떤 마커와도 겹치지 않는** 첫 자리를 잡고, 6자리를 다 쓰면 바깥 링으로 나간다 — 멀어진 만큼 화살표가 길어져 어느 칸인지가 계속 읽힌다(화살표 끝은 마커 반지름이 아니라 **거리에서 역산**해 언제나 타일 중심 바로 앞에 닿는다). (b)가 다른 칸의 마커까지 본다는 것이 요점이다: 이웃 타일 중심은 140px 인데 초상화 지름이 85px 라, 위아래로 붙은 두 칸이 서로를 향한 슬롯을 고르면 두 얼굴이 정면으로 겹쳤다 — 전장에서 얼굴이 가려지는 유일한 구조적 원인이었고 지금은 뒤에 오는 칸이 한 칸 비껴 앉는다. **한 칸의 6슬롯은 양 팀이 공유한다**(예전의 "적 위 / 아군 아래"는 팀마다 따로 풀어도 부딪히지 않았지만, 방향이 각자의 이동에서 나오는 지금은 같은 슬롯을 노릴 수 있다). 배정은 전장 전체를 좌표순으로 훑는 그리디라 **한 칸만 따로 풀면 같은 답이 안 나온다** — `pilot_marker_positions()` 표 하나가 유일한 답이다. `+N` 오버플로 원은 삭제됐다(전원이 자기 슬롯을 받는다). **이동 중에는 화살표가 크기도 방향도 바꾸지 않는다** — `_render_cell` 이 이동이 시작된 프레임부터 곧장 도착 칸을 돌려주므로 예전에는 꼬리가 초상보다 먼저 목적지를 가리키며 0.3초 내내 회전하고 늘어났다(실측: 91px → 182px). 지금은 `BattleRenderer._arrow_aim_point` 가 직전 프레임의 화살표 벡터를 붙들어 초상에 강체로 매달고, **도착한 뒤** `ARROW_SETTLE_SEC`(0.15초) 동안 회전 + 신축(각도·길이를 따로 보간)으로 제 타일을 다시 가리킨다. 슬롯 방향이 그대로면 붙든 값과 참값이 같아 정착 구간이 아예 무동작이다. |
| 한 셀에 여러 명일 때 대상 지정 | PILOT 히트 테스트는 `grid_pos` 가 아니라 **실제로 그려진 마커 위치**(`BattleRenderer.pilot_marker_positions()`, `_draw()` 와 같은 solve)를 본다. 예전엔 타일 중심 / `pilot_marker_pos_solo` 로 재서 같은 셀의 파일럿이 전부 같은 좌표를 갖는 바람에 어느 얼굴을 눌러도 **맨 왼쪽 파일럿**이 잡혔다. 마커에 안 맞은 클릭은 자기 타일 안이면 여전히 잡히되 마커 거리 순으로 정렬된다. |
| 핸드 상한 10장 | `MAX_HAND_SIZE` = 10. **내 차례가 아닐 때**(작전 점수가 다시 차오르는 동안) 도는 자동 드로우는 핸드가 꽉 차 있어도 무조건 뽑고, 넘친 만큼 **가장 오래된** 카드부터 discard 로 보낸다(양 팀 동일) — 단 **계획 중시로 보존된 카드는 건너뛴다**. 예전처럼 드로우를 건너뛰면 덱이 돌지 않아 손이 그대로 굳어 있었다. 반면 **내 턴에 카드 효과로 뽑은 카드는 상한을 넘겨도 버리지 않는다** — 턴이 끝난 뒤 첫 자동 드로우가 정리한다. 덱이 비면 discard 전체를 되섞어 덱으로 되돌리는 건 기존과 동일(`draw_card`). |
| 카드 시전자 제약 (`scope`) | `cards.csv` 의 `scope` 가 카드를 가질 수 있는 파일럿을 정한다 — `lane`(전진 등)은 **레인 파일럿만**, `jungle`(약탈 · 정글 파밍 · 전투 준비 · 정밀 이동)은 **정글러만**, `any` 는 제약 없음. 판정은 **스타터 덱을 돌릴 때 한 번**만 한다(`CardPhaseManager._pool_for_pilot`): 시전자는 배분 후 바뀌지 않으므로, 사용 시점에 막으면 쓸 수 없는 카드가 손패에 영영 잠긴 채 남는다. 알 수 없는 `scope` 값은 제약 없음으로 읽어 CSV 오타가 카드를 통째로 지우지 않게 한다. **파급**: 전투 준비 / 정밀 이동이 정글 전용이 되면서 **레인 파일럿은 이동 카드를 전혀 갖지 못한다**(위치 조작은 전진뿐). `RecallSystem._is_out_of_position` 은 이제 발동할 수 없는 경로지만 향후 레인 이동 카드 자리로 남겨 둔다. |
| 카드 종류 / 덱 슬롯 (`card_type` · `card_cat`) | `scope` 가 **누가 가질 수 있는가**를 정한다면 이 둘은 **어느 슬롯을 채우는가**를 정한다. `card_type` = `mech` / `pilot`, `card_cat` = `-` / `lane` / `draw` / `jungle` / `common`. 파일럿마다 **메크 3장 + 파일럿 3장**을 받고, 파일럿 3장의 내역은 역할이 가른다 — **정글러** `jungle` 2 + `draw` 1, **서포터** `lane` 1 + `draw` 2, **나머지 3인** `lane` 2 + `draw` 1. 각 슬롯은 **중복 없이** 뽑는다(라인전 풀이 3종인데 2장을 요구하므로 중복 허용이면 같은 카드 두 장이 더 흔했다); 풀이 모자랄 때만 중복으로 폴백한다. `card_cat = common` 은 **라인전 슬롯과 정글 슬롯 양쪽 후보**이며 지금은 **복귀** 하나뿐이다 — 라인전 카드이면서 정글러의 유일한 HP 회복 수단이라 어느 한쪽에만 두면 한쪽이 굶는다. 덱 크기는 그대로 5명 × 6장 = 30장. |
| 10턴 경제 게이트 (`ECONOMY_START_TURN`) | 전략 점수 회복과 자동 드로우는 **10턴부터** 돈다(`CardPhaseManager.do_battle_turn`). 그 전에는 두 카운터를 아예 굴리지 않아 게이트가 열릴 때 밀린 회복이 몰려 터지지도 않는다. 개시 손패가 없어졌으므로 **0턴에 들어가는 것은 블루 선점 1점뿐**이고, 1~9턴은 양 팀 다 손패 0장 · 점수 고정(블루 1 / 레드 0)인 순수 라인전 구간이다. **성장은 게이트를 타지 않는다**(1턴부터). 실측: 회복·드로우가 10·12·14·16·18·20·22턴에 7회씩 들어가 첫 작전 단계가 **22턴 · 손패 7장**(player 8 / ai 7) — 4턴 게이트 시절 16턴, 게이트 이전 13턴. `match_ctx` 없이 BattleSim.tscn 을 직접 돌리면 HQ 가 20턴께 무너져 **첫 작전 단계에 닿기도 전에 판이 끝난다**. |
| 성장 (인게임 누적) | 살아 있는 파일럿의 `atk` / `max_hp` 가 매 턴 `GROWTH_PER_TURN`(game_config, 0.01 = +1%p) 만큼 원본 대비 늘어난다(`SimulationCore.tick_growth_and_expiries`, 턴 루프의 **맨 앞**). 스탯은 매 턴 곱해 나가는 대신 `PilotData.base_atk` / `base_max_hp` 에서 **다시 계산**한다 — 매 턴 반올림이 끼면 오차가 누적돼 실제 성장률을 갉아먹는다. 최대 체력 증가분만큼 현재 체력도 함께 오른다. **죽어 있는 동안은 성장이 멈추지만 누적치는 남는다** — 부활하면 죽기 전 성장을 들고 돌아온다. 획득 배율(`growth_rate_mult`)은 **안전한 파밍**(+10%, 턴 만료)과 **완벽한 마무리**(+25%, 다음 작전 단계까지, 팀 전원)가 건드리며 같은 필드라 나중에 건 쪽이 덮어쓴다. |
| 성장치 (파일럿 점수) | 파일럿마다 **개시 1.00k** 에서 시작해 경기 내내 누적되는 종합 기여 지표(`PilotData.score`). **바로 위의 성장(`growth`)과는 다른 것이다** — 성장은 스탯을 밀어 올리는 배율, 성장치는 스탯에 아무 영향이 없는 기록이다. 적립: **적 처치 +0.20k / 사망 −0.10k(하한 `SCORE_MIN` 0.10k) / 적에게 준 피해 100당 +0.01k / 포탑 피해 100당 +0.02k / 포탑 파괴 +0.15k / HQ 피해 100당 +0.03k**. 상수는 `BattleSim` 의 `SCORE_*` 절에 모여 있고 모든 변동은 `BattleSim.add_score` 한 곳을 지난다(하한을 한 자리에서만 지키기 위해). 표시는 `fmt_score` → `"1.00k"` 이고 상한이 없으므로 **게이지가 아니라 숫자**다. 팀 점수(`team_score`)는 팀원 합산이라 개시값이 `5.00k - 5.00k` 이며 죽어 있는 파일럿도 포함한다. **처치 귀속의 배선**: 전장 피해는 판정 단계(`damage_map` 에 양만 쌓기)와 적용 단계(HP 깎기)로 갈라져 있어 적용 시점에는 공격자가 남아 있지 않다 — 그래서 `SimulationCore._credit_pilot_damage` / `_credit_turret_damage` 가 "마지막으로 때린 자"를 `_last_hitter` / `_last_turret_hitter` 에 적어 두고 적용 단계가 `mark_pilot_dead(victim, killer)` / `score_turret_kill` 에 넘긴다. 두 dict 는 **매 턴과 매 전진 카드 시작 시 비운다** — 턴을 넘겨 살아남으면 엉뚱한 사람에게 처치가 붙는다. 교전 무대와 공격 카드는 공격자를 손에 들고 있어 이 우회가 필요 없다. |
| 파일럿 표시 (스트립 ×2) | 파일럿 다섯 명이 **눈높이 초상화 → 체력 바 → 성장치 숫자** 세 줄로 한 칸을 이루고, 다섯 칸이 가로로 나란히 선다(`ui/PilotStrip.gd`). **적 팀은 화면 최상단**(상단 패널의 자식, `ENEMY_STRIP_RECT` 175,42,730×84), **아군은 핸드 행보다 아래**(`PLAYER_STRIP_RECT` 25,1766,1030×122)다 — 예전에는 열 명이 전부 상단 패널 양옆에 84px 정사각 슬롯으로 몰려 있어 누가 누구인지도, 어느 쪽이 내 팀인지도 읽히지 않았다. 초상화는 `PilotImages.eye_for` = **`eye/N_eye.png`(480×200, 양 눈이 보이게 가로로 자른 밴드)**이고 칸 높이는 그 비율(`EYE_ASPECT` 2.4)에서 유도한다 — 임의 높이로 늘리면 얼굴이 찌그러진다. 체력 바는 **`ColorRect` 두 장**이다: `ProgressBar` 는 테마 컨텐트 마진에서 최소 크기를 계산해 `size` 를 24px 안팎까지 끌어올리므로 6~10px 바를 요청해도 아래의 성장치 라벨을 덮어썼다(실측 확인). 보호막이 있으면 채움이 노란색이 된다(바를 이어 붙이지 않는 이유는 얇아서 두 구간이 구분되지 않아서다). 쓰러진 파일럿은 초상화가 어두워지고 **부활까지 남은 턴 수**가 한가운데 크게 찍힌다. 하단 스트립의 y(1766)는 **카드 밑단에서 계산해 나온 값**이다 — 부채꼴 양 끝 카드가 가운데보다 21.4px 처지고 호버 시 1.2배로 커져 최악 y≈1763 까지 내려왔었다(핸드 행이 1500 이던 시절). 핸드가 1440 으로 올라간 지금은 최악이 y≈1703 이라 여유가 63px 로 늘었지만, 스트립은 화면 바닥(1888)에 붙어 있어 더 내릴 자리가 없으므로 그대로 둔다. 정렬은 `_bs.pilots` 의 **사본**에 한다 — 원본은 스폰 순서(= 역할 순서)를 유지해야 `BattleSim.player_data_for` 가 그 인덱스로 로스터를 찾을 수 있다. |
| 파일럿 상세 패널 | **자기 작전 단계에** 스트립의 얼굴을 누르면 열리는 모달(`ui/PilotDetailPanel.gd`, 자기 `CanvasLayer` 13 — 버리기 10 / 대상 지정 11 / 열람·교전 12 위). **아군 하단 스트립과 적 상단 스트립 양쪽 다 눌린다** — 적도 같은 게이트에 같은 내용으로 열리며, 상대 로스터는 이미 `match_ctx.enemy_roster` 로 들어와 있어 `BattleSim.player_data_for` 가 인덱스 5..9 로 그대로 찾아 준다. 화면이 검정 α 0.88 로 딤드되고 **누른 쪽 팀의 스트립만 숨겨진다**(딤 위에 남으면 지금 무엇을 보는지 흐려지고, 딤 아래에 두면 방금 누른 얼굴이 어두워진다. 반대 팀은 딤에 가려질 뿐이므로 그대로 둔다). **좌측에는 전신 아트가 두 장** 겹쳐 서고(파일럿 / 메크), 우측에 **앞에 선 쪽의** 스탯이 온다 — 파일럿이면 **인게임**(체력 / 공격력+기본 / 성장 / 명중·회피 / 보호막 / 라인, 사망 시 부활 턴) + **파일럿**(라인전 · 메카닉 · 게임센스 · 한타 · 멘탈 = `PlayerData`), 메크면 **메크**(기체명 / 체력 / 공격력 / 존재감). 하단에 **전환**(정보 블록 왼쪽 아래) · **닫기**. 값 라벨에는 **`clip_text = true` 가 필수** — 오른쪽 정렬 `Label` 은 글자가 rect 보다 넓으면 정렬을 포기하고 rect 왼쪽부터 그려 **오른쪽으로 넘쳐 화면을 벗어난다**(실측 확인). 작전 단계를 벗어나면 `close_if_phase_left()` 가 강제로 닫는다 — 열어 둔 채 BATTLE 이 흐르면 딤 뒤에서 전장이 굴러간다. |
| 상세 패널의 아트 2장 (파일럿 ↔ 메크) | 앞자리와 뒷자리를 두 아트가 나눠 갖는다. **앞** = 밝게, 가로 중심 `ART_FRONT_CENTER_X`(320). **뒤** = `ART_BACK_SHIFT_PX`(400px) 오른쪽으로 밀리고 `ART_BACK_SCALE`(0.90)로 작아지고 `ART_BACK_TINT`(검정 반투명)로 딤드 — "약간 오른쪽에 반쯤 겹쳐 뒤에 선" 자세다. **전환 버튼이 둘을 맞바꾼다**(`ART_SWAP_SEC` 0.22초 트윈; 자리 · 딤 · z-order · 우측 스탯이 한꺼번에 바뀐다). **아트는 화면 하단이 자른다** — 아래끝(`ART_BOTTOM` 2010)이 화면(1920) 밖이라 다리 아랫부분이 잘려 나가고, 예전의 무릎 크롭(`_knee_crop` / `KNEE_FRACTION`, 알파 실루엣 높이의 80% 지점에서 `AtlasTexture.region` 으로 텍스처를 자르던 것)은 **삭제됐다**. **크기는 높이(`ART_H` 1400)로 정규화한다** — 전신 아트는 전부 세로 1024 에 인물이 꽉 차 있고 가로만 572~756 이라 폭으로 맞추면 인물 키가 제각각이 된다. 뒤로 물러날 때 노드 크기는 그대로 두고 **`scale` 만** 줄인다: `pivot_offset` 이 **아래 가운데**라 작아져도 바닥선이 그대로여서 둘이 같은 바닥에 선 것처럼 읽힌다. **메크 아트는 30칸이 전부 채워져 있다** — `MechImages.full_for(mech.id)` 가 `res://resources/images/mech/{id}_full.png` 를 찾는다(없으면 `ResourceLoader.exists` 로 조용히 null → 옅은 α 0.30 실루엣 슬래브 + 기체명 플레이스홀더). 파일럿 아트는 세로 1024 에 폭이 572~756 으로 제각각이지만 **메크 아트는 1024×1024 고정 캔버스**다 — 기체 렌더는 검·날개가 옆으로 뻗어 바운딩 박스 비율이 1.5 까지 가고, 높이 정규화가 그 폭을 그대로 환산하면 화면 폭의 두 배로 벌어지기 때문. 그래서 크기도 바운딩 박스가 아니라 **불투명 픽셀 면적**으로 맞춰 본체 겉보기 크기를 고르게 했다. 출처(Gundam Evolution 기체 렌더 24종)와 id ↔ 기체 대응표는 `resources/README.md`. **정보 블록은 아래로 내려왔다**(`STAT_TOP` 170 → 640) — 아트가 커지며 화면 위쪽 절반이 인물의 머리·상체 자리가 됐기 때문이고, 글자 뒤에는 받침 `Panel`(α 0.86)이 내용 높이에 맞춰 깔린다. 버튼 행의 y 는 **고정**이다(받침 높이를 따라가면 메크 쪽 스탯이 짧아 버튼이 위아래로 튄다). |
| 라인전 스탯 | **`hit` / `evasion` 전용** 배율(±10%)이며 `SimulationCore.roll_hit` **한 곳에서만** 곱해진다 — 공격자의 `hit` 과 방어자의 `evasion` 에 각자 자기 배율이 붙는다. `atk` / `max_hp` 는 성장이 담당하므로 여기서 건드리지 않는다. `roll_hit` 은 전장 자동 교전과 공격 카드가 공유하므로 둘 다 반영되고, **교전 무대는 자기 확률 구간(80~100%)을 쓰므로 반영되지 않는다**. 같은 파일럿에 두 번 걸면 **덮어쓴다**(합산 아님) — 3종 풀에서 2장 뽑는 구조상 합산을 허용하면 +20~30% 가 그냥 운으로 굴러 나온다. **공격적인 라인전**(+10%) / **안전한 파밍**(−10%, 대신 성장 +10%). |
| 지연 효과 3종 (작전 단계 진입 정산) | `CardPhaseManager._apply_phase_entry_carryovers(is_player)` 가 **자기 팀의 다음 작전 단계 진입 시점**에 한꺼번에 정산한다. (1) **계획 중시**의 보존 목록(`BattleSim.preserved_cards_p/ai`)을 비운다 — 보존은 BATTLE 구간 한 번만 버틴다. (2) **아드레날린**의 `next_phase_strategy_*`(−2)를 점수에 더한다(0 아래로는 안 내려간다). (3) **완벽한 마무리**의 팀 성장 배율을 1.0 으로 되돌린다. 한편 **계획 살인**의 예약(`kill_bounty_*`)은 그 단계가 끝날 때(`end_card_phase` / AI 턴 종료) 사라진다. |
| 계획 중시 (보존) | 보존은 **상한 초과 자동 버리기(`_trim_hand_overflow`)로부터만** 지켜 준다. 카드 효과에 의한 강제 버리기(재고 / 완벽한 마무리 / 과감한 정리 / 솔로 퍼포먼스)는 보존을 무시한다. 플레이어는 찾기와 같은 그리드로 **손패**를 펼쳐 고르고(`CardSelectOverlay.start_preserve`), 고른 카드는 손패에서 빠지지 않는다 — 오버레이는 픽만 돌려주고 등록은 `CardPhaseManager` 가 한다. 표시는 `Card` 의 시안 테두리(`PreserveMark`)이며 카드를 어둡게 하지 않는다(보존은 제약이 아니라 보증). |
| 계획 살인 (처치 현상금) | **선불 예약형**이다. 카드를 낸 시점에 `BattleSim.kill_bounty_p/ai` 를 심고, **모든 사망이 지나는 유일한 지점**인 `mark_pilot_dead` 가 쓰러진 파일럿의 **반대 팀**에 한 번 지급하고 0으로 소모한다. 전장에 제3세력이 없으므로 처치자 인자를 따로 넘기지 않는다. 같은 단계에 두 장을 내면 큰 쪽 하나만 남는다. |
| 완벽한 마무리 (`end_phase`) | 이 절은 **자리에서 단계를 닫지 않는다.** 효과 체인이 도는 동안 카드는 손패 밖에 떠 있어서, 지금 닫으면 소멸 / discard 라우팅 전에 문이 닫힌다. `_end_phase_requested` 플래그만 세우고 **플레이어는 `_finalize_pending_play` 말미**가, **AI 는 `AiCardPlayer` 의 플레이 루프**가(교전 아레나를 기다린 **뒤**에) `consume_end_phase_request()` 로 받아 간다. |
| AI 한 차례 플레이 상한 | `AiCardPlayer.MAX_PLAYS_PER_TURN`(12). 루프의 실제 종료 조건은 "낼 수 있는 카드가 없을 때"인데, **재고**(비용 0, 손패를 전부 버리고 같은 수를 다시 뽑는다)처럼 비용을 안 쓰고 손패를 회전시키는 카드가 그 조건을 덱+discard 가 마를 때까지 미룰 수 있다. 구조적 루프를 끊는 백스톱이지 밸런스 노브가 아니다. |
| 랜덤 풀 제외 (`pool = 0`) | `pool = 0` 인 카드는 `_build_pool_from_db` 가 걸러 내 랜덤 스타터 덱에 절대 들어가지 않는다. **결투(id 3)** 가 첫 사례 — 구현과 효과 처리는 전부 살아 있지만 아무에게도 지급되지 않으며, 특정 메크 고유 카드로 전환할 자리로 남겨 둔 것이다. |
| 손패 복귀 (`return_left:N`) | **정밀 이동**은 discard 로 가지 않고 **손패 맨 왼쪽**으로 돌아오며, 돌아올 때마다 **그 카드 자신의 비용만** N 오른다(0 → 1 → 2 …). 시전자별 사본(`make_card_copy`)에 찍히므로 다른 카드는 영향이 없다 — 단계 전체에 세금을 매기는 `cost_inc_phase` 와는 별개의 노브이고, 정밀 이동은 더 이상 그 절을 달고 있지 않다(`move;return_left:1`). 판정은 effect chain 이 아니라 `_dispose_used_card` 가 한다 — chain 이 도는 동안 카드는 손패 밖에 있기 때문. 비용이 감당 못 할 만큼 오르면 맨 왼쪽 = `_trim_hand_overflow` 가 가장 먼저 버리는 자리이므로 알아서 정리된다. **이 절을 다는 카드는 비용이 반드시 올라야 한다** — 0코스트가 0코스트로 돌아오면 `AiCardPlayer.run_ai_plays` 루프가 끝나지 않는다. |
| 카드 소멸 규칙 | **소멸은 `keyword = exhaust` 하나로만 결정된다.** 손패 복귀 카드를 뺀 나머지는 전부 discard 로 간다. 예전엔 `uses > 0` 인 카드가 사용 횟수를 다 쓰면 사라졌는데, `cards.csv` 는 exhaust 가 아닌 카드도 거의 전부 `uses = 1` 이라 **전투 개시를 포함한 대부분의 카드가 한 번 내면 그대로 소멸**했다 — 덱이 돌지 않고 매치 내내 줄어들기만 했고, discard 는 버리기 카드로만 찼다. `CardData.remaining_uses` 는 삭제됐고 `uses` 컬럼은 로드만 될 뿐 아무도 읽지 않는다(향후 "N회 사용 후 소멸" 용으로 남겨 둔 자리). |
| 덱 / 버린 더미 뭉치 | 핸드 행 양옆 거터의 Deck / Discard 는 **앞으로 누운 카드 뭉치**로 그려진다(`ui/CardPileStack.gd`) — 카드 뒷면이 위를 향한 채 겹쳐 쌓이고, 아래 카드들의 단면이 뭉치 밑으로 삐져나온다. 예전에는 `"Deck\n18"` 두 줄짜리 Label 하나였다: 숫자는 읽혔지만 더미가 **물건으로 보이지 않아** 카드가 어디서 오고 어디로 가는지가 화면에 없었다. 누워 보이게 하는 것은 둘이다 — 세로를 `FORESHORTEN`(0.55)만큼 누르고, **윗변을 아랫변보다 좁게**(`TOP_EDGE_SCALE` 0.78) 그려 원근을 넣는다. **두께가 곧 장수다**(4장당 한 층, 상한 8층). **바닥선은 고정이고 위로만 자란다** — 세로 중심을 고정하면 카드 한 장이 오갈 때마다 뭉치가 아래위로 떨린다. 장수는 맨 위 카드 뒷면 한가운데에 찍히고 제목은 뭉치 아래에 붙는다. 카운트는 `float` 로 들어와 리셔플 트윈 동안 두께도 같은 곡선을 탄다. 0장이면 테두리만 남은 빈 슬롯. **뒷면은 `Card._apply_back_style` 와 같은 색 하나로 균일하게 칠한다** — 예전에는 면 안쪽에 더미별 accent 사다리꼴(덱 보라 / 버린 더미 적갈)을 덧그렸는데 뭉치가 작아 그 액자가 무늬가 아니라 **면에 얹힌 계조**로 읽혔고, 두 더미는 아래 제목 라벨이 이미 갈라 준다. |
| 뭉치를 오가는 카드 (잔상) | 숫자만 바뀌면 카드가 더미에서 **나왔다 / 들어갔다**가 화면에 남지 않는다. 그래서 뭉치는 맨 위 카드와 같은 모양의 **잔상** 한 장을 더 그린다(`_draw()` 안의 사다리꼴 하나 — 노드가 아니라 레이아웃 · 입력 · z-order 에 영향이 없다). **덱은 위로 `GHOST_RISE_PX`(74px) 떠오르며 사라지고**(`play_pop`, 드로우 때), **버린 더미는 그 높이에서 내려앉으며 나타난다**(`play_land`, 버리기 때). 한 장이 도는 시간은 `GHOST_SEC`(0.26초)이고, 여러 장이 동시에 돌 수 있어야 하므로 트윈이 아니라 `_ghosts` 배열 + `_process` 로 굴린다. **두 이음매의 규칙이 정반대다**: 드로우의 왼쪽 진입(`_play_draw_intro` ①)은 잔상이 다 사라진 뒤가 아니라 알파가 `GHOST_HANDOFF_ALPHA`(0.30) 남은 시점(0.182초)에 시작해 **겹친다**(완전히 사라진 뒤에 시작하면 한 장이 두 번 나온 것처럼 끊겨 보인다). 반대로 버리기의 착지 잔상은 손패 카드가 다 떨어진 **뒤**(0.30초)에 출발해 **이어 붙는다** — 드로우는 한 장이 덱에서 손으로 이어 달리는 그림이고, 버리기는 손에서 떨어진 카드가 더미에 도착하는 그림이기 때문이다. 착지 쪽은 **장수가 늘어난 것을 한 곳에서 알아채** 부른다(`CardPhaseManager._notice_discard_gain` ← `update_deck_discard_labels`): 버린 더미가 카드를 받는 코드는 일곱 군데지만 숫자가 바뀌는 자리는 하나이고, 리셔플처럼 줄어드는 경우는 델타가 음수라 저절로 걸러진다. **소멸(`exhaust`)은 버린 더미로 가지 않으므로 잔상도 없다.** |
| Deck / Discard 목록 열람 | 핸드 행 양옆의 **Deck / Discard 뭉치를 누르면** 그 더미의 카드가 찾기 그리드와 같은 5열 목록으로 펼쳐진다(`card_phase/CardPileViewer.gd`, 읽기 전용). **정렬은 이름 오름차순** — 실제 덱 순서를 보여 주면 다음 드로우가 그대로 읽히기 때문이며, 찾기(`search:N`) 그리드도 같은 규칙으로 정렬한다. 열리는 시점은 **작전 단계뿐**(`CardPhaseManager.can_browse_piles()`); 못 여는 상태에서는 버튼이 비활성이고 뭉치가 흐려진다. 열려 있는 동안 핸드 입력 · 턴 넘기기 · 도넛 플립이 모두 잠긴다 — 특히 `CostDonut` 은 `_input` 으로 듣기 때문에 딤만으로는 막히지 않아 `set_flip_allowed` 를 따로 끈다. 닫기는 닫기 버튼 또는 딤 클릭. |
| 사용 불가 카드 표시 | 마나 부족 / 시전자 부활 대기는 **카드 전체를 덮는 반투명 슬래브**(`Card.BlockOverlay`)로 표현한다 — 카드 배경만 회색으로 칠하면 그 위의 파일럿 일러스트가 밝게 남아 쓸 수 있는 카드처럼 읽혔다. 시전자가 쓰러져 있으면 그 위에 **부활까지 남은 턴 수**가 카드 한가운데 큰 폰트로 찍히고, 그 동안 확인 버튼은 비활성이다. |
| 전장 크기 | `HexGrid.DISPLAY_SCALE` = **1.35** (예전 1.5의 90%). 전장 픽셀 박스가 990×1092 → 891×983 으로 줄어 화면 중앙(y 860) 기준 상단 314 → **369**, 하단 1406 → **1351** 이 된다. 타일·건물·웨이포인트 스케일과 hex 기하가 이 상수 하나에서 나오고, 파일럿 마커 / HP 바 / 폰트 크기도 `hex_size` 또는 `DISPLAY_SCALE` 에서 유도되므로 전부 함께 줄어든다. |
| 핸드 레이아웃 | Row top is `BS_HAND_CENTER.y` = **1440** (전장이 90%로 줄며 하단이 55px 올라간 만큼 60px 위로 옮겼다 — 카드 윗단과 전장 아랫단 사이 ~90px 간격 유지). 확인/취소 행 · 전략 포인트 도넛 · Deck/Discard 카운터 · 히트 레이어가 전부 이 값에서 역산되므로 함께 따라온다. Row is `BS_HAND_WIDTH` = (viewport − 2×`BS_HAND_AREA_MARGIN`) × `BS_HAND_WIDTH_SCALE` (1.10) = 902px wide; the Deck/Discard labels re-derive their gutter from the real hand edge. **The fan is one circle**: every card centre rides a circle of radius `BS_HAND_FAN_RADIUS` (3200px) pivoted *below* the row, so tilt and vertical offset always agree and **the middle card is the highest while both ends curve down** (12-card hand: ±6.7°, ends hanging 21.4px below the middle). A plain click does nothing at all — see 카드 드래그 앤 드롭. Each player card casts a `DropShadow` child whose offset/blur grows with height — rest 10px → hover 24px → dragged 32px. **The row spreads around one "focus" card — `_push_focus_card()` = the card being dragged, else the hovered one** — so grabbing a card opens the hand exactly as hovering it does. Focus scales the card to `Card.HOVER_SCALE` (1.2×, cubic EASE_OUT in 0.04s) and slides its neighbours away by `_hover_push_amount` — solved from the coverage it must prevent (96px enlarged half-width + `BS_HAND_HOVER_MIN_STRIP` 32px clickable sliver − the row's own spacing), so **it grows with the hand size**: `BS_HAND_HOVER_PUSH` 28px floor up to 8 cards → 60.5px at 12 cards. **The hand's width is fixed**: the two end cards are anchors, and the push ramps to exactly 0 at them via `1 − (steps/steps_to_end)^BS_HAND_HOVER_FALLOFF_POW` (2.0, so near neighbours keep nearly the full push) — the row redistributes rather than growing. Dragging a 대상 지정 card lifts it by `Card.PRESS_LIFT` **along its own up-axis, keeping its fan rotation** (±4.6px sideways at the ends of a 12-card hand); `_begin_drag` reflows the whole row around it first, and since the focus card's own push is 0 there is no push-free slot variant — lift and drop are exact opposites. `_reorder_hand_nodes` raises the dragged — else hovered — card above all others. A hover reflow lays out the **incoming focus card too** — only the *dragged* card is skipped — otherwise it stays stranded at the push the previous focus gave it. **Hand cards don't pick the mouse**: `spawn_card_node` sets the whole card subtree to `MOUSE_FILTER_IGNORE` (PASS is not enough — a PASS container is still returned by picking) and one `HandHitLayer` Control over the row routes hover/clicks by cursor x, using bands cut at the midpoints between card centres, with the focus card holding the cursor while it's on its enlarged face. Rect picking let the focus card cover its right-hand neighbour down to 0–17px. Hover reflows are **deferred + coalesced** (`move_child` re-fires mouse_entered/exited synchronously — see card_phase/README.md), and `scale` is owned solely by `Card._refresh_float_state`. Card layout tweens `position`, never `global_position` (the latter is scale-coupled — see card_phase/README.md). |
| 상대 핸드 레이아웃 | 상대 핸드도 겹쳐진 **부채꼴**이며, 플레이어 핸드를 **상하 반전**한 모양이다: 원의 중심이 카드보다 *위*에 있어 θ=0 지점이 호의 가장 낮은 점이 되고, 따라서 **가운데 카드가 패널 아래로 가장 많이 튀어나오고 양 끝이 위로 말려 올라간다**. 기울기는 `−θ`(플레이어 팬의 좌우 기울기를 거울대칭). `HudBuilder.AI_HAND_FAN_RADIUS` 620 / `AI_HAND_FAN_STEP_DEG` 3.2 / `AI_HAND_FAN_MAX_SPREAD_DEG` 28 로, 카드 간 중심 간격은 34.6px(72px 카드 대비 절반 넘게 겹침)에서 12장 기준 26.9px 까지 좁아진다. 자세한 식은 `ui/README.md`. |
| 전투 행동 로그 | `debug/BattleLogger.gd` (`_bs.blog`). 매 턴 전/후 위치 스냅샷 + 리스폰·리콜·교전·데미지·사망·자유이동(스텝 단위)·푸시·포탑·HQ·정글·카드까지 콘솔과 `user://battle_logs/battle_<timestamp>.log` 양쪽에 기록. 턴 종료 시 같은 스코프의 적끼리 자리를 맞바꾸면 `!!SWAP` / `!!CROSS` 로 표시하고 두 파일럿의 이동 이력을 되짚어 준다. 기본 ON — `blog.enabled` 로 끈다. |
| 이동 해석 (단일 패스) | 자유이동과 교전 푸시는 **하나의 패스**(`SimulationCore.resolve_movement`)에서 **락스텝**으로 해석된다 — 한 라운드 안의 모든 파일럿이 같은 스냅샷을 보고 목적지를 정한 뒤 동시에 커밋하므로, 같은 스코프의 적끼리 자리를 맞바꾸거나 서로를 통과하는 일이 구조적으로 불가능하다. 한 라운드에서 중재되는 충돌은 둘이다. (1) **버티는 적 지나치기** — 전진은 적 HQ 쪽, 후퇴는 자기 HQ 쪽이라 방향이 같으므로 **승자는 밀려난 패자를 따라 들어간다**(= 라인이 한 턴에 한 칸 밀린다). 예전엔 두 목적지가 겹치면 전진 쪽을 취소해 "패자만 쫓겨나고 승자는 그 칸을 지킨다" 였는데, 일직선 레인에서는 목적지가 **항상** 겹쳐서 교전에 이겨도 승자가 영영 한 칸도 나아가지 못했다. 지금은 적이 밀려날 곳이 없어 그 칸에 **남을 때만** 전진을 취소한다(`_veto_advance_over_stuck_enemy`) — 서 있는 적을 스쳐 지나가지 않기 위해서다. 적 포탑 칸은 막지 않는다 — 패자가 자기 포탑 칸으로 밀려나면 승자도 거기까지 따라 들어가고, 그 칸에서 공성이 시작된다. (2) **정면 충돌**(서로의 칸을 노림)은 **푸시 > 자유이동, 동률이면 팀0** 우선순위로 한쪽이 그 칸을 차지하고 다른 쪽이 멈춰 **같은 칸에서 만나** 다음 턴에 교전한다. 데미지 적용은 이동보다 **앞**에 온다(이번 턴에 죽은 파일럿은 움직이지 않는다). |
| Combat | **Same-cell only** — no adjacent-cell engagement, no attack range. Lane pilots paired 1:1 by HP against enemy lane pilots; each rolls `hit/(hit+evasion)` for damage — 이 판정에 **라인전 스탯**이 곱해진다(위 항목). **명중 1회 피해 = `atk × BATTLE_PILOT_DMG_MULT`**(game_config, 0.35 — 반올림, 최소 1). 이 배율은 **파일럿이 받는 전장 피해 전용**이다: 파일럿→포탑 / 파일럿→HQ 는 `atk` 원본 그대로이고, 공격 카드와 교전 무대도 각자 계산을 쓴다. 원본 `atk` 로는 한 대가 복귀 구간보다 컸다 — atk 28 상대 vs max_hp 75 스나이퍼는 1타가 최대 체력의 37% 라 20% 복귀선 위에서 곧장 0 으로 떨어졌고, 저HP 복귀가 발동할 구간 자체가 없었다. **Push is team-level**: tally unilateral wins per team across all pairs in the cell; the side with strictly more unilateral wins sweeps — every pilot of that side in the cell (including unpaired pilots in e.g. 2v1) advances, every opposing pilot retreats. Tie/0-0 → no push. Advance and retreat point the **same way** (enemy HQ vs own HQ), so the winners **follow the losers into the next cell** — 교전 칸 전체가 패자 HQ 쪽으로 한 칸 미끄러지고 다음 턴에 거기서 다시 붙는다. 이것이 라인 푸시다. 전진이 취소되는 경우는 **패자가 밀려날 곳이 없어 그 칸에 남을 때** 하나뿐이다 — 앞 칸이 적 포탑이어도 승자는 그 칸까지 따라 들어간다(포탑 공성은 그 다음 턴). `_move_pilot` aborts further multi-step movement only when a *same-scope* enemy enters the cell (jungler-vs-jungler or lane-vs-lane); cross-scope contacts never freeze movement. |
| Engagement scopes | Junglers and lane pilots run on **separate engagement brackets**. A jungler never engages an enemy lane pilot, never deals turret damage, and is never paired against attackers as a turret defender. Lane pilots ignore enemy junglers in the same cell. |
| Turret Combat (포탑 칸 점거) | **Only same-lane lane pilots interact with a turret** (e.g. a RIGHT-lane pilot cannot damage a CENTER turret). 전진하는 레인 파일럿은 같은 레인 적 포탑 칸에 **실제로 올라선다** — 그냥 걸어 올라가든, 교전에서 이겨 밀려나는 적을 따라 들어가든, 전진 카드로 들어가든 같다(예전의 "발만 들였다 빼는" 인접 공성 `resolve_turret_sieges` / `_bounce_off_enemy_turret` 은 삭제). **진입한 턴에는 피해가 없다.** 그 칸에 서서 맞는 **다음 턴**에 `_resolve_turret_combat` 이 돌아 **명중 판정 없이** `atk` 전량을 포탑에 넣는다. **적이 그 칸에서 농성 중이어도 포탑 피해는 반드시 들어간다** — 수비자는 포탑을 가려 주지 못한다. 포탑 피해를 넣은 **다음**, 같은 레인 공격자와 수비자가 **서로 명중 판정을 굴려**(HP 오름차순 1:1 페어링, 양쪽 다 `_pilot_hit_damage`) 피해를 주고받는다. 예전엔 "공격은 전부 포탑으로 간다"며 **공격자가 수비자에게 0 피해**였고, 그래서 포탑에 눌러앉은 수비자는 공격자를 일방적으로 두들길 수 있었다. 넉백은 그대로 **수비자가 있을 때만**이고, **명중 여부와 무관하게** 공격자는 직전 칸으로 밀려난다. 수비자가 없으면 밀어낼 주체가 없어 공격자는 그 자리에 눌러앉아 **매 턴** 포탑을 갈아 낸다. 예외는 **때릴 수 없는 포탑**(같은 레인 T1 이 살아 있는 T2)뿐 — 갈아 낼 게 없으니 무조건 물러난다(파일럿끼리의 판정은 그래도 굴린다). 결과적으로 포탑 피해는 무방비면 매 턴, 수비가 붙으면 2턴에 1회(진입 → 타격 후 밀려남 → 재진입). 오프레인 파일럿은 포탑을 무시하고, 양 팀 오프레인끼리는 여전히 파일럿 교전을 한다. **Turrets do NOT attack pilots. Junglers do NOT attack/defend turrets.** T2 는 같은 레인 T1 이 살아 있는 동안 무적. 포탑 파괴 시 `Building` 노드도 해제해 스프라이트가 사라진다. |
| 포탑 피격 연출 | 살아남은 포탑이 피해를 입으면 `BattleSim.anim_turret_hit(td)` 가 0.26초(`ANIM_TURRET_HIT_DUR`) 동안 **좌우로 흔들리며 붉게 번쩍이는** 연출을 건다(파괴 타격은 제외 — 스프라이트가 그 자리에서 사라진다). 포탑 그림은 렌더러가 그리는 게 아니라 `BattleField/BuildingLayer` 아래의 `Building` 노드라, `BattleSim._apply_turret_hit_visual` 이 그 노드의 `position` / `modulate` 를 직접 흔든다(기본 위치는 셀별로 `_turret_home_pos` 에 캐시, 마지막 프레임과 재시작 시 원복). `BattleRenderer` 는 `BattleSim.turret_hit_offset(td)` 를 읽어 **HP 바를 같은 오프셋으로** 흔들 뿐이다. |
| 전진 카드 (`advance:N`) | 카드 한 장이 **라인을 N 칸 밀어 올린다**. 미니틱 하나가 `SimulationCore._advance_tick` 이고, 전장 규칙을 그대로 쓰되 판정 하나만 강제한다 — **전진을 낸 쪽은 그 칸의 교전에서 무조건 이긴 것으로 친다**(피해 판정은 평소대로 굴리므로 맞을 건 맞는다. 밀리는 쪽만 고정). 그래서 **시전자와 같은 칸·같은 스코프의 아군이 함께 한 칸 전진하고, 같은 칸의 적은 함께 한 칸 밀려난다**. 예전엔 (1) 일방 명중 우세를 그대로 읽어 주사위가 나쁘면 시전자가 자기 HQ 쪽으로 물러났고(= 전진 카드가 후퇴 카드였다), (2) "카드는 한 명만 움직인다"며 진 적을 제자리에 두고 시전자만 옆을 스쳐 갔다. 다음 칸이 **같은 레인 적 포탑**이면 무리는 전장 규칙 그대로 **그 칸에 올라선다**(그 틱에는 포탑 피해 없음). 밀려날 곳이 없어 적이 칸에 남으면 무리도 전진하지 않는다. 시전 시점에 **이미 같은 레인 적 포탑 칸 위**라면 포탑 규칙이 이긴다 — 포탑에 무판정 피해를 넣고, 그 칸에 **수비자가 있으면** 한 칸 후퇴(**전진이 뒤로 가는 유일한 경우**), 없으면 물러나지 않고 제자리에서 계속 갈아 낸다. |
| Recall / Respawn | **복귀 = 본진 귀환.** 두 가지 사유가 `RecallSystem.return_to_hq` 한 경로로 들어온다 — (1) HP ≤ `RECALL_HP_THRESHOLD`(20%), (2) 이동 카드가 파일럿을 **정글이나 다른 레인의 통로**에 떨어뜨린 위치 이탈. **복귀는 전장을 비우지 않는다** — 그 턴에 곧장 자기 HQ 에 **만피로** 서고 `alive` 는 계속 true 다. 파일럿이 전장에서 사라지는 사유는 **사망뿐**. 대신 복귀한 턴에는 움직이지 않고(`PilotData.recall_hold` → `resolve_movement` 가 이동 패스 1회를 걸러 내며 플래그를 소비), **다음 턴부터** 웨이포인트 0 부터 자기 레인을 다시 걸어 나간다. 즉 복귀 비용은 회복 대기가 아니라 **HQ 에서 전선까지 다시 걸어가는 시간**이다. **자기 레인 위라면 아무리 깊어도 위치 이탈이 아니다** — 스플릿 푸시는 살려 둔 설계다. 복귀 카드(`recall_ally`)는 여기에 대기 없이 즉시 HQ + 만피. 전장을 비우는 것은 사망뿐이므로 `respawn_timer` 와 **`BattleSim.turns_until_return(p)`** 은 **사망 전용 시계**다 — "남은 턴 수"가 필요한 곳(카드 잠금 표시, 로그 `dead:N`)은 여전히 헬퍼를 거친다. **리스폰 턴 수는 경기 시간에 따라 늘어난다** — `BattleSim.respawn_turns_now()` = `RESPAWN_TURNS`(game_config, 5) + `turn_count / 10`. 사망은 **오직** `BattleSim.mark_pilot_dead(p)` 한 곳을 지난다(전장 교전 / 전진 / 공격 카드 / 교전 무대 공통). |
| 전장 파일럿 마커 | 초상(`PilotImages.circle_for` = `circle/N_circle.png`)은 정사각형에 **내접한 원** 그림이고, `BattleRenderer._draw_pilot_circle` 이 그 **뒤에 흰 원을 깐다**. 40장 중 일부는 원 **안쪽까지** 알파 구멍이 있어 그냥 그리면 뒤의 타일 색이 얼굴을 뚫고 비쳤다 — 특히 점령된 정글 타일 위에서 파일럿이 타일과 같은 색으로 물들었다. 반지름은 그리는 반지름에서 1px 줄여 안티에일리어싱된 가장자리 바깥으로 흰 테가 삐져나오지 않게 하고, 색은 초상과 **같은** tint · alpha 를 타므로(사망 딤 / 복귀 페이드) 배경만 밝게 남지 않는다. |
| 사망 연출 | 쓰러진 파일럿은 그 자리에서 **1초간 딤드된 채 남았다가**(`ANIM_DEATH_HOLD_DUR`) 0.45초 동안 투명해지며 위로 떠올라 전장을 뜬다. `alive` 는 이미 false 이므로 순수 UI다 — `BattleRenderer._is_renderable()` 이 `anim_death_phase != 0` 을 살아 있음과 함께 그리기 조건으로 삼는다. 시신도 셀 레이아웃 슬롯을 차지하므로 그 1.45초 동안 같은 칸의 산 파일럿이 밀린다(히트 테스트도 같은 solve 를 읽으므로 어긋나지 않는다). |
| 공격 돌진 연출 | **공격 카드를 내면 시전자 초상이 대상 초상에 파고들었다 돌아온다.** 한 타격이 세 박자다 — **파고들기**(`BattleSim.anim_pilot_lunge`, `ANIM_LUNGE_IN_DUR` **0.08초**, `t²` 로 서서히 빨라진다, **거리와 무관하게 고정 시간**이라 먼 대상일수록 빠르게 날아간다) → **타격**(정지한 그 프레임에 피해 · 쉐이크 · 팝업이 들어간다 — **맞는 쪽의 쉐이크는 전장 자동 교전보다 훨씬 격렬하다**: `ANIM_SHAKE_CARD_DUR` 0.26초 / `ANIM_SHAKE_CARD_AMP_PX` **20px** vs 전장 기본 0.18초 / 6px. 세기는 `PilotData.anim_shake_amp` 로 실려 가고 렌더러는 **주파수를 고정한 채 진동 수를 지속시간에 비례**시킨다 — 진동 수를 고정하면 길게 흔들라는 지시가 "느리게 흔들라"가 되어 격렬함이 사라진다. 매 턴 자동으로 오가는 교전 피해와 달리 카드 명중은 플레이어가 방금 고른 한 방이다) → **복귀**(`anim_pilot_lunge_return`, `ANIM_LUNGE_OUT_DUR` **0.24초**, smoothstep 으로 되돌아오며 궤적 한가운데서 `ANIM_LUNGE_HOP_PX` 34px 만큼 붕 뜬다). 멈추는 거리는 `ANIM_LUNGE_OVERLAP`(0.5) = **대상 지름의 절반만큼 겹침**(두 마커 반지름이 같으므로 최종 중심 간 거리 = 마커 반지름 1개분)이고, 거리는 타일 중심이 아니라 `BattleRenderer.pilot_marker_positions()` 의 **그려진 마커**로 잰다 — 마커는 적 위 / 아군 아래로 밀려나 있어 타일로 재면 같은 칸의 적에게 돌진할 때 방향이 반대가 된다. **한 타격의 총 연출 시간은 두 값의 합, 0.32초다** — 0.50+0.62=1.12초 → 0.40초 → **파고들기만 다시 절반(0.16 → 0.08)**으로 줄어든 결과이고, 파고들기 : 복귀 = 1 : 3 이라 "튀어나갔다 천천히 돌아온다"가 더 뚜렷하다. 연속 공격(`repeat`, 최대 5타)이 세 박자를 타수만큼 반복하므로 카드 한 장이 최대 5.6초를 먹었고, 그동안 손패도 턴 넘기기도 잠긴다(1타 0.32 / 2타 0.64 / 상한 1.6초). 두 값을 만질 때는 `DMG_POPUP_DUR`(**0.30**)이 그 합보다 짧도록 함께 조정할 것 — 길면 연속 타격의 숫자가 같은 자리에 겹쳐 쌓인다. **연출이 끝나야 다음 카드를 낼 수 있다** — `CardPhaseManager._attack_anim_active` 가 손패 딤(`_is_player_input_blocked`)과 턴 넘기기(`can_end_card_phase`) 양쪽을 잠근다. **AI 공격도 같은 연출을 쓴다**: `_effect_attack` 의 `await` 하나가 `_apply_single_effect` → `_process_pending_chain` / `apply_card_effect` → `apply_and_dispose_ai_card` → `AiCardPlayer.run_ai_plays` 를 줄줄이 코루틴으로 만든다. 1단계는 시간이 다 차도 스스로 꺼지지 않고 **대상 앞에 멈춰 선다**(그 정지 구간이 피해가 적용되는 자리다); 스스로 걷는 것은 2단계뿐이다. 사망 / 복귀 / 부활은 `anim_pilot_lunge_clear` 로 변위를 걷어 낸다. |
| 피해 수치 표시 | **공격 카드(`attack:N`) 전용.** 판정마다 대상 마커 위로 `-N` / `MISS` / `흡수`(보호막이 전부 먹은 경우)가 떠올랐다 사라진다(`BattleRenderer.spawn_pilot_popup`). 연속 공격은 타수마다 돌진 연출(0.32초)이 통째로 끼므로 팝업이 겹칠 일이 없다(`DMG_POPUP_DUR` 0.30 < 0.32) — `DMG_POPUP_STAGGER` 는 연출이 붙지 않는 경우(시전자 없는 레거시 카드)에만 남는다. 좌표는 띄운 순간에 고정되므로 대상이 쓰러져도 숫자가 끝까지 재생된다. 전장 자동 교전은 기존대로 흔들림만. |
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
| `cards` | `cards.csv` | GameManager startup | Card pool for the BattleSim card phase (**28행**). `engage:N` 의 N 은 **라운드 수**이고 설명문도 "전투 개시: 3라운드" 로 적는다(초 표기는 삭제). `scope` (`any`/`lane`/`jungle`) restricts who may be a card's 시전자; `pool` (1/0) keeps a card out of the random starter deck; `card_type` (`mech`/`pilot`) 와 `card_cat` (`-`/`lane`/`draw`/`jungle`/`common`) 은 덱 슬롯을 정한다 — 위 "카드 종류 / 덱 슬롯" 항목 참조. 이름이 비슷한 **재빠른 사고**(id 15, `draw:2`)와 **과감한 정리**(id 29, `discard_right:3;draw:5`)는 다른 카드다. |
| `game_config` | `game_config.csv` | BattleSim startup | Tunable knobs (HP, turns, thresholds). `MAX_HAND_SIZE` 는 **10**, `BLUE_COST_HEAD_START`(1) 은 블루 진영이 선점하는 전략 포인트다. **`INITIAL_HAND_SIZE` 는 삭제됐다** — 개시 손패가 없어졌고 양 팀은 빈 손으로 시작한다. `ECONOMY_START_TURN`(**10**)은 전략 점수 회복 / 자동 드로우가 처음 도는 턴이고, `GROWTH_PER_TURN`(0.01)은 턴당 누적 성장률이다 — 성장은 이 게이트를 타지 않고 1턴부터 돈다. `BATTLE_PILOT_DMG_MULT`(**0.35**) 는 **전장 교전이 파일럿에게 넣는 피해**에만 곱해진다 — 포탑/HQ 피해·공격 카드·교전 무대는 제외. `TURRET_HP` 는 **300**. `TURRET_SPEED` 는 **삭제됐다** — 교전이 라운드 턴제가 되면서 가담 포탑도 라운드마다 한 번 쏘므로 속도 개념이 없다. 복귀는 이제 즉시 만피 + 1턴 대기라 회복/대기 관련 키가 없다 — `RECALL_HEAL_RATIO` 와 `RECALL_RETURN_TURNS` 둘 다 제거됐다. |
| `lane_config` | `lane_config.csv` | BattleSim startup | LANE_NAMES, LANE_MAX, midpoints |
| `players` | `players.csv` | Season + MatchFlow startup | 40 pilots (8 teams × 5 roles), `PlayerData` fields. Player drafts 5 from this pool in Season. **`name` 은 그 id 의 초상화에 묶여 있다** — pilot id `N` 이 쓰는 `resources/images/pilot/*/N+1_*.png` 가 어떤 젠레스 존 제로 에이전트인지가 곧 이름이다(40장 전부 공식 아이콘 아트와 대조). 행 순서·id 를 바꾸면 이름과 얼굴이 어긋난다 — 자세한 규칙과 대체 코스튬 4건은 `resources/README.md` 의 `PilotImages.gd` 절. |
| `mechs` | `mechs.csv` | MatchFlow startup | 30 mech pool (no role); drives PilotData stats when picked. **`id` 는 전신 아트에 묶여 있다** — `resources/images/mech/{id}_full.png` 가 그 id 의 스탯 아키타입(탱커 0–5 / 격투 6–11 / 암살 12–17 / 서포터 18–23 / 스나이퍼 24–29)에 맞춰 배치돼 있으므로, 행 순서나 스탯 구간을 바꾸면 그림과 스탯이 어긋난다 — `resources/README.md` 의 대응표 참조. `name` 은 아트와 무관한 자체 명명이다. `presence`(타겟 어그로)는 **교전 무대 전용** — 전장은 읽지 않는다. **`speed` 컬럼은 삭제됐다** — 교전이 라운드 턴제가 되면서 행동 빈도 개념이 사라졌고, `csv_to_db.gd` 스키마와 `GameManager` 로더에서도 함께 빠졌다. |
| `teams` | `teams.csv` | Season `init_season()` | 8 teams (id/name/short_name) → `season_state["team_meta"]`. Falls back to synthesized `Team N` rows if the table is missing. 팀명은 젠레스 존 제로 **진영(faction)** 에서 땄다 — 다만 **로스터는 진영과 맞지 않는다**(초상화가 진영을 섞어 뽑혀 있어서), 팀명은 순수한 간판이다. |
| `intl_teams` | `intl_teams.csv` | Season `init_season()` | 4 INTL teams (ids 100..103) → `season_state["intl_team_meta"]`. Synthesized fallback `Intl Alpha/Bravo/Charlie/Delta` rows when the table is missing. 국내 8팀이 쓰지 않은 진영 4개를 쓴다. |
| `intl_players` | `intl_players.csv` | Season `init_season()` | 20 INTL pilots (ids 100..119, 4 teams × 5 roles) → `season_state["intl_pilots"]`. Used by `MatchFlow._team_roster` and `InternationalTournament.simulate_ai_match` when `team_id >= 100`. **초상화가 없으므로**(`PilotImages.has_image` 는 id ≥ 100 에 false) 이름은 `players.csv` 40명이 쓰고 남은 에이전트 중에서 자유롭게 붙였다. |

At runtime, `GameManager` and BattleSim's `DataLoader` open the DB once, load
tables into Dictionaries / Arrays keyed by ID, then close the DB. All in-game
access goes through those structures — not live DB queries.
