# Resources

Shared data definitions used across features.

## Files

### CardData.gd
`class_name CardData`, extends `Resource`.

One row from the `cards` SQLite table, plus a few runtime fields:
- `card_name: String`
- `cost: int` — 작전 점수 cost
- `uses: int` — max plays per match (0 = unlimited)
- `cast_method: String` — `range / target / location / instant`
- `target: String` — `caster / enemy / ally / pilot / hand / location`
- `cast_range: int` — tiles from caster (0 = self, 99 = unbounded)
- `area: int` — AoE radius around target (0 = single)
- `keyword: String` — empty or `"exhaust"` (소멸)
- `effect: String` — semicolon-chain dispatched by `CardPhaseManager`
  (e.g. `"draw:2;discard:2"`, `"attack:1|pierce"`)
- `description: String` — text shown on the card front + description box
- `scope: String` — `any` / `lane` / `jungle` (`SCOPE_*` consts). 시전자 제약;
  read once, at deal time, by `CardPhaseManager._pool_for_pilot` via
  `allowed_for_guerrilla(is_guerrilla)`. `lane` cards never reach a 정글러 and
  `jungle` cards never reach a 레인 파일럿. Unknown values = unrestricted.
- `pool: int` — `1` = in the random starter-deck pool, `0` = excluded (결투).
- `card_type: String` — `mech` / `pilot` (`TYPE_*` consts). 덱 구성의 1차 분류:
  파일럿마다 `mech` 3장 + `pilot` 3장을 받는다.
- `card_cat: String` — `-` / `lane` / `draw` / `jungle` / `common` (`CAT_*`
  consts). 파일럿 카드의 슬롯 분류. `fits_category(cat)` 가 매칭을 답하고,
  **`common` 은 라인전 슬롯과 정글 슬롯 양쪽에 든다** — 복귀(id 21) 하나뿐이며,
  라인전 카드이면서 정글러도 뽑을 수 있어야 하기 때문. `scope` 와 역할이
  다르다: `scope` 는 *누가 가질 수 있는가*, `card_cat` 은 *어느 슬롯을 채우는가*.
- `owner_pilot: PilotData` (runtime, **not** `@export`) — the 시전자, set
  by `CardPhaseManager.build_starter_decks()`

Instantiated at runtime by `CardPhaseManager.build_starter_decks()` from the
`cards` SQLite table (loaded into `GameManager.card_pool_bs`). Not saved to disk.

### GameEnums.gd
`class_name GameEnums`, extends `RefCounted`.

Shared enum definitions:
- `Role { TANK, FIGHTER, ASSASSIN, SUPPORT, SNIPER }` — pilot/player position
- `LanePosition { LEFT, CENTER, RIGHT, GUERRILLA }` — battle-lane slot
- `Lane { LEFT, CENTER, RIGHT }` — waypoint/building lanes (no GUERRILLA)
- `BattlePhase { GAMBIT, CARD_PHASE, BATTLE }` — in-battle phase machine
- `TowerLevel { HQ, LEVEL_2, LEVEL_1 }` — building atlas selector
- `MatchPhase { LOAD, BAN_PICK, ASSIGN, JUNGLE_START, LAUNCH }` — out-of-battle pipeline
- `JungleStartDir { LEFT, RIGHT }` — assassin's jungle entry side
- `DraftSide { BLUE, RED }` — ban/pick draft sides

### PilotData.gd
`class_name PilotData`, extends `RefCounted`.

In-battle pilot state: role, hp/max_hp, atk, team, grid_pos, lane, waypoint_idx,
`move_range` (cells per minute), `jungle_start_pref` (GameEnums.JungleStartDir
or -1), plus combat dice stats `hit` and `evasion` populated from PlayerData
(`mechanics` → hit, `gamesense` → evasion).

`presence` is copied from the assigned mech and is **read only by the 교전 무대**
(`TurnEngageSim`) as the target aggro weight. The battlefield ignores it.
Fallback when no mech is assigned (standalone battle): 4 melee / 2 ranged.

