# `features/battle_sim/mech/` — Mech (메크) skills

표시 텍스트는 l10n key (`battle.mech.boon.*`) — `BOON_KEYS` holds keys, `boon_defs()` returns `{key, name, desc}` translated at call time. **Passive descriptions** (`mech_passive.{id}.desc`) carry no numbers: tuning values are `{mech_…}` const placeholders (filled by `Loc.t`), the row's `p1` / `p2` are `{p1}` / `{p2}`, so every screen shows them through the static `MechSkillSystem.passive_description(def)` (a bare `Loc.t(description_key)` leaves `{p1}` · `{p2}` visible).

Owns the runtime state of the permanent abilities (passives) attached to the assigned **machine**
and of the cards that machine brings into the deck (덱). It is a sibling module standing next to
pilot skills (`../skill/`), and for the same reason it is set up **after spawning and deck
distribution are both finished**.

| File | Role |
|---|---|
| `MechSkillSystem.gd` | `class_name MechSkillSystem` — passive state · Charge · event hooks · query functions |
| `MechUpgrades.gd` | `class_name MechUpgrades` (static) — mech upgrade steps (§15 A, `mech_upgrades.csv`): unlocked steps per mastery level, upgraded passive row, upgraded card row, step text. Shared by BattleSim and the outgame (ban/pick `MechDetailPanel`, `MasteryPanel`) |

**If a pilot skill is a move attached to the player, a mech skill is what the machine does.**
The moment a machine is picked in ban/pick (밴픽), half of that pilot's deck and one permanent
ability are decided along with it. The list of 21 machines · keywords · mech-card-only clause
grammar also live in this doc (moved from the former `docs/mech_skills_design.md`).

---

## Data

| Table | Rows | Key |
|---|---|---|
| `data/csv/mech_passives.csv` | 15 | `mech_id` → one passive (6 of the 21 machines have none) |
| `data/csv/mech_cards.csv` | 64 + 54 "+" | `mech_id` → card array, `id` → one card ("+" rows: see "Mech upgrades") |
| `data/csv/mech_upgrades.csv` | 63 | 3 upgrade steps per mech (§15 A) |

`GameManager` holds them as three — `mech_passives` (mech_id → row),
`mech_cards` (mech_id → array), `mech_card_defs` (card id → row). The last one exists separately
because more than ten clauses create cards **by pointing at them**
(`gen_hand:13` / `gen_deck:39` / `search_card:7`) — searching the array each time would rerun the
same linear search for every card.

## Mech upgrades (돌파형, §15 A)

A pilot's **mech mastery level** (0..5, `features/season/mastery/`) on the mech it rides unlocks upgrade
steps: Lv3 → step 1, Lv4 → step 2, Lv5 → step 3, **cumulative**. Every mech has exactly three steps.

| Table | Columns |
|---|---|
| `data/csv/mech_upgrades.csv` | `id, mech_id, level (3/4/5), target (passive \| card), param (p1 \| p2, passive only), card_id (card only, else -1), value (passive delta, else 0), desc_key` |
| `data/csv/mech_cards.csv` | upgraded **"+" rows**: `id` = 100 + base id ("++" = 200 + base id), `count = 0`, name "<base>+"; the base row's `upgrade_id` points at it (`-1` = none). A "+" row may carry its own `upgrade_id` ("++") |

- **Passive step** — `MechUpgrades.passive_def(base_def, mech_id, level)` returns a copy of the passive row
  with `param += value` for each unlocked step. `init_for_match` stores that row, so `_param` /
  `passive_def` / the max-Charge / Overclock's start Charge and the in-match description all read the
  upgraded numbers. 6 mechs without a passive (and 4 whose passive has no parameter) upgrade cards only.
- **Card step** — `MechUpgrades.card_def_for(card_id, mech_id, level)` follows `upgrade_id` while that link's
  own step is unlocked (`card_id` of the step = the card being upgraded, possibly a "+" id for a "++" step).
  Used in two places: `CardPhaseManager._mech_card_defs_for` (deck build — the swapped row keeps the base
  row's `count`) and `make_mech_card_by_id` (cards created by passives / `gen_*` / `search` clauses, so a
  generated 승전보 / 처형 / 락온 is the "+" one too).
- **Identity** — `GameManager._load_mech_skills` keeps "+" rows out of `mech_cards_for(mech)` (the mech's own
  list = base cards only) and stamps them with `base_id` (the root card). `CardData.from_mech_def` sets
  `mech_card_id = base_id`, so a "+" copy keeps the base's art (`card_uid`), and `search_card:ID`,
  `_hand_has_card`, trigger lookups and the phase-chain ids still match it. Only name, cost, numbers and
  keywords differ.
- **Level source** — `BattleSim.mech_level_for(p)` reads `match_ctx.mech_levels["<pilot_id>"]` (written by
  `MatchFlow._finalize_rosters` from `MechMastery.mech_levels_ctx`, both teams). Missing (standalone run) =
  0 → no upgrades.
- **Text** — `step_text(step)` = `Loc.t(desc_key, {from, to})`: the passive param before / after this step,
  or the card cost before / after (numeric card changes are worded qualitatively in the key). Keys
  `mastery.upgrade.<id>.desc` (data column, `data/l10n/config.json`); "+" card names / descriptions are
  `card.mech.<id>.name` / `.desc` like every mech card.
