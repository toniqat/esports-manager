class_name PilotDetailPanel
extends Node

# 파일럿 상세 패널 — 스트립의 얼굴(아군 하단 / **적 상단** 양쪽)을 누르면 열린다.
#
#   좌: 전신 아트 **두 장** — 앞에 선 쪽이 밝고, 뒤에 선 쪽은 오른쪽으로 밀린 채
#       검게 딤드된다. 앞뒤는 **탭**이 정한다(인게임·파일럿 → 사람 / 메크 → 기체).
#       그 **좌측 하단**에 지속 효과 썸네일이 앉는다(제목 없이 칸만).
#   우: 세 개의 판 — **머리글**(파일럿 이름 / 그 아래 메크 이름 + 오른쪽에 성장치)
#       → 탭 셋 + 스탯 칩 판 → (인게임 탭) **파일럿 스킬** 판
#   우하: 정보 칼럼 아래에 보유 카드가 손패와 같은 부채꼴(손패와 같은 크기)로 선다
#
# 닫기 버튼은 없다 — 탭 · 칩 · 카드(근처) · 사용 버튼이 아닌 곳을 누르면 닫힌다.
# 열 때 / 닫을 때 아트와 판이 짧게 미끄러지며 페이드한다(`_play_open` / `_play_close`).
#
# **머리글은 탭과 분리돼 있다.** 이름 · 기체명 · 성장치는 어느 탭을 보든 같은
# 파일럿의 것이므로 탭이 바뀔 때마다 다시 세울 이유가 없고, 예전처럼 본문
# 안에 들어 있으면 메크 탭에서 제목이 기체명으로 바뀌며 **파일럿 이름과
# 성장치가 화면에서 통째로 사라졌다** — 지금 누가 열려 있는지가 탭에 따라
# 흔들린 것이다. 지금은 머리글이 자기 판 위에 상시로 서 있고, 탭이 바꾸는
# 것은 그 아래 상세 패널 하나뿐이다. 기체명은 이름 **아래 줄에 작게** 붙어 늘
# 보인다 — 메크 탭까지 들어가야 알 수 있는 값이 아니다.
#
# **스탯은 줄이 아니라 칩이다.** 예전에는 `키 ─ 값` 두 칸짜리 행이 세로로 열몇
# 줄 이어졌는데, 그러면 (1) 어느 값이 중요한지가 순서 말고는 없고 (2) 값 뒤에
# `(기본 N)` `(N턴)` 같은 괄호가 줄줄이 붙어 정작 **지금 얼마인가**를 읽는 데
# 시간이 걸렸다. 지금은 칩 한 칸이 **최종 값 하나**만 크게 들고 있고, 어디서
# 나온 값인지는 칩을 눌러야 나온다(`_open_menu`) — 평소에는 읽고, 궁금할 때만
# 파고든다.
#
# 여는 곳은 둘 — 스트립의 얼굴을 누르거나, 전장 초상을 **꾹 누르거나**
# (`ui/MarkerTouch.gd`). 여는 조건은 `can_open()` 하나다: **작전 단계와 자동
# 진행(BATTLE) 양쪽**에서 열린다(예전에는 자기 작전 단계뿐이었다). BATTLE 중에
# 열면 `BattleSim._battle_tick_held` 가 이 패널을 보고 **턴을 붙잡는다** — 딤 뒤에서
# 전장이 굴러가면 지금 보고 있는 숫자가 낡는다. 교전 무대 · 개시 전(GAMBIT) ·
# 경기 종료에는 열리지 않고, 그 상태로 넘어가면 `close_if_phase_left()` 가 닫는다.
#
# 열려 있는 동안 **누른 쪽 스트립은 숨긴다**. 딤 위로 스트립만 남으면 "지금 뭘
# 보고 있는지"가 흐려지고, 딤 아래로 넣으면 방금 누른 얼굴이 어두워져 연결이
# 끊긴다 — 아예 치우는 편이 읽힌다.
#
# **레이아웃의 정본은 씬이다** — `UI_View_PilotDetailPanel.tscn`(층 13 + 테마를 단 `%Root`)과 열 때마다
# 인스턴스하는 `UI_View_PilotDetailView.tscn`(딤 · 아트 두 장 · 정보 칼럼 · 카드 부채꼴 자리 · 설명 판
# 뒤판). 반복되는 것은 아이템 씬이다 — 스탯 줄 / 칸(`PilotDetailStatRow` · `PilotDetailStatCell`),
# 지속 효과 썸네일(`PilotDetailFxThumb`), 카드 입력 띠(`PilotDetailCardBand`), 설명 판과 그 줄
# (`PilotDetailInfoMenu` · `PilotDetailInfoRow`), 전신 아트(`PilotDetailArt`). 색 · 판은 전투
# 테마(`resources/BattleTheme.tres`)의 변형이 정한다(`BattlePanel` · `PilotDetailStatPlate` ·
# `BattleTab(On)` · `BattleChipButton(On)` · `BattleFxButton(On)` · `BattleActionButton` …).
# 코드가 정하는 것: 아트 크기 · 앞뒤 자세, 지속 효과 줄의 아래끝(카드 부채꼴 위), 칸 · 탭 강조
# (변형 이름 전환), 효과 약칭 색(데이터 색), 설명 판 위치 · 높이, 코드 위젯(아이콘 타일 ·
# 설명문 · 카드 노드 · 카드 설명판), 열기 / 닫기 연출. 생성: `PilotDetailPanel.create()`.

## 버리기(10) / 대상 지정(11) / 열람·교전(12) 위. 이 패널은 모달이라
## 열려 있는 동안 카드도 못 내고 턴도 못 넘기므로 다른 오버레이와 겹칠 일이
## 없지만, 겹친다면 이쪽이 위여야 한다. 씬 `PilotDetailLayer` 의 `layer` 와 같은 값.
const OVERLAY_LAYER: int = 13

const SCENE_PATH: String = "res://features/battle_sim/ui/UI_View_PilotDetailPanel.tscn"
## 열 때마다 하나씩 인스턴스하는 상세 한 장(닫히는 장이 빠져나가는 동안 다음 장이 들어온다).
const VIEW_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_View_PilotDetailView.tscn")
const ROW_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_Comp_PilotDetailStatRow.tscn")
const CELL_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_Comp_PilotDetailStatCell.tscn")
const FX_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_Comp_PilotDetailFxThumb.tscn")
const BAND_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_Comp_PilotDetailCardBand.tscn")
const MENU_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_Comp_PilotDetailInfoMenu.tscn")
const MENU_ROW_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_Comp_PilotDetailInfoRow.tscn")

## 탭 셋. 인게임 = 지금 이 전장에서의 상태, 파일럿 = 사람의 능력치 + 파일럿
## 카드, 메크 = 기체의 능력치 + 메크 카드. 예전의 "전환" 버튼(파일럿 ↔ 메크
## 2단 토글)을 대신하며, 아트의 앞뒤도 이 값이 정한다.
enum Tab { INGAME, PILOT, MECH }

# ─── 전신 아트 (앞 / 뒤 2슬롯) ───────────────────────────────────────────────
# **아트는 화면 하단에서 잘린다.** 아래끝(`ART_BOTTOM`)을 화면(1920)보다 아래에
# 두어 다리 아랫부분이 화면 밖으로 나간다 — 예전의 `_knee_crop`(알파 실루엣의
# 80% 지점에서 텍스처를 잘라 내던 것)은 그래서 삭제됐다. 자르는 일은 이제
# 화면 가장자리가 하고, 어디서 잘릴지는 아트 크기와 위치 두 상수가 정한다.
#
# 크기는 **높이로 정규화**한다. 전신 아트는 전부 세로 1024 에 인물이 꽉 차 있고
# 가로만 572~756 으로 제각각이라(폭으로 맞추면 인물 키가 이미지마다 다르다),
# 폭은 원본 비율에서 나온다.
#
# 두 아트의 **바닥선은 같다**. 뒤에 선 쪽은 바닥을 딛은 채 `BACK_SCALE` 만큼
# 작아지고(= 멀리 서 있다) 오른쪽으로 `BACK_SHIFT_PX` 밀린다. 축소 기준점을
# 노드의 **아래 가운데**(`pivot_offset`)로 잡았기 때문에 크기를 줄여도 발이
# 뜨지 않는다.
## 앞에 선 아트의 높이(px). 폭은 원본 비율에서 나오므로(대략 0.65~0.74) 이
## 값이 곧 인물이 화면을 얼마나 채우는가다 — 1400 이면 폭 900~1030 으로
## 화면(1080)을 거의 다 쓰고, 그보다 키우면 뒤에 선 메크가 오른쪽으로 완전히
## 밀려 나간다.
const ART_H: float = 1400.0
## 앞에 선 아트의 **아래끝** y. 화면(1920)보다 아래라 하단이 잘린다.
const ART_BOTTOM: float = 2010.0
## 앞에 선 아트의 가로 중심.
const ART_FRONT_CENTER_X: float = 320.0
## 뒤에 선 아트가 오른쪽으로 밀리는 거리(px). 아트 폭이 대략 870 이므로
## 이 값이면 둘이 절반쯤 겹친다.
const ART_BACK_SHIFT_PX: float = 400.0
## 뒤에 선 아트의 축소율(원근).
const ART_BACK_SCALE: float = 0.90
## 뒤에 선 아트에 씌우는 검은 반투명. `modulate` 라 RGB 는 어둡게, A 는 살짝
## 비치게 — 둘 다 필요하다(어둡기만 하면 실루엣이 아니라 검은 판이 된다).
const ART_BACK_TINT := BattleTheme.ART_BACK_TINT
## 앞뒤가 자리를 맞바꾸는 데 걸리는 시간(s).
const ART_SWAP_SEC: float = 0.22
## 아트가 없는 메크(= 아직 에셋이 하나도 없다)의 플레이스홀더 가로/세로 비.
const ART_PLACEHOLDER_ASPECT: float = 0.70

# ─── 우: 정보 칼럼 (씬 `%Column`) ────────────────────────────────────────────
# **정보 블록은 아래쪽에 있다.** 아트가 커지면서 화면 위쪽 절반이 인물의
# 머리·상체 자리가 됐고, 스탯이 예전 자리(y 170)에 남으면 얼굴을 덮는다.
# 칼럼은 머리글(362 .. 546) / 탭(562, 62) + 스탯 판(650 부터 칸) / 파일럿 스킬 판 —
# 세 판 사이 16. 자리 · 크기는 씬이 정하고, 여기 값은 설명 판 위치 · 설명문 폭 계산용 사본.
## 스탯 칸의 왼쪽 끝 · 폭(= 칼럼 판 안쪽).
const STAT_X: float = 600.0
const STAT_W: float = 452.0
## 스킬 판 설명문 폭 — 판 안쪽 폭 − 아이콘 타일 92 − 간격 18 (씬 `SkillInfo`).
const SKILL_DESC_W: float = STAT_W - 92.0 - 18.0

# ─── 스탯 칸 ─────────────────────────────────────────────────────────────────
# 스탯 판 위에 얹힌 **작은 판 하나 = 스탯 하나** — 왼쪽에 이름, 오른쪽 정렬로
# **최종 값**. 줄 하나에 칸이 하나면 판 폭 전체(체력 · 공격력 · 존재감), 둘이면
# 반씩(전장 명중 | 전장 회피 …). 탭마다 줄 구성은 `_chip_defs` 가 정한다.
# 예전에는 3열 칩(위 이름 / 아래 큰 값)이었다.
const CHIP_PAD_X: float = 16.0
## 이름 앞 스탯 아이콘 — 이름 글자색으로 굽는다(자리 · 크기는 씬 `%Icon`).
const CHIP_ICON_PX: float = 26.0
## 칩 key → `KeywordIcon` 아이콘. 같은 스탯은 탭이 달라도 같은 아이콘이다.
const CHIP_ICONS: Dictionary = {
	"hp": KeywordIcon.HP, "m_hp": KeywordIcon.HP,
	"atk": KeywordIcon.ATK, "m_atk": KeywordIcon.ATK,
	"presence": KeywordIcon.PRESENCE, "m_presence": KeywordIcon.PRESENCE,
	"hit": KeywordIcon.FIELD_HIT, "field_hit": KeywordIcon.FIELD_HIT,
	"eva": KeywordIcon.FIELD_EVA, "field_eva": KeywordIcon.FIELD_EVA,
	"e_hit": KeywordIcon.ENGAGE_HIT, "engage_hit": KeywordIcon.ENGAGE_HIT,
	"e_eva": KeywordIcon.ENGAGE_EVA, "engage_eva": KeywordIcon.ENGAGE_EVA,
	"atk_growth": KeywordIcon.ATK_GROWTH, "hp_growth": KeywordIcon.HP_GROWTH,
}
## 값 뒤의 괄호 보너스 `(+N)` — 체력 · 공격력은 기본값 대비 증감, 존재감은 특수
## 능력의 가산분(+ 일 때만). 0 이면 괄호를 달지 않는다. 글자 크기는 씬 `%Bonus`
## (`BattlePositiveLabel` / `BattleNegativeLabel`)와 같은 값 — 폭을 잴 때 쓴다.
const CHIP_BONUS_FONT: int = BattleTheme.FONT_BODY
const CHIP_BONUS_GAP: float = 6.0

# ─── 칩 컨텍스트 메뉴 ────────────────────────────────────────────────────────
# **정보 칼럼 왼쪽에** 펼친다 — 오른쪽은 화면 끝(1080)까지 28px 밖에 없고,
# 칩 위에 겹쳐 띄우면 방금 누른 칩이 자기 설명에 가려진다. 왼쪽은 아트가 선
# 자리이지만 메뉴는 불투명 판이라 읽는 데 문제가 없다. 판(`PilotDetailInfoMenu`)의
# 모양은 카드 설명판과 같다(`PilotDetailMenuPanel` = `CardDescBox.panel_style`).
## 판 폭 · 안쪽 여백 — 씬(최소 폭)과 변형(여백)의 사본(위치 계산용).
const MENU_W: float = 372.0
const MENU_PAD := Vector2(20.0, 16.0)
const MENU_GAP_X: float = 16.0
## 설명 글 속 아이콘이 파내는 판 바탕색 = 판 색.
const MENU_BG := BattleTheme.MENU_BG
## 설명 글의 `{attack}` · `{engage}` 자리에 서는 아이콘.
const MENU_NOTE_ICON: Dictionary = {
	"attack": KeywordIcon.ATTACK, "engage": KeywordIcon.ENGAGE,
}
## 판 아래의 설명 글 크기(`PilotDetailNoteText`) — 아이콘 크기를 여기서 낸다.
const MENU_NOTE_FONT: int = BattleTheme.FONT_CAPTION

