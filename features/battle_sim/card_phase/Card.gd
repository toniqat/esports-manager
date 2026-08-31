class_name Card
extends Control

signal card_hovered(card: Card)
signal card_unhovered(card: Card)

const CARD_W := 160.0
const CARD_H := 220.0

## Pixels the card jumps upward while it is being **aimed** — i.e. a 대상 지정
## card that stays in the hand while a 조준 화살표 runs to the cursor.
## CardPhaseManager applies this lift so the aimed card visually detaches from
## the rest of the row. (Cards without a target don't use it: they leave the row
## entirely and ride the cursor — see `begin_free_drag`.)
const PRESS_LIFT     := 40.0
## 자유 이동 드래그로 승격될 때 부채꼴 기울기를 0 으로 펴는 시간(s). 카드를
## 손에서 뽑아 드는 동작이라 기울기를 유지하면 커서에 비스듬히 매달려 보인다.
const FREE_DRAG_STRAIGHTEN_SEC := 0.10

# ── 드로우 인트로: 뒤집기 (`play_flip_reveal`) ────────────────────────────────
# 왼쪽에서 날아온 뒷면 카드가 손패에 안착하기 직전에 뒤집혀 내용을 드러낸다.
# 3D 회전이 아니라 **가로 폭만 0 으로 접었다 펴는** 2D 흉내다 — scale.x 가 0 이
# 되는 순간(카드가 옆에서 본 종잇장처럼 사라진 순간) 앞/뒷면을 맞바꾸므로
# 뒤집히는 것처럼 읽힌다.
## 접는 데 걸리는 시간(s). 펴는 데도 같은 시간이 걸리므로 총 뒤집기 시간은 2배.
const FLIP_HALF_SEC := 0.09

# ── 버리기 연출 (`begin_discard_fx`) ─────────────────────────────────────────
# 손패를 떠나 버려지는 카드는 **부채꼴 기울기와 무관하게 화면 Y축으로만** 곧장
# 내려가며 투명해진다. 리프트(`PRESS_LIFT`)가 카드 자신의 up 축을 타는 것과
# 반대다 — 버려지는 카드는 손에서 뽑히는 게 아니라 아래로 떨어지는 것이라,
# 기울기를 타면 기울어진 카드만 옆으로 새 나가 줄이 흐트러져 보인다.
#
# **낙하 곡선은 `EASE_OUT`** — 손을 떠나는 순간 확 튕겨 내려간 뒤 아래에서
# 서서히 멎는다. 예전에는 `EASE_IN` 이라 처음엔 굼뜨다가 마지막에 빨라졌는데,
# 그러면 카드가 손패에서 **떨어져 나가는** 순간이 가장 흐릿하고 정작 다 사라질
# 때 제일 빨라 "버렸다"의 무게가 끝에 실렸다.
const DISCARD_DROP_PX  := 150.0
const DISCARD_FADE_SEC := 0.30
## Modulate multiplier applied while the mouse is hovering over a face-up
## player card. Above 1.0 → brighter (Godot canvas modulate supports values
## > 1 for an additive-feeling brighten).
const HOVER_BRIGHTEN := 1.25
const HOVER_TWEEN_DURATION := 0.04
## Scale applied to a hovered face-up player card — the card comes closer to
## the screen, so it reads slightly bigger (and casts a bigger shadow).
const HOVER_SCALE := 1.2
## Hover / selection reactions snap out fast and settle slow (cubic EASE_OUT)
## so the card feels like it jumps to the cursor rather than drifting to it.
const HOVER_EASE  : int = Tween.EASE_OUT
const HOVER_TRANS : int = Tween.TRANS_CUBIC

# ── Floating shadow ───────────────────────────────────────────────────────────
# Hand cards hover above the table rather than lying on it. The gap between a
# card and its shadow encodes that height: at rest the card sits close to the
# surface (short offset, tight and dark shadow); hovering pulls it toward the
# screen (offset pushed out, shadow spread wider and lightened); a selected
# card floats highest of all. The shadow is a Panel child at draw index 0, so
# it inherits the card's fan rotation and hover scale for free.
const SHADOW_REST_OFFSET     := Vector2(2.0, 10.0)
const SHADOW_HOVER_OFFSET    := Vector2(5.0, 24.0)
const SHADOW_SELECTED_OFFSET := Vector2(6.0, 32.0)
## StyleBoxFlat.shadow_size — blur radius bleeding out of the shadow slab.
const SHADOW_REST_BLUR      := 6
const SHADOW_HOVER_BLUR     := 26
const SHADOW_SELECTED_BLUR  := 32
## Shadow darkness. The further a shadow falls from its caster, the more it
## spreads and the lighter it reads.
const SHADOW_REST_ALPHA     := 0.50
const SHADOW_HOVER_ALPHA    := 0.36
const SHADOW_SELECTED_ALPHA := 0.32
## Extra spread of the shadow slab itself (multiplied on top of the card scale).
const SHADOW_REST_SPREAD     := 1.0
const SHADOW_HOVER_SPREAD    := 1.06
const SHADOW_SELECTED_SPREAD := 1.08
## 내 차례가 아닐 때(핸드가 내려가 있을 때)의 그림자. 카드가 카메라에서 멀어진
## 것처럼 보이도록 **그림자가 카드에 더 붙는다** — 거리가 곧 높이이므로, 짧고
## 좁은 그림자는 "바닥에 가까이 누워 있다"로 읽힌다.
const SHADOW_FAR_OFFSET := Vector2(1.0, 4.0)
const SHADOW_FAR_BLUR   := 3
const SHADOW_FAR_ALPHA  := 0.58
const SHADOW_FAR_SPREAD := 0.98
const SHADOW_TWEEN_DURATION  := 0.05

# ── 사용 불가 오버레이 ────────────────────────────────────────────────────────
# 마나(작전 점수) 부족 / 시전자 부활 대기 상태를 **카드 전체를 덮는 반투명
# 판**으로 표현한다. card_front 의 배경색만 회색으로 칠하면 그 위에 얹힌 파일럿
# 일러스트는 밝은 채로 남아 "쓸 수 있는 카드"처럼 읽히므로, 일러스트·이름·비용
# 까지 한꺼번에 어두워지도록 최상위 자식에 슬래브를 깐다. 카드 모서리가
# 둥글기 때문에 ColorRect 가 아니라 corner_radius 를 준 Panel 을 쓴다.
const BLOCKED_OVERLAY_COLOR := Color(0.0, 0.0, 0.0, 0.58)
## 시전자 부활까지 남은 턴 수 — 카드 한가운데 크게 찍힌다.
const RESPAWN_FONT_SIZE     := 76
const RESPAWN_FONT_COLOR    := Color(1.0, 0.86, 0.86)