- Draft content (user tunes it): passive steps — 과적재 p1 −2, 반응 장갑 p1 +1, 고통과 쾌감 p1 +5, 영혼 수확
  p2 +2 / p1 +1, 오버클럭 p1 +20, 무념 p2 −1, 취약 각인 p1 +5, 조준 보정 p1 +1; the rest are card steps,
  mostly cost −1 or one number up (see the csv).

## The 21 mechs

The design sheet's A–W were laid onto the 21 surviving rows of `mechs.csv`. **The ids were kept and
9 rows were deleted** — `resources/images/mech/{id}_full.png` is bound to the id, so renumbering
would misalign art and stats wholesale. Hence the gaps in ids (3·4·5, 10·11, 16·17, 23, 29).
Notation like "탱커 E" (Tank E) or "암살 P" (Assassin P) in code comments and READMEs is the **sheet
letter**.

Passive and card names below are the Korean data strings (as in the CSVs), glossed in English.

| Sheet | id | Name | Role class | Passive | Cards |
|---|---|---|---|---|---|
| E | 0 | Juggernaut | Tank | 과적재 (Overload) | 몸집 불리기 (Bulk Up) · 추적 (Track) · 강습 (Assault) |
| G | 1 | Bastion | Tank | 반응 장갑 전개 (Deploy Reactive Armor) | 최첨단 보호 (Cutting-edge Protection) · 초고출력 (Overpower) · 개시 (Initiate) |
| N | 2 | Ironhide | Tank | 고통과 쾌감 (Pain and Pleasure) | 주먹다짐 (Brawl) · 고통과 쾌감 · 제압 전투 (Suppression Fight) |
| D | 6 | Triumph | Fighter | 승전보 (Victory Report) | 승전보 · 돌격 (Rush) · 질주 (Sprint) |
| F | 7 | Wrecker | Fighter | 철거 명령 (Demolition Order) | 철거 (Demolish) · 우세한 전장 (Dominant Battlefield) · 격렬한 돌진 (Fierce Rush) |
| H | 8 | Headsman | Fighter | 처형 준비 (Execution Prep) | 처형 (Execute) · 일격 (Strike) · 휩쓸기 (Sweep) |
| L | 9 | Reaper | Fighter | 영혼 수확 (Soul Harvest) | 유령의 올가미 (Ghost Snare) · 전쟁의 사슬 (Chains of War) · 영혼 포식 (Soul Devour) |
| P | 12 | Overdrive | Assassin | 오버클럭 (Overclock) | 리부트 (Reboot) · 단계 A (Phase A) · 단계 B (Phase B) · 단계 C (Phase C) |
| R | 13 | Blitz | Assassin | — | 약자 멸시 (Scorn the Weak) · 전격전 (Blitzkrieg) · 즉발 베기 (Instant Slash) |
| T | 14 | Zephyr | Assassin | 무념 (No-mind) | 명상 (Meditate) · 질풍 (Gust) · 신속 (Swift) |
| W | 15 | Siren | Assassin | — | 최면 (Hypnosis) · 매혹적인 침공 (Alluring Invasion) · 매혹 (Charm) |
| K | 18 | Marshal | Support | — | 공격 명령 (Attack Order) · 투자 (Invest) · 간보기 (Probe) |
| Q | 19 | Guardian | Support | 수호 연계 (Guardian Link) | 지원 보호 (Support Shield) · 수호 (Guard) |
| S | 20 | Caprice | Support | — | 강타 (Smash) · 탈진 (Exhaust) · 변덕 (Caprice) |
| U | 21 | Alchemist | Support | — | 밸런스 (Balance) · 파란 약 (Blue Pill) · 붉은 가루 (Red Powder) · 녹색 병 (Green Bottle) |
| V | 22 | Verdict | Support | 불굴 (Indomitable) | 죽음의 손가락 (Finger of Death) · 확신 (Conviction) · 사형 선고 (Death Sentence) |
| A | 24 | Tempest | ADC (원딜) | 취약 각인 (Vulnerability Mark) | 천둥 폭풍 (Thunderstorm) · 천공의 일격 (Sky Strike) · 꿰뚫는 번개 (Piercing Lightning) |
| B | 25 | Scavenger | ADC | — | 캐시 (Cash) · 스캐빈저 (Scavenger) · 로켓 펀치 (Rocket Punch) |
| C | 26 | Payload | ADC | 미사일 적재 (Missile Stock) | 미사일 (Missile) · 미사일 준비 (Missile Prep) · 정밀 폭격 (Precision Bombing) |
| I | 27 | Barrage | ADC | 전탄 발사 (Full Barrage) | 전장 강타 (Battlefield Smash) · 계시 (Revelation) · 결속 (Bond) |
| J | 28 | Deadeye | ADC | 조준 보정 (Aim Assist) | 락온 (Lock-on) · 테러 (Terror) · 파괴 (Destroy) |

**Barrage (I)'s 전탄 발사 (Full Barrage)** splits each engage attack over up to `MECH_BARRAGE_MAX_TARGETS`
presence-weighted random enemies at `MECH_BARRAGE_DMG_MULT` × attack — the per-hit cut is the price, so its
`atk` in `mechs.csv` is a normal ADC value (the old "half attack" baked into the data was removed).

**Deck size** — mech cards are the assigned machine's cards spread out `count` times (the sum of
its rows' `count`, mech_cards.csv), and pilot cards are a fixed 3 per player. Machines differ in how
many cards they bring, so the team deck size depends on which five machines were picked.
The difference in card count is itself part of choosing a machine.

