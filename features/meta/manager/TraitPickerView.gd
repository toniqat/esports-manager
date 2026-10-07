class_name TraitPickerView
extends VBoxContainer

# Trait block shared by the lobby `감독` tab and the run setup `감독` step:
#
#   특성 ······································· 장착 n / TRAIT_SLOTS
#   ┌ 보너스 점수 +3  (제공 +x · 소모 −y)  — red when < 0 ┐
#   [slot] [slot] [slot] [slot]        ← tap an equipped slot = unequip
#   보유 특성 n — rows (tap = equip / unequip)
#   잠긴 특성 n — greyed rows + unlock condition (`ManagerUi.unlock_text`)
#
# **The layout is `UI_Comp_TraitPickerView.tscn`** (+ item scenes `UI_Comp_TraitPickerSlot.tscn` ·
# `UI_Comp_TraitPickerRow.tscn`). Hosts place an instance, call `fill()` on every change and connect
# `trait_pressed` once; the block sizes itself (VBox). Code fills texts, picks label / frame
# variations by state (`TraitPicker*` screen variations) and paints the data colours
# (polarity badge / strip, rarity chip) — the badge / chip on `variation_box` copies.
#
# It only draws and reports taps (`trait_pressed(id)`); the owner applies the rule
# (`ManagerProgress.toggle_trait`) and calls `fill()` again. Lives inside the owner's
# `DragScroll` body, so every tap target is a `MOUSE_FILTER_PASS` Button (scenes).
# Positive traits consume bonus points, negative ones provide them (plan §12.0).

signal trait_pressed(trait_id: int)

const SCENE_PATH: String = "res://features/meta/manager/UI_Comp_TraitPickerView.tscn"
const ROW_SCENE: PackedScene = preload("res://features/meta/manager/UI_Comp_TraitPickerRow.tscn")
const SLOT_SCENE: PackedScene = preload("res://features/meta/manager/UI_Comp_TraitPickerSlot.tscn")

const ROW_H: float = 112.0
const ROW_LOCKED_H: float = 140.0

## Row frame per state (screen variations, `OutgameTheme._add_screen_variations`).
const ROW_ON: StringName = &"TraitPickerRowOn"
const ROW_OWNED: StringName = &"TraitPickerRow"
const ROW_LOCKED: StringName = &"TraitPickerRowLocked"


static func create() -> TraitPickerView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TraitPickerView


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


## Refills the whole block. `equipped` / `owned` / `new_ids` are Array[int].
func fill(equipped: Array, owned: Array, new_ids: Array) -> void:
	var slots: int = TraitSystem.slot_count()
	var count: Label = %Count
	count.text = Loc.t(L.MANAGER_TRAIT_PICKER_EQUIPPED_COUNT, {"n": equipped.size(), "max": slots})
	count.theme_type_variation = &"NegativeLabel" if equipped.size() > slots else &"CaptionLabel"
	_fill_gauge(equipped)
	_fill_slots(equipped, slots)

	var owned_rows: Array = []
	var locked_rows: Array = []
	for raw in TraitSystem.rows():
		var r: Dictionary = raw
		if owned.has(int(r["id"])):
			owned_rows.append(r)
		else:
			locked_rows.append(r)
	# Owned: positives first, then negatives (each in id order) — the pick is
	# "what do I want" then "what do I pay with".
	owned_rows.sort_custom(func(a, b) -> bool:
		var pa: bool = String(a["polarity"]) == TraitSystem.POLARITY_POS
		var pb: bool = String(b["polarity"]) == TraitSystem.POLARITY_POS
		if pa != pb:
			return pa
		return int(a["id"]) < int(b["id"]))

	(%OwnedTitle as Label).text = Loc.t(L.MANAGER_TRAIT_PICKER_OWNED_TITLE, {"n": owned_rows.size()})
	_clear(%OwnedRows)
	for r in owned_rows:
		var tid: int = int((r as Dictionary)["id"])
		_add_row(%OwnedRows, r, equipped.has(tid), true, new_ids.has(tid))
	(%Locked as Control).visible = not locked_rows.is_empty()
	(%LockedTitle as Label).text = Loc.t(L.MANAGER_TRAIT_PICKER_LOCKED_TITLE, {"n": locked_rows.size()})
	_clear(%LockedRows)
	for r in locked_rows:
		_add_row(%LockedRows, r, false, false, false)


# ── Pieces ───────────────────────────────────────────────────────────────────
func _fill_gauge(equipped: Array) -> void:
	var provided: int = 0
	var consumed: int = 0
	for raw in equipped:
		var r: Dictionary = TraitSystem.row(int(raw))
		if r.is_empty():
			continue
		if String(r["polarity"]) == TraitSystem.POLARITY_POS:
			consumed += int(r["bonus_cost"])
		else:
			provided += int(r["bonus_cost"])
	var bonus: int = TraitSystem.bonus_points(equipped)
	var bad: bool = bonus < 0
	(%Gauge as Control).theme_type_variation = &"TraitPickerGaugeBad" if bad else &"TraitPickerGauge"
	var bl: Label = %Bonus
	bl.text = ManagerUi.signed(bonus)
	if bonus < 0:
		bl.theme_type_variation = &"NegativeLabel"
	elif bonus > 0:
		bl.theme_type_variation = &"PositiveLabel"
	else:
		bl.theme_type_variation = &"CaptionLabel"
	(%Note as Label).text = Loc.t(L.MANAGER_TRAIT_PICKER_GAUGE_NOTE, {"gain": provided, "cost": consumed})
	var rule: Label = %Rule
	rule.text = Loc.t(L.MANAGER_TRAIT_PICKER_RULE_BAD) if bad else Loc.t(L.MANAGER_TRAIT_PICKER_RULE_OK)
	rule.theme_type_variation = &"NegativeLabel" if bad else &"FaintLabel"


