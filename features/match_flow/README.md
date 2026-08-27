# Feature: Match Flow

## Purpose
Pre-battle pipeline that runs **before** `BattleSim.tscn`:

```
LOAD → PREP → BAN_PICK → LAUNCH (change_scene → BattleSim)
```

**열거값 둘이 자리만 지킨다 — `ASSIGN` 과 `JUNGLE_START`.**

- **메크 배정**이 밴픽 화면 안으로 들어갔고(아래 BAN_PICK 절),
  `assign/AssignController.gd` 는 삭제됐다.
- **정글 시작 방향**은 **BattleSim 안으로 들어갔다**
  (`features/battle_sim/gambit/JungleStartOverlay.gd`). 좌우 중 어느 정글로
  갈지는 정글 소유 · 캠프 · 우리 정글러의 자리를 보고 정하는 선택인데, 예전의
  `jungle_start/JungleStartController.gd` 는 전장을 한 픽셀도 보여 주지 않은 채
  "← LEFT / RIGHT →" 두 버튼만 세웠다 — 그 화면에서 고르는 것은 동전 던지기와
  다르지 않았다. 그 폴더는 삭제됐다.

두 열거값은 세이브 호환(`match_resume.phase`)을 위해 남는다.

PREP is the pre-match dashboard — both rosters' stats laid out side by
side so the player can review who they're up against before committing
to BAN_PICK. Pressing "경기 시작" advances to BAN_PICK and triggers the
pre-ban-pick autosave.

Entry point: `scenes/MatchFlow.tscn`. Resume saves skip PREP and jump
directly to BAN_PICK (or LAUNCH for post-gambit saves) since the player
already committed when the save was written. On `LAUNCH`,
`GameManager.match_ctx` is populated and the scene transitions to `BattleSim.tscn`.

---

## Module Architecture

`MatchFlow.gd` is a thin orchestrator (`class_name MatchFlow extends Node2D`).
Three child controllers each build their own UI on `enter()` and emit
`phase_finished(result)` when done:

| Node | Script | Responsibility |
|---|---|---|
| MatchPrepController | `match_prep/MatchPrepController.gd` | Pre-match dashboard — both rosters with stats. "경기 시작" → BAN_PICK. |
| BanPickController | `ban_pick/BanPickController.gd` | LoL-international ban/pick (4 bans + 10 picks) with random AI, **그리고 그 자리에서 이어지는 메크 배정**. 아래 두 절 참조 |

배정 단계가 여는 상세 팝업 둘은 컨트롤러의 형제 파일이다:

| File | Purpose |
|---|---|
| `ban_pick/MechDetailPanel.gd` | `class_name MechDetailPanel extends CanvasLayer` — 메크 상세(좌 전신 아트 / 우 스탯 칩 3 → 패시브 → 메크 카드 격자 / 하 닫기) |
| `season/draft/DraftDetailPanel.gd` | 파일럿 상세 — **드래프트 화면과 같은 팝업을 그대로 쓴다**(`open(p: PlayerData)` 하나면 열린다) |

`BanPickController.enter()` 는 다른 둘과 달리 **로스터와 팀명까지 받는다** —
밴픽 화면이 위/아래에 양 팀 파일럿 초상화를 세우고, 14수가 끝나면 그 로스터에
배정을 직접 새기기 때문이다.

---

## BAN_PICK 화면

세로 한 장을 **위 / 가운데 / 아래** 세 덩이로 나눈다.

```
위     밴 칩 2개 → 메크 칸 5개 → 파일럿 초상화 5인      (상대 팀)
가운데 픽창 = 역할군 필터 탭 + 메크 격자 (정사각 칸, 4.5줄 스크롤)
아래   파일럿 초상화 5인 → 메크 칸 5개 → 밴 칩 2개      (아군, 거울)
```

- **메크 칸은 파일럿 칸보다 세로로 두 배 길다**(`MECH_H_RATIO`) — 파일럿은
  눈높이 밴드(2.4:1)라 납작하고 메크는 정사각 초상화라, 같은 폭에서 메크가 두 배
  높이를 가져야 두 그림이 각자 제 비율로 앉는다.
- **거울 배치**라 안쪽(전장 쪽)에 언제나 파일럿 얼굴이 오고 바깥쪽에 메크가 온다.
- **픽창에만 짙은 배경판**(`GRID_BG_COLOR`)이 깔리고 나머지 화면은 어두운 회색
  (`PAGE_BG_COLOR`)이다 — 판 하나가 "여기가 고르는 곳"과 "여기는 양 팀 상황"을
  색 한 단계로 가른다.
