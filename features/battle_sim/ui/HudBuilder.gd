class_name HudBuilder
extends Node

@onready var _bs: BattleSim = get_parent() as BattleSim

# ── 안전 영역 오프셋 ─────────────────────────────────────────────────────────
# 아래의 모든 상수는 **1080×1920 디자인 화면**에 적힌 값 그대로이고, 실제 기기
# 대응은 그 값들을 건드리지 않고 **덩어리째 미는 것**으로 한다. 상단 패널 ↔
# 상대 손패 peek ↔ 적 도넛 ↔ 킬로그가 서로 픽셀 단위로 맞물려 있고(위 주석의
# "사슬"), 하단도 핸드 부채꼴 ↔ 카드 밑단 ↔ 아군 스트립이 마찬가지라, 상수를
# 하나씩 기기 대응으로 바꾸면 그 관계가 조용히 어긋난다. 스칼라 두 개면 관계는
# 전부 보존된다.
#
# 9:16 화면 · 인셋 0 이면 둘 다 0 이라 예전 배치와 한 픽셀도 다르지 않다.


## 상단 덩어리를 밀어 내리는 양 — 노치 / 다이나믹 아일랜드 / 상태 표시줄.
static func top_offset() -> float:
	return ScreenMetrics.top_y()


## 하단 덩어리를 밀어 내리는(음수면 올리는) 양 — 디자인 바닥(1920)과 실제
## 안전 바닥의 차. 화면이 길면 양수, 홈 인디케이터가 1920 안쪽을 파고들면
## 음수다.
static func bottom_offset() -> float:
	return ScreenMetrics.bottom_y() - ScreenMetrics.BASE_H

# ── 상단 패널 (시간 + 팀 점수 + 적 파일럿 스트립) ─────────────────────────────
# 예전에는 이 패널 하나가 열 명 전부를 84px 슬롯으로 담았다(아군 좌 / 점수 중앙 /
# 적 우). 지금은 **적 다섯만** 여기 있고, 아군 다섯은 핸드 행 아래로 내려갔다.
#
# 헤더 줄(y 4..38) 아래가 **스트립 띠**(y 46..127)이고 거기에 5px 를 더한 값이
# 이 높이다. 띠 안에서 적 스트립은 가운데 672px 만 쓰고, 남은 좌우 여백이
# **오브젝트 시계 두 칸**이다(`OBJ_TIMER_*`).
#
# **패널 높이는 내용이 정한다** — 헤더 + 스트립 띠 + 5px 여백, 그게 전부다.
# 예전 168 은 스트립이 아군과 같은 크기(1030×122)이던 시절의 값인데, 스트립이
# 60% 로 줄어든 뒤에도 그대로 남아 띠 아래에 27px 짜리 빈 칸이 붙어 있었다.
#
# 그 아래가 사슬이다 — 패널이 상대 핸드 peek 의 윗부분을 가리는 가림막이고,
# peek 카드 아래 끝에서 `DONUT_AI_HAND_GAP` 만큼 띄운 자리가 적 도넛이며, 그
# 도넛 아래가 곧 전장 픽셀 상단(y 369)이다. **패널 높이를 바꾸면
# `AI_HAND_TOP_Y`(= `TOP_PANEL_H − 50`) 와 `KillFeed.FEED_TOP`(= `TOP_PANEL_H
# + 8`) 을 같은 양만큼 함께 옮겨야 한다** — 전자를 두면 peek 이 패널 뒤로
# 통째로 숨거나(키울 때) 카드 윗부분이 그대로 드러나고(줄일 때), 후자를 두면
# 킬로그가 패널에서 떨어져 뜬다. 도넛은 `AI_HAND_TOP_Y` 에서 계산되므로 따로
# 만질 것이 없다.
#
# 132 로 줄면서 peek 이 82 로, 적 도넛 아래끝이 349 → 311 로 함께 올라왔다 —
# peek 이 드러나는 양(49px)은 그대로이고 전장 상단(369)까지의 여유만
# 20 → 58px 로 늘었다. 그 뒤 적 스트립이 20% 커지며 **148** 이 됐고(띠
# 46..143 + 5), 사슬도 같은 16px 씩 내려갔다 — peek 98, 적 도넛 아래끝 327,
# 킬로그 156. 전장 상단까지의 여유는 42px 로 아직 넉넉하다.
const TOP_PANEL_Y      := 0.0
const TOP_PANEL_H      := 148.0
## 시간 · 팀 점수 한 줄.
const HEADER_ROW_Y     := 4.0
const HEADER_ROW_H     := 34.0
const TIME_FONT        := 18
const TOTAL_SCORE_FONT := 26
## 적 스트립 — 패널 로컬 좌표. **아군 스트립을 66% 로 줄인 것**이고 가로
## 가운데에 놓는다(폭 672, 초상화 118×49). 한때는 아군과 정확히 같은 크기
## (1030×122, 초상화 190×79)였다 — 그 전의 730×84 축소판이 같은 얼굴을 위아래
## 두 배 다른 크기로 보여 준 탓이었다.
##
## 줄인 이유는 자리다. 오브젝트 등장 시계가 전장 타일에서 이 패널로 올라
## 오면서 **스트립 양옆에 아이콘 + 턴 수가 앉을 칸**이 필요해졌다(좌 전령 /
## 우 용 — 지도의 좌우와 같은 배치라 자리가 곧 이름이다). 성장치는 그대로 두
## 자릿수까지 읽히므로 "내 것과 나란히 비교한다"는 원래 목적은 살아 있다.
##
## 처음 줄일 때는 60%(618×76, 초상화 108×45)였는데 얼굴이 그 크기에서 누가
## 누구인지 읽히는 하한을 밑돌았다. 초상화 폭은 칸 폭에서 유도되므로
## (`PilotStrip.setup`) 키우는 방법은 스트립 폭을 미는 것뿐이라 618 → 672 로
## 한 번(초상화 +10%), 다시 **672 → 806 으로 한 번 더(+20%)** 밀었다. 높이도
## eye 비(2.4:1)를 따라 76 → 81 → **97** 로 함께 올라간다(초상화 145×60).
##
## 그만큼 좌우 여백이 줄어 시계 칸은 190 → 168 → **101** 이 됐다 — 시계 쪽에서
## 아이콘과 숫자 사이 여백을 줄이고 "턴" 글자를 지워 그 폭에 맞췄다
## (`ObjectiveTimer`). 얼굴이 먼저 읽혀야 하는 패널이므로 자리를 다툴 때
## 물러나는 쪽은 언제나 시계다.
const ENEMY_STRIP_RECT := Rect2(137.0, 46.0, 806.0, 97.0)
const ENEMY_SCORE_FONT := 14
const ENEMY_HP_H       := 7.0

