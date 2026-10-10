class_name OutgameTheme
extends RefCounted

# ── 아웃게임 흰 배경 팔레트 ────────────────────────────────────────────────
#
# **아웃게임 화면의 모든 색이 여기를 지난다.** 시즌 허브 · 기자회견 · 훈련판 ·
# 시간 경과 · 순위 · 브래킷 · 드래프트가 같은 표를 읽는다 — 화면마다 자기
# `Color(...)` 리터럴을 들고 있으면 같은 카드가 화면마다 다른 회색으로 그려지고,
# 팔레트를 한 번 손보는 일이 파일 열몇 개를 훑는 일이 된다.
#
# 디자인 원칙은 **하얀 종이 위에 색이 있는 카드**다.
# 규칙 셋으로 요약된다:
#   1. 바탕은 흰색(`BG`), 내용은 그보다 **더 흰** 카드(`SURFACE`) 위에 얹는다.
#      경계는 선이 아니라 **그림자와 밝기 차이**가 만든다(`BORDER` 는 아주 옅다).
#   2. 강조는 색면 하나(`ACCENT`)로만 한다 — 지금 어느 요일인가, 지금 누를
#      버튼은 무엇인가.
#   3. 분류는 **카드 왼쪽의 색 띠 또는 카드 자체의 색면**(`CARD_TINTS`)이 한다.
#      역할 색 다섯(`ROLE_COLORS`)도 그 자리에서만 쓴다.
#
# 인게임(BattleSim)은 `BattleTheme` 을 쓴다 — 그 팔레트가 이 표를 별칭으로
# 끌어다 같은 흰 종이 원칙을 따른다(전장 위에 바로 뜨는 글자만 예외).

# ── 바탕과 면 ────────────────────────────────────────────────────────────────
const BG:            Color = Color(0.960, 0.960, 0.968, 1.0)   # 화면 바탕
const SURFACE:       Color = Color(1.000, 1.000, 1.000, 1.0)   # 카드 · 패널
const SURFACE_SUNK:  Color = Color(0.929, 0.933, 0.945, 1.0)   # 눌린 자리 · 빈 칸
const RAIL:          Color = Color(0.110, 0.110, 0.122, 1.0)   # 좌측 요일 레일
const RAIL_TEXT:     Color = Color(0.620, 0.620, 0.650, 1.0)

# ── 글자 ─────────────────────────────────────────────────────────────────────
const TEXT:          Color = Color(0.110, 0.110, 0.122, 1.0)   # 본문 · 제목
const TEXT_SUB:      Color = Color(0.541, 0.541, 0.569, 1.0)   # 부제 · 라벨
const TEXT_FAINT:    Color = Color(0.722, 0.722, 0.749, 1.0)   # 비활성 · 자리표시
const TEXT_ON_FILL:  Color = Color(1.000, 1.000, 1.000, 1.0)   # 색면 위 글자

# ── 강조 ─────────────────────────────────────────────────────────────────────
const ACCENT:        Color = Color(0.961, 0.651, 0.137, 1.0)   # 앰버
const ACCENT_DIM:    Color = Color(0.996, 0.929, 0.808, 1.0)   # 앰버 배경 틴트
## 흰 바탕 위의 앰버 **글자**. `ACCENT` 를 글자에 그대로 쓰면 흰 종이에서
## 대비가 모자라 안 읽힌다. `ACCENT.darkened(0.2)` 와 같은 값을 리터럴로
## 둔 것은 `darkened()` 가 상수식이 아니라 `const` 자리에서 못 쓰이기 때문이다.
const ACCENT_TEXT:   Color = Color(0.769, 0.521, 0.110, 1.0)
const LINK:          Color = Color(0.180, 0.400, 0.918, 1.0)

# ── 의미색 ───────────────────────────────────────────────────────────────────
const POSITIVE:      Color = Color(0.130, 0.680, 0.380, 1.0)   # 상승 · 승리
const NEGATIVE:      Color = Color(0.878, 0.271, 0.271, 1.0)   # 하락 · 패배
const NEUTRAL:       Color = Color(0.620, 0.620, 0.650, 1.0)   # 변화 없음

# ── 선 ───────────────────────────────────────────────────────────────────────
const BORDER:        Color = Color(0.886, 0.890, 0.906, 1.0)
const BORDER_STRONG: Color = Color(0.780, 0.784, 0.808, 1.0)
const SHADOW:        Color = Color(0.110, 0.110, 0.180, 0.10)

# ── 카드 색면 (카드 네 장) ──────────────────────────────────────
## 분류가 필요한 카드가 순서대로 집어 쓴다. 채도가 비슷해야 한 화면에서
## 어느 하나가 먼저 튀지 않는다.
const CARD_TINTS: Array = [
	Color(0.290, 0.760, 0.780, 1.0),   # 청록
	Color(0.960, 0.475, 0.231, 1.0),   # 주황
	Color(0.608, 0.349, 0.816, 1.0),   # 보라
	Color(0.259, 0.522, 0.957, 1.0),   # 파랑
	Color(0.180, 0.702, 0.443, 1.0),   # 초록
]

## 역할 다섯의 색. 순서는 `GameEnums.Role`(TANK · FIGHTER · ASSASSIN ·
## SUPPORT · SNIPER)이고 **자리 순서가 아니다** — 화면은 `ROLE_DISPLAY_ORDER`
## 로 자리를 잡고 색은 그 자리에 앉은 역할 번호로 집는다.
const ROLE_COLORS: Array = [
	Color(0.180, 0.451, 0.898, 1.0),   # TANK     파랑
	Color(0.937, 0.478, 0.145, 1.0),   # FIGHTER  주황
	Color(0.573, 0.322, 0.847, 1.0),   # ASSASSIN 보라
	Color(0.145, 0.671, 0.400, 1.0),   # SUPPORT  초록
	Color(0.867, 0.235, 0.294, 1.0),   # SNIPER   빨강
]
## 역할 이름도 같은 순서. 예전 화면들이 각자 들고 있던 `ROLE_NAMES` 자리.
## 값은 l10n key — 화면은 `role_name(i)` 로 읽는다.
const ROLE_NAMES: Array = [  # l10n-keys: term.mech_role.*
	L.TERM_MECH_ROLE_TANK, L.TERM_MECH_ROLE_FIGHTER, L.TERM_MECH_ROLE_ASSASSIN,
	L.TERM_MECH_ROLE_SUPPORT, L.TERM_MECH_ROLE_SNIPER,
]

# ── 요일 ─────────────────────────────────────────────────────────────────────
## 월(0) … 일(6). 값은 l10n key — 화면은 `day_letter(i)` · `day_name(i)` 로 읽는다.
const DAY_LETTERS: Array = [  # l10n-keys: term.day.short.*
	L.TERM_DAY_SHORT_MON, L.TERM_DAY_SHORT_TUE, L.TERM_DAY_SHORT_WED, L.TERM_DAY_SHORT_THU,
	L.TERM_DAY_SHORT_FRI, L.TERM_DAY_SHORT_SAT, L.TERM_DAY_SHORT_SUN,
]
const DAY_NAMES: Array = [  # l10n-keys: term.day.long.*
	L.TERM_DAY_LONG_MON, L.TERM_DAY_LONG_TUE, L.TERM_DAY_LONG_WED, L.TERM_DAY_LONG_THU,
	L.TERM_DAY_LONG_FRI, L.TERM_DAY_LONG_SAT, L.TERM_DAY_LONG_SUN,
]


## 역할(`GameEnums.Role`) `i` 의 이름 — 현재 로케일. 범위 밖은 양끝으로 자른다.
static func role_name(i: int) -> String:
	return Loc.t(String(ROLE_NAMES[clampi(i, 0, ROLE_NAMES.size() - 1)]))  # l10n-dynamic: term.mech_role.*


## 요일 `i`(월 0 … 일 6)의 약칭 — 좁은 칸. 범위 밖은 "".
static func day_letter(i: int) -> String:
	if i < 0 or i >= DAY_LETTERS.size():
		return ""
	return Loc.t(String(DAY_LETTERS[i]))  # l10n-dynamic: term.day.short.*


## 요일 `i` 의 이름("월요일"). 범위 밖은 "".
static func day_name(i: int) -> String:
	if i < 0 or i >= DAY_NAMES.size():
		return ""
	return Loc.t(String(DAY_NAMES[i]))  # l10n-dynamic: term.day.long.*

