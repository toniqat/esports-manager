# 아웃게임 메타 개발 계획서 — 로그라이트 런 · 컬렉션 · 감독 · 스태프 · 특성

> 작성일 2026-10-06 · 원본 기획 `docs/esports-manager-outgame.md`
> 대상 `autoloads/` · `features/save_load/` · `features/season/` · `features/match_flow/`
> · `features/battle_sim/`(특성 훅만) · `data/csv/` · `resources/`
> 상태: **진행 중 — M0 완료, 다음 M1.** 정식 문서는 `CLAUDE.md` / 각 폴더 `README.md` 이며, 이 파일은
> 마일스톤이 끝날 때마다 맨 아래 **§9 구현 기록**에 달라진 점을 적는 이력 문서다.

---

## 0. 확정된 결정 사항 (질의응답 결과)

| 항목 | 결정 |
|---|---|
| 계획 범위 | **오프라인 메타까지.** 런 구조 · 컬렉션 · 레벨 · 돌파 · 샐러리캡 · 감독 · 스태프 · 특성 · 점수 · 재화를 **로컬 저장**으로 구현. 가챠 · 주간패스는 로컬 시뮬레이션. 유료 패스 · 랭킹 · 결제는 "서버 필요"로 마지막 단계에 기술만 |
| 캠페인 구조 | **현행 6페이즈(≈33주) 유지.** 기획서의 "런 30분~1시간"은 이번 계획에서 고려하지 않는다 |
| 게임오버 | **기획서대로 강화** — 모든 리그 페이즈의 플레이오프와 모든 INTL 에서 **우승하지 못하면 즉시 런 종료**(진출 실패 포함). 6개 대회 전부 우승 = 엔딩 |
| 세이브 | **프로필 1 + 진행 런 1.** 3슬롯 구조는 폐지 |
| 컬렉션 대상 | **네임드 25인 = 수집 대상.** 모브 15인은 수집 불가(AI 팀 머릿수 전용) |
| 팀 선택 | 런 시작 시 **8팀 중 하나 = 예산 · 초기 스태프 · 시작 시설 패키지**를 고른다. 선수는 내 컬렉션 5인 |
| AI 로스터 | 내 5인을 뺀 나머지 선수(네임드 + 모브)를 **매 런 랜덤으로 7개 AI 팀에 분배** — 런마다 적 구성이 달라진다 |
| 감독 스탯 신규 시스템 | **넷 다 포함** — 지식(메크 숙련도) · 멘탈(면담 · 외출 · 신뢰도 · 사건) · 분석(상대 전력 공개) · 관리(팀 예산 · 시설). 훈련 · 전술은 기존 훈련 타일판에 연결 |
| 특성 효과 범위 | **인게임 훅 포함** — 아웃게임 수치뿐 아니라 BattleSim 규칙(전략 포인트 · 덱 · 드로우 등)에 개입하는 특성도 허용, `match_ctx` 로 전달 |
| 우선순위 | **런 루프 우선** — 세이브 → 런 준비 → 런 종료/점수 → 감독 스탯 연결 시스템 → 특성 → 감독 성장 → 수집 경제 |
| 시나리오 | **데이터 구조 + 2개**(저캡 / 고캡). 기믹 시나리오와 시나리오 보너스 특성은 후속 |

---

## 1. 현황 대비 차이 (Gap)