## 오브젝트 시계 두 칸 — 스트립 양옆의 남은 여백.
##
## **세로는 적 초상화 띠와 정확히 같다**(y 46, 높이 60 ≈ `_portrait_h`). 한때는
## 스트립 띠 전체(122px)를 썼는데 — 아이콘이 클수록 곁눈으로 읽힌다는 이유였다 —
## 그러면 시계가 초상화보다 위아래로 튀어나와 패널 안에서 가장 큰 물체가 되고,
## 정작 얼굴 쪽으로 가야 할 시선을 먼저 잡아챈다. 초상화와 밑단·윗단을 맞추면
## 셋(좌 시계 · 얼굴 다섯 · 우 시계)이 한 줄로 읽힌다.
const OBJ_TIMER_W  := 101.0
const OBJ_TIMER_Y  := 46.0
const OBJ_TIMER_H  := 60.0
## 좌우 여백은 대칭이므로 왼쪽 하나만 상수로 두고 오른쪽은 뷰포트 가로에서
## 역산한다 — 예전의 `OBJ_TIMER_RIGHT_X = 953`(= 1080 − 101 − 26)은 가로가
## 1080 보다 넓어질 수 있게 되면서 가운데 정렬을 깨뜨렸다.
const OBJ_TIMER_LEFT_X  := 26.0

# ── 하단 아군 스트립 (핸드 행 아래) ───────────────────────────────────────────
# 핸드 행은 y 1500..1720, 그 아래가 통째로 비어 있었다(예전 하단 코스트 바 자리).
#
# y 1766 은 카드 밑단에서 계산해 나온 값이다. 부채꼴의 **양 끝 카드는 가운데보다
# 21.4px 아래로 처지고**(12장 기준), 호버/선택 시 `Card.HOVER_SCALE`(1.2)로
# 커지므로 최악의 경우 카드 밑단이 y ≈ 1763 까지 내려온다. 1724 에 두었더니
# 카드가 초상화 윗부분을 덮었다(실측 확인). 아이폰 홈 바를 위해 바닥 ~32px 도
# 남긴다 — 위아래가 다 막힌 122px 안에 초상화 · 체력 바 · 성장치가 들어간다.
const PLAYER_STRIP_RECT := Rect2(25.0, 1766.0, 1030.0, 122.0)
const PLAYER_SCORE_FONT := 20
const PLAYER_HP_H       := 10.0
## 아군 스트립 뒤판 — 스트립 영역을 `PLAYER_BG_PAD` 만큼 사방으로 넓힌 짙은
## 패널 한 장. 적 스트립은 상단 패널 위에 앉아 있어 처음부터 받침이 있었지만,
## 아군 스트립은 맨 화면 위에 떠 있어 얼굴·체력 바·성장치 세 줄이 배경 없이
## 흩어져 보였다 — 특히 성장치 숫자는 받침이 없으면 어디까지가 한 파일럿의
## 칸인지가 안 읽힌다. 색과 테두리는 상단 패널과 같게 두어 위아래 두 스트립이
## 같은 판 위에 앉은 것으로 보이게 한다.
const PLAYER_BG_PAD     := 10.0
const STRIP_BG_COLOR    := Color(0.06, 0.06, 0.10, 1.0)
const STRIP_BG_BORDER   := Color(0.18, 0.18, 0.24, 1.0)

# ── AI hand peek (below score panel) ─────────────────────────────────────────
# AI hand is shown as a fan of card-back nodes whose tops are tucked behind the
# score panel — only the bottom strip of each card protrudes, giving an "edge of
# the cards" look that conveys hand size.
#
# The fan is the player hand's fan **flipped top-to-bottom**: every card centre
# rides one circle whose pivot sits *above* the row, so the middle card reaches
# the lowest point of the arc (it protrudes furthest down past the panel) and
# both ends curl back up under it. Card tilt is the negated arc angle, which
# mirrors the player fan's lean without standing the cards on their heads.
#
# Geometry, per card i of n (θ measured from straight-down at the pivot):
#   θ_i    = (i − (n−1)/2) · step
#   centre = pivot + R·(sin θ, cos θ)          ← +cos, so θ=0 is the LOWEST point
#   tilt   = −θ_i
# Adjacent centres therefore sit R·sin(step) apart; at the values below that is
# ~34.6 px against a 72 px card, i.e. the cards overlap by a bit over half.
const AI_HAND_SCALE  := 0.45
## Top of the MIDDLE card; the rest ride higher. Tied to TOP_PANEL_H — the panel
## must hide the card's top 50 px so only the bottom ~49 px peeks out, so this is
## `TOP_PANEL_H − 50`. Move the panel and this moves with it.
const AI_HAND_TOP_Y  := 98.0
## Circle radius (px) the card centres ride. Larger = flatter arc.
const AI_HAND_FAN_RADIUS := 620.0
## Angular step (deg) per card. Sets the horizontal overlap via R·sin(step).
const AI_HAND_FAN_STEP_DEG := 3.2
## Hard cap on the fan's total angular width. Without it a full hand would swing
## its end cards so far up the arc that they vanish behind the score panel — at
## 28° the outermost card rides only R·(1−cos 14°) ≈ 18 px above the middle one.
const AI_HAND_FAN_MAX_SPREAD_DEG := 28.0

