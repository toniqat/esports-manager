# 룰 변경 계획서 — 카드 타입 분리 · 경제 지연 · 성장/라인전 스탯 신설

> 작성일 2026-08-14 · 대상 `features/battle_sim/` + `data/csv/` + `resources/`
> 상태: **구현 완료 (2026-08-14).** §13 의 미해결 항목은 사용자 확답을 받아
> 정리했고, 계획과 달라진 부분은 맨 아래 **§14 구현 기록**에 모아 두었다.
> 정식 문서는 `CLAUDE.md` / 각 폴더 `README.md` 이며 이 파일은 이력 기록이다.

---

## 0. 확정된 결정 사항 (질의응답 결과)

| 항목 | 결정 |
|---|---|
| 서포터 파일럿 카드 3장 | **라인전 1 + 드로우 2** |
| "라인전 스탯" / "성장" | **둘 다 신설.** 라인전 스탯 = `atk` / `hit` / `evasion`, 성장 = 인게임 누적 성장 |
| 성장 시스템 형태 | **매 턴 비율 누적** — `atk` · `max_hp` 가 턴당 +1% |
| 정글 파밍 · 전투 준비 · 정밀 이동 | **파일럿(정글러) 카드** (이동 카드지만 메크가 아님) |
| 4턴 규칙 범위 | 개시 손패(5장) · 블루 선점(1점) 은 **그대로 0턴**, 점수 회복 / 자동 드로우만 4턴부터 |
| 계획 중시의 "보존" | **상한 초과 자동 버리기(`_trim_hand_overflow`)로부터 보호** |
| 인내 카드 | **제거** (잘못 적은 항목 — CSV 에 추가하지 않음) |
| 구현 범위 | 신규 효과 핸들러 **전부** + 계획 살인 스텁 해제까지 |

### 이미 처리되어 있는 것 (작업 불필요)
- **교전 (id 4) 제거** — 커밋 `2eaa1a7` 에서 이미 `cards.csv` 에서 빠졌다. `exclude_lane` 플래그 파싱은 살아 있다.
- **덱 30장** — `CARDS_PER_PILOT = 6` × 5명 = 30. 장수는 이미 맞고 **구성만** 바뀐다.

---

## 1. game_config.csv — 노브 변경/신설

| key | 현재 | 변경 후 | 근거 |
|---|---|---|---|
| `BATTLE_PILOT_DMG_MULT` | 0.5 | **0.35** | 전장 푸시 교전 피해 30% 감소 (0.5 × 0.7) |
| `TURRET_HP` | 150 | **300** | 타워 체력 2배 |
| `ECONOMY_START_TURN` | — | **4** (신설) | 전략 점수 회복 / 자동 드로우가 시작되는 턴 |
| `GROWTH_PER_TURN` | — | **0.01** (신설) | 턴당 누적 성장률 (+1%) |

> `BATTLE_PILOT_DMG_MULT` 는 **전장 교전이 파일럿에게 넣는 피해 전용**이다.
> 파일럿→포탑 / 파일럿→HQ, 공격 카드, 교전 무대는 이 배율을 쓰지 않으므로
> 30% 감소는 의도대로 "서로 푸시하면서 오고 가는 대미지"에만 걸린다.

### 밸런스 파급 (구현 후 재측정 필요)
피해 -30% + 포탑 HP ×2 는 경기 길이를 크게 늘린다. 포탑 하나를 무방비로
갈아 내는 데 필요한 턴이 `TURRET_HP / atk` 이므로 **정확히 2배**가 되고,
파일럿 킬은 그보다 더 느려진다. `HQ_MAX_HP`(1000) · `RESPAWN_TURNS`(5) ·
`RESPAWN_TURN_SCALE_DIV` 는 이번 변경에서 건드리지 않되, 첫 실측 후
재조정 대상으로 남긴다.

---

## 2. 4턴 경제 게이트

### 규칙
- 0~3턴: 전략 점수 회복 **없음**, 자동 드로우 **없음**.
- 4턴부터: 기존 규칙대로 `COST_RECOVERY_INTERVAL` / `CARD_DRAW_INTERVAL` 이 돈다.
- **개시 손패 5장(`_deal_initial_hands`)과 블루 선점 1점(`seed_side_costs`)은 그대로 0턴에 들어간다.**

### 변경 지점
`features/battle_sim/card_phase/CardPhaseManager.gd` · `do_battle_turn()`

```
_bs.sim_core.simulate_turn()
if _bs.game_over: return
if _bs.turn_count >= _bs.ECONOMY_START_TURN:      # ← 신규 게이트
    ... cost_counter / draw_counter 블록 전체 ...
var turn_side := _next_turn_side()
```

> **구현 시 확인**: `turn_count` 가 `simulate_turn()` 안에서 증가하는지, 그
> 앞뒤 중 어디에서 증가하는지에 따라 `>=` 경계가 한 턴 어긋난다. "4턴째부터
> 회복이 들어간다"는 것이 기준이므로 실측(로그)으로 첫 회복 턴을 확인한다.

