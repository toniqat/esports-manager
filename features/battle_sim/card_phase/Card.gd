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
## 충전 배지는 **오른쪽 아래**다 — 오른쪽 위는 파일럿 초상 리본이 가져갔고,
## 왼쪽 위는 비용 칸이다. `N/M` 으로 찍어 숫자 하나가 비용으로 오독되지 않게 한다.
const CHARGE_BADGE_SIZE := Vector2(52.0, 30.0)
const CHARGE_BADGE_COLOR := Color(0.06, 0.05, 0.10, 0.92)
const CHARGE_BADGE_TEXT_COLOR := Color(1.0, 0.92, 0.45)

# ── 앞면 두 층 (아트 · 이름) ─────────────────────────────
# 카드 앞면은 위에서부터 **아트 → 이름판** 두 층이다. **설명문은 카드에 없다** —
# 카드를 가리키면 손패 바로 위에 뜨는 설명 상자(`CardPhaseManager`)가, 밴픽 · 메크
# 상세에서는 카드를 누르면 뜨는 설명판이 그 글을 든다. 160×220 에 많게는 128자를
# 8pt 로 욱여넣던 설명판은 어차피 읽으라고 있는 글씨가 아니었고, 그 자리를 아트가
# 통째로 가져가면 카드가 **그림으로** 알아보인다.
#
# **카드에는 테두리가 없다** — 앞면은 아트와 이름판 두 판이 카드 사각형을 빈틈
# 없이 나눠 채운다(예전의 비용색 바탕 · '낼 수 있음' 노란 테두리는 지웠다. 못 내는
# 카드는 사용 불가 슬래브 하나로 읽힌다).
#
# **아트는 카드 끝까지 붙고 위 두 모서리만 둥글게 깎는다** — `rounded_top_mask`
# 쉐이더가 SDF 로 덮임을 계산해 곡선이 화면 1px 에 걸쳐 흐려진다(안티앨리어싱).
# `clip_children` 은 카드마다 백버퍼를 뜨고 가장자리가 계단이 되어 쓰지 않는다.
# 아래 모서리는 이름판 `StyleBoxFlat` 의 둥근 모서리가 맡는다.
#
# **이름판은 카드 아랫단 전폭**을 아이템 타입색(`TYPE_COLORS`)으로 채운 판이다.
# 아트와의 경계에는 그림자를 깔지 않는다(예전 `ArtShadow` 띠는 삭제). 좌표는 전부
# `scenes/Card.tscn` 과 같은 절대 좌표다.
const CARD_RADIUS := 10.0
const NAME_PLATE_H := 36.0
## 이름판 윗변(184) = 아트 아랫변.
const NAME_TOP := CARD_H - NAME_PLATE_H
const ART_BACK_COLOR := Color(0.05, 0.04, 0.09, 1.0)
const ART_MASK_SHADER: Shader = preload("res://resources/shaders/rounded_top_mask.gdshader")
## 이름판 색 — `CardImages.type_for` 가 답하는 아이템 타입별(deadlock.wiki 색을
## 흰 글씨가 읽히게 어둡게 깐 것). 타입이 없는 카드(표에 없는 새 카드)는 중립색.
const TYPE_COLORS: Dictionary = {
	CardImages.TYPE_WEAPON: Color("#A86A22"),
	CardImages.TYPE_SPIRIT: Color("#7E4FB0"),
	CardImages.TYPE_VITALITY: Color("#5A8A16"),
}
const NAME_PLATE_NEUTRAL_COLOR := Color(0.18, 0.16, 0.24, 1.0)

## 1.5x the old 15. Names wider than the plate (148px) shrink via `_fit_name_font_size`.
const NAME_FONT_SIZE := 23
const NAME_FONT_MIN := 14