| 기획 항목 | 현재 코드 | 차이 / 할 일 |
|---|---|---|
| 런 = 컬렉션에서 5인 선정 | `TeamDraft` 가 네임드 25인 중 역할별 1명을 골라 **팀 0 과 맞교환**(`apply_draft`) | 풀을 "보유 컬렉션"으로 제한, 맞교환 대신 **AI 로스터 랜덤 재분배**, 샐러리캡 검증 추가 |
| 8팀 중 팀 선택 | `init_season(player_team_id = 0)` 고정, `teams.csv` 는 이름만 | 팀 선택 화면 + `teams.csv` 에 예산 · 스태프 · 시설 컬럼 |
| 정규 → PO → 월즈, 우승 실패 = 게임오버 | 6페이즈, PO **진출 실패** 또는 **REGULAR_INTL** 패배만 게임오버 | `_on_playoff_failed` / `_on_intl_completed` 판정 강화(§3 M2) |
| 런 종료 점수 · 재화 · 업적 | 없음. `EndingView` / `GameOverView` 는 "로비로 / 다시 시작"(둘 다 `run.save` 삭제)뿐 | 런 결과 정산 화면 + 프로필 반영 |
| 선수 레벨 1~10 · 샐러리 · 돌파 | `PlayerData` 에 스탯 6개 · 스킬 · 카드만 | `players.csv` 에 샐러리 · 등급, 레벨/돌파 표 신설 |
| 감독 · 스태프 스탯 6종 | 없음 | 감독/스태프 데이터 + **최댓값 커버** 판정 |
| 훈련 · 전술 → 훈련 해금 | 훈련 타일 15종, 등급 D~S(`grade` 0..4)와 **등급별 배치 상한**이 이미 있다 | 훈련 스탯 → 등급 상한 / 효과, 전술 스탯 → 사용 가능한 타일 종류 수 |
| 지식 → 메크 숙련도 | 없음. 밴픽에서 `assigned_mech` 만 정한다 | 선수 × 메크 숙련도 신설, MatchFlow 에서 로스터 사본에 보정 |
| 멘탈 → 면담 · 외출 · 사건 | 기자회견(`press/`)이 **임시 데이터 틀**로만 있다 | 신뢰도 · 면담 · 외출 · 사건 시스템 신설, 기자회견 선택지와 연결 |
| 분석 → 상대 전력 | MatchFlow PREP 에서 로스터 확인만. 상대 AI 오판 확률(`enemy_misjudge_chance`)은 리그 순위로 결정 | 분석 수치에 따른 정보 공개 단계 |
| 관리 → 예산 · 시설 | 없음 | 주간 수지, 스태프 연봉, 시설 레벨/유지비 |
| 감독 특성 · 보너스 점수 | 없음 | 특성 표 · 장착 · 해금 조건 · 인게임 훅 |
| 감독 레벨 · 전문화 · 프레스티지 · 프리셋 | 없음 | 프로필 레벨 진행 |
| 가챠 · 주간패스 · 재화 | 없음 | 로컬 시뮬레이션 |
| 세이브 | ✅ M0 — `user://profile.save` + `user://run.save`, 자동 저장 4지점 유지 | — |

---

## 2. 아키텍처

### 2.1 두 층의 상태
| 층 | 수명 | 위치 | 내용 |
|---|---|---|---|
| **Profile** (계정) | 영구 | 신규 오토로드 `ProfileManager` → `user://profile.save` | 컬렉션(보유 선수 · 레벨 · 돌파), 감독(타입 · 레벨 · EXP · 전문화 분배 · 프레스티지), 보유/해금 특성, 프리셋, 재화, 주간패스 진척, 업적(POM · 진엔딩 등), 런 기록 |
| **Run** (런) | 런 시작 ~ 종료 | 기존 `GameManager.season_state` → `user://run.save` | 지금의 캠페인 상태 전부 + 런 설정 스냅샷(시나리오 · 팀 · 장착 특성 · 감독 스탯 · 스태프) + 런 전용 상태(숙련도 · 신뢰도 · 예산 · 시설 · 보너스 점수) |

- 런 시작 시 프로필에서 **스냅샷을 복사**해 `season_state["run_setup"]` 에 고정한다 — 런 중 감독 스탯 변경 불가 규칙이 구조로 보장된다.
- 런 종료 시 `RunResult` 정산이 **프로필에만** 쓰고 `run.save` 를 지운다. 선수 성장 초기화는 "런 상태를 버린다"로 자연히 성립한다.
- `ProfileManager` 는 오토로드이므로 `class_name` 을 달지 않는다(`CLAUDE.md` Critical Patterns).

