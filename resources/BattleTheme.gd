class_name BattleTheme
extends RefCounted

# ── 인게임(BattleSim) 흰 팔레트 ──────────────────────────────────────────────
#
# **전장 UI 의 색 · 글자 크기 · 모서리가 여기를 지난다.** HUD(`HudBuilder`) · 파일럿
# 스트립(`PilotStrip`) · 상세 패널(`PilotDetailPanel`) · 스킬 말풍선(`SkillPopup`) ·
# MVP 뷰(`MvpView`) · 킬 로그 · 오브젝트 시계 · 카드 설명판 · 교전 화면이 같은 표를 읽는다.
# 원칙은 **아웃게임(`OutgameTheme`)과 같다** — 전장 위에 뜨는 판도 흰 종이다:
#   1. 판은 **흰 카드**(`PANEL_BG` · `POPUP_BG` = `OutgameTheme.SURFACE`), 경계는 선이 아니라
#      **그림자**(`SHADOW`)와 아주 옅은 테두리(`PANEL_BORDER` = `OutgameTheme.BORDER`)가 만든다.
#      전장을 덮는 모달의 바탕은 종이(`PAPER` = `OutgameTheme.BG`), 전장이 비쳐야 하는
#      모달 뒤는 아웃게임과 같은 남색 딤(`DIM_LIGHT` = `OutgameTheme.DIM`).
#   2. 강조는 **앰버** 한 가지 — 면은 `GOLD`(= `OutgameTheme.ACCENT`), 흰 종이 위의 글자는
#      `TEXT_TITLE`(= `OutgameTheme.ACCENT_TEXT`). "지금 눌러" 버튼은 아웃게임 primary 버튼.
#   3. 진영은 파랑(아군) / 빨강(상대) — 흰 종이 위의 글자는 진하게(`ALLY` · `ENEMY`),
#      전장 위의 면은 그대로(`TEAM_*`).
# **판 없이 전장 위에 바로 뜨는 것**(피해 숫자 · 초상 위 배너 · 마커 링 · 스트립 원 위
# 숫자 · 스트레스 한 낱말)은 판이 아니다 — 흰 글자 + 검은 외곽선(`TEXT_BRIGHT` ·
# `OUTLINE`, `BattleOutlinedLabel`)이 그대로 남는다.
#
# 씬(.tscn)으로 옮긴 전투 UI 는 `BattleTheme.tres`(이 파일의 `build_theme()` 결과)를
# 붙이고 **변형**(`theme_type_variation`)을 고른다. `.tres` 는 손으로 고치지 않는다 —
# 여기를 고치고 `BattleThemeBuilder.gd`(에디터 File → Run) /
# `BattleThemeBuilderCli.gd`(헤드리스)로 다시 만든다. 목록 · 규칙: `resources/README.md`.

# ── 판 (배경 면) ─────────────────────────────────────────────────────────────
const PAPER:         Color = OutgameTheme.BG        # 전장을 덮는 모달의 바탕 (상세 패널 · MVP · 교전)
const PANEL_BG:      Color = OutgameTheme.SURFACE   # 정보 판 (상세 패널 칸 · 머리글 · 스킬)
const PANEL_BORDER:  Color = OutgameTheme.BORDER    # 정보 판 · 자리 표시 판 테두리 (아주 옅다)
const POPUP_BG:      Color = OutgameTheme.SURFACE   # 말풍선 (SkillPopup) — 화살표도 이 색
const MODAL_BG:      Color = OutgameTheme.SURFACE   # 결과 판
const GOLD_PANEL_BG: Color = OutgameTheme.SURFACE   # MVP 정보 판
const MENU_BG:       Color = OutgameTheme.SURFACE   # 칸 설명 판 (상세 패널) · 카드 설명판
const SUNK:          Color = OutgameTheme.SURFACE_SUNK   # 판 안의 눌린 칸 · 빈 자리 · 트랙
const LINE_STRONG:   Color = OutgameTheme.BORDER_STRONG  # 종이 위 트랙 · 막대 · 무대의 테두리 선
const DEAD_SLOT:     Color = Color(0.960, 0.880, 0.880, 1.0)   # 쓰러진 참가자 칸의 뒤판 (교전 명단)
## 칸 · 지속 효과 썸네일 — 일반 / 강조(눌러서 설명이 열린 칸).
const CHIP_BG:        Color = OutgameTheme.SURFACE_SUNK
const CHIP_BG_HL:     Color = OutgameTheme.ACCENT_DIM
const CHIP_BORDER:    Color = OutgameTheme.BORDER
const CHIP_BORDER_HL: Color = OutgameTheme.ACCENT
## 탭 — 켜짐(흰 판, 스탯 판과 한 몸) / 꺼짐(눌린 칸).
const TAB_BG_ON:      Color = OutgameTheme.SURFACE
const TAB_BG_OFF:     Color = OutgameTheme.SURFACE_SUNK
const TAB_BORDER_ON:  Color = OutgameTheme.BORDER
const TAB_BORDER_OFF: Color = OutgameTheme.BORDER
const BUTTON_BG:      Color = OutgameTheme.ACCENT   # 앰버 주 행동 버튼 바탕 (MVP "계속" · 사용 · 결과)
## 그림 없는 자리 표시 판 — MVP 전신 / 상세 패널 전신(옅게 — 앞의 파일럿보다
## 눈에 띄면 안 된다).
const SLAB_BG:          Color = OutgameTheme.SURFACE_SUNK
const ART_SLAB_BG:      Color = Color(0.929, 0.933, 0.945, 0.70)
const ART_SLAB_BORDER:  Color = OutgameTheme.BORDER_STRONG
## 상세 패널 뒤에 선 전신 — `modulate` 라 RGB 는 어둡게(실루엣), A 는 살짝 비친다.
## 종이 위라 예전(거의 검정)보다 옅은 회청색 실루엣.
const ART_BACK_TINT:    Color = Color(0.46, 0.47, 0.54, 0.92)
const FX_VALUE_BAND:    Color = Color(0.00, 0.00, 0.00, 0.62)  # 지속 효과 썸네일(카드 아트) 아래 수치 띠