# ── 모달 딤 ──────────────────────────────────────────────────────────────────
## 팝업 · 시트 뒤를 덮는 반투명 막. 씬에서는 `DimPanel` 변형(`OutgameTheme.tres`).
const DIM: Color = Color(0.110, 0.110, 0.180, 0.58)

# ── 글자 크기 (테마 변형의 기본값) ───────────────────────────────────────────
## 씬은 `OutgameTheme.tres` 의 라벨 · 버튼 변형으로 이 크기를 받고, 다른 크기가
## 필요한 노드만 `theme_override_font_sizes/font_size` 로 덮는다.
const FONT_HEADING: int = 52   # 화면 큰 제목 (선수 이름 · 결과 제목)
const FONT_TITLE:   int = 36   # 팝업 · 카드 제목
const FONT_BODY:    int = 26   # 본문
const FONT_CAPTION: int = 22   # 라벨 · 캡션 · 보조 설명
const FONT_BTN_PRIMARY: int = 34
const FONT_BTN_GHOST:   int = 30
const FONT_BTN_TEXT:    int = 26
const FONT_BTN_DARK:    int = 34

# ── 카드 치수 (테마 변형) ────────────────────────────────────────────────────
## `card_style` 의 반지름과 `PanelContainer` 패딩(스타일박스 content_margin).
const CARD_RADIUS:  int = 18
const CARD_PAD:     float = 32.0
const POPUP_RADIUS: int = 24     # 가운데 뜨는 모달 카드 (ConfirmPopup · ManagerTypePopup)
const POPUP_PAD:    float = 48.0
const POPUP_PAD_WIDE: float = 40.0  # 내용이 넓은 팝업 (ShopPopup — 결과 카드 5칸)
const SHEET_RADIUS: int = 28     # 화면 대부분을 덮는 시트 (CollectionDetailSheet)
const SHEET_PAD:    float = 36.0    # 좌우
const SHEET_PAD_V:  float = 27.0    # 위아래
const SUNK_RADIUS:  int = 12     # 카드 안의 눌린 칸 (스탯 칸 · 빈 자리)
const BAR_RADIUS:   int = 7      # 진행 바 트랙 · 채움 (ProgressTrack / ProgressFill)

# ── 칩 (알약, 테마 변형 `AccentChip` · `SurfaceChip`) ────────────────────────
## 알약 = 반지름이 높이의 절반. 높이를 모르므로 아주 큰 값을 주고 `StyleBoxFlat` 이
## 그리는 순간 변 길이에 맞춰 줄이게 한다(마주 보는 두 모서리 합 ≤ 변 길이) —
## 높이가 폭보다 작은 칩이면 결과는 정확히 높이/2.
const CHIP_RADIUS: int = 999
const CHIP_PAD_H:  float = 20.0   # 칩 좌우 안쪽 여백 (글자에 맞춰 크는 칩)
const CHIP_PAD_V:  float = 4.0    # 위아래

# ── 선택형 카드 · 타일 (일반 / 선택 쌍) ──────────────────────────────────────
## 일반 = `SURFACE` + `BORDER` 테두리, 선택 = `ACCENT_DIM` + `ACCENT` 테두리(더 굵게).
## 안쪽 여백은 0 으로 못 박는다 — 비워 두면 StyleBoxFlat 이 테두리 굵기만큼 여백을
## 잡아 선택할 때마다 내용이 테두리 차이만큼 밀린다.
const SELECT_BORDER:         int = 2   # 일반 테두리 (카드 · 타일 공통)
const SELECT_BORDER_ON:      int = 4   # 선택 카드 테두리
const SELECT_TILE_RADIUS:    int = 8   # 작은 타일 · 필터 탭 · 격자 칸
const SELECT_TILE_BORDER_ON: int = 3   # 선택 타일 테두리

## 포지션 배지 가장자리 (색면 위 옅은 검은 테두리, `PositionBadgePanel`).
const POSITION_BADGE_EDGE: Color = Color(0, 0, 0, 0.18)
## 포지션 배지 글자 좌우 / 위아래 여백.
const POSITION_BADGE_PAD_H: float = 8.0
const POSITION_BADGE_PAD_V: float = 1.0
## 주간 레일 요일 칩 반지름 (`WeekDayChip` · `WeekDayChipToday`).
const WEEK_DAY_CHIP_RADIUS: int = 20

## `build_theme()` 이 만든 테마가 저장되는 곳. 손으로 고치지 않는다 —
## 이 파일을 고치고 `OutgameThemeBuilder` 를 다시 돌린다 (`resources/README.md`).
const THEME_PATH: String = "res://resources/OutgameTheme.tres"


# ── StyleBox 공장 ────────────────────────────────────────────────────────────

## 카드 한 장. `tint` 를 주면 그 색으로 꽉 찬 색면 카드가, 안 주면 흰 카드가 된다.
static func card_style(radius: int = CARD_RADIUS, tint: Variant = null,
		with_shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if tint is Color:
		sb.bg_color = tint
	else:
		sb.bg_color = SURFACE
		sb.border_color = BORDER
		sb.set_border_width_all(1)
	set_corner_radius(sb, radius)
	if with_shadow:
		sb.shadow_color = SHADOW
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0, 3)
	return sb