# ── 전략 포인트 도넛 (cost gauges) ────────────────────────────────────────────
# The old bottom cell-bar stack and the rectangular 단계 넘기기 button are gone.
# Both sides now read out on a ring gauge in the **left-hand** gutter (the
# targeting overlay's 확인 / 취소 row owns the bottom-right corner):
#   player — above the Deck counter, top-left of the hand row; doubles as
#            the 턴 넘기기 button once tapped (see CostDonut).
#   enemy  — top-left of the screen, just under the AI hand peek.
const DONUT_FILL_PLAYER := Color(0.25, 0.60, 1.00)
const DONUT_FILL_ENEMY  := Color(0.95, 0.35, 0.25)
## Vertical gap between the player donut and the targeting overlay's
## 취소 / 확인 button row, which itself hovers just above the hand row. Keeping
## the donut clear of that band means the two never overlap mid-targeting.
const DONUT_HAND_GAP    := 24.0
## Vertical gap between the AI hand peek's bottom edge and the enemy donut.
const DONUT_AI_HAND_GAP := 20.0
## Fallback 100% mark used before DataLoader fills PHASE_THRESHOLD.
const DONUT_DEFAULT_MAX := 8

# ── 파일럿 스트립 refs ────────────────────────────────────────────────────────
var _enemy_strip:  PilotStrip = null   # team 1, 화면 상단
var _player_strip: PilotStrip = null   # team 0, 핸드 행 아래
## 아군 스트립 뒤판. 스트립과 **함께** 숨어야 한다 — 상세 패널이 스트립만
## 치우면 빈 판이 딤 위에 덩그러니 남는다.
var _player_strip_bg: Panel = null
## 적 스트립 좌우의 오브젝트 등장 시계 — 좌 전령 / 우 용.
var _obj_timers: Array = []           # Array[ObjectiveTimer]

# ── Deck / Discard 카운터 히트 버튼 ───────────────────────────────────────────
# 카운터 라벨 위에 얹힌 투명 버튼. 누르면 CardPileViewer 가 그 더미의 카드를
# 목록으로 펼친다 (작전 단계 한정 — _update_pile_buttons 가 활성 상태를 관리).
var _btn_deck_view:    Button = null
var _btn_discard_view: Button = null

# ── Center labels ────────────────────────────────────────────────────────────
var _lbl_time: Label = null
var _lbl_total_score: Label = null


# ── AI hand peek refs ────────────────────────────────────────────────────────
# `_ai_hand_root` is added to the canvas BEFORE `_build_top_panel`, so the
# score panel z-orders above it and visually clips the cards' top portion.
var _ai_hand_root:        Control = null
var _ai_card_back_nodes:  Array   = []   # Array<Card> — face-down cards

# ── Turn announcer refs ──────────────────────────────────────────────────────
# Centre-screen "당신의 차례 / 상대 차례" banner shown when CARD_PHASE starts
# (player) or before the AI's run_ai_plays loop (enemy). Built last so it
# z-orders above every other HUD element including the AI hand.
var _turn_announce_root: Control = null


func build_ui() -> void:
	_bs.canvas = CanvasLayer.new()
	_bs.add_child(_bs.canvas)

	# AI hand peek must build BEFORE the score panel so the panel's opaque
	# background covers the cards' top portion (sibling z-order = child index).
	_build_ai_hand_peek()
	_build_top_panel()
	_build_player_strip()
	_build_kill_feed()
	_build_hand_indicators()
	_build_cost_donuts()
	_build_victory_panel()
	# Turn announcer added last so its banner draws over everything.
	_build_turn_announcer()


# ── Deck / Discard 카드 뭉치 ─────────────────────────────────────────────────
# Live in the BS_HAND_AREA_MARGIN gutters on either side of the hand row.
# The hand row spans y=BS_HAND_CENTER.y .. y=BS_HAND_CENTER.y + Card.CARD_H,
# so we centre the piles vertically across that same band.
#
# 예전에는 이 자리에 `"Deck\n18"` 두 줄 Label 하나였다. 지금은 같은 rect 안에
# **앞으로 누운 카드 뭉치**(`CardPileStack`)를 그린다 — 뒷면이 위를 향한 채
# 겹쳐 쌓이고, 두께가 실제 장수에 비례하며, 장수는 맨 위 카드 뒷면에 찍힌다.
# 자리와 크기(gutter · inset)는 그대로라 도넛 · 핸드 · 전장은 손대지 않았다.
const HAND_INDICATOR_FONT       := 22
const HAND_INDICATOR_TITLE_COL  := Color(0.85, 0.85, 0.85)
## 목록을 열 수 없는 상태에서 뭉치에 씌우는 알파.
const PILE_LABEL_DIM_ALPHA      := 0.45
# 예전에는 뒷면 안쪽에 더미별 accent 무늬(덱 보라 / 버린 더미 적갈)를 덧그렸다.
# 뭉치가 작아 그 액자가 무늬가 아니라 면에 얹힌 계조로 읽혀 삭제했고, 두 더미는
# 아래 제목 라벨이 가른다 — `CardPileStack.BACK_FILL` 주석 참고.
func _build_hand_indicators() -> void:
	var hand_y: float = _bs.BS_HAND_CENTER.y
	var hand_h: float = Card.CARD_H
	var screen_w := get_viewport().get_visible_rect().size.x
	# BS_HAND_WIDTH_SCALE widens the card row past the nominal margin, so the
	# real gutter is whatever is left beside the hand — never wider than the
	# nominal margin, and never overlapped by the outermost card.
	var margin: float = min(_bs.BS_HAND_AREA_MARGIN,
			(screen_w - _bs.BS_HAND_WIDTH) * 0.5)
	# Inset a few px so the pile doesn't kiss the screen edge. 예전 라벨은 8px
	# 씩 물러났는데, 뭉치는 폭이 곧 카드 크기라 4px 만 남기고 최대한 넓게 쓴다.
	var inset: float  = 4.0
	var w: float      = max(1.0, margin - inset * 2.0)
	# Shrink the font when the gutter is tighter than nominal so "Discard"
	# still fits inside it (~3.5 px of glyph per point of font size).
	var font_size: int = clampi(int(w / 3.5), 12, HAND_INDICATOR_FONT)

	_bs.pile_deck = _make_pile_stack("Deck", font_size,
			Vector2(inset, hand_y), Vector2(w, hand_h))
	_bs.pile_discard = _make_pile_stack("Discard", font_size,
			Vector2(screen_w - margin + inset, hand_y), Vector2(w, hand_h))

	# 두 뭉치는 눌러서 해당 더미의 카드 목록을 펼치는 버튼이기도 하다.
	# `CardPileStack` 은 스스로 MOUSE_FILTER_IGNORE 라 클릭을 받지 못하므로,
	# 뭉치 rect 를 그대로 덮는 투명 Button 을 얹어 입력만 가져간다.
	_btn_deck_view = _make_pile_button(_bs.pile_deck,
			CardPileViewer.Pile.DECK)
	_btn_discard_view = _make_pile_button(_bs.pile_discard,
			CardPileViewer.Pile.DISCARD)
	_update_pile_buttons()