> **`speed` 는 삭제됐다.** 교전이 ATB 실시간에서 **라운드 기반 턴제**로 바뀌면서
> 라운드마다 전원이 정확히 한 번씩 행동하므로, "행동 빈도"를 가르는 스탯이
> 존재하지 않는다. `mechs.csv` 컬럼 · `MechData.speed` · `PilotData.speed` ·
> `game_config.TURRET_SPEED` 가 모두 제거됐다 — 되살리지 말 것.

`respawn_timer: int` is the off-field clock and **death is the only thing that
puts a pilot off the field**. It counts down from `BattleSim.respawn_turns_now()`
in `SimulationCore.process_respawns` while `alive = false`. **Never read it
directly to show "turns left"** — call `BattleSim.turns_until_return(p)`, which
also floors the answer at 1 for a downed pilot so a card doesn't flicker
unlocked on the tick before the return.

`recall_hold: bool` is the 본진 복귀 cost. A recall (`RecallSystem.return_to_hq`)
lands the pilot in its HQ at full HP **without touching `alive`** — it is in
play the whole time — and sets this flag; `SimulationCore.resolve_movement`
spends it to skip the pilot for exactly one movement pass, so the lane walk
restarts from waypoint 0 the next turn. Nothing else reads it. (The former
model — off the field, healing `RECALL_HEAL_RATIO` per turn until full — and its
`is_recalling` flag are both gone.)

**성장 필드 6개** — `base_atk` / `base_max_hp` / `growth` / `growth_rate_mult` /
`growth_rate_expire_turn` / `growth_until_phase`. 매 턴
`SimulationCore.tick_growth_and_expiries` 가 살아 있는 파일럿의 `growth` 를
`BattleSim.GROWTH_PER_TURN × growth_rate_mult` 만큼 올리고, `atk` / `max_hp` 를
**원본에서 다시 계산**한다(매 턴 곱하면 반올림 오차가 누적된다). 두 원본은
`_init` 이 채운다 — 메크 스탯 주입(`SimulationCore._stats_for`)이 생성자를
거치므로 어떤 스폰 경로에서도 비지 않는다. `growth` 는 파일럿에 붙어 있어
**사망·리스폰으로 초기화되지 않는다**(죽어 있는 동안 성장이 멈출 뿐).
`growth_rate_mult` 는 안전한 파밍(턴 만료)과 완벽한 마무리(작전 단계 만료)가
공유하므로 나중에 건 쪽이 덮어쓴다.

**성장치 `score`** (개시 1.0) — 위의 `growth` 와 **다른 것이다**. `growth` 는
스탯을 밀어 올리는 배율이고, `score` 는 스탯에 아무 영향이 없는 **기여 지표**다
(처치 / 사망 / 준 피해 / 포탑 · HQ 피해로 누적, 상한 없음, 하한 0.10).
파일럿 스트립에 `1.00k` 형식으로 찍히고 팀 점수는 팀원 합산이다. 적립 규칙과
상수는 전부 `BattleSim` 의 `SCORE_*` 절에 있고 변동은 `BattleSim.add_score`
한 곳만 지난다 — 이름이 비슷해 헷갈리기 쉬우니 필드도 갈라 두었다.

**라인전 스탯 2개** — `lane_stat_mod` (±0.10) / `lane_stat_expire_turn`.
`SimulationCore.roll_hit` **한 곳에서만** 읽히며, 공격자의 `hit` 과 방어자의
`evasion` 에 각자 자기 배율이 곱해진다(`lane_adjusted`). `atk` / `max_hp` 는
건드리지 않는다 — 그쪽은 성장 담당이다. 전장 자동 교전과 공격 카드가 같은
`roll_hit` 을 쓰므로 둘 다 반영되고, 교전 무대는 자기 확률 구간을 쓰므로
반영되지 않는다.

