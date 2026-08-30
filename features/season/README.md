# Season (Outgame) Feature

The campaign / out-of-match metagame, restructured around weekly progression.
Player picks a 5-pilot team from a 40-pilot pool, then plays through six
events from December → next year:

```
PRESEASON → PRESEASON_INTL → MIDSEASON → MIDSEASON_INTL → REGULAR → REGULAR_INTL
```

Win the final REGULAR_INTL = ending. Fail to make playoffs in any league
phase = game over. The campaign progresses **one week at a time** — the
calendar internally rolls 7 days per "다음 주" press, but the player only
sees a phase / week counter.

## Entry point
`scenes/Season.tscn` — entered from `scenes/TitleScreen.tscn` once the
player picks a save slot. Root: `Control` with `SeasonHub.gd` attached.
SeasonHub branches on `gm.season_state["active"]`: false → run
`init_season()` and route to DRAFT (new campaign), true → skip init and
route directly to HUB (loaded campaign). See `features/save_load/` for the
save-system contract.

## Weekly flow
주는 **월~일 이레 내내 하루씩** 흘러간다(`season_state["week_day"]` 0..6).

```
HUB (주 시작 직전 — 로스터 · 다음 경기 · "이번 주 시작 →")
  → PRESS      (기자회견 — 메신저. 대사 몇 줄 뒤 답변 선택지)
  → TRAINING   (타일을 판에 끼워 이번 주 훈련을 짜고 "훈련 확정")
  → WEEK       (시간 경과 — 좌측 요일 레일 + 그날의 카드 목록)
       월 → 화 → 수 → 목 → 금   각 요일에 apply_day_training(day) 로 그 줄만
                                 정산해 스탯을 올리고 결과를 카드로 보여 준다
       토 (경기일 0) ┬ 플레이어 경기 있음 → "경기 시작"
       일 (경기일 1) │     → MatchFlow (PREP → BAN_PICK) → BattleSim
                     │     → Season 재진입 → 결과 적용 + 그 경기일 AI 정산
                     │     → STANDINGS → "확인" → WEEK (같은 요일)
                     └ 없음 → "확인" 하나로 그날 AI 경기만 정산하고 다음 날
       일요일의 "주 마감 →"
  → CalendarSystem.advance_week (rolls 7 days, bumps phase_week, possibly
    advances phase / bootstraps tournament for next phase)
  → TrainingBoard.reset_for_new_week (판 비우기 + 주 진행 상태 초기화)
  → HUB (autosave: post_week)
```

**훈련은 요일 단위로 먹는다.** 예전에는 "훈련 확정"이
`apply_week_training()` 한 번으로 한 주를 통째로 정산하고 `TRAINING_RESULT`
한 장이 그 결과를 보여 줬는데, 시간 경과 화면이 "그날 무슨 일이 있었는가"를
요일마다 물으면서 정산도 `apply_day_training(day)` 로 쪼개졌다.
`Screen.TRAINING_RESULT` 와 `TrainingResultView` 는 그때 **삭제됐다**.

**토·일 이틀이 경기일이다.** 리그는 한 주에 두 라운드를 돌려 그 둘을 채우고,
토너먼트(플레이오프 · 국제대회)는 주에 라운드 하나라 언제나 토요일에만 선다.
자세한 것은 `calendar/README.md`.

## Architecture
`SeasonHub.gd` is a thin orchestrator (`class_name SeasonHub extends Control`).
Each child module reads/writes shared state via `GameManager.season_state`
and exposes intent methods on the hub. Pattern mirrors `BattleSim`:

```gdscript
@onready var _hub: SeasonHub = get_parent() as SeasonHub
```