# `setup()` 은 size 에서 폰트 크기와 자리를 유도하므로 **size 를 넣은 뒤**에
# 불러야 한다. 트리에 붙이는 것도 그 전이어야 _ready 의 mouse_filter 가 선다.
func _make_pile_stack(title: String, font_size: int,
		at: Vector2, of_size: Vector2) -> CardPileStack:
	var pile := CardPileStack.new()
	pile.name = "CardPile" + title
	pile.position = at
	pile.size     = of_size
	_bs.canvas.add_child(pile)
	pile.setup(title, font_size)
	return pile


# 뭉치 위에 얹는 투명 히트 버튼. flat + alpha 0 이라 뭉치의 생김새는
# 그대로 두고 클릭만 가로챈다.
func _make_pile_button(anchor: Control, which: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.modulate = Color(1, 1, 1, 0)
	b.position = anchor.position
	b.size = anchor.size
	b.pressed.connect(func() -> void: _on_pile_button_pressed(which))
	_bs.canvas.add_child(b)
	return b


func _on_pile_button_pressed(which: int) -> void:
	if _bs.card_pile_viewer == null:
		return
	if _bs.card_phase == null or not _bs.card_phase.can_browse_piles():
		return
	_bs.card_pile_viewer.open(which)


# 열람이 불가능한 상태(BATTLE 진행 중, 상대 차례, 다른 오버레이 활성)에서는
# 버튼을 비활성화하고 뭉치를 흐리게 해 "지금은 못 연다"를 보여 준다.
func _update_pile_buttons() -> void:
	var can: bool = _bs.card_phase != null and _bs.card_phase.can_browse_piles()
	if _btn_deck_view != null:
		_btn_deck_view.disabled = not can
	if _btn_discard_view != null:
		_btn_discard_view.disabled = not can
	if _bs.pile_deck != null:
		_bs.pile_deck.set_dimmed(not can)
	if _bs.pile_discard != null:
		_bs.pile_discard.set_dimmed(not can)


# ── 상단 패널: 시간 · 팀 점수 한 줄 + 그 아래 적 파일럿 스트립 ────────────────
func _build_top_panel() -> void:
	var tp := Panel.new()
	var vp_w: float = ScreenMetrics.vp_w()
	tp.position = Vector2(0.0, TOP_PANEL_Y + top_offset())
	tp.size     = Vector2(vp_w, TOP_PANEL_H)
	# Force an opaque dark background so the AI hand card backs sitting
	# behind this panel are visually clipped to the peek strip below.
	var tp_style := StyleBoxFlat.new()
	tp_style.bg_color = Color(0.06, 0.06, 0.10, 1.0)
	tp_style.border_color = Color(0.18, 0.18, 0.24, 1.0)
	tp_style.border_width_top    = 1
	tp_style.border_width_bottom = 1
	tp_style.border_width_left   = 1
	tp_style.border_width_right  = 1
	tp.add_theme_stylebox_override("panel", tp_style)
	_bs.canvas.add_child(tp)

	# 시계는 왼쪽 끝, 팀 점수는 가운데. 둘이 같은 줄에 앉는다.
	_lbl_time = UiHelpers.mk_label(tp, "00:00", TIME_FONT,
			Color(0.85, 0.85, 0.85),
			Vector2(20.0, HEADER_ROW_Y), Vector2(220.0, HEADER_ROW_H),
			HORIZONTAL_ALIGNMENT_LEFT)
	_lbl_total_score = UiHelpers.mk_label(tp, "", TOTAL_SCORE_FONT,
			Color(1.0, 0.95, 0.6),
			Vector2(0.0, HEADER_ROW_Y), Vector2(vp_w, HEADER_ROW_H),
			HORIZONTAL_ALIGNMENT_CENTER)

	# 적 스트립은 패널의 자식이라 패널 배경 위에 그려진다(= 상대 핸드 peek 을
	# 가리는 가림막의 일부).
	# 적 스트립도 **눌러서 상세 패널을 연다** — 아군과 같은 게이트(작전 단계),
	# 같은 내용(인게임 · 파일럿 · 메크). 상대 로스터는 이미 `match_ctx.enemy_roster`
	# 로 들어와 있어 `BattleSim.player_data_for` 가 그대로 찾아 준다.
	_enemy_strip = PilotStrip.new()
	_enemy_strip.name = "EnemyPilotStrip"
	tp.add_child(_enemy_strip)
	var strip_rect := Rect2(
			Vector2((vp_w - ENEMY_STRIP_RECT.size.x) * 0.5, ENEMY_STRIP_RECT.position.y),
			ENEMY_STRIP_RECT.size)
	_enemy_strip.setup(_bs, 1, strip_rect, true,
			ENEMY_SCORE_FONT, ENEMY_HP_H)
	_enemy_strip.pilot_pressed.connect(_on_pilot_strip_pressed)

	# 오브젝트 등장 시계 — 스트립 양옆. 전령이 왼쪽 · 용이 오른쪽인 것은
	# 전장에서 두 오브젝트가 서는 칸의 좌우와 같다.
	_obj_timers.clear()
	var timer_right_x: float = vp_w - OBJ_TIMER_W - OBJ_TIMER_LEFT_X
	for spec in [[ObjectiveSystem.Kind.HERALD, OBJ_TIMER_LEFT_X],
			[ObjectiveSystem.Kind.DRAGON, timer_right_x]]:
		var timer := ObjectiveTimer.new()
		timer.name = "ObjTimer%d" % int(spec[0])
		tp.add_child(timer)
		timer.position = Vector2(float(spec[1]), OBJ_TIMER_Y)
		timer.size = Vector2(OBJ_TIMER_W, OBJ_TIMER_H)
		timer.setup(_bs, int(spec[0]))
		# 누르면 그 오브젝트의 보상 카드를 실물로 띄운다. 회피할 수 있는
		# 사건이므로 무엇을 주는지는 결판 전에 볼 수 있어야 한다.
		timer.timer_pressed.connect(_on_obj_timer_pressed)
		_obj_timers.append(timer)


func _on_obj_timer_pressed(kind: int) -> void:
	if _bs.objective_reward != null:
		_bs.objective_reward.toggle(kind)


# ── 하단 아군 스트립 ─────────────────────────────────────────────────────────
# 핸드 행 아래. 누르면 파일럿 상세 패널이 열린다 — 다만 **자기 작전 단계에만**
# 눌린다(`_update_pilot_strips` 가 버튼 활성 상태를 관리).
## 아군 스트립의 실제 자리 — 디자인 좌표를 안전 영역만큼 민 것. 가로도 뷰포트
## 기준으로 다시 가운데 잡는다(태블릿에서 1080 이 가운데가 아니다).
static func player_strip_rect() -> Rect2:
	var vp_w: float = ScreenMetrics.vp_w()
	return Rect2(
			Vector2((vp_w - PLAYER_STRIP_RECT.size.x) * 0.5,
					PLAYER_STRIP_RECT.position.y + bottom_offset()),
			PLAYER_STRIP_RECT.size)


func _build_player_strip() -> void:
	# 뒤판을 **먼저** 붙인다 — 형제 z-order 가 곧 자식 인덱스라, 나중에 붙으면
	# 판이 초상화를 덮는다.
	var bg := Panel.new()
	bg.name = "PlayerStripBackdrop"
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_rect := player_strip_rect()
	bg.position = strip_rect.position - Vector2(PLAYER_BG_PAD, PLAYER_BG_PAD)
	bg.size = strip_rect.size + Vector2(PLAYER_BG_PAD, PLAYER_BG_PAD) * 2.0
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = STRIP_BG_COLOR
	bg_style.border_color = STRIP_BG_BORDER
	bg_style.border_width_top    = 1
	bg_style.border_width_bottom = 1
	bg_style.border_width_left   = 1
	bg_style.border_width_right  = 1
	bg.add_theme_stylebox_override("panel", bg_style)
	_bs.canvas.add_child(bg)
	_player_strip_bg = bg

	_player_strip = PilotStrip.new()
	_player_strip.name = "PlayerPilotStrip"
	_bs.canvas.add_child(_player_strip)
	_player_strip.setup(_bs, 0, strip_rect, true,
			PLAYER_SCORE_FONT, PLAYER_HP_H)
	_player_strip.pilot_pressed.connect(_on_pilot_strip_pressed)


# ── 킬로그 ───────────────────────────────────────────────────────────────────
# 적 스트립 바로 아래, 화면 우측. **상단 패널보다 뒤에 붙는다** — 형제 z-order 가
# 곧 자식 인덱스라, peek 카드 위에 그려져야 줄이 카드에 잘리지 않는다.
func _build_kill_feed() -> void:
	_bs.kill_feed = KillFeed.new()
	_bs.kill_feed.name = "KillFeed"
	_bs.canvas.add_child(_bs.kill_feed)
	_bs.kill_feed.setup(_bs)


func _on_pilot_strip_pressed(p: PilotData) -> void:
	if _bs.pilot_detail == null:
		return
	if _bs.game_phase != GameEnums.BattlePhase.CARD_PHASE:
		return
	_bs.pilot_detail.open(p)


## 상세 패널이 열려 있는 동안 **그 파일럿이 속한 팀의 스트립**을 치운다 — 딤 위에
## 남으면 지금 무엇을 보고 있는지가 흐려지고, 딤 아래로 넣으면 방금 누른 얼굴이
## 어두워진다. 반대 팀 스트립은 그대로 둔다(딤에 가려질 뿐이고, 치우면 화면에서
## 무엇이 사라졌는지가 더 헷갈린다).
## 아군 스트립 뒤판 노드. `CardPhaseManager` 가 두 가지로 읽는다 — 내 차례가
## 아닐 때 손패 카드를 **이 판보다 뒤로** 내려보낼 기준 노드이고(형제 z-order 가
## 곧 자식 인덱스다), 카드가 얼마나 내려가야 절반쯤 가려지는지를 재는 자다.
func player_strip_backdrop() -> Panel:
	return _player_strip_bg


## 그 뒤판의 위쪽 끝(y). 세이프 에어리어 오프셋이 이미 먹은 실제 좌표다.
func player_strip_backdrop_top() -> float:
	if _player_strip_bg != null and is_instance_valid(_player_strip_bg):
		return _player_strip_bg.position.y
	return player_strip_rect().position.y - PLAYER_BG_PAD


## 개시 전(정글 시작 선택) 동안 **지금 쓸 수 없는 HUD 를 걷는다** — 손패 행
## 양옆의 덱 / 버린 더미 뭉치(와 그 히트 버튼), 전략 포인트 도넛 둘, 상단
## 패널의 오브젝트 등장 시계 둘. 셋 다 아직 존재하지 않는 것을 0 으로 보여
## 주는 자리이고, 특히 손패 자리는 정글러 초상화가 통째로 쓴다.
##
## **파일럿 스트립과 상단 패널은 남는다** — 개시 직전에 양 팀 로스터를 다시
## 확인하는 것은 이 화면이 하는 일의 일부다.
func set_pregame_chrome_visible(on: bool) -> void:
	for node in [_bs.pile_deck, _bs.pile_discard, _btn_deck_view,
			_btn_discard_view, _bs.cost_donut, _bs.cost_donut_enemy]:
		var c := node as CanvasItem
		if c != null:
			c.visible = on
	for raw in _obj_timers:
		var t := raw as CanvasItem
		if t != null:
			t.visible = on


func set_strip_visible(team: int, on: bool) -> void:
	var strip: PilotStrip = _player_strip if team == 0 else _enemy_strip
	if strip != null:
		strip.visible = on
	if team == 0 and _player_strip_bg != null:
		_player_strip_bg.visible = on


# AI hand peek — row of face-down card backs whose tops hide behind the score
# panel. update_ai_hand_visuals() syncs the visible count to `_bs.ai_hand`.
func _build_ai_hand_peek() -> void:
	_ai_hand_root = Control.new()
	# 루트를 통째로 내리면 안쪽 부채꼴 좌표(`AI_HAND_TOP_Y` 기반)를 손대지 않고
	# 노치 아래로 옮겨진다.
	_ai_hand_root.position = Vector2(0.0, top_offset())
	_ai_hand_root.size     = ScreenMetrics.viewport_size()
	_ai_hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Force opaque dark background on the score panel later by giving the
	# panel an explicit StyleBoxFlat. The panel is created in `_build_top_panel`,
	# but we apply the override here so the AI cards always stay visually
	# clipped, even with a transparent default theme.
	_bs.canvas.add_child(_ai_hand_root)


# Sync `_ai_card_back_nodes` count with `_bs.ai_hand.size()` and reflow.
# Called from CardPhaseManager.do_battle_turn() after the AI draws, and from
# pop_ai_hand_card_node() after AiCardPlayer pulls a card out for the
# centre animation.
func update_ai_hand_visuals() -> void:
	if _ai_hand_root == null:
		return
	var n: int = _bs.ai_hand.size()
	while _ai_card_back_nodes.size() < n:
		var card := _bs.CARD_SCENE.instantiate() as Card
		card.scale = Vector2(AI_HAND_SCALE, AI_HAND_SCALE)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# add_child BEFORE setup — Card.gd's @onready refs only resolve after
		# the node enters the tree; setup() touches card_back/card_front.
		_ai_hand_root.add_child(card)
		card.setup(null, false, false)  # face-down card back
		# Belt-and-braces: card sub-controls also non-interactive.
		for child in card.get_children():
			if child is Control:
				(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ai_card_back_nodes.append(card)
	while _ai_card_back_nodes.size() > n:
		var node := _ai_card_back_nodes.pop_back() as Card
		if is_instance_valid(node):
			node.queue_free()
	_layout_ai_hand()


# Pops the rightmost card-back from the AI hand visuals and reparents it
# to `_bs.canvas` (preserving world position and scale), so AiCardPlayer can
# fly it freely to the centre of the screen. Returns null if the hand is
# already empty.
func pop_ai_hand_card_node() -> Card:
	if _ai_card_back_nodes.is_empty():
		return null
	var card := _ai_card_back_nodes.pop_back() as Card
	_layout_ai_hand()
	if not is_instance_valid(card):
		return null
	var world_pos: Vector2  = card.global_position
	var world_scale: Vector2 = card.scale
	var parent := card.get_parent()
	if parent != null:
		parent.remove_child(card)
	_bs.canvas.add_child(card)
	card.global_position = world_pos
	card.scale = world_scale
	return card


## 상대 손패의 **왼쪽 끝** 자리(뷰포트 좌표, 카드 좌상단 기준). 지금 손패보다
## 한 장 많은 부채꼴로 재므로, 여기로 날아온 카드가 실제로 앉을 자리와 맞는다.
##
## 쓰는 곳은 오브젝트 보상 연출(`objective/ObjectiveRewardFx.gd`) 하나다 —
## 적이 전령 / 용을 가져갔을 때 보상 카드가 빨려 들어가는 지점. 상대의 덱은
## 화면에 없으므로 손패 자리가 "상대 것이 됐다"를 말하는 유일한 좌표다.
func ai_hand_left_anchor() -> Vector2:
	var n: int = maxi(1, _ai_card_back_nodes.size() + 1)
	var step_deg: float = AI_HAND_FAN_STEP_DEG
	if n > 1:
		step_deg = min(step_deg, AI_HAND_FAN_MAX_SPREAD_DEG / float(n - 1))
	var half_card := Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	# `_ai_hand_root` 가 `top_offset()` 만큼 내려가 있으므로 로컬 → 뷰포트 변환에
	# 그 값을 더한다. 이 함수만 뷰포트 좌표를 약속한다(`_layout_ai_hand` 는 로컬).
	var mid_center_y: float = AI_HAND_TOP_Y + Card.CARD_H * AI_HAND_SCALE * 0.5 			+ top_offset()
	var pivot := Vector2(ScreenMetrics.center_x(), mid_center_y - AI_HAND_FAN_RADIUS)
	var theta: float = deg_to_rad(-float(n - 1) * 0.5 * step_deg)
	var centre: Vector2 = pivot + Vector2(sin(theta), cos(theta)) * AI_HAND_FAN_RADIUS
	return centre - half_card


# Lays the AI card backs out on the inverted fan described above. The step
# angle shrinks once the hand is wide enough to hit AI_HAND_FAN_MAX_SPREAD_DEG,
# so the row redistributes instead of growing — the same "fixed width, tighter
# overlap" rule the player hand follows.
func _layout_ai_hand() -> void:
	var n: int = _ai_card_back_nodes.size()
	if n == 0:
		return
	var step_deg: float = AI_HAND_FAN_STEP_DEG
	if n > 1:
		step_deg = min(step_deg, AI_HAND_FAN_MAX_SPREAD_DEG / float(n - 1))
	# The pivot sits directly above the middle card by exactly one radius, so
	# θ=0 lands that card's centre at AI_HAND_TOP_Y + half its scaled height.
	var half_card := Vector2(Card.CARD_W, Card.CARD_H) * 0.5
	var mid_center_y: float = AI_HAND_TOP_Y + Card.CARD_H * AI_HAND_SCALE * 0.5
	var pivot := Vector2(ScreenMetrics.center_x(), mid_center_y - AI_HAND_FAN_RADIUS)
	for i in n:
		var card := _ai_card_back_nodes[i] as Card
		var theta: float = deg_to_rad((float(i) - float(n - 1) * 0.5) * step_deg)
		var centre: Vector2 = pivot \
				+ Vector2(sin(theta), cos(theta)) * AI_HAND_FAN_RADIUS
		# Rotation and scale both pivot around `pivot_offset`, and a Control's
		# visual centre is `position + pivot_offset` — unscaled, unrotated (see
		# card_phase/README.md). So the top-left we want is centre − half_card,
		# with no scale correction.
		card.pivot_offset = half_card
		card.rotation = -theta
		card.position = centre - half_card


# ── Turn announcer ───────────────────────────────────────────────────────────
# A horizontal bar that sweeps in from the centre with the message
# "당신의 차례" / "상대 차례", holds briefly, then fades out. Caller awaits
# play_turn_announce(...) so input gating can re-enable on completion.
const TURN_ANNOUNCE_BAR_H        := 110.0
const TURN_ANNOUNCE_IN_DUR       := 0.32
const TURN_ANNOUNCE_HOLD_DUR     := 0.55
const TURN_ANNOUNCE_OUT_DUR      := 0.32
const TURN_ANNOUNCE_PLAYER_COLOR := Color(0.18, 0.45, 0.95, 0.92)
const TURN_ANNOUNCE_ENEMY_COLOR  := Color(0.95, 0.30, 0.25, 0.92)

func _build_turn_announcer() -> void:
	_turn_announce_root = Control.new()
	_turn_announce_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_turn_announce_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_announce_root.visible = false
	_bs.canvas.add_child(_turn_announce_root)


# Plays the centre-screen turn banner. `is_player == true` shows "당신의 차례"
# in blue; false shows "상대 차례" in red. Awaits the full sweep-in / hold /
# fade-out cycle so the caller can use it as a gate.
func play_turn_announce(is_player: bool) -> void:
	if _turn_announce_root == null:
		return
	for child in _turn_announce_root.get_children():
		child.queue_free()
	var bar_color: Color = TURN_ANNOUNCE_PLAYER_COLOR if is_player else TURN_ANNOUNCE_ENEMY_COLOR
	var msg: String      = "당신의 차례" if is_player else "상대 차례"
	var vp := ScreenMetrics.viewport_size()
	var center_y: float = vp.y * 0.5 - TURN_ANNOUNCE_BAR_H * 0.5

	var bar := ColorRect.new()
	bar.color = bar_color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(vp.x * 0.5, center_y)
	bar.size     = Vector2(0.0, TURN_ANNOUNCE_BAR_H)
	bar.pivot_offset = Vector2(0.0, TURN_ANNOUNCE_BAR_H * 0.5)
	_turn_announce_root.add_child(bar)

	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 56)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0.0, center_y)
	lbl.size     = Vector2(vp.x, TURN_ANNOUNCE_BAR_H)
	lbl.modulate = Color(1.0, 1.0, 1.0, 0.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_announce_root.add_child(lbl)

	_turn_announce_root.visible = true

	var tw_in := _bs.create_tween().set_parallel()
	tw_in.tween_property(bar, "size", Vector2(vp.x, TURN_ANNOUNCE_BAR_H),
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw_in.tween_property(bar, "position", Vector2(0.0, center_y),
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw_in.tween_property(lbl, "modulate", Color.WHITE,
			TURN_ANNOUNCE_IN_DUR).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	await tw_in.finished

	await _bs.get_tree().create_timer(TURN_ANNOUNCE_HOLD_DUR).timeout

	if not is_instance_valid(bar) or not is_instance_valid(lbl):
		_turn_announce_root.visible = false
		return
	var tw_out := _bs.create_tween().set_parallel()
	tw_out.tween_property(bar, "modulate", Color(1.0, 1.0, 1.0, 0.0),
			TURN_ANNOUNCE_OUT_DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw_out.tween_property(lbl, "modulate", Color(1.0, 1.0, 1.0, 0.0),
			TURN_ANNOUNCE_OUT_DUR).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	await tw_out.finished

	_turn_announce_root.visible = false
	for child in _turn_announce_root.get_children():
		child.queue_free()


# 전략 포인트 도넛 두 개를 화면 **좌측** 거터에 배치한다. 대상 지정 확인/취소
# 버튼이 우하단으로 옮겨 갔으므로 도넛 열은 반대편(좌측)을 차지한다.
#  - player: 핸드 좌측 상단 (Deck 카운터 바로 위). 탭하면 뒤집혀 턴 넘기기
#    원형 버튼이 되고, 바깥을 탭하면 다시 도넛으로 돌아온다.
#  - enemy: 화면 좌측 상단 (상대 핸드 peek 바로 아래). 표시 전용.
func _build_cost_donuts() -> void:
	var cx: float = _bs.BS_HAND_AREA_MARGIN * 0.5

	_bs.cost_donut_enemy = CostDonut.new()
	_bs.cost_donut_enemy.name = "CostDonutEnemy"
	_bs.canvas.add_child(_bs.cost_donut_enemy)
	_bs.cost_donut_enemy.fill_color = DONUT_FILL_ENEMY
	_bs.cost_donut_enemy.interactive = false
	var ai_hand_bottom: float = AI_HAND_TOP_Y + Card.CARD_H * AI_HAND_SCALE
	_bs.cost_donut_enemy.set_center(Vector2(cx, top_offset()
			+ ai_hand_bottom + DONUT_AI_HAND_GAP + CostDonut.RADIUS))

	_bs.cost_donut = CostDonut.new()
	_bs.cost_donut.name = "CostDonutPlayer"
	_bs.canvas.add_child(_bs.cost_donut)
	_bs.cost_donut.fill_color = DONUT_FILL_PLAYER
	_bs.cost_donut.interactive = true
	var targeting_btn_band: float = CardTargetingOverlay.BTN_HAND_GAP \
			+ CardTargetingOverlay.BTN_H
	_bs.cost_donut.set_center(Vector2(cx, _bs.BS_HAND_CENTER.y
			- targeting_btn_band - DONUT_HAND_GAP - CostDonut.RADIUS))
	_bs.cost_donut.end_turn_pressed.connect(_bs.card_phase.end_card_phase)


func _build_victory_panel() -> void:
	_bs.panel_victory = Panel.new()
	var vp := ScreenMetrics.viewport_size()
	_bs.panel_victory.size     = Vector2(700.0, 400.0)
	_bs.panel_victory.position = (vp - _bs.panel_victory.size) * 0.5
	_bs.panel_victory.visible  = false
	_bs.canvas.add_child(_bs.panel_victory)

	_bs.lbl_victory = Label.new()
	_bs.lbl_victory.add_theme_font_size_override("font_size", 48)
	_bs.lbl_victory.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bs.lbl_victory.position = Vector2(0.0, 80.0)
	_bs.lbl_victory.size     = Vector2(700.0, 80.0)
	_bs.panel_victory.add_child(_bs.lbl_victory)

	# Standalone runs replay the same battle; Season-driven runs return to the
	# campaign hub so LeagueManager can record the result.
	var season_mode: bool = _bs.gm.season_state.get("pending_match", null) != null
	var rb := Button.new()
	rb.text = "다음 →" if season_mode else "Play Again"
	rb.position = Vector2(200.0, 240.0)
	rb.size     = Vector2(300.0, 80.0)
	rb.add_theme_font_size_override("font_size", 32)
	if season_mode:
		rb.pressed.connect(_bs._on_return_to_season_pressed)
	else:
		rb.pressed.connect(_bs._on_restart_pressed)
	_bs.panel_victory.add_child(rb)


func update_hud() -> void:
	# Battle log is no longer surfaced on screen; `_bs.last_log` is still
	# updated by effect handlers for diagnostics but renders nowhere.
	var in_card_phase := _bs.game_phase == GameEnums.BattlePhase.CARD_PHASE
	_update_cost_donuts(in_card_phase)
	_update_pile_buttons()
	_update_pilot_strips(in_card_phase)
	update_time_label()


# The ring is full at PHASE_THRESHOLD; the number in the middle is the raw
# point total, so boost cards read as "8+ on a full ring".
# The player donut only accepts the flip → 턴 넘기기 during 작전 단계.
func _update_cost_donuts(in_card_phase: bool) -> void:
	var maxv: int = _bs.PHASE_THRESHOLD if _bs.PHASE_THRESHOLD > 0 else DONUT_DEFAULT_MAX
	if _bs.cost_donut_enemy != null:
		_bs.cost_donut_enemy.set_value(_bs.ai_cost, maxv)
	if _bs.cost_donut != null:
		# Deck / Discard 목록이 열려 있으면 플립도 막는다 — CostDonut._input 은
		# GUI 픽보다 먼저 돌아 열람 딤을 뚫고 눌린다. 전투 개시 VS 확인 화면도
		# 같은 이유로 막는다: 그 화면이 떠 있는 동안 game_phase 는 아직
		# CARD_PHASE 라, 딤만으로는 도넛이 눌리는 것을 못 막는다.
		var modal_up: bool = (_bs.card_pile_viewer != null
					and _bs.card_pile_viewer.is_active()) \
				or (_bs.engage_phase != null and _bs.engage_phase.is_intro_active())
		_bs.cost_donut.set_value(_bs.player_cost, maxv)
		_bs.cost_donut.set_flip_allowed(in_card_phase and not modal_up)
		_bs.cost_donut.set_end_enabled(in_card_phase
				and _bs.card_phase.can_end_card_phase())


# Smooth in-game timer — driven by turn_count + auto_play_timer fraction.
# Called every frame from BattleSim._process so the seconds tick visibly.
func update_time_label() -> void:
	if _lbl_time == null:
		return
	var sec_total: int = _bs.get_elapsed_ingame_seconds()
	@warning_ignore("integer_division")
	var mm: int = sec_total / 60
	var ss: int = sec_total % 60
	_lbl_time.text = "%02d:%02d" % [mm, ss]


## 스트립의 자리 순서는 **역할**이 정한다 — `GameEnums.ROLE_DISPLAY_ORDER`
## (탑 · 정글 · 미드 · 원딜 · 서폿), 곧 전장을 왼쪽부터 오른쪽으로 훑은 순서
## (좌측 → 정글 → 중앙 → 우측 ×2)다. 예전에는 여기 `LANE_SEAT_ORDER` 표를 따로
## 두고 `PilotData.lane` 으로 정렬했는데, **우측 레인에는 두 명이 앉아 있어**
## (스나이퍼 · 서포터) 그 둘의 순서를 lane 이 가르지 못했다 — `sort_custom` 은
## 안정 정렬이 아니므로 같은 lane 두 명의 앞뒤가 실행마다 흔들릴 수 있었다.
## 역할로 정렬하면 다섯 자리가 전부 유일하게 정해지고, **아웃게임 화면들과도
## 같은 표 하나를 읽는다**(시즌 허브 로스터 · 훈련 격자 · 밴픽 화면).
static func _lane_seat_less(a: PilotData, b: PilotData) -> bool:
	return GameEnums.role_seat(a.role) < GameEnums.role_seat(b.role)


# 두 스트립 + 팀 합산 점수 갱신, 그리고 상세 패널의 단계 게이트.
#
# `_bs.pilots` 는 스폰 순서(= 역할 순서)를 그대로 유지해야 한다
# (`BattleSim.player_data_for` 가 그 인덱스로 로스터를 찾는다). 그래서 여기서는
# **사본을 정렬**한다 — 원본을 sort_custom 하면 아웃게임 스탯이 엉뚱한
# 파일럿에게 붙는다.
func _update_pilot_strips(in_card_phase: bool) -> void:
	var team0: Array = []
	var team1: Array = []
	for p in _bs.pilots:
		var pd := p as PilotData
		(team0 if pd.team == 0 else team1).append(pd)
	team0.sort_custom(_lane_seat_less)
	team1.sort_custom(_lane_seat_less)
	if _player_strip != null:
		_player_strip.set_pilots(team0)
		_player_strip.set_interactive_enabled(in_card_phase)
	if _enemy_strip != null:
		_enemy_strip.set_pilots(team1)
		_enemy_strip.set_interactive_enabled(in_card_phase)
	if _lbl_total_score != null:
		_lbl_total_score.text = "%s - %s" % [
			BattleSim.fmt_score(_bs.team_score(0)),
			BattleSim.fmt_score(_bs.team_score(1))]
	for raw in _obj_timers:
		(raw as ObjectiveTimer).queue_redraw()
	if _bs.pilot_detail != null:
		_bs.pilot_detail.close_if_phase_left()
		# 닫히지 않고 살아남았다면 스탯을 지금 값으로 다시 세운다 — 카드가
		# 건 라인전 스탯 / 성장 획득 배율이 그 자리에서 읽혀야 한다.
		_bs.pilot_detail.refresh()