# ─── 지속 효과 썸네일 (일러스트 좌측 하단, 씬 `%FxGrid`) ─────────────────────
# **지금 이 파일럿에게 걸려 있는 것만** 뜬다 — 걸려 있지도 않은 효과의 빈 칸이
# 늘어서 있으면 "무엇이 켜져 있는가"가 도리어 안 읽힌다.
#
# 칩이 답하지 못하는 질문이 있어서 생겼다. 명중 칩이 55 라고 할 때 그 값이
# 라인전 카드 때문인지 원래 그런지는 칩을 눌러야 나오고, 적립 배율처럼 **어느
# 칩에도 안 실리는** 효과는 아예 볼 자리가 없었다. 썸네일 한 줄은 "지금 몇 개가
# 켜져 있는가"를 세지 않고도 보게 하고, 하나를 누르면 스탯 칩과 **같은 패널**에
# 그 설명이 뜬다(둘은 같은 자리를 쓰므로 자연히 배타적이다).
#
# **자리는 정보 칼럼이 아니라 일러스트 좌측 하단이다.** 칼럼 안에서는 스탯 칩과
# 카드 사이에 끼어 116px 를 먹었고, 그만큼 아래 사슬(카드 줄 · 스킬 블록 · 닫기
# 버튼)이 전부 밀려 인게임 탭이 화면 바닥에 닿아 있었다. 화면 왼쪽 아래는 아트의
# 다리와 딤 뿐이라 비어 있는 자리이고, 여기로 옮기면 칩 ↔ 스킬이 곧바로 이어진다.
#
# **제목("지속 효과")은 삭제됐다.** 칼럼 안에서는 위아래 블록과 구분하는 이름표가
# 필요했지만, 화면 구석에 홀로 선 68px 칸 여섯의 머리에 밑줄 달린 절 제목을
# 붙이면 그 제목이 칸보다 눈에 띈다. 걸린 효과가 없으면 **아무것도 안 그린다** —
# 예전의 "걸려 있는 효과 없음" 한 줄은 제목이 있어야 뜻이 서는 문장이었다.
#
# 칸(68 × 68, 간격 12, 한 줄 여섯 — x 26 부터 정보 칼럼과 부딪히지 않는 폭)은 씬이 정한다.
## 썸네일 줄의 아래끝과 카드 부채꼴 윗변 사이 간격(호버로 커진 카드가 ≈17px
## 솟는 몫 포함). 줄은 여기서 **위로** 자란다 — 아래로 자라면 두 줄짜리 효과
## 목록이 카드 부채꼴 위로 내려앉는다.
const FX_ABOVE_FAN_GAP: float = 36.0

# ─── 보유 카드 (손패와 같은 자리 · 같은 부채꼴) ─────────────────────────────
# 손패와 **같은 카드 노드**(`Card.tscn`)를 손패와 **같은 자리, 같은 모습**으로
# 세운다 — 화면 가로 가운데, 손패 너비(`BattleSim.BS_HAND_WIDTH`) 안에서 같은
# 간격 압축(`CardPhaseManager.slot_spacing` 규칙), 같은 행 높이(`BS_HAND_CENTER`),
# 같은 부채꼴 기울기 · 처짐, 같은 호버(`Card.HOVER_SCALE` 확대 + 이웃 비켜남),
# 같은 드롭 쉐도우(`Card` 의 그림자 — `is_player_card` 로 켠다). 다른 그림이면
# "이 카드가 그 카드"라는 연결이 끊긴다. 드로우 인트로(뒷면으로 날아와 뒤집힘)는
# 쓰지 않는다 — 대신 열 때 가운데로 모여 있던 카드가 **살짝 펼쳐진다**
# (`FAN_SPREAD_FROM` → 1).
#
# **어느 탭이든 6장 전부**(파일럿 3 → 메크 3)가 같은 자리에 선다. 탭에 맞지 않는
# 카드(파일럿 탭의 메크 카드 · 메크 탭의 파일럿 카드)는 **딤드되고 눌리지 않는다**
# — 카드 노드는 탭이 바뀌어도 다시 세우지 않고 딤 / 입력 밴드만 고친다
# (`_rebuild_fan_hits`). 카드 줄 제목은 없다 — 손패에도 없다.
## 펼침 연출 — 시작할 때 각 카드의 가로 오프셋(dx)에 곱하는 값과 걸리는 시간.
const FAN_SPREAD_FROM: float = 0.55
const FAN_SPREAD_SEC: float = 0.24
## 부채꼴 둘레의 여유 — 이 안의 빈 곳(겹친 카드 사이 틈 · 딤드 카드)은 눌러도
## 상세 화면이 닫히지 않는다(`_card_zone`).
const FAN_ZONE_PAD: float = 24.0
## 정보 칼럼(머리글 · 탭 · 스탯 판 · 스킬 판) 둘레의 여유. 칩이나 탭을 조금
## 빗겨 눌러도 이 안이면 화면이 닫히지 않는다.
const INFO_ZONE_PAD: float = 40.0

# ─── 파일럿 스킬 판 (인게임 탭 · 스탯 판 아래, 자기 판 — 씬 `%SkillPanel`) ───
# 스킬은 카드와 다른 종류의 자원이라 **자기 판**을 갖는다 — 왼쪽에 아이콘 타일
# (`SkillImages.make_icon_tile`, 흐린 그림자), 오른쪽에 이름 · 설명문, 아래에 큰
# 사용 버튼. 제목 줄("파일럿 스킬")과 타입 · 키워드 꼬리표는 없다 — 판 자체가
# 이름표이고, 타입은 버튼(있다 / 없다 / 딤드)이 말한다.
## 설명문 글자 크기 — `SkillPopup` 도 같은 값을 읽는다.
const SKILL_DESC_FONT: int = BattleTheme.FONT_BODY
const SKILL_TILE_PX: float = 92.0

# ─── 열기 / 닫기 연출 ────────────────────────────────────────────────────────
# 열 때: 아트가 왼쪽에서 살짝 오른쪽으로 오며, 정보 판들이 아래에서 올라오며 페이드인.
# 닫을 때: 그 반대(아트는 왼쪽으로, 판은 아래로) 페이드아웃. 딤도 같이 페이드.
const OPEN_SEC: float = 0.2
const CLOSE_SEC: float = 0.1
const ART_SLIDE_PX: float = 48.0
const UI_SLIDE_PX: float = 56.0

var _bs: BattleSim = null
## 지금 열린 상세 한 장(`UI_View_PilotDetailView.tscn` 인스턴스). null = 닫힘.
var _view: Control = null
## 딤 / 정보 묶음(머리글 · 탭 · 본문 · 카드). 열기 · 닫기 연출이 이 둘과 아트 홀더를 움직인다.
var _dim: Control = null
var _ui_root: Control = null
var _column: Control = null
var _pilot: PilotData = null
var _tab: int = Tab.INGAME

# 아트 두 장. 어느 쪽이 앞이냐는 `_tab` 이 정하고, 노드 자체는 바뀌지 않는다.
var _art_pilot: Control = null
var _art_mech: Control = null
var _art_holder: Control = null
var _swap_tween: Tween = null

var _tab_buttons: Array = []          # Array[Button], Tab 순서

# 머리글(이름 · 기체명 · 성장치)은 **탭과 무관**하므로 열 때 한 번만 채우고
# `refresh()` 가 숫자만 고친다.
var _growth_label: Label = null
## 파일럿 스킬 블록의 상태 줄과 사용 버튼. `refresh()` 가 이 둘만 다시 쓴다 —
## 트리를 다시 세우면 카드 노드가 매 갱신마다 인스턴스화된다. 패시브 스킬 ·
## 스킬 없는 파일럿 · 인게임이 아닌 탭에서는 버튼이 null 이다.
var _skill_status: Label = null
var _skill_use_btn: Button = null
## 판을 세울 때 상태 줄을 넣었는가. 준비 완료(쿨타임 0)면 "사용 가능" 줄을 빼므로
## 이 값이 지금 답과 달라지면 `refresh()` 가 본문을 다시 세운다.
var _skill_status_shown: bool = false

## 정보 패널을 열 수 있는 모든 것이 여기 한 표에 모인다 — 스탯 칩,
## 지속 효과 썸네일, 카드. 셋이 같은 패널을 쓰므로(= 자연히 배타적) 강조
## 스타일도, 여는 경로도, 메뉴 뒤판의 클릭 라우팅도 한 벌이면 된다.
##
##   key → {"button": Button, "style": TargetStyle, "value": Label?, …}
##
## 키 접두사가 종류를 가른다: 접두사 없음 = 스탯 칩, `fx:` = 지속 효과,
## `card:` = 카드. `_menu_rows` / `_menu_note` / `_target_title` 이 이 접두사로
## 갈라 읽는다.
enum TargetStyle { CHIP, FX, CARD }
var _targets: Dictionary = {}
## 지금 세워져 있는 효과 썸네일의 키 목록 — `refresh()` 가 이 목록과 지금
## 걸려 있는 효과를 견줘 달라졌을 때만 본문을 다시 세운다.
var _fx_keys: Array = []

# 열려 있는 정보 패널의 키. "" = 닫힘. `refresh()` 가 이 값을 보고 내용을 다시
# 세우므로 패널에 적힌 숫자도 언제나 지금 값이다.
var _menu_key: String = ""
## 설명 판 뒤판(씬 `%InfoMenu`, 맨 위). 판은 그 자식으로 코드가 넣는다.
var _menu_root: Control = null

# 보유 카드 부채꼴 상태. `_build_card_fan` 이 열 때 한 번 채우고 `close()` 가
# 비운다 — 탭 전환 · 본문 재구성은 입력 밴드(`_fan_hits`)만 다시 세운다.
var _fan_nodes: Array = []             # Array[Card], 왼쪽부터
var _fan_cards: Array = []             # 같은 순서의 CardData
var _fan_slots: Array = []             # 같은 순서의 "pilot" / "mech"
var _fan_keys: Array = []              # 같은 순서의 `card:` 키 ("" = 딤드, 눌리지 않음)
var _fan_dx: PackedFloat32Array = PackedFloat32Array()   # 쉬는 자리의 중심 dx
var _fan_cx: float = 0.0
var _fan_spacing: float = 0.0
var _fan_root: Control = null
var _fan_hits: Control = null
## 지금 가리키는 카드(밴드 호버). -1 = 없음 — 그때는 정보 패널이 열린 카드가 초점.
var _fan_hover: int = -1
var _fan_relayout_queued: bool = false

## 열면서 숨긴 스트립의 팀. 닫을 때 그 스트립만 되돌린다.
var _hidden_team: int = -1


## 씬을 인스턴스한다. `PilotDetailPanel.new()` 는 층이 없는 빈 노드라 쓰지 않는다.
static func create() -> PilotDetailPanel:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PilotDetailPanel


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


# CardSelectOverlay / CardPileViewer 와 같은 패턴 — BattleSim._ready 가
# add_child 직후 호출한다.
func bind(bs: BattleSim) -> void:
	_bs = bs


func is_active() -> bool:
	return _view != null


func open(p: PilotData) -> void:
	if p == null:
		return
	if is_active():
		close()
	_pilot = p
	_tab = Tab.INGAME
	_build()
	_play_open()
	if _bs.hud != null:
		_hidden_team = p.team
		_bs.hud.set_strip_visible(_hidden_team, false)


## 상태는 **즉시** 비운다(`is_active()` 가 곧바로 false — 턴 붙잡기도 풀린다).
## 화면만 `CLOSE_SEC` 동안 빠져나가다 지워지고, 그동안은 입력을 받지 않는다.
func close() -> void:
	_close_menu()
	if _view != null:
		_play_close(_view, _art_holder, _ui_root, _dim)
		_view = null
	_dim = null
	_ui_root = null
	_column = null
	_menu_root = null
	_targets.clear()
	_fx_keys.clear()
	_reset_fan()
	_growth_label = null
	_skill_status = null
	_skill_use_btn = null
	_tab_buttons.clear()
	_art_pilot = null
	_art_mech = null
	_art_holder = null
	_pilot = null
	if _bs != null and _bs.hud != null and _hidden_team >= 0:
		_bs.hud.set_strip_visible(_hidden_team, true)
	_hidden_team = -1


## 열 수 없는 상태(`can_open`)로 넘어가면 닫는다. `HudBuilder.update_hud` 가 매
## 갱신마다 부른다.
func close_if_phase_left() -> void:
	if is_active() and not can_open():
		close()


## 지금 열 수 있는가 — 작전 단계 또는 자동 진행 중, 교전 무대가 없고 경기가
## 끝나지 않았을 때. 스트립 버튼 활성화와 전장 꾹 누르기가 같은 답을 읽는다.
func can_open() -> bool:
	if _bs == null or _bs.game_over:
		return false
	if _bs.engage_phase != null and _bs.engage_phase.is_active():
		return false
	return _bs.game_phase == GameEnums.BattlePhase.CARD_PHASE \
			or _bs.game_phase == GameEnums.BattlePhase.BATTLE


