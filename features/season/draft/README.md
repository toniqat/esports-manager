# Team Draft

Initial campaign step: the player picks one pilot per role (5 total) from
the **네임드 25인** pool. The displaced pilot from team-0 swaps with the picked
pilot's prior team — every team always has exactly one pilot per role.

**화면은 우마무스메식 인물 고르기다.** 아래 절반이 스크롤되는 캐릭터 썸네일
격자이고, 그 위에 역할 필터 한 줄, 그 위에 뽑은 5인의 **상체 일러스트**가
가로로 선다. 예전의 5열(역할) × 5행(순위) 고정 격자는 25명을 한 화면에
욱여넣느라 칸을 키울 수 없었고, 그래서 얼굴이 48px 라 "누구를 뽑는가"가
이름표로만 읽혔다 — 격자가 스크롤되면서 칸 크기가 인원 수에서 풀려났다.

## 화면은 두 모드를 오간다 — PICK ↔ CONFIRM
**PICK** 이 위 그림이고, 하단 바의 **"다음"**(다섯 칸이 다 차야 활성)이
**CONFIRM** 으로 넘긴다. 넘어가는 동안 **픽창(필터 줄 + 격자 + 뒤판)이 화면
아래로 빠지고 선택 5인 블록이 화면 세로 가운데로 내려온다** — 두 움직임이 한
트윈(`MODE_ANIM_SEC` 0.38초, cubic in-out)으로 돌고, "뒤로"는 그 반대를 돈다.
픽창은 하단 바보다 먼저 붙어 있어 빠져나가는 격자가 바 뒤로 숨는다. 연출이 도는
동안(`_busy`)은 모든 입력을 무시한다.

CONFIRM 의 주 행동은 **"게임 시작"**(예전 "드래프트 확정")이다. 팀 결성은
아웃게임의 마지막 화면이고 그 다음부터가 캠페인이라 화면을 그냥 갈아 끼우지 않는다 —
**암전(0.30초) → 가짜 로딩(0.50초, `LOADING` + 막대) → 밝아짐(0.35초)**
(`_play_launch_transition` → 공용 `resources/SceneFade.gd`). 덮개는 **root 에
붙인 `CanvasLayer`(layer 100)** 라 드래프트가 숨겨진 뒤에도 남는다(밴픽 → 전장
전환도 같은 헬퍼를 쓴다). `validate_draft` 는 **암전 전에** 돌고(거절될
확정이면 화면을 가리지 않는다), `apply_draft` · 상세 팝업 닫기 · `goto(HUB)`
(= 드래프트 직후 자동 저장)는 **화면이 다 가려진 순간에** 돈다(`_commit_draft`).

**선택 5인 블록은 `_slot_row` 한 Control 의 지역 좌표로 산다.** 그래야 CONFIRM
이 그 노드의 y 하나만 밀어 블록째 내릴 수 있다. 픽창도 같은 이유로
`_pick_root` 한 Control 에 모여 있다.

## 화면에서 걷어 낸 것들
- **제목("TEAM DRAFT")과 인원 수("내 팀 N/5")** — 다섯 칸이 채워지는 것 자체가
  이미 그 답이다.
- **썸네일 칸의 역할군 이름 · 파일럿 이름 · 종합 스탯 세 줄** — 그 자리는
  **왼쪽 위 역할군 배지** 하나로 줄었고(밴픽 메크 격자와 **같은 배지**), 칸은
  정사각이 되어 얼굴이 칸을 다 쓴다.
- **일러스트 위의 포지션 글자(탑 · 정글 …)와 아래의 이름** — 역할은 일러스트
  **왼쪽 위의 역할군 배지**가(격자 썸네일과 같은 `PilotThumb.add_role_badge`,
  **빈 칸에도 선다** — 빈 칸이 어느 역할의 자리인지를 그 배지가 말한다),
  이름은 상세 팝업이 들고 있다.
