# Outgame (Season) 개발 계획

## 진행 상황 요약

| Phase | 제목 | 상태 | 핵심 산출물 |
|---|---|---|---|
| 1 | Foundation (데이터/스캐폴딩) | ✅ Complete | players.csv 40명, season enums, season_state, features/season/ 골격, Season.tscn |
| 2 | Team Draft UI | ✅ Complete | 40명 풀에서 포지션당 1명 픽 화면 |
| 3 | Calendar UI + 일 진행 | ✅ Complete | 월간 뷰 + "다음 날" 버튼 + 페이즈 전환 |
| 4 | Training Scheduler UI | ✅ Complete | 7일 × 5파일럿 그리드 + 스탯 적용 |
| 5 | League Standings + 자동 스케줄 | ✅ Complete | 라운드로빈 생성, 순위표, AI vs AI 시뮬 |
| 6 | Season → MatchFlow → BattleSim 연결 | ✅ Complete | 매치데이 자동 진입, 결과 복귀, 순위 갱신 |
| 7 | 플레이오프 브래킷 | ✅ Complete | 상위 4팀 토너먼트 + 진출 실패 시 게임오버 |
| 8 | 국제대회 + 엔딩/게임오버 | ✅ Complete | 8팀 INTL 토너먼트, REGULAR_INTL 우승 → ENDING / 패배 → GAME_OVER |

상세 일정 / 의존성은 아래 각 Phase 항목 참조.

---

## 글로벌 결정 사항 (변경 시 모든 Phase 영향)

- **풀 크기**: 40명 (8팀 × 5포지션). `players.csv`에서 관리.
- **플레이어 팀**: `team_id = 0`. 드래프트로 5명 자동 스왑 (역할 동일 교환).
- **시간 단위**: 1일 = 1 tick. 주는 월~일 (weekday 0~6).
- **경기 처리**: 모든 리그 경기는 BattleSim 풀 플레이 (자동 시뮬 옵션 없음).
- **스탯 모델**: 기존 5스탯 유지 (`laning, mechanics, gamesense, teamfight, mental`). 신규 스탯/컨디션 시스템 도입 안 함.
- **리그 구조**: 8팀 정규리그 + 상위 4팀 플레이오프.
- **캠페인 길이**: 6대회 (12월 시작 → 다음 해 11월).

---

## Phase 1 — Foundation (데이터/스캐폴딩) ✅

**목표**: 데이터/상태 모델과 폴더 구조 확정. UI 없음.

### 산출물
- [x] `data/csv/players.csv` 40행 (8팀 × 5역할)
- [x] `resources/GameEnums.gd` 시즌 enum 4종 추가
- [x] `autoloads/GameManager.gd`
  - `season_state` dict + `reset_season_state()` + `init_season()`
  - 상수 `TEAM_COUNT = 8`, `PLAYOFF_TEAMS = 4`
- [x] `features/season/` 폴더 + 5개 모듈 골격
  - `SeasonHub.gd` (오케스트레이터)
  - `calendar/CalendarSystem.gd`
  - `draft/TeamDraft.gd`
  - `training/TrainingScheduler.gd`
  - `league/LeagueManager.gd`
- [x] `scenes/Season.tscn` (placeholder Label)
- [x] `project.godot` main_scene → Season.tscn
- [x] `CLAUDE.md` 갱신

### 검증
1. Godot 에디터 → `Project → Tools → Rebuild game.db` 실행 → players 40행 갱신 확인
2. F5 실행 → 콘솔에 `SeasonHub: route to DRAFT` 출력 확인
3. `_gm.season_state["all_pilots"].size() == 40` 검증

---

## Phase 2 — Team Draft UI ✅

**목표**: 40명 풀에서 포지션당 1명 선택해 팀 0 구성. 게임 시작 시 첫 화면.

