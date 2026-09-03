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
**PICK** 이 위 그림이고, 하단 가운데의 **"다음"**(다섯 칸이 다 차야 활성)이
**CONFIRM** 으로 넘긴다. CONFIRM 은 **픽창(필터 줄 + 격자 + 뒤판)을 통째로
숨기고 선택 5인 블록을 화면 세로 가운데로 내린다** — 확정 직전에 보아야 하는
것은 후보 스물다섯이 아니라 내가 고른 다섯이기 때문이다. 그 자리에서
**"드래프트 확정"** 이 팀을 확정하고, 그 왼쪽의 작은 **"뒤로"** 가 다시 픽창을
연다. 모드 전환이 건드리는 것은 셋뿐이다(`_apply_mode`) — 픽창의 `visible`,
`_slot_row.position.y`, 그리고 하단 버튼 셋 중 무엇이 서는가.

**선택 5인 블록은 `_slot_row` 한 Control 의 지역 좌표로 산다.** 그래야 CONFIRM
이 그 노드의 y 하나만 밀어 태그 · 일러스트 · 이름을 한 덩어리로 내릴 수 있다.

## 화면에서 걷어 낸 것들
- **제목("TEAM DRAFT")과 인원 수("내 팀 N/5")** — 다섯 칸이 채워지는 것 자체가
  이미 그 답이다.
- **썸네일 칸의 역할군 이름 · 파일럿 이름 · 종합 스탯 세 줄** — 그 자리는
  **왼쪽 위 역할군 배지** 하나로 줄었고(밴픽 메크 격자와 **같은 배지**), 칸은
  정사각이 되어 얼굴이 칸을 다 쓴다.
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
| `PilotThumb.gd`       | `class_name PilotThumb extends Button` — 격자 한 칸. **정사각(200×200)이고 얼굴 크롭 하나와 왼쪽 위 역할군 배지가 전부다.** 선택되면 금색 테두리 + 우상단 체크 배지. Emits `thumb_tapped(pilot_id)`. |
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

## 카드는 보여 주지 않는다 — 후보 풀 절은 **삭제됐다**
상세 팝업에 "받게 될 파일럿 카드" 절이 있었다. 역할이 확정하는 슬롯 내역
(정글러 정글 2 + 드로우 1 / 서포터 라인전 1 + 드로우 2 / 나머지 라인전 2 +
드로우 1)과 그 슬롯에 들어갈 수 있는 **후보 카드 전부**(역할에 따라 7~14장)를
`Card.tscn` 실물로 3열 격자에 깔았다.

**그 목록이 답하는 질문이 없었다.** (1) 실제 3장은 경기 시작 시
`CardPhaseManager._deal_team_deck` 이 표집하므로 드래프트에서 본 후보와 인게임에서
손에 잡히는 카드가 다르고, (2) 후보 풀은 **역할이 정하는 것이라** 같은 역할이면
누구를 뽑아도 같은 목록이 나온다 — 선수를 고르는 판단에 들어갈 수가 없다.
의미를 갖는 것은 인게임에서 **확정된** 카드뿐이고, 그건
`battle_sim/ui/PilotDetailPanel` 이 `BattleSim.starter_cards` 를 읽어 보여 준다.

함께 삭제된 것 — `DraftDetailPanel` 의 `_build_card_sections` / `_cards_in_cat` /
`_build_card_grid` 와 `CARD_*` 상수 여섯, 그리고 `TeamDraft` 의 후보 풀 헬퍼 넷
(`pilot_card_slots_for_role` / `candidate_cards_for_role` / `slot_summary_for_role`
/ `cat_label`). 이 팝업이 넷의 유일한 소비자였다. **배분 규칙의 원본은
`CardPhaseManager._pilot_slots_for` 이므로** 되살릴 일이 생기면 사본을 다시 만들지
말고 그쪽을 부를 것.

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
`_slot_row` 안쪽 좌표(블록 높이 502):

| Y (지역) | Block |
|---|---|
| 0..28     | 슬롯 태그 (탑 · 정글 · 미드 · 원딜 · 서폿), 역할 색 |
| 32..444   | 상체 일러스트 5칸 = `Button` (204×412, 간격 12, x0 = 6) — 상세 팝업 트리거 |
| 448..502  | 이름 Label ×5 |

화면 좌표:

| Y range     | Block |
|---|---|
| 24..526     | `_slot_row` (PICK 모드) |
| 546..610    | 필터 버튼 6개 (x0 24, 총 폭 1032) — CONFIRM 에서 숨는다 |
| 626..1768   | 썸네일 격자 뒤판 + `ScrollContainer` (x0 24, w 1032, 5열 × `PilotThumb` **200×200**) — CONFIRM 에서 숨는다 |
| 1780..1900  | 하단 버튼 줄. PICK = 가운데 "다음"(480×120). CONFIRM = 가운데 "드래프트 확정"(480×120) + 그 왼쪽에 작은 "뒤로"(160×80) |
| **709..1211** | CONFIRM 모드의 `_slot_row` — 화면 세로 가운데(`confirm_row_y()`) |

격자 높이와 하단 줄의 y 는 상수가 아니라 `ScreenMetrics.safe_h()` 에서 역산한다
(`bar_y()` / `grid_h()`) — 하단 버튼은 이 화면에서 가장 아래의 터치 대상이라
홈 인디케이터 / 제스처 바와 맞닿는다.

상세 팝업(`DraftDetailPanel`)은 자기 `CanvasLayer`(layer 20) 위에 선다:
좌 전신 아트(높이 1400, 아래끝 2010, 중심 x 300) / 우 정보 패널
(x 596, w 460, y 150..1740, 안쪽은 `ScrollContainer`) / 닫기 (1756..1840).
닫기 버튼에 **불투명 스타일이 필수다** — 그 자리는 드래프트 화면의 "드래프트
확정" 버튼과 겹치는데, 기본 Button 테마는 반투명이라 딤 아래의 그 글자가 비쳐
두 라벨이 한 칸에 겹쳐 읽혔다.

---

## 격자 스크롤 — 썸네일이 `MOUSE_FILTER_PASS` 인 이유

`PilotThumb` 는 `Button` 이지만 필터를 **PASS 로 내려 둔다**. 기본값 STOP 이면
폰에서 격자가 통째로 안 굴러간다 — Godot 의 드래그 스크롤은 터치에서
에뮬레이트된 **마우스 press 가 `ScrollContainer` 까지 올라와야** 시작되는데
STOP 이 그 전파를 끊고, 썸네일이 격자를 빈틈없이 덮으므로 손가락을 어디에
대도 문턱을 넘지 못한다. 데스크톱에서는 휠이 STOP 을 뚫도록 엔진이 예외를
두고 있어 이 결함이 드러나지 않는다. 규칙과 검증법은
**`docs/mobile_safe_area.md` §5**.