### 2.2 신규 폴더 (제안 — 착수 시 사용자 확인 후 생성)
```
features/
├── meta/                     ← 런 밖의 아웃게임 (로비)
│   ├── README.md
│   ├── lobby/                ← 메인 메뉴 (런 시작 / 이어하기 / 컬렉션 / 감독 / 특성 / 가챠 / 패스)
│   ├── run_setup/            ← 시나리오 → 팀 → 감독 프리셋 → 5인 편성(샐러리캡) → 시작
│   ├── run_result/           ← 런 종료 정산 (점수 · 재화 · 감독 EXP · 해금 특성 · 업적)
│   ├── collection/           ← 선수 목록 · 레벨 조정 · 돌파 정보
│   ├── manager/              ← 감독 스탯 분배 · 프리셋 · 프레스티지
│   ├── traits/               ← 특성 목록 · 장착 · 제작
│   └── shop/                 ← 가챠 · 주간패스 (로컬)
└── season/
    ├── staff/                ← 감독+스태프 유효 스탯 판정(커버 규칙) — 런 안의 단일 진입점
    ├── mental/               ← 신뢰도 · 면담 · 외출 · 사건
    ├── finance/              ← 주간 수지 · 시설
    └── (mastery 는 match_flow/ 쪽 — 아래 M4)
features/battle_sim/trait/    ← 인게임 특성 훅 (MechSkillSystem 과 같은 KEY_* 패턴)
```

### 2.3 유효 스탯 판정 — 한 함수
감독 스탯을 읽는 모든 자리는 `StaffSystem.effective(stat) -> int` 하나를 거친다.
```
effective(stat) = max(감독[stat] + 일시 보정, 어시스턴트[stat], 담당 일반 스태프[stat])
```
- 일반 스태프는 **분야당 1명**, 어시스턴트 매니저는 팀에 1명(여러 스탯 보유), 여러 빈자리를 동시에 메우는 것은 감독만.
- 멘탈은 예외: 면담 · 외출은 **감독 값만**, 사건 처리만 스태프 값을 쓴다(`effective_for_incident`).
- "누가 담당하는가"(`owner(stat)` → `manager` / `assistant` / `staff`)도 같은 곳에서 답해 **자동/수동 분리**(기획서 §8 검토 제안)의 근거가 된다.

### 2.4 데이터 표 (신설 / 변경)
| 표 | 상태 | 컬럼(초안) |
|---|---|---|
| `players.csv` | 변경 | `+ salary`(Lv1 기준) `+ rarity` `+ collectible`(네임드 1 / 모브 0 — 지금의 `is_mob` 와 겹치므로 `is_mob` 재사용 검토) |
| `pilot_levels.csv` | 신설 | `level`(1..10) · `stat_bonus` · `salary_bonus` — **모든 선수 공통**(기획서 "레벨당 효율 동일") |
| `pilot_breakthrough.csv` | 신설 | `pilot_id` · `stage`(1..5) · `kind`(`stat_flat` / `stat_growth` / `salary_down` / `card_swap`) · `value` |
| `scenarios.csv` | 신설 | `id` · `name` · `salary_cap` · `desc` · `trait_mods`(시나리오 보너스 특성 수치 변동, 후속) · `recommended_traits` |
| `teams.csv` | 변경 | `+ budget` · `+ facility_level` · `+ staff_ids`(`\|`) · `+ manual_areas`(팀 선택 화면 표시용) |
| `staff.csv` | 신설 | `id` · `name` · `job`(`coach_training` / `coach_tactics` / `coach_knowledge` / `analyst` / `finance` / `assistant`) · 스탯 6개 · `salary` |
| `manager_types.csv` | 신설 | `type`(운영형 / 실전형) · 초기 스탯 6개 |
| `manager_levels.csv` | 신설 | `level`(1..25) · `exp_required` |
| `traits.csv` | 신설 | `id` · `key`(런타임 분기) · `name` · `rarity`(0..4) · `polarity`(+/-) · `bonus_cost`(+ 소모 / - 제공) · `layer`(`outgame` / `ingame`) · `p1` · `p2` · `unlock`(조건 식) · `default_owned` · `craft_cost` · `desc` |
| `facilities.csv` | 신설 | `level` · `upkeep` · `train_exp_pct` · `upgrade_cost` |
| `mental_events.csv` | 신설 | 면담 · 외출 · 사건 대사와 선택지, 신뢰도/보정 결과 |
| `game_config.csv` | 변경 | 숙련도 · 신뢰도 · 예산 노브(아래 각 마일스톤) |

표를 더할 때마다 `addons/csv_to_db/csv_to_db.gd` 의 `SCHEMAS` + `TABLE_DEFS` 를 고치고 **Rebuild game.db** (`data/README.md`).
**구체 수치(레벨당 상승량, 캡, 비용 등)는 기획서 "범위 외"이므로 전부 자리표시 값으로 넣고** `game_config` / CSV 에서 조정한다.

---