| Node                     | Script                                       | Purpose                                                          |
|---|---|---|
| CalendarSystem           | `calendar/CalendarSystem.gd`                 | `advance_week()` — rolls 7 days, bumps `phase_week`, transitions phase. Emits `week_advanced`, `phase_changed`. |
| HubView                  | `HubView.gd`                                 | Simplified hub — phase/week counter + roster + "이번 주 시작" + 순위 buttons. |
| TeamDraft                | `draft/TeamDraft.gd`                         | 초기 5인 선발 (네임드 25인 풀) — 역할 고정 5칸 · 역할 필터 · 스크롤 썸네일 격자 · 상세 팝업. `draft/README.md` |
| PressConferenceView      | `press/PressConferenceView.gd`               | **기자회견** — 주 시작 직전의 메신저 화면. 지금은 대사 · 선택지가 임시 데이터인 틀이다. `press/README.md` |
| TrainingBoard            | `training/TrainingBoard.gd`                  | **주간 훈련 타일판** — 5열(선수) × 5행(월~금). 배치 판정 + 정산(`cell_exp` / `compute_day_gains`) + **요일 적용**(`apply_day_training(day)`) + 나머지 EXP 통장. `training/README.md` |
| TrainingView             | `training/TrainingView.gd`                   | Schedule editor; "훈련 확정" calls `SeasonHub.on_training_confirmed` — 판을 정산하지 않고 **주를 연다**(요일 커서를 월요일에 세운다). |
| WeekProgressView         | `week/WeekProgressView.gd`                   | **시간 경과** — 좌측 세로 요일 레일 + 그날의 훈련 결과 / 경기 카드 + 아래 "확인" (경기일이면 "경기 시작"). `week/README.md` |
| LeagueManager            | `league/LeagueManager.gd`                    | Round-robin schedule keyed by `phase_week` (1 round per week), standings, `resolve_current_week()` for AI matches. |
| TournamentManager        | `tournament/TournamentManager.gd`            | 4-team SE playoff bracket distributed across 2 weeks (SF week + F week). |
| InternationalTournament  | `tournament/InternationalTournament.gd`      | 8-team SE INTL bracket distributed across 3 weeks (QF / SF / F). |
| LeagueView               | `league/LeagueView.gd`                       | Standings screen — "다음 주 →" advances week, "돌아가기" returns to HUB. |
| BracketView              | `tournament/BracketView.gd`                  | Phase-7 playoff bracket UI (3 panels: SF1/SF2/F)                 |
| IntlBracketView          | `tournament/IntlBracketView.gd`              | Phase-8 INTL bracket UI (7 panels: 4 QF / 2 SF / F)              |
| GameOverView             | `GameOverView.gd`                            | Game-over screen — playoff miss (Phase 7) or REGULAR_INTL loss   |
| EndingView               | `EndingView.gd`                              | World-champion ending screen — REGULAR_INTL win                  |

## Phase week budget (CalendarSystem.PHASE_WEEKS)
| Phase           | League weeks | Playoff weeks | Total |
|---|---|---|---|
| PRESEASON       | 7  (single RR) | 2 (SF / F)    | 9     |
| PRESEASON_INTL  | —              | 3 (QF / SF / F) | 3   |
| MIDSEASON       | 14 (double RR) | 2             | 16    |
| MIDSEASON_INTL  | —              | 3             | 3     |
| REGULAR         | 14 (double RR) | 2             | 16    |
| REGULAR_INTL    | —              | 3             | 3     |

Total ≈ 50 weeks (~ 11.5 months).

## Match-day handoff
- 시간 경과 화면의 토 / 일에서 `SeasonHub.has_player_match_on_day(day)` 가
  참이면 아래 버튼이 **"경기 시작"** 이 된다. 누르면
  `on_week_day_match_start()` → `_launch_player_match_on_day(matchday)` 가
  `season_state["pending_match"]`(`{source, schedule_idx, enemy_team_id,
  winner_side}`)를 채우고 MatchFlow 로 `change_scene_to_file` 한다.
  우선순위는 예전과 같이 INTL > 플레이오프 > 리그(`_find_player_match_source`).
- MatchFlow runs PREP → BAN_PICK(밴픽 + 메크 배정) → BattleSim. 정글 시작
  방향은 BattleSim 이 개시 직전에 묻는다.
