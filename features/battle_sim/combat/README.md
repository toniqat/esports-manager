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
4. **Same-cell engagement resolution** — see "Combat" section below.
5. **Movement** for non-engaged pilots (`_move_pilot`). Multi-step movement
   stops as soon as the pilot's current cell contains an enemy, so a fast
   mover cannot walk past an enemy in a single tick.
6. Apply collected pilot / turret damage. T1 destruction triggers
   `_on_t1_destroyed` (jungle capture). Any destroyed turret also frees the
   corresponding `Building` node from `BuildingLayer`.
7. **Push** moves: advance / retreat by 1 cell for unilateral combat winners
   and losers.
8. HQ damage: any pilot sitting on enemy HQ once any defender T2 is down.
9. `process_neutral_zone_captures` — junglers stepping on a neutral cell flip it.
10. `check_win_condition` — HQ HP ≤ 0 → game over.

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

Two enemies that approach each other on a lane will collide in a shared cell
because `_move_pilot` halts further multi-step movement as soon as the
pilot's current cell contains an enemy. From that shared cell, same-cell
combat takes over on the following turn.

Turrets do not attack pilots (the old retaliation logic has been removed).

### Movement
- `_move_pilot(p)` — up to `move_range` calls of `_step_pilot_once`. Each
  iteration first checks `_has_engaging_enemy_at(p.grid_pos, p)` and breaks
  if a same-scope enemy (jungler vs jungler, or lane vs lane) shares the
  cell, so a pilot that just stepped into a real opponent stops there for
  same-cell combat next turn. Cross-scope contacts are ignored.
- **Lane pilots also break the step loop when standing on an alive enemy
  turret cell** — the pilot must engage and destroy the turret before
  advancing further. Junglers are exempt (they never interact with turrets).
- `_step_pilot_once(p)`:
  - Jungler → `_jungle_goal_for(p)` (uncaptured neutral, else farthest own-captured cell to roam).
  - Support whose same-lane SNIPER is dead or sitting at own HQ
    (`_supporter_should_fall_back`) → forward-most alive own-team turret cell on
    the support's lane (`_own_forward_turret_cell`); falls back to
    `current_waypoint(p)` if every own-lane turret is down.
  - All other lane pilots (including Support with sniper alive on lane) → `current_waypoint(p)`.
    SUPPORT no longer chases weak allies — the right-lane SNIPER/SUPPORT pair
    stays coupled because both follow the same lane path every turn.
- All pathfinding calls pass `_movement_forbidden_for(p)` to `bfs_next_step`:
  - Junglers receive `{}` (no restrictions).
  - Lane pilots receive jungle/neutral cells **plus alive enemy turret cells in
    lanes other than their own**. The same-lane enemy turret stays reachable
    (so the pilot can engage and damage it). This stops e.g. right-lane pilots
    from routing through the still-alive center T2 cell on their way to the
    enemy HQ after their own-lane turrets are down.
  - The forbidden dict is rebuilt fresh per call — `_bs.neutral_zone_cells` is
    never mutated.
- Push helpers: `_push_advance(p)` (toward goal) and `_push_retreat(p)` (toward
  own HQ for lanes; toward nearest own-captured cell for junglers; rolls back
  `waypoint_idx` accordingly). Both honour the same forbidden set. `_push_advance`
  additionally bails out for lane pilots already on an alive enemy turret cell
  so push wins cannot punt a pilot past an undefeated turret. `_push_retreat`
  is unaffected — retreating away from a turret is always allowed.
- `current_waypoint(p)` — auto-advances `waypoint_idx` when pilot stands on the current waypoint cell.

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
  not move — the card is a single-pilot push, not a full battle tick.
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

- `_move_pilot` / `_push_advance` / `_push_retreat` capture the pilot's cell
  before the move and call `_bs.anim_pilot_move(p, orig)` if the cell changed.
- The damage_map application loop calls `_bs.anim_pilot_shake(p)` for surviving
  pilots that took damage > 0.
- `process_respawns` calls `_bs.anim_pilot_respawn(p)` after reviving the pilot
  at HQ.
- `RecallSystem._teleport_home` calls `_bs.anim_pilot_recall(p, orig_pos)`
  after snapping `grid_pos` to HQ — visuals fade out at `orig_pos` first,
  then fade in at HQ.

Logical state is unaffected: the sim never reads animation fields on
`PilotData`. Animation timing constants live on `BattleSim`.
