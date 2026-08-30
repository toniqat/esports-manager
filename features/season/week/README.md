# 시간 경과 (week)

주가 **월요일부터 일요일까지 하루씩** 흘러가는 화면. `SeasonHub` 의
`Screen.WEEK`. 참고 디자인은 `docs/ref_image.jpg`.

| 파일 | 역할 |
|---|---|
| `WeekProgressView.gd` | `class_name WeekProgressView extends Control` — 화면 전부 |

## 화면

```
┌──┬──────────────────────────────────────┐
│1주│ 프리시즌 · 3주차            1년 12월   │
│월│                                  5     │
│화│  금요일                               │
│수│ ──────────────────────────────────── │
│목│  ▌(○) Evelyn      전명 전회 교명 …      │  ← 세로 스크롤
│금│  ▌    탱커         86   87   83        │
│토│                    +1   +1  12/40      │
│일│  ▌(○) Seed  …                         │
└──┴──────────────────────────────────────┘
        [           확인           ]
```

* **왼쪽 세로 레일** — 어두운 알약 위에 요일 칩 일곱. **지금 요일 한 칸만
  앰버로 채워진다.** 지나온 날은 흰 글자, 남은 날은 흐린 글자 — 그 대비가
  "며칠 남았나"를 레일만 보고 읽게 한다. 맨 위에 `N주`.
* **오른쪽 머리글** — 왼쪽에 페이즈 · 주차와 큰 요일 이름, 오른쪽에 `1년 12월`
  과 그날의 **일(日)** 큰 숫자. 날짜는 그 주 월요일(`season_state.year/month/day`)
  에 요일만큼 더해 만든다(`_date_of_day`, 달을 넘길 수 있으므로
  `CalendarSystem.DAYS_IN_MONTH` 를 지난다).
* **본문** — 카드 목록, 세로 스크롤(`OutgameTheme.add_vscroll`).
* **아래 버튼** — 보통 `확인`(앰버), 일요일이면 `주 마감 →`, 그날 플레이어
  경기가 남아 있으면 **`경기 시작`**(어두운 색면 — "이 화면을 떠난다"는 뜻).

## 요일이 하는 일

| 요일 | 하는 일 |
|---|---|
| 월~금 | **훈련일.** 그 요일에 처음 닿을 때 `TrainingBoard.apply_day_training(day)` 가 판의 그 줄을 정산해 선수 스탯을 실제로 올린다. |
| 토 · 일 | **경기일**(`CalendarSystem.MATCH_DAYS` — 토 = 경기일 0, 일 = 경기일 1). 그날 배정된 경기가 카드로 뜬다. |

### 훈련 카드

선수 한 명이 한 장. 왼쪽에 역할 색 띠(`OutgameTheme.lead_bar_style`), 원형
초상화, 이름 · 역할, 오른쪽에 여섯 스탯이 `이름 / 지금 값 / 이번 날의 결과`
세 줄로 선다.

세 번째 줄이 **오른 포인트가 있으면 `+N`(초록), 없으면 `27/40`**(다음 한 점까지
모인 EXP)이다. 기초 코스만 깔린 판은 하루 EXP 가 `EXP_PER_POINT`(40)에 못 미쳐
월~목이 전부 `—` 로 보이고 금요일에 한꺼번에 오르는데(실측: 닷새에 스탯 총합
+6), 그러면 이 화면이 매일 답해야 하는 "오늘 뭐가 늘었나"에 나흘 동안 답이 없다.

### 경기 카드

그 경기일의 경기를 전부 늘어놓되 **플레이어 경기가 맨 위**이고 어두운 색면이다
(나머지는 흰 카드에 절반 높이). 출처는 둘 — 토너먼트가 돌고 있으면 대진표,
아니면 리그 스케줄(`_matches_on_day`). 상태 칸은 `예정` / `승` / `패` /
`<팀> 승`.

## 두 번 정산하지 않는다

그 요일의 결과는 `season_state["week_day_log"][day]` 에 남고, **이미 있으면 다시
정산하지 않는다**(`_settle_day_if_needed`). 경기를 치르고 같은 요일로 돌아오는
경로가 실제로 있다 —

```
WEEK 토  →  경기 시작  →  MatchFlow → BattleSim  →  Season 재진입
        →  SeasonHub 가 결과 적용 + 그 경기일 AI 정산  →  STANDINGS
        →  확인  →  WEEK 토 (그 경기는 이제 played 라 버튼이 다시 "확인")
        →  확인  →  WEEK 일
```

주 진행 상태는 셋이다(전부 `season_state`, 세이브에 실린다).

| 키 | 뜻 |
|---|---|
| `week_day` | 지금 보고 있는 요일 0..6. **-1 은 주가 아직 안 열렸다는 뜻** — 허브 · 기자회견 · 훈련 계획 구간이 전부 -1 이고, 그 값이 순위표의 "확인"이 주로 돌아갈지 허브로 돌아갈지를 가른다(`SeasonHub.on_standings_confirmed`). |
| `week_day_log` | `day(int) → Array[줄]`. 정수 키라 세이브에서 `_int_keyed_dict_in` 을 지난다 — 안 지나면 `log[3]` 이 영원히 빈 배열을 돌려줘 같은 요일 훈련이 두 번 먹는다. |
| `training_exp_carry` | 나머지 EXP 통장. `TrainingBoard` 항목 참조. |

셋 다 `TrainingBoard.reset_week_progress()` 가 비우고, 그것은 **훈련 확정**
(`SeasonHub.on_training_confirmed`)과 **주 종료**(`reset_for_new_week`) 두 곳에서 돈다.

## SeasonHub 와 주고받는 것

| 부르는 쪽 | 함수 |
|---|---|
| 화면 → 허브 | `has_player_match_on_day(day)` · `opponent_name_on_day(day)` · `on_week_day_match_start()` · `on_week_day_confirmed()` |
| 허브 → 화면 | `ensure_view()` (라우팅할 때마다) |

`on_week_day_confirmed()` 는 **넘어가기 전에** 그날의 AI 경기를 쓸어 담는다
(`_resolve_ai_for_matchday`) — 플레이어가 그날 경기가 없어 그냥 넘어가는
경우에도 그날 리그는 돌아가야 하고, 그래야 다음에 보는 순위표가 날짜와 맞는다.
