class_name BattleTheme
extends RefCounted

# ── 인게임(BattleSim) 어두운 팔레트 ─────────────────────────────────────────
#
# **전장 UI 의 색 · 글자 크기 · 모서리가 여기를 지난다.** HUD(`HudBuilder`) · 파일럿
# 스트립(`PilotStrip`) · 상세 패널(`PilotDetailPanel`) · 스킬 말풍선(`SkillPopup`) ·
# MVP 뷰(`MvpView`)가 같은 표를 읽는다. 아웃게임(`OutgameTheme`)과 짝을 이루지만
# 원칙이 반대다 — 전장은 어두운 화면이라 흰 카드는 눈부신 판이 된다:
#   1. 판은 **반투명한 남색**(`PANEL_BG` · `POPUP_BG`) — 뒤의 전장이 살짝 비쳐
#      "전장 위에 뜬 정보"로 읽힌다. 결과처럼 전장을 끝내는 판만 불투명(`MODAL_BG`).
#   2. 경계는 옅은 푸른 회색 테두리(`PANEL_BORDER`), 강조는 **금색**(`GOLD`) 한 가지 —
#      MVP · 결과 화면 · "지금 눌러" 버튼.
#   3. 진영은 파랑(아군) / 빨강(상대) — `ALLY` · `ENEMY`(글자), `TEAM_*`(면).
#
# 값은 각 화면에 흩어져 있던 리터럴을 **그대로 옮긴 것**이다(렌더가 바뀌지 않게).
# 비슷하지만 다른 값(예: `TEXT_VALUE` / `TEXT_BRIGHT`)도 일부러 합치지 않았다 —
# 합치는 것은 디자인 결정이라 화면을 보고 따로 한다.
#
# 씬(.tscn)으로 옮긴 전투 UI 는 `BattleTheme.tres`(이 파일의 `build_theme()` 결과)를
# 붙이고 **변형**(`theme_type_variation`)을 고른다. `.tres` 는 손으로 고치지 않는다 —
# 여기를 고치고 `BattleThemeBuilder.gd`(에디터 File → Run) /
# `BattleThemeBuilderCli.gd`(헤드리스)로 다시 만든다. 목록 · 규칙: `resources/README.md`.

# ── 판 (배경 면) ─────────────────────────────────────────────────────────────
const PANEL_BG:      Color = Color(0.04, 0.05, 0.09, 0.86)   # 정보 판 (상세 패널 칸 · 머리글 · 스킬)
const PANEL_BORDER:  Color = Color(0.30, 0.34, 0.46, 0.70)   # 정보 판 · 자리 표시 판 테두리
const POPUP_BG:      Color = Color(0.05, 0.06, 0.11, 0.97)   # 말풍선 (SkillPopup) — 화살표도 이 색
const MODAL_BG:      Color = Color(0.05, 0.06, 0.10, 1.00)   # 결과 판 (불투명)
const GOLD_PANEL_BG: Color = Color(0.06, 0.07, 0.12, 0.92)   # MVP 정보 판
const MENU_BG:       Color = Color(0.08, 0.08, 0.12, 1.00)   # 칸 설명 판 (상세 패널)
## 칸 · 지속 효과 썸네일 — 일반 / 강조(눌러서 설명이 열린 칸).
const CHIP_BG:        Color = Color(0.10, 0.12, 0.18, 0.94)
const CHIP_BG_HL:     Color = Color(0.17, 0.22, 0.34, 0.98)
const CHIP_BORDER:    Color = Color(0.32, 0.36, 0.48, 0.80)
const CHIP_BORDER_HL: Color = Color(0.72, 0.86, 1.00, 0.95)
## 탭 — 켜짐 / 꺼짐.
const TAB_BG_ON:      Color = Color(0.16, 0.21, 0.34, 0.96)
const TAB_BG_OFF:     Color = Color(0.06, 0.07, 0.11, 0.80)
const TAB_BORDER_ON:  Color = Color(0.62, 0.80, 1.00, 0.95)
const TAB_BORDER_OFF: Color = Color(0.26, 0.29, 0.38, 0.65)
const BUTTON_BG:      Color = Color(0.16, 0.21, 0.34, 0.98)  # 금테 버튼 바탕 (MVP "계속")
## 그림 없는 자리 표시 판 — MVP 전신(진하게) / 상세 패널 전신(옅게 — 앞의 파일럿보다
## 눈에 띄면 안 된다).
const SLAB_BG:          Color = Color(0.14, 0.15, 0.20, 0.60)
const ART_SLAB_BG:      Color = Color(0.14, 0.15, 0.20, 0.30)
const ART_SLAB_BORDER:  Color = Color(0.42, 0.45, 0.56, 0.45)
const ART_BACK_TINT:    Color = Color(0.14, 0.14, 0.18, 0.88)  # 상세 패널 뒤에 선 전신
const FX_VALUE_BAND:    Color = Color(0.00, 0.00, 0.00, 0.62)  # 지속 효과 썸네일 아래 수치 띠