- **격자 칸은 정사각 초상화 + 아래 이름 한 줄이 전부다.** 왼쪽 위에 역할군 배지
  (역할 색으로 채운 둥근 사각형 + 하얀 두 글자 `Tk/As/Fi/Sn/Su`)가 붙는다. 예전에는
  칸마다 `HP · ATK · 존재감` 과 패시브 이름이 두 줄 더 붙었는데, 스물한 대를 훑는
  화면에서 칸마다 다섯 줄을 읽게 하면 정작 **그림으로 알아보는** 일이 안 된다 —
  숫자와 패시브 설명은 한 번 눌러 여는 하단 시트가 통째로 들고 있다.
- 초상화는 `MechImages.portrait_for()` 가 주는 **미리 구운 256² 정사각 컷**이다.
  예전의 "전신 아트를 런타임에 격자 크기로 줄여 굽기"(`_bake_thumbs` / `THUMB_PX`)는
  삭제됐다.
- **다섯 칸의 순서는 `GameEnums.ROLE_DISPLAY_ORDER`**(탑 · 정글 · 미드 · 원딜 ·
  서폿)다. 그래서 파일럿 초상화에 이름표도 역할 태그도 붙지 않는다 — 자리가 곧
  역할이고, 인게임 스트립도 같은 순서로 선다.
- **진행 상태 줄은 칩 14개뿐이다.** 예전의 "BLUE 픽 — 내 차례 (3 / 14)" 한 줄은
  삭제됐다 — 누구 차례인지는 밝아진 칩이, 무엇을 하는 차례인지는 시트의 확정
  버튼("밴 확정" / "픽 확정" / "상대 차례")이 말한다.

조작은 그대로 **1탭 = 선택(하단 시트 열기), 같은 메크 2탭 = 확정**이고, 시트는
내 차례가 아닐 때도 열린다(확정 버튼만 잠긴다).

---

## 배정 (밴픽 화면 안에서)

14수가 끝나면 **화면을 갈아타지 않는다** — `_enter_assign_mode()` 가 픽창(탭 +
격자 + 배경판)을 걷어 내고 그 자리에 **"게임 시작" 버튼 하나**를 세운 뒤, 아군
블록을 다시 세운다:

```
파일럿 상체 일러스트 5인  (`PilotImages.bust_for` — 드래프트 화면의 선택 칸과
                          같은 크롭 · 같은 비율)
메크 칸 5개               (끌 수 있음, 처음엔 픽 순서)
"드래그 드롭으로 메크-파일럿 지정 변경"   (메크 줄 오른쪽 아래, 17pt)
밴 칩 2개
```

**파일럿이 위, 메크가 아래다.** 배정은 "이 사람이 무엇을 타는가"를 정하는
일이고, 그 문장의 주어가 위에 와야 한 칸을 세로로 훑는 것이 곧 한 문장이 된다.
예전에는 메크가 위였다 — 끄는 손가락이 그 밑의 "어느 파일럿 자리인가"를 가리지
않게 하려는 배치였는데, 그러면 목적어가 주어보다 먼저 와서 다섯 칸이 무엇을
정하는 화면인지가 뒤집혀 읽혔다. 초상화가 상체 일러스트로 커진 지금은 손가락이
덮을 수 있는 넓이보다 칸이 훨씬 커서 그 걱정 자체가 없다.

초상화 높이는 폭에서 유도한다 — `portrait_w / PilotImages.BUST_ASPECT`
(`_lay["assign_portrait_h"]`). 예전의 정사각 `faces` 크롭은 삭제됐다. 어느
크롭을 쓸지는 **칸 비율이 정한다**(`_build_pilot_portrait`): 가로로 납작하면
눈높이 밴드(밴픽 단계), 세로로 길면 상체 일러스트(배정 단계).

메크 칸을 **끌어다 다른 칸에 놓으면 둘이 맞바뀐다**(`_swap_assign`). 드롭했을
때만 바뀌고, `DRAG_THRESHOLD_PX`(8px)를 못 넘긴 것은 **탭**이라 그 칸의 메크
상세를 연다. 끄는 동안 원래 칸은 자국으로 남고(α 0.35) 커서 밑의 칸은 테두리가
금색으로 굵어진다. 입력은 칸마다 붙은 `gui_input` 하나가 받는다 — 누른 컨트롤이
마우스 포커스를 유지하므로 커서가 칸 밖으로 나가도 motion / release 가 계속
들어온다.

