# features/battle_sim/skill — pilot skills

A **unique ability** attached to one player (선수). If cards (카드) are a shared resource handed out by
mechs (메크) and pilots (파일럿), a skill is the one move only that player can make.

| File | Role |
|---|---|
| `PilotSkillSystem.gd` | `class_name PilotSkillSystem` — state storage · activation · event hooks · passive queries |

`BattleSim` creates and attaches it in code **after pilot spawning and deck (덱) distribution are both done**
(`skill = PilotSkillSystem.new()`). It finds pairs via `player_data_for` and touches the deck that the
백본 (Backbone) passive has already run on, so it must be in that order. Access is `_bs.skill`.

---

## Data

The table is `data/csv/pilot_skills.csv` (**25 rows**); the pairing is held by `skill_id` in
`players.csv`. `GameManager._load_pilot_skills` reads it once at startup into
`gm.pilot_skills` (id → row), and `gm.skill_def(id)` fetches it.

| Column | Meaning |
|---|---|
| `id` | 0..24. The value `players.skill_id` points to |
| `key` | Runtime branch key (snake_case). 1:1 with `PilotSkillSystem.KEY_*` constants |
| `name` | Name shown on screen |
| `role` | `GameEnums.Role`. 탑 (top)=TANK / 미드 (mid)=FIGHTER / 정글 (jungle)=ASSASSIN / 서포터 (support)=SUPPORT / 원딜 (ADC)=SNIPER |
| `type` | `cooldown` / `charge` / `passive` |
| `p1` | Cooldown in turns, or the number of charges activation costs |
| `p2` | Max charges (0 = no charges) |
| `keyword` | Category tag (display only) |
| `description` | Description text shown as-is in the detail panel |

**Skills are bound to a lane** — they attach only to pilots of the same role, 5 per role.
With only 25, **15 of the 40 players (mobs) have no skill** (`skill_id = -1`, `is_mob = 1`).
Their portraits are silhouette (실루엣) cuts and they are also excluded from the season draft grid —
see the mob pilot (모브 파일럿) entry in `resources/README.md` and `features/season/draft/README.md`.

### Why effects were not made into a grammar
Cards are written by combining clauses like `draw:2;discard:2`, but the 25 skills all hook into different
events (turret destroyed · objective won · kill participation · attack card hit · comparison with the
opposing laner …). A clause grammar would just produce 25 clauses, so here we branch on the CSV
`key` — to change one skill, grep its `KEY_*` constant and every place that skill hooks into shows up.

---

## Three types

| Type | Ready condition | Portrait wipe | Number next to portrait |
|---|---|---|---|
| `cooldown` | `p1` turns since last use | elapsed ratio | turns left (blank when ready) |
| `charge` | charges ≥ `p1` | charges / `p1` | charge count |
| `passive` | cannot be pressed | **always 100%** | charge count (only when `p2 > 0`) |

A passive always being 100% is not an exception to the rule but its definition — it cannot be pressed but
applies constantly, so "not ready yet" does not exist. For charge-stacking passives (퍼포먼스 (Performance) ·
축적 (Accumulation) · 신예 (Rookie) · 몰아치기 (Onslaught) · 전리품 수집가 (Trophy Collector)) the charge is not fuel for activation but
**the strength of the effect** itself, and the number next to the portrait tells that value.

---

## Screen

| Where | What |
|---|---|
| `ui/PilotStrip.gd` | **Ally strips only** — the portrait is covered dark and brightens **from the left** as it gets ready. Number at top right |
| `ui/PilotDetailPanel.gd` | Dedicated block **below the card row** in the in-game tab — name · type · keyword · description · one status line · a big **사용** (Use) button |

The wipe does not lay a rectangle over the bright side; it **pushes the left edge of the dark side (dim)** —
the overlay approach still leaves one layer at 100% fill, while the shrinking approach reaches width 0 and
the portrait shows its original colours.

Not shown on enemy strips. Only allies can press skills, and dimming enemy slots too would make the
opponent's faces look faded for reasons unrelated to skills.

