# Feature: Match Flow

## Purpose
Pre-battle pipeline that runs **before** `BattleSim.tscn`:

```
LOAD → PREP → BAN_PICK → JUNGLE_START → LAUNCH (change_scene → BattleSim)
```

**`MatchPhase.ASSIGN` 은 더 이상 지나지 않는다.** 메크 배정이 밴픽 화면 안으로
들어갔고(아래 BAN_PICK 절), `assign/AssignController.gd` 는 삭제됐다. 열거값은
세이브 호환을 위해 자리만 지킨다.

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
| JungleStartController | `jungle_start/JungleStartController.gd` | Choose Assassin's jungle start direction (LEFT or RIGHT) |

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
격자 + 배경판)을 걷어 내고 그 자리에 안내와 "배정 완료" 버튼을 세운 뒤, 아군
블록을 다시 세운다:

```
메크 칸 (끌 수 있음, 처음엔 픽 순서)
파일럿 초상화 (정사각으로 확장 — eye 밴드가 아니라 faces 크롭)
밴 칩
```

메크 칸을 **끌어다 다른 칸에 놓으면 둘이 맞바뀐다**(`_swap_assign`). 드롭했을
때만 바뀌고, `DRAG_THRESHOLD_PX`(8px)를 못 넘긴 것은 탭으로 친다. 끄는 동안
원래 칸은 자국으로 남고(α 0.35) 커서 밑의 칸은 테두리가 금색으로 굵어진다.
입력은 칸마다 붙은 `gui_input` 하나가 받는다 — 누른 컨트롤이 마우스 포커스를
유지하므로 커서가 칸 밖으로 나가도 motion / release 가 계속 들어온다.

정사각 확장에 `faces` 크롭을 쓰는 것이 요점이다 — 눈높이 밴드(`eye`)를 정사각
칸에 넣으면 얼굴이 위아래로 잘려 이목구비가 통째로 사라진다.

상대 팀은 예전 `AssignController` 와 똑같이 **자동 배정(섞기)** 이다.

"배정 완료"가 `_finish()` 를 부르고, 거기서 자리(seat) → 역할 변환
(`ROLE_DISPLAY_ORDER` 한 겹)을 거쳐 `PlayerData.assigned_mech` 를 채운 뒤
`phase_finished` 로 로스터를 그대로 넘긴다. **로스터 배열 자체는 역할 0..4 순서를
지킨다** — `MatchFlow._roster_mech_ids` 의 재개 스냅샷이 그 순서를 전제한다.

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
| `jungle_start/JungleStartController.gd` | Jungle direction phase |

---

## Save hooks
`MatchFlow.gd` owns two of the four campaign autosave triggers (the other
two live in `SeasonHub`):

- **Pre-ban-pick** — fires in `_on_prep_finished()` when the player
  presses "경기 시작" on the PREP dashboard. Writes
  `season_state.match_resume = {phase: BAN_PICK, player_side, ...empty
  arrays}`. Skipped when running MatchFlow standalone (no `pending_match`).
- **Post-gambit** — fires in `_on_jungle_finished()` before `_launch_battle`
  scene-changes to BattleSim. Writes the full match snapshot:
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
  controllers run.

`match_resume` is cleared in-memory on consumption; on disk it's only
overwritten by the next post-gambit or post-week save. Closing mid-battle
keeps the disk save at the post-gambit snapshot, so the resume path
replays the battle from scratch with the same locked-in picks.

---

## 화면 대응 (세이프 에어리어)

세 컨트롤러(PREP / BAN_PICK / JUNGLE_START)는 모두 `_mf.canvas` 아래에
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
