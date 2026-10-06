# `features/battle_sim/mech/` — 메크 스킬

배정된 **기체**에 붙는 상시 능력(패시브)과 그 기체가 덱에 들고 오는 카드들의
런타임 상태를 맡는다. 파일럿 스킬(`../skill/`)과 나란히 서는 형제 모듈이고,
같은 이유로 **스폰과 덱 배분이 모두 끝난 뒤에** 세워진다.

| 파일 | 역할 |
|---|---|
| `MechSkillSystem.gd` | `class_name MechSkillSystem` — 패시브 상태 · 충전 · 사건 훅 · 질의 함수 |

**파일럿 스킬이 선수에게 붙는 한 수라면, 메크 스킬은 기체가 하는 일이다.**
밴픽에서 기체를 고르는 순간 그 파일럿의 덱 절반과 상시 능력 하나가 함께 정해진다.
21대 목록 · 키워드 · 메크 카드 전용 절 문법도 이 문서에 있다(예전
`docs/mech_skills_design.md` 를 옮겨 왔다).

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

## 메크 21대

기획 시트의 A~W 를 `mechs.csv` 의 살아남은 21행에 얹었다. **id 는 그대로 두고 9행을
지웠다** — `resources/images/mech/{id}_full.png` 가 id 에 묶여 있어서, 번호를 다시
매기면 그림과 스탯이 통째로 어긋난다. 그래서 id 에 구멍이 있다(3·4·5, 10·11,
16·17, 23, 29). 코드 주석과 README 의 "탱커 E", "암살 P" 같은 표기는 **시트 문자**다.

| 시트 | id | 이름 | 역할군 | hp | atk | 패시브 | 카드 (덱 장수) |
|---|---|---|---|---|---|---|---|
| E | 0 | Juggernaut | 탱커 | 220 | 7 | 과적재 | 몸집 불리기 1 · 추적 1 · 강습 1 (3) |
| G | 1 | Bastion | 탱커 | 200 | 8 | 반응 장갑 전개 | 최첨단 보호 1 · 초고출력 1 · 개시 1 (3) |
| N | 2 | Ironhide | 탱커 | 240 | 6 | 고통과 쾌감 | 주먹다짐 2 · 고통과 쾌감 0 · 제압 전투 1 (3) |
| D | 6 | Triumph | 전사 | 160 | 14 | 승전보 | 승전보 0 · 돌격 1 · 질주 2 (3) |
| F | 7 | Wrecker | 전사 | 145 | 16 | 철거 명령 | 철거 0 · 우세한 전장 1 · 격렬한 돌진 2 (3) |
| H | 8 | Headsman | 전사 | 170 | 13 | 처형 준비 | 처형 0 · 일격 1 · 휩쓸기 1 (2) |
| L | 9 | Reaper | 전사 | 155 | 15 | 영혼 수확 | 유령의 올가미 1 · 전쟁의 사슬 1 · 영혼 포식 1 (3) |
| P | 12 | Overdrive | 암살자 | 90 | 26 | 오버클럭 | 리부트 3 · 단계 A 1 · 단계 B 0 · 단계 C 0 (4) |
| R | 13 | Blitz | 암살자 | 85 | 28 | — | 약자 멸시 1 · 전격전 1 · 즉발 베기 1 (3) |
| T | 14 | Zephyr | 암살자 | 100 | 24 | 무념 | 명상 3 · 질풍 1 · 신속 1 (5) |
| W | 15 | Siren | 암살자 | 80 | 30 | — | 최면 1 · 매혹적인 침공 1 · 매혹 1 (3) |
| K | 18 | Marshal | 지원 | 130 | 9 | — | 공격 명령 1 · 투자 1 · 간보기 1 (3) |
| Q | 19 | Guardian | 지원 | 120 | 10 | 수호 연계 | 지원 보호 2 · 수호 1 (3) |
| S | 20 | Caprice | 지원 | 140 | 8 | — | 강타 1 · 탈진 1 · 변덕 1 (3) |
| U | 21 | Alchemist | 지원 | 115 | 11 | — | 밸런스 1 · 파란 약 1 · 붉은 가루 1 · 녹색 병 1 (4) |
| V | 22 | Verdict | 지원 | 135 | 9 | 불굴 | 죽음의 손가락 1 · 확신 1 · 사형 선고 1 (3) |
| A | 24 | Tempest | 원딜 | 75 | 24 | 취약 각인 | 천둥 폭풍 1 · 천공의 일격 1 · 꿰뚫는 번개 3 (5) |
| B | 25 | Scavenger | 원딜 | 85 | 22 | — | 캐시 1 · 스캐빈저 1 · 로켓 펀치 1 (3) |
| C | 26 | Payload | 원딜 | 90 | 21 | 미사일 적재 | 미사일 1 · 미사일 준비 1 · 정밀 폭격 1 (3) |
| I | 27 | Barrage | 원딜 | 80 | **12** | 전탄 발사 | 전장 강타 1 · 계시 1 · 결속 1 (3) |
| J | 28 | Deadeye | 원딜 | 95 | 20 | 조준 보정 | 락온 0 · 테러 1 · 파괴 1 (2) |