## 3. 마일스톤

각 마일스톤은 **플레이 가능한 상태로 끝난다**(앞 단계만으로 런 한 판이 돈다).

### 진행 상황
| 마일스톤 | 상태 | 완료일 | 비고 |
|---|---|---|---|
| M0 세이브 구조 전환 | ✅ 완료 | 2026-10-06 | §9 구현 기록 |
| M1 런 준비 | ⏭ 다음 | | 착수 전 §8 #3 · #4 확정 |
| M2 런 종료 | ⬜ 대기 | | |
| M3 감독 · 스태프 | ⬜ 대기 | | |
| M4 지식 — 메크 숙련도 | ⬜ 대기 | | |
| M5 분석 — 상대 전력 | ⬜ 대기 | | |
| M6 관리 — 예산 · 시설 | ⬜ 대기 | | |
| M7 멘탈 | ⬜ 대기 | | |
| M8 감독 특성 | ⬜ 대기 | | |
| M9 감독 성장 | ⬜ 대기 | | |
| M10 수집 경제 | ⬜ 대기 | | |
| M11 서버 (범위 밖) | — | | |

### M0. 세이브 구조 전환 — 프로필 1 + 런 1 ✅
- `ProfileManager` 오토로드 신설(`project.godot` 등록), `user://profile.save` (`version: 1`).
- `SaveSystem` 을 슬롯 인덱스 대신 `save_run()` / `load_run()` / `delete_run()` / `has_run()` 으로 바꾼다. `active_save_slot` 제거.
- 자동 저장 4지점(드래프트 후 → **런 시작 후**, 밴픽 전, 밴픽 후, 주 마감)과 경기 중 이어하기(`match_resume`)는 그대로.
- `TitleScreen` → **로비**(`features/meta/lobby/`): `이어하기`(런 있을 때) / `새 런` / 이후 마일스톤에서 메뉴 추가. 새 런을 누를 때 진행 중 런이 있으면 **포기 확인**(포기 = 실패 정산, M2 이후).
- 기존 3슬롯 파일: 개발 단계이므로 **읽지 않는다**(마이그레이션 없음). 필요해지면 slot0 → run.save 1회 변환만 추가.
- 문서: `features/save_load/README.md` 전면 갱신, `CLAUDE.md` 의 "Save / load" 한 줄 수정.

### M1. 런 준비 — 시나리오 · 팀 · 5인 편성 · 샐러리캡 · AI 로스터
1. **시나리오 선택** — `scenarios.csv` 2행(저캡 / 고캡).
2. **팀 선택** — 8팀 카드: 팀명 · 예산 · 시설 · 스태프 구성 · "직접 해야 하는 일"(`manual_areas`). 예산이 높을수록 쉬움.
3. **감독 프리셋 확인** — M3/M9 전까지는 감독 타입 기본값 표시만.
4. **5인 편성** — 기존 `TeamDraftView` 재사용(PICK ↔ CONFIRM, 역할 고정 5칸). 바뀌는 것:
   - 격자 = **보유 컬렉션**만(`get_pool_grid()` 한 곳에서 필터).
   - 칸마다 **레벨 선택**(1 ~ 달성 최대 레벨), 레벨 → 스탯 · 샐러리 즉시 반영.
   - 상단에 **샐러리 합계 / 캡** 게이지. 초과 시 "게임 시작" 비활성(`validate_draft` 가 캡도 검사 — 규칙은 고를 때 보인다).
5. **AI 로스터 생성** — `apply_draft` 의 맞교환을 대체:
   - 역할별로 "내 5인을 뺀 나머지"(지금 데이터 기준 역할당 7명 = 네임드 4 + 모브 3)를 섞어 7팀에 1명씩. 40 = 8팀 × 5 이라 정확히 맞는다.
   - 시드 = 런 시드(`season_state["run_seed"]`) — 세이브 재현성.
   - 컬렉션이 늘어 역할당 인원이 7을 넘으면 네임드/모브 비율 규칙으로 7명을 뽑는다(그때 결정).
   - 선수의 `team_id` 는 **런 사본에서만** 덮어쓴다(CSV 값은 기본 소속 표시용).
- 프로필 초기값: 네임드 중 **역할별 1명씩 5인 보유**(기본 지급, 자리표시), 레벨 1.
- `init_season(player_team_id)` 에 `run_setup` 을 받게 확장.
- 문서: `features/season/draft/README.md`, `features/season/README.md`(Entry point), `data/README.md`.

