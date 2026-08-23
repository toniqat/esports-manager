class_name PilotDetailPanel
extends Node

# 파일럿 상세 패널 — 스트립의 얼굴(아군 하단 / **적 상단** 양쪽)을 누르면 열린다.
#
#   좌: 전신 아트 **두 장** — 앞에 선 쪽이 밝고, 뒤에 선 쪽은 오른쪽으로 밀린 채
#       검게 딤드된다. 앞뒤는 **탭**이 정한다(인게임·파일럿 → 사람 / 메크 → 기체).
#   우: **머리글**(파일럿 이름 + 메크 이름 + 성장치) → 탭 셋 → 상세 패널
#   하: 닫기
#
# **머리글은 탭과 분리돼 있다.** 이름 · 기체명 · 성장치는 어느 탭을 보든 같은
# 파일럿의 것이므로 탭이 바뀔 때마다 다시 세울 이유가 없고, 예전처럼 본문
# 안에 들어 있으면 메크 탭에서 제목이 기체명으로 바뀌며 **파일럿 이름과
# 성장치가 화면에서 통째로 사라졌다** — 지금 누가 열려 있는지가 탭에 따라
# 흔들린 것이다. 지금은 머리글이 자기 판 위에 상시로 서 있고, 탭이 바꾸는
# 것은 그 아래 상세 패널 하나뿐이다. 기체명은 이름 **옆에 작게** 붙어 늘
# 보인다 — 메크 탭까지 들어가야 알 수 있는 값이 아니다.
#
# **스탯은 줄이 아니라 칩이다.** 예전에는 `키 ─ 값` 두 칸짜리 행이 세로로 열몇
# 줄 이어졌는데, 그러면 (1) 어느 값이 중요한지가 순서 말고는 없고 (2) 값 뒤에
# `(기본 160)` `(7턴)` 같은 괄호가 줄줄이 붙어 정작 **지금 얼마인가**를 읽는 데
# 시간이 걸렸다. 지금은 칩 한 칸이 **최종 값 하나**만 크게 들고 있고, 어디서
# 나온 값인지는 칩을 눌러야 나온다(`_open_menu`) — 평소에는 읽고, 궁금할 때만
# 파고든다.
#
# 여는 조건은 **자기 작전 단계**뿐이다 — `HudBuilder._update_pilot_strips` 가
# 스트립 버튼을 그때만 활성화하고, `close_if_phase_left()` 가 단계를 벗어나면
# 강제로 닫는다. BATTLE 이 흐르는 동안 열려 있으면 화면이 딤드된 채 전장이
# 굴러가 버린다.
#
# 열려 있는 동안 **누른 쪽 스트립은 숨긴다**. 딤 위로 스트립만 남으면 "지금 뭘
# 보고 있는지"가 흐려지고, 딤 아래로 넣으면 방금 누른 얼굴이 어두워져 연결이
# 끊긴다 — 아예 치우는 편이 읽힌다.

## 버리기(10) / 대상 지정(11) / 열람·교전(12) 위. 이 패널은 모달이라
## 열려 있는 동안 카드도 못 내고 턴도 못 넘기므로 다른 오버레이와 겹칠 일이
## 없지만, 겹친다면 이쪽이 위여야 한다.
const OVERLAY_LAYER: int = 13

const VP_W: float = 1080.0
const VP_H: float = 1920.0
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.88)

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
const ART_BACK_TINT := Color(0.14, 0.14, 0.18, 0.88)
## 앞뒤가 자리를 맞바꾸는 데 걸리는 시간(s).
const ART_SWAP_SEC: float = 0.22
## 아트가 없는 메크(= 아직 에셋이 하나도 없다)의 플레이스홀더 가로/세로 비.
const ART_PLACEHOLDER_ASPECT: float = 0.70

# ─── 우: 정보 칼럼 ───────────────────────────────────────────────────────────
# **정보 블록은 아래쪽에 있다.** 아트가 커지면서 화면 위쪽 절반이 인물의
# 머리·상체 자리가 됐고, 스탯이 예전 자리(y 170)에 남으면 얼굴을 덮는다.
# ─── 머리글 (탭 위, 상세 패널과 분리) ───────────────────────────────────────
# 파일럿 이름 + 기체명 + 성장치 한 줄. **탭 바로 위**에 자기 받침을 깔고 앉아
# 있고, 탭이 바뀌어도 다시 세워지지 않는다(`_build_header_block` 은 `_build`
# 에서 한 번만 돈다).
const HDR_TOP: float = 452.0
## 머리글 받침의 아래끝 = 탭 바의 윗변. 둘이 맞닿아 "이 탭들은 이 파일럿의
## 것"으로 읽힌다.
const HDR_BOTTOM: float = 562.0
const HDR_NAME_FONT: int = 40
## 기체명 — 이름 **옆에** 작게. 아래 줄에 두면 이름이 두 줄짜리 덩어리가 되어
## 오른쪽 성장치와 세로 중심이 어긋난다.
const HDR_MECH_FONT: int = 22
const HDR_MECH_COLOR := Color(0.68, 0.74, 0.86)
const HDR_GROWTH_FONT: int = 40
## 성장치 칸의 폭. 이름 줄은 그만큼 좁아진다.
const HDR_GROWTH_W: float = 170.0

const STAT_X: float = 600.0
const STAT_W: float = 452.0
const STAT_TOP: float = 650.0
## 스탯 블록 뒤에 까는 받침. 아트가 이 자리까지 올라오므로 글자만 얹으면
## 일러스트 위에서 읽히지 않는다. 내용 높이에 맞춰 자란다.
const STAT_PANEL_PAD := Vector2(22.0, 26.0)
const STAT_PANEL_BG := Color(0.04, 0.05, 0.09, 0.86)
const STAT_PANEL_BORDER := Color(0.30, 0.34, 0.46, 0.70)

const HEADER_COLOR := Color(1.0, 0.92, 0.55)
const SECTION_COLOR := Color(0.58, 0.78, 1.0)
const KEY_COLOR := Color(0.72, 0.74, 0.80)
const VALUE_COLOR := Color(0.96, 0.96, 0.98)
## 이름 오른쪽의 성장치. 스트립의 성장치 숫자와 같은 값이므로 같은 계열로 둔다.
const GROWTH_COLOR := Color(0.72, 1.0, 0.80)

# ─── 탭 바 ───────────────────────────────────────────────────────────────────
# 받침 **바로 위에 붙는다**(아래끝 = 받침 위끝) — 떼어 놓으면 탭이 어느 판에
# 달린 것인지가 안 보인다. 켜진 탭은 아래 테두리를 그리지 않아 받침과 한 몸이
# 된다.
const TAB_H: float = 62.0
const TAB_GAP: float = 8.0
const TAB_BG_ON  := Color(0.16, 0.21, 0.34, 0.96)
const TAB_BG_OFF := Color(0.06, 0.07, 0.11, 0.80)
const TAB_BORDER_ON := Color(0.62, 0.80, 1.0, 0.95)
const TAB_BORDER_OFF := Color(0.26, 0.29, 0.38, 0.65)

# ─── 스탯 칩 ─────────────────────────────────────────────────────────────────
# 끝이 둥근 사각형 한 칸 = 스탯 하나. 위에 작게 이름, 아래에 크게 **최종 값**.
# 3열이라 인게임 6칸이 정확히 2행, 파일럿 5칸이 2행(마지막 줄 2칸), 메크 3칸이
# 1행으로 떨어진다.
const CHIP_COLS: int = 3
const CHIP_GAP: float = 14.0
const CHIP_H: float = 92.0
const CHIP_RADIUS: int = 18
const CHIP_BG := Color(0.10, 0.12, 0.18, 0.94)
const CHIP_BG_HL := Color(0.17, 0.22, 0.34, 0.98)
const CHIP_BORDER := Color(0.32, 0.36, 0.48, 0.80)
const CHIP_BORDER_HL := Color(0.72, 0.86, 1.0, 0.95)
const CHIP_NAME_FONT: int = 20
const CHIP_NAME_H: float = 28.0