## 열려 있는 동안 값을 현재 값으로 다시 쓴다. `HudBuilder.update_hud` 가 매
## 갱신마다 부른다 — 패널은 모달이라 열려 있는 사이에 카드가 나가지는 않지만,
## 값이 바뀌는 자리(카드 효과 · 만료 · 성장 재계산)는 전부 update_hud 를 지나므로
## 이 한 줄이 "화면의 숫자는 언제나 지금 값"을 보장한다.
##
## **트리는 다시 세우지 않는다** — 칩 라벨과 열려 있는 메뉴의 글자만 고친다.
## 통째로 다시 세우면 카드 노드 셋이 매 갱신마다 인스턴스화되고, 눌러 둔 칩의
## 강조도 그때마다 깜빡인다. 아트와 앞뒤 자세도 건드리지 않는다(전환 트윈이 끊긴다).
func refresh() -> void:
	if not is_active():
		return
	if _growth_label != null and is_instance_valid(_growth_label):
		_growth_label.text = BattleSim.fmt_score(_pilot.score)
	_refresh_skill_block()
	# 스킬 상태 줄이 생기거나 사라져야 하면(쿨타임이 막 끝남 / 막 씀) 판 높이가
	# 바뀌므로 본문을 다시 세운다.
	if _skill_status_shown != _skill_status_visible():
		_rebuild_body()
		return
	# 걸려 있는 효과의 **구성**이 달라졌으면(만료 / 새 효과) 본문을 다시 세운다.
	# 값만 바뀐 경우에는 아래 라벨 갱신으로 끝난다 — 트리를 다시 세우면 카드
	# 노드가 매 갱신마다 인스턴스화되고 열어 둔 패널이 닫힌다.
	if _fx_signature() != _fx_keys:
		_rebuild_body()
		return
	_refresh_target_values()
	# 카드 설명판은 값이 없는 글(계산식은 식 문구)이라 다시 세울 것이 없다 —
	# 매 갱신마다 세우면 등장 연출이 되풀이된다.
	if _menu_key != "" and not _menu_key.begins_with("card:"):
		_build_menu_content()


# ─── UI ──────────────────────────────────────────────────────────────────────
## 상세 한 장을 인스턴스하고 채운다. 크기 · 자리는 씬(전부 `%Root` 의 full rect —
## CanvasLayer 아래 Control 의 full-rect 앵커는 뷰포트 크기로 풀린다)이 정한다.
func _build() -> void:
	_view = VIEW_SCENE.instantiate() as Control
	%Root.add_child(_view)
	_dim = _view.get_node("%Dim")
	_art_holder = _view.get_node("%ArtHolder")
	_art_pilot = _view.get_node("%PilotDetailArt_ArtPilot")
	_art_mech = _view.get_node("%PilotDetailArt_ArtMech")
	_ui_root = _view.get_node("%InfoColumn")
	_column = _view.get_node("%Column")
	_fan_root = _view.get_node("%CardFan")
	_fan_hits = _view.get_node("%CardFanHits")
	_menu_root = _view.get_node("%InfoMenu")
	_growth_label = _view.get_node("%Growth")

	# 딤 = "바깥". 탭 · 칩 · 카드 · 사용 버튼이 아닌 곳을 누르면 여기로 떨어져
	# 상세 화면이 닫힌다(`_on_dim_input`). 판과 글자는 전부 IGNORE 라 판
	# 위를 눌러도 딤이 받는다 — 닫기 버튼은 없다.
	_dim.gui_input.connect(_on_dim_input)
	# 설명 판 뒤판 — 이 판이 STOP 이라 뒤쪽 버튼이 전부 가려지므로 **뒤판이 직접
	# 라우팅한다**(`_on_menu_backdrop_input`).
	_menu_root.gui_input.connect(_on_menu_backdrop_input)
	_tab_buttons = [_view.get_node("%TabIngame"), _view.get_node("%TabPilot"),
			_view.get_node("%TabMech")]
	for i in _tab_buttons.size():
		(_tab_buttons[i] as Button).pressed.connect(_on_tab_pressed.bind(i))
	(_view.get_node("%SkillUse") as Button).pressed.connect(_on_skill_use_pressed)
	# 지속 효과 줄 — 아래끝을 카드 부채꼴 윗변 위에 붙이고 위로 자란다(씬 grow = 위).
	var fx_grid: Control = _view.get_node("%FxGrid")
	fx_grid.offset_top = _fx_bottom_y()
	fx_grid.offset_bottom = _fx_bottom_y()

	_build_arts()
	_fill_header()
	_refresh_tab_styles()
	_rebuild_body()
	# 펼침 연출은 열 때만.
	_build_card_fan(_starter_cards("pilot") + _starter_cards("mech"),
			_slot_tags("pilot") + _slot_tags("mech"))


# ─── 바깥 누르기 = 닫기 ─────────────────────────────────────────────────────
## 손을 **뗄 때** 닫는다 — 누를 때 닫으면 떼는 이벤트가 이미 IGNORE 가 된 패널을
## 지나 아래 손패 · 전장으로 떨어진다. 카드 부채꼴 근처(`_card_zone`)는 예외 —
## 겹친 카드 사이 틈을 눌렀다고 화면이 닫히면 카드를 고르기가 어렵다.
func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return
	if _card_zone().has_point(mb.position) or _info_zone().has_point(mb.position):
		return
	close()


## 정보 칼럼이 차지하는 구역(`INFO_ZONE_PAD` 여유 포함) — 씬 `%Column` 의 rect
## (머리글 윗변 ~ 마지막 판 아랫변, 정보 묶음 로컬 = 열기 연출 오프셋을 뺀 화면 좌표).
## 이 안의 빈 곳은 닫지 않는다.
func _info_zone() -> Rect2:
	if _column == null or not is_instance_valid(_column):
		return Rect2()
	return Rect2(_column.position, _column.size).grow(INFO_ZONE_PAD)

## 카드 부채꼴이 차지하는 구역(여유 포함). 이 안의 빈 곳은 닫지 않는다.
func _card_zone() -> Rect2:
	if _fan_nodes.is_empty():
		return Rect2()
	var half_w: float = (absf(_fan_dx[0]) + CardPhaseManager.hand_card_w() * 0.5
			+ FAN_ZONE_PAD)
	var top: float = _fan_top_y() - FAN_ZONE_PAD
	var bottom: float = (_fan_top_y() + CardPhaseManager.hand_card_h()
			+ _fan_arc_drop(_fan_dx[0]) + FAN_ZONE_PAD)
	return Rect2(_fan_cx - half_w, top, half_w * 2.0, bottom - top)


# ─── 열기 / 닫기 연출 ────────────────────────────────────────────────────────
func _play_open() -> void:
	_art_holder.position.x = -ART_SLIDE_PX
	_art_holder.modulate.a = 0.0
	_ui_root.position.y = UI_SLIDE_PX
	_ui_root.modulate.a = 0.0
	_dim.modulate.a = 0.0
	var tw := _view.create_tween().set_parallel() 			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_art_holder, "position:x", 0.0, OPEN_SEC)
	tw.tween_property(_art_holder, "modulate:a", 1.0, OPEN_SEC)
	tw.tween_property(_ui_root, "position:y", 0.0, OPEN_SEC)
	tw.tween_property(_ui_root, "modulate:a", 1.0, OPEN_SEC)
	tw.tween_property(_dim, "modulate:a", 1.0, OPEN_SEC)


## 떠나는 루트를 빼내고 지운다. 상태는 이미 비었으므로 노드 참조는 인자로 받는다.
## 빠지는 동안 버튼이 눌리지 않게 트리 전체를 IGNORE 로 돌린다.
func _play_close(old_root: Control, art: Control, ui: Control, dim: Control) -> void:
	_ignore_input_recursive(old_root)
	var tw := old_root.create_tween().set_parallel() 			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	if art != null:
		tw.tween_property(art, "position:x", art.position.x - ART_SLIDE_PX, CLOSE_SEC)
		tw.tween_property(art, "modulate:a", 0.0, CLOSE_SEC)
	if ui != null:
		tw.tween_property(ui, "position:y", ui.position.y + UI_SLIDE_PX, CLOSE_SEC)
		tw.tween_property(ui, "modulate:a", 0.0, CLOSE_SEC)
	if dim != null:
		tw.tween_property(dim, "modulate:a", 0.0, CLOSE_SEC)
	tw.chain().tween_callback(old_root.queue_free)


static func _ignore_input_recursive(node: Node) -> void:
	var c := node as Control
	if c != null:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_input_recursive(child)


# ─── 전신 아트 ───────────────────────────────────────────────────────────────
# 두 장(씬 `%PilotDetailArt_ArtPilot` · `%PilotDetailArt_ArtMech`)을 채우고, 앞뒤 자세는 `_apply_focus(false)` 가 잡는다.
func _build_arts() -> void:
	var mech: MechData = _mech()
	_fill_art(_art_pilot, PilotImages.full_for(_pilot.pilot_id), "초상화 없음")
	_fill_art(_art_mech, MechImages.full_for(mech.id) if mech != null else null,
			mech.name if mech != null else "메크 미배정")
	_apply_focus(false)


## 아트 한 장(`UI_Comp_PilotDetailArt.tscn`). `tex` 가 null 이면(메크 에셋이 아직 없다 /
## INTL 파일럿) 같은 자리에 실루엣 플레이스홀더(`%Slab` + `%FallbackLabel`)를 세운다 —
## 자리와 전환 동작은 그대로 확인된다.
##
## 노드 크기는 **언제나 앞에 선 크기**(`ART_H`)로 고정하고, 뒤로 물러날 때는
## `scale` 로만 줄인다. `pivot_offset` 이 아래 가운데라 줄여도 바닥선이 그대로다.
func _fill_art(holder: Control, tex: Texture2D, fallback_text: String) -> void:
	var aspect: float = ART_PLACEHOLDER_ASPECT
	if tex != null:
		var ts: Vector2 = tex.get_size()
		if ts.y > 0.0:
			aspect = ts.x / ts.y
	var w: float = ART_H * aspect
	holder.size = Vector2(w, ART_H)
	holder.pivot_offset = Vector2(w * 0.5, ART_H)
	# 크기를 원본 비율로 이미 맞췄으므로 STRETCH_SCALE 이 정확히 채운다.
	var rect: TextureRect = holder.get_node("%Texture")
	rect.texture = tex
	rect.visible = tex != null
	# 옅은 판 — "아직 그림이 없다"는 자리 표시이지 그림이 아니다(`PilotDetailArtSlab`).
	holder.get_node("%Slab").visible = tex == null
	var lbl: Label = holder.get_node("%FallbackLabel")
	lbl.visible = tex == null
	lbl.text = fallback_text

## 앞/뒤 자세를 적용한다. `animate` 면 두 노드가 자리를 맞바꾸는 과정이 보인다.
## 앞에 서는 쪽은 **탭**이 정한다 — 메크 탭이면 기체, 그 밖에는 사람.
func _apply_focus(animate: bool) -> void:
	var mech_front: bool = _tab == Tab.MECH
	var front: Control = _art_mech if mech_front else _art_pilot
	var back: Control  = _art_pilot if mech_front else _art_mech
	# 앞에 선 쪽이 위에 그려져야 한다 — 형제 순서가 곧 z-order 다.
	_art_holder.move_child(back, 0)
	_art_holder.move_child(front, 1)

	if _swap_tween != null and _swap_tween.is_running():
		_swap_tween.kill()
	if animate:
		_swap_tween = _art_holder.create_tween().set_parallel() \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pose_art(front, true, animate)
	_pose_art(back, false, animate)


## 아트 한 장을 앞자리 / 뒷자리에 앉힌다. 뒷자리는 오른쪽으로 밀리고, 작아지고,
## 검게 딤드된다 — 셋 다 같은 트윈을 탄다.
func _pose_art(node: Control, is_front: bool, animate: bool) -> void:
	var x: float = ART_FRONT_CENTER_X - node.size.x * 0.5
	if not is_front:
		x += ART_BACK_SHIFT_PX
	var goal_pos := Vector2(x, ART_BOTTOM - ART_H)
	var goal_scale: Vector2 = Vector2.ONE if is_front \
			else Vector2(ART_BACK_SCALE, ART_BACK_SCALE)
	var goal_tint: Color = Color.WHITE if is_front else ART_BACK_TINT
	if animate and _swap_tween != null:
		_swap_tween.tween_property(node, "position", goal_pos, ART_SWAP_SEC)
		_swap_tween.tween_property(node, "scale", goal_scale, ART_SWAP_SEC)
		_swap_tween.tween_property(node, "modulate", goal_tint, ART_SWAP_SEC)
	else:
		node.position = goal_pos
		node.scale = goal_scale
		node.modulate = goal_tint


# ─── 탭 바 ───────────────────────────────────────────────────────────────────
# 받침 **바로 위에 붙는다**(아래끝 = 받침 위끝) — 떼어 놓으면 탭이 어느 판에
# 달린 것인지가 안 보인다. 켜진 탭(`BattleTabOn`)은 아래 테두리를 그리지 않아
# 받침과 한 몸이 된다.
func _refresh_tab_styles() -> void:
	for i in _tab_buttons.size():
		(_tab_buttons[i] as Button).theme_type_variation = \
				&"BattleTabOn" if i == _tab else &"BattleTab"

func _on_tab_pressed(idx: int) -> void:
	if idx == _tab:
		return
	_tab = idx
	_close_menu()
	_refresh_tab_styles()
	_apply_focus(true)
	_rebuild_body()


# ─── 본문 (칩 · 효과 · 스킬) ─────────────────────────────────────────────────
# 탭이 바뀔 때 칸 줄과 효과 썸네일을 통째로 다시 세운다 — 구성이 아예 다르다.
# 판(스탯 · 스킬)은 씬 노드라 그대로 두고 내용과 보임만 바꾼다. 판 높이는
# 컨테이너가 내용에 맞춘다.
func _rebuild_body() -> void:
	_targets.clear()
	_fan_hover = -1
	_fx_keys = _fx_signature()
	_clear_children(_view.get_node("%Chips"))
	_clear_children(_view.get_node("%FxGrid"))

	_build_chip_grid(_chip_defs())
	var ingame: bool = _tab == Tab.INGAME
	# 죽어 있을 때만 뜨는 한 줄. 스트립의 부활 카운트는 패널이 열려 있는 동안
	# 숨겨져 있으므로 여기 말고는 남은 턴 수를 볼 자리가 없다.
	var dead: bool = ingame and not _pilot.alive
	_view.get_node("%DeadGap").visible = dead
	_view.get_node("%DeadBox").visible = dead
	if dead:
		(_view.get_node("%DeadLabel") as Label).text = \
				"부활까지 %d턴" % _bs.turns_until_return(_pilot)
	# 파일럿 스킬은 스탯 판 아래 **자기 판** — 인게임 탭에만 선다. 지속 효과는 칼럼
	# 밖(일러스트 좌측 하단)에 산다.
	_view.get_node("%SkillPanel").visible = ingame
	_skill_status = null
	_skill_use_btn = null
	_skill_status_shown = _skill_status_visible()
	if ingame:
		_build_skill_panel()
		_build_effect_thumbs()
	# 카드 밴드 · 딤은 탭을 따른다. `_targets` 를 방금 비웠으므로 카드 키도 다시 싣는다.
	_rebuild_fan_hits()

	# 열려 있던 정보 패널의 대상 버튼은 방금 통째로 free 됐다 — `_menu_key` 가
	# 가리키던 강조도 그 버튼과 함께 사라졌으므로 새 버튼에 다시 입힌다. 효과가
	# 만료돼 그 키 자체가 없어졌으면 패널을 닫는다(빈 판이 남는 것보다 낫다).
	if _menu_key != "":
		if _targets.has(_menu_key):
			_style_target(_menu_key, true)
			_build_menu_content()
		else:
			_close_menu()


