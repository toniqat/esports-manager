# Feature: Battle Sim

## Purpose
Tactical battle simulator on a hex grid. Five pilot roles per team
(Tank, Fighter, Assassin, Support, Sniper) push down a 3-lane map flanked by
jungle. **BATTLE auto-progresses** in 1-minute (`AUTO_PLAY_INTERVAL`) ticks;
players intervene during the threshold-gated **operation phase (작전 단계)** (CARD_PHASE) to spend
operation points (작전 점수) on cards.

## Entry point
Normally entered from `scenes/MatchFlow.tscn` via `change_scene_to_file`.
Standalone launch of `BattleSim.tscn` also works — falls back to `ROLE_STATS`
defaults and a default jungle direction (LEFT).

## Match Context handoff
On `_ready()`, BattleSim reads `GameManager.match_ctx`:

| match_ctx field | Used by |
|---|---|
| `player_roster[i].assigned_mech` | `SimulationCore._stats_for()` → PilotData hp/atk |
| `player_roster[i].field_hit` / `.field_eva` | PilotData.hit / .evasion (battlefield (전장) hit (명중) rolls) |
| `player_roster[i].engage_hit` / `.engage_eva` | PilotData.engage_hit / .engage_eva (engage (교전) stage (무대) hit rolls) |
| `player_roster[i].atk_growth` / `.hp_growth` | PilotData.atk_growth_mult / .hp_growth_mult (growth (성장) coefficient multipliers) |
| `enemy_roster[i].assigned_mech` / stats | same, for team 1 |
| `jungle_start_dir` | PilotData.jungle_start_pref on the player-team assassin |
| `player_side` | `BattleSim.blue_team` via `seed_side_costs()` — the blue side gets the strategy-point head start + first turn |
| `traits` | `[{id, key, p1, p2}]` — manager in-game traits, **my team only** → `TraitHooks` (`trait/README.md`). Empty / ignored when `active = false` → no change |
| `active = false` | Triggers fallback to ROLE_STATS (no MatchFlow ran); the side also falls back to player = blue |

### Match result payload (`season_state.pending_match`)
At match end `BattleSim.end_match(winner_side)` (called once by
`SimulationCore.check_win_condition`) writes, **only when `pending_match` exists** (standalone
runs write nothing):

| Key | Value |
|---|---|
| `winner_side` | 0 = my team (team 0), 1 = opponent |
| `pilot_stats` | 10 rows in `pilots` order (0..4 = my team): `{"pilot_id", "side", "role", "k", "d", "a", "dmg", "taken", "care"}` — `pilot_id` = `PlayerData.id` (falls back to `PilotData.pilot_id`), `role` = `GameEnums.Role`. Contract: `docs/outgame_dev_plan.md` §10.4; how each number is counted: `combat/README.md` "Match stats" |
| `mvp_pilot_id` | winning team's best `RunStats.mvp_score(row)` (`features/season/run_stats/README.md`), -1 if none |

Then the **MVP view** opens, and its "계속" opens the existing result panel (now with an MVP
line) — `ui/README.md` "Match end — MVP view → result panel". SeasonHub consumes the payload
(`RunStats.record_match`).

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
| TraitHooks | Node | `trait/TraitHooks.gd` | **Manager in-game traits (M8)** — parses `match_ctx.traits` into `KEY_*` sums and exports query functions only (opening points · first draw · hand cap · first card cost · cost tick); player team only. Added in `_ready()` **before** `_populate_from_data_loader()` (the opening points are seeded there). Spawns `trait/TraitBanner.gd` once at the opening. See `trait/README.md` |
| CardPhaseManager | Node | `card_phase/CardPhaseManager.gd` | Operation-phase turn flow, deck, fanned hand layout, phase-end gating |
| GambitPhaseManager | Node | `gambit/GambitPhaseManager.gd` | Pre-opening (개시 전) phase — role-fixed lane assignment + battlefield setup (`prepare_field`) + **jungle start (정글 시작) overlay** + opening (`begin_battle`). See `gambit/README.md` |
| JungleStartOverlay | Node | `gambit/JungleStartOverlay.gd` | **Jungle start cell** — the player drags the ally jungler marker standing on the battlefield (no tail) directly onto one of our jungle / neutral cells (the enemy jungle is disabled; shows HQ→that cell + the 6-turn path after arrival with turn numbers — `SimulationCore.predict_jungle_path`) and confirms with "전투 시작" (Start battle). That cell becomes the jungler's first target (`PilotData.jungle_start_cell`). Opens only when `match_ctx.active`. Lazily added by `GambitPhaseManager`. |
| EngagePhaseManager | Node | `engage/EngagePhaseManager.gd` | Battle-start (engage) modal — **round-based turn side-view belt engage** (`engage/TurnEngageSim.gd` headless sim + `engage/EngageArena.gd` renderer) triggered by `engage:N` / `duel` cards. Lazily added in `_ready()`. |
| HudBuilder     | Node | `ui/HudBuilder.gd`         | HUD (scene `ui/UI_View_BattleHud.tscn`, bound by `build_ui`); strategy-point donut (`ui/CostDonut.gd`), **both teams' pilot strips** (`ui/PilotStrip.gd`, enemy on top / ally at bottom), top-right **kill feed** (`ui/KillFeed.gd`), **objective timers** on both sides of the enemy strip (`ui/ObjectiveTimer.gd`) |
| ObjectiveSystem | Node | `objective/ObjectiveSystem.gd` | **Objectives (Herald (전령) / Dragon (용))** — engage events that open on the left/right neutral cells at set turns. Timer · participation decision · settlement. The decision window and stage borrow the engage module's VS screen and arena. Lazily added in `_ready()` **after** config load. |
| ObjectiveRewardFx | Node | `objective/ObjectiveRewardFx.gd` | **Objective reward pickup effect** — spreads the reward card in the centre of the screen, then flies it to where it goes (deck pile / left end of the hand / opponent's hand). `ObjectiveSystem._grant_reward` awaits it **right before granting**. |
| MarkerTouch | Node | `ui/MarkerTouch.gd` | Battlefield portrait press — press to enlarge and bring to front, long-press for the detail panel. Added in `_ready()`. |
| PilotDetailPanel | Node | `ui/PilotDetailPanel.gd` | Pilot detail modal — opens by tapping a face in the strip or long-pressing a battlefield portrait (operation phase + auto-progress; during auto-progress the turn pauses). The header (name · mech name · growth points) is separate from the tabs and always visible; tabs change only the detail panel below. Lazily added in `_ready()`. |
| ObjectiveRewardPopup | Node | `ui/ObjectiveRewardPopup.gd` | Objective reward preview — tapping a timer in the top panel shows the real card that objective grants. **Does not hold the battlefield.** Lazily added in `_ready()`. |
| PilotSkillSystem | Node | `skill/PilotSkillSystem.gd` | **Pilot skills** — a unique ability attached to each player (cooldown / charge-based / passive). State · activation · event hooks · passive queries. Lazily added in `_ready()` **after** `build_starter_decks()` (it finds partners in the roster, and backbone passives touch the deck). See `skill/README.md` |
| MechSkillSystem | Node | `mech/MechSkillSystem.gd` | **Mech skills** — 15 passives attached to the assigned **mech** and the persistent states its mech cards leave (vulnerable · reactive armour · target · tracking · bounty · bond · exhaustion …). Built at the end of `_ready()` right next to pilot skills (same precondition — roster + deck must already exist). Passive modifiers go out **only through query functions**; the computation happens where it always did. See `mech/README.md` (includes the 21-mech list · clause grammar) |
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
- Declares all DB-driven config vars and **state vars** (pilots, turrets, neutral_zone_cells, game_phase, HUD refs, card state, `gambit_lanes`)
- Holds `@onready` refs to all child modules
- Public **coordinate helpers**: `cell_center(pos)`, `pilot_label(p)`, `role_stats_str(role)`
- **Lifecycle**: `_ready()`, `_process(delta)`
  - `_ready` calls `_gambit.auto_assign_lanes()` then `_gambit.launch_battle()`.
    Inside it the battlefield is fully set up (`field_ready = true`), and **when entered from a match
    (`match_ctx.active`) it stays in GAMBIT and opens the jungle start overlay** —
    BATTLE is invoked by that screen's "전투 시작". Standalone runs (launching BattleSim.tscn directly
    / headless verification) have nobody to ask, so they go straight to BATTLE. Either way
    `_ready` continues to wire deck distribution · pilot/mech skills · logger
    (the battlefield is already fully set up; only the BATTLE ticks are deferred).
  - **`field_ready`** is the only gate on `BattleRenderer._draw`. Previously it drew nothing at all
    while `game_phase == GAMBIT`, but once jungle start selection moved inside that GAMBIT,
    the battlefield had to be visible before the opening too.
  - `_process` auto-ticks `card_phase.do_battle_turn()` every `AUTO_PLAY_INTERVAL`
    seconds while `game_phase == BATTLE`. CARD_PHASE pauses the tick, and so does
    the opponent's turn (상대 차례) — that one runs *inside* BATTLE, so the guard also reads
    `_ai_turn_active()` (`card_phase.is_ai_turn_active()`). The same flag freezes
    `get_elapsed_ingame_seconds()`.
