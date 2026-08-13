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
| EngagePhaseManager | Node | `engage/EngagePhaseManager.gd` | 전투 개시(engage) modal — **실시간 사이드뷰 벨트 교전** (`engage/RealtimeEngageSim.gd` ATB 시뮬 + `engage/EngageArena.gd` 렌더러) triggered by `engage:N` / `duel` cards. Lazily added in `_ready()`. |
| HudBuilder     | Node | `ui/HudBuilder.gd`         | HUD construction; 전략 포인트 도넛 (`ui/CostDonut.gd`) is the only interactive in-battle widget |
| BattleLogger   | Node | `debug/BattleLogger.gd`    | Full action log (console + `user://battle_logs/`) and enemy cross-over detector. Lazily added in `_ready()` after pilots spawn; reachable as `_bs.blog`. |

Cross-module calls go through `_bs`:
```gdscript
_bs.sim_core.simulate_turn()
_bs.pathfinder.bfs_next_step(...)
_bs.renderer.queue_redraw()
```

---

## BattleSim.gd (thin orchestrator)

Responsibilities:
- Declares all DB-driven config vars and **state vars** (pilots, turrets, neutral_zone_cells, game_phase, HUD refs, card state, `gambit_lanes`, `cards_played_this_phase`)
- Holds `@onready` refs to all child modules
- Public **coordinate helpers**: `cell_center(pos)`, `pilot_label(p)`, `role_stats_str(role)`
- **Lifecycle**: `_ready()`, `_process(delta)`
  - `_ready` calls `_gambit.auto_assign_lanes()` then `_gambit.launch_battle()` —
    no overlay, scene transitions straight into BATTLE.
  - `_process` auto-ticks `card_phase.do_battle_turn()` every `AUTO_PLAY_INTERVAL`
    seconds while `game_phase == BATTLE`. CARD_PHASE pauses the tick, and so does
    the 상대 차례 — that one runs *inside* BATTLE, so the guard also reads
    `_ai_turn_active()` (`card_phase.is_ai_turn_active()`). The same flag freezes
    `get_elapsed_ingame_seconds()`.
- **Button callbacks**: `_on_restart_pressed()` (the only manual entry point left).

---

## Data Classes (resources/)

| File | class_name | Description |
|---|---|---|
| `resources/PilotData.gd` | PilotData | role, hp/max_hp, atk, team, grid_pos, lane, waypoint_idx, **move_range**, **hit**, **evasion**, **jungle_start_pref**, **respawn_timer** (death-only off-field clock — see `BattleSim.turns_until_return`), **recall_hold** (본진 복귀한 턴의 이동 1회 스킵) |
| `resources/TurretData.gd` | TurretData | team, grid_pos, hp, tier, lane, alive |
| `resources/PlayerData.gd` | PlayerData | id, name, role, team_id, 5 stats (laning / mechanics / gamesense / teamfight / mental), `assigned_mech` |
| `resources/MechData.gd` | MechData | id, name, hp, atk, **presence** (4=melee/2=ranged; engage 무대의 타겟 어그로 가중치로만 사용), **speed** (40~100; engage 무대의 ATB 충전 속도로만 사용 — 전장은 읽지 않는다) |

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
- **Free movement and combat pushes resolve in one simultaneous pass**
  (`SimulationCore.resolve_movement`), so two same-scope enemies can never
  trade cells or move through each other. A pilot mid-move stops as soon as it
  shares a cell with a same-scope enemy; a head-on exchange is arbitrated so
  one side takes the cell and the two meet there. Cross-scope contacts
  (jungler vs lane pilot) are ignored, so a jungler crossing a lane never
  freezes on — or is blocked by — a lane enemy.
- **Pilots are not attacked by turrets.**
- **전진 = 라인 푸쉬, 그리고 포탑 칸에 실제로 올라선다.** A lane pilot whose next
  lane step is a same-lane enemy turret **occupies that cell** — free walk-ups,
  engagement winners following the losers in, and the 전진 card alike. There is
  no adjacent "step in and bounce out" siege any more; entering costs a turn and
  deals no damage.