# ── 강조 · 딤 · 그림자 ───────────────────────────────────────────────────────
const GOLD:        Color = Color(1.00, 0.80, 0.30, 1.00)
const GOLD_BORDER: Color = Color(1.00, 0.80, 0.30, 0.75)   # MVP 판 · 결과 판 · 금테 버튼
const GLOW:        Color = Color(1.00, 0.80, 0.30, 0.28)   # MVP 전신 뒤 후광 (가운데)
const DIM:         Color = Color(0.00, 0.00, 0.00, 0.88)   # 상세 패널 딤
const DIM_DEEP:    Color = Color(0.02, 0.03, 0.06, 0.95)   # MVP 뷰 딤 (거의 불투명)
const DIM_LIGHT:   Color = Color(0.00, 0.00, 0.00, 0.65)   # 결과 판 뒤 딤
const SHADOW:      Color = Color(0.00, 0.00, 0.00, 0.45)   # 말풍선 그림자 (아래로만)
const OUTLINE:      Color = Color(0.00, 0.00, 0.00, 0.90)  # 판 없이 뜬 글자의 외곽선
const OUTLINE_SOFT: Color = Color(0.00, 0.00, 0.00, 0.85)  # 시계 · 차례 알림 외곽선

# ── 스킬 아이콘 타일 (`SkillImages.make_icon_tile`) ──────────────────────────
const SKILL_TILE_BG:     Color = Color(0.22, 0.26, 0.38)
const SKILL_TILE_ICON:   Color = Color(1.00, 0.94, 0.78)
const SKILL_TILE_SHADOW: Color = Color(0.00, 0.00, 0.00, 0.70)
const SKILL_KW_ICON:     Color = Color(0.55, 0.85, 1.00)   # 설명문 키워드 아이콘
const SKILL_KNOCK:       Color = Color(0.04, 0.05, 0.09)   # 아이콘 뚫림 색 = `PANEL_BG` 불투명