### 파급
첫 작전 단계 도달 시점이 뒤로 밀린다.
- 현재: 블루 선점 1 + `PHASE_THRESHOLD` 8 → 2턴에 1점씩 → **약 13틱**
- 변경 후: 4턴 대기 + 7점 × 2턴 → **약 18틱**

손패는 개시 5장에서 4턴 동안 그대로 멈춰 있다가 5턴째부터 늘기 시작한다.
첫 작전 단계 손패는 5 + (18−4)/2 ≈ **12장** 으로 여전히 상한 근처다.
`MAX_HAND_SIZE` 는 그대로 12로 둔다.

---

## 3. 카드 타입 분리 — cards.csv 신규 컬럼 2개

| 컬럼 | 값 | 의미 |
|---|---|---|
| `card_type` | `mech` / `pilot` | 카드가 메크에 붙는가, 파일럿에 붙는가 |
| `card_cat` | `-` / `lane` / `draw` / `jungle` | 파일럿 카드의 하위 분류. 메크 카드는 `-` |

`scope`(`any`/`lane`/`jungle`) 는 **그대로 유지**한다. 두 컬럼의 역할이 다르다:
- `card_cat` = **덱 구성 슬롯**을 정한다 (라인전 2장 / 드로우 1장 …)
- `scope` = **시전자 제약**을 정한다 (레인 파일럿만 / 정글러만)

메크 카드는 `card_cat = -` 이므로 `scope` 만으로 제약이 걸리고(전진=lane,
약탈=jungle), 파일럿 카드는 둘이 대체로 일치한다(`card_cat=lane` →
`scope=lane`, `card_cat=jungle` → `scope=jungle`, `card_cat=draw` → `scope=any`).

### 반영해야 할 곳
1. `data/csv/cards.csv` — 헤더 + 전 행에 두 컬럼 추가
2. `addons/csv_to_db/csv_to_db.gd` — `SCHEMAS["cards"].req` 에 `card_type`,`card_cat` 추가 / `TABLE_DEFS["cards"]` 에 두 `text` 컬럼 추가
3. `autoloads/GameManager.gd` · `_load_card_pool_bs()` — `row.get("card_type","mech")` / `row.get("card_cat","-")` 로 **기본값과 함께** 읽어 옛 game.db 도 로드되게 유지 (기존 `scope`/`pool` 과 같은 패턴)
4. `resources/CardData.gd` — `@export var card_type` / `card_cat` + 상수 정의
5. `CardPhaseManager._make_card_from_def()` / `make_card_copy()` — 두 필드 복사
6. **Project → Tools → Rebuild game.db** 실행

---

## 4. cards.csv 최종 카드 목록 (28행)

### 4-1. 메크 카드 — `card_type = mech`, `card_cat = -` (9행, pool 대상 8종)

| id | 이름 | cost | scope | effect | 비고 |
|---|---|---|---|---|---|
| 1 | 전투 개시 | 6 | any | `engage:3` | 기존 |
| 2 | 완벽한 기회 | 8 | any | `engage:4` | 기존 |
| 3 | 결투 | 6 | any | `duel` | 기존, **`pool = 0` 유지** |
| 7 | 공격 | 1 | any | `attack:1` | 기존 |
| 8 | 필중 | 2 | any | `attack:1\|pierce` | 기존 |
| 9 | 연속 공격 | 3 | any | `attack:1\|repeat` | 기존 |
| 11 | 전진 | 1 | lane | `advance:1` | 기존 |
| 22 | 보호 | 2 | any | `shield_pct:20` | 기존 |
| 23 | 약탈 | 1 | jungle | `capture_jungle:10` | 기존 |

메크 풀 실효 크기: 레인 파일럿 7종 / 정글러 7종. 3장 뽑기에 충분.

### 4-2. 파일럿 · 라인전 — `card_type = pilot`, `card_cat = lane`, `scope = lane` (3행)

| id | 이름 | cost | effect | 설명 |
|---|---|---|---|---|
| 24 | 안전한 파밍 | 3 | `lane_stat:-10\|turns:10;growth:10\|turns:10` | 10턴 동안 라인전 스탯 -10%, 성장 +10% |
| 25 | 공격적인 라인전 | 3 | `lane_stat:10\|turns:10` | 10턴 동안 라인전 스탯 +10% |
| 21 | 복귀 | 0 | `recall_ally` | **기존 카드. `scope` 를 `any` → `lane` 로 변경** |

> **인내는 만들지 않는다.**
> **파급**: 복귀가 라인전 카드가 되면서 **정글러는 복귀 카드를 받지 못한다.**
> 정글러의 HP 복구 수단은 `RECALL_HP_THRESHOLD`(20%) 자동 복귀뿐이다.

### 4-3. 파일럿 · 드로우 — `card_type = pilot`, `card_cat = draw`, `scope = any` (13행)