- **A pilot standing on an enemy turret cell attacks it that turn, with no hit
  roll** — full `atk` straight into the turret (`_resolve_turret_combat`). Then:
  - a same-lane **defender on that cell** and the attacker **trade hit rolls**
    (paired by HP, halved `_pilot_hit_damage` both ways), and the attacker is
    pushed back to the tile it came from — **hit or miss, the knockback
    happens**;
  - **no defender → no knockback.** The attacker stays on the turret and grinds
    it every turn. An undefended turret simply falls.
  - The one extra bounce: an **unattackable** turret (T2 while its own-lane T1
    stands) never holds an attacker — nothing to grind, so it retreats. Only
    card displacement can put a pilot there.
- **농성 중인 수비자도 맞는다** — the turret takes its damage first and
  unconditionally, and *on top of that* the attacker rolls on the defender
  standing on it. Camping a turret used to be a free beating of the attacker
  (attackers dealt zero to defenders); now it is a mutual exchange. A defender is
  `engaged` only while attackers stand on its turret.
- Turret damage cadence follows from the above: **every turn** on an undefended
  turret, **every other turn** on a defended one (enter → hit + get pushed out →
  re-enter).
- Off-lane lane pilots in a turret cell ignore the turret entirely; if both
  teams have off-lane lane pilots there they may still fight each other as
  pilot-vs-pilot. Junglers are always spectators at turret cells. T2 is
  invulnerable while its own-lane T1 stands.
- When a turret is destroyed, the matching `Building` node in
  `BattleField/BuildingLayer` is unregistered and `queue_free`'d so the
  sprite disappears from the field.

### Recall / Respawn
- **복귀 = 본진 귀환.** Two triggers, one path (`RecallSystem.return_to_hq`):
  HP ≤ `RECALL_HP_THRESHOLD`, **or** a card effect that dropped the pilot on a
  jungle cell / on **another lane's corridor**.
- **복귀는 전장을 비우지 않는다.** The pilot lands in its own HQ **at full HP**
  on the spot, `alive` untouched — a pilot only ever leaves the field by dying.
  The cost is the walk back: `return_to_hq` sets `PilotData.recall_hold`, and
  the next `resolve_movement` spends it to hold the pilot still for exactly one
  pass, so it starts down its lane from waypoint 0 **the following turn**.
- The old model — leave the field, heal `RECALL_HEAL_RATIO` of `max_hp` per
  turn, come back the turn after hitting full — is gone, and so is that
  game_config key.
- A deep jump along the pilot's **own** lane is legal, however far into enemy
  territory it lands. That is a split push, not a displacement.
- The 복귀 (`recall_ally`) card is the same teleport minus the hold: instant
  full-HP HQ landing, free to walk out the same turn.
- **Only the dead are off the field** (`alive = false`), so `respawn_timer` and
  **`BattleSim.turns_until_return(p)`** are death-only clocks. Anything needing
  "turns left" still calls the helper rather than reading the timer.
- **Respawn length scales with match time**: `BattleSim.respawn_turns_now()` =
  `RESPAWN_TURNS` (game_config, default **5**) + `turn_count / 10`. An early
  death costs 5 turns, a late one grows with the clock. The DB value used to be
  a flat 16, which meant one death in the opening minutes erased the whole
  laning phase. **`BattleSim.mark_pilot_dead(p)` is the only place a pilot
  dies** — battlefield combat, 전진, 공격 카드 and the engage arena all funnel
  through it, so the scaling and the 전사 연출 can never be wired into one path
  and forgotten in another.
- During CARD_PHASE the recall check is paused; it runs again at end of phase
  via `process_phase_end_recalls`.

### Lanes / movement
- Pilots follow waypoint lane paths (Left / Center / Right) loaded from `BattleField/WaypointLayer`.
- The old "minion line" / "lane strength" concept is gone. Lane pilots simply
  step toward `current_waypoint(p)` each minute.
