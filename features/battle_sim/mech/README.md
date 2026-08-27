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
| `engage_targets_all` / `overclock_extra_attack` / `last_stand_available` | `TurnEngageSim` |
| `contempt_active` / `consume_contempt` | `TurnEngageSim._pick_target` (약자 멸시) |
| `try_stun` / `consume_stun_turn` | `TurnEngageSim` (강타 / 기절) |
| `consume_phase_boon` | `CardPhaseManager._effect_gen_card` · `_effect_phase_b` · `_phase_c_payout` |
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
| `on_engage_damage(a, t, dealt)` | `TurnEngageSim._strike_one` |
| `on_shielded_ally_damage(a, t)` | `SimulationCore._flush_guardian_rides`, `CardPhaseManager._apply_attack_damage` |
| `on_engage_end(participants)` | `EngagePhaseManager._finish_engage` |
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

## 교전 무대에서 걸리는 것들

무대 자체는 `../engage/TurnEngageSim.gd` 가 굴리고, 이 모듈은 **질의 함수만**
내보낸다. 다섯 자리다.

| 무엇 | 어디서 | 규칙 |
|---|---|---|
| 전탄 발사(I) | `_resolve_attack` | `engage_targets_all` 이 true 면 대상 집합이 **적 전원**이 된다. 대가(공격력 절반)는 `mechs.csv` 의 atk 12 에 이미 들어가 있다 |
| 오버클럭(P) | `_strike_one` | 피해 직후 `overclock_extra_attack` 을 굴려 **같은 대상에게** 한 번 더. 추가 공격은 다시 굴리지 않는다(`allow_extra = false`) — 그러면 한 차례가 확률에 따라 무한히 늘어난다 |
| 불굴(V) | `_apply_damage` | 체력이 0 이하로 떨어지는 순간 1 로 붙잡고 소모. **포탑 사격도 같은 함수를 지나므로** 파일럿 공격에만 걸면 포탑 한 방에 죽는 구멍이 남는다 |
| 약자 멸시(R) | `setup` → `_contempt_opening` | **1라운드가 돌기 전에** `take_contempt_charges` 로 손패의 [약자 멸시] 충전을 통째로 태우고, 그 수만큼 **체력이 가장 적은 적**(비율이 아니라 절대값)을 공격력 50% 로 때린다. 예전의 "스택이 남은 동안 겨눔 강제"는 교전 라운드 수에 값이 매달려 삭제됐다 |
| 강타([강타] 카드) | `_strike_one` | 때린 쪽이 장전돼 있으면 맞은 적의 다음 차례가 통째로 사라진다. `_stun_applied` 가 **같은 적 두 번**을 막고, 없으면 근접 하나가 한 적을 교전 내내 잠재운다 |

교전 한 번짜리 상태(`_stun_applied` · `_last_stand_*`)는
`on_engage_start` 가 켜고 `on_engage_end` 가 걷는다. **반응 장갑은 그 짝에
없다** — 남은 겹수가 곧 다음 교전까지 가는 값이라 교전이 아니라 전장을 떠날 때
(`clear_field_effects`) 걷힌다.

## 수호 연계(Q)의 편승 공격

"이 메크의 보호막을 두른 아군이 피해를 주면 이 메크도 그 적을 친다."
`shield_source`(아군 → 그 보호막을 건 메크)를 읽는 유일한 소비자이고, 게이트가
셋이다 — 그 아군이 **지금도** 보호막을 두르고 있을 것(다 깎이면 연계도 끝난다),
편승하는 메크가 자기 자신이 아닐 것([수호]는 시전자에게도 보호막을 건다),
그리고 `_guardian_busy` 재진입 금지(두 메크가 서로에게 보호막을 걸면 고리가
실제로 닫힌다).

**부르는 자리가 두 곳이고 타이밍이 다르다.**

- **카드 피해**(`CardPhaseManager._apply_attack_damage`) — 그 자리에서 곧장.
  카드 피해는 판정과 적용이 갈려 있지 않다.