# ─── 칩 컨텍스트 메뉴 ────────────────────────────────────────────────────────
# **정보 칼럼 왼쪽에** 펼친다 — 오른쪽은 화면 끝(1080)까지 28px 밖에 없고,
# 칩 위에 겹쳐 띄우면 방금 누른 칩이 자기 설명에 가려진다. 왼쪽은 아트가 선
# 자리이지만 메뉴는 불투명 판이라 읽는 데 문제가 없다.
const MENU_W: float = 372.0
const MENU_ROW_H: float = 36.0
const MENU_PAD := Vector2(20.0, 16.0)
const MENU_GAP_X: float = 16.0
const MENU_BG := Color(0.07, 0.09, 0.14, 0.97)
const MENU_BORDER := Color(0.62, 0.80, 1.0, 0.85)
## 판 아래의 설명 글. 카드 설명이 여기로 들어오므로 판 높이는 이 글의 실제
## 줄 수에서 유도한다(`_text_height`).
const MENU_NOTE_FONT: int = 20
## 이름 칸이 차지하는 비율. 나머지가 값 칸이다. 0.52 이던 시절 "다음 작전
## 단계까지" 같은 값이 159px 안에 안 들어가 **왼쪽부터 잘려 나갔다** — 오른쪽
## 정렬 Label 은 넘치면 정렬을 포기하고 rect 왼쪽부터 그리므로, 잘리는 쪽이
## 글의 머리다(clip_text 가 없으면 대신 화면 밖으로 넘친다).
const MENU_KEY_FRAC: float = 0.42

# ─── 지속 효과 썸네일 ───────────────────────────────────────────────────────
# 스탯 칩 아래 한 줄. **지금 이 파일럿에게 걸려 있는 것만** 뜬다 — 걸려 있지도
# 않은 효과의 빈 칸이 늘어서 있으면 "무엇이 켜져 있는가"가 도리어 안 읽힌다.
#
# 칩이 답하지 못하는 질문이 있어서 생겼다. 명중 칩이 55 라고 할 때 그 값이
# 라인전 카드 때문인지 원래 그런지는 칩을 눌러야 나오고, 적립 배율처럼 **어느
# 칩에도 안 실리는** 효과는 아예 볼 자리가 없었다. 썸네일 한 줄은 "지금 몇 개가
# 켜져 있는가"를 세지 않고도 보게 하고, 하나를 누르면 스탯 칩과 **같은 패널**에
# 그 설명이 뜬다(둘은 같은 자리를 쓰므로 자연히 배타적이다).
const FX_SIZE: float = 68.0
const FX_GAP: float = 12.0
const FX_SECTION_H: float = 34.0
const FX_RADIUS: int = 16
const FX_BG := Color(0.10, 0.12, 0.18, 0.94)
const FX_BG_HL := Color(0.17, 0.22, 0.34, 0.98)
const FX_SHORT_FONT: int = 21
const FX_VALUE_FONT: int = 16
const FX_EMPTY_COLOR := Color(0.58, 0.61, 0.70)

# ─── 카드 ────────────────────────────────────────────────────────────────────
# 손패와 **같은 카드 노드**(`Card.tscn`)를 축소해 세운다. 다른 그림으로 그리면
# "이 카드가 그 카드"라는 연결이 끊긴다.
## **인게임 탭은 6장을 3열 2행으로 다 보여 준다** — 이 파일럿이 무엇을 들고
## 시작했는지는 한 화면에 있어야 하는 정보이고, 예전처럼 파일럿 탭과 메크 탭에
## 3장씩 갈라 두면 여섯 장을 견주려면 탭을 오가야 했다. 두 탭의 3장 줄은 그대로
## 남는다 — 거기서는 그 탭 스탯 옆에 붙은 "이 몸이 주는 카드" 라는 맥락이 있다.
const CARD_VIEW_SCALE: float = 0.80
const CARD_GAP: float = 16.0
const CARD_ROW_GAP: float = 16.0
const CARD_SECTION_H: float = 34.0
const CARD_GRID_COLS: int = 3

# ─── 하: 닫기 ────────────────────────────────────────────────────────────────
# **받침 아래끝에 붙어 다닌다.** 탭마다 내용 높이가 달라(인게임 ~360 / 파일럿
# ~600) 한 자리에 못 박아 두면 짧은 탭에서 버튼만 화면 한가운데에 떠 있다 —
# 어느 판에 달린 버튼인지가 안 보인다. 자리가 바뀌는 것은 **탭을 누른 순간**
# 뿐이고, 값만 바뀌는 `refresh()` 는 받침을 건드리지 않으므로 버튼이 숫자를
# 따라 위아래로 떨지 않는다.
# ─── 파일럿 스킬 블록 (인게임 탭 · 카드 줄 아래) ────────────────────────────
# 스킬은 카드와 다른 종류의 자원이라 카드 격자에 섞지 않고 **자기 블록**을 갖는다
# — 이름 · 타입 · 설명문 · 상태 한 줄 · 그리고 큰 사용 버튼. 지속 효과 썸네일에
# 한 칸으로 끼워 넣는 길도 있었지만, 그러면 "지금 쓸 수 있는가"를 알려면 썸네일을
# 한 번 더 눌러야 한다 — 스킬은 누르라고 있는 것이므로 버튼이 바로 보여야 한다.
const SKILL_SECTION_H: float = 34.0
const SKILL_NAME_FONT: int = 30
const SKILL_TYPE_FONT: int = 20
const SKILL_DESC_FONT: int = 22
const SKILL_STATUS_FONT: int = 22
const SKILL_KW_FONT: int = 19
const SKILL_KW_COLOR := Color(0.58, 0.63, 0.76)
const SKILL_LINE_GAP: float = 8.0
const SKILL_NAME_COLOR := Color(1.0, 0.88, 0.52)
const SKILL_TYPE_COLOR := Color(0.66, 0.78, 0.96)
const SKILL_DESC_COLOR := Color(0.88, 0.90, 0.95)
const SKILL_READY_COLOR := Color(0.70, 1.0, 0.78)
const SKILL_WAIT_COLOR  := Color(0.80, 0.82, 0.90)
const SKILL_USE_H: float = 68.0
## 타입 이름 — CSV 값 그대로는 화면에 안 쓴다.
const SKILL_TYPE_LABEL: Dictionary = {
	"cooldown": "쿨타임", "charge": "충전식", "passive": "패시브",
}

const BTN_W: float = 212.0
const BTN_H: float = 76.0
## 받침 아래끝과 버튼 윗변 사이 간격.
const BTN_GAP_Y: float = 24.0

var _bs: BattleSim = null
var _layer: CanvasLayer = null
var _root: Control = null
var _pilot: PilotData = null
var _tab: int = Tab.INGAME

# 아트 두 장. 어느 쪽이 앞이냐는 `_tab` 이 정하고, 노드 자체는 바뀌지 않는다.
var _art_pilot: Control = null
var _art_mech: Control = null
var _art_holder: Control = null
var _swap_tween: Tween = null

var _tab_buttons: Array = []          # Array[Button], Tab 순서

# 머리글(이름 · 기체명 · 성장치)은 **탭과 무관**하므로 `_build` 에서 한 번만
# 세우고 `refresh()` 가 숫자만 고친다.
var _growth_label: Label = null
## 파일럿 스킬 블록의 상태 줄과 사용 버튼. `refresh()` 가 이 둘만 다시 쓴다 —
## 트리를 다시 세우면 카드 노드가 매 갱신마다 인스턴스화된다. 패시브 스킬과
## 스킬 없는 파일럿에서는 버튼이 null 이다.
var _skill_status: Label = null
var _skill_use_btn: Button = null

# 본문(칩 · 효과 · 카드)은 탭이 바뀔 때 통째로 다시 세운다 — 구성이 아예 다르다.
# 값만 바뀌는 `refresh()` 는 이 트리를 건드리지 않고 라벨만 고친다.
var _body_root: Control = null
var _stat_panel: Panel = null

## **정보 패널을 열 수 있는 모든 것**이 여기 한 표에 모인다 — 스탯 칩,
## 지속 효과 썸네일, 카드. 셋이 같은 패널을 쓰므로(= 자연히 배타적) 강조
## 스타일도, 여는 경로도, 메뉴 뒤판의 클릭 라우팅도 한 벌이면 된다.
##
##   key → {"button": Button, "style": TargetStyle, "value": Label?}
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
var _menu_root: Control = null

var _close_btn: Button = null

## 열면서 숨긴 스트립의 팀. 닫을 때 그 스트립만 되돌린다.
var _hidden_team: int = -1


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = OVERLAY_LAYER
	_layer.name = "PilotDetailLayer"
	add_child(_layer)


# CardSelectOverlay / CardPileViewer 와 같은 패턴 — BattleSim._ready 가
# add_child 직후 호출한다.
func bind(bs: BattleSim) -> void:
	_bs = bs


func is_active() -> bool:
	return _root != null


func open(p: PilotData) -> void:
	if p == null:
		return
	if is_active():
		close()
	_pilot = p
	_tab = Tab.INGAME
	_build()
	if _bs.hud != null:
		_hidden_team = p.team
		_bs.hud.set_strip_visible(_hidden_team, false)


