# 아웃게임 메타 개발 계획서 — 로그라이트 런 · 컬렉션 · 감독 · 스태프 · 특성

> 작성일 2026-10-06 · 원본 기획 `docs/esports-manager-outgame.md`
> 대상 `autoloads/` · `features/save_load/` · `features/season/` · `features/match_flow/`
> · `features/battle_sim/`(특성 훅만) · `data/csv/` · `resources/`
> 상태: **M0 ~ M10 완료(2026-10-06). 남은 것은 M11(서버, 범위 밖)과 밸런스 점검.** 정식 문서는 `CLAUDE.md` / 각 폴더 `README.md` 이며, 이 파일은
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
| M1 런 준비 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §10 계약 |
| M2 런 종료 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §10 계약 |
| M3 감독 · 스태프 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §11 계약 |
| M4 지식 — 메크 숙련도 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §11 계약 |
| M5 분석 — 상대 전력 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §11 계약 |
| M6 관리 — 예산 · 시설 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §11 계약 |
| M7 멘탈 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §11 계약 |
| M8 감독 특성 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §12 계약 |
| M9 감독 성장 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §12 계약 |
| M10 수집 경제 | ✅ 완료 | 2026-10-06 | §9 구현 기록 · §12 계약 |
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
- 기획서의 "선수 파편 스킬"은 **기벽**으로 이름을 바꿔 정의했다(§8 #2) — 재화(`pilot_shard`)와 무관.
  - **런 한정 선수 패시브**, 긍정 효과만, 효과는 **스탯 보정만**(숙련도처럼 MatchFlow 가 로스터 사본에 얹는다 → BattleSim 수정 없음).
  - 0개로 시작, 칸 2개. **훈련 타일 · 메크 연구 카드**로 획득하면 무작위 기벽이 빈 칸에 **강제 장착**.
  - 별도 훈련으로 **재굴림**, 별도 훈련으로 칸을 **최대 5개**까지 확장.
  - **지식 스탯** → 좋은(고등급) 기벽이 뽑힐 가중치.
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
| 시나리오 · 팀 · 5인 편성 (기존 드래프트 확장) | `meta/run_setup/` | `뒤로` / `다음`, 편성은 PICK / CONFIRM |
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
| 1 | ~~진엔딩의 "리그 우승" 판정~~ — **런 클리어 + 외출 5회**(§11) | M7 |
| 2 | ~~"선수 파편 스킬"(지식 스탯)의 정의~~ — **기벽**(런 한정 긍정 스탯 패시브, §3 M4) | M4 |
| 3 | ~~프로필 초기 보유 선수 구성~~ — **역할별 2명 = 10인**(`players.starter`), 전원 Lv1 | M1 |
| 4 | ~~캡 · 레벨 수치~~ — 자리표시 값으로 확정(`scenarios.csv` · `pilot_levels.csv` · `players.salary`) | M1 |
| 5 | 점수 · 재화 공식 — 자리표시(`RUN_*` const 키), 감독 EXP 곡선은 M9. **헤드리스 런 시뮬로 페이즈 도달률 · 점수 분포를 뽑아 역산**하기로 결정 | M2 / M9 |
| 6 | ~~잔고 음수(예산 파산) 처리~~ — **음수 불가, 지출 강제 삭감**(§11) | M6 |
| 7 | ~~첫 특성 묶음 목록~~ — **24종**(`traits.csv`, §12) | M8 |
| 8 | ~~감독 타입별 초기 스탯, 감독 스탯 총합~~ — 1~20 척도, 자리표시(`manager_types.csv`, 총합 36) | M3 |
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

### M1 · M2 — 런 준비 · 런 종료 (2026-10-06)
기반 커밋(데이터 표 · `RunRules` · 컬렉션 API · §10 계약) 위에서 기능 5개를 워크트리 병렬로 개발해 병합했다.
- **런 준비**: 편성까지 `meta/run_setup/` 한 씬(`RunSetupScreen`, 단계 표 `STEPS`). `season/draft/` 는 옮기고 지웠다 — Season 은 HUB 부터, "런 시작 후" 자동 저장은 첫 HUB 진입(`SeasonHub._is_run_start`, 새 저장 키 없음).
- **계획과 달라진 점**
  - `init_season()` 은 이제 `start_run(default_run_setup())` 이다(가장 높은 캡 시나리오 · 팀 0 · 역할별 첫 스타터 Lv1). 에디터 직접 실행도 같은 길을 탄다. 테스트 런은 보유 검사 대신 "네임드면 허용".
  - `RunStats.record_match` 는 결과를 일정에 반영하기 **직전**에 부른다 — 반영이 곧바로 런 종료 정산(현재 페이즈 POM 마감)으로 이어질 수 있어서.
  - 경기 종료는 `BattleSim.end_match` 한 곳. 피해 · 보호막 · 회복 집계는 `apply_pilot_damage` / `grant_shield` / `apply_heal` 훅으로 모았다. `care` 는 **다른 아군**에게 준 보호막 흡수 + 회복만 센다(자기 자신 제외).
  - 킬은 킬 피드의 마지막 타격자에게 간다(미상이면 최다 피해자) — 예전에는 미상 킬이 집계되지 않았다.
  - INTL 우승 실패도 즉시 게임오버라 `intl_completed` 는 내가 우승할 때만, 두 시그널 모두 1회성이다.
  - 정산 결과에 `id`(중복 반영 방지) · `breakdown` · `pilots` 등 화면용 키가 더 붙었다. 프로필 `runs` 의 `result` 는 포기도 `"fail"`.
- **후속 결정 (같은 날)**: 점수의 페이즈 항은 **끝낸 페이즈만** 센다(`phases_cleared` — 실패 · 포기한 페이즈 제외, 클리어는 6). 결과 패널은 자기 CanvasLayer + 전체 화면 딤 + 불투명 판으로 옮겨, 전장 · 마커가 비치던 문제를 고쳤다.
- 시나리오 · 팀 단계는 **선택 없이 시작**한다(확정) — 플레이어가 카드를 직접 눌러야 `다음` 이 켜진다. 규칙을 읽지 않고 `다음` 연타로 넘어가지 않게.

### M3 ~ M7 — 감독 · 숙련도 · 분석 · 재무 · 멘탈 (2026-10-06)
기반 커밋(표 · `StaffSystem` · `PilotMods` · 스텁 · 허브 관리 카드 줄 · 훅 · §11 계약) 위에서 다섯 기능을
워크트리 병렬로 개발해 병합했다. 병합 충돌은 `const.csv` 끝 추가분뿐이었다(합집합).
- **M3**: 로비 첫 진입 감독 타입 팝업(`meta/lobby/ManagerTypePopup.gd`). 전술 → 등급 해금, 훈련 → 등급별
  상한(상한표 × 단계 %) · EXP 배율. 모든 훈련 배율은 `TrainingBoard.cell_exp()` 한 곳에서 곱한다.
  숙련도 타일 `T16` · `T17`(색 `M`, `exp` 에 `mastery:N`). 훈련 위임 팀에만 `코치 추천` 자동 편성.
  `TrainingTile.place_limit()` → `place_limit(training_stat)`.
- **M4**: `MechMastery` — 60명 × 메크 21 전부 초기화(주력 / 같은 역할군 / 그 외). **MatchFlow 로스터가 원본
  공유 참조였던 버그를 사본으로 고쳤다.** 밴픽 숙련도 태그 · 예상 픽(분석 ≥2) · 추천 밴(분석 위임) ·
  AI 숙련도 선호. 계약 밖 규칙: 상대 선수 획득엔 내 배율 미적용, 지식 위임이면 빈 연구 칸 자동 채움.
  `main_mechs` 를 역할군에 고르게 재분배.
- **M5**: `match_prep/OpponentIntel.gd`(공개 규칙 빌더) + `IntelView.gd`. PREP 을 흰 아웃게임 화면으로
  다시 짰다. 리그 순위표 줄 → 팀 상세 시트. `StaffPanel` 완성.
- **M6**: 흑자의 `FINANCE_RESERVE_PCT` 는 잔고, 나머지를 훈련 · 시설 적립 · 복지로. 효과는 지출 상한
  (`*_FULL_SPEND`)까지만 늘어 자동 균등 배분이 최적이 아니다. 파산 규칙: 배분 중단 → 잔고 → 적립금 →
  시설 강등(Lv1 이면 훈련 페널티). **슬라이더 대신 −/+ 스테퍼**(시트 스크롤이 드래그를 먹는다).
  `facilities.csv` 유지비 상향(적자가 날 수 있게).
- **M7**: `MentalEvents.gd`(문법 · 조건 · 판정), `press/MessengerView.gd`(공용 메신저 — 기자회견 · 면담 ·
  외출 · 사건). 모든 무작위는 `run_seed` + 주 + 요일 시드, 대화는 열기 전에 기록해 재진입 · 이어하기에도
  재굴림 · 중복 적용이 없다. 기자회견은 답 뒤 효과 칩을 보이고 탭으로 넘어간다(0.7초 자동 → 탭).
- **후속 과제**: 수치 전부 자리표시(밸런스 점검), 코치 추천이 단순(저스탯 팀은 `T02` 만), 치트 즉시
  결과는 숙련도 미지급, 시간 경과 화면이 숙련도 획득을 아직 표시하지 않음, 허브에 신뢰도 표시 없음,
  감독 관리 스탯은 담당자 판정 외 효과 없음, 부자 팀 잉여 잔고의 사용처(저예산 도구 후속).

### M8 ~ M10 — 특성 · 감독 성장 · 수집 경제 (2026-10-06)
기반 커밋(표 5개 · 프로필 v2 · `TraitSystem` / `ManagerProgress` / `PassSystem` · 런 시작 / 정산 연결 ·
탭 로비 뼈대 · §12 계약) 위에서 다섯 기능을 워크트리 병렬로 개발해 병합했다. 충돌은 `run_setup/README.md`
자동 병합뿐이었다.
- **A 특성 아웃게임**: `evaluate_unlocks`(§12.4 문법 전부, 헬퍼 `unlock_met` · `longest_win_streak` ·
  `max_outings`), 훈련 배율은 `TrainingBoard.exp_mult_table()`(돌파 `train_bonus_pct` 는 그 선수 열만),
  재무 `sponsor_income` / `upkeep_cost` + `finance.manual_profit_weeks`, 신뢰도는 오를 때만
  `max(0, delta + mod)`. StaffPanel 시트에 장착 특성, 정산 화면에 새 특성 · 성장 카드.
- **B 인게임 훅**: `features/battle_sim/trait/TraitHooks.gd`(`_bs.trait_hooks`) + 개시 배너. `cost_tick` 은
  `ECONOMY_START_TURN + k·p2`(k ≥ 1)에, `PHASE_THRESHOLD` 미만일 때만. 첫 카드 할인은 스냅샷 환불에 포함.
- **C 감독 탭 · 감독 단계**: 프리셋을 초안 사본으로 편집(저장 / 이 프리셋 사용), 프레스티지 프리셋은
  `재설정` 전 편집 불가, `ManagerTypePopup.open(prestige_mode, current_type)`. 런 준비 감독 단계의 특성 교체는
  유효할 때만 그 프리셋에 저장. 공용 `TraitPickerView` · `ManagerUi.unlock_text`.
- **D 컬렉션**: 직접 만든 셀(`CollectionCell`)과 상세 시트(돌파 표 · 레벨업). 레벨업은 확인 없이 즉시(버튼에 비용).
- **E 상점 · 패스**: `Gacha.pull`(가챠권 먼저, 모자란 만큼 재화, 10연 할인), `ShopCatalog`(파편 구매 · 제작 ·
  교환 · 개발용 유료 재화), `PassSystem.claim` + 헬퍼. **기반 수정**: `PassSystem.week_id_now` 가 UTC 가 아니라
  기기 시간대로 주를 판정(한국 기준 월 09시 리셋이던 것을 월 00시로).
- **통합 후 변경**: 보너스 점수를 **끝낸 페이즈 수에 비례**(`bonus × phases_cleared × RUN_SCORE_PER_BONUS`) —
  부정 특성만 달고 바로 포기하면 점수가 공짜로 들어오던 허점. 로비 토스트를 불투명 알약 + 자동 페이드로.
- **후속 과제**: 수치 전부 자리표시(특성 · 가챠 · 패스 · 레벨 곡선), 12장 손패 부채꼴 배치 미확인,
  `FinancePanel` 의 스폰서 배율 글자 · `TrainingView` 의 "훈련 효과 ×" 글자가 특성 배율을 아직 안 보여 줌,
  코스메틱 재화 사용처 없음(결정대로 기록만), 특성 레어리티별 색 통일(정산 카드는 앰버 고정).

---

## 10. M1 · M2 작업 계약 (2026-10-06 확정, 병렬 개발용)

질의응답으로 확정한 결정과, 기능별 병렬 작업이 서로 기대는 **인터페이스**. 기반 커밋이
데이터 표 · `RunRules` · `ProfileManager` 컬렉션 API · 스텁 씬/스크립트를 먼저 넣었다.

### 10.1 결정 (M1 · M2)
| 항목 | 결정 |
|---|---|
| 초기 보유 | 네임드 **역할별 2명 = 10인**(`players.starter = 1`), 전원 `max_level` 1. 레벨업 수단은 M10 |
| 수치 | 캡 · 레벨 · 샐러리 · 점수 공식 모두 **자리표시**(CSV / const) |
| 런 준비 위치 | **편성까지 전부 `meta/run_setup/`** — `season/draft/` 는 `meta/run_setup/` 으로 옮기고 지운다. Season 은 DRAFT 없이 HUB 부터 |
| 단계 | 시나리오 → 팀 → 5인 편성(레벨 · 캡). 감독 프리셋 단계는 M3/M9 까지 **생략**(단계 목록만 늘릴 수 있게) |
| 팀 패키지 | `teams.csv` 의 `budget` · `facility_level` · `manual_areas` · `desc` — **표시 · 스냅샷만**, 효과는 M3/M6 |
| AI 로스터 | 내 5인을 뺀 35명(고른 팀의 원래 선수 포함)을 역할별로 섞어 7개 AI 팀에 1명씩, `run_seed` 로 재현 |
| 게임오버 | 6개 대회 중 하나라도 우승 못 하면 즉시 종료(§3 M2) |
| 종료 흐름 | Ending / GameOver 연출 → **정산 화면**(`scenes/RunResult.tscn`) → 로비 |
| 정산 시점 | **GAME_OVER / ENDING 진입 즉시** 프로필에 쓰고 `run.save` 삭제. 테스트 런(`use_test_run`)은 화면만, 프로필 미반영 |
| 포기 | 로비에서 포기 = 그 시점 진척으로 **실패 정산**(`abandon`) → 정산 화면 → 런 준비 |
| 경기 MVP | **내 경기만**, **이긴 팀 5명 중** 지표 최고 1명. 경기 끝 → **MVP 전용 뷰(전신 일러스트)** → BattleSim 결과 화면에 MVP 한 줄 |
| MVP 지표 | d = max(데스, 1). 탑 · 정글 · 미드 · 원딜 = `W_KDA·(1.5k + a)/d + W_DMG·딜량/d` (+ 탑만 `W_TANK·받은 피해/d`). 서폿 = `W_KDA·(k + 1.5a)/d + W_SUP_CARE·(보호막 흡수 + 아군 회복 + 받은 피해)/d`. 가중치 `MVP_*` |
| 페이즈 POM | 6개 페이즈 각각 끝날 때 1명: `POM_W_MVP·(그 페이즈 MVP 횟수) + POM_W_SCORE·(그 페이즈 MVP 지표 합)` 최고 |
| 업적 | 프로필 `achievements[pid].mvp` += 경기 MVP 횟수, `.pom` += 페이즈 POM 횟수 — **내 선수만** |

### 10.2 런 시작 — `GameManager.start_run(run_setup) -> String`
```
run_setup = {
  "scenario": int, "team_id": int,
  "pilot_ids": Array[int],              # 5명, GameEnums.Role 순
  "pilot_levels": {"<pilot_id>": int},  # 5명 모두
  "salary_cap": int, "salary_total": int,
}
```
- 런 준비 화면은 `RunRules.validate_lineup(...)` 이 "" 일 때만 시작을 허락하고, `start_run` 이 `""` 를 돌려주면 `Season.tscn` 으로 간다.
- `start_run` 은 `init_season` → `run_seed` → 내 5인 `team_id = team_id` · `RunRules.apply_level` → 나머지 35명 AI 분배 → `team_rosters` 재구성 → `season_state.run_setup` 저장.
- 에디터에서 Season 을 바로 실행(`season_state.active == false`)하면 `init_season()` 기본 경로가 **스타터 중 역할별 첫 선수 Lv1** 로 기본 `run_setup` 을 만들어 같은 길을 탄다.
- `Season.tscn` 첫 HUB 진입이 "런 시작 후" 자동 저장 지점이다.

### 10.3 런 정산 — `RunResult.settle_current_run(outcome) -> Dictionary`
`outcome` = `"clear"` | `"fail"` | `"abandon"`. 한 런에 한 번만(`season_state.run_over`).
```
result = {
  "outcome": String, "scenario": int, "team_id": int,
  "phase_reached": int, "wins": int, "losses": int, "titles": int,
  "score": int, "bonus_points": 0,
  "currency": {"outgame": int}, "manager_exp": int,
  "mvp": {"<pilot_id>": int}, "pom": {"<phase>": pilot_id},   # 내 선수 기준 집계 포함
  "achievements": {"<pilot_id>": {"mvp": int, "pom": int}},
  "test_run": bool, "at": String,
}
```
- 순서: `RunStats.finalize_phase(지금 페이즈)` → 점수 계산 → (테스트 런이 아니면) `ProfileManager.apply_run_result(result)` + `SaveSystem.delete_run()` → `GameManager.last_run_result = result`.
- `season_state.run_over == true` 이면 `SeasonHub._autosave` 는 쓰지 않는다(정산 뒤 run.save 가 되살아나지 않게).
- 정산 화면 하단 바: 평소 `로비로`, 포기에서 왔으면 `새 런`(→ `RunSetup.tscn`). 구분은 `outcome == "abandon"`.

### 10.4 경기 통계 · MVP — `pending_match.pilot_stats` / `season_state.run_stats`
BattleSim 이 경기 끝에 `pending_match["pilot_stats"]` 를 채운다(단독 실행 = pending_match 없음 → 아무 일 없음):
```
pilot_stats = [ {"pilot_id": int, "side": 0|1 (0 = 내 팀), "role": int,
                 "k": int, "d": int, "a": int, "dmg": int, "taken": int, "care": int}, ... ]   # 10명
```
`care` = 그 선수가 아군에게 준 보호막이 실제로 흡수한 피해 + 아군 회복량(오버힐 제외). 경기 MVP 는
BattleSim 이 같은 지표(`RunStats.mvp_score(row)`, static)로 뽑아 `pending_match["mvp_pilot_id"]` 에 적고 MVP 뷰를 띄운다.

`season_state.run_stats` (모든 키 문자열):
```
{ "matches": [ {"phase": int, "won": bool, "mvp": pilot_id, "scores": {"<pid>": float}} ],
  "mvp_count": {"<phase>": {"<pid>": int}},
  "score_sum": {"<phase>": {"<pid>": float}},
  "pom_by_phase": {"<phase>": pilot_id},
  "wins": int, "losses": int }
```
- `RunStats.record_match(state, pending_match)` — `SeasonHub._consume_pending_match_result` 에서 승패 반영 직후 1회.
- `RunStats.finalize_phase(state, phase)` — 페이즈가 바뀔 때(`CalendarSystem` phase_changed) 직전 페이즈, 그리고 정산 때 지금 페이즈.

### 10.5 파일 소유 (병렬 작업)
| 작업 | 소유 |
|---|---|
| RunSetup UI (M1) | `features/meta/run_setup/*`(RunRoster 제외), `season/draft/` 이동 · 삭제, `Season.tscn` 의 TeamDraft 노드, `SeasonHub` DRAFT 화면 제거, `scenes/RunSetup.tscn` |
| RunCore (M1) | `GameManager.start_run` / `init_season` 기본 run_setup, `features/meta/run_setup/RunRoster.gd`, `SaveSystem`(필요 시) |
| GameOver (M2) | `features/season/tournament/*`, `SeasonHub` 게임오버 · 엔딩 · 자동 저장 처리, `EndingView` / `GameOverView` |
| RunResult (M2) | `features/meta/run_result/*`, `scenes/RunResult.tscn`, `ProfileManager.apply_run_result`, `LobbyScreen` 포기 처리 |
| MVP/POM (M2) | `features/battle_sim/**` 통계 · MVP 뷰 · 결과 화면, `features/season/run_stats/*`, `SeasonHub` 경기 결과 소비 지점 · 페이즈 전환 훅 |

CSV · `const.csv` · `game.db` 는 기반 커밋 소유 — 작업 중 값 조정이 필요하면 자기 키(`MVP_*` 등)만 고치고 병합 후 한 번 다시 굽는다.

---

## 11. M3~M7 작업 계약 (2026-10-06 확정, 병렬 개발용)

기반 커밋이 데이터 표 · `StaffSystem`(완성) · `PilotMods`(완성) · 시스템 스텁 · 상태 키 ·
허브 관리 카드 줄 · 주 마감/경기 결과 훅을 먼저 넣었다. 기능 작업은 **스텁의 몸통을 채우고
자기 화면을 만든다** — 시그니처를 바꾸지 않는다(바꿔야 하면 보고에 적는다).

### 11.0 결정 (질의응답)
| 항목 | 결정 |
|---|---|
| 스탯 척도 | 감독 · 스태프 스탯 **1~20**(FM식). 감독 타입 초기값은 자리표시(`manager_types.csv`, 총합 36, 고른 분배), 스태프 전문 스탯 10~17 |
| 감독 타입 선택 | **첫 프로필 생성 시 로비 팝업**(이후 변경은 M9 프레스티지). `ProfileManager.set_manager_type` / `manager_type_chosen` |
| 훈련 / 전술 | **전술 = 훈련 등급 해금**(D→C→B→A→S, 문턱 const), **훈련 = 등급별 배치 상한 + 타일 EXP 배율** |
| 자동 / 수동 | **일부 자동화** — 스태프(어시스턴트 포함)가 맡은 영역은 화면에 자동 버튼: 훈련판 자동 편성 · 연구 메크 자동 지정 · 분석 해석(추천 밴 · 한 줄 해설) · 예산 자동 배분. 자동안은 **무난한 규칙일 뿐 최적이 아니다**(수동 보너스 수치 없음) |
| 어시스턴트 매니저 | 예산 상위 팀(0 · 1)만 |
| 스태프 UI | 허브 관리 카드 + `HubSheet` 상세 시트. 런 준비 팀 카드는 **지금처럼 `manual_areas` 텍스트만** |
| 숙련도 효과 | 숙련도 0..100 → 등급(미숙/보통/능숙/마스터) → 선수 스탯 6종에 **등급별 고정치**(미숙은 음수). MatchFlow 가 로스터 **사본**에 얹는다 — BattleSim 무수정 |
| 숙련도 초기값 | `players.main_mechs`(네임드 2 · 모브 1, `intl_players` 도) — 주력은 높게, 나머지 낮게 |
| 숙련도 획득 | 그 메크로 경기 출전 · 주간 연구 메크(허브 「메크 연구」 카드) · 훈련판 숙련도 타일(색 `M`). 지식 스탯 · 시설이 배율 |
| AI 숙련도 | 주력 메크 기반 초기값 + **내 경기에 출전한 상대 선수만** 경기 반영. AI 밴픽은 숙련도 높은 메크를 선호 |
| 분석 | **단계적 공개**(`StaffSystem.analysis_tier` 0..3): 이름·역할 → 스탯(대략) → 숙련도 상위 메크 → 파일럿 카드 3장. MatchFlow PREP + **리그 팀 상세**. 밴픽에 상대 예상 픽 표시, 상대 주력 메크 밴 = 숙련도가 만드는 자연 패널티 |
| 예산 | `teams.budget` = **주간 스폰서 수입**. 주 마감 정산 = 수입(× 시설) + 성적 보너스 − 스태프 연봉 − 시설 유지비 |
| 배분 | 남는 예산을 **훈련 · 시설 · 복지** 3축으로. 관리 위임 = 균등 자동, 감독 직접 = 슬라이더 |
| 파산 | **잔고 음수 불가 — 지출 강제 삭감**(배분 → 시설 등급 순, 규칙은 finance README) |
| 저예산 도구 | 스폰서 계약 · 유지보수 연기 · 연봉 재협상은 **후속** |
| 시설 효과 | 훈련 EXP · 숙련도 획득 배율 · 사건 확률 감소 · 주간 수입 증가(`facilities.csv`) |
| 진엔딩 | **런 클리어 + 외출 5회**(그 선수). 정산 결과 `true_endings` → 프로필 `achievements[pid].true_ending` |
| 면담 · 외출 시점 | **월~금 요일 화면(시간 경과)** 마다 "오늘 저녁" 카드 — **하루 1행동**(면담 / 외출 / 패스). 면담은 주 N회(감독 멘탈 비례), 외출은 신뢰도 문턱 이상 · 주 1회 |
| 면담 | 메신저 대화 + 2~3 선택지(기자회견 화면 구조 재사용), 감독 멘탈이 높을수록 좋은 결과 확률 ↑ |
| 외출 | 외출 횟수 +1 · 신뢰도 + 작은 일시 보정(다음 경기까지) · 대가로 **다음 훈련일** EXP 일부 손실 |
| 사건 | 월~금 요일 화면에서 확률 발생(시설 · 복지가 낮춤) → 선택지, 결과는 `effective_for_incident` 로 판정, 효과는 선수 일시 보정 n주 |
| 신뢰도 효과 | **외출 해금 · 진엔딩만**(경기 수치 영향 없음) |
| 기자회견 | 대사를 `mental_events.csv`(kind `press`)로 옮기고, **범용 질문(팀 전체 신뢰도 ± / 감독 일시 보정) + 선수 언급 질문(그 선수 신뢰도 ±)** 을 섞는다 |
| 콘텐츠 양 | 구조 + 범용 자리표시(면담 5~8 · 외출 3~5 · 사건 6~8 · 기자회견 6~10). 감독 타입 분기는 컬럼만 + 일부 |
| 개발 방식 | 기반 커밋 + 기능별 워크트리 5개 병렬 → 병합. 검증 = 헤드리스 + 창 스크린샷. 기능별 커밋, main 병합까지(푸시 없음) |
| 폴더 | 숙련도는 `features/season/mastery/`(§2.2 의 "match_flow 쪽" 대신 — 상태 · 허브 카드가 시즌 쪽이라서) |

### 11.1 상태 키 (`season_state`, 모두 문자열 키 — 세이브 그대로 왕복, 숫자는 읽는 쪽이 `int()`)
| 키 | 모양 | 소유 |
|---|---|---|
| `run_setup.manager_type` · `.manager_stats` · `.staff` | `int` · `{stat: int}` · `[{id, name, job, stats{}, salary}]` | `StaffSystem.snapshot_for_run`(start_run) |
| `staff_mods` | `[{stat, delta, weeks_left, source}]` | `StaffSystem.add_mod / decay_mods` |
| `pilot_mods` | `[{pilot_id, stat("all" 가능), delta, weeks_left(-1 = 다음 경기까지), source}]` | `PilotMods` |
| `mech_mastery` · `mastery_research` | `{"<pid>": {"<mech>": int}}` · `{"<pid>": mech_id}` | `MechMastery` (M4) |
| `finance` | 자유(M6 이 README 에 적는다). `balance` · `facility_level` 키는 고정 | `FinanceSystem` (M6) |
| `trust` · `outings` · `mental` | `{"<pid>": int}` · `{"<pid>": int}` · 자유 | `MentalSystem` (M7) |

**주 마감 순서**(`SeasonHub._end_week`, 달력 전): `FinanceSystem.settle_week` → `MechMastery.settle_week`
→ `MentalSystem.end_week` → `StaffSystem.decay_mods` → `PilotMods.decay_week`.
`settle_week` 결과의 `toast` 문자열은 다음 HUB 에서 허브 토스트로 뜬다(`SeasonHub.hub_toasts`).

**내 경기 결과 소비**(`SeasonHub._consume_pending_match_result`, 결과 반영 전): `RunStats.record_match`
→ `MechMastery.record_match(state, pm)` → `FinanceSystem.record_match(state, pm, won)` → `PilotMods.consume_match`.
`pm.assigned_mechs = {"<pid>": mech_id}`(양 팀 10명)는 **M4(MatchFlow)가 출발 전에 적는다**.

**런 시작**(`GameManager.start_run` 끝): `StaffSystem.snapshot_for_run` 병합 → `MechMastery.init_run`
→ `FinanceSystem.init_run(state, team_id)` → `MentalSystem.init_run`.

### 11.2 허브 관리 카드 줄
`HubView` 로스터 아래 카드 셋 = `[StaffPanel, MasteryPanel, FinancePanel]`. 각 패널은
`static hub_summary(state) -> {title, value, sub, owner, alert}` 와 `static open(host)`(→ `HubSheet.open_on`)
만 구현한다. 시트가 닫히면 허브가 `refresh()` 한다. `HubView.show_toast(msg)` 공개.

### 11.3 일시 보정 · 배율이 만나는 자리
- 훈련 EXP = 타일 EXP × 훈련 스탯 배율(M3) × `FinanceSystem.training_exp_mult` × `MentalSystem.training_exp_mult(pid, day)` — 곱하는 곳은 `TrainingBoard`(M3 소유) 한 곳.
- 경기 로스터 = 원본 선수의 **사본**(`PlayerData.duplicate()`) + `PilotMods.apply_to` + 숙련도 고정치 — 만드는 곳은 `MatchFlow`(M4 소유) 한 곳. **원본(`all_pilots`)에는 절대 쓰지 않는다.**
- 숙련도 획득 = 원값 × 지식 배율 × `FinanceSystem.mastery_mult` — `MechMastery.gain` 안에서.
- 사건 확률 = 기본 × `FinanceSystem.incident_mult` — `MentalSystem` 안에서.

### 11.4 파일 소유 (병렬 작업)
| 작업 | 소유 |
|---|---|
| **A · M3 감독 · 훈련** | `features/season/training/*`, `features/meta/lobby/*`(감독 타입 팝업), `training_tiles.csv`(숙련도 타일 `M`), const `TRAINING_STAT_*` · `TACTICS_*` |
| **B · M4 숙련도 · 밴픽** | `features/season/mastery/*`, `features/match_flow/MatchFlow.gd` · `ban_pick/*`, `players.csv` / `intl_players.csv` 의 `main_mechs` 값, const `MASTERY_*` |
| **C · M5 분석 · 스태프 패널** | `features/season/staff/StaffPanel.gd`(+ README), `features/match_flow/match_prep/*`, `features/season/league/LeagueView.gd`(팀 상세), const `ANALYSIS_*` |
| **D · M6 재무 · 시설** | `features/season/finance/*`, `facilities.csv`, const `FINANCE_*` · `FACILITY_*`, `calendar/README.md` 주 마감 순서 |
| **E · M7 멘탈** | `features/season/mental/*`, `features/season/press/*`, `features/season/week/*`, `features/meta/run_result/*`(진엔딩 표시), `mental_events.csv`, const `MENTAL_*` · `TRUST_*` · `TRUE_ENDING_*` |

- 기반 소유 파일(`SeasonHub` · `HubView` · `GameManager` · `SaveSystem` · `ProfileManager` · `StaffSystem` · `PilotMods` · `csv_to_db.gd` · `HubSheet`)은 **고치지 않는다.** 꼭 필요하면 최소 수정 + 보고.
- `const.csv` 는 **자기 접두사 키를 맨 끝에 추가**만. `data/game.db` · `data/csv/*.translation` 은 **커밋하지 않는다**(로컬 재빌드는 자유 — 커밋 전 `git checkout` 으로 되돌림). 병합 후 한 번 다시 굽는다.

---

## 12. M8~M10 작업 계약 (2026-10-06 확정, 병렬 개발용)

기반 커밋이 데이터 표 · 프로필 v2 스키마와 API · 순수 규칙 모듈(`TraitSystem` ·
`ManagerProgress` · `PassSystem` · `RunRules` 돌파/레벨업) · 런 시작 / 정산 / match_ctx 연결 ·
**탭 로비 뼈대**(+ 탭 스텁)를 먼저 넣었다. 기능 작업은 **스텁을 채우고 자기 화면을 만든다** —
시그니처를 바꾸지 않는다(바꿔야 하면 보고에 적는다).

### 12.0 결정 (질의응답)
| 항목 | 결정 |
|---|---|
| 특성 묶음 | **24종** — 긍정 14(아웃게임 9 · 인게임 5) + 부정 10(아웃게임 7 · 인게임 3), 레어리티 0..4, 기본 보유 6종(`default_owned`). 수치 자리표시 |
| 장착 | **프리셋 + 런 준비 단계** — 로비 `감독` 탭에서 프리셋(전문화 분배 + 특성) 편집, 런 준비에 `감독` 단계(팀 다음 · 편성 앞)에서 프리셋 고르기 · 그 자리 특성 교체(= 그 프리셋을 고쳐 저장). 보너스 점수 < 0 이면 `다음` 비활성 |
| 장착 칸 | `TRAIT_SLOTS` 칸(긍정 · 부정 합산), 프레스티지와 무관 |
| 보너스 점수 | Σ부정 `bonus_cost` − Σ긍정 `bonus_cost`, **끝낸 페이즈에 비례 가산**: `breakdown.bonus = bonus × phases_cleared × RUN_SCORE_PER_BONUS`(바로 포기하면 0) |
| 특성 획득 | 기본 보유 · **런 조건 해금**(정산에서 판정, 다음 런부터) · 특성 가챠 · 제작(M10) |
| 인게임 훅 | **개시 + 턴 중 일부**: 개시 전략 포인트 · 첫 드로우 · 손패 상한 · 작전 단계 첫 카드 비용 · N턴마다 전략 포인트. **내 팀만**(AI 무특성) |
| 감독 성장 | 레벨업마다 **제거 포인트** `MANAGER_REMOVE_PER_LEVEL` → 스탯 하나 −1(1 이면 불가, **영구 — 프레스티지까지**) → **전문화 포인트** +1 → 프리셋마다 자유 분배(붙였다 뗐다). 총합 불변 |
| 감독 스탯 상한 | **15**(`MANAGER_STAT_CAP`) — 분배 후 값. 일시 보정 · `manager_all` 특성은 런 안에서 20 까지 |
| 감독 EXP | 기존 정산 EXP(점수 × 계수) + `manager_levels.csv`(1..25 누적) |
| 프레스티지 | **시즌 제한 없음**(Lv `PRESTIGE_LEVEL`). 레벨 · EXP · 제거 초기화, **타입 재선택**, 기존 프리셋 → 프레스티지 프리셋(재설정 전 사용 불가), 새 일반 프리셋 +1(최대 `PRESET_MAX_COUNT`) 자동 장착, **재화 보상** `PRESTIGE_REWARD_*` |
| 프리셋 | 기본 `PRESET_BASE_COUNT`개 |
| 재화 | **8종 전부**: outgame(런 정산) · levelup(정산 + 상점) · 가챠권 2종 · trait_mat(특성 중복 · 패스) · cosmetic(패스, 기록만) · premium(로컬 숫자, 개발용 버튼) · pilot_shard(돌파 끝 중복) |
| 선수 가챠 | 네임드 25인, **등급별 가중치**(`gacha_rates.csv`). 중복 → 돌파 1..5 → 그 뒤 파편(× 등급). 파편으로 원하는 선수 **확정 구매** |
| 돌파 | **선수별 표**(`pilot_breakthrough.csv`, 25 × 5). 종류 stat_flat · salary_down · stat_growth · card_swap |
| 선수 레벨업 | **둘 다** — 런 출전 EXP 로 최대 레벨 자동 상승(`pilot_levels.exp_required`) + 레벨업 재화로 +1(`levelup_cost`) |
| 주간패스 | `pass_rewards.csv` 25단, 런 점수 → 패스 EXP, 레벨당 고정 EXP, **수동 수령**, 26+ 는 아웃게임 재화, ISO 주(기기 시각) 리셋 |
| 로비 | **하단 탭 내비게이션**(홈 · 컬렉션 · 감독 · 상점 · 패스) + 탭 바 위 행동 바, 위 재화 줄 |
| 개발 방식 | 기반 커밋 + 기능별 워크트리 5개 병렬 → 병합. 검증 = 헤드리스 + 창 스크린샷 |

### 12.1 프로필 v2 (`ProfileManager`, `PROFILE_VERSION` 2)
v1 을 읽으면 빠진 칸이 기본값으로 채워진다(프리셋 5개로 패딩, `manager.removed` · 컬렉션 `exp` · 특성 int).
**M8 이후 변경 함수는 저장하지 않는다** — 화면이 한 조작 끝에 `save_profile()`.
| 키 | 모양 | 규칙 소유 |
|---|---|---|
| `manager.removed` | `{stat: int}` 영구 제거 | `ManagerProgress` |
| `presets` · `active_preset` | `[{kind: normal\|prestige, alloc: {stat: int}, traits: [id]}]` · int | `ManagerProgress` |
| `traits.owned` · `.unlocked_pending` | `[id]` · `[id]`(새로 해금 · 아직 안 본 것 — 감독 탭 배지) | `ProfileManager.grant_trait` |
| `collection[pid]` | `{owned, max_level, breakthrough, dupes, exp}` | `ProfileManager.grant_pilot / add_pilot_exp / level_up_pilot` |
| `currency` | 8종 int | `currency_of / add_currency / spend_currency` |
| `pass` | `{week_id, exp, claimed: [lv], overflow}` | `PassSystem` |

API(기반 완성): `grant_pilot(pid)` → `{result: new|breakthrough|shard, stage, shards}` · `grant_trait(id)` →
`{result: new|material, amount}` · `level_up_cost(pid)` / `level_up_pilot(pid)` · `add_pilot_exp` ·
`owned_trait_ids` · `owned_breakthroughs` · `breakthrough_of` · `pilot_rarity`.

### 12.2 런 시작 · run_setup 추가 키
`run_setup.preset`(-1 = 활성 프리셋)만 화면이 보낸다. `GameManager.start_run` 이 프리셋을 검증
(`ManagerProgress.validate_preset`, 실패 = 시작 거절 · 테스트 런은 특성 없이 진행)하고 스냅샷한다:
`preset` · `traits: [id]` · `bonus_points` · `pilot_breakthrough: {"<pid>": stage}`(내 5인만) ·
`salary_cap`(= `RunRules.salary_cap_with`) · `manager_stats`(= 프리셋 값 + `manager_all`).
돌파는 **내 5인에게만** 적용된다(안 뽑은 보유 선수는 AI 팀에 원래 세기로 간다).

### 12.3 특성 효과 키 (`traits.key`, p1 합산)
| key | 층 | 읽는 곳 (소유) | 뜻 |
|---|---|---|---|
| `train_exp_pct` | out | `TrainingBoard.cell_exp` (A) | 훈련 EXP ×(1 + Σ/100). 같은 자리에서 `PlayerData.train_bonus_pct`(돌파) 도 곱한다 |
| `mastery_pct` | out | `MechMastery.gain_mult` (A) | 내 선수 숙련도 획득 % |
| `income_pct` | out | `FinanceSystem.settle_week` 스폰서 (A) | 주간 스폰서 수입 % |
| `upkeep_pct` | out | `FinanceSystem` 유지비 (A) | 시설 유지비 % |
| `trust_gain` | out | `MentalSystem.add_trust` (A) | 신뢰도가 **오를 때** ±Σ(오름이 0 아래로 가지 않게) |
| `incident_pct` | out | `MentalSystem` 사건 확률 (A) | 사건 확률 % |
| `analysis_tier` | out | `StaffSystem.analysis_tier` (기반 ✅) | 공개 단계 ±, 0..3 |
| `salary_cap` | out | `RunRules.salary_cap_with` (기반 ✅) | 캡 ± |
| `manager_all` | out | `GameManager._manager_setup_for_run` (기반 ✅) | 감독 스탯 여섯 + |
| `open_cost` | in | `BattleSim.seed_side_costs` (B) | 개시 내 전략 포인트 + |
| `first_draw` | in | 첫 자동 드로우 (B) | 그 드로우 장수 ±(0 미만 없음) |
| `hand_size` | in | 내 손패 상한 (B) | ± |
| `first_card_cost` | in | `BattleSim.effective_cost_for` (B) | 작전 단계마다 내 첫 카드 비용 ±(0 미만 없음) |
| `cost_tick` | in | BATTLE 틱 (B) | `ECONOMY_START_TURN` 부터 p2 턴마다 내 전략 포인트 +p1 |

아웃게임은 `TraitSystem.run_mod(state, key)` / `run_pct_mult(state, key)`, 인게임은
`match_ctx.traits = [{id, key, p1, p2}]`(비면 BattleSim 은 지금과 같다).

### 12.4 해금 조건 문법 (`traits.unlock`, `TraitSystem.evaluate_unlocks` — A)
정산 결과 `result` · `season_state` · 프로필로 판정, 이미 보유한 특성은 빼고 돌려준다.
`clear` · `wins:N` · `titles:N` · `phase:N`(`phases_cleared` ≥ N) · `win_streak:N`(`run_stats.matches` 의
최장 연승) · `outings:N`(내 선수 외출 최대) · `mvp:N`(이번 런 내 MVP 합) · `finance_manual_profit:N`
(관리 담당이 감독일 때 흑자 주 수 — `finance.manual_profit_weeks`, A 가 셈) · `true_ending` ·
`runs:N`(프로필 런 수 + 이번 런) · `team:T`(팀 T 로 한 페이즈 이상 끝냄) · `bonus:N`(보너스 ≥ N 으로
한 페이즈 이상 끝냄). 테스트 런은 프로필이 비어 런 조건만 본다.

### 12.5 정산 결과 추가 키 (`RunResult.build_result` → `ProfileManager.apply_run_result`)
`currency: {outgame, levelup}` · `pass_exp` · `pilot_exp: {"<pid>": n}`(경기 · 승 · MVP) ·
`unlocked_traits: [id]` · `bonus_points` + `breakdown.bonus`. 반영 후 `result.profile_delta =
{manager: {from, to}, pilots: {"<pid>": {from, to}}, pass: {from, to, overflow_outgame}, traits: [id]}` —
정산 화면(A)이 그린다.

### 12.6 로비 탭 계약 (`features/meta/lobby/LobbyScreen.gd` 머리말)
탭 = `extends Control` + `bar_specs()` · `setup(host)` · `on_bar_pressed(i)` · `on_shown()`.
host 서비스: `show_toast` · `refresh_currency` · `rebuild_bar` · `relayout_bar` · `bar_buttons` ·
`switch_tab` · `set_tab_badge` · `refresh_badges` · `open_confirm`. 탭 본문 rect 는 host 가 정한다
(재화 줄 아래 ~ 행동 바 / 탭 바 위). 팝업은 탭이 자기 CanvasLayer 로 띄운다.

### 12.7 파일 소유 (병렬 작업)
| 작업 | 소유 |
|---|---|
| **A · M8 특성 아웃게임 · 해금 · 정산 화면** | `TraitSystem.evaluate_unlocks` 몸통 + `features/meta/traits/README.md`, `features/season/training/TrainingBoard.gd`(배율), `features/season/mastery/MechMastery.gd`, `features/season/finance/FinanceSystem.gd`, `features/season/mental/MentalSystem.gd`, `features/season/staff/StaffPanel.gd`(장착 특성 표시), `features/meta/run_result/RunResultScreen.gd` + README, const `TRAIT_*`(새 키) |
| **B · M8 인게임 훅** | `features/battle_sim/trait/*`(신규 `TraitHooks.gd` + README), `BattleSim.gd` · `card_phase/*` 의 훅 자리(최소), `ui/*`(장착 특성 표시, 선택), `features/battle_sim/README.md` 모듈 표, const `TRAITHOOK_*` |
| **C · M8/M9 감독 탭 · 런 준비 감독 단계** | `features/meta/manager/*`(ManagerTab, 프리셋 · 분배 · 특성 장착 · 레벨 · 프레스티지, README; `ManagerProgress` 는 함수 추가만), `features/meta/run_setup/*`(**`DraftDetailPanel.gd` 제외**: 감독 단계, 편성 캡 = `salary_cap_with` + `validate_lineup` 의 `cap_bonus`, `build_run_setup.preset`), `features/meta/lobby/ManagerTypePopup.gd`(프레스티지 재선택 모드) |
| **D · M10 컬렉션** | `features/meta/collection/*`(CollectionTab, 선수 상세 · 레벨업 · 돌파 표, README), `features/meta/run_setup/DraftDetailPanel.gd`(돌파 단계 표시) |
| **E · M10 상점 · 패스** | `features/meta/shop/*`(ShopTab: 선수 · 특성 가챠 · 파편 확정 구매 · 특성 제작 · 재화 교환 · 개발용 유료 재화, `Gacha.gd`, PassTab, `PassSystem.claim` 몸통, README), const `GACHA_*` · `SHOP_*` |

- 기반 소유(`ProfileManager` · `GameManager` · `RunRules` · `RunResult.gd` · `SaveSystem` · `StaffSystem` ·
  `LobbyScreen` · `HomeTab` · `TraitSystem`(해금 몸통 제외) · `PassSystem`(claim 제외) · `csv_to_db.gd`)은
  **고치지 않는다**. 꼭 필요하면 최소 수정 + 보고.
- `const.csv` 는 **자기 접두사 키를 맨 끝에 추가**만. `data/game.db` · `data/csv/*.translation` 은
  **커밋하지 않는다**(로컬 재빌드는 자유 — 커밋 전 `git checkout` 으로 되돌림). 병합 후 한 번 다시 굽는다.

---

## 13. 다음 작업 목록 (2026-10-06 확정, 다른 세션에서 진행)

§8 질의응답과 §9 후속 과제에서 고른 것. 착수 전 해당 폴더 README 를 먼저 읽는다. 순서는 미정 — 착수 세션에서 정한다.

| # | 작업 | 내용 | 주 위치 |
|---|---|---|---|
| T1 | **기벽**(§3 M4, §8 #2) | 런 한정 선수 패시브 · 긍정만 · 스탯 보정만(MatchFlow 가 로스터 사본에 얹음, BattleSim 무수정). 0개 시작, 칸 2 → 훈련으로 최대 5. 획득 = 훈련 타일 · `메크 연구` 카드 → 무작위 기벽을 빈 칸에 강제 장착. 별도 훈련으로 재굴림. 지식 스탯 = 좋은 기벽 가중치. 표(`quirks.csv` 가칭) · `season_state` 키 · 세이브 · 표시 지점(밴픽 · 컬렉션 상세 · 허브)은 착수 시 계약으로 확정 | `season/mastery/`, `season/training/`, `match_flow/` |
| T2 | **점수 · 재화 · EXP 공식 산출**(§8 #5) | 헤드리스 런 시뮬레이션 스크립트로 N회 자동 진행 → 페이즈 도달률 · 점수 · 재화 · 감독 EXP 분포 → 목표치에서 `RUN_*` · 레벨 곡선 · 패스 EXP 역산 | `meta/run_result/`, `data/csv/const.csv` |
| T3 | **특성 배율 UI 반영** | `FinancePanel` 스폰서 배율 글자, `TrainingView` "훈련 효과 ×" 글자에 특성 배율 포함. 특성 레어리티별 색 통일(정산 카드 앰버 고정 해소) | `season/finance/`, `season/training/`, `meta/traits/`, `meta/run_result/` |
| T4 | **허브 · 주간 표시 보강** | 허브에 선수 신뢰도 표시, 시간 경과 화면에 숙련도 획득 표시 | `season/` (HubView), `season/week/`, `season/mental/` |
| T5 | **12장 손패 부채꼴 확인** | 드로우 특성으로 손패 12장일 때 배치 · `HandHitLayer` 판정 검증, 깨지면 수정 | `battle_sim/card_phase/` |
| T6 | **코치 추천 · 감독 관리 스탯** | 저스탯 팀 코치 추천 개선(지금은 `T02` 만), 감독 관리 스탯에 담당자 판정 외 실효과 부여, 부자 팀 잉여 잔고 사용처(저예산 도구 후속 포함) | `season/training/`, `season/staff/`, `season/finance/` |

- 제외: 코스메틱 재화 사용처(기록만 — 결정 유지), 치트 즉시 결과의 숙련도 미지급.
- §8 #9(6대회 전승 난이도)는 **의도된 난이도**라 목록에서 뺐다.

---

## 14. §13 작업 계약 (2026-10-06 확정, 병렬 개발용)

기반 커밋이 기벽 상태 키(`season_state.quirks`) · 세이브 왕복 · `QuirkSystem` 스텁(시그니처 고정) ·
`MatchFlow._finalize_rosters` 의 `QuirkSystem.apply_to` 호출 · `GameManager.start_run` 의
`QuirkSystem.init_run` · 표 스키마 2개(`quirks` · `finance_specials`, 헤더만 있는 CSV) ·
`FinanceSystem.income_mult` / `upkeep_mult`(지금은 특성 배율만)를 먼저 넣었다.
작업 단위는 **5개**: T1 · T2 · T3+T4 · T5 · T6.

### 14.0 결정 (질의응답)
| 항목 | 결정 |
|---|---|
| 기벽 표 | **18종 · 3등급**(0 일반 / 1 희귀 / 2 영웅, 각 6종). 효과 = 스탯 1~2개 고정 가산(`stats`), 영웅은 조건부 추가(`cond` + `cond_stats`, 예: 특정 역할 메크 탑승). 수치 자리표시 |
| 기벽 등급 가중치 | 유효 지식 스탯(`StaffSystem.effective(state, "knowledge")`)이 희귀 · 영웅 확률을 올린다 — `QUIRK_*` const |
| 기벽 획득 · 재굴림 · 칸 | 훈련 타일 효과 절 `quirk:gain` / `quirk:reroll` / `quirk:slot` — 그 요일 정산에서 **타일이 덮은 칸의 선수**에게 적용(칸마다 아니고 선수마다 한 번). `메크 연구` 카드 = 주간 연구 정산(`MechMastery.settle_week`)에서 연구 메크가 있는 내 선수마다 `QUIRK_RESEARCH_CHANCE`% 확률로 `gain_random` |
| 기벽 칸 | 시작 `QUIRK_SLOTS_START`(2), 최대 `QUIRK_SLOTS_MAX`(5). 빈 칸이 없으면 획득은 "full"(아무 일도 없음 — 재굴림으로 바꾼다) |
| 기벽 표시 | 밴픽(슬롯 태그 · 선수 시트), `메크 연구` 시트의 선수 카드, 시간 경과 화면의 요일 행. 컬렉션 상세는 런 밖이라 **표시하지 않는다** |
| T2 목표치 | 평균 런(페이즈 1~2 도달) ≈ 선수 가챠 1회분 아웃게임 재화 · 감독 Lv25 ≈ 40런 · 패스 25단 ≈ 주 7런 · 클리어 런 점수 ≈ 평균 런의 5배. 시뮬 결과 리포트 + const 반영 |
| T6 재무 스탯 | 유효 재무 스탯이 스폰서 수입 % · 유지비 할인 %에 **연속 보정**(`FINANCE_STAT_*`) — `income_mult` / `upkeep_mult` 에 곱해 넣는다(UI 는 이 둘만 읽는다) |
| T6 잔고 사용처 | 재무 시트의 **특별 지출** 목록(`finance_specials.csv`): 단기 코치 고용(`StaffSystem.add_mod` 일시 스탯), 집중 캠프(N주 훈련 EXP %), 스폰서 계약(N주 수입 % — 조건부). 잔고에서 즉시 차감 |
| T6 코치 추천 | `TrainingBoard.auto_arrange` 를 **선수별 약한 스탯 보강 + 등급 균형**으로 개선(T02 만 깔던 문제). 여전히 최적화기는 아니다 |

### 14.1 상태 키 · 인터페이스
| 키 / 함수 | 모양 | 소유 |
|---|---|---|
| `season_state.quirks` | `{"<pilot_id>": {"slots": int, "ids": [quirk_id]}}` — 내 5인만 | T1 (`QuirkSystem`) |
| `QuirkSystem.*` | `features/season/quirk/QuirkSystem.gd` 스텁 시그니처 그대로 | T1 |
| `apply_day_training` 행 | 기존 키 + **`quirk: [{kind: gain\|reroll\|slot, result, id?, from?, to?}]`**(없으면 빈 배열) | T1 이 채움, T3+T4 가 그림 |
| `apply_day_training` 행 `mastery` | 기존 그대로 — 시간 경과 화면에 표시 | T3+T4 가 그림 |
| `season_state.finance.specials` | `[{id, weeks_left, ...}]` 진행 중 특별 지출 | T6 (`FinanceSystem`) |
| `FinanceSystem.income_mult(state)` / `upkeep_mult(state)` | float — 특성 × 재무 스탯 × 특별 지출 | 몸통 T6, 글자 T3 |
| `FinanceSystem.training_exp_mult` | 기존 + 집중 캠프 | T6 |
| 특성 레어리티 색 | 공용 함수 하나(`features/meta/traits/TraitUi.gd` 신규, `rarity_color(rarity)`) | T3 |

### 14.2 파일 소유 (병렬 작업)
| 작업 | 소유 |
|---|---|
| **T1 · 기벽** | `features/season/quirk/*`(+ README), `data/csv/quirks.csv`, `data/csv/training_tiles.csv`(기벽 타일 추가), `features/season/training/TrainingTile.gd`(효과 절 파싱 · 요약), `TrainingBoard.apply_day_training` 의 기벽 적용 부분, `MechMastery.settle_week`(연구 확률 획득 한 자리), `features/season/mastery/MasteryPanel.gd`(시트에 기벽 줄), `features/match_flow/ban_pick/*`(기벽 표시), const `QUIRK_*` |
| **T2 · 공식 산출** | 신규 시뮬 스크립트(`features/meta/run_result/sim/`), 리포트 `docs/run_balance.md`, `data/csv/const.csv` 의 기존 `RUN_*` · `PASS_*` · `MANAGER_*` **값만**, `data/csv/manager_levels.csv` · `pilot_levels.csv`(EXP 곡선), `features/meta/run_result/README.md` |
| **T3+T4 · 표시 보강** | `features/season/training/TrainingView.gd`(훈련 효과 × 글자), `features/season/finance/FinancePanel.gd` 의 **스폰서 배율 글자 줄만**, `features/meta/traits/TraitUi.gd`(신규) + 레어리티 색 쓰는 화면(`RunResultScreen` · `StaffPanel` · `ManagerUi` / `TraitPickerView` · `ShopTab` 의 색 줄만), `features/season/HubView.gd`(신뢰도), `features/season/week/*`(숙련도 · 기벽 표시) |
| **T5 · 12장 손패** | `features/battle_sim/card_phase/*`(+ README) — 검증만 하고 깨질 때만 수정, const `HAND_*` |
| **T6 · 코치 추천 · 재무** | `TrainingBoard.auto_arrange`(+ 보조 함수), `features/season/finance/FinanceSystem.gd`, `FinancePanel.gd`(특별 지출 섹션 — 스폰서 배율 글자 줄 제외), `data/csv/finance_specials.csv`, `features/season/finance/README.md`, `features/season/training/README.md` 코치 추천 절, const `FINANCE_STAT_*` · `FSPEC_*` · `COACH_*` |

- 같은 파일을 두 작업이 만지는 곳(`TrainingBoard.gd`: T1 = `apply_day_training`, T6 = `auto_arrange`;
  `FinancePanel.gd`: T3 = 배율 글자 줄, T6 = 특별 지출 섹션; `training/README.md`: 각자 자기 절)은 **자기 함수 / 절만**.
- 기반 소유(`GameManager` · `SaveSystem` · `MatchFlow.gd` · `csv_to_db.gd` · `StaffSystem` · `TraitSystem` ·
  `ProfileManager`)는 고치지 않는다. 꼭 필요하면 최소 수정 + 보고.
- `const.csv` 는 **자기 접두사 키를 맨 끝에 추가**만(T2 는 기존 값 수정). `data/game.db` · `*.translation` 은 커밋하지 않는다.