| id | 이름 | cost | effect | 상태 |
|---|---|---|---|---|
| 26 | 재고 | 0 | `discard_hand_draw` | **신규** — 손패 전부 버리고, 버린 수만큼 드로우 |
| 27 | 완벽한 마무리 | 0 | `discard_hand;growth_until_phase:25;end_phase` | **신규** — 손패 전부 버리기, 다음 작전 단계까지 성장 +25%, 강제 종료 |
| 28 | 계획 중시 | 1 | `preserve:2` | **신규** — 손패 2장을 다음 작전 단계까지 보존 |
| 29 | 재빠른 생각 | 2 | `discard_right:3;draw:5` | **신규** — 손패 오른쪽 3장 버리고 5장 드로우 |
| 30 | 솔로 퍼포먼스 | 4 | `discard_other_pilots\|strategy_each:1;draw:4` | **신규** — 다른 파일럿 카드 전부 버리기, 장당 전략 점수 +1, 4장 드로우 |
| 18 | 아드레날린 | **0 → 2** | **`strategy:6;strategy_next_phase:-2`** | **변경** — 드로우 제거, 점수 6 획득, 다음 단계 시작 시 -2. `keyword = exhaust` 유지 |
| 12 | 교환 | 0 | `draw:2;discard:2` | 기존 |
| 13 | 조정 | 0 | `draw:1;strategy:1` | 기존 |
| 14 | 임기응변 | 0 | `search:1` | 기존 |
| 15 | 재빠른 사고 | 0 | `draw:2` | 기존 |
| 16 | 집중 | 0 | `cost_reduce_draw_phase:1` | 기존 |
| 17 | 사전 준비 | 2 | `cost_reduce_hand:1` | 기존 |
| 19 | 계획 살인 | 2 | `strategy_on_kill:4` | 기존 — **스텁 해제, 실제 구현** |

> **이름 충돌 주의**: 기존 **재빠른 사고**(id 15) 와 신규 **재빠른 생각**(id 29) 은
> 다른 카드다. 로그·설명에서 헷갈리지 않도록 둘 다 유지하되 문서에 명시한다.

### 4-4. 파일럿 · 정글러 — `card_type = pilot`, `card_cat = jungle`, `scope = jungle` (3행)

| id | 이름 | cost | effect | 상태 |
|---|---|---|---|---|
| 31 | 정글 파밍 | 1 | `move\|own_jungle` | **신규** — 아군 정글 타일 선택 후 이동 |
| 5 | 전투 준비 | 2 | `move;cost_reduce_engage:1` | 기존 — **`scope` `any` → `jungle`** |
| 6 | 정밀 이동 | 0 | `move;return_left:1` | 기존 — **`scope` `any` → `jungle`** |

> **파급**: 전투 준비 / 정밀 이동이 정글러 전용이 되면서 **레인 파일럿은 이동
> 카드를 전혀 갖지 못한다.** 레인 파일럿의 위치 조작 수단은 전진(advance)뿐이다.
> `RecallSystem._is_out_of_position`(이동 카드가 레인 파일럿을 남의 레인에
> 떨어뜨렸을 때의 강제 복귀)은 **이제 발동할 수 없는 경로**가 되지만, 코드는
> 남겨 둔다 — 향후 레인 이동 카드가 생길 자리다.

### 신규 id 배정 원칙
삭제된 id(4 = 교전)와 미사용 id(10, 20)는 재사용하지 않는다. 신규는 24~31.

---

## 5. 덱 구성 규칙 변경

### 현재
`_deal_team_deck()` — 파일럿마다 `scope` 필터를 통과한 풀에서 **중복 허용 랜덤 6장**.

### 변경 후
파일럿마다 **메크 3장 + 파일럿 3장**, 역할에 따라 파일럿 3장의 내역이 갈린다.

| 역할 | 메크 | 파일럿 카드 3장 |
|---|---|---|
| 탱커 / 격투가 / 스나이퍼 | mech 풀에서 3 | `lane` 2 + `draw` 1 |
| 암살자(정글러) | mech 풀에서 3 | `jungle` 2 + `draw` 1 |
| 서포터 | mech 풀에서 3 | `lane` 1 + `draw` 2 |

**역할 판정**
- 정글러: `PilotData.is_guerrilla`
- 서포터: `PilotData.role == GameEnums.Role.SUPPORT`
- 그 외: 나머지 전부

**중복 규칙 변경**: 각 카테고리에서 **중복 없이(without replacement)** 뽑는다.
라인전 풀이 3종인데 2장을 뽑으므로, 기존의 중복 허용 랜덤이면 같은 카드
두 장이 흔하게 나온다. 풀 크기가 요구 장수보다 작으면 중복 허용으로 폴백해
덱이 비는 일은 없게 한다.

### 변경 지점
`CardPhaseManager.gd`
- `CARDS_PER_PILOT = 6` → 의미가 바뀌므로 `MECH_CARDS_PER_PILOT = 3` /
  `PILOT_CARDS_PER_PILOT = 3` 으로 쪼갠다 (합은 그대로 6).
- `_deal_team_deck(pool, pilots, out_deck)` — 풀을 카테고리별로 미리 갈라
  (`_split_pool_by_cat(pool)`) 파일럿마다 슬롯 규칙대로 뽑도록 재작성.