# ── 어두운 설명판 (사용자 결정: 흰 팔레트에서 제외) ──────────────────────────
## 카드 설명판(`CardDescBox` 인게임 쪽 — 손패 · 상세 패널 카드 · 고르기 · 미리보기) · 키워드 풀이 판 ·
## 상세 패널의 칸 설명 판(`PilotDetailInfoMenu` — 행 · 설명 글 · 효과 칸 · 성장 막대)은 **예전 어두운
## 색 그대로** 둔다. 값은 흰 팔레트 전의 리터럴이다.
const DESC_BG:        Color = Color(0.08, 0.08, 0.12, 1.00)   # 판 바탕 (예전 `MENU_BG`)
const DESC_NAME:      Color = Color(1.00, 0.95, 0.55)         # 카드 설명판 이름
const DESC_TEXT:      Color = Color(0.92, 0.92, 0.92)         # 카드 설명문 · 속성 줄
const DESC_NOTE:      Color = Color(0.70, 0.70, 0.74)         # 키워드 풀이
const DESC_KW:        Color = Color(0.55, 0.85, 1.00)         # 키워드 아이콘 · 키워드 줄
const DESC_KNOCK:     Color = Color(0.08, 0.08, 0.12)         # 아이콘 뚫림 = 판 바탕
const DESC_SPECIAL:   Color = KeywordIcon.SPECIAL_COLOR_DARK  # 특수 키워드
const DESC_HEADER:    Color = Color(1.00, 0.92, 0.55)         # 칸 설명 판 제목 · 제목 값 (예전 `TEXT_HEADER`)
const DESC_KEY:       Color = Color(0.72, 0.74, 0.80)         # 칸 설명 판 행 이름 (예전 `TEXT_KEY`)
const DESC_VALUE:     Color = Color(0.96, 0.96, 0.98)         # 칸 설명 판 행 값 (예전 `TEXT_VALUE`)
const DESC_BODY:      Color = Color(0.72, 0.75, 0.84)         # 칸 설명 판 설명 글 (예전 `TEXT_NOTE`)
const DESC_POSITIVE:  Color = Color(0.45, 0.90, 0.55)
const DESC_NEGATIVE:  Color = Color(0.98, 0.42, 0.42)
const DESC_GROWTH:    Color = Color(0.72, 1.00, 0.80)         # 성장 막대 채움
const DESC_GOLD:      Color = Color(1.00, 0.80, 0.30)         # 성장 막대 도달 눈금
const DESC_CHIP_BG:     Color = Color(0.10, 0.12, 0.18, 0.94) # 판 안 효과 칸 · 막대 트랙
const DESC_CHIP_BORDER: Color = Color(0.32, 0.36, 0.48, 0.80)
const DESC_ICON:      Color = Color(1.00, 0.94, 0.78)         # 판 안 효과 칸의 스킬 · 패시브 글리프
## 효과 칸 약칭 색(흰 팔레트 토큰 → 어두운 판 위 예전 색).
const DESC_FX_COLORS: Dictionary = {
	FX_WARM: Color(1.00, 0.55, 0.28), FX_COOL: Color(0.55, 0.82, 1.00),
	FX_GREEN: Color(0.55, 0.95, 0.62), FX_MINT: Color(0.72, 1.00, 0.80),
	FX_GOLD: Color(1.00, 0.72, 0.36), FX_SHIELD: Color(0.92, 0.92, 0.42),
	FX_NEUTRAL: Color(0.86, 0.86, 0.90), FX_ICON: Color(1.00, 0.94, 0.78),
}


## 흰 팔레트의 효과 색을 어두운 설명판 위의 색으로(표에 없으면 그대로).
static func desc_fx_color(c: Color) -> Color:
	return DESC_FX_COLORS.get(c, c) as Color


