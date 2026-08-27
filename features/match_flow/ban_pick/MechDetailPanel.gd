class_name MechDetailPanel
extends CanvasLayer

# 메크 상세 팝업 — 배정 단계에서 **메크 초상화를 누르면** 열린다.
#
#   좌: 전신 아트 한 장
#   우: 머리글(기체명 · 역할군) → 스탯 칩 3개 → 메크 패시브 → 메크 카드
#   하: 닫기
#
# `features/season/draft/DraftDetailPanel.gd`(파일럿 상세)와 **좌우 구성이
# 같다** — 배정 단계에서는 같은 줄의 얼굴과 기체를 번갈아 누르게 되므로, 둘이
# 다른 모양으로 열리면 무엇을 보고 있는지가 매번 새로 읽힌다. 공유하는 것은
# 그 모양이지 구현이 아니다: 이쪽이 다루는 것은 `MechData` 와 메크 카드 표이고
# 저쪽은 `PlayerData` 와 파일럿 스킬 표다.
#
# **인게임 상세 패널(`battle_sim/ui/PilotDetailPanel.gd`)과는 다르다** — 그쪽은
# 파일럿과 메크를 한 화면에 겹쳐 세우고 인게임 탭(체력 · 공격력 · 지속 효과)을
# 앞세우지만, 밴픽은 아직 경기가 시작되지 않아 인게임 상태라는 것이 없다.

const OVERLAY_LAYER: int = 20
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.88)

# ─── 좌: 전신 아트 ───────────────────────────────────────────────────────────
# **높이로 정규화하지 않는다.** 메크 아트는 1024×1024 고정 캔버스라 파일럿
# 아트(가변 폭 × 1024)처럼 높이를 맞추면 폭이 그대로 1400 이 되어 오른쪽
# 정보 패널을 통째로 덮는다. 대신 정해진 상자 안에서 `KEEP_ASPECT_CENTERED` 로
# 앉히므로 기체마다 본체 겉보기 크기가 고르게 남는다.
const ART_X: float = 20.0
const ART_W: float = 556.0
const ART_H: float = 640.0
const ART_CENTER_Y: float = 800.0

# ─── 우: 정보 패널 ───────────────────────────────────────────────────────────
# 파일럿 상세와 **같은 좌표**다 — 두 팝업이 번갈아 열리는데 패널이 조금씩
# 어긋나면 그 흔들림이 곧 "다른 화면"으로 읽힌다.
const PANEL_X: float = 596.0
const PANEL_W: float = 460.0
const PANEL_TOP: float = 150.0
const PANEL_BOTTOM: float = 1740.0
const PANEL_PAD: float = 22.0
const PANEL_BG := Color(0.04, 0.05, 0.09, 0.90)
const PANEL_BORDER := Color(0.30, 0.34, 0.46, 0.70)

const HDR_NAME_FONT: int = 40
const HDR_SUB_FONT: int = 22
const SECTION_H: float = 36.0
const SECTION_FONT: int = 24
const SECTION_COLOR := Color(0.58, 0.78, 1.0)

# ─── 스탯 칩 ─────────────────────────────────────────────────────────────────
const CHIP_COLS: int = 3
const CHIP_GAP: float = 12.0
const CHIP_H: float = 92.0
const CHIP_RADIUS: int = 16
const CHIP_BG := Color(0.10, 0.12, 0.18, 0.94)
const CHIP_BORDER := Color(0.32, 0.36, 0.48, 0.80)
const CHIP_NAME_FONT: int = 19
const CHIP_VALUE_FONT: int = 34
const CHIP_NAME_COLOR := Color(0.72, 0.74, 0.80)
const CHIP_VALUE_COLOR := Color(0.96, 0.96, 0.98)

# ─── 패시브 ──────────────────────────────────────────────────────────────────
const PASSIVE_NAME_FONT: int = 30
const PASSIVE_META_FONT: int = 19
const PASSIVE_DESC_FONT: int = 21
const PASSIVE_NAME_COLOR := Color(1.0, 0.88, 0.52)
const PASSIVE_META_COLOR := Color(0.58, 0.63, 0.76)
const PASSIVE_DESC_COLOR := Color(0.88, 0.90, 0.95)

