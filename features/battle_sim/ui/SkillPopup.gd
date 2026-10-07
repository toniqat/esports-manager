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
# **판 밖 누름을 삼키는 막(`%Catcher`)은 아군 스트립 위끝까지만** 덮는다 — 스트립
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

# **레이아웃의 정본은 씬이다** — `UI_View_SkillPopup.tscn`(층 · 바깥 누름 막)과 열 때마다
# 인스턴스하는 `UI_Comp_SkillPopupCard.tscn`(판 + 화살표). 색 · 판은 전투 테마
# (`resources/BattleTheme.tres`)의 변형(`BattlePopup` · `BattleSkillNameLabel` /
# `BattleKeyLabel` · `BattleCaptionLabel` · `BattleStatusLabel` · `BattleActionButton`)이
# 정한다. 코드가 정하는 것: 판 위치(초상 위, 화면 안 clamp)와 높이(내용), 화살표 모양,
# 막 높이(스트립 위끝), 아이콘 타일 · 설명문(코드 위젯 — `%IconSlot` · `%DescSlot` 에 넣는다),
# 열기 / 닫기 연출. 생성: `SkillPopup.create()`.

## 보상 미리보기 · 더미 열람과 같은 층. 상세 패널(13) 아래 — 상세가 열리면
## 이 말풍선은 먼저 닫힌다. 씬 `Layer` 의 `layer` 와 같은 값.
const OVERLAY_LAYER: int = 12

const SCENE_PATH: String = "res://features/battle_sim/ui/UI_View_SkillPopup.tscn"
## 열 때마다 하나씩 인스턴스하는 판 + 화살표(닫히는 판이 사라지는 동안 다음 판이 올라온다).
const CARD_SCENE: PackedScene = preload("res://features/battle_sim/ui/UI_Comp_SkillPopupCard.tscn")

## 판 폭 · 안쪽 여백은 씬(`%Panel` 최소 폭)과 테마(`BattlePopup`, `BattleTheme.POPUP_PAD`)가
## 정한다 — 여기 값은 화면 안 clamp · 설명문 폭 계산에 쓰는 사본.
const PANEL_W: float = 640.0
## 화면 좌우 가장자리와의 최소 여백.
const SCREEN_MARGIN: float = 20.0
## 화살표 — 판 아래끝에서 초상 머리까지. 밑변 폭 / 높이, 머리와의 틈.
const ARROW_W: float = 40.0
const ARROW_H: float = 22.0
const ARROW_GAP: float = 6.0

const ICON_PX: float = 72.0
## 쿨타임 시계 아이콘 한 변.
const CLOCK_PX: float = 28.0