### M2. 런 종료 — 게임오버 강화 · 점수 · 재화 · 업적
- **판정 강화**: 리그 페이즈의 플레이오프 결승 패배 / 4강 탈락 → 즉시 `GAME_OVER`. `PRESEASON_INTL` · `MIDSEASON_INTL` 도 우승 실패 시 `GAME_OVER`(지금은 토스트 후 계속). `TournamentManager` 에 `playoff_lost` 시그널 추가, `InternationalTournament.intl_failed_campaign` 을 모든 INTL 에서 발사.
- **점수** = 진척 점수(도달 페이즈 · 승수 · 우승 수) + 보너스 점수 반영(M8 전까지 0). 공식은 `game_config` 노브.
- **정산 화면**(`features/meta/run_result/`): 점수 · 재화 · 감독 EXP(M9 전까지 누적만) · 이번 런 업적. `EndingView` / `GameOverView` 의 "다시 시작" → 정산 → 로비.
- **업적**: POM(경기별 최고 선수 — BattleSim 결과에 선수별 기여 지표가 필요하므로 `match_ctx` 결과 페이로드에 킬/딜 집계 추가), 시즌 최고의 선수, 진엔딩(M7).
- 실패해도 재화 · 해금 특성 지급(기획서 확정 사항).
- 문서: `features/season/README.md`(Tournament lifecycle · 게임오버), `features/meta/README.md`.

### M3. 감독 · 스태프 스탯 + 커버 규칙 + 훈련/전술 연결
- `staff.csv` · `manager_types.csv` · `teams.csv.staff_ids`. 런 시작 시 팀의 스태프와 감독 스탯을 `run_setup` 에 스냅샷.
- `features/season/staff/StaffSystem.gd` — §2.3 `effective()` / `owner()`.
- 감독 타입 선택(운영형/실전형) — 첫 프로필 생성 시, 이후 프레스티지 때(M9).
- **훈련 스탯** → 훈련 타일 **등급별 배치 상한**과 타일 EXP 배율(`TrainingTile` 의 등급 표가 상한을 감독 스탯에서 읽게).
- **전술 스탯** → 판에 올릴 수 있는 **타일 종류 수 / 등급 해금**.
- 허브에 "스태프" 패널(누가 무엇을 맡는지, 내가 직접 하는 영역 표시).
- **일시 보정 이벤트**: `season_state["staff_mods"]` = `[{stat, delta, weeks_left}]`, 주 마감에 감소.
- 문서: `features/season/training/README.md`, 신규 `staff/README.md`.

### M4. 지식 — 메크 숙련도
- `season_state["mech_mastery"]` = `pilot_id → {mech_id → int}` (런 한정, 종료 시 소멸).
- 획득: 그 메크로 경기 출전, 훈련(지식 스탯이 배율), 새 메크 적응은 낮은 값에서 시작.
- 효과: MatchFlow 가 밴픽 배정 직후 **로스터 사본의 스탯에 숙련도 보정**을 얹어 `match_ctx` 로 보낸다 → **BattleSim 은 수정하지 않는다.**
- 밴픽 배정 단계 / `MechDetailPanel` 에 숙련도 표시.
- 기획서의 "선수 파편 스킬"은 정의가 없어 **보류**(§8 미결).
- 문서: `features/match_flow/README.md`, `ban_pick/` README.

### M5. 분석 — 상대 전력 공개
- MatchFlow PREP 의 상대 로스터 정보량을 `effective("analysis")` 단계로 나눈다: 이름/역할 → 스탯 → 메크 숙련도 상위 → 파일럿 카드 3장.
- 밴픽에서 상대의 선호 메크(숙련도 상위) 표시 단계.
- 현재 상대 AI 의 `enemy_misjudge_chance` 와는 분리(그건 상대의 능력이지 내 정보가 아니다).
- 문서: `features/match_flow/match_prep/` README.