**Barrage(I)의 공격력만 12 다** — 시트가 "다른 sniper 메크 공격력의 절반"이라고 못
박아 둔 값이고, 그 대가가 전탄 발사(교전 공격이 적 전원 대상)다.

**덱 크기** — 메크 카드는 배정된 기체의 카드를 `count` 만큼 펼친 것(2~5장)이고
파일럿 카드는 선수당 고정 3장이다. 서로 다른 기체 다섯이면 팀 덱은
**28장**(H · J + 3장짜리 셋)에서 **36장**(A · T · P · U + 3장짜리 하나) 사이다.
장수 차이 자체가 기체 선택의 일부다.

## 메크 키워드 넷

| 키워드 | 뜻 | 메모 |
|---|---|---|
| **충전** `charge` | 핸드에 들어올 때마다 충전 +1(상한 `charge_max`), 사용 시 전부 소모하고 그만큼 세진다 | 세기가 카드 **한 장의 상태**(`CardData.charge`)라 `count = 1` 로 족하다. 오르는 자리는 `add_card_to_hand` / `draw_card` 둘(둘 다 `CardData.gain_charge()`), 태우는 자리는 `_burn_charge(cd)` 하나 — 태운 수를 `_charge_spent` 에 적는다(효과 체인이 여러 프레임에 걸쳐 돌아 그 시점의 `charge` 는 이미 0 이다). 쓰는 카드: 미사일(C, 3) · 전장 강타(I, 5 — 충전 + 1 명) · 약자 멸시(R, 3) |
| **count** | 채용 시 덱에 들어가는 장수 | `count = 0` 인 여섯 장(승전보 · 철거 · 처형 · 락온 · 고통과 쾌감 · 단계 B/C)은 다른 효과가 만들어 줄 때만 나온다. 그래도 배분 표(`BattleSim.starter_cards`)에는 적는다 — 상세 패널의 메크 탭이 기체를 반만 보여 주지 않게 |
| **코스트 -1** | 낼 수 없음 — 핸드에 있는 것만으로 효과 | 캐시(B) · 계시(I) · 약자 멸시(R) · 밸런스(U). 비용 칸에 `—`, 슬래브가 덮이고 드래그 거부, **단 버리기 픽 중에는 끌린다**. 효과는 `hand_passive:<key>` 한 줄이고 실제 동작은 `MechSkillSystem` 이 손패를 훑어 읽는다. 0 코스트(공짜로 낼 수 있음)와 다르다 |
| **휘발성** `volatile` | 안 쓰고 버려지면 버린 더미 대신 제거 | 철거(F) · 락온(J), 정밀 폭격이 만드는 임시 미사일. 소멸(쓰면 사라짐)과 함께 달면 어느 쪽으로도 덱을 불리지 않는다 |

