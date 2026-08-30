# Save / Load

Title-screen save-slot system. Three slots persisted as JSON under
`user://saves/slot{0,1,2}.save`. Auto-save fires at four discrete points
across the campaign / match-day lifecycle (no manual save UI):

1. **Post-draft** — first DRAFT → HUB transition (SeasonHub).
2. **Pre-ban-pick** — MatchFlow `_ready()`, right before BAN_PICK starts.
3. **Post-ban-pick** — `_on_ban_pick_finished` in MatchFlow, right after 메크
   배정이 끝나고 BattleSim 이 뜨기 직전. 예전에는 그 뒤의 JUNGLE_START 가
   끝나는 자리였는데(`_on_jungle_finished`), 정글 시작 선택이 BattleSim 안으로
   옮겨 가며 한 단계 앞으로 당겨졌다.
4. **Post-match** — SeasonHub `_ready()` after `_consume_pending_match_result`
   applies the result and clears `match_resume`.

No save fires while BattleSim is running — closing mid-battle resumes from
the post-ban-pick snapshot and replays the battle (정글 시작 화면도 다시 뜬다).

## Entry point
`scenes/TitleScreen.tscn` — set as `run/main_scene` in `project.godot`.
The player picks a slot, then the scene changes to `Season.tscn`.

## Files
| File | Class | Purpose |
|---|---|---|
| `SaveSystem.gd`   | `class_name SaveSystem extends RefCounted` | Static helpers for serialize / deserialize / list / save / load / delete |
| `TitleScreen.gd`  | `extends Control` (no class_name — only used via scene) | Project entry. Builds the 3-slot UI. Routes button presses to GameManager + scene change. |
| `SlotCard.gd`     | `class_name SlotCard extends Control` | One slot card. Builds its own UI; parent feeds meta + callbacks. |

## Slot file schema (v1)
```json
{
  "version": 1,
  "meta": {
    "phase": 0, "year": 1, "month": 12, "day": 1, "weekday": 0,
    "team_name": "Team 0",
    "trophies": 0,
    "rank": 3, "wins": 5, "losses": 2,
    "saved_at": "2026-05-05 23:14",
    "match_in_progress": false
  },
  "season_state": { ...full GameManager.season_state, JSON-encoded... }
}
```

The `meta` block is denormalized info for the title-screen card, computed
once at save time. It lets the title screen render slot cards without
loading the full season_state (and without instantiating LeagueManager).
`match_in_progress` is true when the slot was saved between BAN_PICK start
and BattleSim launch — SlotCard surfaces a "경기 진행 중" tag, and TitleScreen
routes "이어하기" to MatchFlow.tscn instead of Season.tscn.

## Serialization notes
`season_state` is a Dictionary of mostly-primitive values plus a few
Resource-typed entries:
- `all_pilots` / `intl_pilots` are `Array[PlayerData]`. Persisted as plain
  Dicts via `_pilots_to_array` / `_array_to_pilots`. `assigned_mech` is
  runtime-only (set in match flow) and is rebuilt on resume from
  `match_resume.{player,enemy}_assigned_mech_ids`, so it isn't persisted on
  the PlayerData rows themselves.
- `team_rosters`, `league_standings`, `phase_results` are all
  `Dictionary[int, X]`. JSON.stringify converts int keys to strings;
  `_int_keyed_dict_in` rebuilds the int keys on load.
- `training_board` is an `Array` of `{tile: String, x: int, y: int}` (주간 훈련판).
  JSON returns every number as a float, so `_board_in` casts `x`/`y` back to
  int on load — 그러지 않으면 `{x: 0.0}` 이 되어 그 뒤 `Vector2i(...)` 로 감싸는
  자리마다 형변환이 한 겹씩 더 붙고, 한 자리만 빠뜨려도 칸 비교가 어긋난다.
  (예전의 `training_schedule` `Dictionary[int, Array[7]]` 은 삭제됐다.)
- **주 진행 상태 셋** — 한 주가 월~일 하루씩 흘러가면서 생겼다
  (`features/season/week/README.md`).
  - `week_day` — 지금 보고 있는 요일 0..6. **-1 은 주가 아직 안 열렸다는 뜻**이고,
    그 값이 순위표의 "확인"이 주로 돌아갈지 허브로 돌아갈지를 가른다.
  - `week_day_log` — `day(int) → Array[줄]`, 요일별 훈련 결과 기록. **정수 키**라
    `_int_keyed_dict_in` 을 지난다 — 안 지나면 `log[3]` 이 영원히 빈 배열을 돌려줘
    같은 요일 훈련이 두 번 먹는다.
  - `training_exp_carry` — `seat(int) → {stat: 남은 EXP}` 나머지 통장. 바깥 키도
    안쪽 값도 JSON 을 지나면 문자열 / 실수가 되므로 `_exp_carry_in` 이 둘 다 int 로
    되돌린다 — 그러지 않으면 `total / EXP_PER_POINT` 가 정수 나눗셈이 아니게 돼
    나머지가 조용히 사라진다.