### M6. 관리 — 팀 예산 · 시설
- `season_state["finance"]` = `{balance, weekly_income, history}`. 주 마감(`SeasonHub._end_week`)에 수입(팀 예산 · 성적 보너스) - 지출(스태프 연봉 · 시설 유지비) 정산.
- 시설 레벨 → 훈련 EXP 배율 등. 업그레이드는 허브에서 예산 소모.
- **깊이 단계**(기획서 §8): 관리 담당이 스태프면 자동 배분, 감독이 직접이면 영역별 배분 슬라이더(수동, 잘하면 더 이득). 저예산 전용 도구(스폰서 · 유지보수 연기 · 연봉 재협상)는 M6 후속.
- 잔고 음수 페널티 규칙은 수치 결정 때 확정.
- 문서: 신규 `finance/README.md`, `calendar/README.md`(주 마감 순서).

### M7. 멘탈 — 신뢰도 · 면담 · 외출 · 사건 · 진엔딩
- `season_state["trust"]` = `pilot_id → int`. 오르는 곳: 면담, 기자회견 선택지, 사건 대응.
- **면담**: 허브에서 주 N회(감독 멘탈 스탯 비례), 감독 전용.
- **외출**: 신뢰도 문턱 이상부터 가능, 주 1회 슬롯. 선수별 외출 횟수 기록.
- **사건**: 주 마감 랜덤 이벤트(부상 · 슬럼프 · 갈등 등 일시 스탯 보정), 처리에는 `effective_for_incident()`.
- **진엔딩**: 외출 5회 + 우승 → 프로필 업적에 기록, 정산 화면에 연출. "리그 우승"의 판정 시점은 §8 미결.
- 감독 타입(운영형 남 / 실전형 여)에 따른 대사 분기 — `mental_events.csv` 에 `manager_type` 컬럼.
- 기자회견(`press/`)의 임시 데이터를 이 표로 옮긴다.
- 문서: 신규 `mental/README.md`, `press/README.md`.

### M8. 감독 특성 · 보너스 점수 (인게임 훅 포함)
- `traits.csv`, 프로필의 `owned_traits` / 런 설정의 `equipped_traits`.
- **보너스 점수** = Σ(부정 특성 제공) − Σ(긍정 특성 소모), **0 미만이면 장착 불가**(편성 단계에서 막음).
- 효과 계층:
  - `outgame` — `StaffSystem` 보정, 훈련 EXP, 예산, 신뢰도 등. 시즌 측 각 시스템이 `TraitSystem.mod(key)` 를 읽는다.
  - `ingame` — `match_ctx["traits"]` = `[{key, p1, p2}]` 로 BattleSim 에 전달, `features/battle_sim/trait/TraitHooks.gd` 가 `KEY_*` 분기(메크 패시브 `MechSkillSystem` 과 같은 패턴). 첫 묶음은 개시 전략 포인트 · 드로우 · 덱 구성처럼 **개시 시점** 훅만, 턴 중 훅은 후속. 오케스트레이터 경유 규칙(`_bs.*`) 준수.
- **해금 조건**: 런 중 조건 충족 → 정산에서 해금(다음 런부터 장착). 조건 식은 `unlock` 컬럼(예: `finance_manual_profit`, `win_streak:5`). 수동 운영 경험 ↔ 특성 해금 연결(기획서 §8).
- 레어리티 5단계, 시나리오별 추천 특성 표시.
- 문서: 신규 `features/meta/traits/README.md`, `features/battle_sim/trait/README.md`, `battle_sim/README.md` 모듈 표.

### M9. 감독 성장 — 레벨 · 전문화 · 프레스티지 · 프리셋
- 레벨 1~25, 런 진척으로 EXP. 레벨업마다 스탯 1점 → **전문화 포인트**, 런과 런 사이에만 재분배(총합 고정).
- **프레스티지**: Lv25 에서 Lv1 회귀 + 전문화 포인트 초기화 + 타입 재선택, **시즌당 1회**. 오프라인이므로 "시즌"은 `seasons.csv`(시작일/종료일) + 기기 시각으로 판정 — 시계 조작 대응은 서버 단계로 미룬다.
- **프리셋**: (전문화 분배 + 특성) 기본 5개, 프레스티지 시 기존 프리셋 → 프레스티지 프리셋(현재 포인트로 재설정 전 사용 불가), 일반 1개 신규 자동 장착, 최대 10.
- 프리셋 저장 시 보너스 점수 < 0 조합 차단.
- 문서: `features/meta/manager/README.md`.