- `_pool_for_pilot()` 의 `scope` 필터는 그대로 각 카테고리 뽑기 앞에 건다.
- 신규 `_sample_without_replacement(arr, n) -> Array` 헬퍼.

**덱 크기 검증**: 5명 × 6장 = 30장 (양 팀 동일). 기존과 같다.

---

## 6. 신규 시스템 A — 인게임 누적 성장

### 데이터 (`resources/PilotData.gd`)
```gdscript
var base_atk: int      = 0     # 성장 적용 전 원본 (init 에서 atk 로 초기화)
var base_max_hp: int   = 0     # 성장 적용 전 원본
var growth: float      = 0.0   # 누적 성장 배율 (0.10 = +10%)
var growth_rate_mult: float = 1.0        # 성장 획득 배율 (안전한 파밍 +10% → 1.10)
var growth_rate_expire_turn: int = -1    # 턴 만료형 (안전한 파밍). -1 = 없음
var growth_until_phase: bool = false     # 작전 단계 만료형 (완벽한 마무리)
```

### 매 턴 처리 (`SimulationCore.simulate_turn()` 초입, 또는 신설 `_tick_growth()`)
```
for p in 생존 파일럿:
    p.growth += GROWTH_PER_TURN * p.growth_rate_mult
    p.atk = maxi(1, roundi(p.base_atk * (1.0 + p.growth)))
    var new_max := maxi(1, roundi(p.base_max_hp * (1.0 + p.growth)))
    p.hp += (new_max - p.max_hp)          # 최대치 증가분만큼 현재 HP 도 함께
    p.max_hp = new_max
```

### 만료 처리
- `growth_rate_expire_turn >= 0 and turn_count >= growth_rate_expire_turn`
  → `growth_rate_mult = 1.0`, `expire_turn = -1`
- `growth_until_phase` → `start_card_phase()` / `_run_ai_turn()` 진입 시 해제

### 시작 시점
성장은 **1턴부터** 돈다. 4턴 게이트는 "전략 포인트 및 카드 드로우"에만 걸리는
경제 규칙이므로 성장에는 적용하지 않는다.

### 파급
- 사망 후 리스폰은 `growth` 를 유지한다 (누적치는 파일럿에 붙어 있음).
- `RecallSystem.return_to_hq` 의 만피 복구는 `max_hp` 기준이라 자동으로 정합.
- 교전 무대(`RealtimeEngageSim`)는 `PilotData.atk` / `max_hp` 를 읽으므로 자동 반영.
- 스폰 시 `base_atk` / `base_max_hp` 를 반드시 채워야 한다 —
  `BattleSim.spawn_pilots_with_lanes()` 가 `match_ctx` 메크 스탯을 주입하는
  지점 **뒤**에서 초기화한다.

---

## 7. 신규 시스템 B — 라인전 스탯 배율

### 데이터 (`resources/PilotData.gd`)
```gdscript
var lane_stat_mod: float = 0.0        # +0.10 / -0.10
var lane_stat_expire_turn: int = -1   # -1 = 없음
```

### 적용 범위 — **전장 교전 전용**
| 계산 지점 | 적용 |
|---|---|
| `SimulationCore._pilot_hit_damage()` — 파일럿→파일럿 전장 피해 | ✅ `atk × (1 + lane_stat_mod)` |
| `SimulationCore.roll_hit()` — 전장 명중 판정 | ✅ `hit`, `evasion` 양쪽에 `× (1 + lane_stat_mod)` |
| 파일럿 → 포탑 / HQ 피해 | ❌ |
| 공격 카드 (`attack:N`) | ❌ |
| 교전 무대 (`RealtimeEngageSim`) | ❌ |

> **확인 요청**: "라인전 스탯"이라는 이름과 "라인전에서 오고 가는 대미지" 맥락상
> 전장 교전 한정이 자연스럽다고 판단했다. 공격 카드 / 교전 무대에도 걸어야
> 한다면 적용 지점을 넓히면 된다.

### 중복 시전 규칙
같은 파일럿에게 라인전 카드를 두 번 걸면 **덮어쓴다** (합산 아님).
`lane_stat_mod` 와 `lane_stat_expire_turn` 을 최신 값으로 교체.
합산을 허용하면 공격적인 라인전 3장으로 +30% 가 나오는데, 3종 풀에서 2장을
뽑는 구조상 같은 카드가 겹치기 쉬워 의도치 않은 스노볼이 된다.

### 만료
매 턴 `turn_count >= lane_stat_expire_turn` 이면 `lane_stat_mod = 0.0`.
성장 만료와 같은 훅에서 함께 처리.

---

## 8. 신규 효과 핸들러

`CardPhaseManager._apply_single_effect()` 의 `match` 에 추가할 clause 목록.