## The four mech keywords

| Keyword | Meaning | Notes |
|---|---|---|
| **Charge (충전)** `charge` | Charge +`CARD_CHARGE_HAND_GAIN` (const.csv) each time it enters the hand (cap `charge_max`); on use, all Charge is spent and it gets that much stronger | The strength is **the state of one card** (`CardData.charge`), so a single copy (`count`) suffices. It rises in two places, `add_card_to_hand` / `draw_card` (both `CardData.gain_charge()`), and burns in one, `_burn_charge(cd)` — it records the burned amount in `_charge_spent` (the effect chain runs over several frames, so by then `charge` is already 0). Cards that use it (cap = `charge_max`, mech_cards.csv): 미사일 (C) · 전장 강타 (I: Charge + `|base:N` targets) · 약자 멸시 (R) |
| **count** | Number of copies put in the deck when adopted | The six cards with `count = 0` (승전보 · 철거 · 처형 · 락온 · 고통과 쾌감 · 단계 B/C) only appear when another effect creates them. They are still written in the distribution table (`BattleSim.starter_cards`) — so the detail panel's mech tab doesn't show only half the machine |
| **Cost -1** | Cannot be played — has its effect just by being in the hand | 캐시 (B) · 계시 (I) · 약자 멸시 (R) · 밸런스 (U). Cost cell shows `—`, covered by a slab, drag refused, **except it can be dragged during a discard pick**. The effect is a single `hand_passive:<key>` line, and the actual behaviour is read by `MechSkillSystem` scanning the hand. Different from cost 0 (playable for free) |
| **Volatile** `volatile` | If discarded unused, it is removed instead of going to the discard pile | 철거 (F) · 락온 (J), and the temporary missiles made by 정밀 폭격. Combined with exhaust (소멸, disappears when used), it bloats the deck in neither direction |

> **Charge used to be `스택` (stack)** — copies of the same card merged into one in the hand and
> `stack_count` held the number of copies, but they had to be split back into singles every time
> they went to a pile, and the strength cap was the `count` itself, so one card type bloated the deck
> by several cards. **공격 명령 (K)** dropped Charge in this switch and moved to the `death_hand` hook.

## Effect grammar — mech-card-only clauses

Shared clauses (`draw` / `discard` / `strategy` / `attack` / `engage` / `move` / `shield_pct` …) are
in the effect table of `../card_phase/README.md` (`around_target` · `discard_right` ·
`move|own_jungle` · `phase_b` / `phase_c` are there too); below are the ones only mech cards use.
**Naming them so they don't collide with shared clauses is intentional** — looking at just the
`effect` string should tell you "this is a card a machine provides".

**Chain control** — `on_hit` (run the following clauses if the preceding attack clause hit at least
once) / `on_miss` (if everything missed). Instead of hanging a condition on one clause, the chain is
cut in two — card text is always two branches, "on hit A, on miss B", and each branch has several
clauses. Example: 간보기 `attack:N;on_hit;engage:N|at_target;on_miss;strategy:N`.

**Attack clause flags** — `attack:N` defaults to "one enemy, once, for N × ATK", and flags widen the
target set. A target is either `PilotData` or `TurretData`, and the only places that tell them apart
are the two functions that apply damage (hit check · rush animation · popups are shared).

| Flag | Targets | Cards using it |
|---|---|---|
| `all` | All enemy pilots on the battlefield (전장) | 천둥 폭풍 |
| `random` | Random enemy (with `charge`, **Charge count + 1** targets) | 전장 강타 |
| `self_range:N` | Enemies + turrets (포탑) within N cells of the caster (시전자) | 테러 · 초고출력 · 영혼 포식 · 휩쓸기 · 즉발 베기 |
| `area:N` | Enemies + turrets within N cells of the chosen target | 정밀 폭격 · 파괴 |
| `damaged` | All enemies this mech hit during this operation phase (작전 단계) | 락온 · 신속 |
| `line` | The entire lane (레인) from the allied HQ to the chosen turret | 꿰뚫는 번개 |
| `turret_only` | One chosen enemy turret | 철거 |
| `charge` | Repeat **for each target** as many times as the Charge count | 미사일 · 전장 강타 |
| `pierce` / `repeat` | (shared) guaranteed hit / repeat per hit | |

**Pilot→turret card damage is a fixed value** (`PILOT_STRUCTURE_DMG`) — if it scaled with `atk`, one
card would wipe a whole turret in the late game when growth multiplies attack several times over.

**Remaining clauses**