**Pressing the Use button closes the detail panel.** The result appears in the hand · battlefield · strip,
and if the dim covers it, it looks as if nothing happened; a skill that opens its own overlay like
계략 (Scheme) (`CardSelectOverlay`, layer 10) would sit behind this panel (layer 13) and not be visible at all.

### Activation gate
`can_activate(p)` = **ally (team 0) · alive · own operation phase (작전 단계) · not the AI turn ·
resource ready**. It costs no strategy points, and any number can be used in one operation phase —
cooldowns and charges already enforce restraint.

**The AI team only ticks passives and charges; it does not activate.** This is an intended limitation
of the first version (`AiCardPlayer` has no skill decision logic).

### Resources are spent only when the effect succeeds
`activate()` touches neither cooldown nor charges when `_run_activation` returns an empty string —
if an activation where nothing could happen (hand full, card table empty) ate the cooldown, the player
would have no way to get back what was lost.

---

## Cards that skills create

All are `pool = 0` rows in `cards.csv`, so they never enter the starter deck.
Those placed in the hand get **`exhaust|volatile`** applied on top by `_grant_volatile`.

| Skill | Card | id | Where |
|---|---|---|---|
| 배회 (Roam) | 이동 (Move) | 35 | hand (volatile) |
| 복귀 명령 (Return Order) | 복귀 (Return to Base) | 21 | hand (volatile) |
| 격전 (Fierce Battle) | 전투 개시 (Start Battle) | 1 | hand (volatile) — only when the deck has none of your own engage cards |
| 고양감 (Elation) | 아드레날린 (Adrenaline) | 18 | hand (volatile) |
| 약탈자 (Raider) | 약탈 (Plunder) | 23 | hand (volatile) |
| 신예 (Rookie) | 핫핸드 (Hot Hand) | 34 | **deck** (shuffled in) |

**Exhaust (`exhaust`) and volatile (`volatile`) are different things.** Exhaust disappears **when used**;
volatile disappears **when discarded unused** — with both attached, a skill-granted card never grows the
deck either way. The check passes through one place, `CardPhaseManager.send_to_discard`
(see `card_phase/README.md`).

Only 신예's [핫핸드] goes to the deck because one card slotted into the hand every `p2` turns would keep
triggering hand-limit cleanup.

---

## Event hooks — where they are called

