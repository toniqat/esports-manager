# Feature: Battle Sim

## Purpose
Tactical battle simulator on a hex grid. Five pilot roles per team
(Tank, Fighter, Assassin, Support, Sniper) push down a 3-lane map flanked by
jungle. **BATTLE auto-progresses** in 1-minute (`AUTO_PLAY_INTERVAL`) ticks;
players intervene during the threshold-gated **작전 단계** (CARD_PHASE) to spend
작전 점수 on cards.

## Entry point
Normally entered from `scenes/MatchFlow.tscn` via `change_scene_to_file`.
Standalone launch of `BattleSim.tscn` also works — falls back to `ROLE_STATS`
defaults and a default jungle direction (LEFT).

## Match Context handoff
On `_ready()`, BattleSim reads `GameManager.match_ctx`:

| match_ctx field | Used by |
|---|---|
| `player_roster[i].assigned_mech` | `SimulationCore._stats_for()` → PilotData hp/atk |
| `player_roster[i].mechanics` | PilotData.hit (combat 명중률) |
| `player_roster[i].gamesense` | PilotData.evasion (combat 회피율) |
| `enemy_roster[i].assigned_mech` / stats | same, for team 1 |
| `jungle_start_dir` | PilotData.jungle_start_pref on the player-team assassin |
| `active = false` | Triggers fallback to ROLE_STATS (no MatchFlow ran) |

---

## Module Architecture

BattleSim.gd is a **thin orchestrator** (`class_name BattleSim extends Node2D`). All logic lives in child modules. Each module has:
```gdscript
@onready var _bs: BattleSim = get_parent() as BattleSim
```
And accesses shared state via `_bs.pilots`, `_bs.turn_count`, etc.

### Child nodes (in scene order)
| Node | Type | Script | Purpose |
|---|---|---|---|
| SimulationCore | Node | `combat/SimulationCore.gd` | Turn loop, paired combat, movement, push, T1→jungle capture, win condition |
| RecallSystem   | Node | `combat/RecallSystem.gd`   | Instant HQ teleport at HP ≤ threshold; phase-end out-of-position recheck |
| Pathfinding    | Node | `combat/Pathfinding.gd`    | BFS + greedy fallback (hex distance) |
| BattleRenderer | Node2D | `rendering/BattleRenderer.gd` | HQ/turret HP bars + per-cell pilot rendering |
| CardPhaseManager | Node | `card_phase/CardPhaseManager.gd` | 작전 단계 turn flow, deck, fanned hand layout, phase-end gating |
| GambitPhaseManager | Node | `gambit/GambitPhaseManager.gd` | Auto role→lane mapping + launch (UI removed; pre-battle choices live in `features/match_flow/`) |
| EngagePhaseManager | Node | `engage/EngagePhaseManager.gd` | 전투 개시(engage) modal — **실시간** MOBA 교전 아레나 (`engage/RealtimeEngageSim.gd` + `engage/EngageArena.gd`) triggered by `engage:N` / `duel` cards. Lazily added in `_ready()`. |
| HudBuilder     | Node | `ui/HudBuilder.gd`         | HUD construction; 전략 포인트 도넛 (`ui/CostDonut.gd`) is the only interactive in-battle widget |

Cross-module calls go through `_bs`:
```gdscript
_bs.sim_core.simulate_turn()
_bs.pathfinder.bfs_next_step(...)
_bs.renderer.queue_redraw()
```

---

## BattleSim.gd (thin orchestrator)

Responsibilities:
- Declares all DB-driven config vars and **state vars** (pilots, turrets, neutral_zone_cells, game_phase, HUD refs, card state, `gambit_lanes`, `card_phase_entry_cost`)
- Holds `@onready` refs to all child modules
- Public **coordinate helpers**: `cell_center(pos)`, `pilot_label(p)`, `role_stats_str(role)`
- **Lifecycle**: `_ready()`, `_process(delta)`
  - `_ready` calls `_gambit.auto_assign_lanes()` then `_gambit.launch_battle()` —
    no overlay, scene transitions straight into BATTLE.
  - `_process` auto-ticks `card_phase.do_battle_turn()` every `AUTO_PLAY_INTERVAL`
    seconds while `game_phase == BATTLE`. CARD_PHASE pauses the tick.