### 산출물
- [x] `features/season/draft/TeamDraftView.gd` — 5열(역할) × 8행(후보) 그리드 패널
- [x] `features/season/draft/PilotCard.gd` + `.tscn` — 카드 노드(이름, 역할, 5스탯 바, 현 소속팀 라벨)
- [x] 상단 요약: "내 팀 (X/5)" 5슬롯 미리보기 (사이드바 → 모바일 포트레이트 적합 위해 상단 행으로 변경)
- [x] 하단 버튼: `드래프트 확정` (5명 모두 선택 시 활성화)
- [x] 확정 클릭 → `TeamDraft.apply_draft()` 호출 → `SeasonHub.goto(Screen.HUB)`
- [x] `SeasonHub._route()` 실 구현 (DRAFT/HUB placeholder 토글)
- [x] `TeamDraft.get_pool_grid()` 헬퍼: 역할당 8명을 총 스탯 내림차순으로 정렬해 5×8 entry 반환
- [x] Lazy view 빌드 (`TeamDraft.ensure_view()`): `init_season()` 이후에 view를 생성해 빈 풀 참조 방지

### 의존성
- 없음 (Phase 1 데이터만 필요)

### 검증
- 픽 → 같은 역할의 이전 픽이 자동 해제되는가?
- 확정 후 `season_state["team_rosters"][0]`에 5명, 다른 팀들도 5명씩 유지되는가?

### 디자인 노트
- 1080×1920 모바일 포트레이트. 8행이 한 화면에 다 들어가야 하므로 카드 높이 ~180px.
- 카드 탭 = 같은 역할 슬롯에 픽. 같은 카드 다시 탭 = 픽 해제.

---

## Phase 3 — Calendar UI + 일 진행 ✅

**목표**: 월간 달력 뷰. "다음 날" 버튼으로 1일씩 진행. 페이즈 자동 전환.

### 산출물
- [x] `features/season/HubView.gd` — `class_name HubView extends Control`. SeasonHub의 HUB 스크린.
  - 상단 HUD: 연/월/일/요일 + 현재 페이즈 + 페이즈 주차
  - 그 아래: 팀 로스터 5장 (역할별 카드, 이름 + TOTAL 표시)
  - 하단 버튼: `다음 날`, `훈련 편집` (Phase 4 토스트), `리그 순위` (Phase 5 토스트)
  - 토스트 영역: 페이즈 전환 / 매치데이 도달을 알리는 임시 라벨 (2.5s)
- [x] `SeasonHub` HUB 스크린 라우팅: `_ensure_hub_view()` 가 `HubView` 를 동적으로 추가, `_show_hub()` 가 토글
- [x] `CalendarSystem.advance_day()` 확장
  - 종료일 훈련 적용 (`TrainingScheduler.apply_day_training(weekday)`) → 일자 롤 → weekday 롤
  - 월요일 진입 시 `phase_week++` + `TrainingScheduler.refill_player_team_defaults()`
  - `phase_week > phase_max_weeks(phase)` 이면 `_advance_phase()` (REGULAR_INTL 후 noop)
  - `day_advanced` 시그널 emit 후 매치데이면 `match_day_reached` emit
- [x] 페이즈별 주차 매핑 상수 `CalendarSystem.PHASE_WEEKS` (PRESEASON 2 / *_INTL 1 / MIDSEASON 8 / REGULAR 12)

### 의존성
- Phase 2 (드래프트가 끝나야 HUB로 진입)

### 검증
- 드래프트 확정 → HUB 진입 → 좌상단 "Y1 12 / 01 (월)" 표시
- "다음 날" 클릭 → "Y1 12 / 02 (화)" 로 롤, 캘린더의 오늘 셀이 다음 날로 이동
- 6번 클릭하면 일요일 → 다음 클릭에서 월요일 + `phase_week 2 / 2` (PRESEASON 2주차)
- PRESEASON 14일 후 (월요일 진입 시) 페이즈 전환 토스트: "페이즈 진입: 프리시즌 국제대회"
- 12월 31일 → 1월 1일 정상 롤
- 금/토/일 도달 시 매치데이 토스트 + 날짜 라벨 색이 노란색으로 변경

---

## Phase 4 — Training Scheduler UI ✅

**목표**: 7일 × 5파일럿 그리드. 셀 클릭 = 훈련 종류 변경.

