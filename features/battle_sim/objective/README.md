# Module: Objective (Herald (전령) / Dragon (용)) — objectives on the left/right neutral cells

표시 텍스트는 l10n key (`battle.objective.*`) — `kind_name` / `reward_text` return translated text (reward lines keep `[card]` references). `last_log` / `_bs.blog` lines are diagnostics (`# l10n-ignore`).

## Purpose
An **engage event that opens at fixed turns** on the left/right neutral cells of the battlefield (전장).
A jungle camp (정글 캠프) is income you "eat by stepping on it in passing"; an objective (오브젝트) is
an event where **both teams choose, at the same moment, whether to fight over the same spot or not**.

> **Left = Herald, right = Dragon.** The positions are fixed and never change.

> **It fires regardless of whose turn (차례) it is.** Outside the operation phase (작전 단계, cards) flow,
> when the spawn turn comes, the decision window opens on the spot.

> **It can be avoided.** Two options: join / don't join. If only one side joins, that side
> takes it without a fight.

## Files
| File | Purpose |
|---|---|
| `ObjectiveSystem.gd` | `class_name ObjectiveSystem extends Node` — clock · participants · decisions · resolution, all of it. The decision window and the engage stage borrow the engage module's VS screen (`engage/EngageIntro.gd`) and stage (`engage/EngageArena.gd`) as-is. |
| `ObjectiveRewardFx.gd` | `class_name ObjectiveRewardFx extends Node` — **reward acquisition FX**. Fans the reward cards out in the middle of the screen, then flies them to where they go. See the *Reward acquisition FX* section below. |

`BattleSim._ready()` attaches both as children and holds them as `_bs.objective` / `_bs.objective_fx`.
This must happen **after the config values are read** (`_populate_from_data_loader()`) — the first
spawn turn comes from `game_config`.

## There is only one entry point
`CardPhaseManager.do_battle_turn()` calls `await _bs.objective.process_turn()` **right after**
`simulate_turn()`, and **before** the card economy (strategy-point regen / auto draw) and the
operation phase check.

This ordering is the implementation of "fires regardless of whose turn it is". If it came later,
then on a turn where the Herald opens and the operation points happen to cross the threshold, the
objective would slip by one turn.

## Clock
| Knob (`game_config.csv`) | Meaning |
|---|---|
| `OBJ_HERALD_FIRST_TURN` | Turn the Herald first opens |
| `OBJ_DRAGON_FIRST_TURN` | Turn the Dragon first opens (earlier than the Herald) |
| `OBJ_RESPAWN_TURNS` | Until it reopens **after being decided** |
| `OBJ_RETRY_TURNS` | Until retry when it **fizzled because neither team joined** (shorter than `OBJ_RESPAWN_TURNS`) |
| `OBJ_ENGAGE_ROUNDS` | Number of objective engage rounds (a card engage takes its round count from its `engage:N` clause) |
| `OBJ_DRAGON_CARD_COUNT` | Number of Dragon reward cards (shuffled into the deck) |

The per-card Dragon growth bonus is **not** a config knob — it is the [용 보상] (Dragon Reward) card's
`growth_perm` clause in `cards.csv` (the former `OBJ_DRAGON_GROWTH_PCT` key was deleted). Likewise the Herald
turret damage is only the [전령 제압] card's `turret_damage` clause — `OBJ_HERALD_TURRET_DMG` was deleted, and
`ObjectiveSystem.reward_text` reads the clause from the card row so the reward line cannot drift from the effect.

**The Dragon opens first, the Herald later.** It used to be Herald
first with only a short gap, so the first Herald and the first Dragon effectively overlapped in the
same window — the jungler and center (both participants on either side) got dragged left and right,
and neither became a "gather and fight" event. The order was flipped to Dragon-first because of the
nature of the rewards: the Dragon's growth accrual bonus ([용 보상]'s `growth_perm` clause) is a gain that runs for the rest of the match,
so **its value grows the earlier you take it**, while the Herald's turret damage (its card's `turret_damage` clause) is worth the same
whenever you take it.

