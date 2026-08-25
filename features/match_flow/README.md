# Feature: Match Flow

## Purpose
Pre-battle pipeline that runs **before** `BattleSim.tscn`:

```
LOAD → PREP → BAN_PICK → ASSIGN → JUNGLE_START → LAUNCH (change_scene → BattleSim)
```

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
| BanPickController | `ban_pick/BanPickController.gd` | LoL-international ban/pick (4 bans + 10 picks) with random AI |
| AssignController | `assign/AssignController.gd` | Manual mech↔player slot assignment for the player team (enemy auto-shuffled) |
| JungleStartController | `jungle_start/JungleStartController.gd` | Choose Assassin's jungle start direction (LEFT or RIGHT) |

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
| `ban_pick/BanPickController.gd` | Ban/Pick phase |
| `assign/AssignController.gd` | Mech-to-player assignment phase |
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

네 컨트롤러(PREP / BAN_PICK / ASSIGN / JUNGLE_START)는 모두 `_mf.canvas` 아래에
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
`MatchPrepController` 는 `safe_h() - 70 - h`, `AssignController` 는
`safe_h() - 150 - h`(상태 라벨은 그 60px 위).

자세한 내용: **`docs/mobile_safe_area.md`**