> **충전은 예전에 `스택` 이었다** — 같은 카드가 손패에서 한 장으로 뭉치고
> `stack_count` 가 장수를 들었는데, 더미로 갈 때마다 낱장으로 다시 흩어야 했고
> 세기 상한이 곧 `count` 라 카드 한 종류가 덱을 3~5장씩 불렸다. **공격 명령(K)** 은
> 이 전환에서 충전을 버리고 `death_hand` 훅으로 갔다.

## 효과 문법 — 메크 카드 전용 절

공용 절(`draw` / `discard` / `strategy` / `attack` / `engage` / `move` / `shield_pct` …)은
`../card_phase/README.md` 의 효과 표에 있고(`around_target` · `discard_right` ·
`move|own_jungle` · `phase_b` / `phase_c` 도 거기), 아래는 메크 카드만 쓰는 것이다.
**이름을 공용 절과 겹치지 않게 지은 것은 의도된 것** — `effect` 문자열만 보고도
"기체가 주는 카드"임이 읽혀야 한다.

**체인 제어** — `on_hit`(앞선 공격 절이 한 대라도 맞았으면 이후 절 실행) /
`on_miss`(전부 빗나갔으면). 절 하나에 조건을 매다는 대신 체인을 두 토막으로
자른다 — 카드 문장이 언제나 "명중 시 A, 빗나갈 시 B" 두 갈래이고 갈래마다 절이
여럿이기 때문이다. 예: 간보기 `attack:1;on_hit;engage:3|at_target;on_miss;strategy:4`.

**공격 절 플래그** — `attack:N` 은 "적 하나를 N × ATK 로 한 번"이 기본형이고 플래그가
대상 집합을 넓힌다. 대상은 `PilotData` 이거나 `TurretData` 이며, 둘을 가르는 자리는
피해를 넣는 두 함수뿐이다(명중 판정 · 돌진 연출 · 팝업은 공유).

| 플래그 | 대상 | 쓰는 카드 |
|---|---|---|
| `all` | 전장 내 모든 적 파일럿 | 천둥 폭풍 |
| `random` | 무작위 적 (`charge` 와 함께면 **충전 수 + 1** 명) | 전장 강타 |
| `self_range:N` | 시전자 기준 N칸 내 적 + 포탑 | 테러 · 초고출력 · 영혼 포식 · 휩쓸기 · 즉발 베기 |
| `area:N` | 지정 대상 기준 N칸 내 적 + 포탑 | 정밀 폭격 · 파괴 |
| `damaged` | 이번 작전 단계에 이 메크가 때린 적 전부 | 락온 · 신속 |
| `line` | 아군 HQ ~ 지정 포탑까지의 레인 전부 | 꿰뚫는 번개 |
| `turret_only` | 지정한 적 포탑 하나 | 철거 |
| `charge` | **각 대상을** 충전 수만큼 반복 | 미사일 · 전장 강타 |
| `pierce` / `repeat` | (공용) 필중 / 명중마다 반복 | |

**파일럿→포탑 카드 피해는 고정값**(`PILOT_STRUCTURE_DMG`)이다 — `atk` 비례로 두면
성장이 공격력을 ×3 까지 미는 후반에 카드 한 장이 포탑을 통째로 지운다.

**나머지 절**