- **Button callbacks**: `_on_restart_pressed()` (the only manual entry point left).

---

## Data Classes (resources/)

| File | class_name | Description |
|---|---|---|
| `resources/PilotData.gd` | PilotData | role, hp/max_hp, atk, team, grid_pos, lane, waypoint_idx, **move_range**, **hit**, **evasion**, **jungle_start_pref**, **respawn_timer** (death-only off-field clock — see `BattleSim.turns_until_return`), **recall_hold** (skip one move on the turn of a return-to-base (본진 복귀)), **anim_move_path** (path of cells stepped this time — the renderer reads and clears it), **kills / deaths** (cumulative this match — incremented only in `mark_pilot_dead`, kills credited to the kill feed's last hit; the competitive-spirit skill uses them to compare against the opposing laner), **match stats** `assists` / `dmg_dealt` / `dmg_taken` / `care` + the shield-source ledger `shield_grants` (see `combat/README.md` "Match stats") |
| `resources/TurretData.gd` | TurretData | team, grid_pos, hp, tier, lane, alive |
| `resources/PlayerData.gd` | PlayerData | id, name, role, team_id, **6 player (선수) stats** (field_hit / field_eva / engage_hit / engage_eva / atk_growth / hp_growth — tables are `STAT_KEYS` / `STAT_LABELS` / `STAT_SHORT` / `STAT_NOTES`, floor 1 · no cap), `assigned_mech`, **`skill_id`** (pilot_skills.id, -1 = none), **`is_mob`** (silhouette portrait · no skill · excluded from draft) |
| `resources/MechData.gd` | MechData | id, name, hp, atk, **presence** (mechs.csv `presence` — higher for melee, lower for ranged; used only as the target aggro weight on the engage stage). **`speed` has been deleted** — once engage became round-based turns, the concept of action frequency disappeared |

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
- **Advancing = lane push, and the pilot actually steps onto the turret (포탑) cell.** A lane pilot whose next
  lane step is a same-lane enemy turret **occupies that cell** — free walk-ups,
  engagement winners following the losers in, and the 전진 (Advance) card alike. There is
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
- **A defender camping the turret gets hit too** — the turret takes its damage first and
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
- **Return-to-base (복귀) = recall (귀환) to base.** Two triggers, one path (`RecallSystem.return_to_hq`):
  HP ≤ `RECALL_HP_THRESHOLD`, **or** a card effect that dropped the pilot on a
  jungle cell / on **another lane's corridor**.
- **Return-to-base does not empty the field.** The pilot lands in its own HQ **at full HP**
  on the spot, `alive` untouched — a pilot only ever leaves the field by dying.
  The cost is the walk back: `return_to_hq` sets `PilotData.recall_hold`, and
  the next `resolve_movement` spends it to hold the pilot still for exactly one
  pass, so it starts down its lane from waypoint 0 **the following turn**.
- The old model — leave the field, heal `RECALL_HEAL_RATIO` of `max_hp` per
  turn, come back the turn after hitting full — is gone, and so is that
  game_config key.
- A deep jump along the pilot's **own** lane is legal, however far into enemy
  territory it lands. That is a split push, not a displacement.
- The 복귀 (Return; `recall_ally`) card is the same teleport minus the hold: instant
  full-HP HQ landing, free to walk out the same turn.
- **Only the dead are off the field** (`alive = false`), so `respawn_timer` and
  **`BattleSim.turns_until_return(p)`** are death-only clocks. Anything needing
  "turns left" still calls the helper rather than reading the timer.
- **Respawn length scales with match time**: `BattleSim.respawn_turns_now()` =
  `RESPAWN_TURNS` (game_config.csv) + `turn_count / BATTLE_RESPAWN_TURN_SCALE_DIV`
  (const.csv). An early death costs about `RESPAWN_TURNS`, a late one grows with
  the clock. The DB value used to be a much larger flat value, which meant one
  death in the opening minutes erased the whole laning phase. **`BattleSim.mark_pilot_dead(p)` is the only place a pilot
  dies** — battlefield combat, 전진 (Advance), attack cards and the engage arena all funnel
  through it, so the scaling and the death (전사) effect can never be wired into one path
  and forgotten in another. It is also where **계획 살인** (Planned Murder) pays out: the
  reserved `kill_bounty_p/ai` goes to the *opposite* team of the pilot who
  fell (`_award_kill_bounty`). No killer argument was added — the battlefield
  has no third faction, so "the other team did it" is exact.
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
- Map starts with both jungles fully captured. `(-3,-1)` and `(1,-1)` are
  **permanently neutral** — they are the objective (오브젝트) spots (Herald / Dragon), not camps.
  See Objectives below.
- Junglers do not push lanes. They roam own-captured cells harvesting camps.
- Jungler-vs-jungler combat in a contested cell uses the same hit/evasion roll.
  A loser is pushed to the nearest own-captured jungle cell.
- T1 destruction triggers per-lane "취약지점" (vuln cell) flips. The vuln
  cells per team/lane live in `VULN_TEAM{0,1}_{LEFT,CENTER,RIGHT}` in
  `combat/SimulationCore.gd`: side lanes have 1 vuln cell, mid has 2 (the
  flanking cells). When a team's same-lane T1 falls, two branches in priority:
  (1) **Restoration** — if any of the capturer's own same-lane vuln cells are
  owned by the loser, those flip back to the capturer and nothing else moves.
  (2) **Default** — the loser's same-lane vuln cell(s) flip to the capturer.
  **The old side-neutral override is gone**: `(-3,-1)`/`(1,-1)` can never be
  owned by anyone now, so that branch could never fire.

### Objectives (Herald / Dragon)
**Engage events that open on the left/right neutral cells at set turns**. Full rules · knobs · reward
cards are in `objective/README.md`. Summary:

- **Left = Herald (first spawn `OBJ_HERALD_FIRST_TURN`, 3 participants: LEFT/CENTER/JUNGLE)**,
  **right = Dragon (first spawn `OBJ_DRAGON_FIRST_TURN`, 4 participants: RIGHT×2/CENTER/JUNGLE)**. Respawns
  `OBJ_RESPAWN_TURNS` after it is decided; if it falls through because neither team joins, retry after
  `OBJ_RETRY_TURNS` (all game_config.csv). Turns remaining are always shown on the timer.
- **It happens regardless of whose turn it is** — `CardPhaseManager.do_battle_turn()`
  `await`s it right after `simulate_turn()`, **before** the card economy.
- **It can be avoided.** The player gets two buttons, join / skip (VS screen reused); the AI
  computes a win rate from the sum of `(hp+shield)×atk` of both teams' participants and backs off below 0.45.
  If only one side joins, that side takes it without a fight; if both do, after an `OBJ_ENGAGE_ROUNDS`-round engage
  (`EngagePhaseManager.start_objective_engage`) the winner is decided by **survivor count → sum of
  remaining HP ratios**. Dead pilots can't participate, which is a corresponding disadvantage.
- **Rewards** — Herald: 1 [전령 제압] (Herald Subdued) (cost = its cards.csv `cost`, keep (보존) + exhaust) into the hand. Deals
  its `turret_damage` clause (cards.csv) as damage to the outermost enemy turret (doubled if there are no enemies on that lane's
  front line), and **allies in that lane split that much growth points evenly**. Dragon: `OBJ_DRAGON_CARD_COUNT`
  [용 보상] (Dragon Reward) (cost = its cards.csv `cost`, exhaust) shuffled into the deck. Its `draw:N` clause + a **permanent**
  growth accrual multiplier from its `growth_perm:N` clause (cards.csv) for a chosen ally (`PilotData.growth_rate_bonus`, cumulative).
  The old `OBJ_DRAGON_GROWTH_PCT` game_config key was deleted — the card clause is the only source.
  Both cards are `pool = 0` and **have no caster** (`owner_pilot == null`).
- **Rewards come in through an effect** (`objective/ObjectiveRewardFx.gd`) — for Dragon,
  N cards fan out in the centre, stack as one, and go to the **deck pile at the bottom left**;
  for Herald, one card floats up and settles into **the leftmost hand slot**. If the enemy takes it,
  both vanish to **the left end of the opponent's hand at the top**. `_grant_reward` grants **after**
  `await`ing the effect, so the same card is never visible in two places.
- **The objective only borrows those coordinates as a stage; the two cells are ordinary jungle cells** —
  camps stand there, junglers step on them to capture, and side T1 destruction changes their owner. At one point
  they were permanently neutral, so camp cells dropped 14 → 12 and `SCORE_JUNGLE_CAMP` had been raised
  to compensate; with the two cells back, **it was reverted to its previous value**.
- Turns remaining are always shown in the two `ui/ObjectiveTimer.gd` slots in the **top panel**
  (on both sides of the enemy strip, left Herald / right Dragon). The section that printed them on battlefield tiles
  (`BattleRenderer._draw_objectives`) was deleted.

### Card Phase (operation phase)

> **Deck composition changed.** The "3 mech cards" pilots used to receive are gone; **the assigned
> mech brings its whole card set** (`mech_cards.csv`, expanded by `count` —
> 2~7 cards per mech). The 3 pilot cards remain. Deck size opened up from a fixed 30 to
> 25~50, and that difference itself is part of choosing a mech. The new keyword **Charge (충전)**
> (strength accumulates every time it enters the hand and is spent all at once on use) and **cost -1**
> (a card that cannot be played) also attach here — see the corresponding section in `card_phase/README.md`.

- Triggered when `player_cost >= PHASE_THRESHOLD`.
- **The opening state is decided by side.** The `BattleSim.blue_team` side (derived from
  match_ctx.player_side; MatchFlow currently always fixes the player to BLUE) starts with a head start of
  `BLUE_COST_HEAD_START` strategy points, so it reaches the threshold first
  — the price for banning/picking second in ban/pick. **There is no opening hand** — both teams
  start with 0 cards, and the hand fills only through auto-draw running from `ECONOMY_START_TURN`.
  The hand cap is `MAX_HAND_SIZE` (all game_config.csv), read per side through
  `BattleSim.max_hand_size_for(is_player)` (the player's cap takes the `hand_size` trait).
- Ending the phase goes through the player's strategy-point donut: tap it once to
  flip it into a circular 턴 넘기기 (End turn) button, tap again to end. **You can pass without playing a single
  card** — the face greys out and locks only in states where closing now would cut something off, such as
  a banner / modal / attack-hit effect.
  Tapping anywhere else flips it back to the point readout.
- Phase end re-runs recalls (HP threshold + out-of-position card displacement)
  and drops straight back to BATTLE. At that point **strategy points over the threshold are lost**
  (`player_cost` = `PHASE_THRESHOLD`), and the side that passed cannot get the turn again until its hand
  changes or the opponent has had one turn (pass lock). If the opponent is already above the threshold
  it switches **to the opponent's turn on the spot** without waiting for the next tick. There is one more
  paired rule — **above the threshold, `COST_RECOVERY` does not come in**
  (same for both teams). Together the three make the threshold the effective cap on strategy points.
- **The AI's turn is its own**, no longer stapled to the player's phase end:
  it fires from the BATTLE tick when `ai_cost >= PHASE_THRESHOLD` *and* the AI
  holds a card it can pay for, and only then does the "상대 차례" (Opponent's turn) banner show.
  It runs inside BATTLE with the auto-tick held, then runs the same recall
  sweep. When **both** sides are over the threshold on the same tick,
  `CardPhaseManager._next_turn_side()` arbitrates: blue first, and from then on
  **alternation** — the side that didn't take it last time takes it. Alternation handles starvation prevention, so the old
  "always check the AI first" rule is gone.
  See [`card_phase/README.md`](card_phase/README.md).

### Engage (전투 개시) — side-view belt engage (round-based turns)
Card-driven sub-phase: `engage:N` opens a **turn-based side-view belt stage**
(spectate-only — no player input). On close it returns to the phase that opened it —
CARD_PHASE for a player card, BATTLE for an AI card played during the opponent's turn —
see [`engage/README.md`](engage/README.md) for details. Key contract:
- Participants = pilots in radius-1 hex from caster (caster cell + 6 neighbors).
  `exclude_lane` drops lane pilots still on their lane row; junglers and
  displaced-into-jungle lane pilots stay in. Still supported end-to-end, but
  the only card that used it (교전 (Engage), id 4) has been removed from the pool.
- **The N in `engage:N` is the number of rounds** (`engage:N` = N rounds). The old
  "N × 3 seconds" conversion was deleted. `duel` runs until the first kill with only a
  `DUEL_MAX_ROUNDS` cap (const.csv `ENGAGE_DUEL_MAX_ROUNDS`).
- **One round = every participant acts exactly once.** There is always **only one** unit
  out on the stage (`current_actor`), and when that turn (approach → attack → settle) ends it moves to
  the next in order. On reaching the end of the order the round increments and it goes **back to the caster**.
- **The action order is fixed once at the opening and repeats every round** — starting with the caster's team,
  **alternating teams** one at a time, and within a team **fixed by role** (assassin → fighter → tank →
  sniper → supporter), except that **the caster is pulled to the front of its own team**. Turrets act once each
  after all pilots, starting with the caster team's turrets. Dead actors are skipped.
- **The mech `speed` stat has been deleted** — since everyone acts once per round, there is no stat
  deciding action frequency. `game_config.TURRET_SPEED` disappeared with it.
- **Battlefield cell positions are not reflected in the layout.** The stage is a flat belt with team 0 on the left /
  team 1 on the right facing each other, and position is decided by role — melee in the front row, ranged in the back.
- Melee closes in to contact (`ENGAGE_MELEE_REACH`), ranged to `ENGAGE_RANGED_APPROACH_RATIO` **of max
  range** (`ENGAGE_RANGE_RANGED`, all const.csv), then strikes. Range checks get a `STRIKE_DIST_EPSILON` slack — without it a unit standing exactly
  at range fails the check due to floating-point error and the attack never happens.
  **There is no return to the original position** — where the attack ended is the new anchor. On a hit the target is
  knocked back and **the spot it was pushed to also becomes its new anchor** (it doesn't add to damage; it only changes
  position and re-approach distance).
- **No leaving mid-engage** — nobody can leave the stage. It ends only when rounds run out or
  one side is wiped. Even near death (HP<30%) units don't retreat.
- **Between end → dashboard there is an `EngagePhaseManager.END_HOLD_SEC` grace** (const.csv `ENGAGE_END_HOLD_SEC`).
  So the last kill isn't swallowed by the result window, it shows the stage with only combat stopped for that
  long (remaining effects via `TurnEngageSim.step_afterglow`) and puts up an end-reason banner at the top
  (`적군 전멸` (Enemy wiped out) / `N라운드 완료` (N rounds complete) …). `round_index` stops during the grace,
  so the dashboard's round count is exactly the number of rounds actually fought.
- **Assassins prioritise the enemy back row (ranged)** (`DIVE_FOCUS`). Without this
  branch the front row is closer and has higher presence (mechs.csv), so ranged mechs never take a single hit
  the whole engage — a hole confirmed by measurement.
- **Turrets are participants, not range zones**: **in an engage the enemy started**, if a participating pilot
  stands on its own team's turret cell, that turret joins and **attacks an enemy pilot once per
  round** (no range limit; the hit roll is rolled). Turret HP is not reduced on the stage.
  **Two cases where it does not join** — **the caster team's turret** (the side that opened the engage is the side that
  forced it; if a side squatting on a turret cell and opening engages by card also got its turret, that
  cell would become a one-sided safe zone) and **objective engages** (there is no caster, so there is no "who
  started it", and the stage opens on a neutral cell) — the turret section of `engage/README.md`.
- Damage (one atk's worth + shield-first) matches the battlefield, but **hit chance is
  separate**: engage remaps the battlefield probability `base` into **the band
  [`PILOT_HIT_MIN`, `PILOT_HIT_MAX`]** (const.csv; equal stats land at the band's midpoint). The old
  engage-only `ENGAGE_HIT_MIN` / `_MAX` were deleted.
  KO routes through `BattleSim.mark_pilot_dead(victim, killer)`, so an arena kill
  gets the same scaled respawn timer (`respawn_turns_now()`) and the same
  growth-point settlement a battlefield kill does. `grid_pos` is never modified by an engage.
- The screen consists of one horizontally flat **cinema band** (1032×500) and, **below it, a strip of participant
  portraits** (HP is shown by the HP ring on the stage portraits — the same shape as the battlefield marker). The top header is two lines: **round counter
  (`라운드 2 / 3` (Round 2 / 3)) + round pips + "whose turn"** (the remaining-time bar from the real-time era
  was deleted). Dashboard shows per-pilot dealt / taken / kills before resuming.
- Measured (headless 5v5 ×8, 3-round engage): much milder than the ATB era — each unit hits only once per
  round, so 3 rounds = at most 30 hits.

### Growth points (성장치, pilot score) — growth currency
A **growth currency** each pilot starts with at `SCORE_START` (const.csv; lowered in the growth-economy rebalance) and accumulates throughout the match. Equivalent to
gold in a MOBA. It is printed as a number under the HP bar on the pilot strip, and the team
score at top centre is the **sum** of that team's five. There is no cap, so
it is a number, not a gauge.

**`PilotData.growth` is derived from this value** — previously the two were completely unrelated
(growth was elapsed time, growth points were a display-only record), so neither taking kills nor pushing turrets changed
stats one bit. The conversion and the reasons are in "Growth / laning stats" in `combat/README.md`.

All values below live in const.csv (`TURRET_HP` in game_config.csv).

| Source | Value | Who |
|---|---|---|
| Front-line presence (per turn) | `SCORE_FRONTLINE_PER_TURN` — **cut by `SimulationCore.BOND_INCOME_CUT` while lane-bonded** | lane pilots |
| One jungle camp | `SCORE_JUNGLE_CAMP` (respawns after `JUNGLE_CAMP_RESPAWN_TURNS`) | jungler |
| Kill — last hit | `SCORE_KILL_BASE` + lead gap × `SCORE_KILL_BOUNTY_RATE` | everyone |
| Kill — assist | bounty × `SCORE_ASSIST_MAX_SHARE` × (my damage / total damage) | everyone |
| Turret damage | `SCORE_TURRET_FULL` ÷ `TURRET_HP` per 1 damage | lane pilots |

**The turret's share goes to the labour, not the demolition.** Previously the pilot who landed the last hit
at the moment of demolition took the whole turret value (`SCORE_TURRET_KILL`), so a pilot who pushed for many turns
got the same share as one who put in the last hit, and someone who ground it halfway and
died got nothing. Now it is split **per HP point chipped off**
(`BattleSim.score_turret_damage`), so shares match how much each actually pushed — grinding down a whole turret
gives exactly `SCORE_TURRET_FULL` in total, as before. **`TURRET_HP` was raised** (tuned against
`PILOT_STRUCTURE_DMG` — change them together, since together they set how many turns an undefended / defended
siege takes). A turret's worth (`SCORE_TURRET_FULL`) is unchanged, so only the per-point value dropped.
Overkill is cut off: even if three pilots pour more into a turret than its remaining HP,
only the remaining HP's worth pays out. There are two accrual points — turn combat's
`SimulationCore._credit_turret_damage` and card damage's `apply_card_turret_damage`.
`score_turret_kill` now only handles the kill feed line and the event hook.

**What's missing is the point.** HQ **damage** still gives no score (chipping the HQ
is already getting closer to victory). Pilot damage too is only written to a ledger at that moment,
not scored (`SCORE_PER_PILOT_DMG` / `_HQ_DMG` deleted). **There is no death penalty
either** (`SCORE_DEATH` deleted) —
the penalty is that front-line income and camps stop entirely while dead, and that is the real cost,
proportional to respawn turns. No reason to charge the same loss twice.

**Assist = catch-up mechanism.** The bounty is proportional to "how far the victim is ahead of the killer team's average",
so catching an ace far ahead pays much more than a plain kill. A team that is behind
can catch up with one good engage, and the side ahead doesn't lose out.

All constants are gathered in the `SCORE_*` section of `BattleSim`, and every change passes through
`BattleSim.add_score` alone — so that the floor (`SCORE_MIN`, const.csv), accrual multiplier
(`growth_rate_mult`) and stat recompute are handled in one place only.

**Damage attribution wiring**: damage does not become score immediately. `BattleSim.record_pilot_damage`
writes it in **the victim's ledger** (`PilotData.damage_credit`, `attacker → [(turn, that turn's damage)]`),
and when the target actually falls, `_payout_kill_bounty` splits it between the last hit and
assists, then clears the ledger. Battlefield auto-combat · attack cards · the engage stage
all pass through that single point, so there is one table.

**Kill involvement is a `SCORE_ASSIST_WINDOW_TURNS` (const.csv) window.** Each record carries a turn
stamp (damage in the same turn is merged into one entry), and entries older than that drop out of both
assist distribution **and the denominator** — a scratch landed long before the window having a stake in a kill
made now isn't involvement, and if expired entries stayed in the denominator, the shares of the people who actually
got the kill now would be quietly cut. The decision is made only by **one function**, `BattleSim.live_damage_credit(victim)`,
which actually deletes expired entries while reading. All three consumers (bounty distribution ·
kill feed roster · the kill-involvement hook in `PilotSkillSystem.on_kill`) read that function, so
the faces on screen and the faces that got score can't diverge — if any code iterates `damage_credit` directly,
at that moment there are two rules.

**Who the last hit is** is a separate problem: battlefield damage is split into a decision stage (`_resolve_*`
only accumulates amounts into `damage_map`) and an apply stage (which drains it to reduce HP),
and in the apply stage **who hit is no longer recorded**. So `SimulationCore`
writes "the last one who hit this target" in `_last_hitter` / `_last_turret_hitter` inside
`_credit_pilot_damage` / `_credit_turret_damage`, and the apply stage passes
it to `mark_pilot_dead(victim, killer)` / `score_turret_kill(killer, td)`. The two
dicts are **cleared at the start of every turn and every advance card** — if they survived across turns, the kill
would be credited to the wrong person. The engage stage and attack cards hold the attacker in hand, so they don't need
this detour.

**The kill feed reads this same table** — inside `mark_pilot_dead`, `_push_kill_feed` runs **before** settlement
(`_payout_kill_bounty`) and hands the last hit + assist
roster to `ui/KillFeed.gd` (because settlement clears `damage_credit`). So
the faces shown at the top right of the screen and the faces that received growth points can't diverge. Turret demolition
is handed to the same feed by `score_turret_kill`, and objective captures by `ObjectiveSystem._push_feed` — details in the
"Kill log" section of `ui/README.md`.

### Growth-point popup (above battlefield portraits)
Only at moments when growth points rise **by a large amount at once** does a soul icon + white text (thick black outline) `+N`
float up over that pilot's face (`BattleRenderer.spawn_score_popup`, 1.10 s · 72px). **Gains are not folded into k;
they are printed as full integers** (`BattleSim.fmt_score_gain`, 0.3 → `300`) — the growth line on the engage result screen
does the same. Cumulative growth points (strip · detail panel) keep the k notation of `fmt_score` because the slots are narrow. If the number
just changed quietly in the strip slot, "what was that one hit worth" would not stay on screen.

| Where it appears | Trigger |
|---|---|
| Turret damage | `score_turret_damage` — every hit |
| Kill bounty | last hit and each assist separately (`_payout_kill_bounty`) |
| Engage total | after the stage closes, **merged into one** per participant |

| Jungle camp | `SimulationCore.harvest_camp_under` / `steal_camp_point` — `SCORE_JUNGLE_CAMP` each time |
| [캐시] (Cash) interest | `MechSkillSystem._payout_cash` — `MECH_CASH_RATE` (const.csv) of the holder's growth points each time a card is played |

**Only front-line presence (`SCORE_FRONTLINE_PER_TURN` per turn) is left out** — if numbers popped over ten faces every turn they would
become the background and bury the one big gain. Jungle camps are the opposite: the patrol rhythm is the jungler's
play, yet that beat left no trace on screen, and the gain happens once to one pilot, not to ten every turn,
so it doesn't become background. [캐시] is the same reason — without a trace,
holding that card in hand and not holding it would be indistinguishable on screen.

The wiring is one layer: `add_score`, which only accrues silently, is split from
`award_score`, which adds a popup on top, so **which sources show on screen is readable at the call site**.
`add_score` now returns **the actual increase** after the floor and accrual multiplier, so the popup shows
the amount that went in, not the amount requested.

Two things don't get popups. **Dead pilots** — the body leaves the battlefield after 1.45 s, and
a number shown after that stands over no face (assists still arrive after the assister is dead,
so this path really is hit). And **while an engage is running** — the arena covers the screen
so nobody sees it, and popup coordinates are fixed to the marker position at the moment of spawning, so by the time the
stage is cleared they would float somewhere wrong. Accruals in between pile up in `BattleSim._score_popup_hold`
and are released as **one popup per pilot** in `flush_score_popups()`, called by
`EngagePhaseManager._on_dashboard_confirmed` (same place and same reason as the kill feed's `_pending`).

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
| Combat damage (battlefield auto-combat) | `SimulationCore` damage_map apply | `anim_pilot_shake(p)` → `ANIM_SHAKE_DUR` 0.18s / `ANIM_SHAKE_AMP_PX` 6px horizontal jitter (decaying) |
| Attack card hit | `CardPhaseManager._apply_attack_damage` | same call with `ANIM_SHAKE_CARD_DUR` 0.26s / `ANIM_SHAKE_CARD_AMP_PX` **20px** — unlike engagement damage that happens automatically every turn, a card hit is the one blow the player just chose, so it shakes much more violently. The frequency is the same, so the oscillation count rises from 4 → 5.8 along with it |
| Movement (free + push advance + push retreat) | `resolve_movement` (once per pilot per turn) | `anim_pilot_move_path(p, path)` → the renderer glides it along **the polyline of cells actually stepped on** with a 0.30s smoothstep (`BattleRenderer._glide`). Even a mere slot change gets the same glide — the portrait never teleports under any circumstances |
| Card move / advance (`move`, `advance:N`) | `SimulationCore._step_pilot` | `anim_pilot_move(p, orig)` — steps in the same frame are **appended to the path**, so `advance:N` walks N cells in order |
| Recall — low HP / out of position | `RecallSystem.return_to_hq` | `anim_pilot_recall(p, orig)` → 0.20s fade-out + rise at `orig`, then 0.25s fade-in + descend at HQ. Both halves always play — the pilot never leaves the field, and it is holding still that turn, so the fade-in stays anchored at the HQ |
| Recall — 복귀 (Return to Base) card | `CardPhaseManager._effect_recall_ally` | same `anim_pilot_recall(p, orig)` sequence |
| Respawn (after death) | `SimulationCore.process_respawns` | `anim_pilot_respawn` → fade-in + descend at HQ only (skip phase 1); also clears any leftover death effect |
| Death | `BattleSim.mark_pilot_dead` | `anim_pilot_death` → `ANIM_DEATH_HOLD_DUR` (1.0s) dimmed-in-place at the cell they fell on, then `ANIM_DEATH_FADE_DUR` (0.45s) fading out while rising `ANIM_DEATH_RISE_PX`, then off the field |
| Attack card hit / miss | `CardPhaseManager._effect_attack` | `BattleRenderer.spawn_pilot_popup` → `-N` / `MISS` / `흡수` (Absorbed) floating over the target's marker |
| Turret hit | `SimulationCore` turret_dmg apply (`simulate_turn` + `_apply_card_damage`), survivors only | `anim_turret_hit(td)` → `ANIM_TURRET_HIT_DUR` (0.26s) of decaying horizontal jitter (`ANIM_TURRET_HIT_AMP_PX` 9px) plus an `ANIM_TURRET_HIT_TINT` red flash fading back to white |

`BattleSim._process` runs `_advance_pilot_animations(delta)` **and**
`_advance_turret_animations(delta)` every frame (both, never short-circuited)
and calls `renderer.queue_redraw()` while any timer is active. Constants live on
`BattleSim`: `ANIM_MOVE_DUR`, `ANIM_SHAKE_DUR`, `ANIM_SHAKE_AMP_PX`,
`ANIM_SHAKE_CARD_DUR`, `ANIM_SHAKE_CARD_AMP_PX`,
`ANIM_RECALL_FADE_OUT_DUR`, `ANIM_RECALL_FADE_IN_DUR`, `ANIM_RECALL_RISE_PX`,
`ANIM_DEATH_HOLD_DUR`, `ANIM_DEATH_FADE_DUR`, `ANIM_DEATH_RISE_PX`,
`ANIM_DEATH_TINT`, the turret trio `ANIM_TURRET_HIT_DUR` /
`ANIM_TURRET_HIT_AMP_PX` / `ANIM_TURRET_HIT_TINT`, and the popup trio
`DMG_POPUP_DUR` / `DMG_POPUP_RISE_PX` / `DMG_POPUP_STAGGER`.

**Only the turret effect lives outside the renderer.** A turret's sprite is a `Building` node under
`BattleField/BuildingLayer`, not something `BattleRenderer._draw()` paints, so
`BattleSim._apply_turret_hit_visual` writes the shake/flash straight onto that
node's `position` / `modulate` (base position cached per cell in
`_turret_home_pos`, restored on the last frame and on restart via
`_clear_turret_hit_visuals`). The renderer only mirrors the same offset onto the
turret HP bar by reading `BattleSim.turret_hit_offset(td)`.

`BattleRenderer` decides *whether* to draw a pilot with `_is_renderable(p)`
(alive, or mid-death, or mid-recall-fade-out — the last two run after `alive`
is already false), groups them by `_render_cell(p)` (`anim_recall_orig` during
fade-out, `anim_death_cell` during the death effect, otherwise `grid_pos`) and
applies per-pilot pixel offset and alpha via `_pilot_anim_offset` /
`_pilot_anim_alpha`.

**Movement alone is owned entirely by the renderer.** `BattleSim` holds no movement timer
(`anim_prev_grid_pos` / `anim_move_t` / `anim_move_dur` were deleted),
and only leaves **the path of stepped cells** in `PilotData.anim_move_path`. Interpolating marker coordinates and
redrawing meanwhile is handled by `BattleRenderer._glide` — detailed rules (polyline,
separate beats for angle and length, cases where it snaps) are in the *Marker glide* section of
[`rendering/README.md`](rendering/README.md).

---

## Dependencies

- `resources/GameEnums.gd` — shared enums
- `resources/PilotData.gd`, `TurretData.gd` — data classes
- `autoloads/GameManager.gd` — match_ctx + cards table loader
- `scenes/Card.tscn` (script: `features/battle_sim/card_phase/Card.gd`) — card visual node
- `scenes/BattleField.tscn` — TileMapLayer + Building/Waypoint child scenes


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Auto BATTLE | BATTLE auto-ticks every 0.5s (1 tick = "1분" (1 minute)). No Next-Turn or Auto-Play buttons. CARD_PHASE pauses the tick, and so does the opponent's turn — that one runs *inside* BATTLE without changing `game_phase`, so `BattleSim._process` also gates on `card_phase.is_ai_turn_active()` (same flag freezes the MM:SS clock). |
| Side (blue / red) (진영) | `BattleSim.blue_team` (0 = player team) is derived from `match_ctx.player_side`. **Red = first ban/first pick in ban/pick, blue = second ban/second pick + first in-game**. Blue has two in-game advantages — (1) `BattleSim.seed_side_costs()` seeds strategy points at `BLUE_COST_HEAD_START` (game_config.csv) at the opening so it reaches the threshold first (COST_RECOVERY gives both teams the same amount on the same tick, so the gap persists), and (2) when both teams are above the threshold on the same tick, **it takes the turn first**. **`MatchFlow` currently always fixes the player to BLUE** — the old random draw every match was removed; to revive it, revert just the single fresh-entry line in `MatchFlow._ready()`. |
| Economy gate (`ECONOMY_START_TURN`) | Strategy-point recovery and auto-draw run **from turn `ECONOMY_START_TURN`** (game_config.csv, `CardPhaseManager.do_battle_turn`). Before that the two counters don't roll at all, so backed-up recovery doesn't burst out when the gate opens. Since the opening hand is gone, **the only thing in at turn 0 is blue's `BLUE_COST_HEAD_START` head start**, and the turns before the gate are a pure laning stretch with both teams at 0 cards in hand · fixed points. **Growth does not ride the gate** (from turn 1). Recovery and draw then come in every `COST_RECOVERY_INTERVAL` / `CARD_DRAW_INTERVAL` turns until a side reaches `PHASE_THRESHOLD`; the gate was moved later over time, pushing the first operation phase later with it. Running BattleSim.tscn directly without `match_ctx`, the HQ can collapse **before the game even reaches the first operation phase**. |
| Growth (in-game accumulation) | **Growth comes from growth points (`PilotData.score`), not time.** Previously, merely being alive made `atk` and `max_hp` grow together by `GROWTH_PER_TURN` every turn, and that design had two flaws — (1) pilots grew even doing nothing, so kills·turrets·farming had **no effect** on growth, and (2) both grew at **the same rate**, so "how many hits until death" was mathematically invariant (even with both ×1.5 at turn 50, engage hit counts didn't drop by a single hit). It wasn't that growth went unseen; structurally it couldn't be seen. `GROWTH_PER_TURN` was **deleted** from game_config. Now the single place `BattleSim.refresh_growth_stats` derives stats from growth points: **attack `GROWTH_ATK_PER_SCORE` / max HP `GROWTH_HP_PER_SCORE`** (const.csv, multiplier gain per 1k) — attack is tuned to grow **much faster** than max HP, and that asymmetry is the whole feel of growth. The two are tuned against a reference growth-point total reached around mid-game (see `combat/README.md`). Instead of multiplying each turn, stats are **recomputed** from `base_atk` / `base_max_hp` (prevents accumulated rounding error). Current HP rises along with the max-HP increase. The recompute runs **the moment the score moves** (`add_score`), so "took a kill, got stronger" reads as one beat, and `SimulationCore.tick_growth_and_expiries` remains as insurance that only clears multiplier expiries. **Temporary** attack applied by cards goes onto `PilotData.atk_buff`, not `atk` — pushing `atk` directly would be wiped by a mid-turn recompute and the end-of-turn revert would eat into the original. The gain multiplier (`growth_rate_mult`) now multiplies **growth-point accrual, not growth** (same result, one less layer of wiring), and is touched by **신중한 예산 (Careful Budget) · 성장 가속 (Growth Acceleration) · 소극적인 태세 (Passive Stance)** (turn expiry) and **완벽한 마무리 (Perfect Finish)** (its cards.csv clause, until the next operation phase, whole team) — same field, so whichever is applied later overwrites. `add_score`'s final multiplier also adds the [골드러시] (Gold Rush) share (`CardPhaseManager.hand_growth_add` — tokens on Gold Rush cards held in hand × `CARD_GOLD_RUSH_GROWTH_PER_TOKEN`, const.csv). Max HP is multiplied by `bonus_max_hp_mult` ([워밍업] (Warm-up)) together with growth HP. |
| Growth points (pilot score) (성장치) | The pilot's **growth currency**. Equivalent to gold in a MOBA, it starts at `SCORE_START` (const.csv) at the opening and accumulates throughout the match (`PilotData.score`). `SCORE_START` was lowered in the growth-economy rebalance; the measurement below predates that, so it was taken with the old, higher opening value. The accrual constants were **derived backwards** from a headless measurement (5v5, real mech stats injected, full loop — **the floor where the player plays not a single card**) so that this floor, fed through the growth conversion above, lands on the design reference point around mid-game. They were initially set lower, aiming at a front-line + kills split, but front-line presence rates were higher than expected while **almost no kills happened** (battlefield auto-combat damage is scaled down by `BATTLE_PILOT_DMG_MULT` (game_config.csv), so laning alone doesn't kill anyone — kills effectively come only from engages·attack cards, so they depend entirely on how much the player fights). So front-line income was raised so that **the floor where nobody fights** reaches the target, and kills are an acceleration layered on top. **It is not something different from `growth` right above; it is its source** — previously the two were completely unrelated (growth was time, growth points a display-only record), so taking kills didn't change stats one bit. There are only three sources. **(1) Front-line presence** — `SCORE_FRONTLINE_PER_TURN` for each turn alive standing inside your own lane's front line. Most income comes from here (the "Front line" entry below). **(2) Jungle camps** — jungler only, `SCORE_JUNGLE_CAMP` (the "Jungle camp" entry below). **The camp value being much larger than a laner's per-turn income (`SCORE_FRONTLINE_PER_TURN`) is an intended correction** — camps must be walked to and their respawn (`JUNGLE_CAMP_RESPAWN_TURNS`) waited for, so pickup frequency is under once per turn, and with equal per-camp value the jungler's per-turn income is structurally lower than a laner's. The camp value was raised until jungler income roughly matched a laner's, and raised again in proportion when the respawn was slowed — **change `SCORE_JUNGLE_CAMP` and `JUNGLE_CAMP_RESPAWN_TURNS` together**. The growth-economy rebalance then slowed the respawn once more and **cut** the camp value — a deliberate jungle nerf, not an income-preserving correction. In return, a jungler's income is never cut off by being pushed back or by return-to-base. **(3) Kill bounty** — the last hit gets the full `SCORE_KILL_BASE` + `SCORE_KILL_BOUNTY_RATE` of how far the victim is ahead of the killer team's average, and other allies who damaged that target get **up to `SCORE_ASSIST_MAX_SHARE` in proportion to damage** on top (`bounty × SCORE_ASSIST_MAX_SHARE × my damage / total damage that target took this life`). This is the "weak catch-up" mechanism — catching an ace far ahead pays much more than a plain kill. **(4) Turret damage** — `SCORE_TURRET_FULL` ÷ `TURRET_HP` per HP point chipped off (per hit that is times `PILOT_STRUCTURE_DMG`). Previously **at the moment of demolition** the pilot who landed the last hit took the whole turret value (`SCORE_TURRET_KILL`, **deleted**), so a pilot who pushed for many turns got the same share as one who put in the last hit, and someone who ground it halfway and died got nothing — a siege is not a single event but labour over many turns. The total is unchanged, so a turret's worth didn't change, and **overkill is cut off** (even if three pour more into a turret than its remaining HP, only the remaining HP's worth pays out). Accrual passes through the single function `BattleSim.score_turret_damage`, called from two places — turn combat's `SimulationCore._credit_turret_damage` and card damage's `apply_card_turret_damage`. `score_turret_kill` now only handles the kill feed line and the event hook. **HQ damage still gives no score** (`SCORE_PER_PILOT_DMG` / `_HQ_DMG` deleted). **There is no death penalty either** (`SCORE_DEATH` deleted) — the penalty is that front-line income and camps stop entirely while dead, and that is the real cost, proportional to respawn turns. Constants are gathered in the `SCORE_*` section of `BattleSim`, and every change passes through `BattleSim.add_score` alone (so that the floor `SCORE_MIN` and the accrual multiplier are handled in one place only). On top of that is a separate `award_score` that adds one popup layer — the "Growth-point popup" entry below. Display is `fmt_score`, and since there is no cap it is **a number, not a gauge** — as digits grow, decimal places shrink (e.g. `1.00k` → `24.9k` → team total `125k`). Showing the number move in the opening stretch needs two decimal places, but keeping them late pushes digits out of the narrow strip slot into the neighbouring slot. Team score (`team_score`) is the sum of members (opening value five × `SCORE_START`), and it includes dead pilots. **Damage attribution wiring**: damage does not become score immediately; it accumulates in **the victim's ledger** (`PilotData.damage_credit`, `attacker → [(turn hit, total damage that turn)]`) and is settled when that target actually falls — battlefield auto-combat · attack cards · the engage stage all pass through the single point `BattleSim.record_pilot_damage`, so there is one table. The ledger is cleared on settlement. **Kill involvement is a `SCORE_ASSIST_WINDOW_TURNS` (const.csv) window** — each record gets a turn stamp (damage in the same turn is merged into one entry), and entries older than that drop out of assist distribution **and the denominator** (if expired entries stayed in the denominator, the shares of those who got the kill now would be quietly cut). The decision is made only by **one function**, `BattleSim.live_damage_credit(victim)`, which actually deletes expired entries while reading — all three consumers (bounty distribution · kill feed roster · `PilotSkillSystem.on_kill`) read that function together, so the faces on screen and the faces that got score can't diverge. Meanwhile **who the last hit is** is a separate problem: battlefield damage is split into a decision stage (only accumulating amounts in `damage_map`) and an apply stage (reducing HP), and the attacker no longer remains at apply time, so `SimulationCore._credit_pilot_damage` / `_credit_turret_damage` write "the last one who hit" in `_last_hitter` / `_last_turret_hitter`, and the apply stage passes it to `mark_pilot_dead(victim, killer)` / `score_turret_kill(killer, td)`. The two dicts are **cleared at the start of every turn and every advance card**. **The kill feed reads the same table too** — the "Kill feed" entry above. The engage stage and attack cards hold the attacker in hand, so they don't need this detour. |
| Battlefield size | **There are two scales.** `HexGrid.FIELD_SCALE` (90% of `DISPLAY_SCALE`) sets tile·building·waypoint scale and hex geometry (`hex_size` / `hex_height`), and `HexGrid.DISPLAY_SCALE` = **1.35** sets what is drawn **on** the battlefield — pilot portraits / HP rings / popups / preview line widths · fonts. They were split to shrink only the battlefield by 10% while keeping portrait size (before, the single 1.35 did both). The battlefield pixel box went 891×983 → about 802×885; the field centre is unchanged, so top and bottom each move ~49px inward. The hand (`BS_HAND_CENTER`) was not moved up to follow this time. Anything that must track tile size derives from `hex_size`; anything that must track portrait size derives from `DISPLAY_SCALE`. |

### Module Architecture table (moved from root CLAUDE.md)
`BattleSim.gd` is a **thin orchestrator** (`class_name BattleSim extends Node2D`).
Each child module has `@onready var _bs: BattleSim = get_parent() as BattleSim` and accesses state via `_bs.*`.

| Node | Script | Purpose |
|---|---|---|
| SimulationCore | `combat/SimulationCore.gd` | Main turn loop, targeting, movement, win condition |
| RecallSystem | `combat/RecallSystem.gd` | Instant HQ teleport at HP ≤ threshold |
| Pathfinding | `combat/Pathfinding.gd` | BFS + greedy movement |
| BattleRenderer | `rendering/BattleRenderer.gd` | All `_draw()` logic (extends Node2D) |
| CardPhaseManager | `card_phase/CardPhaseManager.gd` | Card turn flow, deck, hand, card effects |
| GambitPhaseManager | `gambit/GambitPhaseManager.gd` | Pre-opening phase — role-fixed lane assignment + battlefield setup (`prepare_field`) + jungle start overlay + opening (`begin_battle`) |
| JungleStartOverlay | `gambit/JungleStartOverlay.gd` | **Jungle start cell** — the player drags the ally jungler marker standing on the battlefield (no tail) directly onto one of our jungle / neutral cells (the enemy jungle is disabled; shows HQ→that cell + the 6-turn path after arrival with turn numbers — `SimulationCore.predict_jungle_path`) and confirms with "전투 시작" (Start battle). That cell becomes the jungler's first target (`PilotData.jungle_start_cell`). Opens only when `match_ctx.active` |
| ObjectiveSystem | `objective/ObjectiveSystem.gd` | Objectives (Herald / Dragon) — timers · participation decision · settlement on the left/right neutral cells. The decision window and stage borrow the engage module's VS screen and arena |
| ObjectiveRewardFx | `objective/ObjectiveRewardFx.gd` | Objective **reward pickup effect** — spreads the reward card in the centre of the screen, then flies it to where it goes (deck pile / left end of the hand / opponent's hand). `_grant_reward` awaits it **right before granting** |
| MechSkillSystem | `mech/MechSkillSystem.gd` | Mech skills — 15 passives attached to the assigned **mech** and the persistent states its mech cards leave (vulnerable · reactive armour · target · tracking · bounty …). The computation happens where it always did; this module only exports query functions |
| TraitHooks | `trait/TraitHooks.gd` | Manager in-game traits (`match_ctx.traits`, player only) — query functions read by `seed_side_costs` · `effective_cost_for` · `max_hand_size_for` · the BATTLE economy tick |
| PilotSkillSystem | `skill/PilotSkillSystem.gd` | Pilot skills — 25 unique abilities attached to each player (cooldown / charge-based / passive). State · activation · event hooks · passive queries |
| EngagePhaseManager | `engage/EngagePhaseManager.gd` | Top-view engage orchestrator — chains `engage/TurnEngageSim.gd` (headless round-based turn sim; `prepare_sim` builds it **in advance**) → `engage/EngageIntro.gd` (VS confirm screen right after submission, showing that stage as a still frame) → `engage/EngageArena.gd` (renderer) |
| HudBuilder | `ui/HudBuilder.gd` | HUD scene binding (`ui/UI_View_BattleHud.tscn` + `ui/UI_Comp_PilotStrip.tscn` · `ui/UI_Comp_PilotStripCell.tscn`) and update (incl. `ui/CostDonut.gd` strategy-point donut ×2, `ui/PilotStrip.gd` pilot strip ×2, `ui/CardPileStack.gd` deck / discard pile stacks ×2, `ui/KillFeed.gd` kill feed, `ui/ObjectiveTimer.gd` objective timer ×2) |
| ObjectiveRewardPopup | `ui/ObjectiveRewardPopup.gd` | Objective reward preview — tapping a timer shows the real card that objective grants. Does not hold the battlefield |
| PilotDetailPanel | `ui/PilotDetailPanel.gd` | Pilot detail modal — opens by tapping a face in the strip / long-pressing a battlefield portrait (operation phase + auto-progress). Header (name / mech name below it / growth points on the right) + 3 tabs In-game / Pilot / Mech + a full-width fan of held cards at the bottom of the screen |
| BattleLogger | `debug/BattleLogger.gd` | Full action log + automatic enemy-pilot cross-over detection |

### Match Flow → Battle Sim handoff
`MatchFlow` populates `GameManager.match_ctx` (player_roster, enemy_roster,
jungle_start_dir, banned_mech_ids, …) then `change_scene_to_file` to BattleSim.
`BattleSim.spawn_pilots_with_lanes()` injects each `PlayerData.assigned_mech`'s
hp/atk into `PilotData`. If `match_ctx.active` is false (running BattleSim
standalone), it falls back to `ROLE_STATS` defaults.