상대 팀은 예전 `AssignController` 와 똑같이 **자동 배정(섞기)** 이고, 블록도
다시 세우지 않는다 — 밴픽 내내 서 있던 그림이 그대로 남아야 "저쪽이 무엇을
골랐나"를 두 번 읽지 않는다.

### 배정 단계의 상세 팝업 (양 팀 전부 눌린다)
- **파일럿 초상화** → `DraftDetailPanel`(드래프트 화면과 같은 팝업)
- **메크 초상화** → `MechDetailPanel`

배정은 스탯을 보고 하는 일인데 그 스탯을 볼 자리가 없으면 픽 순서 그대로 두는
것 말고 할 수 있는 것이 없다. **인게임 상세 패널과는 다르다** — 인게임 탭
(체력 · 공격력 · 지속 효과)이 없고, 파일럿과 메크를 한 화면에 겹치지도 않는다:
아직 경기가 시작되지 않아 인게임 상태라는 것이 존재하지 않고, 지금 묻는 질문은
"이 사람" 또는 "이 기체" 한 쪽이다. 두 팝업은 동시에 뜨지 않는다
(`_close_detail_panels`) — 딤이 두 겹 쌓이면 뒤엣것이 앞엣것을 어둡게 덮는다.

탭 배선은 칸마다 얹은 **투명 Button** 이고 배정에 들어갈 때만 켜진다
(`_set_block_tappable`). **아군 메크 칸만은 예외**로 그 버튼을 켜지 않는다 —
그쪽 탭은 드래그 배선(`_on_slot_input`)이 함께 받으므로, 버튼을 켜면 그 버튼이
press 를 가져가 드래그가 영영 시작되지 않는다.

"게임 시작"이 `_finish()` 를 부르고, 거기서 자리(seat) → 역할 변환
(`ROLE_DISPLAY_ORDER` 한 겹)을 거쳐 `PlayerData.assigned_mech` 를 채운 뒤
`phase_finished` 로 로스터를 그대로 넘긴다. **로스터 배열 자체는 역할 0..4 순서를
지킨다** — `MatchFlow._roster_mech_ids` 의 재개 스냅샷이 그 순서를 전제한다.
팝업 둘도 여기서 닫는다 — `CanvasLayer` 라 `_panel` 을 지워도 따라 사라지지
않아, 열어 둔 채 넘어가면 딤이 BattleSim 위에 그대로 남는다.

Each controller accesses the orchestrator via:
```gdscript
@onready var _mf: MatchFlow = get_parent() as MatchFlow
```
UI panels parent to `_mf.canvas` (the CanvasLayer in MatchFlow.tscn).

---

## MatchFlow.gd

State machine with phases from `GameEnums.MatchPhase`. Loads `players` and `mechs`
tables on entry via `GameManager.load_match_data()`. On the final `LAUNCH` phase
populates:

```gdscript
GameManager.match_ctx = {
	"active": true,
	"player_roster": Array[PlayerData],   # 5 players sorted by role 0..4, assigned_mech set
	"enemy_roster":  Array[PlayerData],
	"jungle_start_dir": int (LEFT|RIGHT),
	"player_side":   int (BLUE|RED),
	"banned_mech_ids": Array[int],
	"all_mechs":      Array[MechData],
}
```

`BattleSim.gd` reads `match_ctx.active` to decide whether to inject mech stats
into pilots; otherwise it falls back to `ROLE_STATS` defaults.

### 진영 (`player_side`) — 지금은 항상 BLUE
`player_side` 는 밴픽 순서와 인게임 선을 **동시에** 정하는 한 값이다:

| 진영 | 밴픽 | 인게임 |
|---|---|---|
| RED  | 선밴 / 선픽 | — |
| BLUE | 후밴 / 후픽 | 전략 포인트 `BLUE_COST_HEAD_START` 선점 + 같은 점수일 때 선턴 |

`_ready()` 의 fresh-entry 경로는 예전에 매 경기 이 값을 랜덤으로 뽑았지만,
지금은 **플레이어를 항상 `DraftSide.BLUE` 로 고정**한다 — 두 축(밴픽 이득 /
인게임 이득)이 균형을 갖출 때까지 한쪽으로 못 박아 둔 것이다. 되살릴 때는 그 한
줄만 되돌리면 되고, 아래 흐름과 `BattleSim.seed_side_costs()` 는 이미
`match_ctx.player_side` 를 그대로 읽어 진영을 판정한다. 재개(resume) 경로는
저장된 `player_side` 를 그대로 복원하므로 이 고정과 무관하다.

---

## Data flow into BattleSim
- `PlayerData.assigned_mech.hp/atk` → `PilotData` stats via
  `SimulationCore._stats_for()`