# ── 글자 ─────────────────────────────────────────────────────────────────────
# 밝은 순.
const TEXT_BRIGHT:      Color = Color(0.97, 0.97, 1.00)   # MVP 이름 · K/D/A
const TEXT_VALUE:       Color = Color(0.96, 0.96, 0.98)   # 칸 수치 · 설명 판 값
const TEXT_DESC:        Color = Color(0.88, 0.90, 0.95)   # 스킬 설명문
const TEXT_CLOCK:       Color = Color(0.85, 0.85, 0.85)   # 경과 시계
const TEXT_KDA:         Color = Color(0.80, 0.84, 0.92)   # 결과 판 MVP 줄 K/D/A
const TEXT_WAIT:        Color = Color(0.80, 0.82, 0.90)   # 스킬 상태 한 줄 (남은 턴 · 토큰)
const TEXT_PLACEHOLDER: Color = Color(0.78, 0.80, 0.88)   # 그림 없는 자리의 이름
const TEXT_NOTE:        Color = Color(0.72, 0.75, 0.84)   # 칸 설명 판 본문
const TEXT_SUB:         Color = Color(0.72, 0.78, 0.90)   # MVP 지표 줄 · 자리 표시 글자
const TEXT_KEY:         Color = Color(0.72, 0.74, 0.80)   # 칸 이름 · 꺼진 탭 · "스킬 없음"
const TEXT_TYPE:        Color = Color(0.70, 0.74, 0.84)   # 스킬 종류 · 쿨타임 수
const TEXT_MECH:        Color = Color(0.68, 0.74, 0.86)   # 상세 패널 메크 이름
# 색 있는 글자.
const TEXT_TITLE:   Color = Color(1.00, 0.85, 0.35)   # "MATCH MVP" · 결과 판 "MVP"
const TEXT_HEADER:  Color = Color(1.00, 0.92, 0.55)   # 상세 패널 이름 · 설명 판 제목
const TEXT_SKILL:   Color = Color(1.00, 0.88, 0.52)   # 스킬 이름
const TEXT_SCORE:   Color = Color(1.00, 0.94, 0.62)   # 스트립 성장치
const TEXT_SECTION: Color = Color(0.58, 0.78, 1.00)   # 상세 패널 섹션 머리
const TEXT_GROWTH:  Color = Color(0.72, 1.00, 0.80)   # 상세 패널 성장치
const TEXT_WARN:    Color = Color(1.00, 0.62, 0.62)   # 상세 패널 경고 줄
const ALLY:     Color = Color(0.55, 0.80, 1.00)   # 아군 (글자)
const ENEMY:    Color = Color(1.00, 0.55, 0.55)   # 상대 팀 (글자)
const POSITIVE: Color = Color(0.45, 0.90, 0.55)   # 기본값 대비 + (칸 보너스)
const NEGATIVE: Color = Color(0.98, 0.42, 0.42)   # 기본값 대비 −
const DEAD:     Color = Color(1.00, 0.55, 0.50)   # 스트립 부활까지 남은 턴

# ── 진영 면 (인덱스 = team, 0 아군 · 1 상대) ─────────────────────────────────
const TEAM_DISC:  Array = [Color(0.17, 0.32, 0.58), Color(0.58, 0.21, 0.18)]   # 스트립 원 · 성장치 탭
const TEAM_RIM:   Array = [Color(0.32, 0.62, 0.95), Color(0.95, 0.40, 0.32)]
const TEAM_DONUT: Array = [Color(0.25, 0.60, 1.00), Color(0.95, 0.35, 0.25)]   # 전략 포인트 고리
const TURN_BAR:   Array = [Color(0.18, 0.45, 0.95, 0.92), Color(0.95, 0.30, 0.25, 0.92)]  # 차례 알림 띠
const STRIP_DRAG_DIM: Color = Color(0.42, 0.42, 0.48, 1.0)   # 카드 끄는 동안 아군 스트립
const DEAD_TINT:      Color = Color(0.42, 0.42, 0.46, 1.0)   # 쓰러진 파일럿 흉상

# ── 글자 크기 (변형 기본값 — 노드마다 다르면 `theme_override_font_sizes`) ──────
const FONT_LARGE:   int = 40   # 상세 패널 이름 · 성장치, 금테 버튼
const FONT_TITLE:   int = 30   # 스킬 이름 · 결과 판 "MVP"
const FONT_VALUE:   int = 28   # 칸 수치 · 사용 버튼
const FONT_TAB:     int = 26   # 탭
const FONT_BODY:    int = 22   # 설명문 · 상태 줄 · 칸 이름
const FONT_CAPTION: int = 20   # 스킬 종류 · 작은 표시
const FONT_SMALL:   int = 18   # 경과 시계