| 절 | 뜻 | 플래그 |
|---|---|---|
| `heal_pct:N` | 대상 최대 체력의 N% 회복 | `self` `per_hit` |
| `max_hp:N` | 최대 체력 **영구** +N | `self` `per_hit` |
| `atk_add:N` | 공격력 **영구** +N | `self` |
| `shield_atk:N` | **시전자 공격력의** N% 보호막 | `all_allies` |
| `reactive_armor:N` | 반응 장갑 N겹 | `self` `per_hit` |
| `charge:N` | 메크 패시브 충전 +N | `per_hit` |
| `score_cost:N` | 성장 점수 N 소모 (**N=100 이 1.00k**) | |
| `growth_eff:N` | 성장 적립 +N% (전장 이탈까지, 누적) | |
| `gen_hand:ID` / `gen_deck:ID` | 그 메크 카드를 만들어 손패 / 덱에 | `per_hit` `per_kill` `temp` |
| `search_card:ID` | 덱에서 그 카드를 찾아 손패로 | `count:N` |
| `search_discard:N` | 묘지 탐색 — 버린 더미를 **펼쳐 고른다** | |
| `draw_discard:N` | 묘지 드로우 — 위에서부터 N장 | `cost_reduce:N` |
| `push:N` | 밀기 N칸 | `bonus_clear:N` |
| `move_target:N` | **적을** N칸 민다 | |
| `move_to_target` | 시전자가 대상 칸으로 뛰어든다 | |
| `pull_to_caster` | 적을 시전자 칸으로 끌어온다 | `self_range:N` |
| `mark_target:N` | 목표 — 시전자에게 받는 피해 +N% | |
| `track:N` | 추적 N턴 | |
| `link_engage` | 결속 | |
| `stun_next` | 강타 | |
| `no_engage_phase` | 탈진 | |
| `dmg_taken:N` | 받는 피해 +N% (중첩 없음) | |
| `bounty:N` | 현상금 = 대상 성장치의 N% | |
| `attack_bounty:N` | 현상금의 N% 를 피해로 | |
| `mutual_attack:N` | 서로 N번씩 (대상 쪽은 필중) | |
| `taunt_all` | 모든 적이 시전자를 필중 공격 | |
| `execute:N` | 최대 체력 N% 이하면 처치 | `charge:N` |
| `growth_link:N` | 매혹 N턴 | |
| `discard_left` / `draw_discarded` | 이 카드 왼쪽을 버리고 그만큼 드로우 | |
| `hand_passive:<key>` | 비용 -1 카드의 표지 (실행되지 않음) | |

**교전 절 플래그**

| 플래그 | 뜻 | 쓰는 카드 |
|---|---|---|
| `at_target` | 지정한 **적 주변**에서 연다 | 돌격 · 강습 · 간보기 |
| `at_marked` | 목표가 찍힌 적 주변에서 | 단계 B |
| `self_range:N` | 시전자 중심 반경 N | 우세한 전장 · 개시 · 제압 전투 |
| `charge_rounds` | 라운드 수를 영혼 포식 충전으로 갈음 | 전쟁의 사슬 |
| `move_in` | 시전자가 대상 칸으로 **전장에서 이동**한 뒤 교전 (무대 낙하 없음) | 돌격 |
| `drop_in` | `move_in` + 무대에서 적 진형 한가운데에 낙하 | 강습 |

`EngagePhaseManager._gather_participants` 가 `center` / `radius` 를 받는다(기본값은
시전자 칸 + 인접 6칸).

**대상 종류 (`target` 컬럼)** — `foe`(적 파일럿 **또는** 포탑 — 칸을 고르게 하고 그 칸의
무엇을 때리는지는 공격 절이 정한다, 파일럿이 먼저. 대상 지정 오버레이는 초상화와 칸
중 하나만 다루는데 포탑에는 초상화가 없다) · `turret_outer`(레인별 최외곽 적 포탑) ·
`turret_any`(살아 있는 적 포탑 전부, 사거리 무시) · `pilot`(아군과 적을 **둘 다**
고를 수 있다 — 매혹).

## 지속 상태 — `PilotData` 필드

메크가 거는 상태는 전부 `PilotData` 에 살고 이 모듈이 켜고 끈다.