# ── 강조 · 딤 · 그림자 ───────────────────────────────────────────────────────
const GOLD:        Color = OutgameTheme.ACCENT
const GOLD_BORDER: Color = OutgameTheme.ACCENT                # MVP 판 · 결과 판 테두리
const GLOW:        Color = Color(0.961, 0.651, 0.137, 0.30)   # MVP 전신 뒤 후광 (가운데) = ACCENT α
## **전투의 모든 딤은 이 한 장**(사용자 결정) — 검정 α 0.30: 전장이 또렷이 보이되 "덮였다"는 느낌만.
## 딤 위에 **판 없이** 바로 서는 글자는 전장 위 글자와 같은 규칙(밝은 글자 + 외곽선, `*_ON_DIM` ·
## `BattleOutlinedLabel`)이고, 흰 판은 그대로 흰 판이다.
const DIM_BLACK:   Color = Color(0.0, 0.0, 0.0, 0.30)
const DIM:         Color = DIM_BLACK   # 상세 패널 · 스트레스 사건 딤 (`BattleDimPanel`)
const DIM_DEEP:    Color = DIM_BLACK   # MVP 뷰 딤
const DIM_LIGHT:   Color = DIM_BLACK   # 결과 판 · 고르기 그리드 · 더미 열람 · 보상 팝업 뒤 딤
const DIM_FIELD:   Color = DIM_BLACK   # 전장만 누르는 딤 (버리기 · 보상 연출) — 카드가 그 위에 뜬다
const SHADOW:      Color = Color(0.110, 0.110, 0.180, 0.18)   # 판 그림자 (아래로만)
const OUTLINE:      Color = Color(0.00, 0.00, 0.00, 0.90)  # 판 없이 전장 위에 뜬 글자의 외곽선
const OUTLINE_SOFT: Color = Color(0.00, 0.00, 0.00, 0.85)  # 스트립 숫자 외곽선

# ── 스킬 아이콘 타일 (`SkillImages.make_icon_tile`) ──────────────────────────
## 타일은 흰 판 위의 진한 칸(`OutgameTheme.RAIL`) — 아이콘이 크림색으로 선다.
const SKILL_TILE_BG:     Color = OutgameTheme.RAIL
const SKILL_TILE_ICON:   Color = Color(1.00, 0.94, 0.78)
const SKILL_TILE_SHADOW: Color = Color(0.110, 0.110, 0.180, 0.30)
const SKILL_KW_ICON:     Color = OutgameTheme.ACCENT_TEXT   # 설명문 키워드 아이콘 (흰 판 위)
const SKILL_KNOCK:       Color = OutgameTheme.SURFACE       # 아이콘 뚫림 색 = 판 바탕
const SPECIAL_KW:        Color = KeywordIcon.SPECIAL_COLOR_LIGHT   # 설명문 특수 키워드 (흰 판 위)
## 흰 / 눌린 칸 위에 서는 글리프(지속 효과 칸의 스킬 · 패시브 아이콘).
const FX_ICON:           Color = OutgameTheme.TEXT