# ── 비용 리본 (좌측 상단, 카드 안에 매달린다) ──────────────────
# 비용은 카드 윗변에서 아래로 늘어진 **세로로 긴 직각사다리꼴 리본**(`CostRibbon`)
# 위쪽에 큰 숫자로 찍힌다. 테두리도 안쪽 아이콘도 없는 어두운 알맹이뿐이다. 손패는 카드끼리 절반 넘게 겹치는 부채꼴이라(오른쪽 카드가 왼쪽 카드를
# 덮는다) 왼쪽 위가 각 카드에서 언제나 보이는 유일한 구석이다. 리본은 카드 둥근
# 모서리(`CARD_RADIUS`) 안쪽에서 시작하므로 윗변이 곧게 붙는다. 윗변은 카드
# 윗변보다 `COST_RIBBON_POKE` 만큼 **위로 튀어나와** 리본이 카드에 매달린 것으로
# 읽힌다(아랫변 · 숫자 자리는 그대로다).
const COST_RIBBON_POKE := 3.0
const COST_RIBBON_RECT := Rect2(10.0, -COST_RIBBON_POKE, 38.0, 70.0 + COST_RIBBON_POKE)
const COST_BADGE_FILL_COLOR := CostRibbon.FILL
## 숫자가 앉는 리본 위쪽 띠 높이.
const COST_NUMBER_H := 50.0
const COST_FONT_SIZE := 32
## 비용 배지는 사용 불가 슬래브 · 보존 테두리보다 **위**에 앉으므로(`_build_block_overlay`)
## 슬래브에 덮이지 않는다. 배지를 따로 어둡게 해 잠긴 카드에서 비용만 밝게 남지 않게 한다.
const COST_BADGE_BLOCKED_TINT := Color(0.42, 0.42, 0.42, 1.0)

# ── 파일럿 초상 리본 (우측 상단 직각삼각형) ─────────────────
# 시전자의 얼굴은 카드 **오른쪽 위 모서리를 덮는 직각삼각형 리본**에 눈이 보이게
# 잘려 앉는다. 두 직각변이 카드 윗변 · 오른변에 붙고, 빗변 아래로만 그림자가
# 떨어진다(빗변 테두리는 없다).
#
# **런타임 마스킹이 아니라 파일럿별로 구운 PNG** 다
# (`PilotImages.ribbon_for`, `make_ribbon_crops.py`). 삼각형 · 둥근 카드 모서리
# (`CARD_RADIUS`) · 안티앨리어싱 · 그림자가 전부 그림 안에 있어 여기서는 평범한
# TextureRect 하나다 — 마스크 쉐이더를 쓰면 손패 카드마다 ShaderMaterial 이 붙어
# 모바일에서 첫 사용 컴파일 · 배치 분리 비용이 생긴다. 크기를 바꾸려면 아래
# 상수와 스크립트의 `LEG` / `SHADOW_PAD` 를 함께 고치고 다시 구울 것.
#
# 손패가 많아 카드가 겹치면 오른쪽 카드가 이 모서리를 덮는다 — 가리킨 카드(줄이
# 벌어진다)와 맨 오른쪽 카드에서만 온전히 보이는 것은 감수한 선택이다.
#
# **손패에서만 그린다**(`is_player_card`). 상세 패널 · 더미 열람 · 밴픽 · 드래프트
# 처럼 "이 기체가 주는 카드"를 보여 주는 자리에서는 시전자가 없거나 의미가 없고,
# 상대 손패 peek 은 뒷면이라 그릴 것이 없다.
## 삼각형 직각변 길이 (카드 단위). 리본 PNG 는 이 값 × 2 px 로 구워져 있다.
const RIBBON_LEG := 60.0
## 삼각형 아래 그림자가 떨어지는 띠 높이. 리본 노드 높이 = LEG + 이 값.
const RIBBON_SHADOW_PAD := 8.0

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
## 비용 미리보기(`set_cost_preview`) 상태와 그 맥박 트윈.
var _cost_preview_on: bool = false
var _cost_pulse: Tween = null
const COST_PULSE_SCALE: float = 1.28
const COST_PULSE_HALF: float = 0.28
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
## 버려질 카드 표시(붉은 딤 + 아래로 흐르는 chevron). **카드 자신의 자식**이라
## 손패의 그리기 순서를 그대로 따른다 — 1번 카드 → 1번 딤 → 2번 카드 → 2번 딤.
## 예전에는 손패 위 한 층(`CardPlayPreview._draw`)에 딤을 모아 그려, 겹친 카드의
## 딤끼리 포개져 진해지고 옆 카드의 보이는 몫까지 덮었다.
var _doomed: bool = false
var _doom_mark: DoomMark = null
## 충전 배지 (`N/M`). 충전 카드가 아니면 꺼진다.
var _charge_badge: Label = null
## 시전자 얼굴 리본 (오른쪽 위 모서리 삼각형). 손패 카드에만 선다.
var _portrait: TextureRect = null
## 핸드가 내려가 있는가(= 내 차례가 아닌가). 그림자 거리만 바꾼다.
var _lowered: bool = false

const DIM_MODULATE: Color = Color(0.42, 0.42, 0.48, 1.0)

