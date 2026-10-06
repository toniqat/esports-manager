class_name HubSheet
extends CanvasLayer

# 허브 관리 카드(스태프 · 메크 연구 · 재무)가 여는 **공용 상세 시트**.
# 화면 전체를 딤으로 덮고, 안전 영역 안에 흰 판 한 장(제목 · 세로 스크롤 본문 ·
# 하단 `닫기`)을 띄운다. 패턴은 `meta/lobby/ConfirmPopup.gd` 와 같다 — CanvasLayer
# 라서 좌표는 뷰포트 기준이고(`docs/mobile_safe_area.md` 패턴 C) 판은 안전 영역
# 안에 선다.
#
# 쓰는 법 (각 패널의 `open(host)`):
#   var sheet := HubSheet.open_on(host, "스태프")
#   var body: Control = sheet.body          # 폭 = sheet.body_w(), 절대 좌표로 얹는다
#   ... body 에 자식을 얹고 ...
#   sheet.set_body_height(y)                # 스크롤 높이
#   sheet.closed.connect(...)               # 닫힐 때(허브 갱신 등)
#
# 시트 안에서 상태를 바꾸는 패널은 닫힐 때 허브가 `refresh()` 하도록
# `HubView` 가 `closed` 를 이미 잇는다 — 패널이 따로 허브를 부를 필요 없다.

signal closed

const OVERLAY_LAYER: int = 18
const DIM_COLOR := Color(0.11, 0.11, 0.18, 0.58)
const SIDE_MARGIN: float = 36.0
const TOP_MARGIN: float = 60.0
const PAD: float = 40.0
const TITLE_H: float = 56.0
const BTN_H: float = 112.0

var body: Control = null
var _root: Control = null
var _card: Panel = null
var _card_w: float = 0.0


func _init() -> void:
	layer = OVERLAY_LAYER


## `host` 아래에 시트를 열어 돌려준다.
static func open_on(host: Node, title: String) -> HubSheet:
	var sheet := HubSheet.new()
	host.add_child(sheet)
	sheet._build(title)
	return sheet


## 본문 폭(스크롤 안쪽).
func body_w() -> float:
	return _card_w - PAD * 2.0


## 본문 높이를 알린다(스크롤 범위).
func set_body_height(h: float) -> void:
	if body != null:
		body.custom_minimum_size.y = h


## 판 위에 고정 버튼 줄이 더 필요할 때(예: 재무의 `업그레이드`) 닫기 버튼
## 왼쪽에 둘 자리 — 판 기준 좌표. 버튼은 부르는 쪽이 만든다.
func card() -> Panel:
	return _card


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	closed.emit()
	queue_free()


func _build(title: String) -> void:
	var vp: Vector2 = ScreenMetrics.viewport_size()
	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 딤은 뒤의 허브로 입력이 새지 않게 먹는다. 빈 곳 누름 = 닫기.
	var dim := Button.new()
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.position = Vector2.ZERO
	dim.size = vp
	dim.pressed.connect(close)
	_root.add_child(dim)
	var dim_rect := ColorRect.new()
	dim_rect.color = DIM_COLOR
	dim_rect.position = Vector2.ZERO
	dim_rect.size = vp
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim_rect)

	var top: float = ScreenMetrics.top_y() + TOP_MARGIN
	var bottom: float = ScreenMetrics.bottom_y() - 24.0
	_card_w = minf(vp.x - SIDE_MARGIN * 2.0, 1008.0)
	var card_h: float = bottom - top
	_card = OutgameTheme.add_card(_root,
			Vector2(ScreenMetrics.center_x() - _card_w * 0.5, top),
			Vector2(_card_w, card_h), 24)
	# 판 위 누름이 딤까지 내려가 시트를 닫으면 안 된다.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP

	UiHelpers.mk_label(_card, title, 40, OutgameTheme.TEXT,
			Vector2(PAD, PAD - 6.0), Vector2(body_w(), TITLE_H))
	OutgameTheme.add_divider(_card, Vector2(PAD, PAD + TITLE_H + 8.0), body_w())

	var scroll_top: float = PAD + TITLE_H + 24.0
	var scroll_h: float = card_h - scroll_top - BTN_H - PAD - 20.0
	var vs: Dictionary = OutgameTheme.add_vscroll(_card, Vector2(PAD, scroll_top),
			Vector2(body_w(), scroll_h))
	body = vs["body"]

	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_ghost_button(close_btn, 30)
	close_btn.position = Vector2(PAD, card_h - PAD - BTN_H)
	close_btn.size = Vector2(body_w(), BTN_H)
	close_btn.pressed.connect(close)
	_card.add_child(close_btn)