| 필드 | 뜻 | 읽는 자리 |
|---|---|---|
| `vulnerable` | 취약 — 1마다 받는 피해 +1% | `damage_taken_mult` |
| `reactive_armor` | 반응 장갑 — 한 대당 90% 감소 후 1 소모 | `consume_reactive_armor` |
| `damage_taken_bonus` | 받는 피해 배율 가산 (죽음의 손가락) | `damage_taken_mult` |
| `bounty` | 현상금 | `attack_bounty` |
| `marked_by` / `marked_bonus` | 목표 (그 시전자에게만) | `damage_taken_mult` |
| `tracked_by` | 추적 — 이 적이 싸우면 끌려 들어올 사람들 | `_gather_participants` |
| `engage_link` | 결속 | `_gather_participants` |
| `engage_locked` | 탈진 | `_gather_participants` |
| `stun_charge` / `stunned_rounds` | 강타 / 기절 | `TurnEngageSim` |
| `growth_link_to` | 매혹 | `BattleSim.add_score` |
| `bonus_atk_flat` / `bonus_atk_mult` / `bonus_max_hp` | 영구 스탯 보정 | `refresh_growth_stats` |
| `phase_return_cell` | 자리 되돌리기 예약 (질풍) | `on_phase_end` |

**반응 장갑은 보호막보다 먼저 걸린다** — 90%를 깎고 남은 10%를 보호막이 받아야 두
방어가 겹쳐 읽힌다. 반대면 보호막이 온전한 피해를 먼저 먹고 장갑은 잔량에만 걸린다.
**취약 · 죽음의 손가락 · 목표는 곱이 아니라 합이다** — 셋 다 "받는 피해 +N%"라는 같은
문장이고, 곱으로 쌓으면 취약 100 에 죽음의 손가락이 겹친 순간 배율이 2.5 를 넘는다.

## 패시브 15개

`type` 이 없다 — 전부 상시/자동이고 누를 수 있는 것은 없다. 충전을 쓰는 패시브의
충전은 **효과의 조건**이지 활성화의 연료가 아니다.

| 기체 | 키 | 하는 일 |
|---|---|---|
| E 0 | `bulk_power` | 최대 체력 10마다 공격력 +1 (체력 확정 **뒤**에 더한다) |
| G 1 | `reactive_plating` | 교전 시 자신에게 반응 장갑 2 |
| N 2 | `pain_pleasure` | 피해를 주고받은 20%만큼 최대 체력 증가 / 자기 레인 포탑을 **자기가** 부수면 덱에 [고통과 쾌감] |
| D 6 | `victory_report` | 오브젝트 승리 시 핸드에 [승전보] |
| F 7 | `demolition_order` | 오브젝트 승리 시 핸드에 [철거] |
| H 8 | `execution_charge` | 처치/철거마다 +1 충전(최대 5) / 최대 충전 시 핸드에 [처형] |
| L 9 | `soul_harvest` | 명중·교전 피해마다 공격력 +1%, 최대 체력 +5 |
| P 12 | `overclock` | 시작 +20 충전(최대 100) / 교전 피해 시 1충전당 1% 로 추가 공격 + 충전 절반 소모 |
| T 14 | `zen_charge` | 카드 사용/버리기마다 +1 충전(최대 6) / 최대 충전 시 전부 태워 사거리 1 내 광역 공격 |
| Q 19 | `guardian_link` | 이 메크의 보호막을 받은 아군이 피해를 주면 이 메크도 그 적을 공격 |
| V 22 | `last_stand` | 교전 시 **팀 전원**이 한 번에 한해 체력 1 이하로 안 내려감 |
| A 24 | `vulnerability_mark` | 이번 작전 단계 동안 카드 명중마다 대상에게 취약 10 |
| C 26 | `missile_stock` | **자신 레인의** 포탑이 어느 팀 것이든 무너질 때마다 덱에 [미사일] |
| I 27 | `barrage` | 교전 중 공격이 적 전원을 대상으로 (대가: 공격력 절반) |
| J 28 | `calibration` | 전장 카드 명중마다 공격력 +1 |

패시브가 없는 여섯: **B(25) · K(18) · R(13) · S(20) · U(21) · W(15)** — 카드로만 논다.