# ── 보존 표시 (계획 중시) ────────────────────────────────────────────────────
# 상한 초과 자동 버리기로부터 보호되는 카드에 붙는 테두리. 사용 불가 슬래브와
# 달리 카드를 어둡게 하지 않는다 — 보존은 제약이 아니라 보증이므로, 카드는
# 평소대로 밝게 두고 테두리만 얹는다. 슬래브와 겹쳐도 서로를 가리지 않도록
# 배경 없는(투명) Panel 이다.
const PRESERVE_BORDER_COLOR := Color(0.45, 0.95, 1.0, 1.0)
const PRESERVE_BORDER_WIDTH := 5

# ── 충전 표시 ────────────────────────────────────────────────────────────────
## 충전 배지는 **오른쪽 아래**다 — 오른쪽 위는 파일럿 초상 배지가 가져갔고,
## 왼쪽 위는 비용 칸이다. `N/M` 으로 찍어 숫자 하나가 비용으로 오독되지 않게 한다.
const CHARGE_BADGE_SIZE := Vector2(52.0, 30.0)
const CHARGE_BADGE_COLOR := Color(0.06, 0.05, 0.10, 0.92)
const CHARGE_BADGE_TEXT_COLOR := Color(1.0, 0.92, 0.45)

# ── 앞면 세 층 (아트 · 이름 · 설명) ──────────────────────────
# 카드 앞면은 위에서부터 **아트 → 이름 → 설명판** 이다.
#
# **아트는 카드 높이의 1/3 만 가져간다**(220 / 3 ≈ 73.3 → 74). 예전에는 이 자리가
# 통째로 비어 있었고(비용색 앞면이 그대로 드러났다) 시전자 얼굴 배지 하나만
# 떠 있었는데, 지금은 그 위쪽 셋째가 그림 자리다.
#
# **아트는 카드 테두리에서 `ART_INSET` 만큼 물러나 앉는다** — 카드 모서리는
# 둥글고 아트는 네모라, 끝까지 붙이면 둥근 모서리 위로 그림의 네모난
# 귀퇰이가 샐져나온다. 물러나 앉히면 둥근 테두리가 그림을 액자처럼 두른다
# (자르지 않으므로 카드마다 백버퍼를 뜨는 `clip_children` 도 필요 없다).
#
# 세 층 모두 **절대 좌표**다. 카드는 160×220 으로 고정이고 컨테이너가 없어야
# 레이아웃 패스를 기다리지 않고 설명 글자 크기를 계산할 수 있다
# (`_apply_description` — `setup()` 은 첫 레이아웃 패스보다 먼저 돌 수 있다).
const ART_INSET := 5.0
const ART_H := 74.0
const ART_BACK_COLOR := Color(0.05, 0.04, 0.09, 1.0)
const ART_LINE_COLOR := Color(0.0, 0.0, 0.0, 0.55)

const NAME_FONT_SIZE := 14

# ── 설명문 ─────────────────────────────────────────────
# 아트 아래의 나머지가 설명판이고, 판은 카드 테두리에서 **좌 · 우 · 아래로**
# `DESC_INSET` 만큼 물러나 앉는다. 판을 깔지 않으면 글자가 비용색 위에 바로
# 얹힐는데, 비용색은 파랑부터 노랑까지 여섯 가지라 어느 한 글자색도 여섯 곳에서
# 다 읽히지 않는다.
#
# **글자 크기는 고정이 기본이고, 넘치는 카드만 줄인다** — `DESC_FONT_MAX` 로
# 찍어 보고 판 안에 안 들어가면 한 단계씩 내려 `DESC_FONT_MIN` 까지 간다.
# 처음부터 카드마다 다른 크기로 찍으면 손패가 들쌀날줍해 보이고, 반대로 전부
# 최소 크기로 맞추면 스무 자짜리 카드까지 개미 글씨가 된다(설명문은 22자
# median 에 mech_cards 쪽 최장 128자다).
const DESC_INSET := 6.0
const DESC_TOP := 106.0
## 판 안쪽 여백(글자와 판 사이) — 좌우 / 위아래.
const DESC_PAD_H := 6.0
const DESC_PAD_V := 5.0
const DESC_FONT_MAX := 13
const DESC_FONT_MIN := 8
const DESC_PLATE_COLOR := Color(0.05, 0.04, 0.09, 0.66)
const DESC_TEXT_COLOR := Color(0.93, 0.94, 0.98)
## 줄 간격은 0 으로 눌러 둔다 — 글자 크기를 고를 때 재는 값
## (`Font.get_multiline_string_size`)이 줄 간격을 모르기 때문이다. 간격이 살아
## 있으면 잴 높이와 실제 높이가 줄 수만큼 어긋나 마지막 줄이 판 밖으로 샐다.
const DESC_LINE_SPACING := 0

# ── 비용 배지 (좌측 상단, 카드 밖으로 걸친다) ──────────────────
# 비용은 카드 **모서리 밖으로 살짝 튀어나온 원** 안에 찍힌다. 손패는 카드끼리
# 절반 넘게 겹치는 부채꼴이라(오른쪽 카드가 왼쪽 카드를 덮는다) 왼쪽 위 모서리가
# 각 카드에서 언제나 보이는 유일한 구석이고, 원이 그 밖으로 나가 있으면 겹친
# 줄에서도 비용이 한 줄로 읽힌다.
const COST_BADGE_SIZE := 42.0
const COST_BADGE_RING_COLOR := Color(0.98, 0.96, 0.90, 0.95)
const COST_BADGE_RING_WIDTH := 3
const COST_FONT_SIZE := 22
## 사용 불가 슬래브는 카드 사각형만 덮으므로 **밖으로 나간 원은 안 덮인다**.
## 배지를 따로 어둡게 해 잠긴 카드에서 비용만 밝게 남지 않게 한다.
const COST_BADGE_BLOCKED_TINT := Color(0.42, 0.42, 0.42, 1.0)