| Clause | Meaning | Flags |
|---|---|---|
| `heal_pct:N` | Heal N% of the target's max HP | `self` `per_hit` |
| `max_hp:N` | Max HP **permanently** +N | `self` `per_hit` |
| `atk_add:N` | Attack **permanently** +N | `self` |
| `shield_atk:N` | Shield of N% **of the caster's attack** | `all_allies` |
| `reactive_armor:N` | N layers of reactive armor | `self` `per_hit` |
| `charge:N` | Mech passive Charge +N | `per_hit` |
| `score_cost:N` | Spend N growth score (in units of `MECH_SCORE_COST_UNIT`, const.csv) | |
| `growth_eff:N` | Growth accrual +N% (until leaving the battlefield, cumulative) | |
| `gen_hand:ID` / `gen_deck:ID` | Create that mech card into hand / deck | `per_hit` `per_kill` `temp` |
| `search_card:ID` | Search (찾기) the deck for that card and put it in hand | `count:N` |
| `search_discard:N` | Graveyard search — **spread out the discard pile and choose** | |
| `draw_discard:N` | Graveyard draw — N cards from the top | `cost_reduce:N` |
| `push:N` | Push N cells | `bonus_clear:N` |
| `move_target:N` | Push **the enemy** N cells | |
| `move_to_target` | Caster leaps into the target's cell | |
| `pull_to_caster` | Pull the enemy to the caster's cell | `self_range:N` |
| `mark_target:N` | Mark — damage taken from the caster +N% | |
| `track:N` | Track for N turns | |
| `link_engage` | 결속 (Bond) — caster ↔ target, **both directions** (see `engage_link` below) | |
| `stun_next` | 강타 (Smash) | |
| `no_engage_phase` | 탈진 (Exhaust) | |
| `dmg_taken:N` | Damage taken +N% (doesn't stack) | |
| `bounty:N` | Bounty = N% of the target's growth points (성장치) | |
| `attack_bounty:N` | Deal N% of the bounty as damage | |
| `mutual_attack:N` | Each attacks the other N times (the target side always hits) | |
| `taunt_all` | All enemies attack the caster with guaranteed hits | |
| `execute:N` | Kill if at or below N% of max HP | `charge:N` |
| `growth_link:N` | Charm for N turns | |
| `discard_left` / `draw_discarded` | Discard the cards left of this card and draw that many | |
| `hand_passive:<key>` | Marker of a cost -1 card (not executed) | |

**Engage clause flags**

| Flag | Meaning | Cards using it |
|---|---|---|
| `at_target` | Open **around the chosen enemy** | 돌격 · 강습 · 간보기 |
| `at_marked` | Around the marked enemy | 단계 B |
| `self_range:N` | Radius N centred on the caster | 우세한 전장 · 개시 · 제압 전투 |
| `charge_rounds` | Replace the round count with 영혼 포식 Charge | 전쟁의 사슬 |
| `move_in` | Caster **moves on the battlefield** to the target's cell, then engage (no stage (무대) drop) | 돌격 |
| `drop_in` | `move_in` + drop into the middle of the enemy formation on the stage | 강습 |

`EngagePhaseManager._gather_participants` takes `center` / `radius` (defaults are the caster's cell
+ the 6 adjacent cells).

**Target kinds (`target` column)** — `foe` (enemy pilot **or** turret — you choose a cell and the
attack clause decides what in that cell gets hit, pilot first. The targeting overlay handles only one
of portrait (초상화) or cell, and turrets have no portrait) · `turret_outer` (outermost enemy turret
per lane) · `turret_any` (all living enemy turrets, ignoring range) · `pilot` (can choose **both**
allies and enemies — 매혹).

## Persistent state — `PilotData` fields

Every state a mech applies lives in `PilotData`, and this module turns it on and off.

| Field | Meaning | Read at |
|---|---|---|
| `vulnerable` | Vulnerable — damage taken + `MECH_VULNERABLE_PER_STACK` per point | `damage_taken_mult` |
| `reactive_armor` | Reactive armor — `MECH_REACTIVE_ARMOR_CUT` reduction per hit, then 1 consumed | `consume_reactive_armor` |
| `damage_taken_bonus` | Additive damage-taken multiplier (죽음의 손가락) | `damage_taken_mult` |
| `bounty` | Bounty | `attack_bounty` |
| `marked_by` / `marked_bonus` | Mark (only against that caster) | `damage_taken_mult` |
| `tracked_by` | Track — the people who get pulled in when this enemy fights | `_gather_participants` |
| `engage_link` | 결속 (Bond) — stored **only on the caster** (one target per caster; re-casting on another ally overwrites it, which drops the old pair in both directions). The reverse direction is read by scanning `engage_link == p` (`EngagePhaseManager._bond_mates`): when either joins an engage the other is pulled in if alive and not 탈진 (`engage_locked`). One pilot may be the target of several casters — each pair is independent. Pulls are one level only (a pulled pilot's own bonds are not followed, same as 추적). `clear_field_effects` clears the leaving pilot's own link **and every link pointing at it**. Battle state is not in the mid-match save (resume replays from the start), so nothing to persist | `_gather_participants` |
| `engage_locked` | 탈진 (Exhaust) | `_gather_participants` |
| `stun_charge` / `stunned_rounds` | 강타 (Smash) / stun | `TurnEngageSim` |
| `growth_link_to` | 매혹 (Charm) | `BattleSim.add_score` |
| `bonus_atk_flat` / `bonus_atk_mult` / `bonus_max_hp` | Permanent stat modifiers | `refresh_growth_stats` |
| `phase_return_cell` | Scheduled position return (질풍) | `on_phase_end` |

**Reactive armor applies before shields** — it cuts `MECH_REACTIVE_ARMOR_CUT` and the shield takes the remainder, so
the two defences read as layered. The other way round, the shield would eat the full damage first
and the armor would only apply to the remainder.
**Vulnerable · 죽음의 손가락 · Mark are additive, not multiplicative** — all three are the same
sentence, "damage taken +N%", and stacking multiplicatively would make the multiplier balloon the
moment 죽음의 손가락 lands on a heavily stacked Vulnerable.

## The 15 passives

There is no `type` — all are permanent/automatic, and none can be pressed. For passives that use
Charge, Charge is **the condition of the effect**, not fuel for activation.

| Machine | Key | What it does |
|---|---|---|
| E 0 | `bulk_power` | Attack +1 per `p1` max HP (added **after** HP is finalised) |
| G 1 | `reactive_plating` | On engage, `p1` layers of reactive armor on self |
| N 2 | `pain_pleasure` | Max HP increases by `p1`% of damage dealt and taken / if it destroys a turret in its own lane **by itself**, [고통과 쾌감] into the deck |
| D 6 | `victory_report` | On objective (오브젝트) win, [승전보] into hand |
| F 7 | `demolition_order` | On objective win, [철거] into hand |
| H 8 | `execution_charge` | +1 Charge per kill/demolish (max `p2`) / at max Charge, [처형] into hand |
| L 9 | `soul_harvest` | Per hit·engage damage, attack +`p1`%, max HP +`p2` |
| P 12 | `overclock` | Starts with +`p1` Charge (max `p2`) / on engage damage, extra attack at `MECH_OVERCLOCK_PROC_PER_CHARGE` per Charge + spend half the Charge |
| T 14 | `zen_charge` | +1 Charge per card played/discarded (max `p2`) / at max Charge, burn it all for an area attack within range 1 |
| Q 19 | `guardian_link` | When an ally shielded by this mech deals damage, this mech also attacks that enemy |
| V 22 | `last_stand` | On engage, **the whole team** can't drop below 1 HP, once each |
| A 24 | `vulnerability_mark` | During this operation phase, Vulnerable `p1` on the target per card hit |
| C 26 | `missile_stock` | Each time a turret **in its own lane** falls, whichever team it belongs to, [미사일] into the deck |
| I 27 | `barrage` | During engage, each attack hits up to `MECH_BARRAGE_MAX_TARGETS` presence-weighted random enemies at `MECH_BARRAGE_DMG_MULT` × attack |
| J 28 | `calibration` | Attack +`p1` per battlefield card hit |

The six without passives: **B(25) · K(18) · R(13) · S(20) · U(21) · W(15)** — they play with cards only.

### Icons
Each passive shows an icon tile like a pilot skill — `MECH_ICON` in `resources/SkillImages.gd`
maps `key` → a Deadlock ability icon in `resources/images/skill/` (none shared with the pilot
`ICON` table). Shown by `SkillImages.make_mech_icon_tile` in the ban/pick `MechDetailPanel` and
sheet, and in the in-match pilot detail's mech tab (+ the passive's lasting-effect thumb,
`mech_icon_for`). A new passive needs a row there too (missing → no icon, no error).

| Key | Icon | Key | Icon |
|---|---|---|---|
| `bulk_power` | Puddle_Punch | `overclock` | Power_Surge |
| `reactive_plating` | Plot_Armor | `zen_charge` | Singularity |
| `pain_pleasure` | Bloodletting | `guardian_link` | Kudzu_Connection |
| `victory_report` | Call_Bell | `last_stand` | Last_Stand |
| `demolition_order` | Sticky_Bomb | `vulnerability_mark` | Djinn's_Mark |
| `execution_charge` | Killing_Blow | `missile_stock` | Gloom_Bombs |
| `soul_harvest` | Siphon_Life | `barrage` | Barrage |
| | | `calibration` | Kinetic_Carbine |

**Event hooks attached to cards** (`mech_cards.trigger`) are not passives but conditions under which
that card comes into existence, so they live on the card side — `turret_kill_deck` (꿰뚫는 번개:
`MECH_TURRET_KILL_DECK_CARDS` copies into the deck each time an enemy turret is destroyed) · `death_hand`
(공격 명령: `MECH_DEATH_HAND_CARDS` copies into hand each time someone dies); both counts in const.csv. Whether a machine brings a hooked card is decided by the distribution
table (`starter_cards`) — the answer is the same wherever it is now, hand/deck/pile (even if
exhausted).

## What this module does not do

**Card effects are not here.** All clause grammar is handled by `CardPhaseManager._apply_single_effect`
(the "Effect grammar" section above); this module owns only the **state** those clauses leave behind
and the **query functions** that read it. If the boundary blurs, fixing one card means opening two
files.

**It doesn't push stats directly.** Passive modifiers are exported only via query functions, and the
calculation stays where it always was:

| Query | Read at |
|---|---|
| `atk_mult` / `bulk_power_atk` | `BattleSim.refresh_growth_stats` |
| `damage_taken_mult` / `consume_reactive_armor` | `SimulationCore._pilot_hit_damage`, `CardPhaseManager._apply_attack_damage` |
| `barrage_active` / `overclock_extra_attack` / `last_stand_available` | `TurnEngageSim` |
| `contempt_active` / `consume_contempt` | `TurnEngageSim._pick_target` (약자 멸시) |
| `try_stun` / `consume_stun_turn` | `TurnEngageSim` (강타 / stun) |
| `consume_phase_boon` | `CardPhaseManager._effect_gen_card` · `_effect_phase_b` · `_phase_c_payout` |
| `chain_rounds` | `CardPhaseManager._effect_engage` (`charge_rounds` flag) |
| `score_cost_waived` | `CardPhaseManager._effect_score_cost` |

Pushing `atk` / `max_hp` here would be wiped by a single growth recalculation
(`refresh_growth_stats`). Permanent increases live in `PilotData.bonus_atk_flat` / `bonus_atk_mult` /
`bonus_max_hp` — those three are **inside** the recalculation formula.

## Event hooks — who calls them and when

| Hook | Caller |
|---|---|
| `init_for_match()` | `BattleSim._ready` (after deck distribution) |
| `on_card_played(cd, is_player)` | `CardPhaseManager._dispose_used_card` |
| `on_card_discarded(cd, is_player)` | `CardPhaseManager.send_to_discard` (excluding the card currently resolving — to avoid counting twice) |
| `on_card_attack_hit(a, t, dealt)` | `CardPhaseManager._apply_attack_damage` |
| `on_card_damage_for_revelation(t, src)` | Same place (계시) |
| `on_engage_damage(a, t, dealt)` | `TurnEngageSim._strike_one` |
| `on_shielded_ally_damage(a, t)` | `SimulationCore._flush_guardian_rides`, `CardPhaseManager._apply_attack_damage` |
| `on_engage_end(participants)` | `EngagePhaseManager._finish_engage` |
| `on_kill(victim, killer)` | `BattleSim.mark_pilot_dead` |
| `on_turret_destroyed(killer, td)` | `BattleSim.score_turret_kill` |
| `on_objective_win(team)` | `ObjectiveSystem` (both engage settlement · uncontested capture) |
| `on_engage_start(participants)` | `EngagePhaseManager._begin` |
| `on_phase_end(is_player)` | `CardPhaseManager._notify_skill_phase_end` |
| `clear_field_effects(p)` | `RecallSystem.return_to_hq`, `on_kill` |
| `tick_expiries(turn)` | `SimulationCore.tick_growth_and_expiries` |

### Effect banners
Conditional passives (and the hand-held 약자 멸시 / 계시 cards) announce the moment they fire with a
banner over the portrait — `_banner(p, key = "")` at the end of `MechSkillSystem.gd` →
`_bs.renderer.spawn_mech_passive_banner`; hand cards use `spawn_buff_banner(p, cd, "hand:<key>")`.
Always-on passives (과적재 · 전탄 발사) and 캐시 / 밸런스 stay silent. The per-passive table (which hook,
on whom) is in `../skill/README.md` → "Effect banners"; adding a conditional passive = add a
`_banner(...)` call at its trigger point and a row there.

## Charge

It rises only in `add_charge`, and the reward **at the moment it hits the cap** (`_on_charge_full`)
is also decided inside it — Charge rises in several places, so leaving it to callers would duplicate
the condition check that many times. Two things currently react to the cap.

- **처형 준비** (H) — one [처형] into hand (not created if already held)
- **무념** (T): burn all Charge for an area attack within range `MECH_ZEN_RANGE` (the only place a passive hits directly)

## What applies on the engage stage

The stage itself is run by `../engage/TurnEngageSim.gd`; this module exports **only query
functions**. Five places.

| What | Where | Rule |
|---|---|---|
| 전탄 발사 (I) | `_resolve_attack` → `_barrage_targets` | If `barrage_active` is true: Instead of the normal single attack, each engage attack hits up to `MECH_BARRAGE_MAX_TARGETS` enemies at `MECH_BARRAGE_DMG_MULT` × attack (`_strike_one`'s `dmg_mult`). The targets are drawn by `_barrage_targets` — **random without replacement, weighted by each enemy's `presence`** (`max(1, presence)`, the same aggro stat `_pick_target` reads); with that many or fewer enemies active, all of them. Battlefield card attacks are untouched, and Barrage's `atk` in `mechs.csv` is a normal ADC value again (the old "half attack" price is gone) |
| 오버클럭 (P) | `_strike_one` | Right after damage, roll `overclock_extra_attack` for one more hit **on the same target**. The extra attack isn't rolled again (`allow_extra = false`) — otherwise one turn could grow indefinitely by chance |
| 불굴 (V) | `_apply_damage` | The moment HP drops to 0 or below, hold it at 1 and consume. **Turret fire goes through the same function too**, so applying it only to pilot attacks would leave a hole where one turret shot kills |
| 약자 멸시 (R) | `setup` → `_contempt_opening` | **Before round 1 runs**, `take_contempt_charges` burns all Charge of the [약자 멸시] cards in hand, and hits **the enemy with the lowest HP** (absolute value, not ratio) that many times at `ENGAGE_CONTEMPT_DMG_MULT` (const.csv) of attack. The old "force targeting while stacks remain" was deleted because its value hung on the engage round count. Cards whose Charge was burned are recorded (`_contempt_spent`) and, once the arena closes, `CardPhaseManager.discard_spent_contempt` (called from `EngagePhaseManager._on_dashboard_confirmed`) discards those still in hand at 0 tokens — a held 약자 멸시 is one engage's worth |
| 강타 ([강타] card) | `_strike_one` | If the attacker is loaded, the hit enemy loses its entire next turn. `_stun_applied` prevents **the same enemy twice**; without it, one melee unit could keep one enemy asleep for the whole engage |

Single-engage state (`_stun_applied` · `_last_stand_*`) is turned on by `on_engage_start` and cleared
by `on_engage_end`. **Reactive armor is not in that pair** — the remaining layers carry over to the
next engage, so it is cleared not on engage end but when leaving the battlefield
(`clear_field_effects`).

## 수호 연계 (Guardian Link) (Q) ride-along attack

"When an ally wearing this mech's shield deals damage, this mech also hits that enemy."
It is the only consumer reading `shield_source` (ally → the mech that applied its shield), and has
three gates — that ally must **still** be wearing the shield (once it's depleted the link ends too),
the riding mech must not be itself ([수호] also shields the caster), and `_guardian_busy` re-entry
prevention (if two mechs shield each other, the loop actually closes).

**It is called from two places with different timing.**

- **Card damage** (`CardPhaseManager._apply_attack_damage`) — immediately, right there.
  Card damage doesn't separate judgement and application.
- **Battlefield auto-combat** — `SimulationCore._credit_pilot_damage` **only records it**
  (`_guardian_rides`), and `_flush_guardian_rides` rolls it after all of this turn's damage has been
  applied. Hitting immediately at the judgement stage would let the ride-along hit drop the opponent
  before damage not yet applied, so the rest of that turn's judgements would run against someone
  already dead.

The engage stage doesn't call it — the riding mech may not be on that stage, and if it is, it already
hits on its own turn.

## Phase A → B → C chain (Assassin P)

A loop of three cards that create each other.

```
[리부트] → search the deck for [단계 A]
[단계 A] → [단계 B] into the deck + Mark (`mark_target:N`) on the chosen enemy
[단계 B] → engage (`engage:N` rounds) around the marked enemy (radius `|self_range:N`, written in the row so the description can name it)
             ├ if an enemy was downed → [단계 C] into the deck
             └ otherwise              → [단계 A] into the deck   (one more lap of the loop)
[단계 C] → [단계 A] into the deck + choose 1 of 3 boons
```

**For `phase_b` to work, the `engage` clause must wait until the stage closes.**
That's why `CardPhaseManager._effect_engage` was changed to await `engage_finished`, and the same
change also fixes [우세한 전장]'s `gen_hand:19|per_kill` (both used to settle before the first round
even ran, i.e. when the kill count was always 0). The engage's kill count is answered by
`EngagePhaseManager.last_engage_kills` — the stage has been cleared by then, so it reads not `_sim`
but its copy (`_last_stats`).

**The 3 boons** (`BOON_KEYS` → `boon_defs()`) are used only for the next single occasion, and only one is reserved
per pilot.

| Key | Card it applies to | What it does | Consumed at |
|---|---|---|---|
| `alpha` | [단계 A] | Puts [단계 B] into the **hand** instead of the deck | `_effect_gen_card` |
| `beta` | [단계 B] | + `MECH_PHASE_BOON_BETA_CHARGE` Charge | `_effect_phase_b` |
| `gamma` | [단계 C] | Growth score + `MECH_PHASE_BOON_GAMMA_RATE` of own | `_phase_c_payout` |

**Gamma payout happens before choosing the new boon** — reversing the order would make the
just-chosen gamma feed back on the spot. The player chooses via `CardSelectOverlay`'s `CHOICE` mode
(the same grid as search, **no cancel**), and the AI chooses at random. Both paths converge on one
function, `CardPhaseManager.register_phase_boon`, so the rules can't diverge.

## Tuning constants

The values now live in `data/csv/const.csv` (read through `ConstTable`); `MechSkillSystem` exposes
them as `static var`s keeping the old const names. Values are not restated here — read const.csv.

| Constant (`MechSkillSystem.`) | const.csv key | Meaning |
|---|---|---|
| `VULNERABLE_PER_STACK` | `MECH_VULNERABLE_PER_STACK` | Damage-taken multiplier per 1 Vulnerable |
| `REACTIVE_ARMOR_CUT` | `MECH_REACTIVE_ARMOR_CUT` | Fraction one layer of reactive armor cuts |
| `OVERCLOCK_PROC_PER_CHARGE` | `MECH_OVERCLOCK_PROC_PER_CHARGE` | Engage extra-attack chance per 1 Charge |
| `CASH_RATE` | `MECH_CASH_RATE` | Fraction of own growth points [캐시] earns per card. Accrual goes through `award_score`, so **a popup appears above the portrait** — without a trace, holding that card and not holding it would look the same on screen |
| `SCORE_COST_UNIT` | `MECH_SCORE_COST_UNIT` | Unit of `score_cost:N` (growth points per N) |
| `PHASE_BOON_BETA_CHARGE` | `MECH_PHASE_BOON_BETA_CHARGE` | Charge that boon beta puts on [단계 B] |
| `PHASE_BOON_GAMMA_RATE` | `MECH_PHASE_BOON_GAMMA_RATE` | Fraction of own growth points boon gamma earns at [단계 C] |
| `ZEN_RANGE` | `MECH_ZEN_RANGE` | 무념 sweep range (tiles) |
| `BULK_POWER_ATK` | `MECH_BULK_POWER_ATK` | 과적재: ATK gained per `p1` max HP |
| `EXECUTION_CHARGE_GAIN` · `ZEN_CHARGE_GAIN` | `MECH_EXECUTION_CHARGE_GAIN` · `MECH_ZEN_CHARGE_GAIN` | Charge (token) gained per event |
| `*_CARDS` | `MECH_PAIN_PLEASURE_CARDS` · `MECH_VICTORY_REPORT_CARDS` · `MECH_DEMOLITION_ORDER_CARDS` · `MECH_EXECUTION_CARDS` · `MECH_MISSILE_STOCK_CARDS` | Cards a passive creates per trigger (`_grant_card_to_hand` / `_grant_card_to_deck` take a `count`; card `trigger` hooks use `MECH_TURRET_KILL_DECK_CARDS` · `MECH_DEATH_HAND_CARDS`) |
| `OVERCLOCK_EXTRA_ATTACKS` | `MECH_OVERCLOCK_EXTRA_ATTACKS` | Extra engage attacks per overclock proc (`TurnEngageSim._strike_one` loops) |

Multipliers (what %) live in const.csv rather than in `mech_passives.csv` for the same reason as pilot skills: to avoid
creating five or six number columns whose meaning differs per passive. The CSV's `p1` / `p2` are two
numbers whose meaning differs per passive (starting Charge · max Charge · Vulnerable amount · damage
ratio), and that meaning is written in the comments next to the `KEY_*` constants.

## Still remaining

| Item | Why |
|---|---|
| **AI judgement for the 3 boons** | The AI picks alpha · beta · gamma at random. It's the same first-order limit as the pilot-skill AI not activating at all, and setting a rule requires the AI to know "which lap of the chain this is" |
| **Stun round length** | Always 1 round (one next turn). The card text doesn't state a length, so the minimum was chosen |

## Verification

The full-loop smoke test (headless, a harness with `match_ctx` filled by hand, 60 turns · several
role-class rotations: 0 script errors · Charge accumulation confirmed) has spots it doesn't reach
within 60 turns, so targeted checks are called separately.

| Check | What it confirms |
|---|---|
| `passive/*` | Passives are actually read on the assigned machine |
| `stun/*` | Same enemy once per engage, consumes one turn, unloaded at engage end |
| `contempt/*` | Right after engage start, hits the lowest-HP enemy at `ENGAGE_CONTEMPT_DMG_MULT` of attack as many times as the Charge count, and Charge goes to 0 |
| `last_stand/*` | Applies to **the whole team**, once each |
| `overclock/*` | At full Charge it always fires and half is lost |
| `engage/*` | A 5v5 with 전탄 발사 · 오버클럭 · 불굴 runs to the end and damage flows |
| `phase_b/*` | Kill → [단계 C] into the deck, none → [단계 A] |
| `boon/alpha` · `boon/gamma` | The reservation is applied and used **only once** |
| `gust/return` | Leaps in and returns to the original cell at phase end |
| `guardian/*` | The ride-along attack actually lands, and **doesn't land without a shield** |
| `ai/*` | Filters out cost -1 cards, filters out out-of-range attack cards, and scores in-range ones |


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Mech skills | **A unique ability and a unique card set attached to one machine.** If a pilot skill is a move attached to the player, this is what the machine that player rides does, so **the moment a machine is picked in ban/pick, half of that pilot's deck and one permanent ability are decided along with it**. The tables are `data/csv/mech_passives.csv` (**15 rows**) and `data/csv/mech_cards.csv` (**64 rows**), paired by `mechs.id` — there's no pointer column like `players.skill_id` because one machine wholly owns its one passive and its card set. **There are 21 mechs** (ADC 5 · Fighter 4 · Tank 3 · Support 5 · Assassin 4), of which only 15 have passives. **Deck composition changed** — the old "draw 3 from the shared mech card pool" is gone, and the assigned machine's card list spread out `count` times fills that space entirely (machines bring different numbers of cards, so **deck size itself is part of choosing a machine**). Its fallback (`MECH_CARDS_PER_PILOT` — the 3 "공용 메크 카드" (shared mech cards) in cards.csv) **was deleted too** — with all the mech rows in cards.csv now being pilot cards, a standalone-run deck with no machine gets only pilot cards. Mech card descriptions dropped their keyword prefixes ("소멸." (Exhaust.) · "충전. …" (Charge. …)), and the internal counters of passives · cards are **tokens (토큰)** on screen. Passive modifiers are exported **only via query functions**, and the calculation stays where it always was (`BattleSim.refresh_growth_stats` / `SimulationCore._pilot_hit_damage` / `CardPhaseManager._apply_attack_damage`) — because pushing stats directly would be wiped by a single growth recalculation; permanent increases live separately in `PilotData.bonus_atk_flat` / `bonus_atk_mult` / `bonus_max_hp`. **Mechs gained a `role` column** — because card sets came to presuppose a role class, but **assignment is still free** (any machine can sit in any role slot — it's for classification and data validation). **Everything is wired up to the engage stage** — 전탄 발사 (each attack hits up to `MECH_BARRAGE_MAX_TARGETS` presence-weighted random enemies at `MECH_BARRAGE_DMG_MULT` × attack) · 오버클럭 (one more hit right after damage) · 불굴 (whole team, one death prevention each) · 약자 멸시 (**before round 1**, hit the lowest-HP enemy at `ENGAGE_CONTEMPT_DMG_MULT` of attack as many times as the Charge count) · 강타/stun (the hit enemy loses its next turn) actually apply in `TurnEngageSim`, and all five go through `MechSkillSystem`'s query functions. **수호 연계** (when an ally wearing this mech's shield hits, the mech piles on) is rolled in battlefield auto-combat **after application finishes, not at judgement** (`SimulationCore._flush_guardian_rides`) — hitting immediately at the judgement stage would let the ride-along hit drop the opponent before damage not yet applied, so the rest of that turn's judgements would run against a corpse. **The Phase A→B→C chain** and the 3 boons are in place too — see the "Phase A → B → C chain" section above. The list of 21 machines · keywords · clause grammar · code-side conventions are all in the sections above in this README. |