### 산출물
- [x] `features/season/training/TrainingView.gd` — 5(파일럿) × 7(요일) 그리드
- [x] 셀 컨텐츠: TrainingType 한 글자 라벨 + 풀네임 (Button 두 줄 표시)
- [x] 매치 셀(금/토/일)은 잠금 (`_is_cell_locked()` — Phase 4 단독 룰: 항상 잠금)
- [x] 셀 탭 → TrainingType 픽업 다이얼로그 (REST/LANING/MECHANICS/GAMESENSE/TEAMFIGHT/SCRIM + 취소)
- [x] 상단 미리보기: 5파일럿 × 5스탯 표 — 현재 값 + 주간 적용 시 예상값 (`+Δ`/`-Δ` 컬러 표시)
- [x] 하단 버튼: `자동 채우기` (`refill_player_team_defaults`) / `저장하고 닫기` (HUB 복귀)
- [x] `TrainingScheduler.projected_week_stats(p)` 헬퍼 — 7일 누적 후 1~100 클램프된 스탯 dict 반환
- [x] `SeasonHub` `Screen.TRAINING` 라우팅 + lazy `_ensure_training_view()`
- [x] HubView "훈련 편집" 버튼이 실제로 `goto(Screen.TRAINING)` 호출

### 의존성
- Phase 3 (HUB에서 "훈련 편집" 진입)

### 검증
- 셀 변경 후 저장 → 다음 날 진행 시 해당 일 훈련이 적용되는가?
- 일주일 누적 시 스탯 5~10 정도 상승 (단, 100 cap 준수)

### 추가 고려
- 매치 셀은 LeagueManager가 매치 스케줄 만든 후 자동 잠금되어야 함 (Phase 5 의존)
- Phase 4 단독으로는 `_is_cell_locked(weekday>=4) == true` 로 금/토/일 = MATCH 고정 처리. Phase 5에서 `LeagueManager`의 실제 매치 스케줄을 확인하도록 교체 필요.

---

## Phase 5 — League Standings + 자동 스케줄 ✅

**목표**: 라운드로빈 자동 생성, 순위표 화면, AI vs AI 자동 결과.

### 산출물
- [x] `features/season/league/LeagueView.gd` — 8팀 순위표 화면 (`Screen.LEAGUE`, lazily built). 헤더에 현재 페이즈 + 다음 플레이어 매치, 본문 8행은 W-L/승률/PO 컬럼. 플레이어 팀 행은 골드 강조, 상위 PLAYOFF_TEAMS 행은 그린 강조.
- [x] `LeagueManager.generate_phase_schedule(phase)` + `ensure_phase_scheduled()` (idempotent)
  - PRESEASON: 단일 라운드로빈 (7라운드 × 4매치 = 28매치)
  - MIDSEASON / REGULAR: 더블 라운드로빈 (14라운드 × 4매치 = 56매치)
  - `_enumerate_match_days(phase)` 가 페이즈 첫 월요일부터 끝까지 금/토/일을 수집
  - `_distribute_rounds(rounds, days)` 가 라운드를 매치데이에 균등 배치 (rounds > days 이면 마지막 날에 surplus 누적)
  - `season_state["match_schedule"]` 에 `{phase, year, month, day, weekday, round, team_a, team_b, played, winner}` 엔트리 추가
- [x] `LeagueManager._on_phase_changed` (CalendarSystem.phase_changed 구독) + `SeasonHub._show_hub()` 가 둘 다 `ensure_phase_scheduled()` 호출 — INTL은 무시, 중복 호출은 no-op
- [x] `LeagueManager._on_match_day_reached` (CalendarSystem.match_day_reached 구독)
  - 플레이어 팀 매치 → 그대로 둠 (Phase 6 에서 BattleSim 연결)
  - AI vs AI 매치 → `simulate_ai_match()` 즉시 실행, `played=true` + `record_result()`