# ── 파일럿 초상 배지 ──────────────────────────────────
# 시전자의 얼굴은 **카드 본체를 채우지 않는다.** 아트 위 왼쪽, **비용 배지 바로
# 아래**에 작은 원형 초상 하나로 앉는다. 예전에는 오른쪽 위였는데, 카드가 겹치는
# 부채꼴에서 오른쪽 절반은 옆 카드에 가려지는 쪽이라 "누구 카드인가"가 손패를
# 펼쳐 봐야만 읽혔다 — 비용과 얼굴은 한 구석에 세로로 모아 둔다.
#
# **손패에서만 그린다**(`is_player_card`). 상세 패널 · 더미 열람 · 밴픽 · 드래프트
# 처럼 "이 기체가 주는 카드"를 보여 주는 자리에서는 시전자가 없거나 의미가 없고,
# 상대 손패 peek 은 뒷면이라 그릴 것이 없다.
const PORTRAIT_SIZE   := 44.0
const PORTRAIT_LEFT   := 5.0
## 비용 배지 아래끈(-9 + 42 = 33) 바로 밑.
const PORTRAIT_TOP    := 34.0
## 초상 뒤에 깔는 원형 받침이 초상보다 넓은 만큼. 초상 PNG 는 정사각형에 내접한
## 원이라 아트 위에 그냥 얹으면 가장자리가 그림에 묻힌다.
const PORTRAIT_RING_PAD := 2.0
const PORTRAIT_RING_COLOR := Color(0.05, 0.04, 0.09, 0.92)
const PORTRAIT_RING_LINE := Color(0.98, 0.96, 0.90, 0.85)

const UNPLAYABLE_COST_TEXT := "—"

var data: CardData = null
var face_up: bool = false
var is_player_card: bool = true
var is_animating: bool = false
## True while the player is holding this card out of the hand. There is no
## separate "selected" state any more — **dragging is the only way a card is
## ever picked up**, so this one flag carries what `is_selected` used to.
##
## Two poses hang off it, chosen by CardPhaseManager:
##   • 대상 지정 카드 — the card **does not travel**. It stays in its lifted slot
##     in the hand and a `CardDragArrow` runs from its top edge to the cursor.
##   • 그 밖의 카드 — the card leaves the row and rides the cursor
##     (`begin_free_drag` / `follow_cursor`).
## Either way the flag buys the look: "lifted highest of all" — hover scale plus
## the tallest shadow — held regardless of where the cursor currently is, since
## the cursor has left the hand row and the hit layer's hover bookkeeping no
## longer speaks for this card. Layout passes leave it alone (`relayout_hand`
## skips it).
var is_dragging: bool = false
## True from the moment a drawn card is spawned (face-down, off the left edge of
## the screen) until it has flown in, flipped face-up and been handed back to the
## layout. `CardPhaseManager.relayout_hand` skips these cards — the intro owns
## the position — and hover / grab both refuse them: a card still in flight is
## not yet part of the row the player can act on.
var intro_active: bool = false

# True while CardPhaseManager is dimming the hand (it's not the player's turn,
# or the player turn-start banner is still playing). Hover/click feedback is
# suppressed in this state so the dimmed look stays consistent.
var _is_dimmed: bool = false

var _is_hovered:  bool  = false
var _active_tween: Tween  = null
var _stored_base_y: float = 0.0
var _hover_tween:  Tween  = null

# Layout scale requested by the last tween_to() — the hover enlargement is
# multiplied on top of this instead of overwriting it.
var _base_scale: Vector2 = Vector2.ONE
var _shadow: Panel = null
var _shadow_tween: Tween = null
var _float_tween: Tween  = null
## 자유 이동 드래그 진입 시 부채꼴 기울기를 펴는 전용 트윈. 위치는 매 모션마다
## `follow_cursor` 가 직접 쓰므로 트윈을 태우지 않는다.
var _free_rot_tween: Tween = null
## 드로우 인트로의 뒤집기 트윈. 도는 동안 `_flip_active` 가 서 있고,
## `_refresh_float_state` 는 그 사이 `scale` 에서 손을 뗀다 — 접혔다 펴지는 폭과
## 호버 확대가 같은 프로퍼티를 두고 다투면 카드가 납작한 채로 굳는다.
var _flip_tween: Tween = null
var _flip_active: bool = false

# 사용 불가 표시 상태. `set_affordable` / `set_respawn_turns` 가 갱신하고
# `_refresh_block_overlay` 가 두 값을 합쳐 슬래브와 숫자를 켜고 끈다.
var _affordable: bool = true
var _respawn_turns: int = 0
var _block_overlay: Panel = null
var _respawn_label: Label = null
# 계획 중시로 보존된 카드인가. `set_preserved` 가 갱신한다.
var _preserved: bool = false
var _preserve_mark: Panel = null
## 충전 배지 (`N/M`). 충전 카드가 아니면 꺼진다.
var _charge_badge: Label = null
## 시전자 얼굴 배지 (카드 안쪽 오른쪽 위). 손패 카드에만 선다.
var _portrait: TextureRect = null
## 그 얼굴 뒤에 깔는 원형 받침. 초상과 언제나 함께 켜지고 꺼진다.
var _portrait_ring: Panel = null
## 핸드가 내려가 있는가(= 내 차례가 아닌가). 그림자 거리만 바꾼다.
var _lowered: bool = false

const DIM_MODULATE: Color = Color(0.42, 0.42, 0.48, 1.0)

@onready var card_front: Panel = $CardFront
@onready var card_back: Panel = $CardBack
@onready var art_frame: Panel = $CardFront/ArtFrame
@onready var art_rect: TextureRect = $CardFront/ArtFrame/Art
@onready var name_label: Label = $CardFront/NameLabel
@onready var desc_plate: Panel = $CardFront/DescPlate
@onready var desc_label: Label = $CardFront/DescPlate/DescLabel
@onready var cost_badge: Panel = $CardFront/CostBadge
@onready var cost_label: Label = $CardFront/CostBadge/CostLabel
@onready var back_cost_label: Label = $CardBack/BackCostLabel


func _ready() -> void:
	_build_shadow()
	_build_block_overlay()


func setup(card_data: CardData, player_card: bool, start_face_up: bool = false) -> void:
	data = card_data
	is_player_card = player_card
	face_up = start_face_up
	_apply_data()
	_apply_back_style()
	card_front.visible = start_face_up
	card_back.visible = not start_face_up
	# setup() may run before or after _ready() depending on the caller's
	# add_child ordering, so both paths re-assert the shadow visibility.
	if _shadow != null:
		_shadow.visible = player_card
	_refresh_block_overlay()


# ── Floating shadow ───────────────────────────────────────────────────────────

## Builds the drop shadow slab and parks it at draw index 0 so both CardBack
## and CardFront cover it. Only player cards cast one — the AI hand peek and
## the 찾기 grid are flat rows where a shadow would only add noise.
func _build_shadow() -> void:
	if _shadow != null:
		return
	_shadow = Panel.new()
	_shadow.name = "DropShadow"
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.size = Vector2(CARD_W, CARD_H)
	_shadow.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5
	_shadow.position = SHADOW_REST_OFFSET
	_shadow.modulate = Color(1.0, 1.0, 1.0, SHADOW_REST_ALPHA)
	_shadow.visible = is_player_card
	add_child(_shadow)
	move_child(_shadow, 0)
	_apply_shadow_blur(SHADOW_REST_BLUR)