# ─── 메크 카드 ───────────────────────────────────────────────────────────────
# 파일럿 상세의 후보 카드 격자와 **같은 축소율 · 같은 열 수**다.
const CARD_SCENE := preload("res://scenes/Card.tscn")
const CARD_VIEW_SCALE: float = 0.80
const CARD_COLS: int = 3
const CARD_GAP: float = 12.0
const CARD_BADGE_FONT: int = 17
const CARD_NOTE_FONT: int = 18
const CARD_NOTE_COLOR := Color(0.62, 0.66, 0.76)

const CLOSE_H: float = 84.0

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),
	Color(1.00, 0.55, 0.20),
	Color(0.75, 0.40, 1.00),
	Color(0.30, 0.85, 0.45),
	Color(1.00, 0.35, 0.35),
]

var _mech: MechData = null
var _root: Control = null


func _init() -> void:
	layer = OVERLAY_LAYER


func open(m: MechData) -> void:
	close()
	_mech = m
	if m == null:
		return
	_build()


func close() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null


func is_open() -> bool:
	return _root != null and is_instance_valid(_root)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	_root = Control.new()
	# CanvasLayer 아래의 Control 은 앵커 프리셋이 뷰포트로 풀리지 않는다 —
	# 크기를 직접 준다.
	_root.position = Vector2.ZERO
	_root.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 딤은 클릭을 먹어 뒤의 배정판으로 새지 않게 하고, 빈 곳을 누르면 닫힌다.
	var dim := Button.new()
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.position = Vector2.ZERO
	dim.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	dim.pressed.connect(close)
	_root.add_child(dim)

	var dim_rect := ColorRect.new()
	dim_rect.color = DIM_COLOR
	dim_rect.position = Vector2.ZERO
	dim_rect.size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim_rect)

	_build_art()
	_build_panel()
	_build_close()


func _build_art() -> void:
	var at := Vector2(ART_X, ART_CENTER_Y - ART_H * 0.5)
	var tex: Texture2D = MechImages.full_for(_mech.id)
	if tex == null:
		var slab := ColorRect.new()
		slab.color = Color(0.30, 0.33, 0.42, 0.30)
		slab.position = at
		slab.size = Vector2(ART_W, ART_H)
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(slab)
		var ph := UiHelpers.mk_label(_root, _mech.name, 32,
				Color(0.70, 0.75, 0.85),
				at + Vector2(0.0, ART_H * 0.5 - 24.0), Vector2(ART_W, 48.0),
				HORIZONTAL_ALIGNMENT_CENTER)
		ph.clip_text = true
		return
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.position = at
	rect.size = Vector2(ART_W, ART_H)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)


func _build_panel() -> void:
	var panel_h: float = PANEL_BOTTOM - PANEL_TOP
	var backdrop := Panel.new()
	backdrop.position = Vector2(PANEL_X, PANEL_TOP)
	backdrop.size = Vector2(PANEL_W, panel_h)
	var sty := StyleBoxFlat.new()
	sty.bg_color = PANEL_BG
	sty.border_color = PANEL_BORDER
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 14
	sty.corner_radius_top_right    = 14
	sty.corner_radius_bottom_left  = 14
	sty.corner_radius_bottom_right = 14
	backdrop.add_theme_stylebox_override("panel", sty)
	_root.add_child(backdrop)

	var inner_w: float = PANEL_W - PANEL_PAD * 2.0
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(PANEL_X + PANEL_PAD, PANEL_TOP + PANEL_PAD)
	scroll.size = Vector2(inner_w, panel_h - PANEL_PAD * 2.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)

	# 스크롤 안쪽은 컨테이너가 아니라 좌표로 쌓는다 — 칩 격자와 카드 격자가
	# 둘 다 2차원이라 VBox 로는 행마다 컨테이너를 하나씩 더 세워야 한다.
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(body)

	var y: float = 0.0
	y = _build_header(body, inner_w, y)
	y = _build_stat_chips(body, inner_w, y + 18.0)
	y = _build_passive_block(body, inner_w, y + 22.0)
	y = _build_card_section(body, inner_w, y + 22.0)

	body.custom_minimum_size = Vector2(inner_w, y + 12.0)
	body.size = Vector2(inner_w, y + 12.0)