- **일러스트 밑의 `역할 · 원소속` 한 줄**과 **하단의 파일럿 스킬 구성 패널** —
  둘 다 상세 팝업이 통째로 들고 있다. 고르는 화면에 요약을 늘어놓으면 그 요약을
  읽느라 정작 얼굴을 안 본다.

**상세 팝업을 여는 자리가 이름 칸에서 일러스트 자체로 옮겨 갔다.** 예전에는
"일러스트를 누르면 슬롯을 비우려는 탭과 헷갈린다"는 이유로 아래 이름 칸이 그
역할을 했는데, 슬롯을 비우는 조작은 **격자에서 같은 썸네일을 다시 누르는 것**
하나뿐이라 위 칸에는 애초에 경쟁하는 탭이 없었다. 이제 인게임에서 파일럿 얼굴을
눌러 상세를 여는 것과 같은 몸짓이다. 이름 칸은 그냥 Label 로 남는다.

**모브 파일럿 15명은 격자에 뜨지 않는다.** `pilot_skills.csv` 가 25개뿐이라
40명 중 15명은 고유 스킬이 없고(`players.is_mob = 1`), 그쪽은 초상화도 실루엣
컷인 "이름 없는 선수"다 — 플레이어가 뽑을 대상이 아니라 AI 팀의 머릿수를 채우는
배경이고, 적으로는 여전히 만난다. `get_pool_grid()` 가 그 필터의 유일한 지점이다.

**팀 0(플레이어 시작 팀)의 다섯 자리는 전부 네임드다.** `apply_draft` 의 맞교환이
네임드끼리만 일어나야 팀별 네임드 수가 드래프트로 흔들리지 않는다 — 네임드 25명은
팀 0 에 5명, 나머지 20명이 7개 AI 팀에 2~3명씩 흩어져 있다(`data/csv/players.csv`).

## Files
| File | Role |
|---|---|
| `TeamDraft.gd`        | `class_name TeamDraft extends Control` — data layer. Owns `validate_draft()`, `apply_draft()`, `get_pool_grid()`, 그리고 화면이 함께 읽는 표 둘 — **슬롯 순서**(`SLOT_ROLES` / `SLOT_NAMES` / `slot_of_role`), **스킬 조회**(`skill_def_for` / `skill_type_label`). 카드 후보 풀 헬퍼 넷은 삭제됐다 — 아래 절. Builds `TeamDraftView` lazily via `ensure_view()` (called by `SeasonHub` after `init_season`). |
| `TeamDraftView.gd`    | `class_name TeamDraftView extends Control` — procedural UI (선택 5인 일러스트 행 + 필터 행 + 스크롤 썸네일 격자 + 하단 스킬 패널/확정 버튼). Lives as a child of the `TeamDraft` node. |
| `PilotThumb.gd`       | `class_name PilotThumb extends Button` — 격자 한 칸. **정사각(200×200)이고 얼굴 크롭 하나와 왼쪽 위 역할군 배지가 전부다.** 선택되면 금색 테두리 + 우상단 체크 배지. Emits `thumb_tapped(pilot_id)`. 두 static 헬퍼를 상단 일러스트와 함께 쓴다 — `add_rounded_art`(**둥근 사각형 마스크**: 둥근 `StyleBoxFlat` 을 그리는 `Panel` + `clip_children = CLIP_CHILDREN_ONLY`. 마스크 굴림은 칸 굴림에서 안쪽 여백을 뺀 값이라 테두리와 같은 중심의 곡선이 된다 — `clip_contents` 는 사각형으로만 자른다) · `add_role_badge`. |
| `DraftDetailPanel.gd` | `class_name DraftDetailPanel extends CanvasLayer` — **파일럿 상세 팝업**. 좌 전신 아트 / 우 스크롤 정보 패널(스탯 칩 6개 → 파일럿 스킬. **받침 높이는 내용이 정한다**). `open(p: PlayerData)` **한 인자뿐이다** — 아래 "두 화면이 함께 쓴다" 절. |