- **전장 자동 교전** — `SimulationCore._credit_pilot_damage` 는 **적어만 두고**
  (`_guardian_rides`), 이번 턴의 피해가 전부 적용된 뒤 `_flush_guardian_rides`
  가 굴린다. 판정 단계에서 곧장 때리면 편승 한 방이 아직 적용되지 않은 피해보다
  먼저 상대를 눕혀, 같은 턴의 나머지 판정이 이미 죽은 사람을 상대로 굴러간다.

교전 무대는 부르지 않는다 — 편승할 메크가 그 무대에 없을 수 있고, 있으면 자기
차례에 이미 때린다.

## 단계 A → B → C 사슬 (암살 P)

세 장이 서로를 만들어 주며 도는 고리다.

```
[리부트] → 덱에서 [단계 A] 탐색
[단계 A] → 덱에 [단계 B] + 지정한 적에게 목표(+15%)
[단계 B] → 목표 주변에서 교전 3라운드
             ├ 적을 눕혔으면 → 덱에 [단계 C]
             └ 아니면        → 덱에 [단계 A]   (고리를 한 바퀴 더)
[단계 C] → 덱에 [단계 A] + 강화 3택
```

**`phase_b` 가 성립하려면 `engage` 절이 무대가 닫힐 때까지 기다려야 한다.**
`CardPhaseManager._effect_engage` 가 `engage_finished` 를 await 하도록 바뀐 것이
그 때문이고, 같은 변경이 [우세한 전장] 의 `gen_hand:19|per_kill` 도 함께 고친다
(둘 다 예전에는 첫 라운드가 돌기도 전에, 즉 처치 수가 언제나 0 인 시점에
정산됐다). 교전의 처치 수는 `EngagePhaseManager.last_engage_kills` 가 답한다 —
무대가 치워진 뒤라 `_sim` 이 아니라 그 사본(`_last_stats`)을 읽는다.

**강화 3택**(`BOON_DEFS`)은 다음 한 번에만 쓰이고 파일럿당 하나만 예약된다.

| 키 | 걸리는 카드 | 하는 일 | 소모하는 자리 |
|---|---|---|---|
| `alpha` | [단계 A] | [단계 B] 를 덱이 아니라 **핸드**에 | `_effect_gen_card` |
| `beta` | [단계 B] | +100 충전 | `_effect_phase_b` |
| `gamma` | [단계 C] | 성장 점수 +10% | `_phase_c_payout` |

**감마 정산은 새 강화를 고르기 전에** 한다 — 순서를 뒤집으면 방금 고른 감마가
그 자리에서 되먹힌다. 플레이어는 `CardSelectOverlay` 의 `CHOICE` 모드(찾기와
같은 그리드, **취소 없음**)로 고르고, AI 는 무작위로 고른다. 두 경로가
`CardPhaseManager.register_phase_boon` 한 함수로 모이므로 규칙이 갈라질 수 없다.

## 튜닝 상수

| 상수 | 값 | 뜻 |
|---|---|---|
| `VULNERABLE_PER_STACK` | 0.01 | 취약 1당 받는 피해 배율 |
| `REACTIVE_ARMOR_CUT` | 0.90 | 반응 장갑 한 겹이 깎는 비율 |
| `OVERCLOCK_PROC_PER_CHARGE` | 0.01 | 충전 1당 교전 추가 공격 확률 |
| `CASH_RATE` | 0.04 | [캐시] 가 카드 한 장마다 버는 자기 성장치 비율 |
| `SCORE_COST_UNIT` | 0.01 | `score_cost:N` 의 단위 — **N=100 이 1.00k** |
| `PHASE_BOON_BETA_CHARGE` | 100 | 강화 베타가 [단계 B] 에 얹는 충전 |
| `PHASE_BOON_GAMMA_RATE` | 0.10 | 강화 감마가 [단계 C] 에서 버는 자기 성장치 비율 |

배율(몇 %인가)이 CSV 가 아니라 여기 사는 이유는 파일럿 스킬과 같다: 패시브마다
의미가 다른 숫자 칸을 대여섯 개 만들지 않기 위해서다. CSV 의 `p1` / `p2` 는
패시브마다 뜻이 다른 두 숫자이고(시작 충전 · 최대 충전 · 취약 수치 · 피해 비율),
그 뜻은 `KEY_*` 상수 옆 주석에 적혀 있다.
