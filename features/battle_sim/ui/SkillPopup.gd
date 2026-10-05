class_name SkillPopup
extends Node

# 파일럿 스킬 말풍선 — 하단 아군 스트립의 초상을 **짧게 탭**하면 그 초상 위에
# 뜬다(꾹 누르기는 상세 패널 — `PilotStrip`). 배경 딤 없이 판 하나와, 판 밖
# 아래에서 그 초상의 머리를 가리키는 화살표:
#
#   ┌──────────────────────────────┐
#   │ [아이콘] 이름        ⏲ 15    │   ← 쿨타임은 시계 + 턴 수, 그 밖은 타입 글자
#   │ 설명문(키워드 아이콘 · 줄바꿈) │
#   │ 상태 한 줄(남은 턴 / 토큰)    │   ← 쿨타임이 준비되면 뺀다
#   │ [           사용           ] │   ← 패시브에는 없다
#   └──────────────▽───────────────┘
#                  (초상)
#
# 닫힘: 판 밖을 누름(그 누름은 삼킨다) · 같은 초상을 다시 탭 · 사용 · 상세 패널이
# 열림 · 카드를 끌기 시작 · 열 수 없는 단계로 넘어감(`close_if_phase_left`).
# 다른 아군 초상을 탭하면 그 파일럿으로 바뀐다(`HudBuilder._on_player_strip_tapped`).
#
# **판 밖 누름을 삼키는 막(`_catcher`)은 아군 스트립 위끝까지만** 덮는다 — 스트립
# 칸은 그대로 눌려야 재탭(닫기) · 다른 초상(교체) · 꾹 누르기(상세)가 산다.
# 스트립 높이 안에서 칸이 아닌 곳을 누르면 `_input` 이 닫기만 한다(삼키지 않음).
#
# 열기: 아래에서 `RISE_PX` 올라오며 0.2초 페이드 인. 닫기: 내려가며 0.1초 페이드
# 아웃(상태는 즉시 비우고 화면만 빠져나간다 — `PilotDetailPanel` 과 같은 방식).
#
# **설명문의 카드 이름**(`[이동]` …)은 누르고 있는 동안 그 카드(`Card.tscn`)와
# 옆에 설명판(`CardDescBox`)을 누른 자리 위에 띄운다 — 올라오며 0.2초 페이드 인,
# 떼면 내려가며 0.1초 페이드 아웃. 어느 카드인지는 `StrategyIcon` 의 meta 구간
# (`card_meta = true`)이 말한다. RichTextLabel 은 meta 를 **뗄 때**(`meta_clicked`)
# 와 **호버**(`meta_hover_started`)로만 알려 주므로, 누름이 오면 그 자리로 마우스
# 이동 이벤트를 한 번 흘려 호버를 갱신시킨다(터치에는 앞선 이동이 없다).
#
# 전장을 붙잡지 않는다 — 순수 정보 + 버튼이라 BATTLE 자동 틱은 그대로 흐른다.
# 사용 버튼의 활성은 상세 패널과 같은 `PilotSkillSystem.can_activate` 다.

## 보상 미리보기 · 더미 열람과 같은 층. 상세 패널(13) 아래 — 상세가 열리면
## 이 말풍선은 먼저 닫힌다.
const OVERLAY_LAYER: int = 12

const PANEL_W: float = 640.0
const PANEL_PAD := Vector2(26.0, 24.0)
## 화면 좌우 가장자리와의 최소 여백.
const SCREEN_MARGIN: float = 20.0
const PANEL_BG := Color(0.05, 0.06, 0.11, 0.97)
const PANEL_RADIUS: int = 18
## 테두리 없음. 그림자는 아래로만 짧게.
const SHADOW_COLOR := Color(0, 0, 0, 0.45)
const SHADOW_SIZE: int = 6
const SHADOW_OFFSET := Vector2(0.0, 6.0)
## 화살표 — 판 아래끝에서 초상 머리까지. 밑변 폭 / 높이, 머리와의 틈.
const ARROW_W: float = 40.0
const ARROW_H: float = 22.0
const ARROW_GAP: float = 6.0

const ICON_PX: float = 72.0
const ICON_GAP: float = 16.0
const NAME_H: float = 40.0
const TYPE_FONT: int = 20
const TYPE_COLOR := Color(0.70, 0.74, 0.84)
const TYPE_W: float = 110.0
## 쿨타임 시계 아이콘 한 변 · 수치 폰트.
const CLOCK_PX: float = 28.0
const CLOCK_FONT: int = 26
const LINE_GAP: float = 10.0
const STATUS_H: float = 30.0
const USE_FONT: int = 28

