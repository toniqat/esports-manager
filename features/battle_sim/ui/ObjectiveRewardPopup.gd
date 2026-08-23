class_name ObjectiveRewardPopup
extends Node

# 오브젝트(전령 / 용) **보상 미리보기** — 상단 패널의 시계를 누르면 열린다.
#
# 오브젝트는 회피할 수 있는 사건이다(참여 / 미참여). 그런데 참여를 물어보는
# 창은 결판이 임박한 그 턴에야 뜨고, 거기 적힌 한 줄(`ObjectiveSystem.reward_text`)
# 말고는 "이걸 먹으면 뭐가 생기는가"를 볼 자리가 경기 내내 없었다. 시계는 남은
# 턴 수를 상시로 말해 주는 물건이니, 그 옆에 **무엇을 두고 세는 시계인지**도
# 붙여 두는 것이 자연스럽다 — 라인을 밀지 정글러를 붙일지는 보상의 값어치를
# 알아야 정해진다.
#
# **전장을 붙잡지 않는다.** `ObjectiveSystem` 의 참여 결정 창과 달리 이건 순수
# 정보 팝업이라 BATTLE 자동 틱도 MM:SS 시계도 평소대로 흐르고, 아무 데나 누르면
# 닫힌다. 대신 열려 있는 동안 뒤쪽 입력은 삼킨다(딤이 STOP).
#
# 보상 카드는 `CardPhaseManager.make_objective_card` 가 만든 **진짜 CardData** 를
# 손패와 같은 `Card.tscn` 노드에 태워 보여 준다 — 따로 그린 그림이면 실제로
# 손에 들어온 카드와 같은 것인지 확인할 길이 없다.

## 열람(12)과 같은 층. 파일럿 상세(13) 아래 — 상세 패널이 열려 있으면 스트립이
## 숨겨져 시계도 눌리지 않으므로 둘이 겹칠 일은 없다.
const OVERLAY_LAYER: int = 12

const VP_W: float = 1080.0
const VP_H: float = 1920.0
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.78)

const PANEL_W: float = 560.0
const PANEL_PAD: float = 28.0
const PANEL_BG := Color(0.06, 0.07, 0.12, 0.98)
const PANEL_BORDER := Color(0.62, 0.80, 1.0, 0.85)

const TITLE_FONT: int = 40
const SUB_FONT: int = 24
const NOTE_FONT: int = 22
const COUNT_FONT: int = 30

const HERALD_COLOR := Color(0.74, 0.62, 0.99)
const DRAGON_COLOR := Color(1.00, 0.55, 0.28)
const SUB_COLOR := Color(0.80, 0.83, 0.90)
const NOTE_COLOR := Color(0.66, 0.70, 0.80)

const BTN_W: float = 200.0
const BTN_H: float = 64.0

var _bs: BattleSim = null
var _layer: CanvasLayer = null
var _root: Control = null
var _kind: int = -1


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = OVERLAY_LAYER
	_layer.name = "ObjectiveRewardLayer"
	add_child(_layer)


func bind(bs: BattleSim) -> void:
	_bs = bs


func is_active() -> bool:
	return _root != null


## 같은 시계를 다시 누르면 닫힌다 — 여는 손잡이가 곧 닫는 손잡이다.
func toggle(kind: int) -> void:
	if is_active() and _kind == kind:
		close()
		return
	open(kind)


func open(kind: int) -> void:
	close()
	if _bs == null or _bs.objective == null or _bs.card_phase == null:
		return
	_kind = kind
	_build()


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_kind = -1