func _fill_slots(equipped: Array, slots: int) -> void:
	var box: HBoxContainer = %Slots
	_clear(box)
	for i in maxi(slots, equipped.size()):
		var slot: Control = SLOT_SCENE.instantiate()
		box.add_child(slot)
		var frame: Button = slot.get_node("%Frame")
		var is_empty: bool = i >= equipped.size()
		frame.visible = not is_empty
		(slot.get_node("%Empty") as Control).visible = is_empty
		if is_empty:
			continue
		var tid: int = int(equipped[i])
		var r: Dictionary = TraitSystem.row(tid)
		var pos_pol: bool = String(r.get("polarity", "+")) == TraitSystem.POLARITY_POS
		frame.pressed.connect(func() -> void: trait_pressed.emit(tid))
		if i >= slots:
			# Past the slot count: red frame.
			frame.theme_type_variation = &"TraitPickerSlotOver"
		(slot.get_node("%Strip") as ColorRect).color = _pol_color(pos_pol)
		(slot.get_node("%Name") as Label).text = TraitSystem.name_of(tid)
		var cost: Label = slot.get_node("%Cost")
		cost.text = _cost_text(r)
		cost.theme_type_variation = _pol_label(pos_pol)


func _add_row(parent: Container, r: Dictionary, on: bool, is_owned: bool, is_new: bool) -> void:
	var tid: int = int(r["id"])
	var pos_pol: bool = String(r["polarity"]) == TraitSystem.POLARITY_POS
	var b: Button = ROW_SCENE.instantiate()
	parent.add_child(b)
	b.custom_minimum_size.y = ROW_H if is_owned else ROW_LOCKED_H
	if on:
		b.theme_type_variation = ROW_ON
	else:
		b.theme_type_variation = ROW_OWNED if is_owned else ROW_LOCKED
	b.pressed.connect(func() -> void: trait_pressed.emit(tid))

	# Badge fill = polarity colour (grey when locked) — data, on an `AccentChip` copy (pill).
	var badge := OutgameTheme.variation_box(&"AccentChip")
	badge.bg_color = _pol_color(pos_pol) if is_owned else OutgameTheme.BORDER_STRONG
	(b.get_node("%Badge") as Panel).add_theme_stylebox_override("panel", badge)
	(b.get_node("%Sign") as Label).text = "+" if pos_pol else "−"

	var name_lbl: Label = b.get_node("%Name")
	name_lbl.text = TraitSystem.name_of(tid)
	name_lbl.theme_type_variation = &"BodyLabel" if is_owned else &"FaintLabel"
	var rar := OutgameTheme.variation_box(&"AccentChip")
	rar.bg_color = TraitUi.rarity_color(int(r["rarity"]))
	(b.get_node("%Rarity") as Panel).add_theme_stylebox_override("panel", rar)
	(b.get_node("%RarityText") as Label).text = GameEnums.rarity_label(int(r["rarity"]))
	var outgame: bool = String(r["layer"]) == TraitSystem.LAYER_OUTGAME
	(b.get_node("%LayerText") as Label).text = Loc.t(L.MANAGER_TRAIT_PICKER_LAYER_OUTGAME) if outgame \
			else Loc.t(L.MANAGER_TRAIT_PICKER_LAYER_INGAME)
	(b.get_node("%New") as Control).visible = is_new

	var desc: Label = b.get_node("%Desc")
	desc.text = TraitSystem.desc_of(tid)
	desc.theme_type_variation = &"CaptionLabel" if is_owned else &"FaintLabel"
	var un: Label = b.get_node("%Unlock")
	un.visible = not is_owned
	if not is_owned:
		un.text = Loc.t(L.MANAGER_TRAIT_PICKER_UNLOCK, {"cond": ManagerUi.unlock_text(String(r["unlock"]))})
	var cost: Label = b.get_node("%Cost")
	cost.text = _cost_text(r)
	cost.theme_type_variation = _pol_label(pos_pol) if is_owned else &"FaintLabel"
	(b.get_node("%Equipped") as Control).visible = on


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


static func _cost_text(r: Dictionary) -> String:
	var c: int = int(r.get("bonus_cost", 0))
	if String(r.get("polarity", "+")) == TraitSystem.POLARITY_POS:
		return Loc.t(L.MANAGER_TRAIT_PICKER_COST_POS, {"n": c})
	return Loc.t(L.MANAGER_TRAIT_PICKER_COST_NEG, {"n": c})


static func _pol_color(positive: bool) -> Color:
	return OutgameTheme.POSITIVE if positive else OutgameTheme.NEGATIVE


static func _pol_label(positive: bool) -> StringName:
	return &"PositiveLabel" if positive else &"NegativeLabel"


## F6 단독 실행 미리보기 — 손으로 적은 장착 · 보유 목록 (`resources/UiPreview.gd`):
## 긍정 2 · 부정 1 장착, NEW 하나. 누르면 장착 / 해제만 바꿔 다시 채운다(저장 없음).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var equipped: Array = [1, 3, 15]
	var owned: Array = [1, 2, 3, 6, 11, 15, 16, 23]
	fill(equipped, owned, [2])
	trait_pressed.connect(func(tid: int) -> void:
		if equipped.has(tid):
			equipped.erase(tid)
		elif owned.has(tid):
			equipped.append(tid)
		fill(equipped, owned, [2]))