**카드에 붙은 사건 훅**(`mech_cards.trigger`)은 패시브가 아니라 그 카드가 존재를 얻는
조건이라 카드 쪽에 산다 — `turret_kill_deck`(꿰뚫는 번개: 적 포탑을 부술 때마다 덱에
1장) · `death_hand`(공격 명령: 누가 죽을 때마다 손패에 1장). 훅이 걸린 카드를 그
기체가 들고 오는가는 배분 표(`starter_cards`)로 판정한다 — 지금 손패/덱/더미 어디에
있든(소멸했어도) 답이 같다.

## 이 모듈이 하지 않는 것

**카드 효과는 여기 없다.** 절 문법은 전부 `CardPhaseManager._apply_single_effect`
가 처리하고(위 "효과 문법" 절), 이 모듈은 그 절들이 남기는 **상태**와 그 상태를 읽는
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
| `CASH_RATE` | 0.04 | [캐시] 가 카드 한 장마다 버는 자기 성장치 비율. 적립은 `award_score` 를 지나 **초상화 위에 팝업이 뜬다** — 흔적이 없으면 그 카드를 손에 들고 있는 것과 없는 것이 화면에서 구분되지 않는다 |
| `SCORE_COST_UNIT` | 0.01 | `score_cost:N` 의 단위 — **N=100 이 1.00k** |
| `PHASE_BOON_BETA_CHARGE` | 100 | 강화 베타가 [단계 B] 에 얹는 충전 |
| `PHASE_BOON_GAMMA_RATE` | 0.10 | 강화 감마가 [단계 C] 에서 버는 자기 성장치 비율 |

배율(몇 %인가)이 CSV 가 아니라 여기 사는 이유는 파일럿 스킬과 같다: 패시브마다
의미가 다른 숫자 칸을 대여섯 개 만들지 않기 위해서다. CSV 의 `p1` / `p2` 는
패시브마다 뜻이 다른 두 숫자이고(시작 충전 · 최대 충전 · 취약 수치 · 피해 비율),
그 뜻은 `KEY_*` 상수 옆 주석에 적혀 있다.

## 아직 남은 것

| 항목 | 왜 |
|---|---|
| **강화 3택의 AI 판단** | AI 는 알파 · 베타 · 감마를 무작위로 고른다. 파일럿 스킬 AI 가 활성화를 아예 하지 않는 것과 같은 1차 한계이고, 규칙을 세우려면 "지금 이 사슬이 몇 바퀴째인가"를 AI 가 알아야 한다 |
| **기절의 라운드 길이** | 언제나 1라운드(다음 차례 하나)다. 카드 텍스트가 길이를 말하지 않아 최소값을 골랐다 |

## 검증

전체 루프 스모크(헤드리스, `match_ctx` 를 손으로 채운 하네스, 60턴 · 역할군 회전
여러 벌: 스크립트 오류 0 · 충전 누적 확인)로는 60턴 안에 닿지 않는 자리가 있어
표적 검사를 따로 부른다.