Both first spawns being pushed back and the respawn intervals growing are for the same reason — an objective should not be an event that cuts into the
laning phase, but one that opens after the lanes have settled once.

**The spot is not consumed.** Whether a team takes it or the engage ends in a draw, it reopens on the
same cell after `OBJ_RESPAWN_TURNS`. Only a fizzle (neither team joined) uses the shorter
`OBJ_RETRY_TURNS` — nothing happened, so there's no reason to keep the resource dormant that long.

The remaining turn count is **always shown in the top panel** — two slots of `ui/ObjectiveTimer.gd`
on either side of the enemy pilot strip (스트립) (left Herald / right Dragon, icon + remaining turns. Each slot is
101×60 and there is no "턴" (turn) text — the number next to the icon can't be anything other than the
remaining turns). If you can't see when it opens, you can't judge whether to push a lane ahead of time
or attach the jungler to that side.

**Tapping the clock shows that objective's reward card as a real card**
(`ui/ObjectiveRewardPopup.gd`). An objective is an event where you choose join / don't join, yet what
it gives could not be seen anywhere for the whole match except one line (`reward_text`) in the decision
window on the turn it was about to be decided — whether to push a lane or attach the jungler depends on
knowing the reward's worth. This popup is **pure information, so it does not hold the battlefield**
(`_battle_tick_held` doesn't read it) — that's how it differs from the join decision window.
At one time the name and turn count were printed **on the battlefield tile**, but when that cell went
back to being an ordinary jungle cell (the camp outline · capture fill colour · portraits (초상화) already use
that cell), the two lines of text became a fourth guest. The left / right layout matches the map's left
/ right, so the position is the name.

## Participants — decided by position
| Objective | Positions | Headcount |
|---|---|---|
| Herald (left) | LEFT · CENTER · GUERRILLA | **3** |
| Dragon (right) | RIGHT · CENTER · GUERRILLA | **4** |

The right side has one more because **two** pilots stand in the RIGHT lane, the supporter and the
sniper — which is why the Dragon is a bigger event than the Herald.

**Dead pilots cannot join.** They are dropped from the list entirely, so that team must fight or
back off at a numbers disadvantage — this is why a kill (처치) just before an objective decides the objective.

A single `participants_for(kind, team)` decides both the roster in the decision window and the roster
that actually goes on stage.

## Decision
Made **simultaneously, without knowing each other's choice**. The AI has already decided before the
window opens but does not show it to the player — if it did, it would become "the enemy backed off,
so I'll just take it", a confirmation step instead of a decision.

### Player
Uses the VS screen of `engage/EngageIntro.gd` as-is, with only the button text changed to
**참여 / 미참여** (Join / Don't join) (`prompt_engage(..., confirm_text, cancel_text, subtitle)`). The
shape of the decision is the same as a card engage — look at the roster, pick one of two options — so
there's no reason to build a new screen; on the contrary, it has to be the same screen for "fight with
this roster" to read as the same picture. One line under the round count states the reward.

If no pilot can participate, the window is not shown and it automatically counts as not joining.

### AI — headcount + misjudgement
```
머릿수(team) = 참가자 중 살아 있고 체력 ≥ OBJ_AI_HEADCOUNT_HP_RATIO 인 인원   # headcount(team) = participants alive with HP ≥ OBJ_AI_HEADCOUNT_HP_RATIO (const.csv)
참여         = 내 머릿수 ≥ 상대 머릿수                   # join = my headcount ≥ opponent headcount
             또는 (열세일 때) randf() < 오판 확률         # or (when outnumbered) randf() < misjudge chance
```
**It does not look at strength differences (HP · attack · growth points (성장치))** — it backs off only when
outnumbered. A pilot below `OBJ_AI_HEADCOUNT_HP_RATIO` HP (체력) goes down in one or two hits even on stage, so both teams exclude
them from the headcount. Equal headcount → fight.

**The misjudge chance is set by the opponent team's league rank** — 1st `OBJ_MISJUDGE_MIN` → last `OBJ_MISJUDGE_MAX` (const.csv), linear
(`MatchFlow._misjudge_chance_for` passes it as `match_ctx.enemy_misjudge_chance`). On equal win/loss,
the team with higher average stats ranks higher, so strong teams misjudge less even at season start
(everyone 0-0). International tournament (국제대회) outside teams (id ≥ 100) are top teams of their own
leagues, so they get the minimum `OBJ_MISJUDGE_MIN`; a standalone run outside a season uses the midpoint
`OBJ_AI_MISJUDGE_DEFAULT` (const.csv). Misjudgement is the weakness of low-ranked teams getting dragged into bad
fights, and the player's chance to punish it after building a numbers advantage.

It used to compute a win rate from the sum of `(hp + shield) × atk` and back off below
`AI_JOIN_WINRATE` (0.45) (**deleted**) — the growth gap was the decision itself, so every AI used the
same scale regardless of rank.

If the opponent can't field anyone, it always joins (free reward).

## Resolution
| Decision | Result |
|---|---|
| Both teams join | **Engage stage** (`EngagePhaseManager.start_objective_engage`) → winner gets the reward |
| Only one team joins | That team gets the reward without a fight. A result window is shown once |
| Neither team joins | Fizzle. Retry after `OBJ_RETRY_TURNS` |

### Engage win/loss
**Survivor count → on a tie, sum of remaining HP ratios.** If both are equal it's a draw and nobody
takes it (the spot reopens after `OBJ_RESPAWN_TURNS`).

The ratio sum is used because total HP differs greatly by role — adding a tank's and a sniper's HP
as absolute values means "the side with the tank alive" always wins.

### How an objective engage differs from a card engage
1. **There is no caster (시전자).** It's an engage opened by a timer, not a card, so there's no "one person
   who acts first every round". The first-acting team is blue (`BattleSim.blue_team`)
   (`TurnEngageSim.setup(..., first_team)`).
2. **Participants are not gathered around a caster.** The roster set by position comes in as-is.
3. **The stage title is the objective name** ("전령" / "용").
4. **No turret (포탑) joins at all.** In a card engage, a participant standing on the engaged side's turret
   cell drags that turret in (turret section of `engage/README.md`), but an objective engage has no
   caster, so there is no "who engaged", and the stage opens on the left/right neutral cells — it's a
   fight with no defensive structure to draw in in the first place. `TurnEngageSim._build_turrets`
   returns immediately when `_has_caster == false`.

The rest of the lifecycle (round progression · end grace · result dashboard · `engage_finished`) is
exactly the same as a card engage.

The end banner uses the same text as a card engage (전멸 (Wiped out) / N라운드 완료 (N rounds complete)). Win/loss and
the reward are told by `last_log` after the stage closes — the banner stays up for `END_HOLD_SEC`
right after the end check, and the caller regains control only **after** that, so there's never a
moment where the win/loss could be put on the banner.

## Rewards
The difference between the two is the character of the two objectives — the Herald is a one-shot to
use right now, the Dragon is a growth gain that runs slowly for the whole match.

### Herald → 1 [전령 제압] (Herald Subdued) **straight into the hand (손패)**
```
id 32 · <cost> · exhaust|preserve · location / cast_range <N> · turret_damage:N
```
- Can be used **only on the outermost enemy turret** — per lane, scan T1 → T2 and take the first living
  turret (`SimulationCore.outermost_enemy_turrets`). In a lane whose T1 has fallen, T2 inherits that
  slot, so a Herald taken late still has somewhere to be used. Sniping inner turrets is still not allowed.
- The card's `turret_damage` amount (cards.csv — the only source) with no
  hit check, measured against `TURRET_HP`. If destroyed, jungle gain · kill log ·
  `Building` node release all run by the normal battlefield rules
  (`SimulationCore.apply_card_turret_damage` reuses `_apply_card_damage`).
- **Uncontested = double.** That's when there are no enemy pilots at all on that lane's
  **front line (전선)** (`SimulationCore.front_line_cells` — between both teams' foremost turrets, i.e. from the
  targeted enemy turret cell to our foremost turret cell. Same set as the gold outline on screen). The
  Herald is an event of pushing into a lane, so if a lane with nobody blocking and a lane held by five
  were worth the same, the question "when and where to use it" would vanish entirely. Junglers count
  too — if one is standing in the lane corridor, that person is the one blocking the lane.
- **Growth points are split evenly among the allies in that lane.** Per 1 HP chipped off,
  `SCORE_TURRET_FULL / TURRET_HP` is divided by the number of living allied laners in that lane
  (the right lane has two, sniper · supporter, so half each). Herald Subdued **has no caster**
  (`owner_pilot == null`), so the usual attribution path reaches nobody — the people who held that lane
  while pushing it own the siege. If there's nobody (that lane wiped out), it just disappears — it is
  not given to an unrelated person just to preserve the total.
  Implementation: `CardPhaseManager._effect_turret_damage` / `_award_turret_damage_to_lane`.
- With the `보존` (Keep) keyword it is immune to any discard — you can choose when to use it.

### Dragon → `OBJ_DRAGON_CARD_COUNT` [용 보상] (Dragon Reward) **shuffled into the deck**
```
id 33 · <cost> · exhaust · target ally / cast_range <N> · draw:N;growth_perm:N
```
- Why not stack them on top: if several arrive in hand at once, the next few draws become entirely
  reward cards and the deck locks up. Shuffled in, they come out one at a time over the late game.
- Draw (`draw:N`) + **permanent bonus (its `growth_perm` clause) to the growth accrual multiplier of the targeted allied (아군) pilot**
  (`PilotData.growth_rate_bonus`). No expiry, no removal, and it **stacks**.
- **The total from one Dragon was cut** — both fewer cards (`OBJ_DRAGON_CARD_COUNT`) and a smaller
  bonus per card (the `growth_perm` clause). The Dragon opens several times, so the old value
  dominated the whole late-game growth curve.

### Reward cards have no caster (`owner_pilot == null`)
An objective is taken by the team, not by someone, and attaching a caster would lock the whole reward
while that pilot is down (card lock checks caster survival).

Instead, **the range anchor disappears**, so target computation reads `caster == null` as "the whole
battlefield is in range" — `CardPhaseManager.compute_valid_pilot_targets` /
`compute_valid_location_targets`, `CardTargetingOverlay.start_card_selection`.
Only engage (PREVIEW) is an exception and requires a caster (it gathers participants around the caster's cell).

Both cards have `pool = 0`, so they never enter the random starter deck and only come into the world
via `grant_cards_to_hand` / `grant_cards_to_deck`.

## Reward acquisition FX (`ObjectiveRewardFx.gd`)
The reward goes in with a single `_grant_reward` line. Its result was only the hand growing by one
(Herald) or the deck count going up (Dragon), so as payback for fighting up to a 4-player
engage over an objective, **nothing happened on screen**. The Dragon in particular is shuffled into the
deck, so nothing lands in your hand at that moment — what you got must be shown once as a real card.

**FX comes before granting.** `_grant_reward` is a coroutine and calls `grant_cards_to_hand` /
`grant_cards_to_deck` **after** `await`ing `objective_fx.play()`. If the order were flipped, the same
card would already be standing in the hand while the FX plays, showing one card in two places. That's
also why both call sites (`_run_objective_engage` / `_award_uncontested`) receive it with `await`.

| Objective | Beats |
|---|---|
| **Dragon** | N reward cards **fan out** in the center (`SPREAD_SEC` 0.34s + `HOLD_SEC` 0.70s) → **stack into what looks like one card** (`COLLAPSE_SEC` 0.26s) → get sucked into the **deck pile** at bottom left (`FLY_SEC` 0.42s) |
| **Herald** | 1 reward card rises in the center → settles into the **leftmost slot of the hand** (it's a single card, so the stacking beat is skipped) |

- **If the enemy (적) takes it, both fly to the left end of the opponent's (상대) hand at the top** and vanish
  (`HudBuilder.ai_hand_left_anchor()`). The opponent's deck isn't on screen, so the Dragon uses that
  spot too — what matters is "whose did it become", and whether the card went up or down answers that.
- **The Herald's landing point equals its actual insertion slot.** The FX heads for the **leftmost slot**
  measured by `slot_position(0, n+1)`, and the grant also inserts it there via
  `grant_cards_to_hand(..., at_left = true)`. The `at_left` path also skips the draw intro
  (`spawn_card_node` turns it off) — if it flew in again from off-screen left, the flight you just saw
  would play twice.
- **The dim lifts when the flight starts.** The deck pile and the opponent's hand are both under the dim,
  so the screen must be bright at that moment to show where it goes.
- The card is the same `Card.tscn` node as the hand (same reason as `ObjectiveRewardPopup` — if it were
  a separately drawn picture, there'd be no way to confirm it's the same card that actually came in).
- **On an uncontested take it comes after the confirmation window closes.** If reward cards flew around
  on top of the notice, it would be unclear which one the screen wants you to look at.
- While the FX plays (about 1.9s) `_busy` stays on, so the BATTLE auto tick and the MM:SS clock are
  stopped — this FX finishes inside `_resolve_objective`.
- Each beat is awaited with a **timer**, not the tween's `finished`. If the node is freed midway
  (restart · scene change) that signal never comes and the coroutine hangs
  (same rule as `CardPhaseManager._play_draw_intro`).

## Don't confuse it with the preview
`ui/ObjectiveRewardPopup.gd` is an info popup you open by tapping the clock **before resolution** to see
"what it gives"; `ObjectiveRewardFx.gd` is the FX that shows the cards actually received **after
resolution**. Only the names are similar — who opens them (clock / `ObjectiveSystem`) and their
lifetimes differ, and the former doesn't hold the battlefield while the latter does.

## Kill feed line (`_push_feed`)
When it is decided, one line appears in the kill feed at the top right **with the same grammar as a
kill line** — `[lead][assists][burst icon][Herald / Dragon glyph + name]`. Before this the result was
only one `last_log` line, so a major turning point of the match left no trace except the team score
widening a little.

- **The lead is the jungler.** Both teams' junglers are always participants in both the Herald and
  the Dragon, and running objectives is the jungle's job itself, so if one face has to say "who took it",
  that seat is the jungler's (`_feed_order`). If the jungler couldn't come (dead · position-locking
  skill), the first of the remaining participants takes the lead and all the rest are attached as assists.
- **The roster is the participants at the moment join was chosen** (the very array `participants_for`
  returned). People who went down in the engage afterwards stay in — the bodies spent taking the
  objective are the contribution.
- **An uncontested take also gets a line.** Taking it for free because nobody showed up is exactly the
  case where nothing happens on screen at that moment, so it needs a trace even more.
- When decided by an engage, this line appears **after the kill lines that were queued during the
  engage** — because `_grant_reward` comes after `await engage_finished`, and that signal is emitted
  after `flush_pending()` (kill → acquisition is the actual order).
- The Herald / Dragon art is drawn by **the same static functions** as the top-panel spawn clock
  (`ObjectiveTimer.draw_kind_glyph` / `kind_color`).

## The stage is borrowed — the neutral cells are **ordinary jungle cells**
The two left/right neutral cells (`SimulationCore.NEUTRAL_LEFT` / `NEUTRAL_RIGHT`) are just the
coordinates where objectives stand; **their tile rules don't differ by a single letter from other
jungle cells**: camps spawn there, junglers step on and capture them, they are patrol targets, and they
change owner via the side-T1-destruction flank-neutral-steal branch. `ObjectiveSystem` reads neither
that cell's owner nor its camp state — what decides an objective is not the tile but **participants and
decisions**.

At one time they were **permanently neutral** (`SimulationCore.is_objective_cell()`). That was the era
when camps didn't spawn, junglers couldn't capture, they were excluded from patrol targets, and the T1
flank-neutral-steal branch was dead code — `_nearest_uncaptured_neutral()` had its check become
permanently true and was deleted as a whole function. Now all three are revived and the camp cells are
back from 12 → **14**. So the correction applied back then (`SCORE_JUNGLE_CAMP`, now in const.csv,
scaled up by 14/12) was also **reverted** — Herald / Dragon never pushed camps out, so
there's nothing to give back.

## Tick hold
While the decision window is up, `game_phase == BATTLE` still holds, so the phase guard alone doesn't
stop the auto tick. `ObjectiveSystem.is_busy()` covers that window, and `BattleSim._battle_tick_held()`
reads it together with the opponent's turn to hold both the auto tick and the MM:SS clock (both must read
the same answer so on-screen time and the actual turn don't drift apart). The engage stage that follows
is also blocked by `game_phase = ENGAGE`, but the decision window before it is blocked only by this guard.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Objectives (Herald / Dragon) | An engage event that opens at fixed turns on the left/right neutral cells. **Those two cells are ordinary jungle cells** — the objective only borrows the coordinates as a stage, so camps spawn and junglers capture there too (the "Jungle (initial)" entry below). **Right = Dragon (first spawn `OBJ_DRAGON_FIRST_TURN`, 4 participants: RIGHT×2·CENTER·JUNGLE)** opens first, and **left = Herald (`OBJ_HERALD_FIRST_TURN`, 3 participants: LEFT·CENTER·JUNGLE)** comes later. Once decided it reopens after `OBJ_RESPAWN_TURNS`; if it fizzles because neither team joined, after `OBJ_RETRY_TURNS` (all game_config.csv). It used to be Herald first with only a short gap, so the first Herald and first Dragon effectively overlapped, and the jungler · center, participants on both sides, got dragged left and right so neither became a "gather and fight" event. The order was flipped because of the rewards' nature — the Dragon's growth accrual bonus ([용 보상]'s `growth_perm` clause, cards.csv) is a gain that runs for the rest of the match, so **its value grows the earlier you take it**, while the Herald's turret damage (its card's `turret_damage` clause) is worth the same whenever you take it. Pushing both first spawns back and lengthening the respawn intervals is for the same reason: an objective should not cut into the laning phase but open after the lanes have settled once. The remaining turns are always shown **on either side of the enemy strip in the top panel** (`ui/ObjectiveTimer.gd`, left Herald / right Dragon — icon + remaining turns. Same layout as the map's left/right, so the position is the name. Each slot is 101×60 and **there is no "턴" (turn) text** — the number next to the icon can't be anything other than remaining turns). **Tapping the clock shows that objective's reward card as a real card** (`ui/ObjectiveRewardPopup.gd`) — it's an avoidable event, so what it gives must be visible before resolution, and this popup is **pure information, so it doesn't hold the battlefield** (that's how it differs from the join decision window) — it's a promise for both teams to gather at the same spot, so if you can't see when it opens, you can't judge whether to push a lane ahead or attach the jungler. This number used to be printed on the tile (`BattleRenderer._draw_objectives`, **deleted**), but when the cell went back to jungle it competed for space with the camp outline · capture fill colour · portraits. **It fires regardless of whose turn it is**: `CardPhaseManager.do_battle_turn` calls `await _bs.objective.process_turn()` right after `simulate_turn()` and **before** the card economy. **It can be avoided** — the player gets two buttons, join / don't join (the `EngageIntro` VS screen reused with only the text changed); the AI **counts heads only** — it backs off only when its participants with HP ≥ `OBJ_AI_HEADCOUNT_HP_RATIO` are fewer than the opponent's (strength differences are ignored), and even then it accepts with the **misjudge chance** (opponent league rank 1st `OBJ_MISJUDGE_MIN` → last `OBJ_MISJUDGE_MAX`, ties by team average stats, international tournament outside teams `OBJ_MISJUDGE_MIN` — `MatchFlow._misjudge_chance_for` → `match_ctx.enemy_misjudge_chance`). Decisions are made simultaneously without knowing each other's. If only one side joins, that side takes it without a fight; if both, after an `OBJ_ENGAGE_ROUNDS`-round engage (`EngagePhaseManager.start_objective_engage` — opens without a caster, blue acts first, **no turret joins for either team**) the winner is decided by **survivor count → on a tie, sum of remaining HP ratios** (why ratios: with absolute values "the side with the tank alive" always wins). **Dead pilots can't join**, so a kill just before an objective decides the objective. Rewards — Herald: 1 **[전령 제압]** (Herald Subdued) (id 32, `exhaust\|preserve`) **straight into the hand**, no-check damage (its `turret_damage` clause) to the **outermost** living enemy turret per lane (in a lane whose T1 fell, T2 inherits the slot). **If there are no enemy pilots on that lane's front line, damage is doubled** (front line = between both teams' foremost turrets = from the targeted enemy turret cell to our foremost turret cell, `SimulationCore.front_line_cells` — same set as the on-screen gold outline), and **the growth points for what was chipped off are split evenly among the allied laners of that lane** (the right lane has two, sniper · supporter, so half each). Herald Subdued has no caster, so the usual attribution path reaches nobody — the people who held that lane while pushing it own the siege. Dragon: **`OBJ_DRAGON_CARD_COUNT`** **[용 보상]** (Dragon Reward) (id 33, `exhaust`) **shuffled into the deck**, a draw + **permanent** `growth_perm` bonus to the targeted ally's growth accrual multiplier (`PilotData.growth_rate_bonus`, stacks). Both cards have `pool = 0` and **no caster** (`owner_pilot == null` — the team took it, not someone, and attaching a caster would lock the reward while that pilot is down). While the decision window is up it's still BATTLE, so `ObjectiveSystem.is_busy()` + `BattleSim._battle_tick_held()` hold the auto tick and the MM:SS clock together. **Rewards come in through FX** (`objective/ObjectiveRewardFx.gd`) — see the "Objective reward acquisition FX" entry below. Details in `objective/README.md`. |
| Objective reward acquisition FX | **Reward cards go in only after being shown once as real cards** (`objective/ObjectiveRewardFx.gd`). It used to end with one `_grant_reward` line, so even though it was the payback for fighting up to a 4-player engage over an objective, nothing happened on screen except the hand growing by one or the deck count going up — the Dragon in particular is **shuffled into the deck**, so nothing lands in your hand at that moment. **Dragon**: N reward cards fan out in the screen center (`SPREAD_SEC` 0.34s + `HOLD_SEC` 0.70s, spacing `FAN_STEP_PX` 118px · edge tilt `FAN_TILT_DEG` 7°), **stack into what looks like one card** (`COLLAPSE_SEC` 0.26s — this beat says "these several cards now become one pile"), and get sucked into the **deck pile at bottom left** (`FLY_SEC` 0.42s). **Herald**: one card rises in the center and settles into the **leftmost slot of the hand** (single card, so the stacking beat is skipped). **If the enemy takes it, both fly to the left end of the opponent's hand at the top** and vanish (`HudBuilder.ai_hand_left_anchor()`) — the opponent's deck isn't on screen, so the Dragon uses that spot too. What matters is "whose did it become", and whether the card went up or down answers that. **The Herald's landing point equals its actual insertion slot** — the FX heads for the leftmost slot measured by `slot_position(0, n+1)` and the grant inserts it there via `grant_cards_to_hand(..., at_left = true)` (that path also skips the draw intro — if it flew in again from off-screen left, the flight you just saw would play twice). **FX comes before granting** — `_grant_reward` became a coroutine and inserts **after** awaiting `play()`. If the order were flipped, the same card would already be in the hand during the FX, showing one card in two places. The dim (α 0.55) **lifts when the flight starts** — the deck pile and the opponent's hand are both under the dim, so the screen must be bright at that moment to show where it goes. On an uncontested take it comes **after the confirmation window closes** (cards flying over the notice would blur which one the screen wants you to look at). The card is the same `Card.tscn` node as the hand (a separately drawn picture would give no way to confirm it's the same card that came in), and each beat waits on a **timer**, not the tween's `finished` (if the node is freed midway, that signal never comes). Don't confuse it with `ui/ObjectiveRewardPopup.gd`, opened by tapping the clock **before** resolution — that one is an info popup previewing what it gives and doesn't hold the battlefield; this one is FX showing the cards actually received and `_busy` holds it. |