## 자식을 **트리에서 먼저 떼고** 지운다 — `queue_free` 만 걸면 이번 프레임까지는
## 그대로 그려져서 새 줄과 글자가 겹쳐 보인다.
static func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# ─── 머리글 (탭 위) ─────────────────────────────────────────────────────────
## 파일럿 이름 + 기체명 + 성장치. **열 때 한 번만** 채우고 탭 전환은 건드리지
## 않는다 — `refresh()` 는 성장치 숫자만 다시 쓴다.
##
## 이름과 기체명은 **두 줄로 쌓는다**(예전에는 `HBoxContainer` 로 한 줄에 이어
## 붙였다). 쌓으면 둘의 x 가 같아 글자 폭을 잴 일이 아예 없어진다 — 각 줄은
## `clip_text` 로 자기 칸 안에 머문다. 기체명은 늘 보인다 — 메크 탭에 들어가야만
## 알 수 있는 값이 아니다.
func _fill_header() -> void:
	var pd: PlayerData = _bs.player_data_for(_pilot)
	var mech: MechData = _mech()
	_growth_label.text = BattleSim.fmt_score(_pilot.score)
	(_view.get_node("%Name") as Label).text = pd.name if pd != null else _bs.pilot_label(_pilot)
	(_view.get_node("%Mech") as Label).text = mech.name if mech != null else "메크 미배정"

# ─── 스탯 칩 ─────────────────────────────────────────────────────────────────
## 이 탭이 보여 줄 스탯 줄 목록. 줄 하나 = `[[key, 이름], …]`(칸 1개 = 전폭,
## 2개 = 반씩) — 값과 메뉴 내용은 key 로 갈린다.
##
## 인게임 / 메크 탭은 체력 · 공격력 · 존재감이 한 줄씩이고 값도 같은 꼴이다
## (체력 = `현재 / 최대`). 명중 / 회피는 **전장 줄과 교전 줄**로 나눈다 — 두
## 무대가 각자 자기 스탯을 읽으므로 한 칸으로 묶으면 어느 말인지가 안 나온다.
func _chip_defs() -> Array:
	match _tab:
		Tab.INGAME:
			return [[["hp", "체력"]], [["atk", "공격력"]], [["presence", "존재감"]],
					[["hit", "전장 명중"], ["eva", "전장 회피"]],
					[["e_hit", "교전 명중"], ["e_eva", "교전 회피"]]]
		Tab.PILOT:
			# 선수 스탯 여섯을 두 칸씩 세 줄로(전장 명중·회피 / 교전 명중·회피 /
			# 공격·체력 성장). 표는 `PlayerData` 가 소유하므로 그 순서대로 짝짓는다.
			var defs: Array = []
			for i in range(0, PlayerData.STAT_KEYS.size(), 2):
				var line: Array = []
				for j in range(i, mini(i + 2, PlayerData.STAT_KEYS.size())):
					line.append([String(PlayerData.STAT_KEYS[j]),
							String(PlayerData.STAT_LABELS[j])])
				defs.append(line)
			return defs
		_:
			return [[["m_hp", "체력"]], [["m_atk", "공격력"]], [["m_presence", "존재감"]]]


## 줄을 펼친 `[key, 이름]` 목록 — 제목 찾기용.
func _flat_chip_defs() -> Array:
	var out: Array = []
	for line in _chip_defs():
		out.append_array(line as Array)
	return out


func _build_chip_grid(lines: Array) -> void:
	var chips: Control = _view.get_node("%Chips")
	for raw in lines:
		var line: Array = raw as Array
		var row: Control = ROW_SCENE.instantiate() as Control
		chips.add_child(row)
		for cell in line:
			_make_chip(String(cell[0]), String(cell[1]), row)


## 스탯 칸 하나(`UI_Comp_PilotDetailStatCell.tscn`) — 스탯 판 위에 얹힌 작은 판. 왼쪽에 이름,
## 오른쪽 정렬로 값. 누르면 메뉴가 열려야 하므로 Button 이고, 라벨들은 IGNORE 라
## 클릭을 가로채지 않는다. 폭은 줄(HBox)이 나눈다.
func _make_chip(key: String, chip_name: String, row: Control) -> void:
	var btn := CELL_SCENE.instantiate() as Button
	row.add_child(btn)
	btn.pressed.connect(_on_target_pressed.bind(key))

	var icon: TextureRect = btn.get_node("%Icon")
	var name_lbl: Label = btn.get_node("%Name")
	var icon_key: String = String(CHIP_ICONS.get(key, ""))
	if icon_key.is_empty():
		icon.visible = false
		name_lbl.offset_left = CHIP_PAD_X
	else:
		icon.texture = KeywordIcon.texture(icon_key, int(CHIP_ICON_PX * 2.0),
				BattleTheme.TEXT_KEY, Color(BattleTheme.CHIP_BG, 1.0))
	name_lbl.text = chip_name

	var rec: Dictionary = {"button": btn, "style": TargetStyle.CHIP,
			"value": btn.get_node("%Value"), "bonus": btn.get_node("%Bonus"), "key": key}
	_targets[key] = rec
	_layout_chip_value(rec)
	_style_target(key, false)


## 칩 값 + 괄호 보너스를 쓰고 자리를 잡는다. 보너스는 맨 오른쪽, 값은 그 왼쪽에
## 붙는다 — 색이 다른 두 덩이라 Label 둘로 나누고 보너스 폭만큼 값 칸의 오른쪽
## 끝을 당긴다. **값 라벨의 clip_text 는 필수다** — 오른쪽 정렬 Label 은 글자가
## rect 보다 넓으면 정렬을 포기하고 rect 왼쪽부터 그려 오른쪽으로 넘쳐 나간다.
func _layout_chip_value(rec: Dictionary) -> void:
	var key: String = String(rec["key"])
	var val_lbl := rec["value"] as Label
	var bonus_lbl := rec["bonus"] as Label
	var bonus: int = _chip_bonus(key)
	var bonus_text: String = "" if bonus == 0 else "(%+d)" % bonus
	bonus_lbl.text = bonus_text
	bonus_lbl.theme_type_variation = \
			&"BattlePositiveLabel" if bonus > 0 else &"BattleNegativeLabel"
	var bonus_w: float = 0.0
	if bonus_text != "":
		bonus_w = bonus_lbl.get_theme_font("font").get_string_size(bonus_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_BONUS_FONT).x + CHIP_BONUS_GAP
	val_lbl.text = _chip_value(key)
	val_lbl.offset_right = -(CHIP_PAD_X + bonus_w)

## 값 뒤 괄호의 보너스. 체력 · 공격력은 기본값(메크) 대비 지금 값의 증감(성장 ·
## 스킬 · 메크 · 카드 영구분이 모두 들어간다), 존재감은 특수 능력이 **올렸을 때만**.
func _chip_bonus(key: String) -> int:
	match key:
		"hp", "m_hp":
			return _pilot.max_hp - _pilot.base_max_hp
		"atk", "m_atk":
			return _pilot.atk - _pilot.base_atk
		"presence", "m_presence":
			return maxi(0, _presence_delta())
	return 0


func _presence_delta() -> int:
	var sk: PilotSkillSystem = _bs.skill if _bs != null else null
	return sk.presence_delta(_pilot) if sk != null else 0


## 정보 패널을 여는 것 셋(칩 · 효과 썸네일 · 카드)의 강조를 한 곳에서 바꾼다.
## 모양은 종류마다 다르지만 **"지금 이걸 보고 있다"는 신호는 하나**여야 하므로
## 색과 테두리 두께 규칙은 공유한다(`BattleChipButton(On)` · `BattleFxButton(On)` —
## `BattleTheme.chip_box`).
func _style_target(key: String, highlighted: bool) -> void:
	if not _targets.has(key):
		return
	var rec: Dictionary = _targets[key] as Dictionary
	var btn := rec["button"] as Button
	if not is_instance_valid(btn):
		return
	match int(rec["style"]):
		TargetStyle.CARD:
			# **버튼은 아무것도 그리지 않는다**(`PilotDetailCardBand`). 강조는 **손패의
			# 호버와 같은 자세**다 — 정보 패널이 열린 카드가 부채꼴의 초점이 되어 커지고
			# 앞으로 나오며 이웃이 비켜선다(`_relayout_fan`). 이전 / 새 키가 같은 프레임에
			# 연달아 오므로 한 번으로 모은다.
			_queue_fan_relayout()
		TargetStyle.FX:
			btn.theme_type_variation = &"BattleFxButtonOn" if highlighted else &"BattleFxButton"
		_:
			btn.theme_type_variation = &"BattleChipButtonOn" if highlighted else &"BattleChipButton"

## 값 라벨을 들고 있는 대상(= 스탯 칩)만 다시 쓴다. 효과 썸네일과 카드는 값이
## 바뀌면 구성 자체가 바뀌므로 `refresh()` 의 서명 비교가 본문을 다시 세운다.
func _refresh_target_values() -> void:
	for key in _targets.keys():
		var rec: Dictionary = _targets[key] as Dictionary
		var lbl := rec.get("value") as Label
		if lbl == null or not is_instance_valid(lbl):
			continue
		_layout_chip_value(rec)


## 칩에 크게 찍히는 **최종 값**. 기본값 · 증가분은 여기 적지 않는다 — 그건
## 칩을 눌러야 나오는 메뉴의 몫이다.
func _chip_value(key: String) -> String:
	var pd: PlayerData = _bs.player_data_for(_pilot)
	# 선수 스탯 여섯은 키 이름이 그대로 `PlayerData` 의 필드명이라 하나씩
	# 적지 않고 표를 지나간다 — 스탯이 늘어도 고칠 자리가 없다.
	if key in PlayerData.STAT_KEYS:
		return str(int(pd.get(key))) if pd != null else "—"
	match key:
		"hp":
			return "%d / %d" % [_pilot.hp, _pilot.max_hp]
		"atk", "m_atk":
			return str(_pilot.atk)
		"hit":
			return str(_bs.sim_core.lane_adjusted(_pilot.hit, _pilot))
		"eva":
			return str(_bs.sim_core.lane_adjusted(_pilot.evasion, _pilot))
		"presence", "m_presence":
			return str(_pilot.presence + maxi(0, _presence_delta()))
		"e_hit":
			return str(_pilot.engage_hit)
		"e_eva":
			return str(_pilot.engage_eva)
		"m_hp":
			# 메크 탭도 인게임과 같은 값 — 지금 이 전장의 체력.
			return "%d / %d" % [_pilot.hp, _pilot.max_hp]
	return "—"


# ─── 지속 효과 썸네일 ───────────────────────────────────────────────────────
## 지금 이 파일럿에게 걸려 있는 효과의 키 목록. `refresh()` 가 이 목록을 지난
## 값과 견줘 **구성이 달라졌을 때만** 본문을 다시 세운다 — 값만 바뀌었으면
## 라벨 갱신으로 끝내야 열어 둔 정보 패널이 안 닫힌다.
func _fx_signature() -> Array:
	var out: Array = []
	for raw in _effect_defs():
		out.append(String((raw as Dictionary)["key"]))
	return out


