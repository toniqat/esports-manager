# Combat Modules

All scripts extend `Node` and are children of the root `BattleSim` node.
Each module accesses shared state via `@onready var _bs: BattleSim = get_parent() as BattleSim`.

## Pathfinding.gd
BFS pathfinding with greedy fallback (hex grid).
- `bfs_next_step(from, to, forbidden_cells={})` → Vector2i
- `greedy(from, to, forbidden_cells={})` → Vector2i
- `neighbors(pos, forbidden_cells={})` → Array[Vector2i]

`forbidden_cells` is a Dictionary used as a set (only `.has()` is read). Neighbors
present in `forbidden_cells` are dropped during expansion. The starting cell is
never filtered, so a displaced pilot can always step out of an otherwise-forbidden
region. SimulationCore uses this to keep lane pilots out of jungle cells.

## RecallSystem.gd
**복귀 = 본진 귀환.** Two triggers, one shared path:

- **저HP 복귀** — at HP ≤ `RECALL_HP_THRESHOLD` the pilot goes home.
- **위치 이탈 복귀** — a card effect dropped the pilot on a jungle cell or on
  **another lane's corridor**.

Both call `return_to_hq(p, log_lines, reason)`, which snaps `grid_pos` to the
HQ, **restores HP to full**, clears `shield`, and resets `waypoint_idx` to 0.
`alive` is not touched: **the only thing that takes a pilot off the field is
death.** A recalled pilot is standing in its own HQ, in play, targetable, and
counted by every sweep in the sim.

**The cost of a recall is the walk back, not a heal timer.** `return_to_hq`
sets `PilotData.recall_hold`, and `resolve_movement` spends that flag to skip
the pilot for exactly one movement pass (logged as a `BLOCK`). So the pilot
stands at the HQ on the turn it recalls and starts walking its lane from
waypoint 0 **the next turn** — however low it dropped, the absence is however
many turns the walk to the front takes. The old model (leave the field, heal
`RECALL_HEAL_RATIO` per turn, return the turn after hitting full) is gone
together with that config key.

Because recalls never leave the field, `respawn_timer` and
`BattleSim.turns_until_return(p)` are now **death-only**. Anything that needs
"turns left" — the card lock overlay, BattleLogger's `dead:N` tag — still goes
through `turns_until_return` rather than reading the timer directly.

The 복귀 card (`recall_ally`, `CardPhaseManager._effect_recall_ally`) does the
same thing minus the hold: instant HQ teleport at full HP, free to walk out the
same turn.

- `process_recalls(log_lines)` — runs each BATTLE turn; called from
  `SimulationCore.simulate_turn()` before combat. Low-HP rule only.
- `process_phase_end_recalls(log_lines)` — runs at end of CARD_PHASE and at the
  end of the AI turn; applies the low-HP rule OR the out-of-position rule.
- `_is_out_of_position(p)` — jungler on enemy-owned jungle, lane pilot on any
  jungle cell, or lane pilot standing on another lane's corridor
  (`SimulationCore.lane_corridor`). The lane test requires **positive membership
  in a different lane**, never mere absence from its own: corridors are rebuilt
  with BFS, and a tie-break that differs by one cell from the route a pilot
  actually walked must never exile a correctly-positioned pilot. A deep jump
  along the pilot's *own* lane is legal by design — that is a split push.

## SimulationCore.gd
Main turn loop and all combat / movement / spawn logic. Each `simulate_turn`
counts as **1 minute** of in-game time.

### Turn loop (`simulate_turn`)
0. **`tick_growth_and_expiries`** — 성장 누적 + 턴 만료형 버프 회수. 턴의 맨
   앞이라야 이번 턴의 교전이 갱신된 스탯으로 굴러가고, 바로 뒤에 붙었다
   떼어지는 `pending_atk_buff` 가 성장 재계산에 지워지지 않는다. 아래
   "성장 / 라인전 스탯" 참조.
1. `process_respawns` — one sweep over everyone off the field, which now means
   the dead and only the dead: count `respawn_timer` down, return at own HQ at
   full HP when it hits 0.
2. Apply pending card-driven ATK buffs (existing flow).
3. `recall_sys.process_recalls` — HP ≤ threshold → home at full HP, holding
   still for this turn's movement pass.