### M10. 수집 경제 (로컬) — 가챠 · 레벨업 · 돌파 · 주간패스
- **재화**: 아웃게임 재화(런 진척), 선수 레벨업 재화, 가챠권 2종, 특성 재료, 코스메틱 재화, 유료 재화(로컬 숫자만).
- **선수 가챠**(낮은 등급 풀) / **특성 가챠** — 확률표 CSV. 중복: 돌파 1~5, 6회차부터 가챠 재화로 변환 → 확정 구매 풀.
- **돌파 보너스** 적용 지점: 런 시작 스냅샷(스탯 고정치 · 샐러리 감소), 훈련 성장(성장치), 파일럿 카드 교체(`pilot_card_ids_for` 에 돌파 단계 반영).
- **특성 제작**: 재료로 고정 특성 제작.
- **주간패스(무료)**: Lv25, 런 점수 → 패스 EXP, 26+ 는 재화 변환, 주 단위 리셋(기기 시각).
- 코스메틱은 재화와 획득 기록만, 실제 스킨 적용은 범위 밖.
- 문서: `features/meta/shop/README.md`, `collection/README.md`.

### M11. (범위 밖 — 서버 필요) 유료 패스 · 랭킹 · 결제
기술만 남긴다: 계정 서버, 프로필 서버 저장(로컬 프로필 업로드 이전 경로), 결제 검증, 시즌 시계, 랭킹 점수 제출 검증, 유료 패스(여러 개 동시 · 영구 귀속 · 시즌 패스 점수 보너스 · 50% 페이백).

---

## 4. 세이브 스키마 초안

### `user://profile.save`
```json
{
  "version": 1,
  "collection": { "<pilot_id>": { "owned": true, "max_level": 1, "breakthrough": 0, "dupes": 0 } },
  "manager": { "type": 0, "level": 1, "exp": 0, "prestige": 0, "last_prestige_season": "", "alloc": { "training": 0, "tactics": 0, "knowledge": 0, "mental": 0, "analysis": 0, "finance": 0 } },
  "traits": { "owned": [], "unlocked_pending": [] },
  "presets": [ { "kind": "normal", "alloc": {}, "traits": [] } ],
  "active_preset": 0,
  "currency": { "outgame": 0, "levelup": 0, "gacha_ticket_pilot": 0, "gacha_ticket_trait": 0, "trait_mat": 0, "cosmetic": 0, "premium": 0, "pilot_shard": 0 },
  "pass": { "week_id": "", "exp": 0, "claimed": [] },
  "achievements": { "<pilot_id>": { "pom": 0, "mvp": 0, "true_ending": false } },
  "runs": [ { "scenario": 0, "team": 0, "score": 0, "result": "clear|fail", "phase_reached": 0, "at": "" } ]
}
```

### `user://run.save`
지금의 슬롯 파일(`meta` + `season_state`)과 같은 모양에, `season_state` 에 더한다:
`run_seed` · `run_setup`(`{scenario, team_id, manager_stats, staff, traits, bonus_points, pilot_levels}`) ·
`staff_mods` · `mech_mastery` · `trust` · `outings` · `finance` · `facility` · `run_stats`(POM 집계 · 업적 후보).
정수 키 딕셔너리(`mech_mastery`, `trust`, `outings`)는 기존 `_int_keyed_dict_in` 경로를 탄다.

---

## 5. 화면 목록 (신규 / 변경)

| 화면 | 위치 | 하단 바 |
|---|---|---|
| 로비 | `meta/lobby/` | `새 런`(1) / `이어하기`(2) — 런 없으면 `새 런` 전폭 |
| 시나리오 · 팀 선택 | `meta/run_setup/` | `뒤로`(1) / `다음`(2) |
| 5인 편성 (기존 드래프트 확장) | `season/draft/` | 기존 PICK / CONFIRM |
| 런 결과 정산 | `meta/run_result/` | `로비로` 전폭 |
| 컬렉션 · 감독 · 특성 · 상점 · 패스 | `meta/*` | 화면별 |
| 허브 확장(스태프 · 예산 · 면담 · 외출) | `season/HubView.gd` | 기존 유지, 행동은 카드 안 |

모든 화면: 색은 `OutgameTheme`, 주 행동은 `OutgameTheme.add_bottom_bar`, 배치 후 `docs/mobile_safe_area.md` 확인.

---

