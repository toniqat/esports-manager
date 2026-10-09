# Resources

Shared data definitions used across features.

**Display text is l10n keys** (`ui` · `term` · `keyword` domains). Shared vocabulary helpers live here —
`GameEnums.position_label` / `role_position_label` / `phase_label` / `rarity_label` / `star_label` / `rank_label` / `tags_text`,
`PlayerData.stat_label` / `stat_note`, `OutgameTheme.role_name` / `day_letter` / `day_name`,
`CardData.category_label(cat)`; the label tables (`POSITION_LABELS`, `PHASE_LABELS`, `STAT_*`, `ROLE_NAMES`,
`DAY_*`, `CATEGORY_LABELS`, …) hold `L.` keys, so **never print a table value directly** — call the helper.
Full list: `docs/localization_design.md` §0.7.

## Files

### CardData.gd
`class_name CardData`, extends `Resource`.

One row from the `cards` SQLite table, plus a few runtime fields:
- `card_name: String`
- `cost: int` — operation points (작전 점수) cost
- `uses: int` — max plays per match (0 = unlimited)
- `cast_method: String` — `range / target / location / instant`
- `target: String` — `caster / enemy / ally / pilot / hand / location`
- `cast_range: int` — tiles from caster (0 = self, 99 = unbounded)
- `area: int` — AoE radius around target (0 = single)
- `card_id: int` — cards.csv row id (mech cards use -1). Fixed pilot cards
  (`PlayerData.pilot_cards`) point at a card by this value.
- `keyword: String` — `|` list (`exhaust` 소멸 / `preserve` 보존 (keep) / `volatile`
  휘발성 / `charge` 충전 (Charge) / `reposition` 재배치; `preserve` and `volatile` never together — Rebuild game.db
  refuses the row). Read it only through `has_keyword()`; the
  on-screen name and explanation come from `keyword_label()` / `keyword_note()` (`KEYWORD_LABELS` /
  `KEYWORD_NOTES` = l10n key tables `L.KEYWORD_*`; Charge uses `keyword.charge.label` / `.note` with `{max}`). **Charge is the keyword; what Charge accumulates is tokens** (the `charge` field)
- `SPECIAL_LABELS` / `SPECIAL_NOTES` — special keyword id → name / note l10n key (`[term]` in descriptions):
  track 추적 · reactive_armor 반응 장갑 · target 목표 (Mark) · bounty 현상금 · stun 기절 · vulnerable 취약.
  `special_note(sp, params)` = the note text; numbers in notes are const.csv placeholders, or effect values the
  caller passes (`CardDescBox.special_note_params`: [목표] reads `{mark_target}` from [단계 A]).
- **l10n (text is keys — `Loc.t`)**: `name_key` / `description_key` (@export) hold the keys;
  `card_name` / `description` are computed properties (`Loc.t(key)`; `description` passes `effect_params()`
  so the text names effect values instead of repeating numbers (D20): clause `op:v|mod:w` → `{op}`, `{op_mod}`,
  `{mod}` (first wins), plus `{<name>_abs}` for numbers; a hand-built card without keys
  shows the text given to `_init`). `from_def` (cards.csv) / `from_mech_def` (mech_cards.csv — always use
  it for mech rows; an upgraded "+" row keeps its base card's `mech_card_id` via the def's `base_id`, §15 A).
  **Identity is never the name** (D3): `card_uid()` = `pilot:<id>` / `mech:<id>`
  (hand-built: `effect:<effect>`) — art (`CardImages`) and effect sources (`PilotData.fx_src` ·
  `persistent_fx`) use it, `name_of_uid(uid)` shows it. `[x]` in a description:
  `ref_entries(description_key)` → `[{key, text, special, card}]` from `Loc.refs` (D4), `ref_for(term, refs, i)`
  picks the entry for the i-th `[term]` (same text first, else same position), `by_name_key(key)` → CardData.
- `effect: String` — semicolon-chain dispatched by `CardPhaseManager`
  (e.g. `"draw:N;discard:N"`, `"attack:N|pierce"`)
- `description: String` — printed verbatim on the **description plate under the art** on the card face (font size shrinks only when it overflows — `Card._fit_desc_font_size`); the same sentence also appears in the description box at the top of the screen
- `scope: String` — **position list**. `any` alone = all, `lane` alone = top ·
  mid · carry · support, otherwise a `|` list of `jungle` / `top` / `mid` / `carry` / `support`.
  `positions_of(scope)` expands it (if only unknown tokens, all positions),
  `allowed_for_position(pos)` checks it, and `scope_label(scope)` turns it into readable text
  like "탑 · 미드 · 원딜" (Top · Mid · Carry) — names via `GameEnums.position_label`, all five = `term.position.all`.
- `pool: int` — `1` = pilot card candidate, `0` = excluded (duel · objective reward · skill-generated cards).
- `card_type: String` — every row in cards.csv is `pilot`. `mech` is stamped by `make_mech_card`
  only on `mech_cards.csv` rows.
- `card_cat: String` — **category `|` list** (`CAT_*`: growth / engage / ambush /
  attack / defense / utility / draw / jungle / lane; grant-only `-`). `categories()` /
  `fits_any_category(cats)` / `categories_text()` ("성장 · 뽑기"); one id → `static category_label(cat)`
  (`CATEGORY_LABELS` holds `term.card_cat.*` keys). Cells in the position slot table pick
  candidates by this value.
- `charge_max: int` / `charge: int` — Charge cap / current token count. `shows_tokens()`
  answers whether to show the badge on the card face (Charge cards + 골드러시 (Gold Rush) with a `token:N` clause).
- `free_this_phase: bool` (runtime) — [신중한 예산] (Careful Budget)'s "free during this operation phase (작전 단계)".
- `owner_pilot: PilotData` (runtime, **not** `@export`) — the caster (시전자), set
  by `CardPhaseManager.build_starter_decks()`

Instantiated at runtime by `CardPhaseManager.build_starter_decks()` from the
`cards` SQLite table (loaded into `GameManager.card_pool_bs`). Not saved to disk.

### GameEnums.gd
`class_name GameEnums`, extends `RefCounted`.

Shared enum definitions:
- `Role { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }` — pilot/player position
- `LanePosition { LEFT, CENTER, RIGHT, GUERRILLA }` — battle-lane slot
- `Lane { LEFT, CENTER, RIGHT }` — waypoint/building lanes (no GUERRILLA)
- `BattlePhase { GAMBIT, CARD_PHASE, BATTLE, ENGAGE }` — in-battle phase
  machine. **`GAMBIT` is not an empty phase** — the battlefield (전장) is fully set up while it sits
  here asking for the jungle start (정글 시작) direction (`battle_sim/gambit/JungleStartOverlay.gd`)
- `TowerLevel { HQ, LEVEL_2, LEVEL_1 }` — building atlas selector
- `MatchPhase { LOAD, PREP, BAN_PICK, ASSIGN, JUNGLE_START, LAUNCH }` — out-of-battle
  pipeline. **`ASSIGN` and `JUNGLE_START` are no longer passed through** — mech assignment moved
  into the ban/pick screen (`ban_pick/BanPickController._enter_assign_mode`), and the jungle start
  direction moved into BattleSim (`battle_sim/gambit/JungleStartOverlay.gd`).
  Both enum values only hold their slots for save compatibility
- `JungleStartDir { LEFT, RIGHT }` — assassin's jungle entry side
- `DraftSide { BLUE, RED }` — ban/pick draft sides
- **Position keys** `POS_TOP` / `POS_JUNGLE` / `POS_MID` / `POS_CARRY` / `POS_SUPPORT`
  (`"top"` …), `POSITION_KEYS` (lane order), `LANE_POSITIONS` (the four of `scope = lane`),
  `POSITION_LABELS` (l10n keys `term.position.*` — read via `position_label(pos_key)` / `role_position_label(role)`),
  `POSITION_ABBREVS` (`TOP` · `JGL` · `MID` · `ADC` · `SUP` — the `PositionBadge` text, not localized), `position_key(role)` — the strings used by card `scope` and
  `pilot_card_slots.position` (they are values humans type directly into CSV, so they are not enum values)
- **Label helpers (l10n)**: `PHASE_LABELS` + `phase_label(phase)` — the one season-phase name table
  (`term.phase.*`; "—" for unknown; `L.TERM_PHASE_INTL` = generic "국제대회"), `RARITY_LABELS` +
  `rarity_label(tier 0..4)` (일반 · 고급 · 희귀 · 영웅 · 전설, `term.rarity.*` — **traits / quirks only**),
  `star_label(stars)` (pilot stars "★n", `term.star.n`; "" for 0) · `rank_label(rank)` ("랭크 n", `term.rank.n`), `TAG_LABELS` + `tag_label(id)` /
  `tags_text(raw)` — the `pilot_skills` / `mech_passives` `keyword` column (`|`-joined ascii tag ids →
  "교전, 전략 점수", joined with `ui.list_separator`)

**Besides the enums there is one more table — `ROLE_DISPLAY_ORDER`.**
```gdscript
const ROLE_DISPLAY_ORDER: Array = [Role.TANK, Role.ASSASSIN, Role.FIGHTER, Role.SNIPER, Role.SUPPORT]
static func role_seat(role: int) -> int   # role → screen seat 0..4
```
The order in which five pilots (파일럿) are laid out on screen — **top · jungle · mid · carry · support** — which
is also the order you get scanning the battlefield left to right (LEFT · GUERRILLA · CENTER · RIGHT · RIGHT).
Using the `Role` enum order as-is would seat the jungler third and the carry fifth, an arrangement
that matches neither the lineup the player knows nor the map.

**In-game and outgame both read this one table** — battlefield pilot strips (스트립)
(`HudBuilder._lane_seat_less`), both team blocks on the ban/pick screen, the season hub roster, the training
grid and training results, the pre-match dashboard, and the draft slots (`TeamDraft.SLOT_ROLES` is now
this constant itself). Previously every screen carried its own order, so **the same five people sat in
different seats on different screens**, and the battlefield strip sorted by `PilotData.lane`, leaving the
front/back order of the two right-lane pilots (sniper · supporter) to the instability of `sort_custom`.

### PilotData.gd
`class_name PilotData`, extends `RefCounted`.

In-battle pilot state: role, hp/max_hp, atk, team, grid_pos, lane, waypoint_idx,
`move_range` (cells per minute), `jungle_start_pref` (GameEnums.JungleStartDir
or -1), `jungle_start_cell` (the jungle start cell chosen before the opening (개시) — the jungler's
first target until reached, (-1,-1) = none), plus **two sets of hit (명중) stats** and **two growth-coefficient multipliers**, all from
PlayerData: `hit` / `evasion` ← `field_hit` / `field_eva` (battlefield), `engage_hit` /
`engage_eva` ← same names (engage (교전) stage (무대)), `atk_growth_mult` / `hp_growth_mult` ←
`PlayerData.growth_mult(atk_growth / hp_growth)`.

`PilotData.hit_chance(hit, eva, range_mult = 1.0)` is **the hit formula shared by both
stages** — it maps the ratio `hit/(hit+eva)` linearly onto `HIT_MIN` ~ `HIT_MAX` (const.csv
`PILOT_HIT_MIN` / `PILOT_HIT_MAX`), so equal stats land at the midpoint of that band. Stats have no cap, so using the ratio directly as a probability would
produce matches where one side can't hit anything once the gap widens. `range_mult` is a slot for a
distance coefficient and is currently always 1.0 (the battlefield only has same-cell fights, so there is no distance).

`presence` is copied from the assigned mech (메크) and is **read only by the engage stage**
(`TurnEngageSim`) as the target aggro weight. The battlefield ignores it.
Fallback when no mech is assigned (standalone battle): a fixed melee / ranged default set in code (melee higher).

> **`speed` has been deleted.** Since engage changed from ATB real-time to **round-based turns**,
> everyone acts exactly once per round (라운드), so no stat deciding "action frequency"
> exists. The `mechs.csv` column · `MechData.speed` · `PilotData.speed` ·
> `game_config.TURRET_SPEED` were all removed — do not bring them back.

`respawn_timer: int` is the off-field clock and **death is the only thing that
puts a pilot off the field**. It counts down from `BattleSim.respawn_turns_now()`
in `SimulationCore.process_respawns` while `alive = false`. **Never read it
directly to show "turns left"** — call `BattleSim.turns_until_return(p)`, which
also floors the answer at 1 for a downed pilot so a card doesn't flicker
unlocked on the tick before the return.

`recall_hold: bool` is the return-to-base (본진 복귀) cost. A recall (`RecallSystem.return_to_hq`)
lands the pilot in its HQ at full HP **without touching `alive`** — it is in
play the whole time — and sets this flag; `SimulationCore.resolve_movement`
spends it to skip the pilot for exactly one movement pass, so the lane walk
restarts from waypoint 0 the next turn. Nothing else reads it. (The former
model — off the field, healing `RECALL_HEAL_RATIO` per turn until full — and its
`is_recalling` flag are both gone.)

**8 growth (성장) fields** — `base_atk` / `base_max_hp` / `growth` / `growth_hp` /
`atk_buff` / `growth_rate_mult` / `growth_rate_expire_turn` / `growth_until_phase`.

**Growth comes from growth points (성장치, `score`), not time.** Previously
`SimulationCore.tick_growth_and_expiries` accumulated `GROWTH_PER_TURN` every turn, which meant
(1) pilots grew even doing nothing, so kills · turrets · farming had no effect on growth, and
(2) `atk` and `max_hp` grew at **the same rate**, so "how many hits until death" never
changed. `GROWTH_PER_TURN` was deleted from game_config.

Now `BattleSim.refresh_growth_stats` derives both from growth points —
`growth` = attack share, `growth_hp` = max-HP share, both from one curve
`BattleSim.growth_curve(score, is_hp)` (piecewise log + spikes, `GROWTH_*` keys in const.csv) × the growth coefficient.
Attack and HP currently share the same curve constants (`GROWTH_ATK_CURVE` = `GROWTH_HP_CURVE`), so
the two diverge only through the pilot's growth coefficients; tune the `GROWTH_*` pairs together. Instead of multiplying each turn, stats are **recomputed** from the two originals (prevents
rounding-error accumulation). `_init` fills the two originals — mech stat injection
(`SimulationCore._stats_for`) goes through the constructor, so they are never empty on any spawn
path. The recompute runs the moment the score moves (`add_score`).

`atk_buff` is a **temporary** attack bonus applied by cards. Pushing `atk` directly would get wiped by
a mid-turn recompute and the end-of-turn revert would eat into the original, so it is held in a
separate field and added last: `base × (1 + growth) + atk_buff`.

`growth_rate_mult` now multiplies **growth-point accrual** rather than growth (expires at the
end of the safe-farming turn / at the end of the perfect-finish operation phase) — same result, one less layer of wiring.
Both share the same field, so whichever is applied later overwrites.