func _apply_shadow_blur(blur: int) -> void:
	if _shadow == null:
		return
	var sb := StyleBoxFlat.new()
	# The slab core lightens as it blurs out, so a high-lift shadow reads as a
	# soft pool rather than a hard black rectangle trailing the card.
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.8 if blur <= SHADOW_REST_BLUR else 0.55)
	sb.corner_radius_top_left     = 10
	sb.corner_radius_top_right    = 10
	sb.corner_radius_bottom_left  = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	sb.shadow_size  = blur
	_shadow.add_theme_stylebox_override("panel", sb)


# ── 사용 불가 오버레이 ────────────────────────────────────────────────────────

## Builds the "can't play this" slab and its countdown number, both parked at
## the END of the child list so they cover CardFront (owner face included).
## Both must be MOUSE_FILTER_IGNORE: hover and click live on the `Card` root,
## and a `Panel` / `Label` left on the default filter would punch a dead hole
## across the whole card — see the module README.
func _build_block_overlay() -> void:
	if _block_overlay != null:
		return
	_block_overlay = Panel.new()
	_block_overlay.name = "BlockOverlay"
	_block_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block_overlay.size = Vector2(CARD_W, CARD_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BLOCKED_OVERLAY_COLOR
	sb.corner_radius_top_left     = 10
	sb.corner_radius_top_right    = 10
	sb.corner_radius_bottom_left  = 10
	sb.corner_radius_bottom_right = 10
	_block_overlay.add_theme_stylebox_override("panel", sb)
	_block_overlay.visible = false
	add_child(_block_overlay)

	_respawn_label = Label.new()
	_respawn_label.name = "RespawnCountdown"
	_respawn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_respawn_label.size = Vector2(CARD_W, CARD_H)
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_respawn_label.add_theme_font_size_override("font_size", RESPAWN_FONT_SIZE)
	_respawn_label.add_theme_color_override("font_color", RESPAWN_FONT_COLOR)
	_respawn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_respawn_label.add_theme_constant_override("outline_size", 10)
	_respawn_label.visible = false
	add_child(_respawn_label)

	_preserve_mark = Panel.new()
	_preserve_mark.name = "PreserveMark"
	_preserve_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preserve_mark.size = Vector2(CARD_W, CARD_H)
	var pm := StyleBoxFlat.new()
	pm.draw_center = false
	pm.border_color = PRESERVE_BORDER_COLOR
	pm.border_width_top    = PRESERVE_BORDER_WIDTH
	pm.border_width_bottom = PRESERVE_BORDER_WIDTH
	pm.border_width_left   = PRESERVE_BORDER_WIDTH
	pm.border_width_right  = PRESERVE_BORDER_WIDTH
	pm.corner_radius_top_left     = 10
	pm.corner_radius_top_right    = 10
	pm.corner_radius_bottom_left  = 10
	pm.corner_radius_bottom_right = 10
	_preserve_mark.add_theme_stylebox_override("panel", pm)
	_preserve_mark.visible = false
	add_child(_preserve_mark)

	_charge_badge = Label.new()
	_charge_badge.name = "ChargeBadge"
	_charge_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_badge.size = CHARGE_BADGE_SIZE
	_charge_badge.position = Vector2(CARD_W - CHARGE_BADGE_SIZE.x - 6.0,
			CARD_H - CHARGE_BADGE_SIZE.y - 6.0)
	_charge_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charge_badge.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_charge_badge.add_theme_font_size_override("font_size", 20)
	_charge_badge.add_theme_color_override("font_color", CHARGE_BADGE_TEXT_COLOR)
	_charge_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_charge_badge.add_theme_constant_override("outline_size", 5)
	var cb := StyleBoxFlat.new()
	cb.bg_color = CHARGE_BADGE_COLOR
	cb.corner_radius_top_left     = 8
	cb.corner_radius_top_right    = 8
	cb.corner_radius_bottom_left  = 8
	cb.corner_radius_bottom_right = 8
	_charge_badge.add_theme_stylebox_override("normal", cb)
	_charge_badge.visible = false
	add_child(_charge_badge)

	# 시전자 얼굴 배지. 앞면 위에 앉되 **사용 불가 슬래브 아래**여야 한다 —
	# 잠긴 카드에서 얼굴만 밝게 남으면 쓸 수 있는 카드처럼 읽힌다. 그래서 배지를
	# 붙인 뒤 슬래브 · 부활 숫자 · 보존 테두리를 다시 맨 뒤로 보낸다.
	_portrait_ring = Panel.new()
	_portrait_ring.name = "OwnerPortraitRing"
	_portrait_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_ring.size = Vector2(PORTRAIT_SIZE + 2.0 * PORTRAIT_RING_PAD,
			PORTRAIT_SIZE + 2.0 * PORTRAIT_RING_PAD)
	_portrait_ring.position = Vector2(PORTRAIT_LEFT - PORTRAIT_RING_PAD,
			PORTRAIT_TOP - PORTRAIT_RING_PAD)
	var pr := StyleBoxFlat.new()
	pr.bg_color = PORTRAIT_RING_COLOR
	pr.border_color = PORTRAIT_RING_LINE
	pr.border_width_top    = 2
	pr.border_width_bottom = 2
	pr.border_width_left   = 2
	pr.border_width_right  = 2
	var rr: int = int(_portrait_ring.size.x * 0.5)
	pr.corner_radius_top_left     = rr
	pr.corner_radius_top_right    = rr
	pr.corner_radius_bottom_left  = rr
	pr.corner_radius_bottom_right = rr
	_portrait_ring.add_theme_stylebox_override("panel", pr)
	_portrait_ring.visible = false
	add_child(_portrait_ring)

	_portrait = TextureRect.new()
	_portrait.name = "OwnerPortrait"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.position = Vector2(PORTRAIT_LEFT, PORTRAIT_TOP)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.visible = false
	add_child(_portrait)
	# 슬래브 · 부활 숫자 · 보존 테두리가 초상 배지를 덮도록 맨 뒤로 다시 보낸다.
	move_child(_block_overlay, get_child_count() - 1)
	move_child(_respawn_label, get_child_count() - 1)
	move_child(_preserve_mark, get_child_count() - 1)


## 충전 배지와 시전자 초상 배지를 지금 상태에 맞춘다. `CardPhaseManager` 가
## 충전이 오르거나 내릴 때마다 부른다.
func refresh_charge_badge() -> void:
	var showable: bool = face_up and is_player_card
	if _charge_badge != null and is_instance_valid(_charge_badge):
		var on: bool = showable and data != null and data.is_charge_card()
		_charge_badge.visible = on
		if on:
			_charge_badge.text = "%d/%d" % [data.charge, maxi(1, data.charge_max)]
	if _portrait != null and is_instance_valid(_portrait):
		var pid: int = -1
		if data != null and data.owner_pilot != null:
			pid = data.owner_pilot.pilot_id
		var tex: Texture2D = PilotImages.circle_for(pid) if pid >= 0 else null
		_portrait.texture = tex
		_portrait.visible = showable and tex != null
		if _portrait_ring != null and is_instance_valid(_portrait_ring):
			_portrait_ring.visible = _portrait.visible


## Turns the slab / countdown on or off from the two independent reasons a card
## can be unplayable. Face-down cards (AI hand peek, 찾기 grid) never show it —
## there is no cost or 시전자 to read on a card back.
func _refresh_block_overlay() -> void:
	if _block_overlay == null or not is_instance_valid(_block_overlay):
		return
	var showable: bool = face_up and is_player_card
	_block_overlay.visible = showable and (_respawn_turns > 0 or not _affordable)
	_respawn_label.visible = showable and _respawn_turns > 0
	if _respawn_turns > 0:
		_respawn_label.text = str(_respawn_turns)
	if _preserve_mark != null and is_instance_valid(_preserve_mark):
		_preserve_mark.visible = showable and _preserved
	# 슬래브는 카드 사각형까지만 덮는다 — 밖으로 걸친 비용 원은 직접 눌러 준다.
	if cost_badge != null and is_instance_valid(cost_badge):
		cost_badge.modulate = (COST_BADGE_BLOCKED_TINT
				if _block_overlay.visible else Color.WHITE)
	refresh_charge_badge()


## Re-poses the card and its shadow for the current hover / selected state.
## Card scale grows on hover only; the shadow drops further away (and softens)
## for both hover and selection, since either state lifts the card off the table.
func _refresh_float_state() -> void:
	# A dragged card holds the enlarged pose wherever the cursor goes — it left
	# the hand row, so the hit layer's hover bookkeeping no longer speaks for it.
	var lifted: bool = _is_hovered or is_dragging
	var target_scale: Vector2 = _base_scale * (HOVER_SCALE if lifted else 1.0)
	# 뒤집기가 도는 동안 `scale` 의 주인은 `play_flip_reveal` 하나다. 여기서
	# 끼어들면 카드가 접힌 폭(scale.x ≈ 0)으로 되돌려져 그대로 굳는다.
	if not _flip_active:
		if _float_tween != null and _float_tween.is_running():
			_float_tween.kill()
		_float_tween = create_tween()
		(_float_tween.tween_property(self, "scale", target_scale, SHADOW_TWEEN_DURATION)
				.set_ease(HOVER_EASE).set_trans(HOVER_TRANS))

	if _shadow == null:
		return
	var offset: Vector2 = SHADOW_REST_OFFSET
	var alpha: float    = SHADOW_REST_ALPHA
	var spread: float   = SHADOW_REST_SPREAD
	var blur: int       = SHADOW_REST_BLUR
	# 내 차례가 아니면 손패가 화면 아래로 물러나 있다 — 그림자를 카드에 바짝
	# 붙여 "카메라에서 멀어졌다"를 거리로 말한다. 그 상태에서는 호버도 드래그도
	# 없으므로(핸드가 딤드 · 입력 차단) 이 갈래가 다른 둘과 다투지 않는다.
	if _lowered:
		offset = SHADOW_FAR_OFFSET
		alpha  = SHADOW_FAR_ALPHA
		spread = SHADOW_FAR_SPREAD
		blur   = SHADOW_FAR_BLUR
	elif is_dragging:
		offset = SHADOW_SELECTED_OFFSET
		alpha  = SHADOW_SELECTED_ALPHA
		spread = SHADOW_SELECTED_SPREAD
		blur   = SHADOW_SELECTED_BLUR
	elif _is_hovered:
		offset = SHADOW_HOVER_OFFSET
		alpha  = SHADOW_HOVER_ALPHA
		spread = SHADOW_HOVER_SPREAD
		blur   = SHADOW_HOVER_BLUR
	_apply_shadow_blur(blur)
	if _shadow_tween != null and _shadow_tween.is_running():
		_shadow_tween.kill()
	_shadow_tween = create_tween().set_parallel() \
			.set_ease(HOVER_EASE).set_trans(HOVER_TRANS)
	_shadow_tween.tween_property(_shadow, "position", offset, SHADOW_TWEEN_DURATION)
	_shadow_tween.tween_property(_shadow, "scale", Vector2(spread, spread),
			SHADOW_TWEEN_DURATION)
	_shadow_tween.tween_property(_shadow, "modulate",
			Color(1.0, 1.0, 1.0, alpha), SHADOW_TWEEN_DURATION)


func _apply_back_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.18, 1.0)
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	style.border_color = Color(0.4, 0.3, 0.6, 1.0)
	style.border_width_bottom = 2
	style.border_width_top    = 2
	style.border_width_left   = 2
	style.border_width_right  = 2
	card_back.add_theme_stylebox_override("panel", style)