4. **Same-cell engagement resolution** — see "Combat" section below. Fills
   `damage_map` / `turret_dmg` / `advance_set` / `retreat_set` / `engaged`
   from the pre-movement positions. Turret sieges are part of it: an attacker
   is a pilot **standing on** the enemy turret cell, so there is no separate
   adjacent-siege pass.
5. Apply collected pilot / turret damage. T1 destruction triggers
   `_on_t1_destroyed` (jungle capture). Any destroyed turret also frees the
   corresponding `Building` node from `BuildingLayer`.
6. **`resolve_movement`** — ONE pass that moves everybody: free movers and
   combat pushes together. See "Movement" below.
7. HQ damage: any pilot sitting on enemy HQ once any defender T2 is down.
8. `process_neutral_zone_captures` — junglers stepping on a neutral cell flip it.
9. `check_win_condition` — HQ HP ≤ 0 → game over.

**Damage is applied before movement, and movement is a single pass.** Both
matter. Damage first means a pilot killed this turn never moves and a turret
destroyed this turn is already gone for everybody's pathfinding — previously
free movement saw the pre-damage world and pushes saw the post-damage one.
A single movement pass is what makes the pass-through bug structurally
impossible; the two-pass split is described under "Movement".

### 성장 / 라인전 스탯 (`tick_growth_and_expiries`)
두 시스템이 같은 훅에서 돌지만 **건드리는 스탯이 겹치지 않는다** — 성장은
`atk` / `max_hp`, 라인전 스탯은 `hit` / `evasion`.

**성장** — 살아 있는 파일럿의 `atk` / `max_hp` 가 매 턴 `GROWTH_PER_TURN`
(game_config, **0.01** = +1%p) 만큼 원본 대비 늘어난다.
- **1턴부터 돈다.** `ECONOMY_START_TURN`(10턴) 게이트는 전략 점수 / 자동 드로우
  같은 **카드 경제** 전용이고 성장에는 걸리지 않는다.
- 스탯은 매 턴 곱해 나가는 대신 `PilotData.base_atk` / `base_max_hp` 에서
  **다시 계산**한다 — 매 턴 반올림이 끼면 오차가 누적돼 실제 성장률을 갉아먹는다.
  두 원본은 `PilotData._init` 이 채우므로 메크 스탯 주입(`_stats_for`)을 포함한
  모든 스폰 경로에서 비지 않는다.
- 최대 체력이 오른 만큼 현재 체력도 같이 올린다(`hp += new_max - max_hp`).
- **죽어 있는 파일럿은 성장하지 않는다.** 누적치(`growth`)는 그대로 남으므로
  부활하면 죽기 전 성장을 들고 돌아온다 — 사망의 비용에 "성장이 멈춘 시간"이
  포함되는 셈이다.
- 획득 배율(`growth_rate_mult`)은 안전한 파밍(턴 만료형)과 완벽한 마무리
  (작전 단계 만료형)가 건드린다. **같은 필드라 나중에 건 쪽이 덮어쓴다.**
  후자의 해제는 `clear_growth_until_phase(team)` 를 `CardPhaseManager` 가
  그 팀의 다음 작전 단계 진입 시 부른다.

**라인전 스탯** (`lane_stat_mod`, ±0.10) — `roll_hit` **하나에만** 걸린다.
전장 자동 교전과 공격 카드가 그 함수를 공유하므로 둘 다 반영되고, 교전 무대는
자기 확률 구간을 쓰므로 반영되지 않는다. 포탑 / HQ 피해는 명중 판정 자체가
없으므로 무관하다. 만료(`lane_stat_expire_turn`)는 성장 만료와 같은 훅에서
처리하며, **죽어 있어도 돈다** — 버프의 수명은 전장에 서 있는지와 무관하다.

### Combat (`_resolve_cell`)
Combat happens **only between pilots in the same cell**. There is no
adjacent-cell engagement and no concept of attack range.

Junglers and lane pilots run on **separate engagement scopes**. Each cell is
split into `t{0,1}_lane` (non-junglers) and `t{0,1}_jung` (junglers); a jungler
will never engage a lane enemy and a lane pilot will never engage an enemy
jungler. `_has_engaging_enemy_at` enforces the same rule for movement so a
jungler crossing a lane cell does not freeze on a lane enemy and vice versa.