`PilotCard.gd` / `PilotCard.tscn` 은 **삭제됐다** — 200×175 칸에 스탯 막대 다섯
줄을 세우던 예전 격자 카드이고, `PilotThumb` 이 그 자리를 대신한다.

## 다섯 칸은 역할 고정
슬롯 순서는 `GameEnums.Role` 의 열거값 순서가 아니라 **MOBA 라인 순서**다 —
탑(TANK) · 정글(ASSASSIN) · 미드(FIGHTER) · 원딜(SNIPER) · 서폿(SUPPORT),
`TeamDraft.SLOT_ROLES` 한 표에 있다. 열거값 순서를 그대로 쓰면 정글러가 세 번째,
서포터가 네 번째로 앉는데 그 배열은 플레이어가 아는 라인업과 대응하지 않는다
(인게임 파일럿 스트립이 같은 이유로 `HudBuilder.LANE_SEAT_ORDER` 를 따로 든다).

**필터 버튼과 위쪽 다섯 칸이 같은 표를 읽으므로** 순서가 갈릴 수 없다 — 필터
`i = 0` 이 "전체"(-1)이고 그 뒤가 `SLOT_ROLES[i - 1]` 이다.

자유 순서(선착순 5칸)를 쓰지 않은 이유는 `validate_draft` 가 "역할당 정확히
1명"을 강제하기 때문이다. 자유 순서면 화면에서만 가능한 조합이 생겨 규칙을
확정 버튼에서 처음 거절당한다 — 규칙은 고를 때 보여야 한다.

## DraftDetailPanel — 두 화면이 함께 쓴다
이 팝업은 **아웃게임에서 파일럿 한 명을 들여다보는 유일한 자리**다. 여는 곳이
둘이다 — 이 화면(선택 슬롯의 상체 일러스트)과 **밴픽의 배정 단계**(양 팀 파일럿
초상화, `features/match_flow/ban_pick/`). 그래서 `TeamDraft` 인스턴스를 요구하지
않는다: 필요한 것은 `PlayerData` 한 장과 오토로드 `GameManager` 뿐이다.

그 탈출이 `TeamDraft.skill_def_for` 를 **삭제**했다 — 하단 스킬 패널이 사라지며
유일한 소비자가 팝업 하나가 됐고, 팝업이 `GameManager.skill_def()` 를 직접 읽는다.
같은 탈출이 `candidate_cards_for_role` 을 **static** 으로 만들어 카드 풀을 인자로
받게 했었는데, 후보 카드 절 자체가 없어지며 그 함수도 함께 사라졌다 — 아래 절.

## 상체 일러스트 (어깨~얼굴) — `PilotImages.bust_for`
`tall/N_tall.png`(210×700, 머리~허벅지)의 **윗부분**을 `AtlasTexture` 로 잘라
쓴다(`PilotImages.BUST_REGION` = `Rect2(18, 0, 174, 351)`). `full` 아트에서
직접 자르지 않는 것이 요점이다 — full 은 파일럿마다 인물 배율이 달라 다섯 칸의
얼굴 크기가 들쭉날쭉해지는데, `tall` 은 이미 얼굴 사각형을 템플릿 매칭으로 찾아
배율을 통일해 둔 컷이라 그 위에서 자르면 다섯 얼굴이 같은 크기로 선다
(`resources/images/pilot/make_tall_crops.py` 참조).

**크롭이 `PilotImages` 로 옮겨 갔다**(예전 `TeamDraftView.BUST_REGION`) — 밴픽의
배정 단계가 같은 크롭을 쓰게 되면서, 두 화면이 각자 자기 `Rect2` 를 들고 있으면
한쪽만 고쳐도 두 화면의 얼굴 크기가 갈린다.

영역 비율(174 : 351 = `PilotImages.BUST_ASPECT` 0.496)은 칸 비율(204 : 412 =
0.495)과 같게 잡아 늘어남이 없다 — 둘 중 하나만 바꾸면 얼굴이 찌그러진다.