func _build_header(body: Control, w: float, y: float) -> float:
	var name_lbl := UiHelpers.mk_label(body, _mech.name, HDR_NAME_FONT,
			Color(1, 1, 1), Vector2(0, y), Vector2(w, 52))
	name_lbl.clip_text = true
	y += 54.0

	var r: int = int(_mech.role)
	var role_name: String = String(ROLE_NAMES[r]) if r >= 0 and r < ROLE_NAMES.size() else "?"
	var role_col: Color = ROLE_COLORS[r] if r >= 0 and r < ROLE_COLORS.size() else Color(1, 1, 1)
	var sub := UiHelpers.mk_label(body, role_name, HDR_SUB_FONT, role_col,
			Vector2(0, y), Vector2(w, 28))
	sub.clip_text = true
	return y + 30.0


func _build_stat_chips(body: Control, w: float, y: float) -> float:
	y = _section(body, w, y, "기체 능력치")
	var keys: Array = ["체력", "공격력", "존재감"]
	var values: Array = [_mech.hp, _mech.atk, _mech.presence]
	var chip_w: float = (w - CHIP_GAP * float(CHIP_COLS - 1)) / float(CHIP_COLS)
	for i in keys.size():
		var at := Vector2(float(i) * (chip_w + CHIP_GAP), y)
		_mk_chip(body, at, Vector2(chip_w, CHIP_H),
				String(keys[i]), str(int(values[i])))
	return y + CHIP_H


func _mk_chip(body: Control, at: Vector2, sz: Vector2, key: String,
		val: String) -> void:
	var chip := Panel.new()
	chip.position = at
	chip.size = sz
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color = CHIP_BG
	sty.border_color = CHIP_BORDER
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.border_width_bottom = 2
	sty.corner_radius_top_left     = CHIP_RADIUS
	sty.corner_radius_top_right    = CHIP_RADIUS
	sty.corner_radius_bottom_left  = CHIP_RADIUS
	sty.corner_radius_bottom_right = CHIP_RADIUS
	chip.add_theme_stylebox_override("panel", sty)
	body.add_child(chip)

	UiHelpers.mk_label(chip, key, CHIP_NAME_FONT, CHIP_NAME_COLOR,
			Vector2(0, 10), Vector2(sz.x, 24), HORIZONTAL_ALIGNMENT_CENTER)
	var v := UiHelpers.mk_label(chip, val, CHIP_VALUE_FONT, CHIP_VALUE_COLOR,
			Vector2(0, 36), Vector2(sz.x, 44), HORIZONTAL_ALIGNMENT_CENTER)
	v.clip_text = true


func _build_passive_block(body: Control, w: float, y: float) -> float:
	y = _section(body, w, y, "메크 패시브")
	var gm: Node = get_node_or_null("/root/GameManager")
	var pas: Dictionary = gm.mech_passive_def(_mech.id) if gm != null else {}
	if pas.is_empty():
		# 21대 중 15대만 패시브를 갖는다 — 없는 것이 결함이 아니라 그 기체의
		# 성질이므로 한 줄로 말해 준다.
		UiHelpers.mk_label(body, "이 기체에는 패시브가 없다",
				PASSIVE_DESC_FONT, PASSIVE_META_COLOR, Vector2(0, y), Vector2(w, 30))
		return y + 32.0

	var name_lbl := UiHelpers.mk_label(body, String(pas.get("name", "?")),
			PASSIVE_NAME_FONT, PASSIVE_NAME_COLOR, Vector2(0, y), Vector2(w, 40))
	name_lbl.clip_text = true
	y += 42.0

	var kw: String = String(pas.get("keyword", ""))
	if not kw.is_empty():
		UiHelpers.mk_label(body, kw, PASSIVE_META_FONT, PASSIVE_META_COLOR,
				Vector2(0, y), Vector2(w, 26))
		y += 28.0

	return y + _wrapped_label(body, w, y, String(pas.get("description", "")),
			PASSIVE_DESC_FONT, PASSIVE_DESC_COLOR)