# ── 모서리 · 테두리 · 여백 ───────────────────────────────────────────────────
const RADIUS:          int = 18   # 말풍선 · MVP 판 · 결과 판 · 금테 버튼
const PANEL_RADIUS:    int = 14   # 상세 패널 정보 판 · 탭 위 모서리
const FX_RADIUS:       int = 16   # 지속 효과 썸네일
const CHIP_RADIUS:     int = 12   # 스탯 칸
const SLAB_RADIUS:     int = 18   # MVP 자리 표시 판
const ART_SLAB_RADIUS: int = 24   # 상세 패널 자리 표시 판 (위 모서리만)
const SCORE_TAB_RADIUS: int = 8   # 스트립 성장치 탭
const GOLD_BORDER_W:   int = 3
const PANEL_BORDER_W:  int = 1
const TAB_BORDER_W:    int = 2
const CHIP_BORDER_W:    int = 1
const CHIP_BORDER_W_HL: int = 3
const SLAB_BORDER_W:   int = 2
const PANEL_PAD:  Vector2 = Vector2(22.0, 26.0)   # 정보 판 안쪽 여백 (좌우, 위아래)
const POPUP_PAD:  Vector2 = Vector2(26.0, 24.0)   # 말풍선 안쪽 여백
const SHADOW_SIZE: int = 6
const SHADOW_OFFSET: Vector2 = Vector2(0.0, 6.0)
const OUTLINE_SIZE: int = 6
## 금테 버튼을 누른 동안 바탕을 밝히는 양.
const BUTTON_PRESS_LIGHTEN: float = 0.15

const THEME_PATH: String = "res://resources/BattleTheme.tres"

## 버튼 상태 스타일박스 이름 (`OutgameTheme.BUTTON_STATES` 와 같다).
const BUTTON_STATES: Array = ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]


# ── 스타일박스 공장 ──────────────────────────────────────────────────────────

