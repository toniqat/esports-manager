# Module: Engage (전투 개시) — 실시간 MOBA 교전

## Purpose
`engage:N` / `duel` 카드 효과로 발동되는 **실시간 교전**. 전장(BattleSim)이
셀 단위 턴제로 굴러가는 것과 달리, 교전은 전용 풀스크린 아레나에서 각
파일럿이 자기 AI로 접근 / 카이팅 / 공격 / 포탑 회피 / 다이브 / 후퇴를
연속 시간 위에서 수행한다. **플레이어 입력은 없다 — 관전 전용.**

> 2026-08 이전의 N 라운드 턴제 루프(`EngageOverlay.gd` + `EngagePhaseManager`
> 의 `_run_engage` / `resolve_silent`)는 제거되었다. 되살리지 말 것.

## Files
| File | Purpose |
|---|---|
| `EngagePhaseManager.gd` | `class_name EngagePhaseManager extends Node` — 오케스트레이터. 참가자를 모으고, `RealtimeEngageSim` 을 만들고, `_process` 에서 고정 스텝으로 굴리고, 종료 시 대시보드를 띄운다. 공개 API는 이전과 동일: `start_engage(caster, rounds, exclude_lane, on_done)` / `start_duel(caster, target, on_done)` / `is_active()` / `engage_finished` 시그널. |
| `RealtimeEngageSim.gd` | `class_name RealtimeEngageSim extends RefCounted` — **헤드리스 시뮬레이터**. 노드를 하나도 만들지 않는다. 유닛 AI, 포탑, 데미지, 종료 판정 전부 여기. 튜닝 상수도 전부 여기 상단에 모여 있다. |
| `EngageArena.gd` | `class_name EngageArena extends Control` — 시뮬레이터 상태를 그리기만 하는 렌더러. `_draw()` 로 바닥 / 셀 육각 / 포탑 사거리원 / 유닛 / 투사체를, Label 노드로 타이틀·타이머·로스터·데미지 팝업을 담당한다. 결과 대시보드도 여기. |

매니저는 `BattleSim._ready()` 에서 자식으로 붙고 `_bs.engage_phase` 에 잡힌다.
매니저가 소유한 전용 `CanvasLayer`(`ENGAGE_OVERLAY_LAYER = 12`)에 아레나가
붙는다. 이 레이어는 HUD 캔버스(1), `CardSelectOverlay`(10),
`CardTargetingOverlay`(11) 위이므로 아레나와 대시보드는 항상 핸드 행과
남아 있는 타게팅 UI 위에 그려진다.

## Trigger flow
1. 플레이어(또는 AI)가 engage 카드(`engage:3`, `engage:4`,
   `engage:3|exclude_lane`) 또는 결투(`duel`)를 낸다.
2. `CardPhaseManager._effect_engage()` → `EngagePhaseManager.start_engage(...)`,
   `_effect_duel()` → `start_duel(...)`.
3. 매니저가 `_bs.game_phase = ENGAGE` 로 전환. BATTLE 자동 틱은 멈추고,
   카드 hover/click 과 턴 넘기기도 `CARD_PHASE` 가드 때문에 차단된다.
4. 아레나가 열리고 매니저의 `_process` 가 시뮬레이터를 고정 스텝
   (`FIXED_DT = 1/60`, 프레임당 최대 `MAX_STEPS_PER_FRAME = 8` 스텝)으로 굴린다.
5. 종료 → 대시보드(준 딜량 / 받은 딜량 / 처치 수) → `확인` → 아레나 제거,
   `phase = CARD_PHASE`, `on_done` 호출, `engage_finished` emit.

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
| 교전 | `engage:3\|exclude_lane` | 9초 |
| 결투 | `duel` | 처치/이탈까지 (상한 `DUEL_MAX_SEC` 15초) |

`data/csv/cards.csv` 의 description 도 초 표기로 갱신되어 있다. CSV 를 만졌으면
**Project → Tools → Rebuild game.db** 를 돌려야 게임에 반영된다.

제한 시간이 끝나면 곧바로 끝나는 게 아니라 전원이 `RETREAT` 로 전환되고
`RETREAT_GRACE`(1.8초) 동안 물러나는 연출이 붙는다. 그래서 `engage:3` 의
실제 모달 시간은 9 + 1.8 = 10.8초다.

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

