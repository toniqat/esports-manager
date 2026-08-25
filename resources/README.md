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

**성장 필드 8개** — `base_atk` / `base_max_hp` / `growth` / `growth_hp` /
`atk_buff` / `growth_rate_mult` / `growth_rate_expire_turn` / `growth_until_phase`.

**성장은 시간이 아니라 성장치(`score`)가 만든다.** 예전에는
`SimulationCore.tick_growth_and_expiries` 가 매 턴 `GROWTH_PER_TURN` 을 누적했는데,
그러면 (1) 아무것도 안 해도 자라 킬·포탑·파밍이 성장에 아무 영향이 없었고,
(2) `atk` 와 `max_hp` 가 **같은 비율**로 자라 "몇 대 맞아야 죽는가"가 영원히
그대로였다. `GROWTH_PER_TURN` 은 game_config 에서 삭제됐다.

지금은 `BattleSim.refresh_growth_stats` 가 성장치에서 둘을 파생시킨다 —
`growth` = 공격력분(+8.33%p per 1k), `growth_hp` = 최대 체력분(+2.08%p per 1k).
**공격력이 4배 빠르게 자라는 이 비대칭이 성장 체감의 전부다**(25k 에서 atk ×3.0 /
hp ×1.5). 스탯은 매 턴 곱해 나가는 대신 두 원본에서 **다시 계산**한다(반올림
오차 누적 방지). 두 원본은 `_init` 이 채운다 — 메크 스탯 주입
(`SimulationCore._stats_for`)이 생성자를 거치므로 어떤 스폰 경로에서도 비지
않는다. 재계산은 점수가 움직이는 그 순간(`add_score`)에 돈다.

`atk_buff` 는 카드가 거는 **일시** 공격력 가산이다. `atk` 를 직접 밀면 턴
한가운데의 재계산에 지워지고 턴 끝의 되돌리기가 원본을 깎으므로, 별도 필드로
들고 있다가 `base × (1 + growth) + atk_buff` 로 마지막에 더한다.

`growth_rate_mult` 는 이제 성장이 아니라 **성장치 적립**에 곱해진다(안전한
파밍 턴 만료 / 완벽한 마무리 작전 단계 만료) — 결과는 같고 배선이 한 겹 준다.
둘이 같은 필드를 공유하므로 나중에 건 쪽이 덮어쓴다.

**성장치 `score`** (개시 1.0) — 위의 성장의 **원천**이다. 파일럿의 성장 통화이고
MOBA 의 골드에 해당한다(개시 1.00k → 50턴 25k → 캐리 40k+). 적립처는 셋이다:
**전선 체류**(턴당 0.50k) / **정글 캠프**(0.50k, 4턴 리스폰, 정글러) / **처치
현상금**(라스트힛 1.5k + 앞선 격차 20%, 어시스트가 피해 비례로 최대 50%). 포탑
철거 +1.0k. **포탑/HQ 피해와 사망 벌점은 삭제됐다.** 상한 없음, 하한 0.10k.
파일럿 스트립에 `18.05k` 형식으로 찍히고 팀 점수는 팀원 합산이다. 규칙과 상수는
전부 `BattleSim` 의 `SCORE_*` 절에 있고 변동은 `BattleSim.add_score` 한 곳만
지난다 — 하한 · 적립 배율 · 스탯 재계산을 한 자리에서만 처리하기 위해서다.

**`damage_credit: Dictionary`** (`공격자 → 이번 생에 받은 누적 피해`) — 피해는
곧장 점수가 되지 않고 **피해자의 이 장부**에 쌓였다가, 그 대상이 쓰러질 때
`BattleSim._payout_kill_bounty` 가 라스트힛과 어시스트에게 나눠 주고 비운다.
전장 자동 교전 · 공격 카드 · 교전 무대가 전부 `BattleSim.record_pilot_damage`
한 지점을 지나므로 표가 하나다.