## 파일럿 카드 3장 — 선수마다 고정이라 다시 보여 준다
상세 팝업 맨 아래에 **"파일럿 카드"** 절이 있다(`DraftDetailPanel._build_pilot_cards`).
그 선수의 고정 3장(`GameManager.pilot_card_ids_for(pd)`)을 설명판
(`CardDescBox.build(cd, w, light = true)`)으로 위에서부터 쌓는다 — 이름 · 비용 ·
키워드 줄 · 설명문 · 키워드 풀이가 한 판에 다 들어 있어 카드 노드 격자가 필요 없다.

**지금은 이 절이 판단의 근거가 된다.** 파일럿 카드가 경기 시작 시 표집되던 시절에는
드래프트에서 보여 줄 수 있는 것이 역할별 **후보 풀**뿐이었고, 그 목록은 같은 역할이면
누구를 뽑아도 같아서 절째로 지웠었다. 지금은 선수마다 고정(`players.pilot_cards`,
비었으면 선수 id 씨앗 뽑기)이라 여기서 본 3장이 인게임에서 손에 잡히는 바로 그 3장이고,
같은 역할이라도 선수마다 다르다.

그때 함께 삭제된 것 — `DraftDetailPanel` 의 `_build_card_sections` / `_cards_in_cat` /
`_build_card_grid`, 그리고 `TeamDraft` 의 후보 풀 헬퍼 넷(`pilot_card_slots_for_role` /
`candidate_cards_for_role` / `slot_summary_for_role` / `cat_label`) — 은 되살리지
않는다. 카드의 원본은 `GameManager.pilot_card_ids_for` 하나다.

**받침 높이가 내용을 따라가게 됐다.** 카드 격자가 있을 때는 우측 패널이 언제나
꽉 차서 `PANEL_TOP` ~ `PANEL_BOTTOM` 고정으로 충분했는데, 스탯 칩과 스킬 한
문단만 남으니 아래 절반이 빈 흰 판이 됐다. 지금은 위쪽만 못박고 아래끝이 내용에
맞춰 올라오며(넘치면 `PANEL_BOTTOM` 에서 멈추고 그때부터 스크롤이 일한다) **닫기
버튼이 그 아래끝을 따라간다** — 인게임 상세 패널의 `_reposition_close` 와 같은
규칙이다.

## UI flow
1. `SeasonHub._show_draft()` calls `TeamDraft.ensure_view()` then sets `TeamDraft.visible = true`.
2. `TeamDraftView` instantiates one `PilotThumb` per pool entry, laid out 5 columns wide inside a `ScrollContainer`. 격자 순서는 슬롯 순서 안에서 종합 스탯 내림차순. 모브는 `get_pool_grid()` 가 이미 걸러 냈다.
3. 필터 버튼(전체/탑/정글/미드/원딜/서폿)이 `_reflow_grid()` 를 돌린다 — **보이는 칸만 좌표를 다시 받는다**. 숨긴 칸을 그대로 두고 `visible` 만 끄면 빈 구멍이 남아 5열 배치가 무너진다.
4. 썸네일을 누르면 그 파일럿이 **자기 역할 칸**에 앉는다. 같은 칸의 같은 사람을 다시 누르면 비고, 다른 사람을 누르면 교체.
5. 채워진 칸의 **상체 일러스트**를 누르면 `DraftDetailPanel` 이 열린다. 그 칸은 `Button` 이고 **`flat` 이면 안 된다** — flat 버튼은 스타일박스를 통째로 무시해서 빈 칸의 테두리와 바탕이 사라지고 "선택 없음" 글자만 허공에 뜬다(실측).
6. **"다음"** 은 다섯 칸이 다 찼을 때만 활성화되고, 누르면 CONFIRM 모드로 넘어간다(픽창이 사라지고 5인이 가운데로 내려온다). "뒤로"가 그 반대다.
7. **"드래프트 확정"** 은 `_picks` 를 **역할 순서**(`GameEnums.Role`)로 다시 정렬해 `apply_draft()` 에 넘긴다 — `validate_draft` 는 순서를 보지 않지만, 화면의 슬롯 순서를 그대로 흘려보내면 이 목록이 무엇의 순서인지가 호출부마다 달라진다.
8. Confirm → `TeamDraft.apply_draft()` rewires team rosters → **`_detail.close()`** → `SeasonHub.goto(Screen.HUB)`. 팝업은 `CanvasLayer` 라 부모 Control 의 `visible` 을 따르지 않는다 — 열어 둔 채 넘어가면 딤이 화면에 그대로 남는다.