Per cell with at least one pilot:
- **Lane scope (lane pilots only)**:
  - **Pilot vs pilot** (`_resolve_pilot_combat`): teams paired 1:1 by ascending HP
    *for damage rolls*. Each pair rolls hit independently. Hit chance =
    `attacker.hit / (attacker.hit + defender.evasion)` (`roll_hit`, public —
    card attacks share it, see `card_phase/README.md`) — **battlefield-only**;
    the 교전 무대 remaps this into its own 80~100% band
    (`ENGAGE_HIT_MIN` / `ENGAGE_HIT_MAX`, see `engage/README.md`), and the two
    are tuned independently. **라인전 스탯**(`lane_stat_mod`)이 붙는 유일한
    지점도 여기다 — `lane_adjusted()` 가 공격자의 `hit` 과 방어자의 `evasion` 에
    각자 자기 배율을 곱한다.
    Damage per landed hit is `_pilot_hit_damage(attacker)` =
    `atk × BATTLE_PILOT_DMG_MULT` (game_config, **0.35**), rounded, floored at 1.
    That multiplier covers **only damage pilots take from battlefield
    engagement** — the same helper is used by the turret-siege defender rolls.
    Pilot → turret and pilot → HQ damage stay at raw `atk` (siege speed is match
    length), and attack cards / the engage arena run their own numbers. It exists
    because a single unmitigated hit could exceed the whole recall window: an
    atk-28 opponent against a max_hp-75 sniper takes 37% per hit, so the sniper
    fell from above the 20% recall line straight to 0 and **the low-HP recall had
    no interval to fire in**. Damage from successful
    hits is applied at step 4 of the loop and only affects paired pilots.
    Push, however, is decided **at the team level for the whole bracket**:
    - Tally unilateral-hit wins per team across all pairs.
    - Side with strictly more unilateral wins sweeps: **every** pilot of that
      side in the cell (including unpaired ones, e.g. the spare in a 2v1)
      advances, **every** opposing pilot in the cell retreats.
    - Tie (including 0-0) → no push.
    - Unpaired pilots take no damage this turn but ride the team push.
    - The *net* result on the board is that **the whole cell slides one tile
      toward the loser's HQ**: the losers retreat and the winners follow them
      in, so the fight continues next turn one cell further up the lane. That
      is the lane push. The follow-up is only cancelled when the loser has
      nowhere to retreat to, or when the tile ahead is an enemy turret — see
      "Movement" step 3.
  - **Pilot vs enemy turret** — a lane pilot **occupies** the same-lane enemy
    turret cell. Advancing into it is an ordinary move (nothing bounces it back
    at destination-selection time), so the sequence is *enter this turn, attack
    next turn*. There is exactly one entry point, `_resolve_turret_combat`,
    reached from `_resolve_cell` → `_resolve_lane_at_turret` whenever a lane
    pilot stands on an enemy turret cell — walked in, pushed in behind a beaten
    enemy, or dropped there by a card. `resolve_turret_sieges` /
    `_apply_sieges_for` (the old adjacent-siege pass) are **gone**.
    - Judgement (`_apply_turret_siege`), in this order:
      1. **Turret damage is unconditional** — same-lane attackers put their full
         `atk` into the turret **with no hit roll** (`BATTLE_PILOT_DMG_MULT` is
         pilot-damage only). A defender camping the tile does not shield it.
      2. **Then attackers and defenders trade hit rolls**, paired by ascending
         HP, both directions dealing the halved `_pilot_hit_damage`. Attackers
         used to deal *nothing* to defenders — their whole attack went into the
         turret — so a defender sitting on its turret beat on the attacker for
         free. Now the attacker grinds the turret *and* still rolls on whoever
         is standing on it.

      T2 is invulnerable while own-lane T1 is alive (`_turret_attackable`), and
      the pilot-vs-pilot exchange runs regardless of that (the attackers are
      still in the cell with the defenders). Turret
      destruction frees the matching `Building` node via
      `building_registry.unregister(b); b.queue_free()` so the visual disappears.
    - **Knockback needs a defender.** After the judgement the attackers go into
      `retreat_set` **only if a same-lane defender stands on the cell**, and then
      unconditionally — the defender's roll may miss and the attacker still
      falls back to the tile it came from. With no defender there is nobody to
      push the attacker out: it stays on the turret and grinds it every turn.
      The single exception is an **unattackable** turret (T2 behind a live T1):
      there is nothing to grind, so the attacker always retreats and can never
      be frozen on it by card displacement.
    - Everyone on the cell is `engaged`, so an attacker with no defender holds
      its ground instead of walking on, and a defender is pinned only for as
      long as attackers stand on its turret.
    - Net cadence: turret damage **every turn** when undefended, **every other
      turn** when defended (enter → hit + pushed out → re-enter).
    - Off-lane lane pilots (e.g. a RIGHT pilot pushed into a CENTER turret cell
      by card displacement) are bystanders to the turret. If both teams have
      off-lane pilots in the cell they fight each other as pilot-vs-pilot;
      otherwise they sit out the turn and rely on the next phase-end recall to
      pull them out of position.
    - Junglers in the same cell are excluded entirely — they neither attack
      nor defend turrets.