| clause | 사용 카드 | 동작 | 비고 |
|---|---|---|---|
| `lane_stat:N\|turns:T` | 안전한 파밍 / 공격적인 라인전 | 시전자 `lane_stat_mod = N/100`, `expire = turn_count + T` | 동기 |
| `growth:N\|turns:T` | 안전한 파밍 | 시전자 `growth_rate_mult = 1 + N/100`, `expire = turn_count + T` | 동기 |
| `growth_until_phase:N` | 완벽한 마무리 | **시전자 팀 전원** `growth_rate_mult = 1 + N/100`, `growth_until_phase = true` | 동기 |
| `discard_hand_draw` | 재고 | 손패 전부 → discard, 버린 장수 K 만큼 `draw_card` K회 | 동기 |
| `discard_hand` | 완벽한 마무리 | 손패 전부 → discard | 동기 |
| `end_phase` | 완벽한 마무리 | 플레이어: `end_card_phase()` / AI: `AiCardPlayer` 루프 중단 | **체인 마지막이어야 함** |
| `preserve:N` | 계획 중시 | `CardSelectOverlay` 로 N장 픽 → 보존 목록 등록 | **비동기 (UI)** |
| `discard_right:N` | 재빠른 생각 | `player_hand` 배열 **뒤에서** N장 → discard | 동기 |
| `strategy_next_phase:N` | 아드레날린 | 다음 작전 단계 시작 시 `player_cost += N` (음수 가능) | 동기 등록 |
| `discard_other_pilots\|strategy_each:M` | 솔로 퍼포먼스 | `owner_pilot != caster` 인 손패 카드 전부 → discard, 장당 `strategy += M` | 동기 |
| `move\|own_jungle` | 정글 파밍 | LOCATION 타겟을 **자기 팀 소유 정글 셀**로 제한 | 타겟팅 필터 |
| `strategy_on_kill:N` | 계획 살인 | **스텁 해제** — 아래 8-1 참조 | 지연 지급 |

### 8-1. 계획 살인 (`strategy_on_kill:N`) 구현
설명이 "**사용 후**, 이번 작전 단계에서 적을 처치했다면"이므로 **선불 예약형**이다.
1. 카드 사용 시 `_bs.kill_bounty_p / kill_bounty_ai = N` 설정
2. `BattleSim.mark_pilot_dead(p)` — 전장 교전 / 전진 / 공격 카드 / 교전 무대의
   **유일한 사망 경로** — 에서 처치자 측의 bounty 가 0 이 아니면 지급 후 0으로 소모
3. 작전 단계 종료 시(`end_card_phase` / AI 턴 종료) bounty 리셋

> `mark_pilot_dead` 에는 "누가 죽였는가"가 넘어오지 않을 수 있다. 인자로
> 처치자 팀을 추가하거나, 죽은 파일럿의 반대 팀에 지급하는 단순 규칙 중
> 하나를 고른다 (전장에는 제3세력이 없으므로 후자로 충분).

### 8-2. 보존 목록 (`preserve:N`)
```gdscript
# BattleSim.gd
var preserved_cards_p:  Array = []   # Array[CardData]
var preserved_cards_ai: Array = []
```
- `_trim_hand_overflow(is_player)` 가 앞에서부터 버릴 때 **보존 목록에 있는
  카드는 건너뛴다.**