## Cost number colours: white when the displayed cost matches the card's
## printed (data.cost) value, green when reduced by an active modifier, red
## when increased. Surfaced via update_displayed_cost so CardPhaseManager can
## refresh the card whenever effective_cost_for changes.
const COST_COLOR_BASE     := Color(1.0, 1.0, 1.0)
const COST_COLOR_REDUCED  := Color(0.45, 1.0, 0.45)
const COST_COLOR_INCREASED := Color(1.0, 0.45, 0.45)


func _apply_data() -> void:
	if data == null:
		return
	name_label.text = data.card_name
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 3)
	var col := _cost_color(data.cost)
	var style := StyleBoxFlat.new()
	style.bg_color = col
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	card_front.add_theme_stylebox_override("panel", style)
	_apply_art()
	_apply_cost_badge()
	_apply_description()
	refresh_charge_badge()


## 카드 아트 — 위쪽 1/3. 전용 아트가 없는 카드는 `CardImages` 가 이름으로 고른
## 배경을 받는다(그림이 아예 없으면 액자만 남고 비용색 앞면이 비친다).
func _apply_art() -> void:
	if art_frame == null or art_rect == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = ART_BACK_COLOR
	sb.border_color = ART_LINE_COLOR
	sb.border_width_top    = 1
	sb.border_width_bottom = 1
	sb.border_width_left   = 1
	sb.border_width_right  = 1
	art_frame.add_theme_stylebox_override("panel", sb)
	art_rect.texture = CardImages.art_for(data.card_name)