func close() -> void:
	_close_menu()
	if _root != null:
		_root.queue_free()
		_root = null
	_body_root = null
	_stat_panel = null
	_close_btn = null
	_targets.clear()
	_fx_keys.clear()
	_growth_label = null
	_tab_buttons.clear()
	_art_pilot = null
	_art_mech = null
	_art_holder = null
	_pilot = null
	if _bs != null and _bs.hud != null and _hidden_team >= 0:
		_bs.hud.set_strip_visible(_hidden_team, true)
	_hidden_team = -1


## 작전 단계를 벗어나면 닫는다. `HudBuilder.update_hud` 가 매 갱신마다 부른다 —
## 열어 둔 채로 BATTLE 이 흐르면 딤 뒤에서 전장이 굴러간다.
func close_if_phase_left() -> void:
	if is_active() and _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		close()


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
	# 걸려 있는 효과의 **구성**이 달라졌으면(만료 / 새 효과) 본문을 다시 세운다.
	# 값만 바뀐 경우에는 아래 라벨 갱신으로 끝난다 — 트리를 다시 세우면 카드
	# 노드가 매 갱신마다 인스턴스화되고 열어 둔 패널이 닫힌다.
	if _fx_signature() != _fx_keys:
		_rebuild_body()
		return
	_refresh_target_values()
	if _menu_key != "":
		_build_menu_content()


# ─── UI ──────────────────────────────────────────────────────────────────────
func _build() -> void:
	_root = Control.new()
	_root.name = "PilotDetail"
	# 앵커 프리셋은 쓰지 않는다 — CanvasLayer 아래의 Control 은 full-rect 앵커를
	# 해석해 줄 부모 rect 가 없어서 크기가 그대로 0 이고, 프리셋을 걸어 두면
	# "_ready 뒤에 size 가 덮어써진다"는 경고만 남는다. 크기는 명시한다.
	_root.position = Vector2.ZERO
	_root.size = Vector2(VP_W, VP_H)
	# 모달 — 뒤쪽(핸드 · 전장 · 도넛) 입력을 전부 삼킨다.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_root)

	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.position = Vector2.ZERO
	dim.size = Vector2(VP_W, VP_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	_build_arts()
	_build_header_block()
	_build_tabs()
	_rebuild_body()
	_build_buttons()


# ─── 전신 아트 ───────────────────────────────────────────────────────────────
# 두 장을 만들어 자기 홀더에 넣고, 앞뒤 자세는 `_apply_focus(false)` 가 잡는다.
func _build_arts() -> void:
	_art_holder = Control.new()
	_art_holder.name = "ArtHolder"
	_art_holder.position = Vector2.ZERO
	_art_holder.size = Vector2(VP_W, VP_H)
	_art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_art_holder)

	var mech: MechData = _mech()
	_art_pilot = _make_art(PilotImages.full_for(_pilot.pilot_id), "초상화 없음")
	_art_mech  = _make_art(MechImages.full_for(mech.id) if mech != null else null,
			mech.name if mech != null else "메크 미배정")
	_art_holder.add_child(_art_mech)
	_art_holder.add_child(_art_pilot)
	_apply_focus(false)


## 아트 한 장. `tex` 가 null 이면(메크 에셋이 아직 없다 / INTL 파일럿) 같은
## 자리에 실루엣 플레이스홀더를 세운다 — 자리와 전환 동작은 그대로 확인된다.
##
## 노드 크기는 **언제나 앞에 선 크기**(`ART_H`)로 고정하고, 뒤로 물러날 때는
## `scale` 로만 줄인다. `pivot_offset` 이 아래 가운데라 줄여도 바닥선이 그대로다.
func _make_art(tex: Texture2D, fallback_text: String) -> Control:
	var aspect: float = ART_PLACEHOLDER_ASPECT
	if tex != null:
		var ts: Vector2 = tex.get_size()
		if ts.y > 0.0:
			aspect = ts.x / ts.y
	var w: float = ART_H * aspect

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(w, ART_H)
	holder.pivot_offset = Vector2(w * 0.5, ART_H)

	if tex != null:
		var rect := TextureRect.new()
		rect.position = Vector2.ZERO
		rect.size = Vector2(w, ART_H)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# 크기를 원본 비율로 이미 맞췄으므로 STRETCH_SCALE 이 정확히 채운다.
		# KEEP_ASPECT 계열은 여기서 레터박스를 한 번 더 계산할 뿐이다.
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.texture = tex
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
	else:
		var slab := Panel.new()
		slab.position = Vector2.ZERO
		slab.size = Vector2(w, ART_H)
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		# 옅게 — 이 판은 "아직 그림이 없다"는 자리 표시이지 그림이 아니다.
		# 알파를 올리면 화면 절반을 차지하는 밝은 사각형이 되어 정작 앞에 선
		# 파일럿보다 눈에 띈다.
		sb.bg_color = Color(0.14, 0.15, 0.20, 0.30)
		sb.border_color = Color(0.42, 0.45, 0.56, 0.45)
		sb.border_width_top = 3
		sb.border_width_bottom = 3
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.corner_radius_top_left = 24
		sb.corner_radius_top_right = 24
		slab.add_theme_stylebox_override("panel", sb)
		holder.add_child(slab)

		var lbl := _make_label(fallback_text, 34, Color(0.78, 0.80, 0.88),
				HORIZONTAL_ALIGNMENT_CENTER)
		lbl.position = Vector2(0.0, ART_H * 0.42)
		lbl.size = Vector2(w, 60.0)
		holder.add_child(lbl)
	return holder


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
func _build_tabs() -> void:
	_tab_buttons.clear()
	var titles: Array = ["인게임", "파일럿", "메크"]
	var w: float = (STAT_W - float(titles.size() - 1) * TAB_GAP) / float(titles.size())
	var top: float = STAT_TOP - STAT_PANEL_PAD.y - TAB_H
	for i in titles.size():
		var btn := Button.new()
		btn.text = String(titles[i])
		btn.add_theme_font_size_override("font_size", 26)
		btn.position = Vector2(STAT_X + float(i) * (w + TAB_GAP), top)
		btn.size = Vector2(w, TAB_H)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_tab_pressed.bind(i))
		_root.add_child(btn)
		_tab_buttons.append(btn)
	_refresh_tab_styles()


func _refresh_tab_styles() -> void:
	for i in _tab_buttons.size():
		var btn := _tab_buttons[i] as Button
		var on: bool = i == _tab
		var sb := StyleBoxFlat.new()
		sb.bg_color = TAB_BG_ON if on else TAB_BG_OFF
		sb.border_color = TAB_BORDER_ON if on else TAB_BORDER_OFF
		sb.border_width_top = 2
		sb.border_width_left = 2
		sb.border_width_right = 2
		# 켜진 탭은 **아래 테두리를 그리지 않는다** — 받침과 한 몸으로 이어져야
		# "이 판이 그 탭의 내용"으로 읽힌다.
		sb.border_width_bottom = 0 if on else 2
		sb.corner_radius_top_left = 14
		sb.corner_radius_top_right = 14
		for state in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, sb)
		btn.add_theme_color_override("font_color",
				Color.WHITE if on else KEY_COLOR)


func _on_tab_pressed(idx: int) -> void:
	if idx == _tab:
		return
	_tab = idx
	_close_menu()
	_refresh_tab_styles()
	_apply_focus(true)
	_rebuild_body()


# ─── 본문 (이름 · 칩 · 카드) ─────────────────────────────────────────────────
# 탭이 바뀔 때 통째로 다시 세운다. 받침 Panel 을 **먼저** 넣어 글자 뒤에 깔고,
# 높이는 다 세운 뒤에 내용에 맞춰 준다.
func _rebuild_body() -> void:
	if _body_root != null and is_instance_valid(_body_root):
		# 트리에서 **먼저** 뗀다 — `queue_free` 만 걸면 이번 프레임까지는 그대로
		# 그려져서 새 블록과 글자가 겹쳐 보인다.
		_root.remove_child(_body_root)
		_body_root.queue_free()
	_targets.clear()
	_fx_keys = _fx_signature()

	_body_root = Control.new()
	_body_root.name = "BodyColumn"
	_body_root.position = Vector2.ZERO
	_body_root.size = Vector2(VP_W, VP_H)
	# IGNORE 는 **이 노드만** 히트 테스트에서 뺀다 — 자식 칩 버튼은 그대로 눌린다.
	_body_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_body_root)
	# 탭 · 닫기 버튼보다 아래(= 뒤)에 둔다. 0 = dim, 1 = 아트 홀더.
	_root.move_child(_body_root, 2)

	_stat_panel = Panel.new()
	_stat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = STAT_PANEL_BG
	sb.border_color = STAT_PANEL_BORDER
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	# 위쪽 모서리는 각지게 — 켜진 탭이 그 위에 앉아 한 몸으로 이어진다.
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	_stat_panel.add_theme_stylebox_override("panel", sb)
	_body_root.add_child(_stat_panel)

	var bottom: float = _build_body_content()
	_stat_panel.position = Vector2(STAT_X, STAT_TOP) - STAT_PANEL_PAD
	_stat_panel.size = Vector2(STAT_W, bottom - STAT_TOP) + STAT_PANEL_PAD * 2.0
	_reposition_close()

	# 열려 있던 정보 패널의 대상 버튼은 방금 통째로 free 됐다 — `_menu_key` 가
	# 가리키던 강조도 그 버튼과 함께 사라졌으므로 새 버튼에 다시 입힌다. 효과가
	# 만료돼 그 키 자체가 없어졌으면 패널을 닫는다(빈 판이 남는 것보다 낫다).
	if _menu_key != "":
		if _targets.has(_menu_key):
			_style_target(_menu_key, true)
			_build_menu_content()
		else:
			_close_menu()


