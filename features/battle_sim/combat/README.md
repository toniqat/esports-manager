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
Simplified recall: at HP ≤ `RECALL_HP_THRESHOLD`, the pilot is **instantly**
teleported to their HQ at full HP. No retreat march, no channeling.

- `process_recalls(log_lines)` — runs each BATTLE turn; called from
  `SimulationCore.simulate_turn()` before combat.
- `process_phase_end_recalls(log_lines)` — runs at end of CARD_PHASE; recalls
  any pilot under threshold OR any pilot whose grid_pos is outside their lane
  path / own-team jungle (covers card-effect displacement).
- `_teleport_home(p, log_lines, reason)` — internal helper.

## SimulationCore.gd
Main turn loop and all combat / movement / spawn logic. Each `simulate_turn`
counts as **1 minute** of in-game time.

### Turn loop (`simulate_turn`)
1. `process_respawns` — count down respawn timers, return at full HP.
2. Apply pending card-driven ATK buffs (existing flow).
3. `recall_sys.process_recalls` — instant HQ teleport for HP ≤ threshold.
4. **Same-cell engagement resolution** — see "Combat" section below. Fills
   `damage_map` / `turret_dmg` / `advance_set` / `retreat_set` / `engaged`
   from the pre-movement positions.
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
    `attacker.hit / (attacker.hit + defender.evasion)`. Damage from successful
    hits is applied at step 4 of the loop and only affects paired pilots.
    Push, however, is decided **at the team level for the whole bracket**:
    - Tally unilateral-hit wins per team across all pairs.
    - Side with strictly more unilateral wins sweeps: **every** pilot of that
      side in the cell (including unpaired ones, e.g. the spare in a 2v1)
      advances, **every** opposing pilot in the cell retreats.
    - Tie (including 0-0) → no push.
    - Unpaired pilots take no damage this turn but ride the team push.
    - The *net* result on the board is that the losers are expelled and the
      winners hold the contested cell — the movement pass vetoes an advance that
      would follow the retreat into the same cell. See "Movement" step 3.
  - **Pilot vs enemy turret** (`_resolve_lane_at_turret` → `_resolve_turret_combat`):
    only **same-lane** lane pilots interact with the turret. The cell's lane
    pilots are split by `pilot.lane == td.lane`:
    - Same-lane attackers damage the turret at 100% hit. Same-lane defenders
      roll on same-lane attackers (paired by HP). Damage from a defender hit
      stays per-pair, but retreat is **team-wide**: any successful defender hit
      forces every same-lane attacker in the cell (paired or not) to retreat
      together. Attackers do NOT retaliate against defenders during turret
      combat. T2 is invulnerable while own-lane T1 is alive. Turret destruction
      also frees the matching `Building` node via
      `building_registry.unregister(b); b.queue_free()` so the visual disappears.
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
   old two-pass behaviour.
2. **Lockstep rounds** — in each round, every still-moving pilot names its next
   cell against the *same* snapshot; conflicts are arbitrated; the survivors
   commit together. A `move_range` > 1 pilot takes part in more rounds, a push
   in exactly one. Because destinations are all chosen before any of them
   lands, nobody can walk into space another pilot is about to leave.
3. **Push follow-through arbitration** (`_veto_push_followthrough`) — advance
   walks toward the *enemy* HQ and retreat walks toward the retreater's *own*
   HQ, and for the two sides of one fight those are **the same direction**. Both
   halves of a push therefore named the same cell, landed together again and
   re-engaged there next turn, forever — a logged tank pair rode locked in one
   cell from (-4,-2) to the enemy HQ for twenty turns. When an advancer and a
   same-cell, same-scope enemy retreater name the same destination, the
   **advance** gives way: the loser is expelled from the contested cell and the
   winner holds the ground it just won. Every advancer out of that cell is
   vetoed, so a 2v1 sweep holds as a unit.
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
  enemy already shares the cell, or when a lane pilot stands on an alive enemy
  turret (it must destroy the turret before advancing; junglers are exempt).
  Otherwise defers to `_next_step_for(p)`.
- `_next_step_for(p)` — raw goal + BFS, ignoring occupancy:
  - Jungler → `_jungle_goal_for(p)` (uncaptured neutral, else farthest own-captured cell to roam).
  - Support whose same-lane SNIPER is dead or sitting at own HQ
    (`_supporter_should_fall_back`) → forward-most alive own-team turret cell on
    the support's lane (`_own_forward_turret_cell`); falls back to
    `current_waypoint(p)` if every own-lane turret is down.
  - All other lane pilots (including Support with sniper alive on lane) → `current_waypoint(p)`.
    SUPPORT no longer chases weak allies — the right-lane SNIPER/SUPPORT pair
    stays coupled because both follow the same lane path every turn.
- `_desired_push_advance_cell(p)` — toward the lane goal (jungle goal for
  junglers). Holds for a lane pilot already on an alive enemy turret cell, so
  push wins cannot punt a pilot past an undefeated turret.
- `_desired_push_retreat_cell(p)` — toward own HQ for lane pilots, toward the
  nearest own-captured cell for junglers. Never blocked by a turret —
  retreating away from one is always allowed. `_rollback_waypoint(p)` runs
  after the commit. **This is the same physical direction as the winner's
  advance**, which is why step 3 exists — read the two helpers as a pair.
- All pathfinding calls pass `_movement_forbidden_for(p)` to `bfs_next_step`:
  - Junglers receive `{}` (no restrictions).
  - Lane pilots receive jungle/neutral cells **plus alive enemy turret cells in
    lanes other than their own**. The same-lane enemy turret stays reachable
    (so the pilot can engage and damage it). This stops e.g. right-lane pilots
    from routing through the still-alive center T2 cell on their way to the
    enemy HQ after their own-lane turrets are down.
  - The forbidden dict is rebuilt fresh per call — `_bs.neutral_zone_cells` is
    never mutated.
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

### Card-driven single-pilot push (`advance_pilot`)
- Public entry point used by the 전진 (advance:N) card. Runs `N` mini-ticks
  for `caster` only — at each step it groups pilots by cell, calls
  `_resolve_cell` on the caster's current cell (so pilot-vs-pilot combat and
  same-lane turret damage / retreat use the standard rules), applies pilot
  HP / turret HP / T1 jungle capture exactly as `simulate_turn` does, and
  then either pushes/retreats the caster from the cell's `advance_set` /
  `retreat_set` membership or steps them once toward their lane goal when
  the cell was uncontested. Other pilots in the same cell take damage but do
  not move — the card is a single-pilot push, not a full battle tick. It uses
  the same `_desired_*_cell` helpers as `resolve_movement` but skips the
  lockstep machinery: only one pilot moves, so there is no simultaneity to
  arbitrate and no way to pass through anybody.
- Skips `process_respawns` / `process_neutral_zone_captures` /
  `process_temp_zone_expiries` and does **not** bump `turn_count`. Win
  condition is rechecked at the end so a turret-destruction kill via 전진
  resolves immediately.

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
  pilots that took damage > 0.
- `process_respawns` calls `_bs.anim_pilot_respawn(p)` after reviving the pilot
  at HQ.
- `RecallSystem._teleport_home` calls `_bs.anim_pilot_recall(p, orig_pos)`
  after snapping `grid_pos` to HQ — visuals fade out at `orig_pos` first,
  then fade in at HQ.

Logical state is unaffected: the sim never reads animation fields on
`PilotData`. Animation timing constants live on `BattleSim`.
