# Combat Modules

표시 텍스트는 l10n key (`battle` 도메인) — this folder has none: its Korean strings are diagnostics (`_bs.blog`, recall / advance `log_lines` → `last_log`), marked `# l10n-ignore`.

All scripts extend `Node` and are children of the root `BattleSim` node.
Each module accesses shared state via `@onready var _bs: BattleSim = get_parent() as BattleSim`.

## Pathfinding.gd
BFS pathfinding with greedy fallback (hex grid).
- `bfs_next_step(from, to, forbidden_cells={}, greedy_fallback=true)` → Vector2i
  (with `greedy_fallback = false` it returns `UNREACHABLE` when there is no path — used by callers
  that loosen the forbidden set and ask again. Reachability is carried as a bool: the old
  `found == (-1,-1)` sentinel treated a found path as not found when the mid cell `(-1,-1)`
  was the goal)
- `greedy(from, to, forbidden_cells={})` → Vector2i
- `neighbors(pos, forbidden_cells={})` → Array[Vector2i]

`forbidden_cells` is a Dictionary used as a set (only `.has()` is read). Neighbors
present in `forbidden_cells` are dropped during expansion. The starting cell is
never filtered, so a displaced pilot can always step out of an otherwise-forbidden
region. SimulationCore uses this to keep lane pilots out of jungle cells, and
`SimulationCore.jungle_step` uses it to keep **junglers out of enemy-owned jungle
cells whenever a path around exists** (see "Jungler roaming").

## RecallSystem.gd
**복귀 (return-to-base) = going back to base (본진 귀환).** Two triggers, one shared path:

- **Low-HP return (저HP 복귀)** — at HP ≤ `RECALL_HP_THRESHOLD` the pilot goes home.
- **Out-of-position return (위치 이탈 복귀)** — a card effect dropped the pilot on a jungle cell or on
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

The 복귀 (Return to Base) card (`recall_ally`, `CardPhaseManager._effect_recall_ally`) does the
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
0. **`tick_growth_and_expiries`** — collects turn-expiring buffs + recalculates everyone's stats.
   It must be at the very start of the turn so this turn's combat runs on the updated stats. See
   "Growth / laning stats" below.
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
   Right after it, `_apply_lane_bonds` spreads any retreat to the pilot's
   lane-bond partners (see "Lane bond" below).
5. Apply collected pilot / turret damage. T1 destruction triggers
   `_on_t1_destroyed` (jungle capture). Any destroyed turret also frees the
   corresponding `Building` node from `BuildingLayer`.
6. **`resolve_movement`** — ONE pass that moves everybody: free movers and
   combat pushes together. See "Movement" below.
7. HQ damage: any pilot sitting on enemy HQ once any defender T2 is down.
8. `process_neutral_zone_captures` — junglers stepping on a neutral cell flip it.
9. **Growth-point income (성장치 수입)** — `award_frontline_income` + `process_jungle_camps`. See
   "Growth-point income" below. It must run **after movement and capture are both done** so it is judged
   on that turn's final positions — on the turn a pilot walks into the front line it earns from that turn,
   and on a turn it is pushed out it earns nothing.
10. `check_win_condition` — HQ HP ≤ 0 → game over.

**Damage is applied before movement, and movement is a single pass.** Both
matter. Damage first means a pilot killed this turn never moves and a turret
destroyed this turn is already gone for everybody's pathfinding — previously
free movement saw the pre-damage world and pushes saw the post-damage one.
A single movement pass is what makes the pass-through bug structurally
impossible; the two-pass split is described under "Movement".

### Growth / laning stats (`tick_growth_and_expiries`)
The two systems **do not touch overlapping stats** — growth (성장) touches `atk` / `max_hp`,
laning stats touch `hit` / `evasion`.

**Growth — made by growth points (`PilotData.score`), not by time.**
This hook used to accumulate `GROWTH_PER_TURN` for every living pilot. That design had
two flaws, both fatal.
- Pilots grow even doing nothing → kills · turrets · farming have **no effect** on growth.
- `atk` and `max_hp` grow at **the same rate** → `atk / max_hp` is invariant, so
  "how many hits to die" does not drop by even one hit after 50 turns. It is not that growth was
  invisible — structurally it could not be seen.