| 검사 | 확인하는 것 |
|---|---|
| `passive/*` | 패시브가 배정된 기체에서 실제로 읽힌다 |
| `stun/*` | 한 교전에 같은 적 한 번, 차례 하나를 소모, 교전 종료 시 장전 해제 |
| `contempt/*` | 교전 개시 직후 충전 수만큼 최저 HP 적을 공격력 50% 로 때리고 충전이 0 이 된다 |
| `last_stand/*` | **팀 전원**에게 걸리고 각자 한 번씩 |
| `overclock/*` | 충전이 가득하면 반드시 발동하고 절반이 날아간다 |
| `engage/*` | 전탄 발사 · 오버클럭 · 불굴이 얹힌 5v5 가 끝까지 굴러가고 피해가 흐른다 |
| `phase_b/*` | 처치 있음 → 덱에 [단계 C], 없음 → [단계 A] |
| `boon/alpha` · `boon/gamma` | 예약이 걸리고 **한 번만** 쓰인다 |
| `gust/return` | 뛰어들고 단계 종료 시 원래 칸으로 |
| `guardian/*` | 편승 공격이 실제로 들어가고, **보호막이 없으면 안 들어간다** |
| `ai/*` | 비용 -1 카드를 거르고, 사거리 밖 공격 카드를 거르고, 사거리 안이면 점수를 준다 |


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| 메크 스킬 | **기체 한 대에 붙는 고유 능력과 고유 카드 셋.** 파일럿 스킬이 선수에게 붙는 한 수라면 이쪽은 그 선수가 타고 있는 기체가 하는 일이라, **밴픽에서 기체를 고르는 순간 그 파일럿의 덱 절반과 상시 능력 하나가 함께 정해진다**. 표는 `data/csv/mech_passives.csv`(**15행**)와 `data/csv/mech_cards.csv`(**64행**)이고 짝은 `mechs.id` 다 — `players.skill_id` 같은 포인터 컬럼이 없는 것은 기체 한 대가 자기 패시브 하나와 자기 카드 셋을 통째로 소유하기 때문이다. **메크는 21대**이고(원딜 5 · 전사 4 · 탱커 3 · 지원 5 · 암살 4) 그중 15대만 패시브를 갖는다. **덱 구성이 바뀌었다** — 예전의 "공용 메크 카드 풀에서 3장 뽑기"가 사라지고 배정된 기체의 카드 목록을 `count` 만큼 펼친 것이 그 자리를 통째로 채운다(기체마다 2~7장이라 **덱 크기 자체가 기체 선택의 일부**다). 그 폴백(`MECH_CARDS_PER_PILOT` — cards.csv 의 "공용 메크 카드" 3장)도 **삭제됐다** — cards.csv 의 mech 행이 전부 파일럿 카드가 되면서 기체가 없는 단독 실행 덱에는 파일럿 카드만 들어간다. 메크 카드 설명문은 키워드 머리말("소멸." · "충전. …")을 걷었고, 패시브 · 카드의 내부 카운터는 화면에서 **토큰**이다. 패시브 보정은 **질의 함수로만** 나가고 계산은 원래 하던 자리가 한다(`BattleSim.refresh_growth_stats` / `SimulationCore._pilot_hit_damage` / `CardPhaseManager._apply_attack_damage`) — 스탯을 직접 밀면 성장 재계산 한 번에 지워지기 때문이고, 영구 증가분은 `PilotData.bonus_atk_flat` / `bonus_atk_mult` / `bonus_max_hp` 로 따로 산다. **메크에 `role` 컬럼이 생겼다** — 카드 셋이 역할군을 전제하게 됐기 때문이며, 다만 **배정은 여전히 자유다**(어느 역할 슬롯에 어느 기체를 앉혀도 된다 — 분류와 데이터 검증용). **교전 무대까지 전부 배선됐다** — 전탄 발사(공격이 적 전원) · 오버클럭(피해 직후 한 번 더) · 불굴(팀 전원 1회 사망 방지) · 약자 멸시(**1라운드 전** 충전 수만큼 최저 HP 적을 공격력 50% 로) · 강타/기절(맞은 적이 다음 차례를 잃음)이 `TurnEngageSim` 에서 실제로 걸리고, 그 다섯은 전부 `MechSkillSystem` 의 질의 함수를 지난다. **수호 연계**(이 메크의 보호막을 두른 아군이 때리면 메크도 얹는다)는 전장 자동 교전에서 **판정이 아니라 적용이 끝난 뒤** 굴린다(`SimulationCore._flush_guardian_rides`) — 판정 단계에서 곧장 때리면 편승 한 방이 아직 적용되지 않은 피해보다 먼저 상대를 눕혀 같은 턴의 나머지 판정이 시체를 상대로 굴러간다. **단계 A→B→C 사슬**과 강화 3택도 섰다 — 아래 "단계 사슬" 항목. 21대 목록 · 키워드 · 절 문법 · 코드 쪽 규약은 전부 이 README 위쪽 절들. |
