# Calendar System

Drives the **week-by-week** clock that frames the entire campaign.

- 1 tick = 1 week. `SeasonHub` advances the clock when the player closes
  **Sunday** on the 시간 경과 화면 (`on_week_day_confirmed` → `_end_week`).
  The standings/bracket views no longer carry a "다음 주" button.
- `CalendarSystem.advance_week()` rolls the date 7 days forward, bumps
  `season_state["phase_week"]`, and triggers a phase transition when
  `phase_week > phase_max_weeks(current_phase)`.
- `season_state["weekday"]` stays at 0 (Mon) — it is the *week's* date, and
  every match entry is stamped with that Monday for save metadata.
  **The day the player actually sits on is `season_state["week_day"]`**
  (0 = 월 … 6 = 일), owned by the 시간 경과 화면
  (`features/season/week/`). -1 means the week has not been opened yet.
- Month/year roll-over and SeasonPhase transitions are owned here:
  PRESEASON → PRESEASON_INTL → MIDSEASON → ... → REGULAR_INTL.

## Signals
- `week_advanced(new_date)` — fires every `advance_week()` call. Listened
  to by TournamentManager + InternationalTournament for bracket bootstrap,
  and by HubView for refresh.
- `phase_changed(new_phase)` — fires when `_advance_phase()` triggers.
  LeagueManager schedules the new phase here; tournament managers clear
  their own bracket type.

## 요일과 경기일
한 주는 **월~일 이레**다(`DAYS_PER_WEEK`).

| 요일 index | | 하는 일 |
|---|---|---|
| 0..4 | 월~금 | **훈련일**(`TRAINING_DAYS` = 5, 훈련판의 다섯 행) |
| 5 | 토 | **경기일 0**(`MATCH_DAYS`) |
| 6 | 일 | **경기일 1** |

**리그는 한 주에 두 라운드를 돌린다**(`ROUNDS_PER_WEEK` = 2) — 토 한 라운드,
일 한 라운드. 스케줄 엔트리의 `matchday` 컬럼이 그 둘을 가른다.
**토너먼트(플레이오프 · 국제대회)는 여전히 주 1경기**이고 언제나 토요일
(`matchday = 0`)에 선다 — 8강 · 4강 · 결승은 라운드 사이에 한 주씩 쉬어야
대진표가 읽히고, 리그처럼 이틀에 몰면 3주짜리 국제대회가 이틀 반이 된다.

정적 헬퍼 둘이 그 표를 읽는다 — `is_training_day(day)` / `matchday_of(day)`
(경기가 실제로 **배정돼 있는가**는 답하지 않는다. 그건 스케줄이 답한다).

## Phase boundaries (CalendarSystem.PHASE_WEEKS)
라운드 수는 그대로이고 **주에 두 라운드씩 들어가므로 리그 주차가 절반이 됐다**
(= `ceil(rounds / 2)`). 팀이 치르는 경기 수는 안 달라졌다.

| Phase           | Rounds | League weeks | Playoff weeks | Total |
|---|---|---|---|---|
| PRESEASON       | 7  (single RR) | 4  | 2 (SF / F)      | 6 |
| PRESEASON_INTL  | —              | —  | 3 (QF / SF / F) | 3 |
| MIDSEASON       | 14 (double RR) | 7  | 2               | 9 |
| MIDSEASON_INTL  | —              | —  | 3               | 3 |
| REGULAR         | 14 (double RR) | 7  | 2               | 9 |
| REGULAR_INTL    | —              | —  | 3               | 3 |

Total ≈ 33 weeks. 프리시즌은 라운드가 홀수(7)라 **마지막 주는 토요일 한
라운드로 끝나고 일요일이 빈다** — 그 요일은 경기 카드가 "예정된 경기 없음"을
띄우고 그냥 넘어간다.

## Helpers
- `is_league_match_week()` — true iff inside the league portion of a
  league phase (`phase_week <= LEAGUE_WEEKS[phase]`).
- `is_playoff_week()` — true iff inside the trailing playoff weeks.
- `is_playoff_bootstrap_week()` — true iff `phase_week == LEAGUE_WEEKS + 1`
  (the SF week). Used by TournamentManager to bootstrap the bracket.
- `date_of_week_offset(n)` — returns `{year, month, day, weekday}` of the
  Monday `n` weeks ahead. Schedulers stamp matches with this so save
  metadata stays coherent.


## Detail moved from root CLAUDE.md

### Weekly progression contract
`CalendarSystem.advance_week()` rolls 7 days forward, bumps `phase_week`,
and emits `week_advanced` (and `phase_changed` on transitions). **부르는
자리는 `SeasonHub._end_week()` 하나** — 시간 경과 화면에서 일요일을 닫을 때다.
All three managers (LeagueManager, TournamentManager,
InternationalTournament) listen to `week_advanced` and either bootstrap
their bracket (`is_playoff_bootstrap_week()` for playoff,
`phase_week == 1 && is_intl_phase` for INTL) or no-op. Match resolution is
explicit: `SeasonHub` calls `_resolve_ai_for_matchday(md)` **경기일마다**
(주 통째가 아니다 — 토요일 경기를 마치고 보는 순위표에 아직 치르지도 않은
일요일 결과가 들어가면 안 된다), never on signal.

### 요일과 경기일 (한 주의 안쪽)
한 주는 월~일 이레이고 지금 요일은 `season_state["week_day"]`(0..6, **-1 은
주가 아직 안 열렸다**)가 든다. 월~금 닷새가 훈련판의 다섯 행이고 **토(경기일 0) ·
일(경기일 1)** 이틀이 경기일이다(`CalendarSystem.MATCH_DAYS`).

**리그는 한 주에 두 라운드를 돌린다**(`ROUNDS_PER_WEEK` = 2) — 스케줄 엔트리에
`matchday` 컬럼이 생겨 그 둘을 가른다. 라운드 수는 안 바뀌었고 주에 두 개씩
들어가므로 **리그 주차가 절반**이 됐다(프리시즌 7→4주, 미드 / 정규 14→7주;
캠페인 전체 ≈ 50주 → **33주**). 프리시즌은 라운드가 홀수라 마지막 주는 토요일
한 라운드로 끝나고 일요일이 빈다. **토너먼트(플레이오프 · 국제대회)는 여전히
주 1경기**이고 언제나 토요일(`matchday = 0`)에 선다 — 8강 · 4강 · 결승은 라운드
사이에 한 주씩 쉬어야 대진표가 읽힌다.

주 진행 상태 셋이 `season_state` 에 살고 세이브에 실린다 — `week_day`,
`week_day_log`(요일별 훈련 결과 기록, **정수 키**라 로드에서 되돌린다),
`training_exp_carry`(나머지 EXP 통장). 셋 다
`TrainingBoard.reset_week_progress()` 가 비우고, 그것은 훈련 확정과 주 종료
두 곳에서 돈다.