- **Jungle scope (junglers only)**: jungler vs jungler runs in parallel using
  the same `_resolve_pilot_combat` rules, contained to the cell's junglers.

Two enemies that approach each other on a lane collide in a shared cell, and
same-cell combat takes over on the following turn. `resolve_movement` guarantees
it: nobody can move through anybody.

Turrets do not attack pilots (the old retaliation logic has been removed).

### Debug logging hooks
Every `grid_pos` mutation in this folder reports to `_bs.blog`
(`debug/BattleLogger.gd`) via `log_move(p, from, to, kind, note)`, and every
hold reports via `log_block(p, reason)`. `simulate_turn` stamps a `stage` name
before each pass so the log says which pass moved whom.
`_enemies_on_cell_str(p)` is a logging-only helper that names the enemies
standing on the pilot's cell right after a step. See
[`../debug/README.md`](../debug/README.md).

### Movement (`resolve_movement` — one simultaneous pass)

Free movement and combat pushes used to be two passes with damage application
between them, and neither looked at where it was sending a pilot. That let two
same-lane enemies trade cells inside one turn: an un-engaged pilot walked into
an enemy's cell, and that enemy — queued to advance from a fight it had just
won — pushed out into the cell just vacated. Both moves were individually legal,
so nothing caught it, and the pair passed through each other without engaging.
Confirmed twice by the cross detector in a 6-battle headless run before the fix,
zero times in 241 turns after it.

**There is now exactly one movement pass, and every pilot's intent is visible
inside it.**

1. **Intent** — every alive pilot gets one: `push-adv` / `push-ret` when combat
   decided one, *nothing at all* when it is in `engaged` without a push result
   (locked in melee), otherwise `free`. Push outranks `engaged`, matching the
   old two-pass behaviour. A pilot carrying `recall_hold` is skipped before any
   of that and the flag is cleared on the spot — that one skipped pass is the
   whole cost of a 본진 복귀, and clearing it here is what makes it exactly one.
2. **Lockstep rounds** — in each round, every still-moving pilot names its next
   cell against the *same* snapshot; conflicts are arbitrated; the survivors
   commit together. A `move_range` > 1 pilot takes part in more rounds, a push
   in exactly one. Because destinations are all chosen before any of them
   lands, nobody can walk into space another pilot is about to leave.
3. **Advance-over-a-stuck-enemy veto** (`_veto_advance_over_stuck_enemy`) —
   advance walks toward the *enemy* HQ and retreat walks toward the retreater's
   *own* HQ, and for the two sides of one fight those are **the same
   direction**, so both halves of a push name the same cell. That is intended:
   the winner follows the loser in and the lane moves one tile. This used to be
   inverted (`_veto_push_followthrough` cancelled the *advance* so the winner
   "held the ground"), and because the two destinations always coincide on a
   straight lane, a pilot that won its fight could never move forward — the
   loser drifted back and the line never advanced. The only thing vetoed now is
   an advance **over an enemy that is not leaving the cell** (`_stuck_enemy_on_cell`
   / `_is_leaving_cell`): nobody walks past a pilot still standing in the
   contested tile. Runs *after* head-on arbitration, since a move cancelled
   there turns that pilot into a stuck one. **An enemy turret cell is not a
   veto**: when the beaten side retreats onto its own turret the winner follows
   it in, and the siege takes over from that cell next turn.
4. **Head-on arbitration** (`_veto_head_on_exchanges`) — A aiming at B's cell
   while B aims at A's would be a pass-through. Vetoing *both* would leave them
   adjacent and deadlocked forever, so the higher-priority mover takes the step
   and the other holds: they finish in the same cell and fight next turn, which
   is what the engagement rules want. `_move_priority` = push (+10) over free,
   then team 0 (+1) as a deterministic tie-break — so the side that just won a
   fight keeps its advance. Cross-scope pairs (jungler vs laner) are skipped;
   they never engage, so sliding past each other is correct.