@onready var card_front: Panel = $CardFront
@onready var card_back: Panel = $CardBack
@onready var art_frame: Panel = $CardFront/ArtFrame
@onready var art_rect: TextureRect = $CardFront/ArtFrame/Art
@onready var name_label: Label = $CardFront/NameLabel
@onready var name_plate: Panel = $CardFront/NamePlate
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
	_sync_face_visibility(start_face_up)
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
	# 이름판 바로 위, 아트의 오른쪽 아래 구석.
	_charge_badge.position = Vector2(CARD_W - CHARGE_BADGE_SIZE.x - 8.0,
			NAME_TOP - CHARGE_BADGE_SIZE.y - 5.0)
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

	# 시전자 얼굴 리본. 앞면 위에 앉되 **사용 불가 슬래브 아래**여야 한다 —
	# 잠긴 카드에서 얼굴만 밝게 남으면 쓸 수 있는 카드처럼 읽힌다. 그래서 리본을
	# 붙인 뒤 슬래브 · 부활 숫자 · 보존 테두리를 다시 맨 뒤로 보낸다.
	_portrait = TextureRect.new()
	_portrait.name = "OwnerRibbon"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.size = Vector2(RIBBON_LEG, RIBBON_LEG + RIBBON_SHADOW_PAD)
	_portrait.position = Vector2(CARD_W - RIBBON_LEG, 0.0)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.visible = false
	add_child(_portrait)
	# 슬래브 · 부활 숫자 · 보존 테두리가 초상 리본을 덮도록 맨 뒤로 다시 보낸다.
	move_child(_block_overlay, get_child_count() - 1)
	move_child(_respawn_label, get_child_count() - 1)
	move_child(_preserve_mark, get_child_count() - 1)
	# 비용 배지는 그보다도 위다 — 보존 테두리가 왼쪽 위 모서리에서 비용 숫자를
	# 가리지 않게 `CardFront` 밖(루트 맨 뒤)으로 옮긴다. `CardFront` 는 카드 원점에
	# 붙어 있어 로컬 좌표가 그대로이고, 표시 여부는 `_sync_face_visibility` 가
	# 앞면과 맞춘다.
	cost_badge.reparent(self, false)
	move_child(cost_badge, get_child_count() - 1)
	# 버려질 표시는 비용 배지까지 덮는다 — 카드 한 장 전체가 "나간다"는 뜻이다.
	_doom_mark = DoomMark.new()
	_doom_mark.name = "DoomMark"
	_doom_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_doom_mark.size = Vector2(CARD_W, CARD_H)
	_doom_mark.visible = false
	add_child(_doom_mark)


## 앞/뒷면 표시를 바꾼다. 비용 배지는 `CardFront` 밖으로 나가 있으므로 앞면과
## 함께 켜고 끈다.
func _sync_face_visibility(show_front: bool) -> void:
	card_front.visible = show_front
	card_back.visible = not show_front
	cost_badge.visible = show_front


## 토큰 배지와 시전자 초상 리본을 지금 상태에 맞춘다. `CardPhaseManager` 가
## 토큰이 오르거나 내릴 때마다 부른다. 충전 카드는 `토큰/상한`, 상한 없이 쌓이는
## 카드([골드러시])는 토큰 수만 찍는다.
func refresh_charge_badge() -> void:
	var showable: bool = face_up and is_player_card
	if _charge_badge != null and is_instance_valid(_charge_badge):
		var on: bool = showable and data != null and data.shows_tokens()
		_charge_badge.visible = on
		if on:
			if data.is_charge_card():
				_charge_badge.text = "%d/%d" % [data.charge, maxi(1, data.charge_max)]
			else:
				_charge_badge.text = str(data.charge)
	if _portrait != null and is_instance_valid(_portrait):
		var pid: int = -1
		if data != null and data.owner_pilot != null:
			pid = data.owner_pilot.pilot_id
		var tex: Texture2D = PilotImages.ribbon_for(pid) if pid >= 0 else null
		_portrait.texture = tex
		_portrait.visible = showable and tex != null


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
	if _doom_mark != null and is_instance_valid(_doom_mark):
		_doom_mark.set_on(showable and _doomed)
	# 비용 배지는 슬래브 위에 앉으므로 슬래브에 덮이지 않는다 — 직접 눌러 준다.
	if cost_badge != null and is_instance_valid(cost_badge):
		cost_badge.modulate = (COST_BADGE_BLOCKED_TINT
				if _block_overlay.visible else Color.WHITE)
	refresh_charge_badge()