- 보존은 **다음 작전 단계 시작 시 해제** (`start_card_phase` / `_run_ai_turn`).
- 카드 효과에 의한 강제 버리기(재고 / 완벽한 마무리 / 재빠른 생각 /
  솔로 퍼포먼스)는 **보존을 무시한다** — 사용자 결정("상한 초과 자동
  버리기로부터 보호")에 따른 범위 한정.
- 보존 카드가 손패를 떠나면(사용/버리기) 목록에서도 제거해 유령 참조를 막는다.
- **시각 표시**: `Card` 에 보존 마크(테두리 색 또는 작은 자물쇠 아이콘) 1개 추가.

### 8-3. 다음 단계 전략 점수 (`strategy_next_phase:N`)
```gdscript
# BattleSim.gd
var next_phase_strategy_p:  int = 0
var next_phase_strategy_ai: int = 0
```
`start_card_phase()` 진입 시 `player_cost += next_phase_strategy_p` 후 0으로 리셋
(AI 는 `_run_ai_turn` 진입 시). 점수는 0 미만으로 내려가지 않게 `maxi(0, ...)`.

> **주의**: 아드레날린은 `cost 2` 로 내고 `+6` 을 받아 순이득 +4, 다음 단계에
> -2 → 실질 +2. `keyword = exhaust` 이므로 한 판에 한 번만 쓴다.

---

## 9. 타겟팅 / UI 변경

### 9-1. 정글 파밍 — `move|own_jungle`
`CardPhaseManager.compute_valid_location_targets(cd, caster)` 에 분기 추가:
`own_jungle` 플래그가 있으면 유효 셀을 **시전자 팀이 소유한 정글 셀**로 좁힌다
(`_bs` 의 정글 소유 맵 + `temp_zone_overrides` 반영). `cast_range` 는 무시
(`cast_range = 99`).

AI 경로(`_ai_pick_target`)는 같은 함수를 쓰므로 자동으로 따라간다.

### 9-2. 계획 중시 — CardSelectOverlay 신규 모드
`CardSelectOverlay` 에 `start_preserve(n, on_complete, on_cancel)` 추가.
버리기 모드와 같은 손패 픽 UI 를 재사용하되 **카드를 손패에서 빼지 않는다**
(표시만 하고 확인 시 보존 목록에 등록).

`_process_pending_chain()` 에 `preserve` 를 `discard` / `search` 와 같은
**비동기 clause** 로 등록하고, 취소 시 기존 스냅샷 복원 경로를 그대로 탄다.

### 9-3. 완벽한 마무리 — `end_phase`
체인이 다 돈 뒤 `_finalize_pending_play()` 가 끝나고 나서 `end_card_phase()` 를
불러야 한다. 체인 도중에 부르면 카드 소멸 라우팅 전에 단계가 닫힌다.
→ `_pending_play["end_phase_after"] = true` 플래그를 두고 finalize 말미에 처리.

AI 측은 `AiCardPlayer.run_ai_plays()` 루프에 "이 카드가 `end_phase` 를 가지면
루프 종료" 를 추가한다.

---

## 10. AI 대응 (`AiCardPlayer.gd`)

| 신규 clause | AI 처리 |
|---|---|
| `preserve:N` | 랜덤 N장 표시 (UI 없이 동기) |
| `discard_hand_draw` / `discard_hand` / `discard_right:N` | 동기 처리, `update_ai_hand_visuals()` 호출 |
| `discard_other_pilots` | 동기 처리 |
| `end_phase` | 플레이 루프 즉시 종료 |
| `move\|own_jungle` | `_ai_pick_target` 이 같은 필터를 쓰므로 자동 |
| `lane_stat` / `growth` / `strategy_next_phase` | 상태 변경뿐, 별도 처리 없음 |

**무한 루프 방지 재확인**: `AiCardPlayer.run_ai_plays` 는 "낼 수 있는 카드가
있는 동안" 돈다. 신규 카드 중 `strategy:6`(아드레날린)은 점수를 늘리지만
`exhaust` 라 재사용 불가, `draw` 계열은 덱을 소모하므로 종료성은 유지된다.
단 **재고(비용 0, 손패 전부 버리고 같은 수 드로우)** 는 비용을 쓰지 않고
손패를 회전시키므로, 덱+discard 가 마르기 전까지 AI 가 재고를 반복해서
뽑아 낼 여지가 있다. → `run_ai_plays` 에 **한 턴 최대 플레이 수 상한**
(`MAX_AI_PLAYS_PER_TURN`, 예: 12) 을 추가한다.

---

## 11. 변경 파일 요약

| 파일 | 변경 내용 |
|---|---|
| `data/csv/cards.csv` | 컬럼 2개 추가, 신규 8행, 기존 4행 수정(18/21/5/6) |
| `data/csv/game_config.csv` | 2개 값 변경, 2개 키 신설 |
| `addons/csv_to_db/csv_to_db.gd` | `SCHEMAS`/`TABLE_DEFS` 의 cards 항목 |
| `autoloads/GameManager.gd` | `_load_card_pool_bs` 에 두 컬럼 |
| `resources/CardData.gd` | `card_type` / `card_cat` 필드 + 상수 |
| `resources/PilotData.gd` | 성장 6필드 + 라인전 스탯 2필드 |
| `features/battle_sim/BattleSim.gd` | 신규 config 2개, 보존/다음단계점수/killbounty 상태, `mark_pilot_dead` 훅, `spawn_pilots_with_lanes` 의 base 스탯 초기화 |
| `features/battle_sim/combat/SimulationCore.gd` | 성장/만료 틱, `_pilot_hit_damage` / `roll_hit` 에 라인전 스탯 |
| `features/battle_sim/card_phase/CardPhaseManager.gd` | 4턴 게이트, 덱 구성 재작성, 신규 효과 핸들러 12종, 보존/타겟팅 필터, 계획 살인 |
| `features/battle_sim/card_phase/CardSelectOverlay.gd` | `start_preserve` 모드 |
| `features/battle_sim/card_phase/AiCardPlayer.gd` | 신규 카드 대응 + 플레이 수 상한 |
| `features/battle_sim/card_phase/Card.gd` | 보존 마크 표시 |
| `features/battle_sim/rendering/BattleRenderer.gd` | 정글 파밍용 유효 셀 하이라이트(기존 경로 재사용 가능성 높음) |

### 문서 갱신 (CLAUDE.md 규칙)
- `CLAUDE.md` — Active Systems 표에 카드 타입 / 덱 구성 / 4턴 경제 / 성장 / 라인전 스탯 항목 추가, `game_config` · `cards` 테이블 설명 갱신
- `features/battle_sim/card_phase/README.md` — 덱 구성 절 전면 개정, 효과 핸들러 표에 12종 추가, cards.csv 컬럼 절
- `features/battle_sim/combat/README.md` — 피해 배율 / 포탑 HP / 성장 · 라인전 스탯 적용 지점
- `resources/README.md` — `PilotData` 신규 필드, `CardData` 신규 컬럼

---

## 12. 작업 순서 (제안)

1. **데이터 층** — cards.csv 컬럼/행, game_config, csv_to_db, GameManager, CardData → Rebuild game.db → 로드 확인
2. **밸런스 노브** — 피해 배율 / 포탑 HP (코드 변경 없음, 값만)
3. **4턴 게이트** — `do_battle_turn` 한 곳. 로그로 첫 회복 턴 실측
4. **덱 구성** — `_deal_team_deck` 재작성 + 30장 / 카테고리 내역 로그 검증
5. **성장 시스템** — PilotData 필드 + 틱 + spawn 초기화. 성장 없는 상태에서 회귀 확인 후 켜기
6. **라인전 스탯** — 필드 + 두 계산 지점
7. **동기 효과 핸들러** — `lane_stat` / `growth` / `growth_until_phase` / `discard_hand*` / `discard_right` / `strategy_next_phase` / `discard_other_pilots` / `end_phase`
8. **비동기·타겟팅** — `preserve:N` (오버레이 신규 모드), `move|own_jungle`
9. **계획 살인** — `mark_pilot_dead` 훅
10. **AI 대응** + 플레이 수 상한
11. **문서 갱신** + 헤드리스 파스 체크 / 실전 1경기 로그 검증

---

## 13. 미해결 / 확인 필요

1. **라인전 스탯의 적용 범위** — 전장 교전 한정으로 계획했다 (§7). 공격 카드와
   교전 무대에도 걸어야 하는가?
2. **성장의 시작 턴** — 1턴부터로 계획했다. 4턴 경제 게이트와 맞춰야 하는가?
3. **밸런스 재조정** — 피해 -30% + 포탑 HP ×2 로 경기가 길어진다. 첫 실측 후
   `HQ_MAX_HP` / `RESPAWN_TURNS` / `PHASE_THRESHOLD` 를 다시 볼 필요가 있다.
4. **정글러의 복귀 수단 상실** — 복귀 카드가 라인전 전용이 되면서 정글러는
   자동 복귀(HP 20%)만 남는다. 의도한 것인가?
5. **레인 파일럿의 이동 수단 상실** — 전투 준비 / 정밀 이동이 정글러 전용이
   되면서 레인 파일럿은 전진 외 위치 조작이 없다. 의도한 것인가?
6. **`재빠른 사고`(기존) vs `재빠른 생각`(신규)** — 이름이 거의 같다. 둘 다
   유지하는 것이 맞는가?

---

## 14. 구현 기록 (2026-08-14) — 계획과 달라진 점

§13 의 확답과, 구현하면서 계획을 고친 자리들.

### 14-1. 확정된 답 (§13)

| # | 질문 | 답 |
|---|---|---|
| 1 | 라인전 스탯의 적용 범위 | **`hit` / `evasion` 에만** 걸린다. `atk` / `max_hp` 는 기본 메크 스탯 + 성장 담당. 적용 지점은 `SimulationCore.roll_hit` 한 곳(전장 전용) — 교전 무대의 명중률은 별개 구간이라 건드리지 않는다. **§7 의 `_pilot_hit_damage` 적용은 취소.** |
| 2 | 성장의 시작 턴 | **1턴부터** (계획 §6 그대로). 4턴 게이트는 카드 경제 전용. |
| 4 | 정글러의 복귀 수단 상실 | **수용하지 않는다.** 복귀는 `scope = any` 를 유지하고 `card_cat = common` 으로 라인전 슬롯과 정글 슬롯 양쪽에 걸친다. |
| 5 | 레인 파일럿의 이동 수단 상실 | **수용한다.** 전투 준비 / 정밀 이동은 `scope = jungle`. |
| 6 | 이름 충돌 | 신규 id 29 를 **`과감한 정리`** 로 개명 (계획의 "재빠른 생각" 폐기). |

### 14-2. 계획을 고친 자리

- **`card_cat` 에 `common` 값 추가.** 계획은 `-` / `lane` / `draw` / `jungle` 4값
  이었으나, "복귀는 라인전 카드인데 정글러도 뽑을 수 있어야 한다"는 §13-4 의
  답을 담을 자리가 없었다. `CardData.fits_category(cat)` 가 `common` 을 라인전과
  정글 양쪽에 매칭시킨다. 이 값이 없으면 (a) 복귀를 `draw` 로 옮겨 라인전 풀이
  2종만 남아 "2장 중복 없이"가 결정론이 되거나, (b) 정글러가 복귀를 못 받는다.
- **라인전 스탯을 `roll_hit` 안에 넣었다** (`lane_adjusted` 헬퍼). 계획은
  `_pilot_hit_damage` 와 `roll_hit` 두 곳이었는데 §13-1 답에 따라 후자만 남았다.
  `roll_hit` 은 전장 자동 교전과 공격 카드가 **공유하는 단일 함수**라, 한 곳을
  고치면 둘 다 일관되게 따라간다.
- **`end_phase` 를 `_pending_play["end_phase_after"]` 대신 매니저 플래그로.**
  계획 §9-3 은 `_pending_play` 에 실으려 했으나, AI 경로(`apply_card_effect`)는
  `_pending_play` 를 쓰지 않는다. `CardPhaseManager._end_phase_requested` +
  `consume_end_phase_request()` 로 양 경로가 같은 플래그를 공유한다. 한 번에 한
  쪽만 자기 작전 단계를 갖고 있으므로 팀별로 나눌 필요가 없다.
- **`preserve` 오버레이는 찾기 그리드를 그대로 재사용.** 계획 §9-2 는 "버리기
  모드와 같은 손패 픽 UI"를 말했지만, 버리기 모드는 고른 카드를 **손패에서
  빼내** 중앙 부채꼴로 옮긴다 — 보존에는 맞지 않는다. 찾기 모드는 더미를 건드리지
  않고 픽만 돌려주므로 그쪽이 정확한 재사용처였다. `Mode.PRESERVE` 는
  `_build_search_grid(_bs.player_hand)` 로 **손패**를 소스로 주는 것과 취소 버튼
  라벨(`보존 취소`)만 다르다.
- **`_trim_hand_overflow` 를 `pop_front` 루프에서 인덱스 스캔으로.** 보존 카드가
  손패 앞쪽에 있으면 `pop_front` 는 그 자리에서 막힌다. 인덱스 스캔이면 보존
  카드를 건너뛰고 계속 돌 수 있고, 손패가 통째로 보존된 극단에서도 루프가 끝난다.
- **`_award_kill_bounty` 는 처치자 인자를 받지 않는다** (계획 §8-1 의 두 선택지 중
  후자). 쓰러진 파일럿의 반대 팀이 처치자다 — 전장에 제3세력이 없다.
- **`base_atk` / `base_max_hp` 초기화는 `spawn_pilots_with_lanes` 가 아니라
  `PilotData._init`.** 메크 스탯 주입(`_stats_for`)이 생성자를 거치므로, 어떤
  스폰 경로를 타도 원본이 비지 않는다. 계획대로 spawn 에 두면 새 스폰 경로가
  생길 때마다 잊을 자리가 하나씩 늘어난다.
- **성장 스탯은 매 턴 곱하지 않고 원본에서 다시 계산한다.** 계획 §6 의 의사코드도
  같은 취지였지만, 매 턴 반올림이 끼면 오차가 누적돼 실제 성장률이 명목보다
  낮아진다는 점을 주석에 명시해 두었다.
- **`AiCardPlayer` 의 `end_phase` 확인은 교전 아레나 await **뒤**.** 먼저 끊으면
  그 카드가 연 교전이 화면에 뜬 채로 상대 차례가 닫힌다.
- **`MAX_AI_PLAYS_PER_TURN` → `MAX_PLAYS_PER_TURN`** (AiCardPlayer 안에 있으므로
  접두사가 중복이다). 값은 계획대로 12.

### 14-3. 실측 검증

- **덱 구성** — 양 팀 30/30장. 파일럿마다 mech 3 + 파일럿 3, 서포터만 draw 2,
  정글러만 jungle 슬롯 2(`jungle` 2 또는 `jungle` 1 + `common` 1). 같은 파일럿이
  같은 카드를 두 장 가진 사례 0.
- **4턴 게이트** — 첫 작전 단계가 13턴 → **16턴**(`player 8 / ai 7`). 회복이
  4·6·8·10·12·14·16턴에 7회 들어간 결과로, 계획의 "약 18틱" 추정과 같은 자리다.
- **성장** — 탱커(base 200)의 HP 가 턴마다 200 → 202 → 204 → 206. 성장 배율 1.25
  (완벽한 마무리)에서 atk 160 → 162 / max_hp 200 → 203.
- **효과 핸들러 12종** — 전부 AI 경로로 실행 확인. 라인전 스탯 덮어쓰기
  (−10% → +10%), `roll_hit` 반영(hit 50 → 55), 과감한 정리(손패 5−3+5=7),
  솔로 퍼포먼스(다른 파일럿 카드 5장 + 전략 점수 +5), 재고(6장 버리고 6장),
  아드레날린(+6 / 다음 단계 −2), 계획 살인(사망 시 `ai_cost` 11 → 15, 현상금 소모),
  완벽한 마무리(팀 5명 배율 1.25 + 단계 종료 요청), 정글 파밍(유효 셀 6).

### 14-4. 남은 밸런스 과제 (§13-3)

피해 −30%(0.5 → 0.35) + 포탑 HP ×2(150 → 300) 로 경기가 길어진다. `HQ_MAX_HP`
(1000) · `RESPAWN_TURNS`(5) · `RESPAWN_TURN_SCALE_DIV`(10) · `PHASE_THRESHOLD`(8)
은 이번에 건드리지 않았고, 실제 매치(메크 스탯 주입 경로) 실측 후 재조정 대상이다.
헤드리스 standalone 실측은 `ROLE_STATS` 폴백(atk 160~500)을 쓰므로 밸런스 지표로
읽으면 안 된다 — 그 경로에서는 포탑이 여전히 5턴 만에 깨진다.