- `pending_match` round-trips as-is. Non-null between match-day dispatch
  and `_consume_pending_match_result` (always paired with `match_resume`
  except briefly during post-match save where both are null).
- `current_tournament` rounds-trips as a plain dict.
- `match_resume` is the mid-match snapshot. Non-null between the pre-ban-pick
  save and the post-match save. Shape:
  ```
  { phase: int (MatchPhase.BAN_PICK or LAUNCH),
    player_side: int,
    banned_mech_ids, player_picked_mech_ids, enemy_picked_mech_ids: Array[int],
    player_assigned_mech_ids, enemy_assigned_mech_ids: Array[int] (5, role-sorted),
    jungle_start_dir: int }
  ```
  At BAN_PICK only `phase` + `player_side` are meaningful; the assignment
  fields are filled in at the post-ban-pick save. `jungle_start_dir` 은 이제
  **기본값(LEFT)만 적힌다** — 그 선택은 BattleSim 이 개시 직전에 묻고, 재개는
  어차피 전투를 처음부터 다시 돌린다.

## Auto-save trigger points
Four trigger points across two scripts:

| # | When | Where | match_resume |
|---|---|---|---|
| 1 | DRAFT → HUB | `SeasonHub.goto()` | null (cleared) |
| 2 | Pre-ban-pick (MatchFlow entry, before BAN_PICK starts) | `MatchFlow._ready()` | `{phase: BAN_PICK, ...}` |
| 3 | Post-ban-pick (after 메크 배정 완료, before BattleSim) | `MatchFlow._on_ban_pick_finished()` | `{phase: LAUNCH, ...}` |
| 4 | Post-match (return from BattleSim, result applied) | `SeasonHub._ready()` | null (cleared by `_consume_pending_match_result`) |

`active_save_slot` is set on GameManager by TitleScreen. If a session enters
Season.tscn / MatchFlow.tscn directly (no slot chosen, e.g. running the
scene from the editor) `active_save_slot == -1` and `SaveSystem.save_slot(-1)`
is a no-op.

## Mid-match resume
Closing the game between save #2 (pre-ban-pick) and save #4 (post-match)
leaves `match_resume` non-null on disk. On `이어하기`:

- TitleScreen branches on `season_state.match_resume`. Non-null →
  `MatchFlow.tscn`. Null → `Season.tscn`.
- `MatchFlow._ready()` reads `season_state.match_resume`, clears it
  in-memory, and skips ahead:
  - `phase == BAN_PICK`: restore `player_side`, fall into the normal
    entry path. The pre-ban-pick save then re-fires (idempotent).
  - `phase == LAUNCH`: rebuild `match_ctx` (rosters, assigned mechs,
    bans, jungle dir) from the resume payload, scene-change directly to
    BattleSim. No phase UI runs.
- The on-disk `match_resume` is only overwritten by save #3 (post-ban-pick)
  or save #4 (post-match). Closing mid-battle leaves the disk save at #3,
  so the next resume drops back into BattleSim with the same locked-in
  picks.

## New-game vs continue flow
- **New game on empty slot**: `TitleScreen` calls `gm.reset_season_state()`,
  sets `active_save_slot = idx`, scene-changes to Season.tscn. SeasonHub
  sees `season_state["active"] == false`, calls `init_season()`, shows DRAFT.
  First save fires at DRAFT → HUB transition.
- **Continue on filled slot**: `SaveSystem.load_slot(idx)` overwrites
  `gm.season_state` from disk (active=true), `active_save_slot = idx`,
  scene-changes to Season.tscn. SeasonHub sees active=true, skips
  `init_season()`, routes straight to HUB.
- **Delete**: requires double-tap on the SlotCard (first tap arms, second
  tap deletes). No undo.
- **New game on filled slot**: not allowed directly — player must delete
  first. Keeps the destructive path explicit.

---

## 화면 대응 (세이프 에어리어)

`TitleScreen._build()` 이 `ScreenMetrics.indent_to_safe_top(self)` 로 화면째
안전 영역 위끝까지 내리고, 배경 `ColorRect` 만 `extend_background(bg)` 로 도로
화면 끝까지 늘린다(노치 자리는 쓰지 않을 곳이지 비워 둘 곳이 아니다).

하단의 안내 라벨은 `ScreenMetrics.safe_h() - 100` 에 매단다.

**여기서 실제로 났던 버그**: 제목 라벨만 `top_y()` 만큼 내렸더니 본문(슬롯
카드)은 제자리에 남아 제목이 카드 밑으로 들어갔다. 여백은 요소마다가 아니라
화면째 준다.

자세한 내용: **`docs/mobile_safe_area.md`**