## 6. 테스트 · 검증 기준 (마일스톤 공통)
- 새 런 → 저장 → 앱 종료 → 이어하기가 같은 상태(시드 · AI 로스터 · 숙련도 · 신뢰도)로 복원.
- 런 종료 후 `run.save` 삭제, 프로필에 결과 반영, 선수 스탯은 다음 런에서 기본값.
- 샐러리캡 초과 편성이 "게임 시작"에서가 아니라 **편성 중**에 막힘.
- 커버 규칙: 같은 스탯에 감독/어시스턴트/스태프가 모두 있을 때 최댓값이 쓰이는지 단위 확인(헤드리스 스크립트).
- 인게임 특성: `match_ctx["traits"]` 가 비어 있을 때(단독 실행) BattleSim 동작이 지금과 동일.
- iOS 빌드에서 `user://profile.save` 쓰기/읽기 확인(`docs/ios_testbuild.md`).

---

## 7. 문서 갱신 체크리스트
- `CLAUDE.md`: Directory Map 에 `features/meta/` 와 시즌 하위 신규 폴더 한 줄씩, Feature Map 에 로비 행, "Save / load" 한 줄. **상세는 README 로.**
- 각 신규 폴더 `README.md` 생성, 기존 `season/` · `save_load/` · `match_flow/` · `battle_sim/` · `data/` README 갱신.

---

## 8. 미결 사항 (착수 전 / 해당 마일스톤 전 확정 필요)

| # | 항목 | 마일스톤 |
|---|---|---|
| 1 | 진엔딩의 "리그 우승" 판정 — 게임오버 강화로 생존한 런은 이미 모든 플레이오프를 이긴다. "외출 5회 달성 시점 이후의 첫 리그 우승" / "런 클리어 시 외출 5회" 중 무엇인가 | M7 |
| 2 | "선수 파편 스킬"(지식 스탯)의 정의 | M4 |
| 3 | 프로필 초기 보유 선수 구성(역할별 1명? 무작위? 선택?) | M1 |
| 4 | 저캡 / 고캡 시나리오의 캡 값, 레벨당 스탯 · 샐러리 상승치, 선수별 Lv1 샐러리 | M1 |
| 5 | 점수 · 재화 공식, 감독 EXP 곡선 | M2 / M9 |
| 6 | 잔고 음수(예산 파산) 처리 | M6 |
| 7 | 첫 특성 묶음 목록(기본 제공 · 해금형 · 인게임 훅) | M8 |
| 8 | 감독 타입별 초기 스탯, 감독 스탯 총합 | M3 |
| 9 | 6대회 전승 필수로 난이도가 급격히 높아지는 점 — 저예산 팀 · 저캡 시나리오 밸런스 점검 필요 | M2 이후 |
| 10 | ~~신규 폴더 구조(§2.2) 승인~~ — **승인됨**(M0, 2026-10-06) | M0 착수 시 |

---

## 9. 구현 기록
(마일스톤 완료 시 계획과 달라진 점을 여기에 적는다.)

### M0 — 세이브 구조 전환 (2026-10-06)
- §2.2 폴더 구조 승인. 이번에는 `features/meta/`(README) + `meta/lobby/` 만 만들었다.
- `TitleScreen` → `features/meta/lobby/LobbyScreen.gd`, `scenes/TitleScreen.tscn` → `scenes/Lobby.tscn`(main_scene). `SlotCard.gd` 삭제.
- **계획에 없던 것 — 테스트 런 파일**: 자동 저장은 항상 하되, 에디터에서 Season / MatchFlow 를 바로 실행하면 숨은 `user://run_test.save` 에 쓴다(`GameManager.use_test_run`, 기본 true, 로비가 false 로). 옛 `active_save_slot == -1` no-op 을 대체.
- 새 런 포기 확인은 **모달 팝업**(`meta/lobby/ConfirmPopup.gd`, 재사용 가능) — 두 번 탭 방식은 쓰지 않는다.
- 런 종료: `EndingView` / `GameOverView` 의 두 버튼이 `delete_run()` 후 이동(`로비로` / `다시 시작`). M2 정산은 이 삭제 직전에 끼운다.
- `ProfileManager` 는 M0 에서 생성 · 로드 · 기본값 채우기만(깨진 파일은 `.bak` 로 백업 후 기본값). 아직 쓰는 곳은 없다.