- **Lane pilots are forbidden from entering jungle/neutral cells AND alive
  enemy off-lane turret cells.** Pathfinding receives the union of the
  jungle-cell set and every alive enemy turret in a lane other than the
  pilot's own. Same-lane enemy turret cells remain reachable — BFS has to be
  willing to name one as the next step, since that is exactly what the siege
  check reads. This prevents e.g. right-lane pilots from being routed through
  the still-alive center T2 cell after their own-lane turrets fall.
- **There is no defensive behaviour.** A lane pilot's goal is always
  `current_waypoint(p)`; nobody turns around because an own turret is under
  attack. Pilots leave their HQ, follow their lane, and run into the enemy
  laner — that collision is the design. (The old SUPPORT fall-back that hugged
  the forward own turret while its same-lane SNIPER was down is removed.)
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
  face stays disabled until the player **plays at least one card** this phase
  (tracked via `cards_played_this_phase`) — or until the hand holds nothing
  playable at all, which passes straight through so the phase can't deadlock.
  Tapping anywhere else flips it back to the point readout.
- Phase end re-runs recalls (HP threshold + out-of-position card displacement)
  and drops straight back to BATTLE.
- **The AI's turn is its own**, no longer stapled to the player's phase end:
  it fires from the BATTLE tick when `ai_cost >= PHASE_THRESHOLD` *and* the AI
  holds a card it can pay for, and only then does the "상대 차례" banner show.
  It runs inside BATTLE with the auto-tick held, then runs the same recall
  sweep. See [`card_phase/README.md`](card_phase/README.md).

### Engage (전투 개시) — 사이드뷰 벨트 교전 (ATB)
Card-driven sub-phase: `engage:N` opens a **real-time side-view belt-scroll
stage** (관전 전용 — no player input). On close it returns to the phase that
opened it — CARD_PHASE for a player card, BATTLE for an AI card played during
상대 차례 — see [`engage/README.md`](engage/README.md) for details. Key contract:
- Participants = pilots in radius-1 hex from caster (caster cell + 6 neighbors).
  `exclude_lane` drops lane pilots still on their lane row; junglers and
  displaced-into-jungle lane pilots stay in. Still supported end-to-end, but
  the only card that used it (교전, id 4) has been removed from the pool.
- **`engage:N` = `N × RealtimeEngageSim.SEC_PER_ROUND` 초** (현재 3.0 → 9초),
  not N rounds. `duel` runs to first KO with a `DUEL_MAX_SEC` cap.
- **전장 셀 위치는 배치에 반영되지 않는다.** 무대는 팀0 왼쪽 / 팀1 오른쪽으로
  마주 선 평면 벨트이고, 자리는 역할이 정한다 — 근접은 앞줄, 원거리는 뒷줄.
- **ATB**: 각 유닛이 메크 `speed` 스탯(mechs.csv, 40~100)에 비례해 차오르는
  **보이지 않는 게이지**를 굴린다. 만충되면 대상에게 **접근 → 공격 → 원위치
  복귀**. 게이지는 행동 중에도 차므로 빠른 메크는 느린 메크가 한 번 움직일 때
  두 번 움직인다. 근접은 밀착(88px)까지, 원거리는 **최대 사거리의 90%**(270px)
  까지 파고든 다음 때린다. 사거리 판정에는 `STRIKE_DIST_EPSILON` 여유가 붙는다
  — 없으면 사거리에 딱 맞춰 선 유닛이 부동소수 오차로 판정을 통과하지 못해
  공격이 아예 성립하지 않는다. 명중하면 대상이 넉백되고 **밀려난 자리가 새
  앵커가 된다**(피해에는 얹히지 않고 위치와 재접근 거리만 바꾼다).
- **교전 중 이탈은 없다** — 아무도 무대를 뜰 수 없고, 시간이 끝나면 그
  프레임에 전투가 멈춘다(engage:3 = 전투 시간 정확히 9초). 종료는 시간 만료
  또는 한 쪽 전멸뿐. 빈사(HP<30%)여도 후퇴하지 않는다.