## 좌측 상단 비용 원. 알맹이는 그 비용색을 어둡게 깔은 것이고 테두리는 밝은
## 링이라, 카드 본체(같은 비용색)와 겹쳐도 원이 원으로 읽힌다.
func _apply_cost_badge() -> void:
	if cost_badge == null or cost_label == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = _cost_color(data.cost).darkened(0.55)
	sb.border_color = COST_BADGE_RING_COLOR
	sb.border_width_top    = COST_BADGE_RING_WIDTH
	sb.border_width_bottom = COST_BADGE_RING_WIDTH
	sb.border_width_left   = COST_BADGE_RING_WIDTH
	sb.border_width_right  = COST_BADGE_RING_WIDTH
	var r: int = int(COST_BADGE_SIZE * 0.5)
	sb.corner_radius_top_left     = r
	sb.corner_radius_top_right    = r
	sb.corner_radius_bottom_left  = r
	sb.corner_radius_bottom_right = r
	cost_badge.add_theme_stylebox_override("panel", sb)
	cost_label.text = UNPLAYABLE_COST_TEXT if not data.is_playable() else str(data.cost)
	cost_label.add_theme_font_size_override("font_size", COST_FONT_SIZE)
	cost_label.add_theme_color_override("font_color", COST_COLOR_BASE)
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cost_label.add_theme_constant_override("outline_size", 3)


## 설명문 — 아트 아래 판에 찍는다. 글자 크기는 `DESC_FONT_MAX` 가 기본이고,
## 그 크기로 판을 넘치는 카드만 한 단계씩 줄여 `DESC_FONT_MIN` 까지 내려간다.
func _apply_description() -> void:
	if desc_plate == null or desc_label == null:
		return
	var plate := StyleBoxFlat.new()
	plate.bg_color = DESC_PLATE_COLOR
	plate.corner_radius_top_left     = 6
	plate.corner_radius_top_right    = 6
	plate.corner_radius_bottom_left  = 8
	plate.corner_radius_bottom_right = 8
	desc_plate.add_theme_stylebox_override("panel", plate)

	desc_label.text = data.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_color_override("font_color", DESC_TEXT_COLOR)
	desc_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	desc_label.add_theme_constant_override("outline_size", 2)
	desc_label.add_theme_constant_override("line_spacing", DESC_LINE_SPACING)
	desc_label.add_theme_font_size_override("font_size", _fit_desc_font_size())


## 설명문이 판 안에 들어가는 가장 큰 글자 크기. 들어가는 크기가 없으면 최소값을
## 돌려준다. **자리는 노드 크기가 아니라 상수에서 계산한다** — `setup()` 은
## 카드가 트리에 들어간 직후, 첫 레이아웃 패스보다 **먼저** 돌 수 있어 그때
## `desc_label.size` 는 아직 0 이다. 카드가 160×220 고정이라 상수 산술이 언제나
## 같은 답을 준다.
func _fit_desc_font_size() -> int:
	var text: String = data.description
	if text.is_empty():
		return DESC_FONT_MAX
	var avail_w: float = CARD_W - 2.0 * DESC_INSET - 2.0 * DESC_PAD_H
	var avail_h: float = CARD_H - DESC_TOP - DESC_INSET - 2.0 * DESC_PAD_V
	# 충전 카드는 오른쪽 아래에 `N/M` 배지가 앉는다 — 그 한 줄만큼 자리를 비운다.
	if data.is_charge_card():
		avail_h -= CHARGE_BADGE_SIZE.y
	var f: Font = desc_label.get_theme_font("font")
	if f == null:
		f = ThemeDB.fallback_font
	if f == null:
		return DESC_FONT_MIN
	var brk: int = (TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
			| TextServer.BREAK_ADAPTIVE | TextServer.BREAK_TRIM_EDGE_SPACES)
	var fs: int = DESC_FONT_MAX
	while fs > DESC_FONT_MIN:
		var m: Vector2 = f.get_multiline_string_size(text,
				HORIZONTAL_ALIGNMENT_LEFT, avail_w, fs, -1, brk)
		if m.y <= avail_h:
			return fs
		fs -= 1
	return DESC_FONT_MIN


func _cost_color(cost: int) -> Color:
	match cost:
		1: return Color(0.2, 0.6, 0.9)
		2: return Color(0.2, 0.75, 0.4)
		3: return Color(0.9, 0.75, 0.1)
		4: return Color(0.9, 0.45, 0.1)
		5: return Color(0.85, 0.2, 0.2)
		6: return Color(0.6, 0.1, 0.8)
		_: return Color(0.15, 0.1, 0.25)


# ── Layout Tween ──────────────────────────────────────────────────────────────

## Converts a viewport-space layout slot into the raw `position` this card must
## hold to land there.
##
## Do NOT tween `global_position` on these cards. `Control.global_position` is
## the *rotated-and-scaled top-left corner*, not the card's anchor: its getter
## returns `position + pivot − R·S·pivot` and its setter inverts that using
## whatever rotation/scale the node happens to have at the instant of the write.
## Once hover scaling entered the picture that made the landing spot depend on
## the live scale — a card written at scale 1.2 settles ~15px right and ~22px
## below the same card written at scale 1.0, which is exactly how the lifted
## card drifted up-right and the deselected card sank below its slot. `position`
## has no such coupling (the card's visual centre is always `position + pivot`),
## so all layout goes through it.
func layout_position_from_global(target_global: Vector2) -> Vector2:
	var parent_ci := get_parent() as CanvasItem
	if parent_ci == null:
		return target_global
	return parent_ci.get_global_transform_with_canvas().affine_inverse() * target_global