- `match_ctx.jungle_start_dir` → `PilotData.jungle_start_pref` (assassin only),
  consumed by `SimulationCore._nearest_uncaptured_neutral()` for zone preference

---

## Files

| File | Purpose |
|---|---|
| `MatchFlow.gd` | State machine orchestrator |
| `match_prep/MatchPrepController.gd` | Pre-match dashboard |
| `ban_pick/BanPickController.gd` | Ban/Pick + 메크 배정 — 양 팀 초상화 + 메크 격자 + 하단 상세 시트 + 드래그 배정 |
| `ban_pick/MechDetailPanel.gd` | 배정 단계의 메크 상세 팝업 |

---

## Save hooks
`MatchFlow.gd` owns two of the four campaign autosave triggers (the other
two live in `SeasonHub`):

- **Pre-ban-pick** — fires in `_on_prep_finished()` when the player
  presses "경기 시작" on the PREP dashboard. Writes
  `season_state.match_resume = {phase: BAN_PICK, player_side, ...empty
  arrays}`. Skipped when running MatchFlow standalone (no `pending_match`).
- **Post-ban-pick** — fires in `_on_ban_pick_finished()` right after 배정
  완료, before `_launch_battle` scene-changes to BattleSim. 예전에는 정글
  방향까지 여기 들어와 이 저장이 `_on_jungle_finished()` 에 있었지만, 그 선택이
  BattleSim 으로 옮겨 가면서 저장 시점이 한 단계 앞으로 당겨졌다 — 재개는
  어차피 전투를 처음부터 다시 돌리므로 정글 방향도 그때 다시 묻는다
  (스냅샷의 `jungle_start_dir` 은 상대 정글러와 폴백을 위한 기본값 LEFT 다).
  Writes the full match snapshot:
  `{phase: LAUNCH, player_side, banned_mech_ids, player_picked_mech_ids,
  enemy_picked_mech_ids, player_assigned_mech_ids, enemy_assigned_mech_ids,
  jungle_start_dir}`. The mech-id arrays are 5-entry, role-sorted (0..4) so
  resume can re-attach `assigned_mech` to each PlayerData.

### Resume entry
`_ready()` reads `season_state.match_resume`. Non-null → skip PREP (the
player already committed when the save was written) and:
- `phase == BAN_PICK` → restore `player_side` and `_enter_phase(BAN_PICK)`.
- `phase == LAUNCH` → `_resume_at_launch(resume)` rebuilds `match_ctx`
  from the resume payload (rosters via `_team_roster()`, mechs via
  `_find_mech()`) and scene-changes to BattleSim immediately. No UI
  controllers run — 정글 시작 화면은 BattleSim 이 열므로 재개해도 그 한
  물음은 다시 나온다.

`match_resume` is cleared in-memory on consumption; on disk it's only
overwritten by the next post-ban-pick or post-week save. Closing mid-battle
keeps the disk save at the post-ban-pick snapshot, so the resume path
replays the battle from scratch with the same locked-in picks.

---

## 화면 대응 (세이프 에어리어)

두 컨트롤러(PREP / BAN_PICK)는 모두 `_mf.canvas` 아래에
전체 화면 `Panel` 하나를 세우고 거기에 절대 좌표로 그린다. `_panel` 을 만든
직후 두 줄이 따라온다.

```gdscript
_mf.canvas.add_child(_panel)
ScreenMetrics.indent_to_safe_top(_panel)          # 판째 노치 밑으로
ScreenMetrics.backfill_top(_panel, <판 배경색>)   # 비워진 위쪽 띠를 메운다
```

배경이 **판 자신의 StyleBox** 라 판을 위로 늘릴 수 없다(늘리면 안쪽 좌표계가
같이 움직여 내용이 도로 노치 밑으로 들어간다). 그래서 시즌 뷰의
`extend_background()` 대신 띠 한 장을 판의 **첫 자식**으로 까는
`backfill_top()` 을 쓴다.

내려간 판 안에서 하단 버튼은 `ScreenMetrics.safe_h()` 기준이다 —
`MatchPrepController` 는 `safe_h() - 70 - h`. `BanPickController` 는 버튼이 아니라
**블록 전체**를 `safe_h()` 에서 역산한다(`_lay["bot_block_y"]` /
`_lay["assign_block_y"]`), 그리고 픽창 높이는 위아래 블록이 먹고 남은 띠에서
나온다 — 그래서 어느 화면에서나 격자 칸은 정사각으로 남고 보이는 줄 수만 바뀐다.

자세한 내용: **`docs/mobile_safe_area.md`**