# ── 글자 ─────────────────────────────────────────────────────────────────────
# 흰 종이 위의 글자 — 진한 순.
const TEXT:             Color = OutgameTheme.TEXT        # 본문 · 이름 · 값
const TEXT_VALUE:       Color = OutgameTheme.TEXT        # 칸 수치 · 설명 판 값
const TEXT_DESC:        Color = OutgameTheme.TEXT        # 스킬 · 카드 설명문
const TEXT_CLOCK:       Color = OutgameTheme.TEXT        # 경과 시계 (흰 알약 위)
const TEXT_KDA:         Color = OutgameTheme.TEXT_SUB    # 결과 판 MVP 줄 K/D/A
const TEXT_WAIT:        Color = OutgameTheme.TEXT_SUB    # 스킬 상태 한 줄 (남은 턴 · 토큰)
const TEXT_PLACEHOLDER: Color = OutgameTheme.TEXT_SUB    # 그림 없는 자리의 이름
const TEXT_NOTE:        Color = OutgameTheme.TEXT_SUB    # 칸 설명 판 본문 · 키워드 풀이
const TEXT_SUB:         Color = OutgameTheme.TEXT_SUB    # MVP 지표 줄 · 자리 표시 글자
const TEXT_KEY:         Color = OutgameTheme.TEXT_SUB    # 칸 이름 · 꺼진 탭 · "스킬 없음"
const TEXT_TYPE:        Color = OutgameTheme.TEXT_SUB    # 스킬 종류 · 쿨타임 수
const TEXT_MECH:        Color = OutgameTheme.TEXT_SUB    # 상세 패널 메크 이름
const TEXT_FAINT:       Color = OutgameTheme.TEXT_FAINT  # 비활성 · 못 번 성장 "—"
const TEXT_ON_FILL:     Color = OutgameTheme.TEXT_ON_FILL   # 색면(버튼 · 막대 · 띠) 위 글자
# 판 없이 전장 / 그림 / 딤 위에 뜨는 글자(외곽선과 함께).
const TEXT_BRIGHT:      Color = Color(0.97, 0.97, 1.00)
const TITLE_ON_DIM:     Color = Color(1.00, 0.82, 0.40)   # 딤 위 앰버 제목 (교전 제목 · MATCH MVP · 승리)
const SUB_ON_DIM:       Color = Color(0.86, 0.88, 0.94)   # 딤 위 보조 글자 (차례 줄 · 힌트 · 빈 더미)
const NEGATIVE_ON_DIM:  Color = Color(1.00, 0.55, 0.50)   # 딤 위 경고 · 패배 · 마지막 턴
const GROWTH_ON_DIM:    Color = Color(1.00, 0.86, 0.45)   # 딤 위 번 성장치
const POSITIVE_ON_DIM:  Color = Color(0.45, 0.90, 0.55)   # 딤 위 이로운 효과 줄
# 색 있는 글자 (흰 종이 위).
const TEXT_TITLE:   Color = OutgameTheme.ACCENT_TEXT   # "MATCH MVP" · 결과 판 "MVP" · 교전 제목
const TEXT_HEADER:  Color = OutgameTheme.TEXT          # 상세 패널 이름 · 설명 판 제목
const TEXT_SKILL:   Color = OutgameTheme.TEXT          # 스킬 이름
const TEXT_SCORE:   Color = Color(1.00, 0.94, 0.62)    # 스트립 성장치 (팀색 탭 위, 외곽선)
const TEXT_SECTION: Color = OutgameTheme.LINK          # 상세 패널 섹션 머리
const TEXT_GROWTH:  Color = OutgameTheme.ACCENT_TEXT   # 상세 패널 성장치 · 성장 막대 채움
const TEXT_WARN:    Color = OutgameTheme.NEGATIVE      # 상세 패널 경고 줄
const ALLY:     Color = Color(0.157, 0.400, 0.851)   # 아군 (흰 종이 위 글자)
const ENEMY:    Color = Color(0.835, 0.220, 0.220)   # 상대 팀 (흰 종이 위 글자)
const POSITIVE: Color = Color(0.090, 0.560, 0.300)   # 기본값 대비 + (흰 종이 위에서 읽히게 `OutgameTheme.POSITIVE` 보다 진하게)
const NEGATIVE: Color = OutgameTheme.NEGATIVE        # 기본값 대비 −
const DEAD:     Color = Color(1.00, 0.55, 0.50)   # 스트립 부활까지 남은 턴 (원 위, 외곽선)
## 스트레스 상태 (`StressSystem.Mood`) — 각성 = 금색, 패닉 = 빨강, 위축 = 보라. 전장 · 그림
## 위에 외곽선과 함께 뜬다.
const STRESS_AWAKEN: Color = Color(1.00, 0.80, 0.30)
const STRESS_PANIC:  Color = Color(0.98, 0.42, 0.42)
const STRESS_SHAKEN: Color = Color(0.72, 0.58, 1.00)
## 효과 칸 약칭 색(상세 패널 `_effect_defs` · `FX_KIND_COLOR`) — 눌린 칸(`CHIP_BG`) 위 글자.
const FX_WARM:    Color = Color(0.850, 0.380, 0.140)   # 성장률 · 레인 상승
const FX_COOL:    Color = Color(0.180, 0.420, 0.840)   # 회피 · 레인 하락 · 패시브
const FX_GREEN:   Color = Color(0.110, 0.560, 0.300)   # 체력 · 매복
const FX_MINT:    Color = Color(0.070, 0.520, 0.440)   # 성장 배율
const FX_GOLD:    Color = OutgameTheme.ACCENT_TEXT     # 공격력
const FX_SHIELD:  Color = Color(0.520, 0.490, 0.080)   # 보호막
const FX_NEUTRAL: Color = OutgameTheme.TEXT_SUB        # 그 밖
## 오브젝트 색 — 전령은 보랏빛, 용은 주홍(흰 판 위 글리프 · 제목 · 테두리: 시계 · 킬 로그 · 보상 팝업).
const OBJ_HERALD: Color = Color(0.520, 0.360, 0.880)
const OBJ_DRAGON: Color = Color(0.900, 0.420, 0.140)
## 같은 두 색의 밝은 판 — 판 없이 전장 위에 바로 뜨는 오브젝트 시계(`ObjectiveTimer`).
const OBJ_HERALD_FIELD: Color = Color(0.74, 0.62, 0.99)
const OBJ_DRAGON_FIELD: Color = Color(1.00, 0.55, 0.28)

