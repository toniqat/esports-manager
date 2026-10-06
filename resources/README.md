# Resources

Shared data definitions used across features.

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
  휘발성 / `charge` 충전 (Charge) / `reposition` 재배치). Read it only through `has_keyword()`; the
  on-screen name and explanation come from `keyword_label()` / `keyword_note()` (`KEYWORD_LABELS` /
  `KEYWORD_NOTES`). **Charge is the keyword; what Charge accumulates is tokens** (the `charge` field)
- `effect: String` — semicolon-chain dispatched by `CardPhaseManager`
  (e.g. `"draw:N;discard:N"`, `"attack:N|pierce"`)
- `description: String` — printed verbatim on the **description plate under the art** on the card face (font size shrinks only when it overflows — `Card._fit_desc_font_size`); the same sentence also appears in the description box at the top of the screen
- `scope: String` — **position list**. `any` alone = all, `lane` alone = top ·
  mid · carry · support, otherwise a `|` list of `jungle` / `top` / `mid` / `carry` / `support`.
  `positions_of(scope)` expands it (if only unknown tokens, all positions),
  `allowed_for_position(pos)` checks it, and `scope_label(scope)` turns it into readable text
  like "탑 · 미드 · 원딜" (Top · Mid · Carry).
- `pool: int` — `1` = pilot card candidate, `0` = excluded (duel · objective reward · skill-generated cards).
- `card_type: String` — every row in cards.csv is `pilot`. `mech` is stamped by `make_mech_card`
  only on `mech_cards.csv` rows.