func _build_card_section(body: Control, w: float, y: float) -> float:
	y = _section(body, w, y, "메크 카드")
	var gm: Node = get_node_or_null("/root/GameManager")
	var defs: Array = gm.mech_cards_for(_mech.id) if gm != null else []
	if defs.is_empty():
		UiHelpers.mk_label(body, "이 기체에는 고유 카드가 없다", CARD_NOTE_FONT,
				CARD_NOTE_COLOR, Vector2(0, y), Vector2(w, 30))
		return y + 32.0

	y += _wrapped_label(body, w, y,
			"이 기체를 배정받은 파일럿은 아래 카드를 장수만큼 덱에 넣는다.",
			CARD_NOTE_FONT, CARD_NOTE_COLOR) + 10.0

	var cw: float = Card.CARD_W * CARD_VIEW_SCALE
	var ch: float = Card.CARD_H * CARD_VIEW_SCALE
	var badge_h: float = 24.0
	var row_h: float = ch + badge_h
	var row_w: float = float(CARD_COLS) * cw + float(CARD_COLS - 1) * CARD_GAP
	var x0: float = maxf(0.0, (w - row_w) * 0.5)
	var rows: int = int(ceil(float(defs.size()) / float(CARD_COLS)))
	for i in defs.size():
		var def: Dictionary = defs[i]
		var col: int = i % CARD_COLS
		@warning_ignore("integer_division")
		var row: int = i / CARD_COLS
		var at := Vector2(x0 + float(col) * (cw + CARD_GAP),
				y + float(row) * (row_h + CARD_GAP))
		var node := CARD_SCENE.instantiate() as Card
		# add_child 를 setup 보다 **먼저** — Card.gd 의 @onready 참조는 트리에
		# 들어간 뒤에야 풀린다(DraftDetailPanel / CardPileViewer 와 같은 순서).
		body.add_child(node)
		node.setup(CardData.from_def(def), false, true)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.pivot_offset = Vector2.ZERO
		node.scale = Vector2(CARD_VIEW_SCALE, CARD_VIEW_SCALE)
		node.position = at

		# 장수 배지 — `count = 0` 인 카드는 덱에 처음부터 들어가지 않고 패시브나
		# 다른 카드가 만들어 줄 때만 세상에 나온다. 그 사정을 적어 두지 않으면
		# "왜 이 카드가 손에 안 들어오나"가 화면 어디에도 없다.
		var cnt: int = int(def.get("count", 0))
		var badge := UiHelpers.mk_label(body,
				("×%d" % cnt) if cnt > 0 else "생성 전용",
				CARD_BADGE_FONT,
				Color(0.92, 0.94, 1.0) if cnt > 0 else Color(0.62, 0.70, 0.92),
				at + Vector2(0.0, ch + 2.0), Vector2(cw, badge_h),
				HORIZONTAL_ALIGNMENT_CENTER)
		badge.clip_text = true
	return y + float(rows) * row_h + float(maxi(0, rows - 1)) * CARD_GAP


## 줄바꿈되는 문단 한 덩이. **실제 높이는 폰트가 정한다** — 손으로 재면 긴
## 설명문이 아래 블록을 덮는다. 반환값은 그 높이다.
func _wrapped_label(body: Control, w: float, y: float, text: String,
		font_size: int, color: Color) -> float:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.position = Vector2(0, y)
	lbl.custom_minimum_size = Vector2(w, 0)
	body.add_child(lbl)
	var h: float = lbl.get_minimum_size().y
	lbl.size = Vector2(w, h)
	return h


func _section(body: Control, w: float, y: float, title: String) -> float:
	var lbl := UiHelpers.mk_label(body, title, SECTION_FONT, SECTION_COLOR,
			Vector2(0, y), Vector2(w, SECTION_H))
	lbl.clip_text = true
	return y + SECTION_H


func _build_close() -> void:
	var btn := Button.new()
	btn.text = "닫기"
	btn.add_theme_font_size_override("font_size", 30)
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = Vector2(PANEL_X, PANEL_BOTTOM + 16.0)
	btn.size = Vector2(PANEL_W, CLOSE_H)
	# **불투명 스타일이 필수다** — 이 자리는 배정 화면의 아군 블록과 겹치는데,
	# 기본 Button 테마는 반투명이라 딤 아래의 초상화가 비쳐 버튼이 그림 위에
	# 얹힌 글자로 읽힌다.
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.16, 0.19, 0.28, 1.0)
	sty.border_color = Color(0.46, 0.52, 0.66, 1.0)
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 10
	sty.corner_radius_top_right    = 10
	sty.corner_radius_bottom_left  = 10
	sty.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  sty)
	btn.add_theme_stylebox_override("hover",   sty)
	btn.add_theme_stylebox_override("pressed", sty)
	btn.add_theme_stylebox_override("focus",   sty)
	btn.pressed.connect(close)
	_root.add_child(btn)