Now all growth is derived from growth points in one place, `BattleSim.refresh_growth_stats`
— `GROWTH_PER_TURN` was deleted from game_config.
- **One curve, `BattleSim.growth_curve(score, is_hp)`** (× the pilot's growth coefficient):
  a piecewise log with slope `K · D^i / (C + score − SCORE_START)` (i = spikes reached,
  `C` = `GROWTH_CURVE_SCALE`, `D` = `GROWTH_SPIKE_SLOPE_DECAY`) plus a **spike** (`GROWTH_SPIKE_ATK` /
  `GROWTH_SPIKE_HP`) at every `GROWTH_SPIKE_STEP` k of absolute score up to `GROWTH_SPIKE_MAX`. Front-loaded,
  never capped, each milestone a jump and then a flatter slope. **Attack and HP currently use the same
  constants** (`GROWTH_ATK_CURVE` = `GROWTH_HP_CURVE`, `GROWTH_SPIKE_ATK` = `GROWTH_SPIKE_HP`) — reference
  ≈ +27% at 10k, +50% at 25k, +76% at 50k, +87% at 100k for both; the gap between the two comes only from
  the pilot's ATK / HP growth coefficients. Mech base attack (`mechs.csv` `atk`) was doubled when attack
  growth was lowered to the HP curve.
- Instead of multiplying every turn, stats are **recalculated** from `PilotData.base_atk` / `base_max_hp`
  — repeated rounding would let accumulated error eat into the growth rate.
  Both originals are filled by `PilotData._init`, so they are never empty on any spawn path,
  including mech stat injection (`_stats_for`).
- Current HP rises by however much max HP rose (`hp += new_max - max_hp`).
- Recalculation runs **the moment the score moves** (`BattleSim.add_score`) — it must be there, not at
  the turn boundary, so "got a kill and got stronger" reads as one beat. The recalculation left in this
  hook is **insurance**; what it actually does is sweep multiplier expiries.
- So **temporary** attack applied by cards must go on `PilotData.atk_buff`, not on `atk`.
  If pushed as `atk += buff` as before, a recalculation mid-turn (where a kill happened) erases
  the added amount, and the end-of-turn `atk -= buff` cuts into the original.
  `refresh_growth_stats` adds it last as `base × (1 + growth) + atk_buff`.
- **There is no income while dead, so growth stops too.** The accumulated total stays, so on
  respawn the pilot comes back carrying its pre-death growth.
- `growth_rate_mult` now multiplies **growth-point accrual**, not growth (turn-expiring for
  안전한 파밍 (Safe Farming) / operation-phase-expiring for 완벽한 마무리 (Perfect Finish)). Same result, one less layer of
  wiring. **It is the same field, so whichever is applied later overwrites.** The latter is cleared by
  `CardPhaseManager` calling `clear_growth_until_phase(team)` when that team enters its next operation
  phase (작전 단계).

**Laning stats** (`lane_stat_mod`, set from the card's `lane_stat:N` clause in cards.csv) — applied to **only** `roll_hit`.
Battlefield (전장) auto-combat and attack cards share that function so both reflect it; the engage (교전) stage
uses its own probability bands, so it does not. Turret / HQ damage has no hit check at all,
so it is unaffected. Expiry (`lane_stat_expire_turn`) is handled in the same hook as growth expiry,
and **runs even while dead** — a buff's lifetime is independent of standing on the battlefield.

### Growth-point income (`award_frontline_income` / `process_jungle_camps`)
Since growth comes from growth points (성장치), **where growth points are earned is the growth design itself**.
There are three sources and two are here (the third, kill bounty, is in `BattleSim.mark_pilot_dead`).

**Front line (전선) — lane pilots' income.** In each lane, the stretch **between both teams' living frontmost turrets**
(turret cells included) is the front line, and every turn a pilot stands inside it alive it earns `SCORE_FRONTLINE_PER_TURN` (const.csv).
- The boundary is `_front_boundary_index(team, lane, order)` — that team's living outermost
  turret (T1 → T2 order); if both are destroyed, the end of the corridor (that team's HQ side).
  **When T1 falls, the front line widens toward that team** — pushing in creates more room to earn.
- Front/back ordering is answered by `lane_corridor_order(lane)`. At the place where the corridor is linked
  with BFS, it numbers cells starting from the team-0 HQ side, writing the number **only on first visit**
  so segments that double back between waypoints cannot flip front and back.
- The answer changes whenever a turret falls, so `front_line_cells(lane)` is **not
  cached**. Three lanes × dozens of cells costs nothing.
- **Nothing is earned while walking out of HQ · while walking back after a low-HP return · while
  dead.** This is the real cost of death and return, which is why death carries no separate score
  penalty.
- **Junglers are excluded** — a jungler's front line is the jungle.

**Jungle camps (캠프) — the jungler's income.** Every **jungle/neutral cell** has one camp
(`BattleSim.jungle_camps`, `cell → ready_turn`); stepping on it eats `BattleSim.jungle_camp_score()` and that cell
refills only `JUNGLE_CAMP_RESPAWN_TURNS` later (both const.csv). **The two left/right neutral cells are included** — Herald (전령) / Dragon (용) only borrow those
coordinates as a stage; the tile rules are the same as other jungle cells (`objective/README.md`).
- **Why the camp value is larger than a laner's per-turn income (`SCORE_FRONTLINE_PER_TURN`)**: camps require walking and
  waiting for respawn, so with an equal per-camp value the jungler's per-turn income is structurally
  lower. It was measured (50 turns · no turrets destroyed · enemy jungle not captured, average of 4 runs) and the
  camp value raised until jungler income roughly matched a laner's. See the `BattleSim.SCORE_JUNGLE_CAMP` comment for the back-calculation.
- It was once raised further — when the two left/right neutral cells became objective-only spots and camp cells
  went 14 → 12, their share (× 14/12) was added on. When the two cells went back to being ordinary jungle
  cells that correction lost its basis and **was reverted**.
- **When the respawn was slowed, the camp value was raised together in the same proportion.**
  Jungler income is entirely camps and harvest frequency is inversely proportional to the respawn period, so
  stretching the period needs a proportionally larger value for the same income — **change `SCORE_JUNGLE_CAMP` and
  `JUNGLE_CAMP_RESPAWN_TURNS` together**. What was slowed is the **circuit rhythm**,
  not the jungler's share — waiting longer for a cell to come back, but eating more per harvest.
- **A later rebalance slowed the respawn again and cut the camp value at the same time — a deliberate
  jungle nerf.** This time the change does not preserve income; it lowers jungler income itself, the
  opposite direction of the proportional correction above.
- **The camp value now scales with game time** (`jungle_camp_score()`): it opens at
  `SCORE_JUNGLE_CAMP_START_MULT` of `SCORE_JUNGLE_CAMP` (the 100% value) and gains `SCORE_JUNGLE_CAMP_STEP`
  every `SCORE_JUNGLE_CAMP_STEP_TURNS` turns until `SCORE_JUNGLE_CAMP_CAP_TURN` — a weaker early jungle that
  catches up as laners' kill / turret income grows.
- The check is just one function, `camp_harvestable(cell, team)`, and **the renderer reads the same
  function** — the camps shown on screen and the camps actually harvestable can never diverge.
  `camp_charged(cell)`, which drops ownership and asks only "is it full now", sits inside it,
  and the renderer uses it when drawing **camps on enemy-owned cells** with a dark amber outline
  (`rendering/README.md`).
- Only cells **owned by your own team or still neutral** can be eaten. Capturing the enemy jungle
  adds camps to the circuit and can let the jungler overtake laners — that is where the value of jungle capture lies.
- **The payout function is just `harvest_camp_under(p)`.** The turn loop
  (`process_jungle_camps`) and **cards that move the jungler** (`_effect_move` — 정밀
  이동 (Precise Move) / 정글 파밍 (Jungle Farming)) pass through the same function. The card side eats on the spot for
  timing — waiting for the turn loop would leave a few seconds between playing the card and the harvest,
  making it look like "I played a card and nothing happened", and if the enemy jungler stepped on the same
  cell in between, it would be stolen outright.
- **Plunder (`steal_camp`) remotely intercepts that cell's camp via `steal_camp_point(cell, thief)`**
  — the value and respawn clock are the same as eating by stepping on it, and **ownership is not
  touched**. What is stolen is not the tile but that one income.
- **Accrual goes through `award_score`** — so a growth-point popup appears over the portrait.
  All jungler income comes from camps, and if the number just quietly rose in a corner of the strip,
  "ate a camp" would leave no trace on screen. The circuit rhythm is the jungler's play, and harvests happen
  once for one pilot rather than for ten every turn, so it does not become background noise
  (front-line presence is the opposite and so remains a quiet `add_score`). Plunder is the same.
- Runs **after** `process_neutral_zone_captures`: so the camp of a just-captured neutral cell
  can be eaten that same turn.
- The jungler's move goal follows this too — `_jungle_goal_for` looks at `_best_ready_camp` after
  not-yet-taken neutral cells, and once eaten that cell is empty for `JUNGLE_CAMP_RESPAWN_TURNS`,
  so the next camp naturally becomes the new goal. **That repetition is the circuit**, so the old
  sticky roaming remains only as the fallback for when no camp is full.
- **The cost for choosing a goal is not distance but `distance × JUNGLE_CAMP_STALE_PER_STEP −
  turns neglected`** (`JUNGLE_CAMP_STALE_PER_STEP`, const.csv). With distance alone the jungler **gets trapped in the 4 cells at its feet**: one jungle side is
  4 cells, so when the respawn period is close to that cell count one cell comes back every turn, nearest-distance greedy
  always found a distance-1 camp, and the opposite jungle stayed full of camps from opening to end
  (measured over 60 turns: the three cells of the right jungle never stepped on —
  on screen it looks like "circling empty cells while cells with food remain"). If a full but idle
  camp gets slightly cheaper every turn, the neglected side periodically becomes the cheapest goal,
  producing a left-right circuit (more cells stepped on, at the price of a small share of camp income
  lost to the circuit's travel time).
- **Moving one step toward the goal always lowers that goal's cost further** (distance −1 =
  −`JUNGLE_CAMP_STALE_PER_STEP`, neglect +1 = −1). Other camps only get −1 cheaper in the same turn, so the goal never
  flips midway into a back-and-forth — that back-and-forth was why the old sticky roaming was needed.
- **If the camp under the jungler's feet is full, that cell is unconditionally the goal.** Movement comes before
  `process_jungle_camps`, so just standing still eats it this turn —
  leaving because of the neglect discount would throw away that whole turn.

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
    the engage stage (교전 무대) remaps this into its own band
    [`PILOT_HIT_MIN`, `PILOT_HIT_MAX`] (const.csv; the old `ENGAGE_HIT_MIN` / `_MAX` were deleted,
    see `engage/README.md`), and the two are tuned independently. This is also the only place **laning stats** (`lane_stat_mod`)
    apply — `lane_adjusted()` multiplies the attacker's `hit` and the defender's `evasion`
    each by its own multiplier; the roll then uses `effective_hit` / `effective_evasion` = that ×
    `hit_mult_total` / `evasion_mult_total` (skill × card) — the same functions the pilot detail chips read.
    Damage per landed hit is `_pilot_hit_damage(attacker)` =
    `atk × BATTLE_PILOT_DMG_MULT` (game_config.csv), rounded, floored at 1.
    That multiplier covers **only damage pilots take from battlefield
    engagement** — the same helper is used by the turret-siege defender rolls.
    Pilot → turret and pilot → HQ damage do not read `atk` at all — they use the fixed
    `PILOT_STRUCTURE_DMG` (game_config.csv; siege speed is match length), and attack
    cards / the engage arena run their own numbers. It exists
    because a single unmitigated hit could exceed the whole recall window: a
    high-atk opponent against a low-max_hp sniper took a large share per hit, so the sniper
    fell from above the `RECALL_HP_THRESHOLD` line straight to 0 and **the low-HP recall had
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
      1. **Turret damage is unconditional** — same-lane attackers put the fixed
         `PILOT_STRUCTURE_DMG` (game_config.csv) into the turret **with no hit roll**
         (`BATTLE_PILOT_DMG_MULT` is pilot-damage only). A defender camping the tile does not shield it.
      2. **Then attackers and defenders trade hit rolls**, paired by ascending
         HP, both directions dealing `_pilot_hit_damage`. Attackers
         used to deal *nothing* to defenders — their whole attack went into the
         turret — so a defender sitting on its turret beat on the attacker for
         free. Now the attacker grinds the turret *and* still rolls on whoever
         is standing on it.

      T2 is invulnerable while own-lane T1 is alive (`_turret_attackable`), and
      the pilot-vs-pilot exchange runs regardless of that (the attackers are
      still in the cell with the defenders). Turret
      destruction frees the matching `Building` node via
      `building_registry.unregister(b); b.queue_free()` so the visual disappears.
    - **Knockback needs a defender's hit.** After the judgement an attacker goes
      into `retreat_set` **only if a same-lane defender's roll hit it** — a
      missed roll, an unpaired attacker or no defender at all means it stays on
      the turret and grinds it every turn.
    - **The defender follows the push.** If the defenders hit at least one
      attacker, **every** same-lane defender on the cell goes into `advance_set`
      (team-level, like a normal fight's sweep — per-hitter would leave a bonded
      duo stuck by `_enforce_lane_bonds` when only one of them hit). Advance =
      toward the enemy HQ = the cell the attacker retreats to, so the defender
      chases it off the turret. If an un-hit attacker is still standing on the
      turret, `_veto_advance_over_stuck_enemy` cancels the chase.
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

### Guardian Link ride-along queue (`_guardian_rides`)

Support Q (수호 연계, Guardian Link) is "when an ally wrapped in this mech's shield deals damage, this mech also hits that
enemy". Battlefield damage is **split into judgement (`_resolve_*` → `damage_map`) and application (cutting HP)**,
so the ride-along attack must not be rolled right at the judgement site — the ride-along goes through
`CardPhaseManager.deal_simple_attack` and **cuts HP on the spot**, so it would down the opponent before
this turn's not-yet-applied damage, and the rest of the judgement would keep rolling against a corpse.

So `_credit_pilot_damage` **only records** the (attacker, victim) pair in `_guardian_rides`,
and `_flush_guardian_rides()` rolls them all at once right after the pilot damage application loop ends. By then
anyone who fell this turn is already `alive == false`, so the gate of
`MechSkillSystem.on_shielded_ally_damage` filters those two out.
It is called from two places — the turn loop (`simulate_turn`) and the advance card path
(`_apply_card_damage`). Card attacks do not split judgement and application, so
`CardPhaseManager` calls it directly at its own damage point.

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
   whole cost of a return-to-base (본진 복귀), and clearing it here is what makes it exactly one.
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
  - Jungler → `_jungle_goal_for(p)` (best ready camp, else a **sticky** roam
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

### Lane bond (`lane_bond_partners` / `_apply_lane_bonds` / `_enforce_lane_bonds`)
**Lane pilots of the same team assigned to the same lane are bonded.** Today
only the bottom duo (SNIPER + SUPPORT on RIGHT) qualifies. The check reads
`lane`, not role, so a future lane reassignment carries the bond with it.
Junglers are never bonded.

- **Only while standing on the same cell.** Once separated (recall, death),
  each moves on its own; the bond resumes when they share a cell again. Because
  of that, a bond group is always a full clique inside one cell, so one pilot's
  partner list is the whole group minus itself.
- **Retreat wins.** `_apply_lane_bonds(advance_set, retreat_set)` runs right
  after cell resolution. It runs in both `simulate_turn` and `_advance_tick`.
  If one pilot got a retreat verdict, it moves the partner from advance to
  retreat. The typical case is the turret cell: the turret defender hits only
  the carry, and the support is dragged back with them. Before this change the
  support stayed on the turret cell and kept grinding.
- **Advance only together.** `_enforce_lane_bonds(wants)` runs inside each
  lockstep round, after both vetoes. If any member has no surviving ADVANCE
  want, every member's advance is cancelled. If any member has a surviving
  RETREAT want, a vetoed partner is re-enabled toward the same destination.
- **Not bonded:** free walking, card / skill movement, and low-HP or card
  recall (`RecallSystem`, `_effect_move`, …). Those move only their target; the
  bond code never runs on those paths.
- **Shared field stats.** In auto lane combat only (`field_roll_hit`, used by
  `_resolve_pilot_combat` / `_resolve_turret_combat`), a bonded pilot's base
  `hit` / `evasion` is the **average over its bond group**
  (`bond_shared_hit` / `bond_shared_evasion`); per-pilot lane-stat and skill
  multipliers still apply on top. The carry (high hit, low eva) and support
  (low hit, high eva) thus fight like one balanced solo laner; once separated,
  the survivor's skew shows. Attack cards keep using `roll_hit` with each
  pilot's own stats.
- **Income cut.** `award_frontline_income` pays a bonded pilot
  `SCORE_FRONTLINE_PER_TURN × (1 − BOND_INCOME_CUT)` (judged on the turn's
  final cell); a pilot left alone gets the full `SCORE_FRONTLINE_PER_TURN`.
- Bond events log under `BOND`. There is no on-screen indicator (decided
  2026-10-03).

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
| Neutral | (-3,-1), (1,-1) — uncaptured at start, up for grabs |

- `init_neutral_zones()` — paints the initial owner of each cell.
- `process_neutral_zone_captures()` — a jungler standing alone on a neutral
  cell (no enemy in same cell) flips it to their team.

#### Left/right neutral cells = objective stage, but **ordinary jungle cells**
`(-3,-1)` and `(1,-1)` are where Herald / Dragon stand, but **their tile rules do not differ by a single letter
from other jungle cells**: a camp stands there (`init_jungle_camps`), junglers capture it by stepping on it
(`process_neutral_zone_captures`), it becomes a circuit goal, and its owner changes through the
**flank-neutral seizure branch** (`_on_t1_destroyed`) of side T1 destruction.

They were once **permanently neutral** — objective-only spots with no camp and no capture. Back then
`is_objective_cell()` made that check, and `_nearest_uncaptured_neutral()` was deleted as a whole function since its
check would be true forever. When the two cells returned to the jungle, all three came back to life,
and `is_objective_cell` no longer exists. The objective side **only borrows those coordinates as a
stage**, so it neither reads nor writes tile state — the turns-left display also moved from the tile to
the top panel (`ui/ObjectiveTimer.gd`). Details in
`objective/README.md`.

#### Jungler roaming (`_jungle_goal_for`)
**First comes the start cell chosen before the opening** (`PilotData.jungle_start_cell`, written by the jungle start
overlay) — the path that screen drew must be the real walk, so it takes precedence over everything else until reached.
When reached or when that cell becomes the opponent's, it is cleared and the order below follows.
In a standalone run it is empty. Rolling this function forward as-is to predict the jungler's walk is `predict_jungle_path(p, turns)` (the path on the jungle start screen — it pushes state temporarily and restores it. It is a simple expected route that assumes our jungler walks alone, so collisions with the opponent jungler are not computed. `gambit/README.md`).

**A single step is decided by `jungle_step(p, goal)` — at equal distance it routes around opponent-owned jungle
cells.** Junglers have no forbidden cells, so it was always shortest distance, and when there were several shortest
paths, the neighbor scan order (top first) picked the route, so the team-0 jungler crossed the opponent jungle
when moving between the left/right neutrals (`(-3,-1)` → `(-2,-2)` → `(-1,-2)` → `(0,-2)` → `(1,-1)`, two of four were
opponent cells). Now it first asks with opponent-owned jungle cells (except the goal cell itself) blocked, and only when
there is no path asks without blocking. Measured: for all 8 droppable cells, 0 opponent cells on the predicted path, 0 turns
spent in the opponent jungle over 40 turns, and the same path changed to `(-2,-1)` → `(-1,-1)` → `(0,-1)` → `(1,-1)`.
The three spots in the turn loop (`_next_step_for` · push advance · retreat) and the prediction
(`predict_jungle_path`) all go through this function.

Next, a neutral cell nobody has captured yet is **priority 1** (`_nearest_uncaptured_neutral`;
the `jungle_start_pref` chosen in ban/pick sets the left/right order) — just stepping on it makes one cell
of the map ours, and that cell's camp comes with it. After that comes the best ready camp
(`_best_ready_camp`). With no camp charged the jungler
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
- `_on_t1_destroyed(td, log_lines)` — two priority branches keyed off
  per-lane "취약지점" (vulnerable cell) sets in `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}`.
  A vulnerable point is the jungle cell in a team's own territory closest to
  enemy territory along that lane: side lanes have 1 cell, mid has 2 flanking
  cells. When a team's same-lane T1 falls:
    1. **Restoration (all lanes)** — if any of the *capturer's* own same-lane
       vuln cells are currently owned by the loser, those cells flip back to
       the capturer and nothing on the loser's side is taken.
    2. **Default capture** — the loser's same-lane vuln cell(s) flip to the
       capturer. Side lanes flip 1 cell, mid flips both flanking cells.

  The old **side-neutral override** (side-lane T1 grabbing `(-3,-1)`/`(1,-1)`
  when the loser owned it) is deleted: those cells are permanently neutral now,
  so the condition could never be true.

### Spawning
- `spawn_pilots_with_lanes()` — builds 5 player + 5 enemy `PilotData` using
  `GambitPhaseManager.ROLE_TO_LANE`. Stats come from `_stats_for(...)`.
- `_stats_for(...)` — when match_ctx is active, pulls hp/atk/presence from
  the assigned mech and everything else from the **6 player stats (선수 스탯 6종)**:
  `field_hit`/`field_eva` → `hit`/`evasion`, `engage_hit`/`engage_eva` →
  the engage-arena pair, `atk_growth`/`hp_growth` → `atk_growth_mult` /
  `hp_growth_mult` (via `PlayerData.growth_mult`). Otherwise falls back to
  `ROLE_STATS` defaults with every stat at 50 / every multiplier at 1.0.
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
Public entry point used by the 전진 (Advance, advance:N) card. Runs `N` mini-ticks; one
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
3. **`_apply_card_damage`** — pilots (shield (보호막) first) then turrets, with T1
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

Skips `process_respawns` / `process_neutral_zone_captures` and does **not**
bump `turn_count`. Win condition
is rechecked at the end so a turret-destruction kill via 전진 resolves
immediately.

### Match stats (MVP metric) — damage / shield / heal hook points
Per-pilot match counters live on `PilotData` (`kills` · `deaths` · `assists` · `dmg_dealt` ·
`dmg_taken` · `care`) and are only ever moved by **a handful of `BattleSim` hooks**, so no damage
path can forget one:

| Counter | Hook | Paths that reach it |
|---|---|---|
| `kills` / `deaths` / `assists` | `BattleSim.mark_pilot_dead` via `kill_roster(victim, killer)` — the **same roster the kill feed shows** (last hit = `killer`, or the top damage contributor when unknown; assists = everyone else in `live_damage_credit`) | every death (battlefield, advance card, attack cards, [확신], execute, engage stage) |
| `dmg_dealt` | `BattleSim.record_pilot_damage` (the bounty ledger — same value, shield-absorbed share included) + the remaining HP of an instant kill in `mark_pilot_dead` (execute) | battlefield `_credit_pilot_damage`, attack cards, [확신], engage strikes |
| `dmg_taken` | `BattleSim.apply_pilot_damage(victim, amount)` — shield first, then HP (floored at 0); counts **HP actually lost** (no overkill) | `simulate_turn` step 4, `_apply_card_damage` (advance card), `CardPhaseManager._apply_attack_damage`, `_effect_attack_bounty`, `TurnEngageSim._apply_damage` (pilot strikes **and** turret shots; 불굴 (Last Stand) gives the 1 HP back to the counter too). Execute: remaining HP in `mark_pilot_dead` |
| `care` | shield absorption inside `apply_pilot_damage` (credited to the **grantor** of the absorbed shield) + `BattleSim.apply_heal(target, amount, healer)` (overheal dropped) | shields: `grant_shield` from `shield_pct` / `shield_atk` cards; heals: `heal_pct` |

- **Shield attribution**: `BattleSim.grant_shield(target, amount, source)` appends
  `{src, amt}` to `PilotData.shield_grants`; absorption drains it **FIFO** and credits each
  grant's source. Places that zero `shield` outside the ledger (return to base, card recall,
  death) need no hook — before draining, the ledger is trimmed (oldest first) to the current
  `shield`, so a stale grant is never credited.
- **Care counts other allies only** — a self-shield / self-heal, or a shield whose source is on
  the other team, credits nobody. Protecting yourself already shows as lower `dmg_taken`.
- `BattleSim.build_pilot_stats()` turns the ten pilots into `pending_match.pilot_stats` rows
  (shape in `features/battle_sim/README.md` "Match result payload").

### Misc helpers
- `t1_alive_in_lane`, `any_t2_destroyed`, `has_enemy_turret_at`
- `process_respawns`
- `check_win_condition`

### Animation hooks (UI-only side-effects)
SimulationCore and RecallSystem call back into `BattleSim` after mutating
logical state so the renderer can soften the transition:

- `resolve_movement` accumulates each mover's **path** (`m["path"]`, one cell
  appended per committed lockstep round) and calls
  `_bs.anim_pilot_move_path(p, path)` once at the end for every pilot that
  actually moved. The renderer slides the portrait along that polyline, so
  a `move_range` 2 move goes **around the corner** instead of skimming past the middle cell.
  `advance_pilot` calls `_step_pilot` → `_bs.anim_pilot_move(p, orig)` per mini-tick,
  and steps in the same frame are appended to the same path on that side.
- The damage_map application loop calls `_bs.anim_pilot_shake(p)` for surviving
  pilots that took damage > 0 — this is the **default strength with no arguments** (0.18s / 6px). Attack
  cards pass their own constants (`ANIM_SHAKE_CARD_*`, 0.26s / 20px) to the same function to shake
  much more violently.
- The `turret_dmg` application loop calls `_bs.anim_turret_hit(td)` for turrets
  that took damage > 0 **and survived** — both in `simulate_turn` step 5 and in
  `_apply_card_damage`. A killing blow is skipped: the `Building` node is freed
  on the same line, so there would be nothing left to shake.
- `process_respawns` calls `_bs.anim_pilot_respawn(p)` after returning a **dead**
  pilot to HQ; that call also clears any leftover death presentation (전사 연출).
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


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Jungle camp value | Camps stand on **14 cells** (12 jungle + 2 left/right neutral) and `BattleSim.SCORE_JUNGLE_CAMP` (const.csv) is the 100% per-camp value (paid × a turn-scaled multiplier, `jungle_camp_score()`) — most recently cut together with a slower `JUNGLE_CAMP_RESPAWN_TURNS` as a deliberate jungle nerf. It was once raised, adding the share (× 14/12) when the two neutral cells became objective-only spots and the count dropped to 12, but it was reverted when the two cells returned to the jungle — Herald / Dragon never pushed camps out, so there is no share to give back. |
| Front line (전선, 前線) — lane pilots' income source | In each lane, the stretch **between both teams' living frontmost turrets** (turret cells included) is the front line, and lane pilots earn `SCORE_FRONTLINE_PER_TURN` (const.csv) **every turn they stand inside it alive** (`SimulationCore.award_frontline_income`, turn loop step 8 — judged on **that turn's final position** after movement and capture are both done). When the outer turret (T1) falls, that team's boundary retreats to T2, and when T2 falls too, to the end of the corridor (HQ side), so **the front line widens** — pushing in creates more room to earn. The check is built fresh every turn by `front_line_cells(lane)` (not cached since it changes whenever a turret falls; three lanes × dozens of cells costs nothing). Front/back ordering is `lane_corridor_order(lane)` — a table numbered from the team-0 HQ side at the place where the corridor is built; numbers are written only on first visit so doubling-back segments do not flip front and back. **Nothing is earned while walking out of HQ, while walking back after a low-HP return, or while dead** — this is the real cost of death and return. **Junglers are excluded** (a jungler's front line is the jungle). On screen, front-line cell borders are drawn in thin gold (`BattleRenderer._draw_front_line_overlays`) — income comes from position, and if that position were invisible you could not tell why you are falling behind; it is shown only as a border so it does not compete with tile colour (jungle capture). |
| Jungle camps — the jungler's income source | **Every jungle/neutral cell has one camp** (`BattleSim.jungle_camps`, `cell → ready_turn`), all full at the opening (`SimulationCore.init_jungle_camps`, right after `init_neutral_zones`). When a jungler stands on a **full camp** it eats `jungle_camp_score()` and that cell refills only `JUNGLE_CAMP_RESPAWN_TURNS` later (both const.csv) — so the jungler cannot stay in one place and must **keep circling** to match a laner's per-turn income (the cost difference between holding ground and circling remains as is). **The camp value is back-calculated from measurement** — the baseline is "50 turns · no turrets destroyed · enemy jungle not captured" (average of 4 headless runs with turrets made immortal, removing both T1 destruction rewards and front-line widening); with an equal per-camp value the jungler earned clearly less than the laner average. Jungler income is entirely camps, so the camp value was scaled up by the measured income ratio until the two roughly matched (the back-calculation is in the `BattleSim.SCORE_JUNGLE_CAMP` comment). **When the respawn was slowed, the camp value was raised in the same proportion** — harvest frequency is inversely proportional to the period, so that keeps income the same; **change `SCORE_JUNGLE_CAMP` and `JUNGLE_CAMP_RESPAWN_TURNS` together**. What was slowed is the **circuit rhythm**, not the jungler's share (waiting longer for a cell but eating more at once). A later rebalance slowed the respawn once more **and cut** the camp value — a deliberate jungle nerf, not an income-preserving correction. Capturing the enemy jungle is acceleration on top of that; this constant only lines up the **no-capture floor** with laners. Only camps on cells **owned by your own team or still neutral** can be eaten, so capturing the enemy jungle (pre-empting neutral cells / T1 destruction reward) adds camps to the circuit and can let the jungler overtake laners — this is the value of jungle capture. The check is the single function `camp_harvestable(cell, team)` and **the renderer reads the same function** (ringing that cell's **tile border** with a yellow outline), so visible camps and harvestable camps can never diverge. **Camps on enemy-owned cells are on screen too** — the same outline in dark amber (`BattleRenderer.CAMP_LINE_ENEMY_COLOR`) separates "exists but not ours right now" with a single colour. That check is `SimulationCore.camp_charged(cell)`, which drops ownership and asks only "is it full now"; if you could not see whether there is something worth stealing right now, plunder could not be a decision. **Outlines join up between adjacent cells of the same kind** — see the "Camp outline" entry below. They used to be a small **diamond** in the middle of the cell (ours = filled / enemy's = hollow). **The payout function is just `harvest_camp_under(p)`**, shared by the turn loop (`process_jungle_camps`) and **cards that move the jungler** — landing on a camp via a card eats it **on the spot** without waiting for the turn loop (see the "Move cards" entry below). Payout runs **after** `process_neutral_zone_captures` — so a just-captured neutral cell's camp can be eaten that same turn. |
| Move cards = instant camp harvest | When a card that moves the jungler (**정밀 이동 (Precise Move) / 정글 파밍 (Jungle Farming)**, `_effect_move`) **lands on a full camp, it eats it on the spot** — without waiting for the turn loop's `process_jungle_camps`. The entry point is the single `SimulationCore.harvest_camp_under(p)`, so the value and respawn clock are the same as eating by stepping on it, and `· 캠프 +N` (camp +N) is appended to the log and the card result text. Leaving it to wait opened a few seconds between playing the card and the harvest, so it looked like "I played a card and nothing happened", and if the enemy jungler stepped on the same cell in between, it was stolen outright. |
| Plunder (약탈, `steal_camp`) | **Remotely intercepts one full camp on an enemy-owned jungle cell** — the caster (시전자) receives `jungle_camp_score()` and that cell enters its `JUNGLE_CAMP_RESPAWN_TURNS` respawn (`SimulationCore.steal_camp_point`). **The tile owner does not change**: what is stolen is not the land but that one income, so the enemy jungler walks over that cell empty-handed until the next respawn. Valid targets are **all enemy-owned jungle cells with a full camp**, with no range check (`compute_steal_camp_targets`; the card's cards.csv `cast_range` is a whole-field value) — empty cells cannot be chosen at all, so there are no whiffs, and which cells still hold value is already told by the camp outlines on screen. It used to be a **capture** card (`capture_jungle:N` — flipped enemy jungle cells adjacent to allied jungle to your colour for N turns, and `temp_zone_overrides` reverted them on expiry). That wiring and `SimulationCore.process_temp_zone_expiries` / `set_zone_cell` were **deleted** together. |
| Player stats (six) | **A player holds only six values, and all six are inputs to combat calculation.** `PlayerData` owns the tables (`STAT_KEYS` / `STAT_LABELS` / `STAT_NOTES` (no short forms: screens write the full name)) and every screen reads them — previously each screen held its own array. **Floor 1, no ceiling** — they keep growing past 100 through daily training (일상 훈련) (which is why hit is read as a ratio; see the next row). ① **Field hit `field_hit`** / ② **field evasion `field_eva`** → `PilotData.hit` / `evasion` → `SimulationCore.roll_hit` (battlefield auto-combat + attack cards). ③ **Engage hit `engage_hit`** / ④ **engage evasion `engage_eva`** → `PilotData.engage_hit` / `engage_eva` → `TurnEngageSim`. The point is that they **live separately** from the battlefield ones — a player being strong in laning and strong in teamfights are different things, and splitting them becomes the choice on the training board. ⑤ **Attack growth coefficient `atk_growth`** / ⑥ **HP growth coefficient `hp_growth`** → `PilotData.atk_growth_mult` / `hp_growth_mult` → `BattleSim.refresh_growth_stats` multiplies them into `GROWTH_ATK_PER_SCORE` / `GROWTH_HP_PER_SCORE`. The multiplier's reference point is `PlayerData.GROWTH_STAT_BASE` (const.csv `PLAYER_GROWTH_STAT_BASE`), where ×1.0 = the current balance unchanged — it is set near the measured average of `players.csv`, not at the mid-scale value 50; with 50, everyone would start well above ×1.0 and the untouched balance would shift. **Growth coefficients do not push stats directly** — pushing stats would be wiped by one growth recalculation, and what training changes is not the opening stats but the slope of how the match unfolds. **The old five (`laning` / `mechanics` / `gamesense` / `teamfight` / `mental`) were deleted** — only `mechanics` (→hit) and `gamesense` (→evasion) were actually read in-game; the other three were used only in strength totals. Strength totals were consolidated into the pair `PlayerData.stat_total()` / `stat_avg()` (previously hand-summed expressions over five fields were scattered across eight places). |
| Hit check (band remap) | **Battlefield and engage use the same formula** — `PilotData.hit_chance(hit, eva)` = `HIT_MIN + (HIT_MAX − HIT_MIN) × hit/(hit+eva)` (const.csv `PILOT_HIT_MIN` / `PILOT_HIT_MAX`). An even match lands at the band's midpoint; it only reaches either end when fully skewed one way. Only **the inputs** differ — battlefield uses `hit`/`evasion`, engage uses `engage_hit`/`engage_eva`. **Previously the battlefield used the ratio directly as the probability (even = 50%) and only the engage did this remap** (`TurnEngageSim.ENGAGE_HIT_MIN` / `_MAX`, **deleted**) — the same stat gap read at completely different sizes on the two stages, and now that stats have no ceiling, a widening gap would produce matches where one team hits practically nothing. **Knock-on: battlefield laning damage throughput rose sharply** (even opponents went from a 50% ratio to the band midpoint). `BATTLE_PILOT_DMG_MULT` (game_config.csv) was left untouched, so a single hit is unchanged, but the old property "laning alone does not kill anyone" weakens — that constant is the first knob if the growth-point curve needs re-measuring. **A slot for a distance coefficient is left empty** — the third argument of `hit_chance`, `range_mult`, is always 1.0. The battlefield currently has only same-cell combat, so there is no notion of distance; if a range rule appears, callers just pass a coefficient in that argument (the formula itself is not touched). **Laning stats and skill multipliers are multiplied into the stats first, before they enter this formula** — pushing the probability directly would go out of band or hit the cap, and the multiplier would silently vanish. |
| Laning stats | A multiplier (the card's `lane_stat:N` clause, cards.csv) **for `hit` / `evasion` only**, multiplied in **only one place**, `SimulationCore.roll_hit` — the attacker's `hit` and the defender's `evasion` each get their own multiplier. `atk` / `max_hp` are handled by growth, so they are not touched here. `roll_hit` is shared by battlefield auto-combat and attack cards so both reflect it, and **the engage stage does not** (the formula is the same but its inputs are `engage_hit`/`engage_eva`, and this multiplier is only applied inside `roll_hit`). Applying it twice to the same pilot **overwrites** (not additive) — with a structure drawing 2 cards from a pool of 3, allowing stacking would let a large multiplier roll out by pure luck. **공격적인 라인전 (Aggressive Laning)** (its `lane_stat:N` clause). The old 안전한 파밍 (Safe Farming) (a laning penalty + an accrual bonus) became **소극적인 태세 (Passive Stance)** — it does not touch laning stats and puts its evasion bonus (cards.csv clause) **only on field evasion** (`PilotData.eva_card_mod`). `roll_hit` multiplies two more card-side multipliers on top: attacker hit × (1 + `CardPhaseManager.hand_hit_add` — `CARD_CONFIDENCE_HIT_BONUS` (const.csv) per [자신감] (Confidence) held in hand), defender evasion × (1 + `eva_card_mod`). |
| Ambush hold (`ambush_hold`) | Flag set by the [매복] (Ambush) card. `resolve_movement` **removes that pilot from movement candidates entirely** (no free movement and no push result — the check right after `recall_hold`). `RecallSystem.process_phase_end_recalls` also skips the out-of-position check (a lane pilot being on a jungle cell is the point of an ambush). It is cleared by that team's next operation phase entry settlement, death (`mark_pilot_dead`), return-to-base (`return_to_hq`), the Return card, and the retreat card. A lane pilot still in the jungle after it clears is recalled as out-of-position as usual at the end of that operation phase. |
| Movement resolution (single pass) | Free movement and engage pushes are resolved in **lockstep** in **one pass** (`SimulationCore.resolve_movement`) — every pilot in a round picks its destination from the same snapshot and they commit simultaneously, so same-scope enemies swapping places or passing through each other is structurally impossible. Two conflicts are arbitrated per round. (1) **Passing a holding enemy** — advance is toward the enemy HQ and retreat is toward one's own HQ, the same direction, so **the winner follows the pushed-out loser in** (= the lane moves one cell per turn). Previously, when the two destinations overlapped, the advance was cancelled, giving "only the loser is driven out and the winner holds that cell", but on a straight lane the destinations **always** overlap, so even after winning the engage the winner could never move a single cell forward. Now the advance is cancelled **only when the enemy has nowhere to be pushed and stays** in that cell (`_veto_advance_over_stuck_enemy`) — so nobody brushes past a standing enemy. Enemy turret cells do not block — if the loser is pushed onto its own turret cell, the winner follows it in too, and the siege begins from that cell. (2) **Head-on collisions** (each aiming at the other's cell) are resolved by priority **push > free movement, team 0 on ties**: one side takes the cell, the other stops, and they **meet in the same cell** and engage next turn. Damage application comes **before** movement (a pilot killed this turn does not move). |
| Combat | **Same-cell only** — no adjacent-cell engagement, no attack range. Lane pilots paired 1:1 by HP against enemy lane pilots; each rolls `PilotData.hit_chance(hit, evasion)` (= ratio remapped onto [`PILOT_HIT_MIN`, `PILOT_HIT_MAX`]) for damage — **laning stats** are multiplied into this check (row above). **Damage per hit = `atk × BATTLE_PILOT_DMG_MULT`** (game_config.csv — rounded, minimum 1). This multiplier is **only for battlefield damage pilots take**: pilot→turret / pilot→HQ does not read `atk` at all and uses the fixed `PILOT_STRUCTURE_DMG` (the "Turret Combat" row below), and attack cards and the engage stage each use their own calculation. With raw `atk`, one hit was larger than the return window — a high-atk opponent vs a low-max_hp sniper took a large share of max HP per hit, dropping straight to 0 from above the `RECALL_HP_THRESHOLD` line, so there was no interval at all for the low-HP return to fire. **Push is team-level**: tally unilateral wins per team across all pairs in the cell; the side with strictly more unilateral wins sweeps — every pilot of that side in the cell (including unpaired pilots in e.g. 2v1) advances, every opposing pilot retreats. Tie/0-0 → no push. Advance and retreat point the **same way** (enemy HQ vs own HQ), so the winners **follow the losers into the next cell** — the whole engage cell slides one cell toward the loser's HQ and they clash again there next turn. This is the lane push. The only case where the advance is cancelled is **when the loser has nowhere to be pushed and stays in that cell** — even if the cell ahead is an enemy turret, the winner follows into that cell (turret siege comes the turn after). `_move_pilot` aborts further multi-step movement only when a *same-scope* enemy enters the cell (jungler-vs-jungler or lane-vs-lane); cross-scope contacts never freeze movement. |
| Lane bond (bottom duo) | **Laners of the same team assigned to the same lane are bonded** (currently only the right-lane sniper + support. The check uses `lane`, not role, so it follows if lane assignment changes. Junglers are excluded). It works **only while standing together in the same cell**, and its one job is to align engage-result movement (push · turret-defender-hit knockback) as a group — **retreat wins**: if even one gets a retreat verdict the partner retreats too (on a turret cell, if only the ADC is hit, the support falls back too), and advance happens only when every member of the group can go. **Card · skill · low-HP return movement moves only the target** (bond code does not run on those paths). Free movement is not bonded either. No on-screen indicator (log `BOND` only). **While bonded, stats are shared and income is cut** — the battlefield auto-combat hit check (`field_roll_hit`) uses the group's **average** field hit / evasion (attack cards use each pilot's own stats), and that turn's front-line income is reduced by `SimulationCore.BOND_INCOME_CUT`. A pilot left alone uses its own stats and earns the full `SCORE_FRONTLINE_PER_TURN`. `SimulationCore.lane_bond_partners` / `_apply_lane_bonds` (right after judgement, turn combat + advance card) / `_enforce_lane_bonds` (inside movement rounds). Details in "Lane bond" in `combat/README.md`. |
| Engagement scopes | Junglers and lane pilots run on **separate engagement brackets**. A jungler never engages an enemy lane pilot, never deals turret damage, and is never paired against attackers as a turret defender. Lane pilots ignore enemy junglers in the same cell. |
| Turret Combat (turret cell occupation) | **Only same-lane lane pilots interact with a turret** (e.g. a RIGHT-lane pilot cannot damage a CENTER turret). An advancing lane pilot **actually steps onto** the same-lane enemy turret cell — the same whether it simply walks up, follows a pushed-out enemy in after winning an engage, or goes in via an advance card (the old "dip a foot in and pull out" adjacent siege `resolve_turret_sieges` / `_bounce_off_enemy_turret` was deleted). **No damage on the entry turn.** On the **next turn** standing on that cell, `_resolve_turret_combat` runs and puts `PILOT_STRUCTURE_DMG` (game_config.csv) into the turret **with no hit roll**. **It is a fixed value, not proportional to `atk`** — now that growth multiplies attack several times over, putting full `atk` in would melt late-game turrets in one turn, and match length would collapse inversely with growth. Structures should fall fast not because attack got bigger but **because defenders emptied the battlefield through low-HP returns · deaths**. Turret HP `TURRET_HP` (game_config.csv) is tuned against `PILOT_STRUCTURE_DMG` — together they set how many turns an undefended / defended siege takes, so change them together. It was raised from its old value, which also shrank [전령 제압] (Herald Subdued)'s `turret_damage` clause (cards.csv) relative to a turret and made sieges take one more beat. **Turret damage always lands even if an enemy is holding out on that cell** — defenders cannot shield the turret. **After** turret damage, same-lane attackers and defenders **roll hit checks against each other** (1:1 pairing by ascending HP, both sides `_pilot_hit_damage`) and trade damage. Previously, "all attack goes into the turret" meant **attackers dealt 0 damage to defenders**, so a defender squatting on its turret could beat on the attacker one-sidedly. **Hitting the turret does not make you retreat** — knockback pushes back to the previous cell **only attackers hit by the turret-cell defender's attack** (`_apply_turret_siege` returns the set of attackers hit). If the defender missed, if nobody targeted the attacker because it had no pair (the spare in a 2v1), or if there is no defender at all, the attacker stays put and grinds the turret **every turn**. Previously, as long as a defender existed, all attackers retreated regardless of hits (`_same_lane_defenders_at` deleted). The only exception is an **unattackable turret** (a T2 whose same-lane T1 is alive) — there is nothing to grind, so the attacker always retreats (pilot-vs-pilot checks still roll). As a result, turret damage is every turn when undefended, and when defended close to once per 2 turns (enter → hit then pushed out → re-enter) at the defender's hit rate, grinding once more on each turn the defender misses. **The HQ also takes the same fixed damage** (`HQ_MAX_HP`, game_config.csv — the HQ was not part of the turret HP raise). Off-lane pilots ignore the turret, and off-lane pilots of both teams still fight each other as pilots. **Turrets do NOT attack pilots. Junglers do NOT attack/defend turrets.** T2 is invulnerable while the same-lane T1 is alive. When a turret is destroyed the `Building` node is freed too so the sprite disappears. |
| Advance card (전진, `advance:N`) | One card **pushes the lane up by N cells**. One mini-tick is `SimulationCore._advance_tick`; it uses the battlefield rules as-is but forces one verdict — **the side that played the advance is treated as having won that cell's engage unconditionally** (damage rolls run as usual, so what gets hit gets hit; only who is pushed is fixed). So **the caster and same-cell · same-scope allies advance one cell together, and enemies in that cell are pushed back one cell together**. Previously (1) it read the unilateral-hit advantage as-is, so with bad dice the caster retreated toward its own HQ (= the advance card was a retreat card), and (2) "a card moves only one person" left the beaten enemy in place while only the caster brushed past. If the next cell is a **same-lane enemy turret**, the group **steps onto that cell** per the battlefield rules (no turret damage that tick). If the enemy has nowhere to be pushed and stays in the cell, the group does not advance either. If at cast time the caster is **already on a same-lane enemy turret cell**, the turret rule wins — it puts roll-free damage into the turret, and **only those hit by that cell's defender's attack** retreat one cell (**the only case where advance goes backwards**); the rest do not retreat and keep grinding in place. |
| Recall / Respawn | **복귀 (return-to-base) = going back to base (본진 귀환).** Two reasons come in through the single path `RecallSystem.return_to_hq` — (1) HP ≤ `RECALL_HP_THRESHOLD` (game_config.csv), (2) out-of-position when a move card dropped the pilot **in the jungle or another lane's corridor**. **Returning does not empty the battlefield** — that same turn the pilot stands at its own HQ **at full HP** and `alive` stays true. The only reason a pilot vanishes from the battlefield is **death**. Instead, it does not move on the turn it returns (`PilotData.recall_hold` → `resolve_movement` filters out one movement pass and consumes the flag), and **from the next turn** walks its lane again from waypoint 0. So the cost of returning is not a recovery wait but **the time to walk from HQ back to the front line**, and that time is **the time growth-point income is cut off** (the "Front line" row above) — death is the same, so the respawn turn count (longer later in the match) converts directly into growth loss. That is why death carries no separate score penalty. **However deep, being on your own lane is not out-of-position** — split push is a design kept alive. The Return card (`recall_ally`) is this with no wait: instant HQ + full HP. Only death empties the battlefield, so `respawn_timer` and **`BattleSim.turns_until_return(p)`** are **death-only clocks** — places that need "turns left" (card lock display, log `dead:N`) still go through the helper. **Respawn turns grow with match time** — `BattleSim.respawn_turns_now()` = `RESPAWN_TURNS` (game_config.csv) + `turn_count / BATTLE_RESPAWN_TURN_SCALE_DIV` (const.csv). Death passes through **only** one place, `BattleSim.mark_pilot_dead(p)` (shared by battlefield combat / advance / attack cards / engage stage). |
| Jungle (initial) | Both jungles start fully captured, **with only the two cells `(-3,-1)` and `(1,-1)` left neutral**. Those two are also where Herald / Dragon stand, but **their tile rules do not differ by a single letter from other jungle cells** — a camp stands there, junglers capture it by stepping on it, it becomes a circuit goal, and its owner changes through the flank-neutral seizure branch of side T1 destruction. They were once **permanently neutral** (objective-only) so all three were blocked, with `is_objective_cell` / `_nearest_uncaptured_neutral` doing that check; when the two cells returned to the jungle the former was deleted and the latter revived. **Priority 1 in goal selection is a neutral cell nobody has taken yet** (`_nearest_uncaptured_neutral`; `jungle_start_pref` sets the left/right order), followed by full camps. **Lane pilots are forbidden from entering any jungle/neutral cell** — Pathfinding receives `_bs.neutral_zone_cells` as the forbidden set for non-junglers. **Once the neutrals are all taken, the goal is a camp that can be eaten now** (`_best_ready_camp`) — the jungler's income comes entirely from camps, so the camp is the goal, and once eaten that cell is empty for `JUNGLE_CAMP_RESPAWN_TURNS` so the next camp naturally becomes the new goal. That repetition is the circuit (the "Jungle camps" row above). **The cost for choosing that camp is not distance but `distance × JUNGLE_CAMP_STALE_PER_STEP − turns neglected`** (const.csv). With distance alone the jungler **gets trapped in the 4 cells at its feet** — one jungle side is 4 cells, so when the respawn period was close to that count one cell came back every turn, nearest-distance greedy always found a distance-1 camp, and the opposite jungle stayed full of camps from opening to end (measured over 60 turns: the three right-jungle cells never stepped on). On screen it looks like "circling empty cells while cells with food remain". If a full but idle camp gets slightly cheaper every turn, the neglected side periodically becomes the cheapest goal, producing a left-right circuit (more cells stepped on; a small share of camp income is lost to the circuit's travel time, and in exchange the whole jungle gets used). Moving one step toward the goal always lowers its cost further (by `JUNGLE_CAMP_STALE_PER_STEP` + 1, other camps only −1), so the goal never flips midway into a back-and-forth. **If the camp under the jungler's feet is full, that cell is unconditionally the goal** — movement comes before payout, so just standing still eats it this turn. Only when no camp is full does it fall back to the old **sticky** roaming (`PilotData.jungle_roam_target`, kept until reached) — re-picking "the farthest allied cell" every turn made the side just left the farthest after one step, so it shuttled between two cells of the *mid-lane* corridor. |
| T1 → Jungle | T1 destroyed in lane L → priority branches off per-lane 취약지점 (vulnerable cell) sets `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}` (side lanes 1 cell, mid 2 flanking cells). (1) **Restoration**: if any of capturer's own same-lane vuln cells are loser-owned, restore them, nothing else flips. (2) **Side-neutral override (L/R only)**: if `(-3,-1)`/`(1,-1)` is loser-owned, capturer takes that neutral instead of loser's vuln. (3) **Default**: loser's same-lane vuln cell(s) flip to capturer. Mid has no neutral override. |
| 3-Lane System | Waypoint paths from HQ → side waypoints → enemy HQ. The old minion / lane-strength concept is **removed**. |
| No defense concept | A lane pilot's goal is **always** just `current_waypoint(p)`. There is no behaviour of coming back because an allied turret is being hit — pilots set off from their own HQ, follow the lane road, and running into the opposing laner along the way is the design. (`_supporter_should_fall_back` / `_own_forward_turret_cell`, where the support hugged the frontmost allied turret when the same-lane sniper died, were deleted.) |
| Lane corridor (`lane_corridor`) | The set of cells each lane actually passes through. Built **only once** by BFS-linking that lane's waypoints with jungle forbidden, then cached (team 1's path is team 0's reversed, so the cell set is shared). Its only consumer is `RecallSystem._is_out_of_position` — "did a move card drop this lane pilot **on someone else's lane**". The check must confirm **membership in another lane**, never judge from absence from its own lane alone: even if the BFS tie-break is one cell off from the actually walked route, a correctly placed pilot must not be exiled. `LANE_NAMES` also has a GUERRILLA slot, so iterate with `lane_corridor_count()`. |