# ─── UI ──────────────────────────────────────────────────────────────────────
func _build() -> void:
	_root = Control.new()
	_root.name = "ObjectiveReward"
	# CanvasLayer 아래의 Control 은 full-rect 앵커를 풀어 줄 부모 rect 가 없다 —
	# 크기는 명시한다(PilotDetailPanel 과 같은 이유).
	_root.position = Vector2.ZERO
	_root.size = Vector2(VP_W, VP_H)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.position = Vector2.ZERO
	dim.size = Vector2(VP_W, VP_H)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)

	var is_herald: bool = _kind == ObjectiveSystem.Kind.HERALD
	var accent: Color = HERALD_COLOR if is_herald else DRAGON_COLOR
	var card_id: int = ObjectiveSystem.HERALD_CARD_ID if is_herald \
			else ObjectiveSystem.DRAGON_CARD_ID
	var copies: int = 1 if is_herald else int(_bs.OBJ_DRAGON_CARD_COUNT)
	var cd: CardData = _bs.card_phase.make_objective_card(card_id)

	# 판 높이는 내용이 정한다 — 제목 · 남은 턴 · 보상 한 줄 · 카드 · 설명 · 닫기.
	var card_h: float = Card.CARD_H
	var body_h: float = 54.0 + 34.0 + 12.0 + 34.0 + 18.0 + card_h + 14.0 \
			+ 34.0 + 20.0 + BTN_H
	var panel_h: float = body_h + PANEL_PAD * 2.0
	var px: float = (VP_W - PANEL_W) * 0.5
	var py: float = (VP_H - panel_h) * 0.5

	var panel := Panel.new()
	panel.position = Vector2(px, py)
	panel.size = Vector2(PANEL_W, panel_h)
	# 판 위 클릭은 닫지 않는다 — 딤까지 이벤트가 내려가지 않게 STOP.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = accent
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.corner_radius_top_left = 20
	sb.corner_radius_top_right = 20
	sb.corner_radius_bottom_left = 20
	sb.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var iw: float = PANEL_W - PANEL_PAD * 2.0
	var y: float = PANEL_PAD

	_add_label(panel, ObjectiveSystem.kind_name(_kind), TITLE_FONT, accent,
			Vector2(PANEL_PAD, y), Vector2(iw, 54.0), HORIZONTAL_ALIGNMENT_CENTER)
	y += 54.0

	var left: int = _bs.objective.turns_until_cell(_cell())
	var when_txt: String = "%d턴 뒤 등장" % left if left > 0 else "지금 열려 있다"
	_add_label(panel, when_txt, SUB_FONT, SUB_COLOR,
			Vector2(PANEL_PAD, y), Vector2(iw, 34.0), HORIZONTAL_ALIGNMENT_CENTER)
	y += 34.0 + 12.0

	_add_label(panel, _bs.objective.reward_text(_kind), SUB_FONT, SUB_COLOR,
			Vector2(PANEL_PAD, y), Vector2(iw, 34.0), HORIZONTAL_ALIGNMENT_CENTER)
	y += 34.0 + 18.0

	_build_card(panel, cd, Vector2(PANEL_PAD, y), iw, card_h, copies, accent)
	y += card_h + 14.0

	_add_label(panel, _where_text(is_herald), NOTE_FONT, NOTE_COLOR,
			Vector2(PANEL_PAD, y), Vector2(iw, 34.0), HORIZONTAL_ALIGNMENT_CENTER)
	y += 34.0 + 20.0

	var btn := Button.new()
	btn.text = "닫기"
	btn.add_theme_font_size_override("font_size", 26)
	btn.position = Vector2(PANEL_PAD + (iw - BTN_W) * 0.5, y)
	btn.size = Vector2(BTN_W, BTN_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(close)
	panel.add_child(btn)


## 보상 카드 한 장 + (여러 장이면) `×N` 배지. 카드가 DB 에서 안 나오면
## (`make_objective_card` 가 null) 자리만 비워 둔다 — 팝업 하나 때문에 매치를
## 세우지 않는다.
func _build_card(panel: Panel, cd: CardData, at: Vector2, iw: float,
		card_h: float, copies: int, accent: Color) -> void:
	if cd == null:
		_add_label(panel, "보상 카드를 찾지 못했다", NOTE_FONT, NOTE_COLOR,
				at, Vector2(iw, card_h), HORIZONTAL_ALIGNMENT_CENTER)
		return
	var node := _bs.CARD_SCENE.instantiate() as Card
	# add_child BEFORE setup — Card.gd 의 @onready 참조가 트리 진입 후에야 풀린다
	# (CardPileViewer._build_grid 와 동일).
	panel.add_child(node)
	node.setup(cd, false, true)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = at + Vector2((iw - Card.CARD_W) * 0.5, 0.0)

	if copies <= 1:
		return
	_add_label(panel, "×%d" % copies, COUNT_FONT, accent,
			Vector2(at.x + (iw + Card.CARD_W) * 0.5 + 10.0, at.y + card_h * 0.5 - 22.0),
			Vector2(80.0, 44.0), HORIZONTAL_ALIGNMENT_LEFT)


## 그 카드가 **어디로** 들어오는지. 손패냐 덱이냐는 "지금 쓸 수 있는가"를 가르는
## 차이라 카드 그림만으로는 안 나온다.
func _where_text(is_herald: bool) -> String:
	if is_herald:
		return "획득 즉시 손패로 들어온다"
	return "획득 시 덱에 섞여 들어간다"


func _cell() -> Vector2i:
	return SimulationCore.NEUTRAL_LEFT \
			if _kind == ObjectiveSystem.Kind.HERALD else SimulationCore.NEUTRAL_RIGHT


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		close()


static func _add_label(parent: Control, text: String, font_size: int,
		color: Color, at: Vector2, sz: Vector2, halign: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# `clip_text` 를 크기보다 **먼저** 켠다 — 끄고 있는 Label 의 최소 폭은 한 줄로
	# 편 글자 전체 폭이라, 그 상태로 좁은 rect 를 요청하면 세터가 요청을 무시하고
	# 글자 폭까지 부풀린다(가운데 정렬이 그만큼 어긋난다).
	lbl.clip_text = true
	lbl.position = at
	lbl.size = sz
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