# ── 진영 면 (인덱스 = team, 0 아군 · 1 상대) ─────────────────────────────────
const TEAM_DISC:  Array = [Color(0.17, 0.32, 0.58), Color(0.58, 0.21, 0.18)]   # 스트립 원
const TEAM_RIM:   Array = [Color(0.32, 0.62, 0.95), Color(0.95, 0.40, 0.32)]   # 테두리 · 성장치 탭 테 · 킬 로그
const TEAM_DONUT: Array = [Color(0.25, 0.60, 1.00), Color(0.95, 0.35, 0.25)]   # 전략 포인트 고리
const TURN_BAR:   Array = [Color(0.18, 0.45, 0.95), Color(0.90, 0.28, 0.24)]   # 차례 알림 띠의 위아래 색 줄
## 흰 종이 위의 진영 글자 (`ALLY` · `ENEMY`).
const SIDE_TEXT:  Array = [Color(0.157, 0.400, 0.851), Color(0.835, 0.220, 0.220)]
const STRIP_DRAG_DIM: Color = Color(0.42, 0.42, 0.48, 1.0)   # 카드 끄는 동안 아군 스트립
const DEAD_TINT:      Color = Color(0.42, 0.42, 0.46, 1.0)   # 쓰러진 파일럿 흉상
## F6 단독 실행 미리보기에서 전장 대신 까는 회색(판이 전장 위에 뜬 모습을 흉내 낸다).
const PREVIEW_FIELD:  Color = Color(0.30, 0.30, 0.30, 1.0)

# ── 글자 크기 (변형 기본값 — 노드마다 다르면 `theme_override_font_sizes`) ──────
const FONT_LARGE:   int = 40   # 상세 패널 이름 · 성장치, 앰버 버튼
const FONT_TITLE:   int = 30   # 스킬 이름 · 결과 판 "MVP"
const FONT_VALUE:   int = 28   # 칸 수치 · 사용 버튼
const FONT_TAB:     int = 26   # 탭
const FONT_BODY:    int = 22   # 설명문 · 상태 줄 · 칸 이름
const FONT_CAPTION: int = 20   # 스킬 종류 · 작은 표시 · 경과 시계
const FONT_SMALL:   int = 18   # 성장 막대 눈금

# ── 모서리 · 테두리 · 여백 ───────────────────────────────────────────────────
const RADIUS:          int = 18   # 말풍선 · MVP 판 · 결과 판 · 앰버 버튼
const PANEL_RADIUS:    int = 14   # 상세 패널 정보 판 · 탭 위 모서리
const FX_RADIUS:       int = 16   # 지속 효과 썸네일
const CHIP_RADIUS:     int = 12   # 스탯 칸
const SLAB_RADIUS:     int = 18   # MVP 자리 표시 판
const ART_SLAB_RADIUS: int = 24   # 상세 패널 자리 표시 판 (위 모서리만)
const SCORE_TAB_RADIUS: int = 8   # 스트립 성장치 탭
const GOLD_BORDER_W:   int = 3
const PANEL_BORDER_W:  int = 1
const TAB_BORDER_W:    int = 1
const CHIP_BORDER_W:    int = 1
const CHIP_BORDER_W_HL: int = 3
const SLAB_BORDER_W:   int = 2
const PANEL_PAD:  Vector2 = Vector2(22.0, 26.0)   # 정보 판 안쪽 여백 (좌우, 위아래)
const POPUP_PAD:  Vector2 = Vector2(26.0, 24.0)   # 말풍선 안쪽 여백
const SHADOW_SIZE: int = 8
const SHADOW_OFFSET: Vector2 = Vector2(0.0, 4.0)
# 카드 설명 판 — 손패 설명판 · 상세 패널 칸 설명 판 공용 (`desc_box`, 어두운 판 — 예전 값).
const DESC_BOX_RADIUS: int = 12
const DESC_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.6)
const DESC_SHADOW_SIZE: int = 16
const DESC_SHADOW_DROP: float = 10.0
const OUTLINE_SIZE: int = 6
## 경과 시계 알약 안쪽 여백 (좌우, 위아래).
const CLOCK_PAD: Vector2 = Vector2(14.0, 1.0)
## 킬 로그 한 줄 · 오브젝트 시계 판 모서리.
const ROW_RADIUS: int = 8

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


## 판에 아래로 떨어지는 그림자(`SHADOW`, `SHADOW_SIZE`, `SHADOW_OFFSET`)를 얹는다 — 흰 판의
## 경계는 선이 아니라 이것이 만든다(`OutgameTheme.card_style` 과 같은 규칙).
static func with_shadow(sb: StyleBoxFlat) -> StyleBoxFlat:
	sb.shadow_color = SHADOW
	sb.shadow_size = SHADOW_SIZE
	sb.shadow_offset = SHADOW_OFFSET
	sb.anti_aliasing = true
	return sb


## 카드 설명 판 — **어두운** 불투명 `DESC_BG`(흰 팔레트에서 제외된 판), 테두리 없음, 아래로
## 흐린 그림자. 안쪽 여백은 쓰는 쪽이 정한다.
static func desc_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = DESC_BG
	sb.set_corner_radius_all(DESC_BOX_RADIUS)
	sb.shadow_color = DESC_SHADOW
	sb.shadow_size = DESC_SHADOW_SIZE
	sb.shadow_offset = Vector2(0.0, DESC_SHADOW_DROP)
	return sb


## 정보 판 — 흰 `PANEL_BG` + 1px 옅은 `PANEL_BORDER`, `PANEL_RADIUS`, 그림자.
static func panel_box() -> StyleBoxFlat:
	return with_shadow(box(PANEL_BG, PANEL_RADIUS, PANEL_BORDER, PANEL_BORDER_W))