## 걸려 있는 효과 하나 = 사전 하나. **걸려 있지 않으면 목록에 없다** — 꺼져 있는
## 칸을 회색으로 늘어놓으면 "몇 개가 켜져 있는가"를 세어야 한다.
##
## 두 종류가 섞여 있다.
##
## **(1) 슬롯 효과** — 한 칸을 카드들이 서로 덮어쓰는 것들이라 출처를 물어봐야
## 답이 하나뿐이다. 라인전 스탯(명중/회피 배율), 적립 배율(턴 · 단계 만료),
## 일시 공격력, 보호막 넷.
##
## **(2) 카드별 지속 효과** — `PilotData.persistent_fx` 장부의 한 줄이 한 칸이
## 된다. 예전에는 이쪽도 속성으로 뭉쳐 있어서 `영구 +N%` 한 칸이 [용 보상]과
## [핫핸드]를 함께 뜻했고, 최대 체력 · 공격력 가산분([붉은 가루] · [녹색 병])은
## **아예 표시되지 않았다** — 성장 재계산에 지워지지 않으려고 `bonus_*` 필드로
## 따로 사는 값들이라 어느 칩에도 안 실렸기 때문이다. 지금은 카드 이름이 곧
## 칸 이름이라 "무엇을 몇 번 먹었나"가 그대로 읽힌다.
##
## **(3) 잔여분** — 장부에 없는 몫(메크 패시브가 직접 미는 영혼 수확 · 조준
## 보정 …)은 합계에서 장부를 뺀 나머지를 한 칸으로 세운다. 합계 슬롯과 장부가
## 어긋나면 화면이 조용히 거짓말을 하게 되므로 남는 몫을 감추지 않는다.
##
## 팀 단위로 걸리는 계획 살인 예약은 여기 없다 — 파일럿의 것이 아니라 팀의
## 것이라 다섯 명 모두에게 같은 썸네일이 떠 무엇이 누구 것인지가 흐려진다.
func _effect_defs() -> Array:
	var out: Array = []
	if not is_zero_approx(_pilot.lane_stat_mod):
		var up: bool = _pilot.lane_stat_mod > 0.0
		out.append({
			"key": "fx:lane",
			"src": String(_pilot.fx_src.get("lane", "")),
			"short": "라인",
			"title": "라인전 스탯",
			"value": "%+d%%" % roundi(_pilot.lane_stat_mod * 100.0),
			"color": Color(1.00, 0.62, 0.48) if up else Color(0.55, 0.82, 1.00),
		})
	if not is_zero_approx(_pilot.eva_card_mod):
		out.append({
			"key": "fx:eva",
			"src": String(_pilot.fx_src.get("eva", "")),
			"short": "회피",
			"title": "전장 회피 (카드)",
			"value": "%+d%%" % roundi(_pilot.eva_card_mod * 100.0),
			"color": Color(0.55, 0.82, 1.00),
		})
	if _pilot.ambush_hold:
		out.append({
			"key": "fx:ambush",
			"src": String(_pilot.fx_src.get("ambush", "")),
			"short": "매복",
			"title": "매복",
			"value": "고정",
			"color": Color(0.62, 0.90, 0.55),
		})
	if not is_equal_approx(_pilot.growth_rate_mult, 1.0):
		out.append({
			"key": "fx:rate",
			"src": String(_pilot.fx_src.get("rate", "")),
			"short": "적립",
			"title": "성장치 적립 배율",
			"value": "%+d%%" % roundi((_pilot.growth_rate_mult - 1.0) * 100.0),
			"color": Color(0.72, 1.00, 0.80),
		})
	if _pilot.atk_buff != 0:
		out.append({
			"key": "fx:atk",
			"short": "공격",
			"title": "일시 공격력",
			"value": "%+d" % _pilot.atk_buff,
			"color": Color(1.00, 0.82, 0.42),
		})
	if _pilot.shield > 0:
		out.append({
			"key": "fx:shield",
			"src": String(_pilot.fx_src.get("shield", "")),
			"short": "보호",
			"title": "보호막",
			"value": str(_pilot.shield),
			"color": Color(0.92, 0.92, 0.42),
		})
	_append_card_fx(out)
	_append_residual_fx(out)
	return out


## 종류별 색 / 잔여분 칸의 이름. 카드 칸과 잔여분 칸이 같은 표를 읽으므로
## 같은 종류의 효과는 어디에 뜨든 같은 색이다.
const FX_KIND_COLOR := {
	PilotData.FX_GROWTH_RATE: Color(1.00, 0.55, 0.28),
	PilotData.FX_MAX_HP:      Color(0.55, 0.95, 0.62),
	PilotData.FX_ATK:         Color(1.00, 0.72, 0.36),
	PilotData.FX_ATK_PCT:     Color(1.00, 0.72, 0.36),
	PilotData.FX_HP_PCT:      Color(0.55, 0.95, 0.62),
}
const FX_KIND_NAME := {
	PilotData.FX_GROWTH_RATE: "성장 적립",
	PilotData.FX_MAX_HP:      "최대 체력",
	PilotData.FX_ATK:         "공격력",
	PilotData.FX_ATK_PCT:     "공격력 %",
	PilotData.FX_HP_PCT:      "최대 체력 %",
}
## 단위가 %인 종류(나머지는 스탯 값 그대로).
const FX_PCT_KINDS: Array = [
	PilotData.FX_GROWTH_RATE, PilotData.FX_ATK_PCT, PilotData.FX_HP_PCT,
]


## 장부(`PilotData.persistent_fx`)의 한 줄 = 썸네일 한 칸. **카드 이름이 곧
## 칸 이름**이고 약칭은 그 앞 두 글자다(공백은 빼고 센다 — "용 보상" 은 "용보").
func _append_card_fx(out: Array) -> void:
	for raw in _pilot.persistent_fx:
		var e: Dictionary = raw as Dictionary
		var amount: float = float(e["amount"])
		if is_zero_approx(amount):
			continue
		var kind: String = String(e["kind"])
		# 장부의 출처는 카드 식별자(`CardData.card_uid`) — 이름은 표시할 때 푼다(l10n).
		var src: String = String(e["src"])
		var src_name: String = CardData.name_of_uid(src)
		out.append({
			"key": "fx:src:%s|%s" % [kind, src],
			"src": src,
			"short": _fx_short(src_name),
			"title": src_name,
			"value": _fx_value(kind, amount),
			"color": FX_KIND_COLOR.get(kind, Color(0.86, 0.86, 0.90)) as Color,
		})


## 합계 슬롯에서 장부를 뺀 나머지. 메크 패시브가 `bonus_*` 를 직접 미는 몫이라
## 출처를 카드 이름으로 부를 수 없다 — 종류 이름으로 한 칸을 세운다.
func _append_residual_fx(out: Array) -> void:
	var specs: Array = [
		[PilotData.FX_GROWTH_RATE, "적립", _pilot.growth_rate_bonus],
		[PilotData.FX_MAX_HP, "체력", float(_pilot.bonus_max_hp)],
		[PilotData.FX_ATK, "공격", float(_pilot.bonus_atk_flat)],
		[PilotData.FX_ATK_PCT, "공%", _pilot.bonus_atk_mult],
		[PilotData.FX_HP_PCT, "체%", _pilot.bonus_max_hp_mult],
	]
	for raw in specs:
		var spec: Array = raw as Array
		var kind: String = String(spec[0])
		var rest: float = float(spec[2]) - _pilot.persistent_fx_total(kind)
		if is_zero_approx(rest):
			continue
		out.append({
			"key": "fx:rest:%s" % kind,
			"short": String(spec[1]),
			"title": "%s (그 밖의 영구 가산)" % String(FX_KIND_NAME.get(kind, kind)),
			"value": _fx_value(kind, rest),
			"color": FX_KIND_COLOR.get(kind, Color(0.86, 0.86, 0.90)) as Color,
		})


## 썸네일에 찍히는 두 글자. 아이콘 에셋이 없으므로 약칭이 곧 아이콘이고,
## 온전한 이름은 눌러서 여는 정보 패널의 제목이 들고 있다.
static func _fx_short(src: String) -> String:
	var compact: String = src.replace(" ", "")
	return compact.substr(0, 2) if compact.length() >= 2 else compact


## 종류마다 단위가 다르다 — 배율 종류는 %, 나머지는 스탯 값 그대로.
static func _fx_value(kind: String, amount: float) -> String:
	if kind in FX_PCT_KINDS:
		return "%+d%%" % roundi(amount * 100.0)
	return "%+d" % roundi(amount)


## `fx:src:` / `fx:rest:` 키가 가리키는 (종류, 값). 정보 패널의 내역이 읽는다.
func _fx_entry(key: String) -> Dictionary:
	for raw in _effect_defs():
		var d: Dictionary = raw as Dictionary
		if String(d["key"]) == key:
			return d
	return {}


## 지속 효과 썸네일 — **일러스트 좌측 하단**, 카드 부채꼴 바로 위(씬 `%FxGrid`, 한 줄
## 여섯). 제목은 없고 걸린 효과가 없으면 아무것도 안 그린다(위 상수 절의 주석 참고).
##
## **줄은 위로 자란다.** 격자의 아래끝을 카드 부채꼴 위에 붙여 놓았으므로(`_build`),
## 효과가 여섯 개를 넘어 두 줄이 되어도 카드 부채꼴을 침범하지 않는다 — 아래로
## 자라게 두면 두 번째 줄이 그대로 카드 위에 내려앉는다.
func _build_effect_thumbs() -> void:
	for raw in _effect_defs():
		_make_fx_thumb(raw as Dictionary)

## 썸네일 줄의 아래끝 y. 카드 부채꼴 윗변에서 역산한다.
func _fx_bottom_y() -> float:
	return _fan_top_y() - FX_ABOVE_FAN_GAP


## 썸네일 한 칸(`UI_Comp_PilotDetailFxThumb.tscn`) — 위에 두 글자 약칭(효과별 색), 아래에 작게
## 지금 값. 아이콘 에셋이 없으므로 **글자가 곧 아이콘**이다. 두 글자로 줄인 것은 68px
## 칸에서 온전한 이름("공격적인 라인전")이 들어갈 자리가 없기 때문이고, 전체
## 이름은 눌러서 여는 패널의 제목이 들고 있다.
##
## 출처 카드를 알면 그 카드 일러스트가 곧 아이콘이다 — 둥근 사각형으로 깎은 아트
## (`%Art`, 버튼 테두리가 보이게 인셋 3) + 아래 값 띠(`%Band` · `%BandValue`).
func _make_fx_thumb(d: Dictionary) -> void:
	var key: String = String(d["key"])
	var btn := FX_SCENE.instantiate() as Button
	_view.get_node("%FxGrid").add_child(btn)
	btn.pressed.connect(_on_target_pressed.bind(key))

	var art: Texture2D = CardImages.art_for(String(d.get("src", "")))
	var has_art: bool = art != null
	for n in ["%Art", "%Band", "%BandValue"]:
		btn.get_node(n).visible = has_art
	for n in ["%Short", "%Value"]:
		btn.get_node(n).visible = not has_art
	if has_art:
		(btn.get_node("%Art") as TextureRect).texture = art
		(btn.get_node("%BandValue") as Label).text = String(d["value"])
	else:
		var short_lbl: Label = btn.get_node("%Short")
		short_lbl.text = String(d["short"])
		short_lbl.add_theme_color_override("font_color", d["color"] as Color)
		(btn.get_node("%Value") as Label).text = String(d["value"])

	_targets[key] = {"button": btn, "style": TargetStyle.FX}
	_style_target(key, false)

# ─── 카드 ────────────────────────────────────────────────────────────────────
## 이 파일럿이 개시에 배분받은 카드(`slot` = "mech" / "pilot").
func _starter_cards(slot: String) -> Array:
	var rec: Dictionary = _bs.starter_cards.get(_pilot, {}) as Dictionary
	return rec.get(slot, []) as Array


## `_starter_cards(slot)` 와 같은 길이의 슬롯 꼬리표 — 탭별 딤이 읽는다.
func _slot_tags(slot: String) -> Array:
	var out: Array = []
	out.resize(_starter_cards(slot).size())
	out.fill(slot)
	return out