## 버려질 카드 표시를 켜고 끈다. 무엇이 버려질지는 `CardPhaseManager.refresh_doom_marks`
## 한 곳이 정한다(끄는 카드의 버리기 효과 / 턴 넘기기 패널이 열린 동안의 상한 초과 예측).
func set_doomed(on: bool) -> void:
	if _doomed == on:
		return
	_doomed = on
	_refresh_block_overlay()


func is_doomed() -> bool:
	return _doomed


## 버려질 카드 위의 붉은 딤 + 가운데로 흘러 내려가는 chevron(`CardPlayPreview` 와
## 같은 모양). 켜져 있는 동안만 시계를 돌린다.
class DoomMark extends Control:
	const RADIUS: int = 10
	## chevron 기둥이 시작하는 높이(카드 높이 비율).
	const CHEVRON_TOP_RATIO: float = 0.30
	var _t: float = 0.0
	var _sb: StyleBoxFlat = null

	func _ready() -> void:
		_sb = StyleBoxFlat.new()
		_sb.bg_color = CardPlayPreview.DOOMED_TINT
		_sb.set_corner_radius_all(RADIUS)
		set_process(visible)

	func set_on(on: bool) -> void:
		if visible == on:
			return
		visible = on
		_t = 0.0
		set_process(on)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if _sb != null:
			draw_style_box(_sb, Rect2(Vector2.ZERO, size))
		CardPlayPreview.draw_falling_chevrons(self, size.x * 0.5,
				size.y * CHEVRON_TOP_RATIO, CardPlayPreview.DISCARD_COLOR, _t)


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


## Cost number colours — ink on the white cost ribbon: dark (`CostRibbon.INK`)
## when the displayed cost matches the card's printed (data.cost) value, green
## when reduced by an active modifier, red when increased. Surfaced via
## update_displayed_cost so CardPhaseManager can refresh the card whenever
## effective_cost_for changes. Dark enough to read on white — the description
## panel's header ribbon uses the same three.
const COST_COLOR_BASE     := CostRibbon.INK
const COST_COLOR_REDUCED  := Color(0.10, 0.58, 0.18)
const COST_COLOR_INCREASED := Color(0.82, 0.16, 0.14)


func _apply_data() -> void:
	if data == null:
		return
	name_label.text = data.card_name
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.add_theme_font_size_override("font_size", _fit_name_font_size())
	# 앞면 판 자체는 아무것도 그리지 않는다 — 아트와 이름판이 카드를 다 덮고,
	# 그 밑에 깔린 판이 있으면 둥근 모서리의 흐린 가장자리로 비쳐 나온다.
	card_front.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_apply_art()
	_apply_cost_badge()
	_apply_name_plate()
	refresh_charge_badge()