## Smoothly move this card to target slot position / rotation / scale.
## `target_pos` is the viewport-space slot (same convention as before — the
## card's unrotated top-left); it is converted through
## `layout_position_from_global` so rotation and hover scale never bend it.
## Kills any in-progress layout tween first to prevent conflicts.
## `target_scale` is the card's *layout* scale — the hover enlargement is
## multiplied on top of it, so a relayout mid-hover doesn't snap the card back
## down to 1.0.
## ease_type / trans_type accept Tween.EaseType / Tween.TransitionType int values.
func tween_to(target_pos: Vector2, target_rot: float, target_scale: Vector2,
		duration: float,
		ease_type: int = Tween.EASE_OUT,
		trans_type: int = Tween.TRANS_SPRING) -> void:
	if _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	# `scale` has exactly one owner at a time. Unless the caller is actually
	# changing the layout scale (nobody does today — every caller passes ONE),
	# the layout tween keeps its hands off it and `_refresh_float_state` stays
	# the sole driver. Two tweens racing over `scale` is what used to strand a
	# hovered card at 1.0: a relayout fired mid-hover captured the hover factor
	# from a transient `_is_hovered` and killed the hover tween on its way past.
	var takes_scale: bool = not _base_scale.is_equal_approx(target_scale)
	_base_scale = target_scale
	_active_tween = create_tween().set_parallel()
	(_active_tween.tween_property(self, "position",
			layout_position_from_global(target_pos), duration)
			.set_ease(ease_type).set_trans(trans_type))
	(_active_tween.tween_property(self, "rotation", target_rot, duration)
			.set_ease(ease_type).set_trans(trans_type))
	if takes_scale:
		if _float_tween != null and _float_tween.is_running():
			_float_tween.kill()
		var scale_goal: Vector2 = _base_scale * (HOVER_SCALE if _is_hovered else 1.0)
		(_active_tween.tween_property(self, "scale", scale_goal, duration)
				.set_ease(ease_type).set_trans(trans_type))


## Enter / leave the held pose. Entering kills any layout tween still in flight
## and locks in the lifted look; leaving hands the card back to whatever pose
## CardPhaseManager tweens it to next. `_begin_drag` re-poses the card right
## after, so the killed tween never strands it half-way.
func set_dragging(dragging: bool) -> void:
	if is_dragging == dragging:
		return
	is_dragging = dragging
	if dragging and _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	if not dragging and _free_rot_tween != null and _free_rot_tween.is_running():
		_free_rot_tween.kill()
	_refresh_float_state()


## 자유 이동 드래그(대상이 없는 카드) 진입. 카드는 손패의 슬롯을 떠나 커서를
## 따라다니므로, 부채꼴 기울기를 곧게 펴 "손에서 뽑아 든" 자세로 만든다.
## 위치는 `follow_cursor` 가 매 모션마다 직접 쓰므로 여기서 건드리지 않는다.
func begin_free_drag() -> void:
	if _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	if _free_rot_tween != null and _free_rot_tween.is_running():
		_free_rot_tween.kill()
	_free_rot_tween = create_tween()
	(_free_rot_tween.tween_property(self, "rotation", 0.0,
			FREE_DRAG_STRAIGHTEN_SEC)
			.set_ease(HOVER_EASE).set_trans(HOVER_TRANS))


## 드로우 인트로의 마지막 박자 — 뒷면으로 날아온 카드를 그 자리에서 뒤집어
## 내용을 드러낸다. 총 `FLIP_HALF_SEC × 2` 초가 걸리며, 호출 측은 그 시간을
## 타이머로 기다린다(트윈의 `finished` 를 기다리면 도중에 카드가 free 될 때
## 신호가 영영 오지 않는다).
##
## 뒤집기는 `scale.x` 를 0 까지 접었다 다시 펴는 것이고, 앞/뒷면 교체는 폭이
## 0 인 정확히 그 순간에 일어난다 — 카드가 화면에서 사라져 있는 프레임이라
## 바뀌는 장면이 보이지 않는다.
func play_flip_reveal() -> void:
	if _flip_tween != null and _flip_tween.is_running():
		_flip_tween.kill()
	_flip_active = true
	_flip_tween = create_tween()
	(_flip_tween.tween_property(self, "scale", Vector2(0.0, _base_scale.y),
			FLIP_HALF_SEC).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE))
	_flip_tween.tween_callback(_reveal_face)
	(_flip_tween.tween_property(self, "scale", _base_scale, FLIP_HALF_SEC)
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE))
	_flip_tween.tween_callback(_end_flip)


func _reveal_face() -> void:
	face_up = true
	card_front.visible = true
	card_back.visible = false
	# 뒷면인 동안은 `_refresh_block_overlay` 가 슬래브를 무조건 숨겼으므로
	# (뒷면에는 읽을 비용도 시전자도 없다) 앞면이 된 지금 다시 판정한다.
	_refresh_block_overlay()


func _end_flip() -> void:
	_flip_active = false
	# 뒤집는 동안 밀린 호버/드래그 상태를 한 번에 반영한다.
	_refresh_float_state()


## 버려지는 카드의 마지막 연출. 손패 배열에서 이미 빠진 노드를 받아 화면
## 아래로 떨어뜨리며 투명하게 만들고, 다 내려가면 스스로 사라진다.
##
## **방향은 언제나 화면 아래**다: 부모(캔버스)는 회전이 없으므로 `position.y`
## 를 더하는 것이 곧 순수 Y축 이동이고, 카드 자신의 부채꼴 기울기는 이동
## 방향에 아무 영향을 주지 않는다(모양은 기울어진 채로 내려간다).
func begin_discard_fx() -> void:
	intro_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 진행 중이던 레이아웃 / 호버 / 뒤집기 트윈은 전부 이 연출과 같은
	# 프로퍼티를 두고 다투므로 먼저 걷어 낸다.
	for t in [_active_tween, _hover_tween, _float_tween, _shadow_tween,
			_free_rot_tween, _flip_tween]:
		if t != null and t.is_running():
			t.kill()
	_flip_active = false
	var drop_to: Vector2 = position + Vector2(0.0, DISCARD_DROP_PX)
	var faded := Color(modulate.r, modulate.g, modulate.b, 0.0)
	var tw := create_tween().set_parallel()
	(tw.tween_property(self, "position", drop_to, DISCARD_FADE_SEC)
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC))
	(tw.tween_property(self, "modulate", faded, DISCARD_FADE_SEC)
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD))
	tw.chain().tween_callback(queue_free)


## 카드의 **시각 중심**을 `cursor`(뷰포트 좌표)에 맞춘다. 중심은 회전/스케일에
## 불변인 `position + pivot_offset` 이므로 (Card.tween_to 주석 참조) 목표
## 좌상단은 `cursor - pivot_offset` 이고, 그 값을 부모 좌표계로 되돌려 `position`
## 에 쓴다 — `global_position` 은 절대 쓰지 않는다(스케일 결합).
func follow_cursor(cursor: Vector2) -> void:
	position = layout_position_from_global(cursor - pivot_offset)


# ── Interaction ───────────────────────────────────────────────────────────────

func store_base_y() -> void:
	_stored_base_y = position.y