## 보유 카드를 **손패와 같은 자리 · 같은 부채꼴로** 세운다. 열 때 한 번만 돈다 —
## 탭이 바뀌면 `_rebuild_fan_hits` 가 딤과 입력 밴드만 고친다.
##
## 기하는 손패(`CardPhaseManager.slot_spacing` / `slot_position` / `_fan_angle` /
## `_fan_arc_drop`)와 같은 규칙이다 — 카드 **중심**이 행 아래에 놓인 원 위를 타므로
## 기울기와 세로 처짐이 언제나 일치한다.
##
## 카드는 씬 `%CardFan`, 입력 밴드는 그 **뒤 형제** `%CardFanHits` 에 담아 밴드 쪽이
## 언제나 위에서 픽을 받고, 카드끼리의 z-order 는 `CardFan` 안에서만 흔들린다.
func _build_card_fan(cards: Array, slots: Array) -> void:
	var n: int = cards.size()
	if n <= 0:
		return
	var s: float = _fan_scale()
	var cw: float = CardPhaseManager.hand_card_w()
	# 간격은 손패와 같다 — 겹치지 않는 폭(cw + 간격)에서 시작해 손패 너비를 넘으면
	# 고르게 압축된다(`CardPhaseManager.slot_spacing`).
	_fan_spacing = cw + BattleSim.BS_HAND_CARD_GAP
	if n > 1 and float(n) * cw + float(n - 1) * BattleSim.BS_HAND_CARD_GAP > _bs.BS_HAND_WIDTH:
		_fan_spacing = (_bs.BS_HAND_WIDTH - cw) / float(n - 1)
	# 손패 행의 가운데 — `BS_HAND_CENTER` 는 가운데 카드의 (배율 전) 왼쪽 위다.
	_fan_cx = _bs.BS_HAND_CENTER.x + Card.CARD_W * 0.5

	for i in n:
		var dx: float = (float(i) - float(n - 1) * 0.5) * _fan_spacing
		_fan_dx.append(dx)
		var node := _bs.CARD_SCENE.instantiate() as Card
		node.pivot_offset = Vector2(Card.CARD_W * 0.5, Card.CARD_H * 0.5)
		# 배율은 트리에 들어가기 전에(손패 `spawn_card_node` 와 같은 순서) — 아래
		# `tween_to` 는 인트로의 첫 비행 트윈이 곧바로 끊어 버리므로 그것만으로는
		# 배율이 안 들어간다.
		node.scale = Vector2.ONE * s
		# add_child BEFORE setup — Card.gd 의 @onready 참조가 트리 진입 후에야
		# 풀린다 (CardPileViewer._build_grid 와 동일).
		_fan_root.add_child(node)
		# is_player_card=true — 손패와 같은 그림(시전자 리본 · 드롭 쉐도우 · 호버
		# 확대/밝기)을 그대로 쓴다. 입력은 받지 않는다(밴드 버튼이 받는다).
		node.setup(cards[i] as CardData, true, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 펼침 — 가운데 쪽으로 모인 자리(dx × `FAN_SPREAD_FROM`)에서 출발해 제자리로.
		var from_dx: float = dx * FAN_SPREAD_FROM
		node.position = _fan_pos_for_dx(from_dx, 0.0)
		node.rotation = _fan_angle(from_dx)
		# `tween_to` 가 `Card._base_scale` 을 기록한다 — 그래야 호버 확대
		# (×`HOVER_SCALE`)가 이 배율 위에 곱해진다.
		node.tween_to(_fan_global(_fan_pos_for_dx(dx, 0.0)), _fan_angle(dx), Vector2.ONE * s,
				FAN_SPREAD_SEC, Tween.EASE_OUT, Tween.TRANS_CUBIC)
		_fan_nodes.append(node)
		_fan_cards.append(cards[i])
		_fan_slots.append(slots[i])
		_fan_keys.append("")
	_rebuild_fan_hits()

## 이 탭에서 카드 i 가 살아 있는가 — 인게임은 전부, 파일럿 / 메크 탭은 그 슬롯만.
func _fan_card_active(i: int) -> bool:
	match _tab:
		Tab.PILOT:
			return String(_fan_slots[i]) == "pilot"
		Tab.MECH:
			return String(_fan_slots[i]) == "mech"
	return true


## 지금 탭에 맞춰 카드 딤과 입력 밴드를 다시 세우고 카드 키를 `_targets` 에 싣는다.
## `_rebuild_body` 가 `_targets` 를 비운 직후마다 부른다.
##
## **입력은 카드 rect 가 아니라 밴드(`PilotDetailCardBand`)가 받는다.** 겹친 카드 중
## 나중 카드가 앞에 서므로 카드 i 가 실제로 보이는 폭은 자기 왼쪽 변부터 **다음 카드의
## 왼쪽 변**까지다 — 그 폭이 그대로 버튼 하나가 된다(손패의 `_apply_hit_bands` 와 같은
## 계산). 밴드는 **쉬는 자리**에 고정이다 — 호버로 카드가 비켜설 때마다 밴드까지
## 움직이면 커서 밑의 밴드가 바뀌어 초점이 떨린다. 딤드 카드에는 밴드가 없다 —
## 그 자리를 누르면 `_card_zone` 이 받아 아무 일도 일어나지 않는다.
func _rebuild_fan_hits() -> void:
	if _fan_hits == null or not is_instance_valid(_fan_hits):
		return
	_clear_children(_fan_hits)
	var n: int = _fan_nodes.size()
	if n == 0:
		return
	var cw: float = CardPhaseManager.hand_card_w()
	var top_y: float = _fan_top_y()
	var band_h: float = CardPhaseManager.hand_card_h() + _fan_arc_drop(_fan_dx[0])
	for i in n:
		var active: bool = _fan_card_active(i)
		var node := _fan_nodes[i] as Card
		if is_instance_valid(node):
			node.set_dimmed(not active)
		if not active:
			_fan_keys[i] = ""
			continue
		var key: String = "card:%d" % i
		_fan_keys[i] = key
		# 양 끝 카드만 자기 변까지 밴드를 넓힌다 — 왼쪽 끝은 왼쪽으로 가려질
		# 것이 없고, 오른쪽 끝은 맨 앞에 서 있어 카드 전체가 보인다.
		var cx: float = _fan_cx + _fan_dx[i]
		var left: float = cx - cw * 0.5
		var right: float = cx + cw * 0.5
		if i < n - 1:
			right = _fan_cx + _fan_dx[i + 1] - cw * 0.5
		var btn := BAND_SCENE.instantiate() as Button
		btn.position = Vector2(left, top_y)
		btn.size = Vector2(maxf(12.0, right - left), band_h)
		btn.pressed.connect(_on_target_pressed.bind(key))
		btn.mouse_entered.connect(_on_fan_band_hover.bind(i, true))
		btn.mouse_exited.connect(_on_fan_band_hover.bind(i, false))
		_fan_hits.add_child(btn)
		_targets[key] = {"button": btn, "style": TargetStyle.CARD,
				"card": _fan_cards[i], "node": node}
		_style_target(key, false)
	_queue_fan_relayout()

## 부채꼴 카드 배율 = 손패 배율.
static func _fan_scale() -> float:
	return CardPhaseManager.HAND_CARD_SCALE


## 부채꼴 상태를 비운다(카드 노드는 떠나는 상세 한 장과 함께 지워진다).
func _reset_fan() -> void:
	_fan_nodes.clear()
	_fan_cards.clear()
	_fan_slots.clear()
	_fan_keys.clear()
	_fan_dx = PackedFloat32Array()
	_fan_root = null
	_fan_hits = null
	_fan_hover = -1

## 카드 i 의 자리(왼쪽 위, 배율 전 좌표 — 손패 `slot_position` 과 같은 규약).
## `push` 는 초점 카드를 피해 비켜서는 가로 거리.
func _fan_slot_pos(i: int, push: float) -> Vector2:
	return _fan_pos_for_dx(_fan_dx[i], push)


## 부채꼴 좌표(정보 묶음 로컬) → `Card.tween_to` 가 받는 화면 좌표. 열기 연출 동안
## `_ui_root` 가 아래로 밀려 있으므로 그만큼 더해 줘야 한다 — 안 그러면 tween_to 가
## 그 오프셋을 빼 버려 카드가 `UI_SLIDE_PX` 만큼 위에 내려앉는다(실측: 제목을 덮었다).
func _fan_global(local: Vector2) -> Vector2:
	if _ui_root == null or not is_instance_valid(_ui_root):
		return local
	return local + _ui_root.position


## 가로 오프셋 `dx` 의 부채꼴 자리 — 손패 `slot_position` 과 같은 식(행 높이
## `BS_HAND_CENTER.y` + 원호 처짐). 펼침 연출이 제자리가 아닌 dx 로도 부른다.
func _fan_pos_for_dx(dx: float, push: float) -> Vector2:
	return Vector2(_fan_cx + dx + push - Card.CARD_W * 0.5,
			_bs.BS_HAND_CENTER.y + _fan_arc_drop(dx))


## 부채꼴 윗변(= 가운데 카드의 **보이는** 윗변) y. 손패와 같은 행이라
## `BS_HAND_CENTER` 가 이미 세이프 에어리어 오프셋을 먹고 있다.
func _fan_top_y() -> float:
	return _bs.BS_HAND_CENTER.y + Card.CARD_H * 0.5 - CardPhaseManager.hand_card_h() * 0.5


## 부채꼴 원 위에서의 기울기(라디안) — 손패와 같은 원.
static func _fan_angle(dx: float) -> float:
	return asin(clampf(dx / BattleSim.BS_HAND_FAN_RADIUS, -1.0, 1.0))


## 그 카드가 부채꼴 꼭대기보다 아래로 처지는 높이(px). 가운데에서 0.
static func _fan_arc_drop(dx: float) -> float:
	var r: float = BattleSim.BS_HAND_FAN_RADIUS
	var d: float = clampf(absf(dx), 0.0, r)
	return r - sqrt(r * r - d * d)


# ─── 부채꼴 초점 (손패 호버와 같은 동작) ─────────────────────────────────────
func _on_fan_band_hover(i: int, entered: bool) -> void:
	if entered:
		_fan_hover = i
	elif _fan_hover == i:
		_fan_hover = -1
	_queue_fan_relayout()


## 초점 카드 — 가리키는 카드가 우선, 없으면 정보 패널이 열린 카드. -1 = 없음.
func _fan_focus() -> int:
	if _fan_hover >= 0 and _fan_hover < _fan_nodes.size():
		return _fan_hover
	return _fan_keys.find(_menu_key) if _menu_key.begins_with("card:") else -1


## 밴드를 옮겨 가면 exit / enter 가 한 프레임에 연달아 온다 — 둘을 한 번으로
## 모아야 트윈끼리 서로 죽이지 않는다(손패 `_queue_hand_reflow` 와 같은 이유).
func _queue_fan_relayout() -> void:
	if _fan_relayout_queued:
		return
	_fan_relayout_queued = true
	_relayout_fan.call_deferred()


## 모든 카드를 지금 초점에 맞는 자리로 트윈한다. 초점 카드는 `set_hovered` 로
## 커지고 밝아지며 맨 앞에 서고, 나머지는 손패와 같은 감쇠로 비켜선다.
func _relayout_fan() -> void:
	_fan_relayout_queued = false
	var n: int = _fan_nodes.size()
	if n == 0:
		return
	var focus: int = _fan_focus()
	var s: float = _fan_scale()
	for i in n:
		if not is_instance_valid(_fan_nodes[i]):
			continue
		var c := _fan_nodes[i] as Card
		c.set_hovered(i == focus)
		c.tween_to(_fan_global(_fan_slot_pos(i, _fan_push(i, focus, n))), _fan_angle(_fan_dx[i]),
				Vector2.ONE * s, BattleSim.BS_HAND_SPRING_DURATION,
				BattleSim.BS_HAND_TWEEN_EASE, BattleSim.BS_HAND_TWEEN_TRANS)
	# z-order — 왼쪽부터 쌓고(오른쪽 카드가 위) 초점 카드만 맨 앞으로.
	for i in n:
		if is_instance_valid(_fan_nodes[i]):
			var c2 := _fan_nodes[i] as Card
			c2.get_parent().move_child(c2, i)
	if focus >= 0 and is_instance_valid(_fan_nodes[focus]):
		var cf := _fan_nodes[focus] as Card
		cf.get_parent().move_child(cf, n - 1)


## 초점 옆 카드가 비켜서는 거리 — 손패 `hover_push_offset` 과 같은 식(양 끝은
## 고정, 감쇠 `BS_HAND_HOVER_FALLOFF_POW`).
func _fan_push(i: int, focus: int, n: int) -> float:
	if focus < 0 or i == focus or n <= 1:
		return 0.0
	var steps_to_end: int = (n - 1 - focus) if i > focus else focus
	if steps_to_end <= 0:
		return 0.0
	var clearance: float = CardPhaseManager.hand_card_w() * Card.HOVER_SCALE * 0.5 \
			+ BattleSim.BS_HAND_HOVER_MIN_STRIP
	var amount: float = maxf(BattleSim.BS_HAND_HOVER_PUSH, clearance - _fan_spacing)
	var t: float = float(absi(i - focus)) / float(steps_to_end)
	var push: float = amount * (1.0 - pow(t, BattleSim.BS_HAND_HOVER_FALLOFF_POW))
	return push if i > focus else -push


## 파일럿 스킬 판(씬 `%SkillPanel`) — 스탯 판 아래의 **자기 판**.
##   [아이콘 타일]  이름
##                  설명문(키워드 아이콘 · 카드 비용 아이콘 · 줄바꿈)
##                  상태 한 줄 (쿨타임이 남았을 때 / 충전 · 패시브 토큰)
##   [               사용               ]   ← 패시브에는 없다
## 스킬이 없는 파일럿(모브)도 판은 선다 — "스킬 없음" 한 줄. 칸을 통째로 빼면
## "이 선수는 스킬이 없다"가 화면에서 사라져 버그처럼 읽힌다.
## 판 높이는 컨테이너가 내용(타일 92 와 글 줄 중 큰 쪽 + 버튼)에 맞춘다.
func _build_skill_panel() -> void:
	var sk: PilotSkillSystem = _bs.skill
	var icon_slot: Control = _view.get_node("%SkillIconSlot")
	var desc_slot: Control = _view.get_node("%SkillDescSlot")
	_clear_children(icon_slot)
	_clear_children(desc_slot)
	var has_skill: bool = sk != null and sk.has_skill(_pilot)
	_view.get_node("%SkillTop").visible = has_skill
	_view.get_node("%NoSkillBox").visible = not has_skill
	# 패시브에는 버튼이 없다 — 누를 수 없는 것에 비활성 버튼을 두면 "언젠가는
	# 눌리는 것"으로 읽힌다.
	var show_use: bool = has_skill and sk.skill_type(_pilot) != PilotSkillSystem.TYPE_PASSIVE
	_view.get_node("%SkillUseGap").visible = show_use
	_view.get_node("%SkillUse").visible = show_use
	if not has_skill:
		return

	icon_slot.add_child(SkillImages.make_icon_tile(
			String(sk.def_for(_pilot).get("key", "")), SKILL_TILE_PX,
			BattleTheme.SKILL_TILE_BG, BattleTheme.SKILL_TILE_ICON,
			BattleTheme.SKILL_TILE_SHADOW))
	(_view.get_node("%SkillName") as Label).text = sk.skill_name(_pilot)

	# 설명문 — 카드 설명과 같은 길(`StrategyIcon`): 키워드 아이콘, `[카드]` 앞의
	# 비용 아이콘, 줄바꿈, `{eul}` 조사. 높이는 같은 규칙으로 잰다.
	var refs: Array = CardData.ref_entries(sk.skill_description_key(_pilot))
	var desc_text: String = sk.skill_description(_pilot)
	var desc_h: float = StrategyIcon.rich_height(desc_text, SKILL_DESC_W, SKILL_DESC_FONT,
			refs, true)
	var desc := StrategyIcon.make_rich_label(desc_text, SKILL_DESC_FONT,
			BattleTheme.TEXT_DESC, BattleTheme.SKILL_KW_ICON, BattleTheme.SKILL_KNOCK,
			KeywordIcon.TARGET_ANY_COLOR, KeywordIcon.TARGET,
			KeywordIcon.SPECIAL_COLOR_DARK, refs, true)
	desc.position = Vector2.ZERO
	desc.size = Vector2(SKILL_DESC_W, desc_h)
	desc_slot.custom_minimum_size = Vector2(0.0, desc_h)
	desc_slot.add_child(desc)

	# 상태 한 줄 — 남은 턴 / 토큰. **쿨타임이 끝나 "사용 가능"일 때는 뺀다** —
	# 그 말은 아래 사용 버튼이 밝아져 이미 하고 있다.
	_skill_status_shown = _skill_status_visible()
	_view.get_node("%SkillStatusGap").visible = _skill_status_shown
	_view.get_node("%SkillStatusBox").visible = _skill_status_shown
	if _skill_status_shown:
		_skill_status = _view.get_node("%SkillStatus")
	if show_use:
		_skill_use_btn = _view.get_node("%SkillUse")
	_refresh_skill_block()

## 상태 줄을 보일 것인가 — 쿨타임형이 준비된 상태("사용 가능")만 아니다.
func _skill_status_visible() -> bool:
	var sk: PilotSkillSystem = _bs.skill if _bs != null else null
	if sk == null or _pilot == null or not sk.has_skill(_pilot):
		return false
	return not (sk.skill_type(_pilot) == PilotSkillSystem.TYPE_COOLDOWN
			and sk.cooldown_left(_pilot) <= 0)


## 상태 줄과 버튼 활성만 다시 쓴다 — 트리는 건드리지 않는다.
func _refresh_skill_block() -> void:
	var sk: PilotSkillSystem = _bs.skill
	if sk == null or _pilot == null:
		return
	if _skill_status != null and is_instance_valid(_skill_status):
		_skill_status.text = sk.status_text(_pilot)
	if _skill_use_btn != null and is_instance_valid(_skill_use_btn):
		_skill_use_btn.disabled = not sk.can_activate(_pilot)


## 사용 버튼. **발동한 뒤에는 패널을 닫는다** — 결과가 손패 · 전장 · 스트립에
## 나타나는데 딤이 그 위를 덮고 있으면 아무 일도 안 일어난 것처럼 보이고,
## 계략처럼 자기 오버레이(레이어 10)를 여는 스킬은 이 패널(레이어 13) 뒤에
## 깔려 아예 보이지 않는다.
func _on_skill_use_pressed() -> void:
	var sk: PilotSkillSystem = _bs.skill
	if sk == null or _pilot == null or not sk.can_activate(_pilot):
		return
	var target: PilotData = _pilot
	close()
	sk.activate(target)


# ─── 정보 패널 (칩 · 지속 효과 · 카드 공용) ─────────────────────────────────
# 셋이 같은 판 하나를 나눠 쓴다. "지금 무엇을 보고 있는가"는 한 번에 하나여야
# 하는 질문이라, 판을 따로 두면 스탯 설명과 효과 설명이 화면에 동시에 떠서
# 어느 것이 방금 누른 것인지가 흐려진다.
func _on_target_pressed(key: String) -> void:
	if _menu_key == key:
		_close_menu()
		return
	_open_info(key)



func _open_info(key: String) -> void:
	_close_menu()
	_menu_key = key
	_style_target(key, true)
	# 바깥을 누르면 닫힌다. 뒤판(`%InfoMenu`)이 STOP 이라 뒤쪽 버튼이 전부 가려지므로
	# **뒤판이 직접 라우팅한다**(`_on_menu_backdrop_input`) — 아래 주석 참조.
	_menu_root.visible = true
	_build_menu_content(true)


## 뒤판 클릭을 **그 자리에 있던 버튼에게 대신 전달한다.**
##
## 예전에는 이 함수가 무조건 `_close_menu()` 만 했다. 그래서 공격력 설명을 열어
## 둔 채 명중 칩을 누르면 첫 클릭은 패널을 닫는 데 쓰이고, 명중 설명을 보려면
## **한 번 더** 눌러야 했다 — 스탯 여섯 개를 훑어보는 동안 클릭 수가 두 배가
## 되고, 화면은 열림 ↔ 닫힘을 반복해 깜빡인다. 정보 패널은 서로 갈아타는 것이
## 기본 동작이므로, 뒤판은 "닫기"가 아니라 "그 아래 있는 것을 대신 눌러 주기"를
## 해야 한다.
##
## 뒤판은 화면 전체(0, 0)에 놓인 Control 이라 누른 자리가 곧 전역 좌표다 — 버튼마다
## 전역 rect 와 견준다(컨테이너 안의 칸 · 탭도 같은 식).
func _on_menu_backdrop_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var at: Vector2 = mb.position

	# 1) 다른 정보 대상(칩 · 효과 · 카드) 위 — 곧장 그쪽으로 갈아탄다.
	for raw_key in _targets.keys():
		var key := String(raw_key)
		var btn := (_targets[key] as Dictionary)["button"] as Button
		if is_instance_valid(btn) and btn.get_global_rect().has_point(at):
			_on_target_pressed(key)
			return

	# 2) 탭 — 패널을 닫고 탭을 넘긴다(탭 자체도 `_close_menu` 를 부르지만,
	#    같은 탭을 누른 경우 그쪽이 일찍 돌아가므로 여기서 먼저 닫아 둔다).
	for i in _tab_buttons.size():
		var tb := _tab_buttons[i] as Button
		if is_instance_valid(tb) and tb.get_global_rect().has_point(at):
			_close_menu()
			_on_tab_pressed(i)
			return

	# 3) 스킬 사용 버튼 — 패널을 닫고 그대로 누른다(비활성이면 패널만 닫힌다).
	if _skill_use_btn != null and is_instance_valid(_skill_use_btn) \
			and _skill_use_btn.get_global_rect().has_point(at):
		_close_menu()
		_on_skill_use_pressed()
		return

	_close_menu()


func _close_menu() -> void:
	if _menu_key != "":
		_style_target(_menu_key, false)
	_menu_key = ""
	if _menu_root != null and is_instance_valid(_menu_root):
		_clear_children(_menu_root)
		_menu_root.visible = false


## 메뉴 판을 (다시) 세운다. `refresh()` 가 값이 바뀔 때마다 부르므로 메뉴에
## 적힌 숫자도 칩과 같은 순간의 값이다. 카드는 판이 아니라 손패의 설명판이다
## (`_build_card_desc`) — `animate` 는 그 등장 연출을 틀 것인가.
func _build_menu_content(animate: bool = false) -> void:
	if _menu_root == null or not is_instance_valid(_menu_root) or not _menu_root.visible:
		return
	if not _targets.has(_menu_key):
		return
	_clear_children(_menu_root)
	if _menu_key.begins_with("card:"):
		_build_card_desc(animate)
		return

	# 판(`UI_Comp_PilotDetailInfoMenu.tscn`) — 판 위 클릭은 메뉴를 닫지 않는다(씬에서 STOP).
	var panel := MENU_SCENE.instantiate() as Control
	_menu_root.add_child(panel)
	(panel.get_node("%Title") as Label).text = _target_title(_menu_key)
	var rows: Control = panel.get_node("%Rows")
	for row in _menu_rows(_menu_key):
		var line := MENU_ROW_SCENE.instantiate() as Control
		rows.add_child(line)
		(line.get_node("%Key") as Label).text = String(row[0])
		(line.get_node("%Value") as Label).text = String(row[1])

	var note: String = _menu_note(_menu_key)
	var note_lbl: RichTextLabel = panel.get_node("%Note")
	for n in ["%NoteGap", "%Note", "%NoteTail"]:
		panel.get_node(n).visible = note != ""
	if note != "":
		# **설명 높이는 그려진 글이 정한다** — 폭을 준 뒤 실제 내용 높이를 읽어 칸
		# 높이로 준다. 예전에는 fallback 폰트로 따로 재서 아이콘이 끼거나 테마
		# 폰트가 다르면 아랫줄이 판 밖으로 튀어나왔다.
		_fill_note(note_lbl, note)
		note_lbl.size = Vector2(MENU_W - MENU_PAD.x * 2.0, 0.0)
		note_lbl.custom_minimum_size = Vector2(0.0, note_lbl.get_content_height())
	_place_menu(panel)
	# 칸 · 탭이 막 다시 세워진 경우(값 갱신으로 본문 재구성) 컨테이너 정렬이 이번
	# 프레임 끝에 끝나므로 다음 프레임에 한 번 더 맞춘다.
	get_tree().process_frame.connect(_place_menu.bind(panel), CONNECT_ONE_SHOT)


## 판 위치 · 높이 — 누른 것과 같은 높이에서 시작하되 화면 위아래로는 넘기지 않는다.
## x 는 정보 칼럼 왼쪽(`MENU_GAP_X` 띄움). y 는 열기 연출 오프셋을 뺀 자리(정보 묶음 로컬).
func _place_menu(panel: Control) -> void:
	if not is_instance_valid(panel) or not _targets.has(_menu_key) or _ui_root == null:
		return
	var src_btn := (_targets[_menu_key] as Dictionary)["button"] as Button
	if not is_instance_valid(src_btn):
		return
	var src_y: float = src_btn.global_position.y - _ui_root.global_position.y
	var panel_h: float = panel.get_combined_minimum_size().y
	var y: float = clampf(src_y - MENU_PAD.y, 20.0,
			maxf(20.0, ScreenMetrics.bottom_y() - panel_h - 20.0))
	panel.position = Vector2(STAT_X - MENU_GAP_X - MENU_W, y)
	panel.size = Vector2(MENU_W, panel_h)


## 정보 패널 아래의 설명 글(씬 `%Note`). `{attack}` · `{engage}` 자리에 키워드 아이콘
## (`MENU_NOTE_ICON`)을 끼우고, 아이콘과 다음 낱말은 떨어지지 않게 붙인다.
## 글은 `UiHelpers.keep_words` 를 지나 낱말 중간에서 줄이 바뀌지 않는다.
func _fill_note(rtl: RichTextLabel, text: String) -> void:
	rtl.clear()
	var icon_px: int = roundi(float(MENU_NOTE_FONT) * 1.3)
	var parts: PackedStringArray = text.split("{")
	for i in parts.size():
		var part: String = parts[i]
		if i > 0:
			var close_at: int = part.find("}")
			var tag: String = part.substr(0, close_at) if close_at >= 0 else ""
			if MENU_NOTE_ICON.has(tag):
				rtl.add_image(KeywordIcon.texture(String(MENU_NOTE_ICON[tag]), icon_px * 2,
						BattleTheme.SKILL_KW_ICON, MENU_BG), icon_px, icon_px,
						Color.WHITE, INLINE_ALIGNMENT_CENTER)
				part = part.substr(close_at + 1)
				# 아이콘 뒤 빈칸은 줄바꿈하지 않는 빈칸 — 아이콘만 줄 끝에 남지 않게.
				if part.begins_with(" "):
					part = " " + part.substr(1)
			else:
				part = "{" + part
		if part != "":
			rtl.add_text(UiHelpers.keep_words(part))

## 카드를 누르면 **손패에서 가리켰을 때와 같은 설명판**이 선다 — 같은
## `CardDescBox.build`(폭 `CardPhaseManager.DESC_BOX_W`, 키워드 풀이는 옆 판들로
## 따로) + 같은 자리 규칙(`CardPhaseManager._desc_box_spots`: 확대된 카드 바로 옆,
## 카드가 화면 가운데이거나 오른쪽이면 판은 왼쪽, 키워드판은 그 바깥쪽) + 같은 등장
## 연출. 예전의 비용 · 종류 · 분류 · 포지션 행은 삭제됐다 — 손패와 다른 판이면
## "이 카드가 그 카드"라는 연결이 끊긴다. **계산식은 값이 아니라 식 문구로 적는다**
## (`live = false`) — 이 카드는 손에 든 카드가 아니라 쓸 때의 값이 없다.
##
## 판들은 전부 IGNORE 라 위를 눌러도 뒤판(`_on_menu_backdrop_input`)이 받는다.
func _build_card_desc(animate: bool) -> void:
	var cd: CardData = _card_of(_menu_key)
	var i: int = _fan_keys.find(_menu_key)
	if cd == null or i < 0:
		return
	var box: Panel = CardDescBox.build(cd, CardPhaseManager.DESC_BOX_W, false, "", null,
			false, 0.0, false)
	var kw_boxes: Array[Panel] = CardDescBox.build_keyword_panels(cd,
			CardPhaseManager.KEYWORD_BOX_W, false, false)
	var kw_h: float = 0.0
	for k in kw_boxes.size():
		kw_h += kw_boxes[k].size.y + (CardPhaseManager.KEYWORD_BOX_STACK_GAP if k > 0 else 0.0)

	# 확대된 카드의 화면 rect — 쉬는 자리 중심 + 손패 배율 × 호버 배율(초점 카드는
	# 비켜서지 않는다). 기울기는 무시한다(손패와 같다).
	var screen := Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	var center := Vector2(_fan_cx + _fan_dx[i],
			_bs.BS_HAND_CENTER.y + Card.CARD_H * 0.5 + _fan_arc_drop(_fan_dx[i]))
	var half: Vector2 = (Vector2(Card.CARD_W, Card.CARD_H) * 0.5
			* CardPhaseManager.HAND_CARD_SCALE * Card.HOVER_SCALE)
	var card_rect := Rect2(center - half, half * 2.0)
	var on_left: bool = center.x >= screen.x * 0.5
	var gap: float = CardPhaseManager.DESC_BOX_GAP
	var margin: float = CardPhaseManager.DESC_BOX_MARGIN
	var bw: float = CardPhaseManager.DESC_BOX_W
	var kw_w: float = CardPhaseManager.KEYWORD_BOX_W
	var box_x: float = (card_rect.position.x - gap - bw if on_left else card_rect.end.x + gap)
	box_x = clampf(box_x, margin, screen.x - bw - margin)
	var kx: float = (box_x - gap - kw_w if on_left else box_x + bw + gap)
	if kx < margin or kx + kw_w > screen.x - margin:
		kx = (card_rect.end.x + gap if on_left else card_rect.position.x - gap - kw_w)
	kx = clampf(kx, margin, screen.x - kw_w - margin)

	box.position = Vector2(box_x, _desc_y(card_rect.position.y, box.size.y, screen.y))
	_menu_root.add_child(box)
	if animate:
		_animate_desc_in(box)
	var kw_pos := Vector2(kx, _desc_y(card_rect.position.y, kw_h, screen.y))
	for kw_box in kw_boxes:
		kw_box.position = kw_pos
		_menu_root.add_child(kw_box)
		if animate:
			_animate_desc_in(kw_box)
		kw_pos.y += kw_box.size.y + CardPhaseManager.KEYWORD_BOX_STACK_GAP


## 판의 윗변 — 확대된 카드 윗단에 맞추되, 화면 아래로 넘치면 올린다
## (`CardPhaseManager._desc_box_y` 와 같은 식).
static func _desc_y(card_top: float, h: float, screen_h: float) -> float:
	var margin: float = CardPhaseManager.DESC_BOX_MARGIN
	return clampf(card_top, margin, maxf(margin, screen_h - h - margin))


## 등장 — 제자리보다 `DESC_ANIM_RISE` 아래 · 투명에서 올라오며 나타난다
## (`CardPhaseManager._animate_desc_in` 과 같은 연출).
static func _animate_desc_in(box: Control) -> void:
	var rest_y: float = box.position.y
	box.position.y = rest_y + CardPhaseManager.DESC_ANIM_RISE
	box.modulate.a = 0.0
	var tw := box.create_tween().set_parallel()
	tw.tween_property(box, "position:y", rest_y, CardPhaseManager.DESC_ANIM_IN_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(box, "modulate:a", 1.0, CardPhaseManager.DESC_ANIM_IN_TIME)


## 정보 패널의 제목. 접두사가 종류를 가른다 — 스탯은 칩 이름, 효과는 온전한
## 효과 이름(썸네일에는 두 글자 약칭밖에 없다), 카드는 카드 이름.
func _target_title(key: String) -> String:
	if key.begins_with("fx:"):
		for raw in _effect_defs():
			var d: Dictionary = raw as Dictionary
			if String(d["key"]) == key:
				return String(d["title"])
		return key
	for d2 in _flat_chip_defs():
		if String(d2[0]) == key:
			return String(d2[1])
	return key


## `card:` 키가 가리키는 카드. 표에 함께 넣어 두므로 인덱스를 되짚지 않는다.
func _card_of(key: String) -> CardData:
	if not _targets.has(key):
		return null
	return (_targets[key] as Dictionary).get("card") as CardData


## 정보 패널 한 판의 내역 — **기본값과 증가분을 따로** 적는다. 칩이 최종 값만
## 들고 있는 대신, 그 값이 어디서 왔는지는 전부 여기에 있다.
func _menu_rows(key: String) -> Array:
	if key.begins_with("fx:"):
		return _fx_rows(key)
	var pd: PlayerData = _bs.player_data_for(_pilot)
	var mech: MechData = _mech()
	match key:
		"hp":
			var rows: Array = [
				["기본 최대 체력", str(_pilot.base_max_hp)],
				["성장", "+%d%%  (+%d)" % [roundi(_pilot.growth_hp * 100.0),
						_pilot.max_hp - _pilot.base_max_hp]],
				["최대 체력", str(_pilot.max_hp)],
				["현재 체력", str(_pilot.hp)]]
			if _pilot.shield > 0:
				rows.append(["보호막", "+%d" % _pilot.shield])
			return rows
		"atk":
			var rows_atk: Array = [
				["기본 공격력", str(_pilot.base_atk)],
				["성장", "+%d%%  (+%d)" % [roundi(_pilot.growth * 100.0),
						roundi(float(_pilot.base_atk) * _pilot.growth)]]]
			if _pilot.atk_buff != 0:
				rows_atk.append(["일시 효과", "%+d" % _pilot.atk_buff])
			rows_atk.append(["최종", str(_pilot.atk)])
			return rows_atk
		"hit", "eva":
			var base: int = _pilot.hit if key == "hit" else _pilot.evasion
			var rows_h: Array = [["기본", str(base)]]
			if not is_zero_approx(_pilot.lane_stat_mod):
				rows_h.append(["라인전 스탯", "%+d%%%s" % [
					roundi(_pilot.lane_stat_mod * 100.0),
					_remain_txt(_pilot.lane_stat_expire_turn, false)]])
			rows_h.append(["최종", str(_bs.sim_core.lane_adjusted(base, _pilot))])
			return rows_h
		"presence":
			var rows_p: Array = [["기본", str(_pilot.presence)]]
			if _presence_delta() > 0:
				rows_p.append(["특수 능력", "%+d" % _presence_delta()])
			return rows_p
		_:
			pass
	if key in PlayerData.STAT_KEYS:
		if pd == null:
			return [["기본", "—"]]
		# 선수 스탯은 **경기 중에 변하지 않는다** — 주간 훈련으로만 오른다.
		# 그래서 기본값과 최종값이 언제나 같고 증가분 줄이 따로 없다.
		return [["기본", str(int(pd.get(key)))], ["인게임 증가", "없음"]]
	match key:
		"e_hit":
			return [["기본", str(_pilot.engage_hit)],
					["대등한 상대에게", "%d%%" % roundi(
							PilotData.hit_chance(_pilot.engage_hit, _pilot.engage_hit) * 100.0)]]
		"e_eva":
			return [["기본", str(_pilot.engage_eva)],
					["대등한 상대에게", "%d%%" % roundi(
							PilotData.hit_chance(_pilot.engage_eva, _pilot.engage_eva) * 100.0)]]
		"m_hp":
			return [["기체 체력", str(mech.hp) if mech != null else "—"],
					["파일럿 기본 최대 체력", str(_pilot.base_max_hp)],
					["현재", "%d / %d" % [_pilot.hp, _pilot.max_hp]]]
		"m_atk":
			return [["기체 공격력", str(mech.atk) if mech != null else "—"],
					["파일럿 기본 공격력", str(_pilot.base_atk)],
					["현재", str(_pilot.atk)]]
		"m_presence":
			return [["기체 존재감", str(mech.presence) if mech != null else "—"],
					["현재", str(_pilot.presence)]]
	return []


## 지속 효과 하나의 내역. 값 자체는 썸네일에 이미 찍혀 있으므로 여기서는
## **어디에 곱해지는가**와 **언제까지인가**를 말한다 — 그 둘이 안 보이면 효과가
## 켜져 있다는 사실만 알 뿐 그래서 뭘 해야 하는지가 안 나온다.
func _fx_rows(key: String) -> Array:
	if key.begins_with("fx:src:") or key.begins_with("fx:rest:"):
		return _fx_card_rows(key)
	match key:
		"fx:lane":
			return [
				["명중 / 회피", "%+d%%" % roundi(_pilot.lane_stat_mod * 100.0)],
				["남은 시간", _remain_label(_pilot.lane_stat_expire_turn, false)],
				["최종 명중", str(_bs.sim_core.lane_adjusted(_pilot.hit, _pilot))],
				["최종 회피", str(_bs.sim_core.lane_adjusted(_pilot.evasion, _pilot))]]
		"fx:rate":
			return [
				["적립 배율", "%+d%%" % roundi((_pilot.growth_rate_mult - 1.0) * 100.0)],
				["남은 시간", _remain_label(_pilot.growth_rate_expire_turn,
						_pilot.growth_until_phase)],
				["영구 가산", "%+d%%" % roundi(_pilot.growth_rate_bonus * 100.0)],
				["성장치", BattleSim.fmt_score(_pilot.score)]]
		"fx:eva":
			return [
				["전장 회피", "%+d%%" % roundi(_pilot.eva_card_mod * 100.0)],
				["남은 시간", _remain_label(_pilot.eva_card_expire_turn, false)]]
		"fx:ambush":
			return [
				["상태", "다음 작전 단계까지 이동 없음"],
				["위치", "(%d, %d)" % [_pilot.grid_pos.x, _pilot.grid_pos.y]]]
		"fx:atk":
			return [
				["일시 가산", "%+d" % _pilot.atk_buff],
				["기본 공격력", str(_pilot.base_atk)],
				["최종 공격력", str(_pilot.atk)]]
		"fx:shield":
			return [
				["보호막", str(_pilot.shield)],
				["현재 체력", "%d / %d" % [_pilot.hp, _pilot.max_hp]]]
	return []


## 카드별 지속 효과 / 잔여분 한 칸의 내역. **그 한 장이 얹은 몫**과 **그 종류의
## 합계**를 나란히 적는다 — 칸이 여럿으로 갈린 지금은 "이건 얼마고 다 합치면
## 얼마인가"가 한 화면에 없으면 도리어 더하게 된다.
func _fx_card_rows(key: String) -> Array:
	var d: Dictionary = _fx_entry(key)
	if d.is_empty():
		return []
	# `fx:src:<kind>|<카드 이름>` / `fx:rest:<kind>` — 둘 다 세 번째 조각이
	# 종류이고, 카드 쪽에만 `|` 뒤에 이름이 붙어 있다.
	var kind: String = key.get_slice(":", 2).get_slice("|", 0)
	var rows: Array = [
		["이 효과", String(d["value"])],
		["남은 시간", "영구"]]
	match kind:
		PilotData.FX_GROWTH_RATE:
			rows.append(["영구 가산 합계",
					"%+d%%" % roundi(_pilot.growth_rate_bonus * 100.0)])
			rows.append(["성장치", BattleSim.fmt_score(_pilot.score)])
		PilotData.FX_MAX_HP:
			rows.append(["영구 가산 합계", "%+d" % _pilot.bonus_max_hp])
			rows.append(["최대 체력", str(_pilot.max_hp)])
		PilotData.FX_ATK:
			rows.append(["영구 가산 합계", "%+d" % _pilot.bonus_atk_flat])
			rows.append(["최종 공격력", str(_pilot.atk)])
		PilotData.FX_ATK_PCT:
			rows.append(["영구 배율 합계", "%+d%%" % roundi(_pilot.bonus_atk_mult * 100.0)])
			rows.append(["최종 공격력", str(_pilot.atk)])
		PilotData.FX_HP_PCT:
			rows.append(["영구 배율 합계", "%+d%%" % roundi(_pilot.bonus_max_hp_mult * 100.0)])
			rows.append(["최대 체력", str(_pilot.max_hp)])
	return rows


## 남은 수명을 **한 칸짜리 값**으로. `_remain_txt` 는 값 뒤에 괄호로 붙는
## 꼬리표(빈 문자열이 정상)라 행의 값 칸에 그대로 쓰면 빈칸이 남는다.
func _remain_label(expire_turn: int, until_phase: bool) -> String:
	if until_phase:
		return "작전 단계까지"
	if expire_turn < 0:
		return "영구"
	return "%d턴" % maxi(0, expire_turn - _bs.turn_count)


## 명중 · 회피 · 존재감 설명 — 인게임 칩과 파일럿 탭 칩이 같은 글을 쓴다.
## `{attack}` · `{engage}` 자리에는 키워드 아이콘이 선다(`_fill_note`).
const STAT_NOTES: Dictionary = {
	"hit": "카드 효과로 적에게 {attack} 공격할 시, 명중할 확률을 결정합니다.",
	"field_hit": "카드 효과로 적에게 {attack} 공격할 시, 명중할 확률을 결정합니다.",
	"eva": "적의 카드 효과로 {attack} 공격을 받을 때, 빗맞힐 확률을 결정합니다.",
	"field_eva": "적의 카드 효과로 {attack} 공격을 받을 때, 빗맞힐 확률을 결정합니다.",
	"e_hit": "{engage} 교전 중, 적을 공격할 때 명중할 확률을 결정합니다.",
	"engage_hit": "{engage} 교전 중, 적을 공격할 때 명중할 확률을 결정합니다.",
	"e_eva": "{engage} 교전 중, 적의 공격을 받을 때 빗맞힐 확률을 결정합니다.",
	"engage_eva": "{engage} 교전 중, 적의 공격을 받을 때 빗맞힐 확률을 결정합니다.",
	"presence": "존재감이 높을 시, 교전 중 공격 대상이 될 확률이 높아집니다.",
	"m_presence": "존재감이 높을 시, 교전 중 공격 대상이 될 확률이 높아집니다.",
}


## 정보 패널 하나에 붙는 설명. 숫자만으로는 "그래서 뭘 가르는 값인가"가 안 나오는
## 것에만 붙인다. 카드는 이 판을 쓰지 않는다 — 손패의 설명판(`_build_card_desc`).
func _menu_note(key: String) -> String:
	if STAT_NOTES.has(key):
		return String(STAT_NOTES[key])
	if key in PlayerData.STAT_KEYS:
		return PlayerData.STAT_NOTES[PlayerData.STAT_KEYS.find(key)]
	if key.begins_with("fx:src:"):
		return "이 카드가 남긴 영구 가산분. 만료도 해제도 없고 같은 카드를 다시 쓰면 누적된다."
	if key.begins_with("fx:rest:"):
		return "카드가 아니라 메크 패시브가 직접 쌓은 몫. 출처를 카드 이름으로 부를 수 없어 한 칸으로 묶었다."
	match key:
		"fx:lane":
			return "전장 명중 판정에만 곱해진다. 교전 무대는 자기 확률 구간을 쓴다."
		"fx:rate":
			return "성장이 아니라 성장치 적립에 곱해진다. 안전한 파밍과 완벽한 마무리가 같은 칸을 쓴다."
		"fx:atk":
			return "카드가 얹은 임시 가산분. 성장 재계산에 지워지지 않는다."
		"fx:shield":
			return "피해를 체력보다 먼저 먹는다. 본진 복귀 시 사라진다."
		"m_hp", "m_atk":
			return "기체 스탯이 파일럿의 기본값이 되고, 거기서 성장이 붙는다."
	return ""


## 일시 효과의 남은 수명을 괄호 한 덩이로. 턴 만료형(안전한 파밍 / 공격적인
## 라인전)은 남은 턴 수, 단계 만료형(완벽한 마무리)은 "작전 단계까지". 둘 다
## 아니면 빈 문자열이라 값 뒤에 아무것도 붙지 않는다.
func _remain_txt(expire_turn: int, until_phase: bool) -> String:
	if until_phase:
		return "  (작전 단계까지)"
	if expire_turn < 0:
		return ""
	return "  (%d턴)" % maxi(0, expire_turn - _bs.turn_count)


func _mech() -> MechData:
	var pd: PlayerData = _bs.player_data_for(_pilot)
	return pd.assigned_mech if pd != null else null


## F6 단독 실행 미리보기 — 패널은 전투(`_bs`)의 값을 읽으므로 `BattleSim.tscn` 을 단독
## 실행으로 옆에 띄우고(로스터 · 스킬 없는 단독 전투) 첫 아군 파일럿으로 연다
## (`resources/UiPreview.gd`). 스킬 판이 보이게 그 파일럿에게만 첫 스킬을 손으로 쥐여 준다.
## 저장은 없다. 탭 · 칸 · 카드는 그대로 눌린다.
func _fill_preview() -> void:
	var bs := (load("res://scenes/BattleSim.tscn") as PackedScene).instantiate() as BattleSim
	get_parent().add_child.call_deferred(bs)
	await bs.ready
	for _i in 10:
		await get_tree().process_frame
	if bs.pilots.is_empty():
		push_warning("PilotDetailPanel 미리보기: 전투 파일럿이 없다")
		return
	bind(bs)
	var p := bs.pilots[0] as PilotData
	var gm: Node = bs.gm
	if gm != null and bs.skill != null and not bs.skill.has_skill(p):
		var ids: Array = gm.pilot_skills.keys()
		if not ids.is_empty():
			bs.skill.states[p] = {"def": gm.skill_def(int(ids[0])), "charge": 0,
					"ready_turn": bs.turn_count + 3, "killed_roles": {}, "farm_until": -1,
					"hold_until": -1}
	open(p)