- [x] `LeagueManager.player_has_match_on_weekday_this_week(weekday)` — TrainingView 셀 잠금 기준
- [x] `LeagueManager.next_unplayed_player_match()`, `matches_today()`, `team_name()`, `team_short_name()` — Phase 6/7 + LeagueView 헤더 보조
- [x] `data/csv/teams.csv` 신설 (8팀, id/name/short_name) + `addons/csv_to_db/plugin.gd` SCHEMAS+TABLE_DEFS 갱신
- [x] `GameManager._load_team_meta()` 가 `season_state["team_meta"]` 채움 (DB 미빌드 시 fallback Array 합성)
- [x] `TrainingView._is_cell_locked()` 이 `player_has_match_on_weekday_this_week()` 사용. `_normalize_locked_cells` 가 잠금 해제된 MATCH 셀을 REST로 자동 변환. `TrainingScheduler.apply_day_training()` 도 매치 없는 날의 MATCH 셀을 REST 처리하여 mental -2 누락 방지.
- [x] `HubView._on_match_day_reached` 토스트가 "오늘 경기 vs <팀명>" / "오늘은 경기 없음" 으로 분기. "리그 순위" 버튼이 실제로 `goto(Screen.LEAGUE)` 호출.
- [x] PilotCard / TeamDraftView 의 "TEAM N" 라벨이 team_meta short_name 사용

### 의존성
- Phase 3 (calendar tick 필요)

### 검증
- 페이즈 시작 시 8팀이 모두 1번씩 만나는지 (PRESEASON 7라운드, MIDSEASON/REGULAR 14라운드)
- 매치데이 도달 시 AI 매치만 자동 종료, 플레이어 매치는 `played=false` 유지
- 리그 순위 화면이 페이즈 진행에 따라 W-L 갱신 + 플레이어 팀 행 강조
- TrainingView 의 금/토/일 셀이 실제 스케줄에만 잠기는지 (INTL 주간엔 편집 가능)
- "Project → Tools → Rebuild game.db" 후 teams 테이블 8행 갱신

### 알려진 한계 (Phase 6 에서 처리)
- PRESEASON 일요일 마지막 날에 라운드 2개가 겹쳐 플레이어 매치가 동일 날 2개 생기는 경우. Phase 6 가 `matches_today()` 로 모두 순회 처리해야 함.

---

## Phase 6 — Season → MatchFlow → BattleSim 연결 ✅

**목표**: 플레이어 팀 매치데이에 자동으로 MatchFlow 진입, 끝나면 Season 복귀.

### 산출물
- [x] `GameManager.season_state["pending_match"]` 도입: `{schedule_idx, enemy_team_id, winner_side}` (winner_side: -1=미정, 0=플레이어 승, 1=상대 승). `reset_season_state()` 도 reset.
- [x] `SeasonHub._on_match_day_reached`: `CalendarSystem.match_day_reached` 시그널 구독. 부모 `_ready` 가 자식들 뒤에 실행되므로 `LeagueManager.resolve_match_day()` (AI 자동 처리) 이후 `_maybe_launch_next_match_today()` 가 발동.
- [x] `SeasonHub._maybe_launch_next_match_today()`: 오늘 미진행 플레이어 매치를 찾아 `pending_match` 채우고 `change_scene_to_file("res://scenes/MatchFlow.tscn")`.
- [x] `SeasonHub._consume_pending_match_result()`: `_ready()` 진입 시 `pending_match.winner_side >= 0` 이면 `match_schedule[idx].played/winner` 갱신 + `LeagueManager.record_result()` 호출 후 `pending_match` 클리어. 이어서 같은 날 추가 플레이어 매치가 있으면 다시 launch (PRESEASON 일요일 더블 매치 케이스).
- [x] `MatchFlow._ready` / `_load_data`: `pending_match` 가 있으면 `season_state.all_pilots` 를 그대로 사용 (드래프트 결과로 변경된 team_id 보존). 메크는 DB 에서 그대로 로드. `enemy_team_id` 도 `pending_match` 에서 읽어 `_team_roster(enemy_team_id)` 호출.
- [x] `BattleSim` 리턴 경로:
  - `SimulationCore.check_win_condition` 이 `season_state.pending_match.winner_side` 를 0/1 로 기록.
  - `HudBuilder._build_victory_panel` 이 시즌 모드면 "Play Again" 대신 "다음 →" 버튼을 만들고 `BattleSim._on_return_to_season_pressed` 에 연결 (`change_scene_to_file("res://scenes/Season.tscn")`).
- [x] `HubView._on_match_day_reached` 토스트 문구 업데이트 ("Phase 6에서 BattleSim 연결" 제거).

### 의존성
- Phase 5 (스케줄이 있어야 매치데이 발동)