- **Button callbacks**: `_on_restart_pressed()` (the only manual entry point left).

---

## Data Classes (resources/)

| File | class_name | Description |
|---|---|---|
| `resources/PilotData.gd` | PilotData | role, hp/max_hp, atk, team, grid_pos, lane, waypoint_idx, **move_range**, **hit**, **evasion**, **jungle_start_pref** |
| `resources/TurretData.gd` | TurretData | team, grid_pos, hp, tier, lane, alive |
| `resources/PlayerData.gd` | PlayerData | id, name, role, team_id, 5 stats (laning / mechanics / gamesense / teamfight / mental), `assigned_mech` |
| `resources/MechData.gd` | MechData | id, name, hp, atk, **presence** (4=melee/2=ranged; engage 아레나의 타겟 어그로 가중치로만 사용) |

---

## Enums (resources/GameEnums.gd)

| Enum | Values |
|---|---|
| `GameEnums.BattlePhase` | GAMBIT, CARD_PHASE, BATTLE, **ENGAGE** |
| `GameEnums.Role`        | TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER |
| `GameEnums.LanePosition`| LEFT=0, CENTER=1, RIGHT=2, GUERRILLA=3 |
| `GameEnums.Lane`        | NONE=-1, LEFT=0, CENTER=1, RIGHT=2 (waypoint/building lanes) |
| `GameEnums.JungleStartDir` | LEFT, RIGHT (assassin start preference) |

---

## Active Systems

### Combat
- Combat happens **only between pilots in the same cell** — there is no
  adjacent-cell engagement and no concept of attack range.
- Same-cell pilots are paired 1:1 (lowest HP first) and roll
  `hit / (hit + evasion)` independently each minute.
- **Junglers and lane pilots run on separate engagement scopes**: a jungler
  never fights a lane enemy, never deals damage to enemy turrets, and is
  never paired against attackers as a turret defender. Junglers only fight
  other junglers.
- One-sided hit → winner advances 1 cell, loser retreats 1 cell.
- Both hit / both miss → no movement.
- Damage accrues regardless of push.
- A pilot mid-move stops as soon as it enters a same-scope enemy cell
  (`_move_pilot` re-checks before each step). Cross-scope contacts (jungler
  vs lane pilot) are ignored, so a jungler crossing a lane never freezes on
  a lane enemy.
- **Pilots are not attacked by turrets.**
- At an enemy turret cell: only **same-lane** lane pilots interact with the
  turret. Same-lane attacker(s) deal 100% damage to the turret; same-lane
  defenders roll on same-lane attackers, and any successful defender hit
  forces all attackers in the cell to retreat. Attackers do NOT counter-attack
  defenders during turret combat. Off-lane lane pilots in the same cell ignore
  the turret entirely; if both teams have off-lane lane pilots in the cell
  they may still fight each other as pilot-vs-pilot. Junglers are always
  spectators at turret cells.
- **Lane pilots cannot move past an alive enemy turret cell.** Both natural
  movement and push-advance bail once a lane pilot stands on an alive enemy
  turret — the pilot must wait out turret destruction (same-lane case) or be
  recalled / displaced out (off-lane case). Push-retreat is unaffected.
- When a turret is destroyed, the matching `Building` node in
  `BattleField/BuildingLayer` is unregistered and `queue_free`'d so the
  sprite disappears from the field.

### Recall
- HP ≤ `RECALL_HP_THRESHOLD` → instant HQ teleport at full HP.
- During CARD_PHASE the recall check is paused; it runs again at end of phase
  via `process_phase_end_recalls`, which also recalls pilots whose
  card-effect placement put them outside their lane / own jungle.

