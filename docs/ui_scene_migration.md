# UI 씬 전환 (코드 생성 UI → `.tscn`) — 조사 · 진행 상황 · 계획

**목적**: 사람이 Godot 에디터에서 WYSIWYG 로 UI 를 고치고(필요 없는 것 지우기, 위치 · 크기 ·
색 조정), 추가 개발이 필요한 자리는 **씬 안에 마킹**해 두면 LLM 세션이 그 마킹을 읽고 구현하는
작업 방식을 만든다. 이 문서는 다른 세션이 이어받기 위한 인수인계 문서다.

> 이어받는 세션: 루트 `CLAUDE.md` → 이 문서 → 작업할 폴더의 `README.md` 순서로 읽는다.
> 진행 상황이 바뀌면 §4 표와 §6 작업 목록을 갱신한다.

---

## 1. 조사 결과 (2026-10-07 시점)

### 1.1 씬 파일은 거의 비어 있다
| 씬 | 노드 수 | 실제 내용 |
|---|---|---|
| `scenes/Lobby.tscn` · `RunSetup.tscn` · `RunResult.tscn` | 1 | 루트 `Control` + 스크립트뿐 |
| `scenes/Season.tscn` | 8 | 배경 · "Phase 1 placeholder" 라벨 · 시스템 노드 |
| `scenes/MatchFlow.tscn` | 5 | 배경 · 빈 `CanvasLayer` · 컨트롤러 |
| `scenes/BattleSim.tscn` | 13 | 로직 노드. HUD 는 `HudBuilder` 가 코드로 생성 |
| `scenes/Card.tscn` · `BattleField.tscn` | 10 / 31 | 에디터에서 실제로 구성된 유일한 씬 |

팝업 · 시트는 **전부 `.tscn` 없이** `Xxx.new()` → `add_child` 로 만든다
(`extends CanvasLayer` 인 것: `ConfirmPopup`, `ManagerTypePopup`, `ShopPopup`,
`CollectionDetailSheet`, `DraftDetailPanel`, `HubSheet`, `MechDetailPanel`, `MatchCheatMenu`,
`MvpView`, `TraitBanner`).

### 1.2 UI 를 만드는 두 가지 방식
1. **코드로 노드 조립 (대부분)** — `Label.new()` / `Button.new()` 등 약 360곳.
   위치는 픽셀 좌표 상수 (`OutgameTheme.add_card(parent, pos, sz)`, `UiHelpers.mk_label(..., pos, sz)`),
   스타일은 `OutgameTheme.style_*_button` · `card_style` 이 `StyleBoxFlat` 을 코드로 만든다.
   결과물은 일반 Control 노드라 **씬으로 옮길 수 있다**.
2. **`_draw()` 로 직접 그림 (17개 파일)** — 대부분 BattleSim:
   `Card`, `CardDragArrow`, `CardPhaseManager`, `CardPlayPreview`, `EngageArena`, `BattleRenderer`,
   `CardPileStack`, `CostDonut`, `KillFeed`, `ObjectiveTimer`, `ReservationChips`, `SkillBadge`,
   `MentalSystem`, `MessengerView`, `TrainingView`, `CostRibbon`, `OutgameTheme`(둥근 초상).
   → **전환 대상 아님**. 씬에는 해당 위젯 노드를 "배치"만 한다.

### 1.3 지금 구조에서 에디터 편집이 안 되는 이유와 위험
- 씬에 노드가 없으니 지울 것이 없다. Remote 트리에서 지워도 저장되지 않고 다음 실행에 코드가 다시 만든다.
- 씬으로 옮긴 뒤의 위험과 대응:
  | 위험 | 대응 |
  |---|---|
  | 노드를 지우면 `$Path` / `get_node` 가 null 에러 | 접근은 `%UniqueName` 만. 지워도 되는 노드는 null 허용 |
  | LLM 이 기존 "코드로 만든다" 패턴을 따라 지운 것을 되살림 | `CLAUDE.md` 규칙(§3) — 씬에 없는 노드는 **의도된 삭제** |
  | `.tscn` 텍스트 편집 실수 (`ext_resource` id, `load_steps`, uid) | 가능하면 `godot-mcp` scene/node 도구, 텍스트 편집 후엔 실행 검증(§5) |
  | 세이프 에어리어가 `ScreenMetrics` 좌표 계산에 의존 | 앵커 + 컨테이너로 바꾸고, 기기별 인셋만 코드가 오프셋으로 넣는다 (`docs/mobile_safe_area.md`) |

---

## 2. 시범 전환 완료 — `ConfirmPopup`

변경 파일: `features/meta/lobby/ConfirmPopup.tscn`(신규) · `ConfirmPopup.gd`(195 → ~110줄) ·
`LobbyScreen.gd`(한 줄) · `features/meta/lobby/README.md`.