## True while the cursor is on this card and the hover reaction is showing.
## CardPhaseManager reads it to decide which card the hand row spreads around
## and which card sits on top of the z-order.
func is_hovered() -> bool:
	return _is_hovered


## Updates the top-left cost number to reflect any active cost modifier
## (effective_cost) and colours it: green when reduced below printed cost,
## red when increased, white when unchanged. CardPhaseManager calls this
## from highlight_affordable_cards so every modifier (사전 준비 / 전투 준비
## / 집중 / cost_inc_phase) repaints the cost in sync with affordability.
## 정밀 이동's +1 is NOT a modifier — `return_left:1` bumps the card's own
## `cost`, so a returned card reads white at its new printed price.
func update_displayed_cost(effective_cost: int) -> void:
	if data == null:
		return
	# 비용 -1 은 값이 아니라 **낼 수 없다는 표시**다 — 할인도 증세도 얹히지 않고
	# 언제나 같은 글자를 찍는다.
	if not data.is_playable():
		cost_label.text = UNPLAYABLE_COST_TEXT
		cost_label.add_theme_color_override("font_color", COST_COLOR_BASE)
		return
	cost_label.text = str(effective_cost)
	var col: Color = COST_COLOR_BASE
	if effective_cost < data.cost:
		col = COST_COLOR_REDUCED
	elif effective_cost > data.cost:
		col = COST_COLOR_INCREASED
	cost_label.add_theme_color_override("font_color", col)


## 핸드가 내려가 있는가(= 내 차례가 아닌가)를 알린다. 바꾸는 것은 **그림자
## 거리 하나**이고 카드 자리는 `CardPhaseManager.slot_position` 이 따로 민다 —
## 둘 다 같은 질문(`_hand_is_lowered`)을 읽으므로 어긋나지 않는다.
func set_lowered(on: bool) -> void:
	if _lowered == on:
		return
	_lowered = on
	_refresh_float_state()


## Marks whether the player can currently pay for this card. The card body
## keeps its cost colour either way — an unaffordable card is conveyed by the
## full-card dim slab (`_refresh_block_overlay`), not by repainting the panel
## grey, because the grey panel sits *under* the owner face and left the
## portrait reading as bright/playable.
func set_affordable(affordable: bool) -> void:
	_affordable = affordable
	var style := StyleBoxFlat.new()
	style.bg_color = _cost_color(data.cost)
	style.border_color = Color(1.0, 0.9, 0.1, 1.0) if affordable else Color(0.45, 0.42, 0.22, 1.0)
	style.border_width_bottom = 4 if affordable else 2
	style.border_width_top    = 4 if affordable else 2
	style.border_width_left   = 4 if affordable else 2
	style.border_width_right  = 4 if affordable else 2
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10
	card_front.add_theme_stylebox_override("panel", style)
	_refresh_block_overlay()


## Turns (>0) until this card's 시전자 respawns, 0 while they're alive. A card
## whose owner is down is dimmed like an unaffordable one and additionally
## carries the countdown number across its face; CardPhaseManager refuses to
## play it while this is non-zero.
func set_respawn_turns(turns: int) -> void:
	_respawn_turns = max(0, turns)
	_refresh_block_overlay()


## 계획 중시로 보존된 카드인지 표시한다. 순수 시각 표시로, 플레이 가능 여부에는
## 영향을 주지 않는다 — 보존은 `_trim_hand_overflow` 만 읽는 규칙이다.
func set_preserved(preserved: bool) -> void:
	if _preserved == preserved:
		return
	_preserved = preserved
	_refresh_block_overlay()


## True when neither reason blocks this card. Read by CardPhaseManager to gate
## the 확인 button.
func is_playable() -> bool:
	return _affordable and _respawn_turns == 0


## Drives the hover reaction (brighten + enlarge + taller shadow) and fires the
## card_hovered / card_unhovered signals.
##
## Player hand cards are `MOUSE_FILTER_IGNORE` and never pick the mouse for
## themselves — `CardPhaseManager`'s hand hit layer decides which card the cursor
## is on and calls this. The cards overlap far more than they are wide and the
## hovered one is drawn on top at 1.2×, so letting each card claim its own rect
## meant the hovered card swallowed its neighbour's only reachable pixels. The
## remaining `mouse_entered` / `mouse_exited` wiring below still serves the AI
## peek row and the 찾기 grid, which are flat and don't overlap.
func set_hovered(hovered: bool) -> void:
	if not face_up or not is_player_card:
		return
	# 아직 날아오는 중인 카드는 손패의 일원이 아니다 — 호버 확대가 붙으면
	# 인트로가 소유한 `scale` / `position` 을 두고 다툰다.
	if intro_active:
		return
	if hovered and _is_dimmed:
		return
	if _is_hovered == hovered:
		return
	_is_hovered = hovered
	_tween_hover_brightness(hovered)
	_refresh_float_state()
	if hovered:
		card_hovered.emit(self)
	else:
		card_unhovered.emit(self)


func _on_mouse_entered() -> void:
	set_hovered(true)


func _on_mouse_exited() -> void:
	set_hovered(false)


func _tween_hover_brightness(active: bool) -> void:
	if _hover_tween != null and _hover_tween.is_running():
		_hover_tween.kill()
	var target: Color = (Color(HOVER_BRIGHTEN, HOVER_BRIGHTEN, HOVER_BRIGHTEN, 1.0)
			if active else Color.WHITE)
	_hover_tween = create_tween()
	(_hover_tween.tween_property(self, "modulate", target, HOVER_TWEEN_DURATION)
			.set_ease(HOVER_EASE).set_trans(HOVER_TRANS))


# Toggle the player-hand "dim" state. CardPhaseManager calls this whenever the
# player can't act on the hand — i.e., during BATTLE auto-tick, while the
# turn-start banner is mid-flight, or while the AI is playing its own cards.
func set_dimmed(dim: bool) -> void:
	if _is_dimmed == dim:
		return
	_is_dimmed = dim
	if _hover_tween != null and _hover_tween.is_running():
		_hover_tween.kill()
	_is_hovered = false
	modulate = DIM_MODULATE if dim else Color.WHITE
	# Dropping the hover state also drops the hover enlargement / big shadow.
	_refresh_float_state()


# **A card never handles its own press.** Hand cards are MOUSE_FILTER_IGNORE and
# the row's `HandHitLayer` routes every press / motion / release; the 찾기 grid
# and the 버리기 fan park their own transparent Button over each card. The
# `card_clicked` signal this class used to emit had no listeners left once
# click-to-select was removed, so it is gone too.
