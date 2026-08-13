# Module: Engage (전투 개시) — 실시간 MOBA 교전

## Purpose
`engage:N` / `duel` 카드 효과로 발동되는 **실시간 교전**. 전장(BattleSim)이
셀 단위 턴제로 굴러가는 것과 달리, 교전은 전용 풀스크린 아레나에서 각
파일럿이 자기 AI로 추격 / 카이팅 / 공격 / 포탑 회피 / 다이브를 연속 시간
위에서 수행한다. **플레이어 입력은 없다 — 관전 전용.**

> **교전 중 이탈은 없다.** 제한 시간이 끝날 때까지 아무도 아레나를 뜨지
> 못한다. 근접은 사거리에 들 때까지 계속 쫓고, 원거리는 자기 사거리 안에서
> 거리를 벌리며 계속 쏜다. 빈사(HP<30%)여도 후퇴하지 않는다.

> 2026-08 이전의 N 라운드 턴제 루프(`EngageOverlay.gd` + `EngagePhaseManager`
> 의 `_run_engage` / `resolve_silent`)는 제거되었다. 되살리지 말 것.

## Files
| File | Purpose |
|---|---|
| `EngagePhaseManager.gd` | `class_name EngagePhaseManager extends Node` — 오케스트레이터. 참가자를 모으고, `RealtimeEngageSim` 을 만들고, `_process` 에서 고정 스텝으로 굴리고, 종료 판정 후 `END_HOLD_SEC`(2.0초) 유예를 두고 대시보드를 띄운다. 공개 API는 이전과 동일: `start_engage(caster, rounds, exclude_lane, on_done)` / `start_duel(caster, target, on_done)` / `is_active()` / `engage_finished` 시그널. |
| `RealtimeEngageSim.gd` | `class_name RealtimeEngageSim extends RefCounted` — **헤드리스 시뮬레이터**. 노드를 하나도 만들지 않는다. 유닛 AI, 포탑, 데미지, 종료 판정 전부 여기. 튜닝 상수도 전부 여기 상단에 모여 있다. |
| `EngageArena.gd` | `class_name EngageArena extends Control` — 시뮬레이터 상태를 그리기만 하는 렌더러. 바닥 / 셀 육각 / 포탑 사거리원 / 유닛 / 투사체를 **클리핑 창 + 카메라** 아래에 그리고, Label 노드로 타이틀·타이머·로스터·데미지 팝업을 담당한다. 종료 사유 배너(`mark_engage_over`)와 결과 대시보드도 여기. |

매니저는 `BattleSim._ready()` 에서 자식으로 붙고 `_bs.engage_phase` 에 잡힌다.
매니저가 소유한 전용 `CanvasLayer`(`ENGAGE_OVERLAY_LAYER = 12`)에 아레나가
붙는다. 이 레이어는 HUD 캔버스(1), `CardSelectOverlay`(10),
`CardTargetingOverlay`(11) 위이므로 아레나와 대시보드는 항상 핸드 행과
남아 있는 타게팅 UI 위에 그려진다.

## Trigger flow
1. 플레이어(또는 AI)가 engage 카드(`engage:3` 전투 개시, `engage:4` 완벽한
   기회) 또는 결투(`duel`)를 낸다. `engage:N|exclude_lane` 도 그대로
   동작하지만 현재 이 플래그를 다는 카드는 없다.
2. `CardPhaseManager._effect_engage()` → `EngagePhaseManager.start_engage(...)`,
   `_effect_duel()` → `start_duel(...)`.
3. 매니저가 `_bs.game_phase = ENGAGE` 로 전환. BATTLE 자동 틱은 멈추고,
   카드 hover/click 과 턴 넘기기도 `CARD_PHASE` 가드 때문에 차단된다.
4. 아레나가 열리고 매니저의 `_process` 가 시뮬레이터를 고정 스텝
   (`FIXED_DT = 1/60`, 프레임당 최대 `MAX_STEPS_PER_FRAME = 8` 스텝)으로 굴린다.
5. 종료 판정 → **`END_HOLD_SEC`(2.0초) 유예** → 대시보드(준 딜량 / 받은 딜량 /
   처치 수) → `확인` → 아레나 제거, `phase = CARD_PHASE`, `on_done` 호출,
   `engage_finished` emit.