`jungle_roam_target: Vector2i` ((-1,-1) = none) is the jungler's sticky roam
destination, held across turns by `SimulationCore._jungle_goal_for` so the
target cannot flip mid-route and bounce the jungler between two cells. Only
that function writes it; nothing else on `PilotData` reads it.

`shield: int` is the 보호막 pool granted by the 보호 card. Both card attacks
and battlefield damage (the `damage_map` apply step in `SimulationCore.simulate_turn`)
subtract from `shield` first, then `hp`. Cleared on every 본진 복귀 path:
`RecallSystem.return_to_hq` (저HP / 위치 이탈 복귀),
`CardPhaseManager._effect_recall_ally` (복귀 card),
`SimulationCore.process_respawns` (부활) and
`BattleSim.mark_pilot_dead` (death).
`BattleRenderer._draw_pilot_circle` paints a cyan ring just outside the HP ring
sized by `shield / max_hp` so the buff is visible on the field.

UI animation fields (`anim_prev_grid_pos`, `anim_move_t/dur`, `anim_shake_t/dur`,
`anim_recall_phase/t/dur/orig`, `anim_death_phase/t/dur/cell`) are mutated by
`BattleSim.anim_pilot_*` helpers and read only by `BattleRenderer` — the
simulation never reads them. The recall sequence always plays both halves
(fade-out at the old cell → fade-in at HQ), since a 복귀 never removes the pilot
from the field; the `anim_death_*` group is what keeps a killed pilot on screen
(dimmed, then fading upward) after `alive` has already flipped to false.

### TurretData.gd
In-battle turret state — see `features/battle_sim/README.md`.

`anim_hit_t` / `anim_hit_dur` are the 피격 연출 timer, set by
`BattleSim.anim_turret_hit` and consumed by `BattleSim._advance_turret_animations`.
Like the `PilotData.anim_*` group the simulation never reads them, but the
consumer differs: the shake/flash is written onto the turret's `Building` node
(BattleSim owns that), and only the HP-bar offset goes through `BattleRenderer`
via `BattleSim.turret_hit_offset(td)`.

### PlayerData.gd
`class_name PlayerData`, extends `Resource`.

Out-game player persona consumed by MatchFlow / BattleSim:
- `id, name, role (GameEnums.Role), team_id (0=player, 1=enemy)`
- Stats `laning, mechanics, gamesense, teamfight, mental` (each 1–100)
- `assigned_mech: MechData` — set by AssignController at match prep time

Loaded from the `players` table (CSV-seeded via `addons/csv_to_db`).

### MechData.gd
`class_name MechData`, extends `Resource`.

Mech with **no role/position** — any mech is assignable to any player slot:
- `id, name`
- Combat stats `hp, atk` — drive PilotData stats when piloted
- `presence` (4 = melee / 2 = ranged) — **교전 무대 전용**. 타겟 어그로 가중치
  (높을수록 자주 표적이 된다)

> **`speed` 는 삭제됐다** — 교전이 라운드 기반 턴제가 되면서 행동 빈도 개념이
> 사라졌다. `mechs.csv` 의 컬럼과 `csv_to_db.gd` 의 스키마에서도 빠졌으므로,
> 되살리려면 CSV 컬럼 · 스키마 · `GameManager` 로더 · `_stats_for` 를 함께
> 되돌려야 한다.

Loaded from the `mechs` table.

### BuildingData.gd / WaypointData.gd
Optional inspector-set blueprint resources for `Building` / `Waypoint` nodes
under `BattleField/BuildingLayer` and `BattleField/WaypointLayer`.

### PilotImages.gd
`class_name PilotImages`, extends `RefCounted`. Static lookup for the pilot
portraits under `resources/images/pilot/{faces,circle,eye,full}/`.

| 함수 | 파일 | 크기 | 소비자 |
|---|---|---|---|
| `face_for` | `faces/N_rect.png` | 256² | (현재 없음 — 예전 상단 슬롯이 쓰던 컷) |
| `circle_for` | `circle/N_circle.png` | 256² 원형 | 전장 마커 · 교전 무대 초상화 |
| `eye_for` | `eye/N_eye.png` | **480×200** | 파일럿 스트립 (`ui/PilotStrip.gd`) |
| `full_for` | `full/N_full.png` | 가변 × 1024 | 파일럿 상세 패널 (`ui/PilotDetailPanel.gd`) |