## 쿨타임은 글자 대신 시계 아이콘 + 턴 수(`_build_cooldown_tag`).
const TYPE_LABEL := {
	PilotSkillSystem.TYPE_CHARGE:   "충전식",
	PilotSkillSystem.TYPE_PASSIVE:  "패시브",
}

## 열기 / 닫기 — 위로 올라오며 페이드 인, 내려가며 페이드 아웃.
const OPEN_SEC: float = 0.2
const CLOSE_SEC: float = 0.1
const RISE_PX: float = 24.0

## 카드 이름 누름 미리보기.
const PREVIEW_SCALE: float = 1.25
const PREVIEW_DESC_W: float = 300.0
const PREVIEW_GAP: float = 12.0
## 누른 점과 카드 아랫변 사이.
const PREVIEW_LIFT: float = 28.0
const PREVIEW_RISE_PX: float = 18.0

var _bs: BattleSim = null
var _layer: CanvasLayer = null
var _root: Control = null
## 판 + 화살표 — 열기 / 닫기 연출이 움직이는 덩어리(막은 움직이지 않는다).
var _body: Control = null
var _pilot: PilotData = null
## 설명문 라벨과 그 위의 카드 이름 누름 상태.
var _desc: RichTextLabel = null
var _hover_meta: Variant = null
var _kw_down: bool = false
var _kw_pos: Vector2 = Vector2.ZERO
var _preview: Control = null
var _status: Label = null
var _use_btn: Button = null
## 아군 스트립 위끝(전역 y) — 이 아래의 누름은 `_input` 이 본다.
var _strip_top: float = 0.0


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = OVERLAY_LAYER
	_layer.name = "SkillPopupLayer"
	add_child(_layer)


func bind(bs: BattleSim) -> void:
	_bs = bs


func is_active() -> bool:
	return _root != null


func pilot() -> PilotData:
	return _pilot


## 같은 파일럿이면 닫고, 아니면 `anchor`(초상 머리 위끝, 전역)를 가리키며 연다.
## `strip_top` 은 아군 스트립 위끝(전역 y) — 바깥 누름 막이 거기까지만 덮는다.
func toggle(p: PilotData, anchor: Vector2, strip_top: float) -> void:
	if is_active() and _pilot == p:
		close()
		return
	open(p, anchor, strip_top)


func open(p: PilotData, anchor: Vector2, strip_top: float) -> void:
	close()
	if _bs == null or _bs.skill == null or p == null:
		return
	_pilot = p
	_strip_top = strip_top
	_build(anchor)
	refresh()


## 상태는 **즉시** 비운다(`is_active()` 가 곧바로 false). 화면만 `CLOSE_SEC`
## 동안 내려가며 사라지고, 그동안은 입력을 받지 않는다.
func close() -> void:
	_hide_preview()
	if _root != null and is_instance_valid(_root):
		var root := _root
		_set_ignore_recursive(root)
		var tw := root.create_tween().set_parallel(true)
		if _body != null and is_instance_valid(_body):
			tw.tween_property(_body, "position:y", RISE_PX, CLOSE_SEC) \
					.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.tween_property(_body, "modulate:a", 0.0, CLOSE_SEC)
		tw.chain().tween_callback(root.queue_free)
	_root = null
	_body = null
	_pilot = null
	_status = null
	_use_btn = null
	_desc = null
	_hover_meta = null
	_kw_down = false