## 테두리만 있는 판 (그림자 없음) — 표 · 격자처럼 여러 장이 붙어 서는 자리.
static func flat_style(bg: Color, radius: int = 12,
		border: Variant = null, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border is Color:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	set_corner_radius(sb, radius)
	return sb


## 카드 왼쪽에 색 띠 하나를 세운 카드 — 분류는 있지만 색면까지 칠하면
## 글자가 안 읽히는 자리(순위표 한 줄, 훈련 결과 한 줄).
static func lead_bar_style(bar: Color, radius: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.border_color = bar
	sb.border_width_left = 6
	set_corner_radius(sb, radius)
	sb.shadow_color = SHADOW
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func set_corner_radius(sb: StyleBoxFlat, r: int) -> void:
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r


# ── 버튼 ─────────────────────────────────────────────────────────────────────

## 화면의 주된 행동 한 개 — 앰버 색면 + 흰 글자. 한 화면에 하나만 둔다.
##
## **감촉은 여기서 정하지 않는다.** 한때는 버튼의 색을 고르는 자리가 곧 그
## 감촉의 세기를 고르는 자리여서 이 네 함수가 `HapticUi.kind` 를 적었지만(primary
## · dark = MEDIUM / ghost = LIGHT / text = SELECT), 그 표는 폐기됐다 — 지금은
## 모든 버튼이 종류와 무관하게 같은 두 박자(누름 LIGHT → 뗌 SOFT)를 낸다.
## 무게는 화면이 말하고, 손에 오는 것은 눌렸다는 사실 하나다. `autoloads/HapticUi.gd`.
static func style_primary_button(b: Button, font_size: int = FONT_BTN_PRIMARY) -> Button:
	return _style_button(b, font_size, "primary")


## 그 밖의 행동 — 흰 바탕 + 옅은 테두리.
static func style_ghost_button(b: Button, font_size: int = FONT_BTN_GHOST) -> Button:
	return _style_button(b, font_size, "ghost")


## 되돌아가는 행동 — 바탕 없이 글자만.
static func style_text_button(b: Button, font_size: int = FONT_BTN_TEXT) -> Button:
	return _style_button(b, font_size, "text")


## 어두운 색면 — 경기 시작처럼 "지금 이 화면을 떠난다"는 행동.
static func style_dark_button(b: Button, font_size: int = FONT_BTN_DARK) -> Button:
	return _style_button(b, font_size, "dark")


## 지우는 · 포기하는 주 행동 — primary 와 같은 모양에 `NEGATIVE` 색면.
## "다음으로 가는" 행동과 같은 앰버면 안 된다(ConfirmPopup 의 `danger`).
static func style_danger_button(b: Button, font_size: int = FONT_BTN_PRIMARY) -> Button:
	return _style_button(b, font_size, "danger")


## 버튼이 갈아입는 상태들. `hover_pressed` 를 비우면 누른 채 손가락 / 커서가
## 올라가 있는 동안 엔진 기본 테마의 스타일박스가 비친다 — `pressed` 와 같게 채운다.
const BUTTON_STATES: Array = ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]
## 글자색 이름들 — `font_disabled_color` 만 `TEXT_FAINT`, 나머지는 그 종류의 `fg`.
const BUTTON_FONT_COLORS: Array = ["font_color", "font_hover_color", "font_pressed_color",
		"font_hover_pressed_color", "font_focus_color"]


## 버튼 종류(`"primary"` / `"ghost"` / `"text"` / `"dark"` / `"danger"`)의 색과 기본 글자 크기.
## **코드 버튼(`style_*_button`)과 테마 변형(`build_theme` 의 `PrimaryButton` …)이 같은
## 표를 읽는다** — 버튼 색을 바꾸려면 여기만 고친다.
static func button_spec(kind: String) -> Dictionary:
	match kind:
		"ghost":
			return {"bg": SURFACE, "fg": TEXT, "hover": SURFACE_SUNK,
					"pressed": BORDER_STRONG, "border": BORDER, "font": FONT_BTN_GHOST}
		"text":
			return {"bg": Color(1, 1, 1, 0), "fg": TEXT_SUB, "hover": Color(0, 0, 0, 0.04),
					"pressed": Color(0, 0, 0, 0.08), "border": null, "font": FONT_BTN_TEXT}
		"dark":
			return {"bg": RAIL, "fg": TEXT_ON_FILL, "hover": RAIL.lightened(0.12),
					"pressed": RAIL.lightened(0.22), "border": null, "font": FONT_BTN_DARK}
		"danger":
			return {"bg": NEGATIVE, "fg": TEXT_ON_FILL, "hover": NEGATIVE.lightened(0.10),
					"pressed": NEGATIVE.darkened(0.12), "border": null, "font": FONT_BTN_PRIMARY}
	return {"bg": ACCENT, "fg": TEXT_ON_FILL, "hover": ACCENT.lightened(0.10),
			"pressed": ACCENT.darkened(0.12), "border": null, "font": FONT_BTN_PRIMARY}


## 한 종류의 상태별 스타일박스 (`BUTTON_STATES` 전부, 매번 새로 만든다).
static func button_styles(kind: String) -> Dictionary:
	var spec: Dictionary = button_spec(kind)
	var border: Variant = spec["border"]
	var pressed: StyleBoxFlat = button_box(spec["pressed"], border)
	return {
		"normal": button_box(spec["bg"], border),
		"hover": button_box(spec["hover"], border),
		"pressed": pressed,
		"hover_pressed": pressed.duplicate(),
		"focus": button_box(Color(0, 0, 0, 0), null),
		"disabled": button_box(SURFACE_SUNK, BORDER),
	}


static func _style_button(b: Button, font_size: int, kind: String) -> Button:
	if b == null:
		return b
	var fg: Color = button_spec(kind)["fg"]
	b.add_theme_font_size_override("font_size", font_size)
	for c in BUTTON_FONT_COLORS:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", TEXT_FAINT)
	var boxes: Dictionary = button_styles(kind)
	for n in BUTTON_STATES:
		b.add_theme_stylebox_override(n, boxes[n])
	return b


## 버튼 스타일박스 한 장 — 반지름 · 패딩은 모든 종류가 같다.
static func button_box(bg: Color, border: Variant) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border is Color:
		sb.border_color = border
		sb.set_border_width_all(1)
	set_corner_radius(sb, 16)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


# ── 하단 액션 바 ─────────────────────────────────────────────────────────────
#
# **아웃게임 화면의 주된 행동은 화면 한가운데 떠 있는 도형이 아니라 하단
# 구간 전체다.** 좌우 여백 없이 화면 끝에서 끝까지, 아래는 안전선에 밀착하고
# 모서리는 각지게 — 그래서 바가 화면의 한 구획이 되고 "여기 아래는 전부 이
# 행동"이 자리만으로 읽힌다. 버튼이 여럿이면 그 구간을 **무게 비율대로**
# 나눠 갖는다(주 행동 2 : 보조 1) — 무엇이 주 행동인지가 색뿐 아니라 폭으로도
# 읽혀야 하기 때문이다.
#
# **색면은 안전선 아래까지 내려간다.** 홈 인디케이터 / 제스처 바 자리를 비워
# 두면 바 밑에 배경색 띠가 한 줄 남아 바가 화면에서 떠 보인다. 그래서 버튼
# 사각형은 뷰포트 바닥까지 늘리되 **글자는 안전선 위에 남긴다** —
# `content_margin_bottom` 에 인셋을 얹으면 Button 이 글자를 그 안쪽 사각형
# 한가운데에 놓으므로, 눌리는 자리와 읽히는 자리가 둘 다 안전 영역 안이다.
#
# 화면은 `bottom_bar_top()` 하나만 알면 된다 — 본문 높이를 그 값에서 역산하면
# 바가 기기마다 오르내려도 내용이 그 밑에 깔리지 않는다.

## 바의 높이(안전 영역 안쪽 기준). 아래 인셋은 여기에 포함되지 않는다 —
## 그것은 글자가 아니라 색면만 내려가는 몫이다.
const BOTTOM_BAR_H: float = 128.0

## 구간 사이의 실선. ghost 버튼은 자기 테두리가 이미 경계를 만들지만
## primary · dark 끼리 붙으면 그 자리가 통짜 색면이 된다.
const BOTTOM_BAR_SEP: Color = Color(0.110, 0.110, 0.122, 0.14)


## **본문이 끝나야 하는 y.** 화면째 `indent_to_safe_top` 으로 내려놓은
## 좌표계 기준이라 `bottom_y()` 가 아니라 `safe_h()` 에서 뺀다.
static func bottom_bar_top() -> float:
	return ScreenMetrics.safe_h() - BOTTOM_BAR_H


## 하단 바 한 줄을 세운다. `specs` 는 왼쪽부터의 구간 목록이고 한 칸은
## `{text, style, weight, font}` — `style` 은 `"primary"`(기본) / `"ghost"` /
## `"dark"` / `"text"`, `weight` 는 구간 폭의 비(기본 1), `font` 는 글자 크기.
## 주 행동은 **오른쪽 끝**에 둔다(엄지가 닿는 자리이고, 훑는 눈이 마지막에
## 멎는 자리다).
##
## 돌려주는 것은 만든 `Button` 배열이다. 상태에 따라 구간이 접히는 화면
## (드래프트의 "뒤로")은 `visible` 을 끄고 `layout_bottom_bar` 를 다시 부른다.
static func add_bottom_bar(parent: Control, specs: Array) -> Array:
	var out: Array = []
	for s_raw in specs:
		var s: Dictionary = s_raw
		var b := Button.new()
		b.text = String(s.get("text", ""))
		b.focus_mode = Control.FOCUS_NONE
		style_bottom_button(b, String(s.get("style", "primary")),
				int(s.get("font", 34)))
		parent.add_child(b)
		out.append(b)
		if out.size() < specs.size():
			var sep := ColorRect.new()
			sep.color = BOTTOM_BAR_SEP
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(sep)
	layout_bottom_bar(out, specs)
	return out


## 보이는 구간만 무게 비율대로 다시 늘어놓는다. 마지막 구간의 오른쪽 끝은
## 반올림 잔차 없이 화면 끝에 정확히 닿는다 — 1px 이라도 남으면 그 틈으로
## 배경이 비쳐 바가 두 조각으로 보인다.
static func layout_bottom_bar(buttons: Array, specs: Array) -> void:
	var vp_w: float = ScreenMetrics.vp_w()
	var top: float = bottom_bar_top()
	var below: float = maxf(0.0, ScreenMetrics.insets().w)
	var total: float = 0.0
	for i in buttons.size():
		if (buttons[i] as Button).visible:
			total += _bar_weight(specs, i)
	if total <= 0.0:
		return

	var x: float = 0.0
	var used: float = 0.0
	var last: int = -1
	for i in buttons.size():
		if (buttons[i] as Button).visible:
			last = i
	for i in buttons.size():
		var b: Button = buttons[i]
		if not b.visible:
			continue
		var w: float = vp_w - used if i == last \
				else floorf(vp_w * _bar_weight(specs, i) / total)
		b.position = Vector2(x, top)
		b.size     = Vector2(w, BOTTOM_BAR_H + below)
		for c in b.get_children():
			var sep := c as ColorRect
			if sep != null:
				# 구분선은 그 구간의 **오른쪽** 끝에 선다. 마지막 구간은
				# 화면 끝이라 선을 세우면 바깥 테두리가 된다.
				sep.visible = i != last
				sep.position = Vector2(w - 2.0, 0.0)
				sep.size     = Vector2(2.0, BOTTOM_BAR_H + below)
		x   += w
		used += w


static func _bar_weight(specs: Array, i: int) -> float:
	if i < 0 or i >= specs.size():
		return 1.0
	return maxf(0.01, float((specs[i] as Dictionary).get("weight", 1.0)))


## 바 한 칸의 옷을 입힌다 — 색을 고르고, 모서리를 각지게 펴고, 안전선 아래로
## 내려간 몫만큼 글자를 위로 물린다. 스타일박스는 `button_box` 가 호출마다 새로
## 만든 것이라 여기서 고쳐도 다른 버튼에 번지지 않는다.
##
## **바뀌는 버튼은 이 함수를 다시 부른다** — `style_primary_button` 을 직접
## 부르면 둥근 모서리가 되살아나 그 칸만 화면에서 도로 떠오른다.
##
## **코드로 세우는 바(`add_bottom_bar`) 전용이다.** 씬(.tscn)에 놓은 바는 버튼에
## `Bar*Button` 변형을 고르고 `fit_bottom_bar` 로 기기 인셋만 넣는다.
static func style_bottom_button(b: Button, style: String = "primary",
		font_size: int = 34) -> Button:
	if b == null:
		return b
	var kind: String = style if style in ["ghost", "dark", "text", "danger"] else "primary"
	_style_button(b, font_size, kind)
	var boxes: Dictionary = bar_button_styles(kind, bottom_inset())
	for n in BUTTON_STATES:
		b.add_theme_stylebox_override(n, boxes[n])
	return b


## 아래 인셋(홈 인디케이터 / 제스처 바), 뷰포트 단위 — 없으면 0.
static func bottom_inset() -> float:
	return maxf(0.0, ScreenMetrics.insets().w)


## 하단 바 한 칸의 상태별 스타일박스 — `button_styles(kind)` 의 모서리를 각지게 펴고
## 아래 여백에 `below`(색면만 내려가는 인셋 몫)를 얹는다. `below` 0 이 테마 변형
## `Bar*Button` 의 값이고, `fit_bar_button` · `style_bottom_button` 이 기기 값으로 부른다.
static func bar_button_styles(kind: String, below: float = 0.0) -> Dictionary:
	var boxes: Dictionary = button_styles(kind)
	for n in BUTTON_STATES:
		var sb: StyleBoxFlat = boxes[n]
		set_corner_radius(sb, 0)
		sb.content_margin_bottom += below
	return boxes


## **씬에 놓은 하단 바의 기기 몫.** 모양(변형 `Bar*Button` · 칸 비율 · 글자 크기 ·
## 구분선 `BarSeparator`)은 씬이 정하고, 여기서는 아래 인셋만 넣는다:
##   - `safe` 를 주면 그 판의 아래끝을 안전선으로 올린다(`offset_bottom = -인셋`).
##   - 바의 사각형: 위끝 = 안전선 - `BOTTOM_BAR_H`, 아래끝 = 뷰포트 바닥.
##     바가 `safe` 안에 있으면 `offset_bottom = +인셋`, 밖(뷰포트 바닥에 붙은 판)이면
##     `offset_top = -(BOTTOM_BAR_H + 인셋)`. 바는 아래 넓게 앵커(anchor_top = 1)여야 한다.
##   - 바 안의 버튼(바가 곧 버튼이면 그 버튼)마다 `fit_bar_button`.
## 다시 불러도 같은 결과다(값을 더하지 않고 정한다).
static func fit_bottom_bar(bar: Control, safe: Control = null) -> void:
	if bar == null:
		return
	var below: float = bottom_inset()
	var in_safe: bool = false
	if safe != null:
		safe.offset_bottom = -below
		in_safe = safe.is_ancestor_of(bar)
	bar.offset_top = -BOTTOM_BAR_H - (0.0 if in_safe else below)
	bar.offset_bottom = below if in_safe else 0.0
	if bar is Button:
		fit_bar_button(bar as Button)
		return
	for c in bar.get_children():
		if c is Button:
			fit_bar_button(c as Button)


## 바 한 칸의 글자를 인셋만큼 위로 물린다(색면은 인셋 아래까지). 버튼의 변형은
## `BAR_BUTTON_VARIATIONS` 중 하나여야 한다. **칸의 종류가 바뀌면**(시간 경과의
## "경기 시작" = `BarDarkButton`) `theme_type_variation` 을 바꾼 뒤 이것을 다시 부른다.
static func fit_bar_button(b: Button) -> void:
	if b == null:
		return
	var v: String = String(b.theme_type_variation)
	if not BAR_BUTTON_VARIATIONS.has(v):
		push_warning("OutgameTheme.fit_bar_button: %s 의 변형 '%s' 는 Bar*Button 이 아니다"
				% [b.name, v])
		return
	var below: float = bottom_inset()
	if below <= 0.0:
		for n in BUTTON_STATES:
			b.remove_theme_stylebox_override(n)
		return
	var boxes: Dictionary = bar_button_styles(String(BAR_BUTTON_VARIATIONS[v]), below)
	for n in BUTTON_STATES:
		b.add_theme_stylebox_override(n, boxes[n])


# ── 자주 쓰는 조각 ───────────────────────────────────────────────────────────

## 화면 바탕 한 장. `_build()` 첫 줄에서 부른다 —
## `ScreenMetrics.extend_background` 까지 여기서 해 주므로 노치 자리에
## 엔진 기본 회색이 남는 사고를 화면마다 다시 막을 필요가 없다.
## 씬의 바탕과 같은 `ScreenBackground` 변형 `Panel` 이다(테마를 직접 물려 트리 밖에서도 맞다).
static func add_background(parent: Control) -> Panel:
	var bg := Panel.new()
	bg.theme = load(THEME_PATH)
	bg.theme_type_variation = &"ScreenBackground"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ScreenMetrics.extend_background(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg


## 카드 판 한 장을 붙인다. 반환값은 그 `Panel` 이라 자식은 로컬 좌표로 얹는다.
static func add_card(parent: Control, pos: Vector2, sz: Vector2,
		radius: int = 18, tint: Variant = null) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", card_style(radius, tint))
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


## 가로 구분선.
static func add_divider(parent: Control, pos: Vector2, w: float,
		color: Color = BORDER) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = Vector2(w, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## 원형으로 잘린 초상화.
##
## **`clip_contents` 로는 못 만든다** — 그것은 Control 의 사각 rect 로 자르지
## StyleBox 의 모서리 반지름으로 자르지 않는다. `Panel`(radius = 지름/2) 안에
## `TextureRect` 를 넣어 봐야 텍스처가 둥근 모서리를 그대로 덮어 **모서리만 살짝
## 둥근 사각형**이 나온다(실측). 그래서 텍스처를 입힌 **원형 폴리곤**을 직접
## 그린다 — `draw_colored_polygon(points, WHITE, uvs, tex)`.
##
## UV 는 `KEEP_ASPECT_COVERED` 와 같게 잡는다: 짧은 쪽을 꽉 채우고 긴 쪽은
## 가운데를 잘라 낸다. 그래야 정사각이 아닌 컷을 넘겨도 얼굴이 안 늘어난다.
##
## 반환값은 자식을 얹어도 되는 `Control` 이다 — Control 의 `_draw` 는 자식보다
## **먼저** 나가므로 원이 배경, 자식이 그 위다.
static func add_round_portrait(parent: Control, tex: Texture2D,
		pos: Vector2, diameter: float,
		ring: Variant = null) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = Vector2(diameter, diameter)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	holder.draw.connect(_draw_round_portrait.bind(holder, tex, diameter, ring))
	return holder


static func _draw_round_portrait(node: Control, tex: Texture2D,
		diameter: float, ring: Variant) -> void:
	const SEGMENTS: int = 48
	var r: float = diameter * 0.5
	var centre := Vector2(r, r)
	node.draw_circle(centre, r, SURFACE_SUNK)
	if tex != null:
		var ts: Vector2 = tex.get_size()
		# cover: 짧은 축을 1.0 으로, 긴 축은 그 비율만큼 가운데를 쓴다.
		var scale_uv := Vector2(1.0, 1.0)
		if ts.x > 0.0 and ts.y > 0.0:
			if ts.x > ts.y:
				scale_uv.x = ts.y / ts.x
			else:
				scale_uv.y = ts.x / ts.y
		var origin := (Vector2.ONE - scale_uv) * 0.5
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in SEGMENTS:
			var a: float = TAU * float(i) / float(SEGMENTS)
			var off := Vector2(cos(a), sin(a)) * r
			pts.append(centre + off)
			uvs.append(origin + (centre + off) / diameter * scale_uv)
		node.draw_colored_polygon(pts, Color(1, 1, 1), uvs, tex)
	if ring is Color:
		node.draw_arc(centre, r - 1.5, 0.0, TAU, SEGMENTS, ring, 3.0, true)


## 작은 알약형 칩 (`3승 1패`, `T01`, `+2` 같은 것).
static func add_chip(parent: Control, text: String, pos: Vector2,
		sz: Vector2, bg: Color, fg: Color, font_size: int = 20) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", flat_style(bg, int(sz.y * 0.5)))
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var l := UiHelpers.mk_label(p, text, font_size, fg,
			Vector2(0, 0), sz, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return p


## 스크롤 컨테이너 한 장 — 세로만 스크롤. 반환값은
## `{scroll: ScrollContainer, body: Control, drag: DragScroll}` 이고 내용은 `body` 에 절대
## 좌표로 얹은 뒤 `body.custom_minimum_size.y` 로 높이를 알려 준다.
static func add_vscroll(parent: Control, pos: Vector2, sz: Vector2) -> Dictionary:
	var sc := ScrollContainer.new()
	sc.position = pos
	sc.size = sz
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(sc)
	var body := Control.new()
	body.custom_minimum_size = Vector2(sz.x, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(body)
	# 손가락 / 마우스로 끌어 굴린다 — 엔진의 터치 드래그 대신(`DragScroll`).
	var drag := DragScroll.attach(sc)
	return {"scroll": sc, "body": body, "drag": drag}


# ── 공용 Theme 리소스 (`OutgameTheme.tres`) ──────────────────────────────────
#
# 씬(.tscn)으로 옮긴 아웃게임 UI 는 스타일을 코드로 입히지 않고 **테마 변형**
# (`theme_type_variation`)을 고른다. 그 변형들의 정본이 이 함수다 — 위의 색 상수와
# 스타일박스 공장을 그대로 불러 만들므로 코드 버튼과 씬 버튼이 같은 픽셀이 된다.
# `OutgameThemeBuilder.gd`(에디터 File → Run) / `OutgameThemeBuildCli.gd`(헤드리스)가
# 이 결과를 `THEME_PATH` 에 저장한다. **`.tres` 를 손으로 고치지 않는다.**

## 버튼 변형 이름 → `button_spec` 종류.
const BUTTON_VARIATIONS: Dictionary = {
	"PrimaryButton": "primary",
	"GhostButton": "ghost",
	"TextButton": "text",
	"DarkButton": "dark",
	"DangerButton": "danger",
}

## 하단 바 버튼 변형 이름 → `button_spec` 종류. 위 버튼과 같은 색 · 글자에 모서리 0
## (`bar_button_styles`) — 바의 칸으로만 쓴다(`fit_bottom_bar`).
const BAR_BUTTON_VARIATIONS: Dictionary = {
	"BarPrimaryButton": "primary",
	"BarGhostButton": "ghost",
	"BarDarkButton": "dark",
}


## 선택형 카드 · 타일의 판 한 장(`SELECT_*` 상수). 안쪽 여백 0.
static func selectable_box(on: bool, radius: int, border_on: int) -> StyleBoxFlat:
	var sb := flat_style(ACCENT_DIM if on else SURFACE, radius,
			ACCENT if on else BORDER, border_on if on else SELECT_BORDER)
	sb.set_content_margin_all(0.0)
	return sb


static func build_theme() -> Theme:
	var th := Theme.new()

	for v in BUTTON_VARIATIONS:
		var kind: String = BUTTON_VARIATIONS[v]
		_add_button(th, v, int(button_spec(kind)["font"]), button_spec(kind)["fg"],
				button_styles(kind))
	for v in BAR_BUTTON_VARIATIONS:
		var kind: String = BAR_BUTTON_VARIATIONS[v]
		_add_button(th, v, int(button_spec(kind)["font"]), button_spec(kind)["fg"],
				bar_button_styles(kind))
	# 바 칸 사이의 2px 세로선 (ColorRect 대신 Panel 에 이 변형).
	_add_panel(th, "BarSeparator", &"Panel", flat_style(BOTTOM_BAR_SEP, 0), 0.0)

	# 선택형 — 판 전체가 누르는 자리. 상태(일반 / 선택)는 코드가 변형 이름을 바꿔 고른다.
	_add_panel(th, "SelectableCard", &"PanelContainer",
			selectable_box(false, CARD_RADIUS, SELECT_BORDER_ON), 0.0)
	_add_panel(th, "SelectableCardOn", &"PanelContainer",
			selectable_box(true, CARD_RADIUS, SELECT_BORDER_ON), 0.0)
	_add_button(th, "SelectableCardButton", FONT_BTN_TEXT, TEXT,
			_selectable_states(false, CARD_RADIUS, SELECT_BORDER_ON))
	_add_button(th, "SelectableCardButtonOn", FONT_BTN_TEXT, TEXT,
			_selectable_states(true, CARD_RADIUS, SELECT_BORDER_ON))
	_add_button(th, "SelectableTile", FONT_BTN_TEXT, TEXT_SUB,
			_selectable_states(false, SELECT_TILE_RADIUS, SELECT_TILE_BORDER_ON))
	th.set_color(&"font_hover_color", &"SelectableTile", TEXT)
	_add_button(th, "SelectableTileOn", FONT_BTN_TEXT, ACCENT_TEXT,
			_selectable_states(true, SELECT_TILE_RADIUS, SELECT_TILE_BORDER_ON))

	_add_panel(th, "AccentChip", &"PanelContainer", flat_style(ACCENT_DIM, CHIP_RADIUS),
			CHIP_PAD_H, CHIP_PAD_V)
	_add_panel(th, "SurfaceChip", &"PanelContainer", flat_style(SURFACE, CHIP_RADIUS),
			CHIP_PAD_H, CHIP_PAD_V)

	_add_panel(th, "Card", &"PanelContainer", card_style(CARD_RADIUS), CARD_PAD)
	_add_panel(th, "PopupCard", &"PanelContainer", card_style(POPUP_RADIUS), POPUP_PAD)
	_add_panel(th, "PopupCardWide", &"PanelContainer", card_style(POPUP_RADIUS), POPUP_PAD_WIDE)
	_add_panel(th, "SheetCard", &"PanelContainer", card_style(SHEET_RADIUS), SHEET_PAD, SHEET_PAD_V)
	_add_panel(th, "SunkPanel", &"PanelContainer", flat_style(SURFACE_SUNK, SUNK_RADIUS), 0.0)
	_add_panel(th, "DimPanel", &"Panel", flat_style(DIM, 0), 0.0)
	_add_panel(th, "ProgressTrack", &"Panel", flat_style(SURFACE_SUNK, BAR_RADIUS), 0.0)
	_add_panel(th, "ProgressFill", &"Panel", flat_style(ACCENT, BAR_RADIUS), 0.0)

	_add_label(th, "HeadingLabel", FONT_HEADING, TEXT)
	_add_label(th, "TitleLabel", FONT_TITLE, TEXT)
	_add_label(th, "BodyLabel", FONT_BODY, TEXT)
	_add_label(th, "SubLabel", FONT_BODY, TEXT_SUB)
	_add_label(th, "CaptionLabel", FONT_CAPTION, TEXT_SUB)
	_add_label(th, "FaintLabel", FONT_CAPTION, TEXT_FAINT)
	_add_label(th, "AccentLabel", FONT_CAPTION, ACCENT_TEXT)
	_add_label(th, "OnFillLabel", FONT_CAPTION, TEXT_ON_FILL)
	_add_label(th, "NegativeLabel", FONT_CAPTION, NEGATIVE)
	_add_label(th, "PositiveLabel", FONT_CAPTION, POSITIVE)
	_add_label(th, "LinkLabel", FONT_CAPTION, LINK)
	_add_label(th, "RailLabel", FONT_CAPTION, RAIL_TEXT)   # 어두운 레일(`RAIL`) 위 회색 글자

	# 색면(배너 · 칩) 위 텍스트 버튼 — `TextButton` 모양에 글자만 흰색.
	th.set_type_variation(&"OnFillTextButton", &"TextButton")
	for c in BUTTON_FONT_COLORS:
		th.set_color(c, &"OnFillTextButton", TEXT_ON_FILL)

	# 화면 바탕 한 장(전체 화면 `Panel`) — 배경색의 정본.
	_add_panel(th, "ScreenBackground", &"Panel", flat_style(BG, 0), 0.0)

	# 선 끝을 늘리지 않는다(grow 0) — `add_divider` 처럼 노드 폭과 정확히 같은 1px 선.
	var line := StyleBoxLine.new()
	line.color = BORDER
	line.thickness = 1
	line.grow_begin = 0.0
	line.grow_end = 0.0
	th.set_type_variation(&"Divider", &"HSeparator")
	th.set_stylebox(&"separator", &"Divider", line)
	th.set_constant(&"separation", &"Divider", 1)

	_add_screen_variations(th)
	return th


# ── 화면 전용 변형 ───────────────────────────────────────────────────────────
# 한 화면(씬)에서만 쓰는 모양도 씬의 로컬 스타일박스로 두지 않고 여기서 변형으로 만든다.
# 이름 규칙: **`<쓰는 씬><역할>`** (접두사 = 그 모양을 쓰는 씬 이름) — 이름만 보고 어느 씬의
# 것인지 안다. 기반(base)은 가장 가까운 **공용 변형**이라 "어느 공용 모양에서 파생됐나"가
# 테마에 남는다(Godot 변형은 사슬로 이어진다 — 스타일박스는 통째로 덮고, 글자색 · 크기 등
# 나머지 항목은 기반에서 물려받는다).
# 색이 데이터인 것(역할 · 진영 · 등급 색)은 변형이 **모양 + 미리보기 색**을 갖고, 코드는
# `variation_box()` 사본에 색만 넣는다.
static func _add_screen_variations(th: Theme) -> void:
	# match_flow/ban_pick — 밴픽
	_add_derived(th, "BanPickBanChipPanel", &"SunkPanel", flat_style(SURFACE_SUNK, 0, BORDER, 1))
	# 메크 칸 테두리 = 진영 색(데이터, `BanPickMechSlot.setup`) — 여기 색은 미리보기.
	_add_derived(th, "BanPickMechSlotFrame", &"SunkPanel",
			flat_style(SURFACE_SUNK, 5, LINK.lerp(SURFACE, 0.55), 2))
	# 초상화 테두리 = 진영 색(데이터, `BanPickPortrait.setup`).
	_add_derived(th, "BanPickPortraitRim", &"SunkPanel", flat_style(Color(0, 0, 0, 0), 0, LINK, 2))
	var sheet := card_style(CARD_RADIUS)
	sheet.border_color = ACCENT
	sheet.set_border_width_all(3)
	_add_derived(th, "BanPickSheetCard", &"Card", sheet)
	_add_derived(th, "BanPickDragGhost", &"SunkPanel", flat_style(SURFACE_SUNK, 5, ACCENT, 3))

	# 진행 순서 칸 — 칸 색 = 진영 · 상태(데이터), 캡슐 안쪽 모서리는 코드가 사본에서 각지게.
	_add_derived(th, "BanPickOrderPip", &"SunkPanel", flat_style(SURFACE_SUNK, 6))

	# match_flow/match_prep — 분석가 메모 (MatchPrep · 리그 팀 상세)
	_add_derived(th, "IntelAnalystNote", &"SunkPanel", flat_style(ACCENT_DIM, 14))
	# PREP pilot card (`UI_Comp_MatchPrepPilotCard`): the card itself (no padding — the scene
	# places its parts), the embedded `SeasonPilotCard` drawn without its own card, the red
	# "경계 대상" chip and the small mech chips.
	_add_derived(th, "MatchPrepPilotCard", &"Card", card_style(CARD_RADIUS))
	_add_derived(th, "MatchPrepCardInner", &"Card", StyleBoxEmpty.new())
	var warn := flat_style(NEGATIVE, CHIP_RADIUS)
	warn.content_margin_left = 10.0
	warn.content_margin_right = 10.0
	warn.content_margin_top = 2.0
	warn.content_margin_bottom = 2.0
	_add_derived(th, "MatchPrepWarnChip", &"AccentChip", warn)
	var mech_chip := flat_style(SURFACE_SUNK, 8)
	mech_chip.content_margin_left = 4.0
	mech_chip.content_margin_right = 4.0
	mech_chip.content_margin_top = 2.0
	mech_chip.content_margin_bottom = 2.0
	_add_derived(th, "MatchPrepMechChip", &"SunkPanel", mech_chip)

	# meta/collection · meta/manager — 컬렉션 칸 · 프리셋 칩 · 특성 블록 (R2a)
	# 버튼 판은 상태마다 같은 판 — 상태(보유 · 선택 · 장착 · 잠김 · 칸 초과)는 코드가 이름만 바꾼다.
	var r2a_buttons := {
		"CollectionCellFrame": [&"SelectableCardButton", flat_style(SURFACE, 16, BORDER_STRONG, 2)],
		"ManagerPresetChip": [&"SelectableCardButton", flat_style(SURFACE, 16, BORDER, 2)],
		"ManagerPresetChipOn": [&"SelectableCardButtonOn", flat_style(ACCENT_DIM, 16, ACCENT, 4)],
		"TraitPickerSlot": [&"SelectableCardButton", flat_style(SURFACE, 14, BORDER_STRONG, 2)],
		"TraitPickerSlotOver": [&"SelectableCardButton", flat_style(SURFACE, 14, NEGATIVE, 2)],
		"TraitPickerRow": [&"SelectableCardButton", flat_style(SURFACE, 16, BORDER, 1)],
		"TraitPickerRowOn": [&"SelectableCardButtonOn", flat_style(ACCENT_DIM, 16, ACCENT, 3)],
		"TraitPickerRowLocked": [&"SelectableCardButton", flat_style(BG, 16, BORDER, 1)],
	}
	for v in r2a_buttons:
		th.set_type_variation(v, r2a_buttons[v][0])
		for n in BUTTON_STATES:
			th.set_stylebox(n, v, r2a_buttons[v][1])
	_add_derived(th, "CollectionCellArtMask", &"SunkPanel", _mask_box(12))
	# Thumbnail corner tabs (inside the clipped ArtMask, flush with its bottom edge): level ribbon
	# bottom-left (amber, rounded top-right), rank stars bottom-right (dark plate, rounded top-left).
	var ribbon := flat_style(ACCENT, 0)
	ribbon.corner_radius_top_right = 12
	ribbon.content_margin_left = 12.0
	ribbon.content_margin_right = 12.0
	ribbon.content_margin_top = 1.0
	ribbon.content_margin_bottom = 1.0
	_add_derived(th, "CollectionCellLevelRibbon", &"AccentChip", ribbon)
	var plate := flat_style(Color(RAIL, 0.78), 0)
	plate.corner_radius_top_left = 12
	plate.content_margin_left = 10.0
	plate.content_margin_right = 8.0
	plate.content_margin_top = 1.0
	plate.content_margin_bottom = 1.0
	_add_derived(th, "CollectionCellRankPlate", &"SurfaceChip", plate)
	# Rank stars: reached = amber, unlocked by breakthrough but not reached = faint white.
	th.set_type_variation(&"CollectionCellStarOn", &"OnFillLabel")
	th.set_color(&"font_color", &"CollectionCellStarOn", ACCENT)
	th.set_type_variation(&"CollectionCellStar", &"OnFillLabel")
	th.set_color(&"font_color", &"CollectionCellStar", Color(TEXT_ON_FILL, 0.38))
	_add_derived(th, "TraitPickerGauge", &"SelectableCard", flat_style(SURFACE, 16, BORDER, 1))
	_add_derived(th, "TraitPickerGaugeBad", &"ManagerDangerCard",
			flat_style(SURFACE.lerp(NEGATIVE, 0.12), 16, NEGATIVE, 3))
	_add_derived(th, "TraitPickerSlotEmpty", &"SunkPanel", flat_style(SURFACE_SUNK, 14, BORDER, 1))
	_add_derived(th, "TraitPickerLayerChip", &"SurfaceChip", flat_style(SURFACE_SUNK, CHIP_RADIUS))
	_add_derived(th, "TraitPickerNewChip", &"AccentChip", flat_style(NEGATIVE, CHIP_RADIUS))
	_add_derived(th, "TraitPickerEquippedChip", &"AccentChip", flat_style(ACCENT, CHIP_RADIUS))

	# meta/manager — 감독 탭 프레스티지 리셋
	_add_derived(th, "ManagerDangerCard", &"Card",
			flat_style(SURFACE.lerp(NEGATIVE, 0.12), 16, NEGATIVE, 2))

	# meta/run_result — 런 정산
	for v in ["RunResultSectionCard", "RunResultSectionCardAmber"]:
		var sec := card_style(24, ACCENT_DIM if v.ends_with("Amber") else null)
		sec.set_content_margin_all(40.0)
		sec.content_margin_top = 28.0
		_add_derived(th, v, &"Card", sec)
	_add_derived(th, "RunResultTraitCard", &"Card", card_style(16))
	var amber_line := StyleBoxLine.new()
	amber_line.color = ACCENT
	amber_line.thickness = 1
	amber_line.grow_begin = 0.0
	amber_line.grow_end = 0.0
	_add_derived(th, "RunResultAccentDivider", &"Divider", amber_line, &"separator")

	# meta/run_setup — 런 준비
	# 편성 칸 테두리: 빈 칸 = 이 모양, 찬 칸 = 역할 색(데이터, `DraftSlot._set_frame_style`).
	var slot := flat_style(SURFACE_SUNK, 14, BORDER, 3)
	th.set_type_variation(&"DraftSlotFrame", &"SelectableCardButton")
	for n in BUTTON_STATES:
		th.set_stylebox(n, &"DraftSlotFrame", slot)
	_add_derived(th, "DraftSlotArtMask", &"SunkPanel", _mask_box(11))
	_add_derived(th, "PilotThumbArtMask", &"SunkPanel", _mask_box(14))
	_add_derived(th, "PilotThumbCheck", &"AccentChip", flat_style(ACCENT, 20))
	_add_derived(th, "PilotThumbTag", &"SurfaceChip", flat_style(RAIL, 17))
	# resources/PositionBadge — 포지션 배지 = 역할 색(데이터, `PositionBadge.set_role`) — 여기 색은 탑 미리보기.
	var pos_badge := flat_style((ROLE_COLORS[0] as Color).darkened(0.15), 8, POSITION_BADGE_EDGE, 1)
	pos_badge.content_margin_left = POSITION_BADGE_PAD_H
	pos_badge.content_margin_right = POSITION_BADGE_PAD_H
	pos_badge.content_margin_top = POSITION_BADGE_PAD_V
	pos_badge.content_margin_bottom = POSITION_BADGE_PAD_V
	_add_derived(th, "PositionBadgePanel", &"AccentChip", pos_badge)
	# 단계 알약 = 상태 색(`StepChip.paint`) — 여기 색은 "지금 단계" 미리보기.
	_add_derived(th, "StepChipPanel", &"AccentChip", flat_style(ACCENT, CHIP_RADIUS))
	_add_derived(th, "TeamDraftGridBack", &"Card", flat_style(SURFACE, 12, BORDER, 2))

	# meta/shop — 상점
	_add_derived(th, "ShopRowPanel", &"Card", flat_style(SURFACE, CARD_RADIUS, BORDER, 1))
	# 배너 색면 = 뽑기 풀(데이터, `ShopTab._fill_gacha`) — 여기 색은 선수 영입.
	_add_derived(th, "ShopBannerCard", &"Card", card_style(24, CARD_TINTS[3]))
	_add_derived(th, "ShopDevRowPanel", &"SunkPanel",
			flat_style(SURFACE_SUNK, CARD_RADIUS, BORDER, 1))

	# season/training — 훈련 (테두리 · 띠 색 = 등급 / 역할 색, 코드가 사본에 넣는다)
	_add_derived(th, "TrainingCourseCardFrame", &"Card", flat_style(SURFACE, 12, CARD_TINTS[0], 2))
	var band := flat_style(Color(CARD_TINTS[0], 0.22), 0)
	band.corner_radius_top_left = 12
	band.corner_radius_top_right = 12
	_add_derived(th, "TrainingCourseGradeBand", &"SunkPanel", band)
	_add_derived(th, "TrainingCourseShapeWell", &"SunkPanel", flat_style(SURFACE_SUNK, 8))
	var pop := flat_style(SURFACE, 10, CARD_TINTS[0], 2)
	pop.shadow_color = Color(SHADOW, 0.28)
	pop.shadow_size = 10
	_add_derived(th, "TrainingCoursePopoverFrame", &"PopupCard", pop)
	_add_derived(th, "TrainingThumbFrame", &"Card",
			flat_style(SURFACE, 8, Color(ROLE_COLORS[0], 0.85), 2))
	_add_derived(th, "TrainingThumbExpChip", &"AccentChip", flat_style(POSITIVE, 14))

	# season/week — 시간 경과
	_add_derived(th, "WeekRail", &"SunkPanel", flat_style(RAIL, 48))
	_add_derived(th, "WeekDayChip", &"AccentChip", flat_style(Color(0, 0, 0, 0), WEEK_DAY_CHIP_RADIUS))
	_add_derived(th, "WeekDayChipToday", &"AccentChip", flat_style(ACCENT, WEEK_DAY_CHIP_RADIUS))
	# 맵 토큰 위 말풍선 (오전: 그 시간의 훈련 이름)
	var bubble := flat_style(SURFACE, 14, BORDER_STRONG, 2)
	bubble.content_margin_left = 12.0
	bubble.content_margin_right = 12.0
	bubble.content_margin_top = 3.0
	bubble.content_margin_bottom = 3.0
	_add_derived(th, "WeekMapBubble", &"SurfaceChip", bubble)

	# season/press — 기자회견 메신저 (말풍선 안쪽 여백은 씬의 `Pad` MarginContainer)
	var npc := flat_style(SURFACE, 22, BORDER)
	npc.set_content_margin_all(0.0)
	_add_derived(th, "MessengerBubbleNpc", &"Card", npc)
	var mine := flat_style(ACCENT, 22)
	mine.set_content_margin_all(0.0)
	_add_derived(th, "MessengerBubbleMine", &"Card", mine)
	_add_derived(th, "MessengerNoteChipMuted", &"AccentChip", flat_style(SURFACE_SUNK, CHIP_RADIUS))
	th.set_type_variation(&"MessengerAnswerButton", &"GhostButton")
	var ghost: Dictionary = button_styles("ghost")
	for n in BUTTON_STATES:
		var b: StyleBox = (ghost[n] as StyleBox).duplicate()
		b.content_margin_left = 22.0
		b.content_margin_right = 22.0
		b.content_margin_top = 17.0
		b.content_margin_bottom = 17.0
		th.set_stylebox(n, &"MessengerAnswerButton", b)

	# season/mental: 면담 · 외출 비주얼 노벨 대화 (말풍선 안쪽 여백은 씬의 `Pad` MarginContainer)
	var vn_bubble := card_style(28)
	vn_bubble.set_content_margin_all(0.0)
	_add_derived(th, "VnDialogueBubble", &"Card", vn_bubble)
	var vn_plate := flat_style(ACCENT, 14)
	vn_plate.content_margin_left = 20.0
	vn_plate.content_margin_right = 20.0
	vn_plate.content_margin_top = 6.0
	vn_plate.content_margin_bottom = 6.0
	_add_derived(th, "VnDialogueNamePlate", &"AccentChip", vn_plate)
	var vn_plate_mine: StyleBoxFlat = vn_plate.duplicate()
	vn_plate_mine.bg_color = RAIL
	_add_derived(th, "VnDialogueNamePlateMine", &"AccentChip", vn_plate_mine)
	_add_derived(th, "VnDialogueArtSlab", &"SunkPanel", flat_style(SURFACE_SUNK, 24, BORDER))
	th.set_type_variation(&"VnDialogueChoiceButton", &"GhostButton")
	for n in BUTTON_STATES:
		var c: StyleBox = (ghost[n] as StyleBox).duplicate()
		c.content_margin_left = 28.0
		c.content_margin_right = 28.0
		c.content_margin_top = 24.0
		c.content_margin_bottom = 24.0
		th.set_stylebox(n, &"VnDialogueChoiceButton", c)

	# season/calendar — 페이즈 시작 타이틀 카드 (`UI_View_PhaseIntro`): 화면 전체를 덮는 어두운 판.
	_add_derived(th, "PhaseIntroBackdrop", &"ScreenBackground", flat_style(RAIL, 0))
	# season/facility — 시설 화면 토스트(업그레이드 불가 사유 등): 본문 위에 떠도 읽히는 어두운 알약.
	_add_derived(th, "FacilityViewToast", &"SurfaceChip", flat_style(RAIL, 34))

	# meta/lobby — 로비
	_add_derived(th, "LobbyToast", &"SurfaceChip", flat_style(RAIL, 34))
	# Floating nav capsule (dark pill + shadow) and the white inner selector pill that slides.
	var nav := flat_style(RAIL, 999)
	nav.shadow_color = Color(SHADOW, 0.30)
	nav.shadow_size = 18
	nav.shadow_offset = Vector2(0, 6)
	_add_derived(th, "LobbyNavCapsule", &"Card", nav)
	_add_derived(th, "LobbyNavSelector", &"Card", flat_style(SURFACE, 999))
	# Top-left manager level disc (the radial EXP ring is a TextureProgressBar on top).
	_add_derived(th, "LobbyLevelDisc", &"Card", flat_style(RAIL, 999))
	# Top-right wallet: translucent black pill per currency (whole pill = button) + the
	# accent "+" disc on the premium one.
	var pill: Dictionary = {}
	for n in BUTTON_STATES:
		pill[n] = flat_style(Color(0, 0, 0, 0.62 if n in ["pressed", "hover_pressed"] else 0.5), 999)
	pill["focus"] = button_box(Color(0, 0, 0, 0), null)
	_add_button(th, "LobbyCurrencyPill", FONT_BODY, TEXT_ON_FILL, pill)
	_add_derived(th, "LobbyCurrencyPlus", &"Card", flat_style(ACCENT, 999))

	# meta/manager — 감독 modal sheet (rounded top, runs to the screen bottom; BG so the
	# tab's white cards stand out).
	var mgr_sheet := flat_style(BG, SHEET_RADIUS)
	mgr_sheet.corner_radius_bottom_left = 0
	mgr_sheet.corner_radius_bottom_right = 0
	_add_derived(th, "ManagerPopupSheet", &"Card", mgr_sheet)

	# meta/shop — currency shop popup: product tile (white card button) + its price pill.
	_add_button(th, "CurrencyShopTile", FONT_BTN_TEXT, TEXT,
			_selectable_states(false, CARD_RADIUS, SELECT_BORDER_ON))
	_add_derived(th, "CurrencyShopPrice", &"SunkPanel", flat_style(SURFACE_SUNK, 999))
	_add_derived(th, "CurrencyShopPriceCash", &"SunkPanel", flat_style(ACCENT, 999))

	# --- B week UI rework ---
	# season — the round black masks over a stat gauge ring (`UI_Comp_PilotGauge` %Mask, ring
	# 42 → r 21) / a map token (portrait circle = r 42) whose pilot cannot be picked.
	_add_derived(th, "PilotGaugeMask", &"DimPanel", flat_style(Color(0, 0, 0, 0.62), 21))
	_add_derived(th, "WeekMapPilotMask", &"DimPanel", flat_style(Color(0, 0, 0, 0.62), 42))
	# season/week — the afternoon visit menu as a speech bubble over the picked token
	# (`UI_View_VisitMenu`; the tail polygons in the scene use the same SURFACE / BORDER_STRONG).
	var visit := flat_style(SURFACE, 28, BORDER_STRONG, 2)
	visit.shadow_color = Color(SHADOW, 0.22)
	visit.shadow_size = 14
	visit.shadow_offset = Vector2(0, 4)
	visit.content_margin_left = 32.0
	visit.content_margin_right = 32.0
	visit.content_margin_top = 28.0
	visit.content_margin_bottom = 28.0
	_add_derived(th, "VisitMenuBubble", &"PopupCard", visit)

	# --- C week UI rework ---
	# season/mental — event result panel (`UI_Comp_EventResultPanel`): compact stat chip on the
	# white popup card (sunk pill, the SurfaceChip padding).
	var er_chip: StyleBoxFlat = (th.get_stylebox(&"panel", &"SurfaceChip") as StyleBoxFlat).duplicate()
	er_chip.bg_color = SURFACE_SUNK
	_add_derived(th, "EventResultChip", &"SurfaceChip", er_chip)

	# --- Z week UI rework ---
	# season — `SeasonPilotCard` root without a card (portrait and gauges sit on the page;
	# hub roster · week row · detail sheet head · own PREP card).
	_add_derived(th, "SeasonPilotCardBare", &"Card", StyleBoxEmpty.new())

	# --- U level merge ---
	# season — `SeasonPilotDetail` 깨달음 level bar fill in the card ring's colour: LINK while the
	# bar fills (this variation), the plain `ProgressFill` (ACCENT) while capped (code switches).
	_add_derived(th, "SeasonPilotDetailLevelFill", &"ProgressFill", flat_style(LINK, BAR_RADIUS))


## 둥근 그림 마스크(`clip_children` 부모가 그리는 흰 판).
static func _mask_box(radius: int) -> StyleBoxFlat:
	var sb := flat_style(Color.WHITE, radius)
	sb.anti_aliasing = true
	return sb


## 화면 전용 변형 한 개 — 공용 변형 `base` 에서 파생, 스타일박스 하나(`item`)만 덮는다.
## 안쪽 여백은 건드리지 않는다(상자가 정한 값 그대로).
static func _add_derived(th: Theme, variation: String, base: StringName, sb: StyleBox,
		item: StringName = &"panel") -> void:
	th.set_type_variation(variation, base)
	th.set_stylebox(item, variation, sb)


## 테마 변형의 스타일박스 **사본** — 색이 데이터인 화면 전용 변형(`BanPickMechSlotFrame` …)에
## 코드가 색만 넣을 때 쓴다. 테마 파일에서 바로 읽으므로 노드가 트리에 들어가기 전에도 맞다
## (`get_theme_stylebox` 는 트리 밖에서 기본 테마로 떨어진다).
static func variation_box(variation: StringName, item: StringName = &"panel") -> StyleBoxFlat:
	var th: Theme = load(THEME_PATH)
	return th.get_stylebox(item, variation).duplicate() as StyleBoxFlat


## `build_theme()` 결과를 `THEME_PATH` 에 저장한다. 빌더 두 입구가 부른다.
## 다시 돌려도 diff 가 실제 바뀐 값만 보이도록 sub_resource id 는 `변형_상태` 로
## 고정하고, 파일 uid 는 이미 있던 것을 이어 쓴다(씬의 `ext_resource` 가 uid 로 찾는다).
static func save_theme() -> Error:
	var th: Theme = build_theme()
	for t in th.get_stylebox_type_list():
		for n in th.get_stylebox_list(t):
			th.get_stylebox(n, t).resource_scene_unique_id = "%s_%s" % [t, n]
	var uid: int = ResourceLoader.get_resource_uid(THEME_PATH) \
			if ResourceLoader.exists(THEME_PATH) else ResourceUID.INVALID_ID
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var err: Error = ResourceSaver.save(th, THEME_PATH)
	if err == OK:
		err = ResourceSaver.set_uid(THEME_PATH, uid)
	if err != OK:
		push_error("OutgameTheme: %s 저장 실패 (%d)" % [THEME_PATH, err])
	return err


## 버튼 변형 한 벌 — 글자 크기, 글자색(`BUTTON_FONT_COLORS` 전부 `fg`, 비활성은
## `TEXT_FAINT`), 상태별 스타일박스(`BUTTON_STATES` 키).
static func _add_button(th: Theme, variation: String, font_size: int, fg: Color,
		boxes: Dictionary) -> void:
	th.set_type_variation(variation, &"Button")
	th.set_font_size(&"font_size", variation, font_size)
	for c in BUTTON_FONT_COLORS:
		th.set_color(c, variation, fg)
	th.set_color(&"font_disabled_color", variation, TEXT_FAINT)
	for n in BUTTON_STATES:
		th.set_stylebox(n, variation, boxes[n])


## 선택형 버튼의 상태들 — 누르든 올리든 같은 판(상태는 일반 / 선택 변형이 말한다),
## 포커스는 빈 판(`button_styles` 와 같다).
static func _selectable_states(on: bool, radius: int, border_on: int) -> Dictionary:
	var out: Dictionary = {}
	for n in BUTTON_STATES:
		out[n] = selectable_box(on, radius, border_on)
	out["focus"] = button_box(Color(0, 0, 0, 0), null)
	return out


static func _add_panel(th: Theme, variation: String, base: StringName,
		sb: StyleBoxFlat, pad: float, pad_v: float = -1.0) -> void:
	sb.set_content_margin_all(pad)
	if pad_v >= 0.0:
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
	th.set_type_variation(variation, base)
	th.set_stylebox(&"panel", variation, sb)


static func _add_label(th: Theme, variation: String, font_size: int, color: Color) -> void:
	th.set_type_variation(variation, &"Label")
	th.set_font_size(&"font_size", variation, font_size)
	th.set_color(&"font_color", variation, color)
