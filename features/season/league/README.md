# League Manager

Owns the regular-league round-robin schedule, AI-vs-AI auto resolution,
standings table, and the playoff cut-line check (top 4 of 8 = playoffs).
The campaign progresses 1 week at a time, and **each league week holds two
rounds** — 토요일 한 라운드(`matchday = 0`), 일요일 한 라운드(`matchday = 1`).

## Schedule shape
- **PRESEASON** — single round-robin (7 rounds, 28 matches, each team
  plays every other once). **4 league weeks** — 라운드가 홀수라 마지막 주는
  토요일 한 라운드로 끝나고 일요일이 빈다.
- **MIDSEASON / REGULAR** — double round-robin (14 rounds, 56 matches,
  home-and-away). **7 league weeks**.
- **\*\_INTL** phases — no league schedule. INTL bracket lives in
  `features/season/tournament/` (3-week 8-team SE).
- **2 rounds = 1 week.** Round `r_idx` → `phase_week = r_idx / 2 + 1`,
  `matchday = r_idx % 2`. Each match is stamped with the Monday of its
  phase_week so save metadata stays coherent — `weekday` stays 0 and the
  day the match actually lands on is what `matchday` says.
- Schedule is generated lazily and idempotently:
  - `SeasonHub._show_hub()` calls `LeagueManager.ensure_phase_scheduled()`
    on every hub entry — covers the initial PRESEASON post-draft.
  - `LeagueManager._on_phase_changed()` does the same on every league
    phase transition (MIDSEASON, REGULAR). INTL transitions are no-ops.

## Match-day flow
- 플레이어는 **시간 경과 화면의 토 / 일**에서 "경기 시작"을 눌러 들어간다
  (`SeasonHub.on_week_day_match_start` → MatchFlow → BattleSim). 돌아오면
  SeasonHub 가 결과를 적고 **그 경기일의** AI 경기만 정산한다
  (`_resolve_ai_for_matchday`).
- `resolve_matchday(md)` 가 그 일을 한다 — `phase == current_phase &&
  phase_week == current_phase_week && matchday == md` 이면서 플레이어 팀이
  끼지 않은 경기를 `simulate_ai_match()` 로 굴리고 결과를 적는다.
  `md < 0` 이면 그 주 전체(주 마감의 쓸어 담기 경로). 리그 주가 아니면 no-op
  (`is_league_match_week()`).
- `resolve_current_week()` 는 `resolve_matchday(-1)` 의 다른 이름으로 남았다.
- **경기일로 나눠 도는 것이 요점이다** — 주 통째로 돌리면 토요일 경기를 마치고
  보는 순위표에 아직 치르지도 않은 일요일 결과가 미리 들어간다.

## Standings
- `season_state["league_standings"]` — `team_id (int) → {wins, losses}`.
  Reset to all-zeros at the start of every league phase
  (`generate_phase_schedule` clears it).
- `standings_ranked()` returns rows `{team_id, wins, losses}` sorted by
  wins desc, losses asc, team_id asc.
- `player_made_playoffs()` checks whether the player team is in the top
  `GameManager.PLAYOFF_TEAMS` (default 4). Used by Phase 7 at phase end.

## Public API
| Method | Caller |
|---|---|
| `ensure_phase_scheduled()` | SeasonHub on hub entry, self on phase_changed |
| `generate_phase_schedule(phase)` | Internal (called by ensure) |
| `resolve_matchday(md)` | SeasonHub — 그 경기일의 AI 경기 정산 |
| `resolve_current_week()` | `resolve_matchday(-1)` — 주 마감의 쓸어 담기 |
| `record_result(a, b, winner)` | SeasonHub after BattleSim returns |
| `simulate_ai_match(a, b)` | resolve_current_week (and tournaments reuse it) |
| `standings_ranked()` | LeagueView, tournament managers |
| `player_made_playoffs()` | Phase 7 cut |
| `next_unplayed_player_match()` | LeagueView next-match header, HubView |
| `player_match_on_day(md)` | SeasonHub (그 요일에 경기가 있는가) |
| `player_match_this_week()` | `player_match_on_day(-1)` — HubView 머리글 |
| `matches_this_week()` | LeagueView "this week's matches" |
| `team_name(id)` / `team_short_name(id)` | LeagueView, draft, future UIs |

## Match-schedule entry shape
Each entry in `season_state["match_schedule"]` is a Dictionary:
```
{
  "phase":      GameEnums.SeasonPhase,
  "phase_week": int,                  # 1-indexed week within the phase
  "matchday":   int,                  # 0 = 토, 1 = 일
  "round":      int,                  # round-robin round index
  "year":       int, "month": int, "day": int, "weekday": int,
  "team_a":     int, "team_b": int,
  "played":     bool,
  "winner":     int,                  # team_id or -1 if not played
}
```

`year/month/day` are stamped to the Monday of the phase_week — used only
for save metadata and SlotCard display, never for match-day filtering.

## Files
- `LeagueManager.gd` — orchestrator (this README's contract).
- `LeagueView.gd` — standings screen. 8 ranked rows + next-match header
  + **"확인" 버튼 하나**. Routed via `SeasonHub.Screen.LEAGUE`. 주를 넘기는
  일은 시간 경과 화면의 일요일 마감이 가져갔고, 돌아갈 자리는 버튼이 아니라
  주 진행 상태가 정한다(`SeasonHub.on_standings_confirmed`). 색은
  `OutgameTheme` — 흰 종이 위의 카드 목록이다.