## Largest font size (capped at `NAME_FONT_SIZE`) at which the name fits the plate width.
func _fit_name_font_size() -> int:
	var font: Font = name_label.get_theme_font("font")
	var avail: float = name_label.size.x - 2.0 * name_label.get_theme_constant("outline_size")
	var fs: int = NAME_FONT_SIZE
	while fs > NAME_FONT_MIN and font.get_string_size(name_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
		fs -= 1
	return fs


## 카드 아트 — 이름판 위 전부. 전용 아트가 없는 카드는 `CardImages` 가 이름으로 고른
## 아이템 아이콘(없으면 배경)을 받는다. 그림이 아예 없을 때만 액자 판이 어두운
## 바탕을 그린다 — 그림 밑에 판을 깔면 깎인 모서리로 판의 가장자리가 비친다.
func _apply_art() -> void:
	if art_frame == null or art_rect == null:
		return
	art_rect.texture = CardImages.art_for(data.card_uid())
	var mat := ShaderMaterial.new()
	mat.shader = ART_MASK_SHADER
	mat.set_shader_parameter("rect_size", art_rect.size)
	mat.set_shader_parameter("radius", CARD_RADIUS)
	art_rect.material = mat
	if art_rect.texture != null:
		art_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = ART_BACK_COLOR
	sb.corner_radius_top_left  = int(CARD_RADIUS)
	sb.corner_radius_top_right = int(CARD_RADIUS)
	art_frame.add_theme_stylebox_override("panel", sb)


## 좌측 상단 비용 리본 — 세로로 긴 직각사다리꼴(`CostRibbon`), 불투명한 흰 알맹이에
## 어두운 큰 숫자, 아랫변 밑으로 드롭 섀도.
## Panel 의 스타일박스는 비우고 `draw` 신호로 도형을 그린다.
func _apply_cost_badge() -> void:
	if cost_badge == null or cost_label == null:
		return
	cost_badge.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	cost_badge.position = COST_RIBBON_RECT.position
	cost_badge.size = COST_RIBBON_RECT.size
	cost_label.position = Vector2(0.0, 2.0 + COST_RIBBON_POKE)
	cost_label.size = Vector2(COST_RIBBON_RECT.size.x, COST_NUMBER_H)
	if not cost_badge.draw.is_connected(_draw_cost_badge):
		cost_badge.draw.connect(_draw_cost_badge)
	cost_badge.queue_redraw()
	cost_label.text = UNPLAYABLE_COST_TEXT if not data.is_playable() else str(data.cost)
	cost_label.add_theme_font_size_override("font_size", COST_FONT_SIZE)
	cost_label.add_theme_color_override("font_color", COST_COLOR_BASE)
	cost_label.add_theme_constant_override("outline_size", 0)


func _draw_cost_badge() -> void:
	CostRibbon.draw(cost_badge, Rect2(Vector2.ZERO, cost_badge.size),
			COST_BADGE_FILL_COLOR, -1.0, true)


## 이름판 — 카드 아랫단 전폭을 타입색으로 채운 판(테두리 없음). 아래 두 모서리가
## 카드 모서리다. 이름 라벨은 판의 형제로 같은 자리에 앉는다.
func _apply_name_plate() -> void:
	if name_plate == null:
		return
	var plate := StyleBoxFlat.new()
	plate.bg_color = TYPE_COLORS.get(CardImages.type_for(data.card_uid()),
			NAME_PLATE_NEUTRAL_COLOR)
	plate.corner_radius_bottom_left  = int(CARD_RADIUS)
	plate.corner_radius_bottom_right = int(CARD_RADIUS)
	name_plate.add_theme_stylebox_override("panel", plate)



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
	_sync_face_visibility(true)
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
## 정밀 이동 / 골드러시's increase is NOT a modifier — `self_cost:N` bumps the card's
## own `cost`, so a repositioned card reads white at its new printed price.
## [신중한 예산] 의 "이번 단계 0" 과 [맑은 정신] 의 이웃 할인은 수정자라 초록으로 찍힌다.
func update_displayed_cost(effective_cost: int) -> void:
	if data == null:
		return
	# 미리보기가 걸려 있는 동안은 그 값이 이긴다 — 걷히면 다시 불린다.
	if _cost_preview_on:
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


## 손패 미리보기 — 끌고 있는 카드가 이 카드의 비용을 바꿀 때([사전 준비] ·
## [전투 준비] …) **바뀔 값**을 미리 찍고 비용 배지를 맥박치게 한다.
## `clear_cost_preview` 뒤에는 부르는 쪽이 `update_displayed_cost` 로 원래 값을
## 다시 칠한다(`CardPhaseManager.highlight_affordable_cards`).
func set_cost_preview(cost_after: int) -> void:
	if cost_label == null or cost_badge == null:
		return
	_cost_preview_on = true
	cost_label.text = str(cost_after)
	cost_label.add_theme_color_override("font_color", COST_COLOR_REDUCED)
	if _cost_pulse != null and _cost_pulse.is_valid():
		return
	cost_badge.pivot_offset = cost_badge.size * 0.5
	_cost_pulse = create_tween().set_loops()
	_cost_pulse.tween_property(cost_badge, "scale", Vector2.ONE * COST_PULSE_SCALE,
			COST_PULSE_HALF).set_trans(Tween.TRANS_SINE)
	_cost_pulse.tween_property(cost_badge, "scale", Vector2.ONE,
			COST_PULSE_HALF).set_trans(Tween.TRANS_SINE)


func has_cost_preview() -> bool:
	return _cost_preview_on


func clear_cost_preview() -> void:
	_cost_preview_on = false
	if _cost_pulse != null and _cost_pulse.is_valid():
		_cost_pulse.kill()
	_cost_pulse = null
	if cost_badge != null:
		cost_badge.scale = Vector2.ONE


## 핸드가 내려가 있는가(= 내 차례가 아닌가)를 알린다. 바꾸는 것은 **그림자
## 거리 하나**이고 카드 자리는 `CardPhaseManager.slot_position` 이 따로 민다 —
## 둘 다 같은 질문(`_hand_is_lowered`)을 읽으므로 어긋나지 않는다.
func set_lowered(on: bool) -> void:
	if _lowered == on:
		return
	_lowered = on
	_refresh_float_state()


## Marks whether the player can currently pay for this card. The card itself
## is not repainted — an unaffordable card is conveyed only by the full-card
## dim slab (`_refresh_block_overlay`), which also covers the owner face.
func set_affordable(affordable: bool) -> void:
	_affordable = affordable
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
