class_name ConfirmPopup
extends CanvasLayer

# 되돌릴 수 없는 행동 앞에서 한 번 더 묻는 모달. 화면 전체를 딤으로 덮어
# 뒤의 화면 입력을 막고, 가운데에 흰 카드 한 장(제목 · 본문 · 버튼 둘)을 띄운다.
#
# **두 번 누르기 버튼 대신 모달이다** — 런 포기처럼 진행 기록이 통째로 사라지는
# 행동은 "무엇이 사라지는가"를 글로 읽힌 뒤에 고르게 해야 한다. 같은 버튼을
# 두 번 누르는 방식은 그 설명을 담을 자리가 없다.
#
# 딤 패턴은 `meta/run_setup/DraftDetailPanel.gd` 와 같다 — CanvasLayer 아래에
# 뷰포트 전체 크기의 납작한 Button(빈 곳 누르면 취소) + 반투명 ColorRect.
# CanvasLayer 라서 부모 화면의 `indent_to_safe_top` 을 따라 내려가지 않는다 —
# 좌표는 뷰포트 기준이고(`docs/mobile_safe_area.md` 패턴 C), 카드는 안전
# 영역 한가운데에 선다.
#
# 쓰는 법:
#   var p := ConfirmPopup.new()
#   add_child(p)
#   p.confirmed.connect(...)
#   p.open("제목", "본문", "취소", "확인", true)

signal confirmed
signal cancelled

const OVERLAY_LAYER: int = 20
const DIM_COLOR := Color(0.11, 0.11, 0.18, 0.58)
const CARD_W: float = 920.0
const CARD_PAD: float = 48.0
const BODY_H: float = 150.0
const BTN_H: float = 112.0
const BTN_GAP: float = 20.0

var _root: Control = null


func _init() -> void:
	layer = OVERLAY_LAYER


## 팝업을 연다. `danger` 면 확인 버튼이 앰버 대신 빨간 색면이 된다 —
## 지우는 행동이 "다음으로 가는" 주 행동과 같은 색이면 안 된다.
func open(title: String, body: String, cancel_text: String,
		confirm_text: String, danger: bool = false) -> void:
	_close_silently()
	_build(title, body, cancel_text, confirm_text, danger)


func close() -> void:
	if not is_open():
		return
	_close_silently()
	cancelled.emit()


func is_open() -> bool:
	return _root != null and is_instance_valid(_root)


func _close_silently() -> void:
	if is_open():
		_root.queue_free()
	_root = null


# ── Build ────────────────────────────────────────────────────────────────────
func _build(title: String, body: String, cancel_text: String,
		confirm_text: String, danger: bool) -> void:
	var vp: Vector2 = ScreenMetrics.viewport_size()
	_root = Control.new()
	# CanvasLayer 아래의 Control 은 앵커 프리셋이 뷰포트로 풀리지 않는다 —
	# 크기를 직접 준다.
	_root.position = Vector2.ZERO
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 딤은 클릭을 먹어 뒤의 로비로 새지 않게 하고, 빈 곳을 누르면 닫힌다.
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

	# 본문 칸은 고정 높이(네 줄 남짓)다 — 트리 밖에서 줄바꿈 Label 의 높이를
	# 재면 글꼴이 아직 안 풀려 0 이 나온다. 긴 글을 넣을 화면이 생기면 그때
	# 열고 나서 재는 방식으로 바꾼다.
	var inner_w: float = CARD_W - CARD_PAD * 2.0
	var body_lbl := Label.new()
	body_lbl.text = body
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_size_override("font_size", 26)
	body_lbl.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB)
	body_lbl.custom_minimum_size = Vector2(inner_w, 0)
	var body_h: float = BODY_H
	body_lbl.size = Vector2(inner_w, body_h)

	var title_h: float = 52.0
	var card_h: float = CARD_PAD + title_h + 24.0 + body_h + 40.0 + BTN_H + CARD_PAD
	# 안전 영역 한가운데. 노치 밑 / 제스처 띠 위로 버튼이 내려가지 않는다.
	var top: float = ScreenMetrics.top_y()
	var avail: float = ScreenMetrics.bottom_y() - top
	var card_pos := Vector2(ScreenMetrics.center_x() - CARD_W * 0.5,
			top + maxf(0.0, (avail - card_h) * 0.5))

	var card: Panel = OutgameTheme.add_card(_root, card_pos,
			Vector2(CARD_W, card_h), 24)
	# 카드 위 누름은 딤까지 내려가 팝업을 닫으면 안 된다.
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	UiHelpers.mk_label(card, title, 36, OutgameTheme.TEXT,
			Vector2(CARD_PAD, CARD_PAD), Vector2(inner_w, title_h))
	body_lbl.position = Vector2(CARD_PAD, CARD_PAD + title_h + 24.0)
	card.add_child(body_lbl)

	var btn_y: float = card_h - CARD_PAD - BTN_H
	# 버튼 폭도 하단 바와 같은 1 : 2 — 확인이 오른쪽, 더 넓은 쪽이다.
	var cancel_w: float = floorf((inner_w - BTN_GAP) / 3.0)
	var confirm_w: float = inner_w - BTN_GAP - cancel_w

	var cancel_btn := Button.new()
	cancel_btn.text = cancel_text
	cancel_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_ghost_button(cancel_btn, 30)
	cancel_btn.position = Vector2(CARD_PAD, btn_y)
	cancel_btn.size = Vector2(cancel_w, BTN_H)
	cancel_btn.pressed.connect(close)
	card.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = confirm_text
	confirm_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_primary_button(confirm_btn, 30)
	if danger:
		_paint_danger(confirm_btn)
		# 파괴적 확인의 감촉(ERROR)은 부르는 쪽이 결과를 보고 낸다 — 자동 배선까지
		# 울리면 한 누름에 두 번 떤다.
		HapticUi.mute(confirm_btn)
	confirm_btn.position = Vector2(CARD_PAD + cancel_w + BTN_GAP, btn_y)
	confirm_btn.size = Vector2(confirm_w, BTN_H)
	confirm_btn.pressed.connect(_on_confirm)
	card.add_child(confirm_btn)


## primary 버튼의 색면만 `NEGATIVE` 로 갈아입힌다. 스타일박스는 버튼마다 새로
## 만든 것이라 여기서 고쳐도 다른 버튼에 번지지 않는다.
func _paint_danger(b: Button) -> void:
	var fills: Dictionary = {
		"normal":  OutgameTheme.NEGATIVE,
		"hover":   OutgameTheme.NEGATIVE.lightened(0.10),
		"pressed": OutgameTheme.NEGATIVE.darkened(0.12),
	}
	for n in fills:
		var sb := b.get_theme_stylebox(n) as StyleBoxFlat
		if sb != null:
			sb.bg_color = fills[n]


func _on_confirm() -> void:
	_close_silently()
	confirmed.emit()