- **종료 → 대시보드 사이에 `EngagePhaseManager.END_HOLD_SEC`(2.0초) 유예**가
  있다. 마지막 처치가 결과창에 먹히지 않도록 전투만 멈춘 무대를 2초 더
  보여 주고(잔여 연출은 `RealtimeEngageSim.step_afterglow`), 상단에 종료
  사유 배너(`적군 전멸` / `시간 종료` …)를 띄운다. 유예 동안 `elapsed` 는
  멈추므로 대시보드의 교전 시간은 실제 전투 시간 그대로다.
- **암살자는 적 뒷줄(원거리)을 우선 타겟으로 삼는다** (`DIVE_FOCUS`). 이
  분기가 없으면 앞줄이 더 가깝고 존재감도 두 배라 원거리 메크가 교전 내내
  한 대도 맞지 않는다 — 실측으로 확인된 구멍이다.
- **포탑은 사거리 존이 아니라 참가자다**: 참가 파일럿이 자기 팀 포탑 칸 위에
  서 있으면 그 포탑이 교전에 가담해 **자기 ATB(`game_config.TURRET_SPEED`)로
  적 파일럿을 공격한다**(사거리 제한 없음, 명중 판정은 굴린다). 무대에서
  포탑 HP 는 깎이지 않는다.
- Damage (atk 1회분 + shield-first) matches the battlefield, but **명중률은
  별개**: 교전은 전장 확률 `base` 를 **80~100% 구간**으로 리맵한다
  (`ENGAGE_HIT_MIN` 0.80 / `ENGAGE_HIT_MAX` 1.00 → 스탯이 대등하면 90%).
  KO routes through `BattleSim.mark_pilot_dead`, so an arena kill gets the same
  scaled respawn timer (`respawn_turns_now()`) a battlefield kill does.
  `grid_pos` is never modified by an engage.
- 화면은 가로로 납작한 **시네마 밴드** 하나(1032×500)와 그 **아래 참가자
  초상화 + 체력 바 스트립**으로 구성된다. Dashboard shows per-pilot dealt /
  taken / kills before resuming.

### Action logging (`debug/BattleLogger.gd`)
Every turn writes a full transcript to the console **and** to
`user://battle_logs/battle_<timestamp>.log`: before/after position snapshots,
per-cell engagement brackets, the engaged / advance / retreat sets, every
`grid_pos` mutation tagged with the sim pass that caused it, damage, deaths,
turret HP, HQ chip, jungle captures and card plays. `end_turn()` also diffs the
snapshots and flags `!!SWAP` / `!!CROSS` when two same-lane enemies trade
places without engaging. Defaults to on — flip `blog.enabled` in
`BattleSim._ready()` to silence it. Full format in
[`debug/README.md`](debug/README.md); the pass-through bug it surfaced (and the
single-pass movement rewrite that fixed it) is written up in
[`combat/README.md`](combat/README.md).

### Pilot Animations (UI-only, additive on top of logical state)
Pilot logical state (grid_pos, hp, alive…) updates instantly when the sim
ticks; the renderer reads animation timers from `PilotData` to soften the
visual transitions. All durations fit inside the 0.5s `AUTO_PLAY_INTERVAL`.