- When BattleSim ends, the win panel's "다음 →" returns to `Season.tscn`.
- `SeasonHub._ready` consumes `pending_match`, applies the result via
  `LeagueManager.record_result()` / `TournamentManager.record_result()` /
  `InternationalTournament.record_result()`, then calls
  `_resolve_ai_for_matchday(md)` — **그 경기일의 AI 경기만**. 주 통째로
  돌리면 토요일 경기를 마치고 보는 순위표에 아직 치르지도 않은 일요일 결과가
  미리 들어간다. 그러고 나서 STANDINGS 로 라우팅한다.
- 순위표 / 대진표의 **"확인"** 은 `on_standings_confirmed()` 다 — 주가 돌고
  있으면(`week_day >= 0`) 그 요일로, 아니면 허브로 돌아간다. 예전의
  "다음 주 →" 버튼은 세 화면에서 전부 삭제됐다(주를 넘기는 일이 일요일
  마감으로 옮겨 갔다).

## Tournament lifecycle
- TournamentManager and InternationalTournament both listen to
  `CalendarSystem.week_advanced` and bootstrap their bracket on the right
  week (`is_playoff_bootstrap_week()` for playoff, week 1 of an INTL phase
  for INTL).
- They also expose `ensure_active()` so SeasonHub can re-bootstrap on HUB
  entry when loading a save mid-tournament.
- Both share `season_state["current_tournament"]` but discriminate by
  `type` (`"PLAYOFF"` vs `"INTL"`); each manager only clears its own type
  on phase change.
- `resolve_current_week()` runs AI-vs-AI sims for matches scheduled in the
  current `phase_week` of the active bracket. Player matches are left
  unplayed for SeasonHub to launch.

## Match schedule shape
`season_state["match_schedule"]` and bracket entries share most fields:

```gdscript
{
  "phase":      int,            # SeasonPhase
  "phase_week": int,            # 1-indexed week within the phase
  "round":      int,            # round-robin round index (league only)
  "slot":       int,            # bracket slot (tournaments only)
  "team_a":     int,
  "team_b":     int,
  "year":       int,            # Monday of the phase_week — for save metadata
  "month":      int,
  "day":        int,
  "weekday":    int,            # always 0 (Mon) under weekly progression
  "played":     bool,
  "winner":     int,            # team_id, or -1 when unplayed
}
```

`year/month/day` are derived from the phase_week's Monday so save slot
cards still show meaningful dates. The day-of-week distinction is
internal-only and never exposed in-game.

## 흰 배경 테마
아웃게임 화면의 **모든 색이 `resources/OutgameTheme.gd` 를 지난다** — 바탕 ·
카드 · 글자 · 강조 · 역할 색 · 버튼 스타일 · 요일 이름이 그 한 표에 있다.
참고 디자인은 `docs/ref_image.jpg`(하얀 종이 위에 색이 있는 카드). 화면마다
자기 `Color(...)` 리터럴을 들고 있으면 같은 카드가 화면마다 다른 회색으로
그려지고, 팔레트를 한 번 손보는 일이 파일 열몇 개를 훑는 일이 된다.
**인게임(BattleSim)은 이 표를 쓰지 않는다** — 전장은 어두운 화면이다.

## Autosave triggers (5)
0. **Post-match** — `SeasonHub._ready` right after the BattleSim result is
   applied (so closing on the standings screen preserves the outcome).
1. **Post-draft** — `SeasonHub.goto(HUB)` when previous screen was DRAFT.
2. **Pre-ban-pick** — `MatchFlow._on_prep_finished` after the player
   confirms PREP. Writes `season_state["match_resume"] = {phase: BAN_PICK,
   player_side, ...}`.
3. **Post-ban-pick** — `MatchFlow._on_ban_pick_finished` before
   `change_scene_to_file` to BattleSim. Writes the full match snapshot
   (banned/picked/assigned mech IDs) into `match_resume`.