- **근접**: 사거리(86px) 안에 들어갈 때까지 붙는다. 원거리보다 이동속도가
  `MELEE_SPEED_MULT`(1.1)배 빠르다.
- **원거리(카이팅)**: 사거리의 `KITE_INNER_RATIO`(0.72)보다 가까워지면
  물러나고, 0.95배보다 멀면 접근한다. 그 사이 밴드에서는 멈춰서 쏜다.
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

## 이탈 / 후퇴 / 종료
- **저HP 이탈**: HP 가 `FLEE_HP_RATIO`(0.30) 아래로 떨어지면 스스로
  `RETREAT` 로 전환하고 `fled_low_hp = true` 를 남긴다. 자기 진영 방향
  (팀0 아래 / 팀1 위) + 최근접 적 반대 방향 + 포탑 회피를 합성해
  `RETREAT_SPEED_MULT`(1.15)배 속도로 빠진다. 후퇴 중에는 공격하지 않지만
  **맞을 수는 있다.**
- **이탈 성공**: 아레나 사각형 밖으로 나가면 `FLED`. 살아서 전장으로
  돌아간다.
- **제한 시간 만료**: 전원이 `RETREAT` 로 전환(`_begin_global_retreat`)되고
  `RETREAT_GRACE` 뒤 종료. 이건 이탈이 아니라 정리 후퇴이므로
  `fled_low_hp` 가 붙지 않고, 대시보드의 "이탈" 표기에도 잡히지 않는다.
  (안 그러면 시작 위치가 자기 진영 쪽에 가까웠던 팀만 전원 "이탈"로 찍힌다.)
- **한쪽 전멸/전원 이탈**: 활성 인원(생존 && 미이탈)이 0이 되면 즉시
  전역 후퇴 → 종료.

### 전장 상태 반영
- 데미지는 `PilotData.hp` / `.shield` 에 **직접** 적용된다. 교전이 끝나면
  전장에 그대로 반영된다(턴제 시절과 동일).
- 처치 → `alive = false` + `respawn_timer = _bs.RESPAWN_TURNS`.
- **`grid_pos` 는 건드리지 않는다.** 이탈한 파일럿도 원래 셀에 그대로 남는다.
  저HP 파일럿은 작전 단계 종료 시 `RecallSystem.process_phase_end_recalls()`
  의 HP 임계 복귀가 어차피 본진으로 데려간다.

## 데미지 모델 (전장과 동일)
```
명중 = randf() < hit / (hit + evasion)
피해 = attacker.atk        (보호막부터 흡수, 그 다음 HP)
```
포탑 사격만 예외로 명중 굴림 없이 `TURRET_ATK` 를 넣는다.

### 처리량 — 실측 (2026-08-09, 헤드리스 5v5, hp 220 / atk 8 / hit 55 / evasion 45)
9초 교전에서 파일럿당 준 딜량은 **16~72**, 한 명이 받은 최대 누적 딜량은
**~184**. 즉 현재 메크 스탯에서 교전 한 번으로 처치가 나는 일은 드물고
(샘플 전원 생존), 저HP 이탈은 팀당 1~2명 발생한다. 턴제 시절(3라운드 =
파일럿당 3회 공격)보다는 2~3배 많은 딜이 오간다.

처치가 더 자주 나오길 원하면 **`ATK_INTERVAL_MELEE` / `ATK_INTERVAL_RANGED`
를 줄이는 것이 유일한 튜닝 지점**이다. 데미지 공식 자체(atk 1회분)는 전장
룰과 공유하므로 손대면 전장 밸런스까지 같이 움직인다.

## 참가자 수집 (변경 없음)
시전자 셀 + 인접 6칸(반경 1 육각). 시전자는 항상 포함. 양 팀의 생존
파일럿이 그 7칸 안에 있으면 참여한다. 정글러/레인 파일럿의 교전 스코프
구분은 여기서 적용되지 않는다 — engage 는 그 경계를 명시적으로 넘는다.

### `exclude_lane` 플래그 (카드 4 — 교전)
자기 lane 위에 정상적으로 서 있는 lane 파일럿을 제외한다. 정글러는 항상
포함, 카드 효과(`move` 등)로 jungle 셀에 변위된 lane 파일럿도 포함.

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