**라인전 스탯 2개** — `lane_stat_mod` (±0.10) / `lane_stat_expire_turn`.
`SimulationCore.roll_hit` **한 곳에서만** 읽히며, 공격자의 `hit` 과 방어자의
`evasion` 에 각자 자기 배율이 곱해진다(`lane_adjusted`). `atk` / `max_hp` 는
건드리지 않는다 — 그쪽은 성장 담당이다. 전장 자동 교전과 공격 카드가 같은
`roll_hit` 을 쓰므로 둘 다 반영되고, 교전 무대는 자기 확률 구간을 쓰므로
반영되지 않는다.

**`prev_grid_pos: Vector2i` 는 삭제됐다.** 유일한 소비자가
`BattleRenderer._pilot_travel_dir`(초상화를 "온 방향의 반대쪽"에 앉히던 규칙)
였는데, 초상화 자리가 **팀 고정**(아래 진영 = 타일 아래 / 위 진영 = 타일 위)으로
바뀌면서 아무도 읽지 않게 됐다. 갱신 배선(`anim_pilot_move` /
`anim_pilot_move_path` / 복귀 / 부활 4곳)도 함께 걷어 냈다 — 되살릴 일이 생기면
커밋 64bec06 을 볼 것. 아래 `anim_move_path` 와 헷갈리지 말 것: 저쪽은 연출용
경로이고 렌더러가 읽는 즉시 비운다.

`anim_move_path: Array[Vector2i]` 는 **이번에 실제로 밟은 칸의 경로**
(`[출발 칸, …, 도착 칸]`)다. `SimulationCore.resolve_movement` 이 락스텝
라운드마다 칸을 붙이고(`move_range` 2), 전진 카드는 같은 프레임의 걸음을
`BattleSim.anim_pilot_move` 가 이어 붙인다. `BattleRenderer._sync_glide` 가
읽는 즉시 `clear()` 하므로, 다음 턴 이동은 빈 배열에서 새 경로로 시작한다.
**연출 시간은 여기 없다** — 타이머는 렌더러(`_glide`)가 쥐고 있고, 예전의
`anim_prev_grid_pos` / `anim_move_t` / `anim_move_dur` 는 삭제됐다.

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