4. **Post-week-end** — `SeasonHub._end_week` after `advance_week` (the
   일요일 마감). Captures both post-match weeks and no-match weeks.

No save fires inside BattleSim. Closing mid-battle leaves the disk save at
trigger #3; resume re-enters BattleSim with the locked-in picks but the
battle replays from scratch.

## Resume routing
TitleScreen "이어하기" branches on `season_state["match_resume"]`:
- Non-null → `MatchFlow.tscn` (MatchFlow consumes the hint and skips
  PREP, jumping directly to BAN_PICK or LAUNCH depending on the saved
  phase).
- Null → `Season.tscn` → SeasonHub → HUB.

SlotCard shows a "경기 진행 중" tag when `meta.match_in_progress == true`
(set whenever `match_resume` is non-null at save time).

## SeasonHub screen routing
`SeasonHub._route()` toggles child controls based on `current_screen`.
Lazy view builders cache the instance after first creation.
- `Screen.DRAFT` → `TeamDraft`.
- `Screen.HUB` → simplified HubView. Calls `LeagueManager.ensure_phase_scheduled()`
  + `TournamentManager.ensure_active()` + `InternationalTournament.ensure_active()`
  to handle save-loads landing on tournament weeks.
- `Screen.PRESS` → `PressConferenceView` (매번 회견을 새로 연다).
- `Screen.TRAINING` → `TrainingView`.
- `Screen.WEEK` → `WeekProgressView` (요일 커서는 `season_state["week_day"]`).
- `Screen.LEAGUE` → `LeagueView` (standings).
- `Screen.PLAYOFF` → `BracketView`.
- `Screen.INTL_BRACKET` → `IntlBracketView`.
- `Screen.GAME_OVER` → `GameOverView`.
- `Screen.ENDING` → `EndingView`.

## Calendar contract
- `CalendarSystem.advance_week()` is the single tick, and **only
  `SeasonHub._end_week()` calls it** — the 일요일 마감. Rolls 7 days
  forward, bumps `phase_week`, transitions phase if `phase_week` exceeds
  `phase_max_weeks(current_phase)`. Emits `week_advanced` (always) and
  `phase_changed` (on phase transitions).
- `phase_week` weekday stays at 0 (Mon) — the player conceptually sits at
  the start of each week. F/S/S match days are fictional internal
  ordering.
- `is_league_match_week()` / `is_playoff_week()` / `is_playoff_bootstrap_week()`
  drive which subsystem owns the current week.
- `date_of_week_offset(n)` returns the Monday of the week n weeks ahead
  (used by schedulers to stamp matches).

---

## 화면 대응 (세이프 에어리어)

시즌 뷰는 전부 전체 화면 `Control` 에 절대 좌표로 그린다. 규약은 두 줄이다.

```gdscript
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)   # 화면째 노치 밑으로 내린다
	...
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ScreenMetrics.extend_background(bg)      # 배경만 노치 자리까지 도로 늘린다
```

**제목만 내리면 안 된다** — 본문이 제자리에 남아 둘이 겹친다(타이틀 화면에서
실제로 제목이 슬롯 카드 밑으로 들어갔다).

내려간 화면 안에서 하단 액션 바를 매달 때는 `ScreenMetrics.bottom_y()` 가
아니라 **`safe_h()`** 를 쓴다(전자는 뷰포트 좌표라 내린 만큼 두 번 더해진다).
`LeagueView` / `BracketView` / `IntlBracketView` / `TrainingView` 는
`safe_h() - 80 - h`, `TrainingResultView` 는 `- 70`, `HubView` 는 `- 110`,
`TeamDraftView` 는 `bar_y()` 가 `safe_h() - 20 - BAR_H` 다.

`TeamDraftView.grid_h()` 는 **남는 자리**로 계산한다(`bar_y() - 12 - GRID_Y`) —
화면이 길수록 썸네일이 한 줄 더 보인다(1920 에서 950, 2340 에서 1280).

자세한 내용: **`docs/mobile_safe_area.md`**