### 검증
- 12월 첫 금요일 → "다음 날" → BAN_PICK 진입
- 전투 종료 → "다음 →" 버튼으로 Season.tscn 복귀 → 순위표에 결과 반영
- AI 매치는 별도 처리되어 같은 매치데이에 자동 종료
- PRESEASON 마지막 일요일에 두 라운드가 겹쳐도 두 매치 모두 순차 진행

### 알려진 제약
- 진행 중 매치는 저장/복구되지 않음 (세이브 시스템 v2 예정).

---

## Phase 7 — 플레이오프 브래킷 ✅

**목표**: 정규리그 종료 후 상위 4팀 단일 토너먼트. 4위 안 들면 게임오버.

### 산출물
- [x] `CalendarSystem` 리그 페이즈 끝에 1주 PLAYOFF 주차를 예약. `PHASE_WEEKS = LEAGUE_WEEKS + 1` (PRESEASON 3, MIDSEASON 9, REGULAR 13). 헬퍼 `phase_league_weeks()`, `is_league_match_week()`, `is_playoff_week()` 추가.
- [x] `LeagueManager._enumerate_match_days()` 가 LEAGUE 주차만 enumerate. `resolve_match_day()` 가 `is_league_match_week()` false 면 short-circuit. `player_has_match_on_weekday_this_week()` 가 active bracket 매치도 스캔.
- [x] `features/season/tournament/TournamentManager.gd` — 4팀 단일 엘리미네이션
  - 매치데이 분배: 1주 (Fri/Sat/Sun) → SF1 (금), SF2 (토), F (일)
  - 4강 1경기: 1위 vs 4위, 4강 2경기: 2위 vs 3위, 결승: SF1.W vs SF2.W
  - `season_state["current_tournament"]` 에 `{type, phase_at_start, stage, bracket}` 저장
  - `_on_day_advanced` 가 PLAYOFF 주차 첫 월요일에 bootstrap. `player_made_playoffs()` false → `playoff_failed_qualification` 발동 후 단축 종료
  - `_on_match_day_reached` → AI 매치 자동 simulate (LeagueManager.simulate_ai_match 재사용), 플레이어 매치는 SeasonHub 처리에 위임
  - F 종료 시 `phase_results[phase] = {made_playoffs, champion}` 기록 + `playoff_completed` 발동
  - `_on_phase_changed` → `current_tournament` 클리어 (다음 리그 페이즈 준비)
- [x] `features/season/tournament/BracketView.gd` — 브래킷 시각화 (`Screen.PLAYOFF`)
  - SF1, SF2 좌측 스택 + F 우측. 각 매치 패널: 슬롯 라벨 / 일자 / 두 팀 / 승자 강조
  - 플레이어 팀 매치는 골드 보더, 종료된 매치는 그린 보더
  - 헤더: 페이즈 / 토너먼트 단계 / 다음 매치 안내
- [x] `features/season/GameOverView.gd` — 게임오버 화면 (`Screen.GAME_OVER`)
  - "GAME OVER" + 원인 ("X 플레이오프 진출에 실패했습니다") + 최종 순위 / 승-패
  - "다시 시작" 버튼 → `reset_season_state()` + `Season.tscn` 리로드
- [x] `SeasonHub` 라우팅
  - `Screen.PLAYOFF`, `Screen.GAME_OVER` 추가 + `_ensure_bracket_view`, `_ensure_game_over_view`
  - `pending_match["source"]` ("league" / "playoff") 으로 결과 라우팅 분기. `_consume_pending_match_result` 가 source 따라 `LeagueManager.record_result` 또는 `TournamentManager.record_result` 호출
  - `_maybe_launch_next_match_today()` → 1) playoff bracket 우선 `_try_launch_playoff_match_today()`, 2) league schedule `_try_launch_league_match_today()`. 같은 날 매치 cascading은 결과 적용 후 재호출
  - `TournamentManager.playoff_failed_qualification` 구독 → `goto(Screen.GAME_OVER)`
- [x] `HubView`
  - 세 번째 액션 버튼 라벨: PLAYOFF 활성 시 "플레이오프" → `Screen.PLAYOFF`, 아닐 때 "리그 순위" → `Screen.LEAGUE`
  - `playoff_started` / `playoff_completed` 토스트