5. **Contact ends the turn** — after each round, any mover now sharing a cell
   with a same-scope enemy is deactivated and takes no further steps.
6. Animations fire once per pilot at the end, from the turn's original cell.

Destination helpers are pure — they compute a cell and never touch `grid_pos`,
so the resolver can veto a move after asking for it:
- `_desired_free_cell(p)` — holds (returns `p.grid_pos`) when a same-scope
  enemy already shares the cell. Otherwise defers to `_next_step_for(p)`, which
  may well name a same-lane enemy turret cell: the pilot walks onto it.
- `_next_step_for(p)` — raw goal + BFS, ignoring occupancy:
  - Jungler → `_jungle_goal_for(p)` (uncaptured neutral, else a **sticky** roam
    target — see "Jungler roaming" below).
  - **Every lane pilot → `current_waypoint(p)`, with no exceptions.** There is
    no defensive behaviour: a pilot does not turn around because its own turret
    is being hit. Pilots leave their HQ, walk their lane, and run into the enemy
    laner — that collision *is* the design. (An earlier SUPPORT fall-back that
    hugged the forward own turret when its same-lane SNIPER was down has been
    removed. It also had to be careful never to skip the `current_waypoint`
    call, since that call is what advances `waypoint_idx` — a trap that no
    longer exists now that there is only one goal.)
- `_desired_push_advance_cell(p)` — toward the lane goal (jungle goal for
  junglers). Nothing filters enemy turret cells out any more: a push win lands
  the winner **on** the turret, which is where the siege happens. (The old
  `_bounce_off_enemy_turret`, which turned such a step into a hold and paired
  with the adjacent-siege pass, is gone.)
- `_desired_push_retreat_cell(p)` — toward own HQ for lane pilots, toward the
  nearest own-captured cell for junglers. Never blocked by a turret —
  retreating away from one is always allowed. `_rollback_waypoint(p)` runs
  after the commit. **This is the same physical direction as the winner's
  advance** — read the two helpers as a pair: they are what makes a won fight
  slide the whole cell one tile up the lane.
- All pathfinding calls pass `_movement_forbidden_for(p)` to `bfs_next_step`:
  - Junglers receive `{}` (no restrictions).
  - Lane pilots receive jungle/neutral cells **plus alive enemy turret cells in
    lanes other than their own**. The same-lane enemy turret stays reachable —
    BFS must be willing to name it as the next step, because the pilot is meant
    to stand on it and besiege from there. This
    also stops e.g. right-lane pilots from routing through the still-alive
    center T2 cell on their way to the enemy HQ after their own turrets fall.
  - The forbidden dict is rebuilt fresh per call — `_bs.neutral_zone_cells` is
    never mutated.

### Lane corridors (`lane_corridor` / `lane_corridor_count`)
The per-lane set of cells the lane actually runs through, built once by
BFS-chaining that lane's waypoints with jungle cells forbidden, then cached in
`_lane_corridors`. Team 1's path is team 0's reversed, so the cell *set* is
shared and there is one entry per lane. Note `LANE_NAMES` also counts a
GUERRILLA slot — iterate with `lane_corridor_count()`, not `LANE_NAMES.size()`.

Its only consumer is `RecallSystem._is_out_of_position`, which asks "did a card
drop this lane pilot on somebody else's lane?".
- `current_waypoint(p)` — auto-advances `waypoint_idx` when pilot stands on the
  current waypoint cell. Safe to call more than once per turn (idempotent while
  `grid_pos` is unchanged), which the lockstep rounds rely on.

**What this does NOT prevent**: two enemies on *different* lanes standing one
cell apart and walking to different cells, ending with their lane-axis order
flipped. They never share a cell or an edge, and same-cell-only combat has no
zone of control, so neither could have engaged the other — most visible at an
HQ cell, where a recalled defender heads out down its own lane while an
attacker from another lane steps onto the HQ. The cross detector deliberately
ignores cross-lane pairs for this reason.

### Jungle / neutral zones
The map starts with both jungles already captured. Coordinates use the
TileMap negative-coord system:

| Owner   | Cells |
|---------|-------|
| Team 0  | (-2,0), (-2,-1), (-3,0), (0,0), (0,-1), (1,0) |
| Team 1  | (-2,-3), (-2,-2), (-3,-2), (0,-3), (0,-2), (1,-2) |
| Neutral | (-3,-1), (1,-1) |

- `init_neutral_zones()` — paints the initial owner of each cell.
- `process_neutral_zone_captures()` — a jungler standing alone on a neutral
  cell (no enemy in same cell) flips it to their team.

#### Jungler roaming (`_jungle_goal_for`)
An uncaptured neutral always wins. Once both neutrals are taken the jungler
roams to a **sticky** target parked on `PilotData.jungle_roam_target`, and the
target is only recomputed when it has been reached, was never set, or has
stopped belonging to the jungler's team (a lost T1 can flip a jungle cell). The
replacement is `_farthest_captured_cell(grid_pos, own_captured)` — the
own-captured cell farthest from where the jungler is standing *at that moment*.

The target used to be recomputed from scratch every turn, which is the same
coin flipped repeatedly: one step toward the far side makes the side just left
the farthest one, so the jungler turned around. In a logged battle A0 rode
`(-1,0) ↔ (-1,-1)` from turn 31 to the end of the match — and those are
**mid-lane** cells on the corridor between the two jungles, so it read as the
jungler loitering in front of its own mid T1 while the enemy sieged it. With a
sticky target the jungler completes the tour and comes to rest only on a jungle
cell; lane cells are crossed, never idled on. It still does not engage lane
pilots or turrets — see "Engagement scopes".
- `_on_t1_destroyed(td, log_lines)` — three priority branches keyed off
  per-lane "취약지점" (vulnerable cell) sets in `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}`.
  A vulnerable point is the jungle cell in a team's own territory closest to
  enemy territory along that lane: side lanes have 1 cell, mid has 2 flanking
  cells. When a team's same-lane T1 falls:
    1. **Restoration (all lanes)** — if any of the *capturer's* own same-lane
       vuln cells are currently owned by the loser, those cells flip back to
       the capturer and nothing on the loser's side is taken.
    2. **Side-neutral override (LEFT/RIGHT only)** — if the same-side neutral
       (`(-3,-1)` / `(1,-1)`) is owned by the loser, the capturer takes the
       neutral cell instead of the loser's vuln cell.
    3. **Default capture** — the loser's same-lane vuln cell(s) flip to the
       capturer. Side lanes flip 1 cell, mid flips both flanking cells. Mid T1
       has no neutral override (mid has no side neutral).

### Spawning
- `spawn_pilots_with_lanes()` — builds 5 player + 5 enemy `PilotData` using
  `GambitPhaseManager.ROLE_TO_LANE`. Stats come from `_stats_for(...)`.
- `_stats_for(...)` — when match_ctx is active, pulls hp/atk from the
  assigned mech AND hit/evasion from `PlayerData.mechanics` /
  `PlayerData.gamesense`. Otherwise falls back to `ROLE_STATS` defaults
  with `hit = evasion = 50`.
- `_pilot_id_from_roster(ctx_active, roster, idx, fallback_id)` — used to
  populate `pilot.pilot_id` (the portrait lookup key). Returns
  `roster[idx].id` only when ctx is active AND the id is inside the regular
  pool (`0..PilotImages.POOL_SIZE-1`). Otherwise returns `fallback_id`
  (player-side: `idx` 0..4; enemy-side: `5 + idx` 5..9). This guarantees
  every pilot — standalone runs, INTL matches with ids ≥ 100, malformed
  rosters — still gets a valid id so `PilotImages.face_for` /
  `PilotImages.circle_for` resolve to a real portrait instead of falling
  back to the placeholder colored disc.
- The assassin (GUERRILLA) gets `jungle_start_pref` from `match_ctx.jungle_start_dir`
  (player team) or randomly (enemy team).
- `spawn_turrets()` — reads from `FieldLoader.turret_pos`, falls back to
  hardcoded coordinates.

### Card-driven lane push (`advance_pilot` / `_advance_tick`)
Public entry point used by the 전진 (advance:N) card. Runs `N` mini-ticks; one
tick = `_advance_tick`, which pushes the lane one cell. It reuses the turn
loop's helpers (`_resolve_cell`, `_desired_push_*_cell`, `_apply_turret_siege`)
and changes exactly one thing about them: **the caster's side is declared the
winner of its cell.**

