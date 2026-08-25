# Team Draft

Initial campaign step: the player picks one pilot per role (5 total) from
the **네임드 25인** pool. The displaced pilot from team-0 swaps with the picked
pilot's prior team — every team always has exactly one pilot per role.

**화면은 우마무스메식 인물 고르기다.** 아래 절반이 스크롤되는 캐릭터 썸네일
격자이고, 그 위에 역할 필터 한 줄, 그 위에 뽑은 5인의 **상체 일러스트**가
가로로 선다. 예전의 5열(역할) × 5행(순위) 고정 격자는 25명을 한 화면에
욱여넣느라 칸을 키울 수 없었고, 그래서 얼굴이 48px 라 "누구를 뽑는가"가
이름표로만 읽혔다 — 격자가 스크롤되면서 칸 크기가 인원 수에서 풀려났다.

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
| `TeamDraft.gd`        | `class_name TeamDraft extends Control` — data layer. Owns `validate_draft()`, `apply_draft()`, `get_pool_grid()`, 그리고 화면이 함께 읽는 표 셋 — **슬롯 순서**(`SLOT_ROLES` / `SLOT_NAMES` / `slot_of_role`), **카드 후보 풀**(`pilot_card_slots_for_role` / `candidate_cards_for_role` / `slot_summary_for_role`), **스킬 조회**(`skill_def_for` / `skill_type_label`). Builds `TeamDraftView` lazily via `ensure_view()` (called by `SeasonHub` after `init_season`). |
| `TeamDraftView.gd`    | `class_name TeamDraftView extends Control` — procedural UI (선택 5인 일러스트 행 + 필터 행 + 스크롤 썸네일 격자 + 하단 스킬 패널/확정 버튼). Lives as a child of the `TeamDraft` node. |
| `PilotThumb.gd`       | `class_name PilotThumb extends Button` — 격자 한 칸 (얼굴 크롭 · 역할 태그 · 이름 · 종합 스탯). 선택되면 금색 테두리 + 우상단 체크 배지. Emits `thumb_tapped(pilot_id)`. |
| `DraftDetailPanel.gd` | `class_name DraftDetailPanel extends CanvasLayer` — 이름을 누르면 열리는 상세 팝업. 좌 전신 아트 / 우 스크롤 정보 패널(스탯 칩 6개 → 파일럿 스킬 → 후보 카드 격자). |

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

## 상체 일러스트 (어깨~얼굴)
`tall/N_tall.png`(210×700, 머리~허벅지)의 **윗부분**을 `AtlasTexture` 로 잘라
쓴다(`TeamDraftView.BUST_REGION` = `Rect2(18, 0, 174, 351)`). `full` 아트에서
직접 자르지 않는 것이 요점이다 — full 은 파일럿마다 인물 배율이 달라 다섯 칸의
얼굴 크기가 들쭉날쭉해지는데, `tall` 은 이미 얼굴 사각형을 템플릿 매칭으로 찾아
배율을 통일해 둔 컷이라 그 위에서 자르면 다섯 얼굴이 같은 크기로 선다
(`resources/images/pilot/make_tall_crops.py` 참조).

영역 비율(174 : 351 = 0.496)은 칸 비율(204 : 412 = 0.495)과 같게 잡아 늘어남이
없다 — 둘 중 하나만 바꾸면 얼굴이 찌그러진다.

## 카드 후보 풀 — 확정 덱이 아니다
파일럿 카드 3장의 **슬롯 내역은 역할이 확정**하지만(정글러 정글 2 + 드로우 1 /
서포터 라인전 1 + 드로우 2 / 나머지 라인전 2 + 드로우 1) 그 세 장이 어느 카드가
될지는 **경기 시작 시** `CardPhaseManager._deal_team_deck` 이 표집한다. 메크
카드 절반은 밴픽 뒤에나 정해진다. 그래서 드래프트가 보여 줄 수 있는 것은 덱이
아니라 **후보 풀**이고, 상세 팝업이 그렇게 적는다.

`TeamDraft.pilot_card_slots_for_role` 은 `CardPhaseManager._pilot_slots_for` 와
**같은 규칙**이다. 저쪽은 `PilotData.is_guerrilla`(= 배정된 레인)를 보고 이쪽은
역할을 보는데, 레인이 역할에서 유도되므로(ASSASSIN → GUERRILLA) 답이 갈리지
않는다. 후보를 거를 때 `pool = 0` 과 `scope` 를 실제 배분과 같은 자리에서
걸러 내는 것도 같은 이유다 — 화면에 뜬 후보가 실제로는 못 받는 카드이면 그
목록은 거짓말이 된다.