### Lanes / movement
- Pilots follow waypoint lane paths (Left / Center / Right) loaded from `BattleField/WaypointLayer`.
- The old "minion line" / "lane strength" concept is gone. Lane pilots simply
  step toward `current_waypoint(p)` each minute.
- **Lane pilots are forbidden from entering jungle/neutral cells AND alive
  enemy off-lane turret cells.** Pathfinding receives the union of the
  jungle-cell set and every alive enemy turret in a lane other than the
  pilot's own. Same-lane enemy turret cells remain reachable so the pilot can
  step on them to engage. This prevents e.g. right-lane pilots from being
  routed through the still-alive center T2 cell after their own-lane turrets
  fall, then freezing on it because of the "cannot pass past alive enemy
  turret" rule. SUPPORT pilots also refuse to chase a weak ally that is
  currently sitting in a jungle cell.
- **SUPPORT defensive fall-back**: when a SUPPORT pilot's same-lane SNIPER
  teammate is dead (respawning) or sitting at own HQ (instant recall), the
  support's per-tick goal becomes the forward-most alive own-team turret cell
  on their lane (turret hugging) instead of the next waypoint. As soon as the
  sniper is alive on lane again, the support resumes normal pushing. Falls
  back to `current_waypoint(p)` if every own-lane turret is down.
- Junglers move freely (no forbidden cells) — they can transit through lane
  cells when crossing between own-captured jungle clusters, but they never
  engage in lane combat or attack turrets along the way.
- TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT→RIGHT, SNIPER→RIGHT.

### Jungle
- Map starts with both jungles fully captured; only `(-3,-1)` and `(1,-1)`
  start neutral. The roaming jungler can capture neutrals by stepping on them.
- Junglers do not push lanes. They roam own-captured cells and contest neutrals.
- Jungler-vs-jungler combat in a contested cell uses the same hit/evasion roll.
  A loser is pushed to the nearest own-captured jungle cell.
- T1 destruction triggers per-lane "취약지점" (vuln cell) flips. The vuln
  cells per team/lane live in `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}` in
  `combat/SimulationCore.gd`: side lanes have 1 vuln cell, mid has 2 (the
  flanking cells). When a team's same-lane T1 falls, three branches in priority:
  (1) **Restoration** — if any of the capturer's own same-lane vuln cells are
  owned by the loser, those flip back to the capturer and nothing else moves.
  (2) **Side-neutral override (LEFT/RIGHT only)** — if `(-3,-1)`/`(1,-1)` is
  owned by the loser, the capturer takes the neutral instead of the loser's
  vuln. (3) **Default** — the loser's same-lane vuln cell(s) flip to the
  capturer. Mid T1 has no side-neutral override.

### Card Phase (작전 단계)
- Triggered when `player_cost >= PHASE_THRESHOLD`.
- Ending the phase goes through the player's 전략 포인트 도넛: tap it once to
  flip it into a circular 턴 넘기기 button, tap again to end. The 턴 넘기기
  face stays disabled until the player spends at least 1 작전 점수 (tracked
  via `card_phase_entry_cost`); tapping anywhere else flips it back to the
  point readout.
- AI auto-plays affordable cards on phase end. Phase end also re-runs recalls
  (HP threshold + out-of-position card displacement).

### Engage (전투 개시) — 실시간 MOBA 교전
Card-driven sub-phase: `engage:N` opens a full-screen **real-time** arena
during CARD_PHASE (관전 전용 — no player input). Returns to CARD_PHASE on
close — see [`engage/README.md`](engage/README.md) for details. Key contract:
- Participants = pilots in radius-1 hex from caster (caster cell + 6 neighbors).
  `exclude_lane` drops lane pilots still on their lane row; junglers and
  displaced-into-jungle lane pilots stay in. Still supported end-to-end, but
  the only card that used it (교전, id 4) has been removed from the pool.
