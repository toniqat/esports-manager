# `features/battle_sim/mech/` — 메크 스킬

배정된 **기체**에 붙는 상시 능력(패시브)과 그 기체가 덱에 들고 오는 카드들의
런타임 상태를 맡는다. 파일럿 스킬(`../skill/`)과 나란히 서는 형제 모듈이고,
같은 이유로 **스폰과 덱 배분이 모두 끝난 뒤에** 세워진다.

| 파일 | 역할 |
|---|---|
| `MechSkillSystem.gd` | `class_name MechSkillSystem` — 패시브 상태 · 충전 · 사건 훅 · 질의 함수 |

전체 설계와 21대 목록은 **[`docs/mech_skills_design.md`](../../../docs/mech_skills_design.md)**
에 있다. 이 문서는 코드를 만질 때 필요한 것만 적는다.

---

## 데이터

| 표 | 행 | 키 |
|---|---|---|
| `data/csv/mech_passives.csv` | 15 | `mech_id` → 패시브 하나 (21대 중 6대는 없음) |
| `data/csv/mech_cards.csv` | 64 | `mech_id` → 카드 배열, `id` → 카드 하나 |

`GameManager` 가 셋으로 들고 있다 — `mech_passives`(mech_id → 행),
`mech_cards`(mech_id → 배열), `mech_card_defs`(카드 id → 행). 마지막 것이 따로
있는 이유는 효과가 카드를 **지목해서** 만드는 절이 열 개가 넘어서다
(`gen_hand:13` / `gen_deck:39` / `search_card:7`) — 매번 배열을 뒤지면 같은 선형
탐색이 카드 한 장마다 다시 돈다.

## 이 모듈이 하지 않는 것

**카드 효과는 여기 없다.** 절 문법은 전부 `CardPhaseManager._apply_single_effect`
가 처리하고(문서의 4장), 이 모듈은 그 절들이 남기는 **상태**와 그 상태를 읽는
**질의 함수**만 맡는다. 경계가 흐려지면 카드 한 장을 고치려고 두 파일을 열게 된다.

**스탯을 직접 밀지 않는다.** 패시브 보정은 질의 함수로만 내보내고 계산은 원래
하던 자리가 그대로 한다:

| 질의 | 읽는 곳 |
|---|---|
| `atk_mult` / `bulk_power_atk` | `BattleSim.refresh_growth_stats` |
| `damage_taken_mult` / `consume_reactive_armor` | `SimulationCore._pilot_hit_damage`, `CardPhaseManager._apply_attack_damage` |
| `engage_targets_all` / `overclock_extra_attack` / `last_stand_available` | `TurnEngageSim` (2단계) |
| `chain_rounds` | `CardPhaseManager._effect_engage` (`charge_rounds` 플래그) |
| `score_cost_waived` | `CardPhaseManager._effect_score_cost` |

`atk` / `max_hp` 를 여기서 밀면 성장 재계산(`refresh_growth_stats`) 한 번에
지워진다. 영구 증가분은 `PilotData.bonus_atk_flat` / `bonus_atk_mult` /
`bonus_max_hp` 로 산다 — 그 셋은 재계산 식 **안에** 들어가 있다.

## 사건 훅 — 누가 언제 부르나

| 훅 | 부르는 곳 |
|---|---|
| `init_for_match()` | `BattleSim._ready` (덱 배분 뒤) |
| `on_card_played(cd, is_player)` | `CardPhaseManager._dispose_used_card` |
| `on_card_discarded(cd, is_player)` | `CardPhaseManager.send_to_discard` (지금 도는 카드는 제외 — 두 번 세지 않기 위해) |
| `on_card_attack_hit(a, t, dealt)` | `CardPhaseManager._apply_attack_damage` |
| `on_card_damage_for_revelation(t, src)` | 같은 자리 (계시) |
| `on_engage_damage(a, t, dealt)` | `TurnEngageSim` (2단계) |
| `on_kill(victim, killer)` | `BattleSim.mark_pilot_dead` |
| `on_turret_destroyed(killer, td)` | `BattleSim.score_turret_kill` |
| `on_objective_win(team)` | `ObjectiveSystem` (교전 정산 · 무혈 획득 양쪽) |
| `on_engage_start(participants)` | `EngagePhaseManager._begin` |
| `on_phase_end(is_player)` | `CardPhaseManager._notify_skill_phase_end` |
| `clear_field_effects(p)` | `RecallSystem.return_to_hq`, `on_kill` |
| `tick_expiries(turn)` | `SimulationCore.tick_growth_and_expiries` |

## 충전

`add_charge` 한 곳에서만 오르고, **상한에 닿는 순간**의 보상(`_on_charge_full`)도
그 안에서 판정한다 — 충전이 오르는 자리가 여럿이라 호출 측에 맡기면 조건 검사가
그 수만큼 복제된다. 지금 상한에 반응하는 것은 둘이다.

- **처형 준비**(H) — 핸드에 [처형] 한 장 (이미 들고 있으면 만들지 않는다)
- **무념**(T) — 충전을 전부 태워 사거리 1 내 광역 공격 (패시브가 직접 때리는 유일한 자리)

## 튜닝 상수

| 상수 | 값 | 뜻 |
|---|---|---|
| `VULNERABLE_PER_STACK` | 0.01 | 취약 1당 받는 피해 배율 |
| `REACTIVE_ARMOR_CUT` | 0.90 | 반응 장갑 한 겹이 깎는 비율 |
| `OVERCLOCK_PROC_PER_CHARGE` | 0.01 | 충전 1당 교전 추가 공격 확률 |
| `CASH_RATE` | 0.04 | [캐시] 가 카드 한 장마다 버는 자기 성장치 비율 |
| `SCORE_COST_UNIT` | 0.01 | `score_cost:N` 의 단위 — **N=100 이 1.00k** |

배율(몇 %인가)이 CSV 가 아니라 여기 사는 이유는 파일럿 스킬과 같다: 패시브마다
의미가 다른 숫자 칸을 대여섯 개 만들지 않기 위해서다. CSV 의 `p1` / `p2` 는
패시브마다 뜻이 다른 두 숫자이고(시작 충전 · 최대 충전 · 취약 수치 · 피해 비율),
그 뜻은 `KEY_*` 상수 옆 주석에 적혀 있다.
