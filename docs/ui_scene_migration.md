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
- 헤드리스/CLI 로 저장한 `.tscn` 에는 uid 가 안 붙는다. **에디터에서 한 번 열고 저장**하면 붙는다 (미처리).
- **임시 스타일 중복**: 버튼 · 카드 스타일박스를 `OutgameTheme` 값에서 복사해 씬에 넣었다.
  팔레트가 코드에서 바뀌면 이 씬은 안 따라간다 → §6 T1 (공용 Theme 리소스)로 해소.

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
| 5 | `DraftDetailPanel` | `meta/run_setup/` | 모달 | ✅ 전환 (+ `DraftStatChip` 아이템 씬) — **스타일 변경 확인 필요** |
| 6 | `HubSheet` | `season/` | 시트 (허브 관리 카드 공용 틀) | ✅ 틀만 전환 (본문은 #10) |
| 7 | `LobbyScreen` + `HomeTab` · `CollectionTab` · `ManagerTab` · `ShopTab` · `PassTab` | `meta/lobby/` 등 | 화면 / 탭 | ⬜ |
| 8 | `RunSetupScreen` + `TeamDraftView` · `ManagerStepView` · `ChoiceListView` · `TeamStepView` · `PilotThumb` | `meta/run_setup/` | 화면 | ⬜ |
| 9 | `RunResultScreen` | `meta/run_result/` | 화면 | ⬜ |
| 10 | `SeasonHub` / `HubView` · `LeagueView` · `BracketView` · `IntlBracketView` · `WeekProgressView` · `PressConferenceView` · `EndingView` · `GameOverView` · `FinancePanel` · `StaffPanel` · `MasteryPanel` | `season/**` | 화면 / 패널 | ⬜ |
| 11 | `TrainingView` · `MessengerView` | `season/training/`, `press/` | `_draw` 혼합 — 틀만 씬 | ⬜ |
| 12 | `BanPickController` UI · `MechDetailPanel` · `MatchPrep` UI · `MatchCheatMenu` | `match_flow/**` | 화면 | ⬜ |
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
- [ ] **T5** §4 #7 ~ #12 화면 전환. `docs/mobile_safe_area.md` 의 패턴 B/C 를 씬 기반 방식으로 갱신.
- [ ] **T6** `editor_description` TODO 마킹을 실제로 한 번 써 보고(사용자가 마킹 → LLM 구현) 절차 다듬기.

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

### 웨이브 2 에서 제안된 theme variation (웨이브 끝에 한 번에 반영 — 병렬 중엔 테마 수정 금지)
| 제안 | 출처 | 현재 우회 |
|---|---|---|
| 패딩 40 짜리 팝업 카드 (또는 `POPUP_PAD` 축소) — 결과 카드 5장이 `PopupCard` 48 안에 안 들어감 | ShopPopup | `MarginContainer` −8 |
| `OnFillLabel` — 색면 위 흰 글자 | ShopPopup | 코드에서 font_color |
| `Divider` 선 끝 연장(grow) 0 — 정확히 1px 폭 | ShopPopup | 없음 (1px 차이 허용) |
| `OutlinePanel` (흰 · 2px `BORDER` · r14 · 그림자 없음) — 옛 DraftDetailPanel 배경을 되살릴 경우 | DraftDetailPanel | 지금은 `Card` |
| `OutlinedSunkPanel` (`SURFACE_SUNK` · 2px · r16) — 옛 스탯 칩 | DraftDetailPanel | 지금은 `SunkPanel` |
| `SheetCard` 패딩 36/27 변형 — `MarginContainer` 제거 | CollectionDetailSheet | `MarginContainer` 36/27/36/27 |
| 진행 바 track/fill (r7, sunk/accent) | CollectionDetailSheet | 코드 스타일 |
| `OnFillLabel` (재제안 — 돌파 원판 숫자) | CollectionDetailSheet | 코드에서 font_color |
| (나중에) `SelectableCard` 일반/선택 쌍 — 선택형 옵션 카드가 늘어나면 | ManagerTypePopup | `ManagerTypeOption.gd` 의 `flat_style` |

> 웨이브 2 는 T1 머지 직후 시작 (T4 와 무관하므로 T4 진행 중에 병렬 착수).

### 웨이브 2 종료 후 확인 (main, 머지 전부 반영)
- `Lobby` · `RunSetup` · `Season` · `MatchFlow` 헤드리스 실행 — error/warn 없음 (godot-mcp 포트 소음 제외).
- 남은 일:
  1. ~~**사용자** — 새 `.tscn` 전부 에디터에서 열고 저장(uid)~~ ✅ 12개 전부 완료.
  2. **사용자 결정** — DraftDetailPanel 오른쪽 패널을 새 variation 모양으로 둘지, 옛 모양(`OutlinePanel` 등 추가)으로 되돌릴지.
  3. 제안 variation 표를 한 번에 `OutgameTheme.gd` 에 반영 → `.tres` 재생성 → 해당 씬의 우회(MarginContainer · 코드 색) 제거.
  4. 알려진 동작 차이: `CenterContainer` 로 가운데 정렬한 팝업(ShopPopup · ManagerTypePopup)은 안전 영역보다 길어지면 위아래로 넘침 (옛 코드는 위 고정). 현재 데이터로는 해당 없음.
  5. DraftDetailPanel 은 원래부터 안전 영역 처리가 없음(닫기 버튼 y 최대 1840) — 제스처 영역 겹침 가능, 별도 작업.
