# Gambit Phase Module

개시 전 단계(`BattlePhase.GAMBIT`)의 주인. 파일은 둘이다.

| File | Role |
|---|---|
| `GambitPhaseManager.gd`  | `extends Node` — BattleSim 의 씬 자식. 레인 고정 배정 + 전장 세우기 + 개시 |
| `JungleStartOverlay.gd`  | `class_name JungleStartOverlay extends Node` — **정글 시작 칸**을 전장 위의 정글러 마커를 끌어 고르는 오버레이. lazy-add |

인게임 레인 배정 오버레이는 **삭제됐다** — 레인은 역할이 고정하고, 그 자리는
밴픽 화면(`features/match_flow/ban_pick/`)이 가져갔다.

---

## GambitPhaseManager.gd

### Role → Lane mapping (constant `ROLE_TO_LANE`)
| Role | Lane |
|---|---|
| TANK | LEFT |
| FIGHTER | CENTER |
| ASSASSIN | GUERRILLA |
| SUPPORT | RIGHT |
| SNIPER | RIGHT |

LANE_MAX (from `lane_config.csv`) tolerates this distribution: 1 LEFT, 1 CENTER,
2 RIGHT, 1 GUERRILLA = 5 pilots.

### 개시 흐름 — 셋으로 갈라진 예전의 `launch_battle()`
```
launch_battle()
 ├ prepare_field()        전장을 통째로 세운다 → BattleSim.field_ready = true
 ├ _open_jungle_start()   match_ctx.active 면 오버레이를 연다 → 여기서 멈춘다
 └ begin_battle()         game_phase = BATTLE  (오버레이가 안 열렸을 때만)
```

- `prepare_field()` — `spawn_pilots_with_lanes` / `spawn_turrets` /
  `init_neutral_zones` / `init_jungle_camps`. **개시는 하지 않는다.** 대신
  `BattleSim.field_ready` 를 세우는데, 그것이 `BattleRenderer._draw` 의 유일한
  게이트다(아래 절).
- `_open_jungle_start()` — **`match_ctx.active` 일 때만** 연다. 단독 실행
  (BattleSim.tscn 직접 실행 / 헤드리스 검증)에는 물을 상대가 없으므로 곧장
  BATTLE 로 간다 — **여기에 사람을 기다리는 단계를 두면 헤드리스 검증이 통째로
  멈춘다.**
- `begin_battle()` — `game_phase` 가 BATTLE 이 되는 **유일한 자리**.

`auto_assign_lanes()` 와 `launch_battle()` 은 `BattleSim._ready()` 와
`_on_restart_pressed()` 두 곳에서 돈다. `_ready()` 는 `launch_battle()` 뒤에도
덱 배분 · 파일럿/메크 스킬 · 로거 배선을 그대로 이어서 한다 — 전장은 이미 다
섰고 **BATTLE 틱만 미뤄진 것**이라 그 아래 사슬은 오버레이와 무관하다.

---

## JungleStartOverlay.gd — 정글 시작 칸

### 무엇이 보이는가
전장은 이미 다 서 있다(파일럿 · 포탑 · 정글 소유 · 캠프). HUD 에서는 **지금 쓸
수 없는 것들만** 숨는다(`HudBuilder.set_pregame_chrome_visible(false)`) — 덱 /
버린 더미 뭉치, 전략 포인트 도넛 둘, 오브젝트 등장 시계 둘. **파일럿 스트립과
상단 chrome 은 남는다**.

**전장은 이 화면의 질문만 남기고 접힌다**(`BattleRenderer`):

- **놓을 수 없는 칸은 전부 딤드**된다(`_draw_jungle_pick_dim`) — 정글이 아닌 칸,
  그리고 **상대 소유 정글 칸**. 밝게 남는 칸은 `active_cells()`(정글 / 중립 칸
  중 **우리 팀 소유 또는 아직 아무도 안 잡은** 칸)이고 드롭 판정도 같은 목록을
  읽으므로 놓을 수 있는 칸과 밝은 칸이 갈릴 수 없다.
- 놓을 수 있는 칸은 옅은 초록 채움 + 초록 테두리, 마커가 올라온 칸 / 고른 칸은
  진한 채움 + **금색 두꺼운 테두리**(`_draw_jungle_start_zones`, 캠프 아웃라인 뒤).
- **전장 초상화는 아군 정글러 하나만 남는다**(`_hidden_during_jungle_pick`).
  자리 배정(`_solve_slots`)도 같은 목록을 읽으므로 숨은 사람은 슬롯을 잡지 않는다.

