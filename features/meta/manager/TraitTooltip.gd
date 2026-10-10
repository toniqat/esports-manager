class_name TraitTooltip
extends CanvasLayer

# Effect tooltip of a manager trait card (`TraitCard`) — the cards themselves carry no effect text.
# Opened beside the tapped card: to its right when the card is on the left half of the screen,
# to its left otherwise; clamped inside the safe area. Shows name, rarity chip, bonus score and
# the filled-in description; an optional action button (`TraitSwapPopup`: 장착 / 해제).
# A tap anywhere else closes it (`%Catcher`).
#
# - Layout lives in `UI_Comp_TraitTooltip.tscn`; hosts place an instance (it starts hidden) and
#   call `show_for(card, trait_id, action_text)`; `action_pressed(trait_id)` reports the button.
# - A CanvasLayer (25) so it floats over scroll clipping and the modal sheets (20). Card rects are
#   read with `get_global_rect()` — the canvas coordinates every layer here shares.

signal action_pressed(trait_id: int)

const SCENE_PATH: String = "res://features/meta/manager/UI_Comp_TraitTooltip.tscn"
const GAP: float = 12.0
const EDGE: float = 16.0

var _tid: int = 0
var _gen: int = 0     # bumps on every show / hide — a stale deferred placement does nothing


static func create() -> TraitTooltip:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TraitTooltip


func _ready() -> void:
	visible = false
	%Catcher.pressed.connect(hide_tip)
	%Action.pressed.connect(func() -> void:
		var tid: int = _tid
		hide_tip()
		action_pressed.emit(tid))
	if UiPreview.is_standalone(self):
		_fill_preview()


## `card` = the tapped card (any Control); `action_text` "" = no button.
func show_for(card: Control, trait_id: int, action_text: String = "", action_primary: bool = true) -> void:
	_tid = trait_id
	_gen += 1
	var r: Dictionary = TraitSystem.row(trait_id)
	(%Name as Label).text = TraitSystem.name_of(trait_id)
	var chip := OutgameTheme.variation_box(&"AccentChip")
	chip.bg_color = TraitUi.rarity_color(int(r.get("rarity", 0)))
	chip.content_margin_left = 14.0
	chip.content_margin_right = 14.0
	(%Rarity as PanelContainer).add_theme_stylebox_override("panel", chip)
	(%RarityText as Label).text = GameEnums.rarity_label(int(r.get("rarity", 0)))
	var pos_pol: bool = String(r.get("polarity", TraitSystem.POLARITY_POS)) == TraitSystem.POLARITY_POS
	var cost: Label = %Cost
	cost.text = Loc.t(L.MANAGER_TRAIT_PICKER_COST_POS if pos_pol else L.MANAGER_TRAIT_PICKER_COST_NEG,
			{"n": int(r.get("bonus_cost", 0))})
	cost.theme_type_variation = &"PositiveLabel" if pos_pol else &"NegativeLabel"
	(%Desc as Label).text = TraitSystem.desc_of(trait_id)
	var act: Button = %Action
	act.visible = action_text != ""
	act.text = action_text
	act.theme_type_variation = &"PrimaryButton" if action_primary else &"GhostButton"
	(%Card as Control).modulate.a = 0.0
	visible = true
	# Wrapped labels settle their height after a layout pass — place on the next frame.
	_place(card.get_global_rect(), _gen)


func hide_tip() -> void:
	_gen += 1
	visible = false


func is_open() -> bool:
	return visible


func _place(anchor: Rect2, gen: int) -> void:
	await get_tree().process_frame
	if gen != _gen:
		return
	var box: Control = %Card
	box.size = Vector2(box.custom_minimum_size.x, box.get_combined_minimum_size().y)
	var vp: Vector2 = (%Root as Control).size
	var w: float = box.size.x
	var x: float = anchor.end.x + GAP if anchor.get_center().x < vp.x * 0.5 else anchor.position.x - GAP - w
	x = clampf(x, EDGE, vp.x - EDGE - w)
	var top: float = ScreenMetrics.top_y() + EDGE
	var bottom: float = vp.y - OutgameTheme.bottom_inset() - EDGE - box.size.y
	box.position = Vector2(x, clampf(anchor.position.y, top, maxf(top, bottom)))
	create_tween().tween_property(box, "modulate:a", 1.0, 0.12)


## F6 단독 실행 미리보기 — 화면 왼쪽의 가짜 카드 칸 옆에 특성 2번 툴팁 + 장착 버튼.
func _fill_preview() -> void:  # l10n-ignore
	var fake := Control.new()
	fake.position = Vector2(40, 400)
	fake.size = Vector2(196, 236)
	%Root.add_child(fake)
	show_for(fake, 2, Loc.t(L.MANAGER_TRAIT_SWAP_EQUIP))
	action_pressed.connect(func(tid: int) -> void: print("[TraitTooltip] action ", tid))