**Growth points `score`** (opening `SCORE_START`) — the **source** of the growth above. It is the pilot's growth currency,
equivalent to gold in a MOBA. Sources:
**front line (전선) presence** (`SCORE_FRONTLINE_PER_TURN`) / **jungle camp (캠프)** (`BattleSim.jungle_camp_score()`,
respawn `JUNGLE_CAMP_RESPAWN_TURNS`, jungler) / **kill (처치)** (fixed `BattleSim.kill_reward()` split by damage share +
the last hit's bounty `SCORE_KILL_BOUNTY_RATE` of the lead gap) / turret (포탑) damage (`SCORE_TURRET_FULL` per turret).
**HQ damage and death penalties were deleted.** No cap,
floor `SCORE_MIN`. All of these keys live in const.csv.
Shown on the pilot strip in `18.05k` format; team score is the sum of its members. All rules
live in the `SCORE_*` section of `BattleSim` (values from const.csv), and every change passes through `BattleSim.add_score` alone —
so that the floor · accrual multiplier · stat recompute are handled in one place only.

**`damage_credit: Dictionary`** (`attacker → cumulative damage received this life`) — damage does not
become score immediately; it accumulates in **the victim's ledger**, and when that target falls
`BattleSim._payout_kill_bounty` splits it between the last hit and assists, then clears it.
Battlefield auto-combat · attack cards · the engage stage all pass through the single point
`BattleSim.record_pilot_damage`, so there is one table.

**2 laning stats** — `lane_stat_mod` (signed ratio, e.g. skill keys `SKILL_HOLD_LANE_STAT` / `SKILL_BACKBONE_LANE_STAT`) / `lane_stat_expire_turn`.
Read **only in `SimulationCore.roll_hit`**: the attacker's `hit` and the defender's
`evasion` are each multiplied by their own multiplier (`lane_adjusted`). `atk` / `max_hp` are
not touched — those belong to growth. Battlefield auto-combat and attack cards use the same
`roll_hit`, so both reflect it; the engage stage uses its own probability band, so it
does not.

**Card evasion multiplier** — `eva_card_mod` / `eva_card_expire_turn` ([소극적인 태세] (Passive Stance) — the amount is that card's `effect` clause in cards.csv).
Unlike the laning stat it multiplies **evasion only** (the defender side of `roll_hit`). Expiry is in
`SimulationCore.tick_growth_and_expiries`.

**Ambush** — `ambush_hold: bool`. Until that team's next operation-phase entry settlement, the movement pass
(`resolve_movement`) and out-of-position recall (`RecallSystem`) skip that pilot. Death ·
return-to-base · return cards · retreat cards also release it.

**Permanent multiplier bonuses** — `bonus_atk_mult` (Soul Harvest · [몰입] (Immersion) · [워밍업] (Warm-up)) and
`bonus_max_hp_mult` ([워밍업]). `refresh_growth_stats` multiplies them into growth attack · growth HP.
`FX_ATK_PCT` / `FX_HP_PCT` were added to the persistent-effect ledger kinds (the detail panel prints them as %).

**`prev_grid_pos: Vector2i` has been deleted.** Its only consumer was
`BattleRenderer._pilot_travel_dir` (the rule that seated the portrait (초상화) "opposite the direction it came from"),
and once the portrait position became **team-fixed** (bottom side = below the tile / top side = above the tile)
nobody read it any more. The update wiring (`anim_pilot_move` /
`anim_pilot_move_path` / return / respawn, 4 places) was removed too — if it is ever needed again, see
commit 64bec06. Do not confuse it with `anim_move_path` below: that one is a presentation path
and the renderer clears it as soon as it reads it.

`anim_move_path: Array[Vector2i]` is **the path of cells actually stepped on this time**
(`[start cell, …, end cell]`). `SimulationCore.resolve_movement` appends a cell each lockstep
round (`move_range` 2), and for advance cards `BattleSim.anim_pilot_move` appends that frame's steps.
`BattleRenderer._sync_glide` calls `clear()` as soon as it reads it, so the next turn's movement starts a
new path from an empty array.
**Presentation timing does not live here** — the timer is held by the renderer (`_glide`), and the former
`anim_prev_grid_pos` / `anim_move_t` / `anim_move_dur` were deleted.

`jungle_roam_target: Vector2i` ((-1,-1) = none) is the jungler's sticky roam
destination, held across turns by `SimulationCore._jungle_goal_for` so the
target cannot flip mid-route and bounce the jungler between two cells. Only
that function writes it; nothing else on `PilotData` reads it.

`shield: int` is the shield (보호막) pool granted by the 보호 (Protect) card. Both card attacks
and battlefield damage (the `damage_map` apply step in `SimulationCore.simulate_turn`)
subtract from `shield` first, then `hp`. Cleared on every return-to-base path:
`RecallSystem.return_to_hq` (low-HP / out-of-position return),
`CardPhaseManager._effect_recall_ally` (복귀 (Return to Base) card),
`SimulationCore.process_respawns` (respawn) and
`BattleSim.mark_pilot_dead` (death).
`BattleRenderer._draw_pilot_circle` paints a cyan ring just outside the HP ring
sized by `shield / max_hp` so the buff is visible on the field.

UI animation fields (`anim_move_path`, `anim_shake_t/dur/amp`,
`anim_recall_phase/t/dur/orig`, `anim_death_phase/t/dur/cell`) are mutated by
`BattleSim.anim_pilot_*` helpers and read only by `BattleRenderer` — the
simulation never reads them. The recall sequence always plays both halves
(fade-out at the old cell → fade-in at HQ), since a return-to-base never removes the pilot
from the field; the `anim_death_*` group is what keeps a killed pilot on screen
(dimmed, then fading upward) after `alive` has already flipped to false.

### TurretData.gd
In-battle turret state — see `features/battle_sim/README.md`.

`anim_hit_t` / `anim_hit_dur` are the on-hit presentation timer, set by
`BattleSim.anim_turret_hit` and consumed by `BattleSim._advance_turret_animations`.
Like the `PilotData.anim_*` group the simulation never reads them, but the
consumer differs: the shake/flash is written onto the turret's `Building` node
(BattleSim owns that), and only the HP-bar offset goes through `BattleRenderer`
via `BattleSim.turret_hit_offset(td)`.

### PlayerData.gd
`class_name PlayerData`, extends `Resource`.

Out-game player persona consumed by MatchFlow / BattleSim:
- `id, name_key, role (GameEnums.Role), team_id (0=player, 1=enemy)` — **`name_key`** is the l10n key
  (`players.name_key` / `intl_players.name_key`, aliases `name.player.{id}` / `name.intl_player.{id}`) and the
  only name that is stored / saved (D7). **`name`** is a read-only getter = `Loc.t(name_key)` (current locale), so
  display sites keep reading `pd.name`; never assign it. The constructor's 2nd argument is the key.
- `pilot_cards: Array` — **3 fixed pilot cards** (`cards.id`, `players.pilot_cards`). Saved with the save file; if empty (old save), `GameManager.pilot_card_ids_for` fills it from the DB row with the same id → then a seeded draw, in that order.
- **6 player (선수) stats** — `field_hit` battlefield hit / `field_eva` battlefield evasion /
  `engage_hit` engage hit / `engage_eva` engage evasion / `atk_growth` attack growth coefficient /
  `hp_growth` HP growth coefficient. **Floor `STAT_MIN` (const.csv `PLAYER_STAT_MIN`), no cap** (weekly training pushes them past 100).
  The tables are the three `STAT_KEYS` / `STAT_LABELS` / `STAT_NOTES` (the last two hold
  l10n keys `term.stat.*.name|note`), and every screen reads them — text through
  `stat_label(i)` / `stat_note(i)` (current locale, "" out of range). **No short forms** ("전명" →
  "전장 명중" everywhere; `stat_short` and `term.stat.*.short` were removed / deprecated 2026-10). Power totals are `stat_total()` / `stat_avg()`; growth coefficient → multiplier conversion is
  `static growth_mult(v)` = `v / GROWTH_STAT_BASE` (const.csv `PLAYER_GROWTH_STAT_BASE`). The old 5 stats (`laning` /
  `mechanics` / `gamesense` / `teamfight` / `mental`) were deleted
- Run setup fields: `salary` (base salary + applied rank effects; level bonus added on read by
  `RunRules.salary_of`), `rarity` (= **stars** ★1..★3, mobs 0), `level` (0..; stats already include the
  level bonus), **`rank`** (0..5 — rank rows already folded into the stats / salary / pilot cards; 0 = CSV
  base), `train_bonus_pct` (rank-row `stat_growth`). `breakthrough` is a deprecated get/set alias of `rank`
  (old saves / readers).
- `assigned_mech: MechData` — written by the assignment step of the ban/pick screen (`ban_pick/BanPickController._finish`). Previously this was the job of `AssignController`, which was a separate screen

Loaded from the `players` table (CSV-seeded via `addons/csv_to_db`).

### RunRules.gd
`class_name RunRules extends RefCounted` (static, tables cached on first use) — run setup rules shared by the
run setup screens and `GameManager.start_run` (so "what the screen allows" and "what start refuses" never
split): scenarios / salary cap, team packages, **pilot rank + level**, lineup validation.
- **Stars · rank · level** (product rules, `features/meta/collection/` shows them):
  stars ★1..★3 = `players.rarity`, never change. Rank 1..`rank_max()` (`RANK_MAX`); acquired at rank = stars.
  Breakthrough (profile, from dupes) only raises the max rank = stars + breakthrough (cap RANK_MAX − stars).
  Level 0..`level_cap(rank)` (= `RANK_LEVEL_CAP_PER_RANK` × rank). At the cap, `rank_up_cost(rank + 1)` rank
  stones (`RANK_UP_STONE_R2..R5`, currency `rank_stone` 승급석) raise the rank by one and reset level + EXP to 0.
- `rank_rows(pid)` → `[{rank, stage (= rank), kind, value}]` (`pilot_ranks.csv`, several rows per rank
  possible). `apply_rank(pd, rank)` raises a copy from `pd.rank` to `rank`, applying each row once
  (`stat_flat` / `salary_down` / `stat_growth` / `card_swap`) plus `RANK_SALARY_STEP` salary per rank above the
  stars; `apply_ranks(pool, {"<pid>": rank})`, `apply_base_ranks(pool)` (every named pilot at its stars).
- Levels (`pilot_levels.csv`, Lv0..`max_level()` = 50): `stat_bonus_at(lv)` / `salary_bonus_at(lv)` (absolute
  over Lv0), `levelup_cost(lv)` (levelup currency for lv−1 → lv), **`exp_required(lv)` = cumulative EXP from
  Lv0 inside one rank** (`exp_required(0)` = 0; the profile EXP restarts at 0 on every rank-up),
  `level_for_exp(exp)`. `apply_level(pd, lv)` (0 ok, idempotent, stat delta vs `pd.level`),
  `apply_levels(pool, levels)`. `salary_of(pd)` = `pd.salary` + level bonus.
- `apply_progress(pool, ranks, levels)` = `apply_base_ranks` → `apply_ranks` → `apply_levels` — the one
  sequence the run setup pool (`RunSetupScreen`, `TeamDraftView` preview) and `GameManager.start_run` use.
- `lineup_salary(pilots)` (copies at their level) · `validate_lineup(pilot_ids, scenario_id, pool, owned,
  cap_bonus)` — five picks, all in `pool` and `owned` (keys), one per role, salary ≤ cap (+ trait bonus). There is
  **no level argument**: pilots enter a run at their collection rank + level, the cap constrains the combination.
- Deprecated aliases (old callers): `breakthrough_max` · `breakthrough_rows` · `apply_breakthrough`.

### MechData.gd
`class_name MechData`, extends `Resource`.

Mech with **no role/position** — any mech is assignable to any player slot:
- `id, name_key` (l10n key `name.mech.{id}`, `mechs.name_key`; constructor 2nd argument) — **`name`** is a
  read-only getter `Loc.t(name_key)`
- Combat stats `hp, atk` — drive PilotData stats when piloted
- `presence` (melee higher than ranged; values in mechs.csv) — **engage stage only**. Target aggro weight
  (higher = targeted more often)

> **`speed` has been deleted** — once engage became round-based turns, the concept of action frequency
> disappeared. It was also removed from the `mechs.csv` columns and the `csv_to_db.gd` schema, so
> reviving it means reverting the CSV column · schema · `GameManager` loader · `_stats_for`
> together.

Loaded from the `mechs` table.

### BuildingData.gd / WaypointData.gd
Optional inspector-set blueprint resources for `Building` / `Waypoint` nodes
under `BattleField/BuildingLayer` and `BattleField/WaypointLayer`.

### PilotImages.gd
`class_name PilotImages`, extends `RefCounted`. Static lookup for the pilot
portraits under `resources/images/pilot/{faces,circle,eye,tall,full,ribbon,strip}/`, plus the
**mob silhouette (모브 실루엣)** set that mirrors them under `pilot/mob/`.

| Function | File | Size | Consumer |
|---|---|---|---|
| `face_for` | `faces/N_rect.png` | 256² | Draft grid thumbnail (`meta/run_setup/PilotThumb.gd`) |
| `circle_for` | `circle/N_circle.png` | 256² circular | Battlefield marker · engage stage portrait |
| `eye_for` | `eye/N_eye.png` | **480×200** | Kill log · training grid · ban/pick (the battlefield pilot strip now uses `strip_for`) |
| `strip_for` | `strip/N_strip.png` | **256×320** (`STRIP_ASPECT` 0.8, transparent background) | Battlefield pilot strip circular portrait (`ui/PilotStrip.gd`) — baked by `make_strip_crops.py`, circle masking by `shaders/pilot_bust_mask.gdshader` |
| `tall_for` | `tall/N_tall.png` | **210×700** | Engage arena bottom strip (`engage/EngageArena.gd`) |
| `bust_for` | **upper part** of `tall/` as `AtlasTexture` | 174×351 (`BUST_ASPECT` 0.496) | Draft pick 5-person slots · ally pilot slots in the ban/pick **assignment step** |
| `full_for` | `full/N_full.png` | variable × 1024 | Pilot detail panel (`ui/PilotDetailPanel.gd`) |
| `ribbon_for` | `ribbon/N_ribbon.png` | **120×136** (2× the card unit 60×68) | Top-right triangular ribbon (리본) on hand (손패) cards (`card_phase/Card.gd`) |

**Do not make `ribbon/` by hand either** — `make_ribbon_crops.py` bakes it from `full/` with the same
template matching as eye. The right-triangle mask · card rounded corner ·
shadow under the hypotenuse · backing colour for transparent areas are all in the PNG (to avoid a
runtime mask shader), so for mobs the same crop is baked once more from the `mob/full/` silhouettes
(`mob/ribbon/`). The geometry is tied to `Card.RIBBON_LEG` / `RIBBON_SHADOW_PAD`.

**`bust_for` is a crop, not a file** — it cuts the upper part of the `tall` cut (210×700, head~thigh)
as an `AtlasTexture`, so no extra copy of the source is baked.
The point is not cropping directly from `full`: in full, figure scale differs per pilot, so
face sizes across the five slots would be uneven, whereas `tall` is a cut whose scale was already unified by
finding the face rectangle via template matching. **Two screens read this one function**
(draft pick slots / ban/pick assignment step) — if each held its own `Rect2`, fixing only one
would make face sizes diverge between the screens. The slot aspect must be `BUST_ASPECT`.

**Do not crop `eye/` by hand** — `resources/images/pilot/make_eye_crops.py`
generates it automatically from the `full/` art. Rather than guessing the face position, it re-finds `faces/N_rect.png`
inside `full/` with **multi-scale template matching** (measured (실측) correlation 0.84~0.99),
takes the point at 0.38 of that rectangle's height as the eye centre, and cuts a 2.4:1 band. Cropping by
hand would misalign face scale per pilot and make the strip uneven. **One exception**:
for pid 16, `faces/16_rect.png` is a **different illustration** from `full/16_full.png` (different
costume · pose), so matching drops to 0.554 and mismatches onto a weapon part — the eye coordinates are
hard-coded in the script's `OVERRIDE`.

**Do not crop `tall/` by hand either** — `make_tall_crops.py` makes it from `full/` with the same face template
matching (same single `OVERRIDE` exception). The composition is **head~thigh**:
it leaves a margin of `TOP_PAD` (face height ×0.30) above the face rectangle and cuts a vertical band
going down `BUST_H` (×4.40), with width set to **face height × `BAND_W_FACES`
1.32** (`ASPECT` is the 0.30 derived from those two).

**Keep the band width (face height ×1.32) a fixed constant and only adjust the length.** The strip slot width is
fixed at 90px, so this value is the on-screen face size — if you widen the width along with
`BUST_H`, faces get smaller and become unreadable in the strip. The current value was
**increased from 2.40 (head~chest, 220×400) to 4.40** to fill the 556px that sat empty below the strip on a
1920-tall screen, and the on-screen slot grew from 90×164 → **90×300** at the same time.
The two are tied by `STRIP_PORTRAIT_H = 90 × BUST_H / 1.32`, so always change them together.
Fitting the width to the shoulder silhouette makes the figure size differ per pilot — fixing the output aspect
is what keeps face sizes even when ten people stand in one row.

`prime_into(parent)` primes **circle / face / tall**. eye / full are
used only on `TextureRect` nodes, and assigning to a node guarantees GPU upload, so they are not
targets, but **tall is drawn with `draw_texture_rect`, so priming is mandatory** —
skip it and all ten portrait slots of the engage strip come out as white rectangles (measured, confirmed).

**id ↔ file ↔ name are bound in one line.** Pilot id `N` in `players.csv` uses
`N+1_rect.png` / `N+1_circle.png` (filenames are 1-based, ids are 0-based),
and **which Zenless Zone Zero agent** that picture is, is exactly the `name` in `players.csv`
— all 40 names were assigned by matching 1:1 against the official agent icon art.
Therefore **changing the row order or ids in `players.csv` misaligns names and portraits.**
If you want to move stats, keep the id fixed and move only the stat columns.

Four slots are **alternate-costume art** of the same character, so the original name could not be used and a separate tag
was attached — id 6 `Soldier 0` (Soldier 0 - Anby, a separate agent of the same person as id 13 `Anby`),
id 26 `Chandelier` (Astra Yao / Chandelier, id 25 `Astra`),
id 28 `Teatime` (Sunna / Afternoon Tea Break, id 27 `Sunna`),
id 36 `Ink` (Yixuan / Trails of Ink, id 35 `Yixuan`).

INTL pilots (id ≥ 100) have no portrait — `has_image()` returns false and the
caller substitutes a placeholder. So the names in `intl_players.csv` were picked **from the remaining
agents** without portrait constraints.

#### Mob pilot silhouettes (`pilot/mob/`)
There are only 25 entries in `pilot_skills.csv`, so **15 of the 40 have no unique skill**
(`is_mob = 1` in `players.csv`). For those 15, it is the **picture**, not a name tag, that says "this player
is a nameless player" — the five cuts each have a full extra silhouette set, and once
`GameManager.load_match_data()` plants the id list via `PilotImages.set_mob_ids()`, every subsequent lookup
(battlefield marker · strip · engage stage · detail panel) automatically switches to
`pilot/mob/{faces,circle,eye,tall,full}/`. Filenames match the originals.
If the list is empty (BattleSim run standalone) everyone shows the normal cuts — the fallback is the
original, so forgetting to plant it does not produce white rectangles.

**`make_mob_silhouettes.py` makes them**, and for all five cuts it **leaves alpha untouched and
covers RGB with a single colour (`38,42,60`)** — if the face is even slightly readable, it is not a silhouette.

The problem is that **`faces` / `circle` / `eye` are crops where the face fills the frame**.
Their alpha is effectively a solid rectangle (measured: **97.7%** of the eye band is opaque), so painting
in place with a single colour yields one black circle · one black bar — the face is hidden, but you can't
even tell it's a person. So those three are made by **re-cropping head~shoulders from the `full`
art**:

| Cut | Method | Window (multiples of face height) |
|---|---|---|
| `full` · `tall` | only paint in place with a single colour | — (alpha is already the figure outline) |
| `faces` · `circle` | bust re-crop from the `full` silhouette | height 3.3 / margin above face 0.62 |
| `eye` | same re-crop (2.4:1 band) | height 3.0 / margin above face 0.55 |

For the re-crops, `full`'s alpha is the figure outline, so **the background stays transparent** and the
head shape and shoulder line read as a silhouette. The face rectangle is found with **the same template
matching** as `make_eye_crops.py` / `make_tall_crops.py` (measured correlation
0.85~0.99, all 15), so figure scale does not diverge between the three scripts. When the window goes outside the
art, it is not pushed inward but **filled with transparency** — pushing it in would seat the figure
at a different spot in the frame per pilot.

**Only `circle` bakes in an opaque circular background (`108,114,132`).** The battlefield marker lays a white
circle behind the portrait (`BattleRenderer._draw_pilot_circle`) while the engage arena lays nothing
(`EngageArena._draw_unit`); left transparent, the same picture would be a white badge on one side and a
hole showing the background on the other.

**Do not revive — the first two versions that only darkened brightness.** (1) The automatic rule "single colour
if the transparent-pixel ratio is ≥ 10%" just produced a black circle, because `circle` is 20.8% transparent
due to the mask corners. (2) The next version pressed the brightness of `circle`/`faces`/`eye` into a dark
band (0.10~0.46), but **as a portrait with only colour removed, facial features still read clearly** — a dark
portrait is not a silhouette. That traded the silhouette away to keep the frame; now it does the reverse,
giving up the frame to keep the silhouette (only mob slots frame the figure smaller than named ones).

Mobs keep their names and stats, but **their stats are lower than named pilots** — that reduction is
not a runtime coefficient but already baked into the `players.csv` values themselves, leaving room to add a difficulty
multiplier later. They are also excluded from the run-setup lineup grid
(`features/meta/run_setup/README.md`).

`prime_into(parent)` must be called once at an entry point such as `BattleSim._ready()`
— otherwise `draw_texture_rect` draws white rectangles.

### SilhouetteFx.gd + `shaders/silhouette.gdshader`

**One kit for overlaying a character silhouette at runtime.** The shader draws it and
`SilhouetteFx` (static-only, `class_name`) attaches it to nodes — if each screen hand-builds
`ShaderMaterial.new()`, the same silhouette becomes a different grey on every screen
(same reason `OutgameTheme` owns colours).

**This is a different thing from the baked mob silhouette PNGs (`images/pilot/mob/`).** Those are assets that
**permanently** say "this player is a nameless player"; this is **a one-off presentation effect**.
That is also why the shader does not replace those PNGs — the `faces` / `circle` / `eye`
cuts have a solid-rectangle alpha (97.7% of the eye band is opaque), so painting them at runtime yields a black
bar, which is why those three are still re-cropped from `full` and baked.

| Parameter | Meaning |
|---|---|
| `fill_color` | Solid fill colour. Default is **the same** (38, 42, 60) as the baked silhouettes |
| `outline_color` / `outline_width` | Border drawn **outside** the outline. Width is in **texture pixels**, so the border gets thicker as the node grows. Room for the border is made by **insetting the art inward by that width** — section below |
| `reveal` | 0 = silhouette, 1 = original as-is (in the spot inset by the border width). So forgetting a material attached does not change the screen |
| `reveal_soft` / `reveal_dir` | Blur width and direction of the peeling edge (default bottom→top) |
| `sweep_color` / `sweep_width` | Light laid on the edge. Turns itself off when `reveal` is 0 or 1 |

There are five APIs — `make_material()` / `apply(ci)` / `set_reveal(ci, v)` /
`play_reveal(ci, dur, delay)` / `clear(ci)`. **Make one material per node**
(if shared, one node's `reveal` tween also peels other nodes using the same material).
If the node is outside the tree, `play_reveal` **turns the original on as-is and backs off** —
a failed effect leaving the figure covered by a silhouette forever is a far worse failure.

**Nothing uses it right now.** The entry cut of the outgame pilot detail popup
(`meta/run_setup/DraftDetailPanel.gd`) was the only consumer, and when that usage was
removed the call site disappeared entirely — the shader and wiring are a tool kept for the next
use, and since `reveal` defaults to 1, just attaching the material leaves the screen showing the original.

#### Make room for the border by insetting the art
All 40 pilot full-body artworks **have the figure touching all four edges** (measured: figure top y = 0,
left/right margin 0). The border is drawn **outside** the outline, but there were no pixels to draw on, so the
border above the head was cut off entirely — that is literally what happened when it was first attached.
Drawing it inside instead eats into the silhouette and thins the shoulder line.

So the shader **keeps the drawn rectangle as-is and draws only the texture shrunk by
`outline_width` inside it** (`pad = TEXTURE_PIXEL_SIZE * outline_width`).
In exchange for retreating 0.5% inward on full-body art, a border stands on all four edges
(measured: the border sits 4px above · 3px left/right · 2px below outside the fill).
**Width 0 means inset 0**, so call sites that don't use a border stay pixel-identical.

#### Three traps to know before touching this shader (all measured)
1. **In the fragment, `COLOR` is already `texture(TEXTURE, UV) × modulate`.**
   Writing `COLOR = col * COLOR` multiplies the original once more into a silhouette that should be flat,
   so facial features read clearly (a pure red fill came out (170,0,0), a navy fill (11,9,13),
   differing per pixel). Assign only.
2. **The `MODULATE` built-in does not exist in this version's canvas_item fragment**
   (`Unknown identifier`). If you need node modulate, carry `COLOR` from `vertex()` via a
   varying.
3. **`TEXTURE` / `TEXTURE_PIXEL_SIZE` cannot be used inside global functions** — that is why the border
   sampling loop is inlined inside `fragment()`.

And always pass edges **in ascending order** (`smoothstep(front - soft, front, p)`).
Calling it reversed is undefined per the GLSL spec, and the whole screen gets an in-between value.

### CardImages.gd
`class_name CardImages`, extends `RefCounted`. **Illustration lookup for a single card** —
same place as `PilotImages` / `MechImages`, and same rules (only this one file knows where
pictures come from; it never calls `load()` blindly but asks
`ResourceLoader.exists()` first).

| Function | File | Consumer |
|---|---|---|
| `art_for(uid)` | `images/card/<uid>.png` (`:` → `_`, e.g. `pilot_12.png`) → item icon → background | `Card._apply_art` (card face art frame), `BattleRenderer` banner, `PilotDetailPanel` fx thumb, `ReservationChips` |
| `item_for(uid)` | `images/ground/deadlock_items/<타입>_<아이템>.png` (type_item; `ITEM_ART` table) | 〃 (cards without dedicated art) |
| `type_for(uid)` | prefix of the `ITEM_ART` value → `TYPE_WEAPON` / `TYPE_SPIRIT` / `TYPE_VITALITY` (`""` = not in table) | `Card._apply_name_plate` (nameplate (이름판) type colour `Card.TYPE_COLORS`) |
| `ground_for(uid)` | `images/ground/N.png` (`GROUND_COUNT` 5 images) | 〃 (cards not even in the `ITEM_ART` table) |

**Keyed by card identity, not name** (l10n D3): `uid` = `CardData.card_uid()` (`pilot:<cards.id>` /
`mech:<mech_cards.id>`); each `ITEM_ART` line ends with a comment naming the card.

**Every card right now (cards.csv 43 + mech_cards.csv 64 = 107) carries an item icon.**
`ITEM_ART` is a card uid → Deadlock item filename table, picking items with similar effects
(e.g. `필중` (Sure Hit) → Sharpshooter, `보호` (Protect) → Grit, `몸집 불리기` (Bulk Up) → Colossus, `캐시` (Cache) →
Golden Goose Egg; effect source https://deadlock.wiki/Items). **Each item is used for only one card.**
**Icon filenames carry a type prefix** — `wpn_` weapon · `spt_` spirit ·
`vit_` vitality (all 173: 56 · 56 · 61). The classification is Weapon /
Spirit / Vitality from https://deadlock.wiki/Items; the 4 not caught by the wiki list (Extended Magazine · Stalker → weapon,
Bullet Lifesteal · Spirit Lifesteal → vitality) were confirmed via the item page categories in the MediaWiki API.
Add the prefix when adding new icons too — `type_for` reads only that.
Icons are 200×200 squares (opaque beige background), so in the 160×184 art slot
`STRETCH_KEEP_ASPECT_COVERED` trims the left/right a little — the emblem is centred, so it is unharmed.
When adding or renaming a card, add it to the table too; if missing, it falls back without error to the 5 backgrounds below.

**The background is picked by card uid** (`uid.hash() % GROUND_COUNT`). Picking at random
would give the same card a different picture each draw so no "this picture = this card" link
forms; picking by sequence would let the order of entering the hand decide the picture, so the same card
would differ per slot. A name hash gives the same answer regardless of run, so even before dedicated art
is filled in, each card keeps carrying its own picture. **Once dedicated art exists, just drop it into
`images/card/` under the card name and it wins** — no code change.

#### Card backgrounds (`resources/images/ground/N.png`)
480×660 (= 3× the card display size 160×220), **same 8:11 aspect as the card**.
The originals were five 1080×1440 (3:4) full-art lands, touched up twice — (1) cut off the bottom 110px
artist name · ⓒ text strip, (2) centre-crop 8:11 from what remains, then
resample to 480×660. The card face art frame is 150×74, so display scale is around 3×,
and even accounting for hover 1.2× and the detail panel, 3× is enough (the 1080-wide originals were 9.5MB for 5 images,
only bloating the pck). The pictures themselves are **wide landscapes** while the frame is close to 2:1, so
`STRETCH_KEEP_ASPECT_COVERED` fills the middle.

### Team base map art (`resources/images/base_map/`)
Twelve area maps for the week screen's team base map (`features/season/week/base_map/`), loaded straight
by the map scenes (no lookup class). **Prototype placeholders (Blue Archive / Nexon art): replace before any
public release.** Sources and naming: `resources/images/base_map/README.md`.

### SkillImages.gd
`class_name SkillImages`, extends `RefCounted`, static only. **Pilot skill and mech
passive icon lookup** — same role as `CardImages` / `MechImages`.

| Function | Source | Used by |
|---|---|---|
| `icon_for(skill_key)` | `images/skill/skill_<English_Name>.png` via `ICON` (`pilot_skills.key` → file) | `ui/PilotDetailPanel.gd` skill block (left of the name, tinted with the name colour), `ui/SkillBadge.gd` (strip badge), `ui/SkillPopup.gd` |
| `mech_icon_for(passive_key)` | same folder via `MECH_ICON` (`mech_passives.key` → file) | `ui/PilotDetailPanel.gd` mech tab passive plate + the passive's lasting-effect thumb |
| `make_icon_tile(skill_key, px, bg, icon_color, shadow_color, shadow_px = 14)` | `icon_for` inside a `px`×`px` rounded-square `Panel` (radius `px*0.22`, fill `bg`, anti-aliased `StyleBoxFlat` soft shadow: `shadow_size = shadow_px`, offset `(0, shadow_px*0.4)`), icon inset 16% per side and tinted via `modulate` | `ui/PilotDetailPanel.gd` skill block, `meta/run_setup/DraftDetailPanel.gd` skill block |
| `make_mech_icon_tile(passive_key, …)` | the same tile around `mech_icon_for` | `ui/PilotDetailPanel.gd` mech tab, `ban_pick/MechDetailPanel.gd`, `ban_pick/BanPickController.gd` sheet |
| `make_texture_tile(tex, …)` | the tile around any glyph (null → empty tile) — the two above call it | — |

`make_icon_tile` is all `MOUSE_FILTER_IGNORE`; an unmapped key still returns the
empty tile. The shadow paints **outside** the rect — leave about `shadow_px` of
room around the tile so a clipping parent doesn't cut it.

`images/skill/` holds **152 Deadlock hero ability icons** (38 heroes × 4), white
glyph on transparent, mostly 137² (Doorman Call Bell + Victor's four 68²,
Rain of Arrows 200²). Source: namu.wiki `분류:Deadlock(게임)/영웅` → each hero
page's 능력 section, webp/png → png. File name = `skill_` + the English ability
name with spaces → `_` (apostrophes / hyphens kept; namu typos fixed:
Dust Devil, Entangling Thorns). 25 are mapped to pilot skills (`ICON`) and 15
to mech passives (`MECH_ICON`), one ability per skill / passive, chosen by
effect, **never shared between the two tables**; the rest are spare. A new
key without a row returns null and the panel just omits the icon.

### QuirkImages.gd
`class_name QuirkImages`, extends `RefCounted`, static only. **Quirk (기벽) icon lookup** — same role as `SkillImages`.
`icon_for(quirk_id)` → `images/quirks/quirk_<English_Name>.png` via `ICON` (`quirks.id` → file); unmapped / missing → null.
Not drawn by any screen yet.

`images/quirks/` holds **18 LoL Arena augment icons** (256², full-colour glyph in a round frame, transparent),
one per quirk. Source: League of Legends Wiki `Category:Arena_augment_icons`, `<Name> ar augment.png` →
`quirk_<Name>.png`. The augment tier matches the quirk grade — 0 일반 = Silver (grey), 1 희귀 = Gold (yellow),
2 영웅 = Prismatic (rainbow); within a grade the glyph is chosen by effect (eye = field hit, runner = evasion,
sword = engage hit, shield = engage evasion, arrow = growth, anchor = tank …). A new quirk needs a row in `ICON`
with an icon of its grade's tier. **Prototype placeholders (Riot art): replace before any public release.**

### MechImages.gd
`class_name MechImages`, extends `RefCounted`. Mech (frame) illustration lookup in the same
role as `PilotImages`. **All 30 assets remain while `mechs.csv` shrank to 21 rows**
— when mech skills (a unique passive + unique card set per mech) came in, the 9 mechs not in the sheet
were removed, but **surviving ids were not touched**: filenames are bound to ids, so
renumbering would misalign pictures and stats wholesale. So ids now have gaps
(3·4·5 / 10·11 / 16·17 / 23 / 29), and those `N_full.png` files remain unread
— when adding mechs again later, fill those slots first. Source and placement rules are in the
sections right below.

| Function | File | Consumer |
|---|---|---|
| `full_for(mech_id)` | `resources/images/mech/N_full.png` | Pilot detail panel (`ui/PilotDetailPanel.gd`), ban/pick bottom sheet |
| `portrait_for(mech_id)` | `resources/images/mech/portrait/N_portrait.png` | Ban/pick grid · ban chips · mech slots in team blocks |
| `has_image(mech_id)` | whether `N_full.png` exists | placeholder decision |

- **`N` is the `mechs.csv` `id` as-is** — the pilots' +1 offset (a historical artefact of receiving 40 images
  as 1..40) is not repeated here. Unlike pilots, files sit **flat** directly under `mech/` without a `full/`
  subfolder.
- **Never call `load()` blindly.** When a file is missing Godot spits an error and returns null,
  so ask `ResourceLoader.exists()` first and quietly return null if absent.
  Right now all 21 used slots are filled, so the placeholder path doesn't run, but it comes back to life
  if rows are added to `mechs.csv`, so it stays.

#### Mech square portraits (`resources/images/mech/portrait/N_portrait.png`)
256² square cuts baked by cropping **only head~upper body** from the full-body art. A ban/pick grid slot
is under 200px, while the full-body art is a mech standing full-length on a 1024² canvas, so
dropping it in as-is makes the mech pea-sized and **you can't tell which mech it is**. It is the same kind of
cut as a champion icon; only the detail sheet still uses the original full-body art (there it shows
one at a time).

To rebake, **run `resources/images/mech/make_mech_portraits.py`** —
cropping by hand misaligns figure scale per mech (same reason the pilot `eye` / `tall` cuts are
script-generated). How the head is found is the key: do not treat the top of the alpha bounding box as
the head — more than ten of the 21 mechs have a rifle · antenna · wings extending above the head, so cropping there
fills the frame with weapons. So the alpha is **eroded**
(`MinFilter(31)`) to remove thin structures, the top of the remaining blob is taken as the head, and the horizontal
centre is the **median** of the same mask (a mean would let a single arm stretched to one side drag the
centre wholesale). Size is 58% of the mech's total height.

Only mechs where the automatic decision goes wrong are pinned by hand in the script's `OVERRIDES` — currently
four, and of those **0 (Juggernaut) and 20 (Caprice) get absolute-coordinate boxes** (for the former, a
shield crosses the torso so the top of the eroded blob is not the head; for the latter, a rifle stretched sideways
drags the centre of mass). **`portrait/` also has all 30 slots** — the script iterates every
`*_full.png`, so the 9 unused slots get baked too.

#### Mech full-body art (`resources/images/mech/N_full.png`)
The source is 24 mech renders from **Gundam Evolution** (Bandai Namco, service ended 2022–2023),
downloaded from the galleries of the corresponding Gundam Wiki articles. The originals were already **transparent PNGs
with no background**, so no background removal was needed. These are temporary assets for a personal project, not for
distribution (same nature as the pilot portraits being Zenless Zone Zero art).

**The spec follows the pilot full-body art, except for one normalisation basis.** Height 1024 ·
alpha crop · bottom alignment are the same, but size is matched by **the square root of the opaque-pixel area,
not bounding-box height** — mech renders have swords · wings · rifles stretching sideways, so
bounding-box aspect scatters across 0.62~1.51, and matching by height shrinks the body for wider poses.
With the area basis, thin blade tips barely contribute to size, so **apparent body
size** matches evenly. The canvas is **fixed at 1024×1024** (horizontally centred · vertically
bottom-aligned). If widths varied as with pilot art, when the detail panel normalises by height
a mech with aspect 1.5 would spread to twice the screen width. The only things cut off by this spec are
44~64px of weapon tips on three images: Exia / Mahiroo / Marasai.

**id placement follows the stat archetypes in `mechs.csv`** — names (`Juggernaut` etc.) were
left as-is, so names and mechs are unrelated; **what has to match is stats**.

**The table below is the placement from the 30-mech era; `mechs.csv` now uses 21 of those slots.**
Remaining ids by role group — tank 0·1·2 / fighter 6·7·8·9 / assassin 12·13·14·15 /
supporter 18·19·20·21·22 / sniper 24·25·26·27·28. The removed slots were chosen to overlap the
**duplicate placements** among the 24 renders, so no mech actually disappeared from the screen.

| id | Archetype | Mech |
|---|---|---|
| 0–5 | Tank (highest hp / lowest atk) | Sazabi · DOM Trooper · Guntank · Pale Rider · Mahiroo · Zaku II [Melee] |
| 6–11 | Fighter (mid hp / mid atk) | RX-78-2 · Kämpfer · GM · Marasai · Barbatos · *(Kämpfer reused)* |
| 12–17 | Assassin (lowest hp / highest atk) | Exia · Susanowo · Zeta · Unicorn · Asshimar · *(Exia reused)* |
| 18–23 | Supporter (ranged presence / low atk) | Methuss · ∀ Gundam · Hyperion · ν Gundam · *(Methuss)* · *(Hyperion)* |
| 24–29 | Sniper (ranged presence / high atk) | GM Sniper II · Dynames · Heavyarms Custom EW · Zaku II [Shooting] · *(GM Sniper II)* · *(Dynames)* |

24 renders fill 30 slots, so **6 slots are duplicates**, and duplicates are always placed **within the same
archetype**, away from the original (so the same picture doesn't stand side by side on the ban/pick screen). If more than
24 pictures become available, fill the duplicate slots first.

### ConstTable.gd
`class_name ConstTable`, extends `RefCounted` — **static accessor for the `const` table**
(`data/csv/const.csv` → game.db `const`, see `data/README.md`). It holds the gameplay tuning
constants that used to be hard-coded `const`s in scripts.
- `num(key) -> float` / `int_of(key) -> int` (rounded) / `has(key) -> bool`.
- **Lazy cache** — the first call opens game.db once (path from `GameDb.path()`), reads every
  `key, value` row into a static Dictionary and closes the DB; later calls only hit the cache.
- **A missing key calls `push_error` and returns 0** — never silently; an empty / missing table also
  reports an error (run Rebuild game.db).
- Consumers keep the old constant name as a `static var` initialised from it, e.g.
  `static var MOVE_SPEED_MELEE: float = ConstTable.num("ENGAGE_MOVE_SPEED_MELEE")`, so external
  call sites (`TurnEngageSim.MOVE_SPEED_MELEE`) are unchanged.
- **Why static, not an autoload:** `static var` initialisers can run before autoloads are in the tree,
  so the table must be reachable without `/root/GameManager`.
- Values change only in the CSV (+ Rebuild game.db). Docs and comments name keys, never values.

### GameDb.gd
`class_name GameDb`, extends `RefCounted` — **the single place that resolves the game.db path**
(moved here from `GameManager`). `GameDb.path()` returns `res://data/game.db` in the editor; in an
exported build `_extract_to_user()` copies the DB packed in the `.pck` to `user://data/game.db`
**on every run** (SQLite cannot open a path inside the pck; overwriting each run means a stale DB from
an old build can never linger) and returns that copy. Computed once per run and cached.
It is static for the same reason as `ConstTable` (which needs the path before autoloads exist);
`GameManager.db_path()` now simply delegates to `GameDb.path()`. Details: `autoloads/README.md`,
`docs/ios_testbuild.md`.

### ScreenMetrics.gd
`class_name ScreenMetrics`, extends `RefCounted` — **static functions only**
(it reads the window's root viewport directly, so no node is needed).

**The single place every screen coordinate in this repo passes through.** Stretch is `expand`, so
viewport size differs per device, and on top of it sit strips the OS blocks off (notch · Dynamic
Island · home indicator · gesture bar). The bottom strip is a zone where **touches are stolen rather than
content hidden**, so a button placed there is visible but can't be pressed.

| Function | Answer |
|---|---|
| `viewport_size()` / `vp_w()` / `vp_h()` | viewport size after stretch |
| `insets()` | `(left, top, right, bottom)` insets — converted to **viewport units** |
| `safe_rect()` | safe area (안전 영역) rectangle |
| `top_y()` / `bottom_y()` | first · last usable y. **The bottom edge of a touch target must not exceed `bottom_y()`** |
| `left_x()` / `right_x()` / `center_x()` | horizontal. `center_x()` replaces a hard-coded `540` |
| `safe_h()` | safe-area height = local bottom of a screen after `indent_to_safe_top()` |
| `design_offset_y/x/()` | amount to shift a single 1080×1920 screen to centre it inside the safe area |
| `indent_to_safe_top(c)` | moves a full-screen Control down as a whole to the top of the safe area (`offset_top`) |
| `extend_background(c)` | stretches only the **background panel** among its children back out to the screen edges |
| `backfill_top(panel, color)` | when the background is the panel's own StyleBox, fills the emptied top strip with the same colour |
| `gesture_edge_w()` | left/right width taken by the Android back gesture — **a warning line, not an inset** |

`DisplayServer.get_display_safe_area()` answers in **native screen pixels**, so it must not be
used as-is — moving it into logical coordinates by multiplying the window-size-to-viewport-size ratio is
what `_compute_insets` does, and the result is cached keyed by window/viewport size.

To fake device insets on desktop, use the environment variable `ESM_SAFE_AREA="좌,위,우,아래"` (left,top,right,bottom)
or the user argument `-- --safe-area=0,162,0,90`. The three placement conventions and the per-device
numbers table are in **`docs/mobile_safe_area.md`**.

### SceneFade.gd
`class_name SceneFade`, extends `RefCounted` (static only). **Fade to black → fake loading →
fade back in** transition — the effect that says a scene has passed. `play(tree, on_covered)` calls
`on_covered` once at the moment the screen is fully covered, and `change_scene(tree, path)` does
`change_scene_to_file` at that point. The cover is a **`CanvasLayer` (layer 100) on the SceneTree root**,
so it survives the scene change, and that layer also holds the tweens. Timing is `FADE_OUT_SEC` 0.30 /
`LOAD_SEC` 0.50 / `FADE_IN_SEC` 0.35. Used at: run setup "게임 시작" (Start game)
(`RunSetupScreen._on_start_requested`), ban/pick confirm → battlefield
(`MatchFlow._launch_battle`).

### DragScroll.gd
`class_name DragScroll`, extends `Node`. **Scrolls a `ScrollContainer` by finger / mouse
drag.** Attaches with the one line `DragScroll.attach(scroll, horizontal = false, releases_cross = false)`
and lives as a child of that scroll (it is not a Control, so it doesn't take part in content sizing).

**It turns off the engine's touch drag and scrolls instead.** The engine path only turns on when
`is_touchscreen_available()`, so it didn't scroll at all with a desktop mouse, and on phones it got tangled
with tap targets on top of the scroll, producing a steady stream of "it won't scroll" reports. This node takes mouse and (emulated) touch
through the same code, so **what you get dragging with a mouse on desktop is exactly what you get on the phone**.

| State | What it does |
|---|---|
| PENDING | Pressed inside the scroll. Jitter within `THRESHOLD_PX` (14) is **swallowed** — a tap stays a tap, and the built-in drag doesn't start first on a small wobble. |
| SCROLL | Past the threshold and along the scroll axis. At that moment it **cancels the press of the button that was held** (toggling `disabled` on and off makes the engine clear press_attempt → no `pressed` arrives on release). On release, inertia (`FLING_DECAY`). |
| CROSS | Past the threshold but **crossing** the axis (only when `cross_axis_releases`). Emits `cross_drag_started(press_pos)` and leaves subsequent movement alone — the screen opens `force_drag` on that signal. |

Three conventions.
- **The GUI decides where the press came from** — it is received via the scroll node's `gui_input` signal.
  Measuring only the rectangle in `_input` would also capture taps on a popup covering it as scrolls. So
  every `MOUSE_FILTER_STOP` under the scroll is **lowered to PASS** (`_sweep_filters`,
  deferred each time a node enters). PASS still receives events itself, so taps work as before.
- **It accepts that press** (`accept_event`) — if the engine's touch drag also started,
  one finger would scroll twice as far.
- **Tap targets that are not buttons** (panels receiving release via `gui_input`) check `moved` and
  ignore releases that were scrolls · crossings (the training course cards work this way).

`OutgameTheme.add_vscroll` attaches it automatically. Hand-built scrolls — draft grid ·
draft detail · ban/pick mech grid · mech detail · training course list — each call it themselves.
It is not yet attached to the in-game (BattleSim) pile browse · search grids.

### Loc.gd
`class_name Loc`, extends `RefCounted`, static only. **Runtime localization helper** —
every code-side display string goes through `Loc.t(L.X)` (or `Loc.t(row.xxx_key)` + `# l10n-dynamic`).
Spec: `docs/localization_design.md` §10.2 · §10.3 · D4 · D11. `L` is the generated key-constant class
(`data/l10n/generated/L.gd`, written by l10n `build` — never edit it).

| API | Use |
|---|---|
| `t(key, params = {})` | `TranslationServer.translate(key)` → `{name}` placeholders from `params` (`String.format`) → leftover names that are tuning constants filled by `fill_consts` (others and josa tags stay) → literal `\n` → newline + josa via `StrategyIcon.resolve_josa`. Josa runs **after** substitution so it sees the filled name's final consonant. A key missing in both current and fallback locale comes back as the key itself |
| `resolve_plurals(s, params, keep_unknown)` · `pick_plural(forms, n)` · `plural_index(locale, n)` | D22: `{plural:name|one|other}` → form by `name`'s value (params, else const placeholder rule); runs before `String.format`. `t(key, params, keep_unknown_plurals = true)` leaves tags whose value is unknown (card descriptions: `CardDescBox` picks them from live battle values; `CardData.description` passes true). `plural_index` = per-locale rule table (en: 1 → 0; fr / pt: n < 2 → 0), extend it for 3+ form languages |
| `fill_consts(s)` | D20: `{skill_hold_turns}` → `ConstTable` value of `SKILL_HOLD_TURNS`; name suffixes (combinable) `_pct` ×100, `_abs` absolute, `_signed` `+` on positive. Lets descriptions point at const.csv instead of repeating a number |
| `number_text(v, signed = false)` | number for display text: integer without decimals, else up to 2 decimals |
| `has(key)` | translation exists in the current or fallback locale |
| `refs(key)` | `[x]` reference keys of a description key, in order of appearance — read once from `data/l10n/generated/refs.json` (D4) |
| `set_locale(code)` | `TranslationServer.set_locale` (the caller reloads the scene — §10.4) |
| `pick_initial_locale(saved)` | D11: `saved` if in `L.LOCALES` → device locale (`OS.get_locale()`, then `OS.get_locale_language()`) if supported → `L.FALLBACK_LOCALE` |

Godot 4.5's CSV translation importer already turns a literal `\n` in `strings_<loc>.csv` into a
newline; `t` still converts it so text that bypassed the importer behaves the same.

### StrategyIcon.gd
`class_name StrategyIcon`, extends `RefCounted`, static only. **The strategy-point
shape** — a regular octagon in two poses:
- **pointy top / bottom** (`flat = false`, vertex 0 at 12 o'clock, clockwise;
  face 0 = the upper-right face) — the `CostDonut` gauges only.
- **flat top / bottom** (`flat = true`) — the **point indicator**: black fill +
  thick blue rim (`INDICATOR_FILL`, `COLOR`, rim = `INDICATOR_RIM_RATIO` of the
  radius). At icon size the pointy pose reads as a circle, so the inline icon
  before "전략 점수" uses this one.

| API | Use |
|---|---|
| `points(c, r, flat)` | 8 vertices, clockwise |
| `draw(ci, c, r, fill, rim, rim_w, flat)` | filled octagon (+ optional rim; AA edge otherwise) |
| `make_badge(parent, center, r, fill, text, font_size, text_color, rim, rim_w)` | octagon Control with a centred number |
| `texture(px)` | cached indicator ImageTexture for inline use (flat sides touch the square) |
| `raster_convex(w, h, pts, fill, rim, rim_w)` | bakes any convex clockwise polygon into an AA texture with an inner rim (also used by `CostRibbon`) |
| `make_rich_label(text, font_size, color, icon_color, knock, target_color, target_key, special_color, refs, card_costs, card_meta)` / `fill_rich(rtl, …same…)` | description `RichTextLabel`: indicator before every "전략 점수", cost ribbon before every "비용", and a `KeywordIcon` before every keyword word (`KeywordIcon.WORDS` — 전장 명중 · 전장 회피 · 교전 명중 · 교전 회피 · 필중 공격 · 소지 중 · 공격력 · 사거리 · 체력 · 성장 · 필중 · 공격 · 교전 · 이동 · 대상 · 범위 · 뽑기 · 버리기 · 보존 · 찾기 · 생성 · 보호막 · 회복 · 처치 · 버린 더미) and before every duration ("3턴", "(…)턴" — `_duration_end`); **`[이름]` is a special keyword** — printed without brackets in `special_color`, preceded by its `KeywordIcon.SPECIAL_ICONS` icon (in `icon_color`) when it is an effect term; card names get colour only, coloured by `KeywordIcon.color_for` (`icon_color`; 뽑기/버리기 fixed green/red; 대상 = `target_color`); multi-word keywords keep their space as a no-break space; `knock` = panel background (필중 cuts its bow out of the disc with it). At one position the longest word wins (공격력 beats 공격). **Nothing inside `[...]`** gets an icon (card names like `[공격 명령]`). `add_text` / `add_image`, no BBCode — `[캐시]` stays literal. Icon and word are joined by a no-break space; text goes through `UiHelpers.keep_words` |
| `measure_text(text, refs = [], card_costs = false)` | stand-in string for `get_multiline_string_size` (square icons ≈ two glyphs, ribbon ≈ one, card-cost icon ≈ one; same tokenizer `_tokens` and break rules as `fill_rich`) |
| `rich_height(text, width, font_size, refs = [], card_costs = false)` | height a `make_rich_label` label of that width needs — `measure_text` through `ThemeDB.fallback_font.get_multiline_string_size` with the same `keep_words` / break flags / `ceil + 4` as `CardDescBox._text_height` |
| `resolve_josa(text)` | CSV text → display text: literal two-char `\n` → newline, particle tags `{eul}` 을/를 · `{eun}` 은/는 · `{i}` 이/가 · `{wa}` 과/와 picked by the previous visible character (closing `]` skipped, so `[아드레날린]{eul}` → 을). Hangul with a final consonant → first form, anything else → second. `_tokens` calls it first, so `fill_rich` / `measure_text` / `rich_height` resolve tags automatically |

**References and card cost icon (l10n D3 · D4).** `fill_rich`, `make_rich_label`, `measure_text` and
`rich_height` take `refs: Array` = the text key's `CardData.ref_entries(key)` — the i-th `[term]` is matched
to a ref by `CardData.ref_for` (same text, else same position), so special-keyword icons
(`KeywordIcon.SPECIAL_ICONS`, keyed by id) and card costs come from keys, never from the displayed
word. With `card_costs = true`, a `[name]` whose ref is a card gets a
miniature card-face cost ribbon in front (`CostRibbon.number_texture`, height ≈
font × 1.2, width ≈ height × 0.78, baked at 2× and drawn at 1×), then a no-break
space, then the coloured name. Pilot skill descriptions use this (`DraftDetailPanel`,
`PilotDetailPanel`, `SkillPopup`); card descriptions (`CardDescBox`) pass refs without costs.
A further trailing `card_meta: bool` (`fill_rich` / `make_rich_label`) wraps that
ribbon + name in `push_meta(name_key, META_UNDERLINE_NEVER)` so the caller can tell which
card a press hit (`ui/SkillPopup.gd` card preview → `CardData.by_name_key`).
**Word icons follow the locale.** The plain-word icons (`KEYWORD` / `COST_KEYWORD` = `keyword.icon.strategy` /
`.cost`, `KeywordIcon.WORDS`, the duration suffix `keyword.icon.duration_suffix`) are l10n keys whose translation is
the word **as that language's descriptions spell it** (`|` = alternative spellings, en `kill|killed`, `turns|turn`).
`_match_words()` expands them per locale (cached, `KeywordIcon.expand_words`); matching is case-insensitive, and a
word starting with a Latin letter only matches on word boundaries (a plural `s` is absorbed — "attacks", never
"move" inside "remove"); Hangul words match anywhere (particles attach directly). Durations accept one space
between the number and the suffix ("3 turns"). Changing an en description's wording → keep the matching
`keyword.icon.*` en value in step. The `JOSA` table is logic (`# l10n-ignore`).

### KeywordIcon.gd
`class_name KeywordIcon`, extends `RefCounted`, static only. **Card keyword icons**
— 64×64-viewBox SVG strings rasterized at runtime (`Image.load_svg_from_string`,
cached per key · px · colours), so there are no import files and every size is
crisp. Colours are **baked into the SVG** (`{C}` = icon colour, `{K}` = panel
background) rather than modulated, because 필중 needs two colours.

| Key | Shape |
|---|---|
| `RANGE` 사거리 | horizontal double arrow with a vertical bar at each end |
| `TARGET` 대상 | head-and-shoulders bust; colour = side the card aims at (`target_color(target)`: enemy red · ally green · else grey) |
| `AREA` 시전 범위 · 범위 | four isometric diamond tiles (up · down · left · right) |
| `DURATION` 지속시간 | hourglass — inline before "N턴" / en "N turns" only (no longer in the attribute row) |
| `ENGAGE` 교전 | two crossed swords |
| `ATTACK` 공격 | bow aimed right: string at the centre, stave curving just right of it, arrow pointing right |
| `PIERCE` 필중 · 필중 공격 | the same bow cut out of a filled disc |
| `MOVE` 이동 | left-to-right arrow |
| `ATK` 공격력 | one sword |
| `HP` 체력 · 최대 체력 | heart |
| `GROWTH` 성장 | sprout |
| `DRAW` 뽑기 | filled rounded card, arrow from above into its centre (outside part filled, inside part cut out); always `DRAW_COLOR` green |
| `DISCARD` 버리기 · 버린 후 | filled card, arrow from inside it out through the bottom (inside cut out, outside filled); always `DISCARD_COLOR` red |
| `PRESERVE` 보존 | padlock (keyhole cut out) |
| `HOLD` 소지 중 | open right hand, palm out, four fingers up, thumb to the right |
| `SEARCH` 찾기 | magnifying glass |
| `CREATE` 생성 | filled card with a plus to its right — card creation only (a shield is "부여", not "생성") |
| `SHIELD` 보호막 | shield |
| `HEAL` 회복 | heart with a plus cut out |
| `KILL` 처치 · 처치 관여 | skull (eyes · nose · teeth cut out) |
| `DISCARD_PILE` 버린 더미 | three cards lying flat, stacked and slightly staggered |
| `TRACK` [추적] | one footprint: sole + three widely spaced toes |
| `REACTIVE_ARMOR` [반응 장갑] | centred rounded-square plate, thick diagonal groove top-left → bottom-right, rivets top-right · bottom-left |
| `MARK` [목표] | circle with a plain cross through it |
| `BOUNTY` [현상금] | three stacked coins with thick separating outlines; middle coin nudged right, only the (slightly thicker) top coin shows its flat oval face |
| `STUN` [기절] | swaying ring that starts thin at top-centre, is thickest bottom-left and thins out on the right, with a star on its end |
| `VULNERABLE` [취약] | the 보호막 shield with a wide crack down the middle |
| `COOLDOWN` (쿨타임) | clock: ring + 12 o'clock hand + short hand towards 4 o'clock; not a word — `ui/SkillPopup.gd` shows it with the cooldown turns |
| `TILE` (대상 타일) | flat-top hexagon like the battlefield; not a word — `StrategyIcon.fill_rich(..., target_key)` swaps it in for `TARGET` on tile-target cards |
| `FIELD_HIT` 전장 명중 · `FIELD_EVA` 전장 회피 | translucent (`fill-opacity` 0.34) flat-top hexagon = a tile, with a full-colour target (ring + cross, the `MARK` shape) / footprint (the `TRACK` shape, scaled) on top |
| `ENGAGE_HIT` 교전 명중 · `ENGAGE_EVA` 교전 회피 | the same inner icons on a translucent thick X (both bars in **one** path, so the crossing is not doubly opaque) |
| `ATK_GROWTH` 공격 성장 · `HP_GROWTH` 체력 성장 | `ATK` sword / `HP` heart (shared bodies `_ATK_BODY` / `_HP_BODY`) + a short thick up-arrow at the bottom-right, outlined in `{K}` so it cuts where it meets the shape |
| `PRESENCE` 존재감 | head + wide torso (the `TARGET` bust) with a target (ring + cross) cut out of the torso in `{K}` |

**Pilot stat icons** — not words; `ui/PilotDetailPanel.gd` (`CHIP_ICONS`) puts them
before the stat-chip names: 체력 `HP` · 공격력 `ATK` · 존재감 `PRESENCE` · the four
명중 / 회피 keys · 공격 성장 `ATK_GROWTH` · 체력 성장 `HP_GROWTH`.

`texture(key, px, color, knock)` returns the cached `ImageTexture`;
`color_for(key, base, target_color)` picks the colour (fixed for 뽑기/버리기, the
target colour for 대상, else `base`); `target_color(CardData.target)` maps a card's
target to red / green / grey. Users:
`StrategyIcon.fill_rich` (inline, before words), `CardDescBox` (the attribute
row under the keyword line) and `ui/PilotDetailPanel.gd` (stat chips `CHIP_ICONS`,
and the `{attack}` / `{engage}` icons in stat notes).

**`WORDS` is `[[l10n key, icon key], …]`** (`keyword.icon.*`) — `words()` returns the current locale's
`[[lower-case word, icon key], …]` (cached per locale; `expand_words(table)` splits `|` alternatives). Matching
rules live in `StrategyIcon` (above).

### CostRibbon.gd
`class_name CostRibbon`, extends `RefCounted`, static only. **The cost shape** —
a tall right trapezoid hanging from its top edge; only the bottom edge is
slanted, the bottom-left lower than the bottom-right (`SLANT_RATIO` 0.14 of the
height; the inline icon uses `ICON_SLANT_RATIO` 0.30 so it doesn't read as a
plain rectangle). **No rim anywhere.** The ribbon is opaque white (`FILL`) with
dark ink (`INK`) and a downward drop shadow (`draw(..., shadow = true)`, stacked
offset copies — `SHADOW_*`). Used by the card's top-left cost ribbon
(`Card._draw_cost_badge`, big number), the small ribbon left of the
name in `CardDescBox`, and the inline icon before "비용" in descriptions (filled
with the strategy colour, `ICON_COLOR`). Descriptions always write cost changes
as "<value> 비용" (`+1 비용`, `-1 비용`, `0 비용`), so the icon lands between the
number and the word.

**The small badge is baked, not drawn.** `draw()` anti-aliases by stroking a
1px same-colour `draw_polyline(..., true)` round the polygon; on the 26×36
description-panel badge that line's feather read as a **grey rim** on the dark
panel, and the drop shadow read as a black rim under the slant. `make_badge`
therefore paints a coverage-AA texture (`fill_texture`, baked at 2× and drawn
down) and only lays the shadow when asked — `CardDescBox` passes `shadow =
light`, so the in-game (dark) panel has none.

| API | Use |
|---|---|
| `points(rect, slant)` | TL → TR → BR → BL |
| `draw(ci, rect, fill, slant, shadow)` | filled ribbon (AA edge), optional drop shadow |
| `make_badge(parent, rect, text, font_size, text_color, fill, shadow)` | small ribbon Control (baked texture, optional shadow) and a dark number in its upper part |
| `fill_texture(w, h, fill, slant)` | cached rimless ribbon texture, 1px coverage AA |
| `icon_texture(w, h)` | cached inline icon (strategy colour, no rim) — `fill_texture` with `ICON_SLANT_RATIO` |
| `number_texture(text, w, h)` | a `w`×`h` px white ribbon (`SLANT_RATIO`) with `text` in `INK` (font ≈ h × 0.62, centred above the slant like `make_badge`) as a texture — the inline card-cost icon of `StrategyIcon.fill_rich(..., card_costs)`. `add_image` only takes textures, so it is rendered by a cached `SubViewport` (transparent, `disable_3d`, `UPDATE_ONCE`) parented under the SceneTree root via `call_deferred("add_child")`; returns `get_texture()`, which fills in on the next drawn frame (headless dummy renderer: no image). Static cache keyed by text / w / h — viewports live for the whole session. Pass 2× pixel sizes, draw at 1× |

### UiHelpers.gd
`class_name UiHelpers`, extends `RefCounted`. Static helpers for
procedurally-built UI panels — `mk_label(...)` shared by MatchFlow controllers
and HudBuilder, and `keep_words(text)`: inserts U+2060 WORD JOINER between
adjacent non-space characters so autowrapped Korean breaks only at spaces (ICU
otherwise breaks between any two Hangul syllables — "비/용"). Measure the same
joined text, or the height disagrees with the label.

### OutgameTheme.gd
`class_name OutgameTheme`, extends `RefCounted`. **Every colour on outgame screens passes
through here** — season hub · press conference (기자회견) · training board · time-passing · standings · brackets ·
draft. If each screen held its own `Color(...)` literals, the same card would be drawn in a different grey
per screen, and touching up the palette once would mean combing through a dozen-odd files.
**In-game (BattleSim) has its own table, `BattleTheme`** (below) — since 2026-10 it follows the same
white-paper principles and aliases many of these constants.

The design principle is coloured cards on white paper. Three rules:

1. Background is `BG`; content sits on `SURFACE` cards that are **even whiter**. Boundaries are made not by lines
   but by **shadow and brightness difference** (`BORDER` is very faint).
2. Emphasis uses one colour field (`ACCENT`) only — which weekday it is now, which button to press now.
   **Amber for text is `ACCENT_TEXT`** (using `ACCENT` as-is for text on white paper
   lacks contrast. It is a separate literal because `darkened()` is not a constant expression in a
   `const` slot).
3. Classification is done by the card's left colour bar (`lead_bar_style`) or card colour field (`CARD_TINTS`).
   The five role colours (`ROLE_COLORS`) and role names (`ROLE_NAMES` — only for mech-role prose now; a pilot's
   position is always a `PositionBadge`) are also owned here —
   in `GameEnums.Role` order (not seat order).

| Group | Exports |
|---|---|
| Colour | `BG` `SURFACE` `SURFACE_SUNK` `RAIL` `RAIL_TEXT` / `TEXT` `TEXT_SUB` `TEXT_FAINT` `TEXT_ON_FILL` / `ACCENT` `ACCENT_DIM` `ACCENT_TEXT` `LINK` / `POSITIVE` `NEGATIVE` `NEUTRAL` / `BORDER` `BORDER_STRONG` `SHADOW` / `DIM` (modal dim) / `CARD_TINTS` `ROLE_COLORS` `ROLE_NAMES` `DAY_LETTERS` `DAY_NAMES` (these three hold l10n keys — text via `role_name(i)` · `day_letter(i)` · `day_name(i)`) |
| Sizes (theme defaults) | `FONT_HEADING` `FONT_TITLE` `FONT_BODY` `FONT_CAPTION` · `FONT_BTN_PRIMARY` `FONT_BTN_GHOST` `FONT_BTN_TEXT` `FONT_BTN_DARK` · `CARD_RADIUS` `CARD_PAD` `POPUP_RADIUS` `POPUP_PAD` `POPUP_PAD_WIDE` `SHEET_RADIUS` `SHEET_PAD` `SHEET_PAD_V` `SUNK_RADIUS` `BAR_RADIUS` · `CHIP_RADIUS` (pill, clamped to height/2) `CHIP_PAD_H` `CHIP_PAD_V` · `SELECT_BORDER` `SELECT_BORDER_ON` `SELECT_TILE_RADIUS` `SELECT_TILE_BORDER_ON` |
| StyleBox | `card_style` `flat_style` `lead_bar_style` `set_corner_radius` `selectable_box(on, radius, border_on)` |
| Button | `style_primary_button` (amber, one per screen) `style_ghost_button` `style_text_button` `style_dark_button` (dark colour field — "leave this screen") `style_danger_button` (`NEGATIVE` field — destructive confirm). All read **`button_spec(kind)`** (colours + default font) and **`button_styles(kind)`** (one `button_box` per `BUTTON_STATES`, incl. `hover_pressed` = pressed so the engine default never shows while held) — the same table the theme is built from |
| Theme | `build_theme()` → `Theme`, `save_theme()` → writes `THEME_PATH` (`OutgameTheme.tres`), `BUTTON_VARIATIONS` `BAR_BUTTON_VARIATIONS`, `variation_box(name, item)` (duplicate of a variation's stylebox for data colours) — see **OutgameTheme.tres** below |
| Bottom bar | `BOTTOM_BAR_H` `BOTTOM_BAR_SEP` `bottom_bar_top()` `bottom_inset()` · scene bars: `fit_bottom_bar(bar, safe)` `fit_bar_button(b)` `bar_button_styles(kind, below)` · code-built bars: `add_bottom_bar(parent, specs)` `layout_bottom_bar(buttons, specs)` `style_bottom_button(b, style, font)` — see **Bottom action bar** below |
| Pieces | `add_background` (`ScreenBackground` Panel; internally calls `ScreenMetrics.extend_background`) `add_card` `add_divider` `add_round_portrait` `add_chip` `add_vscroll` |

**Button styles decide colour only — feel is not decided here.** At one point these four
functions also set the strength via `HapticUi.kind` (primary · dark = `MEDIUM` / ghost =
`LIGHT` / text = `SELECT`), but that table was scrapped. Now **every button gives the same two beats
regardless of kind** — `LIGHT` on press, `SOFT` on release. Whether it is a confirm or a tab
switch is for the screen to say; a feel in the hand that wobbled per screen was itself
noise. The full wiring is in the `HapticUi.gd` section of `autoloads/README.md`.

### OutgameTheme.tres (shared Theme for scene-authored outgame UI)
Generated `Theme` resource for UI moved into `.tscn` (`docs/ui_scene_migration.md`). Scenes do not embed
StyleBox sub_resources or colour overrides — they attach this theme and pick a **`theme_type_variation`**.
**Never hand-edit the `.tres`**: change `OutgameTheme.gd` (constants / `button_spec` / `build_theme`) and
regenerate. Saving is deterministic (sub_resource ids = `<Variation>_<state>`, file uid kept), so the diff
shows only real value changes.

- **Attach**: set `theme = res://resources/OutgameTheme.tres` on the top **Control** of the scene (for a
  `CanvasLayer` popup: its first Control child, e.g. `Root`). Theme propagates to all Control descendants;
  a `CanvasLayer` breaks propagation, so never set it only on the layer. Then set each node's
  *Theme Type Variation*. Per-node size changes stay as `theme_override_font_sizes/font_size` (or
  `theme_override_constants/*`) — that is layout, not style.
- **Regenerate**: editor — open `OutgameThemeBuilder.gd` (`@tool extends EditorScript`) in the script
  editor → File → Run. Headless — `Godot --headless --path . -s res://resources/OutgameThemeBuilderCli.gd`
  (`extends SceneTree`). Both call `OutgameTheme.save_theme()`.

| Variation | Base | Purpose |
|---|---|---|
| `PrimaryButton` | Button | Main action, amber field + white text (`style_primary_button`) |
| `GhostButton` | Button | Other actions, white + faint border (`style_ghost_button`) |
| `TextButton` | Button | Back / minor, text only (`style_text_button`) |
| `DarkButton` | Button | Dark field, "leave this screen" (`style_dark_button`) |
| `DangerButton` | Button | Destructive confirm, `NEGATIVE` field (`style_danger_button`) |
| `Card` | PanelContainer | White card with shadow, padding `CARD_PAD` (`card_style`) |
| `PopupCard` | PanelContainer | Centred modal card, `POPUP_RADIUS` / `POPUP_PAD` |
| `PopupCardWide` | PanelContainer | Same card, smaller padding `POPUP_PAD_WIDE` for wide content (ShopPopup's 5 result cards) |
| `SheetCard` | PanelContainer | Large sheet over most of the screen, `SHEET_RADIUS`, padding `SHEET_PAD` (sides) / `SHEET_PAD_V` (top · bottom) |
| `SunkPanel` | PanelContainer | Sunk cell inside a card (`SURFACE_SUNK`, `SUNK_RADIUS`, no padding) |
| `ScreenBackground` | Panel | Full-screen paper (`BG`, no radius) — every screen scene's bottom `Background` node (mouse Ignore; code stretches it into the notch band with `ScreenMetrics.extend_background`). `add_background()` builds the same Panel in code. The single source of the background colour |
| `DimPanel` | Panel | Full-rect modal dim (`DIM`); set `mouse_filter` = Ignore, a flat Button underneath takes the tap |
| `ProgressTrack` · `ProgressFill` | Panel | Progress bar track (`SURFACE_SUNK`) and fill (`ACCENT`), `BAR_RADIUS`; the fill's width is data (`anchor_right` = ratio, code) |
| `HeadingLabel` | Label | Big screen heading (`FONT_HEADING`, `TEXT`) |
| `TitleLabel` | Label | Popup / card title (`FONT_TITLE`, `TEXT`) |
| `BodyLabel` | Label | Body text (`FONT_BODY`, `TEXT`) |
| `SubLabel` | Label | Secondary body / description (`FONT_BODY`, `TEXT_SUB`) |
| `CaptionLabel` | Label | Small labels, captions (`FONT_CAPTION`, `TEXT_SUB`) |
| `FaintLabel` | Label | Disabled / placeholder text (`FONT_CAPTION`, `TEXT_FAINT`) |
| `AccentLabel` | Label | Amber text on white (`FONT_CAPTION`, `ACCENT_TEXT`) |
| `OnFillLabel` | Label | White text on a colour fill (`FONT_CAPTION`, `TEXT_ON_FILL`) — the fill colour itself is data |
| `NegativeLabel` · `PositiveLabel` · `LinkLabel` | Label | Semantic text colour `NEGATIVE` (loss, error, warning) · `POSITIVE` (gain, qualified) · `LINK` (blue info, e.g. mastery gain), all `FONT_CAPTION` like `AccentLabel`; a body-size use adds `theme_override_font_sizes/font_size` = `FONT_BODY` |
| `RailLabel` | Label | Grey text on the dark rail (`FONT_CAPTION`, `RAIL_TEXT`) — 주간 화면 `%WeekLabel` |
| `OnFillTextButton` | Button | `TextButton` with every font colour `TEXT_ON_FILL` — a text button on a colour fill (상점 배너 "확률 보기") |
| `BarPrimaryButton` · `BarGhostButton` · `BarDarkButton` | Button | One slot of a **bottom action bar** — same colours / fonts as `PrimaryButton` · `GhostButton` · `DarkButton` with **square corners** (`bar_button_styles(kind)`, `BAR_BUTTON_VARIATIONS`). Only inside a bar; the device inset is added by `fit_bottom_bar` |
| `BarSeparator` | Panel | The vertical line between bar slots (`BOTTOM_BAR_SEP`, no radius) — a `Panel` child of every slot but the last, anchored right-wide, `offset_left = -2`, mouse Ignore. Replaces the `Sep` `ColorRect` and its colour literal |
| `SelectableCard` · `SelectableCardOn` | PanelContainer | Selectable option card, normal / selected: `SURFACE` + `SELECT_BORDER` `BORDER` / `ACCENT_DIM` + `SELECT_BORDER_ON` `ACCENT`, `CARD_RADIUS`, **padding 0 in both states** (a `MarginContainer` child pads, so content never shifts with the border). Code switches the variation name |
| `SelectableCardButton` · `SelectableCardButtonOn` | Button | The same card look on a `Button` root (whole card = tap target). Every press state draws the same box; focus empty; font `FONT_BTN_TEXT` `TEXT` |
| `SelectableTile` · `SelectableTileOn` | Button | Small selectable tab / filter / grid cell: `SELECT_TILE_RADIUS`, border `SELECT_BORDER` / `SELECT_TILE_BORDER_ON`, same fills as the card pair, padding 0. Text `TEXT_SUB` (hover `TEXT`) / `ACCENT_TEXT`, `FONT_BTN_TEXT` |
| `AccentChip` · `SurfaceChip` | PanelContainer | Pill chip, `ACCENT_DIM` / `SURFACE` fill, no border, `CHIP_RADIUS` (StyleBoxFlat clamps it to exactly height/2 — pixel-identical to an explicit h/2 radius), padding `CHIP_PAD_H` / `CHIP_PAD_V`. A fixed-size chip keeps its `custom_minimum_size` with a centred Label child (`AccentLabel` …) |
| `Divider` | HSeparator | 1px `BORDER` line (`add_divider`), no end grow — exactly the node's width |

Not variations (data- or device-dependent, stay in code): tinted cards (`card_style(r, tint)`), lead-bar
cards (`lead_bar_style(bar)`), chips whose fill is data (`add_chip`, rarity / tier colours), role / rarity
colours, and the bottom action bar's **device inset** (`fit_bottom_bar` — the bar's shape is the `Bar*`
variations).
A card whose padding no variation has: use the variation with a smaller (or no) padding and add a
`MarginContainer` child for the rest.

#### Screen variations (one scene's own look — `_add_screen_variations`)
**Scenes embed no StyleBox sub_resources at all**, even for a look only one scene uses. Such a look is a
theme variation too, built in `OutgameTheme._add_screen_variations()`:
- **Name = `<scene><role>`** — the prefix is the scene (`.tscn`) that uses it, so the name says where it
  belongs (`RunResultSectionCard` → `RunResult.tscn`, `ShopRowPanel` → the three `Shop*Row.tscn`).
- **Base = the nearest shared variation** (`Card`, `SunkPanel`, `AccentChip` / `SurfaceChip`, `PopupCard`,
  `Divider`, `SelectableCardButton`) — the theme records which shared look it derives from. Godot chains
  variations: the screen variation replaces the stylebox, every other item (fonts, colours, constants)
  comes from the base.
- **Data colours** (side / role / grade / pool colour): the variation holds the shape + a preview
  colour; code takes `OutgameTheme.variation_box(&"Name", item = &"panel")` — a duplicate read straight
  from the `.tres`, so it is right even before the node enters the tree — and sets only the colour.
- **State looks** switch the variation name (`WeekDayChip` ↔ `WeekDayChipToday`), like the `Selectable*` pairs.
- Adding one: write it in `_add_screen_variations` (palette constants, no colour literals), regenerate,
  pick it in the scene. Never put a `theme_override_styles/*` sub_resource in a scene.

| Variation | Base | Scene · node | Code colour |
|---|---|---|---|
| `BanPickBanChipPanel` | SunkPanel | `BanPickBanChip` root | — |
| `BanPickMechSlotFrame` | SunkPanel | `BanPickMechSlot` `Frame` | side colour border (`setup`) |
| `BanPickPortraitRim` | SunkPanel | `BanPickPortrait` `Rim` | side colour border (`setup`) |
| `BanPickSheetCard` · `BanPickDragGhost` | Card · SunkPanel | `BanPickView` `Sheet` · `DragGhost` | — |
| `ManagerDangerCard` | Card | `ManagerTab` `ResetCard` | — |
| `CollectionCellFrame` | SelectableCardButton | `CollectionCell` root (r16, border 2 `BORDER_STRONG`) | — |
| `CollectionCellArtMask` | SunkPanel | `CollectionCell` `ArtMask` (r12 white AA mask, clips the face + corner tabs) | — |
| `CollectionCellLevelRibbon` · `CollectionCellRankPlate` | AccentChip · SurfaceChip | `CollectionCell` `LevelRibbon` (`ACCENT`, square but r12 top-right) · `RankPlate` (`RAIL` 78 %, r12 top-left), both flush with the face bottom | — |
| `CollectionCellStarOn` · `CollectionCellStar` | OnFillLabel | `CollectionCell` `%Stars` children: reached rank (`ACCENT`) / unlocked by breakthrough, not reached (`TEXT_ON_FILL` 38 %), switched by rank | — |
| `ManagerPresetChip` · `ManagerPresetChipOn` | SelectableCardButton(On) | `ManagerPresetChip` root (r16, border 2 / amber 4), switched by `ManagerPresetChips.fill` | — |
| `TraitPickerGauge` · `TraitPickerGaugeBad` | SelectableCard · ManagerDangerCard | `TraitPickerView` `%Gauge` (r16, border 1 / red 3), switched by bonus < 0 | — |
| `TraitPickerSlot` · `TraitPickerSlotOver` · `TraitPickerSlotEmpty` | SelectableCardButton · SunkPanel | `TraitPickerSlot` `%Frame` (r14, `BORDER_STRONG` / `NEGATIVE` past the slot count) · `%Empty` | — |
| `TraitPickerRow` · `TraitPickerRowOn` · `TraitPickerRowLocked` | SelectableCardButton(On) | `TraitPickerRow` root (r16; border 1 / amber 3 / `BG` fill), `TraitPickerView.ROW_*` | — |
| `TraitPickerLayerChip` · `TraitPickerNewChip` · `TraitPickerEquippedChip` | SurfaceChip · AccentChip | `TraitPickerRow` `Layer` · `%New` · `%Equipped` (pills: sunk / `NEGATIVE` / `ACCENT`) | — |
| `RunResultSectionCard` · `RunResultSectionCardAmber` | Card | `RunResult` cards (padding 40, top 28) | — |
| `RunResultAccentDivider` | Divider | `RunResult` amber card dividers | — |
| `RunResultTraitCard` | Card | `RunResultTraitRow` `Card` | — |
| `DraftSlotFrame` | SelectableCardButton | `DraftSlot` `Frame` (all button states) | fill / role border (`_set_frame_style`) |
| `DraftSlotArtMask` · `PilotThumbArtMask` | SunkPanel | `ArtMask` (white AA mask for `clip_children`) | — |
| `PilotThumbCheck` · `PilotThumbTag` | AccentChip · SurfaceChip | `PilotThumb` `Check` · `Tag` | — |
| `PositionBadgePanel` | AccentChip | `PositionBadge` root (r8, 1px `POSITION_BADGE_EDGE`, padding `POSITION_BADGE_PAD_H` / `_V`) — shared widget in `resources/`, used on outgame and battle screens | role fill (`set_role`) |
| `StepChipPanel` | AccentChip | `StepChip` root (pill) | state fill / border (`paint`) |
| `TeamDraftGridBack` | Card | `TeamDraftView` `GridBack` | — |
| `ShopRowPanel` | Card | `ShopCraftRow` · `ShopExchangeRow` · `ShopShardRow` roots | — |
| `ShopBannerCard` · `ShopDevRowPanel` | Card · SunkPanel | `ShopTab` `Banner` · `DevRow` | banner fill = pool (`_fill_gacha`) |
| `TrainingCourseCardFrame` · `TrainingCourseGradeBand` | Card · SunkPanel | `TrainingCourseCard` root · `Band` | grade colour (`fill` / `set_selected`) |
| `TrainingCourseShapeWell` | SunkPanel | `TrainingCourseCard` `Well` | — |
| `TrainingCoursePopoverFrame` | PopupCard | `TrainingCoursePopover` root | grade border (`fill`) |
| `TrainingThumbFrame` · `TrainingThumbExpChip` | Card · AccentChip | `TrainingThumb` root · `ExpChip` | role border, ± fill (`TrainingView`) |
| `WeekRail` | SunkPanel | `WeekProgressView` `Rail` (the old `WeekEveningHighlight` went with the evening slot scene) | — |
| `WeekDayChip` · `WeekDayChipToday` | AccentChip | `WeekProgressView` day `Chip`s (`WEEK_DAY_CHIP_RADIUS`) | variation switched by `_refresh_rail` |
| `WeekMapBubble` | SurfaceChip | `WeekMapPilot` `%Bubble` (morning speech bubble over a map token: white, `BORDER_STRONG` 2px, radius 14) | scene-set |
| `LobbySurfaceBar` · `LobbyToast` | Card · SurfaceChip | `Lobby` `StripBack` / `TabBarBack` · `Toast` | error toast = `NEGATIVE` copy |
| `BanPickOrderPip` · `IntelAnalystNote` | SunkPanel · SunkPanel | `BanPickOrderPip` root (r6; side colour + capsule corners = code copy) · `IntelView` `Note/Card` (`ACCENT_DIM`, r14) | pip fill = side colour |
| `MatchPrepPilotCard` · `MatchPrepCardInner` · `MatchPrepWarnChip` · `MatchPrepMechChip` | Card · Card · AccentChip · SunkPanel | `UI_Comp_MatchPrepPilotCard` root (card look, no padding) · its embedded `SeasonPilotCard` (`StyleBoxEmpty` — no second card) · `%Warn` `경계 대상` (`NEGATIVE`, pill, padding 10/2) · `MechChip*` (`SURFACE_SUNK`, r8, padding 4/2) | — |
| `MessengerBubbleNpc` · `MessengerBubbleMine` · `MessengerAnswerButton` · `MessengerNoteChipMuted` | Card · Card · GhostButton · AccentChip | `MessengerNpcBubble` / `MessengerPlayerBubble` `%Bubble` (r22, padding 0 — the scene's `Pad` pads) · `MessengerAnswerButton` (ghost + padding 22/17) · failed `MessengerNoteChip` | — |
| `VnDialogueBubble` · `VnDialogueNamePlate` · `VnDialogueNamePlateMine` · `VnDialogueArtSlab` · `VnDialogueChoiceButton` | Card · AccentChip · AccentChip · SunkPanel · GhostButton | `UI_View_VnDialogue` `%Bubble` (r28, padding 0, the scene's `Pad` pads) · `%NamePlate` (pilot `ACCENT` / manager `RAIL`, r14 + padding), switched by `VnDialogueView._show_line` · `%Slab` (no-art placeholder) · `UI_Comp_VnChoiceButton` (ghost + padding) | (none) |

Label colour overrides that are data (side / grade / day state colours) stay `theme_override_colors` set by code;
the scene value is a preview.

### BattleTheme.gd + BattleTheme.tres (in-game white palette / Theme for BattleSim UI)
`class_name BattleTheme`, extends `RefCounted`. The **in-game (BattleSim) counterpart of `OutgameTheme`** —
every colour / font size / radius of the battle UI (`HudBuilder`, `PilotStrip`, `PilotDetailPanel`, `SkillPopup`,
`MvpView`, `KillFeed`, `ObjectiveTimer` / `ObjectiveRewardPopup`, `CardDescBox` (battle side), `CardSelectOverlay`,
`CardPileViewer`, `EngageArena` / `EngageIntro`, `TraitBanner`, `TurnEndPanel`) lives here; code holds no colour
literals, only these tokens. **Since 2026-10 the principles are the outgame ones** (user decision — every in-match
plate converted): plates are **white cards** (`PANEL_BG` · `POPUP_BG` · `MENU_BG` = `OutgameTheme.SURFACE`) whose
edges come from a **drop shadow** (`SHADOW`, `with_shadow()`) and a very faint border (`PANEL_BORDER` = `BORDER`);
**every in-match dim is one token, `DIM_BLACK` = black α 0.30** (user decision — the field stays clearly visible but
reads as covered); `DIM` (pilot detail, stress event) · `DIM_DEEP` (MVP) · `DIM_LIGHT` (victory, grid pickers, pile
viewer, objective reward) · `DIM_FIELD` (hand pick, reward fx) and the engage surround / result all alias it. Text that
stands **directly on a dim** follows the field rule — light colour + black outline (`TEXT_BRIGHT`, `TITLE_ON_DIM`,
`SUB_ON_DIM`, `NEGATIVE_ON_DIM`, `POSITIVE_ON_DIM`, `GROWTH_ON_DIM`; `BattleOutlined*Label`); white plates stay white;
**exception (user decision): description plates stay dark** — card description boxes (`CardDescBox` battle side: hand,
detail card fan, pickers, previews), keyword note panels, and the pilot detail info plate (rows, note, effect cells,
growth bar) keep the pre-white colours as `DESC_*` tokens (`DESC_BG` `DESC_NAME` `DESC_TEXT` `DESC_NOTE` `DESC_KW`
`DESC_KNOCK` `DESC_SPECIAL` `DESC_HEADER` `DESC_KEY` `DESC_VALUE` `DESC_BODY` `DESC_POSITIVE` `DESC_NEGATIVE`
`DESC_GROWTH` `DESC_GOLD` `DESC_CHIP_BG` `DESC_CHIP_BORDER` `DESC_ICON`, `DESC_FX_COLORS` / `desc_fx_color(c)`);
emphasis is **amber** (`GOLD` = `ACCENT` fills, `TEXT_TITLE` = `ACCENT_TEXT` text; primary buttons are the outgame
primary button); sides are blue / red — `ALLY` · `ENEMY` · `SIDE_TEXT` are darkened for white paper, `TEAM_*` stay
as fills over the field. Many constants alias `OutgameTheme` directly (`const PANEL_BG = OutgameTheme.SURFACE`).
**Not plates, so not whitened** (they float on the dark battlefield / art): damage popups, portrait banners, marker
rings, strip disc numbers (`PilotStripDeadLabel`), stress words, the objective clocks (outlined number, light
`OBJ_*_FIELD` glyphs — user decision), the strip growth tab (team-colour fill + outlined `TEXT_SCORE` — user
decision), the skill badge (dark tile face like the skill icon tile), reservation chips — `TEXT_BRIGHT` + `OUTLINE`
(`BattleOutlinedLabel`) stays for those.

| Group | Exports |
|---|---|
| Plates | `PAPER` · `PANEL_BG` `PANEL_BORDER` · `POPUP_BG` (skill popup + its arrow) · `MODAL_BG` · `GOLD_PANEL_BG` · `MENU_BG` (desc boxes) · `SUNK` (tracks, slot backs) · `LINE_STRONG` (tracks / frames on paper) · `DEAD_SLOT` · `CHIP_BG` `CHIP_BG_HL` `CHIP_BORDER` `CHIP_BORDER_HL` (sunk cell / amber-tint highlight) · `TAB_BG_ON/OFF` `TAB_BORDER_ON/OFF` · `BUTTON_BG` · `SLAB_BG` · `ART_SLAB_BG` `ART_SLAB_BORDER` `ART_BACK_TINT` · `FX_VALUE_BAND` |
| Accent · dim | `GOLD` `GOLD_BORDER` `GLOW` · `DIM_BLACK` (α 0.30) and its aliases `DIM` `DIM_DEEP` `DIM_LIGHT` `DIM_FIELD` · `SHADOW` · `OUTLINE` `OUTLINE_SOFT` · on-dim text `TITLE_ON_DIM` `SUB_ON_DIM` `NEGATIVE_ON_DIM` `POSITIVE_ON_DIM` `GROWTH_ON_DIM` |
| Skill tile | `SKILL_TILE_BG` (`RAIL`) `SKILL_TILE_ICON` `SKILL_TILE_SHADOW` `SKILL_KW_ICON` (= `ACCENT_TEXT`) `SKILL_KNOCK` (= white) `SPECIAL_KW` (= `KeywordIcon.SPECIAL_COLOR_LIGHT`) · `FX_ICON` (glyphs on sunk cells) |
| Text | on paper: `TEXT` `TEXT_VALUE` `TEXT_DESC` `TEXT_CLOCK` (= `OutgameTheme.TEXT`) · `TEXT_KDA` `TEXT_WAIT` `TEXT_PLACEHOLDER` `TEXT_NOTE` `TEXT_SUB` `TEXT_KEY` `TEXT_TYPE` `TEXT_MECH` (= `TEXT_SUB`) · `TEXT_FAINT` · `TEXT_ON_FILL` · coloured `TEXT_TITLE` `TEXT_HEADER` `TEXT_SKILL` `TEXT_SECTION` `TEXT_GROWTH` `TEXT_WARN` · `ALLY` `ENEMY` `POSITIVE` `NEGATIVE`; over the field: `TEXT_BRIGHT` `TEXT_SCORE` `DEAD` `STRESS_*` |
| Effect cells | `FX_WARM` `FX_COOL` `FX_GREEN` `FX_MINT` `FX_GOLD` `FX_SHIELD` `FX_NEUTRAL` (detail-panel effect abbreviations on sunk cells) · `OBJ_HERALD` `OBJ_DRAGON` (on white plates) · `OBJ_HERALD_FIELD` `OBJ_DRAGON_FIELD` (objective clocks over the field) |
| Sides (index = team) | `TEAM_DISC` `TEAM_RIM` `TEAM_DONUT` `TURN_BAR` (turn banner side lines) `SIDE_TEXT` · `STRIP_DRAG_DIM` `DEAD_TINT` · `PREVIEW_FIELD` (F6 previews' stand-in battlefield grey) |
| Sizes | `FONT_LARGE` 40 · `FONT_TITLE` 30 · `FONT_VALUE` 28 · `FONT_TAB` 26 · `FONT_BODY` 22 · `FONT_CAPTION` 20 · `FONT_SMALL` 18 · `RADIUS` `PANEL_RADIUS` `FX_RADIUS` `CHIP_RADIUS` `SLAB_RADIUS` `ART_SLAB_RADIUS` `SCORE_TAB_RADIUS` `ROW_RADIUS` `DESC_BOX_RADIUS` · `*_BORDER_W` · `PANEL_PAD` `POPUP_PAD` `CLOCK_PAD` · `SHADOW_SIZE` `SHADOW_OFFSET` `DESC_SHADOW*` `OUTLINE_SIZE` |
| StyleBox | `box(bg, radius, border, border_w)` (padding 0) · `with_shadow(sb)` · `panel_box()` · `chip_box(highlighted, fx)` · `tab_box(on)` · `popup_box()` · `gold_box()` (white + amber rim) · `row_box()` (kill-log row) · `desc_box()` — the same factories the theme is built from, for code that still styles nodes |
| Buttons in code | `style_button(b, kind = "primary", font_size)` — delegates to `OutgameTheme.style_primary/ghost/danger_button` (selection overlay, pile viewer, engage intro / result, objective reward, jungle start) |
| Theme | `build_theme()` · `save_theme()` → `THEME_PATH` (`BattleTheme.tres`) · `variation_box(name, item)` |

**`BattleTheme.tres`** follows the `OutgameTheme.tres` rules exactly: never hand-edit; regenerate with
`BattleThemeBuilder.gd` (editor, File → Run) or
`Godot --headless --path . -s res://resources/BattleThemeBuilderCli.gd` (a brand-new `class_name` needs one
`--import` first so the CLI can see it); attach it on the scene's first **Control** (under a `CanvasLayer`,
e.g. `Root`) and pick a *Theme Type Variation*; no local StyleBoxes / colour overrides in scenes; a node's own
font size stays `theme_override_font_sizes/font_size`. Button variations set their font colours (white on amber,
`ACCENT_TEXT` / `TEXT_SUB` tabs, `TEXT_FAINT` disabled).

| Variation | Base | Purpose |
|---|---|---|
| `BattlePanel` | PanelContainer | Info plate — `panel_box()` (white, 1px faint border, `PANEL_RADIUS`, shadow), padding `PANEL_PAD` (detail header / stat plate / skill plate, stress toast) |
| `BattlePopup` | PanelContainer | Popup plate — `popup_box()` (white, `RADIUS`, shadow), padding `POPUP_PAD` (skill popup, reserve info) |
| `BattleGoldPanel` | PanelContainer | `gold_box()` — white + 3px amber rim + shadow, padding 0 — MVP info |
| `BattleGoldModal` | PanelContainer | Same, `MODAL_BG` — the victory / defeat panel (`%VictoryPanel`, a `Panel`) |
| `BattleSlab` | PanelContainer | "No art yet" slab (`SLAB_BG`, 2px `PANEL_BORDER`, `SLAB_RADIUS`) |
| `BattleDimPanel` | Panel | Full-rect dim `DIM` (= `DIM_BLACK`; detail panel, stress event); set mouse Ignore |
| `BattleGoldButton` | Button | Amber primary (`OutgameTheme.button_styles("primary")`, corners `RADIUS`), white text, `FONT_LARGE` — MVP "계속", victory button (font 32 override) |
| `BattleActionButton` | Button | Amber primary, white text, `FONT_VALUE` — skill "사용" (popup and detail panel) |
| `BattleChipButton` · `BattleChipButtonOn` | Button | Stat cell normal (sunk) / highlighted (amber tint + amber 3px) — `chip_box(false/true)` in every press state |
| `BattleFxButton` · `BattleFxButtonOn` | Button | Same pair with `FX_RADIUS` (lasting-effect thumbnails) |
| `BattleTab` · `BattleTabOn` | Button | Detail panel tab off (sunk) / on (white, joins the plate) — `tab_box(on)`, `FONT_TAB`, text `TEXT_KEY` / `TEXT_TITLE` |
| `BattleTextLabel` | Label | `TEXT`, `FONT_LARGE` — plain dark text on paper (victory line, MVP names, base of the HUD / turn-end labels) |
| `BattleHeaderLabel` | Label | `TEXT_HEADER`, `FONT_LARGE` (detail name, note title) |
| `BattleTitleLabel` | Label | Amber `TEXT_TITLE`, `FONT_TITLE` (result panel "MVP") |
| `BattleSkillNameLabel` | Label | `TEXT_SKILL`, `FONT_TITLE` |
| `BattleValueLabel` · `BattleBodyLabel` · `BattleStatusLabel` · `BattleKeyLabel` | Label | `TEXT_VALUE` `FONT_VALUE` · `TEXT_DESC` · `TEXT_WAIT` · `TEXT_KEY` (the last three `FONT_BODY`) |
| `BattleSectionLabel` · `BattleSubLabel` · `BattleCaptionLabel` | Label | `TEXT_SECTION` · `TEXT_SUB` (`FONT_BODY`) · `TEXT_TYPE` `FONT_CAPTION` |
| `BattleGrowthLabel` | Label | `TEXT_GROWTH` (amber), `FONT_LARGE` |
| `BattlePositiveLabel` · `BattleNegativeLabel` · `BattleAllyLabel` · `BattleEnemyLabel` | Label | `POSITIVE` · `NEGATIVE` · `ALLY` · `ENEMY`, `FONT_BODY` — binary state colours switch the variation name |
| `BattleOutlinedLabel` | Label | `TEXT_BRIGHT` + `OUTLINE` outline `OUTLINE_SIZE`, `FONT_LARGE` — text floating on the field / art / dim with no plate |
| `BattleOutlinedSubLabel` · `BattleOutlinedNegativeLabel` · `BattleOutlinedPositiveLabel` | BattleOutlinedLabel | `SUB_ON_DIM` / `NEGATIVE_ON_DIM` / `POSITIVE_ON_DIM`, `FONT_BODY`, outline 4 — small lines on a dim (stress event `%Hint` / `%Effect`, switched by mood) |

Screen variations (`_add_screen_variations`, same `<Scene><Role>` rule as outgame; label variations override
only `font_color` unless noted):

| Variation | Base | Scene · node | Code |
|---|---|---|---|
| `MvpDimPanel` | BattleDimPanel | `MvpView` `Dim` (`DIM_DEEP` = `DIM_BLACK`) | — |
| `MvpTitleLabel` · `MvpSubLabel` · `MvpNameLabel` | BattleOutlinedLabel (`TITLE_ON_DIM`, on the dim) · BattleSubLabel · BattleTextLabel (both on white plates / slab) | `MvpView` `Title` · `Metric` / `FallbackLabel` · `%Name` / `%Kda` | — |
| `HudClockLabel` | BattleTextLabel | `BattleHud` `%TimeLabel` — white pill (the label's own `normal` box, r999, shadow, padding `CLOCK_PAD`), `TEXT_CLOCK`, `FONT_CAPTION`; the scene label is 102 wide, centred | — |
| `HudStripBackdrop` | BattleDimPanel | `BattleHud` `%EnemyStripBackdrop` · `%PlayerStripBackdrop` — `StyleBoxEmpty` (invisible; z-order / hide anchors) | — |
| `HudTurnBar` | BattleDimPanel | `BattleHud` `%TurnBar` — white bar, shadow, 4px top / bottom lines in `TURN_BAR[0]`, AA off | `variation_box` copy, `border_color` = `TURN_BAR[team]` |
| `HudTurnLabel` | BattleTextLabel | `BattleHud` `%TurnLabel` — `SIDE_TEXT[0]`, 56 | colour override `SIDE_TEXT[team]` |
| `HudVictoryDimPanel` | BattleDimPanel | `BattleHud` `%VictoryBackdrop` (`DIM_LIGHT`) | — |
| `HudVictoryKdaLabel` | BattleSubLabel | `BattleHud` `%MvpKda` — `TEXT_KDA`, 26 | — |
| `PilotStripScoreTab` | BattleDimPanel | `PilotStripCell` `%Pill` — `box(TEAM_DISC[0], SCORE_TAB_RADIUS)`, AA (team colour kept on purpose) | `variation_box` copy, `bg_color` = `TEAM_DISC[team]` (`PilotStrip.setup`) |
| `PilotStripScoreLabel` | BattleOutlinedLabel | `PilotStripCell` `%Score` — `TEXT_SCORE`, 20, outline black α 0.6, 3 | — |
| `PilotStripDeadLabel` | BattleOutlinedLabel | `PilotStripCell` `%Dead` — `DEAD`, 53 | — |
| `TurnEndPanelPlate` · `TurnEndGauge` · `TurnEndLabel` | BattleGoldPanel · BattleDimPanel · BattleTextLabel | `UI_Comp_TurnEndPanel` `%Plate` (white, amber rim, `PANEL_RADIUS`) · `%Gauge` (`CHIP_BG_HL` amber tint, r `PANEL_RADIUS` − 4; width = code) · `Label` (`TEXT`, `FONT_TITLE`) | gauge width (`_apply_fill`) |
| `PilotDetailStatPlate` | BattlePanel | `PilotDetailView` StatPanel — top corners square (the active tab sits on it) | — |
| `StressEventAwakenLabel` · `StressEventPanicLabel` | BattleOutlinedLabel | `StressEventView` `%Result` — `STRESS_AWAKEN` / `STRESS_PANIC` | code switches by mood |
| `StressMoodAwakenLabel` · `StressMoodPanicLabel` · `StressMoodShakenLabel` | BattleOutlinedLabel | `PilotStripCell` `%Mood`, `PilotDetailView` `%Stress` — `STRESS_*`, `FONT_BODY`, outline 4 | code switches by mood (`StressEvents.mood_variation`) |
| `PilotDetailArtSlab` | BattleSlab | `PilotDetailArt` `%Slab` — "no art yet" (`ART_SLAB_BG`, 3px `ART_SLAB_BORDER`, top corners `ART_SLAB_RADIUS`) | shown when the texture is missing |
| `PilotDetailFxBand` · `PilotDetailFxBandLabel` | BattleDimPanel · BattleValueLabel | `PilotDetailFxThumb` `%Band` (`FX_VALUE_BAND`, bottom corners `FX_RADIUS` − 3) · `%BandValue` (`TEXT_ON_FILL`) | — |
| `PilotDetailMenuPanel` | BattlePopup | `PilotDetailInfoMenu` — `desc_box()` (the **dark** card description box, `DESC_BG`; `CardDescBox.panel_style(false)` returns the same), padding 20 / 16 | — |
| `PilotDetailMenuTitleLabel` · `PilotDetailMenuKeyLabel` · `PilotDetailMenuValueLabel` · `PilotDetailMenuPositiveLabel` · `PilotDetailMenuNegativeLabel` · `PilotDetailMenuFxButton` | BattleHeaderLabel · BattleKeyLabel · BattleValueLabel · BattlePositiveLabel · BattleNegativeLabel · BattleFxButton | Inside the dark info plate: `%Title` / `%TitleValue` (`DESC_HEADER`), `PilotDetailInfoRow` key / value (`DESC_KEY` / `DESC_VALUE`), `PilotDetailStatFx` `%Pct` / `%Flat` (`DESC_POSITIVE` / `DESC_NEGATIVE`, `_sign_variation`), its thumb (`DESC_CHIP_BG` + `DESC_CHIP_BORDER`) | effect abbreviation colour `desc_fx_color()` |
| `PilotDetailCardBand` | Button | `PilotDetailCardBand` — `StyleBoxEmpty` in every state (input band over a fan card) | — |
| `PilotDetailMechLabel` · `PilotDetailWarnLabel` · `PilotDetailPlaceholderLabel` | BattleKeyLabel · BattleNegativeLabel · BattleSubLabel | `%Mech` (`TEXT_MECH` 24) · `%DeadLabel` (`TEXT_WARN` 24) · `%FallbackLabel` (`TEXT_PLACEHOLDER` 34) — these also set `font_size` | — |
| `PilotDetailNoteText` | RichTextLabel | `PilotDetailInfoMenu` `%Note` (`TEXT_NOTE`, `normal_font_size` `FONT_CAPTION`) | text + icons via `_fill_note` |

The victory panel uses the shared `BattleGoldModal` / `BattleTitleLabel`; its result line and MVP name are
`BattleTextLabel` (48 · 34 overrides), its button `BattleGoldButton` (32).

### Bottom action bar (`add_bottom_bar`)
**The main action on an outgame screen is not a shape floating in the middle of the screen but the whole bottom
zone.** Zero left/right margin, bottom flush to the safe line, square corners — so the bar becomes
a section of the screen and "everything down here is this action" reads from position alone. With
several buttons they split that zone **by weight ratio**, and the convention is **primary 2 : secondary 1** with
**the primary at the far right** (where the thumb reaches and where the scanning eye stops last).

Eight screens use it: season hub (`리그 순위` (League standings) 1 / `이번 주 시작 →` (Start this week →) 2) · daily training (일상 훈련)
(`판 비우기` (Clear board) 1 / `훈련 확정` (Confirm training) 2) · draft (`뒤로` (Back) 1 / `다음` (Next)·`게임 시작` (Start game) 2) ·
league standings · playoffs · international tournament (국제대회) brackets · time-passing (each a single full-width `확인` (OK)) ·
ending / game over (a single full-width `정산` (Settle)), lobby (`새 런` 1 / `이어하기` 2, no run → `새 런` full width).

Four conventions.
- **Derive body height backwards from `bottom_bar_top()`.** If each screen re-wrote the bar height as a constant,
  every time the bar was touched those screens' lists would quietly slide under the bar.
- **The colour field extends below the safe line; the text stays above it.** Leaving the home indicator /
  gesture bar area empty leaves a strip of background colour under the bar, making the bar look like it floats.
  Stretch the button rectangle down to the viewport bottom but add the inset to `content_margin_bottom`, and
  Button places the text at the centre of that inner rectangle, so both the press area and the read area
  are inside the safe area.
- **Screens whose slots collapse call `layout_bottom_bar` again.** Only visible slots share the weight,
  so in the draft's PICK state "다음" (Next) uses the full screen width.
- **Buttons that change outfits stay bar buttons.** Calling `style_dark_button` directly brings back
  rounded corners and that slot alone pops back up off the screen (the time-passing screen's
  "경기 시작" (Start match) switches this way). Scene bars switch the variation
  (`BarPrimaryButton` → `BarDarkButton`) and call `fit_bar_button(b)`; code-built bars call
  `style_bottom_button` again.

#### Scene-built bars (`.tscn`) — `fit_bottom_bar(bar, safe = null)`
The scene owns the shape: a bottom-wide anchored node (`anchor_top = anchor_bottom = 1`,
`offset_top = -BOTTOM_BAR_H`, `offset_bottom = 0`) that is either **one `Button`** (single full-width
slot) or an **`HBoxContainer`** (`separation` 0) of `Button`s split by `size_flags_stretch_ratio`
(secondary 1 : primary 2, primary right). Each button picks `BarPrimaryButton` / `BarGhostButton` /
`BarDarkButton` (+ `theme_override_font_sizes/font_size` when not the default); every slot but the
last gets a `BarSeparator` Panel child. The script adds only the device inset, from `_ready`
(the scene must be in the tree):

```gdscript
OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)   # safe is optional: the panel whose bottom = safe line
```
- `safe` (optional): its `offset_bottom` becomes `-bottom_inset()`.
- The bar's rect becomes *top = safe line - `BOTTOM_BAR_H`, bottom = viewport bottom*: bar inside `safe`
  (`safe.is_ancestor_of(bar)`) → `offset_top = -BOTTOM_BAR_H`, `offset_bottom = +inset`; otherwise (bar
  anchored to a parent whose bottom is the viewport bottom) → `offset_top = -(BOTTOM_BAR_H + inset)`,
  `offset_bottom = 0`. So the bar's parent bottom must be the safe line (inside `safe`) or the viewport
  bottom (outside).
- Every `Button` (the bar itself, or its children — hidden ones too) gets `fit_bar_button`: with an inset
  each state is overridden with `bar_button_styles(kind, inset)` (text lifted above the inset, colour runs
  under it); with no inset the overrides are removed (the variation is already exact). The variation must
  be one of `BAR_BUTTON_VARIATIONS` (otherwise a warning and no change).
- Idempotent — values are set, never added. Call again after switching a slot's variation; toggling a
  slot's `visible` needs nothing (the HBox re-splits the visible slots by ratio).

```gdscript
# 1 slot — a Button anchored bottom-wide on the screen root (not inside the safe panel):
OutgameTheme.fit_bottom_bar(%OkButton)
# 2 slots — HBox %Bar (Back: BarGhostButton + BarSeparator child, Next: BarPrimaryButton, ratio 2) in %SafeArea:
OutgameTheme.fit_bottom_bar(%Bar, %SafeArea)
# a slot that changes kind at runtime:
btn.theme_type_variation = &"BarDarkButton"
OutgameTheme.fit_bar_button(btn)
```

#### Code-built bars — `add_bottom_bar` / `layout_bottom_bar` / `style_bottom_button`
Kept for the lobby's action bar, whose slots come from each tab's `bar_specs()`.
`style_bottom_button(b, style, font)` = the `style_<kind>_button` colours + `bar_button_styles(kind, inset)`
(the same boxes as the `Bar*` variations). Scene-built bars do not call it — they use the variations.

**`add_round_portrait` is not built with `clip_contents`.** That clips by the Control's
rectangle, not the StyleBox corner radius, so putting a `TextureRect` inside a `Panel`
(radius = diameter/2) lets the texture cover the rounded corners as-is, giving **a rectangle with only
slightly rounded corners** (measured). So it draws a **textured circular polygon** directly
(`draw_colored_polygon(points, WHITE, uvs, tex)`), with UVs matching
`KEEP_ASPECT_COVERED` (fill the short axis fully, crop the centre of the long axis).
The return value is a `Control` you may add children to — a Control's `_draw` runs
**before** its children, so the circle is the background and the children sit on top.

## Usage Pattern
```gdscript
# Reference enums
GameEnums.MatchPhase.BAN_PICK

# Create card data
var card = CardData.new("Strike", cost, "A basic attack.")

# Match-flow data
var p := PlayerData.new(0, "Corin", GameEnums.Role.ASSASSIN, 0, <stats…>)   # stat values come from players.csv
var m := MechData.new(12, name_key, hp, atk, presence)   # values come from mechs.csv (name_key = l10n key)
p.assigned_mech = m
```

## How mech skills relate to this folder
**`MechData` gained a `role` field** (GameEnums.Role, -1 = none). The old comment said
"mechs have no role — they can be seated in any slot", but once each mech got a unique card set,
those cards came to presuppose a role group. **Assignment itself is still free** — this
value is used for ban/pick screen classification and data validation, and does not block ASSIGN.

`CardData` gained five — `mech_card_id` / `mech_id` (which card number of which mech),
`trigger` (the event hook attached to that card), `charge_max` (Charge cap, `mech_cards.charge_max`),
`charge` (Charge accumulated now). The keyword **`charge`** was also added, and
**`cost = -1` means "a card that cannot be played"** (`is_playable()`) — **cost -1 receives
neither discounts nor increases**: `BattleSim.effective_cost_for` returns -1 as-is
and `_effect_cost_reduce_hand` (사전 준비 (Preparation)) skips it too. Previously -1 was treated as a plain
number and became 0 by passing through `max(0, …)`, and then every place that didn't check
`is_playable()` read that card as "a card you can play for free".
`stack_count` and the keyword `stack` (bundling in hand) were deleted, replaced by Charge.

`PilotData` gained twelve persistent states applied by mechs and three permanent stat modifiers —
for details see that file's "메크가 거는 지속 상태" (Persistent states applied by mechs) section and the
"Persistent state" (지속 상태) section of [`features/battle_sim/mech/README.md`](../features/battle_sim/mech/README.md).


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Mob pilots (모브 파일럿) | **15 without skills.** There are only 25 skills, so not all 40 can be filled, and for the remaining 15 it is the **picture**, not a name tag, that says "nameless player" — the five cuts (circle / eye / faces / tall / full) each have a full extra silhouette set (`resources/images/pilot/mob/`), and once `GameManager.load_match_data()` plants the list via `PilotImages.set_mob_ids()`, every subsequent portrait lookup switches automatically. For all five cuts the silhouette **leaves alpha untouched and covers RGB with a single colour** — a dark portrait is not a silhouette (the old method of only darkening brightness just removed colour, and facial features still read clearly). However, `faces` / `circle` / `eye` are crops where the face fills the frame (measured: 97.7% of the eye band is opaque), so painting in place gives one black circle · one black bar; only those three are made by **re-cropping head~shoulders from the `full` art** — full's alpha is the figure outline, so the background stays transparent and the head shape and shoulder line read as a silhouette (the face rectangle is found with **the same template matching** as `make_eye_crops.py`, so figure scale does not diverge from other cuts). In exchange, only mob slots frame differently, with the figure smaller than named ones. **Only `circle` bakes in an opaque circular background** — the battlefield marker lays a white circle behind the portrait while the engage arena lays nothing, so left transparent, the same picture would be a white badge on one side · a hole showing the background on the other. Stats are **10% lower** than named pilots, and that reduction is baked into **the `players.csv` values themselves**, not a runtime coefficient — leaving room to multiply in a difficulty factor later. **They are excluded from the run-setup lineup grid** (`TeamDraft.get_pool_grid`) but still sit on their teams, so you still meet them as opponents. `players.team_id` is only the **default affiliation shown in UI** — at run start `GameManager.start_run` puts my 5 on the chosen team and `RunRoster` shuffles the other 35 (named + mob) one per role onto the 7 AI teams by `run_seed` (`features/season/README.md` "Entry point"). |

### Pilot strip circular portrait shader (`shaders/pilot_bust_mask.gdshader`)
`ui/PilotStrip.gd` attaches it to a `ColorRect` per slot (not a TextureRect: the circle must be drawn
even without an image). It draws a team-colour circle (diameter = slot width) at the bottom of the slot and
lays the `strip/N_strip.png` bust over it, clipped **to the circle below the circle's centre and only to the
slot's left/right edges above it**, so the head pokes out above the circle. The circle rim (`rim_width` — the
strip currently passes 0 = **no rim**; 0 skips the ring entirely) and the downed tint (`tint` — multiplied
**into the bust only**, the team circle stays) are done by the same shader — an overlaid rectangle would also
paint the empty corners outside the circle. The old skill-readiness dim (`fill` / `dim`) was deleted. The
`rect_size` uniform must be set to the node size (the mask is measured in local pixels).

### Card art corner shader (`shaders/rounded_top_mask.gdshader`)
`Card._apply_art` attaches it to the art `TextureRect`. It rounds off the top two corners by `radius`,
computing coverage with a rounded-rectangle SDF + `fwidth` so the curve blurs across 1 screen px
(anti-aliasing — no `clip_children` staircase). The mask is measured in node-local
pixels (`VERTEX`), not UV, so the `rect_size` uniform must be set to the node size —
`STRETCH_KEEP_ASPECT_COVERED` draws only part of the texture, so UV doesn't cover the rect.
The bottom edge is not blurred (computed by extending the box downward by `radius`).

### Card art rounded-rectangle shader (`shaders/rounded_rect_mask.gdshader`)
Four-corner version of `rounded_top_mask`. Same SDF + `fwidth` anti-aliasing, same local-pixel
measurement (`rect_size` = node size). Used on card art in the pilot detail panel's lasting-effect
thumbnails (`PilotDetailPanel._make_fx_art_thumb`).

### Character silhouette shader (currently unused)
`resources/shaders/silhouette.gdshader` + `resources/SilhouetteFx.gd`
**exist but no screen calls them.** There used to be an entry cut in the outgame pilot detail popup
(`meta/run_setup/DraftDetailPanel.gd`) where the full-body art stood as a silhouette and peeled away from bottom
to top, but **that usage was removed** — the popup now shows the art as-is
(`ART_SIL_REVEAL_SEC` / `_DELAY` and the `SilhouetteFx.apply` / `play_reveal` calls disappeared
together). The shader and wiring are a tool kept for the next use.

**It does not replace the baked mob silhouette PNGs (`images/pilot/mob/`).** Those are
assets that permanently say "nameless player", and above all the `faces` / `circle` / `eye`
cuts have solid-rectangle alpha, so painting them at runtime yields a black bar. The places where the shader can live
are **cuts whose alpha is the figure outline** (the `full` / `tall` family).

Room for the border is made by insetting the art by that width (all 40 full-body artworks have the figure touching
all four edges, so otherwise the border above the head gets cut off). The parameter table and the three traps to see
before touching the shader (the fragment `COLOR` already arrives multiplied by the texture ·
no `MODULATE` built-in · `TEXTURE` can't be read in global functions) are written down with measurements in
`resources/README.md`.

---

### `CardData.from_def()` is static (moved from root CLAUDE.md)

`CardData.gd` — `from_def()` is **static** —
it is the only place that assembles one `cards.csv` row into a card, so
it must run without BattleSim (used by the ban/pick bottom sheet · mech detail.
The draft detail popup used it too, but that screen's candidate-card section was deleted)

---

### PositionBadge.gd + UI_Comp_PositionBadge.tscn (pilot position badge — every screen)
`class_name PositionBadge extends PanelContainer`. **The one way a pilot's position is shown** — a colour pill with
`TOP` / `JGL` / `MID` / `ADC` / `SUP` (`GameEnums.POSITION_ABBREVS`) in the role colour (`OutgameTheme.ROLE_COLORS`,
darkened like the old role badge). Replaces the per-screen texts ("탱커" / "미드" / "TANK" / `Tk`) and the old
`run_setup/RoleBadge`.

- **Used by**: `PilotThumb` · `DraftSlot` · `CollectionCell` (top-left of the art), `CollectionDetailSheet`
  (`PilotThumb.add_position_badge`), `DraftDetailPanel` header, `SeasonPilotCard` (hub · week),
  `MasteryPilotRow`, `RunResultPilotRow`, `IntelPilotRow`, `ShopShardRow`, `EndingView` roster, BattleSim
  `MvpView` and the victory panel's MVP row (`UI_View_BattleHud.tscn` `%PositionBadge_MvpPosition`).
- **Look**: the root attaches `OutgameTheme.tres` itself, so the badge looks the same inside dark battle scenes;
  variation `PositionBadgePanel`. Width = the widest of the five abbreviations at the current size, so text placed
  after a badge starts at the same x on every row.
- **API**: `create()`, `set_role(role) -> bool` (unknown role → hidden, false), static `abbrev(role)`,
  `@export text_size` (set per placement in the host scene; scene default 18).
- **Not badges** (prose, not a position label): card scope text (`CardData`), analyst sentences in
  `OpponentIntel`, the "no art" slab text in `MvpView` / `PilotDetailPanel`, mech roles (ban/pick `TANK` / `Tk`,
  `QuirkSystem` "탱커 메크"), battle log `pilot_label`.

### UiPreview.gd (dev — standalone-run (F6) dummy data for outgame UI scenes)

Opening an outgame UI `.tscn` and running it alone ("Run Current Scene") fills it with dummy data,
so each screen / popup / item can be checked on its own. Each scene script ends its `_ready` with
```gdscript
	if UiPreview.is_standalone(self):
		_fill_preview()
```
and keeps a private `_fill_preview()` at the bottom that fills data **through the script's normal
API**. Screens / panels / popups use real data (in-memory run from game.db, profile reads); small
item scenes use hand-written values. Script-less item scenes already show the sample text baked into
the scene. `scenes/*.tscn` roots (Lobby, RunSetup, Season, …) are real entry points — no preview.

| Function | Does |
|---|---|
| `is_standalone(node)` | `node` is the root of the scene launched with F6 (`current_scene`). Always false in release builds and whenever the scene is a child of a real screen |
| `ensure_run()` → GameManager | In-memory run via `GameManager.init_season()` (test run, **never saved**); null on failure |
| `ensure_league(host, weeks = 2)` → `LeagueManager` | Preview-only `LeagueManager` child of `host`, current phase scheduled, `weeks` weeks played with random results |
| `playoff_bracket(s, lm)` → bracket | Writes a 4-team PLAYOFF `current_tournament` (top 4 of `lm`, own team forced into 4th) shaped like `TournamentManager._bootstrap_playoff`; the caller records results |
| `stage(node)` | Outgame `BG` clear colour; a full-width top-anchored root gets side padding; any other non-full-rect Control root is centred (a zero-width container root gets screen width − padding) |
| `mute(btn, owner_obj, label)` | Disconnects the `pressed` handlers `owner_obj` wired (saves, navigation) and traces instead; `HapticUi` wiring stays |
| `trace(signal, label)` | Prints `[UiPreview] …` when the signal fires — buttons whose host (SeasonHub, LobbyScreen) is absent |

Rules: the preview never writes the run file or the profile and never changes scene; production code paths
stay unchanged (dependencies the host normally provides are injected in `_fill_preview`).
Render check without the editor: `UiSceneDumpRunner --scene res://<scene>.tscn --shot <png>` (below).

---

### UiSceneDump.gd + UiSceneDumpRunner.gd (dev tool — running UI → `.tscn` draft)

`docs/ui_scene_migration.md` §6 T4. **Saves a running, code-built UI subtree as a `.tscn` draft**
so a big screen (HubView, ban/pick) does not have to be transcribed by hand. The draft is
**reference only**: every node keeps its absolute `offset_*` from the live run, so the porting session
still rebuilds it with containers (§5 step 2) and then deletes the draft. Game code never calls it.

**Run it** (window mode for `--shot`; `--headless` is fine for a dump alone):
```
<godot> --path . --script res://resources/UiSceneDumpRunner.gd -- --scene res://scenes/Lobby.tscn --node .
<godot> --path . --script res://resources/UiSceneDumpRunner.gd -- --scene res://scenes/Season.tscn --node HubView
<godot> --path . --script res://resources/UiSceneDumpRunner.gd -- --scene res://scenes/MatchFlow.tscn \
        --press "경기 시작" --node CanvasLayer --out res://_dump/BanPick.tscn
# look at a draft (or the live screen) — no --node = screenshot only
<godot> --path . --script res://resources/UiSceneDumpRunner.gd -- --scene res://_dump/UI_View_HubView.tscn --shot <scratchpad>/draft.png
```
| Arg | Meaning |
|---|---|
| `--scene` | scene to load (required) |
| `--node` | `.` = scene root · a path containing `/` = relative to it · otherwise the first node (breadth-first) whose name, script `class_name` or engine class matches (`HubView` finds the auto-named `@Control@2`). Omitted → no dump |
| `--frames N` | frames to wait after loading and after each `--press` (default 30) |
| `--press "A\|B"` | emit `pressed` on visible Buttons found by their text, one by one — reaches a screen a tap away |
| `--out` | default `res://_dump/<name>.tscn` (auto names → script class_name) |
| `--shot path.png` | root viewport screenshot (702×1248 window) taken before dumping |
| `--keep-root-script` / `--no-scripts` | the `keep_root_script` / `keep_scripts` options below |

**Why a `--script` runner** (`extends SceneTree`): it reaches any screen without touching game code,
`project.godot` or an autoload — the scene is loaded with `change_scene_to_file` and the autoloads are
still added. `Season.tscn` / `MatchFlow.tscn` run standalone exactly like an editor F6 run:
`GameManager.use_test_run` defaults to `true`, so `init_season()` builds a fresh test run and autosaves
only into `user://run_test.save` (`features/save_load/README.md`). Verified reachable: Lobby (with the
first-run manager-type popup open), Season → HUB, MatchFlow PREP, MatchFlow BAN_PICK
(`--press "경기 시작"`). Other hub screens (training, week …) need more taps — chain `--press`.

**What `UiSceneDump.dump(root, out_path = "", opts = {}) -> Error` does** (report in
`UiSceneDump.last_report`; `report_text()` formats it — the runner prints it):
- **The live tree is not touched.** Each node is rebuilt as a fresh node of the same engine class with
  its `PROPERTY_USAGE_STORAGE` properties copied, `owner` = draft root → `PackedScene.pack()` →
  `ResourceSaver.save()`. `Node.duplicate()` is not used: it copies signal connections and doubles
  children that a script's `_init` builds.
- **Scripts**: descendants keep their script reference (§3 rule 3 — `_draw` widgets are placed as
  nodes); children a script's `_init` already built are discarded so the copied live children are not
  doubled. The **root's** script is not attached (`keep_root_script` false) — it is usually the builder
  of this very tree; its path goes into the root's `editor_description`.
- **Sub-scene instances** (`scene_file_path` set, e.g. `ConfirmPopup`) stay instances: only overrides
  are saved (editor build → `GEN_EDIT_STATE_INSTANCE`), the scene's own internals are not owned; only
  children added to it at runtime are copied.
- **Code-made resources** (`StyleBoxFlat`, code-built textures / fonts) embed as `sub_resource`s,
  counted per class in the report; file resources stay `ext_resource`.
- **Connections: none are saved.** Nothing is connected on the copies, so `pack()` has nothing to
  persist (runtime lambdas are never `CONNECT_PERSIST` anyway — verified: no `[connection]` in the
  drafts); the dropped count is reported. **A `draw` signal callback is the drawing itself** (e.g.
  `OutgameTheme`'s round portrait) → that node renders **empty** in the draft and its
  `editor_description` says so.
- `metadata/*` is dropped (`keep_meta`) — runtime markers like HapticUi's `haptic_bound` would make the
  ported scene skip its binding. Unsaveable values (Callable / RID / non-Resource objects) are dropped.
- Auto names `@Label@123` → `Label_<text>` (script class_name first if any; `rename_auto`). Scripted
  nodes and the root get `editor_description = "dump: …"` — the prefix keeps them apart from the §3
  rule 5 `TODO:` marks.

**Limitations**: absolute positions only (rebuild with containers); one captured state (current texts,
visibility, one tab — open other tabs / popups first via `--press`); non-exported script state is lost,
so a kept `_draw` widget draws its default state, and a kept builder-like script rebuilds its children
if the draft is *run* (the editor does not run non-`@tool` scripts, so editing is unaffected); runtime
children under a scene-owned node of an instance are lost; no uid (open + save in the editor if a draft
is ever kept). Measured: Lobby, HubView and BanPick drafts render **pixel-identical** to the live
screen; MatchFlow PREP differs only in its 10 round portraits (`draw` callbacks).

**`_dump/` is gitignored — never commit drafts.**