## 스탯 칸(`fx` = 지속 효과 썸네일) 한 장 — 일반(눌린 칸) / 강조(앰버 틴트 + 앰버 테).
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


## 말풍선 판 — 흰 `POPUP_BG`, 테두리 없음, 아래로 그림자, 안쪽 여백 `POPUP_PAD`.
static func popup_box() -> StyleBoxFlat:
	var sb := with_shadow(box(POPUP_BG, RADIUS))
	sb.content_margin_left = POPUP_PAD.x
	sb.content_margin_right = POPUP_PAD.x
	sb.content_margin_top = POPUP_PAD.y
	sb.content_margin_bottom = POPUP_PAD.y
	return sb


## 앰버 테를 두른 흰 판 — MVP 정보 판 · 결과 판.
static func gold_box() -> StyleBoxFlat:
	return with_shadow(box(GOLD_PANEL_BG, RADIUS, GOLD_BORDER, GOLD_BORDER_W))


## 킬 로그 한 줄 · 오브젝트 시계의 흰 판(전장 위에 뜨는 작은 판, 그림자).
static func row_box() -> StyleBoxFlat:
	return with_shadow(box(PANEL_BG, ROW_RADIUS))


## 코드로 만드는 버튼의 옷 — 아웃게임 버튼과 같은 표(`OutgameTheme.button_spec`)를 읽는다.
## `kind` = `"primary"`(앰버, 한 화면에 하나) · `"ghost"`(흰 판 + 옅은 테) · `"danger"`.
## 씬의 버튼은 변형(`BattleGoldButton` · `BattleActionButton`)을 고른다.
static func style_button(b: Button, kind: String = "primary", font_size: int = FONT_VALUE) -> Button:
	if b == null:
		return b
	match kind:
		"ghost":
			OutgameTheme.style_ghost_button(b, font_size)
		"danger":
			OutgameTheme.style_danger_button(b, font_size)
		_:
			OutgameTheme.style_primary_button(b, font_size)
	return b


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
	_add_box(th, "BattleGoldPanel", &"PanelContainer", gold_box())
	var modal := gold_box()
	modal.bg_color = MODAL_BG
	_add_box(th, "BattleGoldModal", &"PanelContainer", modal)
	_add_box(th, "BattleSlab", &"PanelContainer",
			box(SLAB_BG, SLAB_RADIUS, PANEL_BORDER, SLAB_BORDER_W))
	_add_box(th, "BattleDimPanel", &"Panel", box(DIM, 0))

	# 버튼 — 주 행동은 아웃게임 primary(앰버 면 + 흰 글자)와 같은 표.
	var primary: Dictionary = OutgameTheme.button_styles("primary")
	for n in BUTTON_STATES:
		var sb: StyleBoxFlat = primary[n]
		sb.set_corner_radius_all(RADIUS)
	_add_button(th, "BattleGoldButton", FONT_LARGE, primary)
	_set_button_font_colors(th, "BattleGoldButton", TEXT_ON_FILL)
	# 사용 버튼 — 같은 앰버 버튼, 글자만 `FONT_VALUE`.
	_add_button(th, "BattleActionButton", FONT_VALUE, OutgameTheme.button_styles("primary"))
	_set_button_font_colors(th, "BattleActionButton", TEXT_ON_FILL)
	for on in [false, true]:
		var suffix: String = "On" if on else ""
		_add_button(th, "BattleChipButton" + suffix, -1, _same_states(chip_box(on)))
		_add_button(th, "BattleFxButton" + suffix, -1, _same_states(chip_box(on, true)))
		_add_button(th, "BattleTab" + suffix, FONT_TAB, _same_states(tab_box(on)))
		_set_button_font_colors(th, "BattleTab" + suffix, TEXT_TITLE if on else TEXT_KEY)

	# 글자
	_add_label(th, "BattleTextLabel", FONT_LARGE, TEXT)
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
	# 판 없이 전장 · 그림 위에 뜨는 글자 — 외곽선으로 읽힘을 지킨다.
	_add_label(th, "BattleOutlinedLabel", FONT_LARGE, TEXT_BRIGHT)
	th.set_color(&"font_outline_color", &"BattleOutlinedLabel", OUTLINE)
	th.set_constant(&"outline_size", &"BattleOutlinedLabel", OUTLINE_SIZE)
	# 같은 규칙의 작은 글자 — 딤 위 보조 줄 / 경고 줄(스트레스 사건 힌트 · 효과).
	_add_derived_label(th, "BattleOutlinedSubLabel", &"BattleOutlinedLabel", SUB_ON_DIM)
	th.set_font_size(&"font_size", &"BattleOutlinedSubLabel", FONT_BODY)
	th.set_constant(&"outline_size", &"BattleOutlinedSubLabel", 4)
	_add_derived_label(th, "BattleOutlinedNegativeLabel", &"BattleOutlinedSubLabel", NEGATIVE_ON_DIM)
	_add_derived_label(th, "BattleOutlinedPositiveLabel", &"BattleOutlinedSubLabel", POSITIVE_ON_DIM)

	_add_screen_variations(th)
	return th