| Trigger | Site | Visual |
|---|---|---|
| Combat / card damage | `SimulationCore` damage_map apply, `CardPhaseManager.apply_card_effect` | `anim_pilot_shake` → 0.18s horizontal jitter (decaying) |
| Movement (free + push advance + push retreat) | `resolve_movement` (once per pilot per turn) | `anim_pilot_move(p, orig)` → 0.30s ease-out tween from `orig` cell to `grid_pos` |
| Recall — 저HP / 위치 이탈 | `RecallSystem.return_to_hq` | `anim_pilot_recall(p, orig)` → 0.20s fade-out + rise at `orig`, then 0.25s fade-in + descend at HQ. Both halves always play — the pilot never leaves the field, and it is holding still that turn, so the fade-in stays anchored at the HQ |
| Recall — 복귀 카드 | `CardPhaseManager._effect_recall_ally` | same `anim_pilot_recall(p, orig)` sequence |
| Respawn (사망 후 부활) | `SimulationCore.process_respawns` | `anim_pilot_respawn` → fade-in + descend at HQ only (skip phase 1); also clears any leftover 전사 연출 |
| 사망 | `BattleSim.mark_pilot_dead` | `anim_pilot_death` → `ANIM_DEATH_HOLD_DUR` (1.0s) dimmed-in-place at the cell they fell on, then `ANIM_DEATH_FADE_DUR` (0.45s) fading out while rising `ANIM_DEATH_RISE_PX`, then off the field |
| 공격 카드 명중 / 빗나감 | `CardPhaseManager._effect_attack` | `BattleRenderer.spawn_pilot_popup` → `-N` / `MISS` / `흡수` floating over the target's marker |
| 포탑 피격 | `SimulationCore` turret_dmg apply (`simulate_turn` + `_apply_card_damage`), survivors only | `anim_turret_hit(td)` → `ANIM_TURRET_HIT_DUR` (0.26s) of decaying horizontal jitter (`ANIM_TURRET_HIT_AMP_PX` 9px) plus an `ANIM_TURRET_HIT_TINT` red flash fading back to white |

`BattleSim._process` runs `_advance_pilot_animations(delta)` **and**
`_advance_turret_animations(delta)` every frame (both, never short-circuited)
and calls `renderer.queue_redraw()` while any timer is active. Constants live on
`BattleSim`: `ANIM_MOVE_DUR`, `ANIM_SHAKE_DUR`, `ANIM_SHAKE_AMP_PX`,
`ANIM_RECALL_FADE_OUT_DUR`, `ANIM_RECALL_FADE_IN_DUR`, `ANIM_RECALL_RISE_PX`,
`ANIM_DEATH_HOLD_DUR`, `ANIM_DEATH_FADE_DUR`, `ANIM_DEATH_RISE_PX`,
`ANIM_DEATH_TINT`, the turret trio `ANIM_TURRET_HIT_DUR` /
`ANIM_TURRET_HIT_AMP_PX` / `ANIM_TURRET_HIT_TINT`, and the popup trio
`DMG_POPUP_DUR` / `DMG_POPUP_RISE_PX` / `DMG_POPUP_STAGGER`.

**포탑 연출만 렌더러 밖에 있다.** A turret's sprite is a `Building` node under
`BattleField/BuildingLayer`, not something `BattleRenderer._draw()` paints, so
`BattleSim._apply_turret_hit_visual` writes the shake/flash straight onto that
node's `position` / `modulate` (base position cached per cell in
`_turret_home_pos`, restored on the last frame and on restart via
`_clear_turret_hit_visuals`). The renderer only mirrors the same offset onto the
turret HP bar by reading `BattleSim.turret_hit_offset(td)`.

`BattleRenderer` decides *whether* to draw a pilot with `_is_renderable(p)`
(alive, or mid-death, or mid-recall-fade-out — the last two run after `alive`
is already false), groups them by `_render_cell(p)` (`anim_recall_orig` during
fade-out, `anim_death_cell` during the 전사 연출, otherwise `grid_pos`) and
applies per-pilot pixel offset and alpha via `_pilot_anim_offset` /
`_pilot_anim_alpha`.

---

## Dependencies

- `resources/GameEnums.gd` — shared enums
- `resources/PilotData.gd`, `TurretData.gd` — data classes
- `autoloads/GameManager.gd` — match_ctx + cards table loader
- `scenes/Card.tscn` (script: `features/battle_sim/card_phase/Card.gd`) — card visual node
- `scenes/BattleField.tscn` — TileMapLayer + Building/Waypoint child scenes