- **`engage:N` = `N × RealtimeEngageSim.SEC_PER_ROUND` 초** (현재 3.0 → 9초),
  not N rounds. `duel` runs to first KO with a `DUEL_MAX_SEC` cap.
- Battlefield hex positions map 1:1 into arena coordinates, so pilots start
  where they stood. Same-cell allies spawn clumped together.
- **교전 중 이탈은 없다** — 아무도 아레나를 뜰 수 없고, 시간이 끝나면 그
  프레임에 즉시 종료된다(engage:3 = 정확히 9초). 종료는 시간 만료 또는 한 쪽
  전멸뿐. 빈사(HP<30%)여도 후퇴하지 않는다.
- Per-pilot AI: 근접은 사거리에 들 때까지 계속 쫓고(원거리보다 이동속도 1.1배,
  시전자 근접이면 개전 1회 대쉬), 원거리는 자기 사거리 안에서 붙은 적과 거리를
  벌리며 계속 쏜다(사거리 끝에 닿으면 후진 대신 타겟 주위를 선회). 공격 시
  짧은 경직.
- Turrets within 2 hexes appear in the arena and **do attack pilots** (unlike
  on the battlefield). AI avoids enemy turret range unless a survive-kill-escape
  계산 approves a dive. Turret HP is not damaged in the arena.
- Damage uses the same `hit/(hit+evasion)` + shield-first formula as the
  battlefield. KO sets `respawn_timer = RESPAWN_TURNS` (battlefield-equivalent).
  `grid_pos` is never modified by an engage.
- Dashboard shows per-pilot dealt / taken / kills before resuming.

### Pilot Animations (UI-only, additive on top of logical state)
Pilot logical state (grid_pos, hp, alive…) updates instantly when the sim
ticks; the renderer reads animation timers from `PilotData` to soften the
visual transitions. All durations fit inside the 0.5s `AUTO_PLAY_INTERVAL`.

| Trigger | Site | Visual |
|---|---|---|
| Combat / card damage | `SimulationCore` damage_map apply, `CardPhaseManager.apply_card_effect` | `anim_pilot_shake` → 0.18s horizontal jitter (decaying) |
| Movement (free + push advance + push retreat) | `_move_pilot` / `_push_advance` / `_push_retreat` | `anim_pilot_move(p, orig)` → 0.30s ease-out tween from `orig` cell to `grid_pos` |
| Recall (HP-threshold or phase-end out-of-position) | `RecallSystem._teleport_home` | `anim_pilot_recall(p, orig)` → 0.20s fade-out + rise at `orig`, then 0.25s fade-in + descend at HQ |
| Respawn | `SimulationCore.process_respawns` | `anim_pilot_respawn` → fade-in + descend at HQ only (skip phase 1) |

`BattleSim._process` runs `_advance_pilot_animations(delta)` every frame and
calls `renderer.queue_redraw()` while any timer is active. Constants live on
`BattleSim`: `ANIM_MOVE_DUR`, `ANIM_SHAKE_DUR`, `ANIM_SHAKE_AMP_PX`,
`ANIM_RECALL_FADE_OUT_DUR`, `ANIM_RECALL_FADE_IN_DUR`, `ANIM_RECALL_RISE_PX`.

`BattleRenderer` groups pilots by `_render_cell(p)` (= `anim_recall_orig`
during fade-out, otherwise `grid_pos`) and applies per-pilot pixel offset and
alpha via `_pilot_anim_offset` / `_pilot_anim_alpha`.

---

## Dependencies

- `resources/GameEnums.gd` — shared enums
- `resources/PilotData.gd`, `TurretData.gd` — data classes
- `autoloads/GameManager.gd` — match_ctx + cards table loader
- `scenes/Card.tscn` (script: `features/battle_sim/card_phase/Card.gd`) — card visual node
- `scenes/BattleField.tscn` — TileMapLayer + Building/Waypoint child scenes