## 쿨타임은 글자 대신 시계 아이콘 + 턴 수(`%Cooldown`).
const TYPE_LABEL := {  # l10n-keys: hud.skill.type.*
	PilotSkillSystem.TYPE_CHARGE:   L.HUD_SKILL_TYPE_CHARGE,
	PilotSkillSystem.TYPE_PASSIVE:  L.HUD_SKILL_TYPE_PASSIVE,
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
## 지금 열린 판 + 화살표(`UI_Comp_SkillPopupCard.tscn` 인스턴스) — 열기 / 닫기 연출이 움직이는 덩어리.
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


## 씬을 인스턴스한다. `SkillPopup.new()` 는 빈 노드라 쓰지 않는다.
static func create() -> SkillPopup:
	return (load(SCENE_PATH) as PackedScene).instantiate() as SkillPopup


func _ready() -> void:
	%Catcher.gui_input.connect(_on_catcher_input)
	if UiPreview.is_standalone(self):
		_fill_preview()


func bind(bs: BattleSim) -> void:
	_bs = bs


func is_active() -> bool:
	return _body != null


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
	var sk: PilotSkillSystem = _bs.skill
	var has_skill: bool = sk.has_skill(p)
	var stype: String = sk.skill_type(p)
	_pilot = p
	_show({
		"has_skill": has_skill,
		"key": String(sk.def_for(p).get("key", "")) if has_skill else "",
		"name": sk.skill_name(p) if has_skill else Loc.t(L.HUD_SKILL_NONE),
		"type": stype,
		"cooldown_turns": int(sk.def_for(p).get("p1", 0)),
		"desc": sk.skill_description(p) if has_skill else "",
		"refs": CardData.ref_entries(sk.skill_description_key(p)) if has_skill else [],
		"show_status": has_skill and not (stype == PilotSkillSystem.TYPE_COOLDOWN
				and sk.cooldown_left(p) <= 0),
		"show_use": has_skill and stype != PilotSkillSystem.TYPE_PASSIVE,
	}, anchor, strip_top)
	refresh()


## 상태는 **즉시** 비운다(`is_active()` 가 곧바로 false). 화면만 `CLOSE_SEC`
## 동안 내려가며 사라지고, 그동안은 입력을 받지 않는다.
func close() -> void:
	_hide_preview()
	%Catcher.visible = false
	if _body != null and is_instance_valid(_body):
		var body := _body
		_set_ignore_recursive(body)
		var tw := body.create_tween().set_parallel(true)
		tw.tween_property(body, "position:y", RISE_PX, CLOSE_SEC) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(body, "modulate:a", 0.0, CLOSE_SEC)
		tw.chain().tween_callback(body.queue_free)
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
	if not is_active() or _bs == null or _pilot == null:
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
	# 스트립 위쪽은 막(`%Catcher`)이 받는다. 스트립 높이에서 칸이 아닌 곳만 여기서.
	if pos.y < _strip_top:
		return
	var strip: PilotStrip = _bs.hud.player_strip() if _bs != null and _bs.hud != null else null
	if strip != null and strip.pilot_at(pos) != null:
		return
	close()


func _on_catcher_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close()


func _on_use_pressed() -> void:
	if _bs == null:
		return
	var sk: PilotSkillSystem = _bs.skill
	if sk == null or _pilot == null or not sk.can_activate(_pilot):
		return
	var target: PilotData = _pilot
	close()
	sk.activate(target)


# ─── UI ──────────────────────────────────────────────────────────────────────
## 판 하나를 세운다. `d` = `open` 이 스킬 시스템에서 모은 값(미리보기는 손으로 적는다):
## has_skill · key · name · type · cooldown_turns · desc · refs(`CardData.ref_entries`) · show_status · show_use.
func _show(d: Dictionary, anchor: Vector2, strip_top: float) -> void:
	_strip_top = strip_top
	var vp_w: float = ScreenMetrics.vp_w()
	var has_skill: bool = bool(d["has_skill"])
	var stype: String = String(d["type"])

	# 바깥 누름 막 — 투명, 아군 스트립 위끝까지.
	var catcher: Control = %Catcher
	catcher.offset_bottom = maxf(0.0, _strip_top)
	catcher.visible = true

	_body = CARD_SCENE.instantiate() as Control
	%Root.add_child(_body)

	# 머리 줄 — 아이콘 · 이름 · 오른쪽에 종류(쿨타임은 시계 + 턴 수).
	var tile: Control = SkillImages.make_icon_tile(String(d["key"]), ICON_PX,
			BattleTheme.SKILL_TILE_BG, BattleTheme.SKILL_TILE_ICON,
			BattleTheme.SKILL_TILE_SHADOW, 8.0)
	_body.get_node("%IconSlot").add_child(tile)
	var name_lbl: Label = _body.get_node("%Name")
	name_lbl.text = String(d["name"])
	name_lbl.theme_type_variation = &"BattleSkillNameLabel" if has_skill else &"BattleKeyLabel"
	var cooldown: bool = has_skill and stype == PilotSkillSystem.TYPE_COOLDOWN
	var type_lbl: Label = _body.get_node("%Type")
	type_lbl.visible = has_skill and not cooldown
	type_lbl.text = Loc.t(String(TYPE_LABEL[stype])) if TYPE_LABEL.has(stype) else ""  # l10n-dynamic: hud.skill.type.*
	_body.get_node("%Cooldown").visible = cooldown
	if cooldown:
		_body.get_node("%Turns").text = str(int(d["cooldown_turns"]))
		_body.get_node("%Clock").texture = KeywordIcon.texture(KeywordIcon.COOLDOWN,
				int(CLOCK_PX * 2.0), BattleTheme.TEXT_TYPE, BattleTheme.POPUP_BG)

	# 설명문 — 상세 패널과 같은 길(`StrategyIcon`). 높이는 같은 규칙으로 잰다.
	var inner_w: float = PANEL_W - BattleTheme.POPUP_PAD.x * 2.0
	var slot: Control = _body.get_node("%DescSlot")
	slot.visible = has_skill
	if has_skill:
		var refs: Array = d["refs"]
		var desc_text: String = String(d["desc"])
		var desc_h: float = StrategyIcon.rich_height(desc_text, inner_w,
				PilotDetailPanel.SKILL_DESC_FONT, refs, true)
		slot.custom_minimum_size = Vector2(0.0, desc_h)
		var desc := StrategyIcon.make_rich_label(desc_text,
				PilotDetailPanel.SKILL_DESC_FONT, BattleTheme.TEXT_DESC,
				BattleTheme.SKILL_KW_ICON, BattleTheme.POPUP_BG,
				KeywordIcon.TARGET_ANY_COLOR, KeywordIcon.TARGET,
				KeywordIcon.SPECIAL_COLOR_DARK, refs, true, true)
		desc.position = Vector2.ZERO
		desc.size = Vector2(inner_w, desc_h)
		# 카드 이름 누름을 받는다 — 그 밖의 글자를 눌러도 판이 닫히지 않는 건 같다.
		desc.mouse_filter = Control.MOUSE_FILTER_STOP
		desc.meta_hover_started.connect(_on_meta_hover_started)
		desc.meta_hover_ended.connect(_on_meta_hover_ended)
		desc.gui_input.connect(_on_desc_input)
		slot.add_child(desc)
		_desc = desc

	var show_status: bool = bool(d["show_status"])
	_body.get_node("%StatusBox").visible = show_status
	_status = _body.get_node("%Status") if show_status else null
	if _status != null:
		_status.text = ""
	var show_use: bool = bool(d["show_use"])
	_body.get_node("%UseGap").visible = show_use
	_use_btn = _body.get_node("%Use")
	_use_btn.visible = show_use
	if show_use:
		_use_btn.pressed.connect(_on_use_pressed)
	else:
		_use_btn = null

	# 판은 아래끝이 화살표에 붙고 위로 자란다 — 높이 = 내용(컨테이너 최소 크기).
	var panel: Control = _body.get_node("%Panel")
	var panel_h: float = panel.get_combined_minimum_size().y
	var tip := Vector2(anchor.x, anchor.y - ARROW_GAP)
	var panel_bottom: float = tip.y - ARROW_H
	var px: float = clampf(anchor.x - PANEL_W * 0.5, SCREEN_MARGIN,
			vp_w - PANEL_W - SCREEN_MARGIN)
	panel.position = Vector2(px, panel_bottom - panel_h)
	panel.size = Vector2(PANEL_W, panel_h)

	# 화살표 — 판과 같은 바탕색 삼각형. 밑변을 판 안쪽으로 2px 묻어 이음매를 없앤다.
	# 판 **뒤에** 그려져야(씬에서 판 다음 형제) 판 그림자가 화살표를 덮지 않는다.
	var arrow: Polygon2D = _body.get_node("%Arrow")
	var half: float = ARROW_W * 0.5
	var base_y: float = panel_bottom - 2.0
	var radius: float = float(BattleTheme.RADIUS)
	var ax: float = clampf(tip.x, px + radius + half, px + PANEL_W - radius - half)
	arrow.polygon = PackedVector2Array([Vector2(ax - half, base_y),
			Vector2(ax + half, base_y), Vector2(tip.x, tip.y)])
	arrow.color = BattleTheme.POPUP_BG

	# 열기 — 아래에서 올라오며 페이드 인.
	_body.position = Vector2(0.0, RISE_PX)
	_body.modulate.a = 0.0
	var tw := _body.create_tween().set_parallel(true)
	tw.tween_property(_body, "position:y", 0.0, OPEN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_body, "modulate:a", 1.0, OPEN_SEC)


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
## `name_key` — 누른 카드 이름의 l10n key(`StrategyIcon.fill_rich` 의 meta).
func _show_preview(name_key: String) -> void:
	_hide_preview()
	if not is_active() or _bs == null or _bs.CARD_SCENE == null:
		return
	var cd: CardData = CardData.by_name_key(name_key)
	if cd == null:
		return
	var vp := Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())
	var card_sz := Vector2(Card.CARD_W, Card.CARD_H) * PREVIEW_SCALE

	_preview = Control.new()
	_preview.name = "CardPreview"
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Root.add_child(_preview)

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


## F6 단독 실행 미리보기 — 전투(`_bs`)가 없으니 쿨타임 스킬 한 장을 손으로 적어
## 판만 연다(`resources/UiPreview.gd`). 사용 · 상태 갱신 · 카드 이름 미리보기는 전투가
## 있어야 움직인다.
func _fill_preview() -> void:  # l10n-ignore
	RenderingServer.set_default_clear_color(BattleTheme.MODAL_BG)
	var vp := ScreenMetrics.viewport_size()
	_show({
		"has_skill": true, "key": "roam", "name": "배회",
		"type": PilotSkillSystem.TYPE_COOLDOWN, "cooldown_turns": 15,
		"desc": "활성화: 손에 있는 가장 낮은 비용의 [이동] 카드의 비용을 0으로 감소.",
		"refs": [], "show_status": true, "show_use": true,
	}, Vector2(vp.x * 0.5, vp.y - 280.0), vp.y - 276.0)
	_status.text = "준비까지 12턴"