```
ConfirmPopup (CanvasLayer 20 — 씬은 visible 로 저장, `create()` 가 숨김)
└ Root (full rect)
  ├ %Dim        flat Button, 빈 곳 누르면 취소
  ├ DimRect     반투명 딤
  └ %SafeArea   CenterContainer — 위아래 오프셋만 코드가 안전 영역으로 맞춤
    └ Card      PanelContainer (스타일박스 content_margin 이 패딩)
      └ VBox (separation 0)
        ├ %Title · Gap1 · %Body(autowrap, 최소 높이) · Gap2
        └ Buttons (HBox) ─ %Cancel (stretch 1) : %Confirm (stretch 2)
```

- 생성: `ConfirmPopup.create()` (`load(SCENE_PATH).instantiate()`). `ConfirmPopup.new()` 는 빈 레이어라 쓰지 않는다.
  자기 씬을 `preload` 하면 스크립트 ↔ 씬 순환 참조가 되므로 `load()` 를 쓴다.
- 열기/닫기 = CanvasLayer `visible` 토글. 노드는 재사용(매번 다시 만들지 않음).
- 스크립트가 하는 일: `%` 노드에 텍스트 넣기, 시그널 연결, 안전 영역 오프셋, `danger` 색.
- 검증: 임시 씬으로 실제 렌더 → 카드 크기 · 버튼 폭이 기존 코드 버전과 픽셀 단위로 동일,
  시그널 · 닫힘 동작 정상, `Lobby.tscn` 실행 시 에러 없음.

### 시범에서 알게 된 것 (다음 전환에 그대로 적용)
- **CanvasLayer 바로 아래 Control 의 full-rect 앵커는 뷰포트 크기로 정상 해석된다.**
  기존 코드 주석("앵커 프리셋이 뷰포트로 풀리지 않는다")은 코드로 만들 때의 순서 문제였다.
- **씬의 sub_resource(StyleBox)는 같은 씬의 인스턴스끼리 공유된다.** 런타임에 색을 바꿀 땐
  `duplicate()` 한 것으로 override 하고 원본은 `_ready` 에서 보관해 되돌린다(`_apply_danger`).
- **씬 루트(CanvasLayer)를 `visible = false` 로 저장하지 않는다** — 에디터 뷰포트에서 자식까지 안 보여
  빈 씬처럼 보인다. 닫힌 상태로 시작하는 건 `create()` 에서 `p.visible = false`.
- **`HapticUi.mute(btn)` 은 되돌리는 API 가 없다** — 재사용 노드라면
  `HapticUi.kind(btn, HapticUi.up_kind)` + `down_kind_for(btn, HapticUi.down_kind)` 로 복구.
- 컨테이너 레이아웃이면 기존의 "줄바꿈 Label 은 트리 밖에서 높이가 0" 문제가 사라진다
  (본문은 최소 높이만 주고 길면 카드가 늘어남).
- 헤드리스/CLI 로 저장한 `.tscn` 에는 uid 가 안 붙는다. **에디터에서 한 번 열고 저장**하면 붙는다 (남은 목록 → §7 웨이브 3 남은 일 1).
- **임시 스타일 중복**: 버튼 · 카드 스타일박스를 `OutgameTheme` 값에서 복사해 씬에 넣었다.
  팔레트가 코드에서 바뀌면 이 씬은 안 따라간다 → §6 T1 (공용 Theme 리소스)로 해소됨.

---

## 3. 작업 방식 (합의된 방향)

1. **레이아웃 · 스타일의 정본은 `.tscn`.** 스크립트는 `%노드` 바인딩 + 데이터 채우기 + 시그널만.
   정적 UI 를 코드로 `.new()` 하지 않는다.
2. **반복 항목**(파일럿 행, 상점 슬롯, 순위 줄 …)은 작은 아이템 `.tscn` 을 만들어 `instantiate()`.
3. **`_draw` 위젯은 코드 유지**, 씬에 노드로 배치만.
4. **씬에서 사라진 노드는 의도된 삭제** — 코드로 되살리지 않는다. 바인딩 코드도 같이 정리.
5. **추가 개발 자리 마킹 = `editor_description`**:
   빈 `Control`/`Panel` 을 원하는 자리 · 크기로 놓고 인스펙터의 *Editor Description* 에
   `TODO: <무엇을>` 을 적는다. `.tscn` 에 `editor_description = "TODO: ..."` 로 저장되므로
   LLM 은 `grep -rn 'editor_description = "TODO' --include=*.tscn` 으로 작업 목록을 얻고,
   그 노드의 위치 · 크기를 그대로 쓴다. 구현이 끝나면 TODO 문구를 지운다.