- [x] `scenes/Season.tscn` 에 `TournamentManager` 노드 추가
- [x] `GameManager.season_state["current_tournament"]` 필드 + `reset_season_state` 갱신

### 의존성
- Phase 6 (매치 진행 가능해야 함)

### 검증
- LEAGUE 마지막 일요일까지 8팀 순위 안정. 그 다음 월요일 진입 시 PLAYOFF bootstrap 시그널.
- 4위 안 들었을 때 곧바로 GAME_OVER 화면 진입 (PLAYOFF 매치데이 발생 안 함).
- 1~4위 진입 시 SF1 (금) → SF2 (토) → F (일) 차례로 매치데이 발동.
- 플레이어 SF/F 매치 진행 후 BattleSim 결과가 bracket에 정확히 반영되고, 다음 라운드의 team_a/team_b 가 시드됨.
- F 종료 시 `phase_results[phase].champion` 기록 + 우승 토스트.
- PLAYOFF 다음 주 월요일 진입 시 phase_changed → INTL 페이즈 진입 + bracket 클리어.
- TrainingView 의 PLAYOFF 매치데이 셀이 잠기는지 (player가 진출했고 출전하는 weekday 한정).

### 알려진 한계 (Phase 8 에서 처리)
- INTL 페이즈는 phase_results 만 보고 라우팅 결정 — Phase 8 에서 `InternationalTournament` + ENDING 라우팅 추가 예정.

---

## Phase 8 — 국제대회 + 엔딩/게임오버 ✅

**목표**: INTL 페이즈에 다른 리그 4팀 + 우리 리그 4팀 = 8팀 단일 엘리미네이션 토너먼트. REGULAR_INTL 우승 = 엔딩, 패배 = 게임오버.

### 산출물
- [x] `data/csv/intl_teams.csv` (4팀, id 100..103) + `data/csv/intl_players.csv` (20명, id 100..119, 4팀 × 5포지션). `addons/csv_to_db/plugin.gd` SCHEMAS+TABLE_DEFS 갱신.
- [x] `GameManager._load_intl_pool()` — `season_state["intl_team_meta"]` + `["intl_pilots"]` 채움. DB 미빌드 시 4팀 합성 fallback.
- [x] `features/season/tournament/InternationalTournament.gd` — 8팀 SE 브래킷 매니저
  - 8강 4매치 (금) → 4강 2매치 (토) → 결승 (일). 시드: L1 vs I4 / L2 vs I3 / L3 vs I2 / L4 vs I1 (high-low intercross).
  - `_on_day_advanced` 가 INTL 페이즈 첫 월요일 bootstrap. `current_tournament.type = "INTL"` 로 Phase 7 PLAYOFF 와 구분.
  - `_on_match_day_reached` → AI 매치는 `simulate_ai_match()` 즉시 실행 (`team_avg_stat` 가 team_id 100 이상이면 intl_pilots 풀 사용). 플레이어 매치는 SeasonHub 위임.
  - F 결과 기록 시 `phase_results[phase] = {intl_played, intl_champion}` 갱신. REGULAR_INTL 한정 mid-bracket 플레이어 탈락 시 `intl_failed_campaign` 발동 (8강·4강에서 진 경우 곧바로 게임오버).
  - 시그널: `intl_started(phase)` / `intl_completed(phase, champion)` / `intl_failed_campaign(phase)`.
- [x] `CalendarSystem.is_match_day()` 가 INTL 페이즈도 true 반환 → `match_day_reached` 발동
- [x] `SeasonHub` 라우팅 확장
  - `Screen.INTL_BRACKET`, `Screen.ENDING` 추가 + `_ensure_intl_bracket_view()`, `_ensure_ending_view()`
  - `_maybe_launch_next_match_today()` 우선순위: INTL > PLAYOFF > LEAGUE
  - `pending_match.source = "intl"` → `_apply_intl_result()` → `InternationalTournament.record_result()`
  - `_on_intl_completed`: REGULAR_INTL 우승 → `Screen.ENDING`, REGULAR_INTL F 패배 → `Screen.GAME_OVER`
  - `_on_intl_failed_campaign`: REGULAR_INTL mid-bracket 탈락 → `Screen.GAME_OVER`
  - `_consume_pending_match_result` 후 라우팅 보정: 시그널 핸들러가 이미 ENDING/GAME_OVER 로 갔으면 HUB 로 덮어쓰지 않음