- `card_cat: String` — **category `|` list** (`CAT_*`: growth / engage / ambush /
  attack / defense / utility / draw / jungle / lane; grant-only `-`). `categories()` /
  `fits_any_category(cats)` / `category_label()`. Cells in the position slot table pick
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
  `POSITION_LABELS`, `position_key(role)` — the strings used by card `scope` and
  `pilot_card_slots.position` (they are values humans type directly into CSV, so they are not enum values)

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
`growth` = attack share (`GROWTH_ATK_PER_SCORE` per 1k), `growth_hp` = max-HP share
(`GROWTH_HP_PER_SCORE` per 1k) — both in const.csv.
**This asymmetry — attack growing several times faster than HP — is the whole feel of growth**, so
tune the two keys together. Instead of multiplying each turn, stats are **recomputed** from the two originals (prevents
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
equivalent to gold in a MOBA. There are three sources:
**front line (전선) presence** (`SCORE_FRONTLINE_PER_TURN`) / **jungle camp (캠프)** (`SCORE_JUNGLE_CAMP`,
respawn `JUNGLE_CAMP_RESPAWN_TURNS`, jungler) / **kill (처치) bounty** (last hit `SCORE_KILL_BASE` +
`SCORE_KILL_BOUNTY_RATE` of the lead gap; assists get up to `SCORE_ASSIST_MAX_SHARE` proportional to damage).
Turret (포탑) demolition `SCORE_TURRET_FULL`. **Turret/HQ damage and death penalties were deleted.** No cap,
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
- `id, name, role (GameEnums.Role), team_id (0=player, 1=enemy)`
- `pilot_cards: Array` — **3 fixed pilot cards** (`cards.id`, `players.pilot_cards`). Saved with the save file; if empty (old save), `GameManager.pilot_card_ids_for` fills it from the DB row with the same id → then a seeded draw, in that order.
- **6 player (선수) stats** — `field_hit` battlefield hit / `field_eva` battlefield evasion /
  `engage_hit` engage hit / `engage_eva` engage evasion / `atk_growth` attack growth coefficient /
  `hp_growth` HP growth coefficient. **Floor `STAT_MIN` (const.csv `PLAYER_STAT_MIN`), no cap** (weekly training pushes them past 100).
  The tables are the four `STAT_KEYS` / `STAT_LABELS` / `STAT_SHORT` / `STAT_NOTES`, and every screen
  reads them. Power totals are `stat_total()` / `stat_avg()`; growth coefficient → multiplier conversion is
  `static growth_mult(v)` = `v / GROWTH_STAT_BASE` (const.csv `PLAYER_GROWTH_STAT_BASE`). The old 5 stats (`laning` /
  `mechanics` / `gamesense` / `teamfight` / `mental`) were deleted
- `assigned_mech: MechData` — written by the assignment step of the ban/pick screen (`ban_pick/BanPickController._finish`). Previously this was the job of `AssignController`, which was a separate screen

Loaded from the `players` table (CSV-seeded via `addons/csv_to_db`).

### MechData.gd
`class_name MechData`, extends `Resource`.

Mech with **no role/position** — any mech is assignable to any player slot:
- `id, name`
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
portraits under `resources/images/pilot/{faces,circle,eye,tall,full,ribbon}/`, plus the
**mob silhouette (모브 실루엣)** set that mirrors them under `pilot/mob/`.

| Function | File | Size | Consumer |
|---|---|---|---|
| `face_for` | `faces/N_rect.png` | 256² | Draft grid thumbnail (`meta/run_setup/PilotThumb.gd`) |
| `circle_for` | `circle/N_circle.png` | 256² circular | Battlefield marker · engage stage portrait |
| `eye_for` | `eye/N_eye.png` | **480×200** | Pilot strip (`ui/PilotStrip.gd`) |
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
| `art_for(card_name)` | `images/card/<이름>.png` (name) → item icon → background | `Card._apply_art` (card face art frame) |
| `item_for(card_name)` | `images/ground/deadlock_items/<타입>_<아이템>.png` (type_item; `ITEM_ART` table) | 〃 (cards without dedicated art) |
| `type_for(card_name)` | prefix of the `ITEM_ART` value → `TYPE_WEAPON` / `TYPE_SPIRIT` / `TYPE_VITALITY` (`""` = not in table) | `Card._apply_name_plate` (nameplate (이름판) type colour `Card.TYPE_COLORS`) |
| `ground_for(card_name)` | `images/ground/N.png` (`GROUND_COUNT` 5 images) | 〃 (cards not even in the `ITEM_ART` table) |

**Every card right now (cards.csv 43 + mech_cards.csv 64 = 107) carries an item icon.**
`ITEM_ART` is a card name → Deadlock item filename table, picking items with similar effects
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

**The background is picked by card name** (`card_name.hash() % GROUND_COUNT`). Picking at random
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

### UiHelpers.gd
`class_name UiHelpers`, extends `RefCounted`. Static helpers for
procedurally-built UI panels — currently `mk_label(...)` shared by MatchFlow
controllers and HudBuilder.

### OutgameTheme.gd
`class_name OutgameTheme`, extends `RefCounted`. **Every colour on outgame screens passes
through here** — season hub · press conference (기자회견) · training board · time-passing · standings · brackets ·
draft. If each screen held its own `Color(...)` literals, the same card would be drawn in a different grey
per screen, and touching up the palette once would mean combing through a dozen-odd files.
**In-game (BattleSim) does not use this table** — the battlefield is a dark screen, and there
a white card becomes a glaring slab.

The design principle is coloured cards on white paper. Three rules:

1. Background is `BG`; content sits on `SURFACE` cards that are **even whiter**. Boundaries are made not by lines
   but by **shadow and brightness difference** (`BORDER` is very faint).
2. Emphasis uses one colour field (`ACCENT`) only — which weekday it is now, which button to press now.
   **Amber for text is `ACCENT_TEXT`** (using `ACCENT` as-is for text on white paper
   lacks contrast. It is a separate literal because `darkened()` is not a constant expression in a
   `const` slot).
3. Classification is done by the card's left colour bar (`lead_bar_style`) or card colour field (`CARD_TINTS`).
   The five role colours (`ROLE_COLORS`) and role names (`ROLE_NAMES`) are also owned here —
   in `GameEnums.Role` order (not seat order).

| Group | Exports |
|---|---|
| Colour | `BG` `SURFACE` `SURFACE_SUNK` `RAIL` `RAIL_TEXT` / `TEXT` `TEXT_SUB` `TEXT_FAINT` `TEXT_ON_FILL` / `ACCENT` `ACCENT_DIM` `ACCENT_TEXT` `LINK` / `POSITIVE` `NEGATIVE` `NEUTRAL` / `BORDER` `BORDER_STRONG` `SHADOW` / `CARD_TINTS` `ROLE_COLORS` `ROLE_NAMES` `DAY_LETTERS` `DAY_NAMES` |
| StyleBox | `card_style` `flat_style` `lead_bar_style` `set_corner_radius` |
| Button | `style_primary_button` (amber, one per screen) `style_ghost_button` `style_text_button` `style_dark_button` (dark colour field — "leave this screen") |
| Bottom bar | `BOTTOM_BAR_H` (128) `bottom_bar_top()` `add_bottom_bar(parent, specs)` `layout_bottom_bar(buttons, specs)` `style_bottom_button(b, style, font)` |
| Pieces | `add_background` (internally calls `ScreenMetrics.extend_background`) `add_card` `add_divider` `add_round_portrait` `add_chip` `add_vscroll` |

**Button styles decide colour only — feel is not decided here.** At one point these four
functions also set the strength via `HapticUi.kind` (primary · dark = `MEDIUM` / ghost =
`LIGHT` / text = `SELECT`), but that table was scrapped. Now **every button gives the same two beats
regardless of kind** — `LIGHT` on press, `SOFT` on release. Whether it is a confirm or a tab
switch is for the screen to say; a feel in the hand that wobbled per screen was itself
noise. The full wiring is in the `HapticUi.gd` section of `autoloads/README.md`.

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
- **Buttons that change outfits use `style_bottom_button`.** Calling `style_dark_button`
  directly brings back rounded corners and that slot alone pops back up off the screen
  (the time-passing screen's "경기 시작" (Start match) switches this way).

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
var m := MechData.new(12, "Overdrive", hp, atk, presence)   # values come from mechs.csv
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

### Card art corner shader (`shaders/rounded_top_mask.gdshader`)
`Card._apply_art` attaches it to the art `TextureRect`. It rounds off the top two corners by `radius`,
computing coverage with a rounded-rectangle SDF + `fwidth` so the curve blurs across 1 screen px
(anti-aliasing — no `clip_children` staircase). The mask is measured in node-local
pixels (`VERTEX`), not UV, so the `rect_size` uniform must be set to the node size —
`STRETCH_KEEP_ASPECT_COVERED` draws only part of the texture, so UV doesn't cover the rect.
The bottom edge is not blurred (computed by extending the box downward by `radius`).

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