6. 기기별로 달라지는 값(세이프 에어리어 인셋)만 코드가 넣는다 — 오프셋으로, 위치 계산이 아니라.
7. **씬에 로컬 StyleBox(`theme_override_styles/*` sub_resource)를 두지 않는다** — 한 씬에서만 쓰는 모양도
   `OutgameTheme._add_screen_variations()` 의 **화면 전용 변형**으로 만든다. 이름 = `<쓰는 씬><역할>`
   (예: `RunResultSectionCard`), 기반 = 가장 가까운 공용 변형(`Card` · `SunkPanel` · `AccentChip` …).
   색이 데이터면 변형은 모양 + 미리보기 색, 코드는 `OutgameTheme.variation_box()` 사본에 색만 넣는다.
   목록 · 규칙: `resources/README.md` → Screen variations.

이 규칙들의 요약은 루트 `CLAUDE.md` Critical patterns 의 "Outgame UI lives in `.tscn`" 항목에 있다.

---

## 4. 전환 대상과 상태

순서: 단순한 아웃게임 팝업 → 로비 탭 → RunSetup → Season → MatchFlow → (BattleSim HUD 는 마지막 / 보류).

| # | 대상 | 폴더 | 종류 | 상태 |
|---|---|---|---|---|
| 1 | `ConfirmPopup` | `meta/lobby/` | 팝업 | ✅ 커밋됨 |
| 2 | `ManagerTypePopup` | `meta/lobby/` | 팝업 (선택지 반복 → 아이템 씬) | ✅ 전환 (+ `ManagerTypeOption` 아이템 씬) |
| 3 | `ShopPopup` | `meta/shop/` | 팝업 | ✅ 전환 (+ `ShopRevealItem` · `ShopRateRow` 아이템 씬) |
| 4 | `CollectionDetailSheet` | `meta/collection/` | 시트 | ✅ 전환 (+ `CollectionStatChip` · `CollectionBreakthroughRow` 아이템 씬) |
| 5 | `DraftDetailPanel` | `meta/run_setup/` | 모달 | ✅ 전환 (+ `DraftStatChip` 아이템 씬) — 스타일은 새 variation 모양으로 확정 |
| 6 | `HubSheet` | `season/` | 시트 (허브 관리 카드 공용 틀) | ✅ 틀만 전환 (본문은 #10) |
| 7 | `LobbyScreen` + `HomeTab` · `CollectionTab` · `ManagerTab` · `ShopTab` · `PassTab` | `meta/lobby/` 등 | 화면 / 탭 | ✅ 전환 (웨이브 3) |
| 8 | `RunSetupScreen` + `TeamDraftView` · `ManagerStepView` · `ChoiceListView` · `TeamStepView` · `PilotThumb` | `meta/run_setup/` | 화면 | ✅ 전환 (웨이브 3) |
| 9 | `RunResultScreen` | `meta/run_result/` | 화면 | ✅ 전환 (웨이브 3) |
| 10 | `SeasonHub` / `HubView` · `LeagueView` · `BracketView` · `IntlBracketView` · `WeekProgressView` · `PressConferenceView` · `EndingView` · `GameOverView` · `FinancePanel` · `StaffPanel` · `MasteryPanel` | `season/**` | 화면 / 패널 | ✅ 전환 (웨이브 3) |
| 11 | `TrainingView` · `MessengerView` | `season/training/`, `press/` | `_draw` 혼합 — 틀만 씬 | ✅ 전환 (웨이브 3) |
| 12 | `BanPickController` UI · `MechDetailPanel` · `MatchPrep` UI · `MatchCheatMenu` | `match_flow/**` | 화면 | ✅ 전환 (웨이브 3) |
| 13 | BattleSim `HudBuilder` · `PilotDetailPanel` · `PilotStrip` · `MvpView` · `SkillPopup` 등 | `battle_sim/ui/` | 인게임 HUD | ⏸ 보류 (다크 UI, `_draw` 다수) |

---

## 5. 전환 절차 (한 화면당)

1. 해당 폴더 `README.md` + 스크립트를 읽고 **노드 트리와 치수 공식**을 뽑는다
   (예: 카드 높이 = 패딩 + 제목 + 간격 + 본문 + 간격 + 버튼 + 패딩).
2. 절대 좌표를 **컨테이너**(VBox/HBox/Margin/Center/PanelContainer + 스페이서 Control)로 재구성한
   `.tscn` 을 스크립트 옆에 만든다. 바인딩할 노드엔 `unique_name_in_owner = true`.
   텍스트에는 미리보기용 샘플 문구를 넣어 에디터에서 모양이 보이게 한다.
   루트는 visible 로 저장하고, 처음에 숨기는 건 `create()` 가 한다(§2).
3. 스크립트에서 `_build` 계열을 지우고 `%노드` 바인딩으로 바꾼다. 생성은 `static func create()`.
   호출부(`Xxx.new()`)를 전부 `Xxx.create()` 로 바꾼다 (`grep -rn "Xxx.new()"`).
4. **렌더 검증** — 임시 테스트 씬을 프로젝트 루트에 만들어 실행하고 스크린샷을 비교한 뒤 지운다:
   ```gdscript
   # res://_tmp_test.gd (extends Control, 같은 이름의 .tscn 루트에 붙임)
   func _ready() -> void:
       OutgameTheme.add_background(self)
       var p := ConfirmPopup.create(); add_child(p); p.open(...)
       for i in 3: await get_tree().process_frame
       print(p.get_node("Root/SafeArea/Card").get_global_rect())
       get_viewport().get_texture().get_image().save_png("<scratchpad>/shot.png")
       get_tree().quit()
   ```
   실행: `Godot_v4.5-stable_win64.exe --path . res://_tmp_test.tscn` (경로는 `.vscode/settings.json`).
   기존 버전과 비교하려면 전환 전에 같은 하네스로 먼저 찍어 둔다.
   본 씬 확인: `... res://scenes/Lobby.tscn --quit-after 120` 후 error/warn 출력 확인.
   (autoload 식별자 때문에 `--check-only --script` 는 신뢰할 수 없다 — 루트 `CLAUDE.md` 참고)
5. 에디터에서 씬을 한 번 열고 저장(uid 부여). 임시 파일 · `.uid` 삭제 확인.
6. 폴더 `README.md` 갱신 (트리, 코드가 소유하는 것 / 씬이 소유하는 것 구분), 이 문서 §4 상태 갱신.

---

## 6. 작업 목록 (다음 세션)

- [x] **T0** `ConfirmPopup` 전환분 커밋.
- [x] **T1 공용 Theme 리소스** (완료 — variation 목록 · 재생성 명령은 `resources/README.md`) — `resources/OutgameTheme.tres`(Theme) 를 만들고
      `theme_type_variation` 으로 `PrimaryButton` · `GhostButton` · `TextButton` · `DarkButton` ·
      `Card` · `TitleLabel` · `BodyLabel` 등을 정의. 값은 `OutgameTheme.gd` 상수와 일치시키고,
      가능하면 `.gd` 상수 → `.tres` 를 생성하는 에디터 툴로 단일 출처 유지. `ConfirmPopup.tscn` 의
      임베드 스타일박스를 variation 으로 교체. (이후 화면은 "버튼 놓고 variation 고르기"로 끝남)
- [x] **T2 규칙 문서화** — 루트 `CLAUDE.md` Critical patterns 에 §3 규칙 1·4·5 요약 + 이 문서 포인터.
- [x] **T3** §4 #2 ~ #6 팝업 · 시트 전환 (웨이브 2, §7).
- [x] **T4 런타임 덤프 툴** (완료 — `resources/UiSceneDump.gd` + `UiSceneDumpRunner.gd`, 사용법은 `resources/README.md`. Lobby · HubView · BanPick 초안이 실화면과 픽셀 동일. `--shot` 은 §5-4 렌더 검증 하네스로도 쓸 수 있다) — 큰 화면(HubView, BanPick)용 초안 생성기:
      실행 중 트리의 `owner` 를 루트로 설정 → `PackedScene.pack()` → `ResourceSaver.save()`.
      결과는 절대 좌표 노드라 컨테이너로 재구성이 필요하므로 **참고용 초안**으로만 쓴다.
      작은 팝업은 손으로 옮기는 편이 낫다(시범에서 확인).
- [x] **T5** §4 #7 ~ #12 화면 전환 (웨이브 3, §7). `docs/mobile_safe_area.md` 패턴 B/C 를 씬 기반으로 갱신 — 완료.
      남은 일은 §7 "웨이브 3 종료 후".
- [ ] **T6** `editor_description` TODO 마킹을 실제로 한 번 써 보고(사용자가 마킹 → LLM 구현) 절차 다듬기.
      (2026-10-07 기준 씬에 TODO 마킹 0개 — 사용자 마킹 대기)
- [x] **T7 화면 전용 변형** — 씬 22개의 로컬 StyleBox 35개 → 접두사 변형 34개(§3 규칙 7, §7 웨이브 4).

---

## 7. 병렬 진행 현황 (2026-10-07 세션)

방식: 오케스트레이터 세션이 작업을 쪼개 에이전트(각자 git worktree `/.claude/worktrees/`)에 맡기고,
끝난 브랜치를 리뷰 → `main` 에 머지 → 이 절을 갱신한다. **에이전트는 이 문서를 고치지 않는다**
(병렬 머지 충돌 방지) — 결과 보고만 하고, 문서 갱신은 오케스트레이터가 한다.

| 웨이브 | 작업 | 담당 | 상태 |
|---|---|---|---|
| 0 | T0 ConfirmPopup 커밋 | 오케스트레이터 | ✅ |
| 1 | T1 공용 Theme 리소스 (+ ConfirmPopup 임베드 스타일 → variation) | 에이전트 A | ✅ 머지 (전후 픽셀 diff 0) |
| 1 | T2 규칙 문서화 (루트 `CLAUDE.md`) | 오케스트레이터 | ✅ |
| 1 | T4 런타임 덤프 툴 | 에이전트 B | ✅ 머지 |
| 2 | T3 #2 `ManagerTypePopup` | 에이전트 | ✅ 머지 (rect 동일, diff 0 / 부제 줄 AA 69px) |
| 2 | T3 #3 `ShopPopup` | 에이전트 | ✅ 머지 (공개 3상태 · 재오픈 diff 0, 확률표 12px — Divider 끝 1px · AA) |
| 2 | T3 #4 `CollectionDetailSheet` | 에이전트 | ✅ 머지 (rect 동일, 스크롤 밖 diff 0 / 안쪽은 정수 픽셀 배치로 ≤0.035px AA 차) |
| 2 | T3 #5 `DraftDetailPanel` | 에이전트 | ✅ 머지 (rect 동일, 아트 · 본문 diff 0. 오른쪽 패널 배경 · 스탯 칩 · 닫기 버튼은 variation 으로 바뀌어 모양이 달라짐 — 사용자 확인) |
| 2 | T3 #6 `HubSheet` | 에이전트 | ✅ 머지 (재무 · 메크 연구 · 스태프 · 리그 픽셀 diff 0, 긴 제목은 의도적으로 말줄임) |
| 끝 | 새 `.tscn` 전부 에디터에서 열고 저장 (uid 부여) | 사용자 | ✅ (12개 전부 uid 확인) |

### 웨이브 2 에서 제안된 theme variation — ✅ 반영 (렌더 전후 diff: Divider 끝 1px 만)
| 제안 | 출처 | 결과 |
|---|---|---|
| 패딩 40 짜리 팝업 카드 | ShopPopup | ✅ `PopupCardWide` (`POPUP_PAD_WIDE`) — `Pad` MarginContainer 제거. `POPUP_PAD` 는 그대로 |
| `OnFillLabel` — 색면 위 흰 글자 | ShopPopup | ✅ `ShopRevealItem` Rarity · MarkText, `ShopRateRow` ChipText. 코드 색 제거 |
| `Divider` 선 끝 연장(grow) 0 | ShopPopup | ✅ 전 Divider 에 적용 (선이 양 끝 1px 짧아짐 = 옛 `add_divider` 와 같음) |
| `OutlinePanel` · `OutlinedSunkPanel` — 옛 DraftDetailPanel 모양 | DraftDetailPanel | ✖ 사용자 결정: 지금 모양(`Card` · `SunkPanel`) 유지 |
| `SheetCard` 패딩 36/27 | CollectionDetailSheet | ✅ `SHEET_PAD_V` 추가, Sheet 를 PanelContainer 로 바꾸고 `Margin` 제거 |
| 진행 바 track/fill | CollectionDetailSheet | ✅ `ProgressTrack` · `ProgressFill` (`BAR_RADIUS`). 코드 스타일 제거 |
| `OnFillLabel` (돌파 원판 숫자) | CollectionDetailSheet | — 도달 여부에 따라 색이 바뀌는 데이터 색이라 코드 유지 |
| (나중에) `SelectableCard` 일반/선택 쌍 | ManagerTypePopup | ⏸ 보류 — 선택형 옵션 카드가 늘어나면 |

### 웨이브 3 — T5 (§4 #7 ~ #12) 화면 전환, 12개 에이전트 병렬 (2026-10-07 착수)
공유 파일 규칙: `OutgameTheme.gd/.tres` · `ScreenMetrics` 등 `resources/` 공용 파일은 에이전트가 고치지 않는다
(variation 은 제안만 → 오케스트레이터 일괄 반영). 호스트 파일(`LobbyScreen._make_tab`, `SeasonHub` 뷰 생성 블록,
`MatchFlow.gd`, `BanPickController` 의 `MechDetailPanel.new()`)은 각자 자기 `.new()` → `.create()` 한 줄만 고친다.

| 작업 | 범위 | 상태 |
|---|---|---|
| #7 a | `LobbyScreen` · `HomeTab` (+ `Lobby.tscn`) | ✅ 머지 (+ `LobbyCurrencyCell` · `LobbyTabButton`. 재화 줄 글자 <1px 이동 외 diff 0. 아래 인셋에서 액션 바가 탭 바를 23px 덮던 버그 수정) |
| #7 b | `CollectionTab` · `ManagerTab` | ✅ 머지 (+ `ManagerStatRow`. rect 동일, 카드 · 바 모서리만 variation 값으로(20→18, 8→7). `CollectionCell` · 프리셋 칩 · `TraitPickerView` 는 RunSetup 과 공용이라 코드 유지) |
| #7 c | `ShopTab` · `PassTab` | ✅ 머지 (+ `PassRow` · `ShopShardRow` · `ShopCraftRow` · `ShopExchangeRow` · `ShopRateChip`. rect 동일, 세그먼트 트랙 모서리 16→12 · 패스 바 9→7) |
| #8 | `run_setup/` 전체 (`RunSetupScreen` · `TeamDraftView` · `ManagerStepView` · `ChoiceListView` · `TeamStepView` · `PilotThumb`) | ✅ 머지 (+ `StepChip` · `ScenarioCard` · `TeamCard` · `DraftSlot` · `PilotThumb` · `RoleBadge` 아이템 씬. 대부분 diff 0, 필터 줄 ±1px · 감독 스탯 카드 모서리 18) |
| #9 | `RunResultScreen` | ✅ 머지 (`scenes/RunResult.tscn` 이 소유, `create()` 없음 + 행 아이템 씬 5개. rect 동일, AA ≤3/255. 홀수 폭 태블릿에서 카드 0.5px 왼쪽) |
| #10 a | `SeasonHub` UI · `HubView` · `EndingView` · `GameOverView` | ✅ 머지 (+ `HubRosterRow` · `HubManageCard`. 엔딩 · 게임오버 diff 0, 허브는 관리 카드 모서리 18 · 칸 정수 픽셀. 하단 바는 `HubView.fit_bottom_bar`) |
| #10 b | `LeagueView` · `BracketView` · `IntlBracketView` | ✅ 머지 (+ `LeagueRow` · `BracketMatchBox`/`IntlMatchBox` 아이템 씬. rect 동일, 인셋 켠 12장 diff 0 / 인셋 0 은 AA 1/255) |
| #10 c | `FinancePanel` · `StaffPanel` · `MasteryPanel` (HubSheet 본문) | ✅ 머지 (+ 행 아이템 씬 10개. 23개 상태 rect · 본문 높이 동일. 바 끝 둥글게(`ProgressTrack`), 카드 모서리 18) |
| #10 d / #11 | `WeekProgressView` · `PressConferenceView` · `MessengerView`(틀) | ✅ 머지 (+ 주간 카드 아이템 씬 8개. 메신저 · 기자회견 diff 0, 주간 화면은 레일 칩 · 칸 ~1px. 말풍선은 코드 유지) |
| #11 | `TrainingView` (틀) | ✅ 머지 (+ `TrainingThumb` · `TrainingCourseCard` · `TrainingCoursePopover`. 보드 `_draw`·드래그 코드 유지, rect 동일, AA ≤50px) |
| #12 a | `BanPickController` UI | ✅ 머지 (`BanPickView` + 아이템 씬 5개, 2593→1634줄. 밴 · 픽 · 배치 결과와 BattleSim 핸드오프 동일, 시트 ~1px · 배치 블록 ~0.5px, 판 모서리 18) |
| #12 b | `MechDetailPanel` · MatchPrep UI · `MatchCheatMenu` | ✅ 머지 (+ `MechMasteryRow` · `MechQuirkRow` · `MechCardCell` · `MatchPrepView` · `MatchCheatItem`. 기벽 없는 경우 diff 0, 기벽 줄은 실제 줄바꿈으로 아래 ~3px. 다크 모달 variation 미정) |
| 끝 | `mobile_safe_area.md` 패턴 B/C 씬 기반으로 갱신 | ✅ |
| 끝 | 새 `.tscn` 전부 에디터에서 열고 저장 (uid 부여) | 사용자 ⬜ |
| 끝 | 제안 variation 반영 — 사용자 결정: 모서리는 지금 모양 유지, `MechDetailPanel` 은 흰 테마로 | ✅ 1단계 `resources/` (Negative/Positive/LinkLabel · Bar*Button · BarSeparator · Accent/SurfaceChip · Selectable* 쌍 · `OutgameTheme.fit_bottom_bar`) → 2단계 meta · season · match_flow 병렬 머지. 하단 바 헬퍼 4갈래 → 1개 (로비 코드 바만 `add_bottom_bar`) |

### 웨이브 3 에서 제안된 theme variation — 결과
공용으로 쓰는 것은 웨이브 3 "끝" 행에서 공용 변형으로, 한 화면 전용은 웨이브 4 에서 **접두사 화면 변형**으로 반영.

| 제안 | 쓰는 곳 | 결과 |
|---|---|---|
| `NegativeLabel` · `PositiveLabel` · `LinkLabel` | 리그 PO 표시, 게임오버 제목, 감독 탭 리셋, 재무/스태프, RunSetup 에러, 훈련 팝오버, 주간 메크 줄 | ✅ 공용 |
| `BarPrimaryButton` · `BarGhostButton` (각진 하단 바 버튼) + 공용 하단 바 헬퍼 | 거의 모든 화면 | ✅ 공용 (`Bar*Button` · `fit_bottom_bar`, 4갈래 → 1개) |
| `ScreenBackground` (BG 패널) | 화면 배경 ColorRect 전부 | ⬜ 미반영 (선택) — 배경은 `ColorRect` 색 |
| `SectionCard` · `SectionCardAmber` (r24, 패딩 40/28) · `AccentDivider` | RunResult | ✅ `RunResultSectionCard` · `RunResultSectionCardAmber` · `RunResultAccentDivider` (+ `RunResultTraitCard`) |
| `AccentChip` · `SurfaceChip` · 흰 pill (r = 높이/2) | RunResult, 홈 탭 "경기 진행 중", 시나리오 연봉 칩, 상점 확률 칩 | ✅ 공용 |
| `SurfaceBar` · `ToastPanel` · `DividerStrong` · `AlertDot` · `BarSeparator` | 로비 재화 줄 · 탭 바 · 토스트, 허브 | ✅ `LobbySurfaceBar` · `LobbyToast`, `BarSeparator` 공용. `DividerStrong` · `AlertDot` 은 `ColorRect` 색이라 해당 없음 |
| `OutlinePanel` · `OutlinedSunkPanel` | 상점 행 타일 · 개발용 행 | ✅ `ShopRowPanel` (Shop*Row 3개 공용) · `ShopDevRowPanel` |
| `DangerCard` (연빨강 + 2px NEGATIVE) | 감독 탭 프레스티지 리셋 | ✅ `ManagerDangerCard` |
| `SelectableTile` / `SelectableCard` (일반/선택 쌍) | BanPick 필터 탭 · 그리드 칸, RunSetup 선택 카드 · 필터 · 썸네일, ManagerTypePopup, 컬렉션 필터 | ✅ 공용 (컬렉션 필터는 웨이브 4) |
| `RailPanel` · `RailLabel` · `HighlightPanel` | 주간 요일 레일, 저녁 선택 파일럿 | ✅ `WeekRail` · `WeekEveningHighlight` · `WeekDayChip`/`WeekDayChipToday`. `RailLabel`(글자색)은 ⬜ 색 override 유지 |
| `OnFillTextButton` | 상점 "확률 보기" | ⬜ 색 override 유지 (StyleBox 아님) |
| 훈련 전용: 썸네일 테두리 r8 · 코스 카드 r12 · 팝오버 카드 r10 · `SunkPanel` r8 | TrainingView | ✅ `TrainingThumb*` · `TrainingCourse*` (7개) |
| BanPick 전용: `AccentSheetCard` (3px 앰버) · 밴 칩 · 드래그 고스트 | BanPick | ✅ `BanPickSheetCard` · `BanPickBanChipPanel` · `BanPickDragGhost` (+ `BanPickMechSlotFrame` · `BanPickPortraitRim`) |
| 다크 모달 (`DarkModalPanel` · `DarkChip` · `DarkModalButton`) | `MechDetailPanel` | ✖ 사용자 결정: 흰 테마로 전환 (불필요) |
| 모서리 반경 되돌리기용 (r12~16 카드, 직각 진행 바, r16 세그먼트 트랙) | 카드 20→18, 바 8/9→7, 세그먼트 16→12 로 바뀐 곳들 | ✖ 사용자 결정: 바뀐 모양 유지 (불필요) |

### 웨이브 3 종료 후 확인 (main, 12개 머지 전부 반영)
- `Lobby` · `RunSetup` · `RunResult` · `Season` · `MatchFlow` 헤드리스 실행 — error/warn 없음.
- 통합 렌더(오케스트레이터): 로비 5탭 전환, Season 9개 화면 라우팅(HUB → PRESS → TRAINING → WEEK → LEAGUE →
  PLAYOFF → INTL → GAME_OVER → ENDING), MatchFlow PREP · BAN_PICK — 에러 없음, 화면 정상.
- 남은 일:
  1. **사용자** — 새 `.tscn` 에디터에서 열고 저장 (uid). 2026-10-07 재확인: 83 → **55개 남음** (`addons/` 제외 —
     `match_flow/**` 13 · `meta/**` 29 · `season/` finance · league · mastery 11 · `scenes/RunSetup` · `RunResult`).
     목록: `for f in $(git ls-files '*.tscn'); do head -1 "$f" | grep -q 'uid="uid://' || echo "$f"; done`
  2. ~~위 variation 표 반영~~ ✅. ~~단일 화면 전용 스타일 로컬 유지~~ → 사용자 결정으로 웨이브 4 에서 화면 변형으로 분리 ✅.
     ~~후속 후보: `CollectionTab` 필터 → `SelectableTile`, `DraftDetailPanel` `%SafeArea`~~ ✅ 웨이브 4.
  3. 코드에 남은 공용 위젯: `CollectionCell` · `ManagerUi.add_preset_chips` · `TraitPickerView` (컬렉션 · 감독 탭 · RunSetup 공용),
     `IntelView` (MatchPrep · 리그 팀 상세 — `HubSheet` 본문에 절대 좌표 자식을 만드는 유일한 곳), `MessengerView` 말풍선,
     `BanPickOrderRow`. 아이템 씬으로 옮길지는 별도 작업 (⬜ 미결정).
  4. ~~`HubSheet.gd` 머리 주석 · `%Body` `editor_description`~~ ✅ 이미 "리그 팀 상세만 해당" 으로 갱신돼 있음.
  5. ~~`DraftDetailPanel` 안전 영역~~ ✅ 웨이브 4.
  6. 병렬 에이전트 교훈: 스크래치패드와 `user://`(모든 worktree 공용) 를 같이 쓴다 — 에이전트마다 하위 폴더,
     `Season.tscn` 실행은 `run_test.save` 를 자동 저장하므로 하네스는 메모리 데이터 + 백업/복원.

### 웨이브 4 — 남은 일 정리 (2026-10-07, 단일 세션)
| 작업 | 내용 | 검증 |
|---|---|---|
| `DraftDetailPanel` 안전 영역 | `%SafeArea`(full rect, 오프셋 = 인셋) 아래로 `%Column` 이동. 위끝 150 고정, 아래끝은 안전 영역 바닥 −80 앵커(아래로만 자람). `PANEL_MAX_H` 상수 삭제 → 최대 높이 = 칸 높이 − 간격 − 닫기 (앵커로 계산) | 인셋 0: 이전과 같은 rect. 인셋 (0,140,0,100): 받침 290 시작 · 1350 으로 제한(스크롤) · 닫기 아래끝 1740 |
| `CollectionTab` 필터 | 코드 `flat_style` (r12, 테두리 2) → `SelectableTile` ↔ `SelectableTileOn` 변형 전환 (런 준비 · 밴픽 필터와 같은 모양, r8 · 선택 테두리 3) | 의도된 모양 변경 |
| 화면 전용 변형 (T7) | 씬 22개 로컬 StyleBox 35개 → `OutgameTheme._add_screen_variations` 의 접두사 변형 34개, 공용 변형에서 파생 (§3 규칙 7). 데이터 색 6곳(밴픽 칸 · 초상 테두리, 편성 칸, 역할 배지, 단계 알약, 상점 배너)과 훈련 · 로비가 읽던 씬 스타일은 `variation_box()` 사본에 색만. 주간 요일 칩은 변형 전환 | 로비 4탭 · RunResult · RunSetup · 허브 · 밴픽 실화면 diff 0 (밴픽 타이머 영역은 원래 매 실행 다름). 씬 단독 렌더 23개 diff 0 — 예외는 코드가 런타임에 칠하는 미리보기 색(역할 배지 · 진영 테두리)뿐 |

남은 것 (웨이브 4 이후):
- ⬜ 데이터가 아닌 **글자색 override** — 주간 `%WeekLabel` (`RAIL_TEXT`, 제안명 `RailLabel`), 상점 "확률 보기" (`OnFillTextButton`).
  StyleBox 가 아니라 이번 범위 밖. 나머지 색 override 는 상태 · 데이터 색의 미리보기(코드가 덮음).
- ⬜ 위 "웨이브 3 종료 후" 1 (uid 55개, 사용자) · 3 (코드 공용 위젯) · §4 #13 BattleSim HUD (보류) · §6 T6 (TODO 마킹 대기).

> 웨이브 2 는 T1 머지 직후 시작 (T4 와 무관하므로 T4 진행 중에 병렬 착수).

### 웨이브 2 종료 후 확인 (main, 머지 전부 반영)
- `Lobby` · `RunSetup` · `Season` · `MatchFlow` 헤드리스 실행 — error/warn 없음 (godot-mcp 포트 소음 제외).
- 남은 일:
  1. ~~**사용자** — 새 `.tscn` 전부 에디터에서 열고 저장(uid)~~ ✅ 12개 전부 완료.
  2. ~~DraftDetailPanel 오른쪽 패널 모양 결정~~ ✅ 지금 모양 유지.
  3. ~~제안 variation 일괄 반영~~ ✅ (위 표).
  4. 알려진 동작 차이: `CenterContainer` 로 가운데 정렬한 팝업(ShopPopup · ManagerTypePopup)은 안전 영역보다 길어지면 위아래로 넘침 (옛 코드는 위 고정). 현재 데이터로는 해당 없음.
  5. ~~DraftDetailPanel 안전 영역~~ ✅ 웨이브 4 (`%SafeArea`).