AI 플레이도 같은 아레나를 탄다. `AiCardPlayer.run_ai_plays()` 는 매 플레이
후 `engage_phase.is_active()` 면 `engage_finished` 를 `await` 한다 — 카드의
effect chain 이 아니라 `is_active()` 로 판정하므로 clause 가 `duel` 인 결투도
정상적으로 기다려진다.

## 시간 규칙 (engage:N → 초)
`N` 은 이제 라운드 수가 아니라 **`N × RealtimeEngageSim.SEC_PER_ROUND` 초**다.
현재 `SEC_PER_ROUND = 3.0` 이므로:

| 카드 | effect | 지속 |
|---|---|---|
| 전투 개시 | `engage:3` | 9초 |
| 완벽한 기회 | `engage:4` | 12초 |
| 결투 | `duel` | 한 쪽 처치까지 (상한 `DUEL_MAX_SEC` 15초) |

`data/csv/cards.csv` 의 description 도 초 표기로 갱신되어 있다. CSV 를 만졌으면
**Project → Tools → Rebuild game.db** 를 돌려야 게임에 반영된다.

제한 시간이 끝나면 **그 프레임에 곧바로 전투가 멈춘다**(후퇴 연출 없음). 그래서
`engage:3` 의 전투 시간은 정확히 9초다. 다만 대시보드는 그 뒤 `END_HOLD_SEC`
(2.0초) 유예를 두고 뜨므로 모달 전체는 약 11초다 — 아래 [종료](#종료) 참고.

## 화면 구성 — 클리핑 창 · 카메라 · 딤
아레나 그래픽은 **`VIEW_RECT`(24, 236, 1032×1184) 한 사각형 안에서만** 보인다.
그 밖(전장 · 핸드 행 · HUD)은 풀스크린 딤(`DIM_COLOR`, 검정 α 0.82)으로 눌린다.

```
EngageArena (Control, 풀스크린, MOUSE_FILTER_STOP)
├─ dim        ColorRect 풀스크린            ← 아레나 밖을 눌러 준다
├─ _clip      Control  VIEW_RECT, clip_contents = true   ← 여기서 잘린다
│   ├─ backdrop  ColorRect (레터박스 색)
│   └─ _world    DrawProxy(Node2D)  position/scale = 카메라
│        └─ 데미지 팝업 Label 들 (아레나 좌표계)
├─ _hud       DrawProxy(Node2D) 화면 좌표계 — 뷰 테두리 · 남은 시간 바
├─ 타이틀 / 타이머 / 상태 / 로스터 Label·Panel
└─ 대시보드 Panel (종료 시)
```

**왜 `_draw()` 를 자기 자신에 안 쓰는가**: Control 은 자기 그림을 먼저 그리고
그 위에 자식을 그린다. 딤 ColorRect 가 자식이므로 자기 `_draw` 로 그린 아레나는
딤 **아래**에 깔려 통째로 어두워진다. 딤보다 뒤에 붙은 프록시 노드에 그려야
"아레나 밖만 딤드"가 성립한다.

**왜 `DrawProxy` 가 Control 이 아니라 Node2D 인가**: Control 은 DRAW 통지마다
자기 크기로 `custom_rect` 를 다시 박는다. 크기 0 인 Control 은 빈 사각형으로
**컬링되어 `_draw` 안의 그림이 통째로 사라진다**(자식 Label 은 자기 rect 가
있으니 멀쩡히 보여서 더 헷갈린다). Node2D 는 실제 draw 커맨드에서 rect 를
잡으므로 카메라 변환(scale/position) 아래에서도 안전하다.

### 카메라 워킹
`_update_camera()` 가 매 프레임 **생존(미처치) 유닛 전원**의 바운딩 박스를
잡아 프레이밍한다.

```gdscript
target_zoom   = clamp(min(VIEW/span.x, VIEW/span.y), _cam_min_zoom, CAM_MAX_ZOOM)
target_center = 바운딩 박스 중심
```

| 상수 | 값 | 의미 |
|---|---|---|
| `_cam_min_zoom` | 런타임 계산 ≈ **1.06** | 아레나 전체(960×1120)가 뷰에 딱 들어가는 배율. 이보다 축소해 봐야 빈 여백만 는다. |
| `CAM_MAX_ZOOM` | 2.4 | 유닛이 뭉쳤을 때의 상한 |
| `CAM_PAD` | 120 | 바운딩 박스 바깥 여백(아레나 px). `UNIT_RADIUS` 는 별도로 더해진다 |
| `CAM_POS_RATE` / `CAM_ZOOM_RATE` | 4.0 / 2.6 | 지수 감쇠 계수(1/s). 줌이 더 느린 이유는 유닛 하나가 튀었다고 배율이 출렁이면 멀미가 나기 때문 |

`_clamp_cam_center()` 가 매 프레임 카메라를 아레나 사각형 안에 가둔다 —
**뷰는 절대 아레나 밖을 비추지 않는다.** 뷰가 아레나보다 넓은 축(최소 배율
근처)은 그냥 아레나 중앙에 고정한다. `setup()` 은 첫 프레임을 보간 없이
스냅한다(중앙에서 스르륵 밀려오면 개전 순간을 놓친다).

실측(5v5, engage:3): 같은 셀에서 시작 → **2.1×**, 흩어져 교전 → **1.85×**.

데미지 팝업은 `_world` 의 자식이라 카메라를 따라 움직이고 뷰 밖에서 잘린다.
대신 월드 스케일까지 먹으므로 글자 크기가 배율에 휘둘리지 않도록 `1/zoom` 을
되먹여 화면상 크기를 고정한다.

## 아레나 좌표계
교전 참여 셀(시전자 셀 + 인접 6칸)의 전장 화면 좌표를 그대로 확대해서
아레나 좌표로 쓴다:

```gdscript
arena = ARENA_CENTER + (hex_to_screen(cell) - hex_to_screen(origin_cell))
        / hex_grid.hex_height * CELL_PITCH
```

즉 **전장에서 왼쪽 위 셀에 있던 파일럿은 아레나에서도 왼쪽 위**에서 시작한다.
`CELL_PITCH = 380` px, 아레나는 `ARENA_CENTER (540, 880)` 중심에
`ARENA_HALF (480, 560)` 반경.

### 시작 배치
- 자기 셀 중심에서 반경 `SPAWN_JITTER`(92px) 안 랜덤 배치. 팀 진영 쪽
  (팀0 아래 / 팀1 위)으로 34px 치우친다.
- **같은 팀이 같은 셀에 겹쳐 있으면** 첫 유닛이 앵커가 되고, 나머지는
  앵커 주변 `ALLY_CLUMP`(48px) 링에 붙어서 시작한다.

### 포탑
`_origin_cell` 에서 육각 거리 `TURRET_GATHER_DIST`(2) 이내의 살아 있는
포탑이 아레나에 등장한다. 사거리는 `TURRET_RANGE`(340px) — `CELL_PITCH`(380)
보다 **작게** 잡혀 있다. 이 값을 `CELL_PITCH` 위로 올리면 이 맵처럼 포탑이
촘촘한 전장에서 아레나 대부분이 금지구역이 되고, AI 가 싸우지 않고 회피만
하게 된다.

> **전장과의 의도적 차이**: 전장에서는 포탑이 파일럿을 공격하지 않지만,
> 아레나에서는 **공격한다**(`TURRET_ATK` 데미지, `TURRET_INTERVAL` 1.1초,
> 명중 굴림 없음). "포탑 사거리에 닿으면 위험하다"가 이 시뮬레이터의 핵심
> 압박이기 때문. 반대로 아레나에서 **포탑 HP 는 깎이지 않는다** — 포탑
> 파괴는 전장 쪽 룰로 남는다.

## 유닛 AI
| 역할 | 판정 | 사거리 | 이동속도 | 공격 간격 | 공격 경직 |
|---|---|---|---|---|---|
| 근접 (TANK / FIGHTER / ASSASSIN) | `_is_melee_role` | 86px | 209px/s (×1.1) | 0.85s | 0.30s |
| 원거리 (SUPPORT / SNIPER) | — | 300px | 190px/s | 1.05s | 0.45s |

- **근접**: 사거리(86px) 안에 들어갈 때까지 계속 쫓는다(이탈이 없으므로 교전
  내내). 원거리보다 이동속도가 `MELEE_SPEED_MULT`(1.1)배 빠르다.
- **원거리(카이팅)** — `_kite_dir`. 기준은 자기 타겟이 아니라 **자기 카이팅
  반경을 가장 깊이 파고든 적**(`_kite_threat`)이다. 근접이 달라붙었는데 멀리
  있는 타겟 쪽으로 걸어 들어가는(= 근접 품으로 들어가는) 짓을 막기 위함.

  | 적 종류 | 허용 최소 거리 (`_kite_inner_dist`) |
  |---|---|
  | 근접 | 그 적의 사거리 + `KITE_MELEE_MARGIN`(70) = 156px |
  | 원거리 | 자기 사거리 × `KITE_INNER_RATIO`(0.72) = 216px |

  둘 다 자기 사거리 × `KITE_OUTER_RATIO`(0.95)로 상한이 걸린다 — 그보다 멀리
  물러나면 영영 못 쏜다. 아무도 그 선을 넘지 않았으면 사거리 끝자락(0.95배)
  까지만 접근한다. **뒤로 빼면 타겟이 사거리 밖으로 나가는 상황**에서는 후진
  대신 타겟을 중심으로 도는 접선 방향으로 움직인다 — "최대 사거리 안에서"
  거리를 벌리라는 요구가 이 분기다.
- **공격 경직**: 공격을 넣으면 `atk_lock` 동안 이동 입력이 무시된다.
  원거리 경직이 더 길어서 "쏘고 빠지는" 리듬이 생긴다.
- **대쉬**: `has_dash` 는 **시전자가 근접일 때만** 켜진다. 교전 시작 직후
  최초 1회, 첫 타겟 방향으로 `DASH_SPEED`(900px/s) × `DASH_SEC`(0.32s)
  ≈ 288px 를 돌진한다. 대쉬 중에는 다른 AI 판단을 하지 않는다.
- **타겟 선정** (`_pick_target`): 점수 = `거리 / 존재감`, 낮을수록 매력적.
  빈사(HP 35% 미만)면 `LOW_HP_FOCUS`(0.6) 가중, **아군이 이미 물고 있는 적**
  이면 인원수만큼 `FOCUS_BONUS`(0.78^n, 하한 0.45) 가중. 이 집중 사격 항목이
  없으면 전원이 각자 최근접 적만 때려서 딜이 흩어지고 처치가 거의 안 나온다.
  타겟은 `RETARGET_SEC`(1.6초)마다 또는 타겟이 빠졌을 때 갱신된다.
- **포탑 회피**: `dive_ok` 가 아니면 적 포탑에서 멀어지는 벡터가 이동 의도에
  `TURRET_AVOID_WEIGHT`(1.7) 가중으로 합성된다. 사거리 안쪽일수록 강해진다.
- **다이브** (`_should_dive`, `DIVE_EVAL_SEC` 0.5초마다 재평가):
  ```
  ttk      = (타겟 HP + 보호막) / 내 DPS
  incoming = 적 포탑 DPS × (ttk + DIVE_ESCAPE_SEC)
  dive_ok  = (내 HP + 보호막) - incoming > max_hp × DIVE_SAFETY_RATIO
  ```
  즉 "버티고, 잡고, 빠져나올 수 있다"는 계산이 서면 회피를 끄고 들어간다.
  타겟이 포탑 사거리 밖이면 다이브라는 개념 자체가 없으므로 항상 false.

## 종료
`State` 는 `COMBAT / DASH / DEAD` 셋뿐이다. **RETREAT / FLED 는 없다** —
`_clamp_to_arena` 가 매 프레임 전원을 아레나 안에 가두므로 물리적으로도 나갈
수 없다.

- **제한 시간 만료**: `elapsed >= duration` 인 프레임에 `finished = true`.
- **한쪽 전멸**: `active_count(team) == 0` 이면 즉시 `finished = true`.
- **저HP**: 아무 일도 일어나지 않는다. 빈사 유닛도 평소와 똑같이 붙고/카이팅
  하며 끝까지 싸운다. HP 30% 미만은 로스터 HP 바 색(`EngageArena.LOW_HP_RATIO`)
  으로만 표시되며 게임플레이 의미는 없다.

### 종료 유예 (`END_HOLD_SEC` = 2.0초)
`finished` 가 서자마자 대시보드를 띄우면 **마지막 처치가 결과창에 먹혀** "방금
누가 죽은 거지?" 가 된다. 그래서 매니저는 종료 판정과 대시보드 사이에
`EngagePhaseManager.END_HOLD_SEC`(2.0초) 유예를 둔다.

- 유예 동안 `_process` 는 `step()` 대신 **`RealtimeEngageSim.step_afterglow(dt)`**
  를 부른다 — 투사체 위치 / `hit_flash` / `swing_t` 만 흐르고 전투 판정(이동,
  공격, 포탑, 종료)은 일절 돌지 않는다. `elapsed` 도 멈추므로 **대시보드의
  교전 시간은 실제 전투 시간 그대로**(engage:3 = 9.0초)다.
- 아레나는 계속 `_process` 를 돌리므로 카메라도 살아 있다. 마지막 생존자
  쪽으로 프레이밍이 마저 붙는다.
- 매니저가 `EngageArena.mark_engage_over(reason)` 로 상단 상태 라벨을 종료
  사유 배너(`교전 종료 — 적군 전멸` / `아군 전멸` / `양측 전멸` / `시간 종료`)
  로 승격시키고 한 번 튕겨(scale 1.18 → 1.0) 시선을 끈다. 배너 문자열은
  `_end_banner_text()` 가 `active_count(0/1)` 로 판정한다.
- 유예 값을 0 으로 두면 예전(즉시 대시보드) 동작으로 돌아간다.

> 이탈이 사라진 대가: 적 포탑 사거리에 갇힌 파일럿은 빠져나갈 수단이 없다.
> `_desired_move_dir` 의 포탑 회피(`TURRET_AVOID_WEIGHT`)가 유일한 방어선이고,
> 아레나 전체가 포탑 사거리에 덮인 배치(예: 시전자 셀이 곧 포탑 셀)에서는
> 교전 시간 내내 포탑에 맞아 죽을 수 있다.

### 전장 상태 반영
- 데미지는 `PilotData.hp` / `.shield` 에 **직접** 적용된다. 교전이 끝나면
  전장에 그대로 반영된다(턴제 시절과 동일).
- 처치 → `_bs.mark_pilot_dead(pilot)`. 전장과 같은 사망 경로라 리스폰 턴
  스케일링(`respawn_turns_now()` = 5 + 경과 턴/10)과 전사 연출이 아레나
  처치에도 그대로 걸린다.
- **`grid_pos` 는 건드리지 않는다.** 살아남은 파일럿은 원래 셀에 그대로 남는다.
  저HP 파일럿은 작전 단계 종료 시 `RecallSystem.process_phase_end_recalls()`
  의 HP 임계 복귀가 어차피 본진으로 데려간다.

## 데미지 모델 — 피해는 전장과 동일, **명중률은 별개**
```
base   = hit / (hit + evasion)                      # 전장과 같은 기준값
명중   = randf() < base + (1 - base) * ENGAGE_HIT_LERP
피해   = attacker.atk        (보호막부터 흡수, 그 다음 HP)
```
피해 공식은 전장(`SimulationCore.roll_hit` / `_apply_damage`)과 공유하지만
**명중 굴림만 교전 전용**이다 — `_hit_chance()` 가 전장 확률을
`ENGAGE_HIT_LERP`(현재 **0.7**)만큼 1.0 쪽으로 끌어올린다. 교전은 몇 초 안에
끝나는 짧은 창이라 전장 명중률(55vs45 → 55%)을 그대로 쓰면 MISS 가 너무
자주 떠서 아무 일도 안 일어난 것처럼 보인다.

| hit vs evasion | 전장 | 교전 (lerp 0.7) |
|---|---|---|
| 55 vs 45 | 0.550 | **0.865** |
| 50 vs 60 | 0.455 | **0.836** |
| 60 vs 40 | 0.600 | **0.880** |

보정은 단조 증가라 **스탯 우열 순서는 그대로 보존**된다(명중 높은 파일럿이
여전히 더 잘 맞힌다). `0.0` 으로 두면 전장과 완전히 동일해지고, `1.0` 이면
무조건 명중. 전장 명중률을 바꾸고 싶으면 `SimulationCore.roll_hit` 쪽을
건드려야 하며, 두 값은 서로 영향을 주지 않는다.

포탑 사격만 예외로 명중 굴림 없이 `TURRET_ATK` 를 넣는다.

### 처리량 — 실측 (`ENGAGE_HIT_LERP` 도입 **이전**, 헤드리스 5v5 ×5, hp 220 / atk 8 / hit 55 / evasion 45)
> 아래 수치는 명중률이 전장과 같던(0.55) 시절의 실측이다. 지금은 명중률이
> 0.865 로 올라갔으므로 딜량·처치 모두 대략 **1.57배** 수준으로 늘어난다고
> 보면 된다. 재측정 전까지는 상대적인 비율(근접 vs 원거리 피해)만 참고할 것.

9초 교전에서 파일럿당 준 딜량 **16~80**, 한 명이 받은 최대 누적 딜량
**160~220**, 처치는 5판 중 1판에서 1건. 이탈이 없어진 만큼 빈사 유닛이
끝까지 맞아 주므로 턴제/이탈 시절보다 처치가 나기 쉬워졌지만 여전히 드물다.

팀 단위로 보면 **원거리가 받는 딜이 근접의 1/5~1/10**(근접 464~604 vs 원거리
40~144)로 갈린다 — 카이팅이 실제로 먹히고 있다는 신호. 근접 쪽 피해가 이보다
줄면 `KITE_MELEE_MARGIN` 이 너무 커서 원거리가 안 잡히는 것이다.

처치 빈도를 조절하는 교전 전용 노브는 둘이다: **`ATK_INTERVAL_MELEE` /
`ATK_INTERVAL_RANGED`**(공격 빈도)와 **`ENGAGE_HIT_LERP`**(명중률). 둘 다
교전에만 적용되므로 전장 밸런스를 건드리지 않는다. 반면 **피해량(atk 1회분)은
전장 룰과 공유**하므로 손대면 전장까지 같이 움직인다.

## 참가자 수집 (변경 없음)
시전자 셀 + 인접 6칸(반경 1 육각). 시전자는 항상 포함. 양 팀의 생존
파일럿이 그 7칸 안에 있으면 참여한다. 정글러/레인 파일럿의 교전 스코프
구분은 여기서 적용되지 않는다 — engage 는 그 경계를 명시적으로 넘는다.

### `exclude_lane` 플래그 (현재 이 플래그를 쓰는 카드는 없음)
이 플래그를 달고 있던 **교전(id 4) 카드는 `cards.csv` 에서 제거**되어, 지금
카드 풀에는 이 플래그를 세우는 카드가 하나도 없다. 플래그 자체는
`CardPhaseManager` → `CardTargetingOverlay` 프리뷰 → `start_engage` 까지
그대로 파싱·처리되므로, 앞으로 어떤 카드든 `engage:N` 절에 `|exclude_lane`
을 붙이면 다시 살아난다.

자기 lane 위에 정상적으로 서 있는(= jungle/neutral 셀에 있지 않은) lane
파일럿을 제외한다. 정글러는 항상 포함, 카드 효과(`move` 등)로 jungle 셀에
변위된 lane 파일럿도 포함. 아군 정글러나 변위된 아군 lane 파일럿을 범위에
밀어 넣어 적 정글러 하나를 2:1 로 잡는 설계 의도다.

```gdscript
# inclusion rule under exclude_lane:
p.is_guerrilla OR _bs.neutral_zone_cells.has(p.grid_pos)
```

## 대시보드 통계
PilotData 를 키로 하는 dict:
```gdscript
{ "dealt": int, "taken": int, "kills": int }
```
`dealt` / `taken` 은 실제로 깎인 양(`shield_absorbed + hp_dmg`). 빗나감은
집계되지 않는다. 포탑에게 맞은 딜은 `taken` 에 잡히지만 `dealt` 는 아무에게도
귀속되지 않는다.

## Presence stat
`presence` 는 이제 **타겟 어그로 가중치**로만 쓰인다(공격 순서 개념이 사라짐).
`mechs.csv → MechData.presence → SimulationCore._stats_for → PilotData.presence`.
메크가 없을 때(standalone) 기본값은 근접 4 / 원거리 2.

## 헤드리스 검증
`RealtimeEngageSim` 은 `RefCounted` 라 노드/프레임 없이 돌릴 수 있다.
BattleSim 인스턴스만 하나 있으면:
```gdscript
var sim := RealtimeEngageSim.new()
sim.setup(bs, caster, team0_pilots, team1_pilots, 9.0, false)
while not sim.finished:
    sim.step(1.0 / 60.0)
```
⚠ standalone BattleSim 은 `pilots.csv` 로 폴백하는데 그 `atk` 는
160/300/500 이라 한 대에 즉사한다. 밸런스를 보려면 PilotData 에
mechs.csv 급 스탯(hp 190~220 / atk 8~9)을 찍고 돌려야 한다.