- [x] `features/season/tournament/IntlBracketView.gd` — 8팀 브래킷 시각화 (`Screen.INTL_BRACKET`)
  - 4 QF 좌측 스택 + 2 SF 중앙 + F 우측. 각 매치 패널에 슬롯/일자/팀명/승자 강조. 플레이어 매치 골드 보더, 종료된 매치 그린 보더.
  - 헤더: 페이즈 / 토너먼트 단계 (8강/4강/결승) / 다음 매치
- [x] `features/season/EndingView.gd` — "WORLD CHAMPION" + 6대회 phase_results 요약 (각 페이즈 우승팀, 우리 팀이 우승한 페이즈는 ★) + 최종 5인 로스터 + "다시 시작"
- [x] `GameOverView` 분기: REGULAR_INTL 패배 시 "최종 국제대회에서 우승하지 못했습니다." + 캠페인 우승 횟수 표시
- [x] `HubView`
  - 세 번째 액션 버튼: INTL 활성 시 "국제대회" → `Screen.INTL_BRACKET`, PLAYOFF 활성 시 "플레이오프", 외엔 "리그 순위"
  - `intl_started` / `intl_completed` 토스트
  - `_on_match_day_reached` 토스트가 활성 토너먼트 타입에 따라 매치 정보 분기
- [x] `MatchFlow._team_roster()`: `team_id >= 100` 이면 `season_state.intl_pilots` 풀 사용
- [x] `TournamentManager._on_phase_changed` 이 자기 (PLAYOFF) 브래킷만 clear 하도록 수정 — INTL 브래킷은 `InternationalTournament` 가 관리
- [x] `GameEnums.TournamentStage` 에 `INTL_QF`, `INTL_SF`, `INTL_F` 추가
- [x] `scenes/Season.tscn` 에 `InternationalTournament` 노드 추가

### 의존성
- Phase 7 (플레이오프 인프라 재사용 — `simulate_ai_match`, `pending_match` 라우팅, BracketView 패턴)

### 검증
- 1~4위 진입 시 INTL 부트스트랩, 1주만에 8강(금) → 4강(토) → 결승(일) 처리
- 각 INTL 페이즈 우승 / 패배 모두 다음 LEAGUE 페이즈로 정상 전이 (REGULAR_INTL 외)
- REGULAR_INTL 우승 → ENDING 화면 (6대회 기록 + 최종 로스터)
- REGULAR_INTL 8강·4강·결승 패배 → GAME_OVER 화면 ("최종 국제대회에서 우승하지 못했습니다")
- TrainingView 의 INTL 매치데이 셀이 잠기는지 (`player_has_match_on_weekday_this_week` 가 active bracket 도 스캔)
- "Project → Tools → Rebuild game.db" 후 intl_teams (4행) / intl_players (20행) 갱신

### 알려진 한계 / 미해결
- 가상 INTL 팀 스탯이 캠페인 동안 변하지 않음 (현재 스탯 모델 단순 유지 정책의 연장).
- 세이브/로드 미구현 (캠페인 1회차 일관 플레이가 v1 목표).
- INTL 매치데이 동안 같은 날 4매치 (8강) 가 모두 한꺼번에 표시되는 바, 사용자 매치 1건만 BattleSim 진입하고 나머지 3건은 백그라운드 즉시 시뮬됨 → UI 상 토스트 1회만 발동.

---

## 부록 — 미해결/추후 결정 사항

- **세이브/로드**: Phase 1~8에 포함하지 않음. 캠페인 1회차 일관 플레이가 v1 목표. 세이브는 v2.
- **AI 팀 훈련**: AI 팀 스탯이 시즌 동안 변하지 않음 (현재 안). 변동 도입 시 별도 phase.
- **트레이드/이적 시스템**: spec에 없으므로 v1 미포함. 잔여 20명 FA 풀이 있다는 컨셉은 v2 후보.
- **퍼지(컨디션/피로도)**: 스탯 모델 단순 유지로 인한 미포함. 사용자가 깊이를 원하면 추후 mental 스탯에 컨디션 의미 부여.