## 본문을 세우고 마지막 요소의 아래 y 를 돌려준다. **머리글은 여기 없다** —
## 이름 · 기체명 · 성장치는 탭과 무관하므로 `_build_header_block` 이 따로 세운다.
func _build_body_content() -> float:
	var y: float = _build_chip_grid(STAT_TOP, _chip_defs())

	if _tab != Tab.INGAME:
		var slot: String = "pilot" if _tab == Tab.PILOT else "mech"
		var title: String = "파일럿 카드" if _tab == Tab.PILOT else "메크 카드"
		return _build_card_grid(y + 18.0, title, _starter_cards(slot),
				slot, _starter_cards(slot).size())

	# 죽어 있을 때만 뜨는 한 줄. 스트립의 부활 카운트는 패널이 열려 있는 동안
	# 숨겨져 있으므로 여기 말고는 남은 턴 수를 볼 자리가 없다.
	if not _pilot.alive:
		y += 12.0
		var dead := _make_label("부활까지 %d턴" % _bs.turns_until_return(_pilot),
				24, Color(1.0, 0.62, 0.62), HORIZONTAL_ALIGNMENT_LEFT)
		dead.position = Vector2(STAT_X, y)
		dead.size = Vector2(STAT_W, 30.0)
		_body_root.add_child(dead)
		y += 30.0

	# 지속 효과는 **스탯 칩 바로 아래**다 — 칩이 보여 주는 최종 값을 밀고 있는
	# 것들이라 같은 눈길 안에 있어야 "왜 이 값인가"가 이어진다.
	y = _build_effect_row(y + 18.0)
	# 인게임 탭의 카드는 **여섯 장 전부**, 3열 2행. 파일럿 3 → 메크 3 순서라
	# 윗줄이 사람, 아랫줄이 기체다.
	var all_cards: Array = _starter_cards("pilot") + _starter_cards("mech")
	y = _build_card_grid(y + 18.0, "보유 카드", all_cards, "all",
			CARD_GRID_COLS)
	# 스킬 블록은 카드 줄 **아래**다 — 카드가 "무엇을 들고 시작했는가"라면
	# 스킬은 "이 선수만이 할 수 있는 것"이라, 읽는 순서가 그쪽이 나중이다.
	return _build_skill_block(y + 22.0)