**`eye/` 는 손으로 자르지 말 것** — `resources/images/pilot/make_eye_crops.py`
가 `full/` 아트에서 자동으로 만든다. 얼굴 위치를 추측하지 않고 `faces/N_rect.png`
를 `full/` 안에서 **다중 스케일 템플릿 매칭**으로 되찾아(실측 상관계수 0.84~0.99)
그 사각형 높이의 0.38 지점을 눈 중심으로 잡고 2.4:1 밴드를 잘라 낸다. 손으로
자르면 파일럿마다 얼굴 배율이 어긋나 스트립이 들쭉날쭉해진다. **예외 1건**:
pid 16 은 `faces/16_rect.png` 가 `full/16_full.png` 와 **다른 일러스트**(다른
코스튬 · 포즈)라 매칭이 0.554 로 떨어지고 무기 부품에 오매칭된다 — 스크립트의
`OVERRIDE` 에 눈 좌표를 직접 박아 두었다.

`prime_into(parent)` 는 **circle / face 만** 프라임한다. eye / full 은 `TextureRect`
노드에만 쓰이고 노드에 할당하는 경로는 GPU 업로드가 보장되므로 대상이 아니다.

**id ↔ file ↔ 이름은 한 줄로 묶여 있다.** `players.csv` 의 pilot id `N` 은
`N+1_rect.png` / `N+1_circle.png` 를 쓰고(파일명은 1-based, id 는 0-based),
그 그림이 **어떤 젠레스 존 제로 에이전트인지**가 곧 `players.csv` 의 `name`
이다 — 40장 전부 공식 에이전트 아이콘 아트와 1:1로 대조해 붙인 이름이다.
그러므로 **`players.csv` 의 행 순서나 id 를 바꾸면 이름과 초상화가 어긋난다.**
스탯을 옮기고 싶으면 id 는 고정한 채 스탯 열만 옮길 것.

네 자리는 같은 캐릭터의 **대체 코스튬 아트**라 원래 이름을 쓸 수 없어 별도 태그를
붙였다 — id 6 `Soldier 0`(Soldier 0 - Anby, id 13 `Anby` 와 동일 인물의 별개
에이전트), id 26 `Chandelier`(Astra Yao / Chandelier, id 25 `Astra`),
id 28 `Teatime`(Sunna / Afternoon Tea Break, id 27 `Sunna`),
id 36 `Ink`(Yixuan / Trails of Ink, id 35 `Yixuan`).

INTL 파일럿(id ≥ 100)은 초상화가 없다 — `has_image()` 가 false 를 돌려주고
호출자가 플레이스홀더로 대체한다. `intl_players.csv` 의 이름은 그래서 초상화
제약 없이 **남은 에이전트 중에서** 골라 붙였다.

`prime_into(parent)` 는 반드시 `BattleSim._ready()` 같은 진입 시점에 한 번
불러야 한다 — 안 부르면 `draw_texture_rect` 가 흰 사각형을 그린다.

### UiHelpers.gd
`class_name UiHelpers`, extends `RefCounted`. Static helpers for
procedurally-built UI panels — currently `mk_label(...)` shared by MatchFlow
controllers and HudBuilder.

## Usage Pattern
```gdscript
# Reference enums
GameEnums.MatchPhase.BAN_PICK

# Create card data
var card = CardData.new("Strike", 1, "A basic attack.")

# Match-flow data
var p := PlayerData.new(0, "Corin", GameEnums.Role.ASSASSIN, 0, 95, 95, 98, 95, 98)
var m := MechData.new(12, "Phantom-S1", 90, 26, 4)   # id, name, hp, atk, presence
p.assigned_mech = m
```