UI animation fields (`anim_move_path`, `anim_shake_t/dur/amp`,
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
portraits under `resources/images/pilot/{faces,circle,eye,tall,full}/`, plus the
**모브 실루엣** set that mirrors all five under `pilot/mob/`.

| 함수 | 파일 | 크기 | 소비자 |
|---|---|---|---|
| `face_for` | `faces/N_rect.png` | 256² | (현재 없음 — 예전 상단 슬롯이 쓰던 컷) |
| `circle_for` | `circle/N_circle.png` | 256² 원형 | 전장 마커 · 교전 무대 초상화 |
| `eye_for` | `eye/N_eye.png` | **480×200** | 파일럿 스트립 (`ui/PilotStrip.gd`) |
| `tall_for` | `tall/N_tall.png` | **210×700** | 교전 아레나 하단 스트립 (`engage/EngageArena.gd`) |
| `full_for` | `full/N_full.png` | 가변 × 1024 | 파일럿 상세 패널 (`ui/PilotDetailPanel.gd`) |

**`eye/` 는 손으로 자르지 말 것** — `resources/images/pilot/make_eye_crops.py`
가 `full/` 아트에서 자동으로 만든다. 얼굴 위치를 추측하지 않고 `faces/N_rect.png`
를 `full/` 안에서 **다중 스케일 템플릿 매칭**으로 되찾아(실측 상관계수 0.84~0.99)
그 사각형 높이의 0.38 지점을 눈 중심으로 잡고 2.4:1 밴드를 잘라 낸다. 손으로
자르면 파일럿마다 얼굴 배율이 어긋나 스트립이 들쭉날쭉해진다. **예외 1건**:
pid 16 은 `faces/16_rect.png` 가 `full/16_full.png` 와 **다른 일러스트**(다른
코스튬 · 포즈)라 매칭이 0.554 로 떨어지고 무기 부품에 오매칭된다 — 스크립트의
`OVERRIDE` 에 눈 좌표를 직접 박아 두었다.

**`tall/` 도 손으로 자르지 말 것** — `make_tall_crops.py` 가 같은 얼굴 템플릿
매칭으로 `full/` 에서 만든다(같은 `OVERRIDE` 예외 1건). 구도는 **머리~허벅지**:
얼굴 사각형 위로 `TOP_PAD`(얼굴 높이 ×0.30)만큼 여백을 두고 아래로
`BUST_H`(×4.40) 내려간 세로 밴드를 잘라, 폭은 **얼굴 높이 × `BAND_W_FACES`
1.32** 로 정한다(`ASPECT` 는 그 둘에서 유도되는 0.30).

**밴드 폭(얼굴 높이 ×1.32)은 고정 상수로 두고 길이만 만진다.** 스트립 칸 폭이
90px 로 고정이라 이 값이 곧 화면에서의 얼굴 크기다 — `BUST_H` 를 늘릴 때 폭까지
같이 늘리면 얼굴이 작아져 스트립에서 안 읽힌다. 지금 값은 세로 1920 화면에서
스트립 아래로 556px 가 그냥 비어 있던 것을 메우려고 **2.40(머리~가슴, 220×400)
에서 4.40 으로 늘린 것**이고, 화면 칸도 90×164 → **90×300** 으로 함께 커졌다.
둘은 `STRIP_PORTRAIT_H = 90 × BUST_H / 1.32` 로 묶여 있으니 반드시 같이 고칠 것.
폭을 어깨 실루엣에 맞추면 파일럿마다 인물 크기가 달라진다 — 출력 비율을 고정하는
쪽이 열 명이 한 줄에 섰을 때 얼굴 크기를 고르게 만든다.

`prime_into(parent)` 는 **circle / face / tall** 을 프라임한다. eye / full 은
`TextureRect` 노드에만 쓰이고 노드에 할당하는 경로는 GPU 업로드가 보장되므로
대상이 아니지만, **tall 은 `draw_texture_rect` 로 그려지므로 프라임이 필수다** —
빠뜨리면 교전 스트립의 초상화 열 칸이 통째로 흰 사각형으로 나온다(실측 확인).

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

#### 모브 파일럿 실루엣 (`pilot/mob/`)
`pilot_skills.csv` 가 25개뿐이라 40명 중 **15명은 고유 스킬이 없다**
(`players.csv` 의 `is_mob = 1`). 그 15명은 이름표가 아니라 **그림**이 "이 선수는
이름 없는 선수다"를 말한다 — 다섯 컷이 통째로 실루엣 한 벌 더 있고,
`GameManager.load_match_data()` 가 `PilotImages.set_mob_ids()` 로 id 목록을 한
번 심으면 그 뒤의 모든 조회(전장 마커 · 스트립 · 교전 무대 · 상세 패널)가 자동으로
`pilot/mob/{faces,circle,eye,tall,full}/` 쪽으로 갈린다. 파일명은 원본과 같다.
목록이 비어 있으면(BattleSim 단독 실행) 전원이 평소 컷으로 나온다 — 폴백이
원본이라 심는 것을 잊어도 흰 사각형이 뜨지는 않는다.

**만드는 것은 `make_mob_silhouettes.py`** 이고 다섯 컷 모두 **알파는 그대로 둔 채
RGB 를 단색(`38,42,60`)으로 덮는다** — 얼굴이 조금이라도 읽히면 실루엣이 아니다.

문제는 **`faces` / `circle` / `eye` 셋이 얼굴이 프레임을 꽉 채운 크롭**이라는
것이다. 알파가 사실상 통짜 사각형이라(실측: eye 밴드의 **97.7%** 가 불투명) 그
자리에서 단색으로 칠하면 검은 원 하나 · 검은 막대 하나가 나온다 — 얼굴은
가려지지만 사람인지도 알 수 없다. 그래서 셋은 **`full` 아트에서 머리~어깨를 다시
잘라** 만든다:

| 컷 | 방식 | 창 (얼굴 높이 배수) |
|---|---|---|
| `full` · `tall` | 제자리에서 단색으로 칠하기만 | — (알파가 이미 인물 윤곽) |
| `faces` · `circle` | `full` 실루엣에서 버스트 재크롭 | 높이 3.3 / 얼굴 위 여백 0.62 |
| `eye` | 같은 재크롭 (2.4:1 밴드) | 높이 3.0 / 얼굴 위 여백 0.55 |

재크롭 쪽은 `full` 의 알파가 곧 인물 윤곽이라 **배경이 투명하게 남아** 머리
모양과 어깨선이 실루엣으로 읽힌다. 얼굴 사각형은 `make_eye_crops.py` /
`make_tall_crops.py` 와 **같은 템플릿 매칭**으로 찾으므로(실측 상관계수
0.85~0.99, 15명 전원) 세 스크립트의 인물 배율이 서로 어긋나지 않는다. 창이 아트
밖으로 나가도 안쪽으로 밀어 넣지 않고 **투명하게 채운다** — 밀어 넣으면
파일럿마다 인물이 프레임 안에서 다른 자리에 앉는다.

**`circle` 만 불투명한 원 바탕(`108,114,132`)을 구워 넣는다.** 전장 마커는 초상
뒤에 흰 원을 깔고(`BattleRenderer._draw_pilot_circle`) 교전 아레나는 아무것도 안
까는데(`EngageArena._draw_unit`), 투명한 채로 두면 같은 그림이 한쪽에선 흰 배지,
다른 쪽에선 배경이 비치는 구멍이 된다.

**되살리지 말 것 — 밝기만 누르던 첫 두 판.** (1) "투명 픽셀 비율이 10% 이상이면
단색"이라는 자동 규칙은 `circle` 이 마스크 모서리 때문에 20.8% 가 투명이라 그냥
검은 원 하나를 만들었다. (2) 그 다음 판은 `circle`/`faces`/`eye` 의 밝기를 어두운
띠(0.10~0.46)로 눌렀는데, **색만 빠진 초상화라 이목구비가 그대로 읽혔다** — 어두운
초상화는 실루엣이 아니다. 프레임을 지키려다 실루엣을 잃은 셈이고, 지금은 반대로
프레임을 놓고 실루엣을 지킨다(모브 칸만 인물이 네임드보다 작게 잡힌다).

모브는 이름도 스탯도 그대로 쓰되 **스탯이 네임드보다 10% 낮다** — 그 하향은
런타임 계수가 아니라 `players.csv` 값 자체에 이미 반영돼 있어서, 나중에 난이도
배율을 넣을 자리가 비어 있다. 시즌 드래프트 격자에서도 빠진다
(`features/season/draft/README.md`).

`prime_into(parent)` 는 반드시 `BattleSim._ready()` 같은 진입 시점에 한 번
불러야 한다 — 안 부르면 `draw_texture_rect` 가 흰 사각형을 그린다.

### MechImages.gd
`class_name MechImages`, extends `RefCounted`. `PilotImages` 와 같은 역할의
메크(기체) 일러스트 조회. **에셋 30장이 그대로 남아 있고 `mechs.csv` 는 21행으로
줄었다** — 메크 스킬(기체마다 고유 패시브 + 고유 카드 셋)이 들어오면서 시트에 없는
9대를 지웠는데, **살아남은 id 는 건드리지 않았다**: 파일 이름이 id 에 묶여 있어
번호를 다시 매기면 그림과 스탯이 통째로 어긋난다. 그래서 지금은 id 에 구멍이 있고
(3·4·5 / 10·11 / 16·17 / 23 / 29), 그 자리의 `N_full.png` 는 아무도 안 읽는 채로
남아 있다 — 나중에 기체를 다시 늘릴 때 그 칸부터 채우면 된다. 출처와 배치 규칙은
바로 아래 절.

| 함수 | 파일 | 소비자 |
|---|---|---|
| `full_for(mech_id)` | `resources/images/mech/N_full.png` | 파일럿 상세 패널 (`ui/PilotDetailPanel.gd`) |
| `has_image(mech_id)` | 위 파일의 존재 여부 | 플레이스홀더 판정 |

- **`N` 은 `mechs.csv` 의 `id` 그대로다** — 파일럿 쪽의 +1 오프셋(40장을 1..40 으로
  받아 온 역사적 사정)은 여기서 반복하지 않는다. 파일은 파일럿과 달리 `full/`
  하위 폴더 없이 `mech/` 바로 아래에 **평평하게** 놓인다.
- **`load()` 를 그냥 부르지 않는다.** 파일이 없으면 Godot 이 에러를 뱉으며 null 을
  돌려주므로 `ResourceLoader.exists()` 로 먼저 물어보고 없으면 조용히 null 을 준다.
  지금은 쓰이는 21칸이 다 차 있어 플레이스홀더 경로가 돌지 않지만, `mechs.csv` 에
  행을 더하면 다시 살아나는 길이라 그대로 둔다.

#### 메크 전신 아트 (`resources/images/mech/N_full.png`)
출처는 **Gundam Evolution**(반다이남코, 2022–2023 서비스 종료)의 기체 렌더
24종이고, Gundam Wiki 의 해당 문서 갤러리에서 받았다. 원본이 이미 **배경 없는
투명 PNG** 라 배경 제거 작업은 없었다. 개인 프로젝트용 임시 에셋이며 배포용이
아니다(파일럿 초상화가 젠레스 존 제로 아트인 것과 같은 성격).

**규격은 파일럿 전신 아트를 따르되 정규화 기준 하나가 다르다.** 세로 1024 ·
알파 크롭 · 바닥 정렬까지는 같지만, 크기는 **바운딩 박스 높이가 아니라 불투명
픽셀 면적의 제곱근**으로 맞췄다 — 기체 렌더는 검·날개·라이플이 옆으로 뻗어
바운딩 박스 비율이 0.62~1.51 로 흩어지고, 높이로 맞추면 넓은 포즈일수록 본체가
쪼그라든다. 면적 기준은 얇은 칼끝이 크기 계산에 거의 기여하지 않아 **본체
겉보기 크기**가 고르게 맞는다. 캔버스는 **1024×1024 고정**이다(가로 중앙 · 세로
바닥 정렬). 파일럿 아트처럼 폭을 각자 다르게 두면 상세 패널이 높이로 정규화할 때
비율 1.5짜리 기체가 화면 폭의 두 배로 벌어진다. 이 규격에서 잘려 나가는 것은
Exia / Mahiroo / Marasai 세 장의 무기 끝 44~64px 뿐이다.

**id 배치는 `mechs.csv` 의 스탯 아키타입을 따른다** — 이름(`Bulwark-A1` 등)은
그대로 두었으므로 이름과 기체는 서로 무관하고, **맞춰야 할 것은 스탯이다**.

**아래 표는 30대 시절의 배치이고 지금 `mechs.csv` 가 쓰는 것은 그중 21칸이다.**
남은 id 는 역할군별로 이렇다 — 탱커 0·1·2 / 격투가 6·7·8·9 / 암살자 12·13·14·15 /
서포터 18·19·20·21·22 / 스나이퍼 24·25·26·27·28. 지워진 칸은 24종 중 **중복 배치**
였던 자리와 겹치도록 골랐으므로 실제로 화면에서 사라진 기체는 없다.

| id | 아키타입 | 기체 |
|---|---|---|
| 0–5 | 탱커 (hp 195–240 / atk 6–10) | Sazabi · DOM Trooper · Guntank · Pale Rider · Mahiroo · Zaku II [Melee] |
| 6–11 | 격투가 (hp 135–170 / atk 13–18) | RX-78-2 · Kämpfer · GM · Marasai · Barbatos · *(Kämpfer 재사용)* |
| 12–17 | 암살자 (hp 80–110 / atk 22–30) | Exia · Susanowo · Zeta · Unicorn · Asshimar · *(Exia 재사용)* |
| 18–23 | 서포터 (presence 2 / atk 8–11) | Methuss · ∀ Gundam · Hyperion · ν Gundam · *(Methuss)* · *(Hyperion)* |
| 24–29 | 스나이퍼 (presence 2 / atk 19–25) | GM Sniper II · Dynames · Heavyarms Custom EW · Zaku II [Shooting] · *(GM Sniper II)* · *(Dynames)* |

24종으로 30칸을 채우므로 **6칸이 중복**이고, 중복은 언제나 **같은 아키타입 안에서**
원본과 떨어뜨려 배치했다(밴픽 화면에 같은 그림이 나란히 서지 않게). 24종을 넘는
그림이 생기면 중복 칸부터 채우면 된다.

### ScreenMetrics.gd
`class_name ScreenMetrics`, extends `RefCounted` — **정적 함수만** 있다
(창의 루트 뷰포트를 직접 읽으므로 노드가 필요 없다).

**이 저장소의 모든 화면 좌표가 지나는 한 곳이다.** 스트레치가 `expand` 라
기기마다 뷰포트 크기가 다르고, 그 위에 OS 가 못 쓰게 막는 띠(노치 · 다이나믹
아일랜드 · 홈 인디케이터 · 제스처 바)가 얹힌다. 아래쪽 띠는 **가려지는 것이
아니라 터치를 빼앗기는** 구간이라 거기 놓인 버튼은 보이지만 눌리지 않는다.

| 함수 | 답 |
|---|---|
| `viewport_size()` / `vp_w()` / `vp_h()` | 스트레치가 먹은 뒤의 뷰포트 크기 |
| `insets()` | `(좌, 위, 우, 아래)` 인셋 — **뷰포트 단위**로 환산해서 |
| `safe_rect()` | 안전 영역 사각형 |
| `top_y()` / `bottom_y()` | 첫 · 마지막으로 쓸 수 있는 y. **터치 대상의 아래끝은 `bottom_y()` 를 넘으면 안 된다** |
| `left_x()` / `right_x()` / `center_x()` | 가로. `center_x()` 가 하드코딩된 `540` 을 대신한다 |
| `safe_h()` | 안전 영역 높이 = `indent_to_safe_top()` 한 화면의 로컬 바닥 |
| `design_offset_y/x/()` | 1080×1920 짜리 화면 한 장을 안전 영역 안에서 가운데로 놓을 때 밀 양 |
| `indent_to_safe_top(c)` | 전체 화면 Control 을 통째로 안전 영역 위끝까지 내린다(`offset_top`) |
| `extend_background(c)` | 그 자식 중 **배경판**만 도로 화면 끝까지 늘린다 |
| `backfill_top(panel, color)` | 배경이 판 자신의 StyleBox 일 때, 비워진 위쪽 띠를 같은 색으로 메운다 |
| `gesture_edge_w()` | 안드로이드 뒤로 가기 제스처가 가져가는 좌우 폭 — **인셋이 아니라 경고선** |

`DisplayServer.get_display_safe_area()` 는 **네이티브 화면 픽셀**로 답하므로
그대로 쓰면 안 된다 — 창 크기 대 뷰포트 크기의 비를 곱해 논리 좌표로 옮기는
것이 `_compute_insets` 가 하는 일이고, 결과는 창/뷰포트 크기를 키로 캐시된다.

데스크톱에서 기기 인셋을 흉내 내려면 환경 변수 `ESM_SAFE_AREA="좌,위,우,아래"`
또는 사용자 인자 `-- --safe-area=0,162,0,90`. 배치 규약 세 가지와 기기별
수치표는 **`docs/mobile_safe_area.md`**.

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

## 메크 스킬과 이 폴더의 관계
`MechData` 에 **`role` 필드가 생겼다**(GameEnums.Role, -1 = 없음). 예전 주석은
"메크는 역할이 없다 — 어느 슬롯에도 앉힐 수 있다" 였는데, 기체마다 고유 카드 셋이
붙으면서 그 카드들이 역할군을 전제하게 됐다. **배정 자체는 여전히 자유다** — 이
값은 밴픽 화면의 분류와 데이터 검증에 쓰이고 ASSIGN 을 막지 않는다.

`CardData` 에는 넷이 붙었다 — `mech_card_id` / `mech_id`(어느 기체의 몇 번 카드인가),
`trigger`(그 카드에 붙은 사건 훅), `stack_count`(손패에서 뭉친 장수). 그리고 키워드에
**`stack`** 이 더해졌고, **`cost = -1` 은 "낼 수 없는 카드"** 를 뜻한다(`is_playable()`).

`PilotData` 에는 메크가 거는 지속 상태 열두 개와 영구 스탯 보정 세 개가 붙었다 —
자세한 내용은 그 파일의 "메크가 거는 지속 상태" 절과
[`docs/mech_skills_design.md`](../docs/mech_skills_design.md).