## 판 한 장 — 바탕, (있으면) 테두리, 네 모서리 반지름. 안쪽 여백은 0.
static func box(bg: Color, radius: int, border: Variant = null, border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border is Color and border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(0.0)
	return sb


## 정보 판 — `PANEL_BG` + 1px `PANEL_BORDER`, `PANEL_RADIUS`.
static func panel_box() -> StyleBoxFlat:
	return box(PANEL_BG, PANEL_RADIUS, PANEL_BORDER, PANEL_BORDER_W)


## 스탯 칸(`fx` = 지속 효과 썸네일) 한 장 — 일반 / 강조.
static func chip_box(highlighted: bool, fx: bool = false) -> StyleBoxFlat:
	return box(CHIP_BG_HL if highlighted else CHIP_BG, FX_RADIUS if fx else CHIP_RADIUS,
			CHIP_BORDER_HL if highlighted else CHIP_BORDER,
			CHIP_BORDER_W_HL if highlighted else CHIP_BORDER_W)


## 탭 한 장. 켜진 탭은 아래 테두리가 없고(받침과 한 몸) 위 모서리만 둥글다.
static func tab_box(on: bool) -> StyleBoxFlat:
	var sb := box(TAB_BG_ON if on else TAB_BG_OFF, 0,
			TAB_BORDER_ON if on else TAB_BORDER_OFF, TAB_BORDER_W)
	sb.border_width_bottom = 0 if on else TAB_BORDER_W
	sb.corner_radius_top_left = PANEL_RADIUS
	sb.corner_radius_top_right = PANEL_RADIUS
	return sb


## 말풍선 판 — `POPUP_BG`, 테두리 없음, 아래로 짧은 그림자, 안쪽 여백 `POPUP_PAD`.
static func popup_box() -> StyleBoxFlat:
	var sb := box(POPUP_BG, RADIUS)
	sb.anti_aliasing = true
	sb.shadow_color = SHADOW
	sb.shadow_size = SHADOW_SIZE
	sb.shadow_offset = SHADOW_OFFSET
	sb.content_margin_left = POPUP_PAD.x
	sb.content_margin_right = POPUP_PAD.x
	sb.content_margin_top = POPUP_PAD.y
	sb.content_margin_bottom = POPUP_PAD.y
	return sb


# ── 공용 Theme 리소스 (`BattleTheme.tres`) ───────────────────────────────────

static func build_theme() -> Theme:
	var th := Theme.new()

	# 판
	var plate := panel_box()
	plate.content_margin_left = PANEL_PAD.x
	plate.content_margin_right = PANEL_PAD.x
	plate.content_margin_top = PANEL_PAD.y
	plate.content_margin_bottom = PANEL_PAD.y
	_add_box(th, "BattlePanel", &"PanelContainer", plate)
	_add_box(th, "BattlePopup", &"PanelContainer", popup_box())
	_add_box(th, "BattleGoldPanel", &"PanelContainer",
			box(GOLD_PANEL_BG, RADIUS, GOLD_BORDER, GOLD_BORDER_W))
	_add_box(th, "BattleGoldModal", &"PanelContainer",
			box(MODAL_BG, RADIUS, GOLD_BORDER, GOLD_BORDER_W))
	_add_box(th, "BattleSlab", &"PanelContainer",
			box(SLAB_BG, SLAB_RADIUS, PANEL_BORDER, SLAB_BORDER_W))
	_add_box(th, "BattleDimPanel", &"Panel", box(DIM, 0))

	# 버튼
	var gold_n := box(BUTTON_BG, RADIUS, GOLD_BORDER, GOLD_BORDER_W)
	var gold_p := box(BUTTON_BG.lightened(BUTTON_PRESS_LIGHTEN), RADIUS, GOLD_BORDER, GOLD_BORDER_W)
	_add_button(th, "BattleGoldButton", FONT_LARGE, {
		"normal": gold_n, "hover": gold_n.duplicate(), "pressed": gold_p,
		"hover_pressed": gold_p.duplicate(), "focus": StyleBoxEmpty.new(),
		"disabled": gold_n.duplicate()})
	# 사용 버튼 — 모양은 엔진 기본 버튼 그대로, 글자 크기만.
	th.set_type_variation(&"BattleActionButton", &"Button")
	th.set_font_size(&"font_size", &"BattleActionButton", FONT_VALUE)
	for on in [false, true]:
		var suffix: String = "On" if on else ""
		_add_button(th, "BattleChipButton" + suffix, -1, _same_states(chip_box(on)))
		_add_button(th, "BattleFxButton" + suffix, -1, _same_states(chip_box(on, true)))
		_add_button(th, "BattleTab" + suffix, FONT_TAB, _same_states(tab_box(on)))
		th.set_color(&"font_color", "BattleTab" + suffix, Color.WHITE if on else TEXT_KEY)

	# 글자
	_add_label(th, "BattleHeaderLabel", FONT_LARGE, TEXT_HEADER)
	_add_label(th, "BattleTitleLabel", FONT_TITLE, TEXT_TITLE)
	_add_label(th, "BattleSkillNameLabel", FONT_TITLE, TEXT_SKILL)
	_add_label(th, "BattleValueLabel", FONT_VALUE, TEXT_VALUE)
	_add_label(th, "BattleBodyLabel", FONT_BODY, TEXT_DESC)
	_add_label(th, "BattleStatusLabel", FONT_BODY, TEXT_WAIT)
	_add_label(th, "BattleKeyLabel", FONT_BODY, TEXT_KEY)
	_add_label(th, "BattleSectionLabel", FONT_BODY, TEXT_SECTION)
	_add_label(th, "BattleCaptionLabel", FONT_CAPTION, TEXT_TYPE)
	_add_label(th, "BattleSubLabel", FONT_BODY, TEXT_SUB)
	_add_label(th, "BattleGrowthLabel", FONT_LARGE, TEXT_GROWTH)
	_add_label(th, "BattlePositiveLabel", FONT_BODY, POSITIVE)
	_add_label(th, "BattleNegativeLabel", FONT_BODY, NEGATIVE)
	_add_label(th, "BattleAllyLabel", FONT_BODY, ALLY)
	_add_label(th, "BattleEnemyLabel", FONT_BODY, ENEMY)
	# 판 없이 딤 · 그림 위에 뜨는 글자 — 외곽선으로 읽힘을 지킨다.
	_add_label(th, "BattleOutlinedLabel", FONT_LARGE, TEXT_BRIGHT)
	th.set_color(&"font_outline_color", &"BattleOutlinedLabel", OUTLINE)
	th.set_constant(&"outline_size", &"BattleOutlinedLabel", OUTLINE_SIZE)

	_add_screen_variations(th)
	return th


# ── 화면 전용 변형 ───────────────────────────────────────────────────────────
# `OutgameTheme._add_screen_variations` 와 같은 규칙: 이름 = `<쓰는 씬><역할>`,
# 기반 = 가장 가까운 공용 변형. 기반에서 바뀌는 항목만 덮는다.
static func _add_screen_variations(th: Theme) -> void:
	# battle_sim/ui/MvpView — 경기 MVP
	_add_derived(th, "MvpDimPanel", &"BattleDimPanel", box(DIM_DEEP, 0))
	_add_derived_label(th, "MvpTitleLabel", &"BattleOutlinedLabel", TEXT_TITLE)
	_add_derived_label(th, "MvpSubLabel", &"BattleOutlinedLabel", TEXT_SUB)
	# 진영 줄 — 아군 / 상대는 코드가 변형 이름을 바꿔 고른다.
	_add_derived_label(th, "MvpAllyLabel", &"BattleOutlinedLabel", ALLY)
	_add_derived_label(th, "MvpEnemyLabel", &"BattleOutlinedLabel", ENEMY)

	_add_hud_variations(th)
	_add_pilot_detail_variations(th)


## battle_sim/ui/HudBuilder · PilotStrip — 전투 HUD (`Hud*` · `PilotStrip*`).
static func _add_hud_variations(_th: Theme) -> void:
	pass


## battle_sim/ui/PilotDetailPanel — 파일럿 상세 (`PilotDetail*`).
static func _add_pilot_detail_variations(th: Theme) -> void:
	# 스탯 판 — 탭 바로 아래. 위 모서리는 각지게(켜진 탭이 그 위에 앉아 한 몸으로 이어진다).
	var stat := (th.get_stylebox(&"panel", &"BattlePanel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	stat.corner_radius_top_left = 0
	stat.corner_radius_top_right = 0
	_add_derived(th, "PilotDetailStatPlate", &"BattlePanel", stat)
	# 그림 없는 전신 자리 — 옅은 판, 3px 테두리, 위 모서리만 둥글다(아래는 화면 밖에서 잘린다).
	var slab := box(ART_SLAB_BG, 0, ART_SLAB_BORDER, 3)
	slab.corner_radius_top_left = ART_SLAB_RADIUS
	slab.corner_radius_top_right = ART_SLAB_RADIUS
	_add_derived(th, "PilotDetailArtSlab", &"BattleSlab", slab)
	# 지속 효과 썸네일(카드 아트) 아래 값 띠 — 썸네일 안쪽(인셋 3)이라 아래 모서리 = FX_RADIUS − 3.
	var band := box(FX_VALUE_BAND, 0)
	band.corner_radius_bottom_left = FX_RADIUS - 3
	band.corner_radius_bottom_right = FX_RADIUS - 3
	_add_derived(th, "PilotDetailFxBand", &"BattleDimPanel", band)
	# 칸 설명 판 — 카드 설명판과 같은 모양(`CardDescBox.panel_style`: 불투명 `MENU_BG` · 테두리
	# 없음 · 아래로 흐린 그림자), 안쪽 여백 20 / 16.
	var menu := CardDescBox.panel_style(false)
	menu.content_margin_left = 20.0
	menu.content_margin_right = 20.0
	menu.content_margin_top = 16.0
	menu.content_margin_bottom = 16.0
	_add_derived(th, "PilotDetailMenuPanel", &"BattlePopup", menu)
	# 카드 부채꼴 입력 띠 — 아무것도 그리지 않는다(카드 rect 가 아니라 보이는 띠라 테를 두르면 띠가 보인다).
	th.set_type_variation(&"PilotDetailCardBand", &"Button")
	for state in BUTTON_STATES:
		th.set_stylebox(state, &"PilotDetailCardBand", StyleBoxEmpty.new())
	# 글자 — 기체명 · 쓰러짐 줄 · 그림 없는 자리의 이름.
	_add_derived_label(th, "PilotDetailMechLabel", &"BattleKeyLabel", TEXT_MECH)
	th.set_font_size(&"font_size", &"PilotDetailMechLabel", 24)
	_add_derived_label(th, "PilotDetailWarnLabel", &"BattleNegativeLabel", TEXT_WARN)
	th.set_font_size(&"font_size", &"PilotDetailWarnLabel", 24)
	_add_derived_label(th, "PilotDetailPlaceholderLabel", &"BattleSubLabel", TEXT_PLACEHOLDER)
	th.set_font_size(&"font_size", &"PilotDetailPlaceholderLabel", 34)
	# 칸 설명 판 아래 설명 글(RichTextLabel — `{attack}` · `{engage}` 아이콘).
	th.set_type_variation(&"PilotDetailNoteText", &"RichTextLabel")
	th.set_font_size(&"normal_font_size", &"PilotDetailNoteText", FONT_CAPTION)
	th.set_color(&"default_color", &"PilotDetailNoteText", TEXT_NOTE)


## 테마 변형의 스타일박스 **사본** — 색이 데이터인 곳에서 코드가 색만 넣을 때.
static func variation_box(variation: StringName, item: StringName = &"panel") -> StyleBoxFlat:
	var th: Theme = load(THEME_PATH)
	return th.get_stylebox(item, variation).duplicate() as StyleBoxFlat


## `build_theme()` 결과를 `THEME_PATH` 에 저장한다(sub_resource id = `변형_상태` 고정,
## 파일 uid 유지 — `OutgameTheme.save_theme` 과 같은 방식).
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
		push_error("BattleTheme: %s 저장 실패 (%d)" % [THEME_PATH, err])
	return err


static func _add_box(th: Theme, variation: String, base: StringName, sb: StyleBox) -> void:
	th.set_type_variation(variation, base)
	th.set_stylebox(&"panel", variation, sb)


static func _add_derived(th: Theme, variation: String, base: StringName, sb: StyleBox,
		item: StringName = &"panel") -> void:
	th.set_type_variation(variation, base)
	th.set_stylebox(item, variation, sb)


static func _add_derived_label(th: Theme, variation: String, base: StringName,
		color: Color) -> void:
	th.set_type_variation(variation, base)
	th.set_color(&"font_color", variation, color)


## 버튼 변형 — 상태별 스타일박스(`boxes` 에 있는 것만), 글자 크기(`font_size` < 0 = 안 정함).
## 글자색은 정하지 않는다(엔진 기본 버튼 글자색) — 필요한 변형만 따로 넣는다.
static func _add_button(th: Theme, variation: String, font_size: int, boxes: Dictionary) -> void:
	th.set_type_variation(variation, &"Button")
	if font_size > 0:
		th.set_font_size(&"font_size", variation, font_size)
	for n in boxes:
		th.set_stylebox(n, variation, boxes[n])


## 누르든 올리든 같은 판(상태는 일반 / 강조 변형이 말한다). 비활성은 엔진 기본.
static func _same_states(sb: StyleBoxFlat) -> Dictionary:
	return {"normal": sb, "hover": sb.duplicate(), "pressed": sb.duplicate(),
			"hover_pressed": sb.duplicate(), "focus": sb.duplicate()}


static func _add_label(th: Theme, variation: String, font_size: int, color: Color) -> void:
	th.set_type_variation(variation, &"Label")
	th.set_font_size(&"font_size", variation, font_size)
	th.set_color(&"font_color", variation, color)