### 조작 — 전장의 정글러 마커를 직접 끈다
HQ 에 서 있는 **아군 정글러 마커 자체**를 집는다. 이 화면 동안 그 마커는
**말풍선 꼬리 없이** 그려지고(가리킬 타일이 아직 없다), 그 자리는 오버레이가
정한다 — `marker_pos(default)`: 끄는 중이면 손가락 밑(집은 지점과 마커 중심의
차이 `_grab_offset` 을 유지해 집는 순간 튀지 않는다), 고른 칸이 있으면 그 칸
한가운데, 아니면 렌더러가 푼 HQ 슬롯 그대로. 집기 판정은 그려진 반지름
(`pilot_marker_radius`) × `GRAB_RADIUS_MULT`(1.35).

드롭 대상은 **칸 하나**다(`_cell_under`: 마커 중심에서 `hex_size` 안의 가장 가까운
놓을 수 있는 칸). 끄는 동안 마커 밑 칸이 바뀔 때마다 경로가 다시 그려진다
(`_draw_jungle_start_path`) — **HQ 에서 그 칸까지(금색) + 도착한 뒤
`AFTER_TURNS`(6)턴의 걸음(하늘색)**. 도착에 2턴이면 8턴까지다. 턴이 끝나는 칸마다
번호 알약이 서고, 순회가 왔던 칸을 다시 지나면 한 알약에 `2·7` 로 묶인다. 마커가
앉는 칸의 번호는 칸 한가운데가 아니라 **얼굴 오른쪽 아래 배지**다
(`_draw_jungle_start_marker_badge`, 마커를 그린 뒤) — 안 그러면 도착 턴이 얼굴에
덮인다.

예측은 `path_cells()` → **`SimulationCore.predict_jungle_path`** 가 한다. 시작 칸을
정글러에게 잠깐 새기고 **진짜 `_jungle_goal_for` 를 앞으로 굴린 뒤 되돌린다** —
턴 수 · 정글러 자리 · 정글 소유 · 캠프 시계를 턴 루프와 같은 순서(턴 증가 → 이동 →
중립 점령 → 캠프 수확)로 밀므로 도착 뒤의 중립 점령 · 캠프 순회까지 실제 규칙
그대로 나온다. 타일맵 색을 바꾸는 `_set_zone_cell` 대신 표만 고치고, 두 표는 같은
Dictionary 객체에 되써서 되돌린다. 제자리에 머문 턴도 한 턴으로 센다. 결과는 칸
하나 단위로 캐시한다(`_path_cache_cell`).

**단순 예상 루트다 — 우리 정글러 혼자 걷는다고 본다.** 상대 정글러의 걸음 · 중립
선점 · 정글러끼리의 교전은 **의도적으로 계산하지 않는다**(사용자 결정). 한때 상대
정글러까지 굴리고 마주치면 `!` 로 끊었는데, 그러면 경로가 상대의 시작 방향을
드러냈다. 그래서 상대가 같은 쪽 중립을 먼저 잡거나 길에서 마주치는 판에서는 실제
걸음이 거기서부터 갈라진다. 헤드리스 실측: 상대가 반대쪽으로 간 판에서 예측 10칸
(도착 4 + 6)과 개시 후 10턴의 걸음이 일치.

**드롭은 선택일 뿐 개시가 아니다.** 놓으면 그 칸이 잡히고 마커가 그 칸에 앉으며,
손패 자리의 안내문이 "전투 시작" 버튼으로 바뀐다. 빗나가면 있던 자리로 돌아간다 —
이미 고른 칸이 있으면 그 칸으로, 아니면 HQ 로.

"전투 시작" → `start_pressed` → `GambitPhaseManager._on_jungle_start_pressed`:
`commit()` 이 고른 칸을 **`PilotData.jungle_start_cell`** 에, 그 칸이 속한 쪽
(`LEFT_CELLS` / `RIGHT_CELLS`)을 `jungle_start_pref` 에 새기고, 매니저가
`match_ctx["jungle_start_dir"]` 에도 방향을 적은 뒤 `begin_battle()`. 정글러는
**HQ 에서 출발해** 그 칸을 첫 목표로 걷는다(`SimulationCore._jungle_goal_for` 의
맨 앞 분기 — 도달하거나 그 칸이 상대 것이 되면 비운다). 개시 순간 마커는 오버레이의
덮어쓰기가 사라지며 HQ 슬롯으로 돌아간다.

입력은 전체 화면 `Control` 하나(`_root`, MOUSE_FILTER_STOP)가 `gui_input` 으로
받는다 — 누른 Control 이 마우스 포커스를 유지하므로 커서가 어디로 나가도 motion /
release 가 계속 이쪽으로 들어온다(손패 드래그와 같은 구조). 좌표 변환도 손패와
같다 — `_root.get_global_transform_with_canvas() * local` 이 곧 뷰포트 좌표이고,
`BattleSim.cell_center()` 의 전장 좌표와 같은 공간이다.