# ─── 머리글 (탭 위) ─────────────────────────────────────────────────────────
## 파일럿 이름 + 기체명 + 성장치. **`_build` 에서 한 번만** 세우고 탭 전환은
## 건드리지 않는다 — `refresh()` 는 성장치 숫자만 다시 쓴다.
##
## 이름과 기체명은 `HBoxContainer` 로 이어 붙인다. 이름 라벨을 고정 폭으로 두고
## 기체명을 그 오른쪽 좌표에 놓으려면 글자 폭을 손으로 재야 하는데, 이름 길이가
## 파일럿마다 다르고 폰트도 폴백을 타므로 그 계산이 조용히 어긋난다 — 컨테이너는
## 각 라벨의 최소 크기를 그대로 읽어 붙여 준다.
func _build_header_block() -> void:
	var pd: PlayerData = _bs.player_data_for(_pilot)
	var mech: MechData = _mech()
	var display_name: String = pd.name if pd != null else _bs.pilot_label(_pilot)

	var bg := Panel.new()
	bg.name = "HeaderBackdrop"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.position = Vector2(STAT_X - STAT_PANEL_PAD.x, HDR_TOP)
	bg.size = Vector2(STAT_W + STAT_PANEL_PAD.x * 2.0, HDR_BOTTOM - HDR_TOP)
	var sb := StyleBoxFlat.new()
	sb.bg_color = STAT_PANEL_BG
	sb.border_color = STAT_PANEL_BORDER
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	bg.add_theme_stylebox_override("panel", sb)
	_root.add_child(bg)

	var row_h: float = HDR_BOTTOM - HDR_TOP - STAT_PANEL_PAD.y * 2.0
	var row_y: float = HDR_TOP + STAT_PANEL_PAD.y

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(STAT_X, row_y)
	row.size = Vector2(STAT_W - HDR_GROWTH_W, row_h)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 10)
	_root.add_child(row)

	var name_lbl := _make_label(display_name, HDR_NAME_FONT, HEADER_COLOR,
			HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	# 기체명은 늘 보인다 — 메크 탭에 들어가야만 알 수 있는 값이 아니다.
	var mech_lbl := _make_label(mech.name if mech != null else "메크 미배정",
			HDR_MECH_FONT, HDR_MECH_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	mech_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(mech_lbl)

	_growth_label = _make_label(BattleSim.fmt_score(_pilot.score),
			HDR_GROWTH_FONT, GROWTH_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	_growth_label.position = Vector2(STAT_X + STAT_W - HDR_GROWTH_W, row_y)
	_growth_label.size = Vector2(HDR_GROWTH_W, row_h)
	# **clip_text 는 필수다** — 오른쪽 정렬 Label 은 글자가 rect 보다 넓으면
	# 정렬을 포기하고 rect 왼쪽부터 그려 오른쪽으로 넘쳐 나간다.
	_growth_label.clip_text = true
	_root.add_child(_growth_label)


# ─── 스탯 칩 ─────────────────────────────────────────────────────────────────
## 이 탭이 보여 줄 칩 목록. `[[key, 이름], …]` — 값과 메뉴 내용은 key 로 갈린다.
func _chip_defs() -> Array:
	match _tab:
		Tab.INGAME:
			return [["hp", "체력"], ["atk", "공격력"], ["growth", "성장"],
					["hit", "명중"], ["eva", "회피"], ["presence", "존재감"]]
		Tab.PILOT:
			return [["laning", "라인전"], ["mechanics", "메카닉"],
					["gamesense", "게임센스"], ["teamfight", "한타"],
					["mental", "멘탈"]]
		_:
			return [["m_hp", "체력"], ["m_atk", "공격력"], ["m_presence", "존재감"]]


func _build_chip_grid(start_y: float, defs: Array) -> float:
	var w: float = (STAT_W - float(CHIP_COLS - 1) * CHIP_GAP) / float(CHIP_COLS)
	var y: float = start_y
	for i in defs.size():
		var col: int = i % CHIP_COLS
		@warning_ignore("integer_division")
		var row: int = i / CHIP_COLS
		var pos := Vector2(STAT_X + float(col) * (w + CHIP_GAP),
				start_y + float(row) * (CHIP_H + CHIP_GAP))
		_make_chip(String(defs[i][0]), String(defs[i][1]), pos, w)
		y = pos.y + CHIP_H
	return y


## 칩 한 칸. 누르면 메뉴가 열려야 하므로 Button 이고, 그 위의 두 라벨은
## IGNORE 라 클릭을 가로채지 않는다.
func _make_chip(key: String, chip_name: String, pos: Vector2, w: float) -> void:
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(w, CHIP_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_target_pressed.bind(key))
	_body_root.add_child(btn)

	var name_lbl := _make_label(chip_name, CHIP_NAME_FONT, KEY_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	name_lbl.position = Vector2(0.0, 8.0)
	name_lbl.size = Vector2(w, CHIP_NAME_H)
	name_lbl.clip_text = true
	btn.add_child(name_lbl)

	var text: String = _chip_value(key)
	var val_lbl := _make_label(text, _value_font_size(text), VALUE_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	val_lbl.position = Vector2(4.0, CHIP_NAME_H + 6.0)
	val_lbl.size = Vector2(w - 8.0, CHIP_H - CHIP_NAME_H - 14.0)
	val_lbl.clip_text = true
	btn.add_child(val_lbl)

	_targets[key] = {"button": btn, "style": TargetStyle.CHIP, "value": val_lbl}
	_style_target(key, false)


## 정보 패널을 여는 것 셋(칩 · 효과 썸네일 · 카드)의 강조 스타일을 한 곳에서
## 그린다. 모양은 종류마다 다르지만 **"지금 이걸 보고 있다"는 신호는 하나**여야
## 하므로 색과 테두리 두께 규칙은 공유한다.
func _style_target(key: String, highlighted: bool) -> void:
	if not _targets.has(key):
		return
	var rec: Dictionary = _targets[key] as Dictionary
	var btn := rec["button"] as Button
	if not is_instance_valid(btn):
		return
	var style: int = int(rec["style"])
	if style == TargetStyle.CARD:
		# 카드는 자기 그림을 가진 물건이라 배경을 칠하면 카드가 안 보인다 —
		# 테두리만 두른다(하이라이트가 아니면 아무것도 안 그린다).
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0, 0, 0, 0)
		csb.border_color = CHIP_BORDER_HL if highlighted else Color(0, 0, 0, 0)
		var cbw: int = 3 if highlighted else 0
		csb.border_width_top = cbw
		csb.border_width_bottom = cbw
		csb.border_width_left = cbw
		csb.border_width_right = cbw
		csb.corner_radius_top_left = 10
		csb.corner_radius_top_right = 10
		csb.corner_radius_bottom_left = 10
		csb.corner_radius_bottom_right = 10
		for cstate in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(cstate, csb)
		return

	var sb := StyleBoxFlat.new()
	var is_fx: bool = style == TargetStyle.FX
	sb.bg_color = (FX_BG_HL if highlighted else FX_BG) if is_fx 			else (CHIP_BG_HL if highlighted else CHIP_BG)
	sb.border_color = CHIP_BORDER_HL if highlighted else CHIP_BORDER
	var bw: int = 3 if highlighted else 1
	sb.border_width_top = bw
	sb.border_width_bottom = bw
	sb.border_width_left = bw
	sb.border_width_right = bw
	var radius: int = FX_RADIUS if is_fx else CHIP_RADIUS
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, sb)


## 값 라벨을 들고 있는 대상(= 스탯 칩)만 다시 쓴다. 효과 썸네일과 카드는 값이
## 바뀌면 구성 자체가 바뀌므로 `refresh()` 의 서명 비교가 본문을 다시 세운다.
func _refresh_target_values() -> void:
	for key in _targets.keys():
		var rec: Dictionary = _targets[key] as Dictionary
		var lbl := rec.get("value") as Label
		if lbl == null or not is_instance_valid(lbl):
			continue
		var text: String = _chip_value(String(key))
		if lbl.text == text:
			continue
		lbl.text = text
		lbl.add_theme_font_size_override("font_size", _value_font_size(text))


## 글자 수에 맞춘 값 폰트. 칩 폭이 141px 뿐이라 `145 / 200` 같은 긴 값을 가장 큰
## 폰트로 두면 잘린다 — 자르느니 한 단계 줄이는 편이 읽힌다.
static func _value_font_size(text: String) -> int:
	var n: int = text.length()
	if n <= 4:
		return 38
	if n <= 6:
		return 32
	if n <= 9:
		return 26
	return 22


## 칩에 크게 찍히는 **최종 값**. 기본값 · 증가분은 여기 적지 않는다 — 그건
## 칩을 눌러야 나오는 메뉴의 몫이다.
func _chip_value(key: String) -> String:
	var pd: PlayerData = _bs.player_data_for(_pilot)
	var mech: MechData = _mech()
	match key:
		"hp":
			return "%d / %d" % [_pilot.hp, _pilot.max_hp]
		"atk":
			return str(_pilot.atk)
		"growth":
			return "+%d%%" % roundi(_pilot.growth * 100.0)
		"hit":
			return str(_bs.sim_core.lane_adjusted(_pilot.hit, _pilot))
		"eva":
			return str(_bs.sim_core.lane_adjusted(_pilot.evasion, _pilot))
		"presence":
			return str(_pilot.presence)
		"laning":
			return str(pd.laning) if pd != null else "—"
		"mechanics":
			return str(pd.mechanics) if pd != null else "—"
		"gamesense":
			return str(pd.gamesense) if pd != null else "—"
		"teamfight":
			return str(pd.teamfight) if pd != null else "—"
		"mental":
			return str(pd.mental) if pd != null else "—"
		"m_hp":
			return str(mech.hp) if mech != null else "—"
		"m_atk":
			return str(mech.atk) if mech != null else "—"
		"m_presence":
			return str(mech.presence) if mech != null else "—"
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
## 다섯 자리가 전부다. 라인전 스탯(명중/회피 배율), 적립 배율(턴 · 단계 만료),
## 영구 적립 배율(용 보상), 일시 공격력, 보호막. 팀 단위로 걸리는 계획 살인
## 예약은 여기 없다 — 파일럿의 것이 아니라 팀의 것이라 다섯 명 모두에게 같은
## 썸네일이 떠 무엇이 누구 것인지가 흐려진다.
func _effect_defs() -> Array:
	var out: Array = []
	if not is_zero_approx(_pilot.lane_stat_mod):
		var up: bool = _pilot.lane_stat_mod > 0.0
		out.append({
			"key": "fx:lane",
			"short": "라인",
			"title": "공격적인 라인전" if up else "안전한 파밍",
			"value": "%+d%%" % roundi(_pilot.lane_stat_mod * 100.0),
			"color": Color(1.00, 0.62, 0.48) if up else Color(0.55, 0.82, 1.00),
		})
	if not is_equal_approx(_pilot.growth_rate_mult, 1.0):
		out.append({
			"key": "fx:rate",
			"short": "적립",
			"title": "성장치 적립 배율",
			"value": "%+d%%" % roundi((_pilot.growth_rate_mult - 1.0) * 100.0),
			"color": Color(0.72, 1.00, 0.80),
		})
	if not is_zero_approx(_pilot.growth_rate_bonus):
		out.append({
			"key": "fx:perm",
			"short": "영구",
			"title": "영구 적립 배율",
			"value": "%+d%%" % roundi(_pilot.growth_rate_bonus * 100.0),
			"color": Color(1.00, 0.55, 0.28),
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
			"short": "보호",
			"title": "보호막",
			"value": str(_pilot.shield),
			"color": Color(0.92, 0.92, 0.42),
		})
	return out


func _build_effect_row(start_y: float) -> float:
	var y: float = _build_section_head(start_y, "지속 효과", FX_SECTION_H)
	var defs: Array = _effect_defs()
	if defs.is_empty():
		var none := _make_label("걸려 있는 효과 없음", 22, FX_EMPTY_COLOR,
				HORIZONTAL_ALIGNMENT_LEFT)
		none.position = Vector2(STAT_X, y)
		none.size = Vector2(STAT_W, 32.0)
		_body_root.add_child(none)
		return y + 32.0

	for i in defs.size():
		var d: Dictionary = defs[i] as Dictionary
		_make_fx_thumb(d, Vector2(STAT_X + float(i) * (FX_SIZE + FX_GAP), y))
	return y + FX_SIZE


## 썸네일 한 칸 — 위에 두 글자 약칭(효과별 색), 아래에 작게 지금 값.
## 아이콘 에셋이 없으므로 **글자가 곧 아이콘**이다. 두 글자로 줄인 것은 68px
## 칸에서 온전한 이름("공격적인 라인전")이 들어갈 자리가 없기 때문이고, 전체
## 이름은 눌러서 여는 패널의 제목이 들고 있다.
func _make_fx_thumb(d: Dictionary, pos: Vector2) -> void:
	var key: String = String(d["key"])
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(FX_SIZE, FX_SIZE)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_target_pressed.bind(key))
	_body_root.add_child(btn)

	var short_lbl := _make_label(String(d["short"]), FX_SHORT_FONT,
			d["color"] as Color, HORIZONTAL_ALIGNMENT_CENTER)
	short_lbl.position = Vector2(0.0, 8.0)
	short_lbl.size = Vector2(FX_SIZE, 26.0)
	short_lbl.clip_text = true
	btn.add_child(short_lbl)

	var val_lbl := _make_label(String(d["value"]), FX_VALUE_FONT, VALUE_COLOR,
			HORIZONTAL_ALIGNMENT_CENTER)
	val_lbl.position = Vector2(2.0, 34.0)
	val_lbl.size = Vector2(FX_SIZE - 4.0, 26.0)
	val_lbl.clip_text = true
	btn.add_child(val_lbl)

	_targets[key] = {"button": btn, "style": TargetStyle.FX}
	_style_target(key, false)


# ─── 카드 ────────────────────────────────────────────────────────────────────
## 이 파일럿이 개시에 배분받은 카드(`slot` = "mech" / "pilot").
func _starter_cards(slot: String) -> Array:
	var rec: Dictionary = _bs.starter_cards.get(_pilot, {}) as Dictionary
	return rec.get(slot, []) as Array


## 제목 한 줄 + 밑줄. 카드 줄과 효과 줄이 같은 모양을 쓴다.
func _build_section_head(start_y: float, title: String, head_h: float) -> float:
	var head := _make_label(title, 26, SECTION_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	head.position = Vector2(STAT_X, start_y)
	head.size = Vector2(STAT_W, head_h)
	_body_root.add_child(head)
	var line := ColorRect.new()
	line.color = Color(SECTION_COLOR.r, SECTION_COLOR.g, SECTION_COLOR.b, 0.35)
	line.position = Vector2(STAT_X, start_y + head_h)
	line.size = Vector2(STAT_W, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_root.add_child(line)
	return start_y + head_h + 14.0


## 카드 `cols` 열 격자. 3장이면 `cols = 3` 으로 한 줄, 인게임 탭의 6장이면 3열
## 2행이다. `key_prefix` 는 카드마다 붙는 정보 패널 키의 앞자리(`card:all:2`).
##
## **카드 노드 위에 투명 버튼을 한 장 덮는다** — `Card` 는 손패에서 호버 · 드래그
## 배선을 스스로 쥐고 있는 노드라 여기서 입력을 직접 받게 하면 그 기계가 함께
## 깨어난다. 버튼은 카드와 정확히 같은 자리를 덮으므로 눌리는 곳과 보이는 곳이
## 어긋나지 않는다.
func _build_card_grid(start_y: float, title: String, cards: Array,
		key_prefix: String, cols: int) -> float:
	var y: float = _build_section_head(start_y, title, CARD_SECTION_H)
	if cards.is_empty():
		var none := _make_label("배분 기록 없음", 24, KEY_COLOR,
				HORIZONTAL_ALIGNMENT_LEFT)
		none.position = Vector2(STAT_X, y)
		none.size = Vector2(STAT_W, 32.0)
		_body_root.add_child(none)
		return y + 32.0

	var ncols: int = maxi(1, cols)
	var cw: float = Card.CARD_W * CARD_VIEW_SCALE
	var ch: float = Card.CARD_H * CARD_VIEW_SCALE
	var row_w: float = float(ncols) * cw + float(ncols - 1) * CARD_GAP
	var x0: float = STAT_X + (STAT_W - row_w) * 0.5
	var rows: int = int(ceil(float(cards.size()) / float(ncols)))
	for i in cards.size():
		var col: int = i % ncols
		@warning_ignore("integer_division")
		var row: int = i / ncols
		var at := Vector2(x0 + float(col) * (cw + CARD_GAP),
				y + float(row) * (ch + CARD_ROW_GAP))

		var node := _bs.CARD_SCENE.instantiate() as Card
		# add_child BEFORE setup — Card.gd 의 @onready 참조가 트리 진입 후에야
		# 풀린다 (CardPileViewer._build_grid 와 동일).
		_body_root.add_child(node)
		# is_player_card=false → 호버 브라이튼 / 그림자가 붙지 않는다. IGNORE 와
		# 합쳐 `Card._refresh_float_state`(= scale 의 주인)가 영영 돌지 않으므로
		# 여기서 준 축소가 그대로 남는다.
		node.setup(cards[i] as CardData, false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = Vector2.ZERO
		node.scale = Vector2(CARD_VIEW_SCALE, CARD_VIEW_SCALE)
		node.position = at

		var key: String = "card:%s:%d" % [key_prefix, i]
		var btn := Button.new()
		btn.position = at
		btn.size = Vector2(cw, ch)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_target_pressed.bind(key))
		_body_root.add_child(btn)
		_targets[key] = {"button": btn, "style": TargetStyle.CARD,
				"card": cards[i]}
		_style_target(key, false)
	return y + float(rows) * ch + float(rows - 1) * CARD_ROW_GAP


## 파일럿 스킬 한 블록. 스킬이 없는 파일럿(모브)에게는 한 줄만 남긴다 —
## 칸을 통째로 빼면 "이 선수는 스킬이 없다"가 화면에서 사라져 버그처럼 읽힌다.
func _build_skill_block(start_y: float) -> float:
	var sk: PilotSkillSystem = _bs.skill
	var y: float = _build_section_head(start_y, "파일럿 스킬", SKILL_SECTION_H)
	if sk == null or not sk.has_skill(_pilot):
		var none := _make_label("스킬 없음", 24, KEY_COLOR,
				HORIZONTAL_ALIGNMENT_LEFT)
		none.position = Vector2(STAT_X, y)
		none.size = Vector2(STAT_W, 32.0)
		_body_root.add_child(none)
		return y + 32.0

	# 이름 + 타입 배지 — 한 줄에 좌/우로 나눠 앉는다.
	var name_lbl := _make_label(sk.skill_name(_pilot), SKILL_NAME_FONT,
			SKILL_NAME_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(STAT_X, y)
	name_lbl.size = Vector2(STAT_W * 0.62, 40.0)
	_body_root.add_child(name_lbl)

	# 배지는 **타입 한 단어만** 이다. 키워드까지 붙이면 긴 스킬(포탑 파괴, 전투
	# 개시)에서 38% 폭을 넘겨 오른쪽 정렬이 왼쪽부터 잘려 나간다 — 우측 정렬
	# Label 은 넘칠 때 정렬을 포기하고 rect 왼쪽부터 그린다(`clip_text` 는 그
	# 넘침을 화면 밖으로 나가지 않게 막을 뿐 잘림 자체는 남는다).
	var type_lbl := _make_label(String(SKILL_TYPE_LABEL.get(
			sk.skill_type(_pilot), sk.skill_type(_pilot))),
			SKILL_TYPE_FONT, SKILL_TYPE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	type_lbl.position = Vector2(STAT_X + STAT_W * 0.62, y + 8.0)
	type_lbl.size = Vector2(STAT_W * 0.38, 30.0)
	type_lbl.clip_text = true
	_body_root.add_child(type_lbl)
	y += 40.0

	# 키워드는 자기 줄에 작고 흐리게 — 분류 꼬리표라 설명문보다 앞에 오되
	# 이름만큼 크면 안 된다.
	var kw: String = sk.skill_keyword(_pilot)
	if not kw.is_empty():
		var kw_lbl := _make_label(kw, SKILL_KW_FONT, SKILL_KW_COLOR,
				HORIZONTAL_ALIGNMENT_LEFT)
		kw_lbl.position = Vector2(STAT_X, y)
		kw_lbl.size = Vector2(STAT_W, 26.0)
		kw_lbl.clip_text = true
		_body_root.add_child(kw_lbl)
		y += 26.0
	y += SKILL_LINE_GAP

	# 설명문 — 줄바꿈은 폰트에게 물어 실제 높이를 잡는다. 글자 수로 어림하면
	# 한글/영문 혼용에서 한두 줄씩 어긋나 아래 버튼이 겹치거나 뜬다.
	var desc := _make_label(sk.skill_description(_pilot), SKILL_DESC_FONT,
			SKILL_DESC_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.position = Vector2(STAT_X, y)
	desc.size = Vector2(STAT_W, 30.0)
	_body_root.add_child(desc)
	var font: Font = desc.get_theme_font("font")
	var desc_h: float = 30.0
	if font != null:
		desc_h = maxf(30.0, font.get_multiline_string_size(
				desc.text, HORIZONTAL_ALIGNMENT_LEFT, STAT_W,
				SKILL_DESC_FONT).y + 6.0)
	desc.size = Vector2(STAT_W, desc_h)
	y += desc_h + SKILL_LINE_GAP

	# 상태 한 줄 — 남은 턴 / 충전 수. `refresh()` 가 이 라벨만 다시 쓴다.
	_skill_status = _make_label(sk.status_text(_pilot), SKILL_STATUS_FONT,
			SKILL_WAIT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	_skill_status.position = Vector2(STAT_X, y)
	_skill_status.size = Vector2(STAT_W, 30.0)
	_body_root.add_child(_skill_status)
	y += 30.0 + SKILL_LINE_GAP

	# 패시브에는 버튼이 없다 — 누를 수 없는 것에 비활성 버튼을 두면 "언젠가는
	# 눌리는 것"으로 읽힌다.
	if sk.skill_type(_pilot) == PilotSkillSystem.TYPE_PASSIVE:
		_skill_use_btn = null
		return y
	_skill_use_btn = Button.new()
	_skill_use_btn.text = "사용"
	_skill_use_btn.focus_mode = Control.FOCUS_NONE
	_skill_use_btn.add_theme_font_size_override("font_size", 28)
	_skill_use_btn.position = Vector2(STAT_X, y)
	_skill_use_btn.size = Vector2(STAT_W, SKILL_USE_H)
	_skill_use_btn.pressed.connect(_on_skill_use_pressed)
	_body_root.add_child(_skill_use_btn)
	_refresh_skill_block()
	return y + SKILL_USE_H


## 상태 줄과 버튼 활성만 다시 쓴다 — 트리는 건드리지 않는다.
func _refresh_skill_block() -> void:
	var sk: PilotSkillSystem = _bs.skill
	if sk == null or _pilot == null:
		return
	if _skill_status != null and is_instance_valid(_skill_status):
		_skill_status.text = sk.status_text(_pilot)
		_skill_status.add_theme_color_override("font_color",
				SKILL_READY_COLOR if sk.can_activate(_pilot) else SKILL_WAIT_COLOR)
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

	_menu_root = Control.new()
	_menu_root.name = "InfoMenu"
	_menu_root.position = Vector2.ZERO
	_menu_root.size = Vector2(VP_W, VP_H)
	# 바깥을 누르면 닫힌다. 이 판이 STOP 이라 뒤쪽 버튼이 전부 가려지므로
	# **뒤판이 직접 라우팅한다**(`_on_menu_backdrop_input`) — 아래 주석 참조.
	_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.gui_input.connect(_on_menu_backdrop_input)
	_root.add_child(_menu_root)
	_build_menu_content()


## 뒤판 클릭을 **그 자리에 있던 버튼에게 대신 전달한다.**
##
## 예전에는 이 함수가 무조건 `_close_menu()` 만 했다. 그래서 공격력 설명을 열어
## 둔 채 명중 칩을 누르면 첫 클릭은 패널을 닫는 데 쓰이고, 명중 설명을 보려면
## **한 번 더** 눌러야 했다 — 스탯 여섯 개를 훑어보는 동안 클릭 수가 두 배가
## 되고, 화면은 열림 ↔ 닫힘을 반복해 깜빡인다. 정보 패널은 서로 갈아타는 것이
## 기본 동작이므로, 뒤판은 "닫기"가 아니라 "그 아래 있는 것을 대신 눌러 주기"를
## 해야 한다.
##
## 좌표계가 전부 같아서 판정이 단순하다 — `_menu_root` · `_body_root` · `_root`
## 가 모두 (0,0) 에 놓인 전체 화면 Control 이라 버튼의 `position` 을 그대로
## 뒤판 로컬 좌표와 견주면 된다.
func _on_menu_backdrop_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var at: Vector2 = mb.position

	# 1) 다른 정보 대상(칩 · 효과 · 카드) 위 — 곧장 그쪽으로 갈아탄다.
	for raw_key in _targets.keys():
		var key := String(raw_key)
		var btn := (_targets[key] as Dictionary)["button"] as Button
		if is_instance_valid(btn) and Rect2(btn.position, btn.size).has_point(at):
			_on_target_pressed(key)
			return

	# 2) 탭 — 패널을 닫고 탭을 넘긴다(탭 자체도 `_close_menu` 를 부르지만,
	#    같은 탭을 누른 경우 그쪽이 일찍 돌아가므로 여기서 먼저 닫아 둔다).
	for i in _tab_buttons.size():
		var tb := _tab_buttons[i] as Button
		if is_instance_valid(tb) and Rect2(tb.position, tb.size).has_point(at):
			_close_menu()
			_on_tab_pressed(i)
			return

	# 3) 닫기 버튼 — 패널만 닫고 마는 것이 아니라 상세 화면째 닫는다.
	if _close_btn != null and is_instance_valid(_close_btn) \
			and Rect2(_close_btn.position, _close_btn.size).has_point(at):
		close()
		return

	_close_menu()


func _close_menu() -> void:
	if _menu_key != "":
		_style_target(_menu_key, false)
	_menu_key = ""
	if _menu_root != null and is_instance_valid(_menu_root):
		_menu_root.queue_free()
	_menu_root = null


## 메뉴 판을 (다시) 세운다. `refresh()` 가 값이 바뀔 때마다 부르므로 메뉴에
## 적힌 숫자도 칩과 같은 순간의 값이다.
func _build_menu_content() -> void:
	if _menu_root == null or not is_instance_valid(_menu_root):
		return
	if not _targets.has(_menu_key):
		return
	for child in _menu_root.get_children():
		_menu_root.remove_child(child)
		child.queue_free()

	var rows: Array = _menu_rows(_menu_key)
	var note: String = _menu_note(_menu_key)
	var inner_w: float = MENU_W - MENU_PAD.x * 2.0
	# **설명 높이는 글자 수가 정한다.** 카드 설명은 스탯 한 줄짜리 주석과 달리
	# 서너 줄까지 가므로 44px 로 못 박아 두면 아랫줄이 판 밖으로 흘러나간다.
	var note_h: float = 0.0
	if note != "":
		note_h = _text_height(note, inner_w, MENU_NOTE_FONT) + 10.0
	var body_h: float = 44.0 + float(rows.size()) * MENU_ROW_H + note_h

	var src_btn := (_targets[_menu_key] as Dictionary)["button"] as Button
	var panel_h: float = body_h + MENU_PAD.y * 2.0
	var x: float = STAT_X - MENU_GAP_X - MENU_W
	# 누른 것과 같은 높이에서 시작하되 화면 위아래로는 넘기지 않는다.
	var y: float = clampf(src_btn.position.y - MENU_PAD.y, 20.0,
			maxf(20.0, VP_H - panel_h - 20.0))

	var panel := Panel.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(MENU_W, panel_h)
	# 판 위 클릭은 메뉴를 닫지 않는다 — 뒤판까지 이벤트가 내려가지 않게 STOP.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = MENU_BG
	sb.border_color = MENU_BORDER
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", sb)
	_menu_root.add_child(panel)

	var iy: float = MENU_PAD.y
	var head := _make_label(_target_title(_menu_key), 28, HEADER_COLOR,
			HORIZONTAL_ALIGNMENT_LEFT)
	head.position = Vector2(MENU_PAD.x, iy)
	head.size = Vector2(inner_w, 36.0)
	panel.add_child(head)
	iy += 44.0

	for row in rows:
		var k := _make_label(String(row[0]), 22, KEY_COLOR,
				HORIZONTAL_ALIGNMENT_LEFT)
		k.position = Vector2(MENU_PAD.x, iy)
		k.size = Vector2(inner_w * MENU_KEY_FRAC, MENU_ROW_H)
		k.clip_text = true
		panel.add_child(k)
		var v := _make_label(String(row[1]), 24, VALUE_COLOR,
				HORIZONTAL_ALIGNMENT_RIGHT)
		v.position = Vector2(MENU_PAD.x + inner_w * MENU_KEY_FRAC, iy)
		v.size = Vector2(inner_w * (1.0 - MENU_KEY_FRAC), MENU_ROW_H)
		# **clip_text 는 필수다.** 오른쪽 정렬 Label 은 글자가 rect 보다 넓으면
		# 정렬을 포기하고 rect 왼쪽부터 그려서 오른쪽으로 넘쳐 나간다.
		v.clip_text = true
		panel.add_child(v)
		iy += MENU_ROW_H

	if note != "":
		var n := _make_label(note, MENU_NOTE_FONT, Color(0.62, 0.66, 0.76),
				HORIZONTAL_ALIGNMENT_LEFT)
		n.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		# **줄바꿈을 켜는 것이 크기보다 먼저여야 한다.** `Control.size` 의 세터는
		# 요청값을 최소 크기로 한 번 걷어 올리는데, 줄바꿈이 꺼진 Label 의 최소
		# 폭은 **한 줄로 편 글자 전체 폭**이다 — 그 상태에서 332px 를 요청하면
		# 라벨이 글자 폭 그대로 부풀고, 뒤늦게 줄바꿈을 켜도 이미 커진 rect 는
		# 줄지 않는다. 화면에서는 첫 줄이 판 밖으로 삐져나가고 아랫줄이 잘린
		# 것으로 보였다(실측 확인).
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.position = Vector2(MENU_PAD.x, iy + 6.0)
		n.size = Vector2(inner_w, note_h)
		panel.add_child(n)


## 자동 줄바꿈된 글의 높이. 판 높이를 내용에서 유도하는 유일한 자리다.
##
## **줄바꿈 규칙을 Label 과 맞춰야 한다.** `get_multiline_string_size` 의 기본
## 플래그는 `BREAK_MANDATORY | BREAK_WORD_BOUND` 인데 라벨 쪽은
## `AUTOWRAP_WORD_SMART`(= 거기에 `BREAK_GRAPHEME_BOUND` 가 더 붙는다)라,
## 기본값으로 재면 라벨이 실제로는 한 줄 더 쓰는 경우가 생겨 마지막 줄이 판
## 아래로 잘려 나간다(실측 확인 — 두 줄로 재고 세 줄로 그렸다).
static func _text_height(text: String, width: float, font_size: int) -> float:
	var font := ThemeDB.fallback_font
	var flags: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND 			| TextServer.BREAK_GRAPHEME_BOUND
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
			width, font_size, -1, flags).y


## 정보 패널의 제목. 접두사가 종류를 가른다 — 스탯은 칩 이름, 효과는 온전한
## 효과 이름(썸네일에는 두 글자 약칭밖에 없다), 카드는 카드 이름.
func _target_title(key: String) -> String:
	if key.begins_with("fx:"):
		for raw in _effect_defs():
			var d: Dictionary = raw as Dictionary
			if String(d["key"]) == key:
				return String(d["title"])
		return key
	if key.begins_with("card:"):
		var cd: CardData = _card_of(key)
		return cd.card_name if cd != null else key
	for d2 in _chip_defs():
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
	if key.begins_with("card:"):
		return _card_rows(key)
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
		"growth":
			var rows_g: Array = [
				["성장치", BattleSim.fmt_score(_pilot.score)],
				["공격력 성장", "+%d%%" % roundi(_pilot.growth * 100.0)],
				["최대 체력 성장", "+%d%%" % roundi(_pilot.growth_hp * 100.0)]]
			if not is_equal_approx(_pilot.growth_rate_mult, 1.0):
				rows_g.append(["적립 배율", "%+d%%%s" % [
					roundi((_pilot.growth_rate_mult - 1.0) * 100.0),
					_remain_txt(_pilot.growth_rate_expire_turn,
							_pilot.growth_until_phase)]])
			if not is_zero_approx(_pilot.growth_rate_bonus):
				rows_g.append(["적립 배율(영구)",
					"%+d%%" % roundi(_pilot.growth_rate_bonus * 100.0)])
			return rows_g
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
			return [["기본", str(_pilot.presence)],
					["출처", mech.name if mech != null else "역할 기본값"]]
		"laning", "mechanics", "gamesense", "teamfight", "mental":
			if pd == null:
				return [["기본", "—"]]
			var vals: Dictionary = {
				"laning": pd.laning, "mechanics": pd.mechanics,
				"gamesense": pd.gamesense, "teamfight": pd.teamfight,
				"mental": pd.mental,
			}
			# 아웃게임 스탯은 **경기 중에 변하지 않는다** — 훈련으로만 오른다.
			# 그래서 기본값과 최종값이 언제나 같고 증가분 줄이 따로 없다.
			return [["기본", str(int(vals[key]))], ["인게임 증가", "없음"]]
		"m_hp":
			return [["기체 체력", str(mech.hp) if mech != null else "—"],
					["파일럿 기본 최대 체력", str(_pilot.base_max_hp)]]
		"m_atk":
			return [["기체 공격력", str(mech.atk) if mech != null else "—"],
					["파일럿 기본 공격력", str(_pilot.base_atk)]]
		"m_presence":
			return [["기체 존재감", str(mech.presence) if mech != null else "—"]]
	return []


## 지속 효과 하나의 내역. 값 자체는 썸네일에 이미 찍혀 있으므로 여기서는
## **어디에 곱해지는가**와 **언제까지인가**를 말한다 — 그 둘이 안 보이면 효과가
## 켜져 있다는 사실만 알 뿐 그래서 뭘 해야 하는지가 안 나온다.
func _fx_rows(key: String) -> Array:
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
		"fx:perm":
			return [
				["영구 적립 배율", "%+d%%" % roundi(_pilot.growth_rate_bonus * 100.0)],
				["남은 시간", "영구"],
				["성장치", BattleSim.fmt_score(_pilot.score)]]
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


## 카드 한 장의 내역. 설명문 자체는 note 로 내려가고 여기에는 **손에서 판단할
## 때 필요한 숫자**만 온다 — 비용, 어느 슬롯의 카드인가, 누가 쓸 수 있는가.
func _card_rows(key: String) -> Array:
	var cd: CardData = _card_of(key)
	if cd == null:
		return []
	var rows: Array = [
		["비용", str(cd.cost)],
		["종류", "메크 카드" if cd.card_type == CardData.TYPE_MECH else "파일럿 카드"],
		["시전자", _scope_label(cd.scope)]]
	var kws: Array = []
	if cd.has_keyword(CardData.KW_EXHAUST):
		kws.append("소멸")
	if cd.has_keyword(CardData.KW_PRESERVE):
		kws.append("보존")
	if not kws.is_empty():
		rows.append(["키워드", " · ".join(kws)])
	return rows


static func _scope_label(scope: String) -> String:
	match scope:
		CardData.SCOPE_LANE:
			return "레인 전용"
		CardData.SCOPE_JUNGLE:
			return "정글러 전용"
	return "제약 없음"


## 남은 수명을 **한 칸짜리 값**으로. `_remain_txt` 는 값 뒤에 괄호로 붙는
## 꼬리표(빈 문자열이 정상)라 행의 값 칸에 그대로 쓰면 빈칸이 남는다.
func _remain_label(expire_turn: int, until_phase: bool) -> String:
	if until_phase:
		return "작전 단계까지"
	if expire_turn < 0:
		return "영구"
	return "%d턴" % maxi(0, expire_turn - _bs.turn_count)


## 정보 패널 하나에 붙는 설명. 숫자만으로는 "그래서 뭘 가르는 값인가"가 안 나오는
## 것에만 붙인다. **카드의 설명문은 여기로 들어온다** — 카드 노드에 적힌 글씨는
## 축소돼 있어 읽으라고 있는 것이 아니다.
func _menu_note(key: String) -> String:
	if key.begins_with("card:"):
		var cd: CardData = _card_of(key)
		return cd.description if cd != null else ""
	match key:
		"fx:lane":
			return "전장 명중 판정에만 곱해진다. 교전 무대는 자기 확률 구간을 쓴다."
		"fx:rate":
			return "성장이 아니라 성장치 적립에 곱해진다. 안전한 파밍과 완벽한 마무리가 같은 칸을 쓴다."
		"fx:perm":
			return "용 보상이 얹는 영구 가산분. 만료도 해제도 없고 누적된다."
		"fx:atk":
			return "카드가 얹은 임시 가산분. 성장 재계산에 지워지지 않는다."
		"fx:shield":
			return "피해를 체력보다 먼저 먹는다. 본진 복귀 시 사라진다."
		"growth":
			return "성장은 성장치에서 파생된다. 공격력이 최대 체력보다 4배 빠르게 자란다."
		"hit":
			return "명중 / (명중 + 상대 회피) 로 전장 명중 판정을 굴린다."
		"eva":
			return "상대 명중 / (상대 명중 + 회피) 로 피격 판정을 굴린다."
		"presence":
			return "교전 무대의 표적 가중치. 전장은 읽지 않는다."
		"mechanics":
			return "인게임 명중의 기준값이 된다."
		"gamesense":
			return "인게임 회피의 기준값이 된다."
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


# ─── 하: 닫기 ────────────────────────────────────────────────────────────────
# 예전의 "전환" 버튼은 삭제됐다 — 파일럿 ↔ 메크는 이제 탭이 가른다.
func _build_buttons() -> void:
	_close_btn = Button.new()
	_close_btn.text = "닫기"
	_close_btn.add_theme_font_size_override("font_size", 28)
	_close_btn.size = Vector2(BTN_W, BTN_H)
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	_root.add_child(_close_btn)
	_reposition_close()


## 받침 아래끝 오른쪽에 붙인다. `_rebuild_body` 가 받침 크기를 정한 직후와
## 버튼을 처음 세울 때 각각 한 번씩 부른다 — 둘 중 어느 쪽이 먼저 와도 되도록
## 상대가 아직 없으면 그냥 돌아간다.
func _reposition_close() -> void:
	if _close_btn == null or not is_instance_valid(_close_btn):
		return
	if _stat_panel == null or not is_instance_valid(_stat_panel):
		return
	_close_btn.position = Vector2(STAT_X + STAT_W - BTN_W,
			_stat_panel.position.y + _stat_panel.size.y + BTN_GAP_Y)


static func _make_label(text: String, font_size: int, color: Color,
		halign: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
