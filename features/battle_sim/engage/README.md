# Module: Engage (전투 개시, battle opening) — top-down (quarter-view) engage (round-based turns)

## Purpose
A **turn-based engage (교전)** triggered by the `engage:N` / `duel` card effects. Unlike the
battlefield (전장, BattleSim), which runs cell by cell, an engage runs on its own **top-down
(quarter-view) stage (무대)** where participants approach / attack **one at a time, in turn,
every round (라운드)**.
**There is no player input — spectate only.**

> **The battlefield tiles decide the start positions.** The cell where the engage opened is
> placed at the centre of the stage; each participant's hex offset from that cell is converted
> to stage coordinates and the participant is placed there — two on the upper tile · two on
> the lower tile · one jungler in the left jungle looks the same on the stage. When several
> share a cell they scatter inside that cell's area, but team 0 uses the left half-circle and
> team 1 the right half-circle. **This is presentation, not resolution** — everyone still hits
> exactly once per round in rotation; the start position only changes the approach distance
> and the distance term of target selection.

> **The opening confirmation screen (VS) previews that layout.** When a card is played, what
> appears is **the stage itself**, not a roster, and pressing confirm continues straight into
> that same stage — because the question that screen asks is "do we fight in this formation?".
> See the [Opening confirmation screen](#opening-confirmation-screen-vs) section below.

> **The N in `engage:N` is a round count.** Not seconds. `engage:N` = N rounds.

> **One round = every participant acts exactly once.** Only one unit (`current_actor`) is ever
> out on the stage at a time. After the last in order, the round counter goes up and the same
> order runs **again from the caster (시전자)**.

> **No one leaves mid-engage.** Nobody can leave the stage until the rounds are over.
> Even near death (HP < 30%) a unit does not retreat.

> **No return to the original spot either.** A unit that finished attacking stays where it is,
> and that spot becomes its new anchor (`anchor_pos`). So the longer an engage runs, the more
> both teams dig into each other and bunch up on one side of the stage.

> The previous **side-view belt** (a flat belt where team 0 stood on the left · team 1 on the
> right facing each other and role decided front row / back row, with a background drawing
> sky · back wall · horizon) was replaced here. It failed for one reason — **the positions on
> screen had nothing to do with the positions on the battlefield.** Seeing two on the upper
> tile and two on the lower tile and deciding to open an engage is this game's decision, and
> the stage reflected not one letter of it. `facing_x` (direction expressed by a single
> left/right sign) · `_place_row` / `_row_x` · `FRONT_OFFSET` / `ROW_GAP` / `DEPTH_MARGIN` /
> `KNOCK_VERTICAL_SCALE` · `TURRET_BACK_OFFSET` / `TURRET_BG_Y` / `TURRET_BG_STEP` · the
> renderer's `SKY_TOP` / `BACKWALL` / `HORIZON_LINE` / `SIDE_TINT_A` / `TURRET_BG_SCALE` were
> all deleted at that time.

> The even earlier **ATB real-time model** (an invisible gauge filled by the mech `speed` stat
> decided action frequency, and `engage:N` was converted to `N × 3 seconds`) had already been
> removed — together with `RealtimeEngageSim.gd`, **the `speed` stat itself disappeared from
> the data** (mechs.csv column / `MechData.speed` / `PilotData.speed` /
> `game_config.TURRET_SPEED`). **The top-down arena before that and today's top-down view are
> different things** — the old one was a **real-time** stage on a coordinate system that
> magnified the battlefield hex cells 1:1, with kiting / turret-range avoidance / dive checks /
> opening dash on top; the current one is a **round-based turn** stage that takes only the
> start positions from the tiles. Do not revive those four or the `EngageOverlay.gd` turn loop.

## Files
| File | Purpose |
|---|---|
| `EngagePhaseManager.gd` | `class_name EngagePhaseManager extends Node` — orchestrator. Gathers participants, builds a `TurnEngageSim`, drives it in fixed steps from `_process`, and after the end check waits the `END_HOLD_SEC` grace (`ENGAGE_END_HOLD_SEC`, const.csv) before showing the dashboard. API: `start_engage(caster, rounds, exclude_lane, on_done, center, radius, drop_in)` / `start_duel(caster, target, on_done)` / **`start_objective_engage(t0, t1, rounds, title, first_team, on_done, origin)`** / `is_active()` / the `engage_finished` signal, plus for the opening confirmation screen `engage_sides(caster, exclude_lane)` / **`prepare_sim(caster, t0, t1, rounds, duel, first_team, origin, drop_in)`** / `prompt_engage(...) -> bool` / `engage_rounds_for(caster, rounds, consume)` / `is_intro_active()`. |
| `EngageIntro.gd` | `class_name EngageIntro extends Control` — **opening confirmation screen (VS)**. Right after a card is played it **shows one copy of the engage stage in preview mode** (= `EngageArena`) and puts only confirm / cancel under it. See the [Opening confirmation screen](#opening-confirmation-screen-vs) section below. |
| `TurnEngageSim.gd` | `class_name TurnEngageSim extends RefCounted` — **headless simulator**. Creates no nodes at all. Stage coordinates, **tile-based placement**, action order, round progression, a unit's single turn, turrets, damage, end check — all here. All tuning constants are also gathered at the top of this file as `static var`s whose values now live in `data/csv/const.csv` under `ENGAGE_*` keys (read via `ConstTable`). **`setup()` and `begin()` are split** — the former only places units (the preview uses only this far); everything that changes state is in the latter. |
| `EngageArena.gd` | `class_name EngageArena extends Control` — a renderer that only draws the simulator state. Owns the top-down stage inside the band (1032×1000) (floor / turrets / units / projectiles) and, below the band, the **participant portrait + HP bar strip** (allies left / enemies right in one row, **face-focused square thumbnails**). The round counter / turn indicator / end-reason banner (`mark_engage_over`) and the **result screen** (`show_dashboard`) are here too. `setup(..., preview)` puts it in **still-image mode**, where it becomes the body of the opening confirmation screen. |

The manager is attached as a child in `BattleSim._ready()` and held in `_bs.engage_phase`.
The **opening confirmation screen and the arena attach in turn** (never both at once) to a
dedicated `CanvasLayer` owned by the manager (`ENGAGE_OVERLAY_LAYER = 12`). This layer is above
the HUD canvas (1), `CardSelectOverlay` (10) and `CardTargetingOverlay` (11), so the stage and
dashboard always draw above the hand row and any remaining targeting UI. (Only the pilot detail
panel is higher, at 13.)

## Trigger flow
1. The player (or AI) plays an engage card (`engage:N` — 전투 개시 (Start Battle),
   완벽한 기회 (Perfect Opportunity)) or a duel (`duel`). `engage:N|exclude_lane` still works,
   but no card currently carries that flag.
2. `CardPhaseManager._effect_engage()` first splits the participants per team with
   `engage_sides()`, and folds right there if either side is empty. Otherwise it
   **opens the VS opening confirmation screen with `prompt_engage()` and `await`s it.**
   On cancel, `_on_overlay_cancel()` undoes the card play itself and the arena never opens.
   On confirm, `EngagePhaseManager.start_engage(...)`. (`_effect_duel()` → `start_duel(...)`
   goes through the same confirmation screen.)
3. The manager **records the phase it entered from in `_phase_before`** and switches to
   `_bs.game_phase = ENGAGE`. The BATTLE auto-tick stops, and card hover/click and end-turn
   are blocked by the `CARD_PHASE` guard.
4. The stage opens and the manager's `_process` drives the simulator in fixed steps
   (`FIXED_DT = 1/60`, at most `MAX_STEPS_PER_FRAME = 8` steps per frame).
5. End check → **`END_HOLD_SEC` (`ENGAGE_END_HOLD_SEC`) grace** → **result screen** (see
   [Result screen](#result-screen-show_dashboard) below) → `확인` (Confirm) → stage removed,
   **`phase = _phase_before`**, `on_done` called, `engage_finished` emitted.

Why the return phase is not hard-coded to `CARD_PHASE`: the opponent's turn
(`CardPhaseManager._run_ai_turn`) runs **inside BATTLE** without changing `game_phase`, so if an
engage card played by the AI returned to CARD_PHASE when it ended, the battlefield would be left
stuck in the operation phase (작전 단계) after the opponent's turn. For an engage opened by a
player card `_phase_before == CARD_PHASE` anyway, so behaviour is identical.

AI play uses the same stage. After every play, `AiCardPlayer.run_ai_plays()` `await`s
`engage_finished` if `engage_phase.is_active()` — it decides by `is_active()`, not by the card's
effect chain, so a duel whose clause is `duel` is also waited for correctly.

## Objective engage (Herald (전령) / Dragon (용))
An engage opened by `ObjectiveSystem`. The stage and lifecycle are **exactly the same** as a
card engage (round progression · end grace · result dashboard · `engage_finished`); only three
things differ.

1. **There is no caster.** It is opened by a timer, not a card, so there is no "one unit who
   acts first every round". The first-acting team is passed directly to
   `TurnEngageSim.setup(..., first_team)` (blue for objectives), and `caster = null` is accepted
   — only the "caster goes first" step of `_role_sorted` is silently skipped.
2. **Participants are not gathered around a caster.** The roster decided by position
   (`ObjectiveSystem.participants_for`) comes in as `t0` / `t1` unchanged.
3. **The stage title is the objective name** (`_arena_title`, "전령" / "용").

The end banner uses the same wording as a card engage (전멸 (wipe) / N라운드 완료 (N rounds
complete)). Win/loss and rewards are reported by `BattleSim.last_log` after the stage closes,
not by the banner — the banner stays up for `END_HOLD_SEC` right after the end check, and the
caller only regains control **after** that, so there is never a moment when win/loss could be
put on the banner.

Win/loss is decided by `ObjectiveSystem._engage_winner`, not the manager —
**number of survivors → on a tie, sum of remaining HP ratios**. Details in `objective/README.md`.

## Opening confirmation screen (VS)
`EngageIntro.gd`. Appears over a dimmed full screen **the moment a card is played**. And the
body of this screen is **the engage stage itself**, not a roster.

```
              전투 개시                ← card name (" (AI)" if the AI played it)
             라운드 1 / 3
     시작 위치 — 이대로 교전을 시작한다
  ┌──────────────────────────────┐
  │                              │
  │   교전 무대 (정지 화면)         │   ← one EngageArena in preview mode
  │   시작 위치가 이미 잡혀 있다      │
  │                              │
  └──────────────────────────────┘
     ▣▣▣▣▣  VS  ▣▣▣▣▣            ← same square-thumbnail strip as the arena
            취소   확인            ← the wording can be changed
```
(Mock-up text: "라운드 1 / 3" = Round 1 / 3; "시작 위치 — 이대로 교전을 시작한다" = Start
positions — start the engage as is; "교전 무대 (정지 화면) / 시작 위치가 이미 잡혀 있다" =
engage stage (still) / start positions already set; "취소 / 확인" = Cancel / Confirm.)

- **The stage is real.** It draws the `TurnEngageSim` built by
  `EngagePhaseManager.prepare_sim(...)` as is — it is still before `begin()`, so no damage and
  no Charge (충전) consumption happen, but **every position is already set**. On confirm `_begin`
  takes over `_pending_sim` unchanged, so **the layout seen on screen is the layout that
  actually fights**. Rebuilding it would change jitter and in-cell positions so "what was seen"
  and "what came out" would differ, and the screen would fall back from a decision to a
  confirmation formality.
- **A roster alone was not enough.** In this game the decision to open an engage is not "who is
  there" but "where and how they stand" — two on the upper tile, two on the lower tile, one
  jungler in the left jungle. The old screen (two rows of eye portraits + a big VS) answered
  only half of that.
- **Lifecycle of `_pending_sim`.** Some paths show the prompt but never open an engage
  (objective not joined · bloodless capture notice · cancel). So `prompt_engage` discards it on
  cancel, and `_begin` takes it over **only when the roster and round count match**
  (`TurnEngageSim.matches`). If they differ it silently builds a new one.
- **The round count is obtained by peeking.** The number on screen must be the real number
  after pilot (파일럿) skill modifiers ([전투 명령] (Battle Command) `SKILL_BATTLE_ORDER_ROUNDS` / [공성전] (Siege
  Warfare) `SKILL_SIEGE_ROUNDS`, const.csv), but [공성전] is a bonus that applies **to one card only**, so if it were spent
  and then cancelled there would be no way to undo it. So there is a single function
  `engage_rounds_for(caster, rounds, consume)`; the screen calls it with `consume = false` and
  `start_engage` with `true`. Previously the screen showed the count **before** modifiers and
  the engage actually ran with a different count.
- The stage appears rising from `RISE_PX` (34px) below over `FADE_SEC` (0.20 s).
  **The buttons are pressable from the start** — if the animation held input, repeated
  spectating would get slow.
- **Button wording and subtitle are arguments.** `setup(bs, sim, title, allow_cancel,
  confirm_text, cancel_text, subtitle)`. Objectives reuse this screen as is as the
  **join / skip** decision window (subtitle = reward info). The objective side passes the
  **objective cell** as the stage centre, so who is running in from which jungle · which lane
  becomes the layout directly — exactly what is needed to decide whether to join.
- **Cancel undoes the card play itself.** `_effect_engage` calls
  `CardPhaseManager._on_overlay_cancel()` to restore wholesale the snapshot taken by
  `_play_card_direct` (hand (손패) / deck / cost / engage discount / keep list) — exactly the
  same path as cancelling the discard / search overlays. Measured (실측): hand 5 → 4 → **5**,
  operation points drop by the card's `cost` and come back in full.
- **A card played by the AI shows confirm only** (`allow_cancel = false`). The player cannot
  undo it, so all that remains is "see who fights and move on".
- While the confirmation screen is up, `game_phase` is still **CARD_PHASE** (or BATTLE on an AI
  turn) — the arena has not opened. So the hand dim and the end-turn lock are not triggered by
  phase alone, and three gates read `is_intro_active()` separately:
  `CardPhaseManager._is_player_input_blocked()` / `can_end_card_phase()` /
  `can_browse_piles()`, plus the donut flip in `HudBuilder._update_cost_donuts`
  (`CostDonut._input` runs before the GUI pick and gets pressed through the dim). `prompt_engage`
  wakes those gates with `_refresh_hand_gates()` when it opens and closes the screen.
- **Do not touch the anchors.** Applying `PRESET_FULL_RECT` to a Control under a CanvasLayer
  makes the opposite anchors differ, so the size written in `_ready` is overwritten by the
  layout pass (exactly the engine warning), and since the parent gives no rect the result is
  0×0 — the dim is not drawn and `MOUSE_FILTER_STOP` does not block input behind it. Leave the
  anchors at the default (all 0) and write only `position` / `size`, and it stays.

### Why the roster moved here
Previously the PREVIEW mode of `CardTargetingOverlay` showed two vertical team panels on the
left/right of the screen **the moment a card was picked up**, listing the participants. Both
were problems:

1. **Wrong timing.** The roster appeared just by picking up a card, so half the screen was
   covered by a table before deciding whether to play it at all. The moment the roster actually
   matters is **right after** the card is played — when "who fights now" is settled.
2. **Left/right vertical panels do not say which side is which.** Two scroll lists side by side
   cannot tell by position which one is my team. Top = enemy / bottom = ally is a rule the
   battlefield screen (`ui/PilotStrip.gd`) already uses, so there is nothing new to learn.

PREVIEW mode itself remains — its role is to light up the caster cell + the 6 adjacent cells
while the card is dragged and highlight the participants inside them.

## Round rules (engage:N → N rounds)
| Card | effect | Duration |
|---|---|---|
| 전투 개시 (Start Battle) | `engage:N` | N rounds (N = its cards.csv `effect` clause) |
| 완벽한 기회 (Perfect Opportunity) | `engage:N` | N rounds (longer than 전투 개시) |
| 결투 (Duel) | `duel` | until one side is killed (cap `DUEL_MAX_ROUNDS` ← `ENGAGE_DUEL_MAX_ROUNDS`, const.csv) |

When the round budget is used up, combat stops on that very frame (no retreat animation).
The dashboard, however, appears after an `END_HOLD_SEC` (`ENGAGE_END_HOLD_SEC`) grace — see
[End](#end) below.

**Spectating time** is set by the pacing keys (see [Throughput](#throughput--measured-headless-5v5-8-3-round-engage)
below) — in one round ten units each do approach → attack → settle once.

---

## Action order — situational (team alternation + fixed role order within a team)
`_build_order` decides it **once at the opening** and it never changes afterwards. The same
order repeats every round, so spectators can predict the next turn, and "always start from the
caster" holds automatically.

1. One unit from **the caster's team first**, then one from the opposing team, **alternating**.
2. Order within a team is fixed by `ROLE_ACT_ORDER` —
   **assassin → fighter → tank → sniper → supporter**. Roles that dive open first; roles that
   hit back from behind clean up later.
3. But **the caster is pulled to the front of its own team** — the side that opened the engage
   striking first is what the battle-opening card is worth.
4. **Turrets take turns after all pilots**, starting with the caster team's turret — but the
   caster team's turret does not join (see [Turrets](#turrets--background-terrain-not-participants)
   below), so in practice only the opposing team's turret stands in that slot.

Measured order (team 0 tank casts, 5v5): `T0, A1, A0, F1, F0, T1, Sn0, Sn1, Su0, Su1`.

> Why turrets are not interleaved between pilots: a turret is background terrain, not a stage
> participant, and **the camera does not frame turrets**. Interleaving them between pilot turns
> would create silent stretches where only shots fly in from off screen.

Dead actors are skipped by `_advance_order`. The order array itself is left untouched, so as
rounds go by **the relative order of the living does not change**.

### Progress state (`Flow`)
```
ROUND_START ──(ROUND_GAP_SEC)──▶ ACTING ──▶ ACTOR_GAP ──(ACTOR_GAP_SEC)──▶ ACTING …
                                                     │
                                       (end of order) ┴──▶ ROUND_START (round +1)
                                                          or DONE (budget used up)
```
The renderer reads `flow` and `round_index` / `total_rounds` / `actor_label()` to draw the
two header lines (round counter + "whose turn") and the round pips.

---

## A single turn (`ACTING`)
```
ADVANCE ──(enters range)──▶ STRIKE ──▶ settle (that spot is the new anchor) ──▶ next in order
```

| State | What it does |
|---|---|
| `IDLE` | Not its turn. Only tidies up knockback residue (`_tick_passive`). |
| `ADVANCE` | Approaches the target. Strikes immediately once within **`MELEE_REACH` (`ENGAGE_MELEE_REACH`) for melee**, **`RANGED_APPROACH_RATIO` (`ENGAGE_RANGED_APPROACH_RATIO`) of its own max range (`ENGAGE_RANGE_RANGED`) for ranged**. If already inside, it does not move and goes straight to STRIKE. Past `ADVANCE_MAX_SEC` (`ENGAGE_ADVANCE_MAX_SEC`) it is treated as a stalemate and this turn is folded — raised together with the floor becoming twice as tall (with the old, shorter value it could not reach an enemy diagonally opposite and the whole turn became "walked and gave up") |
| `STRIKE` | One attack check on entry. Stays stopped in front of the target during the motion hold (`ENGAGE_STRIKE_HOLD_MELEE` / `ENGAGE_STRIKE_HOLD_RANGED`) |
| `DEAD` | Killed. The renderer leaves it **opaque but with brightness pressed down to 32%** (`EngageArena.DEAD_DIM`) — lowering alpha would let a unit standing behind show through the corpse, and in overlapping spots you could not read who is alive |

Move speed is `ENGAGE_MOVE_SPEED_MELEE` melee, `ENGAGE_MOVE_SPEED_RANGED` ranged (const.csv). Set faster than in the ATB days
— back then ten units moved at once, so the stage never went empty even if one
unit's approach was slow, but now **only one moves at a time, so approach time is exactly the
time the spectator waits**. Leave it slow and every round drags.

> **The range check must always carry the `STRIKE_DIST_EPSILON` (0.5px) slack.**
> The approach stop point is `target.pos − dir × strike_dist()` and `_step_toward` snaps to it,
> so a unit that finished a turn stands at **exactly** the range distance. Re-measuring from
> that spot often lands just **above** the reach due to floating-point error, so a slack-less
> `dist <= strike_dist()` is false, and the unit "moves" 0px at a time toward the stop point it
> already reached until it folds its turn only via the `ADVANCE_MAX_SEC` stalemate — the attack
> never happens.

### `_settle()` — no return to the original spot
When a turn ends, `_settle(u)` **fixes the spot it is standing on as `anchor_pos`** and returns
it to IDLE. Folding a turn due to an approach stalemate or a lost target takes the same path.
Result:

- Melee stays where it hit, so it **keeps digging into the enemy side**. Ranged also stays at
  the spot it moved into within its approach distance.
- The anchor-restore movement in `IDLE` (`SETTLE_SPEED_MULT` ← `ENGAGE_SETTLE_SPEED_MULT`) is not a move back into
  formation, and **not a move that undoes knockback either** — knockback pushes the anchor
  along with it (see [Knockback](#knockback-hit-feedback--re-approach-distance) below), so this
  drift has nothing to do while being pushed. Its only remaining role is tidying up residue
  from things like the floor clamp.
- Target distance (`_pick_target`) is also measured from the updated anchor.

### Knockback (hit feedback + re-approach distance)
On a hit, the target gets an initial velocity that decays exponentially with `KNOCK_DAMP`
(`ENGAGE_KNOCK_DAMP`) — melee `KNOCK_IMPULSE_MELEE` (`ENGAGE_KNOCK_IMPULSE_MELEE`) pushes much further
than ranged `KNOCK_IMPULSE_RANGED` (`ENGAGE_KNOCK_IMPULSE_RANGED`). **The push direction is exactly away from the attacker** — in the side-view days the
vertical component was squashed with `KNOCK_VERTICAL_SCALE` (0.35, **deleted**) to push almost
only horizontally (on the belt vertical was just perspective, with no tactical meaning), but in
top-down vertical is real distance too, and squashing it would make knockback disappear only
between two units standing one above the other. **Knockback flows every frame regardless of
state.**

> **The anchor is pushed by the same amount** (`_apply_knockback`). If the anchor stayed put,
> the restore drift in `_tick_passive` (`move_speed × SETTLE_SPEED_MULT`) is faster than the
> knockback initial velocity, so the hit unit returned to its anchor **within the very frame it
> was hit** — `_step_toward` snaps to the goal within 6px, so not even residue remained. That
> is, knockback was **not visible on screen at all**. Moving the anchor along to the pushed
> spot keeps the full push, so the attacker has to close that distance again next turn — this
> is where the melee "dig in on every hit" motion comes from. "The pushed-to spot is the new
> spot" is the same rule as `_settle()`'s "the spot where the attack finished is the new spot".
> Do not revert it.

There is no effect on damage or stats — knockback changes only position and the resulting
re-approach distance.

### Target selection (`_pick_target`)
Score = `distance / presence`, **lower is more attractive**. Near death (HP below `ENGAGE_LOW_HP_FOCUS_RATIO`) applies
the `LOW_HP_FOCUS` (`ENGAGE_LOW_HP_FOCUS`) weight, and **an enemy the same team has already targeted** gets
`FOCUS_BONUS` (`ENGAGE_FOCUS_BONUS`^n, floor `ENGAGE_FOCUS_BONUS_FLOOR`) per time targeted.

> In turn-based play only one unit is on the stage at a time, so "an enemy an ally is already
> on" is counted with **a cumulative counter (`_focus_count`)** — it is not cleared when the
> round changes. Resetting it at round boundaries scatters damage so kills almost never happen
> (in the real-time days simultaneous action played this role).

> **Assassins are the exception — they target the back row** (`dives_backline`). They ignore
> presence aggro and give ranged enemies a `DIVE_FOCUS` (`ENGAGE_DIVE_FOCUS`) weight. **Without this branch a
> ranged mech is never hit even once during the whole engage** — the front row is closer and
> even has higher presence (mechs.csv), so every melee bites only the front row. A hole confirmed
> by measurement; do not revert.

> **약자 멸시 (Contempt for the Weak, assassin R) does not take part in target selection.**
> This card is a pre-emptive strike that fires **before round 1 runs** — `_contempt_opening()`,
> which `setup()` calls after `_build_order`, burns all the Charge on the [약자 멸시] in hand
> (`MechSkillSystem.take_contempt_charges`), and for each one burned hits **the enemy with the
> least HP** (`_weakest_enemy`, absolute value, not ratio) with `CONTEMPT_DMG_MULT` (`ENGAGE_CONTEMPT_DMG_MULT`) ×
> attack. It does not roll overclock (`allow_extra = false`) — if the opening strike spawned
> extra attacks again, one card could end an engage on its own.
>
> It used to be **forced aiming**: while stacks remained, that pilot targeted only the
> lowest-HP enemy and spent one stack per turn (`u.contempt_pick`). That hung the card's whole
> value on "how many rounds is this engage" (if rounds ran short the engage ended with stacks
> left), so what was in hand did not connect to the outcome. Now it is all spent at the opening
> moment, so it is independent of the round count.

---

## What mechs add to the stage

The stage's rules are driven by `TurnEngageSim`, and **every check asks a query function of
`MechSkillSystem`** — that module's contract of not pushing stats directly holds here too.
There are five hook points.

| What | Where | Rule |
|---|---|---|
| **전탄 발사 (Full Barrage, ADC I)** | `_resolve_attack` | The target set for this one turn becomes **every enemy**. The cost (lowered attack) is already baked into Barrage's `atk` in `mechs.csv` |
| **오버클럭 (Overclock, assassin P)** | `_strike_one` | Rolled right after damage; on success hits **the same target** once more. Called again with `allow_extra = false`, so an extra attack never spawns another extra attack |
| **불굴 (Indomitable, support V)** | `_apply_damage` | Once per team member, cannot drop below 1 HP. **Turret fire goes through the same function** — hooking only pilot attacks would leave a hole where one turret shot kills |
| **약자 멸시 (Contempt for the Weak, assassin R)** | `setup` → `_contempt_opening` | Before round 1, hits the lowest-HP enemy once per Charge at `ENGAGE_CONTEMPT_DMG_MULT` × attack. See the Target selection section above |
| **Smash / stun ([강타] (Smash) card)** | `_strike_one` → `_advance_order` | An enemy hit by a loaded pilot **loses its whole next turn**. It is not removed from the order array; `_advance_order` skips it, so the relative order of the living is unchanged. `MechSkillSystem._stun_applied` blocks **the same enemy twice** — without it a single melee would keep one enemy asleep for the whole engage |

`_resolve_attack` **deciding the target set** and `_strike_one` rolling each one are split into
two layers because of Full Barrage and Overclock: the former is several targets in one turn, the
latter several hits on the same target, and one function cannot express both.

**Damage hook**: every hit of `_strike_one` goes through `MechSkillSystem.on_engage_damage`, so
영혼 수확 (Soul Harvest, warrior L) and 고통과 쾌감 (Pain and Pleasure, tank N) also trigger on
the stage.

**Per-engage state** is turned on by `on_engage_start` (right after participants are fixed, in
`_begin`) and cleared by `on_engage_end` (`_finish_engage`) — the Smash load and the Indomitable
ledger. 약자 멸시 ends with its single opening strike and leaves no state. 반응 장갑 (Reactive
Armor) is not in that pair either: its remaining layers are exactly the value carried to the next
engage, so they are cleared when leaving the battlefield.

## What must still be answerable after the engage ends (`_last_stats`)

Clauses that come **after** the `engage:N` clause ask about the engage result — [우세한 전장]
(Dominant Battlefield)'s `gen_hand:19|per_kill` ("교전에서 생존할 시 처치한 적 수만큼" — "if
you survive the engage, as many as enemies killed") and [단계 B] (Phase B)'s `phase_b`
("교전에서 적이 처치되면" — "if an enemy is killed in the engage"). So two things must hold.

1. **`CardPhaseManager._effect_engage` awaits `engage_finished`.** Without waiting, those
   clauses would settle before even the first round runs, i.e. at a point where the kill count
   is always 0.
2. **`_finish_engage` leaves a copy of `_sim.stats`.** `_on_dashboard_confirmed` clears the
   stage with `_sim = null`, and the effect chain wakes up **after that**, so
   `last_engage_kills(p)` / `survived_last_engage(p)` read the copy. It is a single-engage value
   and the next engage overwrites it.

---

## Stage — top-down floor; the battlefield tiles **decide the positions (direction only)**
The stage is **a single floor plane** seen from above, tilted slightly. Left/right does not
divide the sides — what decides positions is **the battlefield tiles**. But only the
**direction** of that cell is reflected; **physical distance is not**: a jungler who ran in from
eight cells away and a jungler two cells over stand in almost the same spot on the stage (both
"came from the left").

```
        무대 (1240 × 1180)                 전장에서 이랬다면
  ┌────────────────────────────┐        ┌──────────────┐
  │               A A          │        │      [A][A]  │   upper tile 2
  │                            │        │              │
  │     J                      │   ←    │  [J]         │   left jungle 1
  │                            │        │              │
  │               B B          │        │      [B][B]  │   lower tile 2
  └────────────────────────────┘        └──────────────┘
      Only the **direction** — up · down · left — remains. How many cells it was does not,
      and no cell outlines are drawn on the floor (they would claim a scale that does not exist).
```
(Diagram labels: "무대" = stage; "전장에서 이랬다면" = if it looked like this on the battlefield.)

| Constant | Value | Meaning |
|---|---|---|
| `STAGE_W` / `STAGE_H` | 1240 / 1180 | Floor size. Units are always confined inside it |
| `CELL_SPAN_X` / `CELL_SPAN_Y` | 360 / 280 | **The reference distance one cell occupies on the stage.** Vertical is shorter because quarter-view squashes depth |
| `CELL_CLUSTER_RX` / `_RY` | 130 / 78 | Radius by which several units on one cell scatter from the cell centre |
| `CELL_TEAM_GAP` | 60 | When two teams share one cell, pushes each team's half-circle centre toward its own side — without it the enemies at the top/bottom tips of the half-circles start touching (measured 26px) |
| `START_ENEMY_GAP` / `START_ALLY_GAP` | 190 / 105 | **Opening gaps.** Right after placement `_spread_start` pushes every pair apart to this distance (y measured stretched by `START_GAP_ASPECT` = 360/280). Applied only at the opening — applying it mid-combat would fight the approach that closes in to strike |
| `CELL_CLUSTER_CROWD` | 0.07 | Ratio added to the radius above for each unit beyond two on one cell |
| `SLOT_JITTER_X/Y` | 24 / 16 | Scatter that breaks a perfect grid |
| `CELL_REACH_MAX` / `CELL_REACH_HALF` | 1.55 / 0.9 (cells) | **Distance saturation curve.** A participant d cells away stands at `MAX × d / (d + HALF)` cells — 1 cell 0.82 · 2 cells 1.07 · 3 cells 1.19 · 5 cells 1.31 · 10 cells 1.42 · ∞ **1.55 = 558 / 434px**. Direction is kept; distance keeps only its order and converges to the cap |
| `STAGE_FIT_MARGIN` | 150 | The whole layout is shrunk so the offset bounding box fits inside this margin |
| `UNIT_RADIUS` | 40 | Portrait circle radius |
| `STAGE_MARGIN` | 130 | `stage_rect()` — widens the range the camera may show by this much beyond the floor. The portrait floats `EngageArena.UNIT_LIFT` (82) above the feet, so with an exact fit the top row's faces get cut off |

`STAGE_W` / `STAGE_H` are set at nearly the same ratio as `EngageArena.BAND_RECT` (1032×1000).
**Enlarging them lowers the camera's minimum zoom and units look small.**

### Tile → stage (`_place_from_grid`)
1. Group participants by `grid_pos`. Joining turrets' cells go into the same table too — the
   shrink factor must be decided by looking at **everything** that has to fit on screen.
2. Compute an offset per cell (`_cell_offset`). The difference in hex screen coordinates is
   divided by the cell pitch to make a **vector in cell units** — **do not write a table by
   hand.** Hex offset coordinates have different neighbour rules for odd/even columns, so a
   hand-written table silently goes wrong easily (this repo has already suffered a sign bug
   there), and `hex_to_screen` is a function that already knows the answer — keep only its
   **unit direction**, re-scale the length with the `CELL_REACH_*` saturation curve, then
   multiply by `CELL_SPAN_*` per component (vertical compression).
3. **Shift to the bounding-box centre** (`_recentre`). What belongs at the centre of the stage
   is the cluster the participants form, not the cell where the engage opened — pinning the
   opening cell as the centre leaves half the stage empty when that cell is at the edge of the
   group (cards like [돌격] (Rush) · [강습] (Assault) that move the stage toward the
   designated enemy, engages opened on an objective cell). Shifting does not change relative
   positions by a single pixel.
4. If the bounding box exceeds the stage, **shrink it as a whole** (`_fit_scale`). The only thing
   the layout states is relative position, so "two up / two down / one left" still reads even at
   a smaller scale. **Since distance compression, this shrink rarely kicks in and only mildly** — even
   two units at the offset cap (558 / 434) in exactly opposite directions span 1116 × 868 against the
   stage minus margins (940 × 880), so that extreme case shrinks by only ≈0.84. With the old method (raw distance + a 660/517
   clamp) the same objective engage spread to 1260 × 517, **scale 0.712**, i.e. faces 29% smaller
   standing at opposite screen edges (measured).
5. Seats inside a cell (`_seat_cell`) — alone, at the cell centre; several, split so **team 0
   sits on the left half-circle · team 1 on the right half-circle**. Which side is my team reads
   without leaving the cell. This differs from splitting teams left/right as a whole — the unit
   of splitting is **one cell**, not the whole stage, so the tile layout is preserved.
6. Turrets stand on their own cell as is.
7. **Spread the opening gaps** (`_spread_start`) — enemies to `START_ENEMY_GAP` 190 · allies to
   `START_ALLY_GAP` 105. Only distance grows and direction is kept, so the layout's shape survives.
   The foot-circle overlap cleanup (`_separate_units`) runs after it. Measured (minimum enemy gap
   at the opening, before → now): one cell 2v2 **26 → 190** · one cell 5v5 60 → 188 · adjacent
   cells 2v2 259 → 276 · 5v5 spread out 192 → 213.

These positions are only **the anchors at the opening** — from the moment a unit finishes its
first attack its anchor is updated to wherever it stands (`_settle`), so the layout matters only
once, at the opening.

### [강습] (Assault) — `drop_in`
Only [강습] (id 30) in `mech_cards.csv` carries `engage:N|at_target|drop_in`.
**The caster actually moves on the battlefield to the designated enemy's cell and joins that
engage** (`CardPhaseManager._effect_engage`). Previously only the stage opened around the target
and the roster was gathered within radius 1 of the target, so a caster who cast from afar **was
left out of the engage it opened** — the first-strike right of "caster team first + caster at the
front of its team" (`_build_order`) leaked into an engage without the caster. Now the roster and
stage are set up **at the moved-to spot** (only during that, `grid_pos` is set to the target cell
and then restored), and the actual move happens **after confirm is pressed** on the opening
confirmation screen (`log_move` "card-leap" · `anim_pilot_move` · `harvest_camp_under` — same
wiring as the move cards). For cancel to be as if nothing happened, the caster must stay put
while the VS screen is up. A caster under a position-lock skill (`blocks_move`) does not leap in.
**The return-to-base rule is unchanged** — landing on someone else's lane · jungle sends it back
to HQ for being out of position at the end of the operation phase (the price of diving deep).

On the stage only the caster **drops into the middle of the enemy formation (centroid of enemy
unit positions)**, and the renderer draws one more gold double ring around its floor marker.
Round resolution is the same as any other engage.

**[돌격] (id 17) is `move_in`** — the battlefield move (all the wiring above) is the same as
`drop_in`, **only the stage drop is missing**. The caster stands in its team's half-circle on the
moved-to cell just like any other participant (`drop_in` implies `move_in` — the `move_in` check
in `_effect_engage`).

### Floor-marker collision — the circle underfoot is the collider
**The floor circle drawn on screen is the collision check.** Two units' foot ellipses never
overlap (`TurnEngageSim._separate_units`) — in top-down what says "where this unit stands" is
this circle, not the portrait floating 82px up, so if circles overlap the position itself cannot
be read. So that drawing and colliding never diverge, `EngageArena`'s `GROUND_RX/RY` **read the
simulator constants directly** (`FOOT_RX` 30 / `FOOT_RY` 13).

- **The check is done in normalized circle space.** Stretching y by `FOOT_ASPECT`
  (= RX/RY ≈ 2.31) turns the two flat ellipses into two circles of radius `FOOT_RX`, so both the
  overlap and the push direction resolve as circles — the shortest distance between ellipses has
  no closed-form solution. After pushing, y is divided back to return to the original space. In
  real distance the minimum gap is **60px side by side · 26px one above the other**.
- **It does not fight the attack motion.** The minimum gap of 60px is smaller than
  `MELEE_REACH` (`ENGAGE_MELEE_REACH`), so an approach trying to hit up close is never pushed away by this check.
  It does real work in two places — **the opening layout** (a crowd on one cell · objective
  engages · the [강습] drop) and **spots shoved by knockback**.
- **It pushes the anchor too.** If the anchor stayed put, IDLE's restore drift would immediately
  undo the push and the two units would jitter, pushing and pulling at the overlap — same reason
  `_apply_knockback` moves the anchor along, and since this module has no return to the original
  spot, **the pushed-to spot is the new spot**.
- **Corpses are not pushed.** They stay where they fell and only living units are pushed out of
  them. Corpses still have their floor circle, so excluding them from the check would let living
  units stand on top of corpses.
- **Overlap is fully resolved within one frame.** With a relaxation ratio below 1, spreading the
  push over several frames draws circles overlapping on a deep single hit like knockback
  (measured: ratio 0.5 · 3 iterations gave worst-case **7.7% overlap**). The pushed unit stepping
  aside right away actually reads better as "bumped and got pushed". It is Gauss-Seidel applying
  each pair immediately, so the share that could not be pushed because of a wall
  (`_clamp_to_ground`) is taken over by the next pair, and that chain grows as long as the head
  count, so the opening layout runs 16 iterations · each frame 6.
- It runs in three places — at `setup()` **after the drop is done** (the [강습] caster above all
  lands on a spot where someone already stands), and at the **very end** of `step()` /
  `step_afterglow()` (it must come after the approach move so the spot actually drawn that frame
  is the resolved one).

Measured (headless, the "Headless verification" method below): even in the worst layout with
**all ten crammed onto one cell**, the opening minimum gap is `1.000` (= exactly touching), the
worst value over all 3 rounds is also `1.000`, and floor escapes are 0.

### What is drawn on the floor (`EngageArena`)
- **No cell outlines are drawn.** Previously a flat hexagon was laid under every cell a
  participant stood on (`_draw_cell_marks` / `_sim.cell_marks` / `cell_mark_radius`, **all three
  deleted**). Now that distance is compressed to direction only, one stage cell is not the same
  size as one battlefield cell, so those hexagons would claim a scale that does not exist and
  make units look like they stand outside their own cell. What says the layout is not random is
  now **direction**, not outlines — the jungler from the left jungle stands on the left, the two
  from the upper tile stand above.
- **Floor grid** — spacing is half the cell pitch, so a sense of distance reads.
- One unit has **three layers** — an ellipse lying on the floor (exact ground position) → a
  handle wedge pointing at that ellipse → a round portrait floating above it (`UNIT_LIFT` 82px).
  In the side-view days the wedge said "facing left/right", but in top-down what must read is not
  direction but **which floor point this face stands on** (the portrait floats, so on its own it
  cannot point at its spot). Direction is carried by `EUnit.facing` (a unit **vector**) and used
  only as the attack-motion angle — a single left/right sign (`facing_x`) cannot tell apart two
  units facing each other vertically.
- Draw order is **ascending depth (y)** — lower (nearer) units overlap on top.

---

## Turrets — **background terrain**, not participants
On the battlefield turrets (포탑) do not attack pilots, but a turret that joins an engage
**does attack**. The old rule "turrets within radius 2 appear and their range circle is a
forbidden zone" was **deleted**. There is now just one rule:

> A turret joins **only in an engage the enemy started**, and **only while a participating pilot
> stands on its own team's turret cell**.

That is, a turret comes out to defend **when the enemy forces an engage on our unit hugging it**;
it is not firepower that tags along when we open an engage from that spot ourselves. If the side
sitting on a turret cell and opening engages with cards got to fight with the turret too, that
cell would become a one-sided safe zone and the defending side would have no way to shake it.

So `TurnEngageSim._build_turrets` filters in two places.

1. **No turret of either team joins an objective engage (Herald / Dragon).** It is an engage
   without a caster (`_has_caster == false`), so there is no "who started it", and the stage opens
   on a neutral cell between the sides — a fight with no defensive structure to rely on in the
   first place.
2. **The caster team's turret is excluded** (`t.team == initiator_team`). The side that opened the
   engage is the side that forced it, so only **the challenged side's** turret can ever join.

A duel (`duel`) is also a card-opened engage and follows the same rule — if the target stands on
its own turret cell that turret joins, and the caster side's turret does not.

- A joining turret has **no range limit** — the whole stage is in range.
- A turret also fires **once per round** (after all pilots, caster team first).
  Damage is `TurretData.atk`, fire motion `TURRET_FIRE_HOLD` (`ENGAGE_TURRET_FIRE_HOLD`).
  Its old ATB (`game_config.TURRET_SPEED`) was **deleted down to the key**.
- Target is **the enemy closest to the turret** — a unit that dug deep into its side gets hit first.
- Turrets roll hit checks too. They have no hit stat, so `TURRET_HIT` (`ENGAGE_TURRET_HIT`) is used.
- On the stage **turret HP is not reduced** — turret destruction remains a battlefield rule.
- A turret kill **credits growth points (성장치) to no pilot** (`mark_pilot_dead(victim, null)`).

### Terrain structure, not a stage participant
A turret stands **on the cell it actually occupies** — it goes through the same `_cell_offset`
mapping as pilots, so the join condition ("our unit stands on that turret cell") itself means
"the turret and the ally hugging it are in the same spot", and the picture lines up on its own.
`EngageArena._draw_turrets` draws it **before** units (= behind) as a floor ellipse + hexagonal
tower body + barrel. The barrel points toward the last target it shot.

**The camera does not frame turrets** (`EngageArena._focus_positions` looks only at the feet and
faces of living units). Including turrets would lower the zoom to fit the stage edges into frame,
and the units actually fighting would look small. In exchange a turret can go out of frame — if
the fight shifts to one side the opposite turret is not visible and only its shots fly in from off
screen.

Projectile launch height is `TURRET_LIFT` (30), and `_shot_origin` uses the same value — change
the barrel height and the shot line's starting point follows automatically.

The side-view-era **"side by side on one horizon line"** (`TURRET_BACK_OFFSET` 90 →
x 225 / 1015, `TURRET_BG_Y` 48, `TURRET_BG_STEP` 160, the renderer's `TURRET_BG_SCALE` 0.58) was
deleted. That only worked because the stage had a horizon; now turrets are on the same floor
plane as pilots.

---

## Hit resolution — damage and hit formula same as the battlefield, **hit input is separate**
```
base   = engage_hit / (engage_hit + engage_eva)
명중   = randf() < PilotData.hit_chance(...)  # HIT_MIN + (HIT_MAX - HIT_MIN) × base   # 명중 = hit
피해   = attacker.atk        (absorbed by shield first, then HP)               # 피해 = damage
```
The damage formula is shared with the battlefield (`SimulationCore.roll_hit` / `_apply_damage`),
and so is the hit (명중) remap: `PilotData.hit_chance` maps the ratio linearly onto the band
`PILOT_HIT_MIN` / `PILOT_HIT_MAX` (const.csv). The engage-only `ENGAGE_HIT_MIN` / `ENGAGE_HIT_MAX`
were **deleted** — what stays engage-specific is the **input** (`engage_hit` / `engage_eva`
instead of the battlefield's `hit` / `evasion`).

The remap is monotonically increasing, so **the stat ranking order is preserved**. Changing the
band moves the battlefield and the engage together.
**Laning stats (`lane_stat_mod`) are not applied in engages** — that multiplier is only applied
inside `roll_hit`.

### Throughput — measured (headless 5v5 ×8, 3-round engage)
Stats: one real mechs.csv `hp` / `atk` row per role (tank/fighter/assassin/supporter/sniper) · hit 55 / evasion 45.

| Metric | Value |
|---|---|
| Kills per 3 rounds (both teams) | **1.0** (exactly 1 in all 8 runs) |
| Survivors | t0=5 / t1=4 in all 8 runs |
| Team cumulative damage taken: melee vs ranged | **2747 vs 468** (about 5.9:1) |

**Much milder than in the ATB days** — back then it was 40.9 attack checks / 2.75 kills in 9 s.
Each unit hits only once per round, so 3 rounds = at most 30 hits (excluding turrets), which is
why a single battle opening does not finish off an engage.

There are three knobs for engage lethality. **Only 1 and 3 are engage-only** — the hit band is
shared with the battlefield:
1. **The card's `engage:N`** — round count. The most direct knob, and it lives in the data
   (cards.csv).
2. **`PILOT_HIT_MIN` / `PILOT_HIT_MAX`** (const.csv) — the hit-chance band (formerly the
   engage-only `ENGAGE_HIT_MIN` / `ENGAGE_HIT_MAX`, deleted).
3. **`DIVE_FOCUS`** (`ENGAGE_DIVE_FOCUS`) — how much assassins leak to the back row. At 1.0 assassins also bite
   only the front row and the back row becomes invincible again.

Spectating-pace knobs are separate: `ENGAGE_MOVE_SPEED_*` / `ENGAGE_STRIKE_HOLD_*` /
`ENGAGE_ACTOR_GAP_SEC` / `ENGAGE_ROUND_GAP_SEC` (const.csv). These do not affect damage.

On the other hand **damage (one atk's worth) is shared with the battlefield rules**, so touching
it moves the battlefield too.

---

## End
- **Rounds used up**: `finished` when the round with `round_index >= total_rounds` ends.
- **One side wiped**: `finished` immediately when `active_count(team) == 0`.
- **Low HP**: nothing happens. Near-death units go out and fight just as usual.
  (The old near-death border pulse `LOW_HP_RATIO` was deleted — the HP ring on the stage portrait
  shows the remaining HP directly.)

### End grace (`END_HOLD_SEC` ← `ENGAGE_END_HOLD_SEC`)
If the dashboard showed up the moment `finished` is set, **the last kill would be swallowed by
the result window** and you get "who just died?". So the manager puts an
`EngagePhaseManager.END_HOLD_SEC` (`ENGAGE_END_HOLD_SEC`, const.csv) grace between the end check and the dashboard.

- During the grace `_process` calls **`TurnEngageSim.step_afterglow(dt)`** instead of `step()` —
  only projectile positions / `hit_flash` / `swing_t` / knockback decay flow, and no combat
  resolution (order advance, movement, attack, turrets, end check) runs at all. `round_index`
  also stops, so **the dashboard's round count is exactly the number of rounds actually fought**.
- The stage keeps running `_process`, so the camera stays alive.
- The manager promotes the top status label to the end-reason banner with
  `EngageArena.mark_engage_over(reason)` (`교전 종료 — 적군 전멸` (Engage over — enemy wiped) /
  `아군 전멸` (ally wiped) / `양측 전멸` (both wiped) / `N라운드 완료` (N rounds complete)) and
  bounces it once (scale 1.18 → 1.0) to catch the eye.
- Setting the grace to 0 goes straight back to the immediate dashboard.

### Applying to the battlefield state
- Damage is applied **directly** to `PilotData.hp` / `.shield` through `BattleSim.apply_pilot_damage` (the battlefield's single shield → HP point, which also counts match stats — `combat/README.md` "Match stats"). When the engage ends it carries
  over to the battlefield as is.
- Kill → `_bs.mark_pilot_dead(pilot, killer)`. It is the same death path as the battlefield, so
  respawn-turn scaling (`respawn_turns_now()` = `RESPAWN_TURNS` (game_config.csv) + elapsed turns / `BATTLE_RESPAWN_TURN_SCALE_DIV` (const.csv)), the death animation, and
  **growth-point settlement** all apply to stage kills too. Damage dealt is written to **the
  victim's ledger** with `_bs.record_pilot_damage`, and when that target falls it is settled as
  the last-hit bounty and damage-proportional assists (same path as the battlefield and attack
  cards) — for growth-point rules see the `SCORE_*` section of `BattleSim`. A kill is growth, so
  **a single engage is a turning point of the growth race**, which is why the result dashboard
  has a growth column (right below).
- **Kills on the stage do not show in the kill log right away.** The arena covers the screen so
  they would not be visible anyway; `ui/KillFeed.gd` checks `is_active()` and holds them, and
  `_on_dashboard_confirmed`, which closes the result dashboard, calls `flush_pending()` to release
  them one line at a time at 0.25 s intervals — what happened in that engage reads at once.
- **`grid_pos` is not touched.** Surviving pilots stay on their original cell. Low-HP pilots are
  taken back to base anyway by the HP-threshold return-to-base in
  `RecallSystem.process_phase_end_recalls()` at the end of the operation phase.

---

## Screen layout (`EngageArena`)
```
EngageArena (Control, fullscreen, MOUSE_FILTER_STOP)
├─ dim        ColorRect fullscreen (black α 0.86)   ← presses down everything outside the stage
├─ title (240) / round counter (292) / round pips (350) / turn·banner (372)
├─ _clip      Control BAND_RECT, clip_contents = true   ← clipped here
│   └─ _world DrawProxy(Node2D)  position/scale = camera
│        └─ damage popup Labels (stage coordinate system)
├─ _hud       DrawProxy(Node2D) screen coordinates — band border · round pips
├─ _roster    DrawProxy(Node2D) screen coordinates — bottom square thumbnails (+ HP bars on the result screen)
└─ two ally/enemy header Labels
```
**No name is written under portraits.** Previously the role name (`T0` / `F1`) was always
printed, but in a 90px cell that label only restated what the portrait already said
(`_name_labels` / `_refresh_names` were deleted then). That line (`STRIP_SUB_Y`) is **used on the
result screen for the growth points earned in this engage**.

### The two header lines
- **Round counter** (`_round_lbl`, y 292) — `턴 2 / 3` (Turn 2 / 3). **The on-screen term is turn
  (턴)** — code and this doc still call it round (`round_index` / `total_rounds`), but every text
  the player reads (counter · start banner · result log · card description) is "턴". Entering the
  last turn changes the colour to `TIME_LOW`. A duel has no budget, so just `턴 2`. The arena's
  default title also changed from "전투 개시" → **"교전"** (Engage).
- **Turn indicator** (`_phase_lbl`, y 372) — `T0 의 차례` (T0's turn) / `턴 2 시작` (Turn 2
  start), and after the end, the end-reason banner. `TurnEngageSim.actor_label()` builds the
  string. **In preview mode `set_hint()` uses this slot** — on a screen where nobody has moved
  yet, "whose turn is it now" is an unanswerable question.
- **Round pips** (`_draw_round_pips`, y 350) — one pip per round, filled up to the rounds played.
  Beyond `ROUND_PIP_MAX` (8) the pips get thread-thin and actually stop reading, so it switches to
  a continuous bar (a duel, capped at `ENGAGE_DUEL_MAX_ROUNDS`, can hit this). The real-time era's time-remaining bar
  (MM:SS.s) was deleted.

### Stage band
The stage is visible **only inside one rectangle**, `BAND_RECT` (24, 406, 1032×1000). Everything
outside it (battlefield · hand row · HUD) is pressed down by the fullscreen dim. The floor
(1240×1180) fits it almost exactly in both width and height.

**It is twice the height of the side-view era** (500 → 1000). On the belt, vertical was
perspective so being flat was fine, but in top-down vertical is **real distance** — the upper
tile and the lower tile must fit inside the same band for the layout to read in the same shape
as the battlefield. To make that height, the upper block (title 240 / round 292 / pips 350 /
turn 372) moved up, and the bottom strip gave up its 300-tall crop and settled into **90×90
square thumbnails**.

**Why not use `_draw()` on itself**: a Control draws its own drawing first and then its children
on top. The dim ColorRect is a child, so a stage drawn with its own `_draw` would lie **under**
the dim and darken entirely. It must be drawn on a proxy node attached after the dim for "only
outside the stage is dimmed" to hold.

**Why `DrawProxy` is a Node2D, not a Control**: a Control re-stamps `custom_rect` with its own
size on every DRAW notification. A size-0 Control is **culled as an empty rect and the drawing in
`_draw` vanishes entirely** (child Labels have their own rect and show fine, which makes it more
confusing). A Node2D takes its rect from the actual draw commands, so it is safe under the
camera transform (scale/position).

### Top-down floor
No horizon, no sky, no back wall — a screen looking down from above has no horizon line. The
floor is a single gradient brightening from top (far) → bottom (near)
(`GROUND_FAR` → `GROUND_NEAR`), and on top of it there is only a faint grid and the stage border.

- **Floor grid** — spacing is **half** the cell pitch (`CELL_SPAN_X/Y`), so a sense of distance
  reads.
- **No cell outlines.** Previously a flat hexagon was laid under every cell a participant stood
  on (`_draw_cell_marks` + `CELL_MARK_FILL/LINE`, with the radius taken from `cell_mark_radius`
  that the simulator passed with the shrink factor already applied — **all deleted**). Now that
  start positions reflect only the tile's *direction* and distance is compressed by the
  saturation curve, one stage cell is not the same size as one battlefield cell, so those hexagons
  would claim a scale that does not exist and make units look like they stand outside their own
  cell.

The floor is drawn `BG_BLEED` (260px) beyond its edges — solely so no blank shows when the camera
looks at the edge.

Units are drawn **sorted by depth (y)**. Lower (nearer) units overlap on top. The simulator's
`units` array is in per-team order, so drawing it as is breaks perspective.

One unit has **three layers**.

1. **An ellipse lying on the floor** (`GROUND_RX`/`GROUND_RY` 30×13) — exact ground position.
   Laid in order shadow → team-colour fill → team-colour border. A unit that dropped in with
   [강습] gets one more gold double ring here.
2. **Wedge** (`PIN_HALF_W` 10) — from the portrait's bottom edge to the ellipse's top edge.
3. **Round portrait (초상화)** (`PilotImages.circle_for`) — `UNIT_LIFT` (82px) above the feet.

In the side-view era a wedge beside the portrait pointed "facing left/right" and the lift was
42px. In top-down what must read is not direction but **which floor point this face stands on**
(the portrait floats, so on its own it cannot point at its spot), and the lift went up to 82px to
make room for that wedge — wedge height = `UNIT_LIFT` − `UNIT_RADIUS` − `GROUND_RY` − 5, so
lowering the lift makes the wedge disappear first.

Direction is carried by `EUnit.facing` (a unit **vector**) and used **only as the attack-motion
angle** — the melee swing arc and the ranged muzzle flash. A single left/right sign (`facing_x`,
deleted) cannot tell apart two units facing each other vertically.

Projectiles also launch/land at body height (`UNIT_LIFT`), not at the feet.

### Camera
`_update_camera()` frames the bounding box of **all living units** every frame.
**Joining turrets are not included** — see
[Turrets](#terrain-structure-not-a-stage-participant) above.

| Constant | Value | Meaning |
|---|---|---|
| `_cam_min_zoom` | computed at runtime ≈ **0.83** | The zoom at which the whole floor (1240×1180) fits the band exactly. Based on `ground_rect()` |
| `CAM_MAX_ZOOM` | 1.55 | Upper limit when units bunch up |
| `CAM_PAD_X` / `CAM_PAD_Y` | 80 / **130** | Padding outside the bounding box (stage px). `UNIT_RADIUS` is added separately. Vertical is generous because the portrait floats `UNIT_LIFT` (82) above the feet |
| `CAM_POS_RATE` / `CAM_ZOOM_RATE` | 4.0 / 2.6 | Exponential decay coefficients (1/s) |
| `CAM_ZOOM_IN_DELAY` | 0.2 | Delay (s) for **zoom-in only**. Zooming in starts only after the layout has stayed narrower (desired zoom > current target) for this long — pulling in the instant an outer unit rushes an inner enemy cuts that rush out of frame. Zoom-out is immediate (delaying it lets spreading units leave the band). While waiting, the centre keeps following — the target zoom is wider, so everyone stays in frame |

Framing targets **both the feet and the faces** of living units — with only the feet, the top
row's faces get cut off above the band (in the side-view era the lift was only 42px and the
padding covered it; now it is 82px).

`_clamp_cam_center()` confines the camera every frame to **`stage_rect()`** (the floor widened by
`STAGE_MARGIN` 130 on all sides) — **the view never shows a place where nothing is drawn.** That
lift is why the clamp reference is not `ground_rect()`; the minimum zoom is still taken from
`ground_rect()` (including the margin would make units look small). On an axis where the view is
wider than the stage, it is simply pinned to the centre. `setup()` snaps the first frame without
interpolation.

Damage popups are children of `_world`, so they follow the camera and get clipped outside the
view. In exchange they also take the world scale, so `1/zoom` is fed back to keep their on-screen
size fixed and stop the text size from swinging with zoom.

### Bottom portrait strip
Below the band all participants stand in **one row** — **allies left / enemies right**, with
"VS" in the `STRIP_MID_GAP` (68px) groove in the middle. For 5v5 it is `IIIII vs IIIII`.

```
        아군                              적군
 [I][I][I][I][I]        VS        [I][I][I][I][I]
  ▔▔ ▔▔ ▔▔ ▔▔ ▔▔                   ▔▔ ▔▔ ▔▔ ▔▔ ▔▔   ← HP bar (result screen only)
 24 ─────────── 506   540   574 ─────────── 1056
```
(Labels: "아군" = allies, "적군" = enemies.)

- **Why it moved from top/bottom to left/right**: on the stage team 0 always stands on the
  **left**. With the strip split top/bottom, "which side is my team" had to be read separately on
  the stage and on the strip. Using the same left/right makes the question disappear.
- **Portraits are face-focused square thumbnails** (`PilotImages.face_for`, 256×256) drawn at
  `STRIP_PORTRAIT_W`×`STRIP_PORTRAIT_H` (**90×90**). The cell is square too, so the ratio does not
  break. In the side-view era it was a tall full-body crop (`tall_for`, 90×300), but **when the
  band doubled (500 → 1000) there was no room left for that height.** Keeping only the face takes
  less room — the strip only has to answer two questions, "who is it · how healthy" — and the
  stage shows the body. (`tall_for` itself remains because draft · ban/pick (밴픽) still use it.)
- The width fits `STRIP_WIDTH` **exactly**: 5×90 + 4×8 = 482, 482×2 + 68 = 1032. Both teams
  **hug the middle groove** and line up outward (`_strip_cell_x(team, count, idx)`), so even with
  fewer than 5 the middle does not go empty and the "facing each other" picture remains — the old
  "split leftover cells to both sides and centre" made the two groups drift apart.
- A **backplate (뒤판)** is laid behind the portrait first. Face crops can have transparent holes,
  like mob-pilot silhouettes, and without the backplate the dimmed screen shows through.
- The border is team colour (`STRIP_RIM_IDLE` 2px). **While acting (ADVANCE/STRIKE) it turns gold
  and thicker** (`STRIP_RIM_ACT` 4px) — a device so who has the turn now also reads from below; in
  turn-based play **exactly one** unit is always gold.
- On a kill the backplate turns red and alpha drops to 35%. The name label only turns grey and does
  not append `(처치)` (killed) — the cell is only 90px, and the portrait already says it was killed.
  Name labels have `clip_text = true` (a centred Label that overflows gives up centring and invades
  the neighbouring cell).
- **The strip has no HP bars during the engage.** HP is shown by the HP ring on the stage portrait,
  drawn by **the same function** as the battlefield marker (`BattleRenderer.draw_hp_ring` — shield
  is light-grey extra HP), and taking damage pops the same in-place grow · fade chip as on the
  battlefield (`_advance_hp_chips` → `BattleRenderer.draw_hp_chip`). The stage portrait uses the
  same layers as the battlefield marker (black disc → base circle → portrait → HP ring, team colour
  `TEAM_RING_COLORS`).
- The HP bar (90×14) is drawn **only on the result screen** — the result screen clears the stage,
  so the ring is not visible there. Shield is appended on the right by the same rule as the ring
  (denominator `hp_ring_span`).
- **`faces/` textures must be primed by `PilotImages.prime_into`.**
  They are drawn with `draw_texture_rect`, so if missed all ten portrait cells come out as white
  squares (confirmed by measurement). `prime_into` bakes all three: circle / faces / tall.
- Portraits (plus HP bars on the result screen) are redrawn every frame by the `_roster` proxy. The only Label nodes are
  names · team names · VS, so only `_refresh_names()` runs.

This strip is **arena-only**. It is different from the always-on pilot strips at the top/bottom of
the screen (`ui/PilotStrip.gd`), which stay pressed under the dim and are not updated during an
engage (the strip on the stage is the authoritative display).

---

## Participant gathering (unchanged)
Caster cell + the 6 adjacent cells (radius-1 hex). The caster is always included. Living pilots of
both teams inside those 7 cells take part. The jungler / lane-pilot engage-scope distinction does
not apply here — engage explicitly crosses that boundary.

### `exclude_lane` flag (no card currently uses this flag)
The **교전 (Engage, id 4) card** that carried this flag was **removed from `cards.csv`**, so no
card in the current pool sets it. The flag itself is still parsed and handled all the way through
`CardPhaseManager` → `CardTargetingOverlay` preview → `start_engage`, so any future card can bring
it back by adding `|exclude_lane` to its `engage:N` clause.

```gdscript
# inclusion rule under exclude_lane:
p.is_guerrilla OR _bs.neutral_zone_cells.has(p.grid_pos)
```

## Result screen (`show_dashboard`)
**It is neither a panel nor a popup.** The stage (band) · band border · round pips · turn banner ·
two team-name lines are removed (`_clip.visible = false` / `_hud.visible = false`), and **only the
portrait strip that stood there throughout the engage remains in place**, turning into the report
card on the dimmed background. The dim gets darker at this point, `RES_DIM_COLOR` (α 0.945) —
during the engage the band covers the middle of the screen so the battlefield was unreadable even
at 0.86, but once the band disappears the grid and portraits rise into that space and compete with
the bars.

What one cell answers, from top to bottom:

| Slot | Content |
|---|---|
| Above the bar | **Damage dealt**. Folded to `1.2k` from four digits (`fmt_damage`) — the cell is only 62px, so digit count becomes width and one big value would make just that cell unusually wide |
| Bar | **Damage-dealt bar**. Grows upward from just above the portrait's top edge (`RES_BAR_BOTTOM`) |
| Bottom inside the bar | **Kill count** (`처치 2` — "2 kills"). **0 is not written** — a row of `0`s across ten cells only fills space with nothing to read; absence means 0 |
| Portrait · HP bar | Same as the strip during the engage |
| Under the HP bar (`STRIP_SUB_Y`) | **Growth points earned in this engage** (`+2150` — `fmt_score_gain`, not folded to k). Same look as the battlefield growth-point popup: outlined soul icon (`BattleRenderer.draw_outlined_icon`) + white text · thick black outline (`GROWTH_*` constants). From five digits, which overflow the 90px cell, only the text is shrunk to fit. If nothing was earned, a grey `—` |

**Damage taken was removed.** The question looked back on after an engage is just "who did how
much", and the HP bar right below already shows how much was taken as a picture. **Total growth
points were also removed** (the old `+2.15k → 12.40k`) — what is asked here is not the total but
this engage's share, and the total is always carried by the battlefield strip and the pilot
detail. The value at the opening is stamped into `stats[p]["score0"]` by `TurnEngageSim` while
placing participants, and the result screen computes the difference from the current value.

### The engage itself sets the bar scale
`_measure_dealt_range()` picks min · max from all participants' `dealt`, and `_bar_height()`
spreads that range over `[RES_BAR_MIN_H 28, RES_BAR_MAX_H 560]`. With an absolute scale, a small
engage leaves all ten cells as stubs and a late-game engage pins them all to the ceiling, so "who
put in more" reads in neither case. When everyone has practically the same value the baseline is
lowered to 0 (otherwise an engage where "everyone dealt a lot" would become a picture where
everyone is a stub). Zero damage leaves only a `RES_BAR_STUB_H` (6px) stub.

### Top line — win / loss / engage result
The title label (`_title_lbl`, y 240) is **swapped from the engage title to a one-line result**.
The old fixed title `교전 결과` (Engage result) and the `N라운드 진행` (N rounds played) subtitle
under it were deleted — the round count has already been seen, and the question that slot must
answer is "so did we win?".

The verdict is made by `EngagePhaseManager._result_title()` (it is the side that knows whether it
is an objective engage). The three strings (`EngageArena.RESULT_WIN` / `RESULT_LOSE` /
`RESULT_NEUTRAL`) are **owned by the arena** — deciding what colour that text gets is this
screen's job.

- **Objective engage** (Herald / Dragon): borrows `ObjectiveSystem.engage_winner()` as is
  (survivors → on a tie, sum of remaining HP ratios). That way the text shown here and the team
  that actually takes the reward can never diverge — the state does not change between the two, so
  the same answer comes out. A draw is `교전 결과`.
- **Card engage**: there is no such verdict to begin with. It is an event that is all about **how
  much advantage was gained**, not winning or losing, so forcing a win/loss would make most engages
  read as meaningless losses. So **only two shapes that can be called a win** count as a win
  (`_side_took_engage`): **opponent wiped**, or **1+ kills + all of our side alive**. If both sides
  give the same answer (both qualify · neither does — an engage where each side downed one, an
  engage that only traded damage, both wiped), win/loss is not stated and it stays `교전 결과`.

### Stats dict
A dict keyed by PilotData:
```gdscript
{ "dealt": int, "taken": int, "kills": int, "score0": float }
```
`dealt` / `taken` are the amounts actually removed (`shield_absorbed + hp_dmg`). Misses are not
counted. Damage taken from turrets is recorded in `taken` but its `dealt` is credited to no one.
**`taken` is no longer shown on screen** — the tally is kept (the log and balance measurements read
it).

## Presence stat
`presence` is used **only as a target aggro weight** (higher = targeted more often).
`mechs.csv → MechData.presence → SimulationCore._stats_for → PilotData.presence`.
Without a mech (standalone) the default is melee 4 / ranged 2. Assassins ignore this weight — see
[Target selection](#target-selection-_pick_target) above.

**There is no `speed`.** Everyone acts once per round, so there is no stat that splits action
frequency — it was deleted from mechs.csv along with its column.

## Headless verification
`TurnEngageSim` is `RefCounted`, so it can run without nodes/frames.
All you need is one BattleSim instance:
```gdscript
var sim := TurnEngageSim.new()
sim.setup(bs, caster, team0_pilots, team1_pilots, 3, false)   # 3 rounds
while not sim.finished:
    sim.step(1.0 / 60.0)
    sim.popups.clear()   # with no renderer, nobody else clears them
```
⚠ Three pitfalls:
1. A standalone BattleSim falls back to `pilots.csv`, whose `atk` is far larger than any mech's, so units die in
   one hit. To look at balance, stamp mechs.csv-level `hp` / `atk` onto PilotData
   before running. If you open an engage on the real screen, eight units fall in round 2 because of
   this fallback — it is not a bug.
2. Instantiating `BattleSim.tscn` **hangs if done inside `SceneTree._initialize`**. Make a `Node`
   scene to throw it into and attach it in `_ready` after `await process_frame`. To also see the
   render, drop `--headless`, launch in windowed mode, and capture with
   `get_viewport().get_texture().get_image().save_png(...)`.
3. If `bs.game_phase` is not set to `ENGAGE` while driving the simulator, BattleSim's BATTLE
   auto-tick runs alongside and battlefield fights mix in.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Engage (ENGAGE) | A **round-based turn-based top-down (quarter-view) engage** opened by `engage:N` / `duel` cards (spectate only, no player input). **The N in `engage:N` is a round count** — `engage:N` = N rounds; the old "N × 3 s" conversion was deleted. **One round = every participant acts exactly once**, and **only one unit** (`current_actor`) is ever on the stage — when that turn (`ADVANCE` approach → `STRIKE` attack → settle) ends it moves to the next in order, and on reaching the end of the order the round goes up and the same order runs **again from the caster**. **The action order is decided once at the opening and repeats every round (situational)**: one unit at a time from the caster's team first, **alternating teams**, with a **fixed role order** within a team (assassin → fighter → tank → sniper → supporter), except that **the caster is pulled to the front of its own team** (the side that opened the engage striking first is what the card is worth). Turrets act once each **after** all pilots, caster team's turret first — the reason they are not interleaved between units is that the camera does not frame turrets, which would create silent stretches where only shots fly in from off screen. Dead actors are skipped but the order array is unchanged, so the relative order of the living does not change. **The mech `speed` stat and `game_config.TURRET_SPEED` were deleted** — everyone acts once per round, so there is no stat that splits action frequency (a legacy of the old ATB real-time model; do not revive). **Start positions are decided by the battlefield tiles, but only direction is reflected** — see the "Engage start positions" entry below. The stage is a **floor plane** seen from above, tilted slightly (`STAGE_W`×`STAGE_H` = 1240×1180), and left/right does not divide the sides. Melee digs in to contact (`MELEE_REACH` ← `ENGAGE_MELEE_REACH`), ranged to **`ENGAGE_RANGED_APPROACH_RATIO` of max range** (`ENGAGE_RANGE_RANGED`), then strikes. Move speed is `ENGAGE_MOVE_SPEED_MELEE` / `ENGAGE_MOVE_SPEED_RANGED` and the approach cap is `ADVANCE_MAX_SEC` (`ENGAGE_ADVANCE_MAX_SEC`) — all three raised from the side-view belt, because **the floor became twice as tall** and some turns now have to walk to the diagonally opposite side (set short, that whole turn becomes "walked and gave up"). Only one moves at a time, so **approach time is exactly the time the spectator waits**. The range check carries `STRIKE_DIST_EPSILON` (0.5px) slack — a unit that finished approaching snaps to **exactly** the range distance, and if floating-point error lands that distance just above the range, a slack-less check fails forever and the unit folds its turn only via the `ADVANCE_MAX_SEC` stalemate. **No return to the original spot** — the spot where an attack finished is the new anchor (`anchor_pos`), so both teams dig into each other and bunch up on one side of the stage. On a hit the target is knocked back and **the pushed-to spot becomes the new anchor as is** — leaving the anchor behind makes the restore drift, which is faster than knockback, pull it back within the hit frame so knockback is never visible, and melee freezes at range so the attack motion also disappears. The knockback direction is **exactly away from the attacker** (`KNOCK_VERTICAL_SCALE` deleted — in top-down vertical is real distance too, and squashing it would make knockback vanish only between two units standing one above the other). It does not touch damage·stats and changes only **position and re-approach distance**. **Only assassins prioritise enemy ranged roles** (`DIVE_FOCUS`) — without this branch, higher presence (mechs.csv) means a ranged mech is never hit once during the whole engage (confirmed by measurement). The focus-fire weight (`_focus_count`) **is not cleared at round boundaries** — resetting it scatters damage so kills almost never happen (in the real-time days simultaneous action played this role). **No one leaves mid-engage** — nobody can leave the stage; the only ends are **rounds used up** or one side wiped, and units do not retreat even near death. **After the end check, the stage with combat stopped is shown for `EngagePhaseManager.END_HOLD_SEC` (`ENGAGE_END_HOLD_SEC`) more (with the end-reason banner) and then the result screen appears** — so the last kill is not swallowed by the result window. **The result is not a panel** — see the "Engage result screen" entry below. During the grace `round_index` stops, so the dashboard's round count is exactly the number of rounds actually fought. **`setup()` and `begin()` are split** — the former only sets up the stage (the opening confirmation screen uses only this far), and everything that changes state (the 약자 멸시 (Scorn the Weak) opening strike · the round loop) is in the latter. This is why cancel really is as if nothing happened. **Turrets are terrain, neither a range zone nor a stage participant**: **only in an engage the enemy started**, and **only while a participating pilot stands on its own team's turret cell**, does that turret join and hit an enemy pilot **once per round** — **the caster team's turret does not join** (filtered when `t.team == initiator_team`) and **no turret of either team joins an objective engage** (`_has_caster == false`). A turret comes out to defend when the enemy **forces** an engage on our unit hugging it; it is not firepower that tags along when we open an engage from that spot first — if the side sitting on a turret cell and opening engages with cards got the turret too, that cell would become a one-sided safe zone (**no range limit**, it does roll hit checks, turret HP is not reduced on the stage). **Its position goes through the same cell→stage mapping as pilots and sits on its own cell** — the join condition itself is "our unit stands on that turret cell", so the turret and the ally hugging it naturally stand in the same spot. The side-view-era "side by side on one horizon line" (x 225 / 1015, y 48) was deleted. The damage formula (one atk's worth, shield first) is shared with the battlefield, and so is the hit-chance formula (`PilotData.hit_chance`, band `PILOT_HIT_MIN` / `PILOT_HIT_MAX` in const.csv — the old engage-only `ENGAGE_HIT_MIN` / `ENGAGE_HIT_MAX` were deleted); only the input differs (`engage_hit` / `engage_eva` on the stage). Kills go through `mark_pilot_dead(victim, killer)`, so respawn scaling and **growth-point settlement** apply as is, and damage dealt is also credited via `score_pilot_damage`. `grid_pos` is not changed by an engage. **Screen**: the stage is visible only inside the single window `EngageArena.BAND_RECT` (24, 406, 1032×**1000**) (`clip_contents`), and outside it is dimmed with black α 0.86. It is **twice the height** of the side-view era (500), because on the belt vertical was perspective so flat was fine, but in top-down vertical is real distance, and **the upper tile and lower tile must fit in the same band** for the layout to read in the same shape as the battlefield. **No cell outlines are drawn** on the floor (only a faint grid and the stage border remain) — now that start positions reflect only the tile's *direction*, one stage cell is not the same size as one battlefield cell, and drawn hexagons would claim a scale that does not exist. One unit has **three layers**: an ellipse lying on the floor (exact ground position) → a wedge pointing at that ellipse → a round portrait floating `UNIT_LIFT` (82px) above. **That floor ellipse is the collider, so two units' foot circles never overlap** (`TurnEngageSim._separate_units` — so the drawn circle and the colliding circle never diverge, `EngageArena.GROUND_RX/RY` read the simulator's `FOOT_RX` 30 / `FOOT_RY` 13 directly). The check is done **in circle space with y stretched by `FOOT_ASPECT` (≈2.31)** — the shortest distance between ellipses has no closed-form solution. The real minimum gap is **60px side by side · 26px one above the other**, smaller than `MELEE_REACH` (`ENGAGE_MELEE_REACH`), so **it does not fight an approach trying to hit up close** — it does real work in two places: the opening layout (a crowd on one cell · objective engages · the [강습] (Assault) drop) and spots shoved by knockback. **When pushing it pushes the anchor too** (otherwise IDLE's restore drift undoes it right away and they jitter at the overlap — same reason as `_apply_knockback`), and **corpses are not pushed** (they stay where they fell and only living units are pushed out of them). Overlap is **fully resolved within one frame** — spreading the push draws circles overlapping on a single knockback hit (measured 7.7%). Measured: even with ten crammed onto one cell, the minimum gap is exactly touching (overlap 0) at the opening and throughout combat, floor escapes 0. This replaced the side-view "facing left/right" wedge; in top-down what must read is not direction but **which floor point this face stands on** (the portrait floats, so on its own it cannot point at its spot). Direction is carried by `EUnit.facing` (a unit **vector**; `facing_x` deleted) and used only as the attack-motion angle. **Below the band a participant strip runs in one row — allies left / enemies right, VS in the middle** (for 5v5, `IIIII vs IIIII`). On the stage team 0 always stands on the left, so the strip uses the same left/right. Portraits are **face-focused square thumbnails** (`PilotImages.face_for` = `faces/N_rect.png` 256×256, 90×90 on screen) — when the band doubled there was no room left for the 300-tall crop, and the strip only has to answer "who is it · how healthy", so the stage shows the body (`tall_for` is still used by draft · ban/pick). The HP bar goes below that **only on the result screen**; during the engage HP is shown by the stage portrait's HP ring (the same `BattleRenderer.draw_hp_ring` as battlefield markers, shield as light-grey extra HP) and the in-place grow · fade chip. **No name is written under portraits** — previously the role name (`T0` / `F1`) was always printed, but in a 90px cell that label only restated what the portrait already said (`_name_labels` / `_refresh_names` deleted). That line (`STRIP_SUB_Y`) is used for growth points earned on the result screen. The border of **exactly the one unit** whose turn it is turns gold and thicker, and on a kill the backplate turns red and alpha drops to 35%. `faces` textures are drawn with `draw_texture_rect`, so **they are `PilotImages.prime_into` prime targets** (missed, all ten cells become white squares). The top header is four lines: **title (240) · round counter (292) · round pips (350) · "whose turn" (372)** — the real-time era's time-remaining bar (MM:SS.s) was deleted. The camera frames **the feet and faces of living units** (turrets excluded — including them lowers the zoom and units look small) and never shows outside `stage_rect()` (floor + `STAGE_MARGIN` 130). Faces are included because the portrait floats 82px up, so framing only feet cuts off the top row's faces. Details and tuning constants in `engage/README.md`. |
| Engage result screen | **Neither a panel nor a popup.** The stage (band) · band border · round pips · turn banner · two team-name lines are removed, and **only the bottom portrait strip that stood there throughout the engage remains in place**, turning into the report card on the dimmed background (`RES_DIM_COLOR` α 0.945 — once the band disappears the battlefield rises into that space, so it is darker than the 0.86 during the engage). What one cell answers from top to bottom — **damage-dealt number** (`1.2k` from four digits) → **damage-dealt bar** (grows upward from the portrait's top edge) → **kill count at the bottom inside the bar** (`처치 2` — "2 kills"; **0 is not written** — a row of 0s across ten cells only fills space with nothing to read) → **portrait** → **remaining HP** → **growth points earned in this engage** (`+2150`, full integer · `—` if nothing was earned). **Damage taken was removed** (the HP bar right below already says how much was taken) and **total growth points were also removed** (the old `+2.15k → 12.40k` — what is asked here is not the total but this engage's share, and the total is always carried by the battlefield strip and the pilot detail). **The engage itself sets the bar scale** — min · max are taken from all participants' damage dealt and spread over `[28, 560]px` (with an absolute scale small engages are all stubs and late-game engages all hit the ceiling, so who put in more reads in neither case). **The top line is win / loss / engage result**, and the old fixed `교전 결과` (Engage result) title + `N라운드 진행` (N rounds played) subtitle were deleted — the round count has already been seen and the question that slot must answer is "so did we win?". The verdict (`EngagePhaseManager._result_title`) splits two ways: **objective engages** borrow `ObjectiveSystem.engage_winner()` as is (survivors → sum of remaining HP ratios — that way the shown text and the team taking the reward can never diverge), and **card engages** have no verdict to begin with, so **only two shapes that can be called a win** count — opponent wiped, or 1+ kills + all of our side alive. If both sides give the same answer (each side downed one, only traded damage, both wiped), win/loss is not stated and it stays `교전 결과`. |
| Engage start positions (tile-based — **direction only**) | **Stage positions are battlefield positions — but only the cell's *direction* is reflected, not physical distance.** The cell where the engage opened goes at the centre of the stage, and each participant's **relative hex offset** from it is converted into stage coordinates (`TurnEngageSim._place_from_grid` / `_cell_offset`, `CELL_SPAN_X/Y` = 300 / 235), **keeping only the unit direction and re-scaling the length with a saturation curve** (`CELL_REACH_MAX` 1.55 / `CELL_REACH_HALF` 0.9 cells → a participant d cells away stands at `1.55 × d/(d+0.9)` cells: 1 cell 0.82 · 2 cells 1.07 · 3 cells 1.19 · 5 cells 1.31 · 10 cells 1.42 · **cap 1.55 = 465 / 364px**). So two on the upper tile · two on the lower tile · one jungler in the left jungle looks the same on the stage, but whether that jungler was eight cells or two cells away looks almost the same on the stage. **Previously distance was multiplied as is and clipped at a cap** (`MAX_CELL_OFFSET_X/Y` 660 / 517, **deleted**) — participants more than three cells away all stuck to the same cap so order vanished while the stage spread to the maximum, especially in **objective (Herald / Dragon) engages** where participants gather from all over the battlefield (measured: offset bounding box 1260 × 517 → `_fit_scale` 0.712, i.e. faces 29% smaller standing at opposite screen edges. Now it is 699 × 294 and the shrink never kicks in). The point is not splitting left/right by side: two teams that met on the same cell stand mixed on one cell on the stage too, and **only within that cell** does team 0 use the left half-circle · team 1 the right half-circle (the unit of splitting is one cell, not the whole stage, so the tile layout is preserved). Each spot gets `SLOT_JITTER_X/Y` (24 / 16) scatter so it never becomes a perfect grid. Offsets are **shifted to the bounding-box centre** (`_recentre`) and then **shrunk as a whole** if they exceed the stage (`_fit_scale`) — pinning the opening cell at the centre leaves half the stage empty when that cell is at the edge of the group, and since the layout only states relative positions, shifting and shrinking lose no information. Cell→stage conversion goes through `HexGrid.hex_to_screen`, not a table — hex offset coordinates have different neighbour rules for odd/even columns, so a hand-written table silently goes wrong easily. **No cell outlines are drawn on the floor** — previously a flat hexagon was laid under every cell a participant stood on (`EngageArena._draw_cell_marks` / `TurnEngageSim.cell_marks` / `cell_mark_radius`, **all three deleted**), but now that distance is compressed, one stage cell is not the same size as one battlefield cell, so those hexagons would claim a scale that does not exist and make units look like they stand outside their own cell. What says the layout is not random is now direction, not outlines. **This layout is presentation** — the resolution where everyone hits once per round in rotation is unchanged, and the start position only changes approach distance and the distance term of target selection. **Only [강습] (Assault, mech_cards id 30) is an exception**: the `drop_in` flag of `engage:N|at_target|drop_in` **actually moves the caster on the battlefield to the designated enemy's cell** and makes it join that engage — that way the opening side's first strike (caster team · caster at the front) applies to the caster itself (previously the roster was gathered only within radius 1 of the target, so a caster who cast from afar was left out of its own engage). The move happens **after confirm is pressed** on the opening confirmation screen (cancel stays put), and landing on someone else's lane · jungle still triggers the out-of-position return-to-base at the end of the operation phase. On the stage only the caster **drops into the middle of the enemy formation (centroid of enemy unit positions)** and its floor marker gets one more gold double ring — the "[강습] (Assault)" section of `engage/README.md`. |
| Battle-opening confirmation screen (VS) | **The moment a card is played, the whole engage stage is previewed** (`engage/EngageIntro.gd`). Over a dimmed full screen it sets up one `EngageArena` in **preview mode** (title · round pips · stage · bottom square-thumbnail strip all sit exactly where they are in the real engage) and puts only **cancel / confirm** under it. **The stage is real** — it draws the `TurnEngageSim` built by `EngagePhaseManager.prepare_sim()` as is, and on confirm `_begin` takes over that stage (`_pending_sim`), so **the layout seen on screen is the layout that actually fights**. Rebuilding would change jitter and in-cell positions so "what was seen" and "what came out" would differ, and the screen would fall back from a decision to a confirmation formality. It is still before `begin()`, so no damage and no Charge consumption happen. **A roster alone was not enough** — the decision to open an engage is not "who is there" but "where and how they stand" (two on the upper tile, two on the lower tile, one jungler in the left jungle), and **the old screen** (two rows of eye portraits laid over the dim: top = enemies / middle = VS + N rounds / bottom = allies) answered only half of that. **Lifecycle of `_pending_sim`**: some paths show the prompt but never open an engage (objective not joined · bloodless capture notice · cancel), so `prompt_engage` discards it on cancel and `_begin` takes it over **only when the roster and round count match** (`TurnEngageSim.matches`). If they differ it silently builds a new one. **The round count is obtained by peeking** — the number on screen must be the real number after pilot skill modifiers ([전투 명령] (Battle Command) `SKILL_BATTLE_ORDER_ROUNDS` / [공성전] (Siege) `SKILL_SIEGE_ROUNDS`), but [공성전] is a bonus that applies to one card only, so if spent and then cancelled it cannot be undone. So there is a single function `engage_rounds_for(caster, rounds, consume)`; the screen calls it with `consume = false` and `start_engage` with `true` (previously the screen showed the count **before** modifiers and the engage actually ran with a different count). **Cancel undoes the card play itself** — `CardPhaseManager._effect_engage` restores wholesale the `_play_card_direct` snapshot (hand / deck / cost / engage discount / keep list) via `_on_overlay_cancel()`, so it is exactly the same path as cancelling discard·search (measured: hand 5→4→**5**, points drop by the card's `cost` and return in full). **A card played by the AI shows confirm only** — it is not something the player can undo. While this screen is up `game_phase` is still CARD_PHASE (BATTLE on an AI turn), so the arena has not opened, which is why hand dim · end turn · pile browse · donut flip read `EngagePhaseManager.is_intro_active()` separately instead of the phase. **The objective (Herald / Dragon) join / skip window is the same screen** — it passes the objective cell as the stage centre, so who is running in from which jungle · which lane becomes the layout directly (exactly what is needed to decide whether to join). The PREVIEW mode of `CardTargetingOverlay` itself remains (while dragging, the caster cell + 6 adjacent cells light up and participants are highlighted). |