# ── 화면 전용 변형 ───────────────────────────────────────────────────────────
# `OutgameTheme._add_screen_variations` 와 같은 규칙: 이름 = `<쓰는 씬><역할>`,
# 기반 = 가장 가까운 공용 변형. 기반에서 바뀌는 항목만 덮는다.
static func _add_screen_variations(th: Theme) -> void:
	# battle_sim/ui/MvpView — 경기 MVP (불투명 종이 위)
	_add_derived(th, "MvpDimPanel", &"BattleDimPanel", box(DIM_DEEP, 0))
	_add_derived_label(th, "MvpTitleLabel", &"BattleOutlinedLabel", TITLE_ON_DIM)
	_add_derived_label(th, "MvpSubLabel", &"BattleSubLabel", TEXT_SUB)
	_add_derived_label(th, "MvpNameLabel", &"BattleTextLabel", TEXT)

	_add_hud_variations(th)
	_add_pilot_detail_variations(th)
	_add_stress_variations(th)


## battle_sim/stress/StressEventView · ui/PilotStrip · ui/PilotDetailPanel — 스트레스 상태 글자.
## 상태가 데이터라 코드가 변형 이름을 바꿔 끼운다(`StressEventView.mood_variation`).
static func _add_stress_variations(th: Theme) -> void:
	# 시험 결과 — 전신 위에 뜨는 큰 글자.
	_add_derived_label(th, "StressEventAwakenLabel", &"BattleOutlinedLabel", STRESS_AWAKEN)
	_add_derived_label(th, "StressEventPanicLabel", &"BattleOutlinedLabel", STRESS_PANIC)
	# 스트립 칸 위 / 상세 패널 머리 — 상태 한 낱말.
	for pair in [["StressMoodAwakenLabel", STRESS_AWAKEN], ["StressMoodPanicLabel", STRESS_PANIC],
			["StressMoodShakenLabel", STRESS_SHAKEN]]:
		_add_derived_label(th, String(pair[0]), &"BattleOutlinedLabel", pair[1] as Color)
		th.set_font_size(&"font_size", String(pair[0]), FONT_BODY)
		th.set_constant(&"outline_size", String(pair[0]), 4)