카드 노드는 `res://scenes/Card.tscn` 실물이고(`CardData.from_def` 이 `cards.csv`
행을 조립한다 — **static 이라 BattleSim 없이도 돈다**, 그것이 그 함수가
`CardPhaseManager` 밖으로 나온 이유다), 축소율은 인게임 상세 패널과 같은 0.80 이라
같은 카드가 두 화면에서 같은 크기로 읽힌다.

## 하단 바 — 파일럿 스킬 구성
좌측 패널이 선택 5인의 고유 스킬을 `슬롯 · 이름 — 스킬명(타입)` 다섯 줄로
적고, 우측이 큰 "드래프트 확정"이다. 카드가 아니라 스킬을 적는 것은 위 절의
이유 그대로다 — 드래프트 시점에 **확정적인** 것은 슬롯 내역과 스킬뿐이고,
"이 팀이 무엇을 할 수 있는가"를 한 줄로 말해 주는 쪽은 스킬이다.

## UI flow
1. `SeasonHub._show_draft()` calls `TeamDraft.ensure_view()` then sets `TeamDraft.visible = true`.
2. `TeamDraftView` instantiates one `PilotThumb` per pool entry, laid out 5 columns wide inside a `ScrollContainer`. 격자 순서는 슬롯 순서 안에서 종합 스탯 내림차순. 모브는 `get_pool_grid()` 가 이미 걸러 냈다.
3. 필터 버튼(전체/탑/정글/미드/원딜/서폿)이 `_reflow_grid()` 를 돌린다 — **보이는 칸만 좌표를 다시 받는다**. 숨긴 칸을 그대로 두고 `visible` 만 끄면 빈 구멍이 남아 5열 배치가 무너진다.
4. 썸네일을 누르면 그 파일럿이 **자기 역할 칸**에 앉는다. 같은 칸의 같은 사람을 다시 누르면 비고, 다른 사람을 누르면 교체.
5. 채워진 칸의 **이름 버튼**을 누르면 `DraftDetailPanel` 이 열린다. 일러스트 전체를 버튼으로 두지 않은 것은 슬롯을 비우려는 탭과 구분되지 않기 때문.
6. "드래프트 확정"은 다섯 칸이 다 찼을 때만 활성화된다. 확정은 `_picks` 를 **역할 순서**(`GameEnums.Role`)로 다시 정렬해 `apply_draft()` 에 넘긴다 — `validate_draft` 는 순서를 보지 않지만, 화면의 슬롯 순서를 그대로 흘려보내면 이 목록이 무엇의 순서인지가 호출부마다 달라진다.
7. Confirm → `TeamDraft.apply_draft()` rewires team rosters → **`_detail.close()`** → `SeasonHub.goto(Screen.HUB)`. 팝업은 `CanvasLayer` 라 부모 Control 의 `visible` 을 따르지 않는다 — 열어 둔 채 넘어가면 딤이 화면에 그대로 남는다.

## Layout (1080×1920 portrait)
| Y range     | Block |
|---|---|
| 18..68      | Title "TEAM DRAFT" |
| 74..102     | "내 팀 (X/5)" count label |
| 112..140    | 슬롯 태그 (탑 · 정글 · 미드 · 원딜 · 서폿), 역할 색 |
| 144..556    | 상체 일러스트 5칸 (204×412, 간격 12, x0 = 6) |
| 560..614    | 이름 버튼 ×5 (= 상세 팝업 트리거) |
| 616..640    | 역할 · 원소속 한 줄 ×5 |
| 660..724    | 필터 버튼 6개 (x0 24, 총 폭 1032) |
| 732..1698   | 썸네일 격자 뒤판 — 그 안에 `ScrollContainer` 740..1690 (x0 24, w 1032, 5열 × `PilotThumb` 200×250) |
| 1702..1900  | 좌 파일럿 스킬 패널 (24, w 640) / 우 "드래프트 확정" (680, w 376) |

상세 팝업(`DraftDetailPanel`)은 자기 `CanvasLayer`(layer 20) 위에 선다:
좌 전신 아트(높이 1400, 아래끝 2010, 중심 x 300) / 우 정보 패널
(x 596, w 460, y 150..1740, 안쪽은 `ScrollContainer`) / 닫기 (1756..1840).
닫기 버튼에 **불투명 스타일이 필수다** — 그 자리는 드래프트 화면의 "드래프트
확정" 버튼과 겹치는데, 기본 Button 테마는 반투명이라 딤 아래의 그 글자가 비쳐
두 라벨이 한 칸에 겹쳐 읽혔다.