| Hook | Called from | Skills that use it |
|---|---|---|
| `on_turn_advanced()` | after step 8 of `SimulationCore.simulate_turn` | 축적 · 신예 (charge), 사냥의 보상 (Hunter's Reward) · 위치 고정 (Hold Position) (expiry) |
| `on_card_played(cd, is_player)` | `CardPhaseManager._dispose_used_card` | 퍼포먼스 |
| `on_attack_hit(caster)` | `CardPhaseManager._apply_attack_damage` | 몰아치기 |
| `on_kill(victim, killer)` | `BattleSim.mark_pilot_dead` | 사냥의 보상 · 약탈자 · 전리품 수집가 · 퍼포먼스 · 신예 · 기회주의자 (Opportunist) |
| `on_turret_destroyed(killer)` | `BattleSim.score_turret_kill` | 공성전 (Siege) |
| `on_dragon_spawned()` | `ObjectiveSystem._resolve_objective` | 용의 가호 (Dragon's Blessing) |
| `on_objective_won(team)` | `ObjectiveSystem._run_objective_engage` | 고양감 |
| `on_engage_started()` | `EngagePhaseManager._begin` | 기회주의자 (ledger reset) |
| `on_phase_end(is_player)` | `end_card_phase` / `_run_ai_turn` | 몰아치기 (charge reset) · 전투 명령 (Battle Command) (stage effect cleared) |

**`on_kill` must be called before `_payout_kill_bounty`** — that payout clears `victim.damage_credit`,
the source of the kill-participation list. The kill log sits in the same spot for the same reason. The list does not
scan that dictionary directly but goes through **`BattleSim.live_damage_credit`** —
damage older than `SCORE_ASSIST_WINDOW_TURNS` (const.csv) is not participation, and that expiry rule must be
read by **one shared function** for bounty distribution · kill log · this hook so all three point at
the same faces.

**`on_objective_won` is called only when won through an engage.** Taking it free because nobody showed up
(`_award_uncontested`) is not "전투에서 승리" (won in battle) as the CSV text says.

---

## Passive queries — the original site does the calculation

This module answers only **how much to add**; the multiplication happens at the original calculation point.
This is because if a skill pushed stats directly, a single growth recalculation would wipe it — the same reason a card's
temporary attack lives separately as `PilotData.atk_buff`.

| Query | Read by | Skills that use it |
|---|---|---|
| `growth_rate_add(p)` | `BattleSim.add_score` | 축적 · 사냥의 보상 · 위치 고정 · 경쟁 심리 (Rivalry) |
| `atk_mult(p)` / `hp_mult(p)` | `BattleSim.refresh_growth_stats` | 퍼포먼스 · 전리품 수집가 · 만능 (All-Rounder) · 경쟁 심리 |
| `hit_mult(p)` / `evasion_mult(p)` | `SimulationCore.roll_hit` | 노련함 (Veteran) · 몰아치기 · 퍼포먼스 |
| `lane_stat_add(p)` | `SimulationCore.lane_adjusted` | 백본 · 위치 고정 |
| `damage_out_mult` / `damage_in_mult` | `SimulationCore._pilot_hit_damage`, `CardPhaseManager._apply_attack_damage`, `TurnEngageSim._resolve_attack` | 불안정한 대포 (Unstable Cannon) |
| `presence_delta(p)` | engage target weighting | 만능 |
| `blocks_move(p)` / `blocks_objective(p)` | `_effect_move`, `ObjectiveSystem.participants_for` | 위치 고정 |
| `engage_round_delta(team, consume)` | `EngagePhaseManager.start_engage` | 전투 명령 (stage) · 공성전 (next one card) |
| `engage_bonus_rounds_from_kills()` | `TurnEngageSim._advance_order` | 기회주의자 |
| `engage_focus_role(p)` / `engage_focus_atk_mult(p)` | `TurnEngageSim._pick_target` / `_resolve_attack` | 원딜 사냥꾼 (ADC Hunter) |

**Skills whose charges change stats call `refresh_growth_stats` when the charge goes up** —
otherwise the on-screen numbers stay at the old values until the next score change.

---

## List of 25

Cooldown / charge numbers are the CSV `p1` / `p2` and are not restated below. Effect sizes are const.csv keys
(`SKILL_*`, exposed on `PilotSkillSystem` as `static var` without the `SKILL_` prefix); "late game" means
from turn `SKILL_LATE_GAME_TURN`.

### Top (탑, TANK)
| Name | Type | Summary |
|---|---|---|
| 공성전 (Siege) | charge | Starts with full charges. +1 on turret destroyed. `p1` charges → next Start Battle card's rounds + `SKILL_SIEGE_ROUNDS` |
| 만능 (All-Rounder) | passive | HP-type mech: presence +1 · max HP + `SKILL_VERSATILE_MULT`; attack-type: presence −1 · attack + `SKILL_VERSATILE_MULT` |
| 원딜 사냥꾼 (ADC Hunter) | passive | The **first attack** of an engage always targets the enemy ADC, with attack + `SKILL_ADC_HUNTER_ATK` on that hit |
| 공격적인 전진 (Aggressive Advance) | cooldown | Creates a volatile [전진] (Advance) |
| 경쟁 심리 (Rivalry) | passive | Vs. the opponent's same-lane pilot: behind in growth points → accrual + `SKILL_RIVALRY_GROWTH` / behind in kills → attack + `SKILL_RIVALRY_ATK` / ahead in deaths → max HP + `SKILL_RIVALRY_HP` |

### Mid (미드, FIGHTER)
| Name | Type | Summary |
|---|---|---|
| 배회 (Roam) | cooldown | The cheapest move card in hand costs 0. If there is no move card or it already costs 0, creates a volatile [이동] (Move) |
| 위치 고정 (Hold Position) | cooldown | For `SKILL_HOLD_TURNS`: accrual + `SKILL_HOLD_GROWTH_RATE` · laning + `SKILL_HOLD_LANE_STAT` (negative) · move cards disabled · no objective participation |
| 퍼포먼스 (Performance) | passive (charges) | +1 charge per card this player uses. `SKILL_PERFORMANCE_PER_CHARGE` to all of own stats per charge. Loses `SKILL_PERFORMANCE_DEATH_LOSS` charges on death |
| 기회주의자 (Opportunist) | passive | If it got a kill during an engage, that engage gets + `SKILL_OPPORTUNIST_ROUNDS` round(s) (once per engage) |
| 축적 (Accumulation) | passive (charges) | +1 charge each turn. `SKILL_ACCUMULATE_PER_CHARGE` growth accrual per charge |

### Jungle (정글, ASSASSIN)
| Name | Type | Summary |
|---|---|---|
| 고양감 (Elation) | charge | +1 on objective **engage win**. `p1` charge(s) → creates a volatile [아드레날린] (Adrenaline) |
| 격전 (Fierce Battle) | cooldown | Draws your own Start Battle card from the deck. If none, creates a volatile [전투 개시] (Start Battle) |
| 전투 명령 (Battle Command) | cooldown | This operation phase: Start Battle cost − `SKILL_BATTLE_ORDER_DISCOUNT`, battle rounds + `SKILL_BATTLE_ORDER_ROUNDS` (negative) |
| 약탈자 (Raider) | charge | +1 on kill participation. `p1` charge(s) → creates a volatile [약탈] (Plunder) |
| 전리품 수집가 (Trophy Collector) | passive (charges) | Attack + `SKILL_LOOT_ATK_PER_CHARGE` per enemy **role type** whose kill it participated in. All 5 types gives an extra `SKILL_LOOT_ATK_FULL_BONUS` |

### Support (서포터, SUPPORT)
| Name | Type | Summary |
|---|---|---|
| 작전 준비 (Operation Prep) | cooldown | All card costs −1 this operation phase |
| 계략 (Scheme) | cooldown | Grants keep (보존) to 1 card in hand (chosen with the same grid as search (찾기)) |
| 복귀 명령 (Return Order) | cooldown | Creates a volatile [복귀] (Return to Base) |
| 노련함 (Veteran) | passive | Hit + `SKILL_VETERAN_HIT_EARLY` · evasion + `SKILL_VETERAN_EVASION` (negative). Late game: hit + `SKILL_VETERAN_HIT_LATE` |
| 용의 가호 (Dragon's Blessing) | charge | +1 when the Dragon (용) **spawns**. `p1` charge(s) → strategy points + `SKILL_BLESSING_STRATEGY`, draw `SKILL_BLESSING_DRAW` |

### ADC (원딜, SNIPER)
| Name | Type | Summary |
|---|---|---|
| 사냥의 보상 (Hunter's Reward) | passive | On kill participation, growth accrual + `SKILL_HUNT_REWARD_RATE` for `SKILL_HUNT_REWARD_TURNS` |
| 불안정한 대포 (Unstable Cannon) | passive | Damage dealt and damage taken both + `SKILL_CANNON_EARLY`. Late game: + `SKILL_CANNON_LATE` each |
| 백본 (Backbone) | passive | At game start sends all of own cards to the discard pile. Late game: laning + `SKILL_BACKBONE_LANE_STAT` |
| 신예 (Rookie) | passive (charges) | +1 charge each turn. When full, creates [핫핸드] (Hot Hand) in the deck and resets charges. Resets on death |
| 몰아치기 (Onslaught) | passive (charges) | +1 charge per attack card hit. Hit + `SKILL_SURGE_HIT_PER_CHARGE` per charge. Resets at the end of the operation phase |

---

## Tuning

The CSV `p1` / `p2` only set **cooldown turns · charge cost · max charges**. Effect sizes (how many %,
how many rounds / turns) now live in `data/csv/const.csv` under `SKILL_*` keys, read through `ConstTable`
into the "튜닝 상수" (tuning constants) section of `PilotSkillSystem` as `static var`s keeping the old
const names (e.g. `PilotSkillSystem.HOLD_TURNS` ← `SKILL_HOLD_TURNS`). They were kept out of
`pilot_skills.csv` because that would create five or six number columns whose meaning differs per skill.
Values themselves are not restated here — read const.csv.

Two values were changed when porting from the original design sheet.
* **퍼포먼스 (Performance)** — read literally, the sheet's per-charge bonus to "all pilot stats" was far
  too large at max charges (`p2`). Lowered (`SKILL_PERFORMANCE_PER_CHARGE`), **self only**.
* **만능 (All-Rounder)** — "when max HP is higher than attack" does not split on raw values (mech HP
  values are far larger than attack values in mechs.csv, so HP is always larger whatever mech is used). It is decided by **mech id
  ranges**: assassin 12–17 · sniper 24–29 = attack-type, the rest = HP-type
  (`MECH_ATK_ARCHETYPE_RANGES`). In a standalone run without mechs it splits by presence.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Pilot skills | **A unique ability attached to one player.** If cards are a shared resource handed out by mechs and pilots, a skill is the one move only that player can make. The table is `data/csv/pilot_skills.csv` (**25 rows**) and the pairing is held by `skill_id` in `players.csv`. **Skills are bound to a lane**, attaching only to pilots of the same role, 5 per role (탑=TANK / 미드=FIGHTER / 정글=ASSASSIN / 서포터=SUPPORT / 원딜=SNIPER). With only 25, **15 of the 40 players (mobs) have no skill** — see the "Mob pilots" entry. There are three types — **cooldown** (reusable `p1` turns after use) · **charge** (charges stack on set events and `p1` charges are burned to activate) · **passive** (cannot be pressed; always on or auto-triggered). For charge-stacking passives (퍼포먼스 · 축적 · 신예 · 몰아치기 · 전리품 수집가) the charge is not fuel for activation but **the strength of the effect** itself. **Effects branch on `key`, not a grammar** — all 25 hook into different events (turret destroyed · objective won · kill participation · attack card hit · comparison with the opposing laner), so a clause grammar would just produce 25 clauses. **This module exports passive modifiers only as query functions, and the calculation stays where it always was** (`BattleSim.refresh_growth_stats` / `add_score`, `SimulationCore.roll_hit` / `lane_adjusted` / `_pilot_hit_damage`, `TurnEngageSim`) — if a skill pushed stats directly, one growth recalculation would wipe it (same reason a card's temporary attack lives separately as `atk_buff`). **Screen**: the portrait in ally strips is covered dark by default and **brightens from the left as it gets ready** (by pushing the dim's left edge — the overlay approach leaves one layer even at 100%), with **turns left for cooldown / charge count for charge** at top right. Passives are **always 100% bright** (they cannot be pressed but always apply, so "not ready yet" does not exist). Not shown on enemy strips. **Below the card row of the detail panel's in-game tab** stand name · type · keyword · description · status · a big **사용** (Use) button, and **pressing it closes the panel** (the result appears in hand·battlefield·strip and if the dim covers it, it looks like nothing happened; a skill that opens its own overlay like 계략 is layer 10 and sits behind this panel at 13). **Activation is free and any number can be used per phase** — cooldowns and charges already enforce restraint. The gate is three conditions: ally · alive · own operation phase; **the AI team only ticks passives and charges and does not activate** (intended limitation of the first version). Resources are spent **only when the effect succeeds** — if an activation where nothing could happen because the hand was full ate the cooldown, there would be no way to undo it. Cards that skills create in hand (이동 · 복귀 · 전투 개시 · 아드레날린 · 약탈) are all `pool = 0` with **`exhaust\|volatile`**, so they never grow the deck either way. The list of 25 is in `skill/README.md`; tuning constants are `SKILL_*` in const.csv. |