## battle_sim/ui/HudBuilder · PilotStrip — 전투 HUD (`Hud*` · `PilotStrip*`).
## 씬: `UI_View_BattleHud.tscn` · `UI_Comp_PilotStrip.tscn` · `UI_Comp_PilotStripCell.tscn`. 색이 데이터인 판(성장치 탭
## 테 = 팀색, 차례 알림 띠의 위아래 줄 = `TURN_BAR`)은 변형이 모양 + 미리보기 색이고 코드가
## `variation_box()` 사본에 색만 넣는다.
static func _add_hud_variations(th: Theme) -> void:
	# 경과 시계 — 흰 알약(라벨 자신의 `normal` 판) 위 진한 글자.
	var clock := with_shadow(box(PANEL_BG, 999))
	clock.content_margin_left = CLOCK_PAD.x
	clock.content_margin_right = CLOCK_PAD.x
	clock.content_margin_top = CLOCK_PAD.y
	clock.content_margin_bottom = CLOCK_PAD.y
	clock.shadow_size = 4
	clock.shadow_offset = Vector2(0.0, 2.0)
	_add_derived_label(th, "HudClockLabel", &"BattleTextLabel", TEXT_CLOCK)
	th.set_font_size(&"font_size", &"HudClockLabel", FONT_CAPTION)
	th.set_stylebox(&"normal", &"HudClockLabel", clock)
	# 스트립 뒤판 — 보이지 않는 판(자리 · z-order 기준만, `HudBuilder` STRIP_BACKDROP_NOTE).
	_add_derived(th, "HudStripBackdrop", &"BattleDimPanel", StyleBoxEmpty.new())
	# 차례 알림 — 흰 띠 + 위아래 4px 진영색 줄(색 = `TURN_BAR[팀]`, 코드가 사본의
	# `border_color` 에 넣는다) + 진영색 큰 글자(코드가 `SIDE_TEXT[팀]` 을 넣는다).
	var bar := with_shadow(box(PANEL_BG, 0))
	bar.border_color = TURN_BAR[0]
	bar.border_width_top = 4
	bar.border_width_bottom = 4
	bar.anti_aliasing = false
	_add_derived(th, "HudTurnBar", &"BattleDimPanel", bar)
	_add_derived_label(th, "HudTurnLabel", &"BattleTextLabel", SIDE_TEXT[0])
	th.set_font_size(&"font_size", &"HudTurnLabel", 56)
	# 결과 화면 — 뒤 딤(아웃게임 모달 딤) · MVP 줄 K/D/A. (판은 공용 `BattleGoldModal`,
	# 결과 줄 · MVP 이름은 `BattleTextLabel`, "MVP" 는 `BattleTitleLabel`, 버튼은 `BattleGoldButton`.)
	_add_derived(th, "HudVictoryDimPanel", &"BattleDimPanel", box(DIM_LIGHT, 0))
	_add_derived_label(th, "HudVictoryKdaLabel", &"BattleSubLabel", TEXT_KDA)
	th.set_font_size(&"font_size", &"HudVictoryKdaLabel", 26)

	# 파일럿 스트립 칸 — 원 아래 성장치 탭. **흰 판으로 바꾸지 않는다**(사용자 결정): 원과 같은
	# 팀색 면(색 = `TEAM_DISC[팀]`, 코드가 사본의 `bg_color` 에 넣는다) + 외곽선 두른 밝은 글자.
	var tab := box(TEAM_DISC[0], SCORE_TAB_RADIUS)
	tab.anti_aliasing = true
	_add_derived(th, "PilotStripScoreTab", &"BattleDimPanel", tab)
	_add_derived_label(th, "PilotStripScoreLabel", &"BattleOutlinedLabel", TEXT_SCORE)
	th.set_font_size(&"font_size", &"PilotStripScoreLabel", 20)
	th.set_color(&"font_outline_color", &"PilotStripScoreLabel", Color(0.0, 0.0, 0.0, 0.6))
	th.set_constant(&"outline_size", &"PilotStripScoreLabel", 3)
	# 턴 넘기기 판(`UI_Comp_TurnEndPanel.tscn`) — 앰버 테 흰 판, 누르는 동안 차는 앰버 틴트
	# 게이지(판 안쪽 8px 인셋이라 모서리 = PANEL_RADIUS − 4), 진한 글자.
	var te_plate := gold_box()
	te_plate.set_corner_radius_all(PANEL_RADIUS)
	_add_derived(th, "TurnEndPanelPlate", &"BattleGoldPanel", te_plate)
	_add_derived(th, "TurnEndGauge", &"BattleDimPanel", box(CHIP_BG_HL, PANEL_RADIUS - 4))
	_add_derived_label(th, "TurnEndLabel", &"BattleTextLabel", TEXT)
	th.set_font_size(&"font_size", &"TurnEndLabel", FONT_TITLE)
	# 부활까지 남은 턴 — 원 한가운데 큰 숫자(크기 = 원 지름 × 0.42). 원(그림) 위라 외곽선.
	_add_derived_label(th, "PilotStripDeadLabel", &"BattleOutlinedLabel", DEAD)
	th.set_font_size(&"font_size", &"PilotStripDeadLabel", 53)


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
	# 그 띠 위의 값 — 어두운 띠 위라 흰 글자.
	_add_derived_label(th, "PilotDetailFxBandLabel", &"BattleValueLabel", TEXT_ON_FILL)
	# 칸 설명 판 — 카드 설명판과 같은 모양(`desc_box`, `CardDescBox.panel_style(false)` 도 이것), 안쪽 여백 20 / 16.
	var menu := desc_box()
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
	th.set_color(&"default_color", &"PilotDetailNoteText", DESC_BODY)
	# 칸 설명 판(어두운 판) 안의 글자 · 효과 칸 — 예전 어두운 팔레트 색.
	_add_derived_label(th, "PilotDetailMenuTitleLabel", &"BattleHeaderLabel", DESC_HEADER)
	_add_derived_label(th, "PilotDetailMenuKeyLabel", &"BattleKeyLabel", DESC_KEY)
	_add_derived_label(th, "PilotDetailMenuValueLabel", &"BattleValueLabel", DESC_VALUE)
	_add_derived_label(th, "PilotDetailMenuPositiveLabel", &"BattlePositiveLabel", DESC_POSITIVE)
	_add_derived_label(th, "PilotDetailMenuNegativeLabel", &"BattleNegativeLabel", DESC_NEGATIVE)
	_add_button(th, "PilotDetailMenuFxButton", -1, _same_states(
			box(DESC_CHIP_BG, FX_RADIUS, DESC_CHIP_BORDER, CHIP_BORDER_W)))
	th.set_type_variation(&"PilotDetailMenuFxButton", &"BattleFxButton")


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


## 버튼 변형의 글자색 — 누름 · 올림 · 포커스 모두 `fg`, 비활성은 `TEXT_FAINT`.
static func _set_button_font_colors(th: Theme, variation: String, fg: Color) -> void:
	for c in OutgameTheme.BUTTON_FONT_COLORS:
		th.set_color(c, variation, fg)
	th.set_color(&"font_disabled_color", variation, TEXT_FAINT)


## 누르든 올리든 같은 판(상태는 일반 / 강조 변형이 말한다). 비활성은 엔진 기본.
static func _same_states(sb: StyleBoxFlat) -> Dictionary:
	return {"normal": sb, "hover": sb.duplicate(), "pressed": sb.duplicate(),
			"hover_pressed": sb.duplicate(), "focus": sb.duplicate()}


static func _add_label(th: Theme, variation: String, font_size: int, color: Color) -> void:
	th.set_type_variation(variation, &"Label")
	th.set_font_size(&"font_size", variation, font_size)
	th.set_color(&"font_color", variation, color)