Order inside a tick — the same order `simulate_turn` uses, and it matters:

1. **`_resolve_cell` on the caster's cell** — damage rolls run untouched, so
   the caster can still get hit hard on the way in.
2. **Forced judgement** — every member of the caster's *group* (the caster plus
   every alive same-team, **same-scope** pilot on that cell,
   `_same_scope_allies_at`) is moved into `advance_set`, and every same-scope
   enemy on the cell (`_same_scope_enemies_at`) into `retreat_set`, whatever the
   dice said. Reading the unilateral-hit tally instead meant a bad roll turned
   the 전진 card into a retreat card — the caster walked back toward its own HQ.
   The exception is a caster **already standing on a same-lane enemy turret
   cell**: the turret rule wins, and it now splits by defender —
   - **defender on the cell** → the group hits the turret and falls back one
     tile. That is the only backwards move 전진 can produce.
   - **no defender** → the group hits the turret and **holds the cell** (in
     neither set). It keeps the turret pinned instead of walking off it.

   A caster that is a jungler, or on an *off-lane* enemy turret cell, ignores the
   turret entirely and advances as usual.
3. **`_apply_card_damage`** — pilots (보호막 first) then turrets, with T1
   destruction firing `_on_t1_destroyed`, exactly as step 5 of `simulate_turn`.
   A caster that died here stops the tick before anything moves.
4. **Movement** — enemies are pushed out first so the group has somewhere to
   land, then the group steps (`_step_pilot`). If an enemy could **not** be
   pushed (nowhere to retreat) the group holds: nobody walks past a pilot that
   is still standing in the contested cell.

Because the group and the pushed enemies move in the same physical direction,
the group normally lands on the cell the loser was just expelled to and the two
meet again one cell further up the lane — that is the lane push. In front of a
turret the loser ends up **on** the turret cell and the group follows it in;
the siege then runs from that cell on the next tick or turn. There is no
adjacent siege — a tick that only moves the group onto the turret deals no
turret damage.

Skips `process_respawns` / `process_neutral_zone_captures` /
`process_temp_zone_expiries` and does **not** bump `turn_count`. Win condition
is rechecked at the end so a turret-destruction kill via 전진 resolves
immediately.

### Misc helpers
- `t1_alive_in_lane`, `any_t2_destroyed`, `has_enemy_turret_at`
- `process_respawns`
- `check_win_condition`

### Animation hooks (UI-only side-effects)
SimulationCore and RecallSystem call back into `BattleSim` after mutating
logical state so the renderer can soften the transition:

- `resolve_movement` records each mover's cell at the start of the turn and
  calls `_bs.anim_pilot_move(p, orig)` once at the end for every pilot that
  actually moved — one tween per pilot per turn even across several lockstep
  rounds. `advance_pilot` does the same per mini-tick.
- The damage_map application loop calls `_bs.anim_pilot_shake(p)` for surviving
  pilots that took damage > 0 — **인자 없는 기본 세기**(0.18s / 6px)다. 공격
  카드는 같은 함수에 자기 상수(`ANIM_SHAKE_CARD_*`, 0.26s / 20px)를 넘겨 훨씬
  격렬하게 흔든다.
- The `turret_dmg` application loop calls `_bs.anim_turret_hit(td)` for turrets
  that took damage > 0 **and survived** — both in `simulate_turn` step 5 and in
  `_apply_card_damage`. A killing blow is skipped: the `Building` node is freed
  on the same line, so there would be nothing left to shake.
- `process_respawns` calls `_bs.anim_pilot_respawn(p)` after returning a **dead**
  pilot to HQ; that call also clears any leftover 전사 연출.
- `RecallSystem.return_to_hq` calls `_bs.anim_pilot_recall(p, orig_pos)` after
  snapping `grid_pos` to HQ — visuals fade out at `orig_pos`, then fade in at
  HQ. Both halves always play now (there is no "stay hidden for N turns" split
  any more), and the pilot is standing still that turn anyway, so the fade-in
  is anchored at the HQ for its whole duration.
- Every death goes through `_bs.mark_pilot_dead(p)`, which stamps the scaled
  respawn timer and starts `anim_pilot_death` — dimmed in place for
  `ANIM_DEATH_HOLD_DUR`, then fading upward off the field.

Logical state is unaffected: the sim never reads animation fields on
`PilotData`. Animation timing constants live on `BattleSim`.