## Layout (1080×1920 portrait)
**아래에서 위로 쌓는다** — 격자를 하단 바에 매달고(`grid_y()`), 필터(`filter_y()`)와
선택 5인(`pick_row_y()`)이 차례로 그 위에 앉는다. 격자는 **썸네일 3.5줄**
(`GRID_VISIBLE_ROWS`, 높이 724)이고 줄인 만큼 선택 5인이 내려왔다 — 반 줄이
잘려 보이는 것이 곧 "아래로 더 있다"이다.

`_slot_row` 는 **일러스트 한 줄뿐**이다(204×412 버튼 ×5, 간격 12, x0 = 6). 그림은
역할 색 테두리(3px) 안으로 물려 둥근 마스크로 깎이고, 왼쪽 위에 역할군 배지.

화면 좌표 (세이프 인셋 0 · 9:16 실측):

| Y range     | Block |
|---|---|
| 520..932    | `_slot_row` (PICK 모드) — `filter_y() − 32 − 412` |
| 964..1028   | 필터 버튼 6개 (x0 24, 총 폭 1032) |
| 1056..1780  | 썸네일 격자 뒤판 + `ScrollContainer` (5열 × `PilotThumb` 200×200, 3.5줄) |
| 하단 바     | PICK = "다음" 전폭. CONFIRM = "뒤로"(1) + "게임 시작"(2) |
| **754..1166** | CONFIRM 모드의 `_slot_row` — 화면 세로 가운데(`confirm_row_y()`) |

모든 y 는 상수가 아니라 `OutgameTheme.bottom_bar_top()` 에서 역산한다 — 하단
버튼은 이 화면에서 가장 아래의 터치 대상이라 홈 인디케이터 / 제스처 바와 맞닿는다.

상세 팝업(`DraftDetailPanel`)은 자기 `CanvasLayer`(layer 20) 위에 선다:
좌 전신 아트(높이 1400, 아래끝 2010, 중심 x 300) / 우 정보 패널
(x 596, w 460, y 150..1740, 안쪽은 `ScrollContainer`) / 닫기 (1756..1840).
닫기 버튼에 **불투명 스타일이 필수다** — 그 자리는 드래프트 화면의 "드래프트
확정" 버튼과 겹치는데, 기본 Button 테마는 반투명이라 딤 아래의 그 글자가 비쳐
두 라벨이 한 칸에 겹쳐 읽혔다.

---

## 격자 스크롤 — `DragScroll`

격자는 **`DragScroll` 이 굴린다**(`resources/DragScroll.gd`). 엔진의 터치 드래그는
데스크톱 마우스로는 아예 안 굴렀고 폰에서도 썸네일 위의 탭과 얽혀 "안 굴러간다"는
보고가 났다. `DragScroll` 은 마우스와 터치를 같은 경로로 받아 14px 문턱을 넘으면
스크롤로 판정하고, **그 순간 눌려 있던 썸네일의 눌림을 취소**한다 — 스크롤하려던
손이 파일럿을 고르지 않는다. 썸네일의 `MOUSE_FILTER_PASS` 는 그대로 필요하다
(눌림이 스크롤까지 올라가야 판정이 시작된다). 상세 팝업의 정보 스크롤도 같다.