static func _set_ignore_recursive(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_set_ignore_recursive(c)


## 열 수 없는 단계(교전 무대 · 경기 종료 …)로 넘어가면 닫는다. 기준은 스트립
## 버튼과 같은 `PilotDetailPanel.can_open`.
func close_if_phase_left() -> void:
	if not is_active():
		return
	if _bs.pilot_detail == null or not _bs.pilot_detail.can_open():
		close()


## 상태 줄과 사용 버튼 활성만 다시 쓴다. `HudBuilder.update_hud` 가 부른다.
func refresh() -> void:
	if not is_active():
		return
	var sk: PilotSkillSystem = _bs.skill
	if _status != null and is_instance_valid(_status):
		_status.text = sk.status_text(_pilot)
	if _use_btn != null and is_instance_valid(_use_btn):
		_use_btn.disabled = not sk.can_activate(_pilot)


# ─── 바깥 누름 ───────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not is_active():
		return
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			return
		pos = st.position
	else:
		return
	# 스트립 위쪽은 막(`_catcher`)이 받는다. 스트립 높이에서 칸이 아닌 곳만 여기서.
	if pos.y < _strip_top:
		return
	var strip: PilotStrip = _bs.hud.player_strip() if _bs.hud != null else null
	if strip != null and strip.pilot_at(pos) != null:
		return
	close()


func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()


func _on_use_pressed() -> void:
	var sk: PilotSkillSystem = _bs.skill
	if sk == null or _pilot == null or not sk.can_activate(_pilot):
		return
	var target: PilotData = _pilot
	close()
	sk.activate(target)


# ─── UI ──────────────────────────────────────────────────────────────────────
func _build(anchor: Vector2) -> void:
	var sk: PilotSkillSystem = _bs.skill
	var vp_w: float = ScreenMetrics.vp_w()

	_root = Control.new()
	_root.name = "SkillPopup"
	# CanvasLayer 아래 Control 은 full-rect 앵커를 풀 부모 rect 가 없다 — 크기 명시.
	_root.position = Vector2.ZERO
	_root.size = Vector2(vp_w, ScreenMetrics.vp_h())
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	# 바깥 누름 막 — 투명, 아군 스트립 위끝까지.
	var catcher := Control.new()
	catcher.name = "OutsideCatcher"
	catcher.position = Vector2.ZERO
	catcher.size = Vector2(vp_w, maxf(0.0, _strip_top))
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_catcher_input)
	_root.add_child(catcher)

	var inner_w: float = PANEL_W - PANEL_PAD.x * 2.0
	var has_skill: bool = sk.has_skill(_pilot)
	var stype: String = sk.skill_type(_pilot)

	# 내용 높이를 먼저 잰다 — 판은 아래끝이 화살표에 붙고 위로 자란다.
	var gm: Node = _bs.gm
	var costs: Dictionary = gm.card_costs_by_name() if gm != null else {}
	var desc_text: String = sk.skill_description(_pilot) if has_skill else ""
	var desc_h: float = 0.0
	if has_skill:
		desc_h = StrategyIcon.rich_height(desc_text, inner_w,
				PilotDetailPanel.SKILL_DESC_FONT, costs)
	var show_status: bool = has_skill and not (stype == PilotSkillSystem.TYPE_COOLDOWN
			and sk.cooldown_left(_pilot) <= 0)
	var show_use: bool = has_skill and stype != PilotSkillSystem.TYPE_PASSIVE
	var content_h: float = ICON_PX
	if has_skill:
		content_h += LINE_GAP + desc_h
	if show_status:
		content_h += LINE_GAP + STATUS_H
	if show_use:
		content_h += LINE_GAP * 2.0 + PilotDetailPanel.SKILL_USE_H
	var panel_h: float = content_h + PANEL_PAD.y * 2.0

	# 판 + 화살표는 `_body` 아래 — 열기 연출이 이 덩어리만 움직인다.
	_body = Control.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_body)

	var tip := Vector2(anchor.x, anchor.y - ARROW_GAP)
	var panel_bottom: float = tip.y - ARROW_H
	var px: float = clampf(anchor.x - PANEL_W * 0.5, SCREEN_MARGIN,
			vp_w - PANEL_W - SCREEN_MARGIN)
	var origin := Vector2(px, panel_bottom - panel_h)

	# 화살표 — 판과 같은 바탕색 삼각형. 밑변을 판 안쪽으로 2px 묻어 이음매를 없앤다.
	var arrow := Polygon2D.new()
	var half: float = ARROW_W * 0.5
	var base_y: float = panel_bottom - 2.0
	var ax: float = clampf(tip.x, px + PANEL_RADIUS + half, px + PANEL_W - PANEL_RADIUS - half)
	arrow.polygon = PackedVector2Array([Vector2(ax - half, base_y),
			Vector2(ax + half, base_y), Vector2(tip.x, tip.y)])
	arrow.color = PANEL_BG

	var panel := Panel.new()
	panel.position = origin
	panel.size = Vector2(PANEL_W, panel_h)
	# 판 위 누름은 막까지 내려가지 않게 STOP — 판을 눌러도 닫히지 않는다.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(PANEL_RADIUS)
	sb.anti_aliasing = true
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = SHADOW_SIZE
	sb.shadow_offset = SHADOW_OFFSET
	panel.add_theme_stylebox_override("panel", sb)
	_body.add_child(panel)
	# 화살표는 판 **뒤에** 붙여야 판 그림자가 화살표를 덮지 않는다 — 그래서 판 다음.
	_body.add_child(arrow)

	var x0: float = PANEL_PAD.x
	var y: float = PANEL_PAD.y
	var key: String = String(sk.def_for(_pilot).get("key", "")) if has_skill else ""
	var tile: Control = SkillImages.make_icon_tile(key, ICON_PX,
			PilotDetailPanel.SKILL_TILE_BG, PilotDetailPanel.SKILL_TILE_ICON,
			PilotDetailPanel.SKILL_TILE_SHADOW, 8.0)
	tile.position = Vector2(x0, y)
	panel.add_child(tile)

	var col_x: float = x0 + ICON_PX + ICON_GAP
	var name_lbl := _label(sk.skill_name(_pilot) if has_skill else "스킬 없음",
			PilotDetailPanel.SKILL_NAME_FONT,
			PilotDetailPanel.SKILL_NAME_COLOR if has_skill else PilotDetailPanel.KEY_COLOR,
			HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.position = Vector2(col_x, y + (ICON_PX - NAME_H) * 0.5)
	name_lbl.size = Vector2(PANEL_W - PANEL_PAD.x - col_x - TYPE_W, NAME_H)
	name_lbl.clip_text = true
	panel.add_child(name_lbl)
	if has_skill and stype == PilotSkillSystem.TYPE_COOLDOWN:
		_build_cooldown_tag(panel, int(sk.def_for(_pilot).get("p1", 0)),
				Vector2(PANEL_W - PANEL_PAD.x - TYPE_W, name_lbl.position.y))
	elif has_skill:
		var type_lbl := _label(String(TYPE_LABEL.get(stype, "")), TYPE_FONT,
				TYPE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
		type_lbl.position = Vector2(PANEL_W - PANEL_PAD.x - TYPE_W, name_lbl.position.y)
		type_lbl.size = Vector2(TYPE_W, NAME_H)
		panel.add_child(type_lbl)
	y += ICON_PX

	if has_skill:
		y += LINE_GAP
		var desc := StrategyIcon.make_rich_label(desc_text,
				PilotDetailPanel.SKILL_DESC_FONT, PilotDetailPanel.SKILL_DESC_COLOR,
				PilotDetailPanel.SKILL_KW_ICON, PANEL_BG,
				KeywordIcon.TARGET_ANY_COLOR, KeywordIcon.TARGET,
				KeywordIcon.SPECIAL_COLOR_DARK, costs, true)
		desc.position = Vector2(x0, y)
		desc.size = Vector2(inner_w, desc_h)
		# 카드 이름 누름을 받는다 — 그 밖의 글자를 눌러도 판이 닫히지 않는 건 같다.
		desc.mouse_filter = Control.MOUSE_FILTER_STOP
		desc.meta_hover_started.connect(_on_meta_hover_started)
		desc.meta_hover_ended.connect(_on_meta_hover_ended)
		desc.gui_input.connect(_on_desc_input)
		panel.add_child(desc)
		_desc = desc
		y += desc_h

	if show_status:
		y += LINE_GAP
		_status = _label("", PilotDetailPanel.SKILL_STATUS_FONT,
				PilotDetailPanel.SKILL_WAIT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
		_status.position = Vector2(x0, y)
		_status.size = Vector2(inner_w, STATUS_H)
		_status.clip_text = true
		panel.add_child(_status)
		y += STATUS_H

	if show_use:
		y += LINE_GAP * 2.0
		_use_btn = Button.new()
		_use_btn.text = "사용"
		_use_btn.focus_mode = Control.FOCUS_NONE
		_use_btn.add_theme_font_size_override("font_size", USE_FONT)
		_use_btn.position = Vector2(x0, y)
		_use_btn.size = Vector2(inner_w, PilotDetailPanel.SKILL_USE_H)
		_use_btn.pressed.connect(_on_use_pressed)
		panel.add_child(_use_btn)

	# 열기 — 아래에서 올라오며 페이드 인.
	_body.position = Vector2(0.0, RISE_PX)
	_body.modulate.a = 0.0
	var tw := _body.create_tween().set_parallel(true)
	tw.tween_property(_body, "position:y", 0.0, OPEN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_body, "modulate:a", 1.0, OPEN_SEC)


## 쿨타임 자리 — 시계 아이콘 + 재사용 턴 수(`p1`), 오른쪽 정렬.
func _build_cooldown_tag(panel: Control, turns: int, at: Vector2) -> void:
	var num := _label(str(turns), CLOCK_FONT, TYPE_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
	var num_w: float = ThemeDB.fallback_font.get_string_size(str(turns),
			HORIZONTAL_ALIGNMENT_LEFT, -1, CLOCK_FONT).x + 2.0
	num.position = Vector2(at.x + TYPE_W - num_w, at.y)
	num.size = Vector2(num_w, NAME_H)
	panel.add_child(num)
	var clock := TextureRect.new()
	clock.texture = KeywordIcon.texture(KeywordIcon.COOLDOWN, int(CLOCK_PX * 2.0),
			TYPE_COLOR, PANEL_BG)
	clock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock.position = Vector2(num.position.x - 6.0 - CLOCK_PX,
			at.y + (NAME_H - CLOCK_PX) * 0.5)
	clock.size = Vector2(CLOCK_PX, CLOCK_PX)
	panel.add_child(clock)


# ─── 카드 이름 누름 미리보기 ─────────────────────────────────────────────────
func _on_meta_hover_started(meta: Variant) -> void:
	_hover_meta = meta
	if _kw_down and _preview == null:
		_show_preview(String(meta))


func _on_meta_hover_ended(_meta: Variant) -> void:
	_hover_meta = null


func _on_desc_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_kw_down = true
		_kw_pos = _desc.get_global_transform() * mb.position
		if _hover_meta != null:
			_show_preview(String(_hover_meta))
		else:
			# 터치에는 앞선 이동이 없어 호버가 비어 있다 — 그 자리로 이동 한 번.
			_nudge_hover.call_deferred(_kw_pos)
	else:
		_kw_down = false
		_hide_preview()


func _nudge_hover(pos: Vector2) -> void:
	if not _kw_down or _desc == null or not is_instance_valid(_desc):
		return
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	_desc.get_viewport().push_input(mm, true)


## 누른 자리 위에 카드 + 오른쪽(자리가 없으면 왼쪽) 설명판.
func _show_preview(card_name: String) -> void:
	_hide_preview()
	if _root == null or _bs == null or _bs.CARD_SCENE == null:
		return
	var cd: CardData = CardDescBox.card_by_name(card_name)
	if cd == null:
		return
	var vp := Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	var card_sz := Vector2(Card.CARD_W, Card.CARD_H) * PREVIEW_SCALE

	_preview = Control.new()
	_preview.name = "CardPreview"
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_preview)

	var node := _bs.CARD_SCENE.instantiate() as Card
	# add_child BEFORE setup — Card.gd 의 @onready 가 트리 진입 후에야 풀린다.
	_preview.add_child(node)
	node.setup(cd, false, true)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.scale = Vector2.ONE * PREVIEW_SCALE

	var box: Panel = CardDescBox.build(cd, PREVIEW_DESC_W)
	_preview.add_child(box)

	var total_w: float = card_sz.x + PREVIEW_GAP + box.size.x
	var card_x: float = _kw_pos.x - card_sz.x * 0.5
	var card_y: float = maxf(8.0, _kw_pos.y - PREVIEW_LIFT - card_sz.y)
	var box_right: bool = card_x + total_w <= vp.x - 8.0
	if not box_right and card_x - PREVIEW_GAP - box.size.x < 8.0:
		# 양쪽 다 모자라면 묶음째 화면 안으로 민다(설명판은 오른쪽).
		box_right = true
		card_x = vp.x - 8.0 - total_w
	card_x = clampf(card_x, 8.0, vp.x - 8.0 - card_sz.x)
	node.position = Vector2(card_x, card_y)
	var box_x: float = card_x + card_sz.x + PREVIEW_GAP if box_right \
			else card_x - PREVIEW_GAP - box.size.x
	box.position = Vector2(box_x, clampf(card_y, 8.0, maxf(8.0, vp.y - box.size.y - 8.0)))

	_preview.position = Vector2(0.0, PREVIEW_RISE_PX)
	_preview.modulate.a = 0.0
	var tw := _preview.create_tween().set_parallel(true)
	tw.tween_property(_preview, "position:y", 0.0, OPEN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_preview, "modulate:a", 1.0, OPEN_SEC)


func _hide_preview() -> void:
	if _preview == null:
		return
	var pv := _preview
	_preview = null
	if not is_instance_valid(pv):
		return
	var tw := pv.create_tween().set_parallel(true)
	tw.tween_property(pv, "position:y", PREVIEW_RISE_PX, CLOSE_SEC) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(pv, "modulate:a", 0.0, CLOSE_SEC)
	tw.chain().tween_callback(pv.queue_free)


func _label(text: String, font_size: int, color: Color,
		align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