감촉: 집기 `SELECT` · 놓을 수 있는 칸에 들어설 때마다 `LIGHT`(칸에 물려 움직이는
판이라 칸마다 운다) · 칸 결정 `MEDIUM`.

예전에는 **손패 자리에 따로 세운 원형 초상화**(지름 150)를 좌 / 우 정글 **무리**
(각 7칸)로 끌어다 놓아 방향 하나만 골랐다 — 끄는 그림과 전장의 정글러가 둘로
갈려 있었고, 상대 정글까지 함께 밝았다.

### 렌더러 게이트가 페이즈에서 `field_ready` 로 바뀌었다
`BattleRenderer._draw()` 는 예전에 `game_phase == GAMBIT` 이면 통째로
건너뛰었다. 정글 시작 선택이 그 GAMBIT 안으로 들어오면서 **개시 전에도 전장이
보여야** 하게 됐으므로, 게이트가 "지금 무슨 페이즈인가"에서 "그릴 것이
있는가"(`BattleSim.field_ready`)로 바뀌었다.

### 왜 여기인가
예전에는 이 선택이 `features/match_flow/jungle_start/` 의 **별도 화면**이었다.
전장을 한 픽셀도 보여 주지 않은 채 "← LEFT / RIGHT →" 두 버튼만 세웠는데,
좌우 정글이 무엇을 끼고 있고 우리 정글러가 어디에 서 있는지가 화면에 없으면
그 선택은 동전 던지기와 다르지 않았다. 그 폴더는 삭제됐다.


## Detail moved from root CLAUDE.md

### Active Systems (moved from root CLAUDE.md)

| System | Description |
|---|---|
| Gambit Phase (개시 전) | 레인은 **역할이 고정한다**(TANK→LEFT, FIGHTER→CENTER, ASSASSIN→GUERRILLA, SUPPORT/SNIPER→RIGHT) — 예전의 인게임 배정 오버레이는 삭제됐고 그 자리는 밴픽 화면이 가져갔다. 이 단계에 남은 선택은 **정글 시작 방향** 하나다(아래 항목). `GambitPhaseManager.launch_battle()` 이 셋으로 갈라져 있다 — `prepare_field()`(파일럿 · 포탑 · 정글 소유 · 캠프를 세우고 `BattleSim.field_ready` 를 켠다) → 정글 시작 오버레이(경기로 들어온 경우) → `begin_battle()`(`game_phase = BATTLE` 이 되는 유일한 자리). |
| 정글 시작 (인게임) | **전장의 아군 정글러 마커를 직접 끌어다 시작 칸에 놓는다**(`gambit/JungleStartOverlay.gd`, `match_ctx.active` 일 때만 — 단독 실행은 기본값 LEFT 로 곧장 개시, 헤드리스 검증이 그 경로를 탄다). HUD 는 지금 못 쓰는 것만 숨고(덱 / 버린 더미 뭉치 · 도넛 둘 · 오브젝트 시계 둘), 전장은 **놓을 수 없는 칸(정글 아닌 칸 + 상대 소유 정글)이 딤드**되며 초상화는 아군 정글러 하나만 남는다. 그 정글러는 HQ 에서 **꼬리 없이** 그려지고, 집어 끄는 동안 마커 밑의 놓을 수 있는 칸이 금색으로 둘리며 **HQ → 그 칸 + 도착 뒤 6턴 경로가 턴 번호와 함께** 그려진다(`SimulationCore.predict_jungle_path` 가 진짜 목표 선택을 앞으로 굴린 단순 예상 루트 — 상대 정글러와의 충돌은 계산하지 않는다). 드롭은 선택일 뿐 개시가 아니다 — 마커가 그 칸에 앉고 손패 자리에 "전투 시작". 확정이 `PilotData.jungle_start_cell`(첫 목표) · `jungle_start_pref`(그 칸의 쪽) · `match_ctx.jungle_start_dir` 을 새기고 BATTLE 을 연다. 정글러는 HQ 에서 걸어간다. **`BattleRenderer._draw` 의 게이트는 페이즈가 아니라 `BattleSim.field_ready`** 다 — 개시 전에도 전장이 보여야 한다. 예전에는 손패 자리의 별도 원형 초상화를 좌 / 우 정글 무리로 끌어 방향만 골랐고, 그보다 전에는 `match_flow/jungle_start/` 의 별도 화면이었다. |
