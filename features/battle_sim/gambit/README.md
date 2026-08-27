# Gambit Phase Module

개시 전 단계(`BattlePhase.GAMBIT`)의 주인. 파일은 둘이다.

| File | Role |
|---|---|
| `GambitPhaseManager.gd`  | `extends Node` — BattleSim 의 씬 자식. 레인 고정 배정 + 전장 세우기 + 개시 |
| `JungleStartOverlay.gd`  | `class_name JungleStartOverlay extends Node` — **정글 시작 방향**을 전장 위에서 고르는 오버레이. lazy-add |

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

## JungleStartOverlay.gd — 정글 시작 방향

### 무엇이 보이는가
전장은 이미 다 서 있다(파일럿 · 포탑 · 정글 소유 · 캠프). HUD 에서는 **지금 쓸
수 없는 것들만** 숨는다(`HudBuilder.set_pregame_chrome_visible(false)`):

- 손패 행 양옆의 **덱 / 버린 더미 뭉치**와 그 히트 버튼
- **전략 포인트 도넛** 둘
- 상단 패널의 **오브젝트 등장 시계** 둘

셋 다 아직 존재하지 않는 것을 0 으로 보여 주는 자리다. **파일럿 스트립과 상단
chrome 은 남는다** — 개시 직전에 양 팀 로스터를 다시 확인하는 것은 이 화면이
하는 일의 일부다.

**전장은 이 화면의 질문만 남기고 접힌다**(`BattleRenderer`):

- **정글이 아닌 칸은 전부 딤드**된다(`_draw_jungle_pick_dim`). 밝게 남는 칸의
  정의를 드롭 대상(`cells_for`)에서 그대로 가져오므로 **놓을 수 있는 칸과 밝은
  칸이 같은 목록**에서 나온다. 캠프 아웃라인 **뒤**, 무리 강조 **앞**에 그린다 —
  그 둘은 이 선택의 근거이자 안내라 딤 위에 남아야 한다.
- **전장 초상화는 아군 정글러 하나만 남는다**(`_hidden_during_jungle_pick`,
  `jungler()` 가 그 한 명을 답한다). 나머지 아홉은 아직 각자 HQ 에 몰려 서 있어
  두 덩어리로 뭉친 얼굴이 정글 소유 · 캠프 · 딤을 가릴 뿐이다. 자리 배정
  (`_solve_slots`)도 같은 목록을 읽으므로 숨은 사람은 슬롯을 잡지 않는다 —
  안 보이는 마커 때문에 정글러가 바깥 링으로 밀리면 안 된다.

비워진 **손패 자리에 아군 정글러의 원형 초상화**(`PilotImages.circle_for`,
지름 150)가 놓인다. 전장 마커와 같은 컷이라 "지금 옮기려는 것이 저 사람"이
그림 하나로 읽힌다. 뒤에 불투명 원을 까는 것도 전장 마커와 같은 이유다 —
`circle` 컷은 안쪽에도 알파 구멍이 있어 그냥 그리면 타일이 얼굴을 뚫고 비친다.

안내문("정글러를 끌어다 시작할 정글에 놓는다")과 확정 버튼("전투 시작")은
**초상화 아래 같은 자리**를 나눠 쓴다 — 고르기 전에는 안내문, 고른 뒤에는
버튼. 위에 두면 안 된다: 우리 팀 HQ 는 격자의 맨 아래 칸이고 그 칸의 초상화
무리는 타일 **밑**에 앉으므로, 전장 픽셀 아래끝(1351)보다 더 내려와 손패 행
윗선까지 밀고 들어온다(실측).

### 드롭 대상은 칸이 아니라 무리
`LEFT_CELLS` / `RIGHT_CELLS` 각 **7칸**(팀0 정글 3 + 팀1 정글 3 + 그 사이의
중립 1)이 한 덩어리다. 정글러가 어느 칸부터 도는지는
`SimulationCore._nearest_uncaptured_neutral` 이 정하는 일이고, 여기서 정하는
것은 "어느 쪽 정글에서 시작하는가" 하나다. 판정(`_dir_under`)은 무리의 어느
칸 중심에서든 `hex_size` 안이면 그 무리다 — 칸 하나를 정확히 겨누게 하는
화면이 아니다.

강조는 `BattleRenderer._draw_jungle_start_zones()` 가 그린다(오버레이가 아니라
렌더러인 것은 전장 좌표계 위의 그림이기 때문). 평소 옅은 초록 채움 + 초록
테두리, 커서가 올라왔거나 이미 고른 쪽은 진한 채움 + **금색 두꺼운 테두리**.
캠프 아웃라인 뒤에 그리므로 그 밑의 소유 색과 캠프 테두리가 가려지지 않는다 —
그 둘이 이 선택의 근거다.

### 조작
**드롭은 선택일 뿐 개시가 아니다.** 놓으면 그 방향이 잡히고 초상화가 그 정글
한가운데(`_zone_centre`)에 앉으며 "전투 시작" 버튼이 뜬다. 빗나가면 초상화가
있던 자리로 돌아간다 — 이미 고른 것이 있으면 그 정글로, 아니면 손패 자리로.
드롭 하나로 곧장 개시하면 잘못 놓은 손가락이 경기를 시작해 버린다.

"전투 시작" → `start_pressed` → `GambitPhaseManager._on_jungle_start_pressed`:
`commit()` 이 방향을 **아군 정글러의 `PilotData.jungle_start_pref` 에 새기고**
매니저가 `match_ctx["jungle_start_dir"]` 에도 적은 뒤 `begin_battle()`.

입력은 전체 화면 `Control` 하나(`_root`, MOUSE_FILTER_STOP)가 `gui_input` 으로
받는다 — 잡는 것은 초상화 하나뿐이지만 놓는 자리는 전장 어디든이라 릴리스를
끝까지 받아야 한다. 누른 Control 이 마우스 포커스를 유지하므로 커서가 전장으로
나가도 motion / release 가 계속 이쪽으로 들어온다(손패 드래그와 같은 구조).
좌표 변환도 손패와 같다 — `_root.get_global_transform_with_canvas() * local` 이
곧 뷰포트 좌표이고, `BattleSim.cell_center()` 가 돌려주는 전장 좌표와 같은
공간에 산다(BattleSim / BattleRenderer 가 원점의 Node2D 이고 카메라가 없다).

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
